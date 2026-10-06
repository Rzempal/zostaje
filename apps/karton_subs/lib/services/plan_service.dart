// plan_service.dart — obliczenia planu rocznego (ADR-035): kwoty okresu,
// sumy miesiąca, statystyki roku, kalendarz płatności, plan na kolejny rok.
//
// Czyste funkcje bez bazy — reguły da się sprawdzić testami, a kontroler
// ([PlanController]) tylko podaje im dane aktywnego budżetu.

import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../utils/cycle_math.dart';
import 'budget_service.dart' show CalendarItem, CalendarItemKind, DayCashflow;
import 'currency_service.dart';

/// Okres widoku planu: cały rok (średnia miesięczna) albo jeden miesiąc.
class PlanPeriod {
  final int year;

  /// 1–12; `null` = cały rok.
  final int? month;

  const PlanPeriod(this.year, [this.month]);

  bool get isYear => month == null;

  String? get monthKey => month == null ? null : planMonthKey(year, month!);

  @override
  bool operator ==(Object other) =>
      other is PlanPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Sumy jednego miesiąca planu (w walucie docelowej).
class PlanMonthTotals {
  final double income;

  /// Pozycje „wydatek" — bez koperty i subskrypcji, które mają własne pola.
  final double expense;

  /// Koperta „Na bieżące wydatki" (ADR-012) — ta sama kwota co miesiąc.
  final double envelope;
  final double subscriptions;
  final double cardLoans;
  final double cardRepayments;

  const PlanMonthTotals({
    this.income = 0,
    this.expense = 0,
    this.envelope = 0,
    this.subscriptions = 0,
    this.cardLoans = 0,
    this.cardRepayments = 0,
  });

  /// Karta netto: pożyczki − spłaty. W skali roku zwykle ~0, w miesiącu nie.
  double get cardNet => cardLoans - cardRepayments;

  /// Wszystko, co plan wydaje poza kartą.
  double get outgoing => expense + envelope + subscriptions;

  /// „Zostaje": wpływy − wydatki (z kopertą i subskrypcjami) ± karta.
  double get left => income - outgoing + cardNet;

  PlanMonthTotals operator +(PlanMonthTotals o) => PlanMonthTotals(
    income: income + o.income,
    expense: expense + o.expense,
    envelope: envelope + o.envelope,
    subscriptions: subscriptions + o.subscriptions,
    cardLoans: cardLoans + o.cardLoans,
    cardRepayments: cardRepayments + o.cardRepayments,
  );

  PlanMonthTotals scaled(double f) => PlanMonthTotals(
    income: income * f,
    expense: expense * f,
    envelope: envelope * f,
    subscriptions: subscriptions * f,
    cardLoans: cardLoans * f,
    cardRepayments: cardRepayments * f,
  );
}

/// Statystyki roku: dwanaście miesięcy i podział wydatków na kategorie.
class PlanYearStats {
  final int year;

  /// Styczeń … grudzień.
  final List<PlanMonthTotals> months;

  /// Wydatki według kategorii, średnio miesięcznie (pozycje „wydatek",
  /// subskrypcje i koperta). Klucz `null` = bez kategorii, koperta stoi pod
  /// [PlanService.envelopeCategoryKey].
  final Map<String?, double> expenseByCategory;

  const PlanYearStats({
    required this.year,
    required this.months,
    required this.expenseByCategory,
  });

  PlanMonthTotals get total =>
      months.fold(const PlanMonthTotals(), (sum, m) => sum + m);

  /// Średnia miesięczna roku — odpowiedź na „ile średnio miesięcznie".
  PlanMonthTotals get average => total.scaled(1 / 12);
}

class PlanService {
  const PlanService();

  static const _currency = CurrencyService();

  /// Klucz koperty „Na bieżące wydatki" w podziale na kategorie.
  static const envelopeCategoryKey = '__envelope__';

