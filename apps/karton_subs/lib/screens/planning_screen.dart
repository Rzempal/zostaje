import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/budget_controller.dart';
import '../controllers/plan_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/category.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/text_sort.dart';
import '../widgets/aurora_add_menu.dart';
import '../widgets/aurora_chip.dart';
import '../widgets/aurora_segmented.dart';
import '../widgets/budget_widgets.dart' show BudgetEntryList, budgetNf;
import '../widgets/category_icons.dart' show subscriptionIcon;
import '../widgets/filter_bars.dart';
import '../widgets/budget_picker.dart' show moveOrCopyPositions;
import '../widgets/plan_widgets.dart';
import '../widgets/section_info_badge.dart' show SectionInfo;
import '../widgets/workspace_top_bar.dart';
import '../widgets/scope_swipe_area.dart';
import '../widgets/selection_bar.dart';
import '../widgets/subscription_row.dart';
import 'add_subscription_screen.dart';
import 'card_loan_form_screen.dart';
import 'installment_loan_form_screen.dart';
import 'plan_copy_year_screen.dart';
import 'plan_position_form_screen.dart';
import 'plan_position_screen.dart';

enum _PlanSort { alpha, amountDesc }

/// Klucze sekcji (stan zwinięcia) — osobne od dawnych „Cyklicznych".
const _kIncomes = 'plan_incomes';

/// Cała grupa „Wydatki" (chevron w nagłówku) — niezależnie od jej części.
const _kExpensesGroup = 'plan_expenses_group';

/// Sekcja „Pożyczki" (dawniej „Karta kredytowa") — klucz zwinięcia zostaje,
/// żeby zapamiętany stan sekcji nie przepadł.
const _kLoans = 'plan_card';

/// Części grup (pigułki): zapisany klucz = część ukryta, więc „tylko pozycje"
/// to ukryte subskrypcje — ten sam zapis co dawne zwijanie części.
const _kExpenses = 'plan_expenses';
const _kSubscriptions = 'plan_subscriptions';
const _kCardLoans = 'plan_loans_card';
const _kInstallmentLoans = 'plan_loans_installment';

