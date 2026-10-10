import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/budget.dart';
import '../models/category.dart';
import '../models/plan_position.dart' show kBudgetHousehold, kBudgetPersonal;
import '../models/subscription.dart';
import '../utils/cycle_math.dart';
import 'app_logger.dart';
import 'plan_excel.dart';
import 'storage_service.dart';

/// Eksport/import subskrypcji do arkusza .xlsx.
///
/// To format "otwarty" (czytelny i edytowalny ręcznie w Excelu), w odróżnieniu
/// od zaszyfrowanego backupu .subkarton. Konsekwencje bezpieczeństwa:
///  - Eksport zapisuje dane JAWNIE — UI sygnalizuje "plik nieszyfrowany".
///  - Import czyta plik NIEZAUFANY (ręcznie edytowany), więc:
///    * parsowanie odbywa się poza głównym wątkiem (ochrona przed zawieszeniem
///      UI na dużym/spreparowanym pliku),
///    * obowiązują limity rozmiaru pliku i liczby wierszy,
///    * każdy wiersz jest walidowany, błędne są pomijane i raportowane,
///    * kategorie/metody płatności są tylko DOPASOWYWANE po nazwie (nie tworzymy
///      nowych z importu — ochrona przed masowym zaśmieceniem),
///    * każda subskrypcja dostaje NOWE id (import nigdy nie nadpisuje istniejących).
class ExcelService {
  static final _log = AppLogger.get('ExcelService');
  static const _uuid = Uuid();

  final StorageService _storage;
  ExcelService(this._storage);

  static const _sheetName = 'Subskrypcje';

  /// Limit rozmiaru importowanego pliku (5 MB) — ochrona przed bombą
  /// dekompresyjną / wyczerpaniem pamięci.
  static const int _maxFileBytes = 5 * 1024 * 1024;

  // Nagłówki kolumn — kolejność zgodna z [_HeaderField] niżej.
  static const List<String> _headers = [
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

  // ── Eksport ────────────────────────────────────────────────────────────────

  /// Buduje arkusz ze wszystkich subskrypcji i udostępnia przez system share.
  Future<void> exportToFile() async {
    final subs = _storage.getSubscriptions();
    // Subskrypcje wszystkich budżetów — nazwy kategorii z każdego (ADR-038).
    final categories = _storage.getAllCategories();
    final bytes = _buildWorkbook(subs, categories, _storage.getBudgets());

    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/subskrypcje_$dateStr.xlsx');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )
      ],
      subject: 'Zostaje — arkusz',
    );

