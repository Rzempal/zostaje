import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/subscription.dart';
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
        if (defaultCategories.any((d) => d.id == key)) continue;
        await _categoriesBox.delete(key);
        _categoriesCache.remove(key);
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
