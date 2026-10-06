// budget_service.dart — Agregacja budżetu domowego.
//
// Warstwa łącząca dwa strumienie kosztów: pozycje budżetu ([BudgetEntry])
// oraz subskrypcje ([Subscription], liczone przez [AnalyticsService]).
// Model czasu: hybryda — rdzeń uśredniony (kwoty/mies) + wydatki jednorazowe
// przypięte do konkretnego miesiąca.

import '../models/spending_allocation_item.dart';
import '../models/budget_entry.dart';
import '../models/subscription.dart';
import '../utils/cycle_math.dart';
import 'analytics_service.dart';
import 'currency_service.dart';

DateTime get _now => Subscription.devDateOverride ?? DateTime.now();

/// Pojedyncze zdarzenie pieniezne danego dnia (kwota w walucie docelowej).
class CalendarItem {
  final String name;
  final double amount;
  final bool isIncome;

  /// Skad pozycja pochodzi — do grupowania „po typie glownym" na Dashboardzie.
  final CalendarItemKind kind;

  /// Czy platnosc jest automatyczna (wg metody platnosci). Wydatek auto = zolty,
  /// manual = czerwony na kalendarzu; manualne trafiaja na liste „Platnosci".
  final bool isAutomatic;

  /// Id zrodla (BudgetEntry lub Subscription) — do trwalego stanu „wykonane".
  final String? sourceId;

  /// Rodzaj pozycji budzetu, z ktorej powstal ten przeplyw. Sluzy WYLACZNIE
  /// do ikony (ADR-032): [kind] grupuje zgrubnie, a lista musi pokazac te sama
  /// ikone co zakladka, na ktorej pozycja mieszka. `null` dla subskrypcji.
  final BudgetEntryType? entryType;

  const CalendarItem({
    required this.name,
    required this.amount,
    required this.isIncome,
    this.kind = CalendarItemKind.budgetEntry,
    this.isAutomatic = false,
    this.sourceId,
    this.entryType,
  });
}

/// Typ glowny pozycji kalendarza (grupowanie na Dashboardzie).
enum CalendarItemKind {
  /// Wydatek biezacy — datowany log wydatku (`BudgetEntryType.spending`).
  spending,

  /// Odnowienie subskrypcji.
  subscription,

  /// Pozostale pozycje budzetu: wplywy, koszty stale, raty, jednorazowe.
  budgetEntry;

  /// Etykieta grupy. „Budzet" zamiast „Cykliczne", bo w tej grupie sa takze
  /// pozycje jednorazowe (premia, wieksze zakupy) — nazwa musi je objac.
  String get label => switch (this) {
        CalendarItemKind.spending => 'Bieżące',
        CalendarItemKind.subscription => 'Subskrypcje',
        CalendarItemKind.budgetEntry => 'Budżet',
      };
}

/// Przeplywy jednego dnia kalendarza.
class DayCashflow {
  final List<CalendarItem> items;
  const DayCashflow(this.items);

  bool get hasIncome => items.any((i) => i.isIncome);
  bool get hasExpense => items.any((i) => !i.isIncome);
  bool get hasAutomaticExpense =>
      items.any((i) => !i.isIncome && i.isAutomatic);
  bool get hasManualExpense => items.any((i) => !i.isIncome && !i.isAutomatic);
  double get incomeTotal =>
      items.where((i) => i.isIncome).fold(0.0, (s, i) => s + i.amount);
  double get expenseTotal =>
      items.where((i) => !i.isIncome).fold(0.0, (s, i) => s + i.amount);
}

/// Rodzaj pozycji w rozbiciu różnicy „bilans − saldo" (ADR-008).
enum BalanceContributionKind {
  oneTimeIncome, // jednorazowy wpływ (+)
  oneTimeExpense, // jednorazowy wydatek (−)
  amountOverride, // korekta kwoty (wydatek/przelew/wpływ, ze znakiem)
  installment, // korekta raty (rata w tym miesiącu vs teraz)
  spendingAllocation, // rezerwa „Na bieżące wydatki" oddana z planu (+) — real liczy faktyczne wydatki bieżące
}

/// Bilans miesiąca rozłożony na strumienie (do sekcji „Rzeczywisty bilans
/// miesiąca"). Wszystkie kwoty w walucie docelowej, koszty jako liczby dodatnie.
class MonthBalanceParts {
  /// Wpływy cykliczne + jednorazowe tego miesiąca + korekty kwot wpływów.
  final double income;

  /// Koszty cykliczne BEZ subskrypcji, z korektami kwot i ratami tego miesiąca.
  final double recurring;

  /// Subskrypcje (kwota/mies).
  final double subscriptions;

  /// Wydatki bieżące tego miesiąca — realne kwoty, zbiorczo.
  final double spending;

  const MonthBalanceParts({
    required this.income,
    required this.recurring,
    required this.subscriptions,
    required this.spending,
  });

  double get costs => recurring + subscriptions + spending;

  double get balance => income - costs;
}

/// Pojedyncza pozycja, która sprawia, że bilans miesiąca różni się od salda.
/// `delta` jest ze znakiem, w walucie docelowej; suma delt == bilans − saldo.
class BalanceContribution {
  final String name;
  final double delta;
  final BalanceContributionKind kind;
  const BalanceContribution({
    required this.name,
    required this.delta,
    required this.kind,
  });
}

