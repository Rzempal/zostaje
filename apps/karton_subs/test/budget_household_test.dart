import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/budget_entry.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/services/excel_service.dart';

final _d = DateTime(2026, 1, 1);

Uint8List _xlsx(List<List<dynamic>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (final row in rows) {
    sheet.appendRow(row.map<CellValue?>((v) {
      if (v == null) return null;
      if (v is double) return DoubleCellValue(v);
      if (v is int) return IntCellValue(v);
      return TextCellValue(v.toString());
    }).toList());
  }
  return Uint8List.fromList(excel.save()!);
}

void main() {
  group('BudgetEntry — householdTransfer', () {
    final transfer = BudgetEntry(
      id: 't',
      name: 'Do wspólnego',
      type: BudgetEntryType.householdTransfer,
      amount: 1000,
      currency: Currency.PLN,
      dataDodania: _d,
      linkId: 'L1',
    );

    test('jest kosztem, nie jednorazowym, znormalizowany', () {
      expect(transfer.isExpense, isTrue);
      expect(transfer.isIncome, isFalse);
      expect(transfer.isOneTime, isFalse);
      expect(transfer.monthlyAmount, closeTo(1000, 0.001));
      expect(transfer.signedMonthlyAmount, closeTo(-1000, 0.001));
      expect(transfer.isLinked, isTrue);
    });

    test('linkId przechodzi przez toJson/fromJson i copyWith', () {
      final back = BudgetEntry.fromJson(transfer.toJson());
      expect(back.linkId, 'L1');
      expect(back.type, BudgetEntryType.householdTransfer);
      expect(transfer.copyWith(clearLinkId: true).linkId, isNull);
    });
  });

  group('Subscription — budżet (ADR-037)', () {
    Subscription sub(String budgetId) => Subscription(
          id: 's',
          name: 'Netflix',
          amount: 43,
          currency: Currency.PLN,
          billingCycle: BillingCycle.monthly,
          startDate: _d,
          dataDodania: _d,
          budgetId: budgetId,
        );

    test('domyślnie budżet osobisty', () {
      final s = Subscription(
        id: 's',
        name: 'x',
        amount: 1,
        currency: Currency.PLN,
        billingCycle: BillingCycle.monthly,
        startDate: _d,
        dataDodania: _d,
      );
      expect(s.budgetId, 'personal');
    });

    test('budżet przechodzi przez toJson/fromJson', () {
      final back = Subscription.fromJson(sub('firma-1').toJson());
      expect(back.budgetId, 'firma-1');
    });

    test('zapis sprzed budżetów (samo „scope") — te same identyfikatory', () {
      final household = sub('household').toJson()..remove('budgetId');
      expect(Subscription.fromJson(household).budgetId, 'household');
      final none = sub('household').toJson()
        ..remove('budgetId')
        ..remove('scope');
      expect(Subscription.fromJson(none).budgetId, 'personal');
    });

    test('dla starszych wersji „scope" zostaje — budżet spoza dwóch jako '
        'osobisty', () {
      expect(sub('household').toJson()['scope'], 'household');
      expect(sub('firma-1').toJson()['scope'], 'personal');
    });
  });

  group('Excel — zakres subskrypcji', () {
    const header = [
      'Nazwa',
      'Kwota',
      'Waluta',
      'Cykl',
      'Kategoria',
      'Metoda płatności',
      'Aktywna',
      'Data startu',
      'Zakres',
    ];

    test('kolumna Zakres=Domowe (stary arkusz) → household; brak → personal',
        () {
      final bytes = _xlsx([
        header,
        ['Netflix', 43.0, 'PLN', 'miesięcznie', '', '', 'tak', '2026-01-01',
            'Domowe'],
        ['Spotify', 20.0, 'PLN', 'miesięcznie', '', '', 'tak', '2026-01-01', ''],
      ]);
      final r = ExcelService.parseBytesForTest(bytes);
      final byName = {for (final s in r.subscriptions) s.name: s};
      expect(byName['Netflix']!.budgetId, 'household');
      expect(byName['Spotify']!.budgetId, 'personal');
    });

    test('eksport → import zachowuje zakres', () {
      final subs = [
        Subscription(
          id: 'a',
          name: 'HBO',
          amount: 30,
          currency: Currency.PLN,
          billingCycle: BillingCycle.monthly,
          startDate: _d,
          dataDodania: _d,
          budgetId: 'household',
        ),
      ];
      final bytes = ExcelService.buildWorkbookForTest(subs, const []);
      final r = ExcelService.parseBytesForTest(bytes);
      expect(r.subscriptions.single.budgetId, 'household');
    });
  });
}
