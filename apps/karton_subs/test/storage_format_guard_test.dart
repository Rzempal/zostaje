import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:karton_subs/models/spending_allocation_item.dart';
import 'package:karton_subs/models/budget.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/backup_service.dart';
import 'package:karton_subs/services/storage_service.dart';

import 'support/hive_test_env.dart';

/// STRAŻNIK FORMATU ZAPISU (ADR-032).
///
/// Te napisy nie są nazwami w kodzie — są **wartościami leżącymi na dyskach
/// telefonów**: w bazie Hive i w kopiach `.zostaje`. Nazwy w kodzie wolno
/// zmieniać dowolnie; te wartości nie.
///
/// Najostrzejszy przypadek to powrót do poprzedniej wersji aplikacji
/// (ADR-035): stara wersja czyta te same pudełka i te same kopie, więc zmiana
/// `"type":"billPayment"` znaczy „pozycje znikają po powrocie", a nie „testy
/// na czerwono".
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

  group('Format zapisu — klucze kopii', () {
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

  group('Format zapisu — pozycja planu (ADR-035)', () {
    test('okres pozycji leży pod „periodStart" i „periodEnd"', () {
      final json = PlanPosition(
        id: 'r',
        budgetId: 'personal',
        name: 'Rata',
        kind: PlanKind.expense,
        currency: Currency.PLN,
        periodStart: '2026-09',
        periodEnd: '2027-07',
        createdAt: DateTime(2026, 9, 1),
      ).toJson();

      // Wersja 0.27 tych kluczy nie zna i je pomija — zmiana nazwy w nowej
      // wersji zgubiłaby okresy zapisane w kopiach i w bazie.
      expect(json['periodStart'], '2026-09');
      expect(json['periodEnd'], '2027-07');
    });

    test('pożyczki zapisują się jak dawne pozycje karty', () {
      // Nazwy w kodzie zmieniły się na „loan"/„loanRepayment" (ADR-036),
      // wartości w zapisie — nie: istniejące pożyczki z karty i wersja 0.27
      // muszą je dalej rozpoznawać.
      PlanPosition of(PlanKind kind) => PlanPosition(
        id: 'x',
        budgetId: 'personal',
        name: 'x',
        kind: kind,
        currency: Currency.PLN,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(of(PlanKind.loan).toJson()['kind'], 'cardLoan');
      expect(of(PlanKind.loanRepayment).toJson()['kind'], 'cardRepayment');
    });

    test('warunki pożyczki ratalnej leżą pod „loan"', () {
      final json = PlanPosition(
        id: 'r',
        budgetId: 'personal',
        name: 'Raty',
        kind: PlanKind.loanRepayment,
        currency: Currency.PLN,
        loanTerms: PlanLoanTerms(
          principal: 2000,
          count: 12,
          installment: 166.67,
          rrso: 0,
          drawdown: DateTime(2026, 9, 13),
          firstMonth: '2026-10',
          day: 13,
        ),
        createdAt: DateTime(2026, 9, 1),
      ).toJson();
      final loan = json['loan'] as Map<String, dynamic>;
      expect(
        loan.keys,
        containsAll([
          'principal',
          'count',
          'installment',
          'rrso',
          'drawdown',
          'firstMonth',
          'day',
        ]),
      );
    });

    test('subskrypcja zapisuje budżet i — dla starszych wersji — „scope"', () {
      final json = Subscription(
        id: 's',
        name: 's',
        amount: 1,
        currency: Currency.PLN,
        billingCycle: BillingCycle.monthly,
        startDate: DateTime(2026, 1, 1),
        dataDodania: DateTime(2026, 1, 1),
        budgetId: 'household',
      ).toJson();
      expect(json['budgetId'], 'household');
      expect(json['scope'], 'household');
    });

    test('lista budżetów jedzie w kopii pod „budgets"', () async {
      await storage.setBudgets(const [
        Budget(id: 'personal', name: 'Osobisty', icon: 'user'),
        Budget(id: 'x', name: 'Firma', icon: 'briefcase'),
      ]);
      final payload =
          jsonDecode(BackupService(storage).buildJsonPayloadForTest())
              as Map<String, dynamic>;
      final settings = payload['settings'] as Map<String, dynamic>;
      expect(settings['budgets'], contains('"Firma"'));
    });

    test('kopia niesie znacznik planu z okresami', () {
      final payload =
          jsonDecode(BackupService(storage).buildJsonPayloadForTest())
              as Map<String, dynamic>;
      expect(payload['planPeriods'], isTrue);
    });
  });
}
