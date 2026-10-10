import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/app_logger.dart';
import '../services/loan_math.dart';
import '../models/cashflow.dart' show DayCashflow;
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import 'budget_controller.dart';

/// Stan planu rocznego aktywnego budżetu (ADR-035) — pozycje z miesiącami
/// i subskrypcje jako osobna sekcja.
///
/// Aktywny budżet i odhaczenia płatności trzyma [BudgetController] — ten
/// kontroler go słucha, więc przełączenie budżetu odświeża plan.
class PlanController extends ChangeNotifier {
  static final _log = AppLogger.get('PlanController');
  static const _uuid = Uuid();
  static const _plan = PlanService();

  final StorageService _storage;
  final BudgetController _budget;

  PlanController(this._storage, this._budget) {
    _budget.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _budget.removeListener(notifyListeners);
    super.dispose();
  }

  // ── Dane aktywnego budżetu ─────────────────────────────────────────────────

  /// Identyfikator aktywnego budżetu — na razie dawny zakres (ADR-035 §2).
  String get budgetId => _budget.budgetId;

  DateTime get today => Subscription.devDateOverride ?? DateTime.now();

  Currency get target {
    final code = _storage.getCurrency();
    return Currency.values.firstWhere(
      (c) => c.name == code || c.label == code,
      orElse: () => Currency.PLN,
    );
  }

  /// Pozycje aktywnego budżetu, łącznie z archiwalnymi.
  List<PlanPosition> get positions => _storage.getPlanPositions(budgetId);

  PlanPosition? position(String id) => _storage.getPlanPosition(id);

  List<Subscription> get subscriptions => _budget.subscriptions;

  List<int> get years => _plan.yearsFor(positions, today);

  // ── Kwoty ──────────────────────────────────────────────────────────────────

  double amountOf(PlanPosition p, PlanPeriod period) =>
      _plan.positionAmount(p, period, target);

  double subscriptionAmountOf(Subscription s, PlanPeriod period) =>
      _plan.subscriptionAmount(s, period, target);

  PlanMonthTotals totals(PlanPeriod period) => _plan.periodTotals(
    positions: positions,
    subscriptions: subscriptions,
    period: period,
    target: target,
  );

  PlanYearStats yearStats(int year) => _plan.yearStats(
    positions: positions,
    subscriptions: subscriptions,
    year: year,
    target: target,
  );

  /// Kalendarz płatności miesiąca: pozycje planu i subskrypcje.
  Map<int, DayCashflow> calendarForMonth(DateTime month) =>
      _plan.calendarForMonth(
        positions: positions,
        subscriptions: subscriptions,
        month: month,
        target: target,
        autoByPayment: {
          for (final pm in _storage.getPaymentMethods(budgetId))
            pm.name: pm.isAutomatic,
        },
      );

  // ── Pozycje ────────────────────────────────────────────────────────────────

  /// Każdy zapis pilnuje okresu: miesiąc poza nim nie trafia do planu, skąd
  /// by nie przyszedł (formularz, szybkie wypełnianie, kopiowanie roku).
  Future<void> _save(PlanPosition p) => _storage.savePlanPosition(
    p.copyWith(
      months: p.hasPeriod
          ? {
              for (final e in p.months.entries)
                if (p.inPeriod(e.key)) e.key: e.value,
            }
          : null,
      updatedAt: DateTime.now(),
    ),
  );

  Future<PlanPosition> create({
    required String name,
    required PlanKind kind,
    required Currency currency,
    required Map<String, PlanMonth> months,
    String? categoryId,
    String? paymentMethod,
    int? day,
    String? note,
    String? periodStart,
    String? periodEnd,
  }) async {
    final p = PlanPosition(
      id: _uuid.v4(),
      budgetId: budgetId,
      name: name,
      kind: kind,
      currency: currency,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      day: day,
      note: note,
      months: months,
      periodStart: periodStart,
      periodEnd: periodEnd,
      createdAt: DateTime.now(),
    );
    await _save(p);
    _log.info('Created plan position: $name (${months.length} mies.)');
    notifyListeners();
    return p;
  }

