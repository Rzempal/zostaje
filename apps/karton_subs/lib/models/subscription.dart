import '../utils/cycle_math.dart';
import 'usage_event.dart';

/// Cykl rozliczeniowy. [monthsOfYear] to wzor roczny — platnosc w wybranych
/// miesiacach (pole `cycleMonths`), np. [1, 4, 9]. Pokrywa tez „co N miesiecy"
/// dla N dzielacego 12: co 2 = szesc miesiecy, co 4 = trzy, co pol roku = dwa
/// (ADR-020). Odstepy istniejace wczesniej (miesiecznie, kwartalnie, rocznie)
/// zostaja jako wlasne wartosci — jeden wzor ma miec jeden zapis.
enum BillingCycle { weekly, monthly, quarterly, yearly, monthsOfYear, custom }

// ignore: constant_identifier_names
enum Currency {
  // ignore: constant_identifier_names
  PLN,
  // ignore: constant_identifier_names
  EUR,
  // ignore: constant_identifier_names
  USD,
  // ignore: constant_identifier_names
  GBP;

  String get symbol {
    switch (this) {
      case Currency.PLN:
        return 'zł';
      case Currency.EUR:
        return 'EUR';
      case Currency.USD:
        return '\$';
      case Currency.GBP:
        return '£';
    }
  }

  String get label {
    switch (this) {
      case Currency.PLN:
        return 'PLN';
      case Currency.EUR:
        return 'EUR';
      case Currency.USD:
        return 'USD';
      case Currency.GBP:
        return 'GBP';
    }
  }
}


class Subscription {
  /// Dev-only: override DateTime.now() do testowania ghost detection
  static DateTime? devDateOverride;
  static DateTime get _now => devDateOverride ?? DateTime.now();

  final String id;
  final String name;
  final String? description;
  final double amount;
  final Currency currency;
  final BillingCycle billingCycle;
  final int? customCycleDays;

  /// Miesiace platnosci dla [BillingCycle.monthsOfYear] (1..12), np. [1, 4, 9].
  /// Ignorowane przy pozostalych cyklach; brak = zachowanie jak dotad.
  final List<int>? cycleMonths;

  final String? categoryId;
  final DateTime startDate;
  final String? cancellationUrl;
  final String? iconName;
  final String? colorHex;
  final bool isPinned;
  final bool isActive;
  final int? reminderDaysBefore;
  final List<UsageEvent> usageLog;
  final DateTime dataDodania;
  final DateTime? cancelledDate;
  final int? sharedWith;
  final String? paymentMethod;
  final bool isTrial;
  final DateTime? trialEndDate;
  final double? postTrialAmount;

  /// Budżet subskrypcji (ADR-037) — identyfikator z listy budżetów.
  final String budgetId;

  const Subscription({
    required this.id,
    required this.name,
    this.description,
    required this.amount,
    required this.currency,
    required this.billingCycle,
    this.customCycleDays,
    this.cycleMonths,
    this.categoryId,
    required this.startDate,
    this.cancellationUrl,
    this.iconName,
    this.colorHex,
    this.isPinned = false,
    this.isActive = true,
    this.reminderDaysBefore,
    this.usageLog = const [],
    required this.dataDodania,
    this.cancelledDate,
    this.sharedWith,
    this.paymentMethod,
    this.isTrial = false,
    this.trialEndDate,
    this.postTrialAmount,
    this.budgetId = 'personal',
  });

  /// Pełna kwota znormalizowana do miesięcznej (bez podziału)
  double get monthlyAmountFull => _monthlyFromAmount(amount);

  /// Kwota miesięczna po podziale na współdzielących.
  /// Zwraca 0 dla aktywnych triali (jeszcze nie płacisz).
  double get monthlyAmount {
    if (isTrialActive) return 0;
    final full = monthlyAmountFull;
    if (sharedWith != null && sharedWith! > 1) return full / sharedWith!;
    return full;
  }

  double get yearlyAmount => monthlyAmount * 12;

  /// Następna data odnowienia (computed z startDate + billingCycle)
  DateTime get nextRenewalDate {
    var next = startDate;
    final now = _now;
    // Wzor roczny (wybrane miesiace) nie da sie policzyc krokiem stalej
    // dlugosci — bierzemy pierwsze wystapienie z projekcji na dwa lata w przod.
    if (billingCycle == BillingCycle.monthsOfYear) {
      final upcoming = occurrencesInRange(
        startDate,
        billingCycle,
        customCycleDays,
        now,
        DateTime(now.year + 2, now.month, now.day),
        cycleMonths: cycleMonths,
      );
      return upcoming.isNotEmpty ? upcoming.first : startDate;
    }
    while (next.isBefore(now)) {
      switch (billingCycle) {
        case BillingCycle.weekly:
          next = next.add(const Duration(days: 7));
        case BillingCycle.monthly:
          next = DateTime(next.year, next.month + 1, next.day);
        case BillingCycle.quarterly:
          next = DateTime(next.year, next.month + 3, next.day);
        case BillingCycle.yearly:
          next = DateTime(next.year + 1, next.month, next.day);
        case BillingCycle.monthsOfYear:
          break; // obsluzone wyzej
        case BillingCycle.custom:
          next = next.add(Duration(days: customCycleDays ?? 30));
      }
    }
    return next;
  }

