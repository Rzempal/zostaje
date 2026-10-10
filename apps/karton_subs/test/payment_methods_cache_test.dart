import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/plan_position.dart' show kBudgetPersonal;
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

/// Posortowana lista metod płatności jest trzymana w pamięci (woła ją każdy
/// wiersz listy) — cała i dla każdego budżetu osobno (ADR-038). Test pilnuje
/// tego, co przy takim buforze psuje się najłatwiej: czy po zapisie
/// i usunięciu widać nowy stan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  setUpAll(() async => storage = await setUpHiveStorage());
  tearDownAll(tearDownHiveStorage);

  test('kolejne wywołania zwracają tę samą listę (bez przeliczania)', () {
    expect(
      identical(storage.getAllPaymentMethods(), storage.getAllPaymentMethods()),
      isTrue,
    );
    expect(
      identical(
        storage.getPaymentMethods(kBudgetPersonal),
        storage.getPaymentMethods(kBudgetPersonal),
      ),
      isTrue,
    );
  });

  test('lista jest posortowana po `order`', () {
    final list = storage.getPaymentMethods(kBudgetPersonal);
    for (var i = 1; i < list.length; i++) {
      expect(list[i - 1].order <= list[i].order, isTrue);
    }
  });

  test('zapis nowej metody unieważnia bufor', () async {
    final before = storage.getPaymentMethods(kBudgetPersonal).length;
    await storage.savePaymentMethod(
      const PaymentMethod(
        id: 'pm_test',
        name: 'Karta testowa',
        order: 99,
        isAutomatic: true,
        budgetId: kBudgetPersonal,
      ),
    );
    final after = storage.getPaymentMethods(kBudgetPersonal);
    expect(after.length, before + 1);
    expect(after.any((p) => p.id == 'pm_test'), isTrue);
  });

  test('zmiana istniejącej metody jest widoczna od razu', () async {
    await storage.savePaymentMethod(
      const PaymentMethod(
        id: 'pm_test',
        name: 'Karta po zmianie',
        order: 99,
        isAutomatic: false,
        budgetId: kBudgetPersonal,
      ),
    );
    final pm = storage
        .getPaymentMethods(kBudgetPersonal)
        .firstWhere((p) => p.id == 'pm_test');
    expect(pm.name, 'Karta po zmianie');
    expect(pm.isAutomatic, isFalse);
    expect(
      storage.paymentMethodNamed(kBudgetPersonal, 'Karta po zmianie')?.id,
      'pm_test',
    );
  });

  test('usunięcie metody unieważnia bufor', () async {
    await storage.deletePaymentMethod('pm_test');
    expect(
      storage.getPaymentMethods(kBudgetPersonal).any((p) => p.id == 'pm_test'),
      isFalse,
    );
  });
}
