import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/plan_controller.dart';
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_icons.dart'
    show paymentMethodIcon, paymentMethodIconColor;
import '../widgets/filter_bars.dart' show kMonthsShort;
import '../widgets/form_action_bar.dart';
import '../widgets/month_picker_dialog.dart';
import '../widgets/plan_widgets.dart' show planMonthLabel;

/// Formularz pozycji planu (ADR-035).
///
/// Przy dodawaniu: dane wspólne, kwota i miesiące, w których pozycja ma
/// obowiązywać — kwota trafia do każdego zaznaczonego miesiąca. Przy edycji
/// tylko dane wspólne i okres: miesiące i ich kwoty zmienia się
/// w szczegółach pozycji, gdzie widać każdy z osobna.
///
/// Okres (od–do) chroni ratę przed wpisaniem po spłacie i pozycję przed
/// wpisaniem przed startem: miesięcy poza nim nie da się wypełnić.
class PlanPositionFormScreen extends StatefulWidget {
  final PlanPosition? existing;
  final int? initialYear;
  final int? initialMonth;

  const PlanPositionFormScreen({
    super.key,
    this.existing,
    this.initialYear,
    this.initialMonth,
  });

  @override
  State<PlanPositionFormScreen> createState() => _PlanPositionFormScreenState();
}

