import 'package:flutter/material.dart';

import '../screens/budgets_screen.dart';
import 'budget_picker.dart';
import 'section_info_badge.dart';

/// Pasek nad ekranami roboczymi: po lewej to, co ekran potrzebuje
/// ([leading] — zakładki „Statystyki | Kalendarz" albo „Dzisiaj" i „Cały
/// rok"), po prawej przełącznik budżetu (ADR-037) i opis sekcji.
///
/// Zastępuje paski tytułu poszczególnych ekranów. Nazwa ekranu i tak stała tam
/// zdublowana z pigułką nawigacji na dole. Budżet jest GLOBALNY (jeden
/// `BudgetController` dla całej aplikacji) — przełącznik stoi w tym samym
/// miejscu na każdym ekranie, który go pokazuje.
class WorkspaceTopBar extends StatelessWidget {
  /// Opis sekcji dla ikony „i"; `null` = ekran bez opisu.
  final SectionInfo? info;

  /// Czy pokazywać przełącznik budżetu. Widać go także przy jednym widocznym
  /// budżecie: mówi, w którym budżecie jesteś, i prowadzi do „Zarządzaj".
  final bool showScope;

  /// Treść po lewej stronie paska (zakładki, „Dzisiaj" i „Cały rok");
  /// `null` = pusto.
  final Widget? leading;

  const WorkspaceTopBar({
    super.key,
    this.info,
    this.showScope = true,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    if (!showScope && info == null && leading == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            // Lewa strona bierze resztę miejsca — przełącznik i „i" zawsze
            // stoją przy prawej krawędzi.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: leading ?? const SizedBox.shrink(),
              ),
            ),
            if (showScope)
              ConstrainedBox(
                // Długa nazwa budżetu skraca się, zamiast zabrać zakładkom
                // całą szerokość.
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth * (leading == null ? 0.75 : 0.45),
                ),
                child: BudgetPicker(
                  onManage: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BudgetsScreen()),
                  ),
                ),
              ),
            if (info != null) ...[
              const SizedBox(width: 2),
              SectionInfoBadge(info!),
            ],
          ],
        ),
      ),
    );
  }
}