    // Plik tymczasowy zawiera jawne dane finansowe — kasujemy po chwili.
    Future.delayed(const Duration(minutes: 2), () {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // best-effort; katalog cache jest sandboxowany (tylko ta aplikacja).
      }
    });

    _log.info('Wyeksportowano ${subs.length} subskrypcji do .xlsx');
  }

  static Uint8List _buildWorkbook(
    List<Subscription> subs,
    List<Category> categories, [
    List<Budget> budgets = Budget.defaults,
  ]) {
    final budgetName = {for (final b in budgets) b.id: b.name};
    final excel = Excel.createExcel();
    // createExcel() tworzy domyślny "Sheet1" — zmieniamy nazwę na czytelną.
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', _sheetName);
    final sheet = excel[_sheetName];

    sheet.appendRow(_headers.map<CellValue?>((h) => TextCellValue(h)).toList());

    String? catName(String? id) {
      if (id == null) return null;
      for (final c in categories) {
        if (c.id == id) return c.name;
      }
      return null;
    }

    for (final s in subs) {
      sheet.appendRow(<CellValue?>[
        TextCellValue(_sanitizeCell(s.name)),
        DoubleCellValue(s.amount),
        TextCellValue(s.currency.label),
        TextCellValue(_cycleLabel(s.billingCycle, s.customCycleDays, s.cycleMonths)),
        TextCellValue(_sanitizeCell(catName(s.categoryId) ?? '')),
        TextCellValue(_sanitizeCell(s.paymentMethod ?? '')),
        TextCellValue(s.isActive ? 'tak' : 'nie'),
        TextCellValue(DateFormat('yyyy-MM-dd').format(s.startDate)),
        // Kolumna „Zakres" niesie nazwę budżetu (ADR-037); import dopasowuje
        // ją po nazwie, a stare „Osobiste/Domowe" — do dwóch pierwszych.
        TextCellValue(_sanitizeCell(budgetName[s.budgetId] ?? '')),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw const FormatException('Nie udało się zbudować arkusza');
    }
    return Uint8List.fromList(bytes);
  }

  /// Ochrona przed wstrzyknięciem formuł (CSV/DDE injection): komórka tekstowa
  /// zaczynająca się od znaku formuły zostaje poprzedzona apostrofem, dzięki
  /// czemu Excel odbiorcy potraktuje ją jako tekst, a nie wykona.
  static String _sanitizeCell(String value) {
    if (value.isEmpty) return value;
    const dangerous = {'=', '+', '-', '@', '\t', '\r'};
    if (dangerous.contains(value[0])) return "'$value";
    return value;
  }

  static String _cycleLabel(
    BillingCycle cycle,
    int? customDays, [
    List<int>? cycleMonths,
  ]) {
    switch (cycle) {
      case BillingCycle.weekly:
        return 'tygodniowo';
      case BillingCycle.monthly:
        return 'miesięcznie';
      case BillingCycle.quarterly:
        return 'kwartalnie';
      case BillingCycle.yearly:
        return 'rocznie';
      case BillingCycle.monthsOfYear:
        // Format czytelny i odwracalny przy imporcie: „miesiące: 1,4,9".
        return 'miesiące: ${normalizedCycleMonths(cycleMonths).join(',')}';
      case BillingCycle.custom:
        return 'co ${customDays ?? 30} dni';
    }
  }

  // ── Import ───────────────────────────────────────────────────────────────────

  /// Otwiera file picker, parsuje arkusz poza głównym wątkiem, mapuje wiersze na
  /// gotowe subskrypcje (nowe id). NIE zapisuje — zwraca wynik do zatwierdzenia.
  /// [fallbackBudgetId] — budżet dla wierszy bez rozpoznanego „Zakresu"
  /// (zwykle aktywny).
  Future<ExcelImportResult> pickAndParse({
    String fallbackBudgetId = kBudgetPersonal,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      throw const FormatException('Nie wybrano pliku');
    }
    final picked = result.files.first;
    if (!picked.name.toLowerCase().endsWith('.xlsx')) {
      throw const FormatException(
          'Nieprawidłowy plik. Wybierz plik Excel (.xlsx)');
    }
    final bytes = picked.bytes;
    if (bytes == null) {
      throw const FormatException('Nie udało się odczytać pliku');
    }
    if (bytes.length > _maxFileBytes) {
      throw const FormatException('Plik jest za duży (limit 5 MB)');
    }

    // Parsowanie w osobnym wątku — duży/spreparowany plik nie zawiesi UI.
    final raw = await compute(_parseWorkbook, bytes);

    return _mapRowsToSubscriptions(raw, fallbackBudgetId);
  }

  /// Mapuje surowe wiersze na subskrypcje. Wykonywane na głównym wątku, bo
  /// wymaga dostępu do bazy (dopasowanie kategorii/metod płatności po nazwie).
  ExcelImportResult _mapRowsToSubscriptions(
    _RawParse raw,
    String fallbackBudgetId,
  ) {
    // Mapy do dopasowania po nazwie (case-insensitive), osobno dla każdego
    // budżetu — kategorie i metody są jego własne (ADR-038). Zachowujemy
    // oryginalną pisownię z bazy (id kategorii, dokładną nazwę metody).
    final catByName = <String, Map<String, String>>{};
    for (final c in _storage.getAllCategories()) {
      final b = c.budgetId;
      if (b != null) (catByName[b] ??= {})[c.name.toLowerCase().trim()] = c.id;
    }
    final pmByName = <String, Map<String, String>>{};
    for (final p in _storage.getAllPaymentMethods()) {
      final b = p.budgetId;
      if (b != null) (pmByName[b] ??= {})[p.name.toLowerCase().trim()] = p.name;
    }
    final existingNames = _storage
        .getSubscriptions()
        .map((s) => s.name.toLowerCase().trim())
        .toSet();

    return _buildResult(
      raw,
      catByName,
      pmByName,
      existingNames,
      _storage.getBudgets(),
      fallbackBudgetId,
    );
  }

  /// Budżet z kolumny „Zakres": nazwa budżetu (bez wielkości liter), a dla
  /// arkuszy sprzed ADR-037 — „Osobiste"/„Domowe"; inaczej [fallback].
  static String _budgetFor(
    String? raw,
    List<Budget> budgets,
    String fallback,
  ) {
    final t = raw?.toLowerCase().trim() ?? '';
    if (t.isEmpty) return fallback;
    for (final b in budgets) {
      if (b.name.toLowerCase().trim() == t) return b.id;
    }
    bool has(String id) => budgets.any((b) => b.id == id);
    if ((t.contains('domow') || t.contains('household')) &&
        has(kBudgetHousehold)) {
      return kBudgetHousehold;
    }
    if ((t.contains('osobist') || t.contains('personal')) &&
        has(kBudgetPersonal)) {
      return kBudgetPersonal;
    }
    return fallback;
  }

  static ExcelImportResult _buildResult(
    _RawParse raw,
    Map<String, Map<String, String>> catByName,
    Map<String, Map<String, String>> pmByName,
    Set<String> existingNames, [
    List<Budget> budgets = Budget.defaults,
    String fallbackBudgetId = kBudgetPersonal,
  ]) {
    final now = DateTime.now();
    final subscriptions = <Subscription>[];
    final warnings = <String>[];

    for (final row in raw.rows) {
      // Kategoria i metoda z listy budżetu wiersza; brak na niej — pusto
      // (import niczego do list budżetu nie dodaje).
      final budgetId = _budgetFor(row.budgetName, budgets, fallbackBudgetId);
      final categoryName = row.categoryName?.toLowerCase().trim();
      final categoryId = categoryName == null
          ? null
          : catByName[budgetId]?[categoryName];
      final paymentName = row.paymentName?.toLowerCase().trim();
      final paymentMethod = paymentName == null
          ? null
          : pmByName[budgetId]?[paymentName];

      if (existingNames.contains(row.name.toLowerCase().trim())) {
        warnings.add('„${row.name}" — subskrypcja o tej nazwie już istnieje '
            '(dodano jako nową)');
      }

      subscriptions.add(Subscription(
        id: _uuid.v4(),
        name: row.name,
        amount: row.amount,
        currency: row.currency,
        billingCycle: row.billingCycle,
        customCycleDays: row.customCycleDays,
        cycleMonths: row.cycleMonths,
        categoryId: categoryId,
        startDate: row.startDate,
        isActive: row.isActive,
        paymentMethod: paymentMethod,
        budgetId: budgetId,
        dataDodania: now,
      ));
    }

    _log.info(
        'Import .xlsx: ${subscriptions.length} gotowych, ${raw.skipped.length} pominiętych');
    return ExcelImportResult(
      subscriptions: subscriptions,
      skipped: raw.skipped,
      warnings: warnings,
    );
  }

  /// Hook testowy: parsuje bajty .xlsx bez dostępu do bazy (puste słowniki
  /// dopasowań). Umożliwia test parsera + walidacji bez inicjalizacji Hive.
  @visibleForTesting
  static ExcelImportResult parseBytesForTest(Uint8List bytes) =>
      _buildResult(_parseWorkbook(bytes), const {}, const {}, <String>{});

  /// Hook testowy: udostępnia sanityzację formuł (ochrona przed CSV injection).
  @visibleForTesting
  static String sanitizeCellForTest(String value) => _sanitizeCell(value);

  /// Hook testowy: buduje bajty arkusza .xlsx (ścieżka eksportu) bez share/IO.
  @visibleForTesting
  static Uint8List buildWorkbookForTest(
    List<Subscription> subs,
    List<Category> categories,
  ) =>
      _buildWorkbook(subs, categories);

  // ── Plan roczny (ADR-035) ──────────────────────────────────────────────────

  /// Tabela roku wybranego budżetu (arkusz na każdy rok z [years]) przez
  /// systemowe okno udostępniania.
  Future<void> exportPlanToFile({
    required String budgetId,
    required String budgetLabel,
    required List<int> years,
  }) async {
    final positions =
        _storage.getPlanPositions(budgetId).where((p) => !p.archived).toList();
    final bytes = PlanExcel.build(
      positions: positions,
      categories: _storage.getCategories(budgetId),
      years: years,
    );

    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Nazwa budżetu jest dowolna (ADR-037) — w nazwie pliku tylko litery
    // i cyfry, reszta (spacje, ukośniki) jako „_".
    final safeLabel = budgetLabel
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final file = File(
      '${dir.path}/plan_${safeLabel.isEmpty ? 'budzet' : safeLabel}_$dateStr.xlsx',
    );
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )
      ],
      subject: 'Zostaje — plan',
    );

    // Plik tymczasowy zawiera jawne dane finansowe — kasujemy po chwili.
    Future.delayed(const Duration(minutes: 2), () {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // best-effort; katalog cache jest sandboxowany.
      }
    });

    _log.info('Wyeksportowano plan ($budgetId): ${positions.length} pozycji');
  }

  /// Otwiera wybór pliku i czyta tabelę roku poza głównym wątkiem. NIE
  /// zapisuje — zwraca pozycje (nowe id) przypisane do budżetu [budgetId].
  Future<PlanExcelImportResult> pickAndParsePlan(String budgetId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      throw const FormatException('Nie wybrano pliku');
    }
    final picked = result.files.first;
    if (!picked.name.toLowerCase().endsWith('.xlsx')) {
      throw const FormatException(
          'Nieprawidłowy plik. Wybierz plik Excel (.xlsx)');
    }
    final bytes = picked.bytes;
    if (bytes == null) {
      throw const FormatException('Nie udało się odczytać pliku');
    }
    if (bytes.length > _maxFileBytes) {
      throw const FormatException('Plik jest za duży (limit 5 MB)');
    }

    // Kategorie budżetu, do którego trafią pozycje (ADR-038).
    final catByName = {
      for (final c in _storage.getCategories(budgetId))
        c.name.toLowerCase().trim(): c.id,
    };
    return await compute(
      _parsePlanWorkbook,
      (bytes, budgetId, catByName),
    );
  }

}

