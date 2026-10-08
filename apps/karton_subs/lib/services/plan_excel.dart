import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:uuid/uuid.dart';

import '../models/category.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart' show Currency;

/// Plan roczny w arkuszu Excel (ADR-035) — tabela jak na ekranie Planowanie:
/// wiersz = pozycja, kolumny = 12 miesięcy roku. Jeden arkusz na rok
/// („Plan 2026", „Plan 2027"), pozycja przez dwa lata stoi w obu.
///
/// Służy do udostępniania budżetu (synchronizacja usunięta) i do poprawek
/// w Excelu. To NIE jest kopia zapasowa — od tego jest `.zostaje`.
///
/// Import czyta plik niezaufany: limity rozmiaru i wierszy, kwoty sprawdzane,
/// kategorie tylko dopasowywane po nazwie, każda pozycja dostaje NOWY
/// identyfikator (import dokłada, niczego nie nadpisuje). Pozycje karty nie
/// wracają z arkusza — para pożyczka/spłata żyje tylko w aplikacji.
class PlanExcel {
  PlanExcel._();

  static const sheetPrefix = 'Plan ';

  static const monthLabels = [
    'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
    'lip', 'sie', 'wrz', 'paź', 'lis', 'gru',
  ];

  static const List<String> headers = [
    'Rodzaj',
    'Nazwa',
    'Kategoria',
    'Metoda płatności',
    'Dzień',
    'Waluta',
    'Notatka',
    ...monthLabels,
    'Suma roku',
  ];

  static const int maxRows = 2000;
  static const int maxNameLength = 100;
  static const double maxAmount = 1000000;

  static String kindLabel(PlanKind kind) => switch (kind) {
        PlanKind.income => 'Wpływ',
        PlanKind.expense => 'Wydatek',
        PlanKind.cardLoan => 'Pożyczka z karty',
        PlanKind.cardRepayment => 'Spłata karty',
      };

  // ── Eksport ────────────────────────────────────────────────────────────────

  /// Arkusz dla każdego z [years], w którym jest choć jedna pozycja.
  /// Kolejność wierszy: wpływy, wydatki, karta — jak sekcje na ekranie.
  static Uint8List build({
    required List<PlanPosition> positions,
    required List<Category> categories,
    required List<int> years,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final catName = {for (final c in categories) c.id: c.name};
    final sorted = [...positions]..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    var sheets = 0;
    for (final year in years) {
      final rows = sorted.where((p) => p.hasYear(year)).toList();
      if (rows.isEmpty) continue;
      final name = '$sheetPrefix$year';
      if (sheets == 0) {
        excel.rename(defaultSheet, name);
      }
      final sheet = excel[name];
      sheets++;
      sheet.appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
      for (final p in rows) {
        sheet.appendRow(<CellValue?>[
          TextCellValue(kindLabel(p.kind)),
          TextCellValue(sanitizeCell(p.name)),
          TextCellValue(sanitizeCell(catName[p.categoryId] ?? '')),
          TextCellValue(sanitizeCell(p.paymentMethod ?? '')),
          p.day == null ? null : IntCellValue(p.day!),
          TextCellValue(p.currency.label),
          TextCellValue(sanitizeCell(p.note ?? '')),
          for (var m = 1; m <= 12; m++) _monthCell(p, year, m),
          DoubleCellValue(_signed(p, p.yearTotal(year))),
        ]);
      }
    }
    if (sheets == 0) {
      // Pusty plan: arkusz z samym nagłówkiem, żeby plik był wzorem do
      // wypełnienia, a nie „Sheet1" bez kolumn.
      final name = '$sheetPrefix${years.isEmpty ? DateTime.now().year : years.first}';
      excel.rename(defaultSheet, name);
      excel[name]
          .appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw const FormatException('Nie udało się zbudować arkusza planu');
    }
    return Uint8List.fromList(bytes);
  }

  /// Pusta komórka = pozycja w tym miesiącu nie obowiązuje; liczba (także 0)
  /// = obowiązuje z tą kwotą (wydatki ze znakiem minus). Dzień inny niż domyślny ginie — arkusz niesie
  /// kwoty, nie terminy pojedynczych miesięcy.
  static CellValue? _monthCell(PlanPosition p, int year, int month) {
    final pm = p.months[planMonthKey(year, month)];
    return pm == null ? null : DoubleCellValue(_signed(p, pm.amount));
  }

  /// Pieniądze wychodzące (wydatek, spłata karty) jako liczby ujemne — jak
  /// sumy na ekranie Planowanie; arkusz da się wtedy wprost zsumować.
  static double _signed(PlanPosition p, double amount) {
    final v = _round(p.isInflow ? amount : -amount);
    return v == 0 ? 0 : v;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));

