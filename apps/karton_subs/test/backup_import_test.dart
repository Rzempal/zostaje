import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/spending_allocation_item.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart'
    show Currency, BillingCycle, Subscription;
import 'package:karton_subs/services/plan_conversion.dart';
import 'package:karton_subs/services/backup_crypto_service.dart';
import 'package:karton_subs/services/backup_service.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

// Import kopii zapasowej — obszar, ktory do tej pory nie mial zadnego testu,
// a ma na koncie realna strate danych: import w trybie SCALANIA przywrocil na
// PROD pozycje wczesniej usuniete (+1455,49 zl w podsumowaniu), bo zapisywal to,
// co w pliku, ale nie usuwal tego, czego w pliku NIE MA (ADR-021).
//
// Testy jada na prawdziwym Hive (katalog tymczasowy) — `BackupService` to
// w calosci efekty uboczne w magazynie, wiec atrapa sprawdzalaby atrape.

late StorageService _storage;
late BackupService _backup;

BudgetEntry _entry(String id, String name, {double amount = 100}) => BudgetEntry(
      id: id,
      name: name,
      type: BudgetEntryType.recurringCost,
      amount: amount,
      currency: Currency.PLN,
      cycle: BillingCycle.monthly,
      dataDodania: DateTime(2026, 7, 1),
    );

/// Plik kopii w formacie v7 — budowany wprost, bez eksportu, zeby test nie
/// zalezal od kanalow natywnych (kod odzyskiwania siedzi w Block Store).
BackupFileInfo _file(Map<String, dynamic> payload) {
  final json = jsonEncode(payload);
  return BackupFileInfo(
    bytes: Uint8List.fromList(utf8.encode(json)),
    fileName: 'test.zostaje',
    format: PlainJsonBackup(json),
  );
}

Map<String, dynamic> _payload({
  List<BudgetEntry> personal = const [],
  List<BudgetEntry> household = const [],
  Map<String, bool>? paymentDone,
  Map<String, dynamic>? spendingAllocation,
  int version = 7,
}) =>
    {
      'version': version,
      'exportDate': DateTime(2026, 7, 31).toIso8601String(),
      'subscriptions': const [],
      'categories': const [],
      'paymentMethods': const [],
      'budgetEntries': [for (final e in personal) e.toJson()],
      'householdBudgetEntries': [for (final e in household) e.toJson()],
      'paymentDone': ?paymentDone,
      'billsAllocation': ?spendingAllocation,
    };