  /// Dni do odnowienia
  int get daysUntilRenewal => nextRenewalDate.difference(_now).inDays;

  /// Czy odnowienie jest bliskie
  bool get isRenewalSoon =>
      isActive && daysUntilRenewal <= (reminderDaysBefore ?? 3);

  int? get daysSinceLastUse {
    if (usageLog.isEmpty) return null;
    final last = usageLog.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    return _now.difference(last.date).inDays;
  }

  /// Ghost: aktywna, opłacana, ale nieużywana > 30 dni
  bool get isGhost {
    if (!isActive) return false;
    final days = daysSinceLastUse;
    if (days == null) return false;
    return days > 30;
  }

  double? get costPerUse {
    if (usageLog.isEmpty) return null;
    final months = _now.difference(startDate).inDays / 30;
    if (months <= 0) return null;
    return (monthlyAmount * months) / usageLog.length;
  }

  // ── Trial ───────────────────────────────────────────────────────────────

  /// Czy trial jest aktywny (jeszcze nie wygasł)
  bool get isTrialActive =>
      isTrial && trialEndDate != null && !trialEndDate!.isBefore(_now);

  /// Czy trial wygasł (data minęła, ale isTrial nadal true)
  bool get isTrialExpired =>
      isTrial && trialEndDate != null && trialEndDate!.isBefore(_now);

  /// Dni do końca triala (null jeśli nie trial)
  int? get trialDaysRemaining {
    if (!isTrial || trialEndDate == null) return null;
    final days = trialEndDate!.difference(_now).inDays;
    return days < 0 ? 0 : days;
  }

  /// Progres triala 0.0–1.0 (null jeśli nie trial)
  double? get trialProgress {
    if (!isTrial || trialEndDate == null) return null;
    final totalDays = trialEndDate!.difference(startDate).inDays;
    if (totalDays <= 0) return 1.0;
    final elapsed = _now.difference(startDate).inDays;
    return (elapsed / totalDays).clamp(0.0, 1.0);
  }

  /// Kwota miesięczna po zakończeniu triala
  double get postTrialMonthlyAmount {
    final base = postTrialAmount ?? amount;
    final full = _monthlyFromAmount(base);
    if (sharedWith != null && sharedWith! > 1) return full / sharedWith!;
    return full;
  }

