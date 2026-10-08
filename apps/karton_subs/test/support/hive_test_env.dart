import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/services/storage_service.dart';

/// Prawdziwy Hive na katalogu tymczasowym — dla testów usług, które są w całości
/// o efektach ubocznych w magazynie (backup, przenoszenie pozycji). Atrapa
/// magazynu sprawdzałaby w nich atrapę.
///
/// Dwie rzeczy, na które łatwo się nadziać i dlatego siedzą tutaj, a nie
/// w każdym pliku testowym z osobna:
///
/// 1. **Hive otwieramy RAZ na plik testowy.** Zamknięcie go między testami
///    zostawia w cache pudełka oznaczone jako zamknięte i kolejny test wywala
///    się na „Box has already been closed".
/// 2. **Izolację daje czyszczenie danych**, nie zamykanie bazy — [resetStorage]
///    przed każdym testem.
///
/// Użycie:
/// ```dart
/// late StorageService storage;
/// setUpAll(() async => storage = await setUpHiveStorage());
/// tearDownAll(tearDownHiveStorage);
/// setUp(() => resetStorage(storage));
/// ```
Directory? _tmpDir;

Future<StorageService> setUpHiveStorage() async {
  _tmpDir = await Directory.systemTemp.createTemp('zostaje_test_');
  Hive.init(_tmpDir!.path);
  final storage = StorageService();
  await storage.initForTests();
  return storage;
}

Future<void> tearDownHiveStorage() async {
  await Hive.close();
  await _tmpDir?.delete(recursive: true);
  _tmpDir = null;
}

/// Czyści dane między testami. Kategorie i metody płatności wracają do stanu
/// domyślnego (seed), bo [StorageService.clearForRestore] zachowuje wpisy
/// wbudowane — tak samo jak przy odtwarzaniu z kopii.
Future<void> resetStorage(StorageService storage) async {
  await storage.clearForRestore(
    subscriptions: true,
    categories: true,
    budgetPersonal: true,
    budgetHousehold: true,
    paymentDone: true,
    spendingAllocation: true,
    planPositions: true,
  );
  for (final scope in BudgetScope.values) {
    await storage.setSpendingAllocationItems(scope, const []);
  }
}
