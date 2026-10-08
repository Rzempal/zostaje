import 'package:flutter/foundation.dart';

import '../models/budget_entry.dart' show BudgetScope, BudgetMode;
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/app_logger.dart';
import '../services/storage_service.dart';
import 'subscription_controller.dart';

/// Aktywny budżet (osobisty / domowy), tryb budżetu, odhaczenia płatności
/// i kaskady słowników.
///
/// Po przebudowie na plan roczny (ADR-035) pozycje i obliczenia żyją
/// w [PlanController] — ten kontroler trzyma tylko to, co wspólne dla planu,
/// kalendarza i subskrypcji. Stare pozycje budżetu leżą w bazie jako archiwum
/// (powrót do poprzedniej wersji) i NIE są tu zmieniane.
class BudgetController extends ChangeNotifier {
  static final _log = AppLogger.get('BudgetController');
  final StorageService _storage;
  final SubscriptionController _subscriptions;

  BudgetController(this._storage, this._subscriptions) {
    _subscriptions.addListener(notifyListeners);
    // Tryb budżetu (preferencja UI) wymusza zakres startowy w trybie jednym.
    _mode = _storage.getBudgetMode();
    _scope = _scopeForMode(_mode) ?? _scope;
  }

  @override
  void dispose() {
    _subscriptions.removeListener(notifyListeners);
    super.dispose();
  }

  void refresh() => notifyListeners();

  // ── Zakres aktywny ─────────────────────────────────────────────────────────

  BudgetScope _scope = BudgetScope.personal;
  BudgetScope get scope => _scope;
  bool get isHousehold => _scope == BudgetScope.household;
  void setScope(BudgetScope s) {
    // W trybie jednozakresowym zakres jest zablokowany (przełącznik ukryty).
    if (!scopeSelectable || _scope == s) return;
    _scope = s;
    notifyListeners();
  }

  // ── Tryb budżetu (Osobisty / Domowy / oba) ─────────────────────────────────

  BudgetMode _mode = BudgetMode.both;
  BudgetMode get budgetMode => _mode;

  /// Czy użytkownik może przełączać zakres (tryb „oba"). W trybie jednym
  /// przełącznik zakresu jest ukryty, a swipe zwalnia się na zakładki 2. rzędu.
  bool get scopeSelectable => _mode == BudgetMode.both;

  /// Wymuszony zakres dla trybu (null dla „oba" — zakres wybiera użytkownik).
  BudgetScope? _scopeForMode(BudgetMode m) => switch (m) {
    BudgetMode.personalOnly => BudgetScope.personal,
    BudgetMode.householdOnly => BudgetScope.household,
    BudgetMode.both => null,
  };

  Future<void> setBudgetMode(BudgetMode m) async {
    if (_mode == m) return;
    _mode = m;
    await _storage.setBudgetMode(m);
    // W trybie jednym wymuś odpowiedni zakres (pomijając blokadę setScope).
    final forced = _scopeForMode(m);
    if (forced != null) _scope = forced;
    notifyListeners();
  }

  /// Subskrypcje aktywnego budżetu (osobiste/domowe) — sekcja planu.
  List<Subscription> get subscriptions {
    final scope =
        isHousehold ? SubscriptionScope.household : SubscriptionScope.personal;
    return _storage.getSubscriptions().where((s) => s.scope == scope).toList();
  }

  // ── Słowniki: użycie i kaskady (Kategorie / Metody płatności) ───────────────
  // Słowniki są wspólne dla wszystkich budżetów, więc operacje działają na
  // pozycjach planu WSZYSTKICH budżetów, niezależnie od aktywnego. Subskrypcje
  // obsługują ekrany słowników osobno (SubscriptionController).

  /// Liczba pozycji planu (wszystkie budżety) w danej kategorii.
  int countCategoryUsage(String categoryId) => _storage
      .getPlanPositions()
      .where((p) => p.categoryId == categoryId)
      .length;

  /// Liczba pozycji planu (wszystkie budżety) z daną metodą płatności.
  int countPaymentMethodUsage(String name) => _storage
      .getPlanPositions()
      .where((p) => p.paymentMethod == name)
      .length;

  /// Przenosi pozycje planu z kategorii [fromId] do [toId] (usunięcie
  /// kategorii). Zwraca liczbę zmienionych pozycji.
  Future<int> reassignCategoryEverywhere(String fromId, String toId) =>
      _updatePlanPositions(
        (p) => p.categoryId == fromId,
        (p) => p.copyWith(categoryId: toId),
      );

  /// Zmienia nazwę metody płatności w pozycjach planu.
  Future<int> renamePaymentMethodEverywhere(String oldName, String newName) {
    if (oldName == newName) return Future.value(0);
    return _updatePlanPositions(
      (p) => p.paymentMethod == oldName,
      (p) => p.copyWith(paymentMethod: newName),
    );
  }

  /// Czyści metodę płatności (po nazwie) w pozycjach planu.
  Future<int> clearPaymentMethodEverywhere(String name) => _updatePlanPositions(
    (p) => p.paymentMethod == name,
    (p) => p.copyWith(clearPaymentMethod: true),
  );

  Future<int> _updatePlanPositions(
    bool Function(PlanPosition) where,
    PlanPosition Function(PlanPosition) change,
  ) async {
    final hits = _storage.getPlanPositions().where(where).toList();
    for (final p in hits) {
      await _storage.savePlanPosition(
        change(p).copyWith(updatedAt: DateTime.now()),
      );
    }
    if (hits.isNotEmpty) {
      _log.info('Dictionary cascade: ${hits.length} plan positions');
      notifyListeners();
    }
    return hits.length;
  }

  // ── Płatności „wykonane" (lokalne, per zakres + źródło + data) ──────────────
  // Klucz `zakres|id|RRRR-MM-DD` — ten sam co przed ADR-035 (identyfikator
  // pozycji planu = identyfikator starej pozycji), więc odhaczenia przetrwały.

  String _paymentKey(String sourceId, DateTime date) {
    final d =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return '${_scope.name}|$sourceId|$d';
  }

  bool isPaymentDone(String sourceId, DateTime date) =>
      _storage.isPaymentDone(_paymentKey(sourceId, date));

  Future<void> togglePaymentDone(String sourceId, DateTime date) async {
    final key = _paymentKey(sourceId, date);
    await _storage.setPaymentDone(key, !_storage.isPaymentDone(key));
    notifyListeners();
  }

  /// Ustawia stan „wykonane" dla wielu płatności naraz (przycisk „odhacz
  /// wszystkie" w grupie płatności miesiąca). Jedno powiadomienie na koniec.
  Future<void> setPaymentsDone(
    Iterable<({String sourceId, DateTime date})> items,
    bool done,
  ) async {
    for (final it in items) {
      await _storage.setPaymentDone(_paymentKey(it.sourceId, it.date), done);
    }
    notifyListeners();
  }
}
