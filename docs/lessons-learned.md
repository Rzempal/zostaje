# 🧠 Lessons Learned

> **Powiązane:** [Standardy](conventions.md) | [Roadmap](roadmap.md)

---

## 2026-10-10: Znak spoza fontu telefonu stoi krzywo („→")

### Problem
W podpisach pozyczek („+6 000,00 → splata 10 paz −6 000,00") strzalka byla mala
i siedziala przy dolnej krawedzi malych liter, a minus i polpauza wyzej. `analyze`
i testy tego nie widza — czcionka testowa rysuje kazdy znak jako kwadrat.

### Przyczyna
Aplikacja nie ma wlasnego fontu, tekst idzie systemowym Roboto. Roboto nie ma znaku
„→" (sprawdzone w pliku fontu), wiec telefon bierze go z fontu zastepczego o innych
proporcjach. Polpauza „–", minus „−", plus, „·" i „×" sa w Roboto i stoja razem
na srodku wysokosci cyfr.

### Rozwiazanie
Strzalka jako ikona w tekscie: `planArrowSpan` (Lucide `moveRight`,
`PlaceholderAlignment.middle`) — srodek linii, czyli wysokosc cyfr i minusa; rosnie
razem z tekstem przy wiekszej czcionce systemowej.

### Wniosek
Przed uzyciem znaku spoza podstawowego alfabetu (strzalki, symbole) sprawdz, czy jest
w Roboto. Jesli nie — ikona albo slowo, nie znak. Zostaja jeszcze „→" w podpowiedziach
i menu (np. „Sortuj: A→Z", „Ustawienia → Metody platnosci") — do poprawy osobno.

---

## 2026-08-04: Co lezy w sejfie systemowym, nie przezyje wymiany telefonu

### Problem
Scenariusz „nowy telefon + kopia z Dysku": dane budzetu domowego wracaja
komplenie, ale synchronizacja z druga osoba nie. Gorzej — nie dalo sie do niej
wrocic: kod QR gospodarstwa powstawal tylko przy zakladaniu, wiec telefon zony
nie mial czego pokazac. Jedyne wyjscie to bylo zalozenie gospodarstwa od nowa,
czyli rozlaczenie obu stron.

### Przyczyna
Parowanie (adres skrzynki + klucz) trzymamy w sejfie systemowym (Keystore) i to
jest sluszne — w kopii zapasowej byloby wydaniem tresci budzetu kazdemu, kto ma
dostep do Dysku. Ale sejf **nie przenosi sie miedzy urzadzeniami**, wiec kazda
funkcja oparta o sekret w sejfie musi miec wlasna, swiadomie zaprojektowana
sciezke odtworzenia. Tej brakowalo: `salt` istnial wylacznie w pamieci podczas
zakladania gospodarstwa, a z klucza nie da sie go wyliczyc wstecz.

### Rozwiazanie
`salt` zapisany razem z parowaniem + akcja „Pokaz kod QR" na sparowanym telefonie
(ADR-009, uzupelnienie). Sekret nie oslabl: sol i tak jedzie jawnie w kodzie QR,
a cala ochrona stoi na hasle przekazywanym ustnie. Ten sam problem rozwiazano
wczesniej inaczej dla kopii w chmurze — kod odzyskiwania lezy obok kopii na
Dysku (ADR-024), wiec odtworzenie dziala bez przepisywania go z kartki.

### Wniosek
Przy kazdym sekrecie w sejfie zadaj pytanie „co sie stanie przy wymianie
telefonu" — i odpowiedz na nie w kodzie, nie w instrukcji. Odpowiedzi sa dwie:
albo sekret da sie odtworzyc z drugiego urzadzenia (QR), albo lezy w miejscu,
ktore uzytkownik odzyskuje razem z kontem. Brak odpowiedzi wychodzi dopiero
przy realnej wymianie telefonu — czyli w najgorszym momencie.

## 2026-08-02: Schemat numeracji wersji ma SUFIT — sprawdz go, zanim go zbudujesz

### Problem
Deploy wersji 0.21 nie zbudowal sie: `buildNumber: 2126080203 is greater than
the maximum allowed value of 2100000000`. Wzor `Major*10^9 + Minor*10^8 +
yyMMDDcc` przekracza twardy limit Androida na **kazdej** wersji od 0.21 wzwyz
(a takze na 1.11 i 2.1). Nie „kiedys zabraknie" — 0.20 bylo ostatnim mozliwym
minorem, i dowiedzielismy sie o tym w momencie, gdy chcielismy wydac kolejny.

### Pulapka w naprawie
`versionCode` **nie moze zmalec** — Android odrzuca APK z mniejszym numerem jako
cofniecie wersji, a OTA porownuje dokladnie ten numer. Wszystkie „czyste"
rozwiazania (licznik od 1, sama data bez bazy) daja liczbe MNIEJSZA od juz
zainstalowanej, wiec sa nie do uzycia bez odinstalowania aplikacji.

### Rozwiazanie
`versionCode = 2 000 000 000 + yyMMDDcc` — baza sztuczna, ale trzyma numer nad
zainstalowanym; data zapewnia wzrost. Do tego straznik w skrypcie deployu, ktory
przerywa PRZED buildem, bo inaczej blad wychodzi po kilku minutach kompilacji
komunikatem Gradle, ktory nie mowi, co z nim zrobic. Szczegoly: ADR-031.

### Wniosek
Projektujac schemat numeracji, **policz jego maksimum i sprawdz limit
platformy** (Android: 2 100 000 000). Wzor z mnoznikami zjada zakres wykladniczo:
kazdy skladnik przesuniety o rzad wielkosci to dziesieciokrotnie mniej miejsca
dla reszty. I pamietaj, ze numeru, ktory raz trafil na urzadzenie, nie da sie
juz obnizyc — schemat jest decyzja jednokierunkowa.

---

## 2026-08-02: Wlasne teksty po polsku to NIE to samo, co polska aplikacja

### Problem
Okna wyboru daty (`showDatePicker`) otwieraly sie po **angielsku**: „August 2026",
„Sun, Aug 2", przyciski „Cancel / OK", tydzien od niedzieli — w aplikacji, ktorej
kazdy wlasny napis jest po polsku. Wygladalo to na blad losowy („niektore
kalendarze"), a bylo systematyczne: **wszystkie** widgety Materiala.

### Przyczyna
Dwa niezalezne mechanizmy jezykowe:
- `DateFormat('LLLL yyyy', 'pl')` — formatowanie WLASNYCH napisow, ustawiane
  przy kazdym wywolaniu. Tego uzywalismy wszedzie i to dzialalo.
- **Delegaty lokalizacji w `MaterialApp`** — jezyk widgetow gotowych
  (kalendarz, przyciski dialogow, etykiety dostepnosci, pierwszy dzien tygodnia).
  Tych nie bylo, wiec Flutter uzywal domyslnego angielskiego.

`initializeDateFormatting('pl_PL')` w `main()` zalatwia tylko pierwszy punkt —
stad zludzenie, ze „polski jest juz ustawiony".

### Rozwiazanie
`flutter_localizations` + w `MaterialApp`: `locale: Locale('pl')`,
`supportedLocales`, trzy delegaty (`GlobalMaterialLocalizations`,
`GlobalWidgetsLocalizations`, `GlobalCupertinoLocalizations`).

### Wniosek
Jesli aplikacja ma jeden jezyk, ustaw go **w `MaterialApp` od pierwszego dnia** —
inaczej kazde gotowe okno systemowe (data, czas, `showLicensePage`, menu
kontekstowe pola tekstowego) bedzie po angielsku, a zauwazysz to dopiero, gdy
uzytkownik trafi na konkretny ekran. Blad zyl tu **kilkanascie wydan**, bo apka
formatuje wlasne daty sama i nikt nie mial powodu podejrzewac `MaterialApp`.

---

## 2026-08-01: Usuwajac widget platformy, sprawdz, co robil ZA CIEBIE

### Problem
Po usunieciu paskow tytulu (ADR-026) na jasnym motywie pasek stanu telefonu
potrafil pokazywac **biale ikony na bialym tle** — godzina i bateria nie do
odczytania. Objaw byl kapryśny („czasem"), wiec dlugo wygladal na blad systemu,
a nie aplikacji.

Przyczyna: `AppBar` — poza rysowaniem paska tytulu — **ustawia styl ikon paskow
systemowych** (`SystemUiOverlayStyle`). Gdy zniknal ostatni `AppBar` z ekranow
roboczych, nikt juz nie mowil systemowi, czy ikony maja byc ciemne czy biale;
zostawal stan po ostatnim ekranie, ktory to ustawil (podekran Ustawien) albo
motyw okna Androida. Stad „czasem".

### Rozwiazanie
Deklaracja stylu **raz dla calej aplikacji**: `AnnotatedRegion` w
`MaterialApp.builder`, liczona z jasnosci aktywnej palety. Deklaratywnie, nie
przez `SystemChrome`: ekran z wlasnym `AppBar` nadpisuje styl na czas swojego
zycia, a po powrocie znow obowiazuje deklaracja z powloki. Do tego ten sam styl
w `appBarTheme.systemOverlayStyle` i `windowLightStatusBar` w `styles.xml`
(klatka startowa, zanim Flutter cokolwiek narysuje).

### Wniosek
Widgety platformowe (`AppBar`, `Scaffold`, `SafeArea`) niosa **efekty uboczne
poza swoim pikselem**. Przy usuwaniu takiego widgetu wypisz, co jeszcze robil —
tu byly dwie rzeczy: odstep od paska stanu (zalatwione `SafeArea` juz w ADR-026)
i kolor ikon systemowych (znalezione dopiero z realnego uzycia, dwa wydania
pozniej). Objaw „czasem dziala" prawie zawsze znaczy: **ktos inny ustawia ten
stan globalnie i kolejnosc ekranow decyduje o wyniku.**

---

## 2026-07-26: „Import backupu" domyslnie SCALAL zamiast odtwarzac — ciche zawyzenie sum

### Problem
Import przechodzil po pozycjach z pliku i zapisywal kazda po `id`, ale nie usuwal
tego, czego w pliku NIE BYLO. Przy przeniesieniu danych z DEV na PROD pozycje
usuniete w DEV zostaly w PROD i **doliczyly sie do sum** — podsumowanie miesiaca
urosło o 1455,49 zl. Zadnego sygnalu: komunikat mowil tylko, ile pozycji wczytano.
Przy okazji wyszlo, ze Planner („Na rachunki") w ogole nie wchodzil do backupu,
choc pomniejsza plan „zostaje/mies".

### Rozwiazanie
Pytanie o tryb przed importem: **Odtworz stan z pliku** (domyslne, czysci dane objete
backupem) albo **Scal**. Podsumowanie po imporcie mowi wprost, ile pozycji usunieto.
Planner dopisany do formatu (wersja 6). Szczegoly: ADR-021.

### Pulapka w samej poprawce (regresja tego samego dnia)
Pierwsza wersja trybu „Odtworz" czyscila WSZYSTKIE obszary bezwarunkowo. Odtworzenie
ze **starszego pliku** (v5, bez pola Plannera) skasowalo wiec Planner i nie mialo czym
go wypelnic — utrata danych wprost z poprawki, ktora miala chronic dane.

Reguła: **nigdy nie kasuj obszaru, ktorego zrodlo nie pokrywa.** `clearForRestore` ma
flage per obszar, a import ustawia je na podstawie pol faktycznie obecnych w pliku.

### Wniosek
Jesli funkcja nazywa sie „backup", to jej import ma **odtwarzac stan**, a nie dokladac
dane. Rozjazd miedzy nazwa a zachowaniem daje bledy, ktorych uzytkownik nie ma jak
zauwazyc — tu ujawnil sie tylko dlatego, ze suma miesiaca „wygladala dziwnie".
Przy kazdym rozszerzeniu modelu sprawdz, czy nowe pole trafia do eksportu: Planner
przezyl w kodzie dwa ADR-y (012, 019), zanim ktos zauwazyl, ze go tam nie ma. A przy
kazdej operacji „wyczysc i wgraj" sprawdz, co plik **naprawde** zawiera.

---

## 2026-07-26: Usuwanie wartosci z enuma modelu wymaga JAWNEGO mapowania w `fromJson`

### Problem
Przy scalaniu typow (`oneTimeExpense` → `billPayment`, ADR-018) usuniecie wartosci
z enuma wyglada na czysta operacje — kompilator wskazuje wszystkie `switch` do
poprawy. Ale deserializacja NIE jest sprawdzana przez kompilator:
`BudgetEntryType.values.firstWhere(..., orElse: () => recurringCost)` po cichu
zamienia kazda stara pozycje nieznanego typu w **koszt cykliczny**. Wydatek
jednorazowy 3000 zl zaczalby obciazac plan „zostaje/mies" CO MIESIAC, i to
naraz w bazie lokalnej, backupie `.zostaje` i synchronizacji domowej (wszystkie
ida tym samym parserem).

Przy ADR-011 (`bill` → `recurringCost`) problem nie wyszedl tylko dlatego, ze
domyslka przypadkiem byla poprawnym celem migracji. To bylo szczescie, nie projekt.

### Rozwiazanie
Kazdy usuniety typ dostaje **jawna linie mapowania** w dedykowanej funkcji
(`BudgetEntry.typeFromName`), a domyslka zostaje wylacznie dla wartosci naprawde
nieznanych. Do tego test-straznik, ktory sprawdza nie tylko sam typ po migracji,
ale i to, ze zmigrowana pozycja ma `monthlyAmount == 0` i nie rusza
`monthlySurplus` (`test/budget_type_migration_test.dart`).

### Wniosek
Usuwajac wartosc z enuma zapisywanego na dysk: najpierw znajdz `fromJson`, dopisz
alias, napisz test na STARY JSON — dopiero potem usuwaj wartosc. Parser formatu
Excela ma wlasne mapowanie po etykiecie i tez trzeba go poprawic osobno.

---

## 2026-07-26: `--target-platform android-arm64` nie przycina bibliotek natywnych wtyczek

### Problem
Po dodaniu OCR (ML Kit) APK urosl z 82 MB do 112 MB. Flaga
`flutter build apk --target-platform android-arm64` zbila go tylko do 70 MB —
w paczce nadal siedzialy biblioteki `armeabi-v7a` i `x86_64`. Flaga Fluttera
przycina wylacznie biblioteki SILNIKA Fluttera; natywne `.so` z wtyczek przychodza
z ich paczek AAR i jej nie respektuja.

### Rozwiazanie
Drugi filtr, na poziomie Gradle, w bloku `release` (`android/app/build.gradle.kts`):
```kotlin
ndk { abiFilters.clear(); abiFilters += "arm64-v8a" }
```
Efekt: 43 MB, czyli mniej niz przed dodaniem OCR. Filtr TYLKO w `release` — buildy
debug zostaja pelne, wiec emulator x86 dziala normalnie.

### Wniosek
Sprawdzaj efekt, nie ufaj fladze: `Expand-Archive` na APK i policz katalogi
`lib/<abi>/`. Kazdy taki APK nie zainstaluje sie na 32-bitowym telefonie.

---

## 2026-07-26: `bindService` nie obudzi apki w stanie „zatrzymana" bez `FLAG_INCLUDE_STOPPED_PACKAGES`

### Problem
Skan rachunku wymagal recznego uruchomienia apki-silnika przed pierwszym uzyciem.
Android trzyma aplikacje w stanie *stopped* (swieza instalacja, „wymus zatrzymanie",
uspienie nieuzywanej apki przez system) i **nie dopasowuje jej komponentow** do
intencji. `bindService` nie zglaszal bledu — polaczenie po prostu nigdy nie
dochodzilo do skutku.

### Rozwiazanie
`Intent(BIND_ACTION).setPackage(...).addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)`
plus **osobny limit czasu na samo polaczenie** (25 s), niezalezny od limitu pracy
silnika (300 s) — inaczej nieudany bind wyglada jak kilkuminutowe zawieszenie.

### Wniosek
Kazde wiazanie do uslugi w INNEJ aplikacji potrzebuje tej flagi. A gdy praca trwa
dziesiatki sekund, rozdzielaj limity: „nie moge sie polaczyc" i „silnik liczy za
dlugo" to dwa rozne bledy i dwie rozne rady dla uzytkownika.

---

## 2026-07-25: Flutter cache'uje `Image.file` po sciezce — podmiana w miejscu nie odswieza miniatury

### Problem
Przy przycinaniu zdjecia rachunku podmieniany plik nadpisywany „w tym samym miejscu"
(ta sama sciezka) nie odswiezal miniatury — `Image.file` pokazywal STARY kadr, mimo ze
plik na dysku byl juz przyciety. Powod: Flutter trzyma zdekodowany obraz w `ImageCache`
pod kluczem sciezki pliku; identyczna sciezka = trafienie w cache, nowa zawartosc
ignorowana. Dodatkowo to samo zdjecie bywa wspoldzielone przez kilka pozycji „Do
zatwierdzenia" (kilka rachunkow z jednego kadru) — nadpisanie w miejscu zepsuloby kadr
rodzenstwa.

### Rozwiazanie
Docietny wynik zapisywac zawsze pod **nowa nazwa pliku** (np. `<id>_<uuid>.jpg`),
zaktualizowac przechowywana sciezke i skasowac stary plik dopiero, gdy nie korzysta z
niego inna pozycja. Zmiana sciezki wymusza ponowne dekodowanie i odswiezenie widoku bez
recznego czyszczenia `ImageCache`. Zastosowane w `BillScanController.recrop` i
`replaceReceiptPhoto`.

### Wniosek
Gdy podmieniasz zawartosc pliku, ktory jest juz gdzies wyswietlany przez `Image.file`
(albo `FileImage`), **zmien sciezke**, nie nadpisuj w miejscu — inaczej cache pokaze
stara wersje. Alternatywa (`imageCache.evict(FileImage(...))`) jest mozliwa, ale nowa
sciezka jest prostsza i przy okazji chroni wspoldzielone pliki.

---

## 2026-07-24: Leciwe wtyczki Fluttera lamia build na nowym Gradle/Kotlinie

### Problem
Dodanie `receive_sharing_intent` (Udostepnij → Zostaje) wywalilo build na dwa sposoby:
- **1.9.0** — `android/build.gradle` wtyczki ma blok `kotlin { ... }` bez zaaplikowanego
  pluginu Kotlin → `Could not find method kotlin() ...`. Wersja jest po prostu zepsuta.
- **1.8.1** — wtyczka nie ustawia targetow JVM: jej Java kompiluje na 1.8, a Kotlin 2.x
  domyslnie celuje wyzej → `Inconsistent JVM Target Compatibility Between Java and Kotlin`.

`flutter analyze`/`flutter test` tego NIE wykryja — to blad na etapie Gradle (natywny build).

### Rozwiazanie
- Przypiac dzialajaca wersje na sztywno w `pubspec.yaml` (`receive_sharing_intent: 1.8.1`,
  bez `^`) i skomentowac dlaczego.
- W `android/build.gradle.kts` (root modulu) wyrownac target JVM **tylko** dla tej wtyczki:
  ```kotlin
  subprojects {
    if (name == "receive_sharing_intent") {
      plugins.withId("org.jetbrains.kotlin.android") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
          compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
        }
      }
    }
  }
  ```
  (Globalne wymuszanie 17/17 na wszystkich podprojektach probowalem — pada na innych
  wtyczkach; celowana poprawka jest bezpieczniejsza.)

### Wniosek
Przy dodawaniu wtyczki, ktora nie mial commita od dawna: **zbuduj APK od razu** (nie ufaj
`analyze`), a gdy Gradle pada w `android/build.gradle` samej wtyczki — przypnij wersje i
napraw target JVM celowanym `subprojects { if (name == ...) }`, nie globalnie.

---

## 2026-07-12: Stan „aktywny" nie moze zalezec tylko od koloru akcentu (motyw mono)

### Problem
Aktywna ikona grupowania w Budzecie sygnalizowala stan tylko **kolorem akcentu**
(`semanticColors.primary`). W motywie „standardowy czarno-bialy" (ADR-010) akcent jest
**bezbarwny** (`accentViolet` = `#E5E5E5` w dark, `#171717` w light) — praktycznie
nieodroznialny od domyslnego koloru ikony. Efekt: w mono nie bylo widac, czy przycisk
jest aktywny. `analyze`/`test` tego nie wykryja — to render zalezny od motywu.

### Rozwiazanie
Aktywny/zaznaczony stan sygnalizuj **ksztaltem, nie sama barwa**: wypelniona pigulka pod
ikona (`IconButton.styleFrom(backgroundColor: primary.withValues(alpha: 0.25))` +
`isSelected`). W motywach kolorowych to zabarwiony krazek, w mono — szary krazek na
czarnym/bialym pasku. Stan widac niezaleznie od hue.

### Wniosek
Przy wielu motywach (w tym mono, ADR-010) **nie koduj stanu aktywny/zaznaczony wylacznie
kolorem** — akcent moze byc szaroscia. Uzyj afordancji ksztaltu (tlo/pigulka/obramowanie)
albo zmiany glifu. To ta sama rodzina bledow co „kolory na sztywno lamia sie przy wielu
motywach" (2026-06-24), ale tu problemem jest sam **kanal informacji** (barwa), nie token.

---

## 2026-07-11: Nowe ikony Lucide tylko w `lucide_icons_flutter`

### Problem
Dwie paczki ikon: stara `lucide_icons` (0.257, uzywana wszedzie jako `LucideIcons`)
i nowsza `lucide_icons_flutter` (alias `lucide`). Stara nie ma nowszych glifow —
zabraklo `cloudSync` (wczesniej) i `receiptText` (ta sesja). Blad wychodzi dopiero
przy `flutter analyze` jako `undefined_getter`.

### Rozwiazanie
Nowszy glif brac z `lucide_icons_flutter` przez alias:
`import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;` →
`lucide.LucideIcons.receiptText`. Przed uzyciem nowej ikony sprawdz, czy jest w
starej paczce (np. `Select-String` po pliku glifow w pub cache); jesli nie — uzyj
aliasu. NIE podbijac `lucide_icons` (zmienia kody wielu glifow).

---

## 2026-01-19: Audyty AI (Read-Only)

### Problem
Agenci AI z nadmierną inicjatywą nadpisywali pliki podczas prośby o review ("Let me fix that"), co utrudniało proces weryfikacji i mogło psuć kod.

### Rozwiązanie
Wprowadzono twardą zasadę **Read-Only** dla tasków review.
- AI ma generować raport w `docs/audits/*-audit-[timestamp].md`.
- Zaktualizowano `code-review.md` i `design-review.md` o dedykowane instrukcje i szablony raportów dla agentów.

---

## 2026-01-19: Separacja Dokumentacji (Standards vs Live)

### Problem
Dokumentacja "żywa" (opisująca konkretny projekt) mieszała się ze standardami firmowymi (Code Review, Konwencje) w jednym katalogu `docs/`, co utrudniało nawigację i zrozumienie co można edytować.

### Rozwiązanie
Wydzielono podkatalog `docs/standards/` dla dokumentów reużywalnych.
- **Project Specific (`docs/*.md`)**: Edytowalne, specyficzne dla projektu.
- **Standards (`docs/standards/*.md`)**: Read-only (chyba że zmieniamy standard globalny).

---

## 2026-03-26: Flutter 3.32+/3.33+ -- Nowe API RadioGroup i DropdownButtonFormField

### Problem
`dart analyze` zglosil `deprecated_member_use` dla:
- `RadioListTile.groupValue` / `RadioListTile.onChanged` (deprecated od Flutter 3.32)
- `DropdownButtonFormField.value` (deprecated od Flutter 3.33)

Te deprecations nie sa oczywiste, poniewaz komponenty nadal dzialaja (tylko ostrzezenie), ale beda usuniete w przyszlych wersjach.

### Rozwiazanie
- `RadioListTile` → opakuj w `RadioGroup<T>(groupValue: ..., onChanged: ..., child: Column([...RadioListTile<T>(value: ...)...]))`
- `DropdownButtonFormField.value` → zamien na `initialValue` (ustawia wartosc startowa; stan kontrolowany przez `setState` / `onChanged`)

### Wniosek
Przy starcie nowego projektu Flutter sprawdz wersje SDK w `pubspec.yaml` i uruchom `dart analyze` przed pierwszym buildem. Nawet swiezy `flutter create` moze generowac deprecated API w szablonach.

---

## 2026-03-27: preview_start (MCP) nie dziala z Flutter mobile

### Problem
`preview_start` (Claude Preview MCP tool) zwrocil blad przy probie uruchomienia `flutter run --release`. Narzedzie jest zaprojektowane dla serwerow HTTP (web) i nie obsluguje interaktywnych procesow wymagajacych polaczonego urzadzenia/emulatora.

### Rozwiazanie
Dla projektow Flutter mobile:
- **Build APK:** `flutter build apk --debug` via Bash
- **Uruchamianie na urzadzeniu:** `flutter run` via terminal (wymaga podlaczonego urzadzenia)
- **`preview_start` mozna uzywac tylko dla:** Dart DevTools (`dart pub global run devtools --port XXXX`) — bo to serwer HTTP

### Wniosek
`.claude/launch.json` w projektach Flutter mobile jest uzyteczny jako dokumentacja dostepnych polecen, ale `preview_start` uruchomi jedynie konfiguracje z prawdziwym HTTP serverem (np. DevTools, web server backendu).

---

## 2026-03-28: ota_update 7.x — wymagana kompletna konfiguracja Android

### Problem
OTA crash po pobraniu APK. Kolejne proby naprawy (generyczny FileProvider, zla klasa, brak Receivera, zly filepaths.xml) zajely kilka iteracji, bo dokumentacja pakietu jest rozproszona.

### Rozwiazanie
Pakiet `ota_update: ^7.1.0` wymaga **trzech** elementow w AndroidManifest.xml:
1. `OtaUpdateFileProvider` (klasa `sk.fourq.otaupdate.OtaUpdateFileProvider`, NIE generyczny `androidx.core.content.FileProvider`)
2. `InstallResultReceiver` (`sk.fourq.otaupdate.InstallResultReceiver`)
3. `filepaths.xml` z `<files-path path="ota_update/"/>` (NIE `<external-path>`)

Plus: `WRITE_EXTERNAL_STORAGE` bez `maxSdkVersion`, desugaring w build.gradle.kts.

### Wniosek
Utworzono `docs/ota-update-setup/` z gotowymi templates i checklist. Przy nastepnym projekcie: kopiuj templates, zamien placeholdery, odhacz checklist.

---

## 2026-03-28: Android namespace vs. package mismatch — crash przy starcie

### Problem
Po zmianie `applicationId` i `namespace` w `build.gradle.kts` (np. z `com.example.karton_subs` na
`com.karton.subs`) aplikacja crashowala przy starcie z `ClassNotFoundException: com.karton.subs.MainActivity`.

Przyczyna: `MainActivity.kt` nadal miala stary `package com.example.karton_subs` i lezala
w katalogu `com/example/karton_subs/`. Android szuka klasy pod `namespace + ".MainActivity"`, wiec
mismatch = crash. Flutter nie daje czytelnego komunikatu — tylko klasyczny Android RuntimeException.

### Rozwiazanie
Po zmianie `namespace` w `build.gradle.kts` **trzeba recznie**:
1. Zmienic `package` w `MainActivity.kt` na nowy namespace
2. Przeniesc plik do katalogu zgodnego z nowym package (`com/karton/subs/MainActivity.kt`)
3. Usunac stary katalog (`com/example/...`)
4. `flutter clean && flutter pub get` — wyczysc cache

### Wniosek
Przy kazdej zmianie `namespace` / `applicationId` w Android: sprawdz synchronizacje package w
`MainActivity.kt` i lokalizacje pliku w drzewie katalogow. `grep -r "stary.package" android/` jest
szybkim sposobem na wykrycie wszystkich pozostalosci.

---

## 2026-01-15: Separacja procesu Review

### Problem
Mieszanie uwag dotyczących logiki biznesowej ("Code Review") z uwagami wizualnymi ("Design Review") powodowało szum informacyjny i rozmycie odpowiedzialności.

### Rozwiązanie
Zastosowano standard branżowy rozdzielający te dwa procesy:
1. **Code Review:** Skupia się na architekturze, bezpieczeństwie i logice (styl Linusa).
2. **Design Review:** Skupia się na UI, UX i zgodności z Design Systemem (pixel-perfect).

### Wnioski
- Pozwala to na precyzyjniejsze dobieranie reviewerów (Backend dev vs Frontend/Designer).
- Zwiększa jakość warstwy wizualnej poprzez dedykowaną checklistę.

---

## 2026-03-29: operator == na modelu blokuje odswiezanie UI w Provider

### Problem
`Subscription.operator ==` porownywal tylko `id`. Po `logUsage()` nowy obiekt mial to samo `id`
ale inne `usageLog` — Flutter uznawal widget za niezmieniony i nie przebudowywal `SubscriptionCard`.

### Rozwiazanie
Usunieto `operator ==` i `hashCode` z modelu. Domyslne porownanie referencji = kazdy `copyWith()` tworzy nowy obiekt.

### Wniosek
W modelach z Provider/ChangeNotifier: **nie nadpisuj operator ==** chyba ze porownujesz WSZYSTKIE pola.

---

## 2026-03-29: replace_all na getterze rekurencyjnym

### Problem
`replace_all: true` zamienilo `DateTime.now()` na `_now` rowniez w definicji gettera `_now`, tworzac nieskonczona rekursje.

### Rozwiazanie
Nigdy nie uzywaj `replace_all` na wyrazeniach ktore moga wystapic w definicji docelowej.

### Wniosek
`replace_all` jest niebezpieczny gdy pattern jest ogolny. Zawsze sprawdz czy zamiana nie wplywa na definicje zamiennika.

---

## 2026-03-29: Duplikat kodu lib/ vs apps/

### Problem
Dwie bazy kodu z roznymi nazwami pol, wzorcami i ikonami. Zmiany trafily do zlego katalogu.

### Rozwiazanie
Usunieto duplikat. Jeden build target: `apps/karton_subs/`. Najlepsze elementy przeniesione przed usunieciem.

### Wniosek
Nigdy nie utrzymuj dwoch wersji kodu. Przy nowej sesji: **zawsze sprawdz gdzie jest build target**.

---

## 12. Adaptive Icon Safe Zone (2026-03-29)

### Problem
Badge DEV na ikonie launchera byl obcinany przez maski launchera (kolo, squircle). Umieszczony na pozycji (72,72) z szerokoscia 34dp konczyl sie na x=106, podczas gdy safe zone adaptive icon konczy sie na x=90.

### Rozwiazanie
Canvas adaptive icon to 108x108dp, ale tylko centralne 72x72dp (18-90 na kazdej osi) jest gwarantowane jako widoczne. Wszystkie elementy foreground musza miescic sie w tym zakresie. Badge przeniesiony na (59,75)→(87,87).

### Wniosek
Przy projektowaniu adaptive icon: **nigdy nie umieszczaj istotnych elementow poza zakresem 18-90dp** na canvas 108dp. Stosuj margines min. 3dp od krawedzi safe zone.

---

## 13. Zlozone ikony stroke-based nie skaluja sie dobrze (2026-03-29)

### Problem
Symbol RotateCcw+DollarSign (dwa nalozne ikony Lucide) renderowal sie jako nieczytelna plama przy rozmiarach mipmap (48-192px). Zbyt wiele nakladajacych sie linii stroke.

### Rozwiazanie
Zamiana na pojedyncza, prostsza ikone (Lucide Gem) z mniejsza liczba sciezek i bez nakladania elementow.

### Wniosek
Przy wyborze symboli na ikone launchera: **preferuj proste, wypelnione ksztalty lub pojedyncze ikony**. Unikaj kompozycji wielu ikon stroke-based — nie przetrwaja skalowania do 48px.

---

## 14. SVG→PNG rendering: przegladarka vs resvg (2026-03-31)

### Problem
PNG ikony wyrenderowane z przegladarki (Canvas export) mialy niską jakosc — brak detali masek SVG, zdegradowane krawedzie sześcianu. SVG zrodlowe wygladaly poprawnie.

### Rozwiazanie
Uzycie `@resvg/resvg-js` (natywny silnik Rust w WASM) do programowego renderowania PNG z SVG. Poprawna obsluga SVG mask, gradientow i stroke na wszystkich rozmiarach.

### Wniosek
Przy generowaniu PNG z SVG zawierajacych maski/gradienty: **nigdy nie polegaj na eksporcie z przegladarki**. Uzyj dedykowanego renderera SVG (resvg, Inkscape CLI, rsvg-convert). Przegladarki zle obsluguja `<mask>` na malych rozmiarach.

---

## 15. Android resource merging w multi-flavor (2026-03-31)

### Problem
Usuniecie `mipmap-anydpi-v26/ic_launcher.xml` z flavora `internal` spowodowalo, ze Android na API 26+ uzywal adaptive icon XML z flavora `main` — ladujac produkcyjny foreground zamiast deweloperskiego.

### Rozwiazanie
Dodanie pelnego zestawu adaptive icon layers (foreground, background, monochrome + XML) do flavora `internal`, nadpisujac zasoby z `main`.

### Wniosek
W Android multi-flavor: **kazdy flavor ktory ma wygladac inaczej MUSI jawnie nadpisac wszystkie warstwy adaptive icon**. Usuniecie XML nie blokuje fallbacku — Android dziedziczy z `main`. Brak pliku ≠ brak ikony.

---

## 2026-04-05: flutter_local_notifications — 3 pulapki przy integracji

### Problem
Integracja `flutter_local_notifications` v18 spowodowala 3 problemy:
1. **Build failure** — brakujacy wymagany parametr `uiLocalNotificationDateInterpretation` w `zonedSchedule()`
2. **App crash na starcie** — `init()` rzucal wyjatki (timezone/plugin init) bez try-catch, blokujac `main()`
3. **Zapis subskrypcji zawieszony** — `await _notifications.scheduleForSubscription()` w controllerze blokowal `update()`/`delete()` gdy plugin nie byl zainicjalizowany

### Rozwiazanie
1. Dodanie brakujacego parametru: `uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime`
2. Owinięcie `init()` w try-catch + guard `if (!_initialized) return` we wszystkich metodach publicznych
3. Notification calls jako **fire-and-forget** (bez `await`) w controllerze — zapis do storage zawsze przechodzi
4. Runtime permission request: `requestNotificationsPermission()` + `requestExactAlarmsPermission()` w `init()` (wymagane na Android 13+)

### Wniosek
Przy integracji pluginu ktory moze failowac (notifications, bluetooth, camera):
- **Nigdy nie blokuj CRUD operacji awaitowaniem pluginu** — fire-and-forget
- **Zawsze try-catch w init** — plugin failure nie moze zabic aplikacji
- **Guard `_initialized`** we wszystkich publicznych metodach
- **Android 13+ wymaga runtime permission** — sam AndroidManifest nie wystarczy

---

## 2026-06-16: Stany dlugotrwalego procesu (OTA) musza miec zawsze wyjscie

### Problem
Ekran OTA w stanie `launchingInstaller` renderowal statyczny tekst bez zadnej akcji.
Gdy systemowe okno instalatora sie nie pojawilo lub zostalo zamkniete (zdarzenie poza
strumieniem `OtaUpdate`), UI wisial w nieskonczonosc bez mozliwosci restartu. Dodatkowo
flaga `_showInstallerHint` (ratunkowa podpowiedz po 5 s) byla wyliczana w serwisie, ale
UI nigdy jej nie czytal — martwy kod.

### Rozwiazanie
Dodano `UpdateService.restartUpdate()` oraz zawsze widoczne przyciski "Zrestartuj
aktualizacje" + "Anuluj" w stanach `downloading` i `launchingInstaller`; wyswietlono
podpowiedz ratunkowa, gdy `showInstallerHint == true`.

### Wniosek
Kazdy stan dlugotrwalego procesu async sterowanego strumieniem zdarzen pluginu (OTA,
pobieranie, instalacja) MUSI miec zawsze dostepna akcje wyjscia/restartu — strumien moze
nigdy nie dostarczyc zdarzenia terminalnego. Jesli serwis wystawia flage pomocnicza, UI
musi ja faktycznie renderowac, inaczej to martwy kod.

---

## 2026-06-17: DateTime.add(Duration(days:)) dryfuje przez zmiane czasu (DST)

### Problem
Rzutowanie wystapien tygodniowych w `occurrencesInRange` krokiem `occ = occ.add(Duration(days: 7))`
dawalo `2026-03-30 01:00` zamiast `2026-03-30 00:00`. Powod: przejscie na czas letni (ostatnia
niedziela marca) — `Duration` to staly czas fizyczny (168 h), wiec po przekroczeniu granicy DST
dodaje sie godzina, ktora kumuluje sie przy kolejnych krokach. Test rownosci dat go wykryl.

### Rozwiazanie
Krok przez konstrukcje kalendarzowa zamiast `Duration`:
`occ = DateTime(occ.year, occ.month, occ.day + step)` — kazde wystapienie powstaje o polnocy
lokalnej danego dnia, niezaleznie od DST. Cykle miesieczne/roczne juz tak liczylem (konstrukcja
`DateTime(y, m, day)`), wiec dotyczylo to tylko krokow dniowych (weekly/custom).

### Wniosek
Do iteracji po datach kalendarzowych **nigdy nie uzywaj `add(Duration(days: n))`** — uzywaj
`DateTime(y, m, d + n)`. `Duration` jest dla czasu fizycznego (timery, timeouty), nie dla
"nastepnego dnia/tygodnia". Zawsze testuj rzutowanie dat na granicy marca/pazdziernika (DST).

---

## 2026-06-17: Flutter UI — 3 niejawne pulapki (motyw, Overlay, slot nawigacji)

### Problem
Podczas redesignu Aurora trzy bledy, ktorych `flutter analyze`/`test` NIE wykrywaja (to czysta
geometria/render runtime — wychwycila je dopiero weryfikacja na urzadzeniu):
1. **`showDatePicker` polprzezroczysty** mimo ustawionego `dialogTheme`. Picker daty korzysta z
   OSOBNEGO `DatePickerThemeData`, nie z `dialogTheme` — brak wpisu = domyslne (polprzezroczyste)
   tlo. To samo dotyczy `timePicker`, `menu`, `snackBar`, `tooltip` (kazdy ma swoj `*ThemeData`).
2. **Zolte podkreslenia pod tekstem** w pigulkach menu „Dodaj" — `Text` w `OverlayEntry` nie mial
   przodka `Material`, wiec Flutter rysowal debugowa dekoracje (yellow underline).
3. **Plywajacy pasek nawigacji wysrodkowany w pionie** zamiast na dole — `Center` w slocie
   `bottomNavigationBar` rozszerza sie na cala (luzna) wysokosc slotu, centrujac dziecko w pionie.

### Rozwiazanie
1. Pelne pokrycie motywem: dodano `datePickerTheme`, `timePickerTheme`, `popupMenuTheme`,
   `menuTheme`, `dropdownMenuTheme`, `snackBarTheme`, `tooltipTheme`, `textSelectionTheme` w
   `app_theme.dart`. Nowy komponent stylujemy RAZ centralnie (ADR-007).
2. Owiniecie zawartosci `OverlayEntry` w `Material(type: MaterialType.transparency)`.
3. Zamiana `Center` na `Row(mainAxisAlignment: center)` — pelna szerokosc, wysokosc = sama pigulka.

### Wniosek
- **Stockowy komponent Material ma wlasny `*ThemeData`** — `dialogTheme` nie pokrywa pickerow/menu/
  snackbarow. Stylowanie tla rob w motywie, nie per-wywolanie; po dodaniu nowego typu komponentu
  sprawdz, czy ma wpis w `ThemeData`.
- **Tekst w `Overlay` wymaga przodka `Material`** (inaczej zolte podkreslenia).
- **W `bottomNavigationBar` nie uzywaj `Center`** dla pigulki — uzyj `Row`/intrinsic height.
- Te bledy przechodza `analyze`/`test` — **weryfikacja wizualna na urzadzeniu jest obowiazkowa**.

---

## 2026-06-17: Deploy buduje z drzewa roboczego — prod bez commita = rozjazd git↔produkcja

### Problem
`deploy.ps1` buduje APK z **biezacego stanu plikow**, nie z commita. Wydanie produkcyjne
(0.4) zrobiono z niezacommitowanej galezi — na produkcji jest kod, ktorego nie ma w git
(`origin/main` stoi na starszym commicie). Brak punktu rollbacku; tag (`-CreateTag`) wskazalby
ostatni commit, NIE faktycznie wydany kod → tag by „klamal".

### Rozwiazanie
Przed deployem **production**: commit + push feature, dopiero potem deploy (+ ewentualny tag).
Dla kanalu **dev/internal** build z drzewa roboczego jest OK (to wlasnie do testow). Dodatkowo:
`docs/_sandbox/` dodane do `.gitignore` — zawiera realne dane finansowe (CSV), nie wolno commitowac.

### Wniosek
Kanal dev = build z drzewa roboczego dozwolony. Kanal **prod = tylko z zacommitowanego (najlepiej
otagowanego) kodu** — inaczej wydanie jest niereprodukowalne. Pliki z danymi osobistymi trzymaj
w ignorowanym katalogu (`docs/_sandbox/`), zeby `git add .` ich nie wciagnal.

---

## 2026-06-18: WinSCP "Kod bledu 4" przy deploy = katalog juz istnieje (nie blad)

### Problem
`deploy.ps1` (kanal internal) wyswietla podczas uploadu glosny komunikat:
`Nie mozna utworzyc katalogu '.../internal/'. Ogolna awaria. Kod bledu: 4 ... Failure`.
Wyglada jak awaria uploadu, ale deploy konczy sie sukcesem (pliki wgrane 100%).

### Rozwiazanie
To NIE jest blad. WinSCP probuje utworzyc katalog docelowy, ktory **juz istnieje** z poprzednich
deployow → SFTP zwraca kod 4, skrypt robi „Pomin" i kontynuuje upload plikow. Wskaznikiem sukcesu
jest `[4/4] Upload zakonczony sukcesem!` + linie `... | 100%` dla APK i version-json.

### Wniosek
Przy deployu czytaj koncowy status skryptu, nie pojedyncze ostrzezenia WinSCP. „Kod bledu 4" przy
tworzeniu istniejacego katalogu jest oczekiwany i nieszkodliwy. (Ewentualne wyciszenie: utworzyc
katalog raz i nie ponawiac `mkdir` w skrypcie.)

---

## 2026-06-24: Kolory na sztywno w widgetach lamia sie przy wielu motywach

### Problem
Po wprowadzeniu systemu motywow (tryb jasny/ciemny x kolor, ADR-010) dwa miejsca
psuly sie w trybie jasnym, bo mialy kolor zaszyty na sztywno zamiast tokenu z palety:
1. **Chip metody platnosci** (`FilterChip`): tekst zaznaczonego chipa znikal na
   ciemnym akcencie. `ChipThemeData.secondaryLabelStyle` NIE jest uzywany przez
   `FilterChip` dla stanu zaznaczonego — kolor trzeba podac stanowo.
2. **Navbar** (`glass_nav_bar`): obramowanie `Colors.white @ 0.16` bylo niewidoczne
   na jasnym tle (w ciemnym dawalo subtelny kontur, w jasnym zlewalo sie z tlem).

### Rozwiazanie
- Chip: kolor tekstu jako `WidgetStateColor.resolveWith` wewnatrz zwyklego
  `TextStyle` (zaznaczony → `onAccent`, inaczej `textSecondary`). UWAGA: NIE
  `WidgetStateTextStyle.resolveWith` — po scaleniu w chipie gubi kolor dla stanu
  niezaznaczonego (bazowe `.color` jest null → tekst znika).
- Navbar: zamiast stalego bialego → `AppColors.frostBorderStrong` (token zalezny
  od trybu: w jasnym ciemny hairline, w ciemnym jasny kontur).

### Wniosek
Przy wielu motywach **nie zaszywaj kolorow** (`Colors.white`, `Colors.black`,
stale hex) w widgetach — uzywaj tokenow z palety (`AppColors.*` / `frostBorder*`),
ktore zmieniaja sie z trybem. Dla kontrastu na akcencie: `onAccent`. Dla kolorow
zaleznych od stanu w komponentach Material uzywaj `WidgetStateColor`, nie
`WidgetStateTextStyle` (ten ostatni gubi kolor po merge w chipie).

---

## 2026-07-09: Efekt „ducha" przy animacji powrotu = dwie warstwy (tlo + przejscie tras)

### Problem
Przy powrocie z pod-ekranu (Ustawienia → opcja → wstecz) przez ulamek sekundy prześwitywala
tresc znikajacego ekranu przez ekran docelowy (np. tekst „Waluta i limit" na liscie Ustawien).
Pierwsza proba naprawy (samo tlo) NIE wystarczyla — bug mial dwie niezalezne przyczyny:
1. **Tlo powielone per ekran:** kazdy ekran owijal swoj Scaffold wlasna kopia `AuroraBackground`.
   Podczas przejscia dwa identyczne gradienty nakladaly sie i „pompowaly" jasnoscia, a poswiaty
   jechaly razem z ekranem.
2. **Domyslne przejscie tras naklada oba ekrany:** androidowy `ZoomPageTransitionsBuilder` pokazuje
   stary i nowy ekran jednoczesnie (przenikanie). Przy przezroczystych Scaffoldach (wspolne tlo)
   tresc starego ekranu przeswituje jak duch — mimo naprawionego tla.

### Rozwiazanie
1. Tlo montowane RAZ globalnie w `MaterialApp.builder` (pod Navigatorem); wszystkie ekrany na
   `Scaffold(backgroundColor: Colors.transparent)`; usuniete owijanie tlem z 10 ekranow.
2. Przejscie `FadeThroughPageTransitionsBuilder` (pakiet `animations`) w `ThemeData.pageTransitionsTheme`
   dla android+iOS, z `fillColor: Colors.transparent` — stary ekran gasnie CALKOWICIE, dopiero
   potem pojawia sie nowy (fazy sie nie nakladaja). `fillColor` transparent, inaczej pod animacja
   mignie nieprzezroczysty prostokat zamiast tla aplikacji.

### Wniosek
Aplikacje z przezroczystymi ekranami na wspolnym tle: **tlo montuj raz w `MaterialApp.builder`,
nigdy nie owijaj pojedynczych ekranow** (podwojne tlo pompuje jasnoscia) ORAZ **zamien domyslne
przejscie zoom na fade-through** (domyslne przenikanie pokazuje oba ekrany naraz → duch). Obie
warstwy sa wymagane — sama naprawa tla nie wystarczy. Bledy przechodza `analyze`/`test`,
**weryfikacja wizualna na urzadzeniu obowiazkowa** (potrzebna byla klatka nagrania, by zdiagnozowac
druga warstwe). Ta sama estetyka = ten sam bug w kazdej takiej aplikacji (dotyczy tez APPteczki).

---

## 2026-07-27: Reguly odczytu dokumentow — liczby, ktore udaja co innego

### Problem
Przy dopisywaniu wzorca faktury do `ReceiptTextParser` dwie reguly wygladaly
poprawnie, a na prawdziwych dokumentach dawaly zla kwote:

1. **Data udajaca kwote.** Wzorzec kwoty `(\d[\d\s]*[,.]\d{2})` dopasowuje sie do
   `15.09.2023` jako `15,09`. Przy sumie dokumentu wygrywala „kwota" kilkunastu
   zlotych.
2. **Etykieta naglowka kolumny.** „wartosc brutto" w zestawieniu VAT stoi NAD
   kolumna, pod ktora ida kolejno netto, podatek i brutto. Okno kilku linii od
   takiej etykiety konczy sie na podatku — reguła podstawiala kwote NETTO
   (24 642,88 zamiast 30 310,74, czyli dokladnie brutto/1,23).
3. **Etykieta bez wartosci.** „Razem do zaplaty:" bywa w osobnej linii, a nad nia
   konczy sie tabela VAT — szukanie kwoty wstecz podstawialo podatek (322,00).

### Rozwiazanie
- Daty wycinane z linii PRZED szukaniem kwot (`replaceAll(_dmyDate/_isoDate)`).
- Suma opierana na „Razem" (etykieta stojaca przy liczbach podsumowania), nie na
  naglowkach kolumn; z okna brana NAJWIEKSZA kwota, bo brutto >= netto >= VAT.
- Etykiety platnosci przeszukiwane tylko w przod; etykiety sumy w obie strony
  (uklad dwukolumnowy potrafi postawic wartosc nad etykieta).

### Wniosek
Reguly na tekscie z OCR **weryfikuj na surowym tekscie prawdziwych dokumentow**,
nie na przepisanym z reki — bledy siedza w rzeczach, ktorych sie nie wymysli
(kolejnosc kolumn, etykieta pod wartoscia, zero na oplaconej fakturze). Kazda
kwota, ktora „prawie pasuje", to kandydat na podatek albo netto: przy sumach
bierz maksimum z okna, a nie pierwsze trafienie.

**Przy okazji, o piaskownicy:** zanim wrzucisz realne dokumenty do repo, sprawdz
`.gitignore`. `docs/_sandbox/` byl ignorowany, ale `_sandbox/` w korzeniu juz nie —
faktury z danymi osobowymi czekaly na pierwszy `git add .`.

---

## 2026-07-31: Pytanie o haslo na podstawie typu pliku, a nie proby odszyfrowania

### Kontekst
Import kopii pytal o haslo wtedy, gdy plik mial typ `password` (`needsPassword`
liczone z naglowka). Dzialalo, dopoki „bez hasla" znaczylo „klucz urzadzenia".

### Blad
Po wprowadzeniu kodu odzyskiwania (ADR-024) kopie z WLASNEGO telefonu tez maja
typ `password` — bo kod jest technicznie haslem, tylko wygenerowanym za
uzytkownika. Efekt: aplikacja pytala o haslo do kopii, ktora potrafi otworzyc
sama, a uzytkownik nie mial czego wpisac.

### Rozwiazanie
`BackupService.needsPasswordPrompt()`: najpierw **cicha proba** odszyfrowania
lokalnym kodem, i dopiero jej niepowodzenie uzasadnia pytanie.

```dart
Future<bool> needsPasswordPrompt(BackupFileInfo fileInfo) async {
  if (!fileInfo.needsPassword) return false;
  return !await _opensWithLocalCode(fileInfo.format as EncryptedBackup);
}
```

### Wniosek
Decyzja „czy zapytac uzytkownika" nie moze wynikac z **metadanych** pliku, tylko
z tego, czy aplikacja faktycznie potrafi go otworzyc. Naglowek mowi „czym to
zaszyfrowano", a nie „czy mam do tego klucz". Ta sama pulapka czeka wszedzie,
gdzie UI pyta o sekret na podstawie deklaracji formatu zamiast realnej proby.

---

## 2026-08-01: Trzy `Flexible` w wierszu dziela szerokosc po rowno (Flutter)

### Problem
Wiersz listy skracal tekst, mimo ze obok bylo widac wolne miejsce. Dwa razy
w tej samej sesji, w dwoch roznych miejscach:

1. `Row([Flexible(nazwa), Flexible(kategoria)])` — nazwa urywala sie na polowie
   szerokosci, choc kategoria „Dom" zajmowala ulamek swojej czesci.
2. `Row([Flexible(opis), Flexible(metoda), Flexible(kategoria)])` — data urywala
   sie do „2…", a po prawej zostawal pusty pas.

### Przyczyna
`Flexible` (i `Expanded`) z domyslnym `flex: 1` dzieli dostepna szerokosc
**po rowno miedzy wszystkie elastyczne dzieci**, niezaleznie od tego, ile ktore
naprawde potrzebuje. Dziecko, ktore chce mniej, po prostu nie wykorzystuje
swojego przydzialu — i ta reszta NIE wraca do rodzenstwa.

### Rozwiazanie
- Gdy jeden element ma dostac cale wolne miejsce, a drugi tylko tyle, ile
  potrzebuje: `Expanded` dla pierwszego, a drugi **nieelastyczny**
  (opcjonalnie `ConstrainedBox` z gornym limitem).
- Gdy kilka fragmentow tekstu ma plynac jak jedno zdanie: **jeden `Text.rich`**
  zamiast kilku `Text` w `Row`. Ikone wstawia sie przez `WidgetSpan`
  (`PlaceholderAlignment.middle`), a `maxLines: 1` + `TextOverflow.ellipsis`
  utnie dopiero na koncu calej linii.

### Wniosek
Kilka `Flexible` obok siebie to podzial szerokosci, a NIE „kazdy bierze, ile
potrzebuje". Jesli tresc ma sie czytac jak jeden ciag — sklej ja w jeden widget
tekstowy; jesli jeden element jest wazniejszy — tylko on ma byc elastyczny.
Objaw („skraca sie mimo wolnego miejsca") wyglada jak brak miejsca, wiec latwo
szukac przyczyny nie tam, gdzie trzeba.

---

## 2026-08-18: `dart format` na katalogu przeformatuje CALY projekt

### Problem
Po dopisaniu jednej klasy uruchomilem `dart format lib test`, zeby uporzadkowac
wlasny kod. Narzedzie zglosilo „Formatted 142 files (96 changed)" — zmienilo 96
plikow, z ktorych 93 nie mialy nic wspolnego z zadaniem. Diff zmiany urosl
z kilkuset linii do kilku tysiecy, a analiza zaczela zglaszac linty
(`curly_braces_in_flow_control_structures`) w plikach, ktorych nikt nie ruszal —
bo formatowanie rozbilo `if (x) return;` na dwie linie.

### Przyczyna
Projekt nie jest utrzymywany w kanonicznym formacie `dart format` i nigdy nie
byl. Kazde uruchomienie narzedzia na katalogu (a nie na pliku) przepisuje wiec
cala reszte przy okazji.

### Rozwiazanie
- Formatowac **tylko pliki, ktore sie zmienialo**: `dart format <sciezka/do/pliku.dart>`.
- Gdy juz sie stanie: `git diff --name-only`, odfiltrowac wlasne pliki i cofnac
  reszte przez `git checkout -- <lista>`. Warto to zrobic OD RAZU, zanim wejdzie
  commit — pozniej zmiany sa nie do odroznienia od merytorycznych.

### Wniosek
`dart format` bez argumentu pliku to operacja na calym repozytorium, a nie
„uporzadkuj to, nad czym pracuje". W projekcie, ktory nie ma wymuszonego
formatowania w CI, jest to zmiana poza zakresem zadania — dokladnie to, czego
zabrania regula o dyscyplinie zakresu.

---

## 2026-08-22: OCR zwraca BLOKI, a nie kolejnosc wizualna

### Problem
Nowa regula czytania potwierdzen z portfela telefonu dzialala na testach
i w polowie dzialala na telefonie: kwota i data byly poprawne, ale nazwa sklepu
wychodzila pusta. Na ekranie nazwa stoi dokladnie pod naglowkiem
„Potwierdzenie", wiec regula brala „pierwsza sensowna linie POD naglowkiem".

### Przyczyna
`recognized.text` z ML Kit sklada tekst z BLOKOW, a kolejnosc blokow nie musi
odpowiadac temu, co widac na ekranie. Naglowek to maly, osobny blok w lewym
gornym rogu — w odczycie potrafi wyladowac za nazwa albo za cala tabela. Kwota
i data przezyly to bez szwanku, bo szuka sie ich PO ETYKIETACH („Kwota:",
„Data:"), czyli niezaleznie od kolejnosci. Nazwa byla jedynym polem opartym
na pozycji i jako jedyna zawiodla.

### Rozwiazanie
- Pole wiazac z ETYKIETA, nie z pozycja linii — wszedzie, gdzie dokument
  jakakolwiek etykiete ma.
- Gdy pole etykiety nie ma (nazwa sklepu w potwierdzeniu), oprzec je o granice,
  ktora z kolejnosci blokow nie wynika: „przed pierwsza etykieta" zamiast
  „pod naglowkiem".
- Kandydata czyscic z naglowka zamiast odrzucac cala linie — bloki bywaja tez
  SKLEJANE, wiec „Potwierdzenie Salon psiej urody" to jedna linia.

### Wniosek
Test napisany z wyrenderowanego zrzutu sprawdza uklad, ktory widzi CZLOWIEK,
a regula dostaje uklad, ktory zwrocil OCR. To dwie rozne rzeczy. Kazda nowa
regula dokumentu powinna miec test „to samo, ale w innej kolejnosci linii" —
inaczej polowa pol dziala, a druga polowa wychodzi pusta dopiero na telefonie.

### Ciag dalszy (2026-08-23): zgadywanie kosztowalo trzy wydania
Dwie kolejne proby naprawy szly „na wyczucie" i obie chybily. Prawdziwy odczyt
okazal sie ukladem DWUKOLUMNOWYM: najpierw cala kolumna etykiet, potem cala
kolumna wartosci — wartosc lezala cztery linie od swojej etykiety, wiec zadne
szukanie „w sasiedztwie" nie mialo szans. Rozwiazaniem bylo parowanie POZYCYJNE
(n-ta wartosc do n-tej etykiety), a nie kolejna heurystyka.

Wniosek procesowy jest ostrzejszy niz techniczny: **przy pierwszym nietrafionym
odczycie dokladamy podglad surowego tekstu, zamiast zgadywac drugi raz.**
Kafelek „Ostatni odczyt OCR" w Developer Tools kosztowal jedno wydanie
i rozstrzygnal sprawe w minute; dwa wczesniejsze strzaly kosztowaly tyle samo
i nie daly nic.

