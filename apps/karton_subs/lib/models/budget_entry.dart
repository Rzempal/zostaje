import 'subscription.dart' show BillingCycle, Currency;
import '../utils/cycle_math.dart';

/// Typ pozycji budżetu — domowe przepływy pieniężne.
enum BudgetEntryType {
  /// Wpływ cykliczny (np. pensja).
  income,

  /// Koszt cykliczny (np. czynsz, prąd, internet, ubezpieczenie, karnet).
  /// Obsługuje opcjonalne korekty miesięczne ([monthOverrides]): kwota bazowa =
  /// plan (wchodzi w „zostaje/mies"), korekta = realna kwota danego miesiąca
  /// (bilans + kalendarz). Patrz [ADR-008]. Scalony z dawnym `bill`.
  recurringCost,

  /// Wydatek bieżący — datowany wydatek jednorazowy: opłacony (log) albo
  /// zaplanowany na przyszłą datę. Zasila **bilans miesiąca**, a NIE plan
  /// („zostaje/mies"); zgadywankę planu dla tej puli pełni koperta
  /// „Na bieżące wydatki". Sekcja w UI: „Bieżące" (ADR-032).
  ///
  /// Scalony z dawnym `oneTimeExpense` (ADR-018): oba typy liczyły się
  /// identycznie, a rozróżnienie „wydatek vs większy zakup" lepiej nosi
  /// kategoria. Stare pozycje `"type":"oneTimeExpense"` czyta [typeFromName].
  ///
  /// Na dysk idzie jako `billPayment` — patrz [_typeWireNames].
  spending,

  /// Wpływ jednorazowy (np. premia, bonus) — przypięty do konkretnej daty.
  oneTimeIncome,

  /// Przelew do budżetu domowego — koszt w osobistym; tworzy lustrzany wpływ
  /// (`income`) w domowym (spięty przez `linkId`). Występuje tylko w osobistym.
  householdTransfer,

  /// Rata — koszt miesięczny z określonym końcem (start + liczba rat). Liczy się
  /// do „zostaje/mies" tylko w trakcie spłaty; po ostatniej racie znika.
  installment,
}

/// Wartości pola `type` W ZAPISIE: baza Hive, kopie `.zostaje` i **paczki
/// synchronizacji budżetu domowego**. Odcięte od nazw w kodzie celowo (ADR-032)
/// — nazwę w Darcie wolno zmieniać, wartość tutaj nie.
///
/// Najostrzejszy przypadek to synchronizacja: dwa telefony aktualizują się
/// w różnym czasie, więc telefon na starszej wersji musi dalej rozumieć paczkę
/// z nowszego. Zmiana wartości = pozycje znikają drugiej osobie.
///
/// Pilnuje tego `test/storage_format_guard_test.dart`.
const Map<BudgetEntryType, String> _typeWireNames = {
  BudgetEntryType.income: 'income',
  BudgetEntryType.recurringCost: 'recurringCost',
  // Wartość z czasów, gdy sekcja nazywała się „Rachunki" (dziś „Bieżące").
  BudgetEntryType.spending: 'billPayment',
  BudgetEntryType.oneTimeIncome: 'oneTimeIncome',
  BudgetEntryType.householdTransfer: 'householdTransfer',
  BudgetEntryType.installment: 'installment',
};

extension BudgetEntryTypeWire on BudgetEntryType {
  /// Wartość zapisywana na dysk — używaj TEGO zamiast [name] wszędzie, gdzie
  /// typ trafia do JSON-a. Patrz [_typeWireNames].
  String get wireName => _typeWireNames[this]!;
}

/// Zakres STAREGO budżetu (archiwum sprzed ADR-035): osobny box na osobisty
/// i domowy. Plan i subskrypcje używają budżetów z nazwami (ADR-037);
/// dawny „tryb budżetu" zastąpiło ukrywanie budżetów — jego zapis
/// (`budgetMode`) czyta już tylko `StorageService.getBudgets` przy pierwszym
/// uruchomieniu.
enum BudgetScope { personal, household }

/// Korekta pozycji cyklicznej ([BudgetEntryType.recurringCost]) lub przelewu do
/// domowego dla konkretnego miesiąca.
///
/// Pozycja ma kwotę bazową i cykl jako domyślne; korekta nadpisuje je dla
/// danego miesiąca: [amount] zmienia kwotę (bilans + kalendarz), [date] zmienia
/// dzień wystąpienia (kalendarz). Pola opcjonalne — `null` = użyj wartości bazowej.
/// Patrz [ADR-008]. Korekty NIE wpływają na „zostaje miesięcznie" (surplus).
class MonthAmountOverride {
  final double? amount;
  final DateTime? date;

