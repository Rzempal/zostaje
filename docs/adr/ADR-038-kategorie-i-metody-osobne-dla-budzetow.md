# ADR-038: Kategorie i metody płatności osobne dla budżetów

Data: 2026-10-10
Status: zaakceptowany

> **Powiązane:** [ADR-037 Budżety z nazwami](ADR-037-budzety-z-nazwami.md)
> (przenoszenie i kopiowanie między budżetami) | [ADR-035 Plan roczny](ADR-035-plan-roczny-pozycje-z-miesiacami.md)

## Kontekst

Budżety są osobne (ADR-037), ale kategorie i metody płatności były jedną
wspólną listą. Przy budżecie osobistym i firmowym to przeszkadza: nie wolno
mieszać kont ani celów, a formularze pokazywały wszystkie kategorie i metody
naraz — długą listę, w której pozycje różnych budżetów się mieszały.

## Decyzja

1. **Każdy budżet ma własne kategorie i metody płatności** (`budgetId`
   w kategorii i metodzie). Ta sama nazwa w dwóch budżetach to dwa niezależne
   wpisy: zmiana nazwy, koloru czy ikony w jednym nie rusza drugiego.
   Formularze, filtr kategorii, zmiana kategorii lub metody dla zaznaczonych,
   statystyki i kalendarz (tryb automatyczny metody) biorą listę swojego
   budżetu.
2. **Podział istniejących danych** (raz, przy starcie i po wczytaniu starszej
   kopii): wpis używany w kilku budżetach trafia do każdego z nich — pierwszy
   (osobisty) zachowuje identyfikator, pozostałe dostają kopie, a pozycje
   i subskrypcje wskazują kopię ze swojego budżetu. **Nieużywany nigdzie —
   do budżetu osobistego.** Gdy budżet ma już wpis o tej nazwie, drugi nie
   powstaje. Pozycja z etykietą innego budżetu (np. ze starej kopii) dostaje
   odpowiednik ze swojego.
3. **Nowy budżet startuje z pustymi listami.** Pusta lista podpowiada
   „Skopiuj z innego budżetu…"; szablony subskrypcji (np. Netflix → Streaming)
   używają kategorii tylko wtedy, gdy budżet ją ma — niczego same nie dodają.
4. **Ekrany Kategorie i Metody płatności** pokazują listę wybranego budżetu
   (przełącznik nad listą). W menu ⋮ wpisu: „Kopiuj do budżetu…" (niezależna
   kopia; tej samej nazwy nie dubluje), „Przenieś do budżetu…" (kopia tam,
   usunięcie tutaj — pozycje tego budżetu zostają bez niej, z ostrzeżeniem)
   i „Usuń". W menu ekranu: „Kopiuj wszystkie do budżetu…". Kategorie
   zawsze alfabetycznie (po polsku: ą po a, ś po s), bez ręcznej kolejności
   (2026-10-10) — także w formularzach, filtrze i podgrupach Planowania.
5. **Przenoszenie i kopiowanie pozycji, pożyczek, subskrypcji i całych
   budżetów** (ADR-037): etykiety idą po nazwie. Gdy budżetowi docelowemu
   czegoś brakuje, okno pyta: „Dodaj je" albo „Bez nich" (pozycje bez
   kategorii i metody).
6. **Usunięcie kategorii** — jej pozycje przechodzą do „Inne" tego samego
   budżetu, a gdy jej nie ma, zostają bez kategorii. Usunięcie budżetu zabiera
   jego kategorie i metody.
7. **Kopia zapasowa v9** — wszystkie kategorie (także domyślne) i metody
   z budżetami; odtworzenie zastępuje obie listy. Starsza kopia — podział jak
   w pkt 2. Starsza aplikacja odrzuca v9, zanim cokolwiek skasuje.

## Konsekwencje

- **Pozytywne:** budżet firmowy nie widzi kont i kategorii osobistych; krótsze
  listy w formularzach; kopia zapasowa nie gubi już zmienionej nazwy
  domyślnej kategorii.
- **Negatywne / ryzyka:** powrót do wersji sprzed tej decyzji — dane całe, ale
  kategorie i metody o tych samych nazwach pokażą się podwójnie (wspólna
  lista). Przeniesienie pozycji do budżetu z innymi etykietami wymaga decyzji
  (okno „Dodaj je / Bez nich").
- Metody płatności pozycje wskazują po nazwie — zmiana nazwy albo usunięcie
  metody działa tylko w jej budżecie.

## Rozważane alternatywy

- **Wspólna lista z „widocznością" w wybranych budżetach** — mniej przeróbki
  danych, ale zmiana nazwy w jednym budżecie zmieniałaby ją wszędzie (to nie
  są osobne definicje). Odrzucona.
- **Wspólna lista, w formularzach najpierw kategorie używane w budżecie** —
  najmniej pracy, nie rozdziela kont firmowych i osobistych. Odrzucona.
- **Nowy budżet z zestawem startowym albo kopią listy** — odrzucone przez
  właściciela: listę budżetu określa się samemu, bez etykiet sierot.
- **Brakujące etykiety przy przenoszeniu dodawane bez pytania** — odrzucone:
  listy budżetu rosłyby same.
