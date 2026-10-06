import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
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

  /// Wiersz przypięty na górze sekcji (koperta „Na bieżące wydatki").
  final Widget? pinnedTop;
  final List<Widget> children;

  const PlanSection({
    super.key,
    required this.title,
    required this.total,
    required this.collapsed,
    required this.onToggle,
    required this.children,
    this.pinnedTop,
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
        if (!collapsed) ...[
          if (pinnedTop != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: pinnedTop!,
            ),
          ...children,
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
                part('Wydatki', totals.outgoing, c.negative),
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

/// Koperta „Na bieżące wydatki" jako wiersz sumy w wydatkach planu — tapnięcie
/// otwiera Planner (ten sam ekran co z „Bieżących").
class PlannerEnvelopeRow extends StatelessWidget {
  final double total;
  final int itemCount;
  final VoidCallback onTap;

  const PlannerEnvelopeRow({
    super.key,
    required this.total,
    required this.itemCount,
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
                          ? 'Na bieżące wydatki — co miesiąc'
                          : 'Zaplanuj kwotę na bieżące wydatki',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                isSet ? '−${budgetNf.format(total)}' : 'Brak',
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