  // ── Subskrypcje w planie ─────────────────────────────────────────────────

  /// Płatności subskrypcji w miesiącu według jej cyklu — PEŁNA kwota
  /// obciążenia (tyle zejdzie z konta; podział na osoby liczy
  /// [subscriptionAmountInMonth]). Okres próbny nic nie kosztuje, a po
  /// anulowaniu płatności się kończą. Anulowana bez daty = brak płatności
  /// (nie wiadomo, od kiedy). W walucie subskrypcji.
  List<({DateTime date, double amount})> subscriptionPaymentsInMonth(
    Subscription s,
    int year,
    int month,
  ) {
    final cancelled = s.cancelledDate;
    if (!s.isActive && cancelled == null) return const [];
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final trialEnd = s.trialEndDate;
    final out = <({DateTime date, double amount})>[];
    for (final d in occurrencesInRange(
      s.startDate,
      s.billingCycle,
      s.customCycleDays,
      first,
      last,
      cycleMonths: s.cycleMonths,
    )) {
      if (!s.isActive &&
          cancelled != null &&
          !d.isBefore(
            DateTime(cancelled.year, cancelled.month, cancelled.day),
          )) {
        continue;
      }
      if (s.isTrial && trialEnd != null && !d.isAfter(trialEnd)) continue;
      out.add((
        date: d,
        amount: s.isTrial ? (s.postTrialAmount ?? s.amount) : s.amount,
      ));
    }
    return out;
  }

  /// Koszt subskrypcji w miesiącu po podziale na współdzielących — to liczy
  /// się do planu (twoja część), w walucie subskrypcji.
  double subscriptionAmountInMonth(Subscription s, int year, int month) {
    final total = subscriptionPaymentsInMonth(
      s,
      year,
      month,
    ).fold(0.0, (sum, p) => sum + p.amount);
    final share = s.sharedWith;
    return share != null && share > 1 ? total / share : total;
  }

  // ── Kwoty okresu ─────────────────────────────────────────────────────────

  /// Kwota pozycji w okresie (waluta docelowa): miesiąc = kwota miesiąca,
  /// rok = średnia miesięczna.
  double positionAmount(PlanPosition p, PlanPeriod period, Currency target) {
    final raw = period.isYear
        ? p.yearAverage(period.year)
        : p.amountIn(period.monthKey!);
    return _currency.convert(raw, p.currency, target);
  }

  /// Kwota subskrypcji w okresie (waluta docelowa), jak [positionAmount].
  double subscriptionAmount(
    Subscription s,
    PlanPeriod period,
    Currency target,
  ) {
    final double raw;
    if (period.isYear) {
      var sum = 0.0;
      for (var m = 1; m <= 12; m++) {
        sum += subscriptionAmountInMonth(s, period.year, m);
      }
      raw = sum / 12;
    } else {
      raw = subscriptionAmountInMonth(s, period.year, period.month!);
    }
    return _currency.convert(raw, s.currency, target);
  }

  /// Sumy miesiąca. Pozycje archiwalne się nie liczą.
  PlanMonthTotals monthTotals({
    required List<PlanPosition> positions,
    required List<Subscription> subscriptions,
    required double envelope,
    required int year,
    required int month,
    required Currency target,
  }) {
    final key = planMonthKey(year, month);
    var income = 0.0, expense = 0.0, loans = 0.0, repayments = 0.0;
    for (final p in positions) {
      if (p.archived) continue;
      final a = _currency.convert(p.amountIn(key), p.currency, target);
      switch (p.kind) {
        case PlanKind.income:
          income += a;
        case PlanKind.expense:
          expense += a;
        case PlanKind.cardLoan:
          loans += a;
        case PlanKind.cardRepayment:
          repayments += a;
      }
    }
    var subs = 0.0;
    for (final s in subscriptions) {
      subs += _currency.convert(
        subscriptionAmountInMonth(s, year, month),
        s.currency,
        target,
      );
    }
    return PlanMonthTotals(
      income: income,
      expense: expense,
      envelope: envelope,
      subscriptions: subs,
      cardLoans: loans,
      cardRepayments: repayments,
    );
  }