/// Wynik importu — subskrypcje gotowe do zapisu + raport.
class ExcelImportResult {
  /// Subskrypcje z nadanymi nowymi id, jeszcze nie zapisane w bazie.
  final List<Subscription> subscriptions;

  /// Powody pominięcia wierszy (np. brak nazwy, nieprawidłowa kwota).
  final List<String> skipped;

  /// Ostrzeżenia niewstrzymujące importu (np. duplikat nazwy).
  final List<String> warnings;

  ExcelImportResult({
    required this.subscriptions,
    required this.skipped,
    required this.warnings,
  });

  int get importedCount => subscriptions.length;
  int get skippedCount => skipped.length;
}

// ── Parsowanie w osobnym wątku (czysty Dart, bez dostępu do bazy) ──────────────

/// Surowy wynik parsowania — tylko typy przesyłalne między izolatami.
class _RawParse {
  final List<_RawRow> rows;
  final List<String> skipped;
  _RawParse(this.rows, this.skipped);
}

class _RawRow {
  final String name;
  final double amount;
  final Currency currency;
  final BillingCycle billingCycle;
  final int? customCycleDays;
  final List<int>? cycleMonths;
  final String? categoryName;
  final String? paymentName;
  final bool isActive;
  final DateTime startDate;
  /// Surowa wartość kolumny „Zakres" (nazwa budżetu).
  final String? budgetName;

