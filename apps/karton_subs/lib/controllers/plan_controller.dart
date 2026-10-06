import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/app_logger.dart';
import '../services/budget_service.dart' show DayCashflow;
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import 'budget_controller.dart';

/// Stan planu rocznego aktywnego budżetu (ADR-035) — pozycje z miesiącami,
/// subskrypcje jako osobna sekcja, koperta „Na bieżące wydatki".
///
/// Aktywny budżet, odhaczenia płatności i kopertę trzyma [BudgetController]
/// — ten kontroler go słucha, więc przełączenie budżetu odświeża plan.
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
  String get budgetId => _budget.scope.name;

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

  /// Koperta „Na bieżące wydatki" — ta sama kwota w każdym miesiącu planu.
  double get envelope => _budget.spendingAllocation ?? 0;

  List<int> get years => _plan.yearsFor(positions, today);

  // ── Kwoty ──────────────────────────────────────────────────────────────────

  double amountOf(PlanPosition p, PlanPeriod period) =>
      _plan.positionAmount(p, period, target);

  double subscriptionAmountOf(Subscription s, PlanPeriod period) =>
      _plan.subscriptionAmount(s, period, target);

  PlanMonthTotals totals(PlanPeriod period) => _plan.periodTotals(
    positions: positions,
    subscriptions: subscriptions,
    envelope: envelope,
    period: period,
    target: target,
  );

  PlanYearStats yearStats(int year) => _plan.yearStats(
    positions: positions,
    subscriptions: subscriptions,
    envelope: envelope,
    year: year,
    target: target,
  );

  /// Kalendarz płatności miesiąca: plan, subskrypcje i Bieżące (stary zapis).
  Map<int, DayCashflow> calendarForMonth(DateTime month) =>
      _plan.calendarForMonth(
        positions: positions,
        subscriptions: subscriptions,
        spending: _storage.getBudgetEntries(_budget.scope),
        month: month,
        target: target,
        autoByPayment: {
          for (final pm in _storage.getPaymentMethods())
            pm.name: pm.isAutomatic,
        },
      );

  // ── Pozycje ────────────────────────────────────────────────────────────────

  Future<void> _save(PlanPosition p) =>
      _storage.savePlanPosition(p.copyWith(updatedAt: DateTime.now()));

  Future<PlanPosition> create({
    required String name,
    required PlanKind kind,
    required Currency currency,
    required Map<String, PlanMonth> months,
    String? categoryId,
    String? paymentMethod,
    int? day,
    String? note,
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
      createdAt: DateTime.now(),
    );
    await _save(p);
    _log.info('Created plan position: $name (${months.length} mies.)');
    notifyListeners();
    return p;
  }

  Future<void> update(PlanPosition p) async {
    await _save(p);
    notifyListeners();
  }

  /// Zmiany miesięcy jednej pozycji: klucz → nowy miesiąc, `null` = usuń
  /// miesiąc z planu.
  Future<void> setMonths(String id, Map<String, PlanMonth?> changes) async {
    final p = position(id);
    if (p == null) return;
    final months = Map<String, PlanMonth>.of(p.months);
    for (final MapEntry(key: key, value: m) in changes.entries) {
      if (m == null) {
        months.remove(key);
      } else {
        months[key] = m;
      }
    }
    await _save(p.copyWith(months: months));
    notifyListeners();
  }

  /// Identyfikatory razem z partnerami z pary karty — operacja na połowie
  /// pary zostawiłaby pożyczkę bez spłaty albo odwrotnie.
  Set<String> _withPartners(Set<String> ids) {
    final links = {for (final id in ids) ?position(id)?.linkId};
    if (links.isEmpty) return ids;
    return {
      ...ids,
      for (final p in _storage.getPlanPositions())
        if (p.linkId != null && links.contains(p.linkId)) p.id,
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

  /// Pozycje, które da się przenieść z [fromYear] — wszystkie poza kartą,
  /// które mają w tym roku choć jeden miesiąc.
  List<PlanPosition> copyCandidates(int fromYear) => [
    for (final p in positions)
      if (!p.isCard && p.hasYear(fromYear)) p,
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
  ({PlanPosition? loan, PlanPosition? repayment}) cardPair(String linkId) {
    PlanPosition? loan, repayment;
    for (final p in _storage.getPlanPositions()) {
      if (p.linkId != linkId) continue;
      if (p.kind == PlanKind.cardLoan) loan = p;
      if (p.kind == PlanKind.cardRepayment) repayment = p;
    }
    return (loan: loan, repayment: repayment);
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
    final existing = cardPair(link);
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

    await _save(side(existing.loan, PlanKind.cardLoan, name, useDate, amount));
    await _save(
      side(
        existing.repayment,
        PlanKind.cardRepayment,
        'Spłata: $name',
        repaymentDate,
        repaymentAmount,
      ),
    );
    _log.info('Saved card loan: $name ($card)');
    notifyListeners();
  }
}