class _PlanPositionFormScreenState extends State<PlanPositionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _amount = TextEditingController();
  late final TextEditingController _day;
  late final TextEditingController _note;
  late PlanKind _kind;
  late Currency _currency;
  String? _categoryId;
  String? _paymentMethod;
  late int _gridYear;
  final Set<String> _months = {};
  String? _periodStart;
  String? _periodEnd;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final plan = context.read<PlanController>();
    _name = TextEditingController(text: e?.name ?? '');
    _day = TextEditingController(text: e?.day?.toString() ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _kind = e?.kind ?? PlanKind.expense;
    _currency = e?.currency ?? plan.target;
    _categoryId = e?.categoryId;
    _paymentMethod = e?.paymentMethod;
    _periodStart = e?.periodStart;
    _periodEnd = e?.periodEnd;
    _gridYear = widget.initialYear ?? plan.today.year;
    if (!_isEditing) {
      final m = widget.initialMonth;
      if (m != null) {
        _months.add(planMonthKey(_gridYear, m));
      } else {
        _selectYear(_gridYear);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    _note.dispose();
    super.dispose();
  }

  void _selectYear(int year) {
    for (var m = 1; m <= 12; m++) {
      final k = planMonthKey(year, m);
      if (_inPeriod(k)) _months.add(k);
    }
  }

  bool _inPeriod(String key) =>
      (_periodStart == null || key.compareTo(_periodStart!) >= 0) &&
      (_periodEnd == null || key.compareTo(_periodEnd!) <= 0);

  DateTime _monthOf(String key) =>
      DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5)));

  Future<void> _pickPeriod({required bool start}) async {
    final today = context.read<PlanController>().today;
    final current = start ? _periodStart : _periodEnd;
    final picked = await showMonthPicker(
      context,
      initialMonth: current != null
          ? _monthOf(current)
          : DateTime(_gridYear, today.month),
      today: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final key = planMonthKey(picked.year, picked.month);
      if (start) {
        _periodStart = key;
      } else {
        _periodEnd = key;
      }
      _months.removeWhere((k) => !_inPeriod(k));
    });
  }

  /// Co trzy miesiące od pierwszego zaznaczonego w pokazanym roku (albo od
  /// stycznia) — kwartał nie zawsze zaczyna się w styczniu.
  void _quarterly() {
    final first =
        [
          for (var m = 1; m <= 12; m++)
            if (_months.contains(planMonthKey(_gridYear, m))) m,
        ].firstOrNull ??
        1;
    _months.removeWhere((k) => k.startsWith('$_gridYear-'));
    for (var m = first; m <= 12; m += 3) {
      final k = planMonthKey(_gridYear, m);
      if (_inPeriod(k)) _months.add(k);
    }
  }

  /// Raty: N kolejnych miesięcy od pierwszego zaznaczonego (także przez
  /// granicę roku) — rata 09.2026–08.2027 to jedna pozycja. Ustawia też
  /// okres pozycji na te miesiące, więc rata nie wydłuży się przez pomyłkę.
  Future<void> _installments() async {
    final ctrl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Liczba rat'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Ile miesięcy',
            helperText: 'Od pierwszego zaznaczonego miesiąca',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v != null && v > 0 && v <= 600) Navigator.pop(dctx, v);
            },
            child: const Text('Zaznacz'),
          ),
        ],
      ),
    );
    if (n == null) return;
    final start =
        (_months.toList()..sort()).firstOrNull ?? planMonthKey(_gridYear, 1);
    final y = int.parse(start.substring(0, 4));
    final m = int.parse(start.substring(5));
    setState(() {
      _months.clear();
      for (var i = 0; i < n; i++) {
        final d = DateTime(y, m + i);
        _months.add(planMonthKey(d.year, d.month));
      }
      final last = DateTime(y, m + n - 1);
      _periodStart = start;
      _periodEnd = planMonthKey(last.year, last.month);
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  /// Zawężenie okresu edytowanej pozycji, gdy poza nowym okresem są kwoty —
  /// zapis by je usunął, więc najpierw pytamy.
  Future<bool> _confirmTrim(PlanPosition e) async {
    final outside = e.monthsOutsidePeriod(start: _periodStart, end: _periodEnd);
    if (outside.isEmpty) return true;
    final shown = outside.take(6).map(planMonthLabel).join(', ');
    final more = outside.length > 6 ? ' i ${outside.length - 6} więcej' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Usunąć ${outside.length} mies. poza okresem?'),
        content: Text(
          'Poza nowym okresem pozycja ma kwoty: $shown$more. Zapis usunie je '
          'z planu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Usuń i zapisz'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_periodStart != null &&
        _periodEnd != null &&
        _periodEnd!.compareTo(_periodStart!) < 0) {
      _snack('Koniec okresu jest przed jego startem');
      return;
    }
    if (!_isEditing && _months.isEmpty) {
      _snack('Zaznacz choć jeden miesiąc');
      return;
    }
    final e = widget.existing;
    if (e != null && !await _confirmTrim(e)) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final plan = context.read<PlanController>();
    final day = int.tryParse(_day.text.trim());
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (e != null) {
      await plan.update(
        e.copyWith(
          name: _name.text.trim(),
          kind: _kind,
          currency: _currency,
          categoryId: _categoryId,
          clearCategoryId: _categoryId == null,
          paymentMethod: _paymentMethod,
          clearPaymentMethod: _paymentMethod == null,
          day: day,
          clearDay: day == null,
          note: note,
          clearNote: note == null,
          periodStart: _periodStart,
          clearPeriodStart: _periodStart == null,
          periodEnd: _periodEnd,
          clearPeriodEnd: _periodEnd == null,
        ),
      );
    } else {
      final amount = double.parse(
        _amount.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'),
      );
      await plan.create(
        name: _name.text.trim(),
        kind: _kind,
        currency: _currency,
        months: {
          for (final k in _months)
            if (_inPeriod(k)) k: PlanMonth(amount: amount),
        },
        categoryId: _categoryId,
        paymentMethod: _paymentMethod,
        day: day,
        note: note,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    final theme = Theme.of(context);
    final c = context.semanticColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FormActionBar(
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        onSave: _saving ? null : _submit,
      ),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edytuj pozycję' : 'Nowa pozycja planu'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, kFormActionBarSpace),
          children: [
            const _Label('Rodzaj'),
            Wrap(
              spacing: 8,
              children: [
                for (final (kind, label) in const [
                  (PlanKind.expense, 'Wydatek'),
                  (PlanKind.income, 'Wpływ'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nazwa *'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Wymagane' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!_isEditing) ...[
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _amount,
                      decoration: const InputDecoration(
                        labelText: 'Kwota w miesiącu *',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final parsed = double.tryParse(
                          (v ?? '')
                              .replaceAll(RegExp(r'\s'), '')
                              .replaceAll(',', '.'),
                        );
                        return parsed == null || parsed < 0
                            ? 'Nieprawidłowa kwota'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _day,
              decoration: const InputDecoration(
                labelText: 'Dzień płatności (opcjonalnie)',
                helperText: 'Bez dnia pozycja nie pojawi się na kalendarzu',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final d = int.tryParse(v.trim());
                return d == null || d < 1 || d > 31 ? 'Dzień 1–31' : null;
              },
            ),
            const SizedBox(height: 24),
            const _Label('Okres (opcjonalnie)'),
            Row(
              children: [
                Expanded(
                  child: _PeriodField(
                    label: 'Od',
                    value: _periodStart,
                    onTap: () => _pickPeriod(start: true),
                    onClear: () => setState(() => _periodStart = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PeriodField(
                    label: 'Do',
                    value: _periodEnd,
                    onTap: () => _pickPeriod(start: false),
                    onClear: () => setState(() => _periodEnd = null),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Rata: od pierwszej do ostatniej raty; umowa: od startu. '
                'Miesięcy poza okresem nie da się wypełnić.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: c.textMuted,
                ),
              ),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 24),
              const _Label('Miesiące'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.chevronLeft),
                    onPressed: () => setState(() => _gridYear--),
                  ),
                  Expanded(
                    child: Text(
                      '$_gridYear · zaznaczone: ${_months.length}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.chevronRight),
                    onPressed: () => setState(() => _gridYear++),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var m = 1; m <= 12; m++)
                    FilterChip(
                      label: Text(kMonthsShort[m - 1]),
                      selected: _months.contains(planMonthKey(_gridYear, m)),
                      // Poza okresem — wyszarzony, nie do zaznaczenia.
                      onSelected: _inPeriod(planMonthKey(_gridYear, m))
                          ? (on) => setState(() {
                              final k = planMonthKey(_gridYear, m);
                              on ? _months.add(k) : _months.remove(k);
                            })
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Cały rok'),
                    onPressed: () => setState(() => _selectYear(_gridYear)),
                  ),
                  ActionChip(
                    label: const Text('Co kwartał'),
                    onPressed: () => setState(_quarterly),
                  ),
                  ActionChip(
                    label: const Text('Raty…'),
                    onPressed: _installments,
                  ),
                  ActionChip(
                    label: const Text('Wyczyść'),
                    onPressed: () => setState(_months.clear),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            const _Label('Kategoria'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Brak'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
                for (final cat in storage.getCategories())
                  FilterChip(
                    label: Text(cat.name),
                    selected: _categoryId == cat.id,
                    selectedColor: cat.color.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _categoryId = cat.id),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const _Label('Metoda płatności'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Brak'),
                  selected: _paymentMethod == null,
                  onSelected: (_) => setState(() => _paymentMethod = null),
                ),
                for (final pm in storage.getPaymentMethods())
                  FilterChip(
                    avatar: Icon(
                      paymentMethodIcon(pm),
                      size: 16,
                      color: _paymentMethod == pm.name
                          ? AppColors.onAccent
                          : paymentMethodIconColor(pm, c),
                    ),
                    label: Text(pm.name),
                    selected: _paymentMethod == pm.name,
                    onSelected: (_) => setState(() => _paymentMethod = pm.name),
                  ),
              ],
            ),
            const SizedBox(height: 24),
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

/// Pole okresu: miesiąc z wyboru albo „—", z krzyżykiem do wyczyszczenia.
class _PeriodField extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _PeriodField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.control),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: value == null
            ? const Icon(LucideIcons.calendar, size: 18)
            : IconButton(
                tooltip: 'Bez ograniczenia',
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: onClear,
              ),
      ),
      child: Text(value == null ? '—' : planMonthLabel(value!)),
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: context.semanticColors.textSecondary,
      ),
    ),
  );
}
