import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/spending_allocation_item.dart';
import 'package:karton_subs/models/subscription.dart'
    show BillingCycle, Currency;
import 'package:karton_subs/services/backup_crypto_service.dart';
import 'package:karton_subs/services/backup_service.dart';
import 'package:karton_subs/services/plan_conversion.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

// Zapis planu rocznego obok starych pozycji (ADR-035). Najważniejsze:
// stare dane zostają nietknięte (powrót do poprzedniej wersji aplikacji),
// a konwersja przy starcie nie nadpisuje planu, który już powstał.

late StorageService _storage;
final _today = DateTime(2026, 10, 6);

BudgetEntry _cost(String id, {double amount = 100}) => BudgetEntry(
  id: id,
  name: 'Koszt $id',
  type: BudgetEntryType.recurringCost,
  amount: amount,
  currency: Currency.PLN,
  cycle: BillingCycle.monthly,
  startDate: DateTime(2025, 1, 10),
  dataDodania: DateTime(2025, 1, 1),
);

void main() {
  setUpAll(() async => _storage = await setUpHiveStorage());
  tearDownAll(tearDownHiveStorage);
  setUp(() => resetStorage(_storage));

  test(
    'konwersja przy starcie zapisuje plan raz, potem nic nie robi',
    () async {
      await _storage.saveBudgetEntry(_cost('a'));
      await _storage.saveBudgetEntry(_cost('h'), BudgetScope.household);
      final runner = PlanConversionRunner(_storage);

      final first = await runner.ensureConverted(_today);
      expect(first, isNotNull);
      expect(_storage.getPlanPositions(), hasLength(2));
      expect(_storage.getPlanPositions(kBudgetHousehold).single.id, 'h');
      expect(_storage.getPlanConversionVersion(), PlanConversion.version);

      // Zmiana w planie nie może zniknąć przy kolejnym starcie aplikacji.
      final edited = _storage.getPlanPosition('a')!.copyWith(name: 'Zmieniona');
      await _storage.savePlanPosition(edited);
      final second = await runner.ensureConverted(_today);
      expect(second, isNull);
      expect(_storage.getPlanPosition('a')!.name, 'Zmieniona');
    },
  );

  test('konwersja nie rusza starych pozycji budżetu', () async {
    final old = _cost('a', amount: 321);
    await _storage.saveBudgetEntry(old);
    final before = jsonEncode(_storage.getBudgetEntry('a')!.toJson());

    await PlanConversionRunner(_storage).reconvert(_today);

    expect(jsonEncode(_storage.getBudgetEntry('a')!.toJson()), before);
    expect(_storage.getBudgetEntries(), hasLength(1));
  });

  test('przeliczenie od nowa zastępuje cały plan', () async {
    await _storage.saveBudgetEntry(_cost('a'));
    final runner = PlanConversionRunner(_storage);
    await runner.reconvert(_today);
    await _storage.savePlanPosition(
      _storage.getPlanPosition('a')!.copyWith(name: 'Zmieniona'),
    );
    await _storage.deleteBudgetEntry('a');
    await _storage.saveBudgetEntry(_cost('b'));

    await runner.reconvert(_today);

    expect(_storage.getPlanPositions().map((p) => p.id), ['b']);
  });

  test('odtworzenie starej kopii zapasowej od razu przelicza plan', () async {
    await _storage.saveBudgetEntry(_cost('a'));
    final runner = PlanConversionRunner(_storage);
    await runner.ensureConverted(_today);

    final json = jsonEncode({
      'version': 7,
      'exportDate': DateTime(2026, 10, 1).toIso8601String(),
      'subscriptions': const [],
      'categories': const [],
      'paymentMethods': const [],
      'budgetEntries': [_cost('z').toJson()],
      'householdBudgetEntries': const [],
    });
    await BackupService(_storage).importFromBytes(
      BackupFileInfo(
        bytes: Uint8List.fromList(utf8.encode(json)),
        fileName: 'prod.zostaje',
        format: PlainJsonBackup(json),
      ),
      replace: true,
    );
    // Bez restartu aplikacji: plan odpowiada już pozycjom z kopii.
    expect(_storage.getPlanPositions().map((p) => p.id), ['z']);
    expect(_storage.getPlanConversionVersion(), PlanConversion.version);
    expect(await runner.ensureConverted(_today), isNull);
  });

  test(
    'Planner dokładany do istniejącego planu raz, bez ruszania zmian',
    () async {
      // Stan sprzed tej zmiany: plan już jest, koperta jeszcze nie w planie.
      await _storage.saveBudgetEntry(_cost('a'));
      final runner = PlanConversionRunner(_storage);
      await runner.ensureConverted(_today);
      await _storage.setPlanEnvelopeMigrated(false);
      await _storage.savePlanPosition(
        _storage.getPlanPosition('a')!.copyWith(name: 'Zmieniona'),
      );
      await _storage.setSpendingAllocationItems(BudgetScope.personal, const [
        SpendingAllocationItem(id: 'x', name: 'Jedzenie', amount: 1500),
      ]);

      expect(await runner.ensureEnvelopeMigrated(_today), 1);
      expect(_storage.getPlanPosition('envelope:x')!.amountIn('2026-10'), 1500);
      expect(_storage.getPlanPosition('a')!.name, 'Zmieniona');

      // Drugi raz nic nie dokłada.
      expect(await runner.ensureEnvelopeMigrated(_today), 0);
      expect(_storage.getPlanPositions(), hasLength(2));
    },
  );

  test('przeliczenie od nowa zawiera Planner i nie dubluje go', () async {
    await _storage.setSpendingAllocationItems(BudgetScope.household, const [
      SpendingAllocationItem(id: 'p', name: 'Paliwo', amount: 400),
    ]);
    final runner = PlanConversionRunner(_storage);
    await runner.reconvert(_today);

    expect(_storage.getPlanPositions(kBudgetHousehold).single.id, 'envelope:p');
    expect(await runner.ensureEnvelopeMigrated(_today), 0);
    expect(_storage.getPlanPositions(), hasLength(1));
  });
}
