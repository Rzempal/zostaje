# ADR-022: Planner w synchronizacji budżetu domowego

Data: 2026-07-26
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — usunięte razem z synchronizacją i Plannerem

## Kontekst

Synchronizacja domowa (ADR-009) przesyłała **wyłącznie** pozycje
`household_budget_entries`. Planner („Na rachunki", ADR-012/019) siedzi w lokalnych
ustawieniach telefonu, więc nie jechał nigdzie — mimo że jego suma **pomniejsza plan
„zostaje miesięcznie"**.

Przy jednym użytkowniku to była kosmetyka. Od 2026-07-26 kanał PROD prowadzi realny
budżet domowy **dwóch osób na dwóch sparowanych telefonach**, więc każde urządzenie
miało własną zaplanowaną kwotę na rachunki i **oba pokazywały różne „zostaje
miesięcznie" dla tego samego budżetu**. To już nie kosmetyka, a sprzeczność.

Dwa ograniczenia zastane w kodzie:

1. `BillsAllocationItem` nie miał znacznika czasu ani nagrobka — inaczej niż
   `BudgetEntry`. Bez nich scalanie per pozycja jest niemożliwe.
2. `SyncMerge.decodeSnapshot` wymaga **dokładnej zgodności** wersji paczki
   (`v != snapshotVersion` → wyjątek). Podbicie wersji **zatrzymuje synchronizację**,
   dopóki oba telefony nie zostaną zaktualizowane.

## Decyzja

### 1. Planner dostaje `updatedAt` i nagrobek

`BillsAllocationItem` zyskuje `updatedAt` (klucz scalania) i `deleted` (nagrobek).
Usunięcie pozycji w zakresie **domowym** zostawia nagrobek, żeby dotarło do drugiego
telefonu; w zakresie **osobistym** (bez synchronizacji) nadal kasujemy twardo.

Scalanie (`SyncMerge.mergeAllocation`) działa tą samą regułą co pozycje budżetu:
nowszy `updatedAt` wygrywa, remis rozstrzyga deterministyczny tie-break po treści.
Pozycje bez znacznika (zapisane przed tym ADR) są traktowane jako najstarsze — mogą
zostać nadpisane świeższą zmianą, ale samo ich istnienie nie ginie.

Konsekwencja w kodzie: **każda mutacja Plannera musi budować listę z wersji
z nagrobkami** (`getBillsAllocationItemsRaw`), nie z widocznej — inaczej pierwszy
zapis wymazywałby nagrobki i usunięcie przestałoby propagować się na drugi telefon.

### 2. Sekcja opcjonalna w paczce, BEZ podbijania wersji

`billsAllocation` dochodzi do paczki przy **tej samej** wersji `v`. Starsza aplikacja
czyta tylko `entries`, więc ignoruje nieznane pole i synchronizacja działa dalej, gdy
jeden telefon zaktualizuje się później. Podbicie `v` zatrzymałoby wymianę danych między
telefonami do czasu aktualizacji obu — nieakceptowalne w układzie używanym na żywo.

### 3. Brak sekcji = brak informacji, NIE „pusta lista"

Paczka bez `billsAllocation` daje `allocation == null` i scalanie **zostawia lokalny
Planner w spokoju**. Pusta lista **w** paczce jest znacząca („Planner jest pusty") i
wygrywa scalaniem.

Bez tego rozróżnienia telefon ze starszą aplikacją wyczyściłby Planner nowszemu —
dokładnie ta pułapka, która tego samego dnia skasowała Planner przy odtwarzaniu
backupu (ADR-021 pkt 2).

### 4. Anty-ping-pong

Gdy paczka na serwerze nie ma sekcji, dopychamy ją **tylko jeśli lokalny Planner nie
jest pusty**. Inaczej dwa telefony z pustym Plannerem biłyby wersję skrzynki bez końca.

### 5. Zakres: tylko domowy

Planner osobisty zostaje lokalny, spójnie z tym, że cały budżet osobisty nie jest
synchronizowany (prywatność każdej ze stron).

## Konsekwencje

- (+) Oba telefony pokazują to samo „zostaje miesięcznie" dla budżetu domowego.
- (+) Jednoczesna edycja Plannera na dwóch telefonach nie gubi zmian (scalanie per
  pozycja, nie „cała lista ostatniego zapisu").
- (+) Aktualizacja telefonów może nastąpić w różnym czasie — synchronizacja nie pada.
- (−) Pozycje Plannera zapisane przed tą zmianą nie mają `updatedAt`, więc w kolizji
  przegrywają z każdą świeższą wersją z drugiego telefonu.
- (−) Nagrobki Plannera zostają w danych na zawsze (jak dla pozycji budżetu) —
  rosną wolno, ale nie ma dziś mechanizmu ich sprzątania.

## Weryfikacja

`test/sync_allocation_test.dart` (scalanie: zachowanie pozycji z obu stron, nowsza
zmiana wygrywa, nagrobek propaguje, brak znacznika nie gubi pozycji, niezależność od
kolejności, idempotencja; paczka: sekcja obecna/nieobecna/pusta) oraz
`test/sync_service_test.dart` (paczka bez sekcji nie czyści lokalnego Plannera; Planner
partnera dociera i scala się; anty-ping-pong nadal działa).
