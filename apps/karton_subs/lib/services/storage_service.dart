import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/subscription.dart';
import '../models/category.dart';
import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import '../models/spending_allocation_item.dart';
import '../models/pending_receipt_scan.dart';
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
    _seedDefaultCategories();
    _seedDefaultPaymentMethods();
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

  void _seedDefaultCategories() {
    if (_categoriesCache.isNotEmpty) return;
    for (final cat in defaultCategories) {
      _categoriesBox.put(cat.id, jsonEncode(cat.toJson()));
      _categoriesCache[cat.id] = cat;
    }
    _log.info('Seeded ${defaultCategories.length} default categories');
  }

  List<Category> getCategories() {
    final cats = _categoriesCache.values.toList();
    cats.sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(cats);
  }

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
    _paymentMethodsSorted = null;
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

  void _seedDefaultPaymentMethods() {
    if (_paymentMethodsCache.isNotEmpty) return;
    for (final pm in defaultPaymentMethods) {
      _paymentMethodsBox.put(pm.id, jsonEncode(pm.toJson()));
      _paymentMethodsCache[pm.id] = pm;
    }
    _paymentMethodsSorted = null;
    _log.info('Seeded ${defaultPaymentMethods.length} default payment methods');
  }

  /// Posortowana lista metod płatności, budowana raz i unieważniana przy każdym
  /// zapisie. Woła ją KAŻDY wiersz listy (żeby sprawdzić, czy płatność jest
  /// automatyczna), a wcześniej każde takie wywołanie tworzyło nową listę
  /// i sortowało ją od nowa — przy kilkuset wierszach to kilkaset sortowań
  /// na jedno przemalowanie ekranu.
  List<PaymentMethod>? _paymentMethodsSorted;

  List<PaymentMethod> getPaymentMethods() {
    final cached = _paymentMethodsSorted;
    if (cached != null) return cached;
    final items = _paymentMethodsCache.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return _paymentMethodsSorted = List.unmodifiable(items);
  }

  PaymentMethod? getPaymentMethod(String id) => _paymentMethodsCache[id];

  /// Zapisuje metodę płatności. [stamp] jak w [saveCategory].
  Future<void> savePaymentMethod(PaymentMethod pm, {bool stamp = true}) async {
    final toSave = stamp ? pm.copyWith(updatedAt: DateTime.now()) : pm;
    await _paymentMethodsBox.put(toSave.id, jsonEncode(toSave.toJson()));
    _paymentMethodsCache[toSave.id] = toSave;
    _paymentMethodsSorted = null;
  }

  Future<void> deletePaymentMethod(String id) async {
    await _paymentMethodsBox.delete(id);
    _paymentMethodsCache.remove(id);
    _paymentMethodsSorted = null;
    _log.info('Deleted payment method: $id');
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
  /// Kategorie domyslne ZOSTAJA: eksport ich nie zapisuje (sa zawsze zasiane),
  /// wiec ich skasowanie osierocilo by pozycje, ktore sie do nich odwoluja.
  Future<void> clearForRestore({
    bool subscriptions = false,
    bool categories = false,
    bool budgetPersonal = false,
    bool budgetHousehold = false,
    bool paymentDone = false,
    bool spendingAllocation = false,
    bool planPositions = false,
  }) async {
    if (subscriptions) await _subscriptionsBox.clear();
    if (planPositions) {
      await _planPositionsBox.clear();
      _planPositionsCache.clear();
      await setPlanConversionVersion(0);
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
        if (defaultCategories.any((d) => d.id == key)) continue;
        await _categoriesBox.delete(key);
      }
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

  /// Zastępuje cały zbiór danego zakresu (po scaleniu przy synchronizacji,
  /// ADR-009). W odróżnieniu od [saveBudgetEntry] NIE modyfikuje pozycji —
  /// zachowuje ich `updatedAt`/`deleted` (łącznie z nagrobkami).
  Future<void> replaceBudgetEntries(
    BudgetScope scope,
    List<BudgetEntry> entries,
  ) async {
    final box = _budgetBox(scope);
    final cache = _budgetCache(scope);
    await box.clear();
    cache.clear();
    for (final e in entries) {
      await box.put(e.id, jsonEncode(e.toJson()));
      cache[e.id] = e;
    }
    _log.info('Replaced ${entries.length} budget entries ($scope) [sync]');
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

  /// Przepina odhaczenia płatności na nowy klucz — przy przeniesieniu wydatku
  /// między budżetami zmienia się i zakres, i `id`, a klucz zawiera oba
  /// (`zakres|id|data`). Bez tego zapłacony wydatek wróciłby na listę
  /// „Płatności" do odhaczenia. Zwraca liczbę przeniesionych wpisów.
  Future<int> movePaymentDone(String fromPrefix, String toPrefix) async {
    final moved = <String, bool>{};
    for (final key in _paymentDoneBox.keys.toList()) {
      final k = '$key';
      if (!k.startsWith(fromPrefix)) continue;
      if (_paymentDoneBox.get(key) == true) {
        moved['$toPrefix${k.substring(fromPrefix.length)}'] = true;
      }
      await _paymentDoneBox.delete(key);
    }
    for (final e in moved.entries) {
      await _paymentDoneBox.put(e.key, e.value);
    }
    return moved.length;
  }

  /// Wszystkie odhaczone płatności (do backupu). Klucz → true.
  Map<String, bool> getAllPaymentDone() {
    final m = <String, bool>{};
    for (final key in _paymentDoneBox.keys) {
      if (_paymentDoneBox.get(key) == true) m['$key'] = true;
    }
    return m;
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

  /// Suma koperty „Na bieżące wydatki" danego zakresu (= Σ pozycji). `null` = pusto.
  /// Silnik obliczeń dostaje jedną liczbę (jak dawniej) — matematyka bez zmian.
  double? getSpendingAllocation(BudgetScope scope) {
    final items = getSpendingAllocationItems(scope);
    if (items.isEmpty) return null;
    final sum = items.fold<double>(0, (a, b) => a + b.amount);
    return sum > 0 ? sum : null;
  }

  /// Powiązanie zdjęcia wydatku z zapisaną pozycją budżetu (id → ścieżka do
  /// prywatnej kopii w katalogu apki). LOKALNE, poza synchronizacją i backupem
  /// — ścieżka nie ma sensu na drugim urządzeniu. Służy podglądowi zdjęcia
  /// przy edycji zatwierdzonego wydatku.
  Map<String, String> getReceiptPhotoPaths() {
    final raw = _settingsBox.get(StorageKeys.receiptPhotoPaths);
    if (raw is String && raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
      } catch (e) {
        _log.warning('Nie udalo sie odczytac receiptPhotoPaths: $e');
      }
    }
    return {};
  }

  String? getReceiptPhotoPath(String entryId) =>
      getReceiptPhotoPaths()[entryId];

  Future<void> setReceiptPhotoPath(String entryId, String path) async {
    final map = getReceiptPhotoPaths()..[entryId] = path;
    await _settingsBox.put(StorageKeys.receiptPhotoPaths, jsonEncode(map));
  }

  Future<void> removeReceiptPhotoPath(String entryId) async {
    final map = getReceiptPhotoPaths();
    if (map.remove(entryId) != null) {
      await _settingsBox.put(StorageKeys.receiptPhotoPaths, jsonEncode(map));
    }
  }

  /// Bieżące rozpoznane przez lokalny silnik AI, oczekujące na zatwierdzenie.
  /// LOKALNE (jak koperta): poza synchronizacją, backupem i bilansem — do budżetu
  /// trafiają dopiero po zatwierdzeniu (wtedy stają się zwykłym billPayment).
  List<PendingReceiptScan> getPendingReceiptScans() {
    final raw = _settingsBox.get(StorageKeys.pendingReceiptScans);
    if (raw is String && raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => PendingReceiptScan.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        _log.warning('Nie udalo sie odczytac pendingBillScans: $e');
      }
    }
    return [];
  }

  /// Tryb budżetu (preferencja UI, lokalna — poza sync). Default: oba zakresy
  /// (jak dotąd). Tryb jednozakresowy chowa przełącznik zakresu i zwalnia swipe.
  BudgetMode getBudgetMode() {
    final raw = _settingsBox.get('budgetMode') as String?;
    return BudgetMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => BudgetMode.both,
    );
  }

  Future<void> setBudgetMode(BudgetMode mode) =>
      _settingsBox.put('budgetMode', mode.name);

  /// Asystent AI (skan wydatków lokalnym silnikiem): opt-in, domyślnie
  /// wyłączony. Wyłączony ukrywa opcje skanowania w menu „Dodaj wydatek".
  bool getAiAssistantEnabled() =>
      _settingsBox.get('aiAssistantEnabled', defaultValue: false) as bool;

  Future<void> setAiAssistantEnabled(bool value) =>
      _settingsBox.put('aiAssistantEnabled', value);

  /// Archiwum wydatków: trwały zapis zdjęć zatwierdzonych wydatków do
  /// publicznego katalogu `Documents/[podfolder]`. Opt-in, lokalne (poza sync).
  bool getReceiptArchiveEnabled() =>
      _settingsBox.get(StorageKeys.receiptArchiveEnabled, defaultValue: false)
          as bool;

  Future<void> setReceiptArchiveEnabled(bool value) =>
      _settingsBox.put(StorageKeys.receiptArchiveEnabled, value);

  /// Podfolder w Documents dla archiwum (domyślnie „Zostaje").
  // ── Nazwy plikow w publicznym archiwum (per wydatek) ──────────────────────
  //
  // Zapamietujemy, pod jaka nazwa wydatek lezy w `Documents/<podfolder>`, bo
  // przy podmianie docietego zdjecia trzeba usunac STARY plik — MediaStore nie
  // nadpisuje po nazwie, tylko dokłada „nazwa (1).jpg". Nazwa zawiera date,
  // nazwe i kwote, wiec po edycji wydatku nie da sie jej odtworzyc.

  Map<String, String> getArchivedReceiptNames() {
    final raw = _settingsBox.get('archivedReceiptNames');
    if (raw is String && raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
      } catch (e) {
        _log.warning('Nie udalo sie odczytac archivedReceiptNames: $e');
      }
    }
    return {};
  }

  String? getArchivedReceiptName(String entryId) =>
      getArchivedReceiptNames()[entryId];

  Future<void> setArchivedReceiptName(String entryId, String filename) async {
    final map = getArchivedReceiptNames()..[entryId] = filename;
    await _settingsBox.put('archivedReceiptNames', jsonEncode(map));
  }

  Future<void> removeArchivedReceiptName(String entryId) async {
    final map = getArchivedReceiptNames();
    if (map.remove(entryId) != null) {
      await _settingsBox.put('archivedReceiptNames', jsonEncode(map));
    }
  }

  // ── „Udostepnij -> Zostaje": juz obsluzone udostepnienia ───────────────────
  //
  // Android przy wznowieniu zadania z listy ostatnich potrafi PONOWIC pierwotny
  // intent ACTION_SEND, wiec `getInitialMedia()` oddaje to samo zdjecie przy
  // kolejnych startach aplikacji. Bez trwalej pamieci co juz przyjelismy, ten
  // sam wydatek dokladal sie do kolejki po kazdym uruchomieniu.
  //
  // Klucz to „podpis" pliku (sciezka + rozmiar + czas modyfikacji), nie sama
  // sciezka: katalog udostepnien bywa recyklingowany pod te sama nazwe.

  /// Podpisy ostatnio obsluzonych udostepnien (najnowsze na koncu).
  List<String> getHandledShares() {
    final raw = _settingsBox.get('handledShares');
    if (raw is String && raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as List).map((e) => '$e').toList();
      } catch (e) {
        _log.warning('Failed to parse handledShares: $e');
      }
    }
    return const [];
  }

  /// Zapisuje podpisy; trzymamy ostatnie [max] — to zabezpieczenie przed
  /// powtorka, nie historia.
  Future<void> setHandledShares(List<String> signatures, {int max = 30}) {
    final trimmed = signatures.length > max
        ? signatures.sublist(signatures.length - max)
        : signatures;
    return _settingsBox.put('handledShares', jsonEncode(trimmed));
  }

  String getReceiptArchiveSubfolder() =>
      _settingsBox.get('receiptArchiveSubfolder', defaultValue: 'Zostaje')
          as String;

  Future<void> setReceiptArchiveSubfolder(String value) {
    final clean = value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return _settingsBox.put(
      'receiptArchiveSubfolder',
      clean.isEmpty ? 'Zostaje' : clean,
    );
  }

  Future<void> savePendingReceiptScans(List<PendingReceiptScan> items) async {
    if (items.isEmpty) {
      await _settingsBox.delete(StorageKeys.pendingReceiptScans);
    } else {
      await _settingsBox.put(
        StorageKeys.pendingReceiptScans,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    }
  }

  // ── Notification preferences ───────────────────────────────────────────────

  bool getNotifyTrialReminders() =>
      _settingsBox.get('notifyTrialReminders', defaultValue: true) as bool;

  Future<void> setNotifyTrialReminders(bool value) async =>
      _settingsBox.put('notifyTrialReminders', value);

  bool getNotifyRenewalReminders() =>
      _settingsBox.get('notifyRenewalReminders', defaultValue: true) as bool;

  Future<void> setNotifyRenewalReminders(bool value) async =>
      _settingsBox.put('notifyRenewalReminders', value);

  // ── Personalizacja Dashboardu (full/compact per sekcja) ─────────────────────

  bool getDashboardSummaryCompact() =>
      _settingsBox.get('dashboardSummaryCompact', defaultValue: false) as bool;

  Future<void> setDashboardSummaryCompact(bool value) async =>
      _settingsBox.put('dashboardSummaryCompact', value);

  bool getDashboardSubscriptionsCompact() =>
      _settingsBox.get('dashboardSubscriptionsCompact', defaultValue: false)
          as bool;

  Future<void> setDashboardSubscriptionsCompact(bool value) async =>
      _settingsBox.put('dashboardSubscriptionsCompact', value);

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

  bool getDashboardAutoPaymentsCompact() =>
      _settingsBox.get('dashboardAutoPaymentsCompact', defaultValue: false)
          as bool;

  Future<void> setDashboardAutoPaymentsCompact(bool value) async =>
      _settingsBox.put('dashboardAutoPaymentsCompact', value);

  /// Sekcja „Rzeczywisty bilans miesiąca" — domyślnie ROZWINIĘTA: to główne
  /// pytanie tej zakładki, a rozpis tłumaczy kwotę pod nim.
  bool getDashboardMonthBalanceCompact() =>
      _settingsBox.get('dashboardMonthBalanceCompact', defaultValue: false)
          as bool;

  Future<void> setDashboardMonthBalanceCompact(bool value) async =>
      _settingsBox.put('dashboardMonthBalanceCompact', value);

  /// Akordeon „Koszty roczne" (Plan) — domyślnie ZWINIĘTY: skala roczna to
  /// doczytanie, codzienne pytanie dotyczy miesiąca.
  bool getDashboardAnnualCostsCompact() =>
      _settingsBox.get('dashboardAnnualCostsCompact', defaultValue: true)
          as bool;

  Future<void> setDashboardAnnualCostsCompact(bool value) async =>
      _settingsBox.put('dashboardAnnualCostsCompact', value);

  /// Sekcja „Szczegóły" na zakładce Plan — domyślnie ZWINIĘTA: wspólne wykresy
  /// nad nią pokazują całość, a karty pojedynczych strumieni to doczytanie.
  bool getDashboardPlanDetailsCompact() =>
      _settingsBox.get('dashboardPlanDetailsCompact', defaultValue: true)
          as bool;

  Future<void> setDashboardPlanDetailsCompact(bool value) async =>
      _settingsBox.put('dashboardPlanDetailsCompact', value);

  /// Początek ewidencji budżetu („YYYY-MM", per zakres) — od kiedy dane w tej
  /// aplikacji są kompletne. Miesiące wcześniejsze nie wchodzą do podsumowania
  /// rocznego ani do planu, z którym się je porównuje: budżet prowadzony od
  /// lipca wygladalby inaczej na wykonanym w połowie tylko dlatego, że przez
  /// pół roku nie było czego zapisywać. `null` = cały rok.
  String? getTrackingStartMonth(BudgetScope scope) {
    final v = _settingsBox.get('trackingStartMonth|${scope.name}');
    return v is String && v.isNotEmpty ? v : null;
  }

  Future<void> setTrackingStartMonth(
    BudgetScope scope,
    String? monthKey,
  ) async {
    final key = 'trackingStartMonth|${scope.name}';
    if (monthKey == null) {
      await _settingsBox.delete(key);
    } else {
      await _settingsBox.put(key, monthKey);
    }
  }

  /// Ujęcie wykresów na zakładce „Plan" (`plan` / `actual`, ADR-028) — osobno
  /// dla trendu i dla podziału na kategorie. Osobno, bo oba widoki służą do
  /// PORÓWNYWANIA: jeden wspólny przełącznik odbierałby możliwość zestawienia
  /// planowego trendu z realnym podziałem. Domyślnie plan — tak nazywa się
  /// zakładka, a rzeczywistość jest doczytaniem.
  String getPlanTrendView() =>
      _settingsBox.get('planTrendView', defaultValue: 'plan') as String;

  Future<void> setPlanTrendView(String value) async =>
      _settingsBox.put('planTrendView', value);

  String getPlanCategoriesView() =>
      _settingsBox.get('planCategoriesView', defaultValue: 'plan') as String;

  Future<void> setPlanCategoriesView(String value) async =>
      _settingsBox.put('planCategoriesView', value);

  /// Podsumowanie roczne — ujęcie i zwinięcie. Domyślnie `actual`: cała sekcja
  /// odpowiada na pytanie „ile już wydaliśmy", a plan jest tu tłem porównania.
  String getPlanYearView() =>
      _settingsBox.get('planYearView', defaultValue: 'actual') as String;

  Future<void> setPlanYearView(String value) async =>
      _settingsBox.put('planYearView', value);

  /// Grupy zakładki „Plan" — zwinięcie całej grupy kart tapnięciem w jej
  /// nagłówek. Domyślnie rozwinięte: to jest treść zakładki, a nie doczytanie.
  bool getPlanMonthGroupCompact() =>
      _settingsBox.get('planMonthGroupCompact', defaultValue: false) as bool;

  Future<void> setPlanMonthGroupCompact(bool value) async =>
      _settingsBox.put('planMonthGroupCompact', value);

  bool getPlanStatsGroupCompact() =>
      _settingsBox.get('planStatsGroupCompact', defaultValue: false) as bool;

  Future<void> setPlanStatsGroupCompact(bool value) async =>
      _settingsBox.put('planStatsGroupCompact', value);

  /// Sekcja „Podsumowanie roczne" — domyślnie ZWINIĘTA: dwanaście wierszy to
  /// doczytanie, a nagłówek z paskiem odpowiada na pytanie od razu.
  bool getDashboardAnnualSummaryCompact() =>
      _settingsBox.get('dashboardAnnualSummaryCompact', defaultValue: true)
          as bool;

  Future<void> setDashboardAnnualSummaryCompact(bool value) async =>
      _settingsBox.put('dashboardAnnualSummaryCompact', value);

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
