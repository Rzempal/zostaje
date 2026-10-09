# ADR-035: Plan roczny — pozycje z miesiącami zamiast cykli i korekt

Data: 2026-10-06
Status: zaakceptowany — wdrożony na PROD w wersji 0.27 (2026-10-08, Faza 16)

> **Powiązane:** [ADR-008 Rachunek zmienny](ADR-008-rachunek-zmienny-surplus-vs-bilans.md)
> | [ADR-020 Cykl „wybrane miesiące roku"](ADR-020-cykl-wybrane-miesiace-roku.md)
> | [ADR-028 Plan vs rzeczywistość](ADR-028-plan-vs-rzeczywistosc-na-wykresach.md)
> | [ADR-029 Podsumowanie roczne](ADR-029-podsumowanie-roczne-i-poczatek-ewidencji.md)
> | [ADR-009 Synchronizacja domowa](ADR-009-synchronizacja-budzetu-domowego-relay-e2e.md)
> | [ADR-031 Numeracja wersji](ADR-031-numeracja-wersji-i-przejscie-na-google-play.md)

## Kontekst

Budżet opierał się na kwocie bazowej z cyklem (tydzień, miesiąc, kwartał, rok,
wybrane miesiące, co N dni) i na korektach wpisywanych miesiąc po miesiącu
(ADR-008). Do tego dochodziło porównanie planu z rzeczywistością (ADR-028/029),
które wymagało rejestrowania realnych wydatków.

W codziennym użyciu wyszło, że:

- korekty miesiąc po miesiącu to dużo klikania, a i tak powstaje z nich plan
  na konkretne miesiące — tylko rozproszony po korektach;
- realnych wydatków nie chce się rejestrować w całości, więc porównanie
  „plan vs rzeczywistość" pokazuje coś, czego nikt nie karmi danymi;
- przelew między budżetami (para pozycja + lustro, ADR-006) się nie sprawdził;
- synchronizacji budżetu domowego nikt aktualnie nie używa (ADR-009).

Właściciel jest jedynym użytkownikiem aplikacji, więc zgodność wstecz nie jest
wymagana — z jednym warunkiem: nie stracić pozycji.

## Decyzja

### 1. Plan roczny jak arkusz: wiersze = pozycje, kolumny = miesiące

- **Pozycja planu** (`PlanPosition`): nazwa, rodzaj (wpływ / wydatek),
  kategoria, metoda płatności, waluta, domyślny dzień płatności, notatka,
  znacznik „archiwalna" i **identyfikator budżetu**.
- **Miesiące pozycji** (`PlanMonth`): „RRRR-MM → kwota (+ dzień)". Brak miesiąca
  = pozycja wtedy nie obowiązuje. Kwota żyje WYŁĄCZNIE w miesiącach; miesiące
  są od siebie niezależne i edytuje się je pojedynczo albo po kilka naraz.
- Pozycja **nie jest przypięta do roku** — rata 09.2026–08.2027 to jedna
  pozycja. Nowy rok powstaje przez skopiowanie miesięcy poprzedniego.
- Filtr na cały rok = **średnia miesięczna** (suma ÷ 12), filtr na miesiąc =
  kwoty tego miesiąca.
- Znikają: cykle pozycji budżetu, korekty miesięcy, typ „rata", przelew do
  domowego, osobna figura „zostaje/mies." (staje się średnią z planu).

### 2. Budżety jako identyfikatory

> Rozwinięte w [ADR-037](ADR-037-budzety-z-nazwami.md): budżety z własnymi
> nazwami i ikonami, przenoszenie i kopiowanie zawartości.

Pozycja niesie `budgetId`, a nie wartość wyliczeniową. Na start dwa budżety
(`personal`, `household` — dawne zakresy); budżety z własnymi nazwami dojdą
później bez ponownej konwersji danych.

### 3. Co zostaje bez zmian

- **Subskrypcje** — osobny moduł ze wszystkimi funkcjami (okresy próbne,
  przypomnienia, limit, przypinanie). W planie są sekcją, a kwoty miesięcy
  liczą się z ich cyklu (miesiąc odnowienia = pełna kwota, okres próbny i po
  anulowaniu = 0).
- **Kalendarz z listą płatności do odhaczenia** — zostaje (bez realnego
  bilansu miesiąca).

### 3b. Bieżące i Planner usunięte (aktualizacja 2026-10-07)

Pierwotnie Bieżące miały zostać „na razie bez zmian". Po E2–E3 właściciel
zdecydował: zaplanowany wydatek to zwykła pozycja planu, więc odpadają:

- **zakładka Bieżące** — dziennik wydatków z datą, formularz, scalanie
  (ADR-018/034), automat karty (ADR-033);
- **skan paragonów** — aparat, galeria, „Udostępnij → Zostaje", rozpoznawanie
  tekstu (ML Kit), mostek do Lokalnego Silnika AI, usługa w tle, archiwum
  zdjęć (ADR-013/015/016/017). Aplikacja zmalała z 44,7 do 32,0 MB;
- **Planner „Na bieżące wydatki"** (ADR-012) — każda pozycja koperty stała się
  osobną pozycją planu (ta sama kwota co miesiąc, z kategorią i metodą;
  identyfikator `envelope:<id pozycji koperty>`, dokładana jednorazowo do już
  istniejącego planu bez przeliczania całości).

Historia wydatków z Bieżących zostaje w starym zapisie bez widoku (archiwum —
widoczna w poprzedniej wersji aplikacji i w jej kopiach). Nie trafia do planu:
liczona obok pozycji z Plannera dawałaby te same pieniądze dwa razy.

Nawigacja: **Budżet | Planowanie | Ustawienia**.

### 4. Karta kredytowa w planie

> Rozszerzone w [ADR-036](ADR-036-pozyczki-ratalne.md): sekcja „Pożyczki"
> (karta i pożyczki ratalne), „Pożyczki netto" zamiast „karty netto".

„Pożyczka z karty" jako para w planie: wpływ w miesiącu użycia i spłata
w miesiącu wynikającym z okresu bezodsetkowego karty (kwotę spłaty można
zmienić osobno, np. o prowizję). Automat w Bieżących (lustro zakupu + spłata,
ADR-033) zniknął razem z Bieżącymi.

Zapis: dwie pozycje planu rodzajów `cardLoan` i `cardRepayment`, każda
z jednym miesiącem, spięte wspólnym `linkId` (usunięcie jednej usuwa drugą).
Liczone OSOBNO od wpływów i wydatków — jako „karta netto" w „Zostaje" — bo
w skali roku para się znosi, a wliczona do wpływów i wydatków zawyżałaby obie
średnie.

### 3a. Zakładka „Budżet" po przebudowie

Dwie pod-zakładki: **Statystyki** (wybrany rok: średnio miesięcznie, wykres
12 miesięcy, kategorie, limity i okresy próbne subskrypcji) i **Kalendarz**
(dawny „Bilans miesiąca" bez realnego bilansu). Kalendarz bierze dane z planu
(miesiące pozycji z dniem płatności) i z odnowień subskrypcji. Pozycja bez
dnia płatności nie ma miejsca na kalendarzu.

### 5. Konwersja danych i powrót

- Konwersja jest automatyczna (przy starcie i po odtworzeniu starej kopii)
  i czysta: reguły w `services/plan_conversion.dart`, sprawdzone testami.
- **Stare pozycje zostają nietknięte** — także przy zmianach słowników
  (usunięcie kategorii, zmiana nazwy metody płatności dotyczą planu
  i subskrypcji, nie archiwum) — w dotychczasowych pudełkach bazy, plan
  trafia do osobnego pudełka `plan_positions`. Identyfikator pozycji planu =
  identyfikator starej pozycji, więc odhaczenia płatności nie przepadają.
- **Powrót** do poprzedniej wersji: zbudowanie starej rewizji z WYŻSZYM numerem
  wersji (numer nadajemy sami, ADR-031) i zwykła aktualizacja — bez
  odinstalowania. Stara wersja widzi plan z chwili konwersji, a Bieżące —
  dziennik z chwili przejścia (nowa wersja go nie zmienia).
- Raport konwersji w Developer Tools porównuje sumy roku ze starego modelu
  z nowym planem — sprawdzenie na prawdziwych danych bez wynoszenia ich
  z telefonu.
- **Kopia `.zostaje` w wersji 8** niesie plan w sekcji `planPositions`; stare
  sekcje zostają w pliku jako archiwum. Plik v8 wczytuje plan wprost (bez
  przeliczania), plik v7 i starszy — przelicza plan ze starych pozycji.
  Poprzednia wersja aplikacji odrzuca plik v8 przed skasowaniem czegokolwiek
  (nie przyjmuje wersji > 7), więc po powrocie trzeba użyć kopii sprzed
  przejścia albo kopii z konta Google zrobionej przez starą wersję.

### 5a. Okres pozycji (aktualizacja 2026-10-09)

„Wypełnij puste" na ekranie pozycji wpisałby ratę także po spłacie — plan nie
wiedział, kiedy rata się kończy (koniec był tylko w notatce). Dlatego pozycja
ma opcjonalny **okres** `periodStart`–`periodEnd` („RRRR-MM", oba końce
włącznie):

- rata: od pierwszej do ostatniej raty; pozycja ze startem (umowa od
  listopada): samo „od"; czynsz czy pensja: bez okresu;
- poza okresem pozycja **nie ma miesięcy** — ekran je wyszarza (nie da się ich
  zaznaczyć ani wypełnić, dotknięcie mówi dlaczego), a kontroler pomija je
  przy każdym zapisie; zawężenie okresu z kwotami poza nim pyta o ich
  usunięcie;
- „Zaplanuj kolejny rok" przenosi tylko miesiące w okresie;
- plan sprzed okresów dostaje je jednorazowo ze starych pozycji o tym samym
  identyfikatorze (raty: data pierwszej raty + liczba rat; start późniejszy
  niż początek okna konwersji), bez przeliczania planu — okres poszerza się,
  by objąć istniejące miesiące, więc żadna kwota nie wypada;
- kopia `.zostaje` (dalej wersja 8) niesie okresy i znacznik `planPeriods`;
  wersja 0.27 je pomija. Arkusz planu ma kolumny „Od" i „Do".

Subskrypcje nie potrzebują okresu: ich miesiące liczą się same z daty startu
i cyklu, bez ręcznego wypełniania.

Ekran pozycji: siatka 3×4 (rząd = kwartał) zamiast listy 12 wierszy;
tapnięcie edytuje miesiąc, przytrzymanie zaznacza (kolejne — zakres), panel
„Szybkie wypełnianie" wpisuje kwotę i dzień w zaznaczone albo puste miesiące.

### 6. Synchronizacja budżetu domowego — usunięta

Udostępnianie budżetu: eksport/import arkusza planu — tabela roku (wiersz =
pozycja, kolumny = 12 miesięcy, zakładka „Plan RRRR" na każdy rok), zawsze dla
budżetu, w którym jest użytkownik. Import DOKŁADA pozycje (nowe identyfikatory),
pozycja przez dwa lata wraca jako jedna. Pozycje karty są w arkuszu do wglądu,
ale nie wracają z niego — para pożyczka/spłata powstaje w aplikacji. Dwa budżety
zostają lokalne. Aplikacja nie łączy się już z serwerem synchronizacji;
przy powrocie do poprzedniej wersji synchronizacja byłaby znów dostępna.

## Konsekwencje

- **Pozytywne:**
  - Jeden mechanizm zamiast cyklu, korekt, rat i przelewów — plan na każdy
    miesiąc widać wprost, bez przeliczeń w głowie.
  - Średnia roku liczy się z tego, co faktycznie zaplanowane, łącznie
    z płatnościami kwartalnymi i rocznymi w ich miesiącach.
  - Mniej kodu do utrzymania (synchronizacja, porównania plan/realne).
- **Negatywne / ryzyka:**
  - Duża przebudowa (~13 tys. z ~30 tys. linii) — dlatego etapami na gałęzi,
    z wydaniami DEV po każdym etapie.
  - Płatność kwartalna i roczna z niepełnym rokiem daje inną sumę roku niż
    dawny model (płatność w jej miesiącu zamiast średniej) — świadomie;
    raport konwersji pokazuje takie pozycje.
  - Cykl tygodniowy i „co N dni" przechodzą jako średnia miesięczna — tracą
    rozkład na konkretne dni.
  - Zmiana ceny subskrypcji dalej zmienia wszystkie miesiące roku (jak dziś).

## Rozważane alternatywy

- **Osobny plan na każdy rok** (pozycja należy do roku) — odrzucona: rata
  przez dwa lata to dwie pozycje, a statystyki nie widzą ciągłości pozycji.
- **Migracja przez Excel** (eksport → poprawki → import) — odrzucona: arkusz
  budżetu obejmuje tylko budżet osobisty i gubi powiązania oraz szczegóły
  subskrypcji, a import tylko dokłada pozycje. Pełną kopią jest `.zostaje`.
- **Subskrypcje jako zwykłe pozycje planu** — odrzucona przez właściciela:
  funkcje subskrypcji (okresy próbne, przypomnienia) są w użyciu i od nich
  zaczęła się aplikacja.
- **Zastąpienie starego zapisu w miejscu** — odrzucona: odebrałoby powrót do
  poprzedniej wersji przez zwykłą aktualizację.
- **Skan paragonów tworzący pozycję planu** (zamiast usunięcia) — odrzucona
  przez właściciela: bez śledzenia realnych wydatków skan nie ma czego zasilać,
  a utrzymanie go kosztowało usługę w tle, mostek AIDL i 13 MB w każdej
  aktualizacji.
- **Historia Bieżących jako sumy miesięcy w planie** — odrzucona: liczyłaby
  te same pieniądze co pozycje z Plannera.
