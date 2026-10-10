import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/budget_entry.dart' show BudgetEntry;
import '../models/plan_position.dart';
import '../services/loan_math.dart';
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'aurora_chip.dart';
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

/// Miesiąc planu "RRRR-MM" po ludzku: „wrz 2026".
String planMonthLabel(String key) =>
    '${kMonthsShort[int.parse(key.substring(5)) - 1]} ${key.substring(0, 4)}';

/// Okres pozycji do opisu: „wrz 2026 – lip 2027 · 11 mies.", „od lis 2026",
/// „do lip 2027"; `null` = pozycja bez okresu.
String? planPositionPeriodText(PlanPosition p) {
  final start = p.periodStart, end = p.periodEnd;
  if (start != null && end != null) {
    int index(String k) =>
        int.parse(k.substring(0, 4)) * 12 + int.parse(k.substring(5));
    final count = index(end) - index(start) + 1;
    return '${planMonthLabel(start)} – ${planMonthLabel(end)} · $count mies.';
  }
  if (start != null) return 'od ${planMonthLabel(start)}';
  if (end != null) return 'do ${planMonthLabel(end)}';
  return null;
}

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

/// Część grupy planu: pigułka z nazwą i sumą oraz lista pod nią.
class PlanGroupPart {
  /// Klucz części — zapamiętany wybór „tylko ta część".
  final String id;
  final String label;

  /// Suma części ze znakiem kierunku (wydatek ujemny, wpływ dodatni).
  final double amount;
  final Color color;
  final List<Widget> children;

  const PlanGroupPart({
    required this.id,
    required this.label,
    required this.amount,
    required this.color,
    required this.children,
  });
}

/// Grupa planu z częściami (ADR-035–037): „Wydatki" (pozycje i subskrypcje)
/// i „Pożyczki" (karta kredytowa i kredyty ratalne).
///
/// Chevron w nagłówku zwija CAŁĄ grupę. Pod nagłówkiem rząd pigułek jak filtr
/// kategorii: „Razem" i części z sumami. „Razem" pokazuje listy części jedna
/// pod drugą (bez mieszania), pigułka części — tylko jej listę. Zapalone
/// pigułki = widoczne listy, więc przy „Razem" świecą wszystkie. Rząd stoi
/// przy prawej krawędzi, a gdy się nie mieści — przewija się w bok. Pasek
/// proporcji — dla części o tym samym kierunku pieniędzy (wydatki); przy
/// pożyczkach netto bywa plus i minus naraz.
class PlanGroup extends StatelessWidget {
  final String title;

  /// Suma grupy ze znakiem kierunku.
  final double total;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Części z czymkolwiek do pokazania (puste pomija wywołujący).
  final List<PlanGroupPart> parts;

  /// Część pokazana sama ([PlanGroupPart.id]); `null` = „Razem". Część,
  /// której w okresie nie ma, liczy się jak „Razem".
  final String? only;
  final ValueChanged<String?> onShow;
  final bool showProportion;

  const PlanGroup({
    super.key,
    required this.title,
    required this.total,
    required this.collapsed,
    required this.onToggle,
    required this.parts,
    required this.only,
    required this.onShow,
    this.showProportion = false,
  });