  /// Ochrona przed wstrzyknięciem formuł: tekst zaczynający się od znaku
  /// formuły dostaje apostrof, więc Excel odbiorcy go nie wykona.
  static String sanitizeCell(String value) {
    if (value.isEmpty) return value;
    const dangerous = {'=', '+', '-', '@', '\t', '\r'};
    return dangerous.contains(value[0]) ? "'$value" : value;
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Bajty .xlsx → nowe pozycje planu w budżecie [budgetId] + raport pominięć.
  /// Ten sam wiersz (rodzaj + nazwa) z arkuszy kolejnych lat składa się
  /// w jedną pozycję — tak jak eksport rozpisał ją na lata.
  static PlanExcelImportResult parse(
    Uint8List bytes, {
    required String budgetId,
    Map<String, String> categoryIdByName = const {},
    DateTime? now,
  }) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Nie udało się odczytać pliku Excel (.xlsx)');
    }
    final created = now ?? DateTime.now();
    final byKey = <String, PlanPosition>{};
    final skipped = <String>[];
    var rowsRead = 0;
    var yearSheets = 0;

    for (final entry in excel.tables.entries) {
      final year = _yearOfSheet(entry.key);
      if (year == null) continue;
      yearSheets++;
      final rows = entry.value.rows;
      if (rows.isEmpty) continue;
      final col = _detectHeader(rows.first);
      if (!col.containsKey(_Col.name)) {
        skipped.add('${entry.key}: brak kolumny „Nazwa" — arkusz pominięty');
        continue;
      }

      for (var r = 1; r < rows.length; r++) {
        if (rowsRead >= maxRows) {
          skipped.add('Pominięto wiersze powyżej limitu $maxRows');
          break;
        }
        final cells = rows[r];
        String? cell(_Col c) {
          final i = col[c];
          if (i == null || i >= cells.length) return null;
          final t = cellText(cells[i])?.trim();
          return (t == null || t.isEmpty) ? null : t;
        }

        if (cells.every((c) => (cellText(c)?.trim() ?? '').isEmpty)) continue;
        rowsRead++;
        final where = '${entry.key}, wiersz ${r + 1}';

        var name = cell(_Col.name);
        if (name == null) {
          skipped.add('$where: brak nazwy');
          continue;
        }
        if (name.startsWith("'")) name = name.substring(1);
        if (name.length > maxNameLength) name = name.substring(0, maxNameLength);

        final kind = _parseKind(cell(_Col.kind));
        if (kind == null) {
          skipped.add('$where ($name): pozycje karty dodaje się w aplikacji');
          continue;
        }

        final months = <String, PlanMonth>{};
        var badAmount = false;
        for (var m = 1; m <= 12; m++) {
          final i = col[_Col.values[_Col.month1.index + m - 1]];
          if (i == null || i >= cells.length) continue;
          final raw = cellText(cells[i])?.trim();
          if (raw == null || raw.isEmpty) continue;
          // Znak kwoty niesie kolumna „Rodzaj"; minus przy wydatku (tak
          // eksportujemy) i jego brak (wpis ręczny) znaczą to samo.
          final amount = parseAmount(raw)?.abs();
          if (amount == null || amount > maxAmount) {
            badAmount = true;
            continue;
          }
          months[planMonthKey(year, m)] = PlanMonth(amount: _round(amount));
        }
        if (badAmount) {
          skipped.add('$where ($name): pominięto nieprawidłowe kwoty miesięcy');
        }
        if (months.isEmpty) {
          skipped.add('$where ($name): brak kwot w miesiącach');
          continue;
        }

        final key = '${kind.name}|${name.toLowerCase()}';
        final existing = byKey[key];
        if (existing != null) {
          byKey[key] = existing.copyWith(
            months: {...existing.months, ...months},
          );
          continue;
        }

        final day = int.tryParse(cell(_Col.day) ?? '');
        final category = cell(_Col.category)?.toLowerCase();
        byKey[key] = PlanPosition(
          id: const Uuid().v4(),
          budgetId: budgetId,
          name: name,
          kind: kind,
          currency: _parseCurrency(cell(_Col.currency)),
          categoryId: kind == PlanKind.expense && category != null
              ? categoryIdByName[category]
              : null,
          paymentMethod: _stripApostrophe(cell(_Col.payment)),
          day: day != null && day >= 1 && day <= 31 ? day : null,
          note: _stripApostrophe(cell(_Col.note)),
          months: months,
          createdAt: created,
        );
      }
    }

