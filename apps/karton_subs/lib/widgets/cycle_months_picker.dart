import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wybór miesięcy płatności dla cyklu „wybrane miesiące" (ADR-020).
///
/// Dwa sposoby myślenia o tym samym: presety „co N miesięcy" wypełniają siatkę
/// od miesiąca startu, a siatka pozwala poprawić wybór ręcznie. Pod spodem jest
/// tylko lista numerów miesięcy — jedno pole, jeden zapis w backupie.
class CycleMonthsPicker extends StatelessWidget {
  /// Wybrane miesiące (1..12).
  final List<int> months;

  /// Miesiąc startu (z daty-kotwicy) — od niego liczą się presety „co N".
  final int anchorMonth;

  final ValueChanged<List<int>> onChanged;

  const CycleMonthsPicker({
    super.key,
    required this.months,
    required this.anchorMonth,
    required this.onChanged,
  });

  static const _short = [
    'Sty', 'Lut', 'Mar', 'Kwi', 'Maj', 'Cze',
    'Lip', 'Sie', 'Wrz', 'Paź', 'Lis', 'Gru',
  ];

  /// Miesiące co [step], licząc od [anchorMonth] i zawijając rok.
  /// Sensowne tylko dla kroków dzielących 12 — inne nie powtarzają się rocznie.
  static List<int> everyN(int step, int anchorMonth) {
    final out = <int>[];
    for (var i = 0; i < 12 ~/ step; i++) {
      out.add((anchorMonth - 1 + i * step) % 12 + 1);
    }
    return out..sort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = months.toSet();

    bool isPreset(int step) {
      final preset = everyN(step, anchorMonth).toSet();
      return preset.length == selected.length && preset.containsAll(selected);
    }

    Widget preset(String label, int step) => ChoiceChip(
          label: Text(label),
          selected: isPreset(step),
          onSelected: (_) => onChanged(everyN(step, anchorMonth)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            preset('Co 2 mies.', 2),
            preset('Co 3 mies.', 3),
            preset('Co 4 mies.', 4),
            preset('Co pół roku', 6),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Miesiące płatności',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var m = 1; m <= 12; m++)
              FilterChip(
                label: Text(_short[m - 1]),
                selected: selected.contains(m),
                onSelected: (_) {
                  final next = selected.toSet();
                  if (!next.remove(m)) next.add(m);
                  // Pusty wybór nie ma sensu — zostawiamy przynajmniej jeden
                  // miesiąc, inaczej pozycja zniknęłaby z kalendarza.
                  if (next.isEmpty) return;
                  onChanged(next.toList()..sort());
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          selected.length == 1
              ? 'Płatność raz w roku, w wybranym miesiącu. Dzień bierze się z daty startu.'
              : 'Płatność ${selected.length}× w roku. Dzień bierze się z daty startu '
                  '(31 oznacza ostatni dzień krótszego miesiąca).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
