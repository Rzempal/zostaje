# ADR-019: Podział sekcji aplikacji — nazwy i właściciele tematów

Data: 2026-07-26
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — zakładki: Budżet, Planowanie, Ustawienia

## Kontekst

Nazwy zakładek rozjechały się ze znaczeniem:

- **„Dashboard"** — nazwa techniczna, a ekran jest przeglądem całego budżetu.
- **„Budżet"** — nazwa całej domeny na ekranie, który jest tylko *zarządzaniem
  pozycjami*. Skoro „Dashboard" pokazuje budżet, „Budżet" musiał znaczyć coś węższego.
- **Wpływy** siedziały w jednym worku z wydatkami, choć to przeciwna strona bilansu.
- **Koperta „Na rachunki"** (rezerwa planu na pulę rachunków) była edytowana na ekranie
  „Budżet", a realizowana i porównywana z rzeczywistością na ekranie „Rachunki" — temat
  rozdarty między dwa ekrany.

Kwestia **wpływów** przeszła pełną pętlę. Pierwotnie odrzucono dla nich osobną
zakładkę (argument: 2–3 pozycje ruszane raz na kwartał dostałyby najdroższą
powierzchnię w aplikacji) i wdrożono je jako pod-zakładkę ekranu wydatków. **W użyciu
okazało się to zbyt schowane** — pod-zakładka nie sygnalizuje, że wpływy w ogóle
istnieją. Decyzja skorygowana na osobną zakładkę; szczegóły w punkcie 2.

## Decyzja

Sześć zakładek — każdy temat ma własną, nazwaną powierzchnię:

Kolejność układa się w ścieżkę pieniędzy: przegląd → skąd przychodzą → gdzie wychodzą.

| Zakładka | Znaczenie |
|---|---|
| **Budżet** (dawny „Dashboard") | Przegląd całości: bilans miesiąca, płatności, podsumowanie, plan |
| **Wpływy** | Wpływy cykliczne (pensja) i jednorazowe (premia) |
| **Rachunki** | Datowane wydatki jednorazowe (ADR-018) + **Planner** (plan kwoty na rachunki) + skan AI |
| **Subskrypcje** | Bez zmian — świadomie oddzielone od kosztów stałych (koszty uznaniowe) |
| **Wydatki** (dawny „Budżet") | Pozycje planowalne: koszty stałe, raty, przelew do domowego. Tytuł ekranu: „Wydatki cykliczne" |
| **Ustawienia** | Bez zmian |

### 1. Koperta „Na rachunki" należy do Rachunków

Skład koperty i jej edycja przenoszą się na ekran „Rachunki" — tam, gdzie widać realne
rachunki tej samej puli i porównanie plan/rzeczywistość. Na ekranie wydatków zostaje
**sam wiersz z sumą** (bez edycji), bo rezerwa nadal pomniejsza „zostaje/mies" i suma
planu musi się tłumaczyć. Kod edytora wyprowadzony do `widgets/bills_allocation_editor.dart`,
żeby nie duplikować go między ekranami.

### 2. Wpływy jako osobna zakładka (decyzja skorygowana po testach)

Wariant z pod-zakładką został **zbudowany i odrzucony w użyciu**: pod-zakładka nie
komunikuje istnienia sekcji, więc wpływy zniknęły z pola widzenia. Osobna zakładka
wygrywa, mimo że jest rzadziej używana — widoczność jest tu ważniejsza niż
oszczędność miejsca.

Obawa o ciasnotę paska okazała się mniejsza, niż zakładano: `GlassNavBar` pokazuje
**etykietę tylko aktywnej** pozycji, pozostałe to same ikony. Do tego pigułka dostała
strażnika szerokości (`FittedBox(scaleDown)` + marginesy) — przy szóstej pozycji albo
na wąskim ekranie skaluje się w dół, zamiast wyjść za krawędź.

Oba ekrany pozycji planowalnych to **jeden widget** w dwóch trybach
(`BudgetEntriesMode`) — filtry, sortowanie, grupowanie, Excel i stany puste są
wspólne, różni je tylko zestaw kubełków i drobiazgi w pasku akcji.

### 3. Nazwy tylko w UI

`BudgetController`, `BudgetScope`, `BudgetEntry` itd. zostają bez zmian — „budget" jest
poprawną nazwą **domeny danych**, a myląca była wyłącznie etykieta zakładki. Refaktor
nazw w kodzie byłby ryzykiem bez zysku.

## Konsekwencje

- (+) Każdy temat ma jednego właściciela: rachunki (z ich rezerwą), koszty cykliczne,
  wpływy, subskrypcje, przegląd.
- (+) Nazwa „Wydatki cykliczne" jest prawdziwa dopiero po ADR-018 (datowane jednorazowe
  wyszły do Rachunków) — te dwie decyzje są ze sobą sprzęgnięte.
- (−) Zmiana nazw łamie pamięć mięśniową; jednorazowy koszt przy jednym użytkowniku.
- (−) Ekran „Rachunki" robi się gęsty (rachunki + koperta + skan) — jeśli zacznie
  przytłaczać, następnym krokiem są tam pod-zakładki, nie rozdzielanie tematu.
- (−) Sześć pozycji w pasku to jego górna granica. Kolejna sekcja wymagałaby
  przeprojektowania nawigacji, nie dopisania ikony.

## Etapy wdrożenia

1. Scalenie typów — [ADR-018](ADR-018-scalenie-wydatku-jednorazowego-z-rachunkiem.md). ✅
2. Koperta „Na rachunki" → ekran Rachunki (wiersz sumy zostaje w wydatkach). ✅
3. Nazwy zakładek + Wpływy (najpierw pod-zakładka, po testach osobna zakładka). ✅
4. Osobno, poza tym ADR: rozszerzenie cykli (co N miesięcy, konkretne miesiące roku).
