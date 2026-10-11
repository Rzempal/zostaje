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

  /// Wcięcie paska; w treści listy (która ma już własne) — zero.
  final EdgeInsetsGeometry padding;

  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        padding: padding,
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

/// Filtr czasu: pasek lat, a po wybraniu roku — pasek jego miesięcy. W obu
/// wybrany chip sam wjeżdża na widok (patrz [_ChipsRow]).
///
/// „Dzisiaj" i przełącznik widoku „Rok / Miesiąc" stoją w pasku ekranu, nie
/// tutaj. Pasek miesięcy jest tylko w widoku miesięcznym ([showMonths]).
class TimeFilterBar extends StatelessWidget {
  final List<int> years;
  final int? activeYear;
  final List<int> monthsOfYear;
  final int? activeMonth;
  final void Function(int?) onSelectYear;
  final void Function(int?) onSelectMonth;

  /// Akcja przyklejona na końcu paska lat (np. „pokaż ukryte").
  final Widget? action;

  /// Czy pokazać pasek miesięcy (widok miesięczny).
  final bool showMonths;

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
    this.showMonths = true,
  });

  @override
  Widget build(BuildContext context) {
    final yearsRow = _ChipsRow(
      // „Wszystkie lata" to chip bez roku — wybrany, gdy roku nie ma.
      selected: activeYear,
      chips: [
        if (allowAllYears)
          (id: null, label: 'Wszystkie lata', onTap: () => onSelectYear(null)),
        for (final y in years)
          (
            id: y,
            label: '$y',
            onTap: () =>
                onSelectYear(allowAllYears && activeYear == y ? null : y),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (action == null)
          yearsRow
        else
          FilterRow(filters: yearsRow, action: action),
        if (activeYear != null && showMonths)
          _ChipsRow(
            selected: activeMonth,
            chips: [
              for (final m in monthsOfYear)
                (
                  id: m,
                  label: kMonthsShort[m - 1],
                  onTap: () => onSelectMonth(m),
                ),
            ],
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

/// Pasek chipów (lata albo miesiące) z jednym wybranym. Wybrany sam wjeżdża
/// na środek paska, gdy nie widać go w całości — przy starcie na bieżącym
/// miesiącu („paź" stałby inaczej za prawą krawędzią) i po zmianie spoza
/// paska (gest przesunięcia, „Dzisiaj"; rok spoza listy dochodzi na końcu).
/// Widoczny w całości zostaje, gdzie jest.
class _ChipsRow extends StatefulWidget {
  final List<({Object? id, String label, VoidCallback onTap})> chips;

  /// Identyfikator wybranego chipu (rok, miesiąc; `null` — chip bez roku).
  final Object? selected;

  const _ChipsRow({required this.chips, required this.selected});

  @override
  State<_ChipsRow> createState() => _ChipsRowState();
}

class _ChipsRowState extends State<_ChipsRow> {
  /// Klucz każdego chipu — do odszukania wybranego.
  final _keys = <Object?, GlobalKey>{};

  GlobalKey _keyOf(Object? id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(_ChipsRow old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _revealSelected(animate: true);
  }

  void _revealSelected({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selected = widget.selected;
      final chip = widget.chips.any((c) => c.id == selected)
          ? _keyOf(selected).currentContext
          : null;
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
    // Wszystkie chipy naraz (nie ListView): wybrany musi istnieć, żeby dało
    // się go przewinąć na widok, a miesięcy jest 12, lat — kilka.
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final chip in widget.chips)
              _timeChip(
                chip.label,
                chip.id == widget.selected,
                chip.onTap,
                key: _keyOf(chip.id),
              ),
          ],
        ),
      ),
    );
  }
}
