import 'dart:math' as math;

import '../models/plan_position.dart';

/// Harmonogram rat pożyczki: dzień wypłaty, miesiąc pierwszej raty i dzień
/// raty w miesiącu (ADR-036).
class LoanSchedule {
  final DateTime drawdown;
  final int firstYear;
  final int firstMonth;

  /// Dzień raty; w krótszym miesiącu rata wypada ostatniego dnia
  /// (rata „31." w lutym to 28 albo 29 lutego).
  final int day;

  const LoanSchedule({
    required this.drawdown,
    required this.firstYear,
    required this.firstMonth,
    required this.day,
  });

  /// Harmonogram z warunków zapisanych przy ratach.
  factory LoanSchedule.ofTerms(PlanLoanTerms t) => LoanSchedule(
    drawdown: t.drawdown,
    firstYear: int.parse(t.firstMonth.substring(0, 4)),
    firstMonth: int.parse(t.firstMonth.substring(5)),
    day: t.day,
  );

  /// Data raty nr [index] (od zera).
  DateTime dateOf(int index) {
    final month = DateTime(firstYear, firstMonth + index);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, math.min(day, lastDay));
  }

  String monthKeyOf(int index) {
    final d = dateOf(index);
    return planMonthKey(d.year, d.month);
  }

  /// Czas od wypłaty do raty w latach — rok = 365 dni, jak we wzorze RRSO
  /// z ustawy o kredycie konsumenckim. Daty w UTC, żeby zmiana czasu nie
  /// skracała doby.
  double yearsTo(int index) {
    final d = dateOf(index);
    final from = DateTime.utc(drawdown.year, drawdown.month, drawdown.day);
    return DateTime.utc(d.year, d.month, d.day).difference(from).inDays / 365;
  }
}

/// Pole pożyczki, które da się policzyć z pozostałych trzech.
enum LoanField { principal, count, installment, rrso }

/// Wynik sprawdzenia danych pożyczki.
sealed class LoanCheck {
  const LoanCheck();
}

/// Za mało danych — brakuje jeszcze [missing] wartości.
class LoanNeedsMore extends LoanCheck {
  final int missing;
  const LoanNeedsMore(this.missing);
}

/// Brakowało jednej wartości — [field] policzone jako [value].
class LoanComputed extends LoanCheck {
  final LoanField field;
  final num value;
  const LoanComputed(this.field, this.value);
}

/// Wszystkie cztery wartości są i się zgadzają.
class LoanConsistent extends LoanCheck {
  const LoanConsistent();
}

/// Wszystkie cztery są, ale się nie zgadzają: przy podanym RRSO rata
/// wyszłaby [expectedInstallment], a z podanej raty RRSO wychodzi
/// [rrsoFromInstallment] (`null`, gdy raty nie pokrywają kwoty).
class LoanMismatch extends LoanCheck {
  final double expectedInstallment;
  final double? rrsoFromInstallment;
  const LoanMismatch(this.expectedInstallment, this.rrsoFromInstallment);
}

/// Dane, z których nie da się nic sensownie policzyć.
class LoanInvalid extends LoanCheck {
  final String message;
  const LoanInvalid(this.message);
}

/// Matematyka pożyczki ratalnej z ratą stałą (ADR-036).
///
/// Cztery wielkości: kwota wypłacona, liczba rat, rata i RRSO — każdą da się
/// policzyć z trzech pozostałych. RRSO liczymy z przepływów, jak w ustawie
/// o kredycie konsumenckim: wypłata dziś = suma rat zdyskontowanych stopą
/// RRSO po czasie od wypłaty. Prowizja czy ubezpieczenie doliczone do rat
/// są więc w wyniku; koszty płacone osobno — nie (stąd możliwa różnica
/// z RRSO z umowy).
class LoanMath {
  LoanMath._();

  static const int maxCount = 600;
  static const double maxRrso = 1000;

