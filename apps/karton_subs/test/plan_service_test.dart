import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/budget_service.dart' show DayCashflow;
import 'package:karton_subs/services/plan_service.dart';

// Obliczenia planu rocznego (ADR-035): subskrypcje w miesiącach, sumy okresu,
// statystyki roku, kalendarz płatności i plan na kolejny rok.

const _svc = PlanService();
const _pln = Currency.PLN;

PlanPosition _pos(
  String id, {
  PlanKind kind = PlanKind.expense,
  Map<String, PlanMonth> months = const {},
  int? day,
  String? categoryId,
  bool archived = false,
  Currency currency = Currency.PLN,
}) => PlanPosition(
  id: id,
  budgetId: kBudgetPersonal,
  name: id,
  kind: kind,
  currency: currency,
  categoryId: categoryId,
  day: day,
  archived: archived,
  months: months,
  createdAt: DateTime(2026, 1, 1),
);

Map<String, PlanMonth> _everyMonth(int year, double amount) => {
  for (var m = 1; m <= 12; m++)
    planMonthKey(year, m): PlanMonth(amount: amount),
};

Subscription _sub(
  String id, {
  double amount = 40,
  BillingCycle cycle = BillingCycle.monthly,
  DateTime? start,
  bool isActive = true,
  DateTime? cancelledDate,
  int? sharedWith,
  bool isTrial = false,
  DateTime? trialEndDate,
  double? postTrialAmount,
  Currency currency = Currency.PLN,
  String? categoryId,
}) => Subscription(
  id: id,
  name: id,
  amount: amount,
  currency: currency,
  billingCycle: cycle,
  startDate: start ?? DateTime(2026, 1, 15),
  dataDodania: DateTime(2026, 1, 1),
  isActive: isActive,
  cancelledDate: cancelledDate,
  sharedWith: sharedWith,
  isTrial: isTrial,
  trialEndDate: trialEndDate,
  postTrialAmount: postTrialAmount,
  categoryId: categoryId,
);

