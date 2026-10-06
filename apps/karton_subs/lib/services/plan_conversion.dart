// plan_conversion.dart — przejście ze starego modelu budżetu (kwota + cykl
// + korekty miesięcy) na plan roczny (pozycje z miesiącami) — ADR-035.
//
// Logika jest czysta (bez bazy), żeby reguły dało się sprawdzić testami na
// każdym rodzaju pozycji. Zapis do bazy robi [PlanConversionRunner].

import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart' show BillingCycle, Currency;
import '../utils/cycle_math.dart';
import 'currency_service.dart';
import 'storage_service.dart';

/// Co konwersja zrobiła z pozycją, która NIE stała się pozycją planu albo
/// przeszła z uwagą.
enum PlanNoteKind {
  /// Wydatek z „Bieżących" — zostaje w starym zapisie bez zmian.
  spendingKept,

  /// Pozycja karty kredytowej (lustro zakupu, pożyczka z karty) — zostaje
  /// w starym zapisie; decyzja, co przenieść do planu, po przejrzeniu.
  cardKept,

  /// Nie dało się przenieść (brakujące dane) — zostaje w starym zapisie.
  skipped,

  /// Przeniesiona, ale z przybliżeniem wartym sprawdzenia.
  remark,
}

class PlanConversionNote {
  final String budgetId;
  final String entryId;
  final String name;
  final PlanNoteKind kind;
  final String message;

  const PlanConversionNote({
    required this.budgetId,
    required this.entryId,
    required this.name,
    required this.kind,
    required this.message,
  });
}

class PlanConversionResult {
  final List<PlanPosition> positions;
  final List<PlanConversionNote> notes;

  const PlanConversionResult({required this.positions, required this.notes});

  Iterable<PlanConversionNote> notesOf(PlanNoteKind kind) =>
      notes.where((n) => n.kind == kind);
}

/// Reguły konwersji (ADR-035).
///
/// - Koszt i wpływ cykliczny → miesiące bieżącego i następnego roku według
///   cyklu i daty startu. Płatność kwartalna, roczna i „wybrane miesiące"
///   trafia CAŁĄ kwotą w miesiące płatności, więc średnia roku = dawna
///   kwota/mies. Tygodniowa i „co N dni" nie mają jednego dnia w miesiącu —
///   dostają średnią miesięczną w każdym miesiącu.
/// - Korekta kwoty → kwota tego miesiąca; korekta samej daty → dzień miesiąca.
/// - Rata → wszystkie miesiące okresu spłaty (także poza oknem dwóch lat).
/// - Przelew do domowego → zwykły wydatek; jego lustro w domowym → zwykły
///   wpływ. Powiązanie znika (ADR-035: rezygnacja z przelewów wewnętrznych).
/// - Premia (wpływ jednorazowy) → wpływ z jednym miesiącem.
/// - Wstrzymana → pozycja archiwalna.
/// - Bieżące i pozycje karty zostają w starym zapisie bez zmian.
///
/// Identyfikator pozycji = identyfikator starej pozycji: odhaczenia płatności
/// (`payment_done`) mają go w kluczu, więc nie przepadną.
class PlanConversion {
  PlanConversion._();

  /// Wersja reguł. Konwersja przy starcie działa, dopóki zapisany plan
  /// pochodzi ze starszej wersji reguł — podbicie po tym, jak plan zacznie
  /// być edytowany, nadpisałoby te zmiany.
  static const version = 1;

  /// Pierwszy i ostatni rok okna, w którym rozpisujemy pozycje cykliczne:
  /// bieżący i następny (plan na kolejny rok powstaje tuż przed jego startem).
  static ({int first, int last}) windowFor(DateTime today) =>
      (first: today.year, last: today.year + 1);

