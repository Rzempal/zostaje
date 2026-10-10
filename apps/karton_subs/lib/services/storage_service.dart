import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import '../models/spending_allocation_item.dart';
import '../utils/money_format.dart';
import 'app_logger.dart';
import 'storage_keys.dart';

/// Hive-based storage — wzorzec z APPteczka, zaadaptowany na modele karton-subs.
/// Boxy: 'subscriptions', 'categories', 'payment_methods', 'budget_entries', 'settings'.
/// Dane przechowywane jako JSON string (brak type adapters = brak code gen).
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static final _log = AppLogger.get('StorageService');

  late Box<String> _subscriptionsBox;
  late Box<String> _categoriesBox;
  late Box<String> _paymentMethodsBox;
  late Box<String> _budgetEntriesBox;
  late Box<String> _householdBudgetEntriesBox;
  late Box<String> _planPositionsBox;
  late Box<bool> _paymentDoneBox;
  late Box<dynamic> _settingsBox;

  // In-memory cache
  final Map<String, Subscription> _subscriptionsCache = {};
  final Map<String, Category> _categoriesCache = {};
  final Map<String, PaymentMethod> _paymentMethodsCache = {};
  final Map<String, BudgetEntry> _budgetEntriesCache = {};
  final Map<String, BudgetEntry> _householdBudgetEntriesCache = {};
  final Map<String, PlanPosition> _planPositionsCache = {};
  bool _initialized = false;

  /// Otwiera pudełka na już zainicjalizowanym Hive — do testów, które robią
  /// `Hive.init(katalogTymczasowy)`. Produkcyjne [init] różni się wyłącznie
  /// `initFlutter()`, którego w teście nie ma jak wywołać (potrzebuje wtyczki
  /// od ścieżek).
  @visibleForTesting
  Future<void> initForTests() => _openBoxes();

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    await _openBoxes();
  }

  Future<void> _openBoxes() async {
    if (_initialized) return;
    _subscriptionsBox = await Hive.openBox<String>('subscriptions');
    _categoriesBox = await Hive.openBox<String>('categories');
    _paymentMethodsBox = await Hive.openBox<String>('payment_methods');
    _budgetEntriesBox = await Hive.openBox<String>('budget_entries');
    _householdBudgetEntriesBox = await Hive.openBox<String>(
      'household_budget_entries',
    );
    _planPositionsBox = await Hive.openBox<String>('plan_positions');
    _paymentDoneBox = await Hive.openBox<bool>('payment_done');
    _settingsBox = await Hive.openBox('settings');
    setAppDefaultCurrency(
      getCurrency(),
    ); // globalna waluta domyślna (ukrywanie w UI)
    _loadSubscriptionsCache();
    _loadCategoriesCache();
    _loadPaymentMethodsCache();
    _loadBudgetEntriesCache();
    _loadPlanPositionsCache();
    await ensureDictionaries();
    _initialized = true;
    _log.info(
      'StorageService initialized (${_subscriptionsCache.length} subs, ${_categoriesCache.length} cats, ${_paymentMethodsCache.length} payment methods, ${_budgetEntriesCache.length}+${_householdBudgetEntriesCache.length} budget entries)',
    );
  }

  // ── Subscriptions ──────────────────────────────────────────────────────────

  void _loadSubscriptionsCache() {
    _subscriptionsCache.clear();
    for (final key in _subscriptionsBox.keys) {
      try {
        final json = jsonDecode(_subscriptionsBox.get(key as String)!);
        _subscriptionsCache[key] = Subscription.fromJson(
          json as Map<String, dynamic>,
        );
      } catch (e) {
        _log.warning('Failed to parse subscription $key: $e');
      }
    }
  }

  List<Subscription> getSubscriptions() =>
      List.unmodifiable(_subscriptionsCache.values);

  List<Subscription> getActiveSubscriptions() =>
      _subscriptionsCache.values.where((s) => s.isActive).toList();

  Subscription? getSubscription(String id) => _subscriptionsCache[id];

  Future<void> saveSubscription(Subscription sub) async {
    await _subscriptionsBox.put(sub.id, jsonEncode(sub.toJson()));
    _subscriptionsCache[sub.id] = sub;
    _log.info('Saved subscription: ${sub.name}');
  }

  Future<void> deleteSubscription(String id) async {
    await _subscriptionsBox.delete(id);
    _subscriptionsCache.remove(id);
    _log.info('Deleted subscription: $id');
  }

  // ── Categories ─────────────────────────────────────────────────────────────

  void _loadCategoriesCache() {
    _categoriesCache.clear();
    for (final key in _categoriesBox.keys) {
      try {
        final json = jsonDecode(_categoriesBox.get(key as String)!);
        _categoriesCache[key] = Category.fromJson(json as Map<String, dynamic>);
      } catch (e) {
        _log.warning('Failed to parse category $key: $e');
      }
    }
  }

  /// Wszystkie kategorie, każdego budżetu — do kopii zapasowej, eksportu
  /// i podziału. Ekrany biorą listę swojego budżetu z [getCategories].
  List<Category> getAllCategories() {
    final cats = _categoriesCache.values.toList();
    cats.sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(cats);
  }

  /// Kategorie budżetu [budgetId] (ADR-038), w kolejności z listy.
  List<Category> getCategories(String budgetId) => [
    for (final c in getAllCategories())
      if (c.budgetId == budgetId) c,
  ];

  Category? getCategory(String id) => _categoriesCache[id];

  /// Zapisuje kategorię. [stamp] ustawia znacznik zmiany (`updatedAt`) — tak
  /// zapisuje UI. Scalanie synchronizacji woła ze `stamp: false`, żeby zachować
  /// znacznik ze źródła: przestemplowanie sprawiłoby, że wpis odebrany z drugiego
  /// telefonu od razu wygrywałby jako „najnowszy" i scalanie by się zapętliło.
  Future<void> saveCategory(Category cat, {bool stamp = true}) async {
    final toSave = stamp ? cat.copyWith(updatedAt: DateTime.now()) : cat;
    await _categoriesBox.put(toSave.id, jsonEncode(toSave.toJson()));
    _categoriesCache[toSave.id] = toSave;
  }

  Future<void> deleteCategory(String id) async {
    await _categoriesBox.delete(id);
    _categoriesCache.remove(id);
    _log.info('Deleted category: $id');
  }

  // ── Payment Methods ────────────────────────────────────────────────────────

  void _loadPaymentMethodsCache() {
    _paymentMethodsCache.clear();
    _invalidatePaymentMethods();
    for (final key in _paymentMethodsBox.keys) {
      try {
        final json = jsonDecode(_paymentMethodsBox.get(key as String)!);
        _paymentMethodsCache[key] = PaymentMethod.fromJson(
          json as Map<String, dynamic>,
        );
      } catch (e) {
        _log.warning('Failed to parse payment method $key: $e');
      }
    }
  }

  /// Posortowana lista metod płatności, budowana raz i unieważniana przy każdym
  /// zapisie. Woła ją KAŻDY wiersz listy (żeby sprawdzić, czy płatność jest
  /// automatyczna), a wcześniej każde takie wywołanie tworzyło nową listę
  /// i sortowało ją od nowa — przy kilkuset wierszach to kilkaset sortowań
  /// na jedno przemalowanie ekranu. To samo dla list poszczególnych budżetów.
  List<PaymentMethod>? _paymentMethodsSorted;
  final Map<String, List<PaymentMethod>> _paymentMethodsByBudget = {};

  void _invalidatePaymentMethods() {
    _paymentMethodsSorted = null;
    _paymentMethodsByBudget.clear();
  }

  /// Wszystkie metody płatności, każdego budżetu — do kopii zapasowej
  /// i podziału. Ekrany biorą listę swojego budżetu z [getPaymentMethods].
  List<PaymentMethod> getAllPaymentMethods() {
    final cached = _paymentMethodsSorted;
    if (cached != null) return cached;
    final items = _paymentMethodsCache.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return _paymentMethodsSorted = List.unmodifiable(items);
  }

  /// Metody płatności budżetu [budgetId] (ADR-038), w kolejności z listy.
  List<PaymentMethod> getPaymentMethods(String budgetId) =>
      _paymentMethodsByBudget[budgetId] ??= List.unmodifiable([
        for (final m in getAllPaymentMethods())
          if (m.budgetId == budgetId) m,
      ]);

  /// Metoda o nazwie [name] w budżecie [budgetId] — pozycje i subskrypcje
  /// wskazują metodę po nazwie.
  PaymentMethod? paymentMethodNamed(String budgetId, String name) =>
      getPaymentMethods(budgetId).where((m) => m.name == name).firstOrNull;

  PaymentMethod? getPaymentMethod(String id) => _paymentMethodsCache[id];

  /// Zapisuje metodę płatności. [stamp] jak w [saveCategory].
  Future<void> savePaymentMethod(PaymentMethod pm, {bool stamp = true}) async {
    final toSave = stamp ? pm.copyWith(updatedAt: DateTime.now()) : pm;
    await _paymentMethodsBox.put(toSave.id, jsonEncode(toSave.toJson()));
    _paymentMethodsCache[toSave.id] = toSave;
    _invalidatePaymentMethods();
  }

  Future<void> deletePaymentMethod(String id) async {
    await _paymentMethodsBox.delete(id);
    _paymentMethodsCache.remove(id);
    _invalidatePaymentMethods();
    _log.info('Deleted payment method: $id');
  }

  // ── Słowniki osobne dla budżetów (ADR-038) ─────────────────────────────────

  static const _uuid = Uuid();

  /// Słowniki gotowe do pracy: przy pustej bazie domyślne kategorie i metody
  /// płatności, a wpisy bez budżetu (sprzed podziału, ze starej kopii
  /// zapasowej) przypisane do budżetów. Bez takich wpisów nic nie robi, więc
  /// można to wołać przy każdym starcie i po każdym wczytaniu kopii.
  Future<void> ensureDictionaries() async {
    if (_categoriesCache.isEmpty) {
      for (final c in defaultCategories) {
        await saveCategory(c, stamp: false);
      }
    }
    if (_paymentMethodsCache.isEmpty) {
      for (final m in defaultPaymentMethods) {
        await savePaymentMethod(m, stamp: false);
      }
    }
    await _splitDictionariesByBudget();
  }

  /// Każdy wpis słownika w budżecie, a każda pozycja i subskrypcja z etykietami
  /// swojego budżetu (ADR-038).
  Future<void> _splitDictionariesByBudget() async {
    final legacyCats = [
      for (final c in getAllCategories())
        if (c.budgetId == null) c,
    ];
    final legacyMethods = [
      for (final m in getAllPaymentMethods())
        if (m.budgetId == null) m,
    ];
    if (legacyCats.isNotEmpty || legacyMethods.isNotEmpty) {
      await _assignLegacyDictionaries(legacyCats, legacyMethods);
    }
    await _repairCrossBudgetLabels();
  }

  /// Wpis bez budżetu trafia do każdego budżetu, który go używa: pierwszy
  /// (osobisty, potem w kolejności listy) zachowuje identyfikator, pozostałe
  /// dostają kopie. Nieużywany nigdzie — do budżetu osobistego. Gdy budżet ma
  /// już wpis o tej nazwie, drugi nie powstaje: odwołania przechodzą na
  /// istniejący. Kategorie pozycje wskazują identyfikatorem (stąd
  /// przepinanie), metody płatności — nazwą (wystarczy wpis w budżecie).
  Future<void> _assignLegacyDictionaries(
    List<Category> legacyCats,
    List<PaymentMethod> legacyMethods,
  ) async {
    final budgetIds = [for (final b in getBudgets()) b.id];
    final home = budgetIds.contains(kBudgetPersonal)
        ? kBudgetPersonal
        : budgetIds.first;
    List<String> owners(Set<String>? used) {
      final list = [
        if (used != null && used.contains(home)) home,
        for (final id in budgetIds)
          if (id != home && used != null && used.contains(id)) id,
      ];
      return list.isEmpty ? [home] : list;
    }

    String key(String name) => name.toLowerCase().trim();

    final catUse = <String, Set<String>>{};
    final methodUse = <String, Set<String>>{};
    void use(String budgetId, String? categoryId, String? method) {
      if (categoryId != null) (catUse[categoryId] ??= {}).add(budgetId);
      if (method != null) (methodUse[method] ??= {}).add(budgetId);
    }

    for (final p in _planPositionsCache.values) {
      use(p.budgetId, p.categoryId, p.paymentMethod);
    }
    for (final sub in _subscriptionsCache.values) {
      use(sub.budgetId, sub.categoryId, sub.paymentMethod);
    }

    // Kategorie: budżet → nazwa → identyfikator; budżet → stare id → nowe.
    final catIds = <String, Map<String, String>>{};
    for (final c in _categoriesCache.values) {
      final b = c.budgetId;
      if (b != null) (catIds[b] ??= {})[key(c.name)] = c.id;
    }
    final remap = <String, Map<String, String>>{};
    for (final c in legacyCats) {
      var placed = false;
      for (final b in owners(catUse[c.id])) {
        final ids = catIds[b] ??= {};
        final existing = ids[key(c.name)];
        if (existing != null) {
          (remap[b] ??= {})[c.id] = existing;
        } else if (!placed) {
          await saveCategory(c.copyWith(budgetId: b), stamp: false);
          ids[key(c.name)] = c.id;
          placed = true;
        } else {
          final copy = c.copyWith(id: _uuid.v4(), budgetId: b);
          await saveCategory(copy, stamp: false);
          ids[key(c.name)] = copy.id;
          (remap[b] ??= {})[c.id] = copy.id;
        }
      }
      if (!placed) await deleteCategory(c.id);
    }
    for (final p in _planPositionsCache.values.toList()) {
      final to = remap[p.budgetId]?[p.categoryId];
      if (to != null) await savePlanPosition(p.copyWith(categoryId: to));
    }
    for (final sub in _subscriptionsCache.values.toList()) {
      final to = remap[sub.budgetId]?[sub.categoryId];
      if (to != null) await saveSubscription(sub.copyWith(categoryId: to));
    }

    final methodNames = <String, Set<String>>{};
    for (final m in _paymentMethodsCache.values) {
      final b = m.budgetId;
      if (b != null) (methodNames[b] ??= {}).add(key(m.name));
    }
    for (final m in legacyMethods) {
      var placed = false;
      for (final b in owners(methodUse[m.name])) {
        final names = methodNames[b] ??= {};
        if (!names.add(key(m.name))) continue;
        await savePaymentMethod(
          placed
              ? m.copyWith(id: _uuid.v4(), budgetId: b)
              : m.copyWith(budgetId: b),
          stamp: false,
        );
        placed = true;
      }
      if (!placed) await deletePaymentMethod(m.id);
    }
    _log.info(
      'Split dictionaries by budget: ${legacyCats.length} categories, '
      '${legacyMethods.length} payment methods',
    );
  }

  /// Pozycja albo subskrypcja z kategorią innego budżetu (np. ze starej kopii
  /// zapasowej czy przeliczenia dawnych pozycji) dostaje kategorię swojego
  /// budżetu o tej nazwie, a gdy jej brak — kopię. Tak samo metoda płatności,
  /// której jej budżet nie ma, a ma ją inny. Przy spójnych danych nic nie robi.
  Future<void> _repairCrossBudgetLabels() async {
    final budgetIds = {for (final b in getBudgets()) b.id};
    String key(String name) => name.toLowerCase().trim();
    final catIds = <String, Map<String, String>>{};
    for (final c in _categoriesCache.values) {
      final b = c.budgetId;
      if (b != null) (catIds[b] ??= {})[key(c.name)] = c.id;
    }
    final methodNames = <String, Set<String>>{};
    for (final m in _paymentMethodsCache.values) {
      final b = m.budgetId;
      if (b != null) (methodNames[b] ??= {}).add(key(m.name));
    }

    var fixed = 0;
    Future<String?> categoryIn(String budgetId, String? categoryId) async {
      final c = categoryId == null ? null : _categoriesCache[categoryId];
      if (c == null || c.budgetId == null || c.budgetId == budgetId) {
        return null;
      }
      final ids = catIds[budgetId] ??= {};
      final existing = ids[key(c.name)];
      if (existing != null) return existing;
      final copy = c.copyWith(id: _uuid.v4(), budgetId: budgetId);
      await saveCategory(copy, stamp: false);
      ids[key(c.name)] = copy.id;
      return copy.id;
    }

    Future<void> methodIn(String budgetId, String? name) async {
      if (name == null) return;
      final names = methodNames[budgetId] ??= {};
      if (names.contains(key(name))) return;
      final source = getAllPaymentMethods()
          .where((m) => m.budgetId != null && m.name == name)
          .firstOrNull;
      if (source == null) return;
      await savePaymentMethod(
        source.copyWith(id: _uuid.v4(), budgetId: budgetId),
        stamp: false,
      );
      names.add(key(name));
    }

    for (final p in _planPositionsCache.values.toList()) {
      if (!budgetIds.contains(p.budgetId)) continue;
      final to = await categoryIn(p.budgetId, p.categoryId);
      if (to != null) {
        await savePlanPosition(p.copyWith(categoryId: to));
        fixed++;
      }
      await methodIn(p.budgetId, p.paymentMethod);
    }
    for (final sub in _subscriptionsCache.values.toList()) {
      if (!budgetIds.contains(sub.budgetId)) continue;
      final to = await categoryIn(sub.budgetId, sub.categoryId);
      if (to != null) {
        await saveSubscription(sub.copyWith(categoryId: to));
        fixed++;
      }
      await methodIn(sub.budgetId, sub.paymentMethod);
    }
    if (fixed > 0) {
      _log.info('Re-pointed $fixed items to own-budget categories');
    }
  }

  /// Usuwa kategorie i metody płatności budżetu (przy jego usunięciu).
  Future<void> deleteDictionariesOf(String budgetId) async {
    for (final c in getCategories(budgetId)) {
      await deleteCategory(c.id);
    }
    for (final m in getPaymentMethods(budgetId)) {
      await deletePaymentMethod(m.id);
    }
  }

  // ── Budget entries (per zakres) ──────────────────────────────────────────────
  // Osobisty i domowy to OSOBNE boxy — domowy jest przyszla jednostka synchronizacji.

  Box<String> _budgetBox(BudgetScope scope) => scope == BudgetScope.household
      ? _householdBudgetEntriesBox
      : _budgetEntriesBox;

  Map<String, BudgetEntry> _budgetCache(BudgetScope scope) =>
      scope == BudgetScope.household
      ? _householdBudgetEntriesCache
      : _budgetEntriesCache;

  void _loadBudgetEntriesCache() {
    for (final scope in BudgetScope.values) {
      final box = _budgetBox(scope);
      final cache = _budgetCache(scope)..clear();
      for (final key in box.keys) {
        try {
          final json = jsonDecode(box.get(key as String)!);
          cache[key] = BudgetEntry.fromJson(json as Map<String, dynamic>);
        } catch (e) {
          _log.warning('Failed to parse budget entry $key ($scope): $e');
        }
      }
    }
  }

  List<BudgetEntry> getBudgetEntries([
    BudgetScope scope = BudgetScope.personal,
  ]) => List.unmodifiable(_budgetCache(scope).values);

  BudgetEntry? getBudgetEntry(
    String id, [
    BudgetScope scope = BudgetScope.personal,
  ]) => _budgetCache(scope)[id];

  Future<void> saveBudgetEntry(
    BudgetEntry entry, [
    BudgetScope scope = BudgetScope.personal,
  ]) async {
    await _budgetBox(scope).put(entry.id, jsonEncode(entry.toJson()));
    _budgetCache(scope)[entry.id] = entry;
    _log.info('Saved budget entry ($scope): ${entry.name}');
  }

  // ── Plan roczny (ADR-035) ───────────────────────────────────────────────────
  // Osobny box — stare pozycje budżetu zostają nietknięte, więc wcześniejsza
  // wersja aplikacji (zbudowana z wyższym numerem) widzi swoje dane bez zmian.

  void _loadPlanPositionsCache() {
    _planPositionsCache.clear();
    for (final key in _planPositionsBox.keys) {
      try {
        final json = jsonDecode(_planPositionsBox.get(key as String)!);
        _planPositionsCache[key] = PlanPosition.fromJson(
          json as Map<String, dynamic>,
        );
      } catch (e) {
        _log.warning('Failed to parse plan position $key: $e');
      }
    }
  }

  /// Pozycje planu — wszystkie albo jednego budżetu.
  List<PlanPosition> getPlanPositions([String? budgetId]) => List.unmodifiable(
    budgetId == null
        ? _planPositionsCache.values
        : _planPositionsCache.values.where((p) => p.budgetId == budgetId),
  );

  PlanPosition? getPlanPosition(String id) => _planPositionsCache[id];

  Future<void> savePlanPosition(PlanPosition position) async {
    await _planPositionsBox.put(position.id, jsonEncode(position.toJson()));
    _planPositionsCache[position.id] = position;
    _log.info('Saved plan position: ${position.name}');
  }

  Future<void> deletePlanPosition(String id) async {
    await _planPositionsBox.delete(id);
    _planPositionsCache.remove(id);
    _log.info('Deleted plan position: $id');
  }

  /// Zastępuje cały plan (konwersja ze starego modelu).
  Future<void> replacePlanPositions(List<PlanPosition> positions) async {
    await _planPositionsBox.clear();
    _planPositionsCache.clear();
    for (final p in positions) {
      await _planPositionsBox.put(p.id, jsonEncode(p.toJson()));
      _planPositionsCache[p.id] = p;
    }
    _log.info('Replaced plan: ${positions.length} positions');
  }

  /// Wersja reguł, którą powstał zapisany plan (0 = konwersji jeszcze nie było).
  int getPlanConversionVersion() =>
      _settingsBox.get('planConversionVersion', defaultValue: 0) as int;

  Future<void> setPlanConversionVersion(int version) =>
      _settingsBox.put('planConversionVersion', version);

  /// Czy pozycje koperty „Na bieżące wydatki" (Planner) trafiły już do planu
  /// jako zwykłe pozycje (ADR-035).
  bool getPlanEnvelopeMigrated() =>
      _settingsBox.get('planEnvelopeMigrated', defaultValue: false) as bool;

  Future<void> setPlanEnvelopeMigrated(bool value) =>
      _settingsBox.put('planEnvelopeMigrated', value);

  /// Czy pozycje planu dostały okresy (raty, daty startu) ze starych pozycji
  /// budżetu — jednorazowe uzupełnienie planu sprzed okresów (ADR-035).
  bool getPlanPeriodsMigrated() =>
      _settingsBox.get('planPeriodsMigrated', defaultValue: false) as bool;

  Future<void> setPlanPeriodsMigrated(bool value) =>
      _settingsBox.put('planPeriodsMigrated', value);

  // ── Ustawienia w backupie (format v7) ──────────────────────────────────────
  //
  // Tylko preferencje UZYTKOWNIKA, ktore zmieniaja liczby albo dzialanie apki.
  // Celowo POZA backupem: `receiptPhotoPaths` (zdjec w pliku nie ma, wiec
  // sciezki odtworzylyby sie jako martwe linki), stan zwiniecia sekcji
  // Dashboardu (stan widoku konkretnego telefonu), `pendingBillScans`
  // (ADR-013) i `devDateOverride` (narzedzie dev).
  static const _backedUpSettingKeys = <String>[
    'currency',
    'budgetLimit',
    'budgetMode',
    // Lista budżetów z nazwami i ikonami (ADR-037) — bez niej odtworzona kopia
    // miałaby pozycje budżetów, których nie ma w przełączniku.
    'budgets',
    'notifyTrialReminders',
    'notifyRenewalReminders',
    'aiAssistantEnabled',
    'receiptArchiveEnabled',
    'receiptArchiveSubfolder',
    'themeMode',
    'accentId',
  ];

  /// Ustawienia do zapisania w backupie (pomija klucze nieustawione).
  Map<String, dynamic> exportSettings() {
    final out = <String, dynamic>{};
    for (final key in _backedUpSettingKeys) {
      final value = _settingsBox.get(key);
      if (value != null) out[key] = value;
    }
    return out;
  }

  /// Wgrywa ustawienia z backupu — wylacznie znane klucze, zeby plik nie mogl
  /// wstrzyknac czegokolwiek do pudelka ustawien.
  Future<void> importSettings(Map<String, dynamic> settings) async {
    for (final key in _backedUpSettingKeys) {
      if (!settings.containsKey(key)) continue;
      await _settingsBox.put(key, settings[key]);
    }
    _log.info('Zaimportowano ustawienia z backupu (${settings.length} pol)');
  }

  /// Czysci zbiory przed odtworzeniem stanu z backupu.
  ///
  /// Kazdy obszar ma wlasna flage i czyscimy TYLKO te, ktore dany plik potrafi
  /// odtworzyc (starsze formaty nie maja wszystkich pol). Bez tego odtworzenie
  /// ze starego pliku kasowaloby dane, ktorych nie ma czym wypelnic — tak
  /// zginal Planner przy pierwszej wersji tej funkcji (ADR-021).
  ///
  /// Kategorie domyslne ZOSTAJA przy kopii sprzed wersji 9 ([keepDefaultCategories]):
  /// tamten eksport ich nie zapisywal, wiec ich skasowanie osierociloby pozycje.
  /// Kopia v9 (ADR-038) niesie wszystkie kategorie i metody platnosci z budzetami.
  Future<void> clearForRestore({
    bool subscriptions = false,
    bool categories = false,
    bool keepDefaultCategories = true,
    bool paymentMethods = false,
    bool budgetPersonal = false,
    bool budgetHousehold = false,
    bool paymentDone = false,
    bool spendingAllocation = false,
    bool planPositions = false,
  }) async {
    // Pudełko i pamięć podręczna razem — inaczej odczyty po odtworzeniu
    // zwracałyby jeszcze dane sprzed niego (aż do restartu aplikacji).
    if (subscriptions) {
      await _subscriptionsBox.clear();
      _subscriptionsCache.clear();
    }
    if (planPositions) {
      await _planPositionsBox.clear();
      _planPositionsCache.clear();
      await setPlanConversionVersion(0);
      await setPlanEnvelopeMigrated(false);
      await setPlanPeriodsMigrated(false);
    }
    if (budgetPersonal) {
      await _budgetEntriesBox.clear();
      _budgetEntriesCache.clear();
    }
    if (budgetHousehold) {
      await _householdBudgetEntriesBox.clear();
      _householdBudgetEntriesCache.clear();
    }
    if (paymentDone) await _paymentDoneBox.clear();
    if (categories) {
      for (final key in _categoriesBox.keys.toList()) {
        if (keepDefaultCategories &&
            defaultCategories.any((d) => d.id == key)) {
          continue;
        }
        await _categoriesBox.delete(key);
        _categoriesCache.remove(key);
      }
    }
    if (paymentMethods) {
      await _paymentMethodsBox.clear();
      _paymentMethodsCache.clear();
      _invalidatePaymentMethods();
    }
    if (spendingAllocation) {
      await setSpendingAllocationItems(BudgetScope.personal, const []);
      await setSpendingAllocationItems(BudgetScope.household, const []);
    }
    _log.info('Wyczyszczono dane przed odtworzeniem z backupu');
  }

  Future<void> deleteBudgetEntry(
    String id, [
    BudgetScope scope = BudgetScope.personal,
  ]) async {
    await _budgetBox(scope).delete(id);
    _budgetCache(scope).remove(id);
    _log.info('Deleted budget entry ($scope): $id');
  }

  // ── Platnosci „wykonane" (lokalne, poza backupem) ───────────────────────────
  // Klucz: "<scope>|<sourceId>|<YYYY-MM-DD>". Brak wpisu = niewykonane.

  bool isPaymentDone(String key) =>
      _paymentDoneBox.get(key, defaultValue: false) as bool;

  Future<void> setPaymentDone(String key, bool done) async {
    if (done) {
      await _paymentDoneBox.put(key, true);
    } else {
      await _paymentDoneBox.delete(key);
    }
  }

  /// Wszystkie odhaczone płatności (do backupu). Klucz → true.
  Map<String, bool> getAllPaymentDone() {
    final m = <String, bool>{};
    for (final key in _paymentDoneBox.keys) {
      if (_paymentDoneBox.get(key) == true) m['$key'] = true;
    }
    return m;
  }

  /// Przenosi odhaczenia płatności [sourceIds] z budżetu [from] do [to]
  /// (klucz zaczyna się od identyfikatora budżetu) — przeniesiona pozycja
  /// nie traci odhaczeń. Zwraca liczbę przeniesionych wpisów.
  Future<int> movePaymentDone(
    String from,
    String to,
    Set<String> sourceIds,
  ) async {
    var moved = 0;
    for (final key in _paymentDoneBox.keys.toList()) {
      final parts = '$key'.split('|');
      if (parts.length != 3 || parts[0] != from) continue;
      if (!sourceIds.contains(parts[1])) continue;
      await _paymentDoneBox.delete(key);
      await _paymentDoneBox.put('$to|${parts[1]}|${parts[2]}', true);
      moved++;
    }
    return moved;
  }

  /// Usuwa odhaczenia płatności budżetu (przy jego usunięciu).
  Future<void> deletePaymentDoneOf(String budgetId) async {
    for (final key in _paymentDoneBox.keys.toList()) {
      if ('$key'.startsWith('$budgetId|')) await _paymentDoneBox.delete(key);
    }
  }

  /// Przywraca odhaczone płatności z backupu (tylko wpisy `true`).
  Future<void> importPaymentDone(Map<String, bool> entries) async {
    for (final e in entries.entries) {
      if (e.value) await _paymentDoneBox.put(e.key, true);
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  String getCurrency() =>
      _settingsBox.get('currency', defaultValue: 'PLN') as String;

  Future<void> setCurrency(String currencyCode) async {
    await _settingsBox.put('currency', currencyCode);
    setAppDefaultCurrency(currencyCode);
  }

  /// Tryb motywu: 'light' | 'dark' | 'system'. Default = 'dark' (obecny wyglad).
  String getThemeMode() =>
      _settingsBox.get('themeMode', defaultValue: 'dark') as String;

  Future<void> setThemeMode(String mode) async =>
      _settingsBox.put('themeMode', mode);

  /// Kolor motywu (id akcentu Aurora). Default = 'purple'.
  String getAccentId() =>
      _settingsBox.get('accentId', defaultValue: 'purple') as String;

  Future<void> setAccentId(String id) async => _settingsBox.put('accentId', id);

  /// Dev-only: override daty do testowania ghost detection
  DateTime? getDevDateOverride() {
    final v = _settingsBox.get('devDateOverride') as String?;
    if (v == null) return null;
    return DateTime.tryParse(v);
  }

  Future<void> setDevDateOverride(DateTime? date) async {
    if (date == null) {
      await _settingsBox.delete('devDateOverride');
    } else {
      await _settingsBox.put('devDateOverride', date.toIso8601String());
    }
  }

  double? getBudgetLimit() {
    final v = _settingsBox.get('budgetLimit');
    return v != null ? (v as num).toDouble() : null;
  }

  Future<void> setBudgetLimit(double? limit) async {
    if (limit == null) {
      await _settingsBox.delete('budgetLimit');
    } else {
      await _settingsBox.put('budgetLimit', limit);
    }
  }

  /// Kwota „Na bieżące wydatki" (koperta/plan przydzielony na wydatki bieżące) — per zakres,
  /// bo osobisty i domowy to osobne budżety. `null` = nie ustawiono. Lokalne
  /// (jak `budgetLimit`) — nie wchodzi do synchronizacji domowego.
  /// Pozycje koperty „Na bieżące wydatki" danego zakresu (nazwa + kwota + metoda).
  /// Migracja: stara pojedyncza kwota (`spendingAllocation|scope`) jest czytana jako
  /// jedna pozycja „Na bieżące wydatki", dopóki użytkownik nie zapisze listy pozycji.
  /// Pozycje Plannera WIDOCZNE (bez nagrobkow) — UI i sumy.
  List<SpendingAllocationItem> getSpendingAllocationItems(BudgetScope scope) =>
      List.unmodifiable(
        getSpendingAllocationItemsRaw(scope).where((e) => !e.deleted),
      );

  /// Pozycje Plannera Z NAGROBKAMI — do synchronizacji i backupu, gdzie
  /// usuniecie musi dotrzec do drugiego telefonu (ADR-022).
  List<SpendingAllocationItem> getSpendingAllocationItemsRaw(
    BudgetScope scope,
  ) {
    final raw = _settingsBox.get(StorageKeys.spendingAllocationItems(scope));
    if (raw is String && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map(
              (e) => SpendingAllocationItem.fromJson(e as Map<String, dynamic>),
            )
            .toList();
        return List.unmodifiable(list);
      } catch (e) {
        _log.warning('Nie udalo sie odczytac pozycji koperty: $e');
      }
    }
    // Migracja starej pojedynczej kwoty -> jedna pozycja koperty.
    final legacy = _settingsBox.get(
      StorageKeys.spendingAllocationLegacy(scope),
    );
    final amount = legacy is num ? legacy.toDouble() : null;
    if (amount != null && amount > 0) {
      return [
        SpendingAllocationItem(
          id: 'legacy-${scope.name}',
          name: 'Na bieżące wydatki',
          amount: amount,
        ),
      ];
    }
    return const [];
  }

  Future<void> setSpendingAllocationItems(
    BudgetScope scope,
    List<SpendingAllocationItem> items,
  ) async {
    final key = StorageKeys.spendingAllocationItems(scope);
    if (items.isEmpty) {
      await _settingsBox.delete(key);
    } else {
      await _settingsBox.put(
        key,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    }
    // Stara pojedyncza kwota jest już zmigrowana do listy — usuń, by nie wracała.
    await _settingsBox.delete(StorageKeys.spendingAllocationLegacy(scope));
  }

  // ── Budżety (ADR-037) ──────────────────────────────────────────────────────

  /// Budżety w kolejności z przełącznika. Brak zapisu = instalacja sprzed
  /// budżetów z nazwami: „Osobisty" i „Domowy", z ukryciem wziętym z dawnego
  /// trybu budżetu (osobisty / domowy / oba).
  List<Budget> getBudgets() {
    final raw = _settingsBox.get('budgets');
    if (raw is String && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => Budget.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (list.isNotEmpty) return list;
      } catch (e) {
        _log.warning('Nie udalo sie odczytac listy budzetow: $e');
      }
    }
    final legacyMode = _settingsBox.get('budgetMode') as String?;
    return [
      for (final b in Budget.defaults)
        b.copyWith(
          hidden:
              (legacyMode == 'personalOnly' && b.id == kBudgetHousehold) ||
              (legacyMode == 'householdOnly' && b.id == kBudgetPersonal),
        ),
    ];
  }

  Future<void> setBudgets(List<Budget> budgets) => _settingsBox.put(
    'budgets',
    jsonEncode([for (final b in budgets) b.toJson()]),
  );

  /// Ostatnio wybrany budżet (lokalnie, poza kopią — to stan widoku).
  String? getActiveBudgetId() => _settingsBox.get('activeBudgetId') as String?;

  Future<void> setActiveBudgetId(String id) =>
      _settingsBox.put('activeBudgetId', id);

  // ── Notification preferences ───────────────────────────────────────────────

  bool getNotifyTrialReminders() =>
      _settingsBox.get('notifyTrialReminders', defaultValue: true) as bool;

  Future<void> setNotifyTrialReminders(bool value) async =>
      _settingsBox.put('notifyTrialReminders', value);

  bool getNotifyRenewalReminders() =>
      _settingsBox.get('notifyRenewalReminders', defaultValue: true) as bool;

  Future<void> setNotifyRenewalReminders(bool value) async =>
      _settingsBox.put('notifyRenewalReminders', value);

  // ── Zakładka Budżet: zwinięcie sekcji kalendarza ──────────────────────────────

  bool getDashboardMonthCompact() =>
      _settingsBox.get('dashboardMonthCompact', defaultValue: false) as bool;

  Future<void> setDashboardMonthCompact(bool value) async =>
      _settingsBox.put('dashboardMonthCompact', value);

  /// Sekcja „Podsumowanie miesiąca" (wpływy i wydatki po dniach) — domyślnie
  /// rozwinięta: to zestawienie ma być widoczne, a nie ukryte pod przyciskiem.
  bool getDashboardMonthSummaryCompact() =>
      _settingsBox.get('dashboardMonthSummaryCompact', defaultValue: false)
          as bool;

  Future<void> setDashboardMonthSummaryCompact(bool value) async =>
      _settingsBox.put('dashboardMonthSummaryCompact', value);

  bool getDashboardPaymentsCompact() =>
      _settingsBox.get('dashboardPaymentsCompact', defaultValue: false) as bool;

  Future<void> setDashboardPaymentsCompact(bool value) async =>
      _settingsBox.put('dashboardPaymentsCompact', value);

  // ── Widok sekcji miesiaca (Platnosci / Podsumowanie) ───────────────────────
  //
  // Sortowanie, grupowanie i zwijanie biezacych — OSOBNO dla kazdej sekcji
  // (`section` = „payments" / „summary"), bo obie listy oglada sie w innym celu.
  // Klucz sekcji jest staly: tytuly na ekranie bywaja poprawiane, klucz nie.
  //
  // Poza backupem, jak reszta stanu widoku Dashboardu — to sposob patrzenia na
  // konkretnym telefonie, a nie preferencja, ktora ma wedrowac z kopia.
  //
  // Wartosci to nazwy enumow. Przemianowanie enuma nie psuje danych: odczyt ma
  // `orElse`, wiec najgorsze, co sie stanie, to powrot do domyslnego widoku.

  String getFlowSort(String section) =>
      _settingsBox.get('flowSort|$section', defaultValue: 'byDate') as String;

  Future<void> setFlowSort(String section, String value) async =>
      _settingsBox.put('flowSort|$section', value);

  String getFlowGrouping(String section) =>
      _settingsBox.get('flowGrouping|$section', defaultValue: 'none') as String;

  Future<void> setFlowGrouping(String section, String value) async =>
      _settingsBox.put('flowGrouping|$section', value);

  bool getFlowSpendingCollapsed(String section) =>
      _settingsBox.get('flowSpendingCollapsed|$section', defaultValue: false)
          as bool;

  Future<void> setFlowSpendingCollapsed(String section, bool value) async =>
      _settingsBox.put('flowSpendingCollapsed|$section', value);

  /// Sekcja „Szczegóły" na zakładce Plan — domyślnie ZWINIĘTA: wspólne wykresy
  /// nad nią pokazują całość, a karty pojedynczych strumieni to doczytanie.
  bool getDashboardPlanDetailsCompact() =>
      _settingsBox.get('dashboardPlanDetailsCompact', defaultValue: true)
          as bool;

  Future<void> setDashboardPlanDetailsCompact(bool value) async =>
      _settingsBox.put('dashboardPlanDetailsCompact', value);

  /// Zwinięte sekcje list „Wydatki" i „Wpływy" (klucze sekcji, nie tytuły).
  /// Jedna lista zamiast flagi na sekcję — sekcji przybywa (subskrypcje,
  /// ADR-027), a każda nowa nie musi dokładać własnego ustawienia.
  /// Domyślnie pusta: sekcje startują rozwinięte.
  Set<String> getCollapsedBudgetSections() =>
      (_settingsBox.get('collapsedBudgetSections', defaultValue: const [])
              as List)
          .cast<String>()
          .toSet();

  Future<void> setCollapsedBudgetSections(Set<String> keys) async =>
      _settingsBox.put('collapsedBudgetSections', keys.toList()..sort());
}