  const MonthAmountOverride({this.amount, this.date});

  /// Pusta korekta (oba pola null) — traktowana jak brak korekty.
  bool get isEmpty => amount == null && date == null;

  factory MonthAmountOverride.fromJson(Map<String, dynamic> json) =>
      MonthAmountOverride(
        amount: (json['amount'] as num?)?.toDouble(),
        date: json['date'] != null
            ? DateTime.parse(json['date'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
    if (amount != null) 'amount': amount,
    if (date != null) 'date': date!.toIso8601String(),
  };

  MonthAmountOverride copyWith({
    double? amount,
    bool clearAmount = false,
    DateTime? date,
    bool clearDate = false,
  }) => MonthAmountOverride(
    amount: clearAmount ? null : (amount ?? this.amount),
    date: clearDate ? null : (date ?? this.date),
  );
}

/// Pozycja budżetu domowego.
///
/// Jeden model dla wpływów i wydatków. Typy cykliczne (income/recurringCost)
/// są normalizowane do kwoty miesięcznej; [oneTimeExpense] i [spending] nie
/// wchodzą do średniej miesięcznej, tylko obciążają bilans wskazanego miesiąca.
///
/// Subskrypcje są osobnym modułem ([Subscription]) — budżet czyta je dodatkowo
/// jako strumień kosztów (patrz `BudgetService`).
class BudgetEntry {
  final String id;
  final String name;
  final BudgetEntryType type;
  final double amount;
  final Currency currency;

  /// Cykl rozliczeniowy — używany przez typy cykliczne. Dla [oneTimeExpense]
  /// pole jest ignorowane (zachowane dla spójności serializacji).
  final BillingCycle cycle;
  final int? customCycleDays;

  /// Miesiace platnosci dla [BillingCycle.monthsOfYear] (1..12), np. [1, 4, 9].
  /// Ignorowane przy pozostalych cyklach; brak = zachowanie jak dotad (ADR-020).
  final List<int>? cycleMonths;

  /// Miesiąc przypisania w formacie "YYYY-MM" — dla [oneTimeExpense] i [spending].
  final String? month;

  /// Korekty miesięczne — dla [BudgetEntryType.recurringCost] i [householdTransfer].
  /// Klucz = "YYYY-MM". Nadpisują kwotę/datę danego miesiąca; nie ruszają surplus.
  /// Patrz [ADR-008].
  final Map<String, MonthAmountOverride>? monthOverrides;

  final String? categoryId;

  /// Metoda płatności (po nazwie, jak w [Subscription]). Decyduje o trybie
  /// auto/manual (przez [PaymentMethod.isAutomatic]) — kolor na kalendarzu i
  /// lista „Płatności". `null` = brak metody = traktowane jako manualne.
  final String? paymentMethod;

  /// Liczba rat — tylko dla [BudgetEntryType.installment]. Start = [startDate].
  final int? installmentCount;

  /// Data rozpoczęcia (typy cykliczne) — na przyszłe rekonstrukcje trendu.
  /// Dla [installment]: data pierwszej raty.
  final DateTime? startDate;

  /// Czy pozycja jest aktywna (wstrzymane wpływy/koszty nie liczą się do sumy).
  final bool isActive;

  final String? note;
  final DateTime dataDodania;

  /// Spina parę przelew↔wkład między budżetem osobistym a domowym.
  /// Ustawione na obu pozycjach (ten sam identyfikator).
  final String? linkId;

  /// Spina pozycje jednej operacji kartą kredytową (ADR-033): źródło (zakup
  /// albo pożyczka), lustrzany wpływ z karty i spłatę po okresie bezodsetkowym.
  ///
  /// **Osobne pole, a nie [linkId]**, bo to inna relacja: [linkId] łączy dwa
  /// RÓŻNE zakresy (osobisty ↔ domowy), a te pozycje siedzą w JEDNYM. Kaskady
  /// szukają partnera po przeciwnej stronie, więc wspólne pole gubiłoby jedną
  /// z dwóch relacji.
  final String? creditLinkId;

  /// Znacznik ostatniej zmiany pozycji — podstawa scalania przy synchronizacji
  /// budżetu domowego (Last-Write-Wins per pozycja, ADR-009). `null` dla starych
  /// danych sprzed synchronizacji — patrz [effectiveUpdatedAt].
  final DateTime? updatedAt;

  /// Nagrobek (tombstone): pozycja usunięta, ale zachowana, by usunięcie
  /// propagowało się do drugiego urządzenia przy synchronizacji (ADR-009).
  /// Pozycje z `deleted == true` są pomijane w UI i agregatach. Domyślnie `false`.
  final bool deleted;

  const BudgetEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.currency,
    this.cycle = BillingCycle.monthly,
    this.customCycleDays,
    this.cycleMonths,
    this.month,
    this.monthOverrides,
    this.categoryId,
    this.paymentMethod,
    this.installmentCount,
    this.startDate,
    this.isActive = true,
    this.note,
    required this.dataDodania,
    this.linkId,
    this.creditLinkId,
    this.updatedAt,
    this.deleted = false,
  });

