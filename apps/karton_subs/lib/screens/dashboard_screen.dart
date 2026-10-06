import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/budget_controller.dart';
import '../controllers/plan_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/category.dart';
import '../models/subscription.dart';
import '../services/analytics_service.dart' show MonthlyDataPoint;
import '../services/budget_service.dart' show DayCashflow;
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/category_breakdown_chart.dart';
import '../widgets/flow_view_controls.dart';
import '../widgets/frost_card.dart';
import '../widgets/month_picker_dialog.dart';
import '../widgets/scope_swipe_area.dart';
import '../widgets/spending_chart.dart';
import '../widgets/sync_refresh.dart';
import '../widgets/subscription_stats_view.dart' show SubscriptionStatsView;

/// Sortowanie, grupowanie i zwijanie JEDNEJ sekcji miesiąca. Trzy ustawienia
/// razem, bo razem stoją w nagłówku sekcji i razem opisują „jak patrzę na tę
/// listę" — rozdzielanie ich na trzy pola po dwa razy tylko by je rozjeżdżało.
///
/// Trwałe: wczytywane w `initState`, zapisywane przy każdej zmianie. Ustawienie
/// listy raz na jakiś czas i zastawanie jej tak samo jest wygodniejsze niż
/// powrót do domyślnego po każdym wyjściu z zakładki.
class _FlowViewState {
  /// Klucz sekcji w ustawieniach. Stały — tytuły na ekranie bywają poprawiane.
  final String section;

  MonthFlowSort sort;
  MonthFlowGrouping grouping;
  bool spendingCollapsed;

  _FlowViewState(this.section, StorageService storage)
    : sort = MonthFlowSort.values.firstWhere(
        (v) => v.name == storage.getFlowSort(section),
        orElse: () => MonthFlowSort.byDate,
      ),
      grouping = MonthFlowGrouping.values.firstWhere(
        (v) => v.name == storage.getFlowGrouping(section),
        orElse: () => MonthFlowGrouping.none,
      ),
      spendingCollapsed = storage.getFlowSpendingCollapsed(section);
}

