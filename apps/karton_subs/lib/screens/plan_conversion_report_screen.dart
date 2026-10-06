import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/plan_conversion.dart';
import '../services/storage_service.dart';
import '../utils/money_format.dart';
import '../widgets/budget_widgets.dart' show budgetNf;
import '../widgets/settings_widgets.dart';

/// Raport konwersji na plan roczny (Developer Tools, ADR-035).
///
/// Konwersję sprawdzamy na prawdziwych danych NA TELEFONIE: raport zestawia
/// sumy roku ze starego modelu z nowym planem, więc dane nie muszą opuszczać
/// urządzenia. Typowa ścieżka: wczytać kopię z PROD do „Zostaje DEV",
/// „Przelicz plan od nowa", przejrzeć różnice.
class PlanConversionReportScreen extends StatefulWidget {
  const PlanConversionReportScreen({super.key});

  @override
  State<PlanConversionReportScreen> createState() =>
      _PlanConversionReportScreenState();
}

class _PlanConversionReportScreenState
    extends State<PlanConversionReportScreen> {
  late PlanConversionReport _report;
  bool _busy = false;

  DateTime get _today => Subscription.devDateOverride ?? DateTime.now();

  PlanConversionRunner get _runner =>
      PlanConversionRunner(context.read<StorageService>());

  @override
  void initState() {
    super.initState();
    _report = _runner.report(_today);
  }

  Future<void> _reconvert() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Przeliczyć plan od nowa?'),
        content: const Text(
          'Plan zostanie wyliczony ze starych pozycji budżetu i zastąpi '
          'obecny. Stare pozycje się nie zmieniają.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Przelicz'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final result = await _runner.reconvert(_today);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _report = _runner.report(_today);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Plan przeliczony: ${result.positions.length} pozycji'),
      ),
    );
  }

  String _budgetLabel(String id) => switch (id) {
    kBudgetPersonal => 'Osobisty',
    kBudgetHousehold => 'Domowy',
    _ => id,
  };

  String _avg(double yearTotal) => budgetNf.format(yearTotal / 12);

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    final stored = storage.getPlanPositions();
    final r = _report;
    final notes = r.result;
    final budgets = {for (final y in r.years) y.budgetId};

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Konwersja planu')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          const SettingsSectionLabel('Stan'),
          SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.database),
                title: Text('Zapisany plan: ${stored.length} poz.'),
                subtitle: Text(
                  'Z obecnych danych wychodzi ${notes.positions.length} poz. · '
                  'reguły v${PlanConversion.version}, zapisane '
                  'v${storage.getPlanConversionVersion()}',
                ),
              ),
              ListTile(
                leading: const Icon(LucideIcons.refreshCw),
                title: const Text('Przelicz plan od nowa'),
                subtitle: const Text(
                  'Po wczytaniu kopii z PROD albo gdy liczby wyżej się różnią',
                ),
                enabled: !_busy,
                onTap: _reconvert,
              ),
            ],
          ),
          for (final budgetId in budgets) ...[
            SettingsSectionLabel(
              '${_budgetLabel(budgetId)} — średnio miesięcznie (stary → nowy)',
            ),
            SettingsGroup(
              children: [
                for (final y in r.years.where((y) => y.budgetId == budgetId))
                  ListTile(
                    title: Text('${y.year}'),
                    subtitle: Text(
                      'Wpływy: ${_avg(y.oldIncome)} → ${_avg(y.newIncome)}\n'
                      'Wydatki: ${_avg(y.oldExpense)} → ${_avg(y.newExpense)}',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ),
          ],
          SettingsSectionLabel('Różne sumy roku (${r.mismatches.length})'),
          SettingsGroup(
            children: [
              if (r.mismatches.isEmpty)
                const ListTile(
                  title: Text('Brak różnic'),
                  subtitle: Text(
                    'Każda pozycja ma w nowym planie tę samą sumę roku',
                  ),
                ),
              for (final m in r.mismatches)
                ListTile(
                  title: Text('${m.name} (${_budgetLabel(m.budgetId)})'),
                  subtitle: Text(
                    '${m.year}: ${budgetNf.format(m.oldTotal)} → '
                    '${budgetNf.format(m.newTotal)}'
                    '${curLabelSuffix(m.currency.label)}\n${m.detail}',
                  ),
                  isThreeLine: true,
                ),
            ],
          ),
          ..._notesSection(
            'Karta — zostaje do przejrzenia',
            notes.notesOf(PlanNoteKind.cardKept),
          ),
          ..._notesSection('Pominięte', notes.notesOf(PlanNoteKind.skipped)),
          ..._notesSection('Uwagi', notes.notesOf(PlanNoteKind.remark)),
          const SettingsSectionLabel('Bieżące — bez zmian'),
          SettingsGroup(
            children: [
              for (final budgetId in budgets)
                ListTile(
                  title: Text(_budgetLabel(budgetId)),
                  trailing: Text(
                    '${notes.notesOf(PlanNoteKind.spendingKept).where((n) => n.budgetId == budgetId).length} poz.',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _notesSection(String title, Iterable<PlanConversionNote> notes) {
    final list = notes.toList();
    if (list.isEmpty) return const [];
    return [
      SettingsSectionLabel('$title (${list.length})'),
      SettingsGroup(
        children: [
          for (final n in list)
            ListTile(
              title: Text('${n.name} (${_budgetLabel(n.budgetId)})'),
              subtitle: Text(n.message),
            ),
        ],
      ),
    ];
  }
}