  /// Czy to pozycja powiazana (lustro przelewu) — w domowym tylko do odczytu.
  bool get isLinked => linkId != null;

  /// Znacznik ostatniej zmiany dla potrzeb scalania (LWW). Stare pozycje bez
  /// [updatedAt] traktujemy jak zmienione w chwili dodania ([dataDodania]).
  DateTime get effectiveUpdatedAt => updatedAt ?? dataDodania;

  /// Czy typ obsługuje korekty miesięczne (koszt cykliczny + przelew do domowego).
  bool get supportsMonthOverrides =>
      type == BudgetEntryType.recurringCost ||
      type == BudgetEntryType.householdTransfer;

  /// Korekta wskazanego miesiąca ("YYYY-MM") lub `null`.
  MonthAmountOverride? overrideForMonth(String monthKey) =>
      monthOverrides?[monthKey];

  /// Kwota dla wskazanego miesiąca: korekta (jeśli ustawiona) lub kwota bazowa.
  /// Dotyczy wydatku; dla pozostałych typów zwraca [amount].
  double amountForMonth(String monthKey) =>
      overrideForMonth(monthKey)?.amount ?? amount;

  bool get isInstallment => type == BudgetEntryType.installment;

  /// Data ostatniej raty = start + (liczba rat − 1) miesięcy. `null` gdy brak danych.
  DateTime? get lastInstallmentDate {
    final s = startDate;
    final n = installmentCount;
    if (!isInstallment || s == null || n == null || n <= 0) return null;
    return DateTime(s.year, s.month + n - 1, s.day);
  }

  /// Czy rata jest aktywna w miesiącu danej daty (miesiąc w oknie [start … ostatnia]).
  bool isInstallmentActiveOn(DateTime date) {
    final s = startDate;
    final last = lastInstallmentDate;
    if (s == null || last == null) return false;
    final m = DateTime(date.year, date.month);
    final from = DateTime(s.year, s.month);
    final to = DateTime(last.year, last.month);
    return !m.isBefore(from) && !m.isAfter(to);
  }

  /// Jak [isInstallmentActiveOn], ale po kluczu miesiąca "YYYY-MM".
  bool isInstallmentActiveInMonth(String monthKey) {
    final d = DateTime.tryParse('$monthKey-01');
    return d != null && isInstallmentActiveOn(d);
  }

  /// Czy pozycja należy do snapshotu miesiąca "YYYY-MM" (filtr czasu w Budżecie):
  /// jednorazowa — gdy przypisana do tego miesiąca; rata — gdy aktywna w oknie
  /// spłaty; pozostałe cykliczne — zawsze (dotyczą każdego miesiąca).
  bool appliesToMonth(String monthKey) {
    if (isOneTime) return month == monthKey;
    if (isInstallment) return isInstallmentActiveInMonth(monthKey);
    return true;
  }

  bool get isIncome =>
      type == BudgetEntryType.income || type == BudgetEntryType.oneTimeIncome;
  bool get isOneTime =>
      type == BudgetEntryType.oneTimeIncome || type == BudgetEntryType.spending;
  bool get isExpense => !isIncome;

  /// Kwota znormalizowana do miesięcznej (bez znaku).
  /// Zwraca 0 dla wydatków jednorazowych — te obciążają konkretny miesiąc,
  /// a nie średnią miesięczną.
  double get monthlyAmount {
    if (isOneTime) return 0;
    return monthlyFromCycle(
      amount,
      cycle,
      customCycleDays,
      cycleMonths: cycleMonths,
    );
  }

  /// Miesięczny wpływ na budżet ze znakiem: wpływy `+`, koszty `-`,
  /// jednorazowe `0` (liczone osobno, per miesiąc).
  double get signedMonthlyAmount {
    if (isOneTime) return 0;
    return isIncome ? monthlyAmount : -monthlyAmount;
  }

