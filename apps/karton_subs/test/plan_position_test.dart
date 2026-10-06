import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart' show Currency;

// Pozycja planu rocznego (ADR-035): kwoty żyją w miesiącach, pozycja niesie
// to, co wspólne.

PlanPosition _position({Map<String, PlanMonth>? months, int? day = 10}) =>
    PlanPosition(
      id: 'p1',
      budgetId: kBudgetHousehold,
      name: 'Czynsz',
      kind: PlanKind.expense,
      currency: Currency.EUR,
      categoryId: 'cat_dom',
      paymentMethod: 'ING',
      day: day,
      note: 'umowa do 2027',
      archived: true,
      months:
          months ??
          {
            '2027-02': const PlanMonth(amount: 200),
            '2026-12': const PlanMonth(amount: 150, day: 3),
            '2026-01': const PlanMonth(amount: 100),
          },
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 10, 6, 12),
    );

void main() {
  group('PlanPosition — zapis', () {
    test('JSON tam i z powrotem zachowuje wszystkie pola', () {
      final p = _position();
      final back = PlanPosition.fromJson(p.toJson());
      expect(back.id, 'p1');
      expect(back.budgetId, kBudgetHousehold);
      expect(back.name, 'Czynsz');
      expect(back.kind, PlanKind.expense);
      expect(back.currency, Currency.EUR);
      expect(back.categoryId, 'cat_dom');
      expect(back.paymentMethod, 'ING');
      expect(back.day, 10);
      expect(back.note, 'umowa do 2027');
      expect(back.archived, isTrue);
      expect(back.createdAt, DateTime(2026, 1, 2));
      expect(back.updatedAt, DateTime(2026, 10, 6, 12));
      expect(
        back.months.keys,
        unorderedEquals(['2026-01', '2026-12', '2027-02']),
      );
      expect(back.months['2026-12']!.amount, 150);
      expect(back.months['2026-12']!.day, 3);
      expect(back.months['2026-01']!.day, isNull);
    });

    test('miesiące zapisują się w kolejności kalendarzowej', () {
      final months = _position().toJson()['months'] as Map<String, dynamic>;
      expect(months.keys.toList(), ['2026-01', '2026-12', '2027-02']);
    });

    test('pola opcjonalne nie trafiają do zapisu, gdy ich brak', () {
      final json = PlanPosition(
        id: 'x',
        budgetId: kBudgetPersonal,
        name: 'Pensja',
        kind: PlanKind.income,
        currency: Currency.PLN,
        createdAt: DateTime(2026, 1, 1),
      ).toJson();
      expect(
        json.keys,
        unorderedEquals([
          'id',
          'budgetId',
          'name',
          'kind',
          'currency',
          'months',
          'createdAt',
        ]),
      );
    });

    test('STRAŻNIK: wartości rodzaju w zapisie się nie zmieniają', () {
      // Zmiana tych napisów = pozycje z kopii zapasowych zmieniają rodzaj.
      expect(PlanKind.income.wireName, 'income');
      expect(PlanKind.expense.wireName, 'expense');
    });

    test('nieznany rodzaj czyta się jako wydatek', () {
      expect(planKindFromWire('cosNowego'), PlanKind.expense);
      expect(planKindFromWire(null), PlanKind.expense);
    });
  });

  group('PlanPosition — miesiące', () {
    test('kwota i dzień miesiąca, z dniem pozycji jako domyślnym', () {
      final p = _position();
      expect(p.amountIn('2026-12'), 150);
      expect(p.amountIn('2026-05'), 0);
      expect(p.dayIn('2026-12'), 3);
      expect(p.dayIn('2026-01'), 10);
    });

    test('suma i średnia roku liczą tylko miesiące tego roku', () {
      final p = _position();
      expect(p.yearTotal(2026), 250);
      expect(p.yearAverage(2026), closeTo(250 / 12, 1e-9));
      expect(p.yearTotal(2027), 200);
      expect(p.yearTotal(2028), 0);
      expect(p.hasYear(2027), isTrue);
      expect(p.hasYear(2028), isFalse);
    });

    test('miesiące roku są posortowane', () {
      final keys = _position().monthsOfYear(2026).map((e) => e.key).toList();
      expect(keys, ['2026-01', '2026-12']);
    });

    test('klucz miesiąca ma stały format', () {
      expect(planMonthKey(2026, 3), '2026-03');
      expect(planMonthKey(2027, 12), '2027-12');
    });
  });
}