/// Ujęcie wydatków na wykresach zakładki „Plan" (ADR-028).
///
/// Te same pozycje dają dwie różne liczby i mieszanie ich w jednym widoku
/// (tak było wcześniej) daje sumę, która nie odpowiada ani planowi, ani
/// żadnemu realnemu miesiącowi.
enum ExpenseView {
  /// Jak budżet zakłada, że wygląda miesiąc: kwoty bazowe uśrednione na
  /// miesiąc, raty w oknie spłaty, a zamiast wydatków — koperta „Na bieżące wydatki".
  plan,

  /// Co faktycznie wyszło w danym miesiącu: kwoty z korektami tego miesiąca,
  /// tylko pozycje, które wtedy istniały, i realne wydatki bieżące (`billPayment`).
  ///
  /// Dla miesięcy wstecz to ODTWORZENIE, nie zapis: aplikacja nie trzyma
  /// historii zmian kwot, tylko korekty miesięczne i daty. Bieżący miesiąc
  /// liczy się dokładnie tak samo jak „Bilans miesiąca".
  actual,
}

/// Jeden miesiąc w podsumowaniu rocznym. `null` = miesiąc poza ewidencją
/// (przed jej początkiem) albo jeszcze nienadeszły — pusty, a nie zerowy.
class YearMonthExpense {
  final int month; // 1–12
  final double? amount;
  final double? cumulative;

  const YearMonthExpense({
    required this.month,
    required this.amount,
    required this.cumulative,
  });
}

/// Rok w jednym miejscu: ile wydano narastająco wobec planu na te miesiące.
class YearExpenseSummary {
  final int year;

  /// Pierwszy miesiąc objęty ewidencją (1–12).
  final int fromMonth;
  final List<YearMonthExpense> months;

  /// Suma miesięcy z danymi (narastająco na koniec roku / na dziś).
  final double spent;

  /// Plan za miesiące od [fromMonth] do grudnia.
  final double planned;

  /// Planowany koszt jednego miesiąca — do wiersza porównawczego.
  final double plannedMonthly;

  const YearExpenseSummary({
    required this.year,
    required this.fromMonth,
    required this.months,
    required this.spent,
    required this.planned,
    required this.plannedMonthly,
  });

  /// Wykonanie planu (0–…): 1.0 = dokładnie plan. `null` gdy planu brak.
  double? get progress => planned <= 0 ? null : spent / planned;
}

class BudgetService {
  static const _currency = CurrencyService();
  static const _analytics = AnalyticsService();
  const BudgetService();

  double _monthly(BudgetEntry e, Currency target) =>
      _currency.convert(e.monthlyAmount, e.currency, target);

  /// Czy pozycja cykliczna istniała w danym miesiącu (ujęcie „rzeczywistość").
  /// Brak daty startu = brak informacji — liczymy ją jak dziś, bo alternatywą
  /// byłoby ciche wyzerowanie starszych pozycji na całym wykresie.
  bool _existsInMonth(BudgetEntry e, String monthKey) {
    if (e.isInstallment) return e.isInstallmentActiveInMonth(monthKey);
    final start = e.startDate;
    if (start == null) return true;
    return BudgetEntry.monthKeyOf(start).compareTo(monthKey) <= 0;
  }

  /// Korekta kwoty na dany miesiąc (ADR-008) jako różnica wobec kwoty bazowej.
  double _overrideDelta(BudgetEntry e, String monthKey, Currency t) {
    final ov = e.overrideForMonth(monthKey);
    if (ov?.amount == null) return 0;
    return _currency.convert(ov!.amount! - e.amount, e.currency, t);
  }