/// Zakładka „Budżet" — przegląd planu rocznego (ADR-035).
///
/// **Statystyki**: wybrany rok — średnio miesięcznie, rozkład na miesiące
/// i kategorie, do tego limity i okresy próbne subskrypcji.
/// **Kalendarz**: płatności miesiąca do odhaczenia i podsumowanie wpływów
/// i wydatków — z planu, subskrypcji i Bieżących. Porównanie planu
/// z rzeczywistością zniknęło razem z korektami (ADR-028/029 zastąpione).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late DateTime _selectedMonth;
  int? _selectedDay;
  late int _statsYear;

  // Personalizacja: zwinięcie sekcji (trwałe — StorageService).
  late bool _monthCompact;
  late bool _monthSummaryCompact;
  late bool _paymentsCompact;
  late bool _planDetailsCompact;

  /// Ustawienia widoku sekcji miesiąca — **osobne dla każdej sekcji** i trwałe.
  /// „Płatności" to lista do odhaczenia, więc chce się ją mieć po dacie;
  /// „Podsumowanie" odpowiada na „co zjadło miesiąc", więc częściej po kwocie.
  late final _FlowViewState _paymentsView;
  late final _FlowViewState _summaryView;

  DateTime get _today => Subscription.devDateOverride ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final now = _today;
    _selectedMonth = DateTime(now.year, now.month, 1);
    _selectedDay = now.day; // bieżący miesiąc → domyślnie dziś
    _statsYear = now.year;
    final storage = context.read<StorageService>();
    _paymentsView = _FlowViewState('payments', storage);
    _summaryView = _FlowViewState('summary', storage);
    _monthCompact = storage.getDashboardMonthCompact();
    _monthSummaryCompact = storage.getDashboardMonthSummaryCompact();
    _paymentsCompact = storage.getDashboardPaymentsCompact();
    _planDetailsCompact = storage.getDashboardPlanDetailsCompact();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Kontrolki widoku dla jednej sekcji miesiąca. Każda sekcja dostaje własny
  /// [_FlowViewState], więc te same trzy ikony sterują tylko listą pod sobą.
  Widget _controlsFor(_FlowViewState view, Map<int, DayCashflow> calendar) {
    final storage = context.read<StorageService>();
    return FlowViewControls(
      sort: view.sort,
      grouping: view.grouping,
      spendingCollapsed: view.spendingCollapsed,
      onSortChanged: (v) {
        setState(() => view.sort = v);
        storage.setFlowSort(view.section, v.name);
      },
      onGroupingChanged: (v) {
        setState(() => view.grouping = v);
        storage.setFlowGrouping(view.section, v.name);
      },
      // Bez czego zwijać nie ma przełącznika (patrz `spendingItemCount`).
      onSpendingCollapsedChanged: spendingItemCount(calendar) > 1
          ? (v) {
              setState(() => view.spendingCollapsed = v);
              storage.setFlowSpendingCollapsed(view.section, v);
            }
          : null,
    );
  }

  void _toggleMonth() {
    setState(() => _monthCompact = !_monthCompact);
    context.read<StorageService>().setDashboardMonthCompact(_monthCompact);
  }

  void _toggleMonthSummary() {
    setState(() => _monthSummaryCompact = !_monthSummaryCompact);
    context.read<StorageService>().setDashboardMonthSummaryCompact(
      _monthSummaryCompact,
    );
  }

  void _togglePayments() {
    setState(() => _paymentsCompact = !_paymentsCompact);
    context.read<StorageService>().setDashboardPaymentsCompact(
      _paymentsCompact,
    );
  }

  void _togglePlanDetails() {
    setState(() => _planDetailsCompact = !_planDetailsCompact);
    context.read<StorageService>().setDashboardPlanDetailsCompact(
      _planDetailsCompact,
    );
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
        1,
      );
      _selectedDay = _defaultDayFor(_selectedMonth);
    });
  }

  /// Powrót do bieżącego miesiąca → zaznacz dziś; inny miesiąc → bez wyboru.
  int? _defaultDayFor(DateTime month) {
    final t = _today;
    return month.year == t.year && month.month == t.month ? t.day : null;
  }

  /// Wybór miesiąca kalendarza — okno zamiast klikania strzałkami przez
  /// pół roku.
  Future<void> _pickMonth() async {
    final picked = await showMonthPicker(
      context,
      initialMonth: _selectedMonth,
      today: _today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month, 1);
      _selectedDay = _defaultDayFor(_selectedMonth);
    });
  }

  /// Zakładka „Statystyki": wybrany rok planu.
  List<Widget> _statsTab(
    PlanController plan,
    BudgetController budget,
    String currency,
  ) {
    final stats = plan.yearStats(_statsYear);
    final c = context.semanticColors;
    List<MonthlyDataPoint> series(double Function(PlanMonthTotals) pick) => [
      for (var m = 1; m <= 12; m++)
        MonthlyDataPoint(
          month: DateTime(_statsYear, m),
          amount: pick(stats.months[m - 1]),
        ),
    ];
    final categories = [
      ...context.read<StorageService>().getCategories(),
      const Category(
        id: PlanService.envelopeCategoryKey,
        name: 'Na bieżące (Planner)',
        colorHex: '#94A3B8',
        iconName: 'receipt',
        order: 999,
      ),
    ];
    final scope = budget.isHousehold
        ? SubscriptionScope.household
        : SubscriptionScope.personal;

    return [
      _YearNav(
        year: _statsYear,
        onPrev: () => setState(() => _statsYear--),
        onNext: () => setState(() => _statsYear++),
      ),
      const SizedBox(height: 12),
      _YearAveragesCard(stats: stats, currency: currency),
      const SizedBox(height: 16),
      SpendingChart.multi(
        title: 'Miesiące $_statsYear',
        currencySymbol: currency,
        series: [
          ChartSeries(
            label: 'Wpływy',
            data: series((m) => m.income),
            color: c.positive,
          ),
          ChartSeries(
            label: 'Wydatki',
            data: series((m) => m.outgoing),
            color: c.negative,
          ),
        ],
      ),
      const SizedBox(height: 16),
      CategoryBreakdownChart(
        categoryTotals: {
          for (final e in stats.expenseByCategory.entries)
            e.key ?? 'budget_other': e.value,
        },
        categories: categories,
        currencySymbol: currency,
        subtitle: 'średnio/mies.',
      ),
      if (SubscriptionStatsView.hasPlanDetails(context, scope)) ...[
        const SizedBox(height: 24),
        _DetailsSection(
          compact: _planDetailsCompact,
          onToggleCompact: _togglePlanDetails,
          children: [SubscriptionStatsView(scopeFilter: scope)],
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetController>();
    final plan = context.watch<PlanController>();
    // Nasłuch subskrypcji — limity i okresy próbne mają się odświeżać.
    context.watch<SubscriptionController>();
    final currency = context.read<StorageService>().getCurrency();
    final calendar = plan.calendarForMonth(_selectedMonth);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: const _UpdateBanner(),
          ),
          TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Statystyki'),
              Tab(text: 'Kalendarz'),
            ],
          ),
          Expanded(
            child: ScopeSwipeArea(
              enabled: budget.scopeSelectable,
              child: TabBarView(
                // Tryb „oba": swipe poziomy zmienia zakres (ScopeSwipeArea),
                // zakładki tapem. Tryb jednozakresowy: swipe przełącza zakładki
                // (ScopeSwipeArea oddaje gest TabBarView).
                physics: budget.scopeSelectable
                    ? const NeverScrollableScrollPhysics()
                    : null,
                controller: _tab,
                children: [
                  SyncRefresh(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                      // Gest musi dzialac takze wtedy, gdy tresc nie wypelnia
                      // ekranu (np. swiezy budzet bez pozycji).
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: _statsTab(plan, budget, currency),
                    ),
                  ),
                  SyncRefresh(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        BudgetMonthSection(
                          month: _selectedMonth,
                          currency: currency,
                          calendar: calendar,
                          selectedDay: _selectedDay,
                          today: _today,
                          compact: _monthCompact,
                          onToggleCompact: _toggleMonth,
                          onPrev: () => _shiftMonth(-1),
                          onNext: () => _shiftMonth(1),
                          onPickMonth: _pickMonth,
                          onSelectDay: (d) => setState(() => _selectedDay = d),
                        ),
                        if (MonthPaymentsSection.hasAny(calendar)) ...[
                          const SizedBox(height: 24),
                          MonthPaymentsSection(
                            month: _selectedMonth,
                            calendar: calendar,
                            currency: currency,
                            compact: _paymentsCompact,
                            onToggleCompact: _togglePayments,
                            isDone: budget.isPaymentDone,
                            onToggle: budget.togglePaymentDone,
                            onSetAll: (items, done) =>
                                budget.setPaymentsDone(items, done),
                            sort: _paymentsView.sort,
                            grouping: _paymentsView.grouping,
                            spendingCollapsed: _paymentsView.spendingCollapsed,
                            viewControls: _controlsFor(_paymentsView, calendar),
                          ),
                        ],
                        if (MonthSummarySection.hasAny(calendar)) ...[
                          const SizedBox(height: 24),
                          MonthSummarySection(
                            month: _selectedMonth,
                            calendar: calendar,
                            currency: currency,
                            compact: _monthSummaryCompact,
                            onToggleCompact: _toggleMonthSummary,
                            sort: _summaryView.sort,
                            grouping: _summaryView.grouping,
                            spendingCollapsed: _summaryView.spendingCollapsed,
                            viewControls: _controlsFor(_summaryView, calendar),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wybór roku statystyk: strzałki na sąsiednie lata.
class _YearNav extends StatelessWidget {
  final int year;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _YearNav({
    required this.year,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    return Row(
      children: [
        IconButton(
          icon: Icon(LucideIcons.chevronLeft, color: c.textSecondary),
          onPressed: onPrev,
        ),
        Expanded(
          child: Text(
            'Plan $year',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: Icon(LucideIcons.chevronRight, color: c.textSecondary),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Średnio miesięcznie w roku — odpowiedź na „jaki jest mój miesięczny
/// budżet": wpływy, składniki wydatków i to, co zostaje.
class _YearAveragesCard extends StatelessWidget {
  final PlanYearStats stats;
  final String currency;

  const _YearAveragesCard({required this.stats, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final avg = stats.average;
    final total = stats.total;
    String fmt(double v) => '${budgetNf.format(v)}${curLabelSuffix(currency)}';

    Widget row(String label, double value, {Color? color, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: bold
                      ? theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: c.textSecondary,
                        ),
                ),
              ),
              Text(
                fmt(value),
                style:
                    (bold
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                          color: color,
                          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
            ],
          ),
        );

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Średnio miesięcznie', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          row('Wpływy', avg.income, color: c.positive),
          row('Wydatki stałe', -avg.expense, color: c.negative),
          if (avg.envelope != 0)
            row('Na bieżące (Planner)', -avg.envelope, color: c.negative),
          if (avg.subscriptions != 0)
            row('Subskrypcje', -avg.subscriptions, color: c.negative),
          if (total.cardLoans != 0 || total.cardRepayments != 0)
            row(
              'Karta netto',
              avg.cardNet,
              color: avg.cardNet >= 0 ? c.positive : c.negative,
            ),
          const Divider(height: 20),
          row(
            'Zostaje',
            avg.left,
            color: avg.left >= 0 ? c.positive : c.negative,
            bold: true,
          ),
          const SizedBox(height: 6),
          Text(
            'Rocznie: wpływy ${fmt(total.income)} · wydatki '
            '${fmt(total.outgoing)} · zostaje ${fmt(total.left)}',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// „Limity i okresy próbne" — dwie rzeczy do pilnowania przy subskrypcjach:
/// wykorzystanie limitu i koszty, które zaczną obowiązywać po zakończeniu
/// trwających okresów próbnych. Sekcja chowa się, gdy nie ma ani limitu, ani
/// trwającego okresu próbnego.
class _DetailsSection extends StatelessWidget {
  final bool compact;
  final VoidCallback onToggleCompact;
  final List<Widget> children;

  const _DetailsSection({
    required this.compact,
    required this.onToggleCompact,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggleCompact,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'Limity i okresy próbne',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Icon(
                  compact ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                  size: 20,
                  color: context.semanticColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (!compact) ...[const SizedBox(height: 12), ...children],
      ],
    );
  }
}

/// Baner aktualizacji na Dashboardzie — proaktywny sygnal, gdy dostepna jest
/// nowsza wersja (OTA). Pokazuje tez postep pobierania/instalacji.
class _UpdateBanner extends StatefulWidget {
  const _UpdateBanner();

  @override
  State<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<_UpdateBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateService>(
      builder: (context, svc, _) {
        final c = context.semanticColors;

        Widget shell(Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.positiveBg,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: c.positive.withValues(alpha: 0.3)),
          ),
          child: child,
        );

        // Pobieranie — postep (niezaleznie od dismiss).
        if (svc.status == UpdateStatus.downloading) {
          return shell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pobieranie aktualizacji… ${svc.downloadProgress.toInt()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.positive,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: svc.downloadProgress / 100,
                  backgroundColor: c.positive.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(c.positive),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          );
        }

        if (svc.status == UpdateStatus.launchingInstaller) {
          return shell(
            Row(
              children: [
                Icon(LucideIcons.smartphone, color: c.positive, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Uruchamianie instalatora…')),
              ],
            ),
          );
        }

        // Dostepna aktualizacja (stan spoczynku) — info + akcja.
        if (!svc.updateAvailable || _dismissed) return const SizedBox.shrink();

        return shell(
          Row(
            children: [
              Icon(LucideIcons.download, color: c.positive, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Dostępna aktualizacja ${svc.latestVersion ?? ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.positive,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => svc.startUpdate(),
                child: const Text('Zainstaluj'),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                tooltip: 'Ukryj',
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        );
      },
    );
  }
}
