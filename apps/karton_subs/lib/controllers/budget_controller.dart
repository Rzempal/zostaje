import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/budget.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/app_logger.dart';
import '../services/storage_service.dart';
import 'subscription_controller.dart';

/// Budżety z nazwami (ADR-037): lista, aktywny budżet, ukrywanie, usuwanie,
/// przenoszenie i kopiowanie zawartości; do tego odhaczenia płatności
/// i kaskady słowników.
///
/// Po przebudowie na plan roczny (ADR-035) pozycje i obliczenia żyją
/// w [PlanController] — ten kontroler trzyma to, co wspólne dla planu,
/// kalendarza i subskrypcji. Stare pozycje budżetu leżą w bazie jako archiwum
/// (powrót do poprzedniej wersji) i NIE są tu zmieniane.
class BudgetController extends ChangeNotifier {
  static final _log = AppLogger.get('BudgetController');
  static const _uuid = Uuid();
  final StorageService _storage;
  final SubscriptionController _subscriptions;

  BudgetController(this._storage, this._subscriptions) {
    _subscriptions.addListener(notifyListeners);
    _budgets = _storage.getBudgets();
    final saved = _storage.getActiveBudgetId();
    final visible = visibleBudgets;
    _budgetId = visible.any((b) => b.id == saved)
        ? saved!
        : (visible.firstOrNull ?? _budgets.first).id;
  }

  @override
  void dispose() {
    _subscriptions.removeListener(notifyListeners);
    super.dispose();
  }

  /// Odświeża ekrany — i czyta listę budżetów od nowa (po odtworzeniu kopii
  /// zapasowej lista mogła się zmienić). Aktywny budżet, którego już nie ma
  /// albo jest ukryty, oddaje miejsce pierwszemu widocznemu.
  void refresh() {
    _budgets = _storage.getBudgets();
    if (!visibleBudgets.any((b) => b.id == _budgetId)) {
      _budgetId = (visibleBudgets.firstOrNull ?? _budgets.first).id;
    }
    notifyListeners();
  }

  // ── Budżety ────────────────────────────────────────────────────────────────

  late List<Budget> _budgets;
  late String _budgetId;

  /// Wszystkie budżety, w kolejności z przełącznika (z ukrytymi).
  List<Budget> get budgets => List.unmodifiable(_budgets);

  /// Budżety widoczne w przełączniku.
  List<Budget> get visibleBudgets => [
    for (final b in _budgets)
      if (!b.hidden) b,
  ];

  /// Identyfikator aktywnego budżetu (`budgetId` pozycji i subskrypcji).
  String get budgetId => _budgetId;

  Budget get activeBudget =>
      _budgets.where((b) => b.id == _budgetId).firstOrNull ?? _budgets.first;

  Budget? budgetById(String id) =>
      _budgets.where((b) => b.id == id).firstOrNull;

  /// Czy jest między czym przełączać (więcej niż jeden widoczny budżet).
  bool get canSwitch => visibleBudgets.length > 1;

  void setBudget(String id) {
    if (_budgetId == id || budgetById(id) == null) return;
    _budgetId = id;
    _storage.setActiveBudgetId(id);
    notifyListeners();
  }