  static PlanConversionResult convert({
    required Map<String, List<BudgetEntry>> entriesByBudget,
    required DateTime today,
  }) {
    final window = windowFor(today);
    final positions = <PlanPosition>[];
    final notes = <PlanConversionNote>[];

    for (final MapEntry(key: budgetId, value: entries)
        in entriesByBudget.entries) {
      for (final e in entries) {
        if (e.deleted) continue;
        void note(PlanNoteKind kind, String message) => notes.add(
          PlanConversionNote(
            budgetId: budgetId,
            entryId: e.id,
            name: e.name,
            kind: kind,
            message: message,
          ),
        );

        if (e.type == BudgetEntryType.spending) {
          note(PlanNoteKind.spendingKept, 'Bieżące — bez zmian');
          continue;
        }
        if (e.creditLinkId != null) {
          note(PlanNoteKind.cardKept, 'Pozycja karty — do przejrzenia');
          continue;
        }

        final Map<String, PlanMonth> months;
        int? day = e.startDate?.day;
        if (e.type == BudgetEntryType.oneTimeIncome) {
          final key =
              e.month ??
              (e.startDate != null
                  ? BudgetEntry.monthKeyOf(e.startDate!)
                  : null);
          if (key == null) {
            note(PlanNoteKind.skipped, 'Wpływ jednorazowy bez miesiąca');
            continue;
          }
          final s = e.startDate;
          months = {
            key: PlanMonth(
              amount: e.amount,
              day: s != null && BudgetEntry.monthKeyOf(s) == key ? s.day : null,
            ),
          };
          day = null;
        } else if (e.isInstallment) {
          final s = e.startDate;
          final n = e.installmentCount;
          if (s == null || n == null || n <= 0) {
            note(
              PlanNoteKind.skipped,
              'Rata bez daty pierwszej raty lub liczby rat',
            );
            continue;
          }
          months = {
            for (var i = 0; i < n; i++)
              BudgetEntry.monthKeyOf(DateTime(s.year, s.month + i)): PlanMonth(
                amount: e.monthlyAmount,
              ),
          };
        } else {
          months = _cyclicMonths(e, window, note);
          if (e.cycle == BillingCycle.weekly ||
              e.cycle == BillingCycle.custom) {
            day = null;
          }
          _applyOverrides(e, months);
        }

        positions.add(
          PlanPosition(
            id: e.id,
            budgetId: budgetId,
            name: e.name,
            kind: e.isIncome ? PlanKind.income : PlanKind.expense,
            currency: e.currency,
            categoryId: e.categoryId,
            paymentMethod: e.paymentMethod,
            day: day,
            note: e.note,
            archived: !e.isActive,
            months: months,
            createdAt: e.dataDodania,
            updatedAt: e.updatedAt,
          ),
        );
      }
    }
    return PlanConversionResult(positions: positions, notes: notes);
  }

  /// Miesiące pozycji cyklicznej w oknie lat. Pozycja startująca po oknie
  /// dostaje swój pierwszy rok — inaczej zniknęłaby z planu bez śladu.
  static Map<String, PlanMonth> _cyclicMonths(
    BudgetEntry e,
    ({int first, int last}) window,
    void Function(PlanNoteKind, String) note,
  ) {
    final start = e.startDate;
    final lastYear = start != null && start.year > window.last
        ? start.year
        : window.last;
    final from = DateTime(window.first, 1, 1);
    final to = DateTime(lastYear, 12, 31);
    final startKey = start != null ? BudgetEntry.monthKeyOf(start) : null;
    final months = <String, PlanMonth>{};

    void everyMonth(double amount) {
      for (var y = window.first; y <= lastYear; y++) {
        for (var m = 1; m <= 12; m++) {
          final key = planMonthKey(y, m);
          if (startKey != null && key.compareTo(startKey) < 0) continue;
          months[key] = PlanMonth(amount: amount);
        }
      }
    }

    switch (e.cycle) {
      case BillingCycle.monthly:
        everyMonth(e.amount);
      case BillingCycle.weekly:
      case BillingCycle.custom:
        everyMonth(e.monthlyAmount);
        note(
          PlanNoteKind.remark,
          e.cycle == BillingCycle.weekly
              ? 'Cykl tygodniowy → średnia miesięczna w każdym miesiącu'
              : 'Cykl co ${e.customCycleDays ?? 30} dni → średnia miesięczna '
                    'w każdym miesiącu',
        );
      case BillingCycle.quarterly:
      case BillingCycle.yearly:
      case BillingCycle.monthsOfYear:
        // Bez daty startu „wybrane miesiące" obowiązują od początku okna,
        // ale kwartał i rok potrzebują punktu odniesienia — najlepszy, jaki
        // mamy, to dzień dodania pozycji.
        final DateTime anchor;
        if (start != null) {
          anchor = start;
        } else if (e.cycle == BillingCycle.monthsOfYear) {
          anchor = from;
        } else {
          anchor = e.dataDodania;
          note(
            PlanNoteKind.remark,
            'Brak daty startu — miesiące płatności liczone od dnia dodania',
          );
        }
        for (final d in occurrencesInRange(
          anchor,
          e.cycle,
          e.customCycleDays,
          from,
          to,
          cycleMonths: e.cycleMonths,
        )) {
          months[BudgetEntry.monthKeyOf(d)] = PlanMonth(amount: e.amount);
        }
    }
    return months;
  }