    if (yearSheets == 0) {
      throw const FormatException(
        'To nie jest arkusz planu — brak zakładki „Plan RRRR"',
      );
    }
    return PlanExcelImportResult(
      positions: byKey.values.toList(),
      skipped: skipped,
    );
  }

  static int? _yearOfSheet(String name) {
    final m = RegExp(r'^\s*plan\s+(\d{4})\s*$', caseSensitive: false)
        .firstMatch(name);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    return y >= 2000 && y <= 2100 ? y : null;
  }

  static Map<_Col, int> _detectHeader(List<Data?> cells) {
    final map = <_Col, int>{};
    for (var i = 0; i < cells.length; i++) {
      final h = cellText(cells[i])?.toLowerCase().trim();
      if (h == null || h.isEmpty) continue;
      final monthIdx = monthLabels.indexOf(h);
      _Col? c;
      if (monthIdx >= 0) {
        c = _Col.values[_Col.month1.index + monthIdx];
      } else if (h.startsWith('rodzaj')) {
        c = _Col.kind;
      } else if (h.startsWith('nazwa')) {
        c = _Col.name;
      } else if (h.startsWith('kateg')) {
        c = _Col.category;
      } else if (h.startsWith('metoda')) {
        c = _Col.payment;
      } else if (h.startsWith('dzie')) {
        c = _Col.day;
      } else if (h.startsWith('walut')) {
        c = _Col.currency;
      } else if (h.startsWith('notat')) {
        c = _Col.note;
      }
      if (c != null) map.putIfAbsent(c, () => i);
    }
    return map;
  }

  /// Rodzaj z kolumny „Rodzaj". Brak = wydatek (najczęstszy przypadek przy
  /// ręcznie dopisanym wierszu). `null` = pozycja karty (nie importujemy).
  static PlanKind? _parseKind(String? raw) {
    final t = raw?.toLowerCase() ?? '';
    if (t.contains('kart')) return null;
    if (t.contains('wpływ') || t.contains('wplyw') || t.contains('przych')) {
      return PlanKind.income;
    }
    return PlanKind.expense;
  }

  static Currency _parseCurrency(String? raw) {
    final t = raw?.toUpperCase();
    for (final c in Currency.values) {
      if (c.label.toUpperCase() == t || c.name.toUpperCase() == t) return c;
    }
    return Currency.PLN;
  }

  static String? _stripApostrophe(String? v) =>
      v != null && v.startsWith("'") ? v.substring(1) : v;

  /// Kwota z zapisu polskiego lub angielskiego („1 234,50", „1,234.50").
  static double? parseAmount(String raw) {
    var s = raw.replaceAll(RegExp(r'[^\d.,-]'), '');
    if (s.isEmpty) return null;
    final hasComma = s.contains(',');
    final hasDot = s.contains('.');
    if (hasComma && hasDot) {
      s = s.lastIndexOf(',') > s.lastIndexOf('.')
          ? s.replaceAll('.', '').replaceAll(',', '.')
          : s.replaceAll(',', '');
    } else if (hasComma) {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  static String? cellText(Data? cell) {
    final v = cell?.value;
    return switch (v) {
      null => null,
      TextCellValue() => v.value.text,
      IntCellValue() => v.value.toString(),
      DoubleCellValue() => v.value.toString(),
      BoolCellValue() => v.value.toString(),
      FormulaCellValue() => v.formula,
      _ => v.toString(),
    };
  }
}

enum _Col {
  kind,
  name,
  category,
  payment,
  day,
  currency,
  note,
  month1,
  month2,
  month3,
  month4,
  month5,
  month6,
  month7,
  month8,
  month9,
  month10,
  month11,
  month12,
}

/// Wynik importu planu — pozycje gotowe do zapisu (nowe id) + raport.
class PlanExcelImportResult {
  final List<PlanPosition> positions;
  final List<String> skipped;

  const PlanExcelImportResult({required this.positions, required this.skipped});

  int get importedCount => positions.length;
}
