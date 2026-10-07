# ADR-012: Koperta „Na rachunki" jako lista pozycji (nazwa + kwota + metoda płatności)

Data: 2026-07-12
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — pozycje koperty stały się zwykłymi pozycjami planu

## Kontekst

Koperta „Na rachunki" (ADR-011 pkt 3) była **pojedynczą kwotą** per zakres
(`billsAllocation|scope` w `settings`). Właściciel chce widzieć, **z czego** składa
się rezerwa (np. Paliwo 300 + Barber 120 = 420) i przypisać każdej pozycji **metodę
płatności**. Bufor/zapas ma być zwykłą pozycją na liście (np. „bufor").

Wymóg twardy: cała matematyka planu vs realny (ADR-008/011) — koperta pomniejsza
`monthlySurplus`, a w `balanceForMonth` jest oddawana i podmieniana na realne rachunki
— **nie może się zmienić** (zero ryzyka rozjazdu „zostaje/mies").

## Decyzja

### 1. Nowy model `BillsAllocationItem`

`{id, name, amount, paymentMethod?}` — lista per zakres w `settings`
(`billsAllocationItems|scope`, JSON). Zastępuje pojedynczą liczbę.

### 2. Silnik dostaje sumę — matematyka bez zmian

`StorageService.getBillsAllocation(scope)` zwraca teraz **Σ pozycji** (null gdy pusto).
`BudgetController.billsAllocation` = ta suma. Cały pipeline (`monthlySurplus`,
`balanceForMonth`, `balanceBreakdownForMonth`, predykcja na Dashboardzie) dostaje
**jedną liczbę jak dawniej** — nietknięty. To sedno: itemizacja jest wyłącznie warstwą
UI/przechowywania nad tą samą liczbą.

### 3. Koperta zostaje izolowana od pozycji budżetu

Pozycje koperty **nie są** `BudgetEntry` (patrz alternatywy) — nie wchodzą do żadnych
agregatów, wykresów kategorii, kalendarza ani Excela. CRUD (`add/update/remove`) na
`BudgetController` zapisuje listę do `settings`.

### 4. Migracja bez utraty

`getBillsAllocationItems` czyta starą pojedynczą kwotę (`billsAllocation|scope`) jako
**jedną pozycję „Na rachunki"**, dopóki użytkownik nie zapisze listy; pierwszy zapis
listy usuwa stary klucz. Istniejąca rezerwa nie ginie.

### 5. Metoda płatności widoczna na kafelkach

Pole `BudgetEntry.paymentMethod` (istniało, nieużywane w UI) jest teraz pokazywane na
`BudgetEntryCard` (ikona ⚡ auto / ✋ manual + nazwa), oraz na pozycjach koperty — tylko
tam, gdzie metodę da się zdefiniować (typy wydatkowe; wpływy bez metody jej nie pokazują).

## Konsekwencje

- **Pozytywne:**
  - Rezerwa ma czytelne rozbicie; bufor = zwykła pozycja (bez osobnego pojęcia).
  - Silnik i inwarianty ADR-008/011 nietknięte (jedna liczba na wejściu).
  - Migracja „w locie", zero utraty danych.
  - Metoda płatności wreszcie widoczna (pole istniało od dawna).
- **Negatywne / ryzyka:**
  - Pozycje koperty — jak sama koperta wcześniej — **poza backupem i synchronizacją
    domowego** (`settings`, nie box synchronizowany). Spójne ze stanem sprzed zmiany;
    do rozważenia razem ze starą otwartą kwestią koperty.
  - Metoda płatności to **słownik współdzielony** — zmiana nazwy/usunięcie metody musi
    kaskadować także na pozycje koperty (zaadresowane w tej samej sesji).

## Rozważane alternatywy

- **Pozycje jako nowy typ `BudgetEntry`.** Odrzucone: rozlałoby się na ~8 agregatów
  (surplus, bilans, wykres kategorii, kalendarz, Excel, kubełki wydatków) z realnym
  ryzykiem **podwójnego liczenia**. Koperta jest celowo izolowana od pozycji (ADR-011).
- **Osobny box/model z pełną serializacją + backup + sync.** Odrzucone: koszt bez zysku;
  utrzymana spójność ze stanem koperty sprzed zmiany (i tak lokalna).
- **Header = osobna rezerwa, pozycje = częściowe rozbicie z buforem.** Odrzucone na
  życzenie właściciela: total = Σ pozycji; bufor dodaje się jako zwykła pozycja.

## Uzupełnienie (2026-08-01): Planner ma własny ekran

Plan koperty był sekcją zwijaną na ekranie „Rachunki", a „Wydatki cykliczne"
pokazywały samą sumę z podpisem „edycja w Rachunkach". Po tym, jak subskrypcje
weszły do „Wydatków" (ADR-027), ten podpis stał się jedyną rzeczą na ekranie,
która odsyłała gdzie indziej zamiast działać.

Plan mieszka teraz na **własnym ekranie** (`BillsPlannerScreen`), a oba ekrany
prowadzą do niego tak samo: karta „Planner" na „Rachunkach" i wiersz sumy na
„Wydatkach". Zwijanie zniknęło razem ze swoim ustawieniem — ekran nie zabiera
miejsca liście, więc nie ma czego chować.

Zakres (osobisty/domowy) jest **dziedziczony** z ekranu, z którego weszliśmy, i
pokazany w podtytule; przełącznika tam nie ma. Koperty są dwie, a przełączanie
zakresu w podekranie to prosta droga do edycji nie tej, o którą chodziło.

## Wpływ na ADR-011

Punkt 3 (koperta „Na rachunki") — koperta **nie jest już pojedynczą kwotą**, lecz
**sumą listy pozycji** (`billsAllocationItems|scope`). Zachowanie w silniku (pomniejsza
`monthlySurplus`, oddawana i podmieniana na realne rachunki w `balanceForMonth`) oraz
brak backupu/sync — **bez zmian**.
