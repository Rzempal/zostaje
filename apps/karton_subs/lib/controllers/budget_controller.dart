import 'dart:math' show max;

import 'package:flutter/foundation.dart' hide Category;
import 'package:uuid/uuid.dart';

import '../models/budget.dart';
import '../models/category.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/app_logger.dart';
import '../services/storage_service.dart';
import 'subscription_controller.dart';

/// Dopisek w nazwie duplikatu (pozycja, pożyczka, subskrypcja w tym samym
/// budżecie) — inaczej na liście stałyby dwie identyczne.
const kCopySuffix = ' (kopia)';

/// Budżety z nazwami (ADR-037): lista, aktywny budżet, ukrywanie, usuwanie,
/// przenoszenie, kopiowanie i duplikowanie zawartości; do tego odhaczenia
/// płatności i kaskady słowników.
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
    await _storage.deleteDictionariesOf(id);
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

  /// Pozycje planu budżetu [id] (z ukrytymi).
  List<PlanPosition> positionsOf(String id) => _storage.getPlanPositions(id);

  List<Subscription> subscriptionsOf(String id) => [
    for (final s in _storage.getSubscriptions())
      if (s.budgetId == id) s,
  ];

  /// Pozycje razem z resztą swojej grupy — pożyczka idzie w całości
  /// (wypłata, raty i zakup), bo połowa pary w innym budżecie nie ma sensu.
  Set<String> _withGroups(Iterable<String> ids) {
    final links = {for (final id in ids) ?_storage.getPlanPosition(id)?.linkId};
    return {
      ...ids,
      if (links.isNotEmpty)
        for (final p in _storage.getPlanPositions())
          if (p.linkId != null && links.contains(p.linkId)) p.id,
    };
  }

  /// Przenosi pozycje (z grupami pożyczek) do budżetu [to] — razem
  /// z odhaczonymi płatnościami. Kategoria i metoda płatności idą po nazwie
  /// (ADR-038): brakujące w [to] dochodzą tam przy [addMissing], inaczej
  /// pozycja przychodzi bez nich. Zwraca liczbę przeniesionych pozycji.
  Future<int> movePositions(
    Iterable<String> ids,
    String to, {
    bool addMissing = true,
  }) async {
    final bySource = <String, Set<String>>{};
    for (final id in _withGroups(ids)) {
      final p = _storage.getPlanPosition(id);
      if (p == null || p.budgetId == to) continue;
      bySource.putIfAbsent(p.budgetId, () => {}).add(id);
      final labels = await _labelsIn(
        to,
        p.budgetId,
        p.categoryId,
        p.paymentMethod,
        addMissing: addMissing,
      );
      await _storage.savePlanPosition(
        p.copyWith(
          budgetId: to,
          categoryId: labels.categoryId,
          clearCategoryId: labels.categoryId == null,
          paymentMethod: labels.method,
          clearPaymentMethod: labels.method == null,
          updatedAt: DateTime.now(),
        ),
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
  /// płatności się nie kopiują; etykiety jak w [movePositions]. Zwraca liczbę
  /// skopiowanych pozycji.
  Future<int> copyPositions(
    Iterable<String> ids,
    String to, {
    bool addMissing = true,
  }) async {
    final copies = await _copyPositions(ids, to: to, addMissing: addMissing);
    _log.info('Copied ${copies.length} plan positions to $to');
    return copies.length;
  }

  /// Duplikaty pozycji (z grupami pożyczek) w ich własnym budżecie, z dopiskiem
  /// [kCopySuffix] w nazwie — na liście widać, która jest kopią. Reszta jak
  /// w [copyPositions]. Zwraca identyfikatory: oryginał → kopia (np. żeby od
  /// razu otworzyć kopię).
  Future<Map<String, String>> duplicatePositions(Iterable<String> ids) async {
    final copies = await _copyPositions(ids, nameSuffix: kCopySuffix);
    _log.info('Duplicated ${copies.length} plan positions');
    return copies;
  }

  /// Duplikat całej pożyczki, do której należy pozycja [partId] (wypłata,
  /// spłata albo raty, zakup). Zwraca powiązanie kopii — żeby otworzyć jej
  /// formularz.
  Future<String?> duplicateLoan(String partId) async {
    final copyId = (await duplicatePositions({partId}))[partId];
    return copyId == null ? null : _storage.getPlanPosition(copyId)?.linkId;
  }

  /// Wspólne kopiowanie pozycji: do budżetu [to] albo (`null`) w budżecie
  /// źródła.
  Future<Map<String, String>> _copyPositions(
    Iterable<String> ids, {
    String? to,
    String nameSuffix = '',
    bool addMissing = true,
  }) async {
    final now = DateTime.now();
    final newLinks = <String, String>{};
    final copies = <String, String>{};
    for (final id in _withGroups(ids)) {
      final p = _storage.getPlanPosition(id);
      if (p == null) continue;
      final link = p.linkId == null
          ? null
          : newLinks.putIfAbsent(p.linkId!, () => _uuid.v4());
      final copyId = _uuid.v4();
      final labels = await _labelsIn(
        to ?? p.budgetId,
        p.budgetId,
        p.categoryId,
        p.paymentMethod,
        addMissing: addMissing,
      );
      final json = p.toJson()
        ..['id'] = copyId
        ..['budgetId'] = to ?? p.budgetId
        ..['name'] = '${p.name}$nameSuffix'
        ..['categoryId'] = labels.categoryId
        ..['paymentMethod'] = labels.method
        ..['linkId'] = link
        ..['createdAt'] = now.toIso8601String()
        ..['updatedAt'] = now.toIso8601String();
      await _storage.savePlanPosition(PlanPosition.fromJson(json));
      copies[id] = copyId;
    }
    notifyListeners();
    return copies;
  }

  /// Subskrypcje do budżetu [to]; etykiety jak w [movePositions].
  Future<void> moveSubscriptions(
    Iterable<Subscription> subs,
    String to, {
    bool addMissing = true,
  }) async {
    for (final s in subs) {
      if (s.budgetId == to) continue;
      await _subscriptions.update(
        await _relabel(s, to, addMissing: addMissing),
      );
    }
  }

  /// Kopie subskrypcji w budżecie [to] — nowe identyfikatory i własne
  /// przypomnienia (kontroler subskrypcji je planuje); etykiety jak
  /// w [movePositions].
  Future<void> copySubscriptions(
    Iterable<Subscription> subs,
    String to, {
    bool addMissing = true,
  }) async {
    for (final s in subs) {
      final copy = await _relabel(s, to, addMissing: addMissing);
      await _subscriptions.add(copy.copyWith(id: _uuid.v4()));
    }
  }

  Future<Subscription> _relabel(
    Subscription s,
    String to, {
    required bool addMissing,
  }) async {
    final labels = await _labelsIn(
      to,
      s.budgetId,
      s.categoryId,
      s.paymentMethod,
      addMissing: addMissing,
    );
    return s.copyWith(
      budgetId: to,
      categoryId: labels.categoryId,
      clearCategoryId: labels.categoryId == null,
      paymentMethod: labels.method,
      clearPaymentMethod: labels.method == null,
    );
  }

  /// Duplikat subskrypcji w jej budżecie, z dopiskiem [kCopySuffix] — własne
  /// przypomnienia jak przy kopii. Zwraca kopię (żeby od razu ją otworzyć).
  Future<Subscription> duplicateSubscription(Subscription s) async {
    final copy = s.copyWith(
      id: _uuid.v4(),
      name: '${s.name}$kCopySuffix',
      dataDodania: DateTime.now(),
    );
    await _subscriptions.add(copy);
    return copy;
  }

  /// Cała zawartość budżetu [from] — pozycje planu i subskrypcje — do [to].
  Future<void> moveAll(String from, String to, {bool addMissing = true}) async {
    await movePositions(
      [for (final p in _storage.getPlanPositions(from)) p.id],
      to,
      addMissing: addMissing,
    );
    await moveSubscriptions(subscriptionsOf(from), to, addMissing: addMissing);
  }

  /// Kopia całej zawartości budżetu [from] w [to]; subskrypcje — gdy
  /// [withSubscriptions] (kopia oznacza też drugie przypomnienia).
  Future<void> copyAll(
    String from,
    String to, {
    bool withSubscriptions = true,
    bool addMissing = true,
  }) async {
    await copyPositions(
      [for (final p in _storage.getPlanPositions(from)) p.id],
      to,
      addMissing: addMissing,
    );
    if (withSubscriptions) {
      await copySubscriptions(
        subscriptionsOf(from),
        to,
        addMissing: addMissing,
      );
    }
  }

  /// Subskrypcje aktywnego budżetu — sekcja planu.
  List<Subscription> get subscriptions => subscriptionsOf(_budgetId);

  // ── Słowniki: osobne dla budżetów (ADR-038) ────────────────────────────────
  // Każdy budżet ma własne kategorie i metody płatności. Pozycje i subskrypcje
  // wskazują kategorię identyfikatorem (należy do jednego budżetu), a metodę
  // nazwą — więc zmiany metody dotyczą tylko pozycji i subskrypcji jej budżetu.

  static String _key(String name) => name.toLowerCase().trim();

  Category? _categoryNamed(String budgetId, String name) => _storage
      .getCategories(budgetId)
      .where((c) => _key(c.name) == _key(name))
      .firstOrNull;

  PaymentMethod? _methodNamed(String budgetId, String name) => _storage
      .getPaymentMethods(budgetId)
      .where((m) => _key(m.name) == _key(name))
      .firstOrNull;

  /// Liczba pozycji planu w kategorii.
  int countCategoryUsage(String categoryId) => _storage
      .getPlanPositions()
      .where((p) => p.categoryId == categoryId)
      .length;

  /// Liczba subskrypcji w kategorii.
  int countCategorySubscriptions(String categoryId) => _storage
      .getSubscriptions()
      .where((s) => s.categoryId == categoryId)
      .length;

  /// Liczba pozycji planu budżetu [budgetId] z metodą płatności [name].
  int countPaymentMethodUsage(String budgetId, String name) => _storage
      .getPlanPositions(budgetId)
      .where((p) => p.paymentMethod == name)
      .length;

  /// Liczba subskrypcji budżetu [budgetId] z metodą płatności [name].
  int countPaymentMethodSubscriptions(String budgetId, String name) =>
      subscriptionsOf(budgetId).where((s) => s.paymentMethod == name).length;

  /// „Inne" z budżetu kategorii [c] (po nazwie) — tam trafiają pozycje
  /// usuwanej kategorii; `null` = budżet jej nie ma (zostaną bez kategorii).
  Category? otherCategoryFor(Category c) => _storage
      .getCategories(c.budgetId ?? _budgetId)
      .where((x) => x.id != c.id && _key(x.name) == 'inne')
      .firstOrNull;

  /// Usuwa kategorię: jej pozycje i subskrypcje przechodzą do „Inne" tego
  /// samego budżetu, a gdy jej nie ma — zostają bez kategorii.
  Future<void> deleteCategory(Category c) async {
    await _recategorize(c.id, otherCategoryFor(c)?.id);
    await _storage.deleteCategory(c.id);
    _log.info('Deleted category ${c.name}');
    _subscriptions.refresh();
    notifyListeners();
  }

  Future<void> _recategorize(String fromId, String? toId) async {
    final now = DateTime.now();
    for (final p in _storage.getPlanPositions()) {
      if (p.categoryId != fromId) continue;
      await _storage.savePlanPosition(
        p.copyWith(
          categoryId: toId,
          clearCategoryId: toId == null,
          updatedAt: now,
        ),
      );
    }
    for (final s in _storage.getSubscriptions()) {
      if (s.categoryId != fromId) continue;
      await _storage.saveSubscription(
        s.copyWith(categoryId: toId, clearCategoryId: toId == null),
      );
    }
  }

  /// Zmiana nazwy metody płatności w pozycjach i subskrypcjach jej budżetu.
  Future<int> renamePaymentMethod(
    String budgetId,
    String oldName,
    String newName,
  ) => _setPaymentMethod(budgetId, oldName, newName);

  /// Usuwa metodę płatności — pozycje i subskrypcje jej budżetu tracą
  /// oznaczenie metody.
  Future<void> deletePaymentMethod(PaymentMethod m) async {
    await _setPaymentMethod(m.budgetId ?? _budgetId, m.name, null);
    await _storage.deletePaymentMethod(m.id);
    _log.info('Deleted payment method ${m.name}');
    _subscriptions.refresh();
    notifyListeners();
  }

  Future<int> _setPaymentMethod(
    String budgetId,
    String from,
    String? to,
  ) async {
    if (from == to) return 0;
    final now = DateTime.now();
    var n = 0;
    for (final p in _storage.getPlanPositions(budgetId)) {
      if (p.paymentMethod != from) continue;
      await _storage.savePlanPosition(
        p.copyWith(
          paymentMethod: to,
          clearPaymentMethod: to == null,
          updatedAt: now,
        ),
      );
      n++;
    }
    for (final s in subscriptionsOf(budgetId)) {
      if (s.paymentMethod != from) continue;
      await _storage.saveSubscription(
        s.copyWith(paymentMethod: to, clearPaymentMethod: to == null),
      );
      n++;
    }
    if (n > 0) {
      _log.info('Payment method "$from" → "$to": $n items in $budgetId');
      _subscriptions.refresh();
      notifyListeners();
    }
    return n;
  }

  /// Niezależna kopia kategorii w budżecie [to] (lista jest alfabetyczna,
  /// więc miejsce wynika z nazwy). Gdy [to] ma już kategorię o tej nazwie, nic
  /// nie dubluje — zwraca `false`.
  Future<bool> copyCategoryTo(Category c, String to) async {
    if (_categoryNamed(to, c.name) != null) return false;
    await _storage.saveCategory(c.copyWith(id: _uuid.v4(), budgetId: to));
    notifyListeners();
    return true;
  }

  /// Przenosi kategorię do budżetu [to]: tam kopia (o ile nie ma tej nazwy),
  /// tu usunięcie — pozycje i subskrypcje tego budżetu zostają bez niej.
  Future<void> moveCategoryTo(Category c, String to) async {
    await copyCategoryTo(c, to);
    await _recategorize(c.id, null);
    await _storage.deleteCategory(c.id);
    _subscriptions.refresh();
    notifyListeners();
  }

  /// Wszystkie kategorie budżetu [from] do [to] (bez nazw, które [to] już
  /// ma). Zwraca liczbę skopiowanych.
  Future<int> copyCategoriesTo(String from, String to) async {
    var n = 0;
    for (final c in _storage.getCategories(from)) {
      if (await copyCategoryTo(c, to)) n++;
    }
    return n;
  }

  /// Niezależna kopia metody płatności w budżecie [to] — jak [copyCategoryTo].
  Future<bool> copyPaymentMethodTo(PaymentMethod m, String to) async {
    if (_methodNamed(to, m.name) != null) return false;
    final order = _storage
        .getPaymentMethods(to)
        .fold(-1, (o, x) => max(o, x.order));
    await _storage.savePaymentMethod(
      m.copyWith(id: _uuid.v4(), budgetId: to, order: order + 1),
    );
    notifyListeners();
    return true;
  }

  /// Przenosi metodę płatności do budżetu [to] — jak [moveCategoryTo].
  Future<void> movePaymentMethodTo(PaymentMethod m, String to) async {
    await copyPaymentMethodTo(m, to);
    await deletePaymentMethod(m);
  }

  /// Wszystkie metody płatności budżetu [from] do [to] — jak
  /// [copyCategoriesTo].
  Future<int> copyPaymentMethodsTo(String from, String to) async {
    var n = 0;
    for (final m in _storage.getPaymentMethods(from)) {
      if (await copyPaymentMethodTo(m, to)) n++;
    }
    return n;
  }

  /// Kategorie i metody płatności pozycji [positionIds] (z grupami pożyczek)
  /// i subskrypcji [subs], których budżet [to] nie ma (po nazwie) — o to
  /// pyta okno przed przeniesieniem albo kopią. Pusto = nic nie zginie.
  ({List<String> categories, List<String> methods}) missingIn(
    String to, {
    Iterable<String> positionIds = const [],
    Iterable<Subscription> subs = const [],
  }) {
    final categories = <String>{};
    final methods = <String>{};
    void check(String from, String? categoryId, String? method) {
      if (from == to) return;
      final c = categoryId == null ? null : _storage.getCategory(categoryId);
      if (c != null && _categoryNamed(to, c.name) == null) {
        categories.add(c.name);
      }
      if (method != null && _methodNamed(to, method) == null) {
        methods.add(method);
      }
    }

    for (final id in _withGroups(positionIds)) {
      final p = _storage.getPlanPosition(id);
      if (p != null) check(p.budgetId, p.categoryId, p.paymentMethod);
    }
    for (final s in subs) {
      check(s.budgetId, s.categoryId, s.paymentMethod);
    }
    return (categories: categories.toList(), methods: methods.toList());
  }

  /// Etykiety pozycji lub subskrypcji z budżetu [from] w budżecie [to]:
  /// kategoria i metoda o tej samej nazwie, a gdy ich tam brak — kopie
  /// ([addMissing]) albo nic.
  Future<({String? categoryId, String? method})> _labelsIn(
    String to,
    String from,
    String? categoryId,
    String? method, {
    required bool addMissing,
  }) async {
    if (from == to) return (categoryId: categoryId, method: method);
    String? category;
    final c = categoryId == null ? null : _storage.getCategory(categoryId);
    if (c != null) {
      category = _categoryNamed(to, c.name)?.id;
      if (category == null && addMissing) {
        await copyCategoryTo(c, to);
        category = _categoryNamed(to, c.name)?.id;
      }
    }
    String? pm;
    if (method != null) {
      pm = _methodNamed(to, method)?.name;
      if (pm == null && addMissing) {
        await copyPaymentMethodTo(
          _storage.paymentMethodNamed(from, method) ??
              PaymentMethod(id: _uuid.v4(), name: method),
          to,
        );
        pm = _methodNamed(to, method)?.name;
      }
    }
    return (categoryId: category, method: pm);
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
