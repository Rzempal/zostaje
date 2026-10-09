import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/plan_controller.dart';
import '../models/budget_entry.dart' show BudgetEntry;
import '../models/plan_position.dart';
import '../models/subscription.dart';
import '../services/loan_math.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/budget_picker.dart' show moveOrCopyPositions;
import '../widgets/budget_widgets.dart' show budgetNf;
import '../widgets/category_icons.dart'
    show paymentMethodIcon, paymentMethodIconColor;
import '../widgets/form_action_bar.dart';
import '../widgets/frost_card.dart';
import '../widgets/month_picker_dialog.dart';
import '../widgets/plan_widgets.dart' show planMonthLabel;

/// Pożyczka ratalna (ADR-036): wypłata jako wpływ, raty jako spłata
/// w Pożyczkach i — opcjonalnie — zakup tego dnia jako zwykły wydatek
/// (raty w Pożyczkach, zakup w Wydatkach: ten sam koszt nie liczy się dwa
/// razy).
///
/// Kwota, liczba rat, rata i RRSO: z dowolnych trzech formularz liczy
/// czwartą (oznaczoną „wyliczone"), a gdy podano wszystkie — sprawdza, czy
/// się zgadzają, i podpowiada poprawkę.
class InstallmentLoanFormScreen extends StatefulWidget {
  /// Istniejąca pożyczka do edycji; `null` = nowa.
  final String? linkId;

  const InstallmentLoanFormScreen({super.key, this.linkId});

  @override
  State<InstallmentLoanFormScreen> createState() =>
      _InstallmentLoanFormScreenState();
}

