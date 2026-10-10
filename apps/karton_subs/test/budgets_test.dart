import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:karton_subs/controllers/budget_controller.dart';
import 'package:karton_subs/controllers/subscription_controller.dart';
import 'package:karton_subs/models/budget.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/notification_service.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

// Budżety z nazwami (ADR-037): lista, aktywny budżet, ukrywanie, usuwanie,
// przenoszenie i kopiowanie zawartości między budżetami.

late StorageService _storage;

BudgetController _controller() =>
    BudgetController(_storage, SubscriptionController(_storage, NotificationService()));

PlanPosition _pos(
  String id,
  String budgetId, {
  PlanKind kind = PlanKind.expense,
  String? linkId,
}) => PlanPosition(
  id: id,
  budgetId: budgetId,
  name: id,
  kind: kind,
  currency: Currency.PLN,
  months: const {'2026-10': PlanMonth(amount: 100)},
  linkId: linkId,
  createdAt: DateTime(2026, 1, 1),
);

Subscription _sub(String id, String budgetId) => Subscription(
  id: id,
  name: id,
  amount: 30,
  currency: Currency.PLN,
  billingCycle: BillingCycle.monthly,
  startDate: DateTime(2026, 1, 5),
  dataDodania: DateTime(2026, 1, 1),
  budgetId: budgetId,
);

