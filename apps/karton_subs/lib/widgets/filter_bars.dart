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

/// Filtr czasu: pasek lat, a po wybraniu roku — pasek jego miesięcy.
///
/// „Dzisiaj" (bieżący rok i miesiąc) i „Cały rok" (bez wybranego miesiąca)
/// stoją w pasku ekranu, nie tutaj — w rzędach lat i miesięcy zabierały
/// miejsce. Dotknięcie wybranego miesiąca też wraca do całego roku.
class TimeFilterBar extends StatelessWidget {
  final List<int> years;
  final int? activeYear;
  final List<int> monthsOfYear;
  final int? activeMonth;
  final void Function(int?) onSelectYear;
  final void Function(int?) onSelectMonth;

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
    this.action,
    this.allowAllYears = true,
  });

  @override
  Widget build(BuildContext context) {
    final yearsRow = SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          if (allowAllYears)
            _timeChip(
              'Wszystkie lata',
              activeYear == null,
              () => onSelectYear(null),
            ),
          ...years.map(
            (y) => _timeChip(
              '$y',
              activeYear == y,
              () => onSelectYear(allowAllYears && activeYear == y ? null : y),
            ),
          ),
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
          _MonthsRow(
            months: monthsOfYear,
            active: activeMonth,
            onSelect: onSelectMonth,
          ),
      ],
    );
  }
}

Widget _timeChip(String label, bool selected, VoidCallback onTap, {Key? key}) =>
    Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AuroraChip(label: label, selected: selected, onTap: onTap),
      ),
    );

/// Pasek miesięcy roku (same miesiące — „Cały rok" jest w pasku ekranu).
/// Wybrany miesiąc sam wjeżdża na środek paska, gdy nie widać go w całości —
/// przy starcie na bieżącym miesiącu (np. „paź") stałby inaczej za prawą
/// krawędzią. Widoczny w całości zostaje, gdzie jest.
class _MonthsRow extends StatefulWidget {
  final List<int> months;
  final int? active;
  final void Function(int?) onSelect;

  const _MonthsRow({
    required this.months,
    required this.active,
    required this.onSelect,
  });

  @override
  State<_MonthsRow> createState() => _MonthsRowState();
}

class _MonthsRowState extends State<_MonthsRow> {
  /// Klucz każdego chipu — do odszukania wybranego.
  final _keys = <int, GlobalKey>{};

  GlobalKey _keyOf(int month) => _keys.putIfAbsent(month, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _revealActive(animate: false);
  }

  @override
  void didUpdateWidget(_MonthsRow old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _revealActive(animate: true);
  }

  void _revealActive({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = widget.active;
      final chip = active == null ? null : _keyOf(active).currentContext;
      if (!mounted || chip == null) return;
      final box = chip.findRenderObject() as RenderBox?;
      final row = context.findRenderObject() as RenderBox?;
      if (box == null || row == null || !box.attached) return;
      final left = box.localToGlobal(Offset.zero, ancestor: row).dx;
      if (left >= 0 && left + box.size.width <= row.size.width) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    // Wszystkie chipy naraz (nie ListView): wybrany musi istnieć, żeby dało
    // się go przewinąć na widok, a miesięcy jest tylko 12.
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final m in widget.months)
              _timeChip(
                kMonthsShort[m - 1],
                active == m,
                () => widget.onSelect(active == m ? null : m),
                key: _keyOf(m),
              ),
          ],
        ),
      ),
    );
  }
}
