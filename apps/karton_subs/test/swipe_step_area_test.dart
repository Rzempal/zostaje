import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/widgets/swipe_step_area.dart';

// Strażnik decyzji gestu przesunięcia: próg prędkości (ukośny ruch przy
// przewijaniu listy nie zmienia okresu) + kierunek → krok naprzód / wstecz
// (w Planowaniu: następny / poprzedni miesiąc albo rok).
void main() {
  group('SwipeStepArea.stepForVelocity', () {
    test('gest poniżej progu nie robi kroku (null)', () {
      expect(SwipeStepArea.stepForVelocity(0), isNull);
      expect(SwipeStepArea.stepForVelocity(100), isNull);
      expect(SwipeStepArea.stepForVelocity(-239.9), isNull);
    });

    test('flick w lewo (prędkość ujemna) → krok naprzód', () {
      expect(SwipeStepArea.stepForVelocity(-240), 1);
      expect(SwipeStepArea.stepForVelocity(-1200), 1);
    });

    test('flick w prawo (prędkość dodatnia) → krok wstecz', () {
      expect(SwipeStepArea.stepForVelocity(240), -1);
      expect(SwipeStepArea.stepForVelocity(1200), -1);
    });

    test('próg jest inkluzywny na granicy', () {
      expect(SwipeStepArea.stepForVelocity(SwipeStepArea.minVelocity), -1);
      expect(SwipeStepArea.stepForVelocity(-SwipeStepArea.minVelocity), 1);
    });
  });
}
