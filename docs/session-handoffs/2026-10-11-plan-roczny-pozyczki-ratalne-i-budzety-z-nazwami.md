# Session Handoff — plan roczny, pozyczki ratalne i budzety z nazwami

Data: 2026-10-11 (sesja 2026-10-06 – 2026-10-11)
Commit: Plan roczny, pozyczki ratalne i budzety z nazwami - handoff sesji i dokumentacja

## Kontekst

Wlasciciel (jedyny uzytkownik) zdecydowal o calkowitej przebudowie, zeby uproscic
aplikacje: budzet z kwot bazowych z cyklami, korekt miesiecy i porownania planu
z rzeczywistoscia przeszedl na **plan roczny jak arkusz** (pozycje × miesiace).
Na tym fundamencie doszly pozyczki ratalne, budzety z nazwami, osobne slowniki
dla budzetow i dzien dopracowania ekranow. Wszystko jest na PROD.

## Co zrobiono

- **Faza 16 — przebudowa na plan roczny** ([ADR-035](../adr/ADR-035-plan-roczny-pozycje-z-miesiacami.md)),
  etapy E0–E8:
  - wydanie DEV z galezi roboczej; `ship.ps1` odroznia „GitHub nieosiagalny"
    od „release nieopublikowany" (3 proby);
  - model `PlanPosition` (miesiace „RRRR-MM → kwota + dzien") i konwersja
    starych danych — stare pozycje nietkniete, raport zgodnosci w Developer Tools;
  - zakladki: **Budzet** (Statystyki roku + Kalendarz platnosci do odhaczania)
    | **Planowanie** | Ustawienia;
  - usuniete: Biezace, Planner, skan paragonow z lokalnym AI, synchronizacja
    domowa, przelewy miedzy budzetami, plan vs rzeczywistosc (APK 44,7 → 32 MB,
    dzis ok. 26 MB);
  - kopia zapasowa v8, Excel jako tabela roku (arkusz na rok, wydatki ujemne);
  - ekran pozycji: siatka 3×4, szybkie wypelnianie, okres od–do z wyszarzeniem;
  - PROD 0.27 (2026-10-08); punkt powrotu `v0.26.26100600`.
- **Faza 17 — pozyczki ratalne** ([ADR-036](../adr/ADR-036-pozyczki-ratalne.md)):
  sekcja Pozyczki (karta + raty), raty z RRSO (trzy wartosci licza czwarta,
  cztery — sprawdzanie zgodnosci), zakup tego dnia jako wydatek; przycisk
  „Dodaj" / „Pokaz" i przejscie zakup ↔ pozyczka w obie strony.
- **Faza 18 — budzety z nazwami i ikonami** ([ADR-037](../adr/ADR-037-budzety-z-nazwami.md)):
  lista budzetow, przelacznik z lista rozwijana, ukrywanie zamiast „trybu
  budzetu", przenies / kopiuj / duplikuj (pozycje, pozyczki, subskrypcje,
  caly budzet).
- **Faza 19 — kategorie i metody platnosci osobne dla budzetow**
  ([ADR-038](../adr/ADR-038-kategorie-i-metody-osobne-dla-budzetow.md)): podzial
  danych przy starcie (`StorageService.ensureDictionaries`), kopia v9, okno
  „Dodaj je / Bez nich" przy przenoszeniu, nowy budzet z pustymi listami;
  kolka zaznaczania w siatce miesiecy.
- **Faza 20 — dopracowanie Planowania i Budzetu** (2026-10-10):
  - „Dzisiaj" i przelacznik „Rok / Miesiac" w rogu (rok = sumy roczne),
    start na biezacym miesiacu;
  - pigulki „Razem" i czesci w grupach Wydatki i Pozyczki, filtry kategorii
    w grupie Wydatki;
  - kategorie zawsze alfabetycznie po polsku (`plSortKey`), budzet pozycji
    na ekranie pozycji;
  - przelacznik „Statystyki / Kalendarz" w stylu „Rok / Miesiac"
    (`AuroraSegmented` compact);
  - subskrypcje w ukladzie wiersza pozycji z paskiem miesiecy
    (`PlanMonthStrip`);
  - strzalka w podpisach pozyczek jako ikona (`planArrowSpan`) — znaku „→"
    nie ma w foncie telefonu.
