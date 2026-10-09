import 'package:flutter/material.dart';

import '../screens/budgets_screen.dart';
import 'budget_picker.dart';
import 'section_info_badge.dart';

/// Wspólny pasek nad ekranami roboczymi: przełącznik budżetu (ADR-037)
/// i opis bieżącej sekcji.
///
/// Zastępuje paski tytułu poszczególnych ekranów. Nazwa ekranu i tak stała tam
/// zdublowana z pigułką nawigacji na dole, a razem z osobnym przełącznikiem
/// zakresu na każdym ekranie zjadała ~112 px, zanim zaczynała się treść.
///
/// Zakres jest GLOBALNY (jeden `BudgetController` dla całej aplikacji), więc
/// jego miejsce jest tutaj, a nie w pięciu ekranach z osobna.
class WorkspaceTopBar extends StatelessWidget {
  /// Opis sekcji dla ikony „i"; `null` = ekran bez opisu.
  final SectionInfo? info;

  /// Czy pokazywać przełącznik zakresu. Ustawienia go nie potrzebują — nie ma
  /// tam czego przełączać, a stały pasek nad listą tylko zabierałby miejsce.
  final bool showScope;

  const WorkspaceTopBar({super.key, this.info, this.showScope = true});

  @override
  Widget build(BuildContext context) {
    // Przełącznik widać zawsze (także przy jednym widocznym budżecie): mówi,
    // w którym budżecie jesteś, i prowadzi do „Zarządzaj budżetami".
    final scopeVisible = showScope;
    if (!scopeVisible && info == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          if (scopeVisible)
            Flexible(
              flex: 4,
              child: BudgetPicker(
                onManage: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BudgetsScreen()),
                ),
              ),
            ),
          const Spacer(),
          if (info != null) ...[
            const SizedBox(width: 8),
            SectionInfoBadge(info!),
          ],
        ],
      ),
    );
  }
}
