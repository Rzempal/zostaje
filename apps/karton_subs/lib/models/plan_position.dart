import 'subscription.dart' show Currency;

/// Rodzaj pozycji planu rocznego (ADR-035).
///
/// Subskrypcje NIE są rodzajem pozycji — mają własny model (okresy próbne,
/// przypomnienia, limit), a plan tylko czyta je jako osobną sekcję.
enum PlanKind {
  /// Wpływ: pensja, premia, wkład do budżetu domowego.
  income,

  /// Wydatek: koszt stały, rata, przelew do innego budżetu.
  expense,

  /// Pożyczka — pieniądze przychodzą: z karty kredytowej w dniu jej użycia
  /// albo pożyczka ratalna w dniu wypłaty (ADR-036). Zawsze ze spłatą
  /// ([PlanPosition.linkId]).
  loan,

  /// Spłata pożyczki — karty po okresie bezodsetkowym (jeden miesiąc) albo
  /// raty pożyczki ratalnej (wiele miesięcy, z warunkami w
  /// [PlanPosition.loanTerms]).
  loanRepayment,
}

/// Wartości pola `kind` W ZAPISIE — odcięte od nazw w kodzie (jak typy
/// [BudgetEntry]): nazwę w Darcie wolno zmienić, wartość tutaj nie.
/// Pożyczki zapisują się jak dawne pozycje karty („cardLoan",
/// „cardRepayment") — pożyczka ratalna to ta sama para z warunkami, więc
/// wersja sprzed ADR-036 widzi ją jak pożyczkę z karty z wieloma spłatami.
const Map<PlanKind, String> _kindWireNames = {
  PlanKind.income: 'income',
  PlanKind.expense: 'expense',
  PlanKind.loan: 'cardLoan',
  PlanKind.loanRepayment: 'cardRepayment',
};

extension PlanKindWire on PlanKind {
  /// Wartość zapisywana na dysk — używaj TEGO zamiast [name] w JSON-ie.
  String get wireName => _kindWireNames[this]!;
}

/// Rodzaj z zapisanej nazwy. Nieznana wartość = wydatek: przeoczony wydatek
/// zawyżyłby „zostaje" po cichu, a wydatek nadmiarowy widać na liście.
PlanKind planKindFromWire(String? raw) => PlanKind.values.firstWhere(
  (k) => k.wireName == raw,
  orElse: () => PlanKind.expense,
);

/// Budżety na start przebudowy — dawne zakresy „osobisty" i „domowy".
///
/// Pozycja niesie identyfikator budżetu, a nie wartość wyliczeniową, bo
/// docelowo budżety mają własne nazwy i może ich być więcej. Wtedy dojdzie
/// ekran budżetów, ale dane nie będą wymagały ponownej konwersji.
const kBudgetPersonal = 'personal';
const kBudgetHousehold = 'household';

/// Klucz miesiąca planu: "RRRR-MM" (ten sam format co klucze korekt i pole
/// `month` w [BudgetEntry]).
String planMonthKey(int year, int month) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

/// Jeden miesiąc pozycji: kwota i opcjonalnie dzień płatności.
///
/// Miesiące są od siebie niezależne — zmiana kwoty jednego nie rusza
/// pozostałych. Dzień `null` = dzień pozycji ([PlanPosition.day]).
class PlanMonth {
  final double amount;
  final int? day;

  const PlanMonth({required this.amount, this.day});

