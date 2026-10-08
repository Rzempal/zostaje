# ADR-011: Rachunki jako realny log opłat, scalenie typów cyklicznych, koperta „Na rachunki"

Data: 2026-07-09
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — nie ma już dziennika realnych wydatków ani typów cyklicznych

## Kontekst

Cel: na koniec miesiąca porównać **plan** z **realnymi wydatkami** danego miesiąca
(„predykcja vs rzeczywisty bilans"). Dotychczasowy model budżetu (ADR-004, ADR-008)
opisywał wyłącznie pozycje **planowalne** (cykliczne + jednorazowe). Brakowało miejsca
na **nieplanowalne, faktycznie już opłacone** rachunki — coś, czego z założenia nie da
się z góry rozpisać co do grosza, a co w przyszłości ma trafiać automatycznie z OCR
(zdjęcie/screenshot/PDF, lokalny silnik Gemma).

Przy projektowaniu ujawniły się dwa problemy w istniejącym modelu:

1. **Kolizja nazw i pojęć.** Typ `bill` był etykietowany „Rachunek", ale semantycznie był
   kosztem cyklicznym z opcjonalną korektą (prąd/gaz/czynsz) — czyli pozycją **planu**,
   a nie logiem realnych opłat.
2. **Sztuczny podział `bill` vs `recurringCost`.** Po ADR-008 jedyną różnicą między nimi
   była możliwość dodania korekty miesięcznej (`monthOverrides`). Dwa typy dla jednej
   różnicy to duplikacja bez wartości.

## Decyzja

### 1. Scalenie `bill` → `recurringCost` (koszt cykliczny z opcjonalną korektą)

Typ `bill` **usunięty z enuma**. `recurringCost` zyskuje obsługę korekt miesięcznych
(`supportsMonthOverrides == recurringCost || householdTransfer`). Brak korekty = zachowanie
jak dawny „Koszt cykliczny" (stały); dodana korekta = jak dawny „Rachunek" (zmienny).
Funkcja korekty (ADR-008) **zostaje** — zmienia się tylko nośnik.

**Migracja bez kodu:** `BudgetEntry.fromJson` ma `orElse: recurringCost`, więc zapisane
pozycje `"type":"bill"` (Hive, backup, sync) same deserializują się do `recurringCost`;
pole `monthOverrides` jest niezależne od typu, więc korekty nie giną. Usunięcie wartości
z enuma sprawia, że kompilator wskazuje wszystkie `switch` do uzupełnienia (bezpieczniej
niż martwa wartość).

### 2. Nowy typ `billPayment` (etykieta „Rachunek") = realny log

Datowana, faktycznie opłacona pozycja. W silniku traktowana jak **wydatek jednorazowy**
(`isOneTime == true`): **nie wchodzi** do planu „zostaje miesięcznie" (`monthlySurplus`),
a **zasila bilans** wskazanego miesiąca (`balanceForMonth`) i kalendarz. Reużywa
istniejącego modelu `BudgetEntry` (serializacja, backup, synchronizacja domowego, kalendarz
— za darmo). Osobny typ (a nie `oneTimeExpense`) pozwala filtrować ekran „Rachunki" i liczyć
statystykę plan vs realny.

### 3. Koperta „Na rachunki" = planowany koszt (pomniejsza plan)

Kwota rezerwowana miesięcznie na pulę nieplanowalnych rachunków. Przechowywana w
`settings` **per zakres** (`billsAllocation|personal` / `billsAllocation|household`),
wzorzec jak `budgetLimit`; edytowana jako **pozycja w Budżecie** (przypięta na górze
listy wydatków, wliczona do sumy sekcji).

**Koperta pomniejsza plan `monthlySurplus`** (`surplus = wpływy − koszty cykliczne −
subskrypcje − „Na rachunki"`). W **bilansie miesiąca** koperta jest **oddawana** i
zastąpiona **realnymi rachunkami** (`billPayment`): `balanceForMonth = surplus +
„Na rachunki" − realne rachunki (jako jednorazowe) + …` — koperta się skraca, więc
bilans liczy **faktyczne** rachunki. Bez podwójnego liczenia. Rozbicie „skąd bilans"
dostaje wkład `BalanceContributionKind.billsAllocation` (+koperta), utrzymując inwariant
`suma delt == bilans − surplus` (ADR-008). Predykcja („Plan"):
`przewidywany bilans = monthlySurplus` (już po odjęciu koperty) vs
`rzeczywisty bilans = balanceForMonth`.

> **Ewolucja decyzji:** pierwotnie koperta miała być czystą statystyką (nie ruszać
> surplus). W trakcie wdrożenia — na życzenie właściciela — stała się planowanym
> kosztem widocznym w Budżecie (pomniejsza „zostaje/mies"), z podmianą na realne
> rachunki w bilansie miesiąca.
>
> **Ewolucja (ADR-012):** koperta nie jest już pojedynczą kwotą, lecz **sumą listy
> pozycji** (`billsAllocationItems|scope`, nazwa + kwota + metoda płatności). Silnik
> nadal dostaje jedną liczbę (Σ) — zachowanie bez zmian. Patrz
> [ADR-012](ADR-012-koperta-na-rachunki-lista-pozycji.md).

### 4. Osobisty/Domowy = pudełko, nie pole

Rachunek (jak każda pozycja) trafia do właściwego boxu Hive przez aktywny `BudgetScope`
(osobisty lokalny, domowy synchronizowany E2E — ADR-006/009). Przełącznik w formularzu
ustawia zakres; **nie** dodajemy pola `scope` do pozycji (to złamałoby granicę
synchronizacji).

## Uzupelnienie (2026-08-02): ekran Rachunkow filtruje zamiast przewijac miesiace

Karta miesiaca ze strzalkami zalatwiala jedno pytanie („ile w tym miesiacu"),
ale kazde inne — „gdzie jest rachunek z maja", „ile poszlo na Dom w tym roku" —
wymagalo klikania miesiac po miesiacu.

Ekran dostal **ten sam uklad co lista „Wydatki"**: paski filtrow (kategoria +
czas ze skrotem „Dzisiaj"), sortowanie przy filtrach i **naglowek sekcji
„Rachunki" z suma pozycji aktualnie widocznych**. Domyslny filtr to biezacy
miesiac, wiec pierwsze wejscie wyglada jak dotad.

Porownanie z koperta (pasek plan/realny) pokazuje sie **tylko przy wybranym
jednym miesiacu** — koperta jest miesieczna, wiec przy filtrze „caly rok"
zestawialaby jablka z gruszkami.

Reguly filtrowania sa te same co w „Wydatkach" (`ExpensesFilter`), bo rachunek
jest datowana pozycja jednorazowa — filtr czasu dziala na nim bez wyjatkow.

## Konsekwencje

- **Pozytywne:**
  - Realne wydatki miesiąca mają wreszcie swoje miejsce, spójne z rozdziałem plan/realny
    (ADR-008) — rachunki zasilają bilans, nie plan.
  - Jeden typ cykliczny zamiast dwóch — mniej pojęć, koniec duplikacji.
  - Zero migracji danych (deserializacja `bill` → `recurringCost` „w locie").
  - Gotowa podstawa pod OCR (rachunek = datowany wpis z kwotą; miejsce na załącznik w przyszłości).
  - Nowy ekran „Rachunki" i koperta „Na rachunki" — bez dotykania rdzenia synchronizacji.
- **Negatywne / ryzyka:**
  - **Excel (ścieżka wtórna):** stare arkusze, w których koszt cykliczny był etykietowany
    „Rachunek", po re-imporcie stają się `billPayment` (log), a nie `recurringCost`. Dane
    aplikacji migrują poprawnie (Hive/backup) — dotyczy tylko ręcznego re-importu starych
    `.xlsx`. Świadomy kompromis (Excel to format wtórny; „Koszt cykliczny"/„stały" →
    `recurringCost`, „Rachunek"/„bill" → `billPayment`).
  - **Koperta „Na rachunki" nie jest w backupie** (spójnie z `budgetLimit`, który też nie
    jest) — pojedyncza liczba per zakres, do ponownego ustawienia po odtworzeniu. Same
    rachunki (wpisy) są w backupie jako `BudgetEntry`.
  - **Inwariant do pilnowania:** test-strażnik potwierdza, że `billPayment` wchodzi w
    `balanceForMonth`, a NIE w `monthlySurplus` (jak jednorazowe, ADR-008).

## Rozważane alternatywy

- **Rachunek jako przeniesiony `bill` (relokacja typu cyklicznego).** Odrzucone: nie
  oddaje „realnych, już opłaconych" pozycji; OCR per paragon tworzyłby co miesiąc nowy
  cykliczny wpis.
- **Rachunki jako osobny model/box.** Odrzucone: kosztowne (własna serializacja, backup,
  sync, kalendarz) bez zysku — `BudgetEntry` już to wszystko ma.
- **Pole `scope` na pozycji zamiast boxa.** Odrzucone: łamie granicę synchronizacji
  (ADR-006/009) — wyciek osobistych na serwer lub przepisanie rdzenia sync.
- **„Na rachunki" jako rezerwa wchodząca do salda/bilansu.** Odrzucone: ryzyko podwójnego
  liczenia z realnymi rachunkami; sprzeczne z rozdziałem plan/realny.

## Wpływ na ADR-008

Podział `bill` (zmienny) vs `recurringCost` (stały) z ADR-008 zostaje **wycofany** —
jeden typ cykliczny z opcjonalną korektą. Sam inwariant ADR-008 (korekty i pozycje
jednorazowe zmieniają bilans miesiąca, nie plan) **pozostaje w mocy** i rozszerza się na
`billPayment`.