class _InstallmentLoanFormScreenState extends State<InstallmentLoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _principal = TextEditingController();
  final _count = TextEditingController();
  final _installment = TextEditingController();
  final _rrso = TextEditingController();
  final _day = TextEditingController();
  final _purchaseAmount = TextEditingController();
  final _note = TextEditingController();
  late Currency _currency;
  late DateTime _drawdown;
  late String _firstMonth;

  /// Pierwsza rata i dzień raty idą za datą wypłaty, dopóki ich nie zmienić.
  bool _firstMonthTouched = false;
  bool _dayTouched = false;
  String? _paymentMethod;
  bool _withPurchase = true;
  String? _purchaseCategoryId;

  /// Pola wpisane przez formularz (wyliczone), nie przez użytkownika.
  final Set<LoanField> _auto = {};
  LoanCheck _check = const LoanNeedsMore(3);
  bool _saving = false;

  final _df = DateFormat('d MMMM yyyy', 'pl');
  static final _pct = NumberFormat('0.##', 'pl_PL');

  bool get _editing => widget.linkId != null;

  @override
  void initState() {
    super.initState();
    final plan = context.read<PlanController>();
    _currency = plan.target;
    _drawdown = plan.today;
    _firstMonth = _monthAfter(_drawdown);
    _day.text = '${_drawdown.day}';

    final link = widget.linkId;
    if (link != null) {
      final parts = plan.loanParts(link);
      final rep = parts.repayment;
      final t = rep?.loanTerms;
      if (rep != null && t != null) {
        _name.text = rep.name;
        _currency = rep.currency;
        _paymentMethod = rep.paymentMethod;
        _note.text = rep.note ?? '';
        _drawdown = t.drawdown;
        _firstMonth = t.firstMonth;
        _firstMonthTouched = true;
        _day.text = '${t.day}';
        _dayTouched = true;
        _principal.text = budgetNf.format(t.principal);
        _count.text = '${t.count}';
        _installment.text = budgetNf.format(t.installment);
        _rrso.text = _pct.format(t.rrso);
      }
      final purchase = parts.purchase;
      _withPurchase = purchase != null;
      if (purchase != null) {
        _purchaseCategoryId = purchase.categoryId;
        final amount = purchase.months.values.firstOrNull?.amount;
        if (amount != null &&
            t != null &&
            (amount - t.principal).abs() > 0.005) {
          _purchaseAmount.text = budgetNf.format(amount);
        }
      }
    }
    _check = _solve();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _principal,
      _count,
      _installment,
      _rrso,
      _day,
      _purchaseAmount,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _monthAfter(DateTime d) {
    final m = DateTime(d.year, d.month + 1);
    return planMonthKey(m.year, m.month);
  }

  TextEditingController _ctrl(LoanField f) => switch (f) {
    LoanField.principal => _principal,
    LoanField.count => _count,
    LoanField.installment => _installment,
    LoanField.rrso => _rrso,
  };

  /// Liczba z pola (spacje grupujące, także twarde z `budgetNf`, przecinek
  /// dziesiętny); `null` dla pustego albo nieczytelnego.
  double? _num(String raw) {
    final t = raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  int get _dayValue {
    final d = int.tryParse(_day.text.trim());
    return d == null || d < 1 || d > 31 ? _drawdown.day : d;
  }

  LoanSchedule get _schedule => LoanSchedule(
    drawdown: _drawdown,
    firstYear: int.parse(_firstMonth.substring(0, 4)),
    firstMonth: int.parse(_firstMonth.substring(5)),
    day: _dayValue,
  );

  LoanCheck _solve() {
    final bad = <String>[];
    void check(TextEditingController c, String name, bool ok) {
      if (c.text.trim().isNotEmpty && !ok) bad.add(name);
    }

    final p = _num(_principal.text);
    final n = _num(_count.text);
    final r = _num(_installment.text);
    final x = _num(_rrso.text);
    check(_principal, 'kwota', p != null);
    check(_count, 'liczba rat', n != null && n == n.roundToDouble());
    check(_installment, 'rata', r != null);
    check(_rrso, 'RRSO', x != null);
    if (bad.isNotEmpty) {
      return LoanInvalid('Nieprawidłowa wartość: ${bad.join(', ')}');
    }
    return LoanMath.solve(
      _schedule,
      principal: p,
      count: n?.toInt(),
      installment: r,
      rrso: x,
    );
  }

  /// Po każdej zmianie wyliczone wcześniej pole zwalnia się i liczy od nowa
  /// z aktualnych danych; gdy brakuje dokładnie jednej wartości, formularz
  /// ją wpisuje i oznacza jako wyliczoną.
  void _recompute() {
    for (final f in _auto) {
      _ctrl(f).text = '';
    }
    _auto.clear();
    final check = _solve();
    if (check case LoanComputed(:final field, :final value)) {
      _ctrl(field).text = switch (field) {
        LoanField.count => '${value.toInt()}',
        LoanField.rrso => _pct.format(value),
        _ => budgetNf.format(value),
      };
      _auto.add(field);
    }
    setState(() => _check = check);
  }

  void _userEdit(LoanField f) {
    _auto.remove(f);
    _recompute();
  }

  void _accept(LoanField f, double value) {
    _ctrl(f).text = f == LoanField.rrso
        ? _pct.format(value)
        : budgetNf.format(value);
    _auto.remove(f);
    _recompute();
  }

  Future<void> _pickDrawdown() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _drawdown,
      firstDate: DateTime(2015),
      lastDate: DateTime(2045),
    );
    if (picked == null) return;
    _drawdown = picked;
    if (!_firstMonthTouched) _firstMonth = _monthAfter(picked);
    if (!_dayTouched) _day.text = '${picked.day}';
    _recompute();
  }

  Future<void> _pickFirstMonth() async {
    final picked = await showMonthPicker(
      context,
      initialMonth: DateTime(
        int.parse(_firstMonth.substring(0, 4)),
        int.parse(_firstMonth.substring(5)),
      ),
      today: context.read<PlanController>().today,
    );
    if (picked == null) return;
    _firstMonth = planMonthKey(picked.year, picked.month);
    _firstMonthTouched = true;
    _recompute();
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final check = _check;
    if (check is LoanNeedsMore) {
      _snack(
        'Uzupełnij dane pożyczki — wpisz jeszcze ${check.missing} z czterech '
        'wartości',
      );
      return;
    }
    if (check is LoanInvalid) {
      _snack(check.message);
      return;
    }
    if (_firstMonth.compareTo(BudgetEntry.monthKeyOf(_drawdown)) < 0) {
      _snack('Pierwsza rata nie może być przed wypłatą');
      return;
    }
    final p = _num(_principal.text)!;
    final n = _num(_count.text)!.toInt();
    final r = _num(_installment.text)!;
    final x = _num(_rrso.text)!;
    if (check is LoanMismatch &&
        !await _confirm(
          'Dane się nie zgadzają',
          'Raty zapiszą się po ${budgetNf.format(r)}, a RRSO ${_pct.format(x)}% '
              'zostanie jako wartość z umowy.',
          'Zapisz mimo to',
        )) {
      return;
    }
    if (!mounted) return;
    final plan = context.read<PlanController>();
    final link = widget.linkId;
    if (link != null &&
        plan.loanInstallmentsEdited(link) &&
        !await _confirm(
          'Przeliczyć raty?',
          'Raty tej pożyczki były poprawiane ręcznie. Zapis przeliczy je od '
              'nowa z warunków.',
          'Przelicz',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final note = _note.text.trim();
    await plan.saveInstallmentLoan(
      linkId: link,
      name: _name.text.trim(),
      currency: _currency,
      paymentMethod: _paymentMethod,
      note: note.isEmpty ? null : note,
      terms: PlanLoanTerms(
        principal: p,
        count: n,
        installment: r,
        rrso: x,
        drawdown: DateTime(_drawdown.year, _drawdown.month, _drawdown.day),
        firstMonth: _firstMonth,
        day: _dayValue,
      ),
      purchase: _withPurchase
          ? (
              amount: _num(_purchaseAmount.text) ?? p,
              categoryId: _purchaseCategoryId,
            )
          : null,
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Cała pożyczka (wypłata, raty i zakup) do innego budżetu (ADR-037) —
  /// w zapisanej wersji; niezapisane zmiany przepadają, więc formularz się
  /// zamyka.
  Future<void> _toBudget({required bool copy}) async {
    final parts = context.read<PlanController>().loanParts(widget.linkId!);
    final any = parts.repayment ?? parts.loan;
    if (any == null) return;
    final done = await moveOrCopyPositions(
      context,
      {any.id},
      copy: copy,
      fromBudgetId: any.budgetId,
      what: 'pożyczkę',
    );
    if (done && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final plan = context.read<PlanController>();
    final link = widget.linkId!;
    final hasPurchase = plan.loanParts(link).purchase != null;
    var withPurchase = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) => AlertDialog(
          title: const Text('Usunąć pożyczkę?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Zniknie z planu razem z ratami.'),
              if (hasPurchase)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: withPurchase,
                  onChanged: (v) => setDialog(() => withPurchase = v ?? true),
                  title: const Text('Usuń też zakup z Wydatków'),
                ),
            ],
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
      ),
    );
    if (ok != true || !mounted) return;
    await plan.deleteLoan(link, withPurchase: hasPurchase && withPurchase);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final storage = context.read<StorageService>();

    Widget loanField(LoanField f, String label) {
      final auto = _auto.contains(f);
      return TextFormField(
        controller: _ctrl(f),
        keyboardType: TextInputType.numberWithOptions(
          decimal: f != LoanField.count,
        ),
        onChanged: (_) => _userEdit(f),
        style: auto ? TextStyle(color: c.primary) : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: auto ? 'wyliczone' : null,
          helperStyle: TextStyle(color: c.primary),
          isDense: true,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FormActionBar(
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        onSave: _saving ? null : _submit,
      ),
      appBar: AppBar(
        title: Text(_editing ? 'Edytuj pożyczkę ratalną' : 'Pożyczka ratalna'),
        actions: [
          if (_editing) ...[
            IconButton(
              tooltip: 'Usuń',
              icon: const Icon(LucideIcons.trash2),
              onPressed: _delete,
            ),
            PopupMenuButton<String>(
              tooltip: 'Więcej',
              onSelected: (v) => _toBudget(copy: v == 'copy'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'move',
                  child: Text('Przenieś do budżetu…'),
                ),
                PopupMenuItem(
                  value: 'copy',
                  child: Text('Kopiuj do budżetu…'),
                ),
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
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nazwa *',
                hintText: 'np. Odkurzacz na raty',
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Wymagane' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDrawdown,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data wypłaty (wpływ)',
                  suffixIcon: Icon(LucideIcons.calendar, size: 18),
                ),
                child: Text(_df.format(_drawdown)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: loanField(LoanField.principal, 'Kwota wypłacona'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<Currency>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Waluta',
                      isDense: true,
                    ),
                    items: [
                      for (final cur in Currency.values)
                        DropdownMenuItem(value: cur, child: Text(cur.label)),
                    ],
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: loanField(LoanField.count, 'Liczba rat')),
                const SizedBox(width: 10),
                Expanded(child: loanField(LoanField.installment, 'Rata')),
                const SizedBox(width: 10),
                Expanded(child: loanField(LoanField.rrso, 'RRSO %')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Wpisz dowolne trzy z czterech: kwota, liczba rat, rata, RRSO '
                '— czwartą policzę. Gdy wpiszesz wszystkie, sprawdzę, czy się '
                'zgadzają.',
                style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickFirstMonth,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Pierwsza rata',
                        suffixIcon: Icon(LucideIcons.calendarDays, size: 18),
                      ),
                      child: Text(planMonthLabel(_firstMonth)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _day,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Dzień raty'),
                    onChanged: (_) {
                      _dayTouched = true;
                      _recompute();
                    },
                    validator: (v) {
                      final d = int.tryParse((v ?? '').trim());
                      return d == null || d < 1 || d > 31
                          ? 'Dzień 1–31'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Konto spłaty',
              style: theme.textTheme.labelLarge?.copyWith(
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 20),
            FrostCard(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _withPurchase,
                    onChanged: (v) => setState(() => _withPurchase = v ?? true),
                    title: Text(
                      _name.text.trim().isEmpty
                          ? 'Dodaj zakup tego dnia'
                          : 'Dodaj zakup „${_name.text.trim()}" tego dnia',
                    ),
                    subtitle: const Text(
                      'Zakup idzie do Wydatków, raty — do Pożyczek, więc ten '
                      'sam koszt nie liczy się dwa razy.',
                    ),
                  ),
                  if (_withPurchase) ...[
                    TextFormField(
                      controller: _purchaseAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Kwota zakupu',
                        hintText: '= kwota pożyczki',
                        isDense: true,
                      ),
                      validator: (v) {
                        if (!_withPurchase || (v ?? '').trim().isEmpty) {
                          return null;
                        }
                        final a = _num(v!);
                        return a == null || a <= 0
                            ? 'Nieprawidłowa kwota'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Bez kategorii'),
                          selected: _purchaseCategoryId == null,
                          onSelected: (_) =>
                              setState(() => _purchaseCategoryId = null),
                        ),
                        for (final cat in storage.getCategories())
                          FilterChip(
                            label: Text(cat.name),
                            selected: _purchaseCategoryId == cat.id,
                            selectedColor: cat.color.withValues(alpha: 0.2),
                            onSelected: (_) =>
                                setState(() => _purchaseCategoryId = cat.id),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _summary(theme, c),
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

  /// Wynik sprawdzenia i podsumowanie pożyczki — liczy się na bieżąco.
  Widget _summary(ThemeData theme, AppSemanticColors c) {
    final check = _check;
    final body = theme.textTheme.bodyMedium;
    final muted = theme.textTheme.bodySmall?.copyWith(color: c.textMuted);

    Widget status(IconData icon, Color color, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: body?.copyWith(color: color))),
      ],
    );

    final children = <Widget>[
      switch (check) {
        LoanNeedsMore(:final missing) => status(
          LucideIcons.calculator,
          c.textSecondary,
          'Brakuje jeszcze ${missing == 1 ? 'jednej wartości' : '$missing '
                    'wartości'} z: kwota, liczba rat, rata, RRSO.',
        ),
        LoanInvalid(:final message) => status(
          LucideIcons.alertTriangle,
          c.negative,
          message,
        ),
        LoanMismatch(:final expectedInstallment) => status(
          LucideIcons.alertTriangle,
          c.warning,
          'Dane się nie zgadzają: przy RRSO ${_rrso.text}% rata wynosi '
          '${budgetNf.format(expectedInstallment)}, a wpisano '
          '${_installment.text}.',
        ),
        LoanComputed(:final field) => status(
          LucideIcons.checkCircle2,
          c.positive,
          'Dane spójne — ${switch (field) {
            LoanField.principal => 'kwota wyliczona',
            LoanField.count => 'liczba rat wyliczona',
            LoanField.installment => 'rata wyliczona',
            LoanField.rrso => 'RRSO wyliczone z wypłaty i rat',
          }}.',
        ),
        LoanConsistent() => status(
          LucideIcons.checkCircle2,
          c.positive,
          'Dane spójne.',
        ),
      },
    ];

    if (check is LoanMismatch) {
      children.addAll([
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () =>
                  _accept(LoanField.installment, check.expectedInstallment),
              child: Text(
                'Przyjmij ratę ${budgetNf.format(check.expectedInstallment)}',
              ),
            ),
            if (check.rrsoFromInstallment != null)
              OutlinedButton(
                onPressed: () =>
                    _accept(LoanField.rrso, check.rrsoFromInstallment!),
                child: Text(
                  'Przyjmij RRSO ${_pct.format(check.rrsoFromInstallment)}% '
                  'z rat',
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Różnicę dają zwykle prowizja albo ubezpieczenie doliczone do rat. '
          'RRSO liczę z wypłaty i rat.',
          style: muted,
        ),
      ]);
    }

    final p = _num(_principal.text);
    final n = _num(_count.text)?.toInt();
    final r = _num(_installment.text);
    final x = _num(_rrso.text);
    final complete =
        (check is LoanComputed ||
            check is LoanConsistent ||
            check is LoanMismatch) &&
        p != null &&
        n != null &&
        r != null &&
        x != null;
    if (complete) {
      final last = LoanMath.lastInstallment(
        principal: p,
        count: n,
        installment: r,
        rrso: x,
      );
      final total = LoanMath.totalRepayment(
        principal: p,
        count: n,
        installment: r,
        rrso: x,
      );
      final lastMonth = _schedule.monthKeyOf(n - 1);
      Widget line(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: Text(label, style: muted)),
            const SizedBox(width: 8),
            // Długa wartość (harmonogram) zawija się zamiast wyjść za ekran.
            Flexible(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: body?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
      final purchase = _num(_purchaseAmount.text) ?? p;
      children.addAll([
        const SizedBox(height: 4),
        line('Raty', '$n × ${budgetNf.format(r)}'),
        line(
          'Harmonogram',
          '${planMonthLabel(_firstMonth)} – ${planMonthLabel(lastMonth)}, '
              'dzień $_dayValue',
        ),
        if (last != r) line('Ostatnia rata', budgetNf.format(last)),
        line('Do spłaty łącznie', budgetNf.format(total)),
        line('Koszt pożyczki', budgetNf.format(total - p)),
        const SizedBox(height: 8),
        Text(
          'W planie: wpływ +${budgetNf.format(p)} w '
          '${planMonthLabel(BudgetEntry.monthKeyOf(_drawdown))}, $n rat '
          'w Pożyczkach'
          '${_withPurchase ? ', zakup −${budgetNf.format(purchase)} '
                    'w Wydatkach' : ''}.',
          style: muted,
        ),
      ]);
    }

    return FrostCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