  /// Gotowe pozycje (import z arkusza) do bieżącego budżetu — jedno
  /// odświeżenie ekranów na końcu zamiast po każdej pozycji.
  Future<void> addAll(List<PlanPosition> positions) async {
    for (final p in positions) {
      await _save(p.copyWith(budgetId: budgetId));
    }
    _log.info('Imported ${positions.length} plan positions ($budgetId)');
    notifyListeners();
  }

  Future<void> update(PlanPosition p) async {
    await _save(p);
    notifyListeners();
  }

  /// Zmiany miesięcy jednej pozycji: klucz → nowy miesiąc, `null` = usuń
  /// miesiąc z planu. Miesiąc poza okresem pozycji jest pomijany. Zwraca
  /// liczbę miesięcy, które faktycznie się zmieniły.
  Future<int> setMonths(String id, Map<String, PlanMonth?> changes) async {
    final p = position(id);
    if (p == null) return 0;
    final months = Map<String, PlanMonth>.of(p.months);
    var applied = 0;
    for (final MapEntry(key: key, value: m) in changes.entries) {
      if (m == null) {
        if (months.remove(key) != null) applied++;
      } else if (p.inPeriod(key)) {
        months[key] = m;
        applied++;
      }
    }
    if (applied == 0) return 0;
    await _save(p.copyWith(months: months));
    notifyListeners();
    return applied;
  }

  /// Identyfikatory razem z partnerami z pary pożyczki — operacja na
  /// połowie pary zostawiłaby pożyczkę bez spłaty albo odwrotnie. Zakup
  /// z pożyczki ratalnej (zwykły wydatek ze wspólnym `linkId`) pożyczki NIE
  /// ciągnie: usunięcie zakupu nie może skasować rat.
  Set<String> _withPartners(Set<String> ids) {
    final links = {
      for (final id in ids)
        if (position(id) case final p? when p.isLoan) ?p.linkId,
    };
    if (links.isEmpty) return ids;
    return {
      ...ids,
      for (final p in _storage.getPlanPositions())
        if (p.isLoan && p.linkId != null && links.contains(p.linkId)) p.id,
    };
  }

  Future<void> deleteAll(Set<String> ids) async {
    final all = _withPartners(ids);
    for (final id in all) {
      await _storage.deletePlanPosition(id);
    }
    _log.info('Deleted ${all.length} plan positions');
    notifyListeners();
  }

  Future<void> setArchivedAll(Set<String> ids, bool archived) =>
      _updateAll(_withPartners(ids), (p) => p.copyWith(archived: archived));

  Future<void> setCategoryForAll(Set<String> ids, String? categoryId) =>
      _updateAll(
        ids,
        (p) => categoryId == null
            ? p.copyWith(clearCategoryId: true)
            : p.copyWith(categoryId: categoryId),
      );

  Future<void> setPaymentMethodForAll(Set<String> ids, String? method) =>
      _updateAll(
        ids,
        (p) => method == null
            ? p.copyWith(clearPaymentMethod: true)
            : p.copyWith(paymentMethod: method),
      );

  Future<void> _updateAll(
    Set<String> ids,
    PlanPosition Function(PlanPosition) change,
  ) async {
    for (final id in ids) {
      final p = position(id);
      if (p != null) await _save(change(p));
    }
    notifyListeners();
  }

  // ── Plan na kolejny rok ────────────────────────────────────────────────────

  /// Pozycje, które da się przenieść z [fromYear] — wszystkie poza
  /// pożyczkami i zakupami z pożyczek (jednorazowe, powiązane `linkId`),
  /// które mają w tym roku choć jeden miesiąc, a ich okres sięga kolejnego
  /// roku (zakończonej raty nie ma czego przenosić).
  List<PlanPosition> copyCandidates(int fromYear) => [
    for (final p in positions)
      if (p.linkId == null &&
          p.hasYear(fromYear) &&
          !PlanService.endsBefore(p, fromYear + 1))
        p,
  ];

  bool defaultCopySelected(PlanPosition p, int fromYear) =>
      _plan.defaultCopySelected(p, fromYear);

