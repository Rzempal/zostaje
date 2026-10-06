import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
import 'package:provider/provider.dart';
import '../controllers/budget_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/budget_entry.dart';
import '../models/category.dart';
import '../models/subscription.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/credit_group.dart';
import '../utils/expenses_filter.dart';
import '../utils/money_format.dart';
import '../widgets/aurora_add_menu.dart';
import '../widgets/aurora_chip.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/category_icons.dart' show subscriptionIcon;
import '../widgets/credit_group_row.dart';
import '../widgets/filter_bars.dart';
import '../widgets/scope_swipe_area.dart';
import '../widgets/selection_bar.dart';
import '../widgets/subscription_row.dart';
import '../widgets/sync_refresh.dart';
import 'add_budget_entry_screen.dart';
import 'add_subscription_screen.dart';
import 'spending_planner_screen.dart';

/// Sortowanie listy budżetu.
enum _BudgetSort { alpha, amountDesc }

/// Grupowanie: zawsze po typach (Wpływy/Przelew/Wydatki stałe/Subskrypcje);
/// `byCategory` dodatkowo grupuje pozycje wydatków po kategoriach (etykietach).
enum _BudgetGrouping { byType, byCategory }

/// Klucze sekcji — stan zwinięcia zapisujemy pod nimi, a nie pod tytułem:
/// tytuł jest tekstem na ekranie i bywa poprawiany, klucz zostaje.
const _kSectionIncomes = 'incomes';
const _kSectionTransfers = 'expenses_transfers';
const _kSectionFixed = 'expenses_fixed';
const _kSectionSubscriptions = 'expenses_subscriptions';

const _expensesTitle = 'Wydatki stałe';
const _subscriptionsTitle = 'Subskrypcje';

/// Co pokazuje ten ekran — dwie osobne zakładki nawigacji na jednym widgecie,
/// bo cała maszyneria (filtry, sortowanie, grupowanie, Excel, stany puste) jest
/// wspólna. Różni je zestaw kubełków i drobiazgi w pasku akcji.
enum BudgetEntriesMode {
  /// „Wydatki cykliczne": koszty stałe, raty, przelew do domowego, subskrypcje.
  expenses,

  /// „Wpływy": wpływy cykliczne (pensja) i jednorazowe (premia).
  incomes,
}

/// Sekcja listy: klucz (stan zwinięcia), tytuł, pozycje i informacja, czy da się
/// ją grupować po kategoriach (wpływy kategorii nie mają).
class _Bucket {
  final String key;
  final String title;
  final List<BudgetEntry> entries;
  final bool categorized;

  const _Bucket(this.key, this.title, this.entries, this.categorized);
}

/// Ekran zarządzania pozycjami PLANOWALNYMI budżetu — w dwóch wariantach
/// ([BudgetEntriesMode]): „Wydatki cykliczne" i „Wpływy" (ADR-019).
///
/// Datowane wydatki jednorazowe = wydatki bieżące, więc mieszkają na ekranie
/// „Bieżące" (ADR-018). Przegląd liczbowy (surplus, bilans miesiąca) jest
/// w zakładce „Budżet". Subskrypcje są trzecią sekcją wydatków (ADR-027) —
/// osobnym modelem danych, ale tym samym strumieniem pieniędzy.
class BudgetDashboardScreen extends StatefulWidget {
  final BudgetEntriesMode mode;

  const BudgetDashboardScreen({
    super.key,
    this.mode = BudgetEntriesMode.expenses,
  });

  @override
  State<BudgetDashboardScreen> createState() => _BudgetDashboardScreenState();
}

class _BudgetDashboardScreenState extends State<BudgetDashboardScreen> {
  bool get _onIncomes => widget.mode == BudgetEntriesMode.incomes;

  /// Aktywny filtr kategorii (null = wszystkie). Filtruje sekcje wydatków.
  String? _filterCategoryId;

  /// Filtr typu pozycji (null = wszystkie).
  BudgetEntryType? _filterType;

  /// Chip „Subskrypcje" w filtrze typów — pseudo-typ (ADR-027). Wyklucza się
  /// z [_filterType]: wybór jednego chipa zdejmuje drugi.
  bool _filterSubscriptions = false;

  /// Filtr czasu (snapshot): wybrany rok i opcjonalnie miesiąc danego roku.
  /// `null` = bez filtra czasu. Miesiąc bez roku nie występuje.
  int? _filterYear;
  int? _filterMonth;

  /// Czy pokazywać to, czego plan nie liczy: wstrzymane pozycje i anulowane
  /// subskrypcje. Przełącznik siedzi przy filtrze czasu — też steruje tym,
  /// co jest na liście, a nie tym, jak jest ułożone.
  bool _showHidden = false;

  /// Zaznaczone pozycje BUDŻETU (tryb zaznaczania, wejście długim
  /// przytrzymaniem wiersza). Subskrypcje zostają poza nim: to inny model
  /// danych, z własnym formularzem i własnym menu pod przytrzymaniem.
  final Set<String> _selected = {};
  bool _selecting = false;