  static String _signed(double v) => budgetNf.format(v.abs() < 0.005 ? 0 : v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final weights = [for (final p in parts) p.amount.abs()];
    final weightSum = weights.fold(0.0, (a, b) => a + b);
    // Jedna część — bez pigułek, sama lista.
    final pills = parts.length > 1;
    final shownId = pills && parts.any((p) => p.id == only) ? only : null;
    final shown = [
      for (final p in parts)
        if (shownId == null || p.id == shownId) p,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  _signed(total),
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
          if (showProportion && pills && weightSum > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      for (final (i, p) in parts.indexed)
                        if (weights[i] > 0)
                          Expanded(
                            flex: (weights[i] / weightSum * 1000).round().clamp(
                              1,
                              1000,
                            ),
                            child: ColoredBox(color: p.color),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          if (pills)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AuroraChip(
                        label: 'Razem',
                        selected: shownId == null,
                        onTap: () => onShow(null),
                      ),
                      for (final p in parts) ...[
                        const SizedBox(width: 8),
                        AuroraChip(
                          label: '${p.label} ${_signed(p.amount)}',
                          selected: shownId == null || shownId == p.id,
                          accent: p.color,
                          onTap: () => onShow(p.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          for (final (i, p) in shown.indexed) ...[
            // Granica list części przy „Razem" — zamiast podtytułów, które
            // powtarzałyby nazwy z pigułek.
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 2, thickness: 2, color: c.border),
              ),
            ...p.children,
          ],
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
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              // Zakup z pożyczki ratalnej (ADR-036): raty są
                              // w Pożyczkach, tu — sam zakup.
                              if (p.linkId != null &&
                                  p.kind == PlanKind.expense) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Zakup z pożyczki ratalnej',
                                  child: Icon(
                                    LucideIcons.link,
                                    size: 13,
                                    color: c.primary,
                                  ),
                                ),
                              ],
                            ],
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
                if (totals.loanInflows != 0 || totals.loanRepayments != 0)
                  part(
                    'Pożyczki netto',
                    totals.loansNet,
                    totals.loansNet >= 0 ? c.positive : c.negative,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// „rata" / „raty" / „rat" po liczebniku.
String _installmentsWord(int n) {
  if (n == 1) return 'rata';
  final tens = n % 100, units = n % 10;
  return units >= 2 && units <= 4 && (tens < 12 || tens > 14) ? 'raty' : 'rat';
}

/// Wiersz pożyczki ratalnej (ADR-036): rata i RRSO, pasek spłaty, co dzieje
/// się w pokazanym okresie (rata k z n, wypłata) i kwota netto okresu.
class InstallmentLoanRow extends StatelessWidget {
  final PlanPosition loan;
  final PlanPosition repayment;

  /// Netto okresu w walucie docelowej (wypłata − raty w tym okresie).
  final double net;
  final PlanPeriod period;
  final DateTime today;
  final VoidCallback? onTap;

  const InstallmentLoanRow({
    super.key,
    required this.loan,
    required this.repayment,
    required this.net,
    required this.period,
    required this.today,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final t = repayment.loanTerms!;
    final s = LoanSchedule.ofTerms(t);
    final keys = [for (var i = 0; i < t.count; i++) s.monthKeyOf(i)];
    final day = DateTime(today.year, today.month, today.day);
    final paid = [
      for (var i = 0; i < t.count; i++)
        if (!s.dateOf(i).isAfter(day)) i,
    ].length;
    final remaining = [
      for (var i = paid; i < t.count; i++) repayment.amountIn(keys[i]),
    ].fold(0.0, (sum, a) => sum + a);
    final total = LoanMath.totalRepayment(
      principal: t.principal,
      count: t.count,
      installment: t.installment,
      rrso: t.rrso,
    );
    final drawKey = BudgetEntry.monthKeyOf(t.drawdown);

    final String now;
    if (period.isYear) {
      final prefix = '${period.year}-';
      final inYear = keys.where((k) => k.startsWith(prefix)).length;
      now =
          'w ${period.year}: $inYear ${_installmentsWord(inYear)}'
          '${drawKey.startsWith(prefix) ? ' + wypłata' : ''}';
    } else {
      final k = planMonthKey(period.year, period.month!);
      final i = keys.indexOf(k);
      now = i >= 0
          ? 'rata ${i + 1} z ${t.count}'
          : k == drawKey
          ? 'wypłata pożyczki'
          : 'bez raty';
    }

    final color = net >= 0 ? c.positive : c.negative;
    final small = theme.textTheme.labelSmall?.copyWith(color: c.textMuted);
    final rrso = NumberFormat('0.##', 'pl_PL').format(t.rrso);
    final drawMonth = kMonthsShort[t.drawdown.month - 1];

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: loan.archived ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(LucideIcons.landmark, size: 18, color: c.trial),
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
                      '${repayment.paymentMethod ?? 'Pożyczka ratalna'} · '
                      '${t.count} × ${budgetNf.format(t.installment)} · '
                      'RRSO $rrso%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: t.count == 0 ? 0 : paid / t.count,
                              minHeight: 4,
                              color: c.trial,
                              backgroundColor: c.border,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Etykieta ma limit szerokości: pasek spłaty zostaje
                        // widoczny także przy dużej czcionce systemowej.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                AppRadii.control,
                              ),
                            ),
                            child: Text(
                              now,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: c.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'spłacono $paid z ${t.count} · zostało '
                      '${budgetNf.format(remaining)} · koszt '
                      '${budgetNf.format(total - t.principal)}',
                      style: small,
                    ),
                    Text(
                      'wypłata ${t.drawdown.day} $drawMonth '
                      '${planSignedAmount(t.principal, inflow: true)} → raty '
                      '${planMonthLabel(t.firstMonth)} – '
                      '${planMonthLabel(t.lastMonth)}',
                      style: small,
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
