import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../models/quick_add_templates.dart';
import '../controllers/budget_controller.dart';
import '../controllers/subscription_controller.dart';
import '../widgets/budget_picker.dart' show showBudgetTargetSheet;
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cycle_months_picker.dart';
import '../widgets/form_action_bar.dart';

class AddSubscriptionScreen extends StatefulWidget {
  final Subscription? existing;

  /// Budżet nowej subskrypcji — ten, na którym stoi użytkownik (ADR-037);
  /// domyślnie aktywny. Formularz nie ma wyboru budżetu, jak pozycja planu
  /// i pożyczka: zmiana budżetu to menu ⋮ „Przenieś do / Kopiuj do".
  final String? initialBudgetId;

  const AddSubscriptionScreen({super.key, this.existing, this.initialBudgetId});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _cancelUrlCtrl;

  Currency _currency = Currency.PLN;
  BillingCycle _cycle = BillingCycle.monthly;

  /// Miesiące płatności dla cyklu „wybrane miesiące" (ADR-020).
  List<int> _cycleMonths = const [];

  /// Miesiące do zapisu: tylko dla swojego cyklu; pusty wybór dostaje domyślne
  /// „co 2 miesiące" od miesiąca startu, żeby pozycja nie wypadła z kalendarza.
  List<int>? get _effCycleMonths => _cycle == BillingCycle.monthsOfYear
      ? (_cycleMonths.isEmpty
            ? CycleMonthsPicker.everyN(2, _startDate.month)
            : _cycleMonths)
      : null;
  String? _categoryId;
  DateTime _startDate = DateTime.now();
  int? _sharedWith;
  String? _paymentMethod;
  bool _isTrial = false;
  DateTime? _trialEndDate;

  /// Budżet NOWEJ subskrypcji; edycja budżetu nie zmienia (menu ⋮).
  late final String _budgetId;
  late final TextEditingController _postTrialAmountCtrl;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existing != null;