  /// Sumy okresu: miesiąc wprost, rok jako średnia miesięczna.
  PlanMonthTotals periodTotals({
    required List<PlanPosition> positions,
    required List<Subscription> subscriptions,
    required double envelope,
    required PlanPeriod period,
    required Currency target,
  }) => period.isYear
      ? yearStats(
          positions: positions,
          subscriptions: subscriptions,
          envelope: envelope,
          year: period.year,
          target: target,
        ).average
      : monthTotals(
          positions: positions,
          subscriptions: subscriptions,
          envelope: envelope,
          year: period.year,
          month: period.month!,
          target: target,
        );

  PlanYearStats yearStats({
    required List<PlanPosition> positions,
    required List<Subscription> subscriptions,
    required double envelope,
    required int year,
    required Currency target,
  }) {
    final months = [
      for (var m = 1; m <= 12; m++)
        monthTotals(
          positions: positions,
          subscriptions: subscriptions,
          envelope: envelope,
          year: year,
          month: m,
          target: target,
        ),
    ];
    final byCategory = <String?, double>{};
    void add(String? key, double value) {
      if (value == 0) return;
      byCategory[key] = (byCategory[key] ?? 0) + value;
    }

    for (final p in positions) {
      if (p.archived || p.kind != PlanKind.expense) continue;
      add(
        p.categoryId,
        _currency.convert(p.yearTotal(year), p.currency, target) / 12,
      );
    }
    for (final s in subscriptions) {
      var sum = 0.0;
      for (var m = 1; m <= 12; m++) {
        sum += subscriptionAmountInMonth(s, year, m);
      }
      add(s.categoryId, _currency.convert(sum, s.currency, target) / 12);
    }
    add(envelopeCategoryKey, envelope);
    return PlanYearStats(
      year: year,
      months: months,
      expenseByCategory: byCategory,
    );
  }

  // ── Kalendarz płatności ──────────────────────────────────────────────────

  /// Kalendarz miesiąca: miesiące pozycji planu (z dniem płatności),
  /// odnowienia subskrypcji i wydatki z Bieżących.
  ///
  /// Pozycja bez dnia nie ma miejsca na kalendarzu — jak dawniej pozycja bez
  /// daty. Identyfikator pozycji jest kluczem odhaczenia płatności, więc
  /// pozycje przeniesione ze starego modelu zachowują swoje odhaczenia.
  Map<int, DayCashflow> calendarForMonth({
    required List<PlanPosition> positions,
    required List<Subscription> subscriptions,
    required List<BudgetEntry> spending,
    required DateTime month,
    required Currency target,
    Map<String, bool>? autoByPayment,
  }) {
    final y = month.year;
    final m = month.month;
    final key = planMonthKey(y, m);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final byDay = <int, List<CalendarItem>>{};
    void add(int day, CalendarItem item) => (byDay[day] ??= []).add(item);
    bool autoOf(String? pm) => pm != null && (autoByPayment?[pm] ?? false);

    for (final p in positions) {
      if (p.archived) continue;
      final pm = p.months[key];
      final day = p.dayIn(key);
      if (pm == null || day == null) continue;
      add(
        day.clamp(1, daysInMonth),
        CalendarItem(
          name: p.name,
          amount: _currency.convert(pm.amount, p.currency, target),
          isIncome: p.isInflow,
          isAutomatic: !p.isInflow && autoOf(p.paymentMethod),
          sourceId: p.id,
          entryType: p.isInflow
              ? BudgetEntryType.income
              : BudgetEntryType.recurringCost,
        ),
      );
    }

    for (final s in subscriptions) {
      for (final pay in subscriptionPaymentsInMonth(s, y, m)) {
        add(
          pay.date.day,
          CalendarItem(
            name: s.name,
            amount: _currency.convert(pay.amount, s.currency, target),
            isIncome: false,
            kind: CalendarItemKind.subscription,
            isAutomatic: autoOf(s.paymentMethod),
            sourceId: s.id,
          ),
        );
      }
    }

    for (final e in spending) {
      if (e.deleted || !e.isActive || e.type != BudgetEntryType.spending) {
        continue;
      }
      final d =
          e.startDate ??
          (e.month != null ? DateTime.tryParse('${e.month}-01') : null);
      if (d == null || d.year != y || d.month != m) continue;
      add(
        d.day,
        CalendarItem(
          name: e.name,
          amount: _currency.convert(e.amount, e.currency, target),
          isIncome: false,
          kind: CalendarItemKind.spending,
          isAutomatic: autoOf(e.paymentMethod),
          sourceId: e.id,
          entryType: e.type,
        ),
      );
    }

    return {
      for (final entry in byDay.entries) entry.key: DayCashflow(entry.value),
    };
  }