/// Zakładka „Planowanie" — plan roczny aktywnego budżetu (ADR-035).
///
/// Wpływy, wydatki, karta i subskrypcje na jednym ekranie. Widok „Rok"
/// pokazuje sumy roku, widok „Miesiąc" — kwoty wybranego miesiąca. Pozycja
/// widoczna w miesiącu to pozycja, która w nim obowiązuje. Ekran startuje na
/// bieżącym miesiącu; „Dzisiaj" w rogu paska wraca do niego (w widoku
/// rocznym — do bieżącego roku).
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  String? _filterCategoryId;
  late int _year;
  /// Miesiąc widoku miesięcznego (1–12) — zostaje zapamiętany przy
  /// przełączaniu na rok i z powrotem.
  late int _month;

  /// Widok roczny: kwoty to sumy roku (bez paska miesięcy); inaczej — kwoty
  /// wybranego miesiąca.
  bool _yearView = false;
  bool _showHidden = false;
  bool _byCategory = false;
  _PlanSort _sort = _PlanSort.alpha;
  late Set<String> _collapsed;

  /// Zaznaczone pozycje planu (wpływy i wydatki). Karta i subskrypcje mają
  /// własne formularze, więc zostają poza zaznaczaniem.
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    // Start na bieżącym miesiącu — najczęstsze pytanie do planu.
    final today = context.read<PlanController>().today;
    _year = today.year;
    _month = today.month;
    _collapsed = context.read<StorageService>().getCollapsedBudgetSections();
  }

  void _toggleSection(String key) {
    setState(() {
      if (!_collapsed.remove(key)) _collapsed.add(key);
    });
    context.read<StorageService>().setCollapsedBudgetSections(_collapsed);
  }

  /// Część grupy pokazana sama (pigułka) albo `null` = „Razem". Ukryte obie
  /// (stan sprzed pigułek) też znaczy „Razem" — inaczej grupa byłaby pusta.
  String? _onlyPart(String a, String b) {
    final hideA = _collapsed.contains(a), hideB = _collapsed.contains(b);
    if (hideA == hideB) return null;
    return hideA ? b : a;
  }

  void _showOnly(String a, String b, String? only) {
    setState(() {
      _collapsed
        ..remove(a)
        ..remove(b);
      if (only == a) _collapsed.add(b);
      if (only == b) _collapsed.add(a);
    });
    context.read<StorageService>().setCollapsedBudgetSections(_collapsed);
  }

  // ── Zaznaczanie ────────────────────────────────────────────────────────────

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

  Future<void> _bulkCategory(Set<String> ids) async {
    final plan = context.read<PlanController>();
    final picked = await _pickOption(
      title: 'Kategoria dla ${ids.length} poz.',
      options: [
        (null, 'Brak kategorii'),
        for (final c in context.read<StorageService>().getCategories(
          plan.budgetId,
        ))
          (c.id, c.name),
      ],
    );
    if (picked == null || !mounted) return;
    await plan.setCategoryForAll(ids, picked.value);
    if (mounted) _afterBulk('Zmieniono kategorię: ${ids.length} poz.');
  }

  Future<void> _bulkMethod(Set<String> ids) async {
    final plan = context.read<PlanController>();
    final picked = await _pickOption(
      title: 'Metoda płatności dla ${ids.length} poz.',
      options: [
        (null, 'Brak metody'),
        for (final m in context.read<StorageService>().getPaymentMethods(
          plan.budgetId,
        ))
          (m.name, m.name),
      ],
    );
    if (picked == null || !mounted) return;
    await plan.setPaymentMethodForAll(ids, picked.value);
    if (mounted) _afterBulk('Zmieniono metodę płatności: ${ids.length} poz.');
  }

  Future<void> _bulkArchive(Set<String> ids, bool archive) async {
    await context.read<PlanController>().setArchivedAll(ids, archive);
    if (mounted) {
      _afterBulk(
        archive
            ? 'Ukryto: ${ids.length} poz. (widoczne po „pokaż ukryte")'
            : 'Przywrócono: ${ids.length} poz.',
      );
    }
  }

  /// Zaznaczone pozycje: duplikat w tym budżecie albo przeniesienie / kopia
  /// do innego (ADR-037) — najpierw wybór, potem (poza duplikatem) budżet
  /// docelowy.
  Future<void> _bulkCopies(Set<String> ids) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.copyPlus),
              title: Text('Duplikuj ${ids.length} poz.'),
              subtitle: const Text('W tym budżecie, z dopiskiem „(kopia)"'),
              onTap: () => Navigator.pop(sheetCtx, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.arrowRightLeft),
              title: Text('Przenieś ${ids.length} poz. do budżetu…'),
              subtitle: const Text('Razem z odhaczonymi płatnościami'),
              onTap: () => Navigator.pop(sheetCtx, 'move'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.copy),
              title: Text('Kopiuj ${ids.length} poz. do budżetu…'),
              subtitle: const Text('Pozycje zostają też tutaj'),
              onTap: () => Navigator.pop(sheetCtx, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final budgets = context.read<BudgetController>();
    if (action == 'duplicate') {
      await budgets.duplicatePositions(ids);
      if (mounted) _afterBulk('Zduplikowano: ${ids.length} poz.');
      return;
    }
    final done = await moveOrCopyPositions(
      context,
      ids,
      copy: action == 'copy',
      fromBudgetId: budgets.budgetId,
    );
    if (done && mounted) _endSelection();
  }

  Future<void> _bulkDelete(Set<String> ids) async {
    final plan = context.read<PlanController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Usunąć ${ids.length} poz.?'),
        content: const Text(
          'Pozycje znikną z planu razem ze wszystkimi miesiącami. '
          'Tego nie da się cofnąć.',
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
    await plan.deleteAll(ids);
    if (mounted) _afterBulk('Usunięto: ${ids.length} poz.');
  }

  // ── Nawigacja ──────────────────────────────────────────────────────────────

  Future<void> _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _showSubscriptionActions(Subscription sub) {
    final subs = context.read<SubscriptionController>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                sub.isPinned ? LucideIcons.pinOff : LucideIcons.pin,
              ),
              title: Text(sub.isPinned ? 'Odepnij' : 'Przypnij na górze'),
              onTap: () {
                Navigator.pop(ctx);
                subs.togglePin(sub.id);
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
                subs.toggleActive(sub.id);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: AppColors.negative),
              title: Text('Usuń', style: TextStyle(color: AppColors.negative)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('Usuń subskrypcję'),
                    content: Text('Czy na pewno chcesz usunąć "${sub.name}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, false),
                        child: const Text('Anuluj'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.negative,
                        ),
                        child: const Text('Usuń'),
                      ),
                    ],
                  ),
                );
                if (ok == true) subs.delete(sub.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Widok ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanController>();
    final budget = context.watch<BudgetController>();
    final storage = context.read<StorageService>();
    final c = context.semanticColors;
    final today = plan.today;

    final years = plan.years;
    if (!years.contains(_year)) years.add(_year);
    years.sort();
    final period = PlanPeriod(_year, _yearView ? null : _month);
    final isToday =
        _year == today.year && (_yearView || _month == today.month);

    final all = plan.positions;
    final subsAll = plan.subscriptions;

    bool inPeriod(PlanPosition p) => period.isYear
        ? p.hasYear(_year)
        : p.months.containsKey(period.monthKey);
    bool keep(PlanPosition p) => (_showHidden || !p.archived) && inPeriod(p);
    // Filtr kategorii stoi w grupie Wydatki i dotyczy tylko jej list —
    // pozycji wydatków i subskrypcji; Wpływy, Pożyczki i „Zostaje" bez niego.
    bool inCategory(String? categoryId) =>
        _filterCategoryId == null || categoryId == _filterCategoryId;
    double amount(PlanPosition p) => plan.amountOf(p, period);
    int cmp(PlanPosition a, PlanPosition b) => switch (_sort) {
      _PlanSort.alpha => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      _PlanSort.amountDesc => amount(b).compareTo(amount(a)),
    };

    final incomes =
        all.where((p) => p.kind == PlanKind.income && keep(p)).toList()
          ..sort(cmp);
    final expenses =
        all
            .where(
              (p) =>
                  p.kind == PlanKind.expense &&
                  keep(p) &&
                  inCategory(p.categoryId),
            )
            .toList()
          ..sort(cmp);

    // Pożyczki (karta i ratalne): para jest widoczna, gdy którakolwiek strona
    // wypada w okresie.
    final loanRows =
        <({PlanPosition loan, PlanPosition? repayment, double net})>[];
    for (final loan in all.where((p) => p.kind == PlanKind.loan)) {
      final pair = plan.loanPair(loan.linkId ?? '');
      final rep = pair.repayment;
      final visible =
          (_showHidden || !loan.archived) &&
          (inPeriod(loan) || (rep != null && inPeriod(rep)));
      if (!visible) continue;
      final net = amount(loan) - (rep == null ? 0 : amount(rep));
      loanRows.add((loan: loan, repayment: rep, net: net));
    }
    loanRows.sort(
      (a, b) => (a.loan.months.keys.firstOrNull ?? '').compareTo(
        b.loan.months.keys.firstOrNull ?? '',
      ),
    );
    // Pożyczki ratalne mają warunki przy ratach (ADR-036), karta — nie.
    final installmentRows = [
      for (final r in loanRows)
        if (r.repayment?.loanTerms != null) r,
    ];
    final cardLoanRows = [
      for (final r in loanRows)
        if (r.repayment?.loanTerms == null) r,
    ];

    double subAmount(Subscription s) => plan.subscriptionAmountOf(s, period);
    final subs =
        subsAll
            .where(
              (s) =>
                  inCategory(s.categoryId) &&
                  (_showHidden ||
                      (period.isYear ? s.isActive : subAmount(s) > 0)),
            )
            .toList()
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return _sort == _PlanSort.alpha
                ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                : subAmount(b).compareTo(subAmount(a));
          });
    // Do sumy wchodzą tylko aktywne — anulowana bywa widoczna, ale nie kosztuje.
    final subsTotal = subs
        .where((s) => s.isActive)
        .fold(0.0, (sum, s) => sum + subAmount(s));

    final empty = all.isEmpty && subsAll.isEmpty;

    // W filtrze tylko kategorie wydatków i subskrypcji.
    final usedCatIds = <String>{
      for (final p in all)
        if (p.kind == PlanKind.expense) ?p.categoryId,
      for (final s in subsAll) ?s.categoryId,
    };
    final filterCategories = storage
        .getCategories(budget.budgetId)
        .where((c) => usedCatIds.contains(c.id))
        .toList();

    // „Zaznacz wszystkie" i akcje zbiorcze — tylko pozycje na widoku: bez
    // zwiniętych sekcji i bez listy schowanej pigułką „Subskrypcje".
    final expensesShown =
        !_collapsed.contains(_kExpensesGroup) &&
        (subs.isEmpty ||
            _onlyPart(_kExpenses, _kSubscriptions) != _kSubscriptions);
    final visibleIds = {
      if (!_collapsed.contains(_kIncomes))
        for (final p in incomes) p.id,
      if (expensesShown)
        for (final p in expenses) p.id,
    };
    final selection = _selected.where(visibleIds.contains).toSet();
    final anyActiveSelected = [
      ...incomes,
      ...expenses,
    ].any((p) => selection.contains(p.id) && !p.archived);
    final hasHidden =
        all.any((p) => p.archived) || subsAll.any((s) => !s.isActive);

    // Rok bez planu, a poprzedni ma pozycje — podpowiedź „zaplanuj na bazie".
    final yearEmpty =
        !all.any((p) => p.hasYear(_year) && !p.archived) &&
        plan.copyCandidates(_year - 1).isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: kAuroraFabLocation,
      floatingActionButton: AuroraAddMenu(
        actions: [
          AuroraAddAction(
            icon: LucideIcons.plus,
            label: 'Dodaj pozycję planu',
            primary: true,
            onTap: () => _push(
              PlanPositionFormScreen(
                initialYear: _year,
                initialMonth: _yearView ? null : _month,
              ),
            ),
          ),
          AuroraAddAction(
            icon: subscriptionIcon,
            label: 'Dodaj subskrypcję',
            onTap: () => _push(
              AddSubscriptionScreen(
                initialBudgetId: context.read<BudgetController>().budgetId,
              ),
            ),
          ),
          AuroraAddAction(
            icon: LucideIcons.creditCard,
            label: 'Pożyczka z karty',
            onTap: () => _push(const CardLoanFormScreen()),
          ),
          AuroraAddAction(
            icon: LucideIcons.landmark,
            label: 'Pożyczka ratalna',
            onTap: () => _push(const InstallmentLoanFormScreen()),
          ),
          AuroraAddAction(
            icon: LucideIcons.copy,
            label: 'Zaplanuj ${_year + 1} na bazie $_year',
            onTap: () => _push(PlanCopyYearScreen(fromYear: _year)),
          ),
        ],
      ),
      body: Column(
        children: [
          WorkspaceTopBar(
            info: SectionInfo.planning,
            // „Dzisiaj" i przełącznik widoku „Rok / Miesiąc" w pustym rogu
            // paska; wcięcie wyrównuje je z chipami filtrów pod spodem. Na
            // wąskim ekranie przewijają się w bok zamiast ucinać.
            leading: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuroraChip(
                    label: 'Dzisiaj',
                    selected: isToday,
                    // Do bieżącego miesiąca — a w widoku rocznym do roku.
                    onTap: () => setState(() {
                      _year = today.year;
                      if (!_yearView) _month = today.month;
                    }),
                  ),
                  const SizedBox(width: 8),
                  AuroraSegmented<bool>(
                    compact: true,
                    segments: const [
                      AuroraSegment(value: true, label: 'Rok'),
                      AuroraSegment(value: false, label: 'Miesiąc'),
                    ],
                    selected: _yearView,
                    onChanged: (year) => setState(() => _yearView = year),
                  ),
                ],
              ),
            ),
          ),
          if (_selecting)
            SelectionBar(
              count: selection.length,
              allSelected:
                  visibleIds.isNotEmpty &&
                  selection.length == visibleIds.length,
              onToggleAll: () => setState(() {
                if (visibleIds.every(_selected.contains)) {
                  _selected.removeAll(visibleIds);
                } else {
                  _selected.addAll(visibleIds);
                }
              }),
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
                  onPressed: () => _bulkMethod(selection),
                ),
                SelectionAction(
                  icon: anyActiveSelected
                      ? LucideIcons.eyeOff
                      : LucideIcons.eye,
                  tooltip: anyActiveSelected
                      ? 'Ukryj zaznaczone'
                      : 'Przywróć zaznaczone',
                  onPressed: () => _bulkArchive(selection, anyActiveSelected),
                ),
                SelectionAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Duplikuj, przenieś lub kopiuj',
                  onPressed: () => _bulkCopies(selection),
                ),
                SelectionAction(
                  icon: LucideIcons.trash2,
                  tooltip: 'Usuń zaznaczone',
                  danger: true,
                  onPressed: () => _bulkDelete(selection),
                ),
              ],
            ),
          TimeFilterBar(
            years: years,
            activeYear: _year,
            monthsOfYear: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            activeMonth: _yearView ? null : _month,
            showMonths: !_yearView,
            allowAllYears: false,
            // Inny rok — w widoku miesięcznym ten sam miesiąc.
            onSelectYear: (y) => setState(() {
              if (y != null) _year = y;
            }),
            onSelectMonth: (m) {
              if (m != null) setState(() => _month = m);
            },
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _sort == _PlanSort.alpha
                      ? 'Sortuj: A→Z'
                      : 'Sortuj: kwota malejąco',
                  icon: Icon(
                    _sort == _PlanSort.alpha
                        ? LucideIcons.arrowDownAZ
                        : LucideIcons.arrowDown10,
                    size: 18,
                  ),
                  onPressed: () => setState(
                    () => _sort = _sort == _PlanSort.alpha
                        ? _PlanSort.amountDesc
                        : _PlanSort.alpha,
                  ),
                ),
                if (hasHidden)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    isSelected: _showHidden,
                    tooltip: _showHidden
                        ? 'Ukryj ukryte i anulowane'
                        : 'Pokaż ukryte i anulowane',
                    icon: Icon(
                      _showHidden ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _showHidden = !_showHidden),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ScopeSwipeArea(
              enabled: budget.canSwitch,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (empty)
                    const _EmptyPlan()
                  else ...[
                    PlanSummaryCard(
                      period: period,
                      totals: plan.totals(period),
                    ),
                    const SizedBox(height: 16),
                    if (yearEmpty) ...[
                      _CopyYearHint(
                        year: _year,
                        onTap: () =>
                            _push(PlanCopyYearScreen(fromYear: _year - 1)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (incomes.isNotEmpty)
                      PlanSection(
                        title: 'Wpływy',
                        total: _sum(incomes, amount),
                        collapsed: _collapsed.contains(_kIncomes),
                        onToggle: () => _toggleSection(_kIncomes),
                        children: _rows(incomes, period, amount, false),
                      ),
                    // Z wybraną kategorią grupa zostaje także pusta — inaczej
                    // filtra nie dałoby się zmienić.
                    if (expenses.isNotEmpty ||
                        subs.isNotEmpty ||
                        _filterCategoryId != null)
                      PlanGroup(
                        title: 'Wydatki',
                        total: -(_sum(expenses, amount) + subsTotal),
                        collapsed: _collapsed.contains(_kExpensesGroup),
                        onToggle: () => _toggleSection(_kExpensesGroup),
                        showProportion: true,
                        filters: filterCategories.isEmpty
                            ? null
                            : _categoryFilters(filterCategories),
                        emptyText: 'Brak wydatków w tej kategorii.',
                        only: _onlyPart(_kExpenses, _kSubscriptions),
                        onShow: (id) =>
                            _showOnly(_kExpenses, _kSubscriptions, id),
                        parts: [
                          if (expenses.isNotEmpty)
                            PlanGroupPart(
                              id: _kExpenses,
                              label: 'Pozycje',
                              amount: -_sum(expenses, amount),
                              color: c.negative,
                              children: _rows(expenses, period, amount, true),
                            ),
                          if (subs.isNotEmpty)
                            PlanGroupPart(
                              id: _kSubscriptions,
                              label: 'Subskrypcje',
                              amount: -subsTotal,
                              color: c.trial,
                              children: _grouped(
                                subs,
                                (s) => s.categoryId,
                                (items) => [
                                  for (final s in items)
                                    SubscriptionRow(
                                      subscription: s,
                                      amountText:
                                          '−${budgetNf.format(subAmount(s))}',
                                      // Pasek jak przy pozycjach: miesiące
                                      // roku, w których subskrypcja kosztuje.
                                      paidMonths: {
                                        for (var m = 1; m <= 12; m++)
                                          if (plan.subscriptionAmountOf(
                                                s,
                                                PlanPeriod(_year, m),
                                              ) >
                                              0)
                                            m,
                                      },
                                      highlightMonth: period.month,
                                      onTap: () => _push(
                                        AddSubscriptionScreen(existing: s),
                                      ),
                                      onLongPress: () =>
                                          _showSubscriptionActions(s),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    if (loanRows.isNotEmpty)
                      PlanGroup(
                        title: 'Pożyczki',
                        total: loanRows.fold(0.0, (s, r) => s + r.net),
                        collapsed: _collapsed.contains(_kLoans),
                        onToggle: () => _toggleSection(_kLoans),
                        only: _onlyPart(_kCardLoans, _kInstallmentLoans),
                        onShow: (id) =>
                            _showOnly(_kCardLoans, _kInstallmentLoans, id),
                        parts: [
                          if (cardLoanRows.isNotEmpty)
                            PlanGroupPart(
                              id: _kCardLoans,
                              label: 'Karta kredytowa',
                              amount: cardLoanRows.fold(
                                0.0,
                                (s, r) => s + r.net,
                              ),
                              color: c.warning,
                              children: [
                                BudgetEntryList(
                                  rows: [
                                    for (final r in cardLoanRows)
                                      CardLoanRow(
                                        loan: r.loan,
                                        repayment: r.repayment,
                                        net: r.net,
                                        onTap: () => _push(
                                          CardLoanFormScreen(
                                            linkId: r.loan.linkId,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          if (installmentRows.isNotEmpty)
                            PlanGroupPart(
                              id: _kInstallmentLoans,
                              label: 'Kredyty ratalne',
                              amount: installmentRows.fold(
                                0.0,
                                (s, r) => s + r.net,
                              ),
                              color: c.trial,
                              children: [
                                BudgetEntryList(
                                  rows: [
                                    for (final r in installmentRows)
                                      InstallmentLoanRow(
                                        loan: r.loan,
                                        repayment: r.repayment!,
                                        net: r.net,
                                        period: period,
                                        today: plan.today,
                                        onTap: () => _push(
                                          InstallmentLoanFormScreen(
                                            linkId: r.loan.linkId,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Szybkie filtry kategorii i podgrupy po kategoriach — w grupie Wydatki,
  /// bo dotyczą tylko jej list, obok pigułek „Razem / Pozycje / Subskrypcje".
  Widget _categoryFilters(List<Category> categories) => FilterRow(
    filters: CategoryFilterBar(
      categories: categories,
      selected: _filterCategoryId,
      onSelect: (id) => setState(() => _filterCategoryId = id),
      padding: EdgeInsets.zero,
    ),
    action: IconButton(
      visualDensity: VisualDensity.compact,
      isSelected: _byCategory,
      tooltip: _byCategory
          ? 'Podgrupy po kategoriach (włączone)'
          : 'Grupuj po kategoriach',
      style: _byCategory
          ? IconButton.styleFrom(
              backgroundColor: context.semanticColors.primary.withValues(
                alpha: 0.25,
              ),
              foregroundColor: context.semanticColors.primary,
            )
          : null,
      icon: const Icon(LucideIcons.layers, size: 18),
      onPressed: () => setState(() => _byCategory = !_byCategory),
    ),
  );

  double _sum(List<PlanPosition> items, double Function(PlanPosition) amount) =>
      items.where((p) => !p.archived).fold(0.0, (s, p) => s + amount(p));

  List<Widget> _rows(
    List<PlanPosition> items,
    PlanPeriod period,
    double Function(PlanPosition) amount,
    bool groupable,
  ) {
    Widget row(PlanPosition p) => SelectableRow(
      selectionMode: _selecting,
      selected: _selected.contains(p.id),
      onTap: () => _toggleSelection(p.id),
      onLongPress: () => _startSelection(p.id),
      child: PlanPositionRow(
        position: p,
        period: period,
        amount: amount(p),
        onTap: () =>
            _push(PlanPositionScreen(positionId: p.id, initialYear: _year)),
      ),
    );
    if (!groupable) return [BudgetEntryList(rows: items.map(row).toList())];
    return _grouped(items, (p) => p.categoryId, (g) => g.map(row).toList());
  }

  /// Podgrupy po kategoriach („Bez kategorii" na końcu), gdy grupowanie jest
  /// włączone — wspólne dla pozycji i subskrypcji, bo słownik jest ten sam.
  List<Widget> _grouped<T>(
    List<T> items,
    String? Function(T) categoryOf,
    List<Widget> Function(List<T>) rows,
  ) {
    if (!_byCategory) return [BudgetEntryList(rows: rows(items))];
    final byId = {
      for (final c in context.read<StorageService>().getCategories(
        context.read<BudgetController>().budgetId,
      ))
        c.id: c,
    };
    final groups = <String?, List<T>>{};
    for (final it in items) {
      (groups[categoryOf(it)] ??= <T>[]).add(it);
    }
    // Podgrupy alfabetycznie, jak lista kategorii; nieznana kategoria
    // (usunięta) i „Bez kategorii" — na końcu.
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ca = a == null ? null : byId[a];
        final cb = b == null ? null : byId[b];
        if (ca == null) return cb == null ? 0 : 1;
        if (cb == null) return -1;
        return plSortKey(ca.name).compareTo(plSortKey(cb.name));
      });
    return [
      for (final k in keys) ...[
        _CategoryLabel(category: k == null ? null : byId[k]),
        BudgetEntryList(rows: rows(groups[k]!)),
      ],
    ];
  }
}

class _CategoryLabel extends StatelessWidget {
  final Category? category;
  const _CategoryLabel({required this.category});

  @override
  Widget build(BuildContext context) {
    final cat = category;
    final c = context.semanticColors;
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
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cat?.color ?? c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Podpowiedź na pustym roku: plan na nowy rok powstaje z poprzedniego.
class _CopyYearHint extends StatelessWidget {
  final int year;
  final VoidCallback onTap;
  const _CopyYearHint({required this.year, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.tile),
        side: BorderSide(color: c.border),
      ),
      child: ListTile(
        leading: Icon(LucideIcons.copy, color: c.primary),
        title: Text('Rok $year nie ma jeszcze planu'),
        subtitle: Text('Zaplanuj go na bazie ${year - 1}'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(LucideIcons.calendarRange, size: 48, color: c.textMuted),
          const SizedBox(height: 12),
          Text(
            'Plan jest pusty — dodaj wpływy i wydatki',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Przy każdej pozycji zaznaczasz miesiące, w których obowiązuje.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