  /// Dopuszczalna różnica raty przy sprawdzaniu — zaokrąglenia banku.
  static const double tolerance = 0.05;

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  /// Σ (1 + X)^(−t) po ratach: ile wart jest dziś 1 zł każdej raty.
  static double _factor(LoanSchedule s, int count, double rate) {
    if (rate == 0) return count.toDouble();
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      sum += math.pow(1 + rate, -s.yearsTo(i)).toDouble();
    }
    return sum;
  }

  static double installment(
    LoanSchedule s, {
    required double principal,
    required int count,
    required double rrso,
  }) => _round(principal / _factor(s, count, rrso / 100));

  static double principal(
    LoanSchedule s, {
    required double installment,
    required int count,
    required double rrso,
  }) => _round(installment * _factor(s, count, rrso / 100));

  /// RRSO (%) z kwoty, liczby rat i raty; `null`, gdy raty nie pokrywają
  /// kwoty (wyszłoby ujemne) albo koszt jest absurdalny (ponad [maxRrso]).
  static double? rrso(
    LoanSchedule s, {
    required double principal,
    required int count,
    required double installment,
  }) {
    final total = installment * count;
    if (total < principal - 0.005) return null;
    if ((total - principal).abs() < 0.005) return 0;
    var lo = 0.0, hi = maxRrso / 100;
    if (installment * _factor(s, count, hi) > principal) return null;
    for (var i = 0; i < 100; i++) {
      final mid = (lo + hi) / 2;
      if (installment * _factor(s, count, mid) > principal) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return _round((lo + hi) / 2 * 100);
  }

  /// Najmniejsza liczba rat, która spłaca kwotę; `null`, gdy rata nie
  /// wystarcza nawet na koszt pożyczki.
  static int? count(
    LoanSchedule s, {
    required double principal,
    required double installment,
    required double rrso,
  }) {
    final rate = rrso / 100;
    var factor = 0.0;
    for (var n = 1; n <= maxCount; n++) {
      factor += rate == 0
          ? 1
          : math.pow(1 + rate, -s.yearsTo(n - 1)).toDouble();
      if (installment * factor >= principal - 0.005) return n;
    }
    return null;
  }

  /// Ostatnia rata: przy 0% wyrównuje grosze zaokrągleń do pełnej kwoty
  /// (2000 zł na 12 rat = 11 × 166,67 + 166,63); przy oprocentowaniu —
  /// równa pozostałym.
  static double lastInstallment({
    required double principal,
    required int count,
    required double installment,
    required double rrso,
  }) {
    if (rrso != 0 || count < 2) return installment;
    final last = _round(principal - installment * (count - 1));
    return last > 0 ? last : installment;
  }

  /// Do spłaty łącznie — suma wszystkich rat.
  static double totalRepayment({
    required double principal,
    required int count,
    required double installment,
    required double rrso,
  }) => _round(
    installment * (count - 1) +
        lastInstallment(
          principal: principal,
          count: count,
          installment: installment,
          rrso: rrso,
        ),
  );

  /// Raty jako miesiące planu: kwota w każdym miesiącu harmonogramu, dzień
  /// tylko tam, gdzie różni się od dnia raty (krótszy miesiąc).
  static Map<String, PlanMonth> installmentMonths(PlanLoanTerms t) {
    final s = LoanSchedule.ofTerms(t);
    final last = lastInstallment(
      principal: t.principal,
      count: t.count,
      installment: t.installment,
      rrso: t.rrso,
    );
    return {
      for (var i = 0; i < t.count; i++)
        s.monthKeyOf(i): PlanMonth(
          amount: i == t.count - 1 ? last : t.installment,
          day: s.dateOf(i).day == t.day ? null : s.dateOf(i).day,
        ),
    };
  }

  /// Uzupełnia albo sprawdza dane: z trzech wartości liczy czwartą,
  /// a przy czterech sprawdza, czy rata zgadza się z RRSO.
  static LoanCheck solve(
    LoanSchedule s, {
    double? principal,
    int? count,
    double? installment,
    double? rrso,
  }) {
    if ((principal != null && principal <= 0) ||
        (installment != null && installment <= 0)) {
      return const LoanInvalid('Kwota i rata muszą być większe od zera');
    }
    if (count != null && (count < 1 || count > maxCount)) {
      return const LoanInvalid('Liczba rat: od 1 do $maxCount');
    }
    if (rrso != null && (rrso < 0 || rrso > maxRrso)) {
      return const LoanInvalid('RRSO: od 0 do 1000%');
    }
    final known = [principal, count, installment, rrso].nonNulls.length;
    if (known < 3) return LoanNeedsMore(3 - known);

    if (known == 3) {
      if (installment == null) {
        return LoanComputed(
          LoanField.installment,
          LoanMath.installment(
            s,
            principal: principal!,
            count: count!,
            rrso: rrso!,
          ),
        );
      }
      if (principal == null) {
        return LoanComputed(
          LoanField.principal,
          LoanMath.principal(
            s,
            installment: installment,
            count: count!,
            rrso: rrso!,
          ),
        );
      }
      if (count == null) {
        final n = LoanMath.count(
          s,
          principal: principal,
          installment: installment,
          rrso: rrso!,
        );
        return n == null
            ? const LoanInvalid('Ta rata nie spłaci pożyczki przy tym RRSO')
            : LoanComputed(LoanField.count, n);
      }
      final x = LoanMath.rrso(
        s,
        principal: principal,
        count: count,
        installment: installment,
      );
      return x == null
          ? const LoanInvalid(
              'Raty sumują się poniżej kwoty pożyczki — sprawdź ratę albo kwotę',
            )
          : LoanComputed(LoanField.rrso, x);
    }

    final expected = LoanMath.installment(
      s,
      principal: principal!,
      count: count!,
      rrso: rrso!,
    );
    if ((expected - installment!).abs() <= tolerance) {
      return const LoanConsistent();
    }
    return LoanMismatch(
      expected,
      LoanMath.rrso(
        s,
        principal: principal,
        count: count,
        installment: installment,
      ),
    );
  }
}