  /// Korekty miesięcy (ADR-008) jako zwykłe miesiące pozycji. Korekta spoza
  /// okna też przechodzi — to dane wpisane ręcznie, nie wolno ich zgubić.
  static void _applyOverrides(BudgetEntry e, Map<String, PlanMonth> months) {
    final overrides = e.monthOverrides;
    if (overrides == null) return;
    for (final MapEntry(key: key, value: ov) in overrides.entries) {
      final ovDate = ov.date;
      final ovDay = ovDate != null && BudgetEntry.monthKeyOf(ovDate) == key
          ? ovDate.day
          : null;
      final amount = ov.amount;
      if (amount != null) {
        months[key] = PlanMonth(amount: amount, day: ovDay ?? months[key]?.day);
      } else if (ovDay != null && months.containsKey(key)) {
        months[key] = months[key]!.copyWith(day: ovDay);
      }
    }
  }
}

// ── Raport konwersji (Developer Tools) ──────────────────────────────────────

/// Sumy roku jednego budżetu: dawny model vs nowy plan (w walucie docelowej).
class PlanYearCheck {
  final String budgetId;
  final int year;
  final double oldIncome;
  final double newIncome;
  final double oldExpense;
  final double newExpense;

  const PlanYearCheck({
    required this.budgetId,
    required this.year,
    required this.oldIncome,
    required this.newIncome,
    required this.oldExpense,
    required this.newExpense,
  });
}

/// Pozycja, której suma roku różni się po konwersji (w walucie pozycji).
class PlanEntryMismatch {
  final String budgetId;
  final String name;
  final int year;
  final double oldTotal;
  final double newTotal;
  final Currency currency;

  /// Krótki opis źródła różnicy: cykl, start, liczba korekt.
  final String detail;

  const PlanEntryMismatch({
    required this.budgetId,
    required this.name,
    required this.year,
    required this.oldTotal,
    required this.newTotal,
    required this.currency,
    required this.detail,
  });
}

/// Porównanie starego modelu z nowym planem — po to, by konwersję dało się
/// sprawdzić na prawdziwych danych na telefonie, bez wynoszenia ich z niego.
///
/// „Stara" suma roku liczy się tak jak dawne koszty cykliczne miesiąca
/// (kwota/mies + różnica korekty, tylko w miesiącach, w których pozycja już
/// istniała). Różnica przy płatnościach kwartalnych i rocznych z niepełnym
/// rokiem jest oczekiwana: nowy plan pokazuje płatność w jej miesiącu, stary
/// rozkładał ją równo na miesiące.
class PlanConversionReport {
  final PlanConversionResult result;
  final List<PlanYearCheck> years;
  final List<PlanEntryMismatch> mismatches;

  const PlanConversionReport({
    required this.result,
    required this.years,
    required this.mismatches,
  });

  static const _currency = CurrencyService();

  static PlanConversionReport build({
    required Map<String, List<BudgetEntry>> entriesByBudget,
    required PlanConversionResult result,
    required DateTime today,
    required Currency target,
  }) {
    final window = PlanConversion.windowFor(today);
    final byId = {for (final p in result.positions) '${p.budgetId}|${p.id}': p};
    final years = <PlanYearCheck>[];
    final mismatches = <PlanEntryMismatch>[];

    for (final MapEntry(key: budgetId, value: entries)
        in entriesByBudget.entries) {
      for (var y = window.first; y <= window.last; y++) {
        var oldIncome = 0.0,
            newIncome = 0.0,
            oldExpense = 0.0,
            newExpense = 0.0;
        for (final e in entries) {
          final p = byId['$budgetId|${e.id}'];
          if (p == null || !e.isActive) continue;
          final oldTotal = _oldYearTotal(e, y);
          final newTotal = p.yearTotal(y);
          final oldT = _currency.convert(oldTotal, e.currency, target);
          final newT = _currency.convert(newTotal, p.currency, target);
          if (p.isIncome) {
            oldIncome += oldT;
            newIncome += newT;
          } else {
            oldExpense += oldT;
            newExpense += newT;
          }
          if ((oldTotal - newTotal).abs() >= 0.005) {
            mismatches.add(
              PlanEntryMismatch(
                budgetId: budgetId,
                name: e.name,
                year: y,
                oldTotal: oldTotal,
                newTotal: newTotal,
                currency: e.currency,
                detail: _describe(e),
              ),
            );
          }
        }
        years.add(
          PlanYearCheck(
            budgetId: budgetId,
            year: y,
            oldIncome: oldIncome,
            newIncome: newIncome,
            oldExpense: oldExpense,
            newExpense: newExpense,
          ),
        );
      }
    }
    return PlanConversionReport(
      result: result,
      years: years,
      mismatches: mismatches,
    );
  }

