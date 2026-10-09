import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/services/loan_math.dart';

// Matematyka pożyczki ratalnej (ADR-036): z trzech wartości (kwota, liczba
// rat, rata, RRSO) liczy się czwarta, a cztery wartości się sprawdza.

/// Odkurzacz na raty 0%: wypłata 13 wrz 2026, raty od października, 13.
final _dreamy = LoanSchedule(
  drawdown: DateTime(2026, 9, 13),
  firstYear: 2026,
  firstMonth: 10,
  day: 13,
);

/// Telefon: wypłata 28 sie 2026, 11 rat od września, dnia 28.
final _fold = LoanSchedule(
  drawdown: DateTime(2026, 8, 28),
  firstYear: 2026,
  firstMonth: 9,
  day: 28,
);

void main() {
  group('Raty 0%', () {
    test('rata z kwoty i liczby rat; ostatnia wyrównuje grosze', () {
      final r = LoanMath.installment(
        _dreamy,
        principal: 2000,
        count: 12,
        rrso: 0,
      );
      expect(r, 166.67);
      expect(
        LoanMath.lastInstallment(
          principal: 2000,
          count: 12,
          installment: r,
          rrso: 0,
        ),
        166.63,
      );
      expect(
        LoanMath.totalRepayment(
          principal: 2000,
          count: 12,
          installment: r,
          rrso: 0,
        ),
        2000,
      );
    });

    test('liczba rat z kwoty i raty', () {
      expect(
        LoanMath.count(_dreamy, principal: 2000, installment: 166.67, rrso: 0),
        12,
      );
      expect(
        LoanMath.count(_dreamy, principal: 2000, installment: 500, rrso: 0),
        4,
      );
    });

    test('RRSO z rat, które dają dokładnie kwotę — zero', () {
      expect(
        LoanMath.rrso(_dreamy, principal: 2000, count: 4, installment: 500),
        0,
      );
    });
  });

  group('Pożyczka oprocentowana', () {
    test('RRSO z wypłaty i rat, a z RRSO z powrotem ta sama rata', () {
      final x = LoanMath.rrso(
        _fold,
        principal: 2400,
        count: 11,
        installment: 226.21,
      )!;
      // 11 × 226,21 = 2488,31 za 2400 zł na niecały rok.
      expect(x, inInclusiveRange(7.0, 8.2));
      expect(
        LoanMath.installment(_fold, principal: 2400, count: 11, rrso: x),
        closeTo(226.21, LoanMath.tolerance),
      );
      expect(
        LoanMath.principal(_fold, installment: 226.21, count: 11, rrso: x),
        closeTo(2400, 0.5),
      );
    });

    test('raty poniżej kwoty — RRSO nie istnieje', () {
      expect(
        LoanMath.rrso(_fold, principal: 2400, count: 10, installment: 200),
        isNull,
      );
    });

    test('rata za niska na sam koszt — liczby rat nie ma', () {
      expect(
        LoanMath.count(_fold, principal: 10000, installment: 10, rrso: 20),
        isNull,
      );
    });
  });

  group('Harmonogram', () {
    test('rata „31." w krótszym miesiącu wypada ostatniego dnia', () {
      final s = LoanSchedule(
        drawdown: DateTime(2027, 1, 15),
        firstYear: 2027,
        firstMonth: 1,
        day: 31,
      );
      expect(s.dateOf(1), DateTime(2027, 2, 28));
      expect(s.monthKeyOf(13), '2028-02');
      expect(s.dateOf(13), DateTime(2028, 2, 29));
    });

    test('raty jako miesiące planu: ostatnia wyrównana, dzień tylko inny', () {
      final months = LoanMath.installmentMonths(
        PlanLoanTerms(
          principal: 2000,
          count: 12,
          installment: 166.67,
          rrso: 0,
          drawdown: DateTime(2026, 9, 13),
          firstMonth: '2026-10',
          day: 13,
        ),
      );
      expect(months.keys.first, '2026-10');
      expect(months.keys.last, '2027-09');
      expect(months['2027-09']!.amount, 166.63);
      expect(months['2026-10']!.day, isNull);
    });
  });

  group('Uzupełnianie i sprawdzanie (trzy z czterech)', () {
    test('za mało danych', () {
      final c = LoanMath.solve(_fold, principal: 2400, count: 11);
      expect(c, isA<LoanNeedsMore>());
      expect((c as LoanNeedsMore).missing, 1);
    });

    test('brakująca rata, liczba rat, kwota albo RRSO — policzona', () {
      final r = LoanMath.solve(_dreamy, principal: 2000, count: 12, rrso: 0);
      expect((r as LoanComputed).field, LoanField.installment);
      expect(r.value, 166.67);

      final n = LoanMath.solve(
        _dreamy,
        principal: 2000,
        installment: 166.67,
        rrso: 0,
      );
      expect((n as LoanComputed).field, LoanField.count);
      expect(n.value, 12);

      final p = LoanMath.solve(_dreamy, count: 12, installment: 100, rrso: 0);
      expect((p as LoanComputed).field, LoanField.principal);
      expect(p.value, 1200);

      final x = LoanMath.solve(
        _fold,
        principal: 2400,
        count: 11,
        installment: 226.21,
      );
      expect((x as LoanComputed).field, LoanField.rrso);
    });

    test('cztery zgodne wartości — spójne (grosze zaokrągleń dozwolone)', () {
      expect(
        LoanMath.solve(
          _dreamy,
          principal: 2000,
          count: 12,
          installment: 166.7,
          rrso: 0,
        ),
        isA<LoanConsistent>(),
      );
    });

    test('cztery niezgodne — podpowiedź raty i RRSO z rat', () {
      final c = LoanMath.solve(
        _fold,
        principal: 2400,
        count: 11,
        installment: 226.21,
        rrso: 12,
      );
      expect(c, isA<LoanMismatch>());
      c as LoanMismatch;
      expect(c.expectedInstallment, greaterThan(226.21));
      expect(c.rrsoFromInstallment, inInclusiveRange(7.0, 8.2));
    });

    test('raty niepokrywające kwoty i bzdurne wartości — błąd z opisem', () {
      expect(
        LoanMath.solve(_fold, principal: 2400, count: 10, installment: 200),
        isA<LoanInvalid>(),
      );
      expect(
        LoanMath.solve(_fold, principal: -1, count: 10, rrso: 5),
        isA<LoanInvalid>(),
      );
      expect(
        LoanMath.solve(_fold, principal: 100, count: 0, rrso: 5),
        isA<LoanInvalid>(),
      );
    });
  });

  test('warunki pożyczki w JSON tam i z powrotem; data bez godziny', () {
    final t = PlanLoanTerms(
      principal: 2400,
      count: 11,
      installment: 226.21,
      rrso: 7.57,
      drawdown: DateTime(2026, 8, 28, 23, 59),
      firstMonth: '2026-09',
      day: 28,
    );
    final json = t.toJson();
    expect(json['drawdown'], '2026-08-28');
    final back = PlanLoanTerms.fromJson(json);
    expect(back.count, 11);
    expect(back.lastMonth, '2027-07');
    expect(back.drawdown, DateTime(2026, 8, 28));
  });
}