  /// Przenosi miesiące wybranych pozycji z [fromYear] na [toYear]. Zwraca
  /// liczbę pozycji, które dostały nowe miesiące.
  Future<int> copyYear(int fromYear, int toYear, Set<String> ids) async {
    var changed = 0;
    for (final id in ids) {
      final p = position(id);
      if (p == null) continue;
      final months = _plan.monthsWithYearCopied(p, fromYear, toYear);
      if (months.length == p.months.length) continue;
      await _save(p.copyWith(months: months));
      changed++;
    }
    _log.info('Copied plan $fromYear → $toYear: $changed positions');
    notifyListeners();
    return changed;
  }

  // ── Pożyczka z karty (ADR-035 §4) ─────────────────────────────────────────

  /// Para pożyczka–spłata o danym `linkId`.
  ({PlanPosition? loan, PlanPosition? repayment}) loanPair(String linkId) {
    PlanPosition? loan, repayment;
    for (final p in _storage.getPlanPositions()) {
      if (p.linkId != linkId) continue;
      if (p.kind == PlanKind.loan) loan = p;
      if (p.kind == PlanKind.loanRepayment) repayment = p;
    }
    return (loan: loan, repayment: repayment);
  }

  // ── Pożyczka ratalna (ADR-036) ─────────────────────────────────────────────

  /// Części pożyczki ratalnej o danym `linkId`: wypłata (wpływ), raty
  /// (z warunkami) i opcjonalny zakup (zwykły wydatek).
  ({PlanPosition? loan, PlanPosition? repayment, PlanPosition? purchase})
  loanParts(String linkId) {
    PlanPosition? loan, repayment, purchase;
    for (final p in _storage.getPlanPositions()) {
      if (p.linkId != linkId) continue;
      switch (p.kind) {
        case PlanKind.loan:
          loan = p;
        case PlanKind.loanRepayment:
          repayment = p;
        case PlanKind.expense:
          purchase = p;
        case PlanKind.income:
          break;
      }
    }
    return (loan: loan, repayment: repayment, purchase: purchase);
  }

  /// Czy raty pożyczki różnią się od tych, które wynikają z jej warunków —
  /// ktoś poprawił je ręcznie, a zapis warunków by te poprawki nadpisał.
  bool loanInstallmentsEdited(String linkId) {
    final rep = loanParts(linkId).repayment;
    final terms = rep?.loanTerms;
    if (rep == null || terms == null) return false;
    final expected = LoanMath.installmentMonths(terms);
    if (expected.length != rep.months.length) return true;
    for (final MapEntry(key: k, value: m) in expected.entries) {
      final actual = rep.months[k];
      if (actual == null ||
          (actual.amount - m.amount).abs() > 0.005 ||
          actual.day != m.day) {
        return true;
      }
    }
    return false;
  }

