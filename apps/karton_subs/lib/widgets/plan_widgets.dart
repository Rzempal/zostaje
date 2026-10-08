import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/plan_position.dart';
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'budget_widgets.dart' show budgetNf;
import 'category_icons.dart';
import 'filter_bars.dart' show kMonthsShort;

/// Wspólne elementy zakładki „Planowanie" i szczegółów pozycji (ADR-035).

/// Kwota ze znakiem kierunku: wpływ „+", wydatek „−".
String planSignedAmount(
  double amount, {
  required bool inflow,
  String? currency,
}) =>
    '${inflow ? '+' : '−'}${budgetNf.format(amount)}${curLabelSuffix(currency)}';

/// Etykieta okresu: „średnio/mies." dla roku albo nazwa miesiąca.
String planPeriodLabel(PlanPeriod period) => period.isYear
    ? 'średnio/mies. ${period.year}'
    : '${kMonthsShort[period.month! - 1]} ${period.year}';

/// Sekcja listy: nagłówek z sumą (tapnięcie zwija) i wiersze pod nim. Suma
/// zostaje widoczna po zwinięciu — po to się sekcję zwija.
class PlanSection extends StatelessWidget {
  final String title;
  final double total;
  final bool collapsed;
  final VoidCallback onToggle;

  final List<Widget> children;

