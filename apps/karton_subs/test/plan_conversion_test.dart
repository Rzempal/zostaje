import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/spending_allocation_item.dart';
import 'package:karton_subs/models/subscription.dart'
    show BillingCycle, Currency;
import 'package:karton_subs/services/plan_conversion.dart';

// Konwersja starego modelu (kwota + cykl + korekty) na plan roczny (ADR-035).
// „Dziś" = 2026-10-06, więc okno lat to 2026–2027.

final _today = DateTime(2026, 10, 6);

BudgetEntry _e({
  String id = 'e1',
  String name = 'Pozycja',
  BudgetEntryType type = BudgetEntryType.recurringCost,
  double amount = 100,
  Currency currency = Currency.PLN,
  BillingCycle cycle = BillingCycle.monthly,
  int? customCycleDays,
  List<int>? cycleMonths,
  String? month,
  Map<String, MonthAmountOverride>? ov,
  int? installmentCount,
  DateTime? startDate,
  bool isActive = true,
  String? linkId,
  String? creditLinkId,
  bool deleted = false,
}) => BudgetEntry(
  id: id,
  name: name,
  type: type,
  amount: amount,
  currency: currency,
  cycle: cycle,
  customCycleDays: customCycleDays,
  cycleMonths: cycleMonths,
  month: month,
  monthOverrides: ov,
  installmentCount: installmentCount,
  startDate: startDate,
  isActive: isActive,
  dataDodania: DateTime(2026, 1, 1),
  linkId: linkId,
  creditLinkId: creditLinkId,
  deleted: deleted,
);

PlanConversionResult _convert(
  List<BudgetEntry> personal, [
  List<BudgetEntry> household = const [],
]) => PlanConversion.convert(
  entriesByBudget: {kBudgetPersonal: personal, kBudgetHousehold: household},
  today: _today,
);

PlanPosition _single(List<BudgetEntry> personal) {
  final r = _convert(personal);
  expect(r.positions, hasLength(1));
  return r.positions.single;
}

List<String> _keys(PlanPosition p) => p.months.keys.toList()..sort();