  /// Przenosi albo kopiuje zapisaną subskrypcję do innego budżetu (ADR-037).
  /// Działa na wersji zapisanej — niezapisane zmiany w formularzu przepadają,
  /// więc po akcji formularz się zamyka.
  Future<void> _moveOrCopy({required bool copy}) async {
    final sub = widget.existing!;
    final budgets = context.read<BudgetController>();
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: sub.budgetId,
      title: copy
          ? 'Kopiuj „${sub.name}" do budżetu…'
          : 'Przenieś „${sub.name}" do budżetu…',
      subtitle: copy ? 'Kopia ma własne przypomnienia.' : null,
    );
    if (target == null || !mounted) return;
    if (copy) {
      await budgets.copySubscriptions([sub], target.budget.id);
    } else {
      await budgets.moveSubscriptions([sub], target.budget.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${copy ? 'Skopiowano' : 'Przeniesiono'} „${sub.name}" do '
          '„${target.budget.name}"',
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  /// Duplikat w tym samym budżecie (z dopiskiem „(kopia)") i od razu jego
  /// formularz. Jak przy przeniesieniu — z zapisanej wersji.
  Future<void> _duplicate() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final copy = await context.read<BudgetController>().duplicateSubscription(
      widget.existing!,
    );
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => AddSubscriptionScreen(existing: copy)),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Utworzono kopię: „${copy.name}"')),
      );
  }

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _budgetId =
        widget.initialBudgetId ?? context.read<BudgetController>().budgetId;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _amountCtrl = TextEditingController(
      text: s != null ? s.amount.toStringAsFixed(2) : '',
    );
    _descCtrl = TextEditingController(text: s?.description ?? '');
    _cancelUrlCtrl = TextEditingController(text: s?.cancellationUrl ?? '');
    _postTrialAmountCtrl = TextEditingController(
      text: s?.postTrialAmount != null
          ? s!.postTrialAmount!.toStringAsFixed(2)
          : '',
    );
    if (s != null) {
      _currency = s.currency;
      _cycle = s.billingCycle;
      _cycleMonths = s.cycleMonths ?? const [];
      _categoryId = s.categoryId;
      _startDate = s.startDate;
      _sharedWith = s.sharedWith;
      _paymentMethod = s.paymentMethod;
      _isTrial = s.isTrial;
      _trialEndDate = s.trialEndDate;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _cancelUrlCtrl.dispose();
    _postTrialAmountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    final categories = storage.getCategories();
    final paymentMethods = storage.getPaymentMethods();
    // Tolerancja orphana: jeśli istniejąca subskrypcja ma wartość spoza
    // aktualnej listy (np. po usunięciu metody albo imporcie starego backupu),
    // pokazujemy ją w dropdownie, żeby nie "znikła" po wejściu w edycję.
    final hasOrphan =
        _paymentMethod != null &&
        !paymentMethods.any((pm) => pm.name == _paymentMethod);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FormActionBar(
        onCancel: _isSubmitting ? null : () => Navigator.of(context).pop(),
        onSave: _isSubmitting ? null : _submit,
      ),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edytuj subskrypcję' : 'Dodaj subskrypcję'),
        actions: [
          if (_isEditing)
            PopupMenuButton<String>(
              tooltip: 'Więcej',
              onSelected: (v) => v == 'duplicate'
                  ? _duplicate()
                  : _moveOrCopy(copy: v == 'copy'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplikuj subskrypcję'),
                ),
                PopupMenuItem(
                  value: 'move',
                  child: Text('Przenieś do budżetu…'),
                ),
                PopupMenuItem(value: 'copy', child: Text('Kopiuj do budżetu…')),
              ],
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, kFormActionBarSpace),
          children: [
            if (!_isEditing) ...[
              _QuickAddBar(onSelected: _applyTemplate),
              const SizedBox(height: 16),
            ],
            _SectionLabel('Podstawowe'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nazwa *'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Wymagane' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Opis (opcjonalnie)',
              ),
            ),
            const SizedBox(height: 24),

            _SectionLabel('Płatność'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(labelText: 'Kwota *'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Wymagane';
                      final parsed = double.tryParse(v.replaceAll(',', '.'));
                      if (parsed == null || parsed <= 0) {
                        return 'Nieprawidłowa kwota';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<Currency>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Waluta'),
                    items: Currency.values
                        .map(
                          (c) =>
                              DropdownMenuItem(value: c, child: Text(c.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BillingCycle>(
              initialValue: _cycle,
              decoration: const InputDecoration(
                labelText: 'Cykl rozliczeniowy',
              ),
              items: BillingCycle.values
                  .map(
                    (c) =>
                        DropdownMenuItem(value: c, child: Text(_cycleLabel(c))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _cycle = v!),
            ),
            if (_cycle == BillingCycle.monthsOfYear) ...[
              const SizedBox(height: 12),
              CycleMonthsPicker(
                months: _cycleMonths,
                anchorMonth: _startDate.month,
                onChanged: (m) => setState(() => _cycleMonths = m),
              ),
            ],
            const SizedBox(height: 24),

            _SectionLabel('Kategoria'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Brak'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
                ...categories.map(
                  (cat) => FilterChip(
                    label: Text(cat.name),
                    selected: _categoryId == cat.id,
                    selectedColor: cat.color.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _categoryId = cat.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _SectionLabel('Data startu'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.calendar),
              title: Text(DateFormat('d MMMM yyyy', 'pl').format(_startDate)),
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: _pickDate,
            ),
            const SizedBox(height: 24),

            _SectionLabel('Free trial'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Okres próbny'),
              subtitle: const Text('Subskrypcja na trialu'),
              secondary: Icon(
                LucideIcons.clock,
                color: _isTrial ? context.semanticColors.trial : null,
              ),
              value: _isTrial,
              onChanged: (v) => setState(() {
                _isTrial = v;
                if (v && _amountCtrl.text.isEmpty) {
                  _amountCtrl.text = '0.00';
                }
              }),
            ),
            if (_isTrial) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.calendarClock),
                title: Text(
                  _trialEndDate != null
                      ? DateFormat('d MMMM yyyy', 'pl').format(_trialEndDate!)
                      : 'Wybierz datę końca triala',
                ),
                subtitle: _trialEndDate != null
                    ? Text(
                        'Za ${_trialEndDate!.difference(DateTime.now()).inDays} dni',
                      )
                    : null,
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _pickTrialEndDate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _postTrialAmountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kwota po trialu',
                  hintText: 'np. 49.99 (puste = ta sama co kwota)',
                  prefixIcon: Icon(LucideIcons.arrowRight),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final parsed = double.tryParse(v.replaceAll(',', '.'));
                  if (parsed == null || parsed < 0) {
                    return 'Nieprawidłowa kwota';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 24),

            _SectionLabel('Opcjonalne'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _cancelUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Link do anulowania',
                hintText: 'https://...',
                prefixIcon: Icon(LucideIcons.link),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),

            // Wspólna subskrypcja
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _sharedWith,
                    decoration: const InputDecoration(
                      labelText: 'Dzielona na',
                      prefixIcon: Icon(LucideIcons.users),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Nie dzielona'),
                      ),
                      for (int i = 2; i <= 10; i++)
                        DropdownMenuItem(value: i, child: Text('$i osób')),
                    ],
                    onChanged: (v) => setState(() => _sharedWith = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Metoda płatności
            DropdownButtonFormField<String?>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Metoda płatności',
                prefixIcon: Icon(LucideIcons.creditCard),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Nie wybrano')),
                ...paymentMethods.map(
                  (pm) =>
                      DropdownMenuItem(value: pm.name, child: Text(pm.name)),
                ),
                if (hasOrphan)
                  DropdownMenuItem(
                    value: _paymentMethod,
                    child: Text('${_paymentMethod!} (usunięta)'),
                  ),
              ],
              onChanged: (v) => setState(() => _paymentMethod = v),
            ),
            const SizedBox(height: 32),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _toggleActive,
                icon: Icon(
                  widget.existing!.isActive
                      ? LucideIcons.xCircle
                      : LucideIcons.checkCircle,
                ),
                label: Text(
                  widget.existing!.isActive
                      ? 'Anuluj subskrypcję'
                      : 'Reaktywuj subskrypcję',
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _confirmDelete(context),
                icon: Icon(LucideIcons.trash2, color: AppColors.negative),
                label: Text(
                  'Usuń subskrypcję',
                  style: TextStyle(color: AppColors.negative),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.negative),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń subskrypcję'),
        content: Text(
          'Czy na pewno chcesz trwale usunąć "${widget.existing!.name}"?\n\n'
          'Ta operacja jest nieodwracalna.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(ctx);
              await context.read<SubscriptionController>().delete(
                widget.existing!.id,
              );
              if (mounted) navigator.pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive() async {
    final ctrl = context.read<SubscriptionController>();
    await ctrl.toggleActive(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _applyTemplate(SubscriptionTemplate t) {
    setState(() {
      _nameCtrl.text = t.name;
      _amountCtrl.text = t.amount.toStringAsFixed(2);
      _currency = t.currency;
      _cycle = t.billingCycle;
      _categoryId = t.categoryId;
    });
  }

  Future<void> _pickTrialEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _trialEndDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: 'Data końca triala',
    );
    if (picked != null) setState(() => _trialEndDate = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final amount = double.parse(_amountCtrl.text.replaceAll(',', '.'));
    final ctrl = context.read<SubscriptionController>();
    final storage = context.read<StorageService>();

    try {
      final postTrialAmt = _postTrialAmountCtrl.text.trim().isNotEmpty
          ? double.tryParse(_postTrialAmountCtrl.text.replaceAll(',', '.'))
          : null;

      if (_isEditing) {
        // Pobierz aktualny obiekt z cache (świeży stan)
        final current =
            storage.getSubscription(widget.existing!.id) ?? widget.existing!;
        await ctrl.update(
          current.copyWith(
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            clearDescription: _descCtrl.text.trim().isEmpty,
            amount: amount,
            currency: _currency,
            billingCycle: _cycle,
            cycleMonths: _effCycleMonths,
            clearCycleMonths: _effCycleMonths == null,
            categoryId: _categoryId,
            startDate: _startDate,
            cancellationUrl: _cancelUrlCtrl.text.trim().isEmpty
                ? null
                : _cancelUrlCtrl.text.trim(),
            clearCancellationUrl: _cancelUrlCtrl.text.trim().isEmpty,
            sharedWith: _sharedWith,
            clearSharedWith: _sharedWith == null,
            paymentMethod: _paymentMethod,
            clearPaymentMethod: _paymentMethod == null,
            isTrial: _isTrial,
            trialEndDate: _isTrial ? _trialEndDate : null,
            clearTrialEndDate: !_isTrial,
            postTrialAmount: _isTrial ? postTrialAmt : null,
            clearPostTrialAmount: !_isTrial,
          ),
        );
      } else {
        await ctrl.create(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          amount: amount,
          currency: _currency,
          billingCycle: _cycle,
          cycleMonths: _effCycleMonths,
          categoryId: _categoryId,
          startDate: _startDate,
          cancellationUrl: _cancelUrlCtrl.text.trim().isEmpty
              ? null
              : _cancelUrlCtrl.text.trim(),
          sharedWith: _sharedWith,
          paymentMethod: _paymentMethod,
          isTrial: _isTrial,
          trialEndDate: _isTrial ? _trialEndDate : null,
          postTrialAmount: _isTrial ? postTrialAmt : null,
          budgetId: _budgetId,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _cycleLabel(BillingCycle cycle) {
    return switch (cycle) {
      BillingCycle.weekly => 'Tygodniowo',
      BillingCycle.monthly => 'Miesięcznie',
      BillingCycle.quarterly => 'Kwartalnie',
      BillingCycle.yearly => 'Rocznie',
      BillingCycle.monthsOfYear => 'Wybrane miesiące',
      BillingCycle.custom => 'Własny cykl',
    };
  }
}

/// Poziomy pasek z chipami Quick Add + przycisk "wszystkie"
class _QuickAddBar extends StatelessWidget {
  final void Function(SubscriptionTemplate) onSelected;
  const _QuickAddBar({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.semanticColors;
    final popular = QuickAddTemplates.all.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SZYBKIE DODAWANIE',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            TextButton(
              onPressed: () => _showAll(context),
              child: const Text('Wszystkie'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: popular.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = popular[i];
              final color = Color(
                int.parse('FF${t.colorHex.replaceFirst('#', '')}', radix: 16),
              );
              return ActionChip(
                label: Text(t.name),
                avatar: CircleAvatar(backgroundColor: color, radius: 8),
                onPressed: () => onSelected(t),
                backgroundColor: c.surfaceVariant,
                side: BorderSide.none,
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAll(BuildContext context) {
    final grouped = QuickAddTemplates.byCategory;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Wybierz szablon',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: grouped.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        _catLabel(entry.key).toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              letterSpacing: 0.8,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((t) {
                          final color = Color(
                            int.parse(
                              'FF${t.colorHex.replaceFirst('#', '')}',
                              radix: 16,
                            ),
                          );
                          return ActionChip(
                            label: Text(t.name),
                            avatar: CircleAvatar(
                              backgroundColor: color,
                              radius: 8,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              onSelected(t);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _catLabel(String catId) => switch (catId) {
    'cat_streaming' => 'Streaming',
    'cat_music' => 'Muzyka',
    'cat_cloud' => 'Cloud',
    'cat_software' => 'Software',
    'cat_gaming' => 'Gaming',
    'cat_fitness' => 'Fitness',
    _ => 'Inne',
  };
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
