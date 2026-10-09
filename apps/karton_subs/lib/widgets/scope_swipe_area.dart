import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../controllers/budget_controller.dart';

/// Warstwa gestu: poziomy „flick" przełącza aktywny budżet na kolejny albo
/// poprzedni z listy (ADR-037) — spójnie na zakładkach Budżet i Planowanie
/// (jeden globalny wybór).
///
/// Kierunek jak przy przewracaniu kartek: palec w lewo → kolejny budżet
/// z listy, palec w prawo → poprzedni. Na końcu listy gest nic nie robi.
///
/// Owija samą treść ekranu (nie przełącznik ani filtry). Gest ustępuje głębszym
/// rozpoznawcom w tym samym kierunku: [Dismissible] na wierszu wygrywa swipe
/// „usuń", a pionowy scroll listy działa bez zmian (inna oś). `TabBarView`
/// Dashboardu ma wyłączony swipe (physics), więc nie konkuruje.
///
/// Przełączenie wymaga wyraźnej prędkości ([minVelocity]) — chroni przed
/// przypadkową zmianą globalnego stanu finansowego przy ukośnym scrollu.
class ScopeSwipeArea extends StatefulWidget {
  final Widget child;

  /// Gdy `false` (jeden widoczny budżet) warstwa jest przezroczysta dla
  /// gestów — oddaje swipe dziecku (np. swipe zakładek na Dashboardzie).
  final bool enabled;

  const ScopeSwipeArea({super.key, required this.child, this.enabled = true});

  /// Minimalna prędkość gestu (px/s), by uznać go za świadome przełączenie.
  static const double minVelocity = 240;

  /// Krok po liście budżetów dla gestu o danej prędkości poziomej: +1
  /// (kolejny) albo -1 (poprzedni); `null`, gdy gest za słaby (poniżej
  /// [minVelocity]). Czysta funkcja pod test-strażnik (próg + kierunek).
  static int? stepForVelocity(double primaryVelocity) {
    if (primaryVelocity.abs() < minVelocity) return null;
    return primaryVelocity < 0 ? 1 : -1;
  }

  @override
  State<ScopeSwipeArea> createState() => _ScopeSwipeAreaState();
}

class _ScopeSwipeAreaState extends State<ScopeSwipeArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _slide;

  String? _lastBudgetId;
  // Kierunek wjazdu nowej treści: +1 z prawej (kolejny budżet), -1 z lewej.
  double _dir = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1, // start w spoczynku (bez przesunięcia)
    );
    _slide = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onDragEnd(DragEndDetails d) {
    final step = ScopeSwipeArea.stepForVelocity(d.primaryVelocity ?? 0);
    if (step == null) return;
    final ctrl = context.read<BudgetController>();
    final before = ctrl.budgetId;
    ctrl.stepBudget(step);
    if (ctrl.budgetId != before) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    // Tryb jednozakresowy: nie przechwytujemy gestu — dziecko dostaje swipe
    // (np. TabBarView Dashboardu przełącza Bilans/Plan).
    if (!widget.enabled) return widget.child;

    final ctrl = context.watch<BudgetController>();
    final id = ctrl.budgetId;
    if (_lastBudgetId != null && _lastBudgetId != id) {
      // Kolejny budżet z listy → nowa treść wjeżdża z prawej (+1),
      // poprzedni → z lewej (-1). Animacja po klatce (nie w trakcie build).
      final ids = [for (final b in ctrl.visibleBudgets) b.id];
      _dir = ids.indexOf(id) > ids.indexOf(_lastBudgetId!) ? 1 : -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _anim.forward(from: 0);
      });
    }
    _lastBudgetId = id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) => _onDragEnd(d),
      child: AnimatedBuilder(
        animation: _slide,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset((1 - _slide.value) * 24 * _dir, 0),
          child: child,
        ),
      ),
    );
  }
}