void main() {
  group('Subskrypcje w miesiącach planu', () {
    test('miesięczna — płatność w dniu odnowienia', () {
      final pays = _svc.subscriptionPaymentsInMonth(_sub('s'), 2026, 10);
      expect(pays.single.date, DateTime(2026, 10, 15));
      expect(pays.single.amount, 40);
    });

    test('roczna — cała kwota w miesiącu odnowienia, średnia = /12', () {
      final s = _sub(
        'y',
        amount: 120,
        cycle: BillingCycle.yearly,
        start: DateTime(2025, 3, 10),
        currency: Currency.EUR,
      );
      expect(_svc.subscriptionAmountInMonth(s, 2026, 3), 120);
      expect(_svc.subscriptionAmountInMonth(s, 2026, 4), 0);
      expect(
        _svc.subscriptionAmount(s, const PlanPeriod(2026), _pln),
        closeTo(10 * 4.28, 1e-9),
      );
    });

    test('okres próbny nic nie kosztuje, potem kwota po okresie próbnym', () {
      final s = _sub(
        't',
        amount: 30,
        start: DateTime(2026, 9, 1),
        isTrial: true,
        trialEndDate: DateTime(2026, 9, 30),
        postTrialAmount: 35,
      );
      expect(_svc.subscriptionAmountInMonth(s, 2026, 9), 0);
      expect(_svc.subscriptionAmountInMonth(s, 2026, 10), 35);
    });

    test('anulowana — płatności do dnia anulowania', () {
      final s = _sub(
        'c',
        amount: 20,
        start: DateTime(2026, 1, 5),
        isActive: false,
        cancelledDate: DateTime(2026, 6, 10),
      );
      expect(_svc.subscriptionAmountInMonth(s, 2026, 6), 20);
      expect(_svc.subscriptionAmountInMonth(s, 2026, 7), 0);
    });

    test('anulowana bez daty — brak płatności', () {
      final s = _sub('x', isActive: false);
      expect(_svc.subscriptionAmountInMonth(s, 2026, 3), 0);
    });

    test('współdzielona — w planie twoja część, płatność w pełnej kwocie', () {
      final s = _sub('w', amount: 60, sharedWith: 3);
      expect(_svc.subscriptionPaymentsInMonth(s, 2026, 5).single.amount, 60);
      expect(_svc.subscriptionAmountInMonth(s, 2026, 5), 20);
    });
  });

  group('Sumy okresu', () {
    final positions = [
      _pos('pensja', kind: PlanKind.income, months: _everyMonth(2026, 10000)),
      _pos('czynsz', months: _everyMonth(2026, 2000)),
      _pos(
        'ubezpieczenie',
        categoryId: 'cat_x',
        months: {'2026-03': const PlanMonth(amount: 1200)},
      ),
      _pos(
        'pozyczka',
        kind: PlanKind.cardLoan,
        months: {'2026-01': const PlanMonth(amount: 3000)},
      ),
      _pos(
        'splata',
        kind: PlanKind.cardRepayment,
        months: {'2026-02': const PlanMonth(amount: 3000)},
      ),
      _pos('ukryta', archived: true, months: _everyMonth(2026, 999)),
    ];
    final subs = [_sub('netflix', categoryId: 'cat_streaming')];

    PlanMonthTotals month(int m) => _svc.monthTotals(
      positions: positions,
      subscriptions: subs,
      envelope: 1500,
      year: 2026,
      month: m,
      target: _pln,
    );

    test('miesiąc: składniki osobno, archiwalne pominięte', () {
      final jan = month(1);
      expect(jan.income, 10000);
      expect(jan.expense, 2000);
      expect(jan.envelope, 1500);
      expect(jan.subscriptions, 40);
      expect(jan.cardLoans, 3000);
      expect(jan.cardRepayments, 0);
      expect(jan.left, closeTo(10000 - 3540 + 3000, 1e-9));
      expect(month(3).expense, 3200);
    });

    test('rok: średnia miesięczna, karta znosi się w skali roku', () {
      final stats = _svc.yearStats(
        positions: positions,
        subscriptions: subs,
        envelope: 1500,
        year: 2026,
        target: _pln,
      );
      final avg = stats.average;
      expect(avg.income, closeTo(10000, 1e-9));
      expect(avg.expense, closeTo((2000 * 12 + 1200) / 12, 1e-9));
      expect(stats.total.cardNet, 0);
      expect(avg.left, closeTo(10000 - 2100 - 1500 - 40, 1e-9));
    });

    test('kategorie: średnio/mies., z kopertą i subskrypcjami, bez karty', () {
      final byCat = _svc
          .yearStats(
            positions: positions,
            subscriptions: subs,
            envelope: 1500,
            year: 2026,
            target: _pln,
          )
          .expenseByCategory;
      expect(byCat['cat_x'], closeTo(100, 1e-9));
      expect(byCat[null], closeTo(2000, 1e-9));
      expect(byCat[PlanService.envelopeCategoryKey], 1500);
      expect(byCat['cat_streaming'], closeTo(40, 1e-9));
      expect(byCat.length, 4);
    });

    test('kwota pozycji: miesiąc wprost, rok jako średnia, w walucie celu', () {
      final p = _pos(
        'eur',
        currency: Currency.EUR,
        months: {'2026-06': const PlanMonth(amount: 120)},
      );
      expect(
        _svc.positionAmount(p, const PlanPeriod(2026, 6), _pln),
        closeTo(120 * 4.28, 1e-9),
      );
      expect(
        _svc.positionAmount(p, const PlanPeriod(2026), _pln),
        closeTo(10 * 4.28, 1e-9),
      );
      expect(_svc.positionAmount(p, const PlanPeriod(2026, 7), _pln), 0);
    });
  });

  group('Kalendarz płatności', () {
    Map<int, DayCashflow> calendar({
      List<PlanPosition> positions = const [],
      List<Subscription> subs = const [],
      List<BudgetEntry> spending = const [],
      DateTime? month,
    }) => _svc.calendarForMonth(
      positions: positions,
      subscriptions: subs,
      spending: spending,
      month: month ?? DateTime(2026, 10),
      target: _pln,
    );

    test('pozycja z dniem trafia na swój dzień z identyfikatorem pozycji', () {
      final cal = calendar(
        positions: [
          _pos(
            'czynsz',
            day: 10,
            months: {'2026-10': const PlanMonth(amount: 2000)},
          ),
        ],
      );
      final item = cal[10]!.items.single;
      // Identyfikator = klucz odhaczenia płatności — po konwersji ze starego
      // modelu pozycja ma TEN SAM identyfikator, więc odhaczenia zostają.
      expect(item.sourceId, 'czynsz');
      expect(item.amount, 2000);
      expect(item.isIncome, isFalse);
    });

    test(
      'dzień miesiąca wygrywa z dniem pozycji, za długi dzień się przycina',
      () {
        final cal = calendar(
          month: DateTime(2027, 2),
          positions: [
            _pos(
              'pensja',
              kind: PlanKind.income,
              day: 31,
              months: {'2027-02': const PlanMonth(amount: 5000)},
            ),
            _pos(
              'prad',
              day: 5,
              months: {'2027-02': const PlanMonth(amount: 300, day: 20)},
            ),
          ],
        );
        expect(cal[28]!.items.single.isIncome, isTrue);
        expect(cal[20]!.items.single.sourceId, 'prad');
        expect(cal[5], isNull);
      },
    );

    test('bez dnia i archiwalne — poza kalendarzem', () {
      final cal = calendar(
        positions: [
          _pos('bez-dnia', months: {'2026-10': const PlanMonth(amount: 50)}),
          _pos(
            'ukryta',
            day: 3,
            archived: true,
            months: {'2026-10': const PlanMonth(amount: 50)},
          ),
        ],
      );
      expect(cal, isEmpty);
    });

    test('subskrypcja w pełnej kwocie, wydatek z Bieżących, karta', () {
      final cal = calendar(
        subs: [_sub('netflix', amount: 60, sharedWith: 2)],
        spending: [
          BudgetEntry(
            id: 'zakupy',
            name: 'Zakupy',
            type: BudgetEntryType.spending,
            amount: 80,
            currency: _pln,
            startDate: DateTime(2026, 10, 3),
            month: '2026-10',
            dataDodania: DateTime(2026, 10, 3),
          ),
        ],
        positions: [
          _pos(
            'pozyczka',
            kind: PlanKind.cardLoan,
            months: {'2026-10': const PlanMonth(amount: 3000, day: 7)},
          ),
          _pos(
            'splata',
            kind: PlanKind.cardRepayment,
            months: {'2026-10': const PlanMonth(amount: 3000, day: 25)},
          ),
        ],
      );
      expect(cal[15]!.items.single.amount, 60);
      expect(cal[3]!.items.single.sourceId, 'zakupy');
      expect(cal[7]!.items.single.isIncome, isTrue);
      expect(cal[25]!.items.single.isIncome, isFalse);
    });
  });

  group('Plan na kolejny rok', () {
    test('pełny rok i pozycja roczna — domyślnie do przeniesienia', () {
      expect(
        _svc.defaultCopySelected(_pos('m', months: _everyMonth(2026, 1)), 2026),
        isTrue,
      );
      final yearly = _pos(
        'r',
        months: {
          '2026-03': const PlanMonth(amount: 1200),
          '2027-03': const PlanMonth(amount: 1200),
        },
      );
      // Ma już miesiąc w 2027 — z 2026 nie ma czego przenosić…
      expect(_svc.defaultCopySelected(yearly, 2026), isFalse);
      // …ale z 2027 na 2028 tak: marzec to nie „urwany ciąg od stycznia".
      expect(_svc.defaultCopySelected(yearly, 2027), isTrue);
    });

    test('kończące się raty, archiwalne i karta — domyślnie odznaczone', () {
      final installment = _pos(
        'rata',
        months: {
          for (var i = 0; i < 12; i++)
            BudgetEntry.monthKeyOf(DateTime(2026, 9 + i)): const PlanMonth(
              amount: 226.21,
            ),
        },
      );
      expect(_svc.defaultCopySelected(installment, 2027), isFalse);
      expect(
        _svc.defaultCopySelected(
          _pos('a', archived: true, months: _everyMonth(2026, 1)),
          2026,
        ),
        isFalse,
      );
      expect(
        _svc.defaultCopySelected(
          _pos(
            'k',
            kind: PlanKind.cardLoan,
            months: {'2026-01': const PlanMonth(amount: 1)},
          ),
          2026,
        ),
        isFalse,
      );
    });

    test('przeniesienie nie nadpisuje miesięcy już obecnych w nowym roku', () {
      final p = _pos(
        'p',
        months: {
          ..._everyMonth(2026, 100),
          '2027-01': const PlanMonth(amount: 150),
        },
      );
      final months = _svc.monthsWithYearCopied(p, 2026, 2027);
      expect(months['2027-01']!.amount, 150);
      expect(months['2027-12']!.amount, 100);
      expect(months.keys.where((k) => k.startsWith('2027-')), hasLength(12));
    });

    test('lata filtra: z danych plus bieżący i następny', () {
      final years = _svc.yearsFor([
        _pos('x', months: {'2029-05': const PlanMonth(amount: 1)}),
      ], DateTime(2026, 10, 6));
      expect(years, [2026, 2027, 2029]);
    });

    test('termin spłaty karty: dzień użycia + okres bezodsetkowy', () {
      expect(
        PlanService.repaymentDateFor(DateTime(2027, 1, 15), 52),
        DateTime(2027, 3, 8),
      );
      expect(
        PlanService.repaymentDateFor(DateTime(2027, 1, 15), null),
        DateTime(2027, 2, 14),
      );
    });
  });
}