  const PlanSection({
    super.key,
    required this.title,
    required this.total,
    required this.collapsed,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  budgetNf.format(total),
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
        if (!collapsed) ...children,
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Grupa „Wydatki" (ADR-035): suma pozycji planu i subskrypcji, pasek
/// proporcji i dwa przełączniki, z których każdy rozwija swoją listę.
/// Subskrypcje to szczególna składowa wydatków — liczą się do sumy grupy
/// (tak jak w karcie „Zostaje"), ale mają osobny moduł i osobną listę.
class PlanExpenseGroup extends StatelessWidget {
  /// Kwoty dodatnie; znak minus dokłada widok.
  final double positionsTotal;
  final double subscriptionsTotal;
  final bool hasPositions;
  final bool hasSubscriptions;
  final bool positionsOpen;
  final bool subscriptionsOpen;
  final VoidCallback onTogglePositions;
  final VoidCallback onToggleSubscriptions;
  final List<Widget> positions;
  final List<Widget> subscriptions;

  const PlanExpenseGroup({
    super.key,
    required this.positionsTotal,
    required this.subscriptionsTotal,
    required this.hasPositions,
    required this.hasSubscriptions,
    required this.positionsOpen,
    required this.subscriptionsOpen,
    required this.onTogglePositions,
    required this.onToggleSubscriptions,
    required this.positions,
    required this.subscriptions,
  });

  static String _minus(double v) => budgetNf.format(v == 0 ? 0 : -v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final total = positionsTotal + subscriptionsTotal;
    final share = total > 0 ? positionsTotal / total : 1.0;
    final posColor = c.negative;
    final subColor = c.trial;

    Widget chip(
      String label,
      double amount,
      Color color,
      bool open,
      VoidCallback onTap,
    ) => Material(
      color: color.withValues(alpha: open ? 0.22 : 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: BorderSide(
          color: open ? color : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$label ${_minus(amount)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 14,
                color: c.textMuted,
              ),
            ],
          ),
        ),
      ),
    );

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: c.textSecondary),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Wydatki', style: theme.textTheme.titleMedium),
              ),
              Text(
                _minus(total),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (hasPositions && hasSubscriptions && total > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    Expanded(
                      flex: (share * 1000).round(),
                      child: ColoredBox(color: posColor),
                    ),
                    Expanded(
                      flex: ((1 - share) * 1000).round(),
                      child: ColoredBox(color: subColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (hasPositions)
              chip('Pozycje', positionsTotal, posColor, positionsOpen,
                  onTogglePositions),
            if (hasSubscriptions)
              chip('Subskrypcje', subscriptionsTotal, subColor,
                  subscriptionsOpen, onToggleSubscriptions),
          ],
        ),
        if (hasPositions && positionsOpen) ...[
          label('Pozycje'),
          ...positions,
        ],
        if (hasSubscriptions && subscriptionsOpen) ...[
          label('Subskrypcje'),
          ...subscriptions,
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Pasek dwunastu kratek: w których miesiącach roku pozycja obowiązuje.
/// Wybrany miesiąc (filtr) jest obwiedziony — widać od razu, czy pozycja
/// w nim jest i jak wygląda reszta roku.
class PlanMonthStrip extends StatelessWidget {
  final PlanPosition position;
  final int year;
  final int? highlightMonth;

  const PlanMonthStrip({
    super.key,
    required this.position,
    required this.year,
    this.highlightMonth,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    final color = position.isInflow ? c.positive : c.negative;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var m = 1; m <= 12; m++)
          Container(
            width: 5,
            height: 10,
            margin: const EdgeInsets.only(left: 1.5),
            decoration: BoxDecoration(
              color: position.months.containsKey(planMonthKey(year, m))
                  ? color.withValues(alpha: 0.85)
                  : c.textMuted.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(1.5),
              border: highlightMonth == m
                  ? Border.all(color: c.textPrimary, width: 1)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Wiersz pozycji planu: nazwa i kwota okresu, w drugiej linii kategoria,
/// metoda i dzień płatności, a z prawej pasek miesięcy roku.
class PlanPositionRow extends StatelessWidget {
  final PlanPosition position;
  final PlanPeriod period;

  /// Kwota okresu w walucie docelowej (miesiąc albo średnia roku).
  final double amount;
  final VoidCallback? onTap;

  const PlanPositionRow({
    super.key,
    required this.position,
    required this.period,
    required this.amount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final storage = context.read<StorageService>();
    final p = position;
    final category = p.categoryId != null
        ? storage.getCategory(p.categoryId!)
        : null;
    final color = p.isInflow ? c.positive : c.negative;
    final day = period.isYear ? p.day : p.dayIn(period.monthKey!);
    final details = [
      ?p.paymentMethod,
      if (day != null) 'dzień $day',
      if (p.archived) 'ukryta',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: p.archived ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Icon(
                category != null
                    ? categoryIcon(category.iconName)
                    : (p.isInflow
                          ? LucideIcons.trendingUp
                          : LucideIcons.repeat),
                size: 18,
                color: category?.color ?? color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          planSignedAmount(amount, inflow: p.isInflow),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
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
                                if (category != null)
                                  TextSpan(
                                    text: details.isEmpty
                                        ? category.name
                                        : ' · ${category.name}',
                                    style: TextStyle(color: category.color),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PlanMonthStrip(
                          position: p,
                          year: period.year,
                          highlightMonth: period.month,
                        ),
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

/// Karta „Zostaje" na górze planu: wynik okresu i jego składniki.
class PlanSummaryCard extends StatelessWidget {
  final PlanPeriod period;
  final PlanMonthTotals totals;

  const PlanSummaryCard({
    super.key,
    required this.period,
    required this.totals,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final left = totals.left;
    Widget part(String label, double value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: c.textMuted),
          ),
          Text(
            budgetNf.format(value),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.tile),
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Zostaje · ${planPeriodLabel(period)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  budgetNf.format(left),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: left >= 0 ? c.positive : c.negative,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                part('Wpływy', totals.income, c.positive),
                // Ze znakiem minus, jak sumy w nagłówkach sekcji.
                part(
                  'Wydatki',
                  totals.outgoing == 0 ? 0 : -totals.outgoing,
                  c.negative,
                ),
                if (totals.cardLoans != 0 || totals.cardRepayments != 0)
                  part(
                    'Karta netto',
                    totals.cardNet,
                    totals.cardNet >= 0 ? c.positive : c.negative,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wiersz pożyczki z karty: obie strony pary w jednej linii (kiedy przychodzi,
/// kiedy wychodzi) i kwota netto okresu.
class CardLoanRow extends StatelessWidget {
  final PlanPosition loan;
  final PlanPosition? repayment;

  /// Netto okresu w walucie docelowej (pożyczka − spłata w tym okresie).
  final double net;
  final VoidCallback? onTap;

  const CardLoanRow({
    super.key,
    required this.loan,
    required this.repayment,
    required this.net,
    this.onTap,
  });

  String _side(PlanPosition? p, {required bool inflow}) {
    final e = p?.months.entries.firstOrNull;
    if (e == null) return '—';
    final m = int.parse(e.key.substring(5));
    final day = p!.dayIn(e.key);
    final when = day != null
        ? '$day ${kMonthsShort[m - 1]}'
        : '${kMonthsShort[m - 1]} ${e.key.substring(0, 4)}';
    return '$when ${planSignedAmount(e.value.amount, inflow: inflow)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final color = net >= 0 ? c.positive : c.negative;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: loan.archived ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Icon(LucideIcons.creditCard, size: 18, color: c.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            loan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          planSignedAmount(net.abs(), inflow: net >= 0),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${loan.paymentMethod ?? 'Karta'} · '
                      '${_side(loan, inflow: true)} → '
                      'spłata ${_side(repayment, inflow: false)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: c.textMuted,
                      ),
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
