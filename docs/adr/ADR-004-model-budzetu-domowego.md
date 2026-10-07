# ADR-004: Model budzetu domowego (BudgetEntry, osobno od subskrypcji, hybryda czasu)

Data: 2026-06-16
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — plan roczny: pozycje z miesiącami
## Kontekst

Aplikacja byla trackerem subskrypcji zbudowanym wokol encji `Subscription`.
Cel rozbudowy: zarzadzanie budzetem domowym — wplywy, koszty stale (rachunki),
koszty cykliczne oraz wieksze wydatki jednorazowe.

Analiza kodu wykazala, ze obecny silnik (`AnalyticsService`) to **kalkulator
sredniej miesiecznej**, a nie ksiega transakcji — brak wymiaru czasu i sald
miesiecznych. Trzy z czterech nowych potrzeb (wplywy, rachunki, koszty cykliczne)
pasuja do tego modelu, ale wydatki jednorazowe go lamia (jednorazowy zakup nie
jest srednia miesieczna).

## Decyzja

1. **Jeden model `BudgetEntry`** z enumem `BudgetEntryType`
   (income / bill / recurringCost / oneTimeExpense) — 1:1 z czterema potrzebami.
   Typy cykliczne normalizowane do kwoty/mies; `oneTimeExpense` przypiety do
   miesiaca (`month` = "YYYY-MM") i nie wchodzi do sredniej.
2. **Osobno od subskrypcji.** Modul subskrypcji (wydany w 0.3) pozostaje nietkniety.
   Budzet to nowa, rownolegla warstwa (`BudgetService`), ktora czyta subskrypcje
   jako dodatkowy strumien kosztow (przez `AnalyticsService.getMonthlyTotal`).
3. **Hybryda czasu.** Rdzen usredniony: `surplus = wplywy - (koszty cykliczne + subskrypcje)`
   ("zostaje miesiecznie"). Dodatkowo bilans wskazanego miesiaca:
   `balanceForMonth = surplus - wydatki jednorazowe tego miesiaca`.
4. **Storage wzorcem istniejacym** — nowy `Box<String> budget_entries`, JSON-string,
   bez type adapters (spojne z [ADR-001](ADR-001-hive-json-bez-code-gen.md)).
   Backup podbity do wersji 3 (obejmuje `budgetEntries`).

## Konsekwencje

- **Pozytywne:**
  - Zmiany addytywne — brak migracji danych, zero ryzyka regresji w subskrypcjach
  - Wspoldzielona normalizacja cyklu (`lib/utils/cycle_math.dart`) — brak duplikacji
  - Sumy budzetu poprawne niezaleznie od tego, gdzie uzytkownik wpisze koszt
    (subskrypcja vs koszt cykliczny) — oba strumienie sa liczone
- **Negatywne / ryzyka:**
  - Dwa rownolegle modele kosztow (Subscription vs BudgetEntry.recurringCost) —
    ryzyko podwojnego wpisu tej samej pozycji; mitygacja: wskazowka w UI
  - 5 zakladek w nawigacji — docelowo "Budzet" moze wchlonac Dashboard
  - Stary build aplikacji nie wczyta backupu v3 (guard `version > 3` rzuca czytelny blad)

## Rozwazane alternatywy

- **Ujednolicenie z `Subscription`** (jeden model pozycji) — odrzucona: refaktor
  wydanego modulu + migracja danych w Hive = realne ryzyko regresji bez wymiernej korzysci.
- **Pelny rejestr miesieczny (ksiega transakcji)** — odrzucona na ten etap:
  duza przebudowa (nowy wymiar czasu, ekran kalendarza) nieproporcjonalna do potrzeby;
  hybryda daje dokladnosc dla jednorazowych bez ksiegi.

## Aktualizacja 2026-06-17: kalendarz przeplywow + jednorazowy wplyw

Rozszerzenie modelu pod kalendarz dni wplywow/wydatkow na Dashboardzie:

- **Kotwica daty bez zmiany schematu:** istniejace, nieuzywane pole `startDate` pelni
  role daty kalendarzowej — dokladna data pozycji jednorazowej; data pierwszego
  wystapienia pozycji cyklicznej. Brak nowego pola = brak migracji.
- **Rzutowanie wystapien:** `occurrencesInRange` (`lib/utils/cycle_math.dart`) liczy dni
  wystapien w miesiacu wg cyklu (clamp dnia 31; krok kalendarzowy `DateTime(y,m,d+n)`
  zamiast `Duration` — odpornosc na DST). Subskrypcje rzutowane z `startDate`+cyklu.
- **Piaty typ `oneTimeIncome`** (premia/bonus): jednorazowy wplyw z data. Nie wchodzi do
  sredniej miesiecznej; `balanceForMonth = surplus + jednorazowe wplywy − jednorazowe wydatki`.
  Dodany jako kolejny typ (a nie refaktor na osie direction×recurrence) — addytywnie,
  niskie ryzyko; `fromJson` z `orElse: recurringCost` chroni stare dane.

**Konsekwencja (znana):** pozycje budzetu utworzone przed ta zmiana nie maja `startDate`,
wiec nie pojawia sie na kalendarzu do czasu edycji (subskrypcje i nowe pozycje dzialaja od razu).