- **Testy:** 304 przypadki (mniej niz przed przebudowa — usuniete moduly
  zabraly swoje testy); nowe m.in. `loan_math_test`, `budgets_test`,
  `dictionaries_by_budget_test`, `plan_group_test`, `text_sort_test`.
- **Dokumentacja:** ADR-035–038, statusy zastapionych ADR, `architecture.md`,
  `database.md`, `roadmap.md` (Fazy 16–20), `deployment.md`, `security.md`,
  `design.md`, README, dwa wpisy w `lessons-learned.md`.
- **Wydania:** PROD od 0.27 do 0.27.26101007, DEV do 0.27.26101011.

## Decyzje

- **Plan roczny zamiast cykli i korekt**; kwota zyje tylko w miesiacach,
  pozycja nie jest przypieta do roku — [ADR-035](../adr/ADR-035-plan-roczny-pozycje-z-miesiacami.md).
  Zmiana 2026-10-10: widok roczny Planowania pokazuje sumy, srednie zostaja
  w Statystykach.
- **Usuniecie funkcji bez wstecznej zgodnosci** — jedyny uzytkownik, warunek:
  nie stracic pozycji; stare dane leza nietkniete w bazie (ADR-035).
- **Pozyczka ratalna = para jak karta + warunki**; raty w „Pozyczkach netto",
  zakup w Wydatkach, zeby koszt nie liczyl sie dwa razy — [ADR-036](../adr/ADR-036-pozyczki-ratalne.md).
- **Budzety oddzielne, bez widoku „wszystkie"; ukrywanie zamiast trybu** —
  [ADR-037](../adr/ADR-037-budzety-z-nazwami.md).
- **Slowniki osobne dla budzetow**; nieuzywane wpisy → osobisty, etykiety przy
  przenoszeniu ida po nazwie — [ADR-038](../adr/ADR-038-kategorie-i-metody-osobne-dla-budzetow.md).
- **Kategorie bez recznej kolejnosci** (zawsze alfabetycznie); metody platnosci
  zachowuja reczna kolejnosc.
- **Znak spoza fontu → ikona** (strzalka w podpisach) — regula w `design.md`
  (Typografia); bez ADR, decyzja na poziomie wygladu.

## Otwarte kwestie

- **E7: sprzatanie Supabase** — gotowe polecenie SQL w tabeli Fazy 16
  (`roadmap.md`); uruchamia wlasciciel w projekcie „karton" (wspolny
  z APPteczka). Obiekty niczego nie psuja — aplikacja sie z nimi nie laczy.
- **Pozostale „→" w menu i podpowiedziach** („Sortuj: A→Z", „Ustawienia →
  Metody platnosci", raport konwersji) — roadmapa, pkt 11.
- **Propozycje bez decyzji wlasciciela:** linia z budzetem na ekranach edycji
  subskrypcji i pozyczki (jak na ekranie pozycji); metody platnosci
  alfabetycznie (dzis reczna kolejnosc).
- **`design.md`, sekcja „Makiety ekranow (Aurora)"** — w duzej czesci
  sprzed przebudowy (listy Wydatki/Wplywy, realny bilans miesiaca); do
  przegladu, np. audytem dokumentacji.
- Dalsze kroki z roadmapy: powiadomienia planu, odnowienia subskrypcji
  w kalendarzu systemowym, zaznaczanie wielu subskrypcji, Material You i pasek
  stanu, wiersz 48 px, onboarding, strona aplikacji, Google Play (ADR-031).
- Sesja 2026-08-22–23 (odczyt potwierdzen z portfela) nie ma handoffu —
  funkcja odpadla w przebudowie (E3b).
