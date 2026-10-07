import 'package:flutter/material.dart';
import '../models/cashflow.dart';
import '../theme/app_theme.dart';

/// Siatka miesiąca z kropkami przepływów: zielona = wpływ, czerwona = wydatek.
/// Tap w dzień wywołuje [onSelectDay]. Lekka, bez zewnętrznych zależności.
class CashflowCalendar extends StatelessWidget {
  final DateTime monthStart;
  final Map<int, DayCashflow> data;
  final int? selectedDay;
  final ValueChanged<int> onSelectDay;
  final DateTime? today;

  const CashflowCalendar({
    super.key,
    required this.monthStart,
    required this.data,
    required this.selectedDay,
    required this.onSelectDay,
    this.today,
  });

  static const _labels = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final year = monthStart.year;
    final month = monthStart.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month, 1).weekday - 1; // Pn=0
    final rows = ((leading + daysInMonth) / 7).ceil();
    final todayDay = (today != null &&
            today!.year == year &&
            today!.month == month)
        ? today!.day
        : null;

    return Column(
      children: [
        Row(
          children: _labels
              .map((l) => Expanded(
                    child: Center(
                      child: Text(l,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: c.textMuted)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        for (int r = 0; r < rows; r++)
          Row(
            children: [
              for (int col = 0; col < 7; col++)
                Expanded(
                  child: _buildCell(
                    context,
                    r * 7 + col - leading + 1,
                    daysInMonth,
                    todayDay,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(
      BuildContext context, int day, int daysInMonth, int? todayDay) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: 44);
    }
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final flow = data[day];
    final isSelected = day == selectedDay;
    final isToday = day == todayDay;

    return InkWell(
      onTap: () => onSelectDay(day),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: isSelected ? c.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: c.primary.withValues(alpha: 0.6))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            _dots(c, flow),
          ],
        ),
      ),
    );
  }

  /// Kropki dnia: zielona = wplyw, czerwona = wydatek manualny, zolta = auto.
  Widget _dots(AppSemanticColors c, DayCashflow? flow) {
    final colors = <Color>[
      if (flow?.hasIncome ?? false) c.positive,
      if (flow?.hasManualExpense ?? false) c.negative,
      if (flow?.hasAutomaticExpense ?? false) c.warning,
    ];
    if (colors.isEmpty) return const SizedBox(height: 5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < colors.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          _dot(colors[i]),
        ],
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
