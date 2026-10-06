import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Ikona squareSigma (zwiniete biezace) jest tylko w nowszym pakiecie.
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
import 'package:provider/provider.dart';
import '../models/budget_entry.dart';
import '../models/subscription.dart';
import '../services/budget_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'aurora_segmented.dart';
import 'cashflow_calendar.dart';
import 'category_icons.dart'
    show
        budgetEntryIcon,
        categoryIcon,
        paymentMethodIcon,
        paymentMethodIconColor,
        subscriptionIcon;
import 'plan_progress_bar.dart';

/// Współdzielone widgety budżetu — używane przez Dashboard i ekran Budżet.

final budgetNf = NumberFormat('#,##0.00', 'pl_PL');

/// Przełącznik zakresu Osobisty/Domowy (wspólny dla Budżetu i Dashboardu).
class BudgetScopeToggle extends StatelessWidget {
  final BudgetScope scope;
  final ValueChanged<BudgetScope> onChanged;
  const BudgetScopeToggle({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AuroraSegmented<BudgetScope>(
      selected: scope,
      onChanged: onChanged,
      segments: const [
        AuroraSegment(
          value: BudgetScope.personal,
          label: 'Osobisty',
          icon: LucideIcons.user,
        ),
        AuroraSegment(
          value: BudgetScope.household,
          label: 'Domowy',
          icon: LucideIcons.home,
        ),
      ],
    );
  }
}

String budgetTypeLabel(BudgetEntryType t) => switch (t) {
  BudgetEntryType.income => 'Wpływ',
  BudgetEntryType.spending => 'Wydatek',
  BudgetEntryType.recurringCost => 'Koszt cykliczny',
  BudgetEntryType.oneTimeIncome => 'Wpływ jednorazowy',
  BudgetEntryType.householdTransfer => 'Przelew do domowego',
  BudgetEntryType.installment => 'Rata',
};

String budgetCycleSuffix(BillingCycle cycle) => switch (cycle) {
  BillingCycle.weekly => 'tyg.',
  BillingCycle.monthly => 'mies.',
  BillingCycle.quarterly => 'kw.',
  BillingCycle.yearly => 'rok',
  BillingCycle.monthsOfYear => 'rok',
  BillingCycle.custom => 'cykl',
};

/// Sekcja „Podsumowanie" Dashboardu: jedna karta „Saldo: zostaje miesięcznie".
/// Kwota-bohater + linia wpływy/koszty (zawsze widoczne). Tap rozwija/zwija opis
/// wyjaśniający jak liczone jest saldo (odróżnienie od „bilansu miesiąca").
class BudgetSummarySection extends StatelessWidget {
  final double surplus;
  final double income;
  final double expenses;
  final double subscriptionsExpense;

  /// Liczba aktywnych subskrypcji — pokazywana po rozwinięciu razem z kosztem
  /// miesięcznym i rocznym (dawny „hero" z osobnej sekcji statystyk).
  final int subscriptionsCount;

  /// Rezerwa „Na bieżące wydatki" (Planner) — trzeci składnik. [expenses]
  /// już ją zawiera; tutaj jest osobno, żeby rozpis pokazał ją jako własną
  /// pozycję zamiast chować w kosztach cyklicznych.
  final double allocation;
  final String currency;
  final bool compact;
  final VoidCallback onToggle;

