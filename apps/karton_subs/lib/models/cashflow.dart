// Przepływy dnia kalendarza (zakładka Budżet → Kalendarz). Wypełnia je
// [PlanService.calendarForMonth] z pozycji planu i odnowień subskrypcji.
// Wydzielone z dawnego modułu obliczeń budżetu (ADR-035).

import 'budget_entry.dart' show BudgetEntryType;

/// Pojedyncze zdarzenie pieniezne danego dnia (kwota w walucie docelowej).
class CalendarItem {
  final String name;
  final double amount;
  final bool isIncome;

  /// Skad pozycja pochodzi — do grupowania „po typie glownym" na Dashboardzie.
  final CalendarItemKind kind;

  /// Czy platnosc jest automatyczna (wg metody platnosci). Wydatek auto = zolty,
  /// manual = czerwony na kalendarzu; manualne trafiaja na liste „Platnosci".
  final bool isAutomatic;

  /// Id zrodla (BudgetEntry lub Subscription) — do trwalego stanu „wykonane".
  final String? sourceId;

  /// Rodzaj pozycji budzetu, z ktorej powstal ten przeplyw. Sluzy WYLACZNIE
  /// do ikony (ADR-032): [kind] grupuje zgrubnie, a lista musi pokazac te sama
  /// ikone co zakladka, na ktorej pozycja mieszka. `null` dla subskrypcji.
  final BudgetEntryType? entryType;

  const CalendarItem({
    required this.name,
    required this.amount,
    required this.isIncome,
    this.kind = CalendarItemKind.budgetEntry,
    this.isAutomatic = false,
    this.sourceId,
    this.entryType,
  });
}

/// Typ glowny pozycji kalendarza (grupowanie na Dashboardzie).
enum CalendarItemKind {
  /// Wydatek biezacy — datowany log wydatku (`BudgetEntryType.spending`).
  spending,

  /// Odnowienie subskrypcji.
  subscription,

  /// Pozostale pozycje budzetu: wplywy, koszty stale, raty, jednorazowe.
  budgetEntry;

  /// Etykieta grupy. „Budzet" zamiast „Cykliczne", bo w tej grupie sa takze
  /// pozycje jednorazowe (premia, wieksze zakupy) — nazwa musi je objac.
  String get label => switch (this) {
        CalendarItemKind.spending => 'Bieżące',
        CalendarItemKind.subscription => 'Subskrypcje',
        CalendarItemKind.budgetEntry => 'Budżet',
      };
}

/// Przeplywy jednego dnia kalendarza.
class DayCashflow {
  final List<CalendarItem> items;
  const DayCashflow(this.items);

  bool get hasIncome => items.any((i) => i.isIncome);
  bool get hasExpense => items.any((i) => !i.isIncome);
  bool get hasAutomaticExpense =>
      items.any((i) => !i.isIncome && i.isAutomatic);
  bool get hasManualExpense => items.any((i) => !i.isIncome && !i.isAutomatic);
  double get incomeTotal =>
      items.where((i) => i.isIncome).fold(0.0, (s, i) => s + i.amount);
  double get expenseTotal =>
      items.where((i) => !i.isIncome).fold(0.0, (s, i) => s + i.amount);
}