void main() {
  setUpAll(() async => _storage = await setUpHiveStorage());
  tearDownAll(tearDownHiveStorage);
  setUp(() async {
    await resetStorage(_storage);
    await Hive.box('settings').delete('budgets');
    await Hive.box('settings').delete('budgetMode');
    await Hive.box('settings').delete('activeBudgetId');
  });

  group('Lista budżetów', () {
    test('start: „Osobisty" i „Domowy" z ikonami, aktywny osobisty', () {
      final b = _controller();
      expect(b.budgets.map((x) => x.name), ['Osobisty', 'Domowy']);
      expect(b.budgets.map((x) => x.icon), ['user', 'home']);
      expect(b.budgetId, kBudgetPersonal);
      expect(b.canSwitch, isTrue);
    });

    test('dawny tryb „tylko osobisty" → domowy ukryty', () async {
      await Hive.box('settings').put('budgetMode', 'personalOnly');
      final b = _controller();
      expect(b.visibleBudgets.map((x) => x.id), [kBudgetPersonal]);
      expect(b.budgetById(kBudgetHousehold)!.hidden, isTrue);
      expect(b.canSwitch, isFalse);
    });

    test('nowy budżet, nazwa i ikona, kolejność — zapisane', () async {
      final b = _controller();
      final firma = await b.addBudget('Firma', 'briefcase');
      await b.updateBudget(firma.copyWith(name: 'Firma JDG'));
      await b.reorderBudgets([firma.id, kBudgetPersonal, kBudgetHousehold]);

      final again = _controller();
      expect(again.budgets.map((x) => x.name), [
        'Firma JDG',
        'Osobisty',
        'Domowy',
      ]);
      expect(again.budgets.first.icon, 'briefcase');
    });

    test('wybrany budżet pamięta się między uruchomieniami', () {
      _controller().setBudget(kBudgetHousehold);
      expect(_controller().budgetId, kBudgetHousehold);
    });

    test('gest: kolejny i poprzedni widoczny budżet, bez wyjścia za listę',
        () async {
      final b = _controller();
      await b.addBudget('Firma', 'briefcase');
      b.stepBudget(1);
      expect(b.budgetId, kBudgetHousehold);
      b.stepBudget(1);
      expect(b.activeBudget.name, 'Firma');
      b.stepBudget(1);
      expect(b.activeBudget.name, 'Firma');
      b.stepBudget(-1);
      expect(b.budgetId, kBudgetHousehold);
    });

    test('ostatniego widocznego nie da się ukryć; ukryty aktywny ustępuje',
        () async {
      final b = _controller();
      expect(await b.setBudgetHidden(kBudgetPersonal, true), isTrue);
      expect(b.budgetId, kBudgetHousehold);
      expect(await b.setBudgetHidden(kBudgetHousehold, true), isFalse);
      expect(b.visibleBudgets.single.id, kBudgetHousehold);
    });
  });

  group('Przenoszenie i kopiowanie', () {
    test('przeniesienie pozycji zabiera odhaczone płatności', () async {
      final b = _controller();
      await _storage.savePlanPosition(_pos('czynsz', kBudgetPersonal));
      await _storage.setPaymentDone('personal|czynsz|2026-10-05', true);

      expect(await b.movePositions({'czynsz'}, kBudgetHousehold), 1);
      expect(_storage.getPlanPosition('czynsz')!.budgetId, kBudgetHousehold);
      expect(_storage.isPaymentDone('household|czynsz|2026-10-05'), isTrue);
      expect(_storage.isPaymentDone('personal|czynsz|2026-10-05'), isFalse);
    });

    test('pożyczka idzie w całości — wypłata, raty i zakup', () async {
      final b = _controller();
      await _storage.savePlanPosition(
        _pos('w', kBudgetPersonal, kind: PlanKind.loan, linkId: 'L'),
      );
      await _storage.savePlanPosition(
        _pos('r', kBudgetPersonal, kind: PlanKind.loanRepayment, linkId: 'L'),
      );
      await _storage.savePlanPosition(_pos('z', kBudgetPersonal, linkId: 'L'));

      expect(await b.movePositions({'w'}, kBudgetHousehold), 3);
      for (final id in ['w', 'r', 'z']) {
        expect(_storage.getPlanPosition(id)!.budgetId, kBudgetHousehold);
      }
    });

    test('kopia: nowe identyfikatory, nowe powiązanie pożyczki, bez odhaczeń',
        () async {
      final b = _controller();
      await _storage.savePlanPosition(
        _pos('w', kBudgetPersonal, kind: PlanKind.loan, linkId: 'L'),
      );
      await _storage.savePlanPosition(
        _pos('r', kBudgetPersonal, kind: PlanKind.loanRepayment, linkId: 'L'),
      );
      await _storage.setPaymentDone('personal|r|2026-10-13', true);

      expect(await b.copyPositions({'r'}, kBudgetHousehold), 2);
      final copies = _storage.getPlanPositions(kBudgetHousehold);
      expect(copies, hasLength(2));
      expect(copies.map((p) => p.id), isNot(contains('r')));
      final link = copies.first.linkId;
      expect(link, isNot('L'));
      expect(copies.every((p) => p.linkId == link), isTrue);
      expect(_storage.getPlanPositions(kBudgetPersonal), hasLength(2));
      expect(
        _storage.getAllPaymentDone().keys.where((k) => k.startsWith('household')),
        isEmpty,
      );
    });

    test('„wszystko": przeniesienie z subskrypcjami, kopia z wyborem', () async {
      final b = _controller();
      final firma = await b.addBudget('Firma', 'briefcase');
      await _storage.savePlanPosition(_pos('a', kBudgetPersonal));
      await _storage.saveSubscription(_sub('netflix', kBudgetPersonal));

      await b.copyAll(kBudgetPersonal, firma.id, withSubscriptions: false);
      expect(b.positionCountOf(firma.id), 1);
      expect(b.subscriptionsOf(firma.id), isEmpty);

      await b.copyAll(kBudgetPersonal, kBudgetHousehold);
      expect(b.subscriptionsOf(kBudgetHousehold), hasLength(1));
      expect(b.subscriptionsOf(kBudgetPersonal), hasLength(1));

      await b.moveAll(kBudgetPersonal, firma.id);
      expect(b.positionCountOf(kBudgetPersonal), 0);
      expect(b.subscriptionsOf(kBudgetPersonal), isEmpty);
      expect(b.positionCountOf(firma.id), 2);
      expect(b.subscriptionsOf(firma.id).single.name, 'netflix');
    });
  });

  group('Duplikowanie (w tym samym budżecie)', () {
    test('pozycja: kopia obok, z dopiskiem, bez odhaczeń', () async {
      final b = _controller();
      await _storage.savePlanPosition(_pos('czynsz', kBudgetHousehold));
      await _storage.setPaymentDone('household|czynsz|2026-10-05', true);

      final copies = await b.duplicatePositions({'czynsz'});
      final copy = _storage.getPlanPosition(copies['czynsz']!)!;
      expect(copy.id, isNot('czynsz'));
      expect(copy.budgetId, kBudgetHousehold);
      expect(copy.name, 'czynsz (kopia)');
      expect(copy.months.keys, ['2026-10']);
      expect(copy.months['2026-10']!.amount, 100);
      expect(_storage.getPlanPositions(kBudgetHousehold), hasLength(2));
      expect(_storage.getAllPaymentDone().keys, [
        'household|czynsz|2026-10-05',
      ]);
    });

    test('pożyczka w całości, z nowym powiązaniem', () async {
      final b = _controller();
      await _storage.savePlanPosition(
        _pos('w', kBudgetPersonal, kind: PlanKind.loan, linkId: 'L'),
      );
      await _storage.savePlanPosition(
        _pos('r', kBudgetPersonal, kind: PlanKind.loanRepayment, linkId: 'L'),
      );

      final link = await b.duplicateLoan('r');
      expect(link, isNotNull);
      expect(link, isNot('L'));
      final copies = _storage
          .getPlanPositions(kBudgetPersonal)
          .where((p) => p.linkId == link)
          .toList();
      expect(
        copies.map((p) => p.kind),
        unorderedEquals([PlanKind.loan, PlanKind.loanRepayment]),
      );
      expect(copies.every((p) => p.name.endsWith(' (kopia)')), isTrue);
    });

    test('subskrypcja: nowy identyfikator, ten sam budżet', () async {
      final b = _controller();
      final original = _sub('netflix', kBudgetHousehold);
      await _storage.saveSubscription(original);

      final copy = await b.duplicateSubscription(original);
      expect(copy.id, isNot('netflix'));
      expect(copy.name, 'netflix (kopia)');
      expect(b.subscriptionsOf(kBudgetHousehold), hasLength(2));
    });
  });

  group('Usuwanie', () {
    test('budżet znika razem z pozycjami, subskrypcjami i odhaczeniami',
        () async {
      final b = _controller();
      final firma = await b.addBudget('Firma', 'briefcase');
      b.setBudget(firma.id);
      await _storage.savePlanPosition(_pos('a', firma.id));
      await _storage.saveSubscription(_sub('s', firma.id));
      await _storage.setPaymentDone('${firma.id}|a|2026-10-01', true);

      expect(await b.deleteBudget(firma.id), isTrue);
      expect(b.budgetById(firma.id), isNull);
      expect(_storage.getPlanPositions(firma.id), isEmpty);
      expect(b.subscriptionsOf(firma.id), isEmpty);
      expect(_storage.getAllPaymentDone(), isEmpty);
      // Aktywny usunięty — przełącznik wraca do pierwszego widocznego.
      expect(b.budgetId, kBudgetPersonal);
    });

    test('ostatniego budżetu usunąć się nie da', () async {
      final b = _controller();
      expect(await b.deleteBudget(kBudgetHousehold), isTrue);
      expect(await b.deleteBudget(kBudgetPersonal), isFalse);
      expect(b.budgets.single.id, kBudgetPersonal);
    });
  });

  test('subskrypcje aktywnego budżetu — tylko jego', () async {
    final b = _controller();
    await _storage.saveSubscription(_sub('p', kBudgetPersonal));
    await _storage.saveSubscription(_sub('h', kBudgetHousehold));
    expect(b.subscriptions.single.id, 'p');
    b.setBudget(kBudgetHousehold);
    expect(b.subscriptions.single.id, 'h');
  });

  test('domyślne budżety mają identyfikatory dawnych zakresów', () {
    expect(Budget.defaults.map((b) => b.id), [kBudgetPersonal, kBudgetHousehold]);
  });
}
