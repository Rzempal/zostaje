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
import '../widgets/aurora_add_menu.dart';
import '../widgets/budget_widgets.dart' show BudgetEntryList, budgetNf;
import '../widgets/category_icons.dart' show subscriptionIcon;
import '../widgets/filter_bars.dart';
import '../widgets/plan_widgets.dart';
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
const _kExpenses = 'plan_expenses';
/// Sekcja „Pożyczki" (dawniej „Karta kredytowa") — klucz zwinięcia zostaje,
/// żeby zapamiętany stan sekcji nie przepadł.
const _kLoans = 'plan_card';
const _kSubscriptions = 'plan_subscriptions';

/// Zakładka „Planowanie" — plan roczny aktywnego budżetu (ADR-035).
///
/// Wpływy, wydatki, karta i subskrypcje na jednym ekranie. Filtr na cały rok
/// pokazuje średnie miesięczne, filtr na miesiąc — kwoty tego miesiąca.
/// Pozycja widoczna w miesiącu to pozycja, która w nim obowiązuje.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  String? _filterCategoryId;
  late int _year;
  int? _month;
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
    _year = context.read<PlanController>().today.year;
    _collapsed = context.read<StorageService>().getCollapsedBudgetSections();
  }

  /// Rozwija albo zwija kilka sekcji naraz (nagłówek grupy Wydatki).
  void _setSections(List<String> keys, {required bool open}) {
    setState(() {
      if (open) {
        _collapsed.removeAll(keys);
      } else {
        _collapsed.addAll(keys);
      }
    });
    context.read<StorageService>().setCollapsedBudgetSections(_collapsed);
  }

  void _toggleSection(String key) {
    setState(() {
      if (!_collapsed.remove(key)) _collapsed.add(key);
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
        for (final c in context.read<StorageService>().getCategories())
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
        for (final m in context.read<StorageService>().getPaymentMethods())
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

  SubscriptionScope get _subscriptionScope =>
      context.read<BudgetController>().isHousehold
      ? SubscriptionScope.household
      : SubscriptionScope.personal;

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
    final today = plan.today;

    final years = plan.years;
    if (!years.contains(_year)) years.add(_year);
    years.sort();
    final period = PlanPeriod(_year, _month);
    final isToday = _year == today.year && _month == today.month;

    final all = plan.positions;
    final subsAll = plan.subscriptions;

    bool inPeriod(PlanPosition p) => period.isYear
        ? p.hasYear(_year)
        : p.months.containsKey(period.monthKey);
    bool keep(PlanPosition p) =>
        (_showHidden || !p.archived) &&
        (_filterCategoryId == null || p.categoryId == _filterCategoryId) &&
        inPeriod(p);
    double amount(PlanPosition p) => plan.amountOf(p, period);
    int cmp(PlanPosition a, PlanPosition b) => switch (_sort) {
      _PlanSort.alpha => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      _PlanSort.amountDesc => amount(b).compareTo(amount(a)),
    };

    final incomes =
        all.where((p) => p.kind == PlanKind.income && keep(p)).toList()
          ..sort(cmp);
    final expenses =
        all.where((p) => p.kind == PlanKind.expense && keep(p)).toList()
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
          _filterCategoryId == null &&
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

    double subAmount(Subscription s) => plan.subscriptionAmountOf(s, period);
    final subs =
        subsAll
            .where(
              (s) =>
                  (_filterCategoryId == null ||
                      s.categoryId == _filterCategoryId) &&
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

    final empty = all.isEmpty && subsAll.isEmpty;

    final usedCatIds = <String>{
      for (final p in all) ?p.categoryId,
      for (final s in subsAll) ?s.categoryId,
    };
    final filterCategories = storage
        .getCategories()
        .where((c) => usedCatIds.contains(c.id))
        .toList();

    final visibleIds = {
      for (final p in [...incomes, ...expenses]) p.id,
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
              PlanPositionFormScreen(initialYear: _year, initialMonth: _month),
            ),
          ),
          AuroraAddAction(
            icon: subscriptionIcon,
            label: 'Dodaj subskrypcję',
            onTap: () =>
                _push(AddSubscriptionScreen(initialScope: _subscriptionScope)),
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
                  icon: LucideIcons.trash2,
                  tooltip: 'Usuń zaznaczone',
                  danger: true,
                  onPressed: () => _bulkDelete(selection),
                ),
              ],
            )
          else if (!empty && filterCategories.isNotEmpty)
            FilterRow(
              filters: CategoryFilterBar(
                categories: filterCategories,
                selected: _filterCategoryId,
                onSelect: (id) => setState(() => _filterCategoryId = id),
              ),
              action: IconButton(
                visualDensity: VisualDensity.compact,
                isSelected: _byCategory,
                tooltip: _byCategory
                    ? 'Podgrupy po kategoriach (włączone)'
                    : 'Grupuj po kategoriach',
                style: _byCategory
                    ? IconButton.styleFrom(
                        backgroundColor: context.semanticColors.primary
                            .withValues(alpha: 0.25),
                        foregroundColor: context.semanticColors.primary,
                      )
                    : null,
                icon: const Icon(LucideIcons.layers, size: 18),
                onPressed: () => setState(() => _byCategory = !_byCategory),
              ),
            ),
          TimeFilterBar(
            years: years,
            activeYear: _year,
            monthsOfYear: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            activeMonth: _month,
            allowAllYears: false,
            todaySelected: isToday,
            onToday: () => setState(() {
              _year = today.year;
              _month = today.month;
            }),
            onSelectYear: (y) => setState(() {
              if (y == null) return;
              _year = y;
              _month = null;
            }),
            onSelectMonth: (m) => setState(() => _month = m),
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
              enabled: budget.scopeSelectable,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (empty)
                    const _EmptyPlan()
                  else ...[
                    if (_filterCategoryId == null) ...[
                      PlanSummaryCard(
                        period: period,
                        totals: plan.totals(period),
                      ),
                      const SizedBox(height: 16),
                    ],
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
                    if (expenses.isNotEmpty || subs.isNotEmpty)
                      PlanExpenseGroup(
                        positionsTotal: _sum(expenses, amount),
                        subscriptionsTotal: subs
                            .where((s) => s.isActive)
                            .fold(0.0, (sum, s) => sum + subAmount(s)),
                        hasPositions: expenses.isNotEmpty,
                        hasSubscriptions: subs.isNotEmpty,
                        positionsOpen: !_collapsed.contains(_kExpenses),
                        subscriptionsOpen:
                            !_collapsed.contains(_kSubscriptions),
                        onTogglePositions: () => _toggleSection(_kExpenses),
                        onToggleSubscriptions: () =>
                            _toggleSection(_kSubscriptions),
                        onToggleAll: (open) => _setSections(
                          const [_kExpenses, _kSubscriptions],
                          open: open,
                        ),
                        positions: _rows(expenses, period, amount, true),
                        subscriptions: _grouped(
                          subs,
                          (s) => s.categoryId,
                          (items) => [
                            for (final s in items)
                              SubscriptionRow(
                                subscription: s,
                                amountText:
                                    '−${budgetNf.format(subAmount(s))}',
                                onTap: () =>
                                    _push(AddSubscriptionScreen(existing: s)),
                                onLongPress: () =>
                                    _showSubscriptionActions(s),
                              ),
                          ],
                        ),
                      ),
                    if (loanRows.isNotEmpty)
                      PlanSection(
                        title: 'Pożyczki',
                        total: loanRows.fold(0.0, (s, r) => s + r.net),
                        collapsed: _collapsed.contains(_kLoans),
                        onToggle: () => _toggleSection(_kLoans),
                        children: [
                          BudgetEntryList(
                            rows: [
                              for (final r in loanRows)
                                if (r.repayment case final rep?
                                    when rep.loanTerms != null)
                                  InstallmentLoanRow(
                                    loan: r.loan,
                                    repayment: rep,
                                    net: r.net,
                                    period: period,
                                    today: plan.today,
                                    onTap: () => _push(
                                      InstallmentLoanFormScreen(
                                        linkId: r.loan.linkId,
                                      ),
                                    ),
                                  )
                                else
                                  CardLoanRow(
                                    loan: r.loan,
                                    repayment: r.repayment,
                                    net: r.net,
                                    onTap: () => _push(
                                      CardLoanFormScreen(linkId: r.loan.linkId),
                                    ),
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
      for (final c in context.read<StorageService>().getCategories()) c.id: c,
    };
    final groups = <String?, List<T>>{};
    for (final it in items) {
      (groups[categoryOf(it)] ??= <T>[]).add(it);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return (byId[a]?.order ?? 999).compareTo(byId[b]?.order ?? 999);
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