  /// Zapisuje pożyczkę ratalną (nową albo istniejącą, gdy podano [linkId]):
  /// wpływ w dniu wypłaty, raty z warunków (z okresem od pierwszej do
  /// ostatniej raty) i — gdy podano [purchase] — zakup tego dnia jako zwykły
  /// wydatek. Raty są w Pożyczkach, zakup w Wydatkach, więc ten sam koszt
  /// nie liczy się dwa razy. Odznaczony zakup istniejącej pożyczki znika.
  Future<String> saveInstallmentLoan({
    String? linkId,
    required String name,
    required Currency currency,
    required PlanLoanTerms terms,
    String? paymentMethod,
    String? note,
    ({double amount, String? categoryId})? purchase,
  }) async {
    final link = linkId ?? _uuid.v4();
    final existing = loanParts(link);
    final now = DateTime.now();
    final drawKey = BudgetEntry.monthKeyOf(terms.drawdown);
    final drawMonth = {
      drawKey: PlanMonth(amount: terms.principal, day: terms.drawdown.day),
    };

    PlanPosition side(
      PlanPosition? old,
      PlanKind kind,
      Map<String, PlanMonth> months, {
      int? day,
      String? period,
      String? periodEnd,
      PlanLoanTerms? loanTerms,
      String? categoryId,
    }) {
      final base =
          old ??
          PlanPosition(
            id: _uuid.v4(),
            budgetId: budgetId,
            name: name,
            kind: kind,
            currency: currency,
            linkId: link,
            createdAt: now,
          );
      return base.copyWith(
        name: name,
        currency: currency,
        paymentMethod: paymentMethod,
        clearPaymentMethod: paymentMethod == null,
        categoryId: categoryId,
        clearCategoryId: categoryId == null,
        note: note,
        clearNote: note == null,
        day: day,
        clearDay: day == null,
        months: months,
        periodStart: period,
        clearPeriodStart: period == null,
        periodEnd: periodEnd,
        clearPeriodEnd: periodEnd == null,
        loanTerms: loanTerms,
        clearLoanTerms: loanTerms == null,
      );
    }

    await _save(side(existing.loan, PlanKind.loan, drawMonth));
    await _save(
      side(
        existing.repayment,
        PlanKind.loanRepayment,
        LoanMath.installmentMonths(terms),
        day: terms.day,
        period: terms.firstMonth,
        periodEnd: terms.lastMonth,
        loanTerms: terms,
      ),
    );
    if (purchase != null) {
      await _save(
        side(
          existing.purchase,
          PlanKind.expense,
          {
            drawKey: PlanMonth(
              amount: purchase.amount,
              day: terms.drawdown.day,
            ),
          },
          categoryId: purchase.categoryId,
        ),
      );
    } else if (existing.purchase != null) {
      await _storage.deletePlanPosition(existing.purchase!.id);
    }
    _log.info('Saved installment loan: $name (${terms.count} rat)');
    notifyListeners();
    return link;
  }

  /// Usuwa pożyczkę (wypłatę i spłatę). Zakup — gdy [withPurchase]; inaczej
  /// zostaje jako zwykły wydatek, już bez powiązania z pożyczką.
  Future<void> deleteLoan(String linkId, {required bool withPurchase}) async {
    final parts = loanParts(linkId);
    for (final p in [parts.loan, parts.repayment].nonNulls) {
      await _storage.deletePlanPosition(p.id);
    }
    final purchase = parts.purchase;
    if (purchase != null) {
      if (withPurchase) {
        await _storage.deletePlanPosition(purchase.id);
      } else {
        await _save(purchase.copyWith(clearLinkId: true));
      }
    }
    _log.info('Deleted loan $linkId (zakup: $withPurchase)');
    notifyListeners();
  }

  /// Zapisuje parę pożyczka–spłata (nową albo istniejącą, gdy podano
  /// [linkId]). Każda strona to pozycja z jednym miesiącem.
  Future<void> saveCardLoan({
    String? linkId,
    required String name,
    required String card,
    required Currency currency,
    required DateTime useDate,
    required double amount,
    required DateTime repaymentDate,
    required double repaymentAmount,
    String? note,
  }) async {
    final link = linkId ?? _uuid.v4();
    final existing = loanPair(link);
    final now = DateTime.now();
    PlanPosition side(
      PlanPosition? old,
      PlanKind kind,
      String sideName,
      DateTime date,
      double value,
    ) {
      final months = {
        BudgetEntry.monthKeyOf(date): PlanMonth(amount: value, day: date.day),
      };
      if (old != null) {
        return old.copyWith(
          name: sideName,
          paymentMethod: card,
          currency: currency,
          months: months,
          note: note,
          clearNote: note == null,
        );
      }
      return PlanPosition(
        id: _uuid.v4(),
        budgetId: budgetId,
        name: sideName,
        kind: kind,
        currency: currency,
        paymentMethod: card,
        note: note,
        months: months,
        linkId: link,
        createdAt: now,
      );
    }

    await _save(side(existing.loan, PlanKind.loan, name, useDate, amount));
    await _save(
      side(
        existing.repayment,
        PlanKind.loanRepayment,
        'Spłata: $name',
        repaymentDate,
        repaymentAmount,
      ),
    );
    _log.info('Saved card loan: $name ($card)');
    notifyListeners();
  }
}
