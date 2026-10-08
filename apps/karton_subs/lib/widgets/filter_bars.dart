import 'package:flutter/material.dart';

import '../models/category.dart';
import 'aurora_chip.dart';

/// Wspólne paski filtrów list: kategorie i czas. Używają ich „Wydatki",
/// „Wpływy" i „Bieżące" — bez tego każdy ekran miałby własną kopię tych samych
/// chipów, a te zaraz rozjechałyby się wyglądem i zachowaniem.

/// Pasek filtrów z akcją przyklejoną na końcu — chipy przewijają się poziomo,
/// akcja (sortowanie, grupowanie, „pokaż ukryte") zostaje na widoku.
class FilterRow extends StatelessWidget {
  final Widget filters;
  final Widget? action;

  const FilterRow({super.key, required this.filters, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: filters),
        if (action != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: action!),
      ],
    );
  }
}

/// Pasek kategorii: „Wszystkie kategorie" + kategorie obecne w danych ekranu.
class CategoryFilterBar extends StatelessWidget {
  final List<Category> categories;
  final String? selected;
  final void Function(String?) onSelect;

  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
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
                label: 'Wszystkie kategorie',
                selected: selected == null,
                onTap: () => onSelect(null),
              ),
            ),
          ),
          ...categories.map(
            (cat) => Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AuroraChip(
                  label: cat.name,
                  selected: selected == cat.id,
                  accent: cat.color,
                  onTap: () => onSelect(selected == cat.id ? null : cat.id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Krótkie polskie nazwy miesięcy (bez zależności od inicjalizacji locale).
const kMonthsShort = [
  'sty',
  'lut',
  'mar',
  'kwi',
  'maj',
  'cze',
  'lip',
  'sie',
  'wrz',
  'paź',
  'lis',
  'gru',
];

/// Filtr czasu: pasek lat ze skrótem **„Dzisiaj"**, a po wybraniu roku — pasek
/// jego miesięcy.
///
/// „Dzisiaj" ustawia bieżący rok ORAZ miesiąc, więc od razu pokazuje ten
/// miesiąc — jedno tapnięcie zamiast dwóch (rok, potem miesiąc). To najczęstsze
/// pytanie do listy, więc ma być najkrótszą drogą.
class TimeFilterBar extends StatelessWidget {
  final List<int> years;
  final int? activeYear;
  final List<int> monthsOfYear;
  final int? activeMonth;
  final void Function(int?) onSelectYear;
  final void Function(int?) onSelectMonth;

  /// Skrót „Dzisiaj" — bieżący rok + bieżący miesiąc.
  final VoidCallback onToday;
  final bool todaySelected;

  /// Akcja przyklejona na końcu paska lat (np. „pokaż ukryte").
  final Widget? action;

  /// Czy jest „Wszystkie lata" (brak filtra roku). Plan roczny (ADR-035)
  /// zawsze pokazuje konkretny rok — średnia „ze wszystkich lat" nic by nie
  /// mówiła — więc tam rok da się tylko przełączyć, nie odznaczyć.
  final bool allowAllYears;

  const TimeFilterBar({
    super.key,
    required this.years,
    required this.activeYear,
    required this.monthsOfYear,
    required this.activeMonth,
    required this.onSelectYear,
    required this.onSelectMonth,
    required this.onToday,
    this.todaySelected = false,
    this.action,
    this.allowAllYears = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) => Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AuroraChip(label: label, selected: selected, onTap: onTap),
      ),
    );

    final yearsRow = SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          if (allowAllYears)
            chip('Wszystkie lata', activeYear == null, () => onSelectYear(null)),
          ...years.map(
            (y) => chip(
              '$y',
              activeYear == y && !todaySelected,
              () => onSelectYear(
                allowAllYears && activeYear == y ? null : y,
              ),
            ),
          ),
          chip('Dzisiaj', todaySelected, onToday),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (action == null)
          yearsRow
        else
          FilterRow(filters: yearsRow, action: action),
        if (activeYear != null)
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                chip(
                  'Cały rok',
                  activeMonth == null,
                  () => onSelectMonth(null),
                ),
                ...monthsOfYear.map(
                  (m) => chip(
                    kMonthsShort[m - 1],
                    activeMonth == m,
                    () => onSelectMonth(activeMonth == m ? null : m),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