  /// Kolejny ([delta] = 1) albo poprzedni (-1) widoczny budżet — gest
  /// przesunięcia palcem. Na końcu listy nic się nie dzieje.
  void stepBudget(int delta) {
    final visible = visibleBudgets;
    final i = visible.indexWhere((b) => b.id == _budgetId);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= visible.length) return;
    setBudget(visible[j].id);
  }

  Future<void> _persistBudgets() async {
    await _storage.setBudgets(_budgets);
    notifyListeners();
  }

  Future<Budget> addBudget(String name, String icon) async {
    final b = Budget(id: _uuid.v4(), name: name, icon: icon);
    _budgets = [..._budgets, b];
    await _persistBudgets();
    _log.info('Added budget: $name');
    return b;
  }

  Future<void> updateBudget(Budget budget) async {
    _budgets = [for (final b in _budgets) b.id == budget.id ? budget : b];
    await _persistBudgets();
  }

  /// Nowa kolejność — przełącznik i gest idą za nią.
  Future<void> reorderBudgets(List<String> ids) async {
    final byId = {for (final b in _budgets) b.id: b};
    _budgets = [
      for (final id in ids) ?byId[id],
      for (final b in _budgets)
        if (!ids.contains(b.id)) b,
    ];
    await _persistBudgets();
  }

  /// Ukrywa albo pokazuje budżet. Ostatniego widocznego ukryć się nie da
  /// (zwraca `false`) — przełącznik musiałby pokazać pustkę. Ukryty aktywny
  /// budżet oddaje miejsce pierwszemu widocznemu.
  Future<bool> setBudgetHidden(String id, bool hidden) async {
    final b = budgetById(id);
    if (b == null || b.hidden == hidden) return true;
    if (hidden && visibleBudgets.length <= 1) return false;
    _budgets = [
      for (final x in _budgets) x.id == id ? x.copyWith(hidden: hidden) : x,
    ];
    if (hidden && _budgetId == id) {
      _budgetId = visibleBudgets.first.id;
      await _storage.setActiveBudgetId(_budgetId);
    }
    await _persistBudgets();
    return true;
  }

  /// Usuwa budżet RAZEM z jego pozycjami planu, subskrypcjami i odhaczonymi
  /// płatnościami (formularz najpierw ostrzega i podpowiada przeniesienie).
  /// Ostatniego budżetu usunąć się nie da (zwraca `false`).
  Future<bool> deleteBudget(String id) async {
    if (_budgets.length <= 1 || budgetById(id) == null) return false;
    for (final p in _storage.getPlanPositions(id)) {
      await _storage.deletePlanPosition(p.id);
    }
    for (final sub in subscriptionsOf(id)) {
      await _subscriptions.delete(sub.id);
    }
    await _storage.deletePaymentDoneOf(id);
    _budgets = [
      for (final b in _budgets)
        if (b.id != id) b,
    ];
    // Ostatni widoczny usunięty — pokaż pierwszy z pozostałych.
    if (visibleBudgets.isEmpty) {
      _budgets = [_budgets.first.copyWith(hidden: false), ..._budgets.skip(1)];
    }
    if (_budgetId == id) {
      _budgetId = visibleBudgets.first.id;
      await _storage.setActiveBudgetId(_budgetId);
    }
    await _persistBudgets();
    _log.info('Deleted budget $id');
    return true;
  }

  // ── Zawartość budżetów: liczniki, przenoszenie, kopiowanie ────────────────

  int positionCountOf(String id) => _storage.getPlanPositions(id).length;

  List<Subscription> subscriptionsOf(String id) => [
    for (final s in _storage.getSubscriptions())
      if (s.budgetId == id) s,
  ];

  /// Pozycje razem z resztą swojej grupy — pożyczka idzie w całości
  /// (wypłata, raty i zakup), bo połowa pary w innym budżecie nie ma sensu.
  Set<String> _withGroups(Iterable<String> ids) {
    final links = {
      for (final id in ids) ?_storage.getPlanPosition(id)?.linkId,
    };
    return {
      ...ids,
      if (links.isNotEmpty)
        for (final p in _storage.getPlanPositions())
          if (p.linkId != null && links.contains(p.linkId)) p.id,
    };
  }

  /// Przenosi pozycje (z grupami pożyczek) do budżetu [to] — razem
  /// z odhaczonymi płatnościami. Zwraca liczbę przeniesionych pozycji.
  Future<int> movePositions(Iterable<String> ids, String to) async {
    final bySource = <String, Set<String>>{};
    for (final id in _withGroups(ids)) {
      final p = _storage.getPlanPosition(id);
      if (p == null || p.budgetId == to) continue;
      bySource.putIfAbsent(p.budgetId, () => {}).add(id);
      await _storage.savePlanPosition(
        p.copyWith(budgetId: to, updatedAt: DateTime.now()),
      );
    }
    for (final MapEntry(key: from, value: moved) in bySource.entries) {
      await _storage.movePaymentDone(from, to, moved);
    }
    final count = bySource.values.fold(0, (n, s) => n + s.length);
    _log.info('Moved $count plan positions to $to');
    notifyListeners();
    return count;
  }

  /// Kopiuje pozycje (z grupami pożyczek) do budżetu [to]. Kopie dostają
  /// nowe identyfikatory — pożyczka nowe wspólne powiązanie — a odhaczenia
  /// płatności się nie kopiują. Zwraca liczbę skopiowanych pozycji.
  Future<int> copyPositions(Iterable<String> ids, String to) async {
    final now = DateTime.now();
    final newLinks = <String, String>{};
    var count = 0;
    for (final id in _withGroups(ids)) {
      final p = _storage.getPlanPosition(id);
      if (p == null) continue;
      final link = p.linkId == null
          ? null
          : newLinks.putIfAbsent(p.linkId!, () => _uuid.v4());
      final json = p.toJson()
        ..['id'] = _uuid.v4()
        ..['budgetId'] = to
        ..['linkId'] = link
        ..['createdAt'] = now.toIso8601String()
        ..['updatedAt'] = now.toIso8601String();
      await _storage.savePlanPosition(PlanPosition.fromJson(json));
      count++;
    }
    _log.info('Copied $count plan positions to $to');
    notifyListeners();
    return count;
  }

  Future<void> moveSubscriptions(Iterable<Subscription> subs, String to) async {
    for (final s in subs) {
      if (s.budgetId != to) await _subscriptions.update(s.copyWith(budgetId: to));
    }
  }

  /// Kopie subskrypcji w budżecie [to] — nowe identyfikatory i własne
  /// przypomnienia (kontroler subskrypcji je planuje).
  Future<void> copySubscriptions(Iterable<Subscription> subs, String to) async {
    for (final s in subs) {
      await _subscriptions.add(s.copyWith(id: _uuid.v4(), budgetId: to));
    }
  }

  /// Cała zawartość budżetu [from] — pozycje planu i subskrypcje — do [to].
  Future<void> moveAll(String from, String to) async {
    await movePositions([for (final p in _storage.getPlanPositions(from)) p.id], to);
    await moveSubscriptions(subscriptionsOf(from), to);
  }

  /// Kopia całej zawartości budżetu [from] w [to]; subskrypcje — gdy
  /// [withSubscriptions] (kopia oznacza też drugie przypomnienia).
  Future<void> copyAll(
    String from,
    String to, {
    bool withSubscriptions = true,
  }) async {
    await copyPositions([for (final p in _storage.getPlanPositions(from)) p.id], to);
    if (withSubscriptions) {
      await copySubscriptions(subscriptionsOf(from), to);
    }
  }

  /// Subskrypcje aktywnego budżetu — sekcja planu.
  List<Subscription> get subscriptions => subscriptionsOf(_budgetId);

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
    return '$_budgetId|$sourceId|$d';
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