  _RawRow({
    required this.name,
    required this.amount,
    required this.currency,
    required this.billingCycle,
    this.customCycleDays,
    this.cycleMonths,
    this.categoryName,
    this.paymentName,
    required this.isActive,
    required this.startDate,
    this.budgetName,
  });
}

/// Maksymalna liczba przetwarzanych wierszy danych — ochrona przed gigantycznym
/// plikiem (wyczerpanie pamięci / czas parsowania).
const int _maxDataRows = 2000;

/// Maksymalna długość nazwy — chroni UI i bazę przed skrajnie długim tekstem.
const int _maxNameLength = 100;

/// Górny rozsądny limit kwoty za okres — odrzuca śmieciowe/absurdalne wartości.
const double _maxAmount = 1000000;

enum _HeaderField {
  name,
  amount,
  currency,
  cycle,
  category,
  payment,
  active,
  date,
  scope
}

/// Funkcja izolatu (compute): bajty .xlsx → surowe wiersze + lista pominięć.
/// Nie dotyka bazy ani UI. Rzuca FormatException przy uszkodzonym pliku.
_RawParse _parseWorkbook(Uint8List bytes) {
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Nie udało się odczytać pliku Excel (.xlsx)');
  }

  if (excel.tables.isEmpty) {
    throw const FormatException('Plik nie zawiera żadnego arkusza');
  }
  // Bierzemy pierwszy arkusz.
  final sheet = excel.tables.values.first;
  final allRows = sheet.rows;
  if (allRows.isEmpty) {
    return _RawParse([], const ['Arkusz jest pusty']);
  }

  // 1. Wykryj nagłówki. Jeśli nie ma rozpoznawalnego nagłówka — zakładamy
  //    układ pozycyjny: kolumna 0 = Nazwa, kolumna 1 = Kwota (i pierwszy wiersz
  //    to już dane).
  final headerMap = _detectHeader(allRows.first);
  final hasHeader = headerMap.containsKey(_HeaderField.name) &&
      headerMap.containsKey(_HeaderField.amount);

  final Map<_HeaderField, int> col;
  final int firstDataRow;
  if (hasHeader) {
    col = headerMap;
    firstDataRow = 1;
  } else {
    col = const {_HeaderField.name: 0, _HeaderField.amount: 1};
    firstDataRow = 0;
  }

  final rows = <_RawRow>[];
  final skipped = <String>[];

  for (var r = firstDataRow; r < allRows.length; r++) {
    final dataIndex = r - firstDataRow + 1; // numer wiersza danych dla raportu
    if (rows.length >= _maxDataRows) {
      skipped.add('Pominięto wiersze powyżej limitu $_maxDataRows');
      break;
    }

    final cells = allRows[r];
    String? cell(_HeaderField f) {
      final i = col[f];
      if (i == null || i >= cells.length) return null;
      return _cellText(cells[i]);
    }

    // Pomiń całkowicie puste wiersze (bez zgłaszania błędu).
    final rawName = cell(_HeaderField.name)?.trim();
    final rawAmount = cell(_HeaderField.amount)?.trim();
    final isEmptyRow = cells.every((c) {
      final t = _cellText(c);
      return t == null || t.trim().isEmpty;
    });
    if (isEmptyRow) continue;

    if (rawName == null || rawName.isEmpty) {
      skipped.add('Wiersz $dataIndex: brak nazwy');
      continue;
    }
    final amount = _parseAmount(rawAmount);
    if (amount == null) {
      skipped.add('Wiersz $dataIndex ($rawName): nieprawidłowa kwota');
      continue;
    }
    if (amount <= 0 || amount > _maxAmount) {
      skipped.add('Wiersz $dataIndex ($rawName): kwota poza zakresem');
      continue;
    }

    final name = rawName.length > _maxNameLength
        ? rawName.substring(0, _maxNameLength)
        : rawName;
    final (cycle, customDays, cycleMonths) = _parseCycle(cell(_HeaderField.cycle));

    rows.add(_RawRow(
      name: name,
      amount: double.parse(amount.toStringAsFixed(2)),
      currency: _parseCurrency(cell(_HeaderField.currency)),
      billingCycle: cycle,
      customCycleDays: customDays,
      cycleMonths: cycleMonths,
      categoryName: _blankToNull(cell(_HeaderField.category)),
      paymentName: _blankToNull(cell(_HeaderField.payment)),
      isActive: _parseActive(cell(_HeaderField.active)),
      startDate: _parseDate(cell(_HeaderField.date)),
      budgetName: _blankToNull(cell(_HeaderField.scope)),
    ));
  }

  return _RawParse(rows, skipped);
}

