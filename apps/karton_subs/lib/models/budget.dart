import 'plan_position.dart' show kBudgetHousehold, kBudgetPersonal;

/// Budżet z własną nazwą i ikoną (ADR-037).
///
/// Budżety są od siebie oddzielne — każdy ma własny plan (pozycje z jego
/// [id]), subskrypcje i odhaczone płatności. Pierwsze dwa to dawne zakresy
/// „osobisty" i „domowy" — z tymi samymi identyfikatorami, więc ich dane nie
/// wymagały żadnej przeróbki.
class Budget {
  /// Identyfikator w danych (`budgetId` pozycji i subskrypcji, początek
  /// klucza odhaczonej płatności). Nie zmienia się przy zmianie nazwy.
  final String id;
  final String name;

  /// Nazwa ikony z katalogu ikon kategorii (`categoryIcon`).
  final String icon;

  /// Ukryty budżet nie pojawia się w przełączniku (dane zostają). Zastępuje
  /// dawny „tryb budżetu" (osobisty / domowy / oba).
  final bool hidden;

  const Budget({
    required this.id,
    required this.name,
    required this.icon,
    this.hidden = false,
  });

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String? ?? 'folder',
    hidden: json['hidden'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    if (hidden) 'hidden': true,
  };

  Budget copyWith({String? name, String? icon, bool? hidden}) => Budget(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    hidden: hidden ?? this.hidden,
  );

  /// Budżety, z którymi startuje aplikacja (i każda instalacja sprzed
  /// ADR-037) — dawne zakresy z ikonami z dawnego przełącznika.
  static const defaults = [
    Budget(id: kBudgetPersonal, name: 'Osobisty', icon: 'user'),
    Budget(id: kBudgetHousehold, name: 'Domowy', icon: 'home'),
  ];
}
