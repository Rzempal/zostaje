# ADR-020: Cykl „wybrane miesiące roku" zamiast osobnego „co N miesięcy"

Data: 2026-07-26
Status: częściowo zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — pozycje planu nie mają cykli (miesiące wprost); cykl wybranych miesięcy zostaje w subskrypcjach

## Kontekst

Model cyklu obsługiwał `weekly | monthly | quarterly | yearly | custom`, gdzie
`custom` to **odstęp w dniach**. Brakowało dwóch realnych przypadków:

1. **Co N miesięcy** (co 2, co 4, co pół roku). Zapis „co 60 dni" nie jest tym samym:
   miesiące mają różną długość, więc taki wzór rozjeżdża się w ciągu roku.
2. **Konkretne miesiące roku** — np. płatność w styczniu, kwietniu i wrześniu.

Matematyka cykli żyła w dwóch miejscach: `cycle_math.occurrencesInRange`
(kalendarz, projekcje budżetu) oraz `Subscription.nextRenewalDate` (przypomnienia).

## Decyzja

### 1. Jedna nowa wartość cyklu: `monthsOfYear` + lista miesięcy

Nowe pole `cycleMonths` (lista 1..12) w `BudgetEntry` i `Subscription`. Dzień
płatności bierze się z daty-kotwicy (`startDate`), z przycięciem do długości
miesiąca (31 → 28/30).

**Dlaczego nie osobne „co N miesięcy":** każdy interwał, który ma sens dla
rachunków — 1, 2, 3, 4, 6, 12 — **dzieli 12**, więc jest tylko innym zestawem
miesięcy. Drugie pole byłoby drugą reprezentacją tego samego wzoru: dwie ścieżki
w matematyce, dwa warianty w formularzach, Excelu i backupie, i pytanie „w którym
polu to zapisać" przy każdej zmianie.

Ograniczenie przyjęte świadomie: **nie da się zapisać „co 5 / co 7 miesięcy"**,
bo taki wzór nie powtarza się w roku. Dla rachunków domowych i subskrypcji nie
występuje.

### 2. Presety to skrót do wypełnienia listy, nie osobny byt

Formularz (`CycleMonthsPicker`) daje oba sposoby myślenia: przyciski „co 2 / 3 / 4
miesiące, co pół roku" wypełniają siatkę miesięcy licząc od miesiąca startu, a
siatkę można potem poprawić ręcznie. Zapisuje się zawsze sama lista.

### 3. Istniejące cykle zostają

`monthly`, `quarterly`, `yearly` **nie** zostały zastąpione listą miesięcy, choć
dałoby się je tak wyrazić. Powód: jeden wzór ma mieć jeden zapis — inaczej te same
dane miałyby dwie reprezentacje w backupie i synchronizacji. Nowy tryb obsługuje
wyłącznie to, czego wcześniej nie dało się zapisać.

### 4. Uśrednienie kwoty

`monthlyFromCycle` dla nowego trybu: **kwota × liczba miesięcy ÷ 12** — spójnie
z kwartalnym (÷3) i rocznym (÷12). Ubezpieczenie 900 zł płatne kwartalnie to
300 zł/mies. niezależnie od tego, czy zapisane jako `quarterly`, czy jako lista
czterech miesięcy.

## Konsekwencje

- (+) „Co 2 miesiące" i „styczeń/kwiecień/wrzesień" są wreszcie zapisywalne
  poprawnie — bez dryfu wynikającego z liczenia w dniach.
- (+) Jedno pole, jedna ścieżka w matematyce, jeden format w Excelu
  („miesiące: 1,4,9") i w backupie.
- (+) Przy okazji zniknęła duplikacja: `Subscription` liczy teraz kwotę miesięczną
  przez wspólne `monthlyFromCycle` zamiast własnego `switch`.
- (−) Brak wsparcia dla interwałów niedzielących 12 (co 5, co 7 miesięcy).
- (−) Pole dochodzi do backupu i synchronizacji; starsze wersje aplikacji
  odczytają pozycję, ale zignorują wzór i potraktują ją jak miesięczną.
- Zmiana harmonogramu = poprawienie zaznaczonych miesięcy. Jednorazowe
  przesunięcie konkretnej płatności (inna data/kwota w danym miesiącu) obsługuje
  istniejący mechanizm korekt miesięcznych (ADR-008) — nie było potrzeby niczego
  dokładać.

## Weryfikacja

`test/cycle_months_test.dart` pilnuje: przełomu roku, przycięcia dnia 31 do lutego,
braku wystąpień przed kotwicą, równoważności „lista czterech miesięcy" ↔ „cykl
kwartalny", presetów zawijających rok oraz tego, że stare dane bez pola
`cycleMonths` czytają się bez zmian.