  /// Normalizacja do kwoty miesięcznej — wspólny wzór z budżetem
  /// (`cycle_math.monthlyFromCycle`), bez duplikowania arytmetyki cykli.
  double _monthlyFromAmount(double amt) => monthlyFromCycle(
    amt,
    billingCycle,
    customCycleDays,
    cycleMonths: cycleMonths,
  );

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: Currency.values.firstWhere(
        (c) => c.name == json['currency'],
        orElse: () => Currency.PLN,
      ),
      billingCycle: BillingCycle.values.firstWhere(
        (b) => b.name == json['billingCycle'],
        orElse: () => BillingCycle.monthly,
      ),
      customCycleDays: json['customCycleDays'] as int?,
      cycleMonths: (json['cycleMonths'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      categoryId: json['categoryId'] as String?,
      startDate: DateTime.parse(json['startDate'] as String),
      cancellationUrl: json['cancellationUrl'] as String?,
      iconName: json['iconName'] as String?,
      colorHex: json['colorHex'] as String?,
      isPinned: json['isPinned'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      reminderDaysBefore: json['reminderDaysBefore'] as int?,
      usageLog: (json['usageLog'] as List<dynamic>? ?? [])
          .map((e) => UsageEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      dataDodania: DateTime.parse(json['dataDodania'] as String),
      cancelledDate: json['cancelledDate'] != null
          ? DateTime.parse(json['cancelledDate'] as String)
          : null,
      sharedWith: json['sharedWith'] as int?,
      paymentMethod: json['paymentMethod'] as String?,
      isTrial: json['isTrial'] as bool? ?? false,
      trialEndDate: json['trialEndDate'] != null
          ? DateTime.parse(json['trialEndDate'] as String)
          : null,
      postTrialAmount: (json['postTrialAmount'] as num?)?.toDouble(),
      // Przed ADR-037 subskrypcja znała tylko „osobista/domowa" (pole
      // `scope`) — budżety o tych samych identyfikatorach przejmują je wprost.
      budgetId:
          json['budgetId'] as String? ??
          (json['scope'] == 'household' ? 'household' : 'personal'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'amount': amount,
    'currency': currency.name,
    'billingCycle': billingCycle.name,
    if (customCycleDays != null) 'customCycleDays': customCycleDays,
    if (cycleMonths != null) 'cycleMonths': cycleMonths,
    if (categoryId != null) 'categoryId': categoryId,
    'startDate': startDate.toIso8601String(),
    if (cancellationUrl != null) 'cancellationUrl': cancellationUrl,
    if (iconName != null) 'iconName': iconName,
    if (colorHex != null) 'colorHex': colorHex,
    'isPinned': isPinned,
    'isActive': isActive,
    if (reminderDaysBefore != null) 'reminderDaysBefore': reminderDaysBefore,
    'usageLog': usageLog.map((e) => e.toJson()).toList(),
    'dataDodania': dataDodania.toIso8601String(),
    if (cancelledDate != null)
      'cancelledDate': cancelledDate!.toIso8601String(),
    if (sharedWith != null) 'sharedWith': sharedWith,
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
    'isTrial': isTrial,
    if (trialEndDate != null) 'trialEndDate': trialEndDate!.toIso8601String(),
    if (postTrialAmount != null) 'postTrialAmount': postTrialAmount,
    'budgetId': budgetId,
    // Dla wersji sprzed ADR-037, które czytają tylko `scope`: budżet spoza
    // dwóch pierwszych pokaże się tam jako osobisty.
    'scope': budgetId == 'household' ? 'household' : 'personal',
  };

  Subscription copyWith({
    String? id,
    String? name,
    String? description,
    bool clearDescription = false,
    double? amount,
    Currency? currency,
    BillingCycle? billingCycle,
    int? customCycleDays,
    bool clearCustomCycleDays = false,
    List<int>? cycleMonths,
    bool clearCycleMonths = false,
    String? categoryId,
    bool clearCategoryId = false,
    DateTime? startDate,
    String? cancellationUrl,
    bool clearCancellationUrl = false,
    String? iconName,
    bool clearIconName = false,
    String? colorHex,
    bool clearColorHex = false,
    bool? isPinned,
    bool? isActive,
    int? reminderDaysBefore,
    bool clearReminderDaysBefore = false,
    List<UsageEvent>? usageLog,
    DateTime? dataDodania,
    DateTime? cancelledDate,
    bool clearCancelledDate = false,
    int? sharedWith,
    bool clearSharedWith = false,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    bool? isTrial,
    DateTime? trialEndDate,
    bool clearTrialEndDate = false,
    double? postTrialAmount,
    bool clearPostTrialAmount = false,
    String? budgetId,
  }) {
    return Subscription(
      id: id ?? this.id,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      billingCycle: billingCycle ?? this.billingCycle,
      customCycleDays: clearCustomCycleDays
          ? null
          : (customCycleDays ?? this.customCycleDays),
      cycleMonths: clearCycleMonths ? null : (cycleMonths ?? this.cycleMonths),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      startDate: startDate ?? this.startDate,
      cancellationUrl: clearCancellationUrl
          ? null
          : (cancellationUrl ?? this.cancellationUrl),
      iconName: clearIconName ? null : (iconName ?? this.iconName),
      colorHex: clearColorHex ? null : (colorHex ?? this.colorHex),
      isPinned: isPinned ?? this.isPinned,
      isActive: isActive ?? this.isActive,
      reminderDaysBefore: clearReminderDaysBefore
          ? null
          : (reminderDaysBefore ?? this.reminderDaysBefore),
      usageLog: usageLog ?? this.usageLog,
      dataDodania: dataDodania ?? this.dataDodania,
      cancelledDate: clearCancelledDate
          ? null
          : (cancelledDate ?? this.cancelledDate),
      sharedWith: clearSharedWith ? null : (sharedWith ?? this.sharedWith),
      paymentMethod: clearPaymentMethod
          ? null
          : (paymentMethod ?? this.paymentMethod),
      isTrial: isTrial ?? this.isTrial,
      trialEndDate: clearTrialEndDate
          ? null
          : (trialEndDate ?? this.trialEndDate),
      postTrialAmount: clearPostTrialAmount
          ? null
          : (postTrialAmount ?? this.postTrialAmount),
      budgetId: budgetId ?? this.budgetId,
    );
  }
}

/// Metoda płatności — edytowalna przez użytkownika w Ustawieniach.
///
/// `id` jest stabilne (UUID), `name` może być zmieniane — przy rename
/// kontroler propaguje nową nazwę do wszystkich subskrypcji (patrz
/// `SubscriptionController.renamePaymentMethod`).
///
/// Subskrypcje nadal przechowują `paymentMethod` jako surową nazwę
/// (`String?`), nie ID — decyzja świadoma (backward-compat z istniejącymi
/// backupami i prostota modelu).
class PaymentMethod {
  final String id;
  final String name;
  final int order;

  /// Tryb płatności: `true` = automatyczna (np. polecenie zapłaty / karta),
  /// `false` = manualna (przelew do zrobienia ręcznie). Domyślnie manualna.
  /// Wpływa na kolor na kalendarzu (auto = żółty) i listę „Płatności".
  final bool isAutomatic;

  /// Karta kredytowa — metoda, która POŻYCZA pieniądze zamiast je wydać.
  ///
  /// Zapłata taką kartą nie zabiera pieniędzy z konta od razu: robi to spłata
  /// po okresie bezodsetkowym. Aplikacja odwzorowuje to parą pozycji spiętych
  /// `linkId` (ADR-033), więc bilans miesiąca zakupu wychodzi na zero, a koszt
  /// ląduje w miesiącu spłaty.
  final bool isCreditCard;

  /// Ile dni od zakupu do spłaty (okres bezodsetkowy). Ma znaczenie tylko przy
  /// [isCreditCard]. `null` = nieustawione; automat wtedy nie działa, bo nie ma
  /// jak wyliczyć daty spłaty.
  final int? graceDays;

  /// Znacznik ostatniej zmiany — rozstrzyga scalanie przy synchronizacji
  /// budżetu domowego (ADR-025). `null` = wpis sprzed tej funkcji albo
  /// domyślny; liczy się jak epoka zero.
  final DateTime? updatedAt;

  const PaymentMethod({
    required this.id,
    required this.name,
    this.order = 0,
    this.isAutomatic = false,
    this.isCreditCard = false,
    this.graceDays,
    this.updatedAt,
  });

  /// Czy z tej metody da się zbudować automat spłaty — sama flaga nie wystarczy,
  /// bez liczby dni nie ma jak wyznaczyć terminu.
  bool get hasCreditTerms =>
      isCreditCard && graceDays != null && graceDays! > 0;

  PaymentMethod copyWith({
    String? id,
    String? name,
    int? order,
    bool? isAutomatic,
    bool? isCreditCard,
    int? graceDays,
    bool clearGraceDays = false,
    DateTime? updatedAt,
  }) => PaymentMethod(
    id: id ?? this.id,
    name: name ?? this.name,
    order: order ?? this.order,
    isAutomatic: isAutomatic ?? this.isAutomatic,
    isCreditCard: isCreditCard ?? this.isCreditCard,
    graceDays: clearGraceDays ? null : (graceDays ?? this.graceDays),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  // Nowe pola sa OPCJONALNE w JSON-ie: starsza aplikacja po drugiej stronie
  // synchronizacji (ADR-025) po prostu ich nie zna i czyta metode jak dotad.
  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
    id: json['id'] as String,
    name: json['name'] as String,
    order: (json['order'] as num?)?.toInt() ?? 0,
    isAutomatic: json['isAutomatic'] as bool? ?? false,
    isCreditCard: json['isCreditCard'] as bool? ?? false,
    graceDays: (json['graceDays'] as num?)?.toInt(),
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    'isAutomatic': isAutomatic,
    if (isCreditCard) 'isCreditCard': true,
    if (graceDays != null) 'graceDays': graceDays,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };
}

/// Domyślne metody płatności — seed przy pierwszym uruchomieniu.
/// Po inicjalizacji boxa użytkownik może je dowolnie edytować.
const List<PaymentMethod> defaultPaymentMethods = [
  PaymentMethod(id: 'pm_bank_transfer', name: 'Przelew bankowy', order: 0),
  PaymentMethod(id: 'pm_credit_card', name: 'Karta kredytowa', order: 1),
  PaymentMethod(id: 'pm_debit_card', name: 'Karta debetowa', order: 2),
  PaymentMethod(id: 'pm_revolut', name: 'Revolut', order: 3),
  PaymentMethod(id: 'pm_paypal', name: 'PayPal', order: 4),
  PaymentMethod(id: 'pm_blik', name: 'BLIK', order: 5),
  PaymentMethod(id: 'pm_cash', name: 'Gotówka', order: 6),
  PaymentMethod(id: 'pm_other', name: 'Inne', order: 7),
];
