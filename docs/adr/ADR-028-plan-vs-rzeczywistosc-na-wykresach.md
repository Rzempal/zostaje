# ADR-028: Plan vs rzeczywistosc na wykresach zakladki „Plan"

Data: 2026-08-01
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — statystyki pokazują wyłącznie plan

> **Powiazane:** [ADR-008 Rachunek zmienny: surplus vs bilans](ADR-008-rachunek-zmienny-surplus-vs-bilans.md)
> | [ADR-011 Rachunki (realny log)](ADR-011-rachunki-realny-log-i-scalenie-typow-cyklicznych.md)
> | [ADR-023 Rozlaczne strumienie wydatkow](ADR-023-rozlaczne-strumienie-wydatkow.md)

## Kontekst

Zakladka „Plan" ma dwa wykresy calosci wydatkow: trend 6 miesiecy (trzy rozlaczne
serie) i podzial na kategorie. Oba byly **mieszanka planu i rzeczywistosci**, przy
czym nigdzie tego nie bylo widac:

| Element | Co pokazywal |
|---|---|
| Trend, seria „Cykliczne" | **plan** — dzisiejsza kwota rzutowana wstecz na wszystkie miesiace |
| Trend, seria „Subskrypcje" | **rzeczywistosc** — z dat startu i anulowania |
| Trend, seria „Rachunki" | **rzeczywistosc** — realne rachunki kazdego miesiaca |
| Podzial na kategorie | cykliczne i subskrypcje usrednione (**plan**) + rachunki wybranego miesiaca (**rzeczywistosc**) |

Suma takiego wykresu nie odpowiadala ani planowi („zostaje miesiecznie"), ani
zadnemu realnemu miesiacowi (bilans miesiaca). Aplikacja ma juz oba te ujecia
policzone osobno (ADR-008) — brakowalo ich na wykresach.

## Decyzja

### 1. Jedno pojecie: `ExpenseView` (plan / actual)

**Plan** — jak budzet zaklada, ze wyglada miesiac:
- koszty cykliczne: kwota bazowa/mies, **bez korekt miesiecznych**
- subskrypcje: dzisiejszy koszt/mies, plasko na calym wykresie
- rachunki: **koperta „Na rachunki"** (rezerwa), nie realne platnosci
- w podziale na kategorie koperta rozbija sie po kategoriach swoich pozycji

**Rzeczywistosc** — co faktycznie wyszlo w danym miesiacu:
- koszty cykliczne: kwoty z korektami tego miesiaca, tylko pozycje, ktore wtedy
  istnialy (raty w oknie splaty, koszty stale od swojej daty startu)
- subskrypcje: historycznie (jak dotad)
- rachunki: realne `billPayment` tego miesiaca

**Inwariant:** rzeczywistosc biezacego miesiaca liczy sie **tak samo jak
`monthBalanceParts`** (Bilans miesiaca) — jest na to test. Inaczej wykres i bilans
pokazywalyby dwie rozne prawdy o tym samym miesiacu.

### 2. Dwa niezalezne przelaczniki, nie jeden wspolny

Kazdy z wykresow ma wlasny przelacznik („Plan" / „Realne") w swoim naglowku, ze
stanem trwalym. Osobne, bo te widoki sluza do POROWNANIA: wspolny przelacznik
odbieralby mozliwosc zestawienia planowego trendu z realnym podzialem. Domyslnie
**Plan** — tak nazywa sie zakladka, rzeczywistosc jest doczytaniem.

W ujeciu realnym podzial na kategorie dopisuje do tytulu **miesiac**, bo dotyczy
konkretnego miesiaca (tego z karty predykcji), a nie sredniej.

### 3. Historia jest ODTWARZANA, nie zapisana

Aplikacja nie trzyma migawek kosztow z przeszlosci — ma tylko korekty miesieczne
(`monthOverrides`) i daty (`startDate`, okna rat). Dlatego:

- biezacy miesiac w ujeciu realnym jest **dokladny**,
- miesiace wstecz sa **odtworzeniem**: koszt bez zapisanej korekty pokaze
  dzisiejsza kwote,
- pozycja bez daty startu liczy sie na calym wykresie (brak daty = brak
  informacji; alternatywa — ciche zerowanie starszych miesiecy — myli bardziej).

Trend w ujeciu „Plan" jest z natury plaski (rusza sie tylko przy ratach wchodzacych
i wychodzacych z okna splaty). To poprawne: plan nie zmienia sie z miesiaca na
miesiac, a ruch widac dopiero w „Realne".

