# ADR-027: Subskrypcje jako sekcja „Wydatkow", nie osobna zakladka

Data: 2026-08-01
Status: częściowo zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — subskrypcje są sekcją planu, wciętą pod wydatkami
> **Powiazane:** [ADR-019 Podzial sekcji aplikacji](ADR-019-podzial-sekcji-aplikacji.md)
> | [ADR-023 Rozlaczne strumienie wydatkow](ADR-023-rozlaczne-strumienie-wydatkow.md)
> | [ADR-026 Gestosc interfejsu](ADR-026-gestosc-interfejsu-bez-paskow-tytulu.md)

## Kontekst

Aplikacja zaczela jako tracker subskrypcji i subskrypcje dostaly wlasna zakladke
w nawigacji. Od tego czasu urosla do menedzera budzetu domowego i ta zakladka
przestala pasowac do reszty:

- **Zakladka miala juz tylko liste.** Statystyki subskrypcji przeniosly sie do
  zakladki „Budzet" (segment „Plan"), wiec zostal sam spis pozycji — dokladnie
  to, co robi ekran „Wydatki" dla kosztow stalych, rat i przelewu wewnetrznego.
- **Subskrypcja to koszt cykliczny.** W planie liczy sie tak samo jak koszt
  staly (kwota × liczba platnosci ÷ 12) i wchodzi do tego samego salda. Osobna
  zakladka sugerowala osobny rodzaj pieniedzy.
- **Dwa style listy.** Subskrypcje mialy wlasna karte (`SubscriptionCard`),
  reszta aplikacji — dwuliniowy wiersz z separatorem (ADR-026). Byla to otwarta
  kwestia z poprzedniej sesji.
- **Szesc zakladek** to duzo jak na pigulke nawigacji telefonu.

## Decyzja

### 1. Subskrypcje sa trzecia sekcja ekranu „Wydatki"

Kolejnosc sekcji: **Przelew wewnetrzny · Wydatki stale · Subskrypcje**.
Zakladka „Subskrypcje" znika z nawigacji (szesc pozycji → piec).

### 2. To przeniesienie WIDOKU, nie migracja danych

`Subscription` zostaje osobnym modelem i osobnym pudelkiem Hive, z wlasnym
formularzem, cyklami, okresami probnymi, limitem, eksportem Excel i miejscem
w kopii zapasowej. Zamiana subskrypcji na `BudgetEntry` ruszylaby naraz
synchronizacje domowa (ADR-009/025), format kopii, Excel i powiadomienia —
na budzecie, ktory jest w realnym uzyciu. Efekt na ekranie jest ten sam, a
ryzyko nieporownywalne.

### 3. Filtry ekranu obejmuja subskrypcje

- **Typ:** chip „Subskrypcje" jako **pseudo-typ** obok typow pozycji budzetu
  (subskrypcja nie jest `BudgetEntryType`, ale na tej liscie zachowuje sie jak
  trzeci typ wydatku). Wybor jednego chipa zdejmuje drugi.
- **Kategoria:** slownik jest wspolny, wiec jeden filtr zawezaja obie listy.
- **Czas:** subskrypcji nie dotyczy — sa cykliczne, czyli naleza do kazdego
  miesiaca, tak samo jak koszty stale.
- Reguly widocznosci siedza w `ExpensesFilter` (poza widgetem), zeby dalo sie je
  sprawdzic testem, a nie tylko klikaniem.

### 4. „Pokaz ukryte" dziala na caly ekran i stoi przy filtrze czasu

Jeden przelacznik chowa i odslania **wszystko, czego plan nie liczy**:
wstrzymane pozycje budzetu i anulowane subskrypcje. Dwa rozne zachowania w
jednej liscie (subskrypcje chowane, pozycje wyszarzone) byly nie do wytlumaczenia.
Miejsce: koniec paska filtra czasu — oba przelaczniki decyduja o tym, CO jest na
liscie (sortowanie i grupowanie, ktore decyduja o UKLADZIE, zostaja przy swoich
paskach, ADR-026).

Konsekwencja liczbowa: **suma w naglowku sekcji liczy tylko aktywne pozycje**.
Wczesniej wstrzymana pozycja podbijala sume sekcji, choc do planu nie wchodzila.

### 5. Sekcje sa zwijane tapnieciem w naglowek

Suma sekcji zostaje widoczna po zwinieciu — po to sie ja zwija. Stan jest trwaly
(jak Planner w „Rachunkach") i trzymany jako **lista kluczy sekcji** w
ustawieniach, a nie flaga na sekcje: sekcji przybywa.

### 6. Jeden styl wiersza (zamkniecie otwartej kwestii z ADR-026)

`SubscriptionCard` (ramka, tlo, kropka statusu) znika na rzecz `SubscriptionRow`
w ukladzie `BudgetEntryCard`. Informacje z karty zeszly do drugiej linii:

```
{ikona kategorii}  {nazwa}                                  {kwota}/{cykl}
                   Subskrypcja · {data} · {okres probny} · {metoda} · {kategoria}
```

Przypiete subskrypcje zostaja na gorze swojej sekcji niezaleznie od sortowania.

## Konsekwencje

- **Pozytywne:**
  - Wszystkie koszty cykliczne sa na jednym ekranie i w jednym stylu — widac
    calosc, a nie trzy widoki tych samych pieniedzy.
  - Piec zakladek zamiast szesciu; nawigacja mniej zatloczona.
  - Zwijane sekcje daja przeglad „same sumy" bez przewijania kilkudziesieciu
    pozycji.
  - Znika drugi styl listy i drugi ekran z wlasnymi filtrami do utrzymania.
- **Negatywne / ryzyka:**
  - Ekran „Wydatki" jest najgestszy w aplikacji: do trzech paskow filtrow nad
    trzema sekcjami.
  - Subskrypcje sa o jedno tapniecie dalej (zakladka „Wydatki" + chip typu albo
    przewiniecie).
  - Wstrzymane pozycje budzetu sa domyslnie schowane — wczesniej byly widoczne
    (wyszarzone). Odslania je przelacznik przy filtrze czasu.
  - Dodawanie subskrypcji i import z Excela mieszkaja teraz w menu „Dodaj"
    ekranu „Wydatki", ktore ma tam do pieciu pozycji.

## Rozwazane alternatywy

- **Migracja subskrypcji do `BudgetEntry`** — odrzucone: jedna zmiana dotknelaby
  synchronizacji, kopii, Excela, powiadomien i okresow probnych naraz, a
  uzytkownik zobaczylby dokladnie to samo co przy przeniesieniu widoku.
- **Zostawic zakladke i dodac sekcje w Wydatkach** — odrzucone: dwa miejsca na
  te sama liste, ktore trzeba utrzymywac zgodne.
- **Przelacznik ukrytych osobno dla subskrypcji** — odrzucone: na wspolnej
  liscie ten sam przycisk musi znaczyc to samo dla obu rodzajow pozycji.
- **Zwijanie bez stanu trwalego** — odrzucone: sekcja rozwijalaby sie sama przy
  kazdym wejsciu, wiec zwijanie nie oszczedzaloby niczego poza jednym spojrzeniem.
