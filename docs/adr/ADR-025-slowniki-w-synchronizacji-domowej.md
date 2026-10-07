# ADR-025: Slowniki (kategorie, metody platnosci) w synchronizacji domowej

Data: 2026-07-29
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — usunięte razem z synchronizacją

## Kontekst

Zgloszenie z uzycia: pozycje budzetu domowego synchronizuja sie miedzy telefonami
razem ze swoja kategoria i metoda platnosci, ale **same slowniki nie jada
w paczce**. Kategorie i metody zyja w osobnych boxach Hive, ktorych
synchronizacja (ADR-009) nigdy nie dotykala.

Skutek u drugiej osoby:

- **Kategoria** — pozycja wskazuje `categoryId`, ktorego nie ma w slowniku:
  `getCategory()` zwraca null, wiec znika kropka koloru i nazwa, a pozycja
  wpada do „Inne" w podziale wg kategorii.
- **Metoda platnosci** — pozycja niesie NAZWE metody; brak wpisu o tej nazwie
  oznacza brak `isAutomatic`, wiec platnosc automatyczna **udaje manualna**:
  laduje na liscie „Platnosci" do odhaczenia i zmienia kolor na kalendarzu.

Domyslne slowniki maja u obu osob te same `id` (wspolny seed), wiec problem
dotyczy wylacznie wpisow dodanych recznie.

Komplikacja: **slowniki sa wspoldzielone** miedzy budzetem osobistym, domowym
i subskrypcjami. Naiwne „synchronizujmy caly slownik" wysylaloby drugiej osobie
takze kategorie uzywane wylacznie w prywatnym budzecie.

## Decyzja

Slowniki jada w paczce jako **sekcja opcjonalna przy tej samej wersji paczki**
(`dictionaries`), tak jak Planner w ADR-022 — starsza aplikacja ignoruje
nieznane pole i synchronizacja nie przestaje dzialac, gdy telefony aktualizuja
sie w roznym czasie.

1. **Tylko to, czego uzywa budzet domowy.** Przy kazdym push wyznaczamy
   podzbior: kategorie wskazane przez pozycje domowe i Planner domowy oraz
   metody platnosci o nazwach wystepujacych w tych pozycjach. Kategoria widoczna
   wylacznie w budzecie osobistym albo w subskrypcjach nie opuszcza telefonu.
2. **Scalanie „ostatnia zmiana wygrywa"** po nowym polu `updatedAt`
   w `Category` i `PaymentMethod`. Pole jest nullowalne (`DateTime` nie moze byc
   `const`, a domyslne wpisy sa stalymi); brak = epoka zero, czyli przegrywa
   z kazda realna zmiana. Remis rozstrzyga deterministyczny tie-break po tresci.
3. **Brak usuwania zdalnego.** Slowniki tylko dochodza i aktualizuja sie. Wpis
   nieobecny po drugiej stronie ZOSTAJE — kasowanie zabieraloby drugiej osobie
   kategorie takze z jej prywatnych pozycji i subskrypcji. Usuwanie pozostaje
   operacja lokalna.
4. **Metody platnosci dopasowywane po NAZWIE**, bo tak wskazuja je pozycje.
   Ta sama metoda utworzona niezaleznie na obu telefonach (rozne `id`) scala sie
   w jeden wpis; zachowywane jest `id` lokalne, tresc wygrywa nowsza.
5. **Kategorie o tej samej nazwie sa kanonizowane.** Kanoniczne jest **mniejsze
   `id` leksykograficznie** — wybor nie zalezy od tego, ktory telefon liczy,
   wiec oba dochodza do tego samego wyniku. Pozycje domowe i Planner sa
   przepinane na kanoniczne `id` bez ruszania ich znacznika zmiany (kanonizacja
   jest deterministyczna i idempotentna). Duplikat w slowniku zostaje —
   przestaje byc uzywany i widac go w Ustawieniach z zerowym licznikiem.

## Konsekwencje

- **Pozytywne:**
  - Pozycja domowa u drugiej osoby ma swoja kategorie (kolor, nazwa, podzial
    na kategorie) i swoj tryb platnosci — koniec „automatyczna udaje manualna".
  - Prywatne kategorie budzetu osobistego nie opuszczaja telefonu.
  - Nic nie znika drugiej osobie bez jej wiedzy: slowniki tylko rosna.
  - Kompatybilnosc w obie strony — telefon ze starsza aplikacja dalej
    synchronizuje pozycje, tylko bez slownikow.
- **Negatywne / ryzyka:**
  - Kategoria przestaje jechac, gdy zadna pozycja domowa jej nie uzywa. Jesli
    druga osoba w miedzyczasie jej nie dostala, zobaczy „Inne" do czasu, az
    ktoras pozycja znow ja wskaze.
  - Po kanonizacji w Ustawieniach moze zostac nieuzywany duplikat kategorii
    — do recznego sprzatniecia (kaskada zmiany nazwy i usuwania juz dziala).
  - Kanonizacja przepina takze pozycje domowe wskazujace duplikat — zmiana
    jest widoczna jako jednorazowy push po pierwszej synchronizacji.
  - Slownik metod platnosci scala sie po nazwie, wiec dwie ROZNE metody
    nazwane identycznie na obu telefonach zostana uznane za te sama.

## Rozwazane alternatywy

- **Synchronizowac cale slowniki** — odrzucone: nazwy kategorii z budzetu
  osobistego trafialyby na drugi telefon.
- **Nagrobki dla slownikow (propagacja usuniecia)** — odrzucone: skasowanie
  kategorii u jednej osoby zabieraloby ja z pozycji osobistych i subskrypcji
  drugiej.
- **Denormalizacja (pozycja niesie nazwe i kolor kategorii)** — odrzucona:
  dublowalaby dane w kazdej pozycji, a zmiana nazwy kategorii przestalaby sie
  propagowac.
- **Kanonizacja przez „kazdy przepina na swoje id"** — odrzucona: telefony
  przestawialyby te same pozycje w kolko przy kazdej synchronizacji.
