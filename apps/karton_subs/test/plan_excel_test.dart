import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/category.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart' show Currency;
import 'package:karton_subs/services/plan_excel.dart';

// Plan roczny w Excelu (ADR-035): tabela roku do udostępniania budżetu.
// Najważniejsze: eksport → import daje ten sam plan (kwoty w tych samych
// miesiącach), a import z ręcznie poprawionego pliku niczego nie psuje.

PlanPosition _pos(
  String id,
  String name,
  Map<String, double> months, {
  PlanKind kind = PlanKind.expense,
  String? categoryId,
}) =>
    PlanPosition(
      id: id,
      budgetId: kBudgetPersonal,
      name: name,
      kind: kind,
      currency: Currency.PLN,
      categoryId: categoryId,
      day: 10,
      months: {
        for (final e in months.entries) e.key: PlanMonth(amount: e.value),
      },
      createdAt: DateTime(2026, 1, 1),
    );

final _categories = [
  Category(
      id: 'cat-dom', name: 'Dom', colorHex: '#000000', iconName: 'home', order: 0),
];

void main() {
  group('Eksport → import', () {
    test('kwoty wracają w tych samych miesiącach, rata przez dwa lata = jedna '
        'pozycja', () {
      final bytes = PlanExcel.build(
        positions: [
          _pos('1', 'Pensja', {'2026-01': 8000, '2026-02': 8000},
              kind: PlanKind.income),
          _pos('2', 'Rata', {'2026-11': 500, '2026-12': 500, '2027-01': 500},
              categoryId: 'cat-dom'),
          _pos('3', 'Ubezpieczenie', {'2026-03': 0}),
        ],
        categories: _categories,
        years: [2026, 2027],
      );

      final result = PlanExcel.parse(
        bytes,
        budgetId: kBudgetHousehold,
        categoryIdByName: {'dom': 'cat-dom'},
      );

      expect(result.skipped, isEmpty);
      final byName = {for (final p in result.positions) p.name: p};
      expect(byName.keys, unorderedEquals(['Pensja', 'Rata', 'Ubezpieczenie']));

      final rata = byName['Rata']!;
      expect(rata.months.keys, ['2026-11', '2026-12', '2027-01']);
      expect(rata.categoryId, 'cat-dom');
      expect(rata.day, 10);
      expect(rata.budgetId, kBudgetHousehold);
      expect(rata.id, isNot('2'), reason: 'import dokłada, nie nadpisuje');

      expect(byName['Pensja']!.kind, PlanKind.income);
      // Zero w komórce = pozycja obowiązuje z kwotą 0; pusta = nie obowiązuje.
      expect(byName['Ubezpieczenie']!.months.keys, ['2026-03']);
    });

    test('wydatki w arkuszu są ujemne, wpływy dodatnie; import bierze kwotę '
        'bez znaku', () {
      final bytes = PlanExcel.build(
        positions: [
          _pos('w', 'Pensja', {'2026-01': 8000}, kind: PlanKind.income),
          _pos('x', 'Czynsz', {'2026-01': 2000}),
        ],
        categories: const [],
        years: [2026],
      );
      final rows = Excel.decodeBytes(bytes).tables['Plan 2026']!.rows;
      final jan = PlanExcel.headers.indexOf('sty');
      final values = {
        for (final r in rows.skip(1))
          PlanExcel.cellText(r[1]): double.parse(PlanExcel.cellText(r[jan])!),
      };
      expect(values['Pensja'], 8000);
      expect(values['Czynsz'], -2000);

      final back = PlanExcel.parse(bytes, budgetId: kBudgetPersonal);
      final czynsz = back.positions.firstWhere((p) => p.name == 'Czynsz');
      expect(czynsz.amountIn('2026-01'), closeTo(2000, 0.001));
      expect(czynsz.kind, PlanKind.expense);
    });

    test('pozycje karty idą do arkusza, ale z niego nie wracają', () {
      final bytes = PlanExcel.build(
        positions: [
          _pos('l', 'Karta', {'2026-01': 3000}, kind: PlanKind.cardLoan),
        ],
        categories: const [],
        years: [2026],
      );

      final result = PlanExcel.parse(bytes, budgetId: kBudgetPersonal);

      expect(result.positions, isEmpty);
      expect(result.skipped.single, contains('karty'));
    });

    test('nazwa zaczynająca się od „=" nie staje się formułą', () {
      final bytes = PlanExcel.build(
        positions: [_pos('x', '=HYPERLINK("zly")', {'2026-01': 1})],
        categories: const [],
        years: [2026],
      );
      final cell = Excel.decodeBytes(bytes).tables['Plan 2026']!.rows[1][1];

      expect(PlanExcel.cellText(cell), startsWith("'="));
      expect(
        PlanExcel.parse(bytes, budgetId: kBudgetPersonal).positions.single.name,
        '=HYPERLINK("zly")',
      );
    });
  });

  group('Plik poprawiany ręcznie', () {
    List<int> sheet(List<List<CellValue?>> rows, {String name = 'Plan 2026'}) {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, name);
      for (final r in rows) {
        excel[name].appendRow(r);
      }
      return excel.save()!;
    }

    List<CellValue?> header() =>
        PlanExcel.headers.map<CellValue?>(TextCellValue.new).toList();

    test('złe kwoty i wiersz bez kwot są raportowane, reszta wchodzi', () {
      final bytes = sheet([
        header(),
        [
          TextCellValue('Wydatek'), TextCellValue('Prąd'), null, null, null,
          null, null, TextCellValue('1 234,50'), TextCellValue('abc'),
        ],
        [TextCellValue('Wydatek'), TextCellValue('Pusty')],
        [null, null, null, null, null, null, null, DoubleCellValue(5)],
      ]);

      final result =
          PlanExcel.parse(Uint8List.fromList(bytes), budgetId: kBudgetPersonal);

      final prad = result.positions.single;
      expect(prad.name, 'Prąd');
      expect(prad.months, hasLength(1));
      expect(prad.amountIn('2026-01'), closeTo(1234.5, 0.001));
      expect(result.skipped, hasLength(3)); // zła kwota, pusty, brak nazwy
    });

    test('plik bez zakładki „Plan RRRR" jest odrzucany', () {
      final bytes = sheet([header()], name: 'Budżet');

      expect(
        () => PlanExcel.parse(Uint8List.fromList(bytes),
            budgetId: kBudgetPersonal),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
