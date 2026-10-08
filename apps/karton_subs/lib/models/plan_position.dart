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

  /// Pożyczka z karty kredytowej — pieniądze przychodzą w miesiącu użycia
  /// karty. Zawsze w parze ze spłatą ([PlanPosition.linkId]).
  cardLoan,

  /// Spłata karty — wychodzi w miesiącu wynikającym z okresu bezodsetkowego.
  cardRepayment,
}

/// Wartości pola `kind` W ZAPISIE — odcięte od nazw w kodzie (jak typy
/// [BudgetEntry]): nazwę w Darcie wolno zmienić, wartość tutaj nie.
const Map<PlanKind, String> _kindWireNames = {
  PlanKind.income: 'income',
  PlanKind.expense: 'expense',
  PlanKind.cardLoan: 'cardLoan',
  PlanKind.cardRepayment: 'cardRepayment',
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
    required this.createdAt,
    this.updatedAt,
  });

  bool get isIncome => kind == PlanKind.income;

  /// Pozycja karty kredytowej (pożyczka albo spłata) — liczona osobno od
  /// wpływów i wydatków: w skali roku para się znosi, więc wliczona do nich
  /// zawyżałaby obie średnie.
  bool get isCard =>
      kind == PlanKind.cardLoan || kind == PlanKind.cardRepayment;

  /// Czy pieniądze przychodzą (wpływ, pożyczka z karty) — kierunek przepływu.
  bool get isInflow => kind == PlanKind.income || kind == PlanKind.cardLoan;

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
    linkId: linkId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
