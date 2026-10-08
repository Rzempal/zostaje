import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Opis sekcji: tytuł + krótkie punkty. Punkty zamiast ciągłego tekstu, bo
/// czyta się je wyrywkowo — jedna myśl na wiersz, bez zdań podrzędnych.
class SectionInfo {
  final String title;
  final List<String> points;

  const SectionInfo(this.title, this.points);

  static const budget = SectionInfo('Budżet — przegląd', [
    'Podsumowanie planu; pozycje dodajesz w „Planowaniu"',
    '„Statystyki": średnio miesięcznie w roku, rozkład na miesiące i kategorie',
    '„Kalendarz": płatności miesiąca do odhaczenia i podsumowanie wpływów i wydatków',
  ]);

  static const planning = SectionInfo('Planowanie', [
    'Plan roczny: wpływy, wydatki, karta i subskrypcje na jednym ekranie',
    'Przy pozycji zaznaczasz miesiące, w których obowiązuje — każdy ma własną kwotę',
    'Cały rok = średnio miesięcznie, miesiąc = kwoty tego miesiąca',
    'Pozycja → miesiące: przytrzymaj, by zmienić kilka naraz',
    'Nowy rok: „Zaplanuj kolejny rok" przenosi miesiące i kwoty',
  ]);

  static const incomes = SectionInfo('Wpływy', [
    'Skąd przychodzą pieniądze',
    'Cykliczne (pensja) — zasilają plan „zostaje miesięcznie"',
    'Jednorazowe (premia) — podbijają bilans swojego miesiąca',
  ]);

  static const spending = SectionInfo('Bieżące', [
    'Wydatki z konkretną datą: opłacone i zaplanowane na przyszłość',
    'Wchodzą w bilans swojego miesiąca, nie w plan miesięczny',
    'Trafia tu wszystko, czego nie chcesz rozkładać na średnią',
    'Planner: kwota zarezerwowana w budżecie na bieżące wydatki',
    'Skan zdjęciem rozpoznaje kwotę, wystawcę i datę',
  ]);

  static const recurringExpenses = SectionInfo('Wydatki cykliczne', [
    'Koszty powtarzalne: stałe, raty, przelew do budżetu domowego',
    'Osobna sekcja „Subskrypcje": usługi odnawiane cyklicznie (streaming,'
        ' software, karnety) — wydatki uznaniowe, łatwiejsze do oceny razem',
    'Liczone jako średnia: kwota × liczba płatności ÷ 12',
    'Miesiąc dodania pozycji nie ma znaczenia',
    'Nie chcesz uśredniać? Dodaj w „Bieżących"',
  ]);
}

/// Ikona „i" przy tytule sekcji — tapnięcie otwiera okno z wyjaśnieniem,
/// po co ta sekcja jest i co do niej trafia.
///
/// Okno, nie podpowiedź: jest przycisk zamykający, więc treść czeka, aż
/// skończysz czytać, zamiast znikać po kilku sekundach.
class SectionInfoBadge extends StatelessWidget {
  final SectionInfo info;

  const SectionInfoBadge(this.info, {super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _SectionInfoDialog(info),
      ),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Powiększa cel dotyku bez rozpychania paska tytułu.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Icon(
          LucideIcons.info,
          size: 18,
          color: AppColors.textSecondary,
          semanticLabel: 'O tej sekcji',
        ),
      ),
    );
  }
}

class _SectionInfoDialog extends StatelessWidget {
  final SectionInfo info;

  const _SectionInfoDialog(this.info);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    return AlertDialog(
      title: Text(info.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final point in info.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '—  ',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Rozumiem'),
        ),
      ],
    );
  }
}
