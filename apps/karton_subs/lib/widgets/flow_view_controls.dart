import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Ikony receiptText i squareSigma sa tylko w nowszym pakiecie.
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;

import '../theme/app_theme.dart';
import 'budget_widgets.dart' show MonthFlowSort, MonthFlowGrouping;

/// Sterowanie widokiem sekcji miesiąca — trzy ikony przy nagłówku sekcji,
/// której dotyczą („Płatności", „Podsumowanie miesiąca"): sortowanie,
/// grupowanie po typie i zwijanie wydatków bieżących do sumy.
///
/// Wcześniej stały w pasku tytułu ekranu: daleko od list, na które działały,
/// i widoczne także wtedy, gdy nie było czego sortować. Tutaj są przy samej
/// treści, więc związek jest oczywisty bez tłumaczenia.
///
/// **Każda sekcja ma własny stan, trwały** — te same trzy ikony sterują
/// wyłącznie listą pod sobą, a ustawienie przeżywa wyjście z zakładki. Wspólny
/// stan zmuszał do przełączania w tę i z powrotem, bo obie listy ogląda się
/// w innym celu.
class FlowViewControls extends StatelessWidget {
  final MonthFlowSort sort;
  final MonthFlowGrouping grouping;
  final ValueChanged<MonthFlowSort> onSortChanged;
  final ValueChanged<MonthFlowGrouping> onGroupingChanged;

  /// Czy wydatki bieżące są zwinięte do jednego wiersza z sumą.
  final bool spendingCollapsed;

  /// `null` = przełącznika nie ma. Tak jest, gdy miesiąc ma mniej niż dwa
  /// wydatki bieżące — nie ma czego zwijać, a martwa ikona myli.
  final ValueChanged<bool>? onSpendingCollapsedChanged;

  const FlowViewControls({
    super.key,
    required this.sort,
    required this.grouping,
    required this.onSortChanged,
    required this.onGroupingChanged,
    this.spendingCollapsed = false,
    this.onSpendingCollapsedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    final grouped = grouping == MonthFlowGrouping.byType;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: switch (sort) {
            MonthFlowSort.byDate => 'Sortuj: po dacie',
            MonthFlowSort.byName => 'Sortuj: A–Z (nazwa)',
            MonthFlowSort.amountDesc => 'Sortuj: od największej kwoty',
          },
          icon: Icon(switch (sort) {
            MonthFlowSort.byDate => LucideIcons.arrowDown01,
            MonthFlowSort.byName => LucideIcons.arrowDownAZ,
            MonthFlowSort.amountDesc => LucideIcons.arrowDownWideNarrow,
          }, size: 18),
          // Jeden przycisk cyklujący, nie trzy osobne: pasek nagłówka ma już
          // trzy ikony, a sortowania i tak nie da się wybrać dwóch naraz.
          onPressed: () => onSortChanged(switch (sort) {
            MonthFlowSort.byDate => MonthFlowSort.byName,
            MonthFlowSort.byName => MonthFlowSort.amountDesc,
            MonthFlowSort.amountDesc => MonthFlowSort.byDate,
          }),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          isSelected: grouped,
          tooltip: grouped
              ? 'Grupowanie po typie (włączone)'
              : 'Grupuj po typie: bieżące / subskrypcje / budżet',
          // Aktywny stan = wypełniona pigułka (widoczna też w motywie mono,
          // gdzie akcent jest bezbarwny) + ikona w kolorze akcentu.
          style: grouped
              ? IconButton.styleFrom(
                  backgroundColor: c.primary.withValues(alpha: 0.25),
                  foregroundColor: c.primary,
                )
              : null,
          icon: const Icon(LucideIcons.layers, size: 18),
          onPressed: () => onGroupingChanged(
            grouped ? MonthFlowGrouping.none : MonthFlowGrouping.byType,
          ),
        ),
        if (onSpendingCollapsedChanged case final onChanged?)
          IconButton(
            visualDensity: VisualDensity.compact,
            isSelected: spendingCollapsed,
            tooltip: spendingCollapsed
                ? 'Bieżące zwinięte do sumy — rozwiń listę'
                : 'Zwiń bieżące do jednej sumy',
            style: spendingCollapsed
                ? IconButton.styleFrom(
                    backgroundColor: c.primary.withValues(alpha: 0.25),
                    foregroundColor: c.primary,
                  )
                : null,
            icon: Icon(
              spendingCollapsed
                  ? lucide.LucideIcons.squareSigma
                  : lucide.LucideIcons.receiptText,
              size: 18,
            ),
            onPressed: () => onChanged(!spendingCollapsed),
          ),
      ],
    );
  }
}