## Uzupelnienie (2026-08-01): tryb „Oba" i poczatek ewidencji na trendzie

Dwa braki wyszly przy pierwszym uzyciu.

**1. Trend zaczyna sie od poczatku ewidencji** (`trackingStartMonth`, ADR-029).
Wczesniej wykres rysowal szesc miesiecy niezaleznie od tego, czy bylo wtedy co
zapisywac — cztery pierwsze punkty pochodzily z odtworzenia dzisiejszych kwot.
Teraz os po prostu zaczyna sie od miesiaca startu (przy starcie w lipcu wykres
ma dwa punkty). Krotszy wykres mowi prawde, dluzszy sciemnia. Wszystkie serie
skracaja sie razem, wiec nic sie nie rozjezdza.

Odrzucone: dziura w linii (puste punkty przed startem) — wymagaloby dopuszczenia
`null` w calym lancuchu danych, gdzie kwota jest dzis zawsze liczba, i mnozylo
miejsca, w ktorych „brak danych" moze sie wyswietlic jako zero.

**2. Trzeci tryb: „Oba"** — dwie linie zbiorcze (realne ciagla, plan przerywana),
na ktorych widac odchylenie. NIE trzy strumienie razy dwa ujecia: szesc linii na
200 px to platanina, a pytanie brzmi „ile odbiegamy od planu", nie „ktory strumien
o ile". Chipy legendy zostaja, wiec kazda linie mozna wylaczyc.

Podzial na kategorie zostaje przy dwoch ujeciach — wykres kolowy laczacy plan
z rzeczywistoscia nie mialby sensu.

**3. Naglowki grup: „Miesiac" i „Statystyki".** Zakladka „Plan" dzieli sie
wedlug tego, CZEGO dotycza liczby, a **kazdy okres ma sterowanie w naglowku
swojej grupy** — nie w srodku jednej z kart, ktore rzadzi takze sasiadka:

| Grupa | Karty | Sterowanie |
|---|---|---|
| (bez naglowka) plan | Saldo, Koszty roczne | brak — to zalozenie |
| **Miesiac** | Plan vs Realne, Kategorie | strzalki + wybor miesiaca |
| **Statystyki** | Trend, Podsumowanie roczne | punkt startu ewidencji |

Karta „Plan vs Realne" stracila wlasne strzalki, a „Podsumowanie roczne" wlasny
wybor startu — obie kontrolki zyja teraz w naglowkach.

Punkt startu (`trackingStartMonth`, ADR-029) siedzial wczesniej w srodku karty
„Podsumowanie roczne", choc ucina takze trend — dwa widoki, jedno ustawienie,
wiec jego miejsce jest w naglowku sekcji. Wybor idzie oknem wyboru miesiaca:
to ustawienie zmienia sie raz na jakis czas, a nie krok po kroku.

Karta „Plan vs Realne" zostaje NAD kreska ze swoimi strzalkami — dotyczy jednego
miesiaca, a nie okresu, od ktorego licza sie statystyki.

## Konsekwencje

- **Pozytywne:**
  - Suma kazdego wykresu ma teraz jedno znaczenie i zgadza sie z karta „Saldo"
    (plan) albo z „Bilansem miesiaca" (realne).
  - Koperta „Na rachunki" pojawia sie wreszcie na wykresach — wczesniej pomniejszala
    plan, ale nie bylo jej widac w zadnym rozbiciu.
  - Roznica plan vs realny jest widoczna na wykresie, a nie tylko w jednej liczbie
    na karcie predykcji.
- **Negatywne / ryzyka:**
  - Realne miesiace wstecz sa tym dokladniejsze, im czesciej uzywa sie korekt kwot;
    bez nich wygladaja jak plan.
  - Dwa przelaczniki to dwa stany do zapamietania przez uzytkownika (i dwa klucze
    ustawien).
  - Subskrypcje w podziale na kategorie sa liczone biezaco takze w ujeciu realnym
    (rozbicia historycznego per kategoria nie mamy).

## Rozwazane alternatywy

- **Zapisywac miesieczne migawki kosztow** — dalaby prawdziwa historie, ale to nowy
  zbior danych do kopii zapasowej i synchronizacji; do rozwazenia, jesli odtwarzanie
  okaze sie w praktyce mylace.
- **Jeden wspolny przelacznik dla obu wykresow** — odrzucone: oba widoki sluza do
  porownywania.
- **Zostawic hybryde i tylko ja opisac** — odrzucone: opis nie naprawia liczby,
  ktora nie odpowiada na zadne pytanie.
