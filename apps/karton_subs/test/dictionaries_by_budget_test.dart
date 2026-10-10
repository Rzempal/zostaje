import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/controllers/budget_controller.dart';
import 'package:karton_subs/controllers/subscription_controller.dart';
import 'package:karton_subs/models/category.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/notification_service.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

// Kategorie i metody płatności osobne dla każdego budżetu (ADR-038): podział
// danych sprzed zmiany i etykiety przy przenoszeniu między budżetami.

late StorageService _storage;

BudgetController _controller() => BudgetController(
  _storage,
  SubscriptionController(_storage, NotificationService()),
);

Category _cat(String id, String name, {String? budgetId}) => Category(
  id: id,
  name: name,
  colorHex: '#64748B',
  iconName: 'folder',
  order: 0,
  budgetId: budgetId,
);

PlanPosition _pos(
  String id,
  String budgetId, {
  String? categoryId,
  String? method,
}) => PlanPosition(
  id: id,
  budgetId: budgetId,
  name: id,
  kind: PlanKind.expense,
  currency: Currency.PLN,
  months: const {'2026-10': PlanMonth(amount: 100)},
  categoryId: categoryId,
  paymentMethod: method,
  createdAt: DateTime(2026, 1, 1),
);

Subscription _sub(String budgetId, {String? categoryId, String? method}) =>
    Subscription(
      id: 'netflix',
      name: 'Netflix',
      amount: 60,
      currency: Currency.PLN,
      billingCycle: BillingCycle.monthly,
      startDate: DateTime(2026, 1, 1),
      dataDodania: DateTime(2026, 1, 1),
      budgetId: budgetId,
      categoryId: categoryId,
      paymentMethod: method,
    );

/// Słowniki „sprzed podziału": wpisy bez budżetu, jak w starej wersji.
Future<void> _legacy({
  List<Category> cats = const [],
  List<PaymentMethod> methods = const [],
}) async {
  await _storage.clearForRestore(
    categories: true,
    keepDefaultCategories: false,
    paymentMethods: true,
  );
  for (final c in cats) {
    await _storage.saveCategory(c);
  }
  for (final m in methods) {
    await _storage.savePaymentMethod(m);
  }
}

