import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../controllers/budget_controller.dart';
import '../models/budget.dart';
import '../theme/app_theme.dart';
import 'category_icons.dart' show categoryIcon;

/// Przełącznik budżetu (ADR-037): przycisk z ikoną i nazwą aktywnego
/// budżetu; dotknięcie rozwija listę widocznych budżetów i „Zarządzaj
/// budżetami". Miejsce zawsze to samo, niezależnie od liczby budżetów.
class BudgetPicker extends StatelessWidget {
  final VoidCallback onManage;

  const BudgetPicker({super.key, required this.onManage});

  static const _manage = '__manage__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final budget = context.watch<BudgetController>();
    final active = budget.activeBudget;

    return PopupMenuButton<String>(
      tooltip: 'Zmień budżet',
      position: PopupMenuPosition.under,
      onSelected: (v) => v == _manage ? onManage() : budget.setBudget(v),
      itemBuilder: (_) => [
        for (final b in budget.visibleBudgets)
          PopupMenuItem(
            value: b.id,
            child: Row(
              children: [
                Icon(categoryIcon(b.icon), size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (b.id == active.id)
                  Icon(LucideIcons.check, size: 18, color: c.primary),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _manage,
          child: Row(
            children: [
              Icon(LucideIcons.settings2, size: 18, color: c.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Zarządzaj budżetami',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.primary),
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: c.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(categoryIcon(active.icon), size: 18, color: c.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 18, color: c.primary),
          ],
        ),
      ),
    );
  }
}

/// Wybór budżetu docelowego dla „Przenieś do…" / „Kopiuj do…" — wszystkie
/// budżety poza [excludeBudgetId] (także ukryte, oznaczone). Przy kopiowaniu
/// całego budżetu [subscriptionsOption] dodaje „z subskrypcjami".
///
/// Zwraca wybrany budżet i decyzję o subskrypcjach; `null` = anulowano.
Future<({Budget budget, bool withSubscriptions})?> showBudgetTargetSheet(
  BuildContext context, {
  required String excludeBudgetId,
  required String title,
  String? subtitle,
  bool subscriptionsOption = false,
}) {
  final budgets = [
    for (final b in context.read<BudgetController>().budgets)
      if (b.id != excludeBudgetId) b,
  ];
  var withSubscriptions = true;
  return showModalBottomSheet<({Budget budget, bool withSubscriptions})>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        final theme = Theme.of(sheetCtx);
        final c = sheetCtx.semanticColors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.textMuted,
                    ),
                  ),
                ],
                if (subscriptionsOption)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: withSubscriptions,
                    onChanged: (v) =>
                        setSheet(() => withSubscriptions = v ?? true),
                    title: const Text('Z subskrypcjami'),
                    subtitle: const Text(
                      'Kopie subskrypcji mają własne przypomnienia',
                    ),
                  ),
                const SizedBox(height: 8),
                if (budgets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nie ma innego budżetu. Dodaj go w Ustawieniach → '
                      'Budżety.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                for (final b in budgets)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(categoryIcon(b.icon)),
                    title: Text(b.name),
                    subtitle: b.hidden ? const Text('ukryty') : null,
                    trailing: const Icon(LucideIcons.chevronRight),
                    onTap: () => Navigator.pop(sheetCtx, (
                      budget: b,
                      withSubscriptions: withSubscriptions,
                    )),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Przenosi albo kopiuje pozycje planu [ids] do wybranego budżetu
/// (ADR-037) — z wyborem budżetu w arkuszu i komunikatem o wyniku. Pożyczka
/// idzie w całości (wypłata, raty, zakup). Zwraca `true`, gdy coś zrobiono.
Future<bool> moveOrCopyPositions(
  BuildContext context,
  Set<String> ids, {
  required bool copy,
  required String fromBudgetId,
  String? what,
}) async {
  final budgets = context.read<BudgetController>();
  final label = what ?? (ids.length == 1 ? 'pozycję' : '${ids.length} poz.');
  final target = await showBudgetTargetSheet(
    context,
    excludeBudgetId: fromBudgetId,
    title: copy ? 'Kopiuj $label do budżetu…' : 'Przenieś $label do budżetu…',
    subtitle: copy
        ? 'Kopie dostają nowe identyfikatory; odhaczone płatności się nie '
              'kopiują.'
        : 'Razem z odhaczonymi płatnościami.',
  );
  if (target == null || !context.mounted) return false;
  final n = copy
      ? await budgets.copyPositions(ids, target.budget.id)
      : await budgets.movePositions(ids, target.budget.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${copy ? 'Skopiowano' : 'Przeniesiono'} $n poz. do '
            '„${target.budget.name}"',
          ),
        ),
      );
  }
  return n > 0;
}
