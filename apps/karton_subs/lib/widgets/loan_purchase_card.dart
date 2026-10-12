import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/plan_controller.dart';
import '../screens/plan_position_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'budget_widgets.dart' show budgetNf;
import 'frost_card.dart';
import 'plan_widgets.dart' show planMonthLabel;

/// Zakup tego dnia w formularzu pożyczki — ratalnej i z karty (ADR-036).
///
/// Bez zakupu — „Dodaj" (pola kwoty i kategorii pojawiają się, zakup powstaje
/// przy zapisie pożyczki), z zakupem — jego kwota i „Pokaż", które prowadzi
/// do jego ekranu. Stamtąd „Wróć do pożyczki" — w obie strony.
///
/// Pola nowego zakupu (czy dodać, kwota, kategoria) trzyma formularz, bo
/// zapisuje je razem z pożyczką.
class LoanPurchaseCard extends StatelessWidget {
  /// Zapisana pożyczka; `null` = nowa, zakupu jeszcze nie ma.
  final String? linkId;

  /// Nazwa pożyczki — z niej nazwa nowego zakupu ([loanPurchaseName]).
  final String loanName;

  /// Budżet, którego kategorie są do wyboru (ADR-038).
  final String budgetId;

  /// Czym pożyczka się spłaca — „raty" albo „spłata" — w wyjaśnieniu, gdzie
  /// co się liczy.
  final String repaymentLabel;

  /// Rok ekranu zakupu, gdy zakup nie ma żadnego miesiąca.
  final int fallbackYear;

  final bool adding;
  final ValueChanged<bool> onAddingChanged;
  final TextEditingController amount;
  final String? categoryId;
  final ValueChanged<String?> onCategoryChanged;

  /// Pole „Nazwa wydatku" (pożyczka z karty): gdy podane, nazwę ustawia się
  /// w bloku — nowego zakupu i istniejącego; formularz zapisuje ją razem
  /// z pożyczką. Bez niego nazwa stoi w tytule (pożyczka ratalna).
  final TextEditingController? name;
  final ValueChanged<String>? onNameChanged;

  const LoanPurchaseCard({
    super.key,
    required this.linkId,
    required this.loanName,
    required this.budgetId,
    required this.repaymentLabel,
    required this.fallbackYear,
    required this.adding,
    required this.onAddingChanged,
    required this.amount,
    required this.categoryId,
    required this.onCategoryChanged,
    this.name,
    this.onNameChanged,
  });

  /// Liczba z pola (spacje grupujące, przecinek dziesiętny); `null` dla
  /// pustego albo nieczytelnego.
  static double? _parse(String raw) {
    final t = raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.semanticColors;
    final storage = context.read<StorageService>();
    final link = linkId;
    final purchase = link == null
        ? null
        : context.watch<PlanController>().loanParts(link).purchase;
    final muted = theme.textTheme.bodySmall?.copyWith(color: c.textMuted);

    Widget header(String title, String subtitle, Widget action) => Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: muted),
            ],
          ),
        ),
        const SizedBox(width: 8),
        action,
      ],
    );

    final nameCtrl = name;
    final nameField = nameCtrl == null
        ? null
        : TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nazwa wydatku',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: onNameChanged,
          );

    if (purchase != null) {
      final entry = purchase.months.entries.firstOrNull;
      final category = purchase.categoryId == null
          ? null
          : storage.getCategory(purchase.categoryId!);
      final summary = header(
        // Z polem nazwy nazwa stoi w polu, nie w tytule.
        nameField == null ? 'Zakup „${purchase.name}"' : 'Zakup tego dnia',
        [
          if (entry != null) '−${budgetNf.format(entry.value.amount)}',
          category?.name ?? 'bez kategorii',
          if (entry != null) planMonthLabel(entry.key),
        ].join(' · '),
        FilledButton.tonalIcon(
          icon: const Icon(LucideIcons.arrowRight, size: 16),
          label: const Text('Pokaż'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlanPositionScreen(
                positionId: purchase.id,
                initialYear:
                    int.tryParse(entry?.key.substring(0, 4) ?? '') ??
                    fallbackYear,
                openedFromLoan: true,
              ),
            ),
          ),
        ),
      );
      return FrostCard(
        padding: const EdgeInsets.all(12),
        child: nameField == null
            ? summary
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [summary, const SizedBox(height: 12), nameField],
              ),
      );
    }

    // Tytuł pokazuje nazwę, z jaką zakup powstanie — chyba że jest pole
    // nazwy (karta): wtedy nazwa stoi w nim.
    final loan = loanName.trim();
    final title = loan.isEmpty || nameField != null
        ? 'Zakup tego dnia'
        : 'Zakup „${loanPurchaseName(loan)}" tego dnia';
    final why =
        'Zakup idzie do Wydatków, $repaymentLabel — do Pożyczek, więc ten sam '
        'koszt nie liczy się dwa razy.';
    if (!adding) {
      return FrostCard(
        padding: const EdgeInsets.all(12),
        child: header(
          title,
          why,
          FilledButton.tonalIcon(
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Dodaj'),
            onPressed: () => onAddingChanged(true),
          ),
        ),
      );
    }

    return FrostCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(
            title,
            'Powstanie przy zapisie. $why',
            TextButton(
              onPressed: () => onAddingChanged(false),
              child: const Text('Nie dodawaj'),
            ),
          ),
          if (nameField != null) ...[const SizedBox(height: 12), nameField],
          const SizedBox(height: 12),
          TextFormField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Kwota zakupu',
              hintText: '= kwota pożyczki',
              isDense: true,
            ),
            validator: (v) {
              if (!adding || (v ?? '').trim().isEmpty) return null;
              final a = _parse(v!);
              return a == null || a <= 0 ? 'Nieprawidłowa kwota' : null;
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Bez kategorii'),
                selected: categoryId == null,
                onSelected: (_) => onCategoryChanged(null),
              ),
              for (final cat in storage.getCategories(budgetId))
                FilterChip(
                  label: Text(cat.name),
                  selected: categoryId == cat.id,
                  selectedColor: cat.color.withValues(alpha: 0.2),
                  onSelected: (_) => onCategoryChanged(cat.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pytanie przed usunięciem pożyczki: [text] mówi, co znika razem z nią,
/// a gdy pożyczka ma zakup — pole „Usuń też zakup z Wydatków" (domyślnie
/// zaznaczone; odznaczony zakup zostaje jako zwykły wydatek). Zwraca `null`
/// przy anulowaniu, inaczej — czy usunąć też zakup.
Future<bool?> confirmLoanDelete(
  BuildContext context, {
  required String text,
  required bool hasPurchase,
}) async {
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
            Text(text),
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
  if (ok != true) return null;
  return hasPurchase && withPurchase;
}