void main() {
  setUpAll(() async => _storage = await setUpHiveStorage());
  tearDownAll(tearDownHiveStorage);
  setUp(() => resetStorage(_storage));

  group('Podział słowników sprzed zmiany', () {
    test(
      'kategoria używana w dwóch budżetach — kopia i przepięte pozycje',
      () async {
        await _legacy(cats: [_cat('dom', 'Dom'), _cat('snieg', 'Śnieżek')]);
        await _storage.savePlanPosition(
          _pos('p', kBudgetPersonal, categoryId: 'dom'),
        );
        await _storage.savePlanPosition(
          _pos('h', kBudgetHousehold, categoryId: 'dom'),
        );

        await _storage.ensureDictionaries();

        expect(_storage.getCategory('dom')!.budgetId, kBudgetPersonal);
        final copy = _storage.getCategories(kBudgetHousehold).single;
        expect(copy.name, 'Dom');
        expect(copy.id, isNot('dom'));
        expect(_storage.getPlanPosition('p')!.categoryId, 'dom');
        expect(_storage.getPlanPosition('h')!.categoryId, copy.id);
        // Nieużywana nigdzie — do budżetu osobistego.
        expect(_storage.getCategory('snieg')!.budgetId, kBudgetPersonal);
      },
    );

    test('metoda płatności — w każdym budżecie, który jej używa', () async {
      await _legacy(
        methods: const [
          PaymentMethod(id: 'ing', name: 'ING', isAutomatic: true),
          PaymentMethod(id: 'cash', name: 'Gotówka'),
        ],
      );
      await _storage.savePlanPosition(
        _pos('p', kBudgetPersonal, method: 'ING'),
      );
      await _storage.saveSubscription(_sub(kBudgetHousehold, method: 'ING'));

      await _storage.ensureDictionaries();

      expect(_storage.paymentMethodNamed(kBudgetPersonal, 'ING')!.id, 'ing');
      final copy = _storage.paymentMethodNamed(kBudgetHousehold, 'ING')!;
      expect(copy.id, isNot('ing'));
      expect(copy.isAutomatic, isTrue);
      expect(
        _storage.getPaymentMethods(kBudgetPersonal).map((m) => m.name),
        contains('Gotówka'),
      );
      expect(_storage.getPaymentMethods(kBudgetHousehold).map((m) => m.name), [
        'ING',
      ]);
    });

    test('budżet ma już kategorię o tej nazwie — bez drugiej', () async {
      await _legacy(
        cats: [
          _cat('dom-stara', 'Dom'),
          _cat('dom-h', 'dom', budgetId: kBudgetHousehold),
        ],
      );
      await _storage.savePlanPosition(
        _pos('h', kBudgetHousehold, categoryId: 'dom-stara'),
      );

      await _storage.ensureDictionaries();

      expect(_storage.getCategories(kBudgetHousehold).map((c) => c.id), [
        'dom-h',
      ]);
      expect(_storage.getPlanPosition('h')!.categoryId, 'dom-h');
      expect(_storage.getCategory('dom-stara'), isNull);
    });

    test(
      'pozycja z kategorią i metodą innego budżetu dostaje własne',
      () async {
        // Np. stara kopia zapasowa albo przeliczenie dawnych pozycji domowych
        // z domyślną kategorią, która należy już do budżetu osobistego.
        await _storage.saveCategory(
          _cat('stream', 'Streaming', budgetId: kBudgetPersonal),
        );
        await _storage.savePaymentMethod(
          const PaymentMethod(
            id: 'rev',
            name: 'Revolut',
            isAutomatic: true,
            budgetId: kBudgetPersonal,
          ),
        );
        await _storage.savePlanPosition(
          _pos('h', kBudgetHousehold, categoryId: 'stream', method: 'Revolut'),
        );

        await _storage.ensureDictionaries();

        final own = _storage.getCategories(kBudgetHousehold).single;
        expect(own.name, 'Streaming');
        expect(_storage.getPlanPosition('h')!.categoryId, own.id);
        expect(
          _storage.paymentMethodNamed(kBudgetHousehold, 'Revolut')?.isAutomatic,
          isTrue,
        );
      },
    );

    test('kolejne uruchomienie niczego nie zmienia', () async {
      await _legacy(cats: [_cat('dom', 'Dom')]);
      await _storage.savePlanPosition(
        _pos('h', kBudgetHousehold, categoryId: 'dom'),
      );
      await _storage.ensureDictionaries();
      final before = [
        for (final c in _storage.getAllCategories()) '${c.id}/${c.budgetId}',
      ];

      await _storage.ensureDictionaries();

      expect([
        for (final c in _storage.getAllCategories()) '${c.id}/${c.budgetId}',
      ], before);
    });
  });

  group('Etykiety przy przenoszeniu i kopiowaniu', () {
    Future<String> labelled(BudgetController b) async {
      await _storage.saveCategory(
        _cat('dom', 'Dom', budgetId: kBudgetPersonal),
      );
      await _storage.savePaymentMethod(
        const PaymentMethod(id: 'ing', name: 'ING', budgetId: kBudgetPersonal),
      );
      await _storage.savePlanPosition(
        _pos('p', kBudgetPersonal, categoryId: 'dom', method: 'ING'),
      );
      return (await b.addBudget('Firma', 'briefcase')).id;
    }

    test('„Dodaj je" — brakujące powstają w budżecie docelowym', () async {
      final b = _controller();
      final firma = await labelled(b);
      final missing = b.missingIn(firma, positionIds: {'p'});
      expect(missing.categories, ['Dom']);
      expect(missing.methods, ['ING']);

      await b.movePositions({'p'}, firma, addMissing: true);

      final moved = _storage.getPlanPosition('p')!;
      expect(moved.categoryId, _storage.getCategories(firma).single.id);
      expect(moved.paymentMethod, 'ING');
      expect(_storage.paymentMethodNamed(firma, 'ING'), isNotNull);
      // Oryginały zostają w budżecie osobistym.
      expect(_storage.getCategory('dom')!.budgetId, kBudgetPersonal);
    });

    test('„Bez nich" — pozycja przychodzi bez kategorii i metody', () async {
      final b = _controller();
      final firma = await labelled(b);

      await b.movePositions({'p'}, firma, addMissing: false);

      final moved = _storage.getPlanPosition('p')!;
      expect(moved.categoryId, isNull);
      expect(moved.paymentMethod, isNull);
      expect(_storage.getCategories(firma), isEmpty);
      expect(_storage.getPaymentMethods(firma), isEmpty);
    });

    test(
      'kategoria o tej nazwie w docelowym — kopia pozycji ją dostaje',
      () async {
        final b = _controller();
        final firma = await labelled(b);
        await _storage.saveCategory(_cat('dom-f', 'dom', budgetId: firma));

        expect(b.missingIn(firma, positionIds: {'p'}).categories, isEmpty);
        await b.copyPositions({'p'}, firma, addMissing: true);

        final copy = _storage.getPlanPositions(firma).single;
        expect(copy.categoryId, 'dom-f');
        expect(_storage.getCategories(firma), hasLength(1));
      },
    );

    test('subskrypcja — etykiety jak przy pozycjach', () async {
      final b = _controller();
      final firma = await labelled(b);
      await _storage.saveSubscription(
        _sub(kBudgetPersonal, categoryId: 'dom', method: 'ING'),
      );

      await b.moveSubscriptions(
        [_storage.getSubscription('netflix')!],
        firma,
        addMissing: true,
      );

      final moved = _storage.getSubscription('netflix')!;
      expect(moved.budgetId, firma);
      expect(moved.categoryId, _storage.getCategories(firma).single.id);
      expect(moved.paymentMethod, 'ING');
    });

    test(
      'kopia kategorii nie dubluje nazwy; przeniesienie ją stąd zabiera',
      () async {
        final b = _controller();
        final dom = _cat('dom', 'Dom', budgetId: kBudgetPersonal);
        await _storage.saveCategory(dom);
        await _storage.savePlanPosition(
          _pos('p', kBudgetPersonal, categoryId: 'dom'),
        );

        expect(await b.copyCategoryTo(dom, kBudgetHousehold), isTrue);
        expect(await b.copyCategoryTo(dom, kBudgetHousehold), isFalse);
        await b.moveCategoryTo(dom, kBudgetHousehold);

        expect(_storage.getCategory('dom'), isNull);
        expect(_storage.getPlanPosition('p')!.categoryId, isNull);
        expect(
          _storage
              .getCategories(kBudgetHousehold)
              .where((c) => c.name == 'Dom'),
          hasLength(1),
        );
      },
    );

    test('usunięty budżet zabiera swoje kategorie i metody', () async {
      final b = _controller();
      final firma = (await b.addBudget('Firma', 'briefcase')).id;
      await _storage.saveCategory(_cat('biuro', 'Biuro', budgetId: firma));
      await _storage.savePaymentMethod(
        PaymentMethod(id: 'konto', name: 'Konto firmowe', budgetId: firma),
      );

      await b.deleteBudget(firma);

      expect(_storage.getCategory('biuro'), isNull);
      expect(
        _storage.getAllPaymentMethods().any((m) => m.id == 'konto'),
        isFalse,
      );
    });

    test('kategorie zawsze alfabetycznie — dawna kolejność się nie liczy',
        () async {
      final b = _controller();
      final firma = (await b.addBudget('Firma', 'briefcase')).id;
      for (final (i, name) in ['Zakupy', 'Śnieżek', 'Auto'].indexed) {
        await _storage.saveCategory(
          Category(
            id: 'c$i',
            name: name,
            colorHex: '#64748B',
            iconName: 'folder',
            order: i,
            budgetId: firma,
          ),
        );
      }
      expect(_storage.getCategories(firma).map((c) => c.name), [
        'Auto',
        'Śnieżek',
        'Zakupy',
      ]);
    });

    test('nowy budżet startuje z pustymi listami', () async {
      final b = _controller();
      final firma = (await b.addBudget('Firma', 'briefcase')).id;
      expect(_storage.getCategories(firma), isEmpty);
      expect(_storage.getPaymentMethods(firma), isEmpty);
      // Domyślne są w budżecie osobistym.
      expect(_storage.getCategories(kBudgetPersonal), isNotEmpty);
    });
  });
}
