import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/budget_controller.dart';
import '../controllers/plan_controller.dart';
import '../models/subscription.dart';
import '../services/plan_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/budget_picker.dart' show moveOrCopyPositions;
import '../widgets/budget_widgets.dart' show budgetNf;
import '../widgets/form_action_bar.dart';

/// Pożyczka z karty kredytowej w planie (ADR-035 §4): pieniądze przychodzą
/// w miesiącu użycia karty, a spłata wychodzi po okresie bezodsetkowym.
///
/// Spłata ma osobną kwotę, bo bywa wyższa (prowizja, odsetki — w wielu
/// bankach wypłata gotówki z karty nie ma okresu bezodsetkowego).
class CardLoanFormScreen extends StatefulWidget {
  /// Istniejąca para do edycji; `null` = nowa pożyczka.
  final String? linkId;

  const CardLoanFormScreen({super.key, this.linkId});

  @override
  State<CardLoanFormScreen> createState() => _CardLoanFormScreenState();
}

class _CardLoanFormScreenState extends State<CardLoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Pożyczka z karty');
  final _amount = TextEditingController();
  final _repaymentAmount = TextEditingController();
  final _note = TextEditingController();
  late List<PaymentMethod> _cards;
  String? _card;
  late Currency _currency;
  late DateTime _useDate;
  late DateTime _repaymentDate;

  /// Czy kwotę spłaty zmieniono ręcznie — wtedy przestaje iść za pożyczką.
  bool _repaymentEdited = false;
  bool _saving = false;

  final _df = DateFormat('d MMMM yyyy', 'pl');

  @override
  void initState() {
    super.initState();
    final plan = context.read<PlanController>();
    // Karty budżetu pożyczki (ADR-038): edytowanej albo aktywnego.
    final budgetId = widget.linkId == null
        ? plan.budgetId
        : plan.loanPair(widget.linkId!).loan?.budgetId ?? plan.budgetId;
    _cards = context
        .read<StorageService>()
        .getPaymentMethods(budgetId)
        .where((pm) => pm.isCreditCard)
        .toList();
    _currency = plan.target;
    _useDate = plan.today;
    _card = _cards.firstOrNull?.name;
    _repaymentDate = PlanService.repaymentDateFor(_useDate, _grace(_card));

    final link = widget.linkId;
    if (link != null) {
      final pair = plan.loanPair(link);
      final loan = pair.loan;
      final rep = pair.repayment;
      if (loan != null) {
        _name.text = loan.name;
        _card = loan.paymentMethod ?? _card;
        _currency = loan.currency;
        _note.text = loan.note ?? '';
        final m = loan.months.entries.firstOrNull;
        if (m != null) {
          _useDate = _dateOf(m.key, loan.dayIn(m.key));
          _amount.text = budgetNf.format(m.value.amount);
        }
      }
      final r = rep?.months.entries.firstOrNull;
      if (rep != null && r != null) {
        _repaymentDate = _dateOf(r.key, rep.dayIn(r.key));
        _repaymentAmount.text = budgetNf.format(r.value.amount);
        _repaymentEdited = true;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _repaymentAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime _dateOf(String monthKey, int? day) => DateTime(
    int.parse(monthKey.substring(0, 4)),
    int.parse(monthKey.substring(5)),
    day ?? 1,
  );

  int? _grace(String? card) =>
      _cards.where((pm) => pm.name == card).firstOrNull?.graceDays;

  double? _parse(String raw) =>
      double.tryParse(raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

  void _recomputeRepayment() {
    _repaymentDate = PlanService.repaymentDateFor(_useDate, _grace(_card));
  }

  Future<void> _pickDate({required bool repayment}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: repayment ? _repaymentDate : _useDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked == null) return;
    setState(() {
      if (repayment) {
        _repaymentDate = picked;
      } else {
        _useDate = picked;
        _recomputeRepayment();
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final card = _card;
    if (card == null) return;
    final amount = _parse(_amount.text)!;
    final repayment = _repaymentEdited
        ? (_parse(_repaymentAmount.text) ?? amount)
        : amount;
    setState(() => _saving = true);
    await context.read<PlanController>().saveCardLoan(
      linkId: widget.linkId,
      name: _name.text.trim(),
      card: card,
      currency: _currency,
      useDate: _useDate,
      amount: amount,
      repaymentDate: _repaymentDate,
      repaymentAmount: repayment,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Cała pożyczka (pożyczka i spłata) do innego budżetu (ADR-037).
  Future<void> _toBudget({required bool copy}) async {
    final loan = context.read<PlanController>().loanPair(widget.linkId!).loan;
    if (loan == null) return;
    final done = await moveOrCopyPositions(
      context,
      {loan.id},
      copy: copy,
      fromBudgetId: loan.budgetId,
      what: 'pożyczkę',
    );
    if (done && mounted) Navigator.of(context).pop();
  }

  /// Duplikat całej pożyczki w tym samym budżecie (z dopiskiem „(kopia)") i od
  /// razu jej formularz — z zapisanej wersji, jak przy przeniesieniu.
  Future<void> _duplicate() async {
    final loan = context.read<PlanController>().loanPair(widget.linkId!).loan;
    if (loan == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final link = await context.read<BudgetController>().duplicateLoan(loan.id);
    if (link == null || !mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => CardLoanFormScreen(linkId: link)),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Utworzono kopię: „${loan.name}$kCopySuffix"')),
      );
  }

  Future<void> _delete() async {
    final plan = context.read<PlanController>();
    final pair = plan.loanPair(widget.linkId!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Usunąć pożyczkę?'),
        content: const Text('Zniknie z planu razem ze spłatą.'),
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
    await plan.deleteAll({?pair.loan?.id, ?pair.repayment?.id});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FormActionBar(
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        onSave: _saving || _cards.isEmpty ? null : _submit,
      ),
      appBar: AppBar(
        title: Text(
          widget.linkId == null ? 'Pożyczka z karty' : 'Edytuj pożyczkę',
        ),
        actions: [
          if (widget.linkId != null) ...[
            IconButton(
              tooltip: 'Usuń',
              icon: const Icon(LucideIcons.trash2),
              onPressed: _delete,
            ),
            PopupMenuButton<String>(
              tooltip: 'Więcej',
              onSelected: (v) => v == 'duplicate'
                  ? _duplicate()
                  : _toBudget(copy: v == 'copy'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplikuj pożyczkę'),
                ),
                PopupMenuItem(
                  value: 'move',
                  child: Text('Przenieś do budżetu…'),
                ),
                PopupMenuItem(value: 'copy', child: Text('Kopiuj do budżetu…')),
              ],
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, kFormActionBarSpace),
          children: [
            if (_cards.isEmpty)
              Card(
                child: ListTile(
                  leading: Icon(LucideIcons.info, color: c.warning),
                  title: const Text('Brak karty kredytowej'),
                  subtitle: const Text(
                    'Oznacz metodę płatności jako kartę kredytową (z okresem '
                    'bezodsetkowym) w Ustawieniach → Metody płatności.',
                  ),
                ),
              )
            else ...[
              Text(
                'Karta',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final pm in _cards)
                    ChoiceChip(
                      label: Text(
                        pm.graceDays != null
                            ? '${pm.name} · ${pm.graceDays} dni'
                            : pm.name,
                      ),
                      selected: _card == pm.name,
                      onSelected: (_) => setState(() {
                        _card = pm.name;
                        _recomputeRepayment();
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nazwa *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Wymagane' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(labelText: 'Kwota *'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final x = _parse(v ?? '');
                      return x == null || x <= 0 ? 'Nieprawidłowa kwota' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<Currency>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Waluta'),
                    items: [
                      for (final cur in Currency.values)
                        DropdownMenuItem(value: cur, child: Text(cur.label)),
                    ],
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.calendar),
              title: Text(_df.format(_useDate)),
              subtitle: const Text('Kiedy bierzesz pieniądze z karty'),
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: () => _pickDate(repayment: false),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.calendarClock),
              title: Text('Spłata ${_df.format(_repaymentDate)}'),
              subtitle: Text(
                _grace(_card) != null
                    ? 'Okres bezodsetkowy karty: ${_grace(_card)} dni'
                    : 'Karta bez okresu bezodsetkowego — przyjęto 30 dni',
              ),
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: () => _pickDate(repayment: true),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inna kwota spłaty'),
              subtitle: const Text('Np. z prowizją albo odsetkami'),
              value: _repaymentEdited,
              onChanged: (v) => setState(() {
                _repaymentEdited = v;
                if (v && _repaymentAmount.text.isEmpty) {
                  _repaymentAmount.text = _amount.text;
                }
              }),
            ),
            if (_repaymentEdited)
              TextFormField(
                controller: _repaymentAmount,
                decoration: const InputDecoration(labelText: 'Kwota spłaty'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final x = _parse(v ?? '');
                  return x == null || x < 0 ? 'Nieprawidłowa kwota' : null;
                },
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Notatka'),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
