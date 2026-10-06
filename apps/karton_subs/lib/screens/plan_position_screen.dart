import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/plan_controller.dart';
import '../models/plan_position.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/budget_widgets.dart' show budgetNf;
import '../widgets/selection_bar.dart';
import 'plan_position_form_screen.dart';

/// Szczegóły pozycji planu: miesiące wybranego roku (ADR-035).
///
/// Każdy miesiąc ma własną kwotę i dzień — tapnięcie edytuje jeden,
/// przytrzymanie zaczyna zaznaczanie kilku (np. podwyżka od lipca: zaznacz
/// lipiec–grudzień, „Ustaw kwotę"). Miesiąc „poza planem" też da się
/// zaznaczyć — ustawienie kwoty dodaje go do planu.
class PlanPositionScreen extends StatefulWidget {
  final String positionId;
  final int initialYear;

  const PlanPositionScreen({
    super.key,
    required this.positionId,
    required this.initialYear,
  });

  @override
  State<PlanPositionScreen> createState() => _PlanPositionScreenState();
}

class _PlanPositionScreenState extends State<PlanPositionScreen> {
  late int _year = widget.initialYear;
  final Set<String> _selected = {};
  bool _selecting = false;

  String _monthName(int m) {
    final name = DateFormat('LLLL', 'pl').format(DateTime(2000, m));
    return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
  }

  void _toggle(String key) => setState(() {
    if (!_selected.remove(key)) _selected.add(key);
    if (_selected.isEmpty) _selecting = false;
  });

  void _endSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  /// Kwota wpisana ręcznie albo podstawiona z formatu (spacje grupujące,
  /// także twarde z `budgetNf`, i przecinek dziesiętny).
  double? _parseAmount(String raw) {
    final v = double.tryParse(
      raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'),
    );
    return v == null || v < 0 ? null : v;
  }

  int? _parseDay(String raw) {
    final v = int.tryParse(raw.trim());
    return v == null || v < 1 || v > 31 ? null : v;
  }

