import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Wysokość paska zaznaczania — równa paskowi filtrów, który zastępuje.
const double kSelectionBarHeight = 48;

/// Pasek trybu zaznaczania: licznik, „Zaznacz wszystkie" i akcje zbiorcze.
///
/// Wzorzec z „Kartonu z lekami": pasek pojawia się NAD listą, a nie zamiast
/// paska nawigacji — filtry zostają widoczne, więc widać, czego dotyczy
/// „Zaznacz wszystkie" (zawsze: pozycji WIDOCZNYCH po filtrach, nie całego
/// archiwum — inaczej jedno tapnięcie zmieniałoby dane, których nie ma na ekranie).
class SelectionBar extends StatelessWidget {
  final int count;

  /// Czy wszystkie widoczne pozycje są już zaznaczone (przełącza etykietę).
  final bool allSelected;
  final VoidCallback onToggleAll;
  final VoidCallback onClose;

  /// Akcje zbiorcze — ikony po prawej stronie paska.
  final List<SelectionAction> actions;

  const SelectionBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.onToggleAll,
    required this.onClose,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    // Pasek ma WYGLADAC jak inny tryb pracy, a nie jak kolejny rzad filtrow:
    // pigulka z tintem akcentu i obwodka. Bez tego zlewa sie z chipami pod nim
    // i nie widac, ze lista jest teraz w trybie zaznaczania.
    //
    // Wysokosc 48 px jest STALA i rowna paskowi filtrow, ktory ten widget
    // zastepuje — inaczej wejscie w tryb zaznaczania przesuwaloby liste
    // dokladnie w chwili, gdy palec trzyma wiersz.
    return SizedBox(
      height: kSelectionBarHeight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.only(left: 12, right: 2),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: c.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.checkCircle, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: theme.textTheme.titleMedium?.copyWith(
                color: c.primary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            // Etykieta, nie sama ikona: to jedyna akcja paska, której skutek nie
            // jest oczywisty z kształtu. Przy wąskim ekranie albo dużej
            // czcionce skraca się wielokropkiem — ikony akcji zostają całe.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onToggleAll,
                  icon: Icon(
                    allSelected
                        ? LucideIcons.circleSlash
                        : LucideIcons.checkCheck,
                    size: 16,
                    color: c.primary,
                  ),
                  label: Text(
                    allSelected ? 'Odznacz' : 'Zaznacz wszystkie',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.primary),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
            for (final a in actions)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: a.tooltip,
                icon: Icon(
                  a.icon,
                  size: 18,
                  color: a.danger ? c.negative : null,
                ),
                onPressed: count == 0 ? null : a.onPressed,
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Zakończ zaznaczanie',
              icon: const Icon(LucideIcons.x, size: 18),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pojedyncza akcja zbiorcza paska zaznaczania.
class SelectionAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Akcja nieodwracalna (usuwanie) — rysowana kolorem ostrzegawczym.
  final bool danger;

  const SelectionAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });
}

/// Wiersz listy w trybie zaznaczania: kółko po lewej i podświetlenie.
///
/// Kółka pojawiają się dopiero w trybie zaznaczania — w zwykłym widoku
/// zabierałyby szerokość w każdym wierszu listy, którą trzymamy gęsto (ADR-026).
class SelectableRow extends StatelessWidget {
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget child;

  const SelectableRow({
    super.key,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    if (!selectionMode) {
      return GestureDetector(onLongPress: onLongPress, child: child);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? c.primary.withValues(alpha: 0.12) : null,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Icon(
                selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                size: 20,
                color: selected ? c.primary : c.textMuted,
              ),
            ),
            Expanded(child: IgnorePointer(child: child)),
          ],
        ),
      ),
    );
  }
}
