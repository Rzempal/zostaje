import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Ikona squareSigma (zwiniete biezace) jest tylko w nowszym pakiecie.
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
import '../models/subscription.dart';
import '../models/cashflow.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'cashflow_calendar.dart';
import 'category_icons.dart' show budgetEntryIcon, subscriptionIcon;

/// Współdzielone widgety budżetu: sekcje miesiąca w kalendarzu (zakładka
/// Budżet) i lista wierszy (Planowanie).

final budgetNf = NumberFormat('#,##0.00', 'pl_PL');

String budgetCycleSuffix(BillingCycle cycle) => switch (cycle) {
  BillingCycle.weekly => 'tyg.',
  BillingCycle.monthly => 'mies.',
  BillingCycle.quarterly => 'kw.',
  BillingCycle.yearly => 'rok',
  BillingCycle.monthsOfYear => 'rok',
  BillingCycle.custom => 'cykl',
};

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