  /// Edycja jednego miesiąca: kwota i dzień; dla miesiąca w planie także
  /// „Usuń z planu".
  Future<void> _editMonth(PlanPosition p, String key, int month) async {
    final plan = context.read<PlanController>();
    final current = p.months[key];
    final amountCtrl = TextEditingController(
      text: current == null ? '' : budgetNf.format(current.amount),
    );
    final dayCtrl = TextEditingController(text: current?.day?.toString() ?? '');
    final result = await showDialog<({PlanMonth? month, bool remove})>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('${_monthName(month)} $_year'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Kwota',
                suffixText: p.currency.label,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dayCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Dzień płatności (opcjonalnie)',
                hintText: p.day != null ? 'domyślnie ${p.day}' : null,
              ),
            ),
          ],
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(dctx, (month: null, remove: true)),
              style: TextButton.styleFrom(foregroundColor: AppColors.negative),
              child: const Text('Usuń z planu'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              final amount = _parseAmount(amountCtrl.text);
              if (amount == null) return;
              Navigator.pop(dctx, (
                month: PlanMonth(amount: amount, day: _parseDay(dayCtrl.text)),
                remove: false,
              ));
            },
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await plan.setMonths(p.id, {key: result.remove ? null : result.month});
  }

  Future<void> _bulkAmount(PlanPosition p) async {
    final plan = context.read<PlanController>();
    final ctrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Kwota dla ${_selected.length} mies.'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Kwota',
            suffixText: p.currency.label,
            helperText: 'Miesiące poza planem zostaną do niego dodane',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              final v = _parseAmount(ctrl.text);
              if (v != null) Navigator.pop(dctx, v);
            },
            child: const Text('Ustaw'),
          ),
        ],
      ),
    );
    if (amount == null || !mounted) return;
    await plan.setMonths(p.id, {
      for (final key in _selected)
        key: (p.months[key] ?? const PlanMonth(amount: 0)).copyWith(
          amount: amount,
        ),
    });
    _endSelection();
  }

  Future<void> _bulkDay(PlanPosition p) async {
    final plan = context.read<PlanController>();
    final ctrl = TextEditingController();
    final day = await showDialog<int?>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Dzień płatności dla ${_selected.length} mies.'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Dzień (1–31)',
            helperText: 'Puste = dzień pozycji',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, _parseDay(ctrl.text) ?? 0),
            child: const Text('Ustaw'),
          ),
        ],
      ),
    );
    if (day == null || !mounted) return;
    await plan.setMonths(p.id, {
      for (final key in _selected)
        if (p.months[key] != null)
          key: day == 0
              ? p.months[key]!.copyWith(clearDay: true)
              : p.months[key]!.copyWith(day: day),
    });
    _endSelection();
  }

  Future<void> _bulkRemove(PlanPosition p) async {
    final keys = _selected.where(p.months.containsKey).toList();
    if (keys.isEmpty) return _endSelection();
    await context.read<PlanController>().setMonths(p.id, {
      for (final k in keys) k: null,
    });
    _endSelection();
  }

  Future<void> _delete(PlanPosition p) async {
    final plan = context.read<PlanController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Usunąć „${p.name}"?'),
        content: const Text(
          'Pozycja zniknie z planu razem ze wszystkimi miesiącami.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pop();
    await plan.deleteAll({p.id});
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanController>();
    final p = plan.position(widget.positionId);
    if (p == null) {
      return const Scaffold(body: Center(child: Text('Pozycja nie istnieje')));
    }
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final storage = context.read<StorageService>();
    final category = p.categoryId != null
        ? storage.getCategory(p.categoryId!)
        : null;
    final color = p.isInflow ? c.positive : c.negative;
    final keys = [for (var m = 1; m <= 12; m++) planMonthKey(_year, m)];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Edytuj pozycję',
            icon: const Icon(LucideIcons.pencil),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlanPositionFormScreen(existing: p),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                await plan.setArchivedAll({p.id}, !p.archived);
              } else if (v == 'delete') {
                await _delete(p);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(p.archived ? 'Przywróć do planu' : 'Ukryj pozycję'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Usuń pozycję')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selecting)
            SelectionBar(
              count: _selected.length,
              allSelected: _selected.length == keys.length,
              onToggleAll: () => setState(() {
                if (_selected.length == keys.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(keys);
                }
              }),
              onClose: _endSelection,
              actions: [
                SelectionAction(
                  icon: LucideIcons.coins,
                  tooltip: 'Ustaw kwotę',
                  onPressed: () => _bulkAmount(p),
                ),
                SelectionAction(
                  icon: LucideIcons.calendarDays,
                  tooltip: 'Ustaw dzień płatności',
                  onPressed: () => _bulkDay(p),
                ),
                SelectionAction(
                  icon: LucideIcons.calendarX,
                  tooltip: 'Usuń z planu',
                  danger: true,
                  onPressed: () => _bulkRemove(p),
                ),
              ],
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  [
                    p.isInflow ? 'Wpływ' : 'Wydatek',
                    ?category?.name,
                    ?p.paymentMethod,
                    if (p.day != null) 'dzień ${p.day}',
                    if (p.archived) 'ukryta',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.textMuted,
                  ),
                ),
                if (p.note != null) ...[
                  const SizedBox(height: 4),
                  Text(p.note!, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.chevronLeft),
                      onPressed: () => setState(() {
                        _year--;
                        _selected.clear();
                        _selecting = false;
                      }),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('$_year', style: theme.textTheme.titleMedium),
                          Text(
                            'suma ${budgetNf.format(p.yearTotal(_year))}'
                            '${curLabelSuffix(p.currency.label)} · średnio '
                            '${budgetNf.format(p.yearAverage(_year))}/mies.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.chevronRight),
                      onPressed: () => setState(() {
                        _year++;
                        _selected.clear();
                        _selecting = false;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var m = 1; m <= 12; m++)
                  SelectableRow(
                    selectionMode: _selecting,
                    selected: _selected.contains(keys[m - 1]),
                    onTap: () => _toggle(keys[m - 1]),
                    onLongPress: () => setState(() {
                      _selecting = true;
                      _selected.add(keys[m - 1]);
                    }),
                    child: _MonthRow(
                      name: _monthName(m),
                      month: p.months[keys[m - 1]],
                      defaultDay: p.day,
                      color: color,
                      inflow: p.isInflow,
                      onTap: () => _editMonth(p, keys[m - 1], m),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  final String name;
  final PlanMonth? month;
  final int? defaultDay;
  final Color color;
  final bool inflow;
  final VoidCallback onTap;

  const _MonthRow({
    required this.name,
    required this.month,
    required this.defaultDay,
    required this.color,
    required this.inflow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final m = month;
    final day = m?.day ?? defaultDay;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: m == null ? c.textMuted : null,
                    ),
                  ),
                  if (m != null && day != null)
                    Text(
                      'dzień $day${m.day == null ? '' : ' (zmieniony)'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              m == null
                  ? 'poza planem'
                  : '${inflow ? '+' : '−'}${budgetNf.format(m.amount)}',
              style: m == null
                  ? theme.textTheme.bodySmall?.copyWith(color: c.textMuted)
                  : theme.textTheme.bodyLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
