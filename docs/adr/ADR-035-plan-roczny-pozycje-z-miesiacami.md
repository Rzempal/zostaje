# ADR-035: Plan roczny — pozycje z miesiącami zamiast cykli i korekt

Data: 2026-10-06
Status: zaakceptowany — wdrażany etapami na gałęzi `przebudowa-plan-roczny` (Faza 16)

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
- **Bieżące** — na razie bez zmian.

### 4. Karta kredytowa w planie

„Pożyczka z karty" jako para w planie: wpływ w miesiącu użycia i spłata
w miesiącu wynikającym z okresu bezodsetkowego karty (kwotę spłaty można
zmienić osobno, np. o prowizję). Automat w Bieżących (lustro zakupu + spłata,
ADR-033) zostaje wyłączony — zakup kartą to zwykły wydatek.

Zapis: dwie pozycje planu rodzajów `cardLoan` i `cardRepayment`, każda
z jednym miesiącem, spięte wspólnym `linkId` (usunięcie jednej usuwa drugą).
Liczone OSOBNO od wpływów i wydatków — jako „karta netto" w „Zostaje" — bo
w skali roku para się znosi, a wliczona do wpływów i wydatków zawyżałaby obie
średnie.

### 3a. Zakładka „Budżet" po przebudowie

Dwie pod-zakładki: **Statystyki** (wybrany rok: średnio miesięcznie, wykres
12 miesięcy, kategorie, limity i okresy próbne subskrypcji) i **Kalendarz**
(dawny „Bilans miesiąca" bez realnego bilansu). Kalendarz bierze dane z planu
(miesiące pozycji z dniem płatności), z odnowień subskrypcji i z Bieżących.
Pozycja bez dnia płatności nie ma miejsca na kalendarzu.

### 5. Konwersja danych i powrót

- Konwersja jest automatyczna (przy starcie i po odtworzeniu starej kopii)
  i czysta: reguły w `services/plan_conversion.dart`, sprawdzone testami.
- **Stare pozycje zostają nietknięte** w dotychczasowych pudełkach bazy, plan
  trafia do osobnego pudełka `plan_positions`. Identyfikator pozycji planu =
  identyfikator starej pozycji, więc odhaczenia płatności nie przepadają.
- **Powrót** do poprzedniej wersji: zbudowanie starej rewizji z WYŻSZYM numerem
  wersji (numer nadajemy sami, ADR-031) i zwykła aktualizacja — bez
  odinstalowania. Stara wersja widzi plan z chwili konwersji, a Bieżące
  aktualne (zostają w tym samym miejscu).
- Raport konwersji w Developer Tools porównuje sumy roku ze starego modelu
  z nowym planem — sprawdzenie na prawdziwych danych bez wynoszenia ich
  z telefonu.

### 6. Synchronizacja budżetu domowego — usunięta

Udostępnianie budżetu: eksport/import (Excel jako tabela roku). Dwa budżety
zostają lokalne.

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
