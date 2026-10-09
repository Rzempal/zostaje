import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/widgets/scope_swipe_area.dart';

// Strażnik decyzji gestu przełączania budżetu: próg prędkości (ochrona przed
// przypadkowym przełączeniem globalnego stanu) + kierunek → krok po liście
// budżetów (ADR-037).
void main() {
  group('ScopeSwipeArea.stepForVelocity', () {
    test('gest poniżej progu nie przełącza (null)', () {
      expect(ScopeSwipeArea.stepForVelocity(0), isNull);
      expect(ScopeSwipeArea.stepForVelocity(100), isNull);
      expect(ScopeSwipeArea.stepForVelocity(-239.9), isNull);
    });

    test('flick w lewo (prędkość ujemna) → kolejny budżet', () {
      expect(ScopeSwipeArea.stepForVelocity(-240), 1);
      expect(ScopeSwipeArea.stepForVelocity(-1200), 1);
    });

    test('flick w prawo (prędkość dodatnia) → poprzedni budżet', () {
      expect(ScopeSwipeArea.stepForVelocity(240), -1);
      expect(ScopeSwipeArea.stepForVelocity(1200), -1);
    });

    test('próg jest inkluzywny na granicy', () {
      expect(ScopeSwipeArea.stepForVelocity(ScopeSwipeArea.minVelocity), -1);
      expect(ScopeSwipeArea.stepForVelocity(-ScopeSwipeArea.minVelocity), 1);
    });
  });
}
