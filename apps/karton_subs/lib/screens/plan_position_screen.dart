import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/plan_controller.dart';
import '../models/plan_position.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/budget_picker.dart' show moveOrCopyPositions;
import '../widgets/budget_widgets.dart' show budgetNf;
import '../widgets/filter_bars.dart' show kMonthsShort;
import '../widgets/frost_card.dart';
import '../widgets/plan_widgets.dart'
    show planMonthLabel, planPositionPeriodText;
import '../widgets/selection_bar.dart';
import 'installment_loan_form_screen.dart';
import 'plan_position_form_screen.dart';

/// Szczegóły pozycji planu: dwanaście miesięcy wybranego roku w siatce
/// (rząd = kwartał) i szybkie wypełnianie pod spodem (ADR-035).
///
/// Dotknięcie miesiąca edytuje jeden; przytrzymanie zaczyna zaznaczanie
/// (jak na liście Planowania), a kolejne przytrzymanie zaznacza zakres od
/// ostatnio zaznaczonego miesiąca. Panel wpisuje kwotę i dzień w zaznaczone
/// miesiące albo w puste miesiące roku. Miesiące poza okresem pozycji (przed
/// startem, po spłacie raty) są wyszarzone — nie da się ich zaznaczyć ani
/// wypełnić, a dotknięcie mówi dlaczego.
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

  /// Ostatnio zaznaczony miesiąc — początek zakresu przy kolejnym
  /// przytrzymaniu.
  String? _lastKey;
  final _amountCtrl = TextEditingController();
  final _dayCtrl = TextEditingController();

  /// Błąd panelu szybkiego wypełniania (pod polami, nie w okienku).
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  String _monthName(int m) {
    final name = DateFormat('LLLL', 'pl').format(DateTime(2000, m));
    return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
  }

  List<String> get _keys => [
    for (var m = 1; m <= 12; m++) planMonthKey(_year, m),
  ];

  void _clearSelection() {
    _selecting = false;
    _selected.clear();
    _lastKey = null;
    _error = null;
  }

  void _endSelection() => setState(_clearSelection);

  void _changeYear(int delta) => setState(() {
    _year += delta;
    _clearSelection();
  });

  void _toggle(String key) => setState(() {
    if (!_selected.remove(key)) _selected.add(key);
    _lastKey = key;
    _error = null;
    if (_selected.isEmpty) _selecting = false;
  });

  /// Przytrzymanie: pierwsze zaczyna zaznaczanie, kolejne zaznacza zakres
  /// od ostatnio zaznaczonego miesiąca — z pominięciem miesięcy poza okresem.
  void _longPress(PlanPosition p, String key) => setState(() {
    _error = null;
    final from = _lastKey;
    if (!_selecting || from == null) {
      _selecting = true;
      _selected.add(key);
    } else {
      final first = from.compareTo(key) <= 0 ? from : key;
      final last = from.compareTo(key) <= 0 ? key : from;
      for (final k in _keys) {
        if (k.compareTo(first) >= 0 && k.compareTo(last) <= 0 && p.inPeriod(k)) {
          _selected.add(k);
        }
      }
    }
    _lastKey = key;
  });

  void _snack(String text, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), action: action));

  void _openForm(PlanPosition p) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PlanPositionFormScreen(existing: p)),
  );

  /// Miesiąc poza okresem nie reaguje martwo — mówi, dlaczego jest
  /// zablokowany i gdzie zmienić okres.
  void _explainOutside(PlanPosition p, int month) {
    final key = planMonthKey(_year, month);
    final before = p.beforePeriod(key);
    final edge = before ? p.periodStart! : p.periodEnd!;
    _snack(
      '${_monthName(month)} $_year jest '
      '${before ? 'przed startem' : 'po zakończeniu'} pozycji '
      '(${planMonthLabel(edge)}). Okres zmienisz w edycji pozycji.',
      action: SnackBarAction(label: 'Edytuj', onPressed: () => _openForm(p)),
    );
  }

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

  // ── Szybkie wypełnianie ────────────────────────────────────────────────────

  /// Pola panelu: kwota i dzień (oba opcjonalne) albo błąd do pokazania.
  ({double? amount, int? day, String? error}) _readPanel() {
    final rawAmount = _amountCtrl.text.trim();
    final rawDay = _dayCtrl.text.trim();
    final amount = rawAmount.isEmpty ? null : _parseAmount(rawAmount);
    if (rawAmount.isNotEmpty && amount == null) {
      return (amount: null, day: null, error: 'Nieprawidłowa kwota');
    }
    final day = rawDay.isEmpty ? null : _parseDay(rawDay);
    if (rawDay.isNotEmpty && day == null) {
      return (amount: null, day: null, error: 'Dzień musi być liczbą od 1 do 31');
    }
    return (amount: amount, day: day, error: null);
  }

  /// Kwota (i dzień) we wszystkie miesiące pokazanego roku, które są
  /// w okresie pozycji, a nie mają kwoty. Miesięcy z kwotą nie rusza.
  Future<void> _fillEmpty(PlanPosition p) async {
    final input = _readPanel();
    final amount = input.amount;
    if (input.error != null || amount == null) {
      setState(() => _error = input.error ?? 'Wpisz kwotę');
      return;
    }
    final empty = [
      for (final k in _keys)
        if (p.inPeriod(k) && !p.months.containsKey(k)) k,
    ];
    setState(() => _error = null);
    if (empty.isEmpty) {
      _snack('Brak pustych miesięcy w $_year');
      return;
    }
    final n = await context.read<PlanController>().setMonths(p.id, {
      for (final k in empty) k: PlanMonth(amount: amount, day: input.day),
    });
    if (mounted) _snack('Dodano do planu $n mies.');
  }

  /// Kwota i/lub dzień w zaznaczone miesiące. Miesiąc bez kwoty dostaje ją
  /// i wchodzi do planu; sam dzień zmienia tylko miesiące z kwotą.
  Future<void> _fillSelected(PlanPosition p) async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Przytrzymaj miesiąc, by go zaznaczyć');
      return;
    }
    final input = _readPanel();
    final amount = input.amount;
    if (input.error != null) {
      setState(() => _error = input.error);
      return;
    }
    if (amount == null && input.day == null) {
      setState(() => _error = 'Wpisz kwotę albo dzień');
      return;
    }
    final changes = <String, PlanMonth?>{};
    for (final k in _selected) {
      final current = p.months[k];
      if (amount != null) {
        changes[k] = PlanMonth(amount: amount, day: input.day ?? current?.day);
      } else if (current != null) {
        changes[k] = current.copyWith(day: input.day);
      }
    }
    final n = changes.isEmpty
        ? 0
        : await context.read<PlanController>().setMonths(p.id, changes);
    if (!mounted) return;
    _endSelection();
    _snack(
      n == 0
          ? 'Sam dzień ustawia się tylko miesiącom z kwotą'
          : 'Ustawiono $n mies.',
    );
  }

  Future<void> _removeSelected(PlanPosition p) async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Przytrzymaj miesiąc, by go zaznaczyć');
      return;
    }
    final keys = _selected.where(p.months.containsKey).toList();
    final n = keys.isEmpty
        ? 0
        : await context.read<PlanController>().setMonths(p.id, {
            for (final k in keys) k: null,
          });
    if (!mounted) return;
    _endSelection();
    _snack(
      n == 0 ? 'Zaznaczone miesiące nie mają kwot' : 'Usunięto z planu $n mies.',
    );
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
    final inPeriodKeys = _keys.where(p.inPeriod).toList();
    final todayKey = planMonthKey(plan.today.year, plan.today.month);
    final period = planPositionPeriodText(p);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Edytuj pozycję',
            icon: const Icon(LucideIcons.pencil),
            onPressed: () => _openForm(p),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                await plan.setArchivedAll({p.id}, !p.archived);
              } else if (v == 'delete') {
                await _delete(p);
              } else if (v == 'move' || v == 'copy') {
                final done = await moveOrCopyPositions(
                  context,
                  {p.id},
                  copy: v == 'copy',
                  fromBudgetId: p.budgetId,
                  what: '„${p.name}"',
                );
                // Przeniesiona pozycja nie należy już do pokazanego budżetu.
                if (done && v == 'move' && context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(p.archived ? 'Przywróć do planu' : 'Ukryj pozycję'),
              ),
              const PopupMenuItem(
                value: 'move',
                child: Text('Przenieś do budżetu…'),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Text('Kopiuj do budżetu…'),
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
              allSelected:
                  inPeriodKeys.isNotEmpty &&
                  _selected.length == inPeriodKeys.length,
              onToggleAll: () => setState(() {
                if (_selected.length == inPeriodKeys.length) {
                  _clearSelection();
                } else {
                  _selected.addAll(inPeriodKeys);
                }
              }),
              onClose: _endSelection,
              // Akcje są w panelu szybkiego wypełniania pod siatką — ten sam
              // panel działa też bez zaznaczenia („Puste").
              actions: const [],
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
                if (period != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(LucideIcons.calendarRange, size: 14, color: c.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Okres: $period',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Zakup z pożyczki ratalnej (ADR-036): raty są w Pożyczkach,
                // tu — sam zakup; warunki zmienia się w pożyczce.
                if (p.kind == PlanKind.expense &&
                    p.linkId != null &&
                    plan.loanParts(p.linkId!).repayment != null)
                  Row(
                    children: [
                      Icon(LucideIcons.link, size: 14, color: c.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Zakup z pożyczki ratalnej',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                InstallmentLoanFormScreen(linkId: p.linkId),
                          ),
                        ),
                        child: const Text('Otwórz pożyczkę'),
                      ),
                    ],
                  ),
                if (p.note != null) ...[
                  const SizedBox(height: 4),
                  Text(p.note!, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Poprzedni rok',
                      icon: const Icon(LucideIcons.chevronLeft),
                      onPressed: () => _changeYear(-1),
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
                      tooltip: 'Następny rok',
                      icon: const Icon(LucideIcons.chevronRight),
                      onPressed: () => _changeYear(1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Rząd = kwartał: płatności kwartalne widać od razu.
                for (var q = 0; q < 4; q++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _tile(p, q * 3 + i + 1, todayKey, color),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                _panel(p, theme, c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(PlanPosition p, int month, String todayKey, Color color) {
    final key = planMonthKey(_year, month);
    final label = kMonthsShort[month - 1];
    if (!p.inPeriod(key)) {
      return _MonthTile(
        label: label,
        outsideReason: p.beforePeriod(key) ? 'przed startem' : 'po zakończeniu',
        onTap: () => _explainOutside(p, month),
      );
    }
    return _MonthTile(
      label: label,
      month: p.months[key],
      defaultDay: p.day,
      inflow: p.isInflow,
      color: color,
      isCurrent: key == todayKey,
      selected: _selected.contains(key),
      onTap: _selecting ? () => _toggle(key) : () => _editMonth(p, key, month),
      onLongPress: () => _longPress(p, key),
    );
  }

  Widget _panel(PlanPosition p, ThemeData theme, AppSemanticColors c) {
    final emptyCount = _keys
        .where((k) => p.inPeriod(k) && !p.months.containsKey(k))
        .length;
    final selectedLabels = (_selected.toList()..sort())
        .map((k) => kMonthsShort[int.parse(k.substring(5)) - 1])
        .join(', ');
    void clearError(String _) {
      if (_error != null) setState(() => _error = null);
    }

    final compact = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return FrostCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Szybkie wypełnianie',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: _endSelection,
                  child: const Text('Wyczyść zaznaczenie'),
                ),
            ],
          ),
          Text(
            _selected.isEmpty
                ? 'Przytrzymaj miesiąc, by go zaznaczyć; kolejne '
                      'przytrzymanie zaznacza zakres.'
                : 'Zaznaczone: $selectedLabels',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: clearError,
                  decoration: InputDecoration(
                    labelText: 'Kwota',
                    suffixText: p.currency.label,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _dayCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: clearError,
                  decoration: InputDecoration(
                    labelText: 'Dzień',
                    hintText: p.day?.toString(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: compact,
                  onPressed: () => _fillEmpty(p),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Puste ($emptyCount)'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  style: compact,
                  onPressed: () => _fillSelected(p),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Zaznaczone (${_selected.length})'),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Usuń zaznaczone z planu',
                icon: Icon(LucideIcons.calendarX, color: c.negative),
                onPressed: () => _removeSelected(p),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: c.negative),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '„Puste" = miesiące $_year bez kwoty'
            '${p.hasPeriod ? ' w okresie pozycji' : ''}. Pusty dzień = dzień '
            'pozycji${p.day != null ? ' (${p.day})' : ''}.',
            style: theme.textTheme.labelSmall?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Kafel miesiąca w siatce roku: skrót miesiąca, kwota i dzień — albo
/// „brak kwoty", albo (poza okresem pozycji) kłódka z powodem.
class _MonthTile extends StatelessWidget {
  final String label;
  final PlanMonth? month;
  final int? defaultDay;
  final bool inflow;
  final Color? color;
  final bool isCurrent;
  final bool selected;

  /// „przed startem" / „po zakończeniu"; `null` = miesiąc w okresie.
  final String? outsideReason;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _MonthTile({
    required this.label,
    required this.onTap,
    this.month,
    this.defaultDay,
    this.inflow = false,
    this.color,
    this.isCurrent = false,
    this.selected = false,
    this.outsideReason,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final m = month;
    final outside = outsideReason != null;
    final radius = BorderRadius.circular(AppRadii.control);
    final day = m?.day ?? defaultDay;

    final Color? background;
    final BoxBorder? border;
    if (selected) {
      background = c.primary.withValues(alpha: 0.12);
      border = Border.all(color: c.primary, width: 2);
    } else if (outside) {
      background = c.textMuted.withValues(alpha: 0.08);
      border = null;
    } else if (m != null) {
      background = c.surface;
      border = Border.all(color: c.border, width: 0.5);
    } else {
      background = null;
      border = Border.all(color: c.border);
    }

    final String bottom;
    if (outside) {
      bottom = outsideReason!;
    } else if (m == null) {
      bottom = 'brak kwoty';
    } else if (day == null) {
      bottom = '';
    } else {
      bottom = 'dzień $day${m.day == null ? '' : ' (zm.)'}';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        // Poza okresem przytrzymanie też tylko wyjaśnia — nie zaznacza.
        onLongPress: onLongPress ?? onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: outside ? c.textMuted : c.textSecondary,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (selected)
                    Icon(LucideIcons.checkCircle2, size: 15, color: c.primary),
                ],
              ),
              const SizedBox(height: 2),
              if (outside)
                Icon(LucideIcons.lock, size: 14, color: c.textMuted)
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    m == null
                        ? '—'
                        : '${inflow ? '+' : '−'}${budgetNf.format(m.amount)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: m == null ? c.textMuted : color,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                bottom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
