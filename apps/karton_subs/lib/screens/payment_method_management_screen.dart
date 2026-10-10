// payment_method_management_screen.dart — Zarządzanie metodami płatności

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription.dart';
import '../controllers/budget_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_icons.dart'
    show paymentMethodIcon, paymentMethodIconColor;
import '../widgets/budget_picker.dart'
    show EmptyBudgetDictionary, showBudgetTargetSheet;
import '../widgets/form_action_bar.dart';
import '../widgets/workspace_top_bar.dart';

class PaymentMethodManagementScreen extends StatefulWidget {
  const PaymentMethodManagementScreen({super.key});

  @override
  State<PaymentMethodManagementScreen> createState() =>
      _PaymentMethodManagementScreenState();
}

class _PaymentMethodManagementScreenState
    extends State<PaymentMethodManagementScreen> {
  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    // Liczniki reagują na zmiany subskrypcji i planu, a lista — na
    // przełączenie budżetu (każdy ma własne metody, ADR-038).
    context.watch<SubscriptionController>();
    final budget = context.watch<BudgetController>();
    final budgetId = budget.budgetId;
    final methods = storage.getPaymentMethods(budgetId);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Metody płatności'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Dodaj metodę płatności',
            onPressed: () => _showEditor(context, storage, null, budgetId),
          ),
          PopupMenuButton<String>(
            tooltip: 'Więcej',
            onSelected: (_) => _copyAll(budget),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'copyAll',
                child: Text('Kopiuj wszystkie do budżetu…'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          WorkspaceTopBar(
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Lista budżetu',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textMuted,
                ),
              ),
            ),
          ),
          Expanded(
            child: methods.isEmpty
                ? EmptyBudgetDictionary(
                    text: 'Ten budżet nie ma jeszcze metod płatności.',
                    onCopyFrom: () => _copyFrom(budget),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: methods.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorder(storage, methods, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final pm = methods[index];
                      final subsCount = budget.countPaymentMethodSubscriptions(
                        budgetId,
                        pm.name,
                      );
                      final budgetCount = budget.countPaymentMethodUsage(
                        budgetId,
                        pm.name,
                      );
                      return Card(
                        key: ValueKey(pm.id),
                        child: ListTile(
                          // Ta sama regula co wszedzie indziej (ADR-033) —
                          // wczesniej KAZDA metoda miala tu karte, wiec lista
                          // przeczyla temu, co uzytkownik widzial przy
                          // pozycjach budzetu.
                          leading: Icon(
                            paymentMethodIcon(pm),
                            color: paymentMethodIconColor(
                              pm,
                              context.semanticColors,
                            ),
                          ),
                          title: Text(pm.name),
                          subtitle: Text(
                            [
                              _usageLabel(subsCount, budgetCount),
                              if (pm.isCreditCard)
                                'Karta · ${pm.graceDays} dni',
                              pm.isCreditCard
                                  ? (pm.isAutomatic
                                        ? 'Spłata automatyczna'
                                        : 'Spłata ręczna')
                                  : (pm.isAutomatic
                                        ? 'Automatyczna'
                                        : 'Manualna'),
                            ].join(' · '),
                            style: theme.textTheme.labelMedium,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edytuj',
                                icon: const Icon(LucideIcons.edit3, size: 18),
                                onPressed: () =>
                                    _showEditor(context, storage, pm, budgetId),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Więcej',
                                onSelected: (v) => switch (v) {
                                  'copy' => _copyTo(pm),
                                  'move' => _moveTo(pm, subsCount, budgetCount),
                                  _ => _confirmDelete(
                                    context,
                                    pm,
                                    subsCount,
                                    budgetCount,
                                  ),
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'copy',
                                    child: Text('Kopiuj do budżetu…'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'move',
                                    child: Text('Przenieś do budżetu…'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Usuń',
                                      style: TextStyle(
                                        color: AppColors.negative,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Icon(LucideIcons.gripVertical, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _reorder(
    StorageService storage,
    List<PaymentMethod> methods,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final list = List<PaymentMethod>.from(methods);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (int i = 0; i < list.length; i++) {
      await storage.savePaymentMethod(list[i].copyWith(order: i));
    }
    if (mounted) context.read<SubscriptionController>().refresh();
  }

  /// Podpis licznika użycia: „X subskrypcji · Y w budżecie" (pomija zerowe
  /// człony). „Nieużywana", gdy nigdzie nie występuje.
  String _usageLabel(int subs, int budget) {
    final parts = <String>[
      if (subs > 0) '$subs subskrypcji',
      if (budget > 0) '$budget w budżecie',
    ];
    return parts.isEmpty ? 'Nieużywana' : parts.join(' · ');
  }

  /// Niezależna kopia w innym budżecie — tu nic się nie zmienia.
  Future<void> _copyTo(PaymentMethod pm) async {
    final budget = context.read<BudgetController>();
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: budget.budgetId,
      title: 'Kopiuj „${pm.name}" do budżetu…',
    );
    if (target == null || !mounted) return;
    final done = await budget.copyPaymentMethodTo(pm, target.budget.id);
    if (!mounted) return;
    _snack(
      done
          ? 'Skopiowano „${pm.name}" do „${target.budget.name}"'
          : 'W „${target.budget.name}" jest już „${pm.name}"',
    );
  }

  /// Przeniesienie: tam kopia, tu usunięcie — z ostrzeżeniem, gdy metoda
  /// jest w tym budżecie używana (pozycje stracą oznaczenie metody).
  Future<void> _moveTo(PaymentMethod pm, int subsCount, int budgetCount) async {
    final budget = context.read<BudgetController>();
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: budget.budgetId,
      title: 'Przenieś „${pm.name}" do budżetu…',
    );
    if (target == null || !mounted) return;
    final used = <String>[
      if (subsCount > 0) '$subsCount subskrypcji',
      if (budgetCount > 0) '$budgetCount pozycji budżetu',
    ];
    if (used.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Przenieść „${pm.name}" do „${target.budget.name}"?'),
          content: Text(
            '${used.join(' i ')} w tym budżecie straci oznaczenie metody '
            'płatności.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Przenieś'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await budget.movePaymentMethodTo(pm, target.budget.id);
    if (mounted) {
      _snack('Przeniesiono „${pm.name}" do „${target.budget.name}"');
    }
  }

  Future<void> _copyAll(BudgetController budget) async {
    final from = budget.budgetId;
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: from,
      title: 'Kopiuj wszystkie metody płatności do budżetu…',
      subtitle: 'Metody, które tam już są, się nie zdublują.',
    );
    if (target == null || !mounted) return;
    final n = await budget.copyPaymentMethodsTo(from, target.budget.id);
    if (!mounted) return;
    _snack(
      n == 0
          ? 'Wszystkie metody są już w „${target.budget.name}"'
          : 'Skopiowano $n metod do „${target.budget.name}"',
    );
  }

  /// Pusty budżet: metody z innego budżetu jednym ruchem.
  Future<void> _copyFrom(BudgetController budget) async {
    final to = budget.budgetId;
    final source = await showBudgetTargetSheet(
      context,
      excludeBudgetId: to,
      title: 'Skopiuj metody płatności z budżetu…',
    );
    if (source == null || !mounted) return;
    final n = await budget.copyPaymentMethodsTo(source.budget.id, to);
    if (mounted) _snack('Skopiowano $n metod z „${source.budget.name}"');
  }

  void _confirmDelete(
    BuildContext context,
    PaymentMethod pm,
    int subsCount,
    int budgetCount,
  ) {
    final budget = context.read<BudgetController>();
    final affected = <String>[
      if (subsCount > 0) '$subsCount subskrypcji',
      if (budgetCount > 0) '$budgetCount pozycji budżetu',
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć "${pm.name}"?'),
        content: affected.isNotEmpty
            ? Text(
                '${affected.join(' i ')} straci oznaczenie metody płatności.',
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              budget.deletePaymentMethod(pm);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
  }

  void _showEditor(
    BuildContext context,
    StorageService storage,
    PaymentMethod? existing,
    String budgetId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PaymentMethodEditor(
        existing: existing,
        budgetId: budgetId,
        onSave: (pm, oldName) async {
          final ctrl = context.read<SubscriptionController>();
          final budget = context.read<BudgetController>();
          await storage.savePaymentMethod(pm);
          if (oldName != null && oldName != pm.name) {
            await budget.renamePaymentMethod(budgetId, oldName, pm.name);
          }
          if (mounted) ctrl.refresh();
        },
      ),
    );
  }
}

class _PaymentMethodEditor extends StatefulWidget {
  final PaymentMethod? existing;

  /// Budżet listy — nazwa musi być w nim unikalna, a nowa metoda do niego
  /// należy (ADR-038).
  final String budgetId;

  /// Callback: `(nowa metoda, stara nazwa lub null)`. Stara nazwa
  /// pozwala propagować zmianę do subskrypcji przy rename.
  final Future<void> Function(PaymentMethod, String? oldName) onSave;

  const _PaymentMethodEditor({
    this.existing,
    required this.budgetId,
    required this.onSave,
  });

  @override
  State<_PaymentMethodEditor> createState() => _PaymentMethodEditorState();
}

class _PaymentMethodEditorState extends State<_PaymentMethodEditor> {
  late TextEditingController _nameCtrl;
  late TextEditingController _graceCtrl;
  late bool _isAutomatic;
  late bool _isCreditCard;
  String? _errorText;
  String? _graceError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _isAutomatic = widget.existing?.isAutomatic ?? false;
    _isCreditCard = widget.existing?.isCreditCard ?? false;
    _graceCtrl = TextEditingController(
      text: widget.existing?.graceDays?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _graceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: widget.existing != null
          ? 'Edytuj metodę płatności'
          : 'Nowa metoda płatności',
      actions: FormActionBar(
        onCancel: () => Navigator.pop(context),
        onSave: _save,
      ),
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Nazwa',
            hintText: 'np. Apple Pay',
            errorText: _errorText,
            // Podglad na zywo: ikona zmienia sie razem z togglami ponizej,
            // wiec widac, jak metoda bedzie wygladac na listach.
            prefixIcon: Icon(
              _isCreditCard
                  ? LucideIcons.creditCard
                  : (_isAutomatic ? LucideIcons.zap : LucideIcons.hand),
              color: _isCreditCard
                  ? (_isAutomatic
                        ? context.semanticColors.warning
                        : context.semanticColors.negative)
                  : null,
            ),
          ),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isAutomatic,
          onChanged: (v) => setState(() => _isAutomatic = v),
          secondary: Icon(_isAutomatic ? LucideIcons.zap : LucideIcons.hand),
          title: Text(_isAutomatic ? 'Automatyczna' : 'Manualna'),
          // Przy karcie ten przełącznik opisuje SPŁATĘ, nie zakup: zakup
          // kartą schodzi od razu zawsze, a przegapić można właśnie spłatę.
          subtitle: Text(
            _isCreditCard
                ? (_isAutomatic
                      ? 'Spłata karty schodzi sama'
                      : 'Spłatę karty robisz ręcznie (lista „Płatności")')
                : (_isAutomatic
                      ? 'Pobierana automatycznie (żółty na kalendarzu)'
                      : 'Przelew do zrobienia ręcznie (lista „Płatności")'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isCreditCard,
          onChanged: (v) => setState(() => _isCreditCard = v),
          secondary: const Icon(LucideIcons.creditCard),
          title: const Text('Karta kredytowa'),
          subtitle: const Text(
            'Pożycza pieniądze: zakup nie obciąża miesiąca, '
            'robi to spłata po okresie bezodsetkowym',
          ),
        ),
        // Pole tylko przy włączonej karcie — przy zwykłej metodzie „dni
        // bezodsetkowych" nie ma czego opisywać.
        if (_isCreditCard) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _graceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Dni bezodsetkowe *',
              hintText: 'np. 50',
              helperText: 'Po tylu dniach od zakupu powstanie spłata',
              errorText: _graceError,
              prefixIcon: const Icon(LucideIcons.calendarClock),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Nazwa nie może być pusta');
      return;
    }

    // Karta bez liczby dni nie ma jak wyznaczyć terminu spłaty, więc automat
    // po cichu by nie zadziałał — lepiej powiedzieć to teraz niż zostawić
    // użytkownika z kartą, która „nic nie robi".
    int? graceDays;
    if (_isCreditCard) {
      graceDays = int.tryParse(_graceCtrl.text.trim());
      if (graceDays == null || graceDays <= 0) {
        setState(() => _graceError = 'Podaj liczbę dni większą od zera');
        return;
      }
      if (graceDays > 365) {
        setState(() => _graceError = 'Najwyżej 365 dni');
        return;
      }
    }

    // Walidacja unikalności w budżecie (case-insensitive)
    final storage = context.read<StorageService>();
    final siblings = storage.getPaymentMethods(widget.budgetId);
    final duplicate = siblings.any(
      (pm) =>
          pm.name.toLowerCase() == name.toLowerCase() &&
          pm.id != widget.existing?.id,
    );
    if (duplicate) {
      setState(() => _errorText = 'Metoda o tej nazwie już jest w budżecie');
      return;
    }

    final oldName = widget.existing?.name;
    final pm = widget.existing != null
        ? widget.existing!.copyWith(
            name: name,
            isAutomatic: _isAutomatic,
            isCreditCard: _isCreditCard,
            graceDays: graceDays,
            // Wyłączenie karty musi wyczyścić dni — inaczej zostałaby martwa
            // liczba, która ożyłaby przy ponownym włączeniu.
            clearGraceDays: !_isCreditCard,
          )
        : PaymentMethod(
            id: const Uuid().v4(),
            name: name,
            order: siblings.length,
            isAutomatic: _isAutomatic,
            isCreditCard: _isCreditCard,
            graceDays: graceDays,
            budgetId: widget.budgetId,
          );

    await widget.onSave(pm, oldName);
    if (mounted) Navigator.pop(context);
  }
}
