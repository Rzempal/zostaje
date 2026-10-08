import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'budget_widgets.dart' show budgetNf, budgetCycleSuffix;
import 'category_icons.dart';

/// Wiersz subskrypcji na liście „Wydatki" — ten sam układ co `BudgetEntryCard`:
/// ikona kategorii, nazwa i kwota w jednej linii, szczegóły w drugiej.
///
/// Subskrypcje miały wcześniej własną kartę (ramka, tło, kropka statusu). Po
/// scaleniu z wydatkami (ADR-027) obie listy są JEDNĄ listą, a dwa style wiersza
/// rozbijałyby ją wzrokowo na dwie wyspy. Informacje z karty nie znikły —
/// zeszły do drugiej linii: okres próbny, współdzielenie, „anulowana".
class SubscriptionRow extends StatelessWidget {
  final Subscription subscription;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Kwota do pokazania zamiast „kwota/cykl" — w planie rocznym wiersz
  /// pokazuje kwotę wybranego okresu (miesiąca albo średnią roku), tak jak
  /// pozycje obok niego (ADR-035).
  final String? amountText;

  const SubscriptionRow({
    super.key,
    required this.subscription,
    this.onTap,
    this.onLongPress,
    this.amountText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final storage = context.read<StorageService>();
    final s = subscription;
    final dimmed = !s.isActive;
    // Okres próbny jeszcze nie kosztuje, więc kwota dostaje kolor trialu —
    // ta sama zasada co na dawnej karcie.
    final color = s.isTrialActive ? c.trial : c.negative;

    final category = s.categoryId != null
        ? storage.getCategory(s.categoryId!)
        : null;

    final amountLine =
        amountText ??
        '−${budgetNf.format(s.amount)}${curLabelSuffix(s.currency.label)}'
            '/${budgetCycleSuffix(s.billingCycle)}';

    // Metoda płatności — ikona ⚡/✋ = automatyczna/manualna (jak w budżecie).
    final method = s.paymentMethod;
    final methodAuto =
        method != null &&
        storage.getPaymentMethods().any(
          (p) => p.name == method && p.isAutomatic,
        );

    // Druga linia: typ · data · (trial / współdzielenie / anulowana) · metoda ·
    // kategoria. Data w tym samym formacie co pozycje budżetu — początek cyklu.
    final details = [
      'Subskrypcja',
      DateFormat('yyyy-MM-dd').format(s.startDate),
      if (s.isTrialActive) 'próbny · ${s.trialDaysRemaining} dni',
      if (s.sharedWith != null && s.sharedWith! > 1) '1/${s.sharedWith} os.',
      if (dimmed) 'anulowana',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Icon(
                category != null
                    ? categoryIcon(category.iconName)
                    : subscriptionIcon,
                size: 18,
                color: category?.color ?? color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (s.isPinned) ...[
                          Icon(
                            LucideIcons.pin,
                            size: 12,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          amountLine,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: c.textMuted,
                        ),
                        children: [
                          TextSpan(text: details),
                          if (method != null) ...[
                            const TextSpan(text: ' · '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(
                                methodAuto ? LucideIcons.zap : LucideIcons.hand,
                                size: 12,
                                color: c.textMuted,
                              ),
                            ),
                            TextSpan(text: ' $method'),
                          ],
                          if (category != null)
                            TextSpan(
                              text: ' · ${category.name}',
                              style: TextStyle(color: category.color),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
