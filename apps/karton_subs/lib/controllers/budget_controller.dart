import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/budget_entry.dart';
import '../models/spending_allocation_item.dart';
import '../models/subscription.dart';
import '../utils/dictionary_usage.dart';
import '../services/storage_service.dart';
import '../services/budget_service.dart';
import '../services/analytics_service.dart' show MonthlyDataPoint;
import '../services/currency_service.dart';
import '../services/app_logger.dart';
import 'subscription_controller.dart';

/// Zarządza stanem budżetu (osobisty + domowy) — CRUD pozycji + computed agregaty.
///
/// Aktywny zakres ([scope]) ustawia UI (przełącznik); wszystkie gettery liczą dla
/// niego. Osobisty i domowy to osobne boxy. Przelew do domowego to para spięta
/// `linkId`: koszt w osobistym + lustrzany wpływ w domowym.
/// Czyta subskrypcje danego zakresu jako dodatkowy strumień kosztów.
class BudgetController extends ChangeNotifier {
  static final _log = AppLogger.get('BudgetController');
  final StorageService _storage;
  final SubscriptionController _subscriptions;
  static const _uuid = Uuid();
  static const _budget = BudgetService();
  static const _currency = CurrencyService();

  BudgetController(this._storage, this._subscriptions) {
    _subscriptions.addListener(_onSubscriptionsChanged);
    // Tryb budżetu (preferencja UI) wymusza zakres startowy w trybie jednym.
    _mode = _storage.getBudgetMode();
    _scope = _scopeForMode(_mode) ?? _scope;
  }

  void _onSubscriptionsChanged() => notifyListeners();

  /// Wywoływane po zmianie dotykającej budżetu domowego — `main` podpina tu
  /// (debounced) synchronizację (ADR-009). `null` = brak synchronizacji.
  void Function()? onHouseholdChanged;

  /// Powiadamia UI i — gdy zmiana dotknęła domowego — wyzwala synchronizację.
  void _notifyMutation({required bool touchedHousehold}) {
    notifyListeners();
    if (touchedHousehold) onHouseholdChanged?.call();
  }

