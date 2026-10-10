// category_management_screen.dart — Zarządzanie kategoriami

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/category.dart';
import '../controllers/budget_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/form_action_bar.dart';
import '../widgets/budget_picker.dart'
    show EmptyBudgetDictionary, showBudgetTargetSheet;
import '../widgets/category_icons.dart' show categoryIcon, availableIconNames;
import '../widgets/workspace_top_bar.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    // Liczniki muszą reagować na zmiany subskrypcji i planu, a lista — na
    // przełączenie budżetu (każdy ma własne kategorie, ADR-038).
    context.watch<SubscriptionController>();
    final budget = context.watch<BudgetController>();
    final budgetId = budget.budgetId;
    final categories = storage.getCategories(budgetId);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Kategorie'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Dodaj kategorię',
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
            child: categories.isEmpty
                ? EmptyBudgetDictionary(
                    text: 'Ten budżet nie ma jeszcze kategorii.',
                    onCopyFrom: () => _copyFrom(budget),
                  )
                // Zawsze alfabetycznie (bez przeciągania) — kategorię
                // znajduje się po nazwie.
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final subsCount = budget.countCategorySubscriptions(
                        cat.id,
                      );
                      final budgetCount = budget.countCategoryUsage(cat.id);
                      return Card(
                        key: ValueKey(cat.id),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cat.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              categoryIcon(cat.iconName),
                              color: cat.color,
                              size: 18,
                            ),
                          ),
                          title: Text(cat.name),
                          subtitle: Text(
                            _usageLabel(subsCount, budgetCount),
                            style: theme.textTheme.labelMedium,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edytuj',
                                icon: const Icon(LucideIcons.edit3, size: 18),
                                onPressed: () => _showEditor(
                                  context,
                                  storage,
                                  cat,
                                  budgetId,
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Więcej',
                                onSelected: (v) => switch (v) {
                                  'copy' => _copyTo(cat),
                                  'move' => _moveTo(
                                    cat,
                                    subsCount,
                                    budgetCount,
                                  ),
                                  _ => _confirmDelete(
                                    context,
                                    cat,
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
  Future<void> _copyTo(Category cat) async {
    final budget = context.read<BudgetController>();
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: budget.budgetId,
      title: 'Kopiuj „${cat.name}" do budżetu…',
    );
    if (target == null || !mounted) return;
    final done = await budget.copyCategoryTo(cat, target.budget.id);
    if (!mounted) return;
    _snack(
      done
          ? 'Skopiowano „${cat.name}" do „${target.budget.name}"'
          : 'W „${target.budget.name}" jest już „${cat.name}"',
    );
  }

  /// Przeniesienie: tam kopia, tu usunięcie — z ostrzeżeniem, gdy kategoria
  /// jest w tym budżecie używana (pozycje zostaną bez niej).
  Future<void> _moveTo(Category cat, int subsCount, int budgetCount) async {
    final budget = context.read<BudgetController>();
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: budget.budgetId,
      title: 'Przenieś „${cat.name}" do budżetu…',
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
          title: Text('Przenieść „${cat.name}" do „${target.budget.name}"?'),
          content: Text(
            '${used.join(' i ')} w tym budżecie zostanie bez kategorii.',
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
    await budget.moveCategoryTo(cat, target.budget.id);
    if (mounted) {
      _snack('Przeniesiono „${cat.name}" do „${target.budget.name}"');
    }
  }

  Future<void> _copyAll(BudgetController budget) async {
    final from = budget.budgetId;
    final target = await showBudgetTargetSheet(
      context,
      excludeBudgetId: from,
      title: 'Kopiuj wszystkie kategorie do budżetu…',
      subtitle: 'Kategorie, które tam już są, się nie zdublują.',
    );
    if (target == null || !mounted) return;
    final n = await budget.copyCategoriesTo(from, target.budget.id);
    if (!mounted) return;
    _snack(
      n == 0
          ? 'Wszystkie kategorie są już w „${target.budget.name}"'
          : 'Skopiowano $n kategorii do „${target.budget.name}"',
    );
  }

  /// Pusty budżet: kategorie z innego budżetu jednym ruchem.
  Future<void> _copyFrom(BudgetController budget) async {
    final to = budget.budgetId;
    final source = await showBudgetTargetSheet(
      context,
      excludeBudgetId: to,
      title: 'Skopiuj kategorie z budżetu…',
    );
    if (source == null || !mounted) return;
    final n = await budget.copyCategoriesTo(source.budget.id, to);
    if (mounted) {
      _snack('Skopiowano $n kategorii z „${source.budget.name}"');
    }
  }

  void _confirmDelete(
    BuildContext context,
    Category cat,
    int subsCount,
    int budgetCount,
  ) {
    final budget = context.read<BudgetController>();
    final other = budget.otherCategoryFor(cat);
    final moved = <String>[
      if (subsCount > 0) '$subsCount subskrypcji',
      if (budgetCount > 0) '$budgetCount pozycji budżetu',
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usuń "${cat.name}"?'),
        content: moved.isNotEmpty
            ? Text(
                other != null
                    ? '${moved.join(' i ')} zostanie przeniesionych do '
                          'kategorii "${other.name}".'
                    : '${moved.join(' i ')} zostanie bez kategorii.',
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
              budget.deleteCategory(cat);
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
    Category? existing,
    String budgetId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CategoryEditor(
        existing: existing,
        budgetId: budgetId,
        onSave: (cat) async {
          final ctrl = context.read<SubscriptionController>();
          await storage.saveCategory(cat);
          if (mounted) ctrl.refresh();
        },
      ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  final Category? existing;

  /// Budżet listy — nazwa musi być w nim unikalna, a nowa kategoria do niego
  /// należy (ADR-038).
  final String budgetId;
  final Future<void> Function(Category) onSave;

  const _CategoryEditor({
    this.existing,
    required this.budgetId,
    required this.onSave,
  });

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late TextEditingController _nameCtrl;
  late String _colorHex;
  late String _iconName;
  late bool _excludeFromGhost;
  String? _errorText;

  static const _palette = [
    '#2563EB',
    '#7C3AED',
    '#0891B2',
    '#EA580C',
    '#16A34A',
    '#DB2777',
    '#D97706',
    '#64748B',
    '#DC2626',
    '#059669',
    '#4F46E5',
    '#0D9488',
    '#CA8A04',
    '#9333EA',
    '#E11D48',
    '#1D4ED8',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _colorHex = widget.existing?.colorHex ?? _palette[0];
    _iconName = widget.existing?.iconName ?? 'folder';
    _excludeFromGhost = widget.existing?.excludeFromGhostAnalysis ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormSheet(
      title: widget.existing != null ? 'Edytuj kategorię' : 'Nowa kategoria',
      actions: FormActionBar(
        onCancel: () => Navigator.pop(context),
        onSave: _save,
      ),
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Nazwa',
            hintText: 'np. AI',
            errorText: _errorText,
          ),
          autofocus: widget.existing == null,
        ),
        const SizedBox(height: 16),

        // Kolor
        Text('Kolor', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _palette.map((hex) {
            final color = Color(
              int.parse('FF${hex.replaceFirst('#', '')}', radix: 16),
            );
            final isSelected = _colorHex == hex;
            return GestureDetector(
              onTap: () => setState(() => _colorHex = hex),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: theme.colorScheme.primary, width: 3)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Ikona
        Text('Ikona', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        // Siatka przewijana W DÓŁ, nie w bok: ikon jest kilkadziesiąt, a
        // ułożone są tematycznie (dom, zakupy, transport, …). Dwa rzędy
        // przewijane poziomo rozbijały tę kolejność na pary i szukanie
        // sprowadzało się do przesuwania przez cały zestaw.
        SizedBox(
          height: 168,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 48,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: availableIconNames.length,
            itemBuilder: (context, index) {
              final name = availableIconNames[index];
              final isSelected = _iconName == name;
              final color = Color(
                int.parse('FF${_colorHex.replaceFirst('#', '')}', radix: 16),
              );
              return GestureDetector(
                onTap: () => setState(() => _iconName = name),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: color, width: 2)
                        : Border.all(color: theme.dividerColor),
                  ),
                  child: Icon(
                    categoryIcon(name),
                    color: isSelected ? color : theme.colorScheme.onSurface,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Wykluczenie z analizy ghost
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pomijaj w analizie nieużywanych'),
          subtitle: Text(
            'Subskrypcje w tej kategorii nie będą oznaczane jako nieużywane',
            style: theme.textTheme.bodySmall,
          ),
          value: _excludeFromGhost,
          onChanged: (v) => setState(() => _excludeFromGhost = v),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final siblings = context.read<StorageService>().getCategories(
      widget.budgetId,
    );
    final duplicate = siblings.any(
      (c) =>
          c.id != widget.existing?.id &&
          c.name.toLowerCase().trim() == name.toLowerCase(),
    );
    if (duplicate) {
      setState(() => _errorText = 'Kategoria o tej nazwie już jest w budżecie');
      return;
    }

    final cat = widget.existing != null
        ? widget.existing!.copyWith(
            name: name,
            colorHex: _colorHex,
            iconName: _iconName,
            excludeFromGhostAnalysis: _excludeFromGhost,
          )
        : Category(
            id: const Uuid().v4(),
            name: name,
            colorHex: _colorHex,
            iconName: _iconName,
            order: siblings.length,
            excludeFromGhostAnalysis: _excludeFromGhost,
            budgetId: widget.budgetId,
          );

    await widget.onSave(cat);
    if (mounted) Navigator.pop(context);
  }
}
