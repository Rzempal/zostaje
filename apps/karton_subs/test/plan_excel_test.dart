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

    test('okres (Od/Do) wraca z arkusza razem z ratą', () {
      final bytes = PlanExcel.build(
        positions: [
          _pos('r', 'Fold 8', {
            '2026-11': 226.21,
            '2026-12': 226.21,
            '2027-01': 226.21,
          }).copyWith(periodStart: '2026-11', periodEnd: '2027-01'),
        ],
        categories: const [],
        years: [2026, 2027],
      );

      final fold = PlanExcel.parse(
        bytes,
        budgetId: kBudgetPersonal,
      ).positions.single;
      expect(fold.periodStart, '2026-11');
      expect(fold.periodEnd, '2027-01');
      expect(fold.months, hasLength(3));
    });

    test('pożyczki idą do arkusza, ale z niego nie wracają', () {
      final bytes = PlanExcel.build(
        positions: [
          _pos('l', 'Karta', {'2026-01': 3000}, kind: PlanKind.loan),
          _pos('r', 'Raty', {'2026-02': 100}, kind: PlanKind.loanRepayment),
        ],
        categories: const [],
        years: [2026],
      );

      final result = PlanExcel.parse(bytes, budgetId: kBudgetPersonal);

      expect(result.positions, isEmpty);
      expect(result.skipped, hasLength(2));
      expect(result.skipped.first, contains('pożyczki'));
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
      // Komórki po nazwie kolumny, nie po pozycji — arkusz dostaje nowe
      // kolumny (np. Od/Do), a test ma sprawdzać kwoty, nie układ.
      List<CellValue?> row(Map<String, CellValue> cells) => [
        for (final h in PlanExcel.headers) cells[h],
      ];
      final bytes = sheet([
        header(),
        row({
          'Rodzaj': TextCellValue('Wydatek'),
          'Nazwa': TextCellValue('Prąd'),
          'sty': TextCellValue('1 234,50'),
          'lut': TextCellValue('abc'),
        }),
        row({'Rodzaj': TextCellValue('Wydatek'), 'Nazwa': TextCellValue('Pusty')}),
        row({'sty': DoubleCellValue(5)}),
      ]);

      final result =
          PlanExcel.parse(Uint8List.fromList(bytes), budgetId: kBudgetPersonal);

      final prad = result.positions.single;
      expect(prad.name, 'Prąd');
      expect(prad.months, hasLength(1));
      expect(prad.amountIn('2026-01'), closeTo(1234.5, 0.001));
      expect(result.skipped, hasLength(3)); // zła kwota, pusty, brak nazwy
    });

    test('miesiące poza okresem z arkusza są pomijane z raportem', () {
      final header = PlanExcel.headers;
      final bytes = sheet([
        header.map<CellValue?>(TextCellValue.new).toList(),
        [
          for (final h in header)
            switch (h) {
              'Rodzaj' => TextCellValue('Wydatek'),
              'Nazwa' => TextCellValue('Rata'),
              'Od' => TextCellValue('03.2026'),
              'Do' => TextCellValue('2026-04'),
              'lut' || 'mar' || 'kwi' || 'maj' => DoubleCellValue(-100),
              _ => null,
            },
        ],
        [
          for (final h in header)
            switch (h) {
              'Nazwa' => TextCellValue('Zły okres'),
              'Od' => TextCellValue('2026-05'),
              'Do' => TextCellValue('2026-01'),
              'sty' => DoubleCellValue(10),
              _ => null,
            },
        ],
      ]);

      final result = PlanExcel.parse(
        Uint8List.fromList(bytes),
        budgetId: kBudgetPersonal,
      );
      final rata = result.positions.firstWhere((p) => p.name == 'Rata');
      expect(rata.months.keys.toList()..sort(), ['2026-03', '2026-04']);
      expect(result.skipped, contains('Rata: pominięto 2 mies. poza okresem'));

      final bad = result.positions.firstWhere((p) => p.name == 'Zły okres');
      expect(bad.hasPeriod, isFalse);
      expect(
        result.skipped,
        contains('Zły okres: koniec okresu przed startem — okres pominięty'),
      );
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
