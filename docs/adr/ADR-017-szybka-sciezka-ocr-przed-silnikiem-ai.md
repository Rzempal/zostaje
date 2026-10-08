# ADR-017: Szybka ścieżka skanu — zwykły OCR + reguły przed silnikiem AI

Data: 2026-07-25
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — skan paragonów usunięty, ML Kit nie jest już w aplikacji

## Kontekst

Skan rachunku (ADR-013) w całości opierał się na modelu językowym w apce-silniku:
każde zdjęcie, niezależnie od tego jak przewidywalny miało układ, kosztowało
~45–180 s pracy procesora i niosło ryzyko halucynacji. Dwa problemy okazały się
uporczywe:

1. **Rok w dacie.** Model nie ma zegara. Dokument z samym dniem i miesiącem
   („sobota, 25 lip" na zrzucie z Google Wallet) wracał z rokiem zmyślonym —
   najczęściej poprzednim. Heurystyka po stronie aplikacji (ADR-016 pkt 4) łata
   objaw, ale nie przyczynę: rok, którego na dokumencie nie ma, zgadujemy.
2. **Limity czasu.** Gęsty paragon fiskalny to dużo tekstu do wygenerowania;
   zdarzały się przekroczenia limitu i zerowy wynik po kilku minutach.

Tymczasem dwie najczęstsze klasy dokumentów właściciela mają **sztywny układ**:
paragon fiskalny (`PARAGON FISKALNY`, `SUMA PLN <kwota>`, pełna data ISO) oraz
zrzut płatności telefonem (sprzedawca, `12,00 zł`, „sobota, 25 lip o 11:23").
Do ich odczytania model językowy nie jest potrzebny — wystarczy tekst i reguły.

## Decyzja

Przed sięgnięciem po silnik AI aplikacja próbuje **szybkiej ścieżki**:

1. `TextOcrService` czyta zdjęcie zwykłym OCR tekstowym (ML Kit Text Recognition
   w wariancie **bundled** — model w APK, bez Google Play Services i bez sieci,
   więc „zero chmury" zostaje nienaruszone). Przy braku trafienia zdjęcie jest
   obracane (90°/270°/180°) i czytane ponownie — paragony fotografuje się
   w poprzek, a OCR czyta tekst poziomy.
2. `ReceiptTextParser` (czysty Dart, bez zależności) dopasowuje wzorce:
   - **Paragon fiskalny** — kwota z etykiety `SUMA PLN` (nigdy `SUMA PTU`, to sam
     podatek), data ISO z wydruku, sprzedawca z nagłówka (pomijając NIP i adres).
   - **Zrzut płatności** — kwota `X,XX zł`, sprzedawca z linii nad kwotą
     (z pominięciem paska stanu telefonu), data z „dzień tygodnia, dzień miesiąc".
   - **Potwierdzenie z portfela** — układ etykieta–wartość (`Data:`, `Kwota:`),
     patrz rozszerzenie z 2026-08-20.
3. Trafienie → pozycja gotowa w ~1–2 s. Brak trafienia albo brak pewnej kwoty →
   dokument przejmuje silnik AI, dokładnie jak dotąd.

**Rok przestaje być zgadywany.** Paragon drukuje pełną datę. Zrzut z Wallet podaje
dzień tygodnia, który jednoznacznie wskazuje rok: „sobota, 25 lip" to 2026, bo
25 lipca 2025 wypadał w piątek. Kotwica roku z ADR-016 zostaje wyłącznie dla
ścieżki modelowej.

Reguły są **zachowawcze**: brak pewnej kwoty oznacza brak wyniku. Wolniejsze
rozpoznanie jest tańsze niż zła kwota w budżecie.

## Konsekwencje

- (+) Paragony i płatności telefonem rozpoznawane w ~1–2 s zamiast ~45–180 s,
  bez limitów czasu, bez grzania telefonu i bez ładowania modelu.
- (+) Data i kwota czytane dosłownie z dokumentu — zero halucynacji w klasach,
  które stanowią większość codziennych skanów.
- (+) Silnik AI zostaje do tego, w czym jest niezastąpiony: faktur i rachunków
  o dowolnym układzie.
- (−) APK rośnie o model rozpoznawania tekstu (rząd kilku MB).
- (−) Reguły trzeba dopisywać per nowy typ dokumentu; nietrafiony wzorzec nie psuje
  jednak niczego — sprawę przejmuje silnik.
- (−) Nietrafione zdjęcie kosztuje do czterech przebiegów OCR (obroty), czyli
  ~2–3 s dodatkowego opóźnienia przed startem silnika.
- Testy regułowe opierają się na tekstach z realnych dokumentów właściciela
  (`test/receipt_text_parser_test.dart`) — nowy typ dokumentu = nowy przypadek
  testowy z jego surowym tekstem.

## Rozszerzenie (2026-07-27): trzeci wzorzec — faktura

Skoro szybka ścieżka jest domyślną (a silnik tylko wspomaga — patrz korekta
decyzji 3 w ADR-013), zakres reguł przestał być wygodą, a stał się granicą
tego, co apka potrafi sama. Doszedł więc wzorzec **faktury**, oparty na
etykietach dokumentu, nie na pozycji tekstu:

- **Kwota:** „Pozostało / Razem / Kwota do zapłaty", „Należność" — szukane
  TYLKO w przód, bo nad tą etykietą kończy się tabela VAT i spojrzenie wstecz
  podstawiało kwotę podatku. Gdy brak takiej etykiety albo wynosi 0,00
  (dokument już opłacony) — suma przy „Razem", z okna brana NAJWIĘKSZA kwota,
  bo obok stoją netto i podatek.
- **Data:** termin płatności → data wystawienia → data sprzedaży; szukana
  w obie strony, bo w układzie dwukolumnowym etykieta bywa POD wartością.
- **Wystawca:** linia przy „Sprzedawca" (pod nią, a gdy tam są dane rejestrowe
  — nad); adresy odpadają po kodzie pocztowym i numerze na końcu linii.

Dwie pułapki warte zapamiętania (obie kosztowały błędny odczyt na prawdziwym
dokumencie): daty w formacie `15.09.2023` pasują do wzorca kwoty jako `15,09`,
więc są wycinane z linii przed szukaniem liczb; a „wartość brutto" to nagłówek
KOLUMNY w zestawieniu VAT, pod którym idą kolejno netto, podatek i brutto —
oparcie sumy na tej etykiecie podstawiało kwotę netto.

Zweryfikowane na trzech prawdziwych fakturach właściciela (kwota, data
i wystawca trafione w każdej); dokumenty zostają lokalnie, testy odwzorowują
ich układ na danych zmienionych.

---

## Rozszerzenie (2026-08-20): czwarty wzorzec — potwierdzenie z portfela

Samsung Wallet pokazuje po płatności ekran o stałym układzie etykieta–wartość:
nagłówek „Potwierdzenie", nazwa sklepu, a pod nią `Data:`, `Nazwa karty:`,
`Stan:` i `Kwota:`. Doszedł wiec czwarty wzorzec, czytany tak samo pewnie jak
paragon fiskalny — z **pełną datą dzienną**, więc znów bez zgadywania roku.

**Kotwicą jest nagłówek RAZEM z etykietami** (co najmniej dwie z czterech).
Samo słowo „Potwierdzenie" nie wystarcza, bo tak samo tytułowane jest bankowe
potwierdzenie przelewu. Etykiety sprawdzamy od POCZĄTKU linii i z dwukropkiem —
inaczej „Kwota A 23,00%" z paragonu fiskalnego udawałaby etykietę kwoty.

**Stan płatności („Zatwierdzone" / „Odrzucone") nie wpływa na odczyt.** Kuszące
było odrzucanie dokumentów o innym stanie, ale szybka ścieżka nie ma kanału
„odrzuć ten dokument": zwrócenie pustego wyniku oddałoby odrzuconą płatność
silnikowi AI, który wpisałby kwotę i tak — tylko wolniej i bez pokazania stanu.
Pozycja czeka w „Do zatwierdzenia" ze zdjęciem obok, więc decyzja i tak należy
do użytkownika.

**Data jest opcjonalna, kwota nie.** Nagłówek i etykiety rozpoznają dokument
pewnie, więc nieudany odczyt samej daty nie jest powodem, żeby posyłać
sekundowy odczyt do czterdziestosekundowego silnika.

**Wartość bywa oddalona od swojej etykiety — pary trzeba składać pozycyjnie.**
Prawdziwy odczyt tego ekranu (podgląd w Developer Tools) zwraca DWIE KOLUMNY:
najpierw wszystkie etykiety, potem wszystkie wartości, a nazwa sklepu na czele
bloku wartości (na ekranie stoi nad nimi). Kwota leżała więc cztery linie od
etykiety `Kwota:` i przy 0° nie była znajdowana w ogóle — odczyt udawał się
dopiero po obróceniu zdjęcia o 90°, gdzie pary sąsiadują. Reguła składa teraz
pary **pozycyjnie**, gdy etykiety tworzą ciąg: n-ta wartość należy do n-tej
etykiety, a nadmiarowa linia na czele bloku to nazwa. Dokument czyta się dzięki
temu bez obracania, czyli jednym przebiegiem OCR zamiast dwoma.

**Gdy nazwy w bloku wartości nie ma, pole zostaje puste.** Nazwa karty i status
też są „sensownymi" liniami, więc luźniejsza reguła wpisywałaby do nazwy
wydatku „Millennium VISA Konto 360". Puste pole jest uczciwsze.

**Żadne pole nie może opierać się na pozycji w odczycie.** Pierwsza wersja
brała nazwę sklepu jako „pierwszą sensowną linię POD nagłówkiem" — na telefonie
wychodziła pusta, choć kwota i data były poprawne. OCR zwraca tekst **blokami**
i nie obiecuje kolejności wizualnej: „Potwierdzenie" to mały, osobny blok
w rogu ekranu, który potrafi trafić w odczycie za nazwę albo nawet za tabelę.
Kwota i data przeżyły to bez szwanku, bo szuka się ich po etykietach. Nazwa
bierze więc pierwszą sensowną linię PRZED pierwszą etykietą, a sam nagłówek
jest z kandydata wycinany (bywa z nazwą sklejony w jedną linię).

**Nazwa karty jest czytana, ale nieużywana.** Kusi, żeby podstawić z niej metodę
płatności (u właściciela decyduje ona o automacie karty kredytowej, ADR-033),
ale wymagałoby to przeciągnięcia nowego pola przez cały łańcuch skanu aż do
formularza. Świadomie odłożone; dziś służy tylko jako element kotwicy.

**Podgląd surowego odczytu (Developer Tools).** Reguły dostają tekst złożony
z bloków, a nie to, co widać na ekranie — bez możliwości zajrzenia w ten tekst
każda nietrafiona reguła kończy się zgadywaniem układu i kolejnym wydaniem
„na próbę". Kafelek „Ostatni odczyt OCR" pokazuje wynik ostatniego skanu
(wszystkie próbowane obroty) z przyciskiem kopiowania. Tekst siedzi w pamięci
procesu jak bufor logów, nigdzie nie jest zapisywany, a Developer Tools istnieje
tylko na kanale DEV — więc zasada „dane nie opuszczają urządzenia" zostaje
nienaruszona.