  @override
  void dispose() {
    _subscriptions.removeListener(_onSubscriptionsChanged);
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

  Currency get _target {
    final code = _storage.getCurrency();
    return Currency.values.firstWhere(
      (c) => c.name == code || c.label == code,
      orElse: () => Currency.PLN,
    );
  }

  /// Subskrypcje pasujące do aktywnego zakresu (osobiste/domowe).
  SubscriptionScope get _subScope =>
      isHousehold ? SubscriptionScope.household : SubscriptionScope.personal;
  List<Subscription> get _subsForScope =>
      _storage.getSubscriptions().where((s) => s.scope == _subScope).toList();

  // ── Listy (aktywny zakres) ───────────────────────────────────────────────

  /// Pozycje aktywnego zakresu widoczne dla UI/agregatów — bez nagrobków
  /// (pozycji oznaczonych `deleted` przy synchronizacji domowego, ADR-009).
  List<BudgetEntry> get all =>
      _storage.getBudgetEntries(_scope).where((e) => !e.deleted).toList();

  /// Wpływy: cykliczne (pensja) + jednorazowe (premia) + wkłady (lustro przelewu w domowym).
  List<BudgetEntry> get incomes =>
      all.where((e) => e.isIncome).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Koszty cykliczne (wydatki bieżące, koszty cykliczne, raty) — BEZ przelewu do domowego,
  /// który ma własną sekcję „Przelew wewnętrzny".
  List<BudgetEntry> get recurringExpenses =>
      all
          .where(
            (e) =>
                e.isExpense &&
                !e.isOneTime &&
                e.type != BudgetEntryType.householdTransfer,
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Przelewy do budżetu domowego (tylko zakres osobisty) — sekcja „Przelew wewnętrzny".
  List<BudgetEntry> get internalTransfers =>
      all.where((e) => e.type == BudgetEntryType.householdTransfer).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Subskrypcje aktywnego zakresu — na liście „Wydatki" są trzecią sekcją obok
  /// przelewu wewnętrznego i wydatków stałych (ADR-027). Przypięte na górze,
  /// tak jak na dawnym ekranie „Subskrypcje".
  List<Subscription> get subscriptions => _subsForScope;

  /// Kwota miesięczna subskrypcji w walucie docelowej. Trwający okres próbny
  /// liczy się jako 0 — tak samo jak w planie i na wykresach.
  double monthlySubscriptionAmount(Subscription s) =>
      _currency.convertMonthlyAmount(s, _target);

  /// Suma subskrypcji do nagłówka sekcji — tylko aktywne, bo tylko one wchodzą
  /// do planu. Anulowana subskrypcja bywa na liście widoczna („pokaż ukryte"),
  /// ale nic nie kosztuje.
  double sumSubscriptions(List<Subscription> subs) => subs
      .where((s) => s.isActive)
      .fold(0.0, (sum, s) => sum + monthlySubscriptionAmount(s));

  /// Suma pozycji w walucie docelowej — do nagłówka sekcji. [monthKey] =
  /// filtr na jednym miesiącu: wtedy z korektami kwot tego miesiąca, tak jak
  /// wiersze listy. Reguła w [BudgetService.sumAmounts].
  double sumAmounts(List<BudgetEntry> entries, {String? monthKey}) =>
      _budget.sumAmounts(entries, monthKey: monthKey, target: _target);

  /// Waluta docelowa (kod) — do formatowania w UI.
  String get targetCurrencyLabel => _target.label;

  /// Bieżące ([BudgetEntryType.spending]) aktywnego zakresu — najnowsze
  /// u góry (ekran „Bieżące"). Obejmuje wydatki jednorazowe: po scaleniu
  /// typów (ADR-018) to jeden byt — datowany wydatek poza planem.
  List<BudgetEntry> get spendingEntries {
    final list = all.where((e) => e.type == BudgetEntryType.spending).toList();
    list.sort(
      (a, b) => (b.startDate ?? b.dataDodania).compareTo(
        a.startDate ?? a.dataDodania,
      ),
    );
    return list;
  }

  // ── Computed agregaty (aktywny zakres, w walucie docelowej) ────────────────

  double get monthlyIncome => _budget.monthlyIncome(all, target: _target);

  double get monthlyBudgetExpenses =>
      _budget.monthlyBudgetExpenses(all, target: _target);

  double get monthlySubscriptionsExpense =>
      _budget.monthlySubscriptionsExpense(_subsForScope, target: _target);

  /// Koszty/mies w planie: cykliczne + subskrypcje + rezerwa „Na bieżące wydatki".
  /// (Dzięki temu wpływy − koszty = „zostaje/mies".)
  double get monthlyExpenses =>
      _budget.monthlyRecurringExpenses(all, _subsForScope, target: _target) +
      _alloc;

  double get monthlySurplus => _budget.monthlySurplus(
    all,
    _subsForScope,
    target: _target,
    spendingAllocation: _alloc,
  );

  /// Bilans miesiąca rozbity na strumienie (sekcja „Rzeczywisty bilans").
  MonthBalanceParts monthBalanceParts(String monthKey) =>
      _budget.monthBalanceParts(all, _subsForScope, monthKey, target: _target);

  double balanceForMonth(String monthKey) => _budget.balanceForMonth(
    all,
    _subsForScope,
    monthKey,
    target: _target,
    spendingAllocation: _alloc,
  );

  /// Pozycje, które sprawiają, że bilans miesiąca różni się od salda planu
  /// (jednorazowe, korekty kwot i rat, rezerwa „Na bieżące wydatki"). Do bottom sheeta.
  List<BalanceContribution> balanceBreakdownForMonth(String monthKey) =>
      _budget.balanceBreakdownForMonth(
        all,
        monthKey,
        target: _target,
        spendingAllocation: _alloc,
      );

  // ── Bieżące: koperta „Na bieżące wydatki" (plan) vs realne wydatki bieżące ──────────────

  /// Suma „Na bieżące wydatki" (plan/koperta) aktywnego zakresu. `null` = nie ustawiono.
  double? get spendingAllocation => _storage.getSpendingAllocation(_scope);

  /// Wartość koperty do obliczeń (0 gdy nieustawiona).
  double get _alloc => spendingAllocation ?? 0;

  /// Pozycje koperty „Na bieżące wydatki" aktywnego zakresu (nazwa + kwota + metoda).
  List<SpendingAllocationItem> get spendingAllocationItems =>
      _storage.getSpendingAllocationItems(_scope);

  /// Pozycje Plannera z nagrobkami — podstawa KAZDEJ mutacji. Budowanie nowej
  /// listy z widocznych pozycji gubiloby nagrobki, a wtedy usuniecie przestaloby
  /// docierac do drugiego telefonu (ADR-022).
  List<SpendingAllocationItem> get _allocRaw =>
      _storage.getSpendingAllocationItemsRaw(_scope);

  Future<void> addSpendingAllocationItem({
    required String name,
    required double amount,
    String? paymentMethod,
    String? categoryId,
  }) async {
    final items = [
      ..._allocRaw,
      SpendingAllocationItem(
        id: _uuid.v4(),
        name: name,
        amount: amount,
        updatedAt: DateTime.now(),
        paymentMethod: paymentMethod,
        categoryId: categoryId,
      ),
    ];
    await _saveAllocation(items);
  }

  Future<void> updateSpendingAllocationItem(SpendingAllocationItem item) async {
    final stamped = item.copyWith(updatedAt: DateTime.now());
    final items = _allocRaw.map((e) => e.id == item.id ? stamped : e).toList();
    await _saveAllocation(items);
  }

  /// Usuwa pozycję Plannera. W zakresie DOMOWYM zostawia nagrobek, by usunięcie
  /// dotarło do drugiego telefonu; w osobistym (bez synchronizacji) kasuje twardo.
  Future<void> removeSpendingAllocationItem(String id) async {
    final items = isHousehold
        ? _allocRaw
              .map(
                (e) => e.id == id
                    ? e.copyWith(deleted: true, updatedAt: DateTime.now())
                    : e,
              )
              .toList()
        : _allocRaw.where((e) => e.id != id).toList();
    await _saveAllocation(items);
  }

  /// Zapis Plannera + powiadomienie UI; w zakresie domowym wyzwala też
  /// synchronizację (ADR-022 — Planner jedzie w tej samej paczce co pozycje).
  Future<void> _saveAllocation(List<SpendingAllocationItem> items) async {
    await _storage.setSpendingAllocationItems(_scope, items);
    _notifyMutation(touchedHousehold: isHousehold);
  }

  // ── Słowniki: użycie i kaskady (Kategorie / Metody płatności) ───────────────
  // Kategorie i metody płatności są współdzielone przez oba zakresy budżetu oraz
  // pozycje „Na bieżące wydatki". Zarządzanie słownikami (Ustawienia) jest globalne, więc
  // te operacje działają PONAD oboma zakresami, niezależnie od aktywnego.

  /// Liczba pozycji budżetu (oba zakresy, bez nagrobków) oraz pozycji koperty
  /// „Na bieżące wydatki" (oba zakresy) w danej kategorii.
  int countCategoryUsage(String categoryId) {
    var n = 0;
    for (final scope in BudgetScope.values) {
      n += DictionaryUsage.categoryInEntries(
        _storage.getBudgetEntries(scope),
        categoryId,
      );
      n += DictionaryUsage.categoryInItems(
        _storage.getSpendingAllocationItems(scope),
        categoryId,
      );
    }
    return n;
  }

  /// Liczba użyć metody płatności (po nazwie) w pozycjach budżetu (oba zakresy)
  /// oraz w kopertach „Na bieżące wydatki" (oba zakresy).
  int countPaymentMethodUsage(String name) {
    var n = 0;
    for (final scope in BudgetScope.values) {
      n += DictionaryUsage.methodInEntries(
        _storage.getBudgetEntries(scope),
        name,
      );
      n += DictionaryUsage.methodInItems(
        _storage.getSpendingAllocationItems(scope),
        name,
      );
    }
    return n;
  }

  /// Przenosi pozycje budżetu (oba zakresy) oraz pozycje koperty „Na bieżące wydatki"
  /// (oba zakresy, lokalne — bez synchronizacji) z kategorii [fromId] do [toId].
  /// Zwraca liczbę zmienionych pozycji. Wywoływane przy usunięciu kategorii.
  Future<int> reassignCategoryEverywhere(String fromId, String toId) async {
    var affected = 0;
    var touchedHousehold = false;
    for (final scope in BudgetScope.values) {
      final entries = _storage
          .getBudgetEntries(scope)
          .where((e) => !e.deleted && e.categoryId == fromId)
          .toList();
      for (final e in entries) {
        await _saveStamped(e.copyWith(categoryId: toId), scope);
      }
      if (entries.isNotEmpty) {
        affected += entries.length;
        if (scope == BudgetScope.household) touchedHousehold = true;
      }
      final items = _storage.getSpendingAllocationItems(scope);
      final hit = items.where((i) => i.categoryId == fromId).length;
      if (hit > 0) {
        await _storage.setSpendingAllocationItems(
          scope,
          items
              .map(
                (i) =>
                    i.categoryId == fromId ? i.copyWith(categoryId: toId) : i,
              )
              .toList(),
        );
        affected += hit;
      }
    }
    if (affected > 0) _notifyMutation(touchedHousehold: touchedHousehold);
    return affected;
  }

  /// Zmienia nazwę metody płatności wszędzie w budżecie: pozycje (oba zakresy)
  /// i koperty „Na bieżące wydatki" (oba zakresy). Zwraca liczbę zmienionych.
  Future<int> renamePaymentMethodEverywhere(
    String oldName,
    String newName,
  ) async {
    if (oldName == newName) return 0;
    var affected = 0;
    var touchedHousehold = false;
    for (final scope in BudgetScope.values) {
      final entries = _storage
          .getBudgetEntries(scope)
          .where((e) => !e.deleted && e.paymentMethod == oldName)
          .toList();
      for (final e in entries) {
        await _saveStamped(e.copyWith(paymentMethod: newName), scope);
      }
      if (entries.isNotEmpty) {
        affected += entries.length;
        if (scope == BudgetScope.household) touchedHousehold = true;
      }
      // Koperty „Na bieżące wydatki" — lokalne (bez synchronizacji).
      final items = _storage.getSpendingAllocationItems(scope);
      final hit = items.where((i) => i.paymentMethod == oldName).length;
      if (hit > 0) {
        await _storage.setSpendingAllocationItems(
          scope,
          items
              .map(
                (i) => i.paymentMethod == oldName
                    ? i.copyWith(paymentMethod: newName)
                    : i,
              )
              .toList(),
        );
        affected += hit;
      }
    }
    if (affected > 0) _notifyMutation(touchedHousehold: touchedHousehold);
    return affected;
  }

  /// Czyści metodę płatności (po nazwie) wszędzie w budżecie: pozycje (oba
  /// zakresy) i koperty „Na bieżące wydatki" (oba zakresy). Zwraca liczbę zmienionych.
  Future<int> clearPaymentMethodEverywhere(String name) async {
    var affected = 0;
    var touchedHousehold = false;
    for (final scope in BudgetScope.values) {
      final entries = _storage
          .getBudgetEntries(scope)
          .where((e) => !e.deleted && e.paymentMethod == name)
          .toList();
      for (final e in entries) {
        await _saveStamped(e.copyWith(clearPaymentMethod: true), scope);
      }
      if (entries.isNotEmpty) {
        affected += entries.length;
        if (scope == BudgetScope.household) touchedHousehold = true;
      }
      final items = _storage.getSpendingAllocationItems(scope);
      final hit = items.where((i) => i.paymentMethod == name).length;
      if (hit > 0) {
        await _storage.setSpendingAllocationItems(
          scope,
          items
              .map(
                (i) => i.paymentMethod == name
                    ? i.copyWith(clearPaymentMethod: true)
                    : i,
              )
              .toList(),
        );
        affected += hit;
      }
    }
    if (affected > 0) _notifyMutation(touchedHousehold: touchedHousehold);
    return affected;
  }

  /// Suma realnych wydatków ([spending]) danego miesiąca w walucie docelowej.
  double spendingActualForMonth(String monthKey) =>
      _budget.spendingActualForMonth(all, monthKey, target: _target);

  // ── Statystyki (Plan): trendy i podział na kategorie ────────────────────────

  List<MonthlyDataPoint> get budgetExpenseTrend =>
      _budget.expenseTrend(all, _subsForScope, target: _target);

  /// Liczba aktywnych subskrypcji aktywnego zakresu (podsumowanie w karcie
  /// „Saldo" — subskrypcje są częścią kosztów cyklicznych).
  int get activeSubscriptionsCount =>
      _subsForScope.where((s) => s.isActive).length;

  /// Rozłączne serie wspólnego wykresu trendu (suma trzech = całość wydatków).
  /// [view] wybiera ujęcie: plan (kwoty bazowe + koperta) albo rzeczywistość
  /// (kwoty miesiąca z korektami + realne wydatki bieżące) — ADR-028.
  /// Wykres zaczyna się od początku ewidencji (ADR-029): wcześniejsze miesiące
  /// byłyby odtworzone z dzisiejszych kwot, czyli zmyślone.
  List<MonthlyDataPoint> recurringExpenseTrend(ExpenseView view) =>
      _budget.recurringExpenseTrend(
        all,
        view: view,
        fromMonth: trackingStartMonth,
        target: _target,
      );

  List<MonthlyDataPoint> subscriptionsTrend(ExpenseView view) =>
      _budget.subscriptionsTrend(
        _subsForScope,
        view: view,
        fromMonth: trackingStartMonth,
        target: _target,
      );

  List<MonthlyDataPoint> spendingTrend(ExpenseView view) =>
      _budget.spendingTrend(
        all,
        view: view,
        spendingAllocation: spendingAllocation ?? 0,
        fromMonth: trackingStartMonth,
        target: _target,
      );

  /// Początek ewidencji aktywnego zakresu („YYYY-MM") — `null` = cały rok.
  String? get trackingStartMonth => _storage.getTrackingStartMonth(_scope);

  Future<void> setTrackingStartMonth(String? monthKey) async {
    await _storage.setTrackingStartMonth(_scope, monthKey);
    notifyListeners();
  }

  /// Podsumowanie roku: ile z planu na te miesiące już wydano (ADR-029).
  /// Miesiące przed początkiem ewidencji nie liczą się po żadnej ze stron.
  YearExpenseSummary yearExpenseSummary(int year, ExpenseView view) {
    final start = trackingStartMonth;
    var fromMonth = 1;
    if (start != null && start.length >= 7) {
      final startYear = int.tryParse(start.substring(0, 4)) ?? year;
      if (startYear == year) {
        fromMonth = int.tryParse(start.substring(5, 7)) ?? 1;
      } else if (startYear > year) {
        fromMonth = 13; // ewidencja zaczyna się dopiero po tym roku
      }
    }
    return _budget.yearExpenseSummary(
      all,
      _subsForScope,
      year,
      view: view,
      fromMonth: fromMonth,
      spendingAllocation: _alloc,
      target: _target,
    );
  }

  /// Ile brakuje do okrągłej kwoty (10/100/1000) — dla „Uzupełnij do pełnej
  /// kwoty" w Plannerze. Bazy: sam plan albo wszystkie koszty miesięczne.
  double roundUpGap(double total, int step) => _budget.roundUpGap(total, step);

  Map<String, double> get expenseByCategory =>
      _budget.expenseBreakdownByCategory(all, target: _target);

  Map<String, double> spendingByCategory(String monthKey) =>
      _budget.spendingBreakdownByCategory(all, monthKey, target: _target);

  /// Podział całych wydatków miesiąca wg kategorii: cykliczne + subskrypcje
  /// + trzeci strumień zależny od ujęcia — koperta „Na bieżące wydatki" (plan) albo
  /// realne wydatki bieżące tego miesiąca (rzeczywistość), ADR-028.
  Map<String, double> combinedExpenseByCategory(
    String monthKey,
    ExpenseView view,
  ) => _budget.combinedExpenseBreakdownByCategory(
    all,
    _subsForScope,
    monthKey,
    view: view,
    allocationItems: spendingAllocationItems,
    target: _target,
  );

  /// Mapa „nazwa metody platnosci → automatyczna?" (do koloru/listy Platnosci).
  Map<String, bool> get _autoByPayment => {
    for (final pm in _storage.getPaymentMethods()) pm.name: pm.isAutomatic,
  };

  Map<int, DayCashflow> calendarForMonth(DateTime monthStart) =>
      _budget.calendarForMonth(
        all,
        _subsForScope,
        monthStart,
        target: _target,
        autoByPayment: _autoByPayment,
      );

  // ── Platnosci „wykonane" (lokalne, per zakres + zrodlo + data) ──────────────

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

  // ── CRUD (aktywny zakres) ──────────────────────────────────────────────────

  /// Zapis pozycji z odświeżeniem znacznika zmiany (`updatedAt`) — podstawa
  /// scalania przy synchronizacji domowego (ADR-009). Hurtowy zapis po scaleniu
  /// idzie osobną ścieżką ([StorageService.replaceBudgetEntries]), by zachować
  /// oryginalne znaczniki.
  Future<void> _saveStamped(BudgetEntry entry, BudgetScope scope) => _storage
      .saveBudgetEntry(entry.copyWith(updatedAt: DateTime.now()), scope);

  /// Zapis pozycji w aktywnym zakresie (używane m.in. przez import Excel).
  Future<void> add(BudgetEntry entry) async {
    await _saveStamped(entry, _scope);
    _log.info('Added budget entry ($_scope): ${entry.name}');
    _notifyMutation(touchedHousehold: _scope == BudgetScope.household);
  }

  Future<BudgetEntry> create({
    required String name,
    required BudgetEntryType type,
    required double amount,
    required Currency currency,
    BillingCycle cycle = BillingCycle.monthly,
    int? customCycleDays,
    List<int>? cycleMonths,
    String? month,
    String? categoryId,
    String? paymentMethod,
    Map<String, MonthAmountOverride>? monthOverrides,
    int? installmentCount,
    DateTime? startDate,
    String? note,
  }) async {
    final now = DateTime.now();

    // Przelew do domowego: para spięta linkId (osobisty wydatek + domowy wpływ).
    if (type == BudgetEntryType.householdTransfer) {
      final linkId = _uuid.v4();
      final personal = BudgetEntry(
        id: _uuid.v4(),
        name: name,
        type: BudgetEntryType.householdTransfer,
        amount: amount,
        currency: currency,
        cycle: cycle,
        customCycleDays: customCycleDays,
        cycleMonths: cycleMonths,
        startDate: startDate,
        monthOverrides: monthOverrides,
        note: note,
        dataDodania: now,
        linkId: linkId,
      );
      await _saveStamped(personal, BudgetScope.personal);
      final mirror = BudgetEntry(
        id: _uuid.v4(),
        name: name,
        type: BudgetEntryType.income,
        amount: amount,
        currency: currency,
        cycle: cycle,
        customCycleDays: customCycleDays,
        cycleMonths: cycleMonths,
        startDate: startDate,
        monthOverrides: monthOverrides,
        note: note ?? 'Z budżetu osobistego',
        dataDodania: now,
        linkId: linkId,
      );
      await _saveStamped(mirror, BudgetScope.household);
      _log.info('Created household transfer (link $linkId): $name');
      _notifyMutation(touchedHousehold: true); // lustro w domowym
      return personal;
    }

    // Karta kredytowa (ADR-033) — pozycje spięte `creditLinkId` powstają razem
    // ze źródłem, więc identyfikator musi być znany PRZED zapisem.
    final card = _creditCardFor(paymentMethod, type);
    final creditLinkId = card != null ? _uuid.v4() : null;

    final entry = BudgetEntry(
      id: _uuid.v4(),
      name: name,
      type: type,
      amount: amount,
      currency: currency,
      cycle: cycle,
      customCycleDays: customCycleDays,
      cycleMonths: cycleMonths,
      month: month,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      monthOverrides: monthOverrides,
      installmentCount: installmentCount,
      startDate: startDate,
      note: note,
      dataDodania: now,
      creditLinkId: creditLinkId,
    );
    await add(entry);
    // Wydatek z datą dzisiejszą lub wcześniejszą to log JUŻ zapłaconej
    // pozycji — oznaczamy go od razu jako wykonany, bez ręcznego odhaczania.
    // Wydatek z datą PRZYSZŁĄ to plan: zostaje nieodhaczony, żeby nie udawał
    // zapłaconego (ADR-018). Klucz musi zgadzać się z kalendarzem: sourceId=id,
    // data = dzień płatności (startDate; fallback pierwszy dzień miesiąca).
    if (type == BudgetEntryType.spending) {
      final payDate =
          startDate ??
          (month != null ? DateTime.tryParse('$month-01') : null) ??
          now;
      final today = DateTime(now.year, now.month, now.day);
      if (!DateTime(payDate.year, payDate.month, payDate.day).isAfter(today)) {
        await _storage.setPaymentDone(_paymentKey(entry.id, payDate), true);
      }
    }
    if (card != null) {
      await _createCreditEntries(entry, card, creditLinkId!, now);
    }
    return entry;
  }

  // ── Karta kredytowa (ADR-033) ──────────────────────────────────────────────

  /// Karta z gotowymi warunkami dla podanej metody — `null`, gdy metoda nie
  /// jest kartą, nie ma liczby dni albo typ pozycji nie pożycza pieniędzy.
  ///
  /// Automat obejmuje TYLKO wydatek bieżący i wpływ jednorazowy: koszt cykliczny
  /// czy rata rozkładają się na miesiące i doklejanie do nich spłaty rozjechałoby
  /// plan („zostaje/mies"), a nie sam bilans miesiąca.
  PaymentMethod? _creditCardFor(String? methodName, BudgetEntryType type) {
    if (methodName == null) return null;
    if (type != BudgetEntryType.spending &&
        type != BudgetEntryType.oneTimeIncome) {
      return null;
    }
    for (final pm in _storage.getPaymentMethods()) {
      if (pm.name == methodName) return pm.hasCreditTerms ? pm : null;
    }
    return null;
  }

  /// Dokłada pozycje, które sprawiają, że karta liczy się poprawnie.
  ///
  /// **Wpływ z karty** (pożyczka gotówkowa): dochodzi sama spłata za `graceDays`
  /// dni. Netto zero — wziąłeś i oddajesz.
  ///
  /// **Zakup kartą**: dochodzi lustrzany WPŁYW tego samego dnia (karta pożycza
  /// pieniądze) oraz spłata za `graceDays` dni. Bez tego wpływu ten sam zakup
  /// obciążyłby budżet DWA razy — raz jako zakup, raz jako spłata. Z nim miesiąc
  /// zakupu wychodzi na zero, a koszt ląduje tam, gdzie pieniądze naprawdę
  /// wychodzą z konta.
  Future<void> _createCreditEntries(
    BudgetEntry source,
    PaymentMethod card,
    String creditLinkId,
    DateTime now,
  ) async {
    final buyDate =
        source.startDate ??
        (source.month != null
            ? DateTime.tryParse('${source.month}-01')
            : null) ??
        now;
    final repayDate = buyDate.add(Duration(days: card.graceDays!));

    if (source.type == BudgetEntryType.spending) {
      await _saveStamped(
        BudgetEntry(
          id: _uuid.v4(),
          name: '${card.name}: ${source.name}',
          type: BudgetEntryType.oneTimeIncome,
          amount: source.amount,
          currency: source.currency,
          month: BudgetEntry.monthKeyOf(buyDate),
          startDate: buyDate,
          note: 'Karta pożycza na ten zakup — spłata ${_dayLabel(repayDate)}',
          dataDodania: now,
          creditLinkId: creditLinkId,
        ),
        _scope,
      );
    }

    await _saveStamped(
      BudgetEntry(
        id: _uuid.v4(),
        name: 'Spłata: ${source.name}',
        type: BudgetEntryType.spending,
        amount: source.amount,
        currency: source.currency,
        month: BudgetEntry.monthKeyOf(repayDate),
        startDate: repayDate,
        categoryId: source.categoryId,
        // Spłata dziedziczy kartę, żeby toggle „automatyczna" cokolwiek
        // znaczył. Oba przełączniki metody opisują RÓŻNE momenty: „karta
        // kredytowa" mówi o zakupie (karta pożycza), „automatyczna" — o tym,
        // czy SPŁATA schodzi sama. To spłatę można przegapić, więc to ona
        // decyduje, czy pozycja trafi na listę „Płatności" do odhaczenia.
        paymentMethod: card.name,
        note: '${card.name} — ${card.graceDays} dni od ${_dayLabel(buyDate)}',
        dataDodania: now,
        creditLinkId: creditLinkId,
      ),
      _scope,
    );

    _log.info(
      'Karta ${card.name}: pozycje splaty (link $creditLinkId) dla ${source.name}',
    );
    _notifyMutation(touchedHousehold: _scope == BudgetScope.household);
  }

  static String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Opis tego, co automat karty dołożył do właśnie zapisanej pozycji —
  /// `null`, gdy nic nie dołożył.
  ///
  /// Pozycje nie mogą pojawiać się po cichu: użytkownik wpisał JEDEN zakup,
  /// a na liście przybyły trzy. Bez komunikatu wyglądałoby to na błąd apki.
  String? creditSummaryFor(BudgetEntry entry) {
    final link = entry.creditLinkId;
    if (link == null) return null;
    final repayment = _storage
        .getBudgetEntries(_scope)
        .where(
          (e) =>
              e.creditLinkId == link &&
              e.id != entry.id &&
              e.type == BudgetEntryType.spending &&
              !e.deleted,
        )
        .firstOrNull;
    if (repayment?.startDate == null) return null;
    final day = _dayLabel(repayment!.startDate!);

    return entry.isIncome
        ? 'Dodano spłatę na $day. Pożyczka i spłata znoszą się — '
              'budżet obciąży dopiero spłata.'
        : 'Karta pożycza na ten zakup, więc ten miesiąc wychodzi na zero. '
              'Dodano spłatę na $day.';
  }

  Future<void> update(BudgetEntry entry) async {
    await _saveStamped(entry, _scope);
    // Kaskada na lustro w domowym (gdy edytujemy przelew w osobistym).
    if (entry.type == BudgetEntryType.householdTransfer &&
        entry.linkId != null) {
      final mirror = _findByLinkId(entry.linkId!, BudgetScope.household);
      if (mirror != null) {
        await _saveStamped(
          mirror.copyWith(
            name: entry.name,
            amount: entry.amount,
            cycle: entry.cycle,
            customCycleDays: entry.customCycleDays,
            clearCustomCycleDays: entry.customCycleDays == null,
            startDate: entry.startDate,
            clearStartDate: entry.startDate == null,
            isActive: entry.isActive,
            // Korekty kaskadują do lustra → bilans domowego zgodny z realnie przelaną kwotą.
            monthOverrides: entry.monthOverrides,
            clearMonthOverrides: entry.monthOverrides == null,
          ),
          BudgetScope.household,
        );
      }
    }
    // Kaskada karty (ADR-033): zmiana kwoty ŹRÓDŁA musi przejść na pożyczkę
    // i spłatę. Bez tego zakup na 200 poprawiony na 300 zostawiłby pożyczkę
    // 200 i spłatę 200 — miesiąc zakupu przestałby wychodzić na zero.
    //
    // Daty NIE przeliczamy: nie wiadomo, czy zmiana dnia zakupu ma przesunąć
    // termin spłaty (bank liczy od rozliczenia cyklu, nie od transakcji).
    // Zgadywanie byłoby gorsze niż zostawienie terminu, który użytkownik widzi
    // i może poprawić ręcznie.
    if (entry.creditLinkId != null && !entry.deleted) {
      await _cascadeCreditAmount(entry);
    }
    _log.info('Updated budget entry ($_scope): ${entry.name}');
    _notifyMutation(
      touchedHousehold:
          _scope == BudgetScope.household ||
          entry.type == BudgetEntryType.householdTransfer,
    );
  }

  /// Wyrównuje kwoty pozostałych pozycji tej samej operacji kartą.
  Future<void> _cascadeCreditAmount(BudgetEntry source) async {
    for (final e in _storage.getBudgetEntries(_scope)) {
      if (e.id == source.id || e.deleted) continue;
      if (e.creditLinkId != source.creditLinkId) continue;
      if (e.amount == source.amount) continue;
      await _saveStamped(e.copyWith(amount: source.amount), _scope);
    }
  }

  Future<void> delete(String id) async {
    final touchedHousehold = await _deleteOne(id);
    if (touchedHousehold == null) return;
    _log.info('Deleted budget entry ($_scope): $id');
    _notifyMutation(touchedHousehold: touchedHousehold);
  }

  /// Usuwa jedną pozycję razem z drugą stroną pary przelewu. Zwraca, czy
  /// zmiana dotknęła budżetu domowego, albo `null` gdy pozycji nie było.
  Future<bool?> _deleteOne(String id) async {
    final entry = _storage.getBudgetEntry(id, _scope);
    if (entry == null) return null;
    await _removeOrTombstone(entry, _scope);
    // Kaskada: usuń drugą stronę pary przelewu (w przeciwnym boxie).
    if (entry.linkId != null) {
      final other = _scope == BudgetScope.personal
          ? BudgetScope.household
          : BudgetScope.personal;
      final partner = _findByLinkId(entry.linkId!, other);
      if (partner != null) {
        await _removeOrTombstone(partner, other);
      }
    }
    // Kaskada karty (ADR-033): pozycje jednej operacji leżą w TYM SAMYM boxie.
    // Zostawienie choćby jednej rozjechałoby bilans — sama spłata bez zakupu to
    // wydatek znikąd, sam wpływ z karty to pieniądze, których nikt nie oddaje.
    final creditLink = entry.creditLinkId;
    if (creditLink != null) {
      for (final e in _storage.getBudgetEntries(_scope)) {
        if (e.id == entry.id || e.deleted) continue;
        if (e.creditLinkId == creditLink) {
          await _removeOrTombstone(e, _scope);
        }
      }
    }
    return _scope == BudgetScope.household || entry.linkId != null;
  }

  // ── Operacje zbiorcze (zaznaczanie wielu pozycji) ──────────────────────────
  //
  // Wszystkie kończą się JEDNYM powiadomieniem: przy kilkudziesięciu
  // zaznaczonych pozycjach lista przebudowywałaby się inaczej tyle razy, ile
  // jest zaznaczeń, a synchronizacja domowa ruszałaby po każdej z nich.

  /// Ustawia kategorię (albo ją czyści) wielu pozycjom. Zwraca liczbę zmienionych.
  Future<int> setCategoryForAll(Iterable<String> ids, String? categoryId) =>
      _updateAll(
        ids,
        (e) => e.copyWith(
          categoryId: categoryId,
          clearCategoryId: categoryId == null,
        ),
      );

  /// Ustawia metodę płatności (albo ją czyści) wielu pozycjom.
  Future<int> setPaymentMethodForAll(Iterable<String> ids, String? method) =>
      _updateAll(
        ids,
        (e) => e.copyWith(
          paymentMethod: method,
          clearPaymentMethod: method == null,
        ),
      );

  /// Wstrzymuje albo wznawia wiele pozycji naraz. Wstrzymana pozycja zostaje
  /// w danych, ale wypada z planu — na liście widać ją dopiero po „pokaż ukryte".
  Future<int> setActiveForAll(Iterable<String> ids, bool active) =>
      _updateAll(ids, (e) => e.copyWith(isActive: active));

  /// Ustawia datę wielu pozycjom datowanym (wydatki bieżące).
  ///
  /// Data wydatku wyznacza jego MIESIĄC, więc ta operacja przenosi pozycje
  /// między bilansami miesięcy — i dlatego musi zabrać ze sobą **odhaczenie
  /// płatności**, którego klucz zawiera datę. Bez tego wydatek po zmianie daty
  /// po cichu wracałby na listę „do zapłaty".
  Future<int> setDateForAll(Iterable<String> ids, DateTime date) async {
    var changed = 0;
    for (final id in ids) {
      final entry = _storage.getBudgetEntry(id, _scope);
      if (entry == null) continue;
      final oldDate = entry.startDate ?? entry.dataDodania;
      final wasDone = _storage.isPaymentDone(_paymentKey(id, oldDate));
      await _saveStamped(
        entry.copyWith(startDate: date, month: BudgetEntry.monthKeyOf(date)),
        _scope,
      );
      if (wasDone) {
        await _storage.setPaymentDone(_paymentKey(id, oldDate), false);
        await _storage.setPaymentDone(_paymentKey(id, date), true);
      }
      changed++;
    }
    if (changed > 0) {
      _log.info('Zbiorcza zmiana daty: $changed pozycji ($_scope)');
      _notifyMutation(touchedHousehold: isHousehold);
    }
    return changed;
  }

  /// Usuwa wiele pozycji naraz (z nagrobkami w domowym, jak pojedyncze
  /// usunięcie). Zdjęcia wydatków kasuje wołający — mieszkają poza budżetem.
  Future<int> deleteAll(Iterable<String> ids) async {
    var changed = 0;
    var touchedHousehold = false;
    for (final id in ids) {
      final touched = await _deleteOne(id);
      if (touched == null) continue;
      touchedHousehold = touchedHousehold || touched;
      changed++;
    }
    if (changed > 0) {
      _log.info('Zbiorcze usuniecie: $changed pozycji ($_scope)');
      _notifyMutation(touchedHousehold: touchedHousehold);
    }
    return changed;
  }

  /// Scala kilka wydatków bieżących w JEDNĄ nową pozycję i usuwa źródłowe.
  /// Zwraca scaloną pozycję albo `null`, gdy scalanie jest niedozwolone.
  ///
  /// **Kolejność jest celowa:** najpierw powstaje scalona pozycja, dopiero
  /// potem znikają źródła. Gdyby kasowanie padło w połowie, na liście zostaje
  /// nadmiar wierszy — widoczny i do posprzątania ręcznie. Odwrotna kolejność
  /// gubiłaby pieniądze bez żadnego śladu.
  ///
  /// **Pozycje spięte są odrzucane.** Wydatek z `creditLinkId` (karta
  /// kredytowa, ADR-033) kasuje się KASKADOWO razem z zakupem i lustrzanym
  /// wpływem, a `linkId` z drugą stroną przelewu — scalanie zjadłoby wtedy
  /// dane, których użytkownik nie zaznaczył.
  ///
  /// Źródła czytamy ponownie z bazy: między zaznaczeniem a zapisem mogła wejść
  /// synchronizacja. Gdy zostanie mniej niż dwie pozycje, scalanie nie ma czego
  /// scalić i nic się nie dzieje.
  Future<BudgetEntry?> mergeSpendings({
    required Iterable<String> sourceIds,
    required String name,
    required double amount,
    required Currency currency,
    required DateTime date,
    String? categoryId,
    String? paymentMethod,
    String? note,
  }) async {
    final sources = <BudgetEntry>[];
    for (final id in sourceIds.toSet()) {
      final entry = _storage.getBudgetEntry(id, _scope);
      if (entry != null && !entry.deleted) sources.add(entry);
    }
    if (sources.length < 2) {
      _log.warning('Scalanie przerwane: mniej niz dwie pozycje zrodlowe');
      return null;
    }
    if (sources.any((e) => e.creditLinkId != null || e.linkId != null)) {
      _log.warning('Scalanie przerwane: pozycja spieta (karta/przelew)');
      return null;
    }

    final merged = await create(
      name: name,
      type: BudgetEntryType.spending,
      amount: amount,
      currency: currency,
      month: BudgetEntry.monthKeyOf(date),
      startDate: date,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      note: note,
    );
    await deleteAll(sources.map((e) => e.id));
    _log.info('Scalono ${sources.length} wydatkow w "$name" ($_scope)');
    return merged;
  }

  Future<int> _updateAll(
    Iterable<String> ids,
    BudgetEntry Function(BudgetEntry) change,
  ) async {
    var changed = 0;
    for (final id in ids) {
      final entry = _storage.getBudgetEntry(id, _scope);
      if (entry == null) continue;
      await _saveStamped(change(entry), _scope);
      changed++;
    }
    if (changed > 0) _notifyMutation(touchedHousehold: isHousehold);
    return changed;
  }

  /// Przenosi pozycję do drugiego budżetu (osobisty ↔ domowy). Zwraca `null`
  /// przy powodzeniu albo komunikat, dlaczego się nie da.
  ///
  /// Zakres nie jest polem pozycji, tylko wynika z pudełka, w którym leży —
  /// przeniesienie to zapis w nowym i usunięcie ze starego. Trzy rzeczy, które
  /// muszą pójść razem z nią:
  ///
  /// 1. **Nagrobek przy wyjściu z domowego.** Domowy kasuje przez `deleted`,
  ///    więc zwykłe wyjęcie rekordu skończyłoby się przywróceniem pozycji
  ///    z serwera przy najbliższej synchronizacji — i liczeniem jej w obu
  ///    budżetach naraz.
  /// 2. **Zdjęcie wydatku**, trzymane poza pozycją (mapa po `id`).
  /// 3. **Odhaczenie płatności**, którego klucz zawiera zakres ORAZ `id`.
  ///
  /// Nowe `id` jest celowe: nagrobek zostaje przy starym, więc pozycja nie ma
  /// jak się z nim zderzyć, gdyby kiedyś wróciła.
  Future<String?> moveToScope(String id) async {
    final from = _scope;
    final to = from == BudgetScope.personal
        ? BudgetScope.household
        : BudgetScope.personal;

    final entry = _storage.getBudgetEntry(id, from);
    if (entry == null) return 'Nie znaleziono pozycji do przeniesienia.';
    // Przelew między budżetami to PARA (pozycja + lustro spięte linkId) —
    // przeniesienie jednej strony rozspoiłoby ją z drugą.
    if (entry.linkId != null) {
      return 'Przelewu między budżetami nie da się przenieść — usuń go '
          'i dodaj w docelowym budżecie.';
    }

    final newId = _uuid.v4();
    final moved = entry.copyWith(
      id: newId,
      updatedAt: DateTime.now(),
      deleted: false,
    );
    await _storage.saveBudgetEntry(moved, to);
    await _removeOrTombstone(entry, from);

    final photo = _storage.getReceiptPhotoPath(id);
    if (photo != null) {
      await _storage.setReceiptPhotoPath(newId, photo);
      await _storage.removeReceiptPhotoPath(id);
    }
    await _storage.movePaymentDone('${from.name}|$id|', '${to.name}|$newId|');

    _log.info('Przeniesiono pozycję $id ($from) -> $newId ($to)');
    // Domowy jest po stronie zmiany zawsze: albo tam trafia pozycja, albo
    // zostaje w nim nagrobek do wysłania.
    _notifyMutation(touchedHousehold: true);
    return null;
  }

  /// Usuwa pozycję: domowy zostawia **nagrobek** (deleted=true), by usunięcie
  /// propagowało się przy synchronizacji; osobisty kasuje twardo (brak sync).
  Future<void> _removeOrTombstone(BudgetEntry entry, BudgetScope scope) async {
    if (scope == BudgetScope.household) {
      await _saveStamped(entry.copyWith(deleted: true), scope);
    } else {
      await _storage.deleteBudgetEntry(entry.id, scope);
    }
  }

  Future<void> toggleActive(String id) async {
    final entry = _storage.getBudgetEntry(id, _scope);
    if (entry == null) return;
    await update(entry.copyWith(isActive: !entry.isActive));
  }

  BudgetEntry? _findByLinkId(String linkId, BudgetScope scope) {
    for (final e in _storage.getBudgetEntries(scope)) {
      if (e.linkId == linkId && !e.deleted) return e;
    }
    return null;
  }
}
