# ADR-006: Budzet domowy jako osobny zbior + przelew jako para linkId

Data: 2026-06-17
Status: częściowo zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — dwa budżety zostają (jako `budgetId` pozycji planu), przelew między budżetami usunięty
## Kontekst

Budzet (dotad jeden, osobisty) rozszerzono o **wspolny budzet domowy** (rodzina/partner,
kilku wplacajacych). Wymog uzytkownika: w przyszlosci synchronizowac online **tylko budzet
domowy** (osobisty zostaje lokalny, zgodnie z zasada „zero cloud").

## Decyzja

1. **Osobny box Hive dla domowego** — `household_budget_entries` obok `budget_entries`
   (osobisty). Granica przechowywania = granica przyszlej synchronizacji (push/pull jednego
   zbioru), bez bolesnego rozcinania wspolnego worka pozniej. Zakres wybiera box:
   `enum BudgetScope { personal, household }`; metody `StorageService` i `BudgetController`
   sa parametryzowane zakresem. Brak migracji — istniejace pozycje zostaja osobiste.
2. **Bez duplikacji kodu** — `BudgetService` jest czysty; ten sam silnik liczy oba zakresy.
   Ekrany (Budzet, Dashboard) parametryzowane aktywnym zakresem (przelacznik `BudgetScope`
   trzymany w `BudgetController`). Jeden komplet ekranow, nie dwa.
3. **Przelew do domowego = para spieta `linkId`** — w osobistym typ
   `BudgetEntryType.householdTransfer` (koszt), w domowym lustrzany `income` („wklad").
   Edycja/usuniecie/pauza po stronie osobistej kaskaduje na lustro; lustro w domowym jest
   tylko do odczytu. Dwie pozycje (nie jedna) sa konieczne, bo osobisty NIE moze sie
   synchronizowac, a domowy musi pokazac wklad rodzinie.
4. **Czlonek rodziny — recznie** jako wplyw w domowym („Wklad — imie"). Encja „czlonek"
   + synchronizacja = przyszlosc (#TODO).
5. **Subskrypcje — lzej**: pole `SubscriptionScope { personal, household }` w istniejacym
   boxie (filtr list i statystyk), bez box-splitu — brak wymogu sync dla subskrypcji.
6. **Backup v4** — obejmuje `householdBudgetEntries` oraz `scope` subskrypcji (guard `version > 4`).

## Konsekwencje

- **Pozytywne:** gotowa granica przyszlej synchronizacji; zero migracji; jeden silnik;
  przelew jako spojna para (saldo osobiste −X, domowe +X); subskrypcje filtrowalne per zakres.
- **Negatywne / ryzyka:**
  - Przelew = dwie pozycje w dwoch boxach → ryzyko desync; mitygacja: `linkId` + kaskada
    w kontrolerze, lustro read-only.
  - Niesymetria: budzet = osobny box, subskrypcje = pole `scope` (swiadoma, uzasadniona wymogiem).
  - Import Excel pozycji `householdTransfer` nie tworzy lustra (pomija kontroler) — edge,
    do obejrzenia przy ewentualnym Excelu budzetu domowego.
  - Faktyczna synchronizacja online = osobna, pozniejsza decyzja (backend + konta = koszt).

## Rozwazane alternatywy

- **Jeden box + pole `scope`** — prostsze lokalnie, ale granica sync przecina jeden zbior →
  bolesne przy przyszlej synchronizacji tylko domowego. Odrzucone z powodu wymogu sync.
- **Dwa osobne budzety (osobne ekrany)** — pelna izolacja, ale podwojne utrzymanie i kruchy
  przelew. Odrzucone — `BudgetService` i tak jest wspoldzielony.