  const BudgetSummarySection({
    super.key,
    required this.surplus,
    required this.income,
    required this.expenses,
    required this.subscriptionsExpense,
    required this.currency,
    required this.compact,
    required this.onToggle,
    this.subscriptionsCount = 0,
    this.allocation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final positive = surplus >= 0;
    final sign = positive ? '' : '−';
    final amountText =
        '$sign${budgetNf.format(surplus.abs())}${curLabelSuffix(currency)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kwota po lewej, wpływy i koszty po prawej — wcześniej wszystko
              // stało w kolumnie przy lewej krawędzi, a prawa połowa karty była
              // pusta i karta zjadała ekran bez powodu.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo: zostaje miesięcznie',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Jedna reguła koloru w całej karcie: zielony =
                        // pieniądze, które przychodzą albo zostają, czerwony =
                        // które wychodzą. Kwota-bohater nie jest wyjątkiem —
                        // gradient akcentu nie niósł tej informacji.
                        Text(
                          amountText,
                          semanticsLabel: 'Saldo $amountText',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: positive ? c.positive : c.negative,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _InlineTrends(
                    income: income,
                    expenses: expenses,
                    currency: currency,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    compact ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                    size: 20,
                    color: c.textMuted,
                  ),
                ],
              ),
              // Rozwijane tapnięciem: przypis subskrypcji + opis „jak liczone
              // jest saldo" (odróżnia saldo — plan, stałe koszty — od bilansu).
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeInOut,
                crossFadeState: compact
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _SurplusBreakdown(
                      income: income,
                      // [expenses] zawiera rezerwę „Zaplanowana na bieżące"
                      // ORAZ subskrypcje, a obie są w rozpisie osobnymi
                      // pozycjami — bez odjęcia policzylibyśmy je dwa razy
                      // i suma nie zeszłaby się z saldem.
                      recurring: expenses - allocation - subscriptionsExpense,
                      subscriptions: subscriptionsExpense,
                      allocation: allocation,
                      surplus: surplus,
                      currency: currency,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Plan: wpływy minus koszty stałe (cykliczne, subskrypcje) '
                      'i rezerwa „Na bieżące wydatki". Bez pozycji jednorazowych, '
                      'korekt i realnych wydatków — te liczy bilans miesiąca.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skąd bierze się saldo: pasek proporcji (ile z wpływów zjadają koszty, ile
/// zostaje) nad rozpisem składników jak na paragonie.
///
/// Pasek odpowiada na „jak dużo", rozpis na „z czego dokładnie" — same procenty
/// nie pozwalają sprawdzić arytmetyki, a same liczby nie pokazują skali.
/// Skala paska to `max(wpływy, koszty + rezerwa)`, więc przy deficycie pasek
/// wypełnia się kosztami zamiast wychodzić poza szerokość karty.
class _SurplusBreakdown extends StatelessWidget {
  final double income;
  final double recurring;
  final double subscriptions;
  final double allocation;
  final double surplus;
  final String currency;

  const _SurplusBreakdown({
    required this.income,
    required this.recurring,
    required this.subscriptions,
    required this.allocation,
    required this.surplus,
    required this.currency,
  });

  // Segmenty paska rozróżnia jasność, nie znaczenie: wszystkie trzy to koszty,
  // więc trzymają się czerwieni, a odcieniami odpowiadają wierszom rozpisu.
  static Color _costColor(AppSemanticColors c) => c.negative;
  static Color _subsColor(AppSemanticColors c) =>
      c.negative.withValues(alpha: 0.7);
  static Color _allocColor(AppSemanticColors c) =>
      c.negative.withValues(alpha: 0.45);

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    final scale = [
      income,
      recurring + subscriptions + allocation,
    ].reduce((a, b) => a > b ? a : b);
    final leftover = surplus > 0 ? surplus : 0.0;

    String pct(double v) => income > 0 ? '${(v / income * 100).round()}%' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scale > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (context, box) {
                  Widget seg(double value, Color color) => SizedBox(
                    width: value <= 0 ? 0 : box.maxWidth * (value / scale),
                    child: ColoredBox(color: color),
                  );
                  return Row(
                    children: [
                      seg(recurring, _costColor(c)),
                      seg(subscriptions, _subsColor(c)),
                      seg(allocation, _allocColor(c)),
                      seg(leftover, c.positive),
                      // Reszta paska (deficyt = 0) tłem, żeby zaokrąglenie
                      // rogów obejmowało pełną szerokość.
                      Expanded(child: ColoredBox(color: c.border)),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _BreakdownRow(
          label: 'Wpływy',
          amount: income,
          currency: currency,
          sign: '',
          color: c.positive,
        ),
        _BreakdownRow(
          label: 'Koszty cykliczne',
          amount: recurring,
          currency: currency,
          sign: '−',
          dotColor: _costColor(c),
          trailing: pct(recurring),
          color: c.negative,
        ),
        if (subscriptions > 0)
          _BreakdownRow(
            label: 'Subskrypcje',
            amount: subscriptions,
            currency: currency,
            sign: '−',
            dotColor: _subsColor(c),
            trailing: pct(subscriptions),
            color: c.negative,
          ),
        if (allocation > 0)
          _BreakdownRow(
            label: 'Zaplanowana na bieżące',
            amount: allocation,
            currency: currency,
            sign: '−',
            dotColor: _allocColor(c),
            trailing: pct(allocation),
            color: c.negative,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: c.border),
        ),
        _BreakdownRow(
          label: 'Zostaje miesięcznie',
          amount: surplus,
          currency: currency,
          sign: surplus < 0 ? '−' : '=',
          dotColor: surplus > 0 ? c.positive : null,
          trailing: surplus > 0 ? pct(surplus) : null,
          emphasis: true,
          color: surplus < 0 ? c.negative : c.positive,
        ),
      ],
    );
  }
}

/// „Rzeczywisty bilans miesiąca" — skąd bierze się bilans wybranego miesiąca.
///
/// Ten sam układ co karta „Saldo" na zakładce Plan (pasek proporcji + rozpis),
/// ale na danych REALNYCH: koszty cykliczne z korektami kwot i ratami tego
/// miesiąca, subskrypcje i wydatki bieżące przypisane do miesiąca.
/// Bieżące zbiorczo — pozycja po pozycji jest ich lista niżej na ekranie.
class MonthBalanceSection extends StatelessWidget {
  final DateTime month;
  final MonthBalanceParts parts;

  /// Saldo planu — punkt odniesienia dla bottom sheeta „bilans vs plan".
  final double surplus;

  /// Pozycje różniące bilans od planu (bottom sheet po przytrzymaniu kwoty).
  final List<BalanceContribution> breakdown;
  final String currency;
  final bool compact;
  final VoidCallback onToggle;

  const MonthBalanceSection({
    super.key,
    required this.month,
    required this.parts,
    required this.surplus,
    required this.breakdown,
    required this.currency,
    required this.compact,
    required this.onToggle,
  });

  void _showBalanceBreakdown(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BalanceBreakdownSheet(
        surplus: surplus,
        balance: parts.balance,
        items: breakdown,
        currency: currency,
        monthLabel: DateFormat('LLLL yyyy', 'pl').format(month),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final balance = parts.balance;
    final positive = balance >= 0;
    final amountText =
        '${positive ? '' : '−'}${budgetNf.format(balance.abs())}'
        '${curLabelSuffix(currency)}';
    final scale = [parts.income, parts.costs].reduce((a, b) => a > b ? a : b);
    final leftover = balance > 0 ? balance : 0.0;

    String pct(double v) =>
        parts.income > 0 ? '${(v / parts.income * 100).round()}%' : '—';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rzeczywisty bilans miesiąca',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    compact ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                    size: 20,
                    color: c.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onLongPress: () => _showBalanceBreakdown(context),
                child: Text(
                  amountText,
                  semanticsLabel: 'Bilans miesiąca $amountText',
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: positive ? c.positive : c.negative,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeInOut,
                crossFadeState: compact
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (scale > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 10,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              Widget seg(double value, Color color) => SizedBox(
                                width: value <= 0
                                    ? 0
                                    : box.maxWidth * (value / scale),
                                child: ColoredBox(color: color),
                              );
                              return Row(
                                children: [
                                  seg(parts.recurring, c.negative),
                                  seg(
                                    parts.subscriptions,
                                    c.negative.withValues(alpha: 0.7),
                                  ),
                                  seg(
                                    parts.spending,
                                    c.negative.withValues(alpha: 0.45),
                                  ),
                                  seg(leftover, c.positive),
                                  Expanded(child: ColoredBox(color: c.border)),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _BreakdownRow(
                      label: 'Wpływy',
                      amount: parts.income,
                      currency: currency,
                      sign: '',
                      color: c.positive,
                    ),
                    _BreakdownRow(
                      label: 'Koszty cykliczne',
                      amount: parts.recurring,
                      currency: currency,
                      sign: '−',
                      dotColor: c.negative,
                      trailing: pct(parts.recurring),
                      color: c.negative,
                    ),
                    if (parts.subscriptions > 0)
                      _BreakdownRow(
                        label: 'Subskrypcje',
                        amount: parts.subscriptions,
                        currency: currency,
                        sign: '−',
                        dotColor: c.negative.withValues(alpha: 0.7),
                        trailing: pct(parts.subscriptions),
                        color: c.negative,
                      ),
                    if (parts.spending > 0)
                      _BreakdownRow(
                        label: 'Bieżące',
                        amount: parts.spending,
                        currency: currency,
                        sign: '−',
                        dotColor: c.negative.withValues(alpha: 0.45),
                        trailing: pct(parts.spending),
                        color: c.negative,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Divider(height: 1, color: c.border),
                    ),
                    _BreakdownRow(
                      label: 'Bilans miesiąca',
                      amount: balance,
                      currency: currency,
                      sign: positive ? '=' : '−',
                      dotColor: positive ? c.positive : null,
                      trailing: positive ? pct(balance) : null,
                      emphasis: true,
                      color: positive ? c.positive : c.negative,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Realne kwoty tego miesiąca: koszty cykliczne razem '
                      'z korektami i ratami, bieżące zbiorczo (lista niżej). '
                      'Przytrzymaj kwotę, by zobaczyć, czym miesiąc różni się '
                      'od planu.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Akordeon „Koszty roczne" — te same składniki kosztów co w rozpisie salda,
/// przeliczone na rok (kwota/mies × 12).
///
/// Osobna sekcja, bo pytanie „ile mnie to kosztuje rocznie" pada rzadziej niż
/// „ile zostaje w tym miesiącu", a mieszanie obu skal w jednej karcie kazałoby
/// przy każdej kwocie sprawdzać, o który okres chodzi.
class AnnualCostsSection extends StatelessWidget {
  final double recurring;
  final double subscriptions;
  final int subscriptionsCount;
  final double allocation;
  final String currency;
  final bool compact;
  final VoidCallback onToggle;

  const AnnualCostsSection({
    super.key,
    required this.recurring,
    required this.subscriptions,
    required this.subscriptionsCount,
    required this.allocation,
    required this.currency,
    required this.compact,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final total = (recurring + subscriptions + allocation) * 12;
    if (total <= 0) return const SizedBox.shrink();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Etykieta i kwota w jednej linii — karta z samą sumą nie
              // potrzebuje dwóch wierszy i połowy szerokości na pustkę.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Koszty roczne',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '${budgetNf.format(total)}${curLabelSuffix(currency)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: c.negative,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    compact ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                    size: 20,
                    color: c.textMuted,
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeInOut,
                crossFadeState: compact
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _BreakdownRow(
                      label: 'Koszty cykliczne',
                      amount: recurring * 12,
                      currency: currency,
                      sign: '',
                      color: c.negative,
                    ),
                    if (subscriptions > 0)
                      _BreakdownRow(
                        label: subscriptionsCount > 0
                            ? 'Subskrypcje ($subscriptionsCount aktywne)'
                            : 'Subskrypcje',
                        amount: subscriptions * 12,
                        currency: currency,
                        sign: '',
                        color: c.negative,
                      ),
                    if (allocation > 0)
                      _BreakdownRow(
                        label: 'Zaplanowana na bieżące',
                        amount: allocation * 12,
                        currency: currency,
                        sign: '',
                        color: c.negative,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Kwoty miesięczne × 12 — koszty cykliczne i subskrypcje '
                      'liczone dzisiejszym stanem, bez pozycji jednorazowych '
                      'i realnych wydatków bieżących.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Akordeon „Podsumowanie roczne" — plan roczny widziany od drugiej strony:
/// ile z niego już wydano, miesiąc po miesiącu (ADR-029).
///
/// „Koszty roczne" mówią, ile rok MA kosztować (kwota/mies × 12). Ta sekcja
/// mówi, gdzie w tym roku realnie jesteśmy — narastająco, więc widać, kiedy
/// zbliżamy się do planu.
class AnnualSummarySection extends StatelessWidget {
  final YearExpenseSummary summary;
  final String currency;
  final bool compact;
  final VoidCallback onToggle;

  /// Przełącznik ujęcia (Plan / Realne) — jak przy wykresach.
  final Widget? trailing;

  const AnnualSummarySection({
    super.key,
    required this.summary,
    required this.currency,
    required this.compact,
    required this.onToggle,
    this.trailing,
  });

  static const _monthNames = [
    'styczeń',
    'luty',
    'marzec',
    'kwiecień',
    'maj',
    'czerwiec',
    'lipiec',
    'sierpień',
    'wrzesień',
    'październik',
    'listopad',
    'grudzień',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final s = summary;
    if (s.planned <= 0 && s.spent <= 0) return const SizedBox.shrink();

    final progress = s.progress;
    final over = progress != null && progress > 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Podsumowanie roczne ${s.year}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: c.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ?trailing,
                      const SizedBox(width: 6),
                      Icon(
                        compact
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronUp,
                        size: 20,
                        color: c.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${budgetNf.format(s.spent)}${curLabelSuffix(currency)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: over ? c.negative : c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.planned > 0
                        ? 'z ${budgetNf.format(s.planned)}${curLabelSuffix(currency)} planowanych'
                              ' (${((progress ?? 0) * 100).round()}%)'
                        : 'brak planu do porównania',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    // Po przekroczeniu planu pasek dzieli sie na plan i nadwyzke
                    // — widac SILE przebicia, a nie tylko fakt (ADR-030).
                    PlanProgressBar(value: s.spent, plan: s.planned),
                  ],
                ],
              ),
            ),
          ),
          // Punktu startu tu nie powtarzamy — stoi w nagłówku sekcji
          // „Statystyki", bo ucina też trend obok.
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeInOut,
            crossFadeState: compact
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  for (final m in s.months)
                    _YearMonthRow(
                      label: _monthNames[m.month - 1],
                      amount: m.amount,
                      cumulative: m.cumulative,
                      currency: currency,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Miesiąc po miesiącu i narastająco. Puste miesiące to te '
                    'sprzed początku ewidencji albo jeszcze nienadeszłe — nie '
                    'wchodzą też do planu, z którym się porównują.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Wiersz miesiąca w podsumowaniu rocznym: kwota miesiąca i narastająco.
class _YearMonthRow extends StatelessWidget {
  final String label;
  final double? amount;
  final double? cumulative;
  final String currency;

  const _YearMonthRow({
    required this.label,
    required this.amount,
    required this.cumulative,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final empty = amount == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: empty ? c.textMuted : null,
              ),
            ),
          ),
          Text(
            empty ? '—' : budgetNf.format(amount!),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: empty ? c.textMuted : c.negative,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(
              empty
                  ? ''
                  : '${budgetNf.format(cumulative!)}${curLabelSuffix(currency)}',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wiersz rozpisu: znak działania, nazwa składnika, kwota i udział w procentach.
class _BreakdownRow extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final String sign;
  final Color? dotColor;
  final String? trailing;
  final bool emphasis;
  final Color? color;

  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.currency,
    required this.sign,
    this.dotColor,
    this.trailing,
    this.emphasis = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final style =
        (emphasis ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              sign,
              style: theme.textTheme.bodyMedium?.copyWith(color: c.textMuted),
            ),
          ),
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
          ] else
            const SizedBox(width: 14),
          Expanded(child: Text(label, style: style)),
          if (trailing != null) ...[
            Text(
              trailing!,
              style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '${budgetNf.format(amount.abs())}${curLabelSuffix(currency)}',
            style: style?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jednolinijkowe wpływy/koszty wewnątrz karty „Saldo" (zawsze widoczne).
class _InlineTrends extends StatelessWidget {
  final double income;
  final double expenses;
  final String currency;
  const _InlineTrends({
    required this.income,
    required this.expenses,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    Widget item(IconData icon, Color color, double amount) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '${budgetNf.format(amount)}${curLabelSuffix(currency)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    // Kolumna, nie Wrap: stoją z boku kwoty-bohatera, więc jedna pod drugą
    // mieszczą się nawet przy pięciocyfrowych sumach.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        item(LucideIcons.trendingUp, c.positive, income),
        const SizedBox(height: 4),
        item(LucideIcons.trendingDown, c.negative, expenses),
      ],
    );
  }
}

/// Sekcja miesiąca: selektor + bilans + kalendarz przepływów + szczegóły dnia.
class BudgetMonthSection extends StatelessWidget {
  final DateTime month;
  final String currency;
  final Map<int, DayCashflow> calendar;
  final int? selectedDay;
  final DateTime? today;
  final bool compact;
  final VoidCallback onToggleCompact;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  /// Tapnięcie w nazwę miesiąca — wybór z okna (rok + siatka miesięcy).
  final VoidCallback onPickMonth;
  final ValueChanged<int> onSelectDay;

  const BudgetMonthSection({
    super.key,
    required this.month,
    required this.currency,
    required this.calendar,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onPrev,
    required this.onNext,
    required this.onPickMonth,
    required this.compact,
    required this.onToggleCompact,
    this.today,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  LucideIcons.calendarDays,
                  size: 20,
                  color: c.textSecondary,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: onPrev,
                      icon: const Icon(LucideIcons.chevronLeft),
                      tooltip: 'Poprzedni miesiąc',
                    ),
                    // Tap w nazwę = wybór miesiąca: skok o rok wstecz
                    // strzałkami to dwanaście tapnięć.
                    InkWell(
                      onTap: onPickMonth,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('LLLL yyyy', 'pl').format(month),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              LucideIcons.calendarDays,
                              size: 14,
                              color: c.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onNext,
                      icon: const Icon(LucideIcons.chevronRight),
                      tooltip: 'Następny miesiąc',
                    ),
                  ],
                ),
                IconButton(
                  onPressed: onToggleCompact,
                  icon: Icon(
                    compact ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                  ),
                  tooltip: compact ? 'Rozwiń kalendarz' : 'Zwiń kalendarz',
                ),
              ],
            ),
            // Kwota bilansu i jej rozbicie mieszkają w sekcji „Rzeczywisty
            // bilans miesiąca" nad kalendarzem — tutaj byłyby drugim miejscem
            // na tę samą liczbę.
            if (!compact) ...[
              const Divider(),
              const SizedBox(height: 12),
              CashflowCalendar(
                monthStart: month,
                data: calendar,
                selectedDay: selectedDay,
                today: today,
                onSelectDay: onSelectDay,
              ),
              const SizedBox(height: 8),
              _DayDetail(
                month: month,
                day: selectedDay,
                flow: selectedDay != null ? calendar[selectedDay] : null,
                currency: currency,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Treść bottom sheeta „dlaczego bilans ≠ saldo": saldo planu → pozycje
/// (grupowane wg rodzaju, ze znakiem) → bilans miesiąca.
class _BalanceBreakdownSheet extends StatelessWidget {
  final double surplus;
  final double balance;
  final List<BalanceContribution> items;
  final String currency;
  final String monthLabel;

  const _BalanceBreakdownSheet({
    required this.surplus,
    required this.balance,
    required this.items,
    required this.currency,
    required this.monthLabel,
  });

  static const _order = [
    BalanceContributionKind.spendingAllocation,
    BalanceContributionKind.oneTimeIncome,
    BalanceContributionKind.oneTimeExpense,
    BalanceContributionKind.amountOverride,
    BalanceContributionKind.installment,
  ];

  String _groupLabel(BalanceContributionKind k) => switch (k) {
    BalanceContributionKind.spendingAllocation => 'Na bieżące (rezerwa)',
    BalanceContributionKind.oneTimeIncome => 'Jednorazowe wpływy',
    BalanceContributionKind.oneTimeExpense => 'Jednorazowe wydatki',
    BalanceContributionKind.amountOverride => 'Korekty kwot',
    BalanceContributionKind.installment => 'Korekty rat',
  };

  String _signed(double v) =>
      '${v >= 0 ? '+' : '−'}${budgetNf.format(v.abs())}${curLabelSuffix(currency)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Skąd bilans $monthLabel', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Bilans to saldo planu skorygowane o ten konkretny miesiąc.',
              style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 16),
            _summaryRow(
              theme,
              c,
              'Saldo planu',
              surplus,
              color: c.textSecondary,
            ),
            const Divider(height: 24),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Brak pozycji jednorazowych i korekt — bilans równy saldu.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.textMuted,
                  ),
                ),
              )
            else
              for (final kind in _order)
                if (items.any((it) => it.kind == kind)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      _groupLabel(kind),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  ...items
                      .where((it) => it.kind == kind)
                      .map((it) => _itemRow(theme, c, it)),
                ],
            const Divider(height: 24),
            _summaryRow(
              theme,
              c,
              'Bilans miesiąca',
              balance,
              color: balance >= 0 ? c.positive : c.negative,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    ThemeData theme,
    AppSemanticColors c,
    String label,
    double value, {
    required Color color,
    bool bold = false,
  }) {
    final sign = value >= 0 ? '' : '−';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style:
              (bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
                  ?.copyWith(color: bold ? null : c.textSecondary),
        ),
        Text(
          '$sign${budgetNf.format(value.abs())}${curLabelSuffix(currency)}',
          style:
              (bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
        ),
      ],
    );
  }

  Widget _itemRow(
    ThemeData theme,
    AppSemanticColors c,
    BalanceContribution it,
  ) {
    final color = it.delta >= 0 ? c.positive : c.negative;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              it.name,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _signed(it.delta),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sortowanie pozycji w sekcjach miesiąca („Płatności", „Podsumowanie miesiąca").
/// Przełącznik siedzi w prawym górnym rogu Dashboardu i rządzi obiema sekcjami.
enum MonthFlowSort {
  /// Chronologicznie — domyślne, bo miesiąc czyta się dzień po dniu.
  byDate,

  /// A→Z po nazwie — do szukania konkretnej pozycji.
  byName,

  /// Od największej kwoty — do pytania „co zjadło ten miesiąc".
  amountDesc,
}

/// Grupowanie pozycji po typie głównym (bieżące / subskrypcje / budżet).
/// Działa jak „warstwy" w Budżecie: nie zastępuje istniejącego podziału sekcji,
/// tylko dokłada podgrupy w środku.
enum MonthFlowGrouping { none, byType }

/// Dzieli pozycje na podgrupy typu głównego w stałej kolejności (puste pomija).
List<({CalendarItemKind kind, List<T> rows})> _groupByKind<T>(
  List<T> rows,
  CalendarItemKind Function(T) kindOf,
) {
  final out = <({CalendarItemKind kind, List<T> rows})>[];
  for (final kind in CalendarItemKind.values) {
    final group = rows.where((r) => kindOf(r) == kind).toList();
    if (group.isNotEmpty) out.add((kind: kind, rows: group));
  }
  return out;
}

/// Ikona pozycji przepływu — ta sama reguła co na listach ([budgetEntryIcon]),
/// żeby jedna pozycja nie wyglądała inaczej w „Płatnościach" niż na swojej
/// zakładce. Strzałka kierunku zostaje tylko awaryjnie, gdy rodzaj pozycji nie
/// dojechał (starsze wywołania bez `entryType`).
IconData _flowIcon(CalendarItem it) => switch (it.kind) {
  CalendarItemKind.subscription => subscriptionIcon,
  _ =>
    it.entryType != null
        ? budgetEntryIcon(it.entryType!)
        : (it.isIncome ? LucideIcons.trendingUp : LucideIcons.trendingDown),
};

/// Podpis wiersza zbiorczego, który zastępuje wszystkie wydatki bieżące
/// miesiąca. Bez odmiany („sierpień 2026", nie „w sierpniu") — miesiąc jest tu
/// etykietą, a nie częścią zdania.
String spendingSummaryLabel(DateTime month) =>
    'Bieżące · ${DateFormat('LLLL yyyy', 'pl').format(month)}';

/// Ile wydatków bieżących ma miesiąc — przełącznik zwijania pokazujemy dopiero
/// od dwóch. Zwijanie jednej pozycji w „sumę jednej pozycji" to sam szum.
int spendingItemCount(Map<int, DayCashflow> calendar) => calendar.values
    .expand((f) => f.items)
    .where((it) => it.kind == CalendarItemKind.spending)
    .length;

/// Podpis podgrupy typu głównego (wewnątrz sekcji).
Widget _kindLabel(
  ThemeData theme,
  AppSemanticColors c,
  CalendarItemKind kind,
) => Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 2),
  child: Text(
    kind.label,
    style: theme.textTheme.labelSmall?.copyWith(color: c.textMuted),
  ),
);

/// Sekcja „Podsumowanie miesiąca": pełne listy wpływów i wydatków z kalendarza
/// przepływów, posortowane wg dnia, z sumami. Kwoty to realne płatności miesiąca
/// (po korektach, z pozycjami jednorazowymi), więc suma może różnić się od
/// bilansu, który uśrednia koszty cykliczne.
///
/// Zestawienie było wcześniej schowane w bottom sheecie pod małą ikoną w karcie
/// bilansu — praktycznie niewidoczne. Teraz jest osobną sekcją na dole zakładki
/// „Bilans miesiąca", zwijaną jak pozostałe (stan trwały w [StorageService]).
class MonthSummarySection extends StatelessWidget {
  final DateTime month;
  final Map<int, DayCashflow> calendar;
  final String currency;
  final bool compact;
  final VoidCallback onToggleCompact;
  final MonthFlowSort sort;
  final MonthFlowGrouping grouping;

  /// Czy wydatki bieżące zwinąć do jednego wiersza z sumą. Miesiąc z kilkunastoma
  /// paragonami zasypywał pozostałe strumienie, choć w bilansie liczą się
  /// zbiorczo — rozwinięta lista jest do przeglądania, zwinięta do porównania.
  final bool spendingCollapsed;

  /// Sterowanie widokiem (sortowanie/grupowanie) w naglowku sekcji — tam, gdzie
  /// dziala. `null` = sekcja bez kontrolek.
  final Widget? viewControls;

  const MonthSummarySection({
    super.key,
    required this.month,
    required this.calendar,
    required this.currency,
    required this.compact,
    required this.onToggleCompact,
    this.sort = MonthFlowSort.byDate,
    this.grouping = MonthFlowGrouping.none,
    this.spendingCollapsed = false,
    this.viewControls,
  });

  /// Czy miesiąc ma cokolwiek do podsumowania (inaczej sekcja się nie pokazuje).
  static bool hasAny(Map<int, DayCashflow> calendar) =>
      calendar.values.any((f) => f.items.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    final incomes = <({int day, CalendarItem item})>[];
    final expenses = <({int day, CalendarItem item})>[];
    final days = calendar.keys.toList()..sort();
    for (final day in days) {
      for (final it in calendar[day]!.items) {
        (it.isIncome ? incomes : expenses).add((day: day, item: it));
      }
    }
    if (incomes.isEmpty && expenses.isEmpty) return const SizedBox.shrink();
    // Wpływy i wydatki sortujemy tą samą regułą, ale osobno — to dwie listy,
    // a nie jedna przecięta nagłówkiem. `null` = zostaw kolejność dni.
    final Comparator<({int day, CalendarItem item})>? cmp = switch (sort) {
      MonthFlowSort.byDate => null,
      MonthFlowSort.byName => (a, b) => a.item.name.toLowerCase().compareTo(
        b.item.name.toLowerCase(),
      ),
      MonthFlowSort.amountDesc => (a, b) => b.item.amount.compareTo(
        a.item.amount,
      ),
    };
    if (cmp != null) {
      incomes.sort(cmp);
      expenses.sort(cmp);
    }

    final incomeTotal = incomes.fold(0.0, (s, r) => s + r.item.amount);
    final expenseTotal = expenses.fold(0.0, (s, r) => s + r.item.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Podsumowanie miesiąca',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?viewControls,
                    IconButton(
                      onPressed: onToggleCompact,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        compact
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronUp,
                      ),
                      tooltip: compact
                          ? 'Rozwiń podsumowanie'
                          : 'Zwiń podsumowanie',
                    ),
                  ],
                ),
              ],
            ),
            // Sumy widoczne zawsze — także po zwinięciu sekcji.
            _InlineTrends(
              income: incomeTotal,
              expenses: expenseTotal,
              currency: currency,
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text(
                'Wpływy i wydatki zaplanowane na ten miesiąc — kwoty miesięcy '
                'pozycji planu, odnowienia subskrypcji i wydatki z Bieżących.',
                style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
              ),
              if (incomes.isNotEmpty) ...[
                _sectionHeader(theme, c, 'Wpływy', incomeTotal, income: true),
                ..._rows(theme, c, incomes),
              ],
              if (expenses.isNotEmpty) ...[
                if (incomes.isNotEmpty) const Divider(height: 24),
                _sectionHeader(
                  theme,
                  c,
                  'Wydatki',
                  expenseTotal,
                  income: false,
                ),
                ..._rows(theme, c, expenses),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Wiersze sekcji — płasko albo w podgrupach typu głównego. Podpisy podgrup
  /// pokazujemy tylko wtedy, gdy jest ich więcej niż jedna (inaczej to sam szum).
  List<Widget> _rows(
    ThemeData theme,
    AppSemanticColors c,
    List<({int day, CalendarItem item})> rows,
  ) {
    // Zwiniete biezace: znikaja z listy i wracaja jako jeden wiersz na koncu.
    // Na koncu, bo to podsumowanie strumienia, a nie zdarzenie konkretnego dnia
    // — wstawione miedzy pozycje z datami psuloby porzadek chronologiczny.
    final spending = rows
        .where((r) => r.item.kind == CalendarItemKind.spending)
        .toList();
    final collapse = spendingCollapsed && spending.length > 1;
    final visible = collapse
        ? rows.where((r) => r.item.kind != CalendarItemKind.spending).toList()
        : rows;
    final collapsedRow = collapse
        ? _collapsedSpendingRow(
            theme,
            c,
            spending.fold(0.0, (s, r) => s + r.item.amount),
            spending.length,
          )
        : null;

    if (grouping == MonthFlowGrouping.none) {
      return [
        for (final r in visible) _itemRow(theme, c, r.day, r.item),
        ?collapsedRow,
      ];
    }
    final groups = _groupByKind(visible, (r) => r.item.kind);
    return [
      for (final g in groups) ...[
        if (groups.length > 1) _kindLabel(theme, c, g.kind),
        for (final r in g.rows) _itemRow(theme, c, r.day, r.item),
      ],
      // Bez podpisu podgrupy — wiersz sam sie przedstawia („Biezace · ...").
      ?collapsedRow,
    ];
  }

  /// Jeden wiersz zamiast wszystkich wydatkow biezacych miesiaca.
  Widget _collapsedSpendingRow(
    ThemeData theme,
    AppSemanticColors c,
    double total,
    int count,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(lucide.LucideIcons.squareSigma, size: 16, color: c.negative),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${spendingSummaryLabel(month)} ($count)',
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '−${budgetNf.format(total)}${curLabelSuffix(currency)}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: c.negative,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  Widget _sectionHeader(
    ThemeData theme,
    AppSemanticColors c,
    String label,
    double total, {
    required bool income,
  }) {
    final color = income ? c.positive : c.negative;
    final sign = income ? '+' : '−';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: c.textSecondary,
            ),
          ),
          Text(
            '$sign${budgetNf.format(total)}${curLabelSuffix(currency)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(
    ThemeData theme,
    AppSemanticColors c,
    int day,
    CalendarItem it,
  ) {
    final color = it.isIncome ? c.positive : c.negative;
    final sign = it.isIncome ? '+' : '−';
    final dateLabel = DateFormat(
      'd MMM',
      'pl',
    ).format(DateTime(month.year, month.month, day));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(_flowIcon(it), size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${it.name} · $dateLabel',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sign${budgetNf.format(it.amount)}${curLabelSuffix(currency)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sekcja płatności miesiąca do odhaczania. [automatic] = false → „Płatności"
/// (manualne przelewy do zrealizowania); true → „Płatności automatyczne"
/// (pobierane same — odhaczanie po zaksięgowaniu). Checkbox oznacza „wykonane"
/// (przekreślenie). Stan trzymany lokalnie per pozycja i data.
/// Płatności miesiąca — jedna sekcja, dwie grupy (Manualne / Automatyczne)
/// rozdzielone separatorem. Każda grupa ma przycisk „odhacz wszystkie".
class MonthPaymentsSection extends StatelessWidget {
  final DateTime month;
  final Map<int, DayCashflow> calendar;
  final String currency;
  final bool compact;
  final VoidCallback onToggleCompact;
  final bool Function(String sourceId, DateTime date) isDone;
  final void Function(String sourceId, DateTime date) onToggle;

  /// Ustawia stan „wykonane" dla wielu płatności naraz (przycisk grupy).
  final void Function(List<({String sourceId, DateTime date})> items, bool done)
  onSetAll;

  final MonthFlowSort sort;
  final MonthFlowGrouping grouping;

  /// Czy wydatki bieżące zwinąć do jednego wiersza. Wiersz zachowuje checkbox:
  /// odhacza WSZYSTKIE bieżące naraz (przez [onSetAll]) i pokazuje stan
  /// zbiorczy — inaczej zwinięcie odbierałoby jedyną funkcję tej sekcji.
  final bool spendingCollapsed;

  /// Sterowanie widokiem (sortowanie/grupowanie) w naglowku sekcji — tam, gdzie
  /// dziala. `null` = sekcja bez kontrolek.
  final Widget? viewControls;

  const MonthPaymentsSection({
    super.key,
    required this.month,
    required this.calendar,
    required this.currency,
    required this.compact,
    required this.onToggleCompact,
    required this.isDone,
    required this.onToggle,
    required this.onSetAll,
    this.sort = MonthFlowSort.byDate,
    this.grouping = MonthFlowGrouping.none,
    this.spendingCollapsed = false,
    this.viewControls,
  });

  /// Czy miesiąc ma jakiekolwiek płatności (manualne lub automatyczne).
  static bool hasAny(Map<int, DayCashflow> calendar) => calendar.values.any(
    (f) => f.items.any((it) => !it.isIncome && it.sourceId != null),
  );

  List<_PayRow> _rows(bool automatic) {
    final out = <_PayRow>[];
    final days = calendar.keys.toList()..sort();
    for (final day in days) {
      for (final it in calendar[day]!.items) {
        if (it.isIncome || it.isAutomatic != automatic || it.sourceId == null) {
          continue;
        }
        out.add(
          _PayRow(
            it.name,
            it.amount,
            DateTime(month.year, month.month, day),
            it.sourceId!,
            it.kind,
          ),
        );
      }
    }
    switch (sort) {
      case MonthFlowSort.byDate:
        break; // kolejność dni z kalendarza
      case MonthFlowSort.byName:
        out.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case MonthFlowSort.amountDesc:
        out.sort((a, b) => b.amount.compareTo(a.amount));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final manual = _rows(false);
    final auto = _rows(true);
    if (manual.isEmpty && auto.isEmpty) return const SizedBox.shrink();

    final total = manual.length + auto.length;
    final done = [
      ...manual,
      ...auto,
    ].where((r) => isDone(r.sourceId, r.date)).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Płatności', style: theme.textTheme.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?viewControls,
                    Text(
                      '$done/$total',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleCompact,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        compact
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronUp,
                      ),
                      tooltip: compact ? 'Rozwiń płatności' : 'Zwiń płatności',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (manual.isNotEmpty)
              _group(
                context,
                'Do zrealizowania ręcznie w tym miesiącu',
                manual,
              ),
            if (manual.isNotEmpty && auto.isNotEmpty) const Divider(height: 20),
            if (auto.isNotEmpty)
              _group(context, 'Pobrane automatycznie w tym miesiącu', auto),
          ],
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String opis, List<_PayRow> rows) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final remaining = rows
        .where((r) => !isDone(r.sourceId, r.date))
        .fold(0.0, (s, r) => s + r.amount);
    final allPaid = remaining < 0.005;
    final items = [for (final r in rows) (sourceId: r.sourceId, date: r.date)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // „opis: kwota" w jednej linii (zamiast osobnego podpisu i sumy).
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$opis: ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: allPaid
                          ? 'rozliczone'
                          : '−${budgetNf.format(remaining)}${curLabelSuffix(currency)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: allPaid ? c.positive : c.negative,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Przycisk „Odhacz" tylko w wersji rozwiniętej.
            if (!compact)
              TextButton.icon(
                onPressed: () => onSetAll(items, !allPaid),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(
                  allPaid ? LucideIcons.square : LucideIcons.checkSquare,
                  size: 16,
                ),
                label: Text(allPaid ? 'Odznacz' : 'Odhacz'),
              ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          ..._payRows(context, theme, c, rows),
        ],
      ],
    );
  }

  /// Wiersze grupy — płasko albo w podgrupach typu głównego (jak „warstwy"
  /// w Budżecie). Podpisy tylko przy więcej niż jednej podgrupie.
  List<Widget> _payRows(
    BuildContext context,
    ThemeData theme,
    AppSemanticColors c,
    List<_PayRow> rows,
  ) {
    final spending = rows
        .where((r) => r.kind == CalendarItemKind.spending)
        .toList();
    final collapse = spendingCollapsed && spending.length > 1;
    final visible = collapse
        ? rows.where((r) => r.kind != CalendarItemKind.spending).toList()
        : rows;
    final collapsedRow = collapse
        ? _collapsedSpendingItem(context, spending)
        : null;

    if (grouping == MonthFlowGrouping.none) {
      return [for (final r in visible) _item(context, r), ?collapsedRow];
    }
    final groups = _groupByKind(visible, (r) => r.kind);
    return [
      for (final g in groups) ...[
        if (groups.length > 1) _kindLabel(theme, c, g.kind),
        for (final r in g.rows) _item(context, r),
      ],
      ?collapsedRow,
    ];
  }

  /// Zwiniete biezace jako jedna pozycja do odhaczenia. Stan zbiorczy:
  /// odhaczone dopiero wtedy, gdy odhaczone sa wszystkie; tapniecie ustawia
  /// wszystkie na raz (odwrotnie do obecnego stanu).
  Widget _collapsedSpendingItem(BuildContext context, List<_PayRow> rows) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final doneCount = rows.where((r) => isDone(r.sourceId, r.date)).length;
    final allDone = doneCount == rows.length;
    final total = rows.fold(0.0, (s, r) => s + r.amount);
    final items = [for (final r in rows) (sourceId: r.sourceId, date: r.date)];

    return InkWell(
      onTap: () => onSetAll(items, !allDone),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              allDone
                  ? LucideIcons.checkSquare
                  : (doneCount > 0
                        ? LucideIcons.minusSquare
                        : LucideIcons.square),
              size: 20,
              color: allDone ? c.positive : c.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${spendingSummaryLabel(month)} ($doneCount/${rows.length})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: allDone ? TextDecoration.lineThrough : null,
                  color: allDone ? c.textMuted : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '−${budgetNf.format(total)}${curLabelSuffix(currency)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: allDone ? c.textMuted : c.negative,
                decoration: allDone ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, _PayRow r) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final done = isDone(r.sourceId, r.date);
    return InkWell(
      onTap: () => onToggle(r.sourceId, r.date),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              done ? LucideIcons.checkSquare : LucideIcons.square,
              size: 20,
              color: done ? c.positive : c.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${r.name} · ${DateFormat('d MMM', 'pl').format(r.date)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? c.textMuted : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '−${budgetNf.format(r.amount)}${curLabelSuffix(currency)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: done ? c.textMuted : c.negative,
                decoration: done ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayRow {
  final String name;
  final double amount;
  final DateTime date;
  final String sourceId;

  /// Typ główny (wydatek / subskrypcja / budżet) — do grupowania podgrupami.
  final CalendarItemKind kind;

  const _PayRow(this.name, this.amount, this.date, this.sourceId, this.kind);
}

class _DayDetail extends StatelessWidget {
  final DateTime month;
  final int? day;
  final DayCashflow? flow;
  final String currency;

  const _DayDetail({
    required this.month,
    required this.day,
    required this.flow,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    if (day == null) {
      return Text(
        'Wybierz dzień, aby zobaczyć wpływy i wydatki.',
        style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
      );
    }
    final dateLabel = DateFormat(
      'd MMMM',
      'pl',
    ).format(DateTime(month.year, month.month, day!));
    final items = flow?.items ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateLabel, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        if (items.isEmpty)
          Text(
            'Brak wpływów i wydatków tego dnia',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
          )
        else
          ...items.map((it) {
            final color = it.isIncome ? c.positive : c.negative;
            final sign = it.isIncome ? '+' : '−';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(_flowIcon(it), size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      it.name,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$sign${budgetNf.format(it.amount)}${curLabelSuffix(currency)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Karta pozycji budżetu (lista zarządzania). Obsługuje wszystkie 4 typy.
class BudgetEntryCard extends StatelessWidget {
  final BudgetEntry entry;
  final VoidCallback onTap;

  /// Miesiąc wybrany w filtrze czasu („YYYY-MM") — `null` przy filtrze na rok
  /// albo „wszystkie lata". Gdy jest ustawiony, karta dokłada po prawej stronie
  /// drugiej linii **kwotę korekty tego miesiąca** (ADR-008).
  ///
  /// Kwota w pierwszej linii to zawsze kwota BAZOWA (plan), więc bez tego przy
  /// zawężeniu do jednego miesiąca nie było jak zobaczyć, ile ta pozycja
  /// naprawdę kosztowała — licznik „korekt: N" mówił tylko, że jakieś są.
  final String? monthKey;

  const BudgetEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.monthKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final storage = context.read<StorageService>();
    final color = entry.isIncome ? c.positive : c.negative;
    final sign = entry.isIncome ? '+' : '−';
    final dimmed = !entry.isActive;
    final cur = entry.currency.label;

    final amountLine = entry.isOneTime
        ? '$sign${budgetNf.format(entry.amount)}${curLabelSuffix(cur)}'
        : '$sign${budgetNf.format(entry.amount)}${curLabelSuffix(cur)}/${budgetCycleSuffix(entry.cycle)}';

    final category = entry.categoryId != null
        ? storage.getCategory(entry.categoryId!)
        : null;

    // Metoda płatności — ikona wg wspólnej reguły (ADR-033): kształt mówi,
    // skąd pieniądze, kolor kto płaci. Bierzemy CAŁĄ metodę, nie samą flagę
    // „automatyczna": inaczej zakup kartą kredytową pokazywałby tu rączkę,
    // choć wszędzie indziej ma kartę.
    final method = entry.paymentMethod;
    final methodPm = method == null
        ? null
        : storage.getPaymentMethods().where((p) => p.name == method).firstOrNull;

    // Druga linia: typ · data · metoda. Data tylko tam, gdzie coś znaczy —
    // pozycja jednorazowa ma swój miesiąc, cykliczna datę startu cyklu.
    // Jeden format daty dla wszystkich pozycji: pelna data pozycji, a gdy jej
    // nie ma (stare rekordy) — sam miesiac. Biezace mialy wczesniej „2026-07",
    // wiec ta sama lista pokazywala dwa rozne formaty.
    final date = entry.startDate != null
        ? DateFormat('yyyy-MM-dd').format(entry.startDate!)
        : entry.month;
    final overrideCount = entry.monthOverrides?.length ?? 0;
    final details = [
      budgetTypeLabel(entry.type),
      ?date,
      if (dimmed) 'wstrzymane',
    ].join(' · ');

    // Prawa strona drugiej linii — jedno z dwojga, nigdy oba naraz:
    //
    //   * kwota tego miesiąca, gdy filtr stoi na jednym miesiącu i pozycja ma
    //     w nim korektę — wtedy licznik nie wnosi nic ponad to, co widać;
    //   * inaczej licznik „korekt: N", czyli sam sygnał „ta pozycja ma miesiące
    //     odbiegające od planu".
    //
    // Korekta samej DATY (bez kwoty) nie ma czego pokazać — kwota miesiąca jest
    // wtedy równa bazowej, więc pozycja spada do licznika.
    final mk = monthKey;
    final overrideAmount = mk != null
        ? entry.overrideForMonth(mk)?.amount
        : null;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ikona kategorii, gdy pozycja ja ma — niesie wiecej informacji
              // niz rodzaj pozycji. Bez kategorii: ikona rodzaju, czyli ta sama,
              // co ikona zakladki, do ktorej pozycja nalezy (ADR-032).
              Icon(
                category != null
                    ? categoryIcon(category.iconName)
                    : budgetEntryIcon(entry.type),
                size: 18,
                color: category?.color ?? color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Linia 1: nazwa i kwota — nazwa ma cala reszte szerokosci.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          amountLine,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Linia 2: opis jako JEDEN ciag (typ · data · metoda ·
                    // kategoria), a kwota korekty POZA nim, dosunieta w prawo.
                    // Osobne elastyczne czesci dzielily szerokosc po rowno,
                    // wiec data urywala sie mimo wolnego miejsca obok; kwota
                    // stoi na zewnatrz, zeby nigdy nie wpadla w wielokropek.
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: c.textMuted,
                              ),
                              children: [
                                TextSpan(text: details),
                                if (method != null) ...[
                                  const TextSpan(text: ' · '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Icon(
                                      methodPm == null
                                          ? LucideIcons.hand
                                          : paymentMethodIcon(methodPm),
                                      size: 12,
                                      // Karta niesie własny kolor (czerwony /
                                      // żółty); zwykła metoda zostaje szara,
                                      // żeby nie krzyczeć w drugiej linii.
                                      color:
                                          (methodPm == null
                                              ? null
                                              : paymentMethodIconColor(
                                                  methodPm,
                                                  c,
                                                )) ??
                                          c.textMuted,
                                    ),
                                  ),
                                  TextSpan(text: ' $method'),
                                ],
                                if (category != null)
                                  TextSpan(
                                    text: ' · ${category.name}',
                                    style: TextStyle(color: category.color),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (overrideAmount == null && overrideCount > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            'korekt: $overrideCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                        ],
                        if (overrideAmount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$sign${budgetNf.format(overrideAmount)}'
                            '${curLabelSuffix(cur)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista pozycji budzetu rozdzielona cienkim separatorem (styl listy
/// maklerskiej): bez ramek i cieni, ktore przy kilkudziesieciu wierszach
/// zjadaly ekran i rozbijaly je wzrokowo na osobne wyspy.
class BudgetEntryList extends StatelessWidget {
  final List<Widget> rows;

  const BudgetEntryList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
          rows[i],
        ],
      ],
    );
  }
}
