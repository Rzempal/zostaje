import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/utils/text_sort.dart';

// Kolejność alfabetyczna po polsku (kategorie, ADR-038): litera z ogonkiem
// tuż po podstawowej, bez względu na wielkość liter.
void main() {
  List<String> sorted(List<String> names) =>
      [...names]..sort((a, b) => plSortKey(a).compareTo(plSortKey(b)));

  test('polskie litery stają po swoich podstawowych, nie na końcu', () {
    expect(sorted(['Zdrowie', 'Śnieżek', 'Software', 'auto', 'Ąbc']), [
      'auto',
      'Ąbc',
      'Software',
      'Śnieżek',
      'Zdrowie',
    ]);
  });

  test('z < ź < ż, wielkość liter bez znaczenia', () {
    expect(sorted(['żaba', 'Źrebak', 'zebra']), ['zebra', 'Źrebak', 'żaba']);
    expect(plSortKey('Dom'), plSortKey(' dom '));
  });
}