Map<_HeaderField, int> _detectHeader(List<Data?> headerCells) {
  final map = <_HeaderField, int>{};
  for (var i = 0; i < headerCells.length; i++) {
    final raw = _cellText(headerCells[i]);
    if (raw == null) continue;
    final h = raw.toLowerCase().trim();
    if (h.isEmpty) continue;

    _HeaderField? field;
    if (h.contains('nazwa') || h.contains('name')) {
      field = _HeaderField.name;
    } else if (h.contains('kwota') ||
        h.contains('cena') ||
        h.contains('amount') ||
        h.contains('price')) {
      field = _HeaderField.amount;
    } else if (h.contains('walut') || h.contains('currency')) {
      field = _HeaderField.currency;
    } else if (h.contains('cykl') ||
        h.contains('okres') ||
        h.contains('cycle') ||
        h.contains('period')) {
      field = _HeaderField.cycle;
    } else if (h.contains('kateg') || h.contains('category')) {
      field = _HeaderField.category;
    } else if (h.contains('płat') ||
        h.contains('plat') ||
        h.contains('payment') ||
        h.contains('metoda')) {
      field = _HeaderField.payment;
    } else if (h.contains('aktyw') ||
        h.contains('active') ||
        h.contains('status')) {
      field = _HeaderField.active;
    } else if (h.contains('data') ||
        h.contains('start') ||
        h.contains('date')) {
      field = _HeaderField.date;
    } else if (h.contains('zakres') ||
        h.contains('scope') ||
        h.contains('przynale')) {
      field = _HeaderField.scope;
    }
    // Pierwsze dopasowanie wygrywa (nie nadpisujemy).
    if (field != null && !map.containsKey(field)) {
      map[field] = i;
    }
  }
  return map;
}