  /// Rozwinięte grupy pozycji karty (klucz z [CreditGroup.key]). Stanu nie
  /// zapamiętujemy między wejściami: grupy powstają i znikają razem z filtrami.
  final Set<String> _expandedCreditGroups = {};

  /// Sortowanie i grupowanie listy.
  _BudgetSort _sort = _BudgetSort.alpha;
  _BudgetGrouping _grouping = _BudgetGrouping.byType;

  /// Zwinięte sekcje (klucze) — stan trwały, jak Planner w „Bieżących".
  late Set<String> _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = context.read<StorageService>().getCollapsedBudgetSections();
  }

  // ── Tryb zaznaczania (pozycje budżetu) ─────────────────────────────────────

  void _startSelection(String id) => setState(() {
    _selecting = true;
    _selected.add(id);
  });

  void _toggleSelection(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _endSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  /// „Zaznacz wszystkie" = wszystkie widoczne pozycje budżetu, w poprzek sekcji.
  /// Zawężanie to rola filtrów — one już decydują, co jest na ekranie.
  void _toggleSelectAll(List<BudgetEntry> visible) => setState(() {
    final ids = visible.map((e) => e.id).toSet();
    if (ids.every(_selected.contains)) {
      _selected.removeAll(ids);
    } else {
      _selected.addAll(ids);
    }
  });

  Future<void> _bulkCategory(Set<String> ids) async {
    final storage = context.read<StorageService>();
    final ctrl = context.read<BudgetController>();
    final picked = await _pickOption(
      title: 'Kategoria dla ${ids.length} poz.',
      options: [
        (null, 'Brak kategorii'),
        for (final c in storage.getCategories()) (c.id, c.name),
      ],
    );
    if (picked == null || !mounted) return;
    await ctrl.setCategoryForAll(ids, picked.value);
    if (mounted) _afterBulk('Zmieniono kategorię: ${ids.length} poz.');
  }

  Future<void> _bulkPaymentMethod(Set<String> ids) async {
    final storage = context.read<StorageService>();
    final ctrl = context.read<BudgetController>();
    final picked = await _pickOption(
      title: 'Metoda płatności dla ${ids.length} poz.',
      options: [
        (null, 'Brak metody'),
        for (final m in storage.getPaymentMethods()) (m.name, m.name),
      ],
    );
    if (picked == null || !mounted) return;
    await ctrl.setPaymentMethodForAll(ids, picked.value);
    if (mounted) _afterBulk('Zmieniono metodę płatności: ${ids.length} poz.');
  }

  /// Wstrzymanie albo wznowienie — kierunek bierzemy z zaznaczenia: jeśli
  /// cokolwiek jest aktywne, wstrzymujemy; jeśli wszystko wstrzymane, wznawiamy.
  Future<void> _bulkToggleActive(Set<String> ids, bool anyActive) async {
    final ctrl = context.read<BudgetController>();
    await ctrl.setActiveForAll(ids, !anyActive);
    if (mounted) {
      _afterBulk(
        anyActive
            ? 'Wstrzymano: ${ids.length} poz. (widoczne po „pokaż ukryte")'
            : 'Wznowiono: ${ids.length} poz.',
      );
    }
  }

  Future<void> _bulkDelete(Set<String> ids) async {
    final ctrl = context.read<BudgetController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Usunąć ${ids.length} poz.?'),
        content: const Text(
          'Pozycje znikną z planu. Przelew do domowego zniknie razem ze swoim '
          'lustrem w drugim budżecie. Tego nie da się cofnąć.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ctrl.deleteAll(ids);
    if (mounted) _afterBulk('Usunięto: ${ids.length} poz.');
  }

  void _afterBulk(String message) {
    _endSelection();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<({T value})?> _pickOption<T>({
    required String title,
    required List<(T, String)> options,
  }) => showDialog<({T value})>(
    context: context,
    builder: (dctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dctx, (value: value)),
            child: Text(label),
          ),
      ],
    ),
  );

  void _toggleSection(String key) {
    setState(() {
      if (!_collapsed.remove(key)) _collapsed.add(key);
    });
    context.read<StorageService>().setCollapsedBudgetSections(_collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<BudgetController>();

    // Kubełki pozycji planowalnych zależne od trybu ekranu: wydatki (koszty
    // stałe, raty, przelew) albo wpływy. Datowane wydatki jednorazowe TU NIE
    // WCHODZĄ — to ten sam byt co wydatek i mieszkają na ekranie
    // „Bieżące" (ADR-018).
    // Flaga `true` = kubełek kategoryzowalny (wydatki), w którym przycisk
    // grupowania włącza podgrupy po kategoriach.
    final rawBuckets = _onIncomes
        ? <_Bucket>[_Bucket(_kSectionIncomes, 'Wpływy', ctrl.incomes, false)]
        : <_Bucket>[
            _Bucket(
              _kSectionTransfers,
              'Przelew wewnętrzny',
              ctrl.internalTransfers,
              false,
            ),
            _Bucket(
              _kSectionFixed,
              _expensesTitle,
              ctrl.recurringExpenses,
              true,
            ),
          ];
    // Subskrypcje to trzecia sekcja wydatków (ADR-027) — inny model danych,
    // ten sam strumień pieniędzy. Na Wpływach nie mają czego robić.
    final rawSubs = _onIncomes ? const <Subscription>[] : ctrl.subscriptions;
    final isEmpty =
        rawBuckets.every((b) => b.entries.isEmpty) && rawSubs.isEmpty;

    // Kategorie do filtra bierzemy z pozycji WIDOCZNYCH na tym ekranie.
    // Liczone ze sztywnej listy wydatkow pokazywaly sie takze na Wplywach,
    // gdzie wybor kategorii czyscil liste do zera (wplywy kategorii nie maja).
    final usedCatIds = <String>{
      for (final b in rawBuckets)
        for (final e in b.entries)
          if (e.categoryId != null) e.categoryId!,
      for (final s in rawSubs)
        if (s.categoryId != null) s.categoryId!,
    };
    final filterCategories = context
        .read<StorageService>()
        .getCategories()
        .where((c) => usedCatIds.contains(c.id))
        .toList();
    final activeCat =
        (_filterCategoryId != null && usedCatIds.contains(_filterCategoryId))
        ? _filterCategoryId
        : null;

    // Typy obecne (filtr typu) + pseudo-typ „Subskrypcje".
    final presentTypes = <BudgetEntryType>{
      for (final b in rawBuckets)
        for (final e in b.entries) e.type,
    };
    final activeType =
        (_filterType != null && presentTypes.contains(_filterType))
        ? _filterType
        : null;
    final activeSubsOnly = _filterSubscriptions && rawSubs.isNotEmpty;
    final filterTypes = presentTypes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    // Filtr czasu (snapshot) — lata/miesiące obecne w danych zmiennych plus
    // bieżący, żeby skrót „Dzisiaj" zawsze miał gdzie zaznaczyć.
    final today = Subscription.devDateOverride ?? DateTime.now();
    final variableMonths = ExpensesFilter.variableMonths(ctrl.all);
    final availableYears = ExpensesFilter.yearsFor(variableMonths, today);
    final activeYear =
        (_filterYear != null && availableYears.contains(_filterYear))
        ? _filterYear
        : null;
    final monthsOfYear = activeYear == null
        ? <int>[]
        : ExpensesFilter.monthsOfYear(variableMonths, activeYear, today);
    final activeMonth =
        (_filterMonth != null && monthsOfYear.contains(_filterMonth))
        ? _filterMonth
        : null;
    final isToday = activeYear == today.year && activeMonth == today.month;

    final filter = ExpensesFilter(
      type: activeType,
      subscriptionsOnly: activeSubsOnly,
      categoryId: activeCat,
      year: activeYear,
      month: activeMonth,
      showHidden: _showHidden,
    );

    int cmp(BudgetEntry a, BudgetEntry b) => switch (_sort) {
      _BudgetSort.alpha => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      _BudgetSort.amountDesc => b.amount.compareTo(a.amount),
    };
    // Przypięte subskrypcje zostają na górze swojej sekcji niezależnie od
    // sortowania — po to się je przypina.
    int cmpSub(Subscription a, Subscription b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return switch (_sort) {
        _BudgetSort.alpha => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _BudgetSort.amountDesc =>
          ctrl
              .monthlySubscriptionAmount(b)
              .compareTo(ctrl.monthlySubscriptionAmount(a)),
      };
    }

    final buckets = rawBuckets
        .map(
          (b) => _Bucket(
            b.key,
            b.title,
            b.entries.where(filter.keepEntry).toList()..sort(cmp),
            b.categorized,
          ),
        )
        .where((b) => b.entries.isNotEmpty)
        .toList();
    final subs = rawSubs.where(filter.keepSubscription).toList()..sort(cmpSub);
    final filteredEmpty = buckets.isEmpty && subs.isEmpty;

    // Zaznaczanie obejmuje pozycje budżetu ze WSZYSTKICH widocznych sekcji.
    // Liczone z listy widocznej: pozycja mogła wypaść przez filtr albo
    // synchronizację, a akcja pracowałaby wtedy na duchu.
    final visibleEntries = [for (final b in buckets) ...b.entries];
    final visibleIds = visibleEntries.map((e) => e.id).toSet();
    final selection = _selected.where(visibleIds.contains).toSet();
    final anyActiveSelected = visibleEntries.any(
      (e) => selection.contains(e.id) && e.isActive,
    );

    // Jest co odsłaniać? Bez tego przełącznik „pokaż ukryte" wisiałby na
    // ekranie, na którym nic nie jest ukryte.
    final hasHidden =
        rawBuckets.any((b) => b.entries.any((e) => !e.isActive)) ||
        rawSubs.any((s) => !s.isActive);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: kAuroraFabLocation,
      floatingActionButton: AuroraAddMenu(
        actions: [
          AuroraAddAction(
            icon: LucideIcons.plus,
            // „Dodaj ręcznie" nie mówiło CO się dodaje — a menu ma obok
            // subskrypcję, więc odróżnienie musi być w nazwie.
            label: _onIncomes ? 'Dodaj wpływ' : 'Dodaj wydatek cykliczny',
            primary: true,
            // Na ekranie Wpływy formularz startuje od razu jako wpływ.
            onTap: () => _openAdd(
              initialType: _onIncomes ? BudgetEntryType.income : null,
            ),
          ),
          if (!_onIncomes)
            AuroraAddAction(
              icon: subscriptionIcon,
              label: 'Dodaj subskrypcję',
              onTap: _openAddSubscription,
            ),
          if (ctrl.isHousehold)
            AuroraAddAction(
              icon: LucideIcons.userPlus,
              label: 'Dodaj wkład członka',
              onTap: () => _openAdd(
                initialType: BudgetEntryType.income,
                initialName: 'Wkład — ',
              ),
            ),
          // Import z Excela mieszka w Ustawieniach → „Eksport/import danych".
          // Wczytanie arkusza to operacja na całym zbiorze, a nie dodanie
          // pozycji — menu „Dodaj" sugerowało coś przeciwnego i stawiało dwa
          // rzadkie importy obok akcji używanej codziennie.
        ],
      ),
      body: Column(
        children: [
          // Sortowanie, grupowanie i „pokaż ukryte" siedza na koncu paskow
          // filtrow, ktorych dotycza: grupowanie przy kategoriach, sortowanie
          // przy typach, widocznosc ukrytych przy czasie (te dwa paski razem
          // decyduja, CO jest na liscie). Osobny wiersz ikon byl czwarta linia
          // nad lista i nie mowil, na co dziala.
          // Pasek zaznaczania ZASTĘPUJE pasek kategorii (ta sama wysokość),
          // żeby wejście w tryb nie spychało listy w chwili, gdy palec trzyma
          // wiersz. Filtry typu i czasu zostają — one wyznaczają, czego dotyczy
          // „Zaznacz wszystkie".
          if (_selecting)
            SelectionBar(
              count: selection.length,
              allSelected:
                  visibleEntries.isNotEmpty &&
                  selection.length == visibleEntries.length,
              onToggleAll: () => _toggleSelectAll(visibleEntries),
              onClose: _endSelection,
              actions: [
                SelectionAction(
                  icon: LucideIcons.tag,
                  tooltip: 'Zmień kategorię',
                  onPressed: () => _bulkCategory(selection),
                ),
                SelectionAction(
                  icon: LucideIcons.creditCard,
                  tooltip: 'Zmień metodę płatności',
                  onPressed: () => _bulkPaymentMethod(selection),
                ),
                SelectionAction(
                  icon: anyActiveSelected
                      ? LucideIcons.pauseCircle
                      : LucideIcons.playCircle,
                  tooltip: anyActiveSelected
                      ? 'Wstrzymaj zaznaczone'
                      : 'Wznów zaznaczone',
                  onPressed: () =>
                      _bulkToggleActive(selection, anyActiveSelected),
                ),
                SelectionAction(
                  icon: LucideIcons.trash2,
                  tooltip: 'Usuń zaznaczone',
                  danger: true,
                  onPressed: () => _bulkDelete(selection),
                ),
              ],
            )
          else if (!isEmpty && filterCategories.isNotEmpty)
            FilterRow(
              filters: CategoryFilterBar(
                categories: filterCategories,
                selected: activeCat,
                onSelect: (id) => setState(() => _filterCategoryId = id),
              ),
              action: IconButton(
                visualDensity: VisualDensity.compact,
                isSelected: _grouping == _BudgetGrouping.byCategory,
                tooltip: _grouping == _BudgetGrouping.byCategory
                    ? 'Podgrupy po kategoriach (włączone)'
                    : 'Grupuj wydatki po kategoriach',
                style: _grouping == _BudgetGrouping.byCategory
                    ? IconButton.styleFrom(
                        backgroundColor: context.semanticColors.primary
                            .withValues(alpha: 0.25),
                        foregroundColor: context.semanticColors.primary,
                      )
                    : null,
                icon: const Icon(LucideIcons.layers, size: 18),
                onPressed: () => setState(
                  () => _grouping = _grouping == _BudgetGrouping.byCategory
                      ? _BudgetGrouping.byType
                      : _BudgetGrouping.byCategory,
                ),
              ),
            ),
          if (!isEmpty && (filterTypes.isNotEmpty || rawSubs.isNotEmpty))
            FilterRow(
              filters: _TypeFilter(
                types: filterTypes,
                selected: activeType,
                hasSubscriptions: rawSubs.isNotEmpty,
                subscriptionsSelected: activeSubsOnly,
                onSelect: (tp) => setState(() {
                  _filterType = tp;
                  _filterSubscriptions = false;
                }),
                onSelectSubscriptions: (on) => setState(() {
                  _filterSubscriptions = on;
                  _filterType = null;
                }),
              ),
              action: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _sort == _BudgetSort.alpha
                    ? 'Sortuj: A→Z'
                    : 'Sortuj: kwota malejąco',
                icon: Icon(
                  _sort == _BudgetSort.alpha
                      ? LucideIcons.arrowDownAZ
                      : LucideIcons.arrowDown10,
                  size: 18,
                ),
                onPressed: () => setState(
                  () => _sort = _sort == _BudgetSort.alpha
                      ? _BudgetSort.amountDesc
                      : _BudgetSort.alpha,
                ),
              ),
            ),
          if (!isEmpty && (availableYears.isNotEmpty || hasHidden))
            TimeFilterBar(
              years: availableYears,
              activeYear: activeYear,
              monthsOfYear: monthsOfYear,
              activeMonth: activeMonth,
              todaySelected: isToday,
              onToday: () => setState(() {
                _filterYear = today.year;
                _filterMonth = today.month;
              }),
              onSelectYear: (y) => setState(() {
                _filterYear = y;
                _filterMonth = null;
              }),
              onSelectMonth: (m) => setState(() => _filterMonth = m),
              action: hasHidden
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      isSelected: _showHidden,
                      tooltip: _showHidden
                          ? 'Ukryj wstrzymane i anulowane'
                          : 'Pokaż wstrzymane i anulowane',
                      icon: Icon(
                        _showHidden ? LucideIcons.eyeOff : LucideIcons.eye,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _showHidden = !_showHidden),
                    )
                  : null,
            ),
          Expanded(
            child: ScopeSwipeArea(
              enabled: ctrl.scopeSelectable,
              child: SyncRefresh(
                child: (filteredEmpty && !isEmpty)
                    // AlwaysScrollable: pusty stan też musi dać się pociągnąć,
                    // inaczej gest odświeżania znika akurat wtedy, gdy
                    // użytkownik podejrzewa, że czegoś brakuje.
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [_FilteredEmpty()],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: _sections(
                          ctrl,
                          buckets,
                          subs,
                          // Koperta „Na bieżące wydatki" należy do wydatków — na ekranie
                          // Wpływy nie ma czego nią pomniejszać. Przy aktywnym
                          // filtrze też nie: nie ma kategorii ani typu, więc
                          // filtr by ją mylił.
                          showAlloc: !filter.hasAny && !_onIncomes,
                          isEmpty: isEmpty,
                          byCategory: _grouping == _BudgetGrouping.byCategory,
                          // Tylko gdy filtr zawezony do JEDNEGO miesiaca —
                          // wtedy „kwota korekty" ma jednoznaczne znaczenie.
                          monthKey: (activeYear != null && activeMonth != null)
                              ? '$activeYear-'
                                    '${activeMonth.toString().padLeft(2, '0')}'
                              : null,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Buduje sekcje listy budżetu. „Na bieżące wydatki" (koperta) jest przypięta na
  /// górze sekcji wydatków i wliczona do jej sumy — pokazywana tylko gdy
  /// [showAlloc] (brak aktywnych filtrów).
  List<Widget> _sections(
    BudgetController ctrl,
    List<_Bucket> buckets,
    List<Subscription> subs, {
    required bool showAlloc,
    required bool isEmpty,
    required bool byCategory,
    String? monthKey,
  }) {
    final cur = ctrl.targetCurrencyLabel;
    final alloc = ctrl.spendingAllocation;
    // Koperta „Na bieżące wydatki" jest tu tylko POKAZYWANA — pomniejsza plan, więc
    // suma wydatków musi się tłumaczyć. Edycja mieszka na ekranie Bieżące,
    // przy realnych wydatkach tej samej puli (ADR-019).
    Widget allocCard() => _AllocationSummaryRow(
      total: alloc ?? 0,
      itemCount: ctrl.spendingAllocationItems.length,
      currency: cur,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SpendingPlannerScreen())),
    );

    if (isEmpty) {
      return [
        if (showAlloc)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: allocCard(),
          ),
        _EmptyBudget(isHousehold: ctrl.isHousehold),
      ];
    }

    // Lustrzane wpływy „karta pożycza na ten zakup" zwijamy w jeden wiersz
    // (ADR-034) — na „Cyklicznych" nie ma ich wcale, więc mapa jest pusta
    // i lista idzie bez zmian.
    // Na „Wpływach" zwijamy OBIE role wpływów z karty, ale osobno: lustro
    // („Zakupy kartą") znosi się z zakupem, a pożyczka gotówkowa to realne
    // pieniądze. Wspólna suma nie znaczyłaby nic.
    final creditCards = _onIncomes
        ? creditMembers(
            ctrl.all,
            kinds: const {
              CreditGroupKind.cardLoan,
              CreditGroupKind.cashAdvance,
            },
          )
        : const <String, CreditMember>{};

    final out = <Widget>[];
    var pinned = false;
    for (final b in buckets) {
      final isExp = showAlloc && b.key == _kSectionFixed;
      Widget entryRow(BudgetEntry e) => SelectableRow(
        selectionMode: _selecting,
        selected: _selected.contains(e.id),
        onTap: () => _toggleSelection(e.id),
        onLongPress: () => _startSelection(e.id),
        child: BudgetEntryCard(
          entry: e,
          onTap: () => _openEdit(e),
          monthKey: monthKey,
        ),
      );
      List<Widget> entryRows(List<BudgetEntry> items) =>
          _creditAwareRows(items, entryRow, creditCards);
      out.add(
        _Section(
          title: b.title,
          // Suma liczy tylko to, co liczy plan — wstrzymana pozycja bywa na
          // liście widoczna („pokaż ukryte"), ale nic nie kosztuje. Przy
          // jednym miesiącu w filtrze bierze kwoty tego miesiąca (korekty),
          // bo te same kwoty pokazują wiersze pod nagłówkiem (ADR-008).
          total:
              ctrl.sumAmounts(
                b.entries.where((e) => e.isActive).toList(),
                monthKey: monthKey,
              ) +
              (isExp ? (alloc ?? 0) : 0),
          currency: cur,
          collapsed: _collapsed.contains(b.key),
          onToggle: () => _toggleSection(b.key),
          pinnedTop: isExp ? allocCard() : null,
          children: byCategory && b.categorized
              ? _categoryGroups(b.entries, (e) => e.categoryId, entryRows)
              : [BudgetEntryList(rows: entryRows(b.entries))],
        ),
      );
      if (isExp) pinned = true;
    }

    if (subs.isNotEmpty) {
      Widget subRow(Subscription s) => SubscriptionRow(
        subscription: s,
        onTap: () => _openEditSubscription(s),
        onLongPress: () => _showSubscriptionActions(s),
      );
      out.add(
        _Section(
          title: _subscriptionsTitle,
          total: ctrl.sumSubscriptions(subs),
          currency: cur,
          collapsed: _collapsed.contains(_kSectionSubscriptions),
          onToggle: () => _toggleSection(_kSectionSubscriptions),
          children: byCategory
              ? _categoryGroups(
                  subs,
                  (s) => s.categoryId,
                  (items) => items.map(subRow).toList(),
                )
              : [BudgetEntryList(rows: subs.map(subRow).toList())],
        ),
      );
    }

    // Brak sekcji wydatków (sam wpływ) — pokaż „Na bieżące wydatki" w osobnej sekcji.
    if (showAlloc && !pinned) {
      out.add(
        _Section(
          title: _expensesTitle,
          total: alloc ?? 0,
          currency: cur,
          collapsed: _collapsed.contains(_kSectionFixed),
          onToggle: () => _toggleSection(_kSectionFixed),
          pinnedTop: allocCard(),
          children: const [],
        ),
      );
    }
    return out;
  }

  /// Wiersze listy z pozycjami karty zwiniętymi w jeden wiersz (ADR-034).
  ///
  /// Pusta mapa [cards] = nie ma czego zwijać, więc lista idzie bez zmian —
  /// tak wygląda ekran „Cykliczne" i każdy budżet bez karty kredytowej.
  /// Pozycje rozwiniętej grupy dostają wcięcie, żeby było widać, że należą
  /// do wiersza nad nimi.
  List<Widget> _creditAwareRows(
    List<BudgetEntry> items,
    Widget Function(BudgetEntry) row,
    Map<String, CreditMember> cards,
  ) {
    if (cards.isEmpty) return items.map(row).toList();

    final out = <Widget>[];
    final rows = buildCreditRows(visible: items, members: cards);
    for (final r in rows) {
      switch (r) {
        case PlainEntryRow(:final entry):
          out.add(row(entry));
        case CreditGroup group:
          // W trybie zaznaczania grupy są rozwinięte na sztywno: „Zaznacz
          // wszystkie" obejmuje też pozycje w grupach, więc muszą być widoczne.
          final expanded =
              _selecting || _expandedCreditGroups.contains(group.key);
          out.add(
            CreditGroupRow(
              group: group,
              expanded: expanded,
              onToggle: _selecting
                  ? null
                  : () => setState(() {
                      if (!_expandedCreditGroups.remove(group.key)) {
                        _expandedCreditGroups.add(group.key);
                      }
                    }),
            ),
          );
          if (expanded) {
            out.addAll(
              group.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(left: kCreditGroupIndent),
                  child: row(e),
                ),
              ),
            );
          }
      }
    }
    return out;
  }

  /// Wiersze sekcji z podgrupami po kategoriach (etykietach); „Bez kategorii"
  /// na końcu. Wspólne dla pozycji budżetu i subskrypcji — słownik kategorii
  /// jest ten sam, więc podgrupy muszą wyglądać tak samo po obu stronach.
  ///
  /// [rows] dostaje CAŁĄ podgrupę, a nie pojedynczą pozycję: wiersze potrafią
  /// się zwijać (grupy karty), więc lista widgetów nie odpowiada już
  /// jeden-do-jednego liście pozycji.
  List<Widget> _categoryGroups<T>(
    List<T> items,
    String? Function(T) categoryOf,
    List<Widget> Function(List<T>) rows,
  ) {
    final byId = {
      for (final cat in context.read<StorageService>().getCategories())
        cat.id: cat,
    };
    final groups = <String?, List<T>>{};
    for (final it in items) {
      (groups[categoryOf(it)] ??= <T>[]).add(it);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1; // „Bez kategorii" na końcu
        if (b == null) return -1;
        return (byId[a]?.order ?? 999).compareTo(byId[b]?.order ?? 999);
      });
    return [
      for (final k in keys) ...[
        _CategoryGroupLabel(category: k == null ? null : byId[k]),
        BudgetEntryList(rows: rows(groups[k]!)),
      ],
    ];
  }

  /// Typy nalezace do TEJ sekcji. Wplywy maja wlasny ekran (ADR-019), wiec
  /// przy nich nie ma po co pokazywac kosztow ani rat.
  List<BudgetEntryType> get _sectionTypes => _onIncomes
      ? const [BudgetEntryType.income, BudgetEntryType.oneTimeIncome]
      : const [
          BudgetEntryType.recurringCost,
          BudgetEntryType.installment,
          BudgetEntryType.householdTransfer,
        ];

  Future<void> _openAdd({BudgetEntryType? initialType, String? initialName}) {
    final ctrl = context.read<BudgetController>();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddBudgetEntryScreen(
          scope: ctrl.scope,
          initialType: initialType,
          initialName: initialName,
          allowedTypes: _sectionTypes,
        ),
      ),
    );
  }

  Future<void> _openEdit(BudgetEntry e) async {
    final ctrl = context.read<BudgetController>();
    // Lustro przelewu w domowym — tylko do odczytu (edycja w osobistym).
    if (ctrl.isHousehold && e.isLinked) {
      await showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Wkład z budżetu osobistego'),
          content: const Text(
            'Tę pozycję dodano jako „Przelew do domowego" w budżecie osobistym. '
            'Edytuj lub usuń ją tam: Wydatki cykliczne → Osobisty.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddBudgetEntryScreen(
          existing: e,
          scope: ctrl.scope,
          allowedTypes: _sectionTypes,
        ),
      ),
    );
  }

  // ── Subskrypcje ────────────────────────────────────────────────────────────

  /// Zakres subskrypcji idzie za zakresem budżetu, na którym stoi lista —
  /// inaczej pozycja dodana w domowym znikałaby z ekranu, z którego ją dodano.
  SubscriptionScope get _subscriptionScope =>
      context.read<BudgetController>().isHousehold
      ? SubscriptionScope.household
      : SubscriptionScope.personal;

  Future<void> _openAddSubscription() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AddSubscriptionScreen(initialScope: _subscriptionScope),
    ),
  );

  Future<void> _openEditSubscription(Subscription sub) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddSubscriptionScreen(existing: sub)),
      );

  /// Akcje subskrypcji pod długim przytrzymaniem wiersza — przypięcie,
  /// anulowanie/wznowienie i usunięcie (jak na dawnym ekranie „Subskrypcje").
  void _showSubscriptionActions(Subscription sub) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                sub.isPinned ? LucideIcons.pinOff : LucideIcons.pin,
              ),
              title: Text(sub.isPinned ? 'Odepnij' : 'Przypnij na górze'),
              onTap: () {
                Navigator.pop(ctx);
                context.read<SubscriptionController>().togglePin(sub.id);
              },
            ),
            ListTile(
              leading: Icon(
                sub.isActive ? LucideIcons.xCircle : LucideIcons.checkCircle,
              ),
              title: Text(
                sub.isActive ? 'Anuluj subskrypcję' : 'Wznów subskrypcję',
              ),
              onTap: () {
                Navigator.pop(ctx);
                context.read<SubscriptionController>().toggleActive(sub.id);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: AppColors.negative),
              title: Text('Usuń', style: TextStyle(color: AppColors.negative)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteSubscription(sub);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSubscription(Subscription sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń subskrypcję'),
        content: Text('Czy na pewno chcesz usunąć "${sub.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<SubscriptionController>().delete(sub.id);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
  }
}

/// Sekcja listy: nagłówek z sumą (tapnięcie zwija/rozwija) i wiersze pod nim.
///
/// Suma zostaje widoczna po zwinięciu — po to się sekcję zwija: żeby zobaczyć
/// same kwoty, bez przewijania kilkudziesięciu pozycji.
class _Section extends StatelessWidget {
  final String title;
  final double total;
  final String currency;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Widget przypięty na górze sekcji (np. „Na bieżące wydatki"), przed pozycjami.
  final Widget? pinnedTop;

  /// Gotowe wiersze sekcji (ewentualnie już pogrupowane po kategoriach).
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.total,
    required this.currency,
    required this.collapsed,
    required this.onToggle,
    required this.children,
    this.pinnedTop,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty && pinnedTop == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = context.semanticColors;

    final List<Widget> out = [
      InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Text(
                '${budgetNf.format(total)}${curLabelSuffix(currency)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                collapsed ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                size: 18,
                color: c.textMuted,
              ),
            ],
          ),
        ),
      ),
    ];

    if (!collapsed) {
      if (pinnedTop != null) {
        out.add(
          Padding(padding: const EdgeInsets.only(bottom: 8), child: pinnedTop!),
        );
      }
      out.addAll(children);
    }
    out.add(const SizedBox(height: 16));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }
}

