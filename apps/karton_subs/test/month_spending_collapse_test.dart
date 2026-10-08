import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/cashflow.dart';
import 'package:karton_subs/widgets/budget_widgets.dart';

CalendarItem _item(String name, double amount, CalendarItemKind kind) =>
    CalendarItem(name: name, amount: amount, isIncome: false, kind: kind);

/// Zwijanie wydatków bieżących w sekcjach miesiąca: przełącznik pokazuje się
/// dopiero, gdy jest co zwijać. Sam widok jest w widgetach, ale reguła „ile
/// pozycji" musi się zgadzać — od niej zależy, czy ikona w ogóle istnieje.
void main() {
  group('spendingItemCount', () {
    test('liczy tylko bieżące, nie subskrypcje i nie resztę budżetu', () {
      final calendar = {
        3: DayCashflow([
          _item('Paliwo', 300, CalendarItemKind.spending),
          _item('Netflix', 40, CalendarItemKind.subscription),
        ]),
        8: DayCashflow([
          _item('Barber', 120, CalendarItemKind.spending),
          _item('Prąd', 700, CalendarItemKind.budgetEntry),
        ]),
      };

      expect(spendingItemCount(calendar), 2);
    });

    test('miesiąc z jednym bieżącym nie daje czego zwijać', () {
      final calendar = {
        3: DayCashflow([
          _item('Paliwo', 300, CalendarItemKind.spending),
          _item('Prąd', 700, CalendarItemKind.budgetEntry),
        ]),
      };

      // Próg to 1: przy jednej pozycji przełącznik się nie pokazuje, bo
      // „suma jednej pozycji" to ta sama liczba, tylko pod inną nazwą.
      expect(spendingItemCount(calendar), 1);
    });

    test('miesiąc bez bieżących', () {
      final calendar = {
        3: DayCashflow([_item('Prąd', 700, CalendarItemKind.budgetEntry)]),
      };

      expect(spendingItemCount(calendar), 0);
    });

    test('pusty kalendarz', () {
      expect(spendingItemCount(const {}), 0);
    });
  });
}
