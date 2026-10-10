# ADR-036: Pożyczki ratalne obok pożyczek z karty

Data: 2026-10-09
Status: zaakceptowany

> **Powiązane:** [ADR-035 Plan roczny](ADR-035-plan-roczny-pozycje-z-miesiacami.md)
> (§4 karta kredytowa, §5a okres pozycji)

## Kontekst

Raty (telefon, odkurzacz) były zwykłymi pozycjami planu — wydatkiem co
miesiąc, z okresem od pierwszej do ostatniej raty. Plan nie wiedział, ile
pożyczka wypłaciła, ile kosztuje ani jakie ma RRSO, a zakup finansowany
ratami nie miał gdzie się pojawić: dopisany jako wydatek liczyłby się drugi
raz obok rat.

Pożyczka z karty (ADR-035 §4) działała dobrze: para „wpływ w dniu użycia —
spłata po okresie bezodsetkowym", liczona osobno od wpływów i wydatków.

## Decyzja

### 1. Pożyczka ratalna to ta sama para co karta, z warunkami

- **Wpływ** w dniu wypłaty (kwota wypłacona) i **spłata** — raty w kolejnych
  miesiącach — spięte wspólnym `linkId`, jak para karty.
- **Warunki** (kwota, liczba rat, rata, RRSO, data wypłaty, pierwsza rata,
  dzień raty) zapisane przy ratach (`loanTerms`, klucz `loan`). Raty w planie
  powstają z warunków; zmiana warunków przelicza raty (ręcznie poprawione raty
  — po pytaniu).
- Raty dostają **okres** od pierwszej do ostatniej raty (ADR-035 §5a), więc
  ekran pozycji wyszarza miesiące przed i po.
- W kodzie rodzaje nazywają się teraz `loan` / `loanRepayment`; **w zapisie
  zostają** „cardLoan" / „cardRepayment". Istniejące pożyczki z karty i kopie
  działają bez zmian, a wersja sprzed tej decyzji widzi pożyczkę ratalną jak
  pożyczkę z karty z wieloma spłatami.

### 2. Raty w „Pożyczkach", zakup w „Wydatkach"

- Opcjonalny **zakup tego dnia** (domyślnie zaznaczony, kwota = kwota
  pożyczki, do zmiany) to zwykły wydatek z kategorią, spięty z pożyczką
  `linkId`. Raty liczą się w „Pożyczkach netto", nie w Wydatkach — inaczej ten
  sam koszt liczyłby się dwa razy.
- Skutek dla liczb: kategoria zakupu dostaje całą kwotę w miesiącu zakupu
  (nie ratę co miesiąc); „Zostaje" w miesiącu wypłaty się nie zmienia (wpływ
  i zakup się znoszą), w kolejnych miesiącach raty obniżają je jako
  „Pożyczki netto".
- Usunięcie zakupu nie kasuje pożyczki; usunięcie pożyczki pyta o zakup
  (zostaje jako zwykły wydatek bez powiązania albo znika). Zakup nie jest
  kandydatem do „Zaplanuj kolejny rok".
- **Przejście w obie strony** (2026-10-10): w formularzu pożyczki zakup
  dodaje przycisk „Dodaj" (pola kwoty i kategorii, zakup powstaje przy
  zapisie — już nie domyślnie zaznaczony checkbox), a istniejący pokazuje się
  z kwotą i przyciskiem „Pokaż" → ekran zakupu. Na ekranie zakupu „Otwórz
  pożyczkę" (albo „Wróć do pożyczki", gdy przyszło się z niej). Istniejący
  zakup to osobna pozycja: zapis pożyczki go nie nadpisuje ani nie usuwa —
  tylko przesuwa za nową datą wypłaty, gdy stał w dniu wypłaty.

### 3. Trzy z czterech — reszta się liczy

Kwota, liczba rat, rata i RRSO: z dowolnych trzech formularz liczy czwartą
(rata stała). Przy czterech sprawdza zgodność — tolerancja 5 gr na racie —
i podpowiada „przyjmij ratę" albo „przyjmij RRSO z rat". RRSO liczone z
przepływów jak w ustawie o kredycie konsumenckim: wypłata dziś = suma rat
zdyskontowanych stopą RRSO po czasie od wypłaty (rok = 365 dni). Koszty
doliczone do rat są w wyniku, koszty płacone osobno — nie, stąd możliwa
różnica z RRSO z umowy (zapis z różnicą jest dozwolony po potwierdzeniu).
Przy 0% ostatnia rata wyrównuje grosze zaokrągleń.

### 4. Sekcja „Pożyczki"

„Karta kredytowa" w Planowaniu staje się „Pożyczkami" — karta i raty razem;
„Karta netto" staje się „Pożyczkami netto" (podsumowanie i statystyki). Karta
raty pokazuje ratę i RRSO, pasek spłaty, ratę miesiąca („rata 3 z 12") lub
wypłatę, ile zostało i koszt.

Gotowe ustawienie „Raty…" w formularzu zwykłej pozycji znika — myliło
z pożyczką ratalną; w jego miejscu odesłanie do „Dodaj → Pożyczka ratalna".
Istniejące raty-pozycje właściciel zastępuje ręcznie (nowa pożyczka, stara
pozycja usunięta) — bez automatycznej zamiany, bo aplikacja nie zna kwoty
wypłaty.

## Konsekwencje

- **Pozytywne:** raty mają kwotę, koszt i RRSO; zakup ma kategorię i miesiąc;
  pomyłka w racie albo RRSO wychodzi od razu; karta i raty w jednym miejscu.
- **Negatywne / ryzyka:** statystyki kategorii pokazują zakup w jednym
  miesiącu zamiast rat rozłożonych w czasie — świadomie (to moment wydatku);
  RRSO może różnić się od umowy o koszty spoza rat.
- **Poza zakresem:** oprocentowanie zmienne, raty malejące, nadpłaty.

## Rozważane alternatywy

- **Raty dalej jako pozycje, tylko kalkulator raty i RRSO** — odrzucona: bez
  wypłaty i zakupu plan nie pokazuje pożyczki, a raty zostają w Wydatkach.
- **Osobny moduł pożyczek** (jak subskrypcje) — odrzucona: dublowałby
  kalendarz, sumy, Excel i kopię zapasową, które pozycje planu już mają.
- **Automatyczna zamiana istniejących rat** — odrzucona przez właściciela.
