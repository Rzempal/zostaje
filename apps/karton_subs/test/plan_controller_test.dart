import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/controllers/budget_controller.dart';
import 'package:karton_subs/controllers/plan_controller.dart';
import 'package:karton_subs/controllers/subscription_controller.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/category.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/notification_service.dart';
import 'package:karton_subs/services/plan_service.dart' show PlanPeriod;
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
    budget.setBudget(kBudgetHousehold);
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
        (p) => p.kind == PlanKind.loan,
      );
      final pair = plan.loanPair(loan.linkId!);
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
      final edited = plan.loanPair(loan.linkId!);
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

  group('Okres pozycji (rata, start)', () {
    Future<PlanPosition> addRata() => plan.create(
      name: 'Fold 8',
      kind: PlanKind.expense,
      currency: Currency.PLN,
      months: {
        // Styczeń 2026 jest przed startem — formularz by go nie przepuścił,
        // ale kontroler też nie może.
        '2026-01': const PlanMonth(amount: 226.21),
        for (var m = 9; m <= 12; m++)
          planMonthKey(2026, m): const PlanMonth(amount: 226.21),
      },
      periodStart: '2026-09',
      periodEnd: '2027-07',
    );

    test('nowa pozycja nie dostaje miesięcy spoza okresu', () async {
      final p = await addRata();
      expect(p.periodEnd, '2027-07');
      expect(plan.position(p.id)!.months.keys, isNot(contains('2026-01')));
      expect(plan.position(p.id)!.months, hasLength(4));
    });

    test('wypełnianie pomija miesiące poza okresem i liczy zmiany', () async {
      final p = await addRata();
      final n = await plan.setMonths(p.id, {
        '2026-08': const PlanMonth(amount: 1),
        '2027-07': const PlanMonth(amount: 226.21),
        '2027-08': const PlanMonth(amount: 1),
      });
      expect(n, 1);
      final after = plan.position(p.id)!;
      expect(after.months.containsKey('2026-08'), isFalse);
      expect(after.months.containsKey('2027-08'), isFalse);
      expect(after.amountIn('2027-07'), 226.21);
    });

    test('zawężenie okresu w edycji usuwa miesiące spoza niego', () async {
      final p = await addRata();
      await plan.update(plan.position(p.id)!.copyWith(periodEnd: '2026-10'));
      expect(plan.position(p.id)!.months.keys, ['2026-09', '2026-10']);
    });

    test('zakończona rata nie jest kandydatem do kolejnego roku', () async {
      final p = await addRata();
      await plan.update(plan.position(p.id)!.copyWith(periodEnd: '2026-12'));
      await addMonthly('Czynsz');
      expect(plan.copyCandidates(2026).map((e) => e.name), ['Czynsz']);
    });

    test('kopiowanie roku nie wydłuża raty poza jej koniec', () async {
      final p = await addRata();
      await plan.copyYear(2026, 2027, {p.id});
      final keys2027 = plan.position(p.id)!.monthsOfYear(2027).map((e) => e.key);
      // Wrzesień–grudzień 2026 przeniesione na 2027 tylko w okresie
      // (do lipca) — w 2027 nic z tego nie mieści się w okresie.
      expect(keys2027, isEmpty);
    });
  });

  group('Pożyczka ratalna (ADR-036)', () {
    PlanLoanTerms terms({int count = 12, double installment = 166.67}) =>
        PlanLoanTerms(
          principal: 2000,
          count: count,
          installment: installment,
          rrso: 0,
          drawdown: DateTime(2026, 9, 13),
          firstMonth: '2026-10',
          day: 13,
        );

    Future<String> addDreamy({bool purchase = true}) =>
        plan.saveInstallmentLoan(
          name: 'Odkurzacz',
          currency: Currency.PLN,
          paymentMethod: 'ING',
          terms: terms(),
          purchase: purchase ? (amount: 2000, categoryId: 'cat_dom') : null,
        );

    test('wypłata, raty z okresem i zakup — spięte jednym linkId', () async {
      final link = await addDreamy();
      final parts = plan.loanParts(link);

      expect(parts.loan!.amountIn('2026-09'), 2000);
      expect(parts.loan!.dayIn('2026-09'), 13);
      final rep = parts.repayment!;
      expect(rep.months, hasLength(12));
      expect(rep.amountIn('2027-09'), 166.63);
      expect(rep.periodStart, '2026-10');
      expect(rep.periodEnd, '2027-09');
      expect(rep.loanTerms!.count, 12);
      expect(parts.purchase!.kind, PlanKind.expense);
      expect(parts.purchase!.categoryId, 'cat_dom');
      expect(parts.purchase!.amountIn('2026-09'), 2000);
    });

    test('raty w Pożyczkach, zakup w Wydatkach — koszt liczy się raz', () async {
      await addDreamy();
      final sep = plan.totals(const PlanPeriod(2026, 9));
      expect(sep.expense, 2000);
      expect(sep.loansNet, 2000);
      final oct = plan.totals(const PlanPeriod(2026, 10));
      expect(oct.expense, 0);
      expect(oct.loansNet, -166.67);
    });

    test('edycja warunków przelicza raty; zakup zostaje osobną pozycją',
        () async {
      final link = await addDreamy();
      await plan.saveInstallmentLoan(
        linkId: link,
        name: 'Odkurzacz',
        currency: Currency.PLN,
        terms: terms(count: 10, installment: 200),
      );
      final parts = plan.loanParts(link);
      expect(parts.repayment!.months, hasLength(10));
      expect(parts.repayment!.periodEnd, '2027-07');
      // Zakup zmienia się i usuwa na jego ekranie — zapis pożyczki go nie rusza.
      expect(parts.purchase!.amountIn('2026-09'), 2000);
      expect(plan.positions.where((p) => p.linkId == link), hasLength(3));
    });

    test('zakup w dniu wypłaty idzie za jej nową datą, przestawiony zostaje',
        () async {
      final link = await addDreamy();
      PlanLoanTerms drawnOn(DateTime day) => PlanLoanTerms(
        principal: 2000,
        count: 12,
        installment: 166.67,
        rrso: 0,
        drawdown: day,
        firstMonth: '2026-11',
        day: 13,
      );

      await plan.saveInstallmentLoan(
        linkId: link,
        name: 'Odkurzacz',
        currency: Currency.PLN,
        terms: drawnOn(DateTime(2026, 10, 2)),
      );
      var purchase = plan.loanParts(link).purchase!;
      expect(purchase.months.keys, ['2026-10']);
      expect(purchase.dayIn('2026-10'), 2);

      // Przestawiony ręcznie na inny miesiąc — zostaje, gdzie jest.
      await plan.setMonths(purchase.id, {
        '2026-10': null,
        '2026-12': const PlanMonth(amount: 2000, day: 5),
      });
      await plan.saveInstallmentLoan(
        linkId: link,
        name: 'Odkurzacz',
        currency: Currency.PLN,
        terms: drawnOn(DateTime(2026, 10, 20)),
      );
      purchase = plan.loanParts(link).purchase!;
      expect(purchase.months.keys, ['2026-12']);
    });

    test('ręcznie poprawiona rata jest wykrywana przed nadpisaniem', () async {
      final link = await addDreamy();
      expect(plan.loanInstallmentsEdited(link), isFalse);
      final rep = plan.loanParts(link).repayment!;
      await plan.setMonths(rep.id, {
        '2026-12': const PlanMonth(amount: 180),
      });
      expect(plan.loanInstallmentsEdited(link), isTrue);
    });

    test('usunięcie pożyczki: zakup zostaje albo znika — na życzenie', () async {
      final kept = await addDreamy();
      await plan.deleteLoan(kept, withPurchase: false);
      final purchase = plan.positions.single;
      expect(purchase.kind, PlanKind.expense);
      expect(purchase.linkId, isNull);

      final gone = await addDreamy();
      await plan.deleteLoan(gone, withPurchase: true);
      expect(plan.positions.where((p) => p.linkId == gone), isEmpty);
    });

    test('usunięcie samego zakupu nie kasuje pożyczki', () async {
      final link = await addDreamy();
      await plan.deleteAll({plan.loanParts(link).purchase!.id});
      final parts = plan.loanParts(link);
      expect(parts.loan, isNotNull);
      expect(parts.repayment, isNotNull);
      expect(parts.purchase, isNull);
    });

    test('zakup z pożyczki nie jest kandydatem do kolejnego roku', () async {
      await addDreamy();
      expect(plan.copyCandidates(2026), isEmpty);
    });
  });

  test('kaskady słowników z Ustawień — tylko w budżecie słownika', () async {
    await storage.saveCategory(
      const Category(
        id: 'cat_old',
        name: 'Stara',
        colorHex: '#64748B',
        iconName: 'folder',
        order: 50,
        budgetId: kBudgetPersonal,
      ),
    );
    final p = await plan.create(
      name: 'Internet',
      kind: PlanKind.expense,
      currency: Currency.PLN,
      months: {'2026-10': const PlanMonth(amount: 60)},
      paymentMethod: 'ING',
      categoryId: 'cat_old',
    );
    // Ta sama nazwa metody w innym budżecie to inna metoda (ADR-038).
    await storage.savePlanPosition(
      PlanPosition(
        id: 'prad',
        budgetId: kBudgetHousehold,
        name: 'Prąd',
        kind: PlanKind.expense,
        currency: Currency.PLN,
        months: const {'2026-10': PlanMonth(amount: 200)},
        paymentMethod: 'ING',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    expect(budget.countPaymentMethodUsage(kBudgetPersonal, 'ING'), 1);
    expect(budget.countCategoryUsage('cat_old'), 1);

    await budget.renamePaymentMethod(kBudgetPersonal, 'ING', 'ING konto');
    expect(plan.position(p.id)!.paymentMethod, 'ING konto');
    expect(storage.getPlanPosition('prad')!.paymentMethod, 'ING');

    // Usunięta kategoria oddaje pozycje do „Inne" swojego budżetu.
    await budget.deleteCategory(storage.getCategory('cat_old')!);
    expect(plan.position(p.id)!.categoryId, 'cat_other');

    await budget.deletePaymentMethod(
      const PaymentMethod(
        id: 'pm_gone',
        name: 'ING konto',
        budgetId: kBudgetPersonal,
      ),
    );
    expect(plan.position(p.id)!.paymentMethod, isNull);
    expect(storage.getPlanPosition('prad')!.paymentMethod, 'ING');
  });

  // Bieżące odpadły (ADR-035): ich stare wydatki zostają w zapisie jako
  // archiwum, ale nie trafiają już do kalendarza.
  test('kalendarz: pozycje planu, bez starych wydatków z Bieżących', () async {
    await addMonthly('Czynsz', amount: 2000);
    await storage.saveBudgetEntry(
      BudgetEntry(
        id: 'zakupy',
        name: 'Zakupy',
        type: BudgetEntryType.spending,
        amount: 80,
        currency: Currency.PLN,
        cycle: BillingCycle.monthly,
        startDate: DateTime(2026, 10, 3),
        month: '2026-10',
        dataDodania: DateTime(2026, 10, 3),
      ),
      BudgetScope.personal,
    );
    final cal = plan.calendarForMonth(DateTime(2026, 10));
    expect(cal[10]!.items.single.name, 'Czynsz');
    expect(cal[3], isNull);
  });
}