  /// Suma roku w starym modelu — wzór dawnych kosztów cyklicznych miesiąca
  /// (`recurringExpensesForMonth`), zastosowany do jednej pozycji.
  static double _oldYearTotal(BudgetEntry e, int year) {
    if (e.type == BudgetEntryType.oneTimeIncome) {
      final key =
          e.month ??
          (e.startDate != null ? BudgetEntry.monthKeyOf(e.startDate!) : null);
      return key != null && key.startsWith('$year-') ? e.amount : 0;
    }
    var sum = 0.0;
    for (var m = 1; m <= 12; m++) {
      final key = planMonthKey(year, m);
      if (!_existsInMonth(e, key)) continue;
      sum += e.monthlyAmount;
      final ov = e.overrideForMonth(key)?.amount;
      if (ov != null) sum += ov - e.amount;
    }
    return sum;
  }

  static bool _existsInMonth(BudgetEntry e, String key) {
    if (e.isInstallment) return e.isInstallmentActiveInMonth(key);
    final s = e.startDate;
    return s == null || BudgetEntry.monthKeyOf(s).compareTo(key) <= 0;
  }

  static String _describe(BudgetEntry e) {
    final parts = <String>[
      switch (e.cycle) {
        BillingCycle.weekly => 'tygodniowy',
        BillingCycle.monthly => 'miesięczny',
        BillingCycle.quarterly => 'kwartalny',
        BillingCycle.yearly => 'roczny',
        BillingCycle.monthsOfYear => 'wybrane miesiące',
        BillingCycle.custom => 'co ${e.customCycleDays ?? 30} dni',
      },
      if (e.isInstallment) 'rata',
      e.startDate != null
          ? 'start ${BudgetEntry.monthKeyOf(e.startDate!)}'
          : 'bez daty startu',
      if ((e.monthOverrides?.length ?? 0) > 0)
        'korekt: ${e.monthOverrides!.length}',
    ];
    return parts.join(' · ');
  }
}

// ── Zapis do bazy ───────────────────────────────────────────────────────────

/// Uruchamia konwersję na danych z bazy i zapisuje plan.
///
/// Stare pozycje zostają NIETKNIĘTE: powrót do poprzedniej wersji aplikacji
/// (zbudowanej z wyższym numerem) widzi swoje dane takie, jakie były przed
/// konwersją.
class PlanConversionRunner {
  final StorageService _storage;

  PlanConversionRunner(this._storage);

  Map<String, List<BudgetEntry>> _oldEntries() => {
    for (final scope in BudgetScope.values)
      scope.name: _storage.getBudgetEntries(scope),
  };

  /// Konwersja przy starcie — tylko gdy plan nie powstał jeszcze z bieżącej
  /// wersji reguł. Zwraca `null`, gdy nie było nic do zrobienia.
  Future<PlanConversionResult?> ensureConverted(DateTime today) async {
    if (_storage.getPlanConversionVersion() >= PlanConversion.version) {
      return null;
    }
    return reconvert(today);
  }

  /// Konwersja od nowa z obecnych starych danych — NADPISUJE plan.
  Future<PlanConversionResult> reconvert(DateTime today) async {
    final result = PlanConversion.convert(
      entriesByBudget: _oldEntries(),
      today: today,
    );
    await _storage.replacePlanPositions(result.positions);
    await _storage.setPlanConversionVersion(PlanConversion.version);
    return result;
  }

  /// Raport z konwersji wyliczonej na świeżo z obecnych starych danych.
  PlanConversionReport report(DateTime today) {
    final old = _oldEntries();
    return PlanConversionReport.build(
      entriesByBudget: old,
      result: PlanConversion.convert(entriesByBudget: old, today: today),
      today: today,
      target: Currency.values.firstWhere(
        (c) =>
            c.name == _storage.getCurrency() ||
            c.label == _storage.getCurrency(),
        orElse: () => Currency.PLN,
      ),
    );
  }
}
