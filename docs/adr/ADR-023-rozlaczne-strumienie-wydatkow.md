# ADR-023: Rozlaczne strumienie wydatkow jako podstawa wykresow i rozpisow

Data: 2026-07-27
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — statystyki liczone z planu rocznego
## Kontekst

Zakladka „Plan" miala trzy osobne podstrony (Budzet / Subskrypcje / Rachunki),
kazda z wlasnym wykresem trendu i wlasnym podzialem na kategorie. Wygladalo to
na trzy rownorzedne widoki, ale liczylo **te same pieniadze trzy razy**:
`expenseTrend` z sekcji „Budzet" zawieral juz subskrypcje i rachunki miesiaca,
wiec nalozenie tych serii na jeden wykres daloby linie, ktora zawsze lezy nad
pozostalymi, bo je w sobie miesci.

Ten sam problem wracal przy pytaniu „skad sie bierze saldo" i „skad sie bierze
bilans miesiaca": karta pokazywala wynik, ale nie skladniki, a skladniki
pochodzily z roznych, czesciowo zachodzacych na siebie sum.

## Decyzja

Wydatki rozbijamy na **trzy rozlaczne strumienie** i to one sa podstawa
wszystkich zestawien:

1. **Cykliczne** — koszty stale i raty, BEZ subskrypcji (`recurringExpenseTrend`,
   `monthlyBudgetExpenses`).
2. **Subskrypcje** — liczone historycznie (data startu i anulowania).
3. **Rachunki** — datowane `billPayment` danego miesiaca (realne kwoty).

Podzial jest zupelny: po ADR-018 „jednorazowy wydatek" to dokladnie
`billPayment`, wiec suma trzech serii rowna sie calosci wydatkow — jest na to
test-straznik (`plan_stats_test.dart`).

Konsekwencje dla ekranow:

- **Plan** ma JEDEN wykres trendu z trzema seriami + chipy wlacz/wylacz
  i czwarta seria „Razem" (suma, linia przerywana, domyslnie wylaczona) oraz
  JEDEN podzial na kategorie laczacy te trzy zrodla (klucz `budget_other`
  sprowadzany do `cat_other`, zeby nie bylo dwoch kawalkow „Inne").
- **Saldo** (Plan) po rozwinieciu pokazuje rozpis: wplywy − cykliczne
  − subskrypcje − zaplanowana na rachunki = zostaje.
- **Rzeczywisty bilans miesiaca** (Bilans miesiaca) pokazuje rozpis realny:
  wplywy − cykliczne (z korektami kwot i ratami tego miesiaca) − subskrypcje
  − rachunki = bilans (`MonthBalanceParts`, test na zgodnosc z `balanceForMonth`).
- Nad kazdym rozpisem pasek proporcji; kolory wg jednej reguly: zielony to
  pieniadze, ktore przychodza albo zostaja, czerwony te, ktore wychodza.

## Konsekwencje

- **Pozytywne:**
  - Jedno miejsce na pytanie „ile i na co" zamiast trzech widokow tych samych pieniedzy.
  - Kazda kwota na ekranie da sie zsumowac recznie i wynik sie zgadza — testy
    pilnuja, ze rozpis rowna sie saldu i bilansowi.
  - Korekty kwot trafiaja do tego strumienia, ktorego dotycza (wplyw / koszt
    cykliczny / rachunek), wiec „koszty cykliczne" pokazuja realny miesiac,
    a nie plan.
- **Negatywne / ryzyka:**
  - Linia „Cykliczne" jest plaska: historii zmian kosztow stalych nie ma
    w danych, wiec dzisiejsza baza jest rzutowana wstecz. Trzeba o tym pamietac,
    czytajac wykres.
  - Rachunki wchodza do podzialu kategorii kwota WYBRANEGO miesiaca, a cykliczne
    i subskrypcje kwota usrednioną — zmiana miesiaca rusza tylko czesc wykresu.
    To ta sama regula, ktora liczy plan i bilans (ADR-008), ale przy jednym
    wykresie widac ja mocniej.
  - Widok rozpisu jest zduplikowany miedzy karta „Saldo" a „Rzeczywisty bilans
    miesiaca" (~90 linii) — do konsolidacji, patrz otwarte kwestie handoffu.

## Rozwazane alternatywy

- **Zostawic dzisiejsze serie (Budzet = calosc, Subskrypcje, Rachunki)** —
  odrzucone: jedna linia zawiera dwie pozostale, wiec wykres nie porownuje
  rownorzednych wielkosci, tylko pokazuje odstepy.
- **Cztery serie z „Razem" domyslnie wlaczonym** — odrzucone: suma jest zawsze
  najwyzsza i splaszcza skladowe przy pierwszym spojrzeniu; zostala jako chip
  do wlaczenia na zadanie.
- **Rozpis salda jako wykres wodospadowy** — odrzucony: przy duzej roznicy skal
  drobne pozycje znikaja, a na waskim ekranie slupki robia sie nieczytelne.
  Pasek proporcji + rachunek daja i obraz, i dokladnosc.
