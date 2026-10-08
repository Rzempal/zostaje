# ADR-018: Scalenie wydatku jednorazowego z rachunkiem (jeden datowany wydatek)

Data: 2026-07-26
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — nie ma już wydatków datowanych; jednorazowy wydatek to pozycja planu z jednym miesiącem

## Kontekst

Model miał dwa typy na jedną rzecz:

- `billPayment` („Rachunek") — datowany wydatek, log już opłaconej pozycji,
- `oneTimeExpense` („Wydatek jednorazowy") — datowany wydatek, większy zakup.

**W matematyce budżetu były nierozróżnialne.** Oba są `isOneTime`, więc oba stoją
poza planem „zostaje/mies" (`monthlyAmount == 0`) i oba korygują `balanceForMonth`
tą samą ścieżką (`BudgetService.oneTimeExpensesForMonth`, wkład
`BalanceContributionKind.oneTimeExpense`). Różniła je wyłącznie intencja i to, na
którym ekranie się pokazywały.

Do tego formularz rachunku od początku przyjmuje **dowolną datę**, także przyszłą —
czyli „rachunek zaplanowany na przyszły miesiąc" i „wydatek jednorazowy" to był
dokładnie ten sam byt wpisywany dwoma ścieżkami. Dwa formularze, dwa miejsca
dodawania, jedna semantyka.

Rozróżnienie „rachunek za prąd vs nowa pralka" nosi już **kategoria** — wymiar
o kilkunastu wartościach zamiast dwóch, i to on zasila statystyki.

## Decyzja

### 1. Jeden typ: `billPayment`

`oneTimeExpense` **usunięty z enuma** (wzorzec z ADR-011: usunięcie zamiast martwej
wartości sprawia, że kompilator wskazuje wszystkie miejsca do poprawy). Znaczenie
`billPayment` rozszerzone: **datowany wydatek jednorazowy** — opłacony (log) albo
zaplanowany na przyszłą datę. Jedno miejsce dodawania: ekran „Rachunki".

Wpływ jednorazowy (`oneTimeIncome`) zostaje osobno — to strona wpływów.

### 2. Migracja przez jawne mapowanie nazwy typu

`BudgetEntry.typeFromName` mapuje `"oneTimeExpense" → billPayment` (oraz nadal
`"bill" → recurringCost` z ADR-011). **To nie jest kosmetyka:** `fromJson` ma
domyślkę `recurringCost`, więc bez tego mapowania każdy stary wydatek jednorazowy
(np. pralka za 3000 zł) odczytałby się jako **koszt cykliczny** i zacząłby
obciążać plan co miesiąc. Dotyczy naraz bazy lokalnej, backupu `.zostaje`
i synchronizacji domowej — wszystkie idą tym samym parserem.

Import Excela ma własny parser: etykieta „Wydatek jednorazowy" ze starszych
arkuszy również mapuje się na rachunek.

Test-strażnik: `test/budget_type_migration_test.dart` pilnuje mapowania oraz tego,
że zmigrowana pozycja ma `monthlyAmount == 0` i nie zmienia `monthlySurplus`.

### 3. Odhaczanie płatności po dacie, nie po typie

Dotychczas **każdy** nowy rachunek był od razu oznaczany jako „wykonany" — więc
rachunek z datą przyszłą udawał zapłacony (istniejący błąd, ujawniony przy
scalaniu). Nowa reguła: `data ≤ dziś → wykonane`, data przyszła → czeka na
ręczne odhaczenie.

### 4. Metoda płatności w formularzu rachunku

Formularz rachunku dostał pole „Metoda płatności", którego wcześniej nie miał
(a formularz pozycji budżetu miał). Bez niego wszystkie scalone pozycje wpadałyby
w kalendarzu do „do zrealizowania ręcznie", bo automat rozpoznaje się właśnie po
metodzie płatności.

## Konsekwencje

- (+) Jeden byt, jeden formularz, jedno miejsce dodawania — koniec z decyzją
  „to rachunek czy wydatek jednorazowy?", która nie miała znaczenia dla wyliczeń.
- (+) Ekran „Budżet" zostaje wyłącznie pozycjami **planowalnymi**, co otwiera drogę
  do przemianowania go na „Wydatki cykliczne" bez kłamstwa w nazwie.
- (+) Rachunek na przyszłą datę przestaje udawać zapłacony.
- (−) Koperta „Na rachunki" porównuje teraz plan z sumą **wszystkich** datowanych
  wydatków miesiąca, więc w miesiącu z dużym zakupem pokaże duże przekroczenie.
  Świadoma zgoda: taki zakup faktycznie rozwala miesiąc, a bilans miesiąca był
  poprawny w obu wariantach. Gdyby szum przeszkadzał, naprawa jest addytywna
  (zawężenie koperty do wybranych kategorii), nie przez przywracanie typu.
- (−) Etykieta „Wydane w tym miesiącu" na ekranie Rachunki zmieniona na
  „Rachunki tego miesiąca" — suma obejmuje pozycje jeszcze nieopłacone.
- Zmiana jest **jednokierunkowa**: po zapisie pozycje mają typ `billPayment`,
  więc powrót do starego układu wymagałby odtworzenia z backupu zrobionego
  przed aktualizacją.
