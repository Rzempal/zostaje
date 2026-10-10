import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Pojedynczy segment przełącznika [AuroraSegmented].
class AuroraSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const AuroraSegment({required this.value, required this.label, this.icon});
}

/// Segmentowy przełącznik w stylu Aurora: kontener „frost", aktywny segment w
/// `--accent-gradient` z ciemnym tekstem ([AppColors.onAccent]) — np. widok
/// „Miesiąc / Rok" w Planowaniu.
class AuroraSegmented<T> extends StatelessWidget {
  final List<AuroraSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Wersja do paska z chipami: segmenty tak szerokie jak napis i wysokość
  /// jak [AuroraChip], zamiast rozciągnięcia na całą szerokość.
  final bool compact;

  const AuroraSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget segment(AuroraSegment<T> seg) => _Segment<T>(
      segment: seg,
      selected: seg.value == selected,
      compact: compact,
      onTap: () => onChanged(seg.value),
    );

    return Container(
      padding: EdgeInsets.all(compact ? 2 : 4),
      decoration: BoxDecoration(
        color: AppColors.frost1,
        border: Border.all(color: AppColors.frostBorder),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (final seg in segments)
            compact ? segment(seg) : Expanded(child: segment(seg)),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  final AuroraSegment<T> segment;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _Segment({
    required this.segment,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onAccent : AppColors.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
            : const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.accentGradient : null,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (segment.icon != null) ...[
              Icon(segment.icon, size: 15, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
