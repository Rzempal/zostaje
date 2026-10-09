# ADR-014: Tryb budżetu (Osobisty / Domowy / oba) sterujący przełącznikiem zakresu i swipe

Data: 2026-07-24
Status: zastąpiony przez [ADR-037](ADR-037-budzety-z-nazwami.md) (2026-10-09) — tryb budżetu zastąpiło ukrywanie budżetów z nazwami

## Kontekst

Zakres budżetu (osobisty/domowy) jest **globalny** (`BudgetController.scope`) i do tej
pory zawsze przełączalny: na każdej karcie (Dashboard, Rachunki, Budżet, Subskrypcje)
wisiał przełącznik/segment zakresu, a poziomy gest przesunięcia (`ScopeSwipeArea`)
przełączał osobisty↔domowy na wszystkich ekranach.

Użytkownik, który świadomie **nie korzysta z budżetu domowego** (a więc i z synchronizacji
E2E, ADR-009), płaci za to miejscem na ekranie (zbędny przełącznik) i „marnuje" gest
przesunięcia na przełączanie, którego nie potrzebuje.

## Decyzja

Wprowadzamy **tryb budżetu** — lokalną preferencję UI `BudgetMode ∈ {personalOnly,
householdOnly, both}` (Ustawienia → Personalizacja → „Wybór budżetów"; domyślnie `both`,
czyli dotychczasowe zachowanie).

- `BudgetController.scopeSelectable` = `mode == both`. Przy trybie jednozakresowym
  `setScope` jest zablokowane, a `setBudgetMode` wymusza odpowiedni zakres.
- **Tryb jednozakresowy** chowa przełącznik/segment zakresu na wszystkich ekranach
  (`if (scopeSelectable)`) — więcej miejsca.
- `ScopeSwipeArea` dostaje `enabled`. Gdy `false` (tryb jeden) staje się **przezroczysta
  dla gestu** — oddaje swipe dziecku. Na Dashboardzie `TabBarView` z włączonym swipe
  przełącza wtedy zakładki drugiego rzędu (Bilans miesiąca ↔ Plan); ekrany bez takich
  zakładek po prostu ignorują gest.
- Zmiana jest **nieniszcząca**: dane obu zakresów zostają, tryb je tylko chowa/odsłania.
  Wpis „Budżet domowy / synchronizacja" w Ustawieniach zostaje widoczny.

## Konsekwencje

- **Pozytywne:** czystszy ekran dla użytkownika jednego budżetu; gest przesunięcia zyskuje
  sensowne działanie tam, gdzie zakres jest zablokowany; zero utraty danych, w pełni
  odwracalne.
- **Negatywne / ryzyka:** dodatkowy stan globalny do uwzględnienia na każdym nowym ekranie
  z zakresem (trzeba pamiętać o `scopeSelectable` i `ScopeSwipeArea(enabled:)`). Swipe na
  zakładki 2. rzędu na razie tylko na Dashboardzie — inne ekrany nie mają celu dla gestu.

## Rozważane alternatywy

- **Trzymać zawsze przełączalny zakres** — odrzucona: nie rozwiązuje prośby o więcej
  miejsca i sensowniejszy gest dla użytkownika jednego budżetu.
- **`ScopeSwipeArea` sama przełącza zakładki w trybie jednym (własny callback)** —
  odrzucona na rzecz oddania gestu natywnemu `TabBarView` (mniej kodu, spójna animacja,
  zero dublowania logiki zakładek).