  /// Klucz miesiąca ("YYYY-MM") dla podanej daty.
  static String monthKeyOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  /// Typ z zapisanej nazwy — z jawnym mapowaniem typów SCALONYCH.
  ///
  /// Bez tego mapowania każdy stary „Wydatek jednorazowy" wpadłby w domyślny
  /// `recurringCost` i zacząłby obciążać plan („zostaje/mies") co miesiąc.
  /// Dotyczy naraz bazy lokalnej, backupu i synchronizacji domowej.
  static BudgetEntryType typeFromName(String? raw) {
    if (raw == 'oneTimeExpense') return BudgetEntryType.spending; // ADR-018
    if (raw == 'bill') return BudgetEntryType.recurringCost; // ADR-011
    return BudgetEntryType.values.firstWhere(
      (t) => t.wireName == raw,
      orElse: () => BudgetEntryType.recurringCost,
    );
  }

  factory BudgetEntry.fromJson(Map<String, dynamic> json) {
    return BudgetEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      type: typeFromName(json['type'] as String?),
      amount: (json['amount'] as num).toDouble(),
      currency: Currency.values.firstWhere(
        (c) => c.name == json['currency'],
        orElse: () => Currency.PLN,
      ),
      cycle: BillingCycle.values.firstWhere(
        (b) => b.name == json['cycle'],
        orElse: () => BillingCycle.monthly,
      ),
      customCycleDays: json['customCycleDays'] as int?,
      cycleMonths: (json['cycleMonths'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      month: json['month'] as String?,
      monthOverrides: (json['monthOverrides'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(
          k,
          MonthAmountOverride.fromJson(v as Map<String, dynamic>),
        ),
      ),
      categoryId: json['categoryId'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      installmentCount: (json['installmentCount'] as num?)?.toInt(),
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
      note: json['note'] as String?,
      dataDodania: DateTime.parse(json['dataDodania'] as String),
      linkId: json['linkId'] as String?,
      creditLinkId: json['creditLinkId'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      deleted: json['deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.wireName,
    'amount': amount,
    'currency': currency.name,
    'cycle': cycle.name,
    if (customCycleDays != null) 'customCycleDays': customCycleDays,
    if (cycleMonths != null) 'cycleMonths': cycleMonths,
    if (month != null) 'month': month,
    if (monthOverrides != null && monthOverrides!.isNotEmpty)
      'monthOverrides': {
        for (final e in monthOverrides!.entries) e.key: e.value.toJson(),
      },
    if (categoryId != null) 'categoryId': categoryId,
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
    if (installmentCount != null) 'installmentCount': installmentCount,
    if (startDate != null) 'startDate': startDate!.toIso8601String(),
    'isActive': isActive,
    if (note != null) 'note': note,
    'dataDodania': dataDodania.toIso8601String(),
    if (linkId != null) 'linkId': linkId,
    if (creditLinkId != null) 'creditLinkId': creditLinkId,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (deleted) 'deleted': true,
  };

  BudgetEntry copyWith({
    String? id,
    String? name,
    BudgetEntryType? type,
    double? amount,
    Currency? currency,
    BillingCycle? cycle,
    int? customCycleDays,
    bool clearCustomCycleDays = false,
    List<int>? cycleMonths,
    bool clearCycleMonths = false,
    String? month,
    bool clearMonth = false,
    Map<String, MonthAmountOverride>? monthOverrides,
    bool clearMonthOverrides = false,
    String? categoryId,
    bool clearCategoryId = false,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    int? installmentCount,
    bool clearInstallmentCount = false,
    DateTime? startDate,
    bool clearStartDate = false,
    bool? isActive,
    String? note,
    bool clearNote = false,
    DateTime? dataDodania,
    String? linkId,
    bool clearLinkId = false,
    String? creditLinkId,
    bool clearCreditLinkId = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
    bool? deleted,
  }) {
    return BudgetEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      cycle: cycle ?? this.cycle,
      customCycleDays: clearCustomCycleDays
          ? null
          : (customCycleDays ?? this.customCycleDays),
      cycleMonths: clearCycleMonths ? null : (cycleMonths ?? this.cycleMonths),
      month: clearMonth ? null : (month ?? this.month),
      monthOverrides: clearMonthOverrides
          ? null
          : (monthOverrides ?? this.monthOverrides),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      paymentMethod: clearPaymentMethod
          ? null
          : (paymentMethod ?? this.paymentMethod),
      installmentCount: clearInstallmentCount
          ? null
          : (installmentCount ?? this.installmentCount),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      isActive: isActive ?? this.isActive,
      note: clearNote ? null : (note ?? this.note),
      dataDodania: dataDodania ?? this.dataDodania,
      linkId: clearLinkId ? null : (linkId ?? this.linkId),
      creditLinkId: clearCreditLinkId
          ? null
          : (creditLinkId ?? this.creditLinkId),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
      deleted: deleted ?? this.deleted,
    );
  }
}
