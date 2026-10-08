# ADR-029: Podsumowanie roczne i poczatek ewidencji

Data: 2026-08-01
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — bez podsumowania wykonania planu i początku ewidencji

> **Powiazane:** [ADR-028 Plan vs rzeczywistosc na wykresach](ADR-028-plan-vs-rzeczywistosc-na-wykresach.md)
> | [ADR-012 Koperta „Na rachunki"](ADR-012-koperta-na-rachunki-lista-pozycji.md)

## Kontekst

Zakladka „Plan" mowila, ile rok MA kosztowac („Koszty roczne" = kwota/mies × 12),
ale nie mowila, gdzie w tym roku realnie jestesmy. Pytanie wlasciciela brzmialo
wprost: kiedy zblizamy sie do planowanych kosztow rocznych.

Druga sprawa: aplikacja jest prowadzona od lipca. Miesiace wczesniejsze nie maja
ewidencji rachunkow — nie dlatego, ze nic sie nie dzialo, tylko dlatego, ze nie
bylo czego zapisywac. Naiwne porownanie „wydano X z planu na 12 miesiecy"
pokazywaloby wykonanie planu w okolicach 15% i wygladalo jak sukces.

## Decyzja

### 1. Sekcja „Podsumowanie roczne" na zakladce „Plan"

Stoi tuz pod „Kosztami rocznymi" — ta sama skala i te same skladniki, raz jako
zalozenie, raz jako wykonanie. Naglowek: suma narastajaco, plan za objete
miesiace, procent i pasek. Po rozwinieciu 12 wierszy: miesiac · kwota miesiaca ·
narastajaco.

Sekcja NIE trafila do „Bilansu miesiaca", mimo ze tam padla prosba — zakladka
odpowiada na pytanie o jeden miesiac, a to jest pytanie o rok. Sasiedztwo
„Kosztow rocznych" niesie wiecej.

### 2. Przelacznik Plan / Realne jak przy wykresach (ADR-028)

- **Realne**: kwota miesiaca = koszty cykliczne z korektami + subskrypcje wtedy
  aktywne + rachunki tego miesiaca. Miesiace przyszle sa **puste, nie zerowe**.
- **Plan**: kazdy miesiac ta sama kwota planowana (koszty cykliczne +
  subskrypcje + koperta) — linia odniesienia, do ktorej porownuje sie wykonanie.

### 3. Poczatek ewidencji (`trackingStartMonth`, per zakres)

Ustawienie „od ktorego miesiaca dane sa kompletne". Miesiace przed nim sa puste
**po obu stronach**: nie licza sie do wykonania ANI do planu, z ktorym porownujemy.
Budzet prowadzony od lipca porownuje sie z planem na szesc miesiecy, nie na
dwanascie.

Ustawiane tapnieciem w podpis pod naglowkiem sekcji („od lipca" / „caly rok"),
osobno dla budzetu osobistego i domowego — moga zaczac sie w roznym czasie.
`null` = caly rok (budzet prowadzony od stycznia nie potrzebuje tego ustawienia).

### 4. „Uzupelnij do pelnej kwoty" w Plannerze

Obok „Dodaj pozycje do planu": liczy reszte brakujaca do okraglej kwoty i dopisuje
ja jako **zwykla pozycje koperty** o nazwie „Bufor" (ADR-012 mowi, ze bufor jest
zwykla pozycja — zadnego nowego pola).

- Baza: **Planner** (suma planu) albo **Wydatki** (wszystkie koszty miesieczne:
  cykliczne + subskrypcje + koperta, czyli to, co pomniejsza „zostaje/mies").
  Obie dzialaja ta sama pozycja, bo Planner jest czescia kosztow miesiecznych.
- Krok: 10 / 100 / 1000, zaokraglenie **w gore** (uzupelnianie w dol wymagaloby
  pozycji na minus).
- Liczone **w groszach** — `1296.56` w arytmetyce zmiennoprzecinkowej daje
  `3.4399999999999`.
- Istniejacy „Bufor" jest **podbijany**, a nie dublowany: po kilku uzyciach plan
  mialby inaczej piec pozycji o tej samej nazwie.
- Zatwierdzenie otwiera zwykly edytor pozycji z wpisana kwota — zapis idzie ta
  sama droga co kazda inna pozycja (nic nie omija synchronizacji ADR-022).

## Konsekwencje

- **Pozytywne:**
  - Widac, ile z rocznego planu juz poszlo i w ktorym miesiacu przyspieszylo.
  - Porownanie jest uczciwe takze przy budzecie zaczetym w polowie roku.
  - Domykanie planu do okraglej kwoty przestalo byc rachunkiem na kartce.
- **Negatywne / ryzyka:**
  - Miesiace wstecz dziedzicza ograniczenie z ADR-028: sa **odtwarzane**, nie
    zapisane. Bez korekt kwot pokaza dzisiejsze koszty stale.
  - Poczatek ewidencji trzeba ustawic recznie; domyslnie liczy sie caly rok.
  - Dopisany „Bufor" to **migawka, nie regula** — po zmianie ktoregokolwiek
    kosztu suma przestanie byc okragla. Celowo: plan jest podstawa „zostaje
    miesiecznie" i nie ma sie zmieniac sam z siebie.

## Rozwazane alternatywy

- **Pozycja domykajaca liczona na biezaco** (zawsze rowna reszcie do okraglej
  kwoty) — odrzucone: zmienialaby plan bez wiedzy uzytkownika.
- **Automatyczne wykrycie poczatku ewidencji** (pierwszy miesiac z danymi) —
  odrzucone jako domysl: jeden rachunek wpisany wstecz przestawilby caly rok.
- **Podsumowanie za ostatnie 12 miesiecy** zamiast roku kalendarzowego —
  odrzucone: plan roczny jest planem na rok, wiec porownanie broni sie tylko
  w tych samych granicach.