void main() {
  setUpAll(() async {
    _storage = await setUpHiveStorage();
    _backup = BackupService(_storage);
  });
  tearDownAll(tearDownHiveStorage);
  setUp(() => resetStorage(_storage));

  group('Odtworzenie vs scalanie (ADR-021)', () {
    test('SCALANIE zostawia pozycje, ktorych nie ma w pliku', () async {
      await _storage.saveBudgetEntry(
        _entry('stara', 'Usunieta wczesniej', amount: 1455.49),
        BudgetScope.personal,
      );

      await _backup.importFromBytes(
        _file(_payload(personal: [_entry('nowa', 'Z pliku')])),
        replace: false,
      );

      final ids = _storage
          .getBudgetEntries(BudgetScope.personal)
          .map((e) => e.id)
          .toSet();
      expect(ids, {'stara', 'nowa'}, reason: 'scalanie niczego nie kasuje');
    });

    test('ODTWORZENIE kasuje pozycje spoza pliku (bug z PROD)', () async {
      await _storage.saveBudgetEntry(
        _entry('stara', 'Usunieta wczesniej', amount: 1455.49),
        BudgetScope.personal,
      );

      final result = await _backup.importFromBytes(
        _file(_payload(personal: [_entry('nowa', 'Z pliku')])),
        replace: true,
      );

      final ids = _storage
          .getBudgetEntries(BudgetScope.personal)
          .map((e) => e.id)
          .toSet();
      expect(ids, {'nowa'});
      expect(result.replaced, isTrue);
      expect(
        result.removedBeforeRestore,
        1,
        reason: 'podsumowanie mowi, ile usunieto',
      );
    });

    test('ODTWORZENIE nie rusza obszarow, ktorych plik NIE zawiera', () async {
      // Na tym poleglo pierwsze podejscie do ADR-021: czyszczenie „wszystkiego"
      // kasowalo Planner, ktorego starsze formaty w ogole nie mialy.
      await _storage.setSpendingAllocationItems(BudgetScope.personal, [
        SpendingAllocationItem(
          id: 'a1',
          name: 'Paliwo',
          amount: 300,
          updatedAt: DateTime(2026, 7, 1),
        ),
      ]);
      await _storage.saveBudgetEntry(
        _entry('domowa', 'Pozycja domowa'),
        BudgetScope.household,
      );

      // Plik ma TYLKO budzet osobisty — bez sekcji domowej i bez Plannera.
      final payload = _payload(personal: [_entry('nowa', 'Z pliku')])
        ..remove('householdBudgetEntries');

      await _backup.importFromBytes(_file(payload), replace: true);

      expect(
        _storage.getBudgetEntries(BudgetScope.household).length,
        1,
        reason: 'brak sekcji w pliku = brak informacji, nie „skasuj"',
      );
      expect(
        _storage.getSpendingAllocationItems(BudgetScope.personal).length,
        1,
        reason: 'Planner bez pokrycia w pliku zostaje',
      );
    });
  });

  group('Zawartosc kopii', () {
    test('pozycje obu budzetow wracaja na swoje miejsca', () async {
      await _backup.importFromBytes(
        _file(
          _payload(
            personal: [_entry('p1', 'Prad')],
            household: [_entry('h1', 'Czynsz')],
          ),
        ),
        replace: true,
      );

      expect(
        _storage.getBudgetEntries(BudgetScope.personal).single.name,
        'Prad',
      );
      expect(
        _storage.getBudgetEntries(BudgetScope.household).single.name,
        'Czynsz',
      );
    });

    test('odhaczone platnosci wracaja', () async {
      await _backup.importFromBytes(
        _file(
          _payload(
            personal: [_entry('p1', 'Prad')],
            paymentDone: {'personal|p1|2026-07-10': true},
          ),
        ),
        replace: true,
      );
      expect(_storage.isPaymentDone('personal|p1|2026-07-10'), isTrue);
    });

    test('Planner wraca z pliku (wersja 6+)', () async {
      await _backup.importFromBytes(
        _file(
          _payload(
            spendingAllocation: {
              'personal': [
                {
                  'id': 'a1',
                  'name': 'Paliwo',
                  'amount': 300.0,
                  'updatedAt': DateTime(2026, 7, 1).toIso8601String(),
                },
              ],
              'household': const [],
            },
          ),
        ),
        replace: true,
      );
      final items = _storage.getSpendingAllocationItems(BudgetScope.personal);
      expect(items.single.name, 'Paliwo');
      expect(items.single.amount, closeTo(300, 0.001));
    });
  });

  group('Plan roczny w kopii (v8, ADR-035)', () {
    PlanPosition position(String id, double amount) => PlanPosition(
          id: id,
          budgetId: kBudgetPersonal,
          name: id,
          kind: PlanKind.expense,
          currency: Currency.PLN,
          months: {'2026-10': PlanMonth(amount: amount)},
          createdAt: DateTime(2026, 10, 1),
        );

    Map<String, dynamic> v8(List<PlanPosition> plan,
            {List<BudgetEntry> personal = const []}) =>
        {
          ..._payload(personal: personal, version: 8),
          'planPositions': [for (final p in plan) p.toJson()],
        };

    test('eksport zapisuje plan i wersje 8', () async {
      await _storage.savePlanPosition(position('czynsz', 2000));

      final data =
          jsonDecode(_backup.buildJsonPayloadForTest()) as Map<String, dynamic>;

      expect(data['version'], 8);
      expect((data['planPositions'] as List).single['id'], 'czynsz');
    });

    test('ODTWORZENIE v8 bierze plan z pliku, bez przeliczania starych pozycji',
        () async {
      await _storage.savePlanPosition(position('lokalna', 50));

      await _backup.importFromBytes(
        _file(v8([position('z-pliku', 300)],
            personal: [_entry('stara', 'Stara pozycja')])),
        replace: true,
      );

      final plan = _storage.getPlanPositions();
      expect(plan.map((p) => p.id), ['z-pliku']);
      expect(plan.single.amountIn('2026-10'), closeTo(300, 0.001));
      // Plan z pliku jest gotowy — start aplikacji nie może go przeliczyć.
      expect(_storage.getPlanConversionVersion(), PlanConversion.version);
      expect(_storage.getPlanEnvelopeMigrated(), isTrue);
    });

    test('SCALANIE v8 dokłada i aktualizuje pozycje po identyfikatorze',
        () async {
      await _storage.savePlanPosition(position('lokalna', 50));
      await _storage.savePlanPosition(position('wspolna', 100));

      await _backup.importFromBytes(
        _file(v8([position('wspolna', 120), position('nowa', 10)])),
      );

      final byId = {for (final p in _storage.getPlanPositions()) p.id: p};
      expect(byId.keys, unorderedEquals(['lokalna', 'wspolna', 'nowa']));
      expect(byId['wspolna']!.amountIn('2026-10'), closeTo(120, 0.001));
    });

    test('eksport oznacza plan z okresami', () {
      final data =
          jsonDecode(_backup.buildJsonPayloadForTest()) as Map<String, dynamic>;
      expect(data['planPeriods'], isTrue);
    });

    test('kopia sprzed okresów: rata dostaje okres zaraz po wczytaniu',
        () async {
      final rata = BudgetEntry(
        id: 'fold',
        name: 'Fold 8',
        type: BudgetEntryType.installment,
        amount: 2488.31,
        currency: Currency.PLN,
        cycle: BillingCycle.monthly,
        installmentCount: 11,
        startDate: DateTime(2026, 9, 28),
        dataDodania: DateTime(2026, 9, 1),
      );
      await _backup.importFromBytes(
        _file(v8([position('fold', 226.21)], personal: [rata])),
        replace: true,
      );

      final p = _storage.getPlanPositions().single;
      expect(p.periodStart, '2026-09');
      expect(p.periodEnd, '2027-07');
      expect(p.amountIn('2026-10'), closeTo(226.21, 0.001));
    });

    test('kopia z okresami: okresów nie uzupełnia (także usuniętych)',
        () async {
      final rata = BudgetEntry(
        id: 'fold',
        name: 'Fold 8',
        type: BudgetEntryType.installment,
        amount: 2488.31,
        currency: Currency.PLN,
        cycle: BillingCycle.monthly,
        installmentCount: 11,
        startDate: DateTime(2026, 9, 28),
        dataDodania: DateTime(2026, 9, 1),
      );
      await _backup.importFromBytes(
        _file({
          ...v8([position('fold', 226.21)], personal: [rata]),
          'planPeriods': true,
        }),
        replace: true,
      );

      expect(_storage.getPlanPositions().single.hasPeriod, isFalse);
      expect(_storage.getPlanPeriodsMigrated(), isTrue);
    });

    test('plik v7 (bez planu) dalej przelicza plan ze starych pozycji',
        () async {
      await _backup.importFromBytes(
        _file(_payload(personal: [_entry('prad', 'Prad', amount: 150)])),
        replace: true,
      );

      expect(_storage.getPlanPositions().map((p) => p.id), contains('prad'));
    });

    test('ODTWORZENIE czyści też pamięć podręczną subskrypcji', () async {
      await _storage.saveSubscription(Subscription(
        id: 'netflix',
        name: 'Netflix',
        amount: 60,
        currency: Currency.PLN,
        billingCycle: BillingCycle.monthly,
        startDate: DateTime(2026, 1, 1),
        dataDodania: DateTime(2026, 1, 1),
      ));

      await _backup.importFromBytes(_file(_payload()), replace: true);

      expect(_storage.getSubscriptions(), isEmpty);
    });
  });

  group('Wersje formatu', () {
    test('stary plik (v1, bez metod platnosci i Plannera) da sie wczytac', () {
      final payload = {
        'version': 1,
        'subscriptions': const [],
        'categories': const [],
        'budgetEntries': [_entry('p1', 'Prad').toJson()],
      };
      expect(
        () => _backup.importFromBytes(_file(payload), replace: true),
        returnsNormally,
      );
    });

    test('plik z przyszlosci (wersja > 8) jest odrzucany, nie psuje danych',
        () async {
      await _storage.saveBudgetEntry(_entry('moja', 'Moja'), BudgetScope.personal);

      await expectLater(
        _backup.importFromBytes(_file(_payload(version: 99)), replace: true),
        throwsA(isA<FormatException>()),
      );
      expect(_storage.getBudgetEntries(BudgetScope.personal).length, 1);
    });
  });

  group('Szyfrowanie haslem', () {
    final crypto = BackupCryptoService();

    test('kopia z haslem otwiera sie tym haslem', () {
      final bytes = crypto.encryptWithPassword('{"version":7}', 'tajne-haslo');
      final format = crypto.detectFormat(bytes);
      expect(format, isA<EncryptedBackup>());
      expect(
        crypto.decryptWithPassword(format as EncryptedBackup, 'tajne-haslo'),
        '{"version":7}',
      );
    });

    test('zle haslo konczy sie bledem, nie smieciami', () {
      final bytes = crypto.encryptWithPassword('{"version":7}', 'tajne-haslo');
      final format = crypto.detectFormat(bytes) as EncryptedBackup;
      expect(
        () => crypto.decryptWithPassword(format, 'inne-haslo'),
        throwsA(isA<FormatException>()),
      );
    });

    test('plik niezaszyfrowany rozpoznaje sie jako zwykly JSON', () {
      final bytes = Uint8List.fromList(utf8.encode('{"version":7}'));
      expect(crypto.detectFormat(bytes), isA<PlainJsonBackup>());
    });
  });
}
