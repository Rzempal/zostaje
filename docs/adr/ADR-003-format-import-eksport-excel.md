# ADR-003: Format importu/eksportu Excel i model bezpieczenstwa

Data: 2026-06-16
Status: częściowo zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — arkusz subskrypcji bez zmian; arkusz budżetu zastąpiła tabela roku planu
## Kontekst

Aplikacja ma dwa formaty wyjscia danych: zaszyfrowany backup `.subkarton` (pelny
round-trip, AES-256-GCM) oraz PDF (tylko do odczytu). Brakowalo formatu **czytelnego i
edytowalnego recznie**, ktorym uzytkownik moglby przeniesc liste subskrypcji z arkusza
(typowo prowadzonej jako `Nazwa | Kwota`). Trzeba bylo wybrac format pliku oraz
zdefiniowac model importu danych **niezaufanych** (recznie edytowanych przez czlowieka).

## Decyzja

- **Format `.xlsx`** przez pakiet `excel` (odczyt + zapis), nie CSV.
- **Kolumny:** `Nazwa`, `Kwota` (wymagane) + `Waluta`, `Cykl`, `Kategoria`,
  `Metoda platnosci`, `Aktywna`, `Data startu` (opcjonalne, z domyslnymi). Naglowek
  wykrywany automatycznie; brak naglowka → uklad pozycyjny (kol. 0 = Nazwa, 1 = Kwota).
  Format **nie** obejmuje `description` ani `cancellationUrl`.
- **Import nie-niszczacy:** kazdy wiersz tworzy nowa subskrypcje z **nowym UUID** —
  import nigdy nie nadpisuje istniejacych. Kategorie i metody platnosci sa tylko
  **dopasowywane po nazwie**, nie tworzone z importu.
- **Bezpieczenstwo:** sanityzacja formul przy eksporcie (ochrona przed CSV/DDE
  injection), limity (5 MB, 2000 wierszy), parsowanie poza glownym watkiem (`compute`),
  walidacja wartosci + raport pominietych wierszy.

## Konsekwencje

- **Pozytywne:** czytelny, edytowalny format; jeden pakiet obsluguje odczyt i zapis;
  brak problemow z polskimi ustawieniami regionalnymi CSV; bezpieczny import danych
  niezaufanych; brak ryzyka cichego nadpisania istniejacych subskrypcji.
- **Negatywne / ryzyka:** +1 zaleznosc (`excel`, stosunkowo ciezka); import gubi opisy i
  linki do anulowania (trzeba dodac recznie); waluty obce przeliczane stalym kursem
  aplikacji; Excel to format "ludzki", nie pelny round-trip (do tego sluzy `.subkarton`).

## Rozwazane alternatywy

- **CSV** — odrzucone: polskie ustawienia regionalne (separator `;` vs przecinek
  dziesietny `,`, kodowanie UTF-8) psuja pliki u uzytkownikow; brak typowania komorek.
- **Rozszerzenie formatu `.subkarton`** — odrzucone: zaszyfrowany i zlozony, nieedytowalny
  recznie — inny cel (bezpieczna kopia, nie wymiana z arkuszem).
- **Upsert po nazwie lub ID** — odrzucone: Excel nie ma stabilnego ID; nadpisywanie po
  nazwie grozi cicha utrata danych przy recznie edytowanym pliku.
