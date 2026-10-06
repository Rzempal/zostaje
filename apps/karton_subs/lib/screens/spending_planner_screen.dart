import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/budget_controller.dart';
import '../controllers/plan_controller.dart';
import '../services/plan_service.dart' show PlanPeriod;
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/spending_allocation_editor.dart';
import '../widgets/budget_widgets.dart' show budgetNf;

/// Ekran „Planner" — plan koperty „Na bieżące wydatki" (ADR-012): z czego się składa
/// i ile razem wynosi.
///
/// Osobny ekran, a nie sekcja zwijana na „Bieżących", bo plan dotyczy dwóch
/// miejsc naraz: wydatki bieżące go realizują, a wydatki cykliczne pomniejsza jako
/// rezerwa. Z obu tych ekranów wchodzi się tutaj, zamiast trzymać edycję
/// w jednym z nich i odsyłać z drugiego.
///
/// Plan jest JEDEN dla wszystkich miesięcy, dlatego nie ma tu nawigacji po
/// miesiącach — wykonanie planu w danym miesiącu pokazuje karta na „Bieżących".
///
/// Zakres (osobisty/domowy) jest dziedziczony z ekranu, z którego tu weszliśmy —
/// koperty są dwie, a przełącznik w podekranie byłby prostą drogą do edycji nie
/// tej, o którą chodziło. Zakres stoi w podtytule.
class SpendingPlannerScreen extends StatelessWidget {
  const SpendingPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<BudgetController>();
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final cur = ctrl.targetCurrencyLabel;
    final alloc = ctrl.spendingAllocation;
    final items = ctrl.spendingAllocationItems.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Planner'),
        // Który budżet edytujemy — koperta osobista i domowa to dwa różne plany.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                ctrl.isHousehold ? 'Budżet domowy' : 'Budżet osobisty',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Kwota zaplanowana w budżecie na bieżące wydatki. Pomniejsza '
            '„zostaje miesięcznie", a realne wydatki tej puli logujesz '
            'w „Bieżących".',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          SpendingAllocationEditor(
            items: items,
            currency: cur,
            onAdd: () => showSpendingAllocationItemEditor(context),
            onEdit: (it) =>
                showSpendingAllocationItemEditor(context, existing: it),
            onFillToRound: () => _fillToRound(context),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('Razem w planie', style: theme.textTheme.bodyMedium),
              ),
              Text(
                alloc == null
                    ? 'Brak'
                    : '−${budgetNf.format(alloc)}${curLabelSuffix(cur)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: alloc == null ? c.textMuted : c.negative,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// „Uzupełnij do pełnej kwoty": dopisuje pozycję planu tak, by suma — planu
  /// albo wszystkich kosztów miesięcznych — wyszła okrągła (10 / 100 / 1000).
  ///
  /// Obie bazy działają tą samą pozycją, bo Planner jest częścią kosztów
  /// miesięcznych: dopisana kwota podnosi obie sumy o tyle samo.
  ///
  /// Wynik to MIGAWKA, nie reguła — po zmianie któregokolwiek kosztu suma
  /// przestanie być okrągła. Celowo: plan jest podstawą „zostaje miesięcznie"
  /// i nie ma się zmieniać sam z siebie.
  Future<void> _fillToRound(BuildContext context) async {
    final ctrl = context.read<BudgetController>();
    final plan = context.read<PlanController>();
    final cur = ctrl.targetCurrencyLabel;
    var basePlanner = true;
    var step = 100;
    // Wydatki planu rocznego (ADR-035): średnio miesięcznie w bieżącym roku —
    // pozycje, subskrypcje i sam Planner.
    double planExpenses() => plan.totals(PlanPeriod(plan.today.year)).outgoing;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) {
          final planTotal = ctrl.spendingAllocation ?? 0;
          final expensesTotal = planExpenses();
          final base = basePlanner ? planTotal : expensesTotal;
          final gap = ctrl.roundUpGap(base, step);
          final theme = Theme.of(dctx);

          String money(double v) =>
              '${budgetNf.format(v)}${curLabelSuffix(cur)}';

          return AlertDialog(
            title: const Text('Uzupełnij do pełnej kwoty'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zaokrąglamy', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('Planner · ${money(planTotal)}'),
                        selected: basePlanner,
                        onSelected: (_) => setLocal(() => basePlanner = true),
                      ),
                      ChoiceChip(
                        label: Text('Wydatki · ${money(expensesTotal)}'),
                        selected: !basePlanner,
                        onSelected: (_) => setLocal(() => basePlanner = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    basePlanner
                        ? 'Suma pozycji planu.'
                        : 'Wydatki planu średnio miesięcznie w bieżącym roku: '
                              'pozycje, subskrypcje i Planner.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text('Do pełnych', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in [10, 100, 1000])
                        ChoiceChip(
                          label: Text('$s'),
                          selected: step == s,
                          onSelected: (_) => setLocal(() => step = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    gap == 0
                        ? 'Ta suma jest już okrągła — nie ma czego uzupełniać.'
                        : 'Dodamy pozycję ${money(gap)} — '
                              '${basePlanner ? 'plan' : 'wydatki'} wyjdą '
                              '${money(base + gap)}.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: gap == 0 ? null : () => Navigator.pop(dctx, true),
                child: const Text('Dalej'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final base = basePlanner
        ? (ctrl.spendingAllocation ?? 0)
        : planExpenses();
    final gap = ctrl.roundUpGap(base, step);
    if (gap == 0) return;

    // Istniejący bufor podbijamy zamiast dokładać drugi — po kilku użyciach
    // plan miałby inaczej pięć pozycji „Bufor" i nikt by nie wiedział, czemu.
    final existing = ctrl.spendingAllocationItems
        .where((it) => it.name.toLowerCase() == _bufferName.toLowerCase())
        .firstOrNull;

    await showSpendingAllocationItemEditor(
      context,
      existing: existing,
      initialName: _bufferName,
      initialAmount: (existing?.amount ?? 0) + gap,
    );
  }
}

/// Nazwa pozycji domykającej plan do okrągłej kwoty. Bufor jest zwykłą pozycją
/// koperty (ADR-012), więc rozpoznajemy go po nazwie, a nie po nowym polu.
const _bufferName = 'Bufor';
