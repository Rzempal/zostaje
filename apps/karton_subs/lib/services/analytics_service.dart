// analytics_service.dart — Engine obliczeń analitycznych

import '../models/subscription.dart';
import 'currency_service.dart';

class MonthlyDataPoint {
  final DateTime month;
  final double amount;
  const MonthlyDataPoint({required this.month, required this.amount});
}

class BudgetStatus {
  final double spent;
  final double limit;
  final double percentage;
  final bool isOverBudget;
  const BudgetStatus({
    required this.spent,
    required this.limit,
    required this.percentage,
    required this.isOverBudget,
  });
}

class AnalyticsService {
  static const _currency = CurrencyService();
  const AnalyticsService();

  double _monthly(Subscription s, Currency target) =>
      _currency.convertMonthlyAmount(s, target);

  double getMonthlyTotal(List<Subscription> subs, {Currency? target}) {
    final t = target ?? Currency.PLN;
    return subs
        .where((s) => s.isActive)
        .fold(0.0, (sum, s) => sum + _monthly(s, t));
  }

  double getYearlyProjection(List<Subscription> subs, {Currency? target}) =>
      getMonthlyTotal(subs, target: target) * 12;

  Map<String, double> getCategoryBreakdown(
    List<Subscription> subs, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final breakdown = <String, double>{};
    for (final sub in subs.where((s) => s.isActive)) {
      final catId = sub.categoryId ?? 'cat_other';
      breakdown[catId] = (breakdown[catId] ?? 0) + _monthly(sub, t);
    }
    return breakdown;
  }

  /// Koszt subskrypcji w KONKRETNYM miesiącu — historycznie, z dat startu
  /// i anulowania. Subskrypcja liczy się, jeśli zaczęła się nie później niż
  /// z końcem tego miesiąca i nie była wtedy jeszcze anulowana.
  double getMonthlyTotalForMonth(
    List<Subscription> subs,
    DateTime month, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final first = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);
    double total = 0;
    for (final sub in subs) {
      final startedBefore = !sub.startDate.isAfter(endOfMonth);
      final wasActive = sub.isActive ||
          (sub.cancelledDate != null && !sub.cancelledDate!.isBefore(first));
      if (startedBefore && wasActive) {
        total += _monthly(sub, t);
      }
    }
    return total;
  }

  BudgetStatus? getBudgetStatus(
    List<Subscription> subs,
    double? budgetLimit, {
    Currency? target,
  }) {
    if (budgetLimit == null || budgetLimit <= 0) return null;
    final spent = getMonthlyTotal(subs, target: target);
    final pct = spent / budgetLimit;
    return BudgetStatus(
      spent: spent,
      limit: budgetLimit,
      percentage: pct,
      isOverBudget: spent > budgetLimit,
    );
  }
}
