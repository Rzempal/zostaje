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

  group('Subscription — scope', () {
    Subscription sub(SubscriptionScope scope) => Subscription(
          id: 's',
          name: 'Netflix',
          amount: 43,
          currency: Currency.PLN,
          billingCycle: BillingCycle.monthly,
          startDate: _d,
          dataDodania: _d,
          scope: scope,
        );

    test('domyślnie osobista', () {
      expect(sub(SubscriptionScope.personal).scope, SubscriptionScope.personal);
    });

    test('scope przechodzi przez toJson/fromJson', () {
      final back = Subscription.fromJson(sub(SubscriptionScope.household).toJson());
      expect(back.scope, SubscriptionScope.household);
    });

    test('brak pola scope w JSON → osobista (migracja)', () {
      final json = sub(SubscriptionScope.household).toJson()..remove('scope');
      expect(Subscription.fromJson(json).scope, SubscriptionScope.personal);
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

    test('kolumna Zakres=Domowe → household; brak → personal', () {
      final bytes = _xlsx([
        header,
        ['Netflix', 43.0, 'PLN', 'miesięcznie', '', '', 'tak', '2026-01-01',
            'Domowe'],
        ['Spotify', 20.0, 'PLN', 'miesięcznie', '', '', 'tak', '2026-01-01', ''],
      ]);
      final r = ExcelService.parseBytesForTest(bytes);
      final byName = {for (final s in r.subscriptions) s.name: s};
      expect(byName['Netflix']!.scope, SubscriptionScope.household);
      expect(byName['Spotify']!.scope, SubscriptionScope.personal);
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
          scope: SubscriptionScope.household,
        ),
      ];
      final bytes = ExcelService.buildWorkbookForTest(subs, const []);
      final r = ExcelService.parseBytesForTest(bytes);
      expect(r.subscriptions.single.scope, SubscriptionScope.household);
    });
  });
}
