import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../controllers/budget_controller.dart';
import '../models/budget.dart';
import '../theme/app_theme.dart';
import '../widgets/budget_picker.dart' show showBudgetTargetSheet;
import '../widgets/category_icons.dart'
    show availableIconNames, categoryIcon;

/// Ustawienia → Budżety (ADR-037): kolejność, ukrywanie, nazwa i ikona,
/// przeniesienie albo kopia całej zawartości do innego budżetu i usuwanie
/// z ostrzeżeniem. Zastępuje dawny „tryb budżetu" (osobisty / domowy / oba).
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  static String _count(int n, String one, String few, String many) {
    if (n == 1) return '$n $one';
    final tens = n % 100, units = n % 10;
    return units >= 2 && units <= 4 && (tens < 12 || tens > 14)
        ? '$n $few'
        : '$n $many';
  }

  void _snack(BuildContext context, String text) => ScaffoldMessenger.of(
    context,
  )..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text)));

  /// Nazwa i ikona — dla nowego budżetu ([budget] `null`) i do edycji.
  Future<({String name, String icon})?> _editDialog(
    BuildContext context, {
    Budget? budget,
  }) {
    final name = TextEditingController(text: budget?.name ?? '');
    var icon = budget?.icon ?? 'folder';
    String? error;
    return showDialog<({String name, String icon})>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) {
          final c = dctx.semanticColors;
          return AlertDialog(
            title: Text(budget == null ? 'Nowy budżet' : 'Nazwa i ikona'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    autofocus: budget == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Nazwa',
                      hintText: 'np. Firma, Wakacje',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ikona',
                    style: Theme.of(dctx).textTheme.labelLarge?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final n in availableIconNames)
                            InkWell(
                              borderRadius: BorderRadius.circular(
                                AppRadii.control,
                              ),
                              onTap: () => setDialog(() => icon = n),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: icon == n
                                      ? c.primary.withValues(alpha: 0.15)
                                      : null,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.control,
                                  ),
                                  border: Border.all(
                                    color: icon == n ? c.primary : c.border,
                                  ),
                                ),
                                child: Icon(
                                  categoryIcon(n),
                                  size: 20,
                                  color: icon == n ? c.primary : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: () {
                  final n = name.text.trim();
                  if (n.isEmpty) {
                    setDialog(() => error = 'Wpisz nazwę');
                    return;
                  }
                  Navigator.pop(dctx, (name: n, icon: icon));
                },
                child: const Text('Zapisz'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final ctrl = context.read<BudgetController>();
    final result = await _editDialog(context);
    if (result == null) return;
    await ctrl.addBudget(result.name, result.icon);
    if (context.mounted) _snack(context, 'Dodano budżet „${result.name}"');
  }

  Future<void> _edit(BuildContext context, Budget b) async {
    final ctrl = context.read<BudgetController>();
    final result = await _editDialog(context, budget: b);
    if (result == null) return;
    await ctrl.updateBudget(b.copyWith(name: result.name, icon: result.icon));
  }

  Future<void> _toggleHidden(BuildContext context, Budget b) async {
    final ok = await context.read<BudgetController>().setBudgetHidden(
      b.id,
      !b.hidden,
    );
    if (!ok && context.mounted) {
      _snack(context, 'Ostatniego widocznego budżetu nie da się ukryć');
    }
  }

  Future<void> _moveOrCopyAll(
    BuildContext context,
    Budget b, {
    required bool copy,
  }) async {
    final ctrl = context.read<BudgetController>();
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: b.id,
      title: copy
          ? 'Kopiuj wszystko z „${b.name}" do…'
          : 'Przenieś wszystko z „${b.name}" do…',
      subtitle: copy
          ? 'Kopie pozycji dostają nowe identyfikatory; odhaczone płatności '
                'się nie kopiują.'
          : 'Pozycje planu i subskrypcje, razem z odhaczonymi płatnościami.',
      subscriptionsOption: copy,
    );
    if (target == null) return;
    if (copy) {
      await ctrl.copyAll(
        b.id,
        target.budget.id,
        withSubscriptions: target.withSubscriptions,
      );
    } else {
      await ctrl.moveAll(b.id, target.budget.id);
    }
    if (context.mounted) {
      _snack(
        context,
        '${copy ? 'Skopiowano' : 'Przeniesiono'} zawartość „${b.name}" do '
        '„${target.budget.name}"',
      );
    }
  }

  /// Usunięcie z ostrzeżeniem: budżet znika razem z zawartością, chyba że
  /// najpierw przeniesie się ją gdzie indziej („Przenieś i usuń").
  Future<void> _delete(BuildContext context, Budget b) async {
    final ctrl = context.read<BudgetController>();
    if (ctrl.budgets.length <= 1) {
      _snack(context, 'Ostatniego budżetu nie da się usunąć');
      return;
    }
    final positions = ctrl.positionCountOf(b.id);
    final subs = ctrl.subscriptionsOf(b.id).length;
    final empty = positions == 0 && subs == 0;
    final choice = await showDialog<String>(
      context: context,
      builder: (dctx) {
        final c = dctx.semanticColors;
        return AlertDialog(
          icon: Icon(LucideIcons.alertTriangle, color: c.warning),
          title: Text('Usunąć budżet „${b.name}"?'),
          content: Text(
            empty
                ? 'Budżet jest pusty.'
                : 'Zniknie razem z '
                      '${_count(positions, 'pozycją planu', 'pozycjami planu', 'pozycjami planu')} '
                      'i ${_count(subs, 'subskrypcją', 'subskrypcjami', 'subskrypcjami')}. '
                      'Tego nie da się cofnąć.\n\n'
                      'Jeśli nie chcesz ich stracić, przenieś je najpierw do '
                      'innego budżetu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Anuluj'),
            ),
            if (!empty)
              TextButton(
                onPressed: () => Navigator.pop(dctx, 'move'),
                child: const Text('Przenieś i usuń…'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, 'delete'),
              style: FilledButton.styleFrom(backgroundColor: c.negative),
              child: const Text('Usuń'),
            ),
          ],
        );
      },
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'move') {
      final target = await showBudgetTargetSheet(
        context,
        excludeBudgetId: b.id,
        title: 'Przenieś zawartość „${b.name}" do…',
        subtitle: 'Potem budżet „${b.name}" zostanie usunięty.',
      );
      if (target == null) return;
      await ctrl.moveAll(b.id, target.budget.id);
      await ctrl.deleteBudget(b.id);
      if (context.mounted) {
        _snack(
          context,
          'Przeniesiono do „${target.budget.name}" i usunięto „${b.name}"',
        );
      }
      return;
    }
    await ctrl.deleteBudget(b.id);
    if (context.mounted) _snack(context, 'Usunięto budżet „${b.name}"');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final ctrl = context.watch<BudgetController>();
    final budgets = ctrl.budgets;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Budżety')),
      body: ReorderableListView(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        onReorder: (from, to) {
          final ids = [for (final b in budgets) b.id];
          final moved = ids.removeAt(from);
          ids.insert(to > from ? to - 1 : to, moved);
          ctrl.reorderBudgets(ids);
        },
        header: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text(
            'Każdy budżet ma własny plan, subskrypcje i odhaczone płatności. '
            'Kolejność to kolejność w przełączniku; ukryty budżet znika '
            'z przełącznika, ale jego dane zostają.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
        ),
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: OutlinedButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(LucideIcons.plus),
            label: const Text('Nowy budżet'),
          ),
        ),
        children: [
          for (final (i, b) in budgets.indexed)
            ListTile(
              key: ValueKey(b.id),
              contentPadding: const EdgeInsets.only(left: 4, right: 0),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        LucideIcons.gripVertical,
                        size: 18,
                        color: c.textMuted,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: b.hidden
                        ? c.textMuted.withValues(alpha: 0.12)
                        : c.primary.withValues(alpha: 0.12),
                    child: Icon(
                      categoryIcon(b.icon),
                      size: 18,
                      color: b.hidden ? c.textMuted : c.primary,
                    ),
                  ),
                ],
              ),
              title: Text(
                b.hidden ? '${b.name} (ukryty)' : b.name,
                style: b.hidden ? TextStyle(color: c.textMuted) : null,
              ),
              subtitle: Text(
                '${_count(ctrl.positionCountOf(b.id), 'pozycja', 'pozycje', 'pozycji')} · '
                '${_count(ctrl.subscriptionsOf(b.id).length, 'subskrypcja', 'subskrypcje', 'subskrypcji')}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: b.hidden ? 'Pokaż w przełączniku' : 'Ukryj',
                    icon: Icon(b.hidden ? LucideIcons.eyeOff : LucideIcons.eye),
                    onPressed: () => _toggleHidden(context, b),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Więcej',
                    onSelected: (v) => switch (v) {
                      'edit' => _edit(context, b),
                      'move' => _moveOrCopyAll(context, b, copy: false),
                      'copy' => _moveOrCopyAll(context, b, copy: true),
                      _ => _delete(context, b),
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Nazwa i ikona'),
                      ),
                      const PopupMenuItem(
                        value: 'move',
                        child: Text('Przenieś wszystko do…'),
                      ),
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('Kopiuj wszystko do…'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Usuń budżet',
                          style: TextStyle(color: c.negative),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