  /// Realne koszty cykliczne danego miesiąca — BEZ subskrypcji i BEZ wydatków.
  /// Różni się od [monthlyBudgetExpenses] tym, że bierze korekty tego miesiąca
  /// i liczy tylko pozycje, które wtedy istniały (raty w oknie spłaty).
  double recurringExpensesForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    return entries
        .where(
          (e) =>
              e.isActive &&
              e.isExpense &&
              !e.isOneTime &&
              _existsInMonth(e, monthKey),
        )
        .fold(0.0, (sum, e) => sum + _monthly(e, t) + _overrideDelta(e, monthKey, t));
  }

  /// Suma pozycji do nagłówka sekcji listy, w walucie docelowej. Cykliczne
  /// liczone kwotą/mies, jednorazowe pełną kwotą (`monthlyAmount` mają 0,
  /// a sens tylko jako jednorazowy wydatek).
  ///
  /// [monthKey] = filtr listy stoi na jednym miesiącu. Wiersz pokazuje wtedy
  /// kwotę z korekty tego miesiąca, więc suma nad nim też ją bierze — tą samą
  /// różnicą wobec bazy co bilans miesiąca (ADR-008), żeby nagłówek zgadzał
  /// się z „Bilansem miesiąca". Plan („zostaje/mies") korekt dalej nie widzi.
  double sumAmounts(
    List<BudgetEntry> entries, {
    String? monthKey,
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    return entries.fold(0.0, (sum, e) {
      if (e.isOneTime) return sum + _currency.convert(e.amount, e.currency, t);
      final delta = monthKey == null ? 0.0 : _overrideDelta(e, monthKey, t);
      return sum + _monthly(e, t) + delta;
    });
  }

  /// Czy pozycja wchodzi do biezacych kosztow/mies. Rata liczy sie tylko gdy
  /// aktywna w biezacym miesiacu (po ostatniej racie znika z surplus) — ADR-008.
  bool _countsNow(BudgetEntry e) =>
      !e.isInstallment || e.isInstallmentActiveOn(_now);

  // ── Strumienie miesięczne (uśrednione) ──────────────────────────────────────

  /// Suma aktywnych wpływów cyklicznych (kwota/mies) w walucie docelowej.
  double monthlyIncome(List<BudgetEntry> entries, {Currency? target}) {
    final t = target ?? Currency.PLN;
    return entries
        .where((e) => e.isActive && e.isIncome && !e.isOneTime)
        .fold(0.0, (sum, e) => sum + _monthly(e, t));
  }

  /// Suma kosztów cyklicznych budżetu (wydatki bieżące + koszty cykliczne) w walucie docelowej.
  double monthlyBudgetExpenses(List<BudgetEntry> entries, {Currency? target}) {
    final t = target ?? Currency.PLN;
    return entries
        .where((e) => e.isActive && e.isExpense && !e.isOneTime && _countsNow(e))
        .fold(0.0, (sum, e) => sum + _monthly(e, t));
  }

  /// Część subskrypcyjna kosztów miesięcznych (do adnotacji „w tym subskrypcje").
  double monthlySubscriptionsExpense(
    List<Subscription> subs, {
    Currency? target,
  }) =>
      _analytics.getMonthlyTotal(subs, target: target ?? Currency.PLN);

  /// Łączne koszty cykliczne: budżet + subskrypcje (kwota/mies).
  double monthlyRecurringExpenses(
    List<BudgetEntry> entries,
    List<Subscription> subs, {
    Currency? target,
  }) =>
      monthlyBudgetExpenses(entries, target: target) +
      monthlySubscriptionsExpense(subs, target: target);

  /// „Zostaje miesięcznie" = wpływy − (koszty cykliczne + subskrypcje) − rezerwa
  /// „Na bieżące wydatki". [spendingAllocation] to koperta planu (zgadywanka na wydatki bieżące),
  /// która pomniejsza plan; w bilansie miesiąca jest oddawana i podmieniana na
  /// realne wydatki bieżące (`billPayment`) — bez podwójnego liczenia (ADR-011).
  double monthlySurplus(
    List<BudgetEntry> entries,
    List<Subscription> subs, {
    Currency? target,
    double spendingAllocation = 0,
  }) =>
      monthlyIncome(entries, target: target) -
      monthlyRecurringExpenses(entries, subs, target: target) -
      spendingAllocation;

  // ── Wydatki jednorazowe (per miesiąc) ───────────────────────────────────────

  /// Wydatki jednorazowe przypisane do danego miesiąca ("YYYY-MM").
  List<BudgetEntry> oneTimeExpensesForMonth(
    List<BudgetEntry> entries,
    String monthKey,
  ) =>
      entries
          .where((e) =>
              e.isActive && e.isOneTime && e.isExpense && e.month == monthKey)
          .toList();

  /// Wpływy jednorazowe (np. premia) przypisane do danego miesiąca ("YYYY-MM").
  List<BudgetEntry> oneTimeIncomesForMonth(
    List<BudgetEntry> entries,
    String monthKey,
  ) =>
      entries
          .where((e) =>
              e.isActive && e.isOneTime && e.isIncome && e.month == monthKey)
          .toList();

  double _sumAmount(List<BudgetEntry> list, Currency t) => list.fold(
        0.0,
        (sum, e) => sum + _currency.convert(e.amount, e.currency, t),
      );

  /// Suma wydatków jednorazowych w danym miesiącu (w walucie docelowej).
  double oneTimeTotalForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) =>
      _sumAmount(
          oneTimeExpensesForMonth(entries, monthKey), target ?? Currency.PLN);

  /// Suma wpływów jednorazowych w danym miesiącu (w walucie docelowej).
  double oneTimeIncomeTotalForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) =>
      _sumAmount(
          oneTimeIncomesForMonth(entries, monthKey), target ?? Currency.PLN);

  // ── Bieżące: realny log ([BudgetEntryType.spending]) ────────────────────

  /// Bieżące (realny log opłaconych, trudnych do zaplanowania pozycji)
  /// przypisane do danego miesiąca ("YYYY-MM"). Datowane wydatki — zasilają
  /// bilans miesiąca (jak jednorazowe), NIE plan („zostaje/mies").
  List<BudgetEntry> spendingForMonth(
    List<BudgetEntry> entries,
    String monthKey,
  ) =>
      entries
          .where((e) =>
              e.isActive &&
              e.type == BudgetEntryType.spending &&
              e.month == monthKey)
          .toList();

  /// Suma realnych wydatków danego miesiąca (waluta docelowa) — „rzeczywiste"
  /// w porównaniu z kopertą „Na bieżące wydatki" (plan).
  double spendingActualForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) =>
      _sumAmount(
          spendingForMonth(entries, monthKey), target ?? Currency.PLN);

  // ── Statystyki: trendy i podział na kategorie (do wykresów w Planie) ────────

  /// Trend miesięcznych wydatków (ostatnie [months] mies.): koszty cykliczne +
  /// subskrypcje (bieżące) + jednorazowe i wydatki bieżące danego miesiąca.
  List<MonthlyDataPoint> expenseTrend(
    List<BudgetEntry> entries,
    List<Subscription> subs, {
    int months = 6,
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final base = monthlyBudgetExpenses(entries, target: t) +
        monthlySubscriptionsExpense(subs, target: t);
    final now = _now;
    return [
      for (var i = months - 1; i >= 0; i--)
        () {
          final m = DateTime(now.year, now.month - i, 1);
          return MonthlyDataPoint(
            month: m,
            amount: base +
                oneTimeTotalForMonth(entries, BudgetEntry.monthKeyOf(m),
                    target: t),
          );
        }()
    ];
  }

  /// Trend samych kosztów cyklicznych budżetu (koszty stałe, raty) — BEZ
  /// subskrypcji i BEZ wydatków. Razem z [subscriptionsTrend] i [spendingTrend]
  /// daje rozłączny podział całości wydatków (po ADR-018 „jednorazowy wydatek"
  /// to dokładnie `billPayment`, więc trzy serie niczego nie gubią i niczego
  /// nie liczą dwa razy).
  ///
  /// W ujęciu [ExpenseView.plan] linia jest płaska: plan nie zmienia się
  /// z miesiąca na miesiąc, a historii zmian kosztów stałych nie ma w danych.
  /// W [ExpenseView.actual] każdy miesiąc liczy się osobno — z korektami kwot
  /// i bez pozycji, które wtedy jeszcze nie istniały.
  List<MonthlyDataPoint> recurringExpenseTrend(
    List<BudgetEntry> entries, {
    required ExpenseView view,
    int months = 6,
    String? fromMonth,
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final base = monthlyBudgetExpenses(entries, target: t);
    return _months(months, fromMonthKey: fromMonth).map((m) {
      return MonthlyDataPoint(
        month: m,
        amount: view == ExpenseView.plan
            ? base
            : recurringExpensesForMonth(
                entries,
                BudgetEntry.monthKeyOf(m),
                target: t,
              ),
      );
    }).toList();
  }

  /// Trend kosztu subskrypcji per miesiąc: w planie dzisiejsza kwota/mies
  /// rzutowana na cały wykres, w rzeczywistości — liczona z dat startu
  /// i anulowania każdej subskrypcji.
  List<MonthlyDataPoint> subscriptionsTrend(
    List<Subscription> subs, {
    required ExpenseView view,
    int months = 6,
    String? fromMonth,
    Currency? target,
  }) {
    final base = monthlySubscriptionsExpense(subs, target: target);
    return _months(months, fromMonthKey: fromMonth)
        .map(
          (m) => MonthlyDataPoint(
            month: m,
            amount: view == ExpenseView.actual
                ? _analytics.getMonthlyTotalForMonth(subs, m, target: target)
                : base,
          ),
        )
        .toList();
  }

  /// Trend wydatków: w planie płaska koperta „Na bieżące wydatki" ([spendingAllocation]),
  /// w rzeczywistości realne `billPayment` każdego miesiąca. To jest ta sama
  /// para plan/realny, którą porównuje karta miesiąca w „Bieżących".
  List<MonthlyDataPoint> spendingTrend(
    List<BudgetEntry> entries, {
    required ExpenseView view,
    double spendingAllocation = 0,
    int months = 6,
    String? fromMonth,
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    return _months(months, fromMonthKey: fromMonth).map((m) {
      return MonthlyDataPoint(
        month: m,
        amount: view == ExpenseView.plan
            ? spendingAllocation
            : spendingActualForMonth(entries, BudgetEntry.monthKeyOf(m), target: t),
      );
    }).toList();
  }

  /// Ostatnie [months] miesięcy, od najstarszego — wspólna oś wszystkich serii.
  ///
  /// [fromMonthKey] („YYYY-MM") ucina miesiące sprzed początku ewidencji: dane
  /// wstecz są ODTWARZANE z dzisiejszych kwot (ADR-028), więc przed startem
  /// byłyby po prostu zmyślone. Krótszy wykres mówi prawdę, dłuższy ściemnia.
  List<DateTime> _months(int months, {String? fromMonthKey}) {
    final end = _now;
    final all = [
      for (var i = months - 1; i >= 0; i--)
        DateTime(end.year, end.month - i, 1),
    ];
    if (fromMonthKey == null) return all;
    final kept = all
        .where((m) => BudgetEntry.monthKeyOf(m).compareTo(fromMonthKey) >= 0)
        .toList();
    // Ewidencja zaczyna się po całej osi (np. start w przyszłym miesiącu) —
    // zostawiamy bieżący miesiąc, bo wykres bez punktów nic nie niesie.
    return kept.isEmpty ? [all.last] : kept;
  }

  // ── Podsumowanie roczne (ADR-029) ──────────────────────────────────────────

  /// Realne wydatki JEDNEGO miesiąca: koszty cykliczne z korektami tego miesiąca
  /// + subskrypcje wtedy aktywne + wydatki bieżące tego miesiąca. Ta sama definicja co
  /// ujęcie „Realne" na wykresach (ADR-028) i co bilans miesiąca.
  double actualExpensesForMonth(
    List<BudgetEntry> entries,
    List<Subscription> subs,
    DateTime month, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final key = BudgetEntry.monthKeyOf(month);
    return recurringExpensesForMonth(entries, key, target: t) +
        _analytics.getMonthlyTotalForMonth(subs, month, target: t) +
        spendingActualForMonth(entries, key, target: t);
  }

  /// Planowany koszt miesięczny: koszty cykliczne + subskrypcje + koperta
  /// „Na bieżące wydatki" — dokładnie to, co pomniejsza „zostaje miesięcznie".
  double plannedMonthlyExpenses(
    List<BudgetEntry> entries,
    List<Subscription> subs, {
    double spendingAllocation = 0,
    Currency? target,
  }) =>
      monthlyRecurringExpenses(entries, subs, target: target) + spendingAllocation;

  /// Podsumowanie roku: ile z planu rocznego już wydano, miesiąc po miesiącu.
  ///
  /// [fromMonth] (1–12) to początek ewidencji w tym roku — miesiące przed nim
  /// są puste i NIE wchodzą do planu, z którym się porównujemy. Bez tego rok
  /// rozpoczęty w lipcu wyglądałby na wykonany w połowie tylko dlatego, że
  /// przez pół roku nie było czego zapisywać.
  ///
  /// Miesiące przyszłe zostają puste w ujęciu [ExpenseView.actual] (nic tam
  /// jeszcze nie wydano) i wypełnione planem w [ExpenseView.plan].
  YearExpenseSummary yearExpenseSummary(
    List<BudgetEntry> entries,
    List<Subscription> subs,
    int year, {
    required ExpenseView view,
    int fromMonth = 1,
    double spendingAllocation = 0,
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final now = _now;
    final planned = plannedMonthlyExpenses(
      entries,
      subs,
      spendingAllocation: spendingAllocation,
      target: t,
    );
    // 13 = ewidencja zaczyna się dopiero w kolejnym roku, więc ten rok jest
    // pusty po obu stronach (i plan, i wykonanie).
    final from = fromMonth.clamp(1, 13);

    final months = <YearMonthExpense>[];
    var running = 0.0;
    for (var m = 1; m <= 12; m++) {
      final month = DateTime(year, m, 1);
      final isFuture =
          year > now.year || (year == now.year && m > now.month);
      double? amount;
      if (m < from) {
        amount = null; // przed początkiem ewidencji
      } else if (view == ExpenseView.plan) {
        amount = planned;
      } else {
        amount = isFuture ? null : actualExpensesForMonth(entries, subs, month, target: t);
      }
      if (amount != null) running += amount;
      months.add(
        YearMonthExpense(
          month: m,
          amount: amount,
          cumulative: amount == null ? null : running,
        ),
      );
    }

    return YearExpenseSummary(
      year: year,
      fromMonth: from,
      months: months,
      spent: running,
      // Plan liczymy tylko za miesiące objęte ewidencją — porównujemy jabłka
      // z jabłkami.
      planned: planned * (from > 12 ? 0 : 12 - from + 1),
      plannedMonthly: planned,
    );
  }

  /// Ile brakuje, by [total] było wielokrotnością [step] (zaokrąglenie W GÓRĘ).
  /// `0` = suma już jest okrągła. Liczone w groszach, bo `1296.56` w arytmetyce
  /// zmiennoprzecinkowej potrafi dać `3.4399999999999`.
  double roundUpGap(double total, int step) {
    if (step <= 0) return 0;
    final cents = (total * 100).round();
    final stepCents = step * 100;
    if (cents <= 0) return 0;
    final rem = cents % stepCents;
    return rem == 0 ? 0 : (stepCents - rem) / 100;
  }

  /// Podział CAŁYCH miesięcznych wydatków wg kategorii: koszty cykliczne
  /// budżetu + subskrypcje + trzeci strumień zależny od [view]. Trzy źródła są
  /// rozłączne, więc to zwykła suma per kategoria.
  ///
  /// [ExpenseView.plan]: koszty bazowe uśrednione na miesiąc, a zamiast
  /// wydatków — pozycje koperty „Na bieżące wydatki" ([allocationItems], rozbite po
  /// swoich kategoriach). Tak liczy plan „zostaje miesięcznie".
  ///
  /// [ExpenseView.actual]: koszty tego miesiąca (z korektami, bez pozycji,
  /// które wtedy nie istniały) + realne wydatki bieżące miesiąca. Tak liczy bilans
  /// miesiąca.
  ///
  /// Pozycje bez kategorii z obu światów (`budget_other` z budżetu,
  /// `cat_other` z subskrypcji) lądują pod jednym kluczem — inaczej wykres
  /// pokazywałby dwa kawałki „Inne".
  Map<String, double> combinedExpenseBreakdownByCategory(
    List<BudgetEntry> entries,
    List<Subscription> subs,
    String monthKey, {
    required ExpenseView view,
    List<SpendingAllocationItem> allocationItems = const [],
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final out = <String, double>{};
    void addAll(Map<String, double> src) {
      for (final e in src.entries) {
        final key = e.key == 'budget_other' ? 'cat_other' : e.key;
        out[key] = (out[key] ?? 0) + e.value;
      }
    }

    addAll(
      view == ExpenseView.plan
          ? expenseBreakdownByCategory(entries, target: t)
          : recurringBreakdownForMonth(entries, monthKey, target: t),
    );
    addAll(_analytics.getCategoryBreakdown(subs, target: t));
    addAll(
      view == ExpenseView.plan
          ? allocationBreakdownByCategory(allocationItems)
          : spendingBreakdownByCategory(entries, monthKey, target: t),
    );
    return out;
  }

  /// Podział realnych kosztów cyklicznych DANEGO miesiąca wg kategorii —
  /// odpowiednik [expenseBreakdownByCategory] w ujęciu „rzeczywistość".
  Map<String, double> recurringBreakdownForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final out = <String, double>{};
    for (final e in entries.where(
      (e) =>
          e.isActive &&
          e.isExpense &&
          !e.isOneTime &&
          _existsInMonth(e, monthKey),
    )) {
      final key = e.categoryId ?? 'budget_other';
      out[key] =
          (out[key] ?? 0) + _monthly(e, t) + _overrideDelta(e, monthKey, t);
    }
    return out;
  }

  /// Podział koperty „Na bieżące wydatki" wg kategorii jej pozycji (ujęcie planu).
  /// Kwoty koperty są już w walucie docelowej — to zwykła suma z ustawień.
  Map<String, double> allocationBreakdownByCategory(
    List<SpendingAllocationItem> items,
  ) {
    final out = <String, double>{};
    for (final it in items.where((it) => !it.deleted)) {
      final key = it.categoryId ?? 'budget_other';
      out[key] = (out[key] ?? 0) + it.amount;
    }
    return out;
  }

  /// Podział realnych wydatków danego miesiąca wg kategorii (wykres kołowy).
  Map<String, double> spendingBreakdownByCategory(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final out = <String, double>{};
    for (final e in spendingForMonth(entries, monthKey)) {
      final key = e.categoryId ?? 'budget_other';
      out[key] = (out[key] ?? 0) + _currency.convert(e.amount, e.currency, t);
    }
    return out;
  }

  /// Wpływ korekt kwoty na bilans miesiąca, ze znakiem (ADR-008). Dla każdej
  /// aktywnej pozycji z nadpisaną kwotą w tym miesiącu: wpływ `+ (korekta−baza)`,
  /// wydatek `− (korekta−baza)`. Dotyczy wydatku, przelewu do domowego oraz
  /// lustrzanego wpływu w domowym. Korekta samej daty nie wpływa na bilans.
  double overrideDeltaForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    double delta = 0;
    for (final e in entries.where((e) => e.isActive && e.monthOverrides != null)) {
      final ov = e.overrideForMonth(monthKey);
      if (ov?.amount != null) {
        final d = _currency.convert(ov!.amount! - e.amount, e.currency, t);
        delta += e.isIncome ? d : -d;
      }
    }
    return delta;
  }

  /// Korekta bilansu z tytułu rat: surplus liczy raty aktywne *teraz*, a dla
  /// wskazanego miesiąca liczą się raty aktywne *w tym miesiącu*. Zwraca
  /// `(rata w miesiącu) − (rata teraz)` — dodatnia = w tym miesiącu drożej niż
  /// w bieżącym, więc bilans niższy (odejmowana, jak delta wydatku).
  double installmentDeltaForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final now = _now;
    double delta = 0;
    for (final e in entries.where((e) => e.isActive && e.isInstallment)) {
      final amt = _monthly(e, t);
      final inMonth = e.isInstallmentActiveInMonth(monthKey) ? amt : 0.0;
      final inNow = e.isInstallmentActiveOn(now) ? amt : 0.0;
      delta += inMonth - inNow;
    }
    return delta;
  }

  /// Bilans wskazanego miesiąca: surplus + jednorazowe wpływy − jednorazowe wydatki
  /// + korekty kwot (wydatek/przelew/wpływ, ze znakiem) − korekta rat tego miesiąca.
  /// Surplus pozostaje „planem"; różnicę realnego miesiąca pokazuje bilans (ADR-008).
  double balanceForMonth(
    List<BudgetEntry> entries,
    List<Subscription> subs,
    String monthKey, {
    Currency? target,
    double spendingAllocation = 0,
  }) =>
      // Rezerwa „Na bieżące wydatki" jest oddawana (+spendingAllocation) — plan ją rezerwuje,
      // ale realny miesiąc liczy faktyczne wydatki bieżące (w oneTimeTotalForMonth).
      monthlySurplus(entries, subs,
              target: target, spendingAllocation: spendingAllocation) +
      spendingAllocation +
      oneTimeIncomeTotalForMonth(entries, monthKey, target: target) -
      oneTimeTotalForMonth(entries, monthKey, target: target) +
      overrideDeltaForMonth(entries, monthKey, target: target) -
      installmentDeltaForMonth(entries, monthKey, target: target);

  /// Bilans miesiąca rozbity na cztery strumienie — tyle, ile potrzeba, by
  /// odpowiedzieć „skąd się wziął ten bilans", bez wyliczania pojedynczych
  /// pozycji. Zawsze zachodzi: `income − recurring − subscriptions − spending`
  /// = [balanceForMonth] dla tego samego miesiąca (jest na to test).
  MonthBalanceParts monthBalanceParts(
    List<BudgetEntry> entries,
    List<Subscription> subs,
    String monthKey, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;

    // Korekty kwot (ADR-008) trafiają do tego strumienia, którego dotyczą —
    // inaczej „koszty cykliczne" pokazywałyby plan, a nie realny miesiąc.
    double incomeOverride = 0;
    double recurringOverride = 0;
    double spendingOverride = 0;
    for (final e in entries.where(
      (e) => e.isActive && e.monthOverrides != null,
    )) {
      final ov = e.overrideForMonth(monthKey);
      if (ov?.amount == null) continue;
      final d = _currency.convert(ov!.amount! - e.amount, e.currency, t);
      if (e.isIncome) {
        incomeOverride += d;
      } else if (e.type == BudgetEntryType.spending) {
        spendingOverride += d;
      } else {
        recurringOverride += d;
      }
    }

    final income = monthlyIncome(entries, target: t) +
        oneTimeIncomeTotalForMonth(entries, monthKey, target: t) +
        incomeOverride;
    // Raty: surplus liczy stan „teraz", ten miesiąc może mieć inny (delta).
    final recurring = monthlyBudgetExpenses(entries, target: t) +
        recurringOverride +
        installmentDeltaForMonth(entries, monthKey, target: t);
    final subscriptions = monthlySubscriptionsExpense(subs, target: t);
    final spending =
        oneTimeTotalForMonth(entries, monthKey, target: t) + spendingOverride;

    return MonthBalanceParts(
      income: income,
      recurring: recurring,
      subscriptions: subscriptions,
      spending: spending,
    );
  }

  /// Rozbicie różnicy „bilans − saldo" danego miesiąca na pojedyncze pozycje
  /// (ADR-008). Suma `delta` zwróconych pozycji jest równa
  /// `balanceForMonth − monthlySurplus`. Kolejność: jednorazowe wpływy,
  /// jednorazowe wydatki, korekty kwot, korekty rat.
  List<BalanceContribution> balanceBreakdownForMonth(
    List<BudgetEntry> entries,
    String monthKey, {
    Currency? target,
    double spendingAllocation = 0,
  }) {
    final t = target ?? Currency.PLN;
    final out = <BalanceContribution>[];

    // Rezerwa „Na bieżące wydatki" oddana z planu (+): plan ją rezerwował, real liczy
    // faktyczne wydatki bieżące (poniżej jako jednorazowe wydatki). Utrzymuje inwariant
    // suma delt == bilans − surplus (ADR-008/011).
    if (spendingAllocation != 0) {
      out.add(BalanceContribution(
        name: 'Na bieżące wydatki (rezerwa planu)',
        delta: spendingAllocation,
        kind: BalanceContributionKind.spendingAllocation,
      ));
    }

    for (final e in oneTimeIncomesForMonth(entries, monthKey)) {
      out.add(BalanceContribution(
        name: e.name,
        delta: _currency.convert(e.amount, e.currency, t),
        kind: BalanceContributionKind.oneTimeIncome,
      ));
    }
    for (final e in oneTimeExpensesForMonth(entries, monthKey)) {
      out.add(BalanceContribution(
        name: e.name,
        delta: -_currency.convert(e.amount, e.currency, t),
        kind: BalanceContributionKind.oneTimeExpense,
      ));
    }
    for (final e
        in entries.where((e) => e.isActive && e.monthOverrides != null)) {
      final ov = e.overrideForMonth(monthKey);
      if (ov?.amount != null) {
        final d = _currency.convert(ov!.amount! - e.amount, e.currency, t);
        out.add(BalanceContribution(
          name: e.name,
          delta: e.isIncome ? d : -d,
          kind: BalanceContributionKind.amountOverride,
        ));
      }
    }
    final now = _now;
    for (final e in entries.where((e) => e.isActive && e.isInstallment)) {
      final amt = _monthly(e, t);
      final inMonth = e.isInstallmentActiveInMonth(monthKey) ? amt : 0.0;
      final inNow = e.isInstallmentActiveOn(now) ? amt : 0.0;
      final raw = inMonth - inNow;
      if (raw != 0) {
        // Bilans odejmuje installmentDelta → wkład pozycji = −(inMonth − inNow).
        out.add(BalanceContribution(
          name: e.name,
          delta: -raw,
          kind: BalanceContributionKind.installment,
        ));
      }
    }
    return out;
  }

  /// Nadchodzące wydatki jednorazowe (miesiąc ≥ bieżący), posortowane rosnąco.
  List<BudgetEntry> upcomingOneTime(
    List<BudgetEntry> entries, {
    String? fromMonth,
  }) {
    final from = fromMonth ?? BudgetEntry.monthKeyOf(_now);
    final list = entries
        .where((e) =>
            e.isActive && e.isOneTime && (e.month ?? '').compareTo(from) >= 0)
        .toList();
    list.sort((a, b) => (a.month ?? '').compareTo(b.month ?? ''));
    return list;
  }

  // ── Breakdown ────────────────────────────────────────────────────────────────

  /// Podział kosztów cyklicznych budżetu wg kategorii (kwota/mies).
  Map<String, double> expenseBreakdownByCategory(
    List<BudgetEntry> entries, {
    Currency? target,
  }) {
    final t = target ?? Currency.PLN;
    final breakdown = <String, double>{};
    for (final e in entries.where(
        (e) => e.isActive && e.isExpense && !e.isOneTime && _countsNow(e))) {
      final key = e.categoryId ?? 'budget_other';
      breakdown[key] = (breakdown[key] ?? 0) + _monthly(e, t);
    }
    return breakdown;
  }

  // ── Kalendarz przeplywow (per dzien miesiaca) ────────────────────────────────

  /// Mapuje wplywy i wydatki na dni wskazanego miesiaca.
  /// Klucz = dzien miesiaca (1..31), wartosc = przeplywy tego dnia.
  ///
  /// Zrodla: pozycje budzetu (cykliczne rzutowane wg `startDate`+cyklu;
  /// jednorazowe wg `startDate`, z fallbackiem na 1. dzien przy starych danych
  /// majacych tylko `month`) oraz odnowienia subskrypcji (`startDate`+cykl).
  /// Kwoty w walucie docelowej.
  Map<int, DayCashflow> calendarForMonth(
    List<BudgetEntry> entries,
    List<Subscription> subs,
    DateTime monthStart, {
    Currency? target,
    Map<String, bool>? autoByPayment,
  }) {
    final t = target ?? Currency.PLN;
    final mStart = DateTime(monthStart.year, monthStart.month, 1);
    final mEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final byDay = <int, List<CalendarItem>>{};
    void add(int day, CalendarItem it) => (byDay[day] ??= []).add(it);
    // Tryb auto wg metody platnosci (po nazwie); brak metody = manualny.
    bool autoOf(String? pm) => pm != null && (autoByPayment?[pm] ?? false);

    for (final e in entries.where((e) => e.isActive)) {
      // Wydatek (realny log oplaty) ma wlasna grupe w widoku Dashboardu.
      final kind = e.type == BudgetEntryType.spending
          ? CalendarItemKind.spending
          : CalendarItemKind.budgetEntry;
      if (e.isOneTime) {
        final d = e.startDate ?? _monthFallbackDate(e.month);
        if (d == null) continue;
        if (!d.isBefore(mStart) && !d.isAfter(mEnd)) {
          add(
            d.day,
            CalendarItem(
              name: e.name,
              amount: _currency.convert(e.amount, e.currency, t),
              isIncome: e.isIncome,
              kind: kind,
              isAutomatic: !e.isIncome && autoOf(e.paymentMethod),
              sourceId: e.id,
              entryType: e.type,
            ),
          );
        }
      } else {
        final anchor = e.startDate;
        // Rata: tylko w oknie spłaty [start … ostatnia rata].
        if (e.isInstallment &&
            !e.isInstallmentActiveInMonth(BudgetEntry.monthKeyOf(mStart))) {
          continue;
        }
        // Korekta miesiąca (wydatek / przelew / lustro wpływu) — ADR-008:
        // data korekty zastępuje projekcję, kwota korekty zastępuje bazę.
        if (e.monthOverrides != null) {
          final ov = e.overrideForMonth(BudgetEntry.monthKeyOf(mStart));
          if (ov != null && !ov.isEmpty) {
            final amt =
                _currency.convert(ov.amount ?? e.amount, e.currency, t);
            final od = ov.date;
            final auto = !e.isIncome && autoOf(e.paymentMethod);
            if (od != null && !od.isBefore(mStart) && !od.isAfter(mEnd)) {
              // Korekta z datą: pojedyncze wystąpienie tego dnia.
              add(
                  od.day,
                  CalendarItem(
                      name: e.name,
                      amount: amt,
                      isIncome: e.isIncome,
                      kind: kind,
                      isAutomatic: auto,
                      sourceId: e.id, entryType: e.type));
              continue;
            }
            if (anchor != null) {
              // Korekta tylko kwoty: projekcja wg cyklu, ale z kwotą korekty.
              for (final d in occurrencesInRange(
                  anchor, e.cycle, e.customCycleDays, mStart, mEnd,
                  cycleMonths: e.cycleMonths)) {
                add(
                    d.day,
                    CalendarItem(
                        name: e.name,
                        amount: amt,
                        isIncome: e.isIncome,
                        kind: kind,
                        isAutomatic: auto,
                        sourceId: e.id, entryType: e.type));
              }
              continue;
            }
          }
        }
        if (anchor == null) continue;
        for (final d in occurrencesInRange(
            anchor, e.cycle, e.customCycleDays, mStart, mEnd,
            cycleMonths: e.cycleMonths)) {
          add(
            d.day,
            CalendarItem(
              name: e.name,
              amount: _currency.convert(e.amount, e.currency, t),
              isIncome: e.isIncome,
              kind: kind,
              isAutomatic: !e.isIncome && autoOf(e.paymentMethod),
              sourceId: e.id,
              entryType: e.type,
            ),
          );
        }
      }
    }

    for (final s in subs.where((s) => s.isActive)) {
      for (final d in occurrencesInRange(
          s.startDate, s.billingCycle, s.customCycleDays, mStart, mEnd,
          cycleMonths: s.cycleMonths)) {
        add(
          d.day,
          CalendarItem(
            name: s.name,
            amount: _currency.convert(s.amount, s.currency, t),
            isIncome: false,
            kind: CalendarItemKind.subscription,
            isAutomatic: autoOf(s.paymentMethod),
            sourceId: s.id,
          ),
        );
      }
    }

    return {
      for (final entry in byDay.entries) entry.key: DayCashflow(entry.value)
    };
  }

  DateTime? _monthFallbackDate(String? monthKey) {
    if (monthKey == null) return null;
    final parts = monthKey.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null) return null;
    return DateTime(y, m, 1);
  }
}