  factory PlanMonth.fromJson(Map<String, dynamic> json) => PlanMonth(
    amount: (json['amount'] as num).toDouble(),
    day: (json['day'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {'amount': amount, 'day': ?day};

  PlanMonth copyWith({double? amount, int? day, bool clearDay = false}) =>
      PlanMonth(
        amount: amount ?? this.amount,
        day: clearDay ? null : (day ?? this.day),
      );
}

/// Warunki pożyczki ratalnej (ADR-036) — zapisane przy jej ratach.
///
/// Raty w planie (miesiące pozycji „spłata") powstają z tych warunków;
/// warunki zostają, żeby formularz pożyczki pokazał, z czego raty wynikają,
/// i przeliczył je po zmianie.
class PlanLoanTerms {
  /// Kwota wypłacona — tyle przychodzi w dniu wypłaty (wpływ w Pożyczkach).
  final double principal;

  /// Liczba rat.
  final int count;

  /// Rata (stała; przy 0% ostatnia wyrównuje grosze zaokrągleń).
  final double installment;

  /// RRSO w procentach (np. 7,57) — z umowy albo wyliczone z wypłaty i rat.
  final double rrso;

  /// Dzień wypłaty pożyczki.
  final DateTime drawdown;

  /// Miesiąc pierwszej raty, "RRRR-MM".
  final String firstMonth;

  /// Dzień raty w miesiącu (1–31; w krótszym miesiącu — ostatni dzień).
  final int day;

  const PlanLoanTerms({
    required this.principal,
    required this.count,
    required this.installment,
    required this.rrso,
    required this.drawdown,
    required this.firstMonth,
    required this.day,
  });

  /// Miesiąc ostatniej raty, "RRRR-MM".
  String get lastMonth {
    final d = DateTime(
      int.parse(firstMonth.substring(0, 4)),
      int.parse(firstMonth.substring(5)) + count - 1,
    );
    return planMonthKey(d.year, d.month);
  }

  factory PlanLoanTerms.fromJson(Map<String, dynamic> json) => PlanLoanTerms(
    principal: (json['principal'] as num).toDouble(),
    count: (json['count'] as num).toInt(),
    installment: (json['installment'] as num).toDouble(),
    rrso: (json['rrso'] as num).toDouble(),
    drawdown: DateTime.parse(json['drawdown'] as String),
    firstMonth: json['firstMonth'] as String,
    day: (json['day'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'principal': principal,
    'count': count,
    'installment': installment,
    'rrso': rrso,
    // Sama data — godzina nie ma znaczenia, a strefa czasowa by ją psuła.
    'drawdown':
        '${drawdown.year.toString().padLeft(4, '0')}-'
        '${drawdown.month.toString().padLeft(2, '0')}-'
        '${drawdown.day.toString().padLeft(2, '0')}',
    'firstMonth': firstMonth,
    'day': day,
  };
}

/// Pozycja planu rocznego — wiersz arkusza „pozycje × miesiące" (ADR-035).
///
/// Kwota żyje WYŁĄCZNIE w miesiącach ([months]); pozycja niesie to, co dla
/// nich wspólne (nazwa, kategoria, metoda, waluta, domyślny dzień). Brak
/// miesiąca w mapie = pozycja w tym miesiącu nie obowiązuje.
///
/// Pozycja nie jest przypięta do roku: rata od 09.2026 do 08.2027 to jedna
/// pozycja z miesiącami w dwóch latach. Widok roku pokazuje pozycje, które
/// mają w nim choć jeden miesiąc.
class PlanPosition {
  final String id;

  /// Budżet, do którego należy pozycja — patrz [kBudgetPersonal].
  final String budgetId;
  final String name;
  final PlanKind kind;
  final Currency currency;
  final String? categoryId;

  /// Metoda płatności po nazwie (jak w [BudgetEntry]).
  final String? paymentMethod;

  /// Domyślny dzień płatności (1–31) dla miesięcy bez własnego dnia.
  final int? day;
  final String? note;

  /// Pozycja ukryta (dawniej: wstrzymana) — widoczna po „pokaż ukryte",
  /// nie liczy się do sum.
  final bool archived;

  /// Miesiące pozycji: "RRRR-MM" → kwota (i dzień).
  final Map<String, PlanMonth> months;

  /// Spina pożyczkę z karty z jej spłatą (ten sam identyfikator na obu).
  /// Usunięcie jednej usuwa drugą — sama pożyczka bez spłaty zawyżałaby
  /// wpływy, a sama spłata zostawiłaby wydatek bez źródła.
  final String? linkId;

  /// Okres obowiązywania ("RRRR-MM", oba końce włącznie): rata ma oba,
  /// pozycja ze startem (umowa od listopada) samo [periodStart], pozycja
  /// bez końca (czynsz, pensja) — żadnego. Poza okresem pozycja nie ma
  /// miesięcy: ekran pozycji ich nie wypełni, a kontroler ich nie zapisze —
  /// to zabezpieczenie przed „wypełnij puste" wpisującym ratę po spłacie.
  final String? periodStart;
  final String? periodEnd;

  /// Warunki pożyczki ratalnej — tylko na pozycji z ratami
  /// ([PlanKind.loanRepayment]); pożyczka z karty ich nie ma.
  final PlanLoanTerms? loanTerms;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PlanPosition({
    required this.id,
    required this.budgetId,
    required this.name,
    required this.kind,
    required this.currency,
    this.categoryId,
    this.paymentMethod,
    this.day,
    this.note,
    this.archived = false,
    this.months = const {},
    this.linkId,
    this.periodStart,
    this.periodEnd,
    this.loanTerms,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isIncome => kind == PlanKind.income;

  /// Pozycja karty kredytowej (pożyczka albo spłata) — liczona osobno od
  /// wpływów i wydatków: w skali roku para się znosi, więc wliczona do nich
  /// zawyżałaby obie średnie.
  bool get isLoan =>
      kind == PlanKind.loan || kind == PlanKind.loanRepayment;

  /// Czy pieniądze przychodzą (wpływ, pożyczka z karty) — kierunek przepływu.
  bool get isInflow => kind == PlanKind.income || kind == PlanKind.loan;

  bool get hasPeriod => periodStart != null || periodEnd != null;

  /// Czy miesiąc mieści się w okresie pozycji (bez okresu — każdy).
  /// Klucze "RRRR-MM" porównują się jak tekst, bo mają stałą długość.
  bool inPeriod(String monthKey) =>
      (periodStart == null || monthKey.compareTo(periodStart!) >= 0) &&
      (periodEnd == null || monthKey.compareTo(periodEnd!) <= 0);

  /// Czy miesiąc jest przed startem okresu (do opisu zablokowanego miesiąca).
  bool beforePeriod(String monthKey) =>
      periodStart != null && monthKey.compareTo(periodStart!) < 0;

  /// Klucze miesięcy z kwotą, które leżą poza okresem — do pytania „usunąć?"
  /// przy zawężaniu okresu.
  List<String> monthsOutsidePeriod({String? start, String? end}) {
    bool inside(String k) =>
        (start == null || k.compareTo(start) >= 0) &&
        (end == null || k.compareTo(end) <= 0);
    return months.keys.where((k) => !inside(k)).toList()..sort();
  }

  /// Kwota w miesiącu (0, gdy pozycja w nim nie obowiązuje).
  double amountIn(String monthKey) => months[monthKey]?.amount ?? 0;

  /// Dzień płatności w miesiącu: własny dzień miesiąca, inaczej dzień pozycji.
  int? dayIn(String monthKey) => months[monthKey]?.day ?? day;

  /// Miesiące danego roku, w kolejności kalendarzowej.
  List<MapEntry<String, PlanMonth>> monthsOfYear(int year) {
    final prefix = '${year.toString().padLeft(4, '0')}-';
    return months.entries.where((e) => e.key.startsWith(prefix)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  /// Czy pozycja ma w danym roku choć jeden miesiąc.
  bool hasYear(int year) => monthsOfYear(year).isNotEmpty;

  /// Suma kwot miesięcy danego roku (w walucie pozycji).
  double yearTotal(int year) =>
      monthsOfYear(year).fold(0.0, (sum, e) => sum + e.value.amount);

  /// Średnia miesięczna roku: suma ÷ 12, także gdy pozycja obowiązuje tylko
  /// w kilku miesiącach — to odpowiedź na „ile średnio miesięcznie".
  double yearAverage(int year) => yearTotal(year) / 12;

  factory PlanPosition.fromJson(Map<String, dynamic> json) => PlanPosition(
    id: json['id'] as String,
    budgetId: json['budgetId'] as String? ?? kBudgetPersonal,
    name: json['name'] as String,
    kind: planKindFromWire(json['kind'] as String?),
    currency: Currency.values.firstWhere(
      (c) => c.name == json['currency'],
      orElse: () => Currency.PLN,
    ),
    categoryId: json['categoryId'] as String?,
    paymentMethod: json['paymentMethod'] as String?,
    day: (json['day'] as num?)?.toInt(),
    note: json['note'] as String?,
    archived: json['archived'] as bool? ?? false,
    months:
        (json['months'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, PlanMonth.fromJson(v as Map<String, dynamic>)),
        ) ??
        const {},
    linkId: json['linkId'] as String?,
    periodStart: json['periodStart'] as String?,
    periodEnd: json['periodEnd'] as String?,
    loanTerms: json['loan'] is Map<String, dynamic>
        ? PlanLoanTerms.fromJson(json['loan'] as Map<String, dynamic>)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : null,
  );

  /// Miesiące zapisujemy posortowane — kopia zapasowa i porównania plików
  /// nie mogą zależeć od kolejności, w jakiej miesiące powstawały.
  Map<String, dynamic> toJson() => {
    'id': id,
    'budgetId': budgetId,
    'name': name,
    'kind': kind.wireName,
    'currency': currency.name,
    'categoryId': ?categoryId,
    'paymentMethod': ?paymentMethod,
    'day': ?day,
    'note': ?note,
    if (archived) 'archived': true,
    'months': {
      for (final k in (months.keys.toList()..sort())) k: months[k]!.toJson(),
    },
    'linkId': ?linkId,
    'periodStart': ?periodStart,
    'periodEnd': ?periodEnd,
    'loan': ?loanTerms?.toJson(),
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  PlanPosition copyWith({
    String? budgetId,
    String? name,
    PlanKind? kind,
    Currency? currency,
    String? categoryId,
    bool clearCategoryId = false,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    int? day,
    bool clearDay = false,
    String? note,
    bool clearNote = false,
    bool? archived,
    Map<String, PlanMonth>? months,
    String? periodStart,
    bool clearPeriodStart = false,
    String? periodEnd,
    bool clearPeriodEnd = false,
    String? linkId,
    bool clearLinkId = false,
    PlanLoanTerms? loanTerms,
    bool clearLoanTerms = false,
    DateTime? updatedAt,
  }) => PlanPosition(
    id: id,
    budgetId: budgetId ?? this.budgetId,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    currency: currency ?? this.currency,
    categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
    paymentMethod: clearPaymentMethod
        ? null
        : (paymentMethod ?? this.paymentMethod),
    day: clearDay ? null : (day ?? this.day),
    note: clearNote ? null : (note ?? this.note),
    archived: archived ?? this.archived,
    months: months ?? this.months,
    linkId: clearLinkId ? null : (linkId ?? this.linkId),
    periodStart: clearPeriodStart ? null : (periodStart ?? this.periodStart),
    periodEnd: clearPeriodEnd ? null : (periodEnd ?? this.periodEnd),
    loanTerms: clearLoanTerms ? null : (loanTerms ?? this.loanTerms),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
