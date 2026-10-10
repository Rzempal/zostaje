import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'budget_widgets.dart' show budgetNf, budgetCycleSuffix;
import 'category_icons.dart';
import 'plan_widgets.dart' show PlanMonthStrip;

/// Wiersz subskrypcji na liście „Wydatki" — ten sam układ co wiersz pozycji
/// planu (`PlanPositionRow`): ikona kategorii, nazwa i kwota w jednej linii,
/// w drugiej metoda · dzień płatności · kategoria, a z prawej pasek miesięcy.
///
/// Subskrypcję odróżnia przedrostek „Subskrypcja · " przy nazwie. Jej własne
/// informacje (okres próbny, współdzielenie, „anulowana") stoją w drugiej
/// linii przed kategorią.
class SubscriptionRow extends StatelessWidget {
  final Subscription subscription;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Kwota do pokazania zamiast „kwota/cykl" — w planie rocznym wiersz
  /// pokazuje kwotę wybranego okresu (miesiąca albo sumę roku), tak jak
  /// pozycje obok niego (ADR-035).
  final String? amountText;

  /// Miesiące roku (1–12) z płatnością — pasek jak przy pozycjach; `null` =
  /// bez paska.
  final Set<int>? paidMonths;

  /// Wybrany miesiąc (obwiedziony na pasku).
  final int? highlightMonth;

  const SubscriptionRow({
    super.key,
    required this.subscription,
    this.onTap,
    this.onLongPress,
    this.amountText,
    this.paidMonths,
    this.highlightMonth,
  });

  /// Dzień płatności jak przy pozycjach; cykl bez stałego dnia miesiąca —
  /// po ludzku.
  static String? _payDay(Subscription s) => switch (s.billingCycle) {
    BillingCycle.weekly => 'co tydzień',
    BillingCycle.custom =>
      s.customCycleDays == null ? null : 'co ${s.customCycleDays} dni',
    _ => 'dzień ${s.startDate.day}',
  };

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

    // Druga linia w kolejności pozycji: metoda · dzień · (próbny /
    // współdzielenie / anulowana) · kategoria.
    final details = [
      ?s.paymentMethod,
      ?_payDay(s),
      if (s.isTrialActive) 'próbny · ${s.trialDaysRemaining} dni',
      if (s.sharedWith != null && s.sharedWith! > 1) '1/${s.sharedWith} os.',
      if (dimmed) 'anulowana',
    ].join(' · ');
    final months = paidMonths;

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
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Subskrypcja · ',
                                  style: TextStyle(color: c.textMuted),
                                ),
                                TextSpan(text: s.name),
                              ],
                            ),
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: c.textMuted,
                              ),
                              children: [
                                TextSpan(text: details),
                                if (category != null)
                                  TextSpan(
                                    text: details.isEmpty
                                        ? category.name
                                        : ' · ${category.name}',
                                    style: TextStyle(color: category.color),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (months != null) ...[
                          const SizedBox(width: 8),
                          PlanMonthStrip(
                            months: months,
                            color: color,
                            highlightMonth: highlightMonth,
                          ),
                        ],
                      ],
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