void main() {
  group('Konwersja — koszty i wpływy cykliczne', () {
    test('miesięczny sprzed okna → 24 miesiące okna, dzień z daty startu', () {
      final p = _single([_e(amount: 120, startDate: DateTime(2025, 3, 10))]);
      expect(_keys(p), hasLength(24));
      expect(_keys(p).first, '2026-01');
      expect(_keys(p).last, '2027-12');
      expect(p.months.values.every((m) => m.amount == 120), isTrue);
      expect(p.day, 10);
      expect(p.kind, PlanKind.expense);
    });

    test('start w trakcie okna → miesiące dopiero od startu', () {
      final p = _single([_e(startDate: DateTime(2026, 6, 15))]);
      expect(_keys(p).first, '2026-06');
      expect(_keys(p), hasLength(19));
    });

    test('bez daty startu → cały okres okna, bez dnia', () {
      final p = _single([_e()]);
      expect(_keys(p), hasLength(24));
      expect(p.day, isNull);
    });

    test('kwartalny → pełna kwota w miesiącach płatności', () {
      final p = _single([
        _e(
          amount: 300,
          cycle: BillingCycle.quarterly,
          startDate: DateTime(2025, 11, 15),
        ),
      ]);
      expect(_keys(p), [
        '2026-02', '2026-05', '2026-08', '2026-11', //
        '2027-02', '2027-05', '2027-08', '2027-11',
      ]);
      expect(p.months.values.every((m) => m.amount == 300), isTrue);
      expect(p.yearAverage(2026), closeTo(100, 1e-9));
    });

    test('roczny → jeden miesiąc w roku', () {
      final p = _single([
        _e(
          amount: 1200,
          cycle: BillingCycle.yearly,
          startDate: DateTime(2024, 3, 10),
        ),
      ]);
      expect(_keys(p), ['2026-03', '2027-03']);
      expect(p.yearAverage(2027), closeTo(100, 1e-9));
    });

    test('wybrane miesiące → te miesiące w obu latach', () {
      final p = _single([
        _e(
          amount: 90,
          cycle: BillingCycle.monthsOfYear,
          cycleMonths: const [1, 4, 9],
          startDate: DateTime(2025, 1, 5),
        ),
      ]);
      expect(_keys(p), [
        '2026-01', '2026-04', '2026-09', //
        '2027-01', '2027-04', '2027-09',
      ]);
      expect(p.yearTotal(2026), 270);
    });

    test('wybrane miesiące bez daty startu → od początku okna', () {
      final p = _single([
        _e(cycle: BillingCycle.monthsOfYear, cycleMonths: const [2, 8]),
      ]);
      expect(_keys(p), ['2026-02', '2026-08', '2027-02', '2027-08']);
    });

    test('kwartalny bez daty startu → od dnia dodania, z uwagą', () {
      final r = _convert([_e(amount: 300, cycle: BillingCycle.quarterly)]);
      expect(_keys(r.positions.single), [
        '2026-01', '2026-04', '2026-07', '2026-10', //
        '2027-01', '2027-04', '2027-07', '2027-10',
      ]);
      expect(r.notesOf(PlanNoteKind.remark), hasLength(1));
    });

    test('tygodniowy → średnia miesięczna w każdym miesiącu, z uwagą', () {
      final r = _convert([
        _e(
          amount: 50,
          cycle: BillingCycle.weekly,
          startDate: DateTime(2025, 1, 6),
        ),
      ]);
      final p = r.positions.single;
      expect(_keys(p), hasLength(24));
      expect(p.months['2026-02']!.amount, closeTo(50 * 52 / 12, 1e-9));
      expect(p.day, isNull);
      expect(r.notesOf(PlanNoteKind.remark), hasLength(1));
    });

    test('co N dni → średnia miesięczna', () {
      final p = _single([
        _e(
          amount: 70,
          cycle: BillingCycle.custom,
          customCycleDays: 14,
          startDate: DateTime(2025, 1, 1),
        ),
      ]);
      expect(p.months['2027-07']!.amount, closeTo(150, 1e-9));
    });

    test('start po oknie → miesiące roku startu', () {
      final p = _single([_e(startDate: DateTime(2028, 4, 1))]);
      expect(_keys(p).first, '2028-04');
      expect(_keys(p), hasLength(9));
    });

    test('STRAŻNIK: pełny rok bez korekt → średnia = dawna kwota/mies.', () {
      for (final cycle in BillingCycle.values) {
        final e = _e(
          amount: 240,
          cycle: cycle,
          customCycleDays: cycle == BillingCycle.custom ? 10 : null,
          cycleMonths: cycle == BillingCycle.monthsOfYear
              ? const [3, 6, 9, 12]
              : null,
          startDate: DateTime(2025, 2, 3),
        );
        final p = _single([e]);
        expect(
          p.yearAverage(2026),
          closeTo(e.monthlyAmount, 1e-9),
          reason: 'cykl ${cycle.name}',
        );
      }
    });
  });

  group('Konwersja — korekty miesięcy', () {
    test('kwota korekty zastępuje kwotę miesiąca, data zmienia dzień', () {
      final p = _single([
        _e(
          startDate: DateTime(2025, 1, 10),
          ov: {
            '2026-10': const MonthAmountOverride(amount: 6000),
            '2026-11': MonthAmountOverride(date: DateTime(2026, 11, 20)),
            '2026-12': MonthAmountOverride(
              amount: 50,
              date: DateTime(2026, 12, 3),
            ),
          },
        ),
      ]);
      expect(p.months['2026-10']!.amount, 6000);
      expect(p.dayIn('2026-10'), 10);
      expect(p.months['2026-11']!.amount, 100);
      expect(p.dayIn('2026-11'), 20);
      expect(p.months['2026-12']!.amount, 50);
      expect(p.dayIn('2026-12'), 3);
    });

    test('korekta spoza okna też przechodzi (dane wpisane ręcznie)', () {
      final p = _single([
        _e(ov: {'2028-02': const MonthAmountOverride(amount: 77)}),
      ]);
      expect(p.months['2028-02']!.amount, 77);
    });

    test('data korekty z innego miesiąca jest pomijana', () {
      final p = _single([
        _e(
          startDate: DateTime(2025, 1, 10),
          ov: {'2026-05': MonthAmountOverride(date: DateTime(2026, 6, 2))},
        ),
      ]);
      expect(p.dayIn('2026-05'), 10);
    });
  });

  group('Konwersja — raty, przelewy, wpływy jednorazowe', () {
    test('rata → wszystkie miesiące spłaty, także poza oknem', () {
      final short = _single([
        _e(
          type: BudgetEntryType.installment,
          amount: 226.21,
          installmentCount: 12,
          startDate: DateTime(2026, 9, 28),
        ),
      ]);
      expect(_keys(short).first, '2026-09');
      expect(_keys(short).last, '2027-08');
      expect(_keys(short), hasLength(12));
      expect(short.day, 28);

      final long = _single([
        _e(
          type: BudgetEntryType.installment,
          installmentCount: 36,
          startDate: DateTime(2026, 1, 15),
        ),
      ]);
      expect(_keys(long).last, '2028-12');
    });

    test('rata bez liczby rat → pominięta z uwagą', () {
      final r = _convert([
        _e(type: BudgetEntryType.installment, startDate: DateTime(2026, 1, 1)),
      ]);
      expect(r.positions, isEmpty);
      expect(r.notesOf(PlanNoteKind.skipped), hasLength(1));
    });

    test('przelew do domowego → wydatek, lustro w domowym → wpływ', () {
      final ov = {'2026-10': const MonthAmountOverride(amount: 500)};
      final r = _convert(
        [
          _e(
            id: 'tr',
            type: BudgetEntryType.householdTransfer,
            amount: 7700,
            linkId: 'L1',
            ov: ov,
            startDate: DateTime(2026, 6, 10),
          ),
        ],
        [
          _e(
            id: 'mir',
            type: BudgetEntryType.income,
            amount: 7700,
            linkId: 'L1',
            ov: ov,
            startDate: DateTime(2026, 6, 10),
          ),
        ],
      );
      final transfer = r.positions.firstWhere((p) => p.id == 'tr');
      final mirror = r.positions.firstWhere((p) => p.id == 'mir');
      expect(transfer.budgetId, kBudgetPersonal);
      expect(transfer.kind, PlanKind.expense);
      expect(transfer.amountIn('2026-10'), 500);
      expect(transfer.amountIn('2026-09'), 7700);
      expect(mirror.budgetId, kBudgetHousehold);
      expect(mirror.kind, PlanKind.income);
      expect(mirror.amountIn('2026-10'), 500);
    });

    test('premia → wpływ z jednym miesiącem i jego dniem', () {
      final p = _single([
        _e(
          type: BudgetEntryType.oneTimeIncome,
          amount: 2000,
          month: '2026-12',
          startDate: DateTime(2026, 12, 20),
        ),
      ]);
      expect(p.kind, PlanKind.income);
      expect(p.months.keys, ['2026-12']);
      expect(p.amountIn('2026-12'), 2000);
      expect(p.dayIn('2026-12'), 20);
      expect(p.day, isNull);
    });

    test('wpływ jednorazowy bez miesiąca → pominięty', () {
      final r = _convert([_e(type: BudgetEntryType.oneTimeIncome)]);
      expect(r.positions, isEmpty);
      expect(r.notesOf(PlanNoteKind.skipped), hasLength(1));
    });
  });

  group('Konwersja — co zostaje w starym zapisie', () {
    test('Bieżące i pozycje karty nie stają się pozycjami planu', () {
      final r = _convert([
        _e(
          id: 's',
          type: BudgetEntryType.spending,
          month: '2026-10',
          creditLinkId: 'C1',
        ),
        _e(
          id: 'm',
          type: BudgetEntryType.oneTimeIncome,
          month: '2026-10',
          creditLinkId: 'C1',
        ),
      ]);
      expect(r.positions, isEmpty);
      expect(r.notesOf(PlanNoteKind.spendingKept).single.entryId, 's');
      expect(r.notesOf(PlanNoteKind.cardKept).single.entryId, 'm');
    });

    test('nagrobki synchronizacji pomijane po cichu', () {
      final r = _convert([_e(deleted: true)]);
      expect(r.positions, isEmpty);
      expect(r.notes, isEmpty);
    });

    test('wstrzymana → archiwalna, z miesiącami', () {
      final p = _single([_e(isActive: false)]);
      expect(p.archived, isTrue);
      expect(p.months, isNotEmpty);
    });

    test('identyfikator i pola wspólne przechodzą bez zmian', () {
      final e = BudgetEntry(
        id: 'stare-id',
        name: 'Netflix rodzinny',
        type: BudgetEntryType.recurringCost,
        amount: 12,
        currency: Currency.EUR,
        categoryId: 'cat_rozrywka',
        paymentMethod: 'Revolut',
        note: 'konto wspólne',
        dataDodania: DateTime(2026, 2, 3),
        updatedAt: DateTime(2026, 9, 1),
      );
      final p = _single([e]);
      expect(p.id, 'stare-id');
      expect(p.name, 'Netflix rodzinny');
      expect(p.currency, Currency.EUR);
      expect(p.categoryId, 'cat_rozrywka');
      expect(p.paymentMethod, 'Revolut');
      expect(p.note, 'konto wspólne');
      expect(p.createdAt, DateTime(2026, 2, 3));
      expect(p.updatedAt, DateTime(2026, 9, 1));
    });
  });

  group('Planner „Na bieżące wydatki" → pozycje planu', () {
    final items = {
      kBudgetPersonal: const [
        SpendingAllocationItem(
          id: 'a',
          name: 'Jedzenie',
          amount: 1500,
          categoryId: 'cat_food',
          paymentMethod: 'Revolut',
        ),
        SpendingAllocationItem(
          id: 'b',
          name: 'Stara',
          amount: 99,
          deleted: true,
        ),
        SpendingAllocationItem(id: 'c', name: 'Pusta', amount: 0),
      ],
      kBudgetHousehold: const [
        SpendingAllocationItem(id: 'd', name: 'Paliwo', amount: 400),
      ],
    };

    test('każda pozycja koperty osobno, z kategorią i metodą, co miesiąc', () {
      final positions = PlanConversion.envelopePositions(
        itemsByBudget: items,
        currency: Currency.PLN,
        today: _today,
      );
      expect(positions.map((p) => p.id), ['envelope:a', 'envelope:d']);
      final food = positions.first;
      expect(food.budgetId, kBudgetPersonal);
      expect(food.kind, PlanKind.expense);
      expect(food.name, 'Jedzenie');
      expect(food.categoryId, 'cat_food');
      expect(food.paymentMethod, 'Revolut');
      expect(_keys(food), hasLength(24));
      expect(food.months.values.every((m) => m.amount == 1500), isTrue);
      expect(positions.last.budgetId, kBudgetHousehold);
    });

    test('pełna konwersja dokłada pozycje koperty do planu', () {
      final r = PlanConversion.convert(
        entriesByBudget: {
          kBudgetPersonal: [_e()],
        },
        today: _today,
        envelopeByBudget: items,
      );
      expect(r.positions.map((p) => p.id), containsAll(['e1', 'envelope:a']));
      expect(
        r.notesOf(PlanNoteKind.remark).map((n) => n.entryId),
        containsAll(['envelope:a', 'envelope:d']),
      );
    });
  });

  group('Raport konwersji', () {
    PlanConversionReport report(List<BudgetEntry> personal) {
      final old = {kBudgetPersonal: personal};
      return PlanConversionReport.build(
        entriesByBudget: old,
        result: PlanConversion.convert(entriesByBudget: old, today: _today),
        today: _today,
        target: Currency.PLN,
      );
    }

    test('kwartalny z niepełnym rokiem wykazany, miesięczny zgodny', () {
      final r = report([
        _e(id: 'm', name: 'Miesięczny', startDate: DateTime(2025, 1, 1)),
        _e(
          id: 'q',
          name: 'Kwartalny',
          amount: 300,
          cycle: BillingCycle.quarterly,
          startDate: DateTime(2026, 5, 10),
        ),
      ]);
      // 2026: stary model rozkłada 100/mies. od maja (8 × 100 = 800), nowy
      // plan pokazuje płatności maj/sierpień/listopad (3 × 300 = 900).
      // 2027 to pełny rok — obie strony dają 1200.
      expect(r.mismatches, hasLength(1));
      final m = r.mismatches.single;
      expect(m.name, 'Kwartalny');
      expect(m.year, 2026);
      expect(m.oldTotal, closeTo(800, 1e-9));
      expect(m.newTotal, closeTo(900, 1e-9));
      expect(m.detail, contains('kwartalny'));
      expect(m.detail, contains('start 2026-05'));
    });

    test('korekta kwoty: suma roku zgodna po obu stronach', () {
      final r = report([
        _e(
          startDate: DateTime(2025, 1, 1),
          ov: {'2026-10': const MonthAmountOverride(amount: 6000)},
        ),
      ]);
      expect(r.mismatches, isEmpty);
      final y2026 = r.years.firstWhere((y) => y.year == 2026);
      expect(y2026.oldExpense, closeTo(7100, 1e-9));
      expect(y2026.newExpense, closeTo(7100, 1e-9));
    });

    test('wpływy liczone osobno i przeliczone na walutę docelową', () {
      final r = report([
        _e(
          type: BudgetEntryType.income,
          amount: 1000,
          currency: Currency.EUR,
          startDate: DateTime(2025, 1, 1),
        ),
      ]);
      final y2026 = r.years.firstWhere((y) => y.year == 2026);
      expect(y2026.newIncome, closeTo(12 * 1000 * 4.28, 1e-6));
      expect(y2026.oldIncome, closeTo(y2026.newIncome, 1e-6));
      expect(y2026.newExpense, 0);
    });

    test('wstrzymane, Bieżące i karta nie wchodzą do porównania', () {
      final r = report([
        _e(id: 'w', isActive: false),
        _e(id: 's', type: BudgetEntryType.spending, month: '2026-10'),
      ]);
      expect(r.mismatches, isEmpty);
      expect(
        r.years.every((y) => y.newExpense == 0 && y.oldExpense == 0),
        isTrue,
      );
    });
  });
}
