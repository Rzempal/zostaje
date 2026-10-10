/// Klucz sortowania po polsku, bez biblioteki porównań: małe litery, a litera
/// z ogonkiem staje tuż po swojej podstawowej (a < ą < b, z < ź < ż) —
/// „Śnieżek" ląduje po „Software", a nie na końcu listy, jak przy zwykłym
/// porównaniu znaków.
String plSortKey(String text) {
  final key = StringBuffer();
  for (final ch in text.toLowerCase().trim().runes) {
    final mapped = _plLetters[ch];
    if (mapped == null) {
      key.writeCharCode(ch);
    } else {
      key.write(mapped);
    }
  }
  return key.toString();
}

/// Litera podstawowa + znacznik za „z" (`{`, a dla ż — `|`): wszystko, co
/// zaczyna się od „a", przed tym, co od „ą".
const _plLetters = {
  0x105: 'a{', // ą
  0x107: 'c{', // ć
  0x119: 'e{', // ę
  0x142: 'l{', // ł
  0x144: 'n{', // ń
  0xF3: 'o{', // ó
  0x15B: 's{', // ś
  0x17A: 'z{', // ź
  0x17C: 'z|', // ż
};
