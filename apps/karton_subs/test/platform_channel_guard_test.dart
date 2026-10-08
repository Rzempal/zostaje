import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// STRAŻNIK KANAŁU PLATFORMOWEGO.
///
/// Nazwy metod kanału to napisy — Dart je wysyła, Kotlin je odbiera, a te dwie
/// strony **nie kompilują się razem**. Przemianowanie po stronie Darta nie jest
/// więc błędem kompilacji: rozjazd wychodzi dopiero na telefonie, jako funkcja,
/// która nagle „nie działa na tym urządzeniu".
///
/// Zdarzyło się to naprawdę: refaktor nazw (ADR-032) zamienił `startBillScan`
/// na `startReceiptScan` po stronie Darta, Kotlin został przy starej nazwie
/// i skanowanie paragonów przestało działać — a komunikat twierdził, że to nie
/// Android. Analiza była czysta, 373 testy przechodziły.
///
/// Ten test czyta OBIE strony i porównuje je ze sobą.
void main() {
  // Most do silnika AI zniknął razem ze skanem paragonów (ADR-035); został
  // sejf na kod odzyskiwania kopii.
  final dartSources = ['lib/services/recovery_key_vault.dart'];
  const kotlinDir = 'android/app/src/main/kotlin';

  /// Nazwy metod, które Dart WYSYŁA.
  ///
  /// Nazwa bywa wpisana wprost (`invokeMethod('foo')`) albo podana stałą
  /// (`invokeMethod(methodFoo)`) — strażnik musi rozumieć oba zapisy, inaczej
  /// samo wyciągnięcie napisu do stałej robi w nim ślepą plamę.
  Set<String> methodsSentByDart() {
    final call = RegExp(
      r"invoke\w*Method(?:<[^>]*>)?\(\s*(?:'([a-zA-Z]+)'|([A-Za-z_]\w*))",
    );
    final constant = RegExp(r"static\s+const\s+(\w+)\s*=\s*'([a-zA-Z]+)'");
    final out = <String>{};
    for (final path in dartSources) {
      final source = File(path).readAsStringSync();
      final consts = {
        for (final m in constant.allMatches(source)) m.group(1)!: m.group(2)!,
      };
      for (final m in call.allMatches(source)) {
        final literal = m.group(1);
        if (literal != null) {
          out.add(literal);
          continue;
        }
        final resolved = consts[m.group(2)];
        if (resolved != null) out.add(resolved);
      }
    }
    return out;
  }

  /// Nazwy, które Kotlin OBSŁUGUJE w `when (call.method)`: `"nazwa" ->`.
  Set<String> methodsHandledByKotlin() {
    final pattern = RegExp(r'"([a-zA-Z]+)"\s*->');
    return {
      for (final f in Directory(kotlinDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt')))
        ...pattern.allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
    };
  }

  test('każda metoda wołana z Darta jest obsłużona w Kotlinie', () {
    final sent = methodsSentByDart();
    final handled = methodsHandledByKotlin();

    expect(sent, isNotEmpty, reason: 'test przestał znajdować wywołania');
    expect(handled, isNotEmpty, reason: 'test przestał czytać źródeł Kotlina');

    final missing = sent.difference(handled).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'Dart woła metody, których warstwa natywna nie zna: $missing.\n'
          'Na telefonie objawi się to jako „funkcja niedostępna", a nie jako '
          'błąd kompilacji. Popraw nazwę po jednej ze stron.',
    );
  });
}
