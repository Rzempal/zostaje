import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/utils/cycle_math.dart';

void main() {
  group('occurrencesInRange', () {
    test('miesięczny — dzień kotwicy w docelowym miesiącu', () {
      final r = occurrencesInRange(DateTime(2026, 1, 10), BillingCycle.monthly,
          null, DateTime(2026, 3, 1), DateTime(2026, 3, 31));
      expect(r, [DateTime(2026, 3, 10)]);
    });

    test('miesięczny — clamp dnia 31 do długości lutego', () {
      final r = occurrencesInRange(DateTime(2026, 1, 31), BillingCycle.monthly,
          null, DateTime(2026, 2, 1), DateTime(2026, 2, 28));
      expect(r, [DateTime(2026, 2, 28)]);
    });

    test('tygodniowy — wiele wystąpień w miesiącu', () {
      final r = occurrencesInRange(DateTime(2026, 3, 2), BillingCycle.weekly,
          null, DateTime(2026, 3, 1), DateTime(2026, 3, 31));
      expect(r, [
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 16),
        DateTime(2026, 3, 23),
        DateTime(2026, 3, 30),
      ]);
    });

    test('roczny — tylko w miesiącu kotwicy', () {
      final julyAnchor = DateTime(2025, 7, 15);
      final inJuly = occurrencesInRange(julyAnchor, BillingCycle.yearly, null,
          DateTime(2026, 7, 1), DateTime(2026, 7, 31));
      final inAugust = occurrencesInRange(julyAnchor, BillingCycle.yearly, null,
          DateTime(2026, 8, 1), DateTime(2026, 8, 31));
      expect(inJuly, [DateTime(2026, 7, 15)]);
      expect(inAugust, isEmpty);
    });

    test('brak wystąpień przed kotwicą', () {
      final r = occurrencesInRange(DateTime(2026, 5, 10), BillingCycle.monthly,
          null, DateTime(2026, 4, 1), DateTime(2026, 4, 30));
      expect(r, isEmpty);
    });
  });

}
