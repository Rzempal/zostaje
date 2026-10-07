import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:karton_subs/models/spending_allocation_item.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/backup_service.dart';
import 'package:karton_subs/services/storage_service.dart';
import 'package:karton_subs/services/sync_merge.dart';

import 'support/hive_test_env.dart';

/// STRAŻNIK FORMATU ZAPISU (ADR-032).
///
/// Te napisy nie są nazwami w kodzie — są **wartościami leżącymi na dyskach
/// telefonów**: w bazie Hive, w kopiach `.zostaje` i w paczkach synchronizacji
/// budżetu domowego. Nazwy w kodzie wolno zmieniać dowolnie; te wartości nie.
///
/// Najostrzejszy przypadek to synchronizacja: dwa telefony aktualizują się
/// w różnym czasie, więc telefon na starszej wersji musi dalej rozumieć paczkę
/// z nowszego. Zmiana `"type":"billPayment"` znaczy „pozycje znikają drugiej
/// osobie", a nie „testy na czerwono".
///
/// Jeśli ten plik świeci na czerwono po refaktorze nazw — to nie test jest do
/// poprawki, tylko refaktor przeciekł do formatu zapisu.
///
/// **Nie puszczać po tym pliku zbiorczych zamian nazw.** Napisy poniżej są
/// wpisane wprost właśnie po to, by nie zmieniały się razem z kodem: gdy
/// przemianuje się je oba naraz, test przechodzi, a dane i tak są zerwane.
void main() {
  late StorageService storage;

  setUpAll(() async => storage = await setUpHiveStorage());
  tearDownAll(tearDownHiveStorage);
  setUp(() => resetStorage(storage));

  group('Format zapisu — wartość pola „type"', () {
    test('wydatek bieżący zapisuje się jako „billPayment"', () {
      final entry = BudgetEntry(
        id: 'x',
        name: 'Paliwo',
        type: BudgetEntryType.spending,
        amount: 300,
        currency: Currency.PLN,
        dataDodania: DateTime(2026, 1, 1),
      );

      expect(entry.toJson()['type'], 'billPayment');
    });

    test('pozostałe typy też mają przypięte wartości', () {
      String wire(BudgetEntryType t) => BudgetEntry(
        id: 'x',
        name: 'x',
        type: t,
        amount: 1,
        currency: Currency.PLN,
        dataDodania: DateTime(2026, 1, 1),
      ).toJson()['type'] as String;

      expect(wire(BudgetEntryType.income), 'income');
      expect(wire(BudgetEntryType.recurringCost), 'recurringCost');
      expect(wire(BudgetEntryType.oneTimeIncome), 'oneTimeIncome');
      expect(wire(BudgetEntryType.householdTransfer), 'householdTransfer');
      expect(wire(BudgetEntryType.installment), 'installment');
    });

    test('odczyt rozumie wartość zapisu i historyczne aliasy', () {
      expect(
        BudgetEntry.typeFromName('billPayment'),
        BudgetEntryType.spending,
      );
      // ADR-018: „wydatek jednorazowy" scalony z rachunkiem.
      expect(
        BudgetEntry.typeFromName('oneTimeExpense'),
        BudgetEntryType.spending,
      );
      // ADR-011: dawne „bill" to dzisiejszy koszt cykliczny.
      expect(
        BudgetEntry.typeFromName('bill'),
        BudgetEntryType.recurringCost,
      );
    });
  });

  group('Format zapisu — klucze w pudełku `settings`', () {
    test('koperta siedzi pod „billsAllocationItems|<zakres>"', () async {
      await storage.setSpendingAllocationItems(BudgetScope.personal, const [
        SpendingAllocationItem(id: 'a', name: 'Paliwo', amount: 300),
      ]);

      final raw = Hive.box('settings').get('billsAllocationItems|personal');
      expect(raw, isNotNull);
      expect(raw.toString(), contains('Paliwo'));
    });
  });

  group('Format zapisu — klucze paczki synchronizacji i kopii', () {
    test('paczka synchronizacji niesie Planner pod „billsAllocation"', () {
      final json = SyncMerge.encodeSnapshot(
        const [],
        allocation: const [
          SpendingAllocationItem(id: 'a', name: 'Paliwo', amount: 300),
        ],
      );

      // Telefon na starszej wersji szuka DOKŁADNIE tej nazwy sekcji.
      expect(json, contains('"billsAllocation"'));
      expect(SyncMerge.decodeSnapshotFull(json).allocation, hasLength(1));
    });

    test('kopia `.zostaje` niesie Planner pod „billsAllocation"', () async {
      await storage.setSpendingAllocationItems(BudgetScope.personal, const [
        SpendingAllocationItem(id: 'a', name: 'Paliwo', amount: 300),
      ]);

      final payload =
          jsonDecode(BackupService(storage).buildJsonPayloadForTest())
              as Map<String, dynamic>;

      expect(payload.containsKey('billsAllocation'), isTrue);
      expect(payload['billsAllocation'], isA<Map>());
    });

    test('stara pojedyncza kwota koperty dalej się wczytuje', () async {
      // Klucz sprzed ADR-012 — telefony, które nie zapisały jeszcze listy.
      await Hive.box('settings').put('billsAllocation|personal', 420.0);

      final items = storage.getSpendingAllocationItemsRaw(BudgetScope.personal);
      expect(items, hasLength(1));
      expect(items.single.amount, 420.0);
    });
  });
}
