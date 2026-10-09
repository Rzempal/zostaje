import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/subscription_controller.dart';
import '../models/subscription.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import 'budget_progress_bar.dart';

/// Szczegóły subskrypcji na zakładce „Plan" → sekcja „Szczegóły": limit
/// subskrypcji i koszty trwających okresów próbnych.
///
/// Tylko to, czego nie pokazuje nic innego. Koszt miesięczny i roczny wraz
/// z liczbą subskrypcji jest w karcie „Saldo", trend i kategorie — we wspólnych
/// wykresach Planu, a sama lista subskrypcji mieszka od ADR-027 w „Wydatkach".
class SubscriptionStatsView extends StatelessWidget {
  /// Budżet, którego subskrypcje pokazujemy (ADR-037).
  final String budgetId;

  const SubscriptionStatsView({super.key, required this.budgetId});

  /// Czy sekcja ma cokolwiek do pokazania. Bez limitu i bez trwających okresów
  /// próbnych „Szczegóły" byłyby samym nagłówkiem, który po rozwinięciu nic nie daje.
  static bool hasPlanDetails(BuildContext context, String budgetId) {
    final storage = context.read<StorageService>();
    final subs = storage
        .getSubscriptions()
        .where((s) => s.budgetId == budgetId)
        .toList();
    final limit = storage.getBudgetLimit();
    final hasLimit = limit != null && limit > 0 && subs.any((s) => s.isActive);
    return hasLimit || subs.any((s) => s.isTrialActive);
  }

  static const _analytics = AnalyticsService();

  @override
  Widget build(BuildContext context) {
    context.watch<SubscriptionController>();
    final storage = context.read<StorageService>();
    final subs = storage
        .getSubscriptions()
        .where((s) => s.budgetId == budgetId)
        .toList();
    final currencyLabel = storage.getCurrency();
    final currencyEnum = Currency.values.firstWhere(
      (c) => c.name == currencyLabel || c.label == currencyLabel,
      orElse: () => Currency.PLN,
    );

    final budgetStatus = _analytics.getBudgetStatus(
      subs,
      storage.getBudgetLimit(),
      target: currencyEnum,
    );
    final activeTrials = subs.where((s) => s.isTrialActive).toList()
      ..sort(
        (a, b) =>
            (a.trialDaysRemaining ?? 99).compareTo(b.trialDaysRemaining ?? 99),
      );

    return Column(
      children: [
        if (budgetStatus != null)
          BudgetProgressBar(status: budgetStatus, currencySymbol: currencyLabel),
        if (activeTrials.isNotEmpty) ...[
          if (budgetStatus != null) const SizedBox(height: 16),
          _TrialCostsCard(trials: activeTrials, currencySymbol: currencyLabel),
        ],
      ],
    );
  }
}

class _TrialCostsCard extends StatelessWidget {
  final List<Subscription> trials;
  final String currencySymbol;

  const _TrialCostsCard({required this.trials, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final nf = NumberFormat('#,##0.00', 'pl_PL');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.trialBg,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: c.trial.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.clock, color: c.trial, size: 20),
              const SizedBox(width: 8),
              Text(
                'Nadchodzące koszty z triali',
                style: theme.textTheme.titleMedium?.copyWith(color: c.trial),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...trials.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'za ${s.trialDaysRemaining} dni',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: (s.trialDaysRemaining ?? 99) <= 3
                          ? c.warning
                          : c.trial,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${nf.format(s.postTrialAmount ?? s.amount)}${curLabelSuffix(currencySymbol)}/${_cycleSuffix(s.billingCycle)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cycleSuffix(BillingCycle cycle) => switch (cycle) {
    BillingCycle.weekly => 'tydz.',
    BillingCycle.monthly => 'mies.',
    BillingCycle.quarterly => 'kw.',
    BillingCycle.yearly => 'rok',
    BillingCycle.monthsOfYear => 'rok',
    BillingCycle.custom => 'cykl',
  };
}
