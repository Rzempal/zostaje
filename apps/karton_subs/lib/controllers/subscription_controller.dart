import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription.dart';
import '../services/storage_service.dart';
import '../services/analytics_service.dart';
import '../services/currency_service.dart';
import '../services/notification_service.dart';
import '../services/app_logger.dart';

/// Zarządza stanem subskrypcji: CRUD + usage log + computed analytics.
class SubscriptionController extends ChangeNotifier {
  static final _log = AppLogger.get('SubscriptionController');
  final StorageService _storage;
  final NotificationService _notifications;
  static const _uuid = Uuid();
  static const _analytics = AnalyticsService();
  static const _currencyService = CurrencyService();

  SubscriptionController(this._storage, this._notifications);

  /// Wymusza odświeżenie UI (np. po zmianie ustawień waluty/budżetu)
  void refresh() => notifyListeners();

  List<Subscription> get all => _storage.getSubscriptions();
  List<Subscription> get active => _storage.getActiveSubscriptions();
  List<Subscription> get trials =>
      active.where((s) => s.isTrialActive).toList();
  List<Subscription> get expiringTrials =>
      trials.where((s) => (s.trialDaysRemaining ?? 99) <= 7).toList();

  Currency get _targetCurrency {
    final code = _storage.getCurrency();
    return Currency.values.firstWhere(
      (c) => c.name == code || c.label == code,
      orElse: () => Currency.PLN,
    );
  }

  double get totalMonthly =>
      _analytics.getMonthlyTotal(all, target: _targetCurrency);
  double get totalYearly => totalMonthly * 12;

  /// Suma miesięczna po zakończeniu aktywnych triali
  double get postTrialMonthlyIncrease {
    final t = _targetCurrency;
    return trials.fold(0.0, (sum, s) {
      return sum + _currencyService.convert(s.postTrialMonthlyAmount, s.currency, t);
    });
  }

  Map<String, double> get categoryBreakdown =>
      _analytics.getCategoryBreakdown(all, target: _targetCurrency);

  List<Subscription> get pinned =>
      active.where((s) => s.isPinned).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<Subscription> sorted({
    String? categoryId,
    bool activeOnly = true,
  }) {
    var list = List<Subscription>.from(activeOnly ? active : all);
    if (categoryId != null) {
      list = list.where((s) => s.categoryId == categoryId).toList();
    }
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<void> add(Subscription sub) async {
    await _storage.saveSubscription(sub);
    _notifications.scheduleForSubscription(sub, storage: _storage);
    _log.info('Added: ${sub.name}');
    notifyListeners();
  }

  Future<Subscription> create({
    required String name,
    String? description,
    required double amount,
    required Currency currency,
    required BillingCycle billingCycle,
    int? customCycleDays,
    List<int>? cycleMonths,
    String? categoryId,
    required DateTime startDate,
    String? cancellationUrl,
    String? colorHex,
    int? reminderDaysBefore,
    int? sharedWith,
    String? paymentMethod,
    bool isTrial = false,
    DateTime? trialEndDate,
    double? postTrialAmount,
    String budgetId = 'personal',
  }) async {
    final sub = Subscription(
      id: _uuid.v4(),
      name: name,
      description: description,
      amount: amount,
      currency: currency,
      billingCycle: billingCycle,
      customCycleDays: customCycleDays,
      cycleMonths: cycleMonths,
      categoryId: categoryId,
      startDate: startDate,
      cancellationUrl: cancellationUrl,
      colorHex: colorHex,
      reminderDaysBefore: reminderDaysBefore,
      sharedWith: sharedWith,
      paymentMethod: paymentMethod,
      isTrial: isTrial,
      trialEndDate: trialEndDate,
      postTrialAmount: postTrialAmount,
      budgetId: budgetId,
      dataDodania: DateTime.now(),
    );
    await add(sub);
    return sub;
  }

  Future<void> update(Subscription sub) async {
    await _storage.saveSubscription(sub);
    _notifications.scheduleForSubscription(sub, storage: _storage);
    _log.info('Updated: ${sub.name}');
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _notifications.cancelForSubscription(id);
    await _storage.deleteSubscription(id);
    _log.info('Deleted: $id');
    notifyListeners();
  }

  Future<void> toggleActive(String id) async {
    final sub = _storage.getSubscription(id);
    if (sub == null) return;
    if (sub.isActive) {
      await update(sub.copyWith(
        isActive: false,
        cancelledDate: DateTime.now(),
      ));
    } else {
      await update(sub.copyWith(
        isActive: true,
        clearCancelledDate: true,
      ));
    }
  }

  Future<void> togglePin(String id) async {
    final sub = _storage.getSubscription(id);
    if (sub == null) return;
    await update(sub.copyWith(isPinned: !sub.isPinned));
  }

  // ── Payment methods (bulk ops) ─────────────────────────────────────────────

  /// Zlicza subskrypcje używające metody płatności o danej nazwie.
  int countSubscriptionsUsingPaymentMethod(String name) =>
      _storage.getSubscriptions().where((s) => s.paymentMethod == name).length;

  /// Propaguje nową nazwę metody płatności do wszystkich subskrypcji
  /// używających starej nazwy. Nie wysyła notyfikacji (metoda płatności
  /// nie wpływa na harmonogram).
  Future<int> renamePaymentMethod(String oldName, String newName) async {
    if (oldName == newName) return 0;
    final affected = _storage
        .getSubscriptions()
        .where((s) => s.paymentMethod == oldName)
        .toList();
    for (final sub in affected) {
      await _storage.saveSubscription(sub.copyWith(paymentMethod: newName));
    }
    if (affected.isNotEmpty) {
      _log.info(
          'Renamed payment method "$oldName" → "$newName" on ${affected.length} subscriptions');
      notifyListeners();
    }
    return affected.length;
  }

  /// Czyści pole `paymentMethod` na wszystkich subskrypcjach używających
  /// danej nazwy. Wywoływane przy usunięciu metody płatności.
  Future<int> clearPaymentMethodFromAll(String name) async {
    final affected = _storage
        .getSubscriptions()
        .where((s) => s.paymentMethod == name)
        .toList();
    for (final sub in affected) {
      await _storage.saveSubscription(sub.copyWith(clearPaymentMethod: true));
    }
    if (affected.isNotEmpty) {
      _log.info(
          'Cleared payment method "$name" from ${affected.length} subscriptions');
      notifyListeners();
    }
    return affected.length;
  }
}