/// Podnagłówek podgrupy kategorii (kropka + nazwa) — „Bez kategorii" na końcu.
class _CategoryGroupLabel extends StatelessWidget {
  final Category? category;
  const _CategoryGroupLabel({required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final cat = category;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cat != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: cat.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            cat?.name ?? 'Bez kategorii',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cat?.color ?? c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeFilter extends StatelessWidget {
  final List<BudgetEntryType> types;
  final BudgetEntryType? selected;

  /// Czy pokazać chip „Subskrypcje" (pseudo-typ, ADR-027).
  final bool hasSubscriptions;
  final bool subscriptionsSelected;
  final void Function(BudgetEntryType?) onSelect;
  final void Function(bool) onSelectSubscriptions;

  const _TypeFilter({
    required this.types,
    required this.selected,
    required this.hasSubscriptions,
    required this.subscriptionsSelected,
    required this.onSelect,
    required this.onSelectSubscriptions,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AuroraChip(
                label: 'Wszystkie typy',
                selected: selected == null && !subscriptionsSelected,
                onTap: () => onSelect(null),
              ),
            ),
          ),
          ...types.map(
            (tp) => Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AuroraChip(
                  label: budgetTypeLabel(tp),
                  selected: selected == tp,
                  onTap: () => onSelect(selected == tp ? null : tp),
                ),
              ),
            ),
          ),
          if (hasSubscriptions)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AuroraChip(
                  label: _subscriptionsTitle,
                  selected: subscriptionsSelected,
                  onTap: () => onSelectSubscriptions(!subscriptionsSelected),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Krótkie polskie nazwy miesięcy (bez zależności od inicjalizacji locale).
class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.inbox, size: 48, color: c.textMuted),
          const SizedBox(height: 12),
          Text(
            'Brak pozycji dla wybranych filtrów',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _EmptyBudget extends StatelessWidget {
  final bool isHousehold;
  const _EmptyBudget({required this.isHousehold});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHousehold ? LucideIcons.home : LucideIcons.wallet,
              size: 48,
              color: c.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              isHousehold
                  ? 'Wspólna kasa domowa — dodaj wkłady i koszty'
                  : 'Zacznij od dodania wpływu i wydatków',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              isHousehold
                  ? 'Przelew z osobistego pojawi się tu jako wpływ.'
                  : 'Podgląd „ile zostaje miesięcznie" znajdziesz na Dashboardzie.',
              style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Koperta „Na bieżące wydatki" na ekranie „Wydatki cykliczne" — suma planu i wejście
/// do niego.
///
/// Rezerwa pomniejsza „zostaje/mies", więc musi być widoczna w sumie wydatków,
/// inaczej plan przestałby się tłumaczyć. Skład koperty edytuje się na własnym
/// ekranie ([SpendingPlannerScreen]) — ten sam, do którego prowadzi karta na
/// „Bieżących". Wcześniej wiersz tylko odsyłał tekstem („edycja w Bieżących").
class _AllocationSummaryRow extends StatelessWidget {
  final double total;
  final int itemCount;
  final String currency;
  final VoidCallback onTap;

  const _AllocationSummaryRow({
    required this.total,
    required this.itemCount,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final isSet = total > 0 || itemCount > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.tile),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(lucide.LucideIcons.receiptText, size: 20, color: c.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Planner', style: theme.textTheme.bodyMedium),
                    Text(
                      isSet
                          ? 'Kwota zaplanowana na bieżące wydatki'
                          : 'Zaplanuj kwotę na bieżące wydatki',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                isSet
                    ? '−${budgetNf.format(total)}${curLabelSuffix(currency)}'
                    : 'Brak',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isSet ? c.negative : c.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 18, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