/// Wyciąga tekst z komórki niezależnie od typu wartości. Formuły zwracane są
/// jako literalny tekst (pakiet nie ewaluuje) — bezpieczne przy odczycie.
String? _cellText(Data? cell) {
  final v = cell?.value;
  if (v == null) return null;
  switch (v) {
    case TextCellValue():
      return v.value.text;
    case IntCellValue():
      return v.value.toString();
    case DoubleCellValue():
      return v.value.toString();
    case BoolCellValue():
      return v.value ? 'true' : 'false';
    case DateCellValue():
      return '${v.year.toString().padLeft(4, '0')}-'
          '${v.month.toString().padLeft(2, '0')}-'
          '${v.day.toString().padLeft(2, '0')}';
    case DateTimeCellValue():
      return v.asDateTimeLocal().toIso8601String();
    case TimeCellValue():
      return v.toString();
    case FormulaCellValue():
      return v.formula;
  }
}

String? _blankToNull(String? v) {
  if (v == null) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Parsuje kwotę tolerując polskie i angielskie formaty: "43,00", "43.00",
/// "1 234,56", "1,234.56", z symbolami waluty. Zwraca null gdy nie da się.
double? _parseAmount(String? raw) {
  if (raw == null) return null;
  var s = raw.replaceAll(RegExp(r'[^\d.,-]'), '');
  if (s.isEmpty) return null;

  final hasComma = s.contains(',');
  final hasDot = s.contains('.');
  if (hasComma && hasDot) {
    // Separatorem dziesiętnym jest ten z prawej; drugi to separator tysięcy.
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma) {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s);
}

Currency _parseCurrency(String? raw) {
  if (raw == null) return Currency.PLN;
  final t = raw.trim().toUpperCase();
  for (final c in Currency.values) {
    if (c.name.toUpperCase() == t || c.label.toUpperCase() == t) return c;
  }
  return Currency.PLN;
}

(BillingCycle, int?, List<int>?) _parseCycle(String? raw) {
  if (raw == null) return (BillingCycle.monthly, null, null);
  final t = raw.toLowerCase().trim();
  // „miesiące: 1,4,9" — wzor roczny (ADR-020). Sprawdzane PRZED „mies", bo
  // slowo „miesiace" zawiera ten sam rdzen co cykl miesieczny.
  if (t.startsWith('miesiąc') || t.startsWith('miesiac') || t.startsWith('months')) {
    final months = RegExp(r'\d+')
        .allMatches(t)
        .map((m) => int.parse(m.group(0)!))
        .where((m) => m >= 1 && m <= 12)
        .toSet()
        .toList()
      ..sort();
    if (months.isNotEmpty) return (BillingCycle.monthsOfYear, null, months);
  }
  if (t.contains('tyg') || t.contains('week')) {
    return (BillingCycle.weekly, null, null);
  }
  if (t.contains('kwart') || t.contains('quart')) {
    return (BillingCycle.quarterly, null, null);
  }
  if (t.contains('rok') ||
      t.contains('rocz') ||
      t.contains('year') ||
      t.contains('annual')) {
    return (BillingCycle.yearly, null, null);
  }
  if (t.contains('dni') || t.contains('custom') || t.contains('day')) {
    final m = RegExp(r'\d+').firstMatch(t);
    final days = m != null ? int.tryParse(m.group(0)!) : null;
    return (BillingCycle.custom, (days != null && days > 0) ? days : 30, null);
  }
  return (BillingCycle.monthly, null, null);
}

bool _parseActive(String? raw) {
  if (raw == null) return true;
  final t = raw.toLowerCase().trim();
  const falsy = {'nie', 'no', 'false', '0', 'nieaktywna', 'anulowana'};
  return !falsy.contains(t);
}

/// Parsuje datę startu z kilku formatów. Wartość nieczytelna lub poza rozsądnym
/// zakresem → dzisiejsza data (import nie przerywa się przez złą datę).
DateTime _parseDate(String? raw) {
  final fallback = DateTime.now();
  if (raw == null || raw.trim().isEmpty) return fallback;
  final t = raw.trim();

  DateTime? parsed = DateTime.tryParse(t);
  if (parsed == null) {
    for (final fmt in ['dd.MM.yyyy', 'dd/MM/yyyy', 'yyyy-MM-dd', 'd.M.yyyy']) {
      try {
        parsed = DateFormat(fmt).parseStrict(t);
        break;
      } catch (_) {
        // próbuj następny format
      }
    }
  }
  if (parsed == null) return fallback;
  if (parsed.year < 1990 || parsed.year > fallback.year + 50) return fallback;
  return parsed;
}

/// Funkcja izolatu (compute) dla [ExcelService.pickAndParsePlan].
PlanExcelImportResult _parsePlanWorkbook(
  (Uint8List, String, Map<String, String>) input,
) {
  final (bytes, budgetId, catByName) = input;
  return PlanExcel.parse(
    bytes,
    budgetId: budgetId,
    categoryIdByName: catByName,
  );
}
