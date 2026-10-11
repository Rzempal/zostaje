import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Warstwa gestu: poziomy „flick" robi krok naprzód albo wstecz — w Planowaniu
/// następny / poprzedni miesiąc (w widoku roku — rok).
///
/// Kierunek jak przy przewracaniu kartek: palec w lewo → krok naprzód (+1),
/// palec w prawo → wstecz (-1). Nowa treść wjeżdża z tej strony, z której
/// przychodzi, a telefon krótko wibruje.
///
/// Owija samą treść ekranu (nie przełącznik ani filtry). Głębsze paski
/// przewijane w bok (filtr kategorii, pigułki części) wygrywają gest u siebie,
/// a pionowy scroll listy działa bez zmian (inna oś).
///
/// Krok wymaga wyraźnej prędkości ([minVelocity]) — ukośny ruch przy
/// przewijaniu listy nie zmienia okresu.
class SwipeStepArea extends StatefulWidget {
  final Widget child;

  /// Krok: +1 (naprzód) albo -1 (wstecz).
  final ValueChanged<int> onStep;

  const SwipeStepArea({super.key, required this.child, required this.onStep});

  /// Minimalna prędkość gestu (px/s), by uznać go za świadomy krok.
  static const double minVelocity = 240;

  /// Krok dla gestu o danej prędkości poziomej: +1 (naprzód) albo -1
  /// (wstecz); `null`, gdy gest za słaby (poniżej [minVelocity]). Czysta
  /// funkcja pod test-strażnik (próg + kierunek).
  static int? stepForVelocity(double primaryVelocity) {
    if (primaryVelocity.abs() < minVelocity) return null;
    return primaryVelocity < 0 ? 1 : -1;
  }

  @override
  State<SwipeStepArea> createState() => _SwipeStepAreaState();
}

class _SwipeStepAreaState extends State<SwipeStepArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _slide;

  // Kierunek wjazdu nowej treści: +1 z prawej (naprzód), -1 z lewej.
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
    final step = SwipeStepArea.stepForVelocity(d.primaryVelocity ?? 0);
    if (step == null) return;
    widget.onStep(step);
    HapticFeedback.selectionClick();
    _dir = step.toDouble();
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _onDragEnd,
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
