import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/subscription.dart';

void main() {
  const t = Currency.PLN;

  BudgetEntry income() => BudgetEntry(
        id: 'i',
        name: 'Pensja',
        type: BudgetEntryType.income,
        amount: 5000,
        currency: t,
        dataDodania: DateTime(2026, 1, 1),
      );

  // Rata 500/mies, start 2026-01-15, 10 rat → aktywna I..X 2026 (ostatnia 2026-10).
  BudgetEntry installment() => BudgetEntry(
        id: 'r',
        name: 'Pralka rata',
        type: BudgetEntryType.installment,
        amount: 500,
        currency: t,
        startDate: DateTime(2026, 1, 15),
        installmentCount: 10,
        dataDodania: DateTime(2026, 1, 1),
      );

  tearDown(() => Subscription.devDateOverride = null);

  group('BudgetEntry — okno raty', () {
    test('lastInstallmentDate i aktywność miesięcy', () {
      final r = installment();
      expect(r.lastInstallmentDate, DateTime(2026, 10, 15));
      expect(r.isInstallmentActiveInMonth('2026-01'), isTrue);
      expect(r.isInstallmentActiveInMonth('2026-10'), isTrue);
      expect(r.isInstallmentActiveInMonth('2025-12'), isFalse);
      expect(r.isInstallmentActiveInMonth('2026-11'), isFalse);
    });
  });

  group('BudgetEntry — appliesToMonth (filtr czasu, snapshot)', () {
    BudgetEntry oneTime(String month) => BudgetEntry(
          id: 'o_$month',
          name: 'Jednorazowy',
          type: BudgetEntryType.spending,
          amount: 300,
          currency: t,
          month: month,
          dataDodania: DateTime(2026, 1, 1),
        );

    test('cykliczny wpływ dotyczy każdego miesiąca', () {
      expect(income().appliesToMonth('2026-03'), isTrue);
      expect(income().appliesToMonth('2030-12'), isTrue);
    });

    test('jednorazowy dotyczy tylko swojego miesiąca', () {
      final e = oneTime('2026-07');
      expect(e.appliesToMonth('2026-07'), isTrue);
      expect(e.appliesToMonth('2026-08'), isFalse);
    });

    test('rata dotyczy tylko miesięcy w oknie spłaty', () {
      final r = installment(); // I..X 2026
      expect(r.appliesToMonth('2026-01'), isTrue);
      expect(r.appliesToMonth('2026-10'), isTrue);
      expect(r.appliesToMonth('2026-11'), isFalse);
    });
  });

}
