import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/controllers/budget_controller.dart';
import 'package:karton_subs/controllers/plan_controller.dart';
import 'package:karton_subs/controllers/subscription_controller.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/notification_service.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

// Kontroler planu rocznego (ADR-035) na prawdziwym Hive: zapis pozycji
// w aktywnym budżecie, miesiące, para karty, plan na kolejny rok i kaskady
// słowników z Ustawień.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late BudgetController budget;
  late PlanController plan;

  setUpAll(() async => storage = await setUpHiveStorage());
  tearDownAll(tearDownHiveStorage);

  setUp(() async {
    await resetStorage(storage);
    budget = BudgetController(
      storage,
      SubscriptionController(storage, NotificationService()),
    );
    plan = PlanController(storage, budget);
  });

  Future<PlanPosition> addMonthly(String name, {double amount = 100}) =>
      plan.create(
        name: name,
        kind: PlanKind.expense,
        currency: Currency.PLN,
        months: {
          for (var m = 1; m <= 12; m++)
            planMonthKey(2026, m): PlanMonth(amount: amount),
        },
        day: 10,
      );

  test('pozycja trafia do aktywnego budżetu', () async {
    await addMonthly('Czynsz');
    budget.setScope(BudgetScope.household);
    await addMonthly('Prąd domowy');

    expect(plan.positions.single.name, 'Prąd domowy');
    expect(storage.getPlanPositions(kBudgetPersonal).single.name, 'Czynsz');
  });

  test('miesiące: zmiana, dodanie i usunięcie jedną operacją', () async {
    final p = await addMonthly('Prąd');
    await plan.setMonths(p.id, {
      '2026-07': const PlanMonth(amount: 180),
      '2027-01': const PlanMonth(amount: 120, day: 3),
      '2026-12': null,
    });
    final after = plan.position(p.id)!;
    expect(after.amountIn('2026-07'), 180);
    expect(after.amountIn('2026-06'), 100);
    expect(after.dayIn('2027-01'), 3);
    expect(after.months.containsKey('2026-12'), isFalse);
  });

  test(
    'pożyczka z karty: para, edycja bez duplikatów, usuwanie w parze',
    () async {
      await plan.saveCardLoan(
        name: 'Gotówka styczeń',
        card: 'PKO',
        currency: Currency.PLN,
        useDate: DateTime(2027, 1, 15),
        amount: 3000,
        repaymentDate: DateTime(2027, 2, 25),
        repaymentAmount: 3090,
      );
      final loan = plan.positions.singleWhere(
        (p) => p.kind == PlanKind.cardLoan,
      );
      final pair = plan.cardPair(loan.linkId!);
      expect(pair.loan!.amountIn('2027-01'), 3000);
      expect(pair.repayment!.amountIn('2027-02'), 3090);
      expect(pair.repayment!.dayIn('2027-02'), 25);

      await plan.saveCardLoan(
        linkId: loan.linkId,
        name: 'Gotówka styczeń',
        card: 'PKO',
        currency: Currency.PLN,
        useDate: DateTime(2027, 1, 20),
        amount: 2500,
        repaymentDate: DateTime(2027, 3, 1),
        repaymentAmount: 2500,
      );
      expect(plan.positions, hasLength(2));
      final edited = plan.cardPair(loan.linkId!);
      expect(edited.repayment!.months.keys, ['2027-03']);
      expect(edited.loan!.amountIn('2027-01'), 2500);

      await plan.deleteAll({edited.loan!.id});
      expect(plan.positions, isEmpty);
    },
  );

  test('plan na kolejny rok dopisuje miesiące wybranym pozycjom', () async {
    final a = await addMonthly('A');
    final b = await addMonthly('B');
    final changed = await plan.copyYear(2026, 2027, {a.id});
    expect(changed, 1);
    expect(plan.position(a.id)!.hasYear(2027), isTrue);
    expect(plan.position(b.id)!.hasYear(2027), isFalse);
  });

  test('kaskady słowników z Ustawień obejmują plan', () async {
    final p = await plan.create(
      name: 'Internet',
      kind: PlanKind.expense,
      currency: Currency.PLN,
      months: {'2026-10': const PlanMonth(amount: 60)},
      paymentMethod: 'ING',
      categoryId: 'cat_old',
    );
    expect(budget.countPaymentMethodUsage('ING'), 1);
    expect(budget.countCategoryUsage('cat_old'), 1);

    await budget.renamePaymentMethodEverywhere('ING', 'ING konto');
    await budget.reassignCategoryEverywhere('cat_old', 'cat_new');
    expect(plan.position(p.id)!.paymentMethod, 'ING konto');
    expect(plan.position(p.id)!.categoryId, 'cat_new');

    await budget.clearPaymentMethodEverywhere('ING konto');
    expect(plan.position(p.id)!.paymentMethod, isNull);
  });

  // Bieżące odpadły (ADR-035): ich stare wydatki zostają w zapisie jako
  // archiwum, ale nie trafiają już do kalendarza.
  test('kalendarz: pozycje planu, bez starych wydatków z Bieżących', () async {
    await addMonthly('Czynsz', amount: 2000);
    await budget.create(
      name: 'Zakupy',
      type: BudgetEntryType.spending,
      amount: 80,
      currency: Currency.PLN,
      startDate: DateTime(2026, 10, 3),
      month: '2026-10',
    );
    final cal = plan.calendarForMonth(DateTime(2026, 10));
    expect(cal[10]!.items.single.name, 'Czynsz');
    expect(cal[3], isNull);
  });
}