  // ── Plan na kolejny rok ──────────────────────────────────────────────────

  /// Czy pozycję domyślnie przenieść z [fromYear] na kolejny rok.
  ///
  /// Nie: archiwalne, karta (para pożyczka–spłata dotyczy konkretnej
  /// operacji), pozycje mające już miesiące w kolejnym roku i pozycje, które
  /// wyglądają na zakończone — biegną z poprzedniego roku i urywają się przed
  /// grudniem bez przerwy od stycznia (typowo ostatnie raty). Pozycja roczna
  /// czy kwartalna nie biegnie od stycznia bez przerwy, więc się nie łapie.
  bool defaultCopySelected(PlanPosition p, int fromYear) {
    if (p.archived || p.isCard) return false;
    if (p.hasYear(fromYear + 1)) return false;
    final keys = p.monthsOfYear(fromYear).map((e) => e.key).toList();
    if (keys.isEmpty) return false;
    final lastMonth = int.parse(keys.last.substring(5));
    final runsFromJanuary =
        keys.first == planMonthKey(fromYear, 1) && keys.length == lastMonth;
    final endsMidYear =
        lastMonth < 12 && runsFromJanuary && p.hasYear(fromYear - 1);
    return !endsMidYear;
  }

  /// Miesiące pozycji z dopisanym rokiem [toYear] — te same miesiące, kwoty
  /// i dni co w [fromYear]. Miesiąc, który już jest w roku docelowym, zostaje.
  Map<String, PlanMonth> monthsWithYearCopied(
    PlanPosition p,
    int fromYear,
    int toYear,
  ) {
    final out = Map<String, PlanMonth>.of(p.months);
    for (final e in p.monthsOfYear(fromYear)) {
      final month = int.parse(e.key.substring(5));
      out.putIfAbsent(planMonthKey(toYear, month), () => e.value);
    }
    return out;
  }

  /// Lata do filtra: obecne w planie oraz zawsze bieżący i następny (plan na
  /// kolejny rok robi się, zanim w nim cokolwiek jest).
  List<int> yearsFor(List<PlanPosition> positions, DateTime today) {
    final years = <int>{today.year, today.year + 1};
    for (final p in positions) {
      for (final k in p.months.keys) {
        final y = int.tryParse(k.substring(0, 4));
        if (y != null) years.add(y);
      }
    }
    return years.toList()..sort();
  }

  /// Termin spłaty pożyczki z karty: dzień użycia + okres bezodsetkowy.
  /// Karta bez ustawionego okresu — 30 dni (najczęstszy rząd wielkości;
  /// datę i tak można poprawić w formularzu).
  static DateTime repaymentDateFor(DateTime use, int? graceDays) =>
      DateTime(use.year, use.month, use.day + (graceDays ?? 30));
}
