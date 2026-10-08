import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/plan_controller.dart';
import '../models/plan_position.dart';
import '../theme/app_theme.dart';
import '../widgets/budget_widgets.dart' show budgetNf;
import '../widgets/form_action_bar.dart';

/// Plan na kolejny rok z poprzedniego (ADR-035): te same miesiące, kwoty
/// i dni. Miesiąc, który w nowym roku już jest, zostaje nietknięty.
///
/// Domyślnie odznaczone są pozycje, które wyglądają na zakończone (biegną
/// z poprzedniego roku i urywają się przed grudniem — typowo ostatnie raty).
class PlanCopyYearScreen extends StatefulWidget {
  final int fromYear;

  const PlanCopyYearScreen({super.key, required this.fromYear});

  @override
  State<PlanCopyYearScreen> createState() => _PlanCopyYearScreenState();
}

class _PlanCopyYearScreenState extends State<PlanCopyYearScreen> {
  late final List<PlanPosition> _candidates;
  final Set<String> _selected = {};
  bool _saving = false;

  int get _toYear => widget.fromYear + 1;

  @override
  void initState() {
    super.initState();
    final plan = context.read<PlanController>();
    _candidates = plan.copyCandidates(widget.fromYear)
      ..sort((a, b) {
        if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    _selected.addAll([
      for (final p in _candidates)
        if (plan.defaultCopySelected(p, widget.fromYear)) p.id,
    ]);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final changed = await context.read<PlanController>().copyYear(
      widget.fromYear,
      _toYear,
      _selected,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Zaplanowano $_toYear: $changed poz.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final from = widget.fromYear;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FormActionBar(
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        onSave: _saving || _selected.isEmpty ? null : _submit,
        saveLabel: 'Zaplanuj',
      ),
      appBar: AppBar(title: Text('Plan $_toYear na bazie $from')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, kFormActionBarSpace),
        children: [
          Text(
            'Zaznaczone pozycje dostaną w $_toYear te same miesiące, kwoty '
            'i dni co w $from. Miesiące, które już są w $_toYear, zostaną bez '
            'zmian — także kwoty z niego da się potem poprawiać miesiąc po '
            'miesiącu.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'W $from nie ma pozycji do przeniesienia.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final p in _candidates)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selected.contains(p.id),
              onChanged: (on) => setState(() {
                on == true ? _selected.add(p.id) : _selected.remove(p.id);
              }),
              title: Text(p.name),
              subtitle: Text(
                '${p.isInflow ? 'Wpływ' : 'Wydatek'} · '
                '${p.monthsOfYear(from).length} mies. w $from · '
                'suma ${budgetNf.format(p.yearTotal(from))}'
                '${p.hasYear(_toYear) ? ' · ma już miesiące w $_toYear' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}
