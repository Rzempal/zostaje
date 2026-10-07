# ADR-030: Pasek plan vs realny pokazuje SILE przekroczenia

Data: 2026-08-02
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — bez porównań plan vs realny

> **Powiazane:** [ADR-011 Rachunki (realny log)](ADR-011-rachunki-realny-log-i-scalenie-typow-cyklicznych.md)
> | [ADR-029 Podsumowanie roczne](ADR-029-podsumowanie-roczne-i-poczatek-ewidencji.md)
> | [Design system](../design.md)

## Kontekst

Aplikacja porownuje plan z wykonaniem w trzech miejscach: rachunki wobec koperty
„Na rachunki", rok wobec planu rocznego i subskrypcje wobec limitu. Kazde
uzywalo `LinearProgressIndicator` z wartoscia **przycieta do 1.0** i calym
paskiem na czerwono po przekroczeniu.

Skutek: pasek mowil tylko „przekroczono", a wygladal **tak samo przy 1% i przy
200% nadwyzki**. Informacja, ktora najbardziej interesuje — jak bardzo — ginela.

## Decyzja

Wspolny widget `PlanProgressBar(value, plan)`:

- **W planie:** zielony odcinek rosnie na neutralnym torze; reszta toru to
  „ile jeszcze zostalo".
- **Ponad plan:** caly tor dzieli sie w proporcji do WYDANEJ kwoty — zielone to
  plan (`plan / wydane`), czerwone to nadwyzka (`nadwyzka / wydane`).

```
w planie:      [■■■■■■□□□□□□]   zielone = wydane, szare = zostalo
lekko ponad:   [■■■■■■■■■■■▓]   czerwony pasek = 100/1100 szerokosci
mocno ponad:   [■■■■▓▓▓▓▓▓▓▓]   czerwone = 2/3 przy trzykrotnym przebiciu
```

Skala rosnie razem z wydatkiem, wiec **udzial czerwieni jest miara sily
przekroczenia** — widac ja jednym spojrzeniem, bez czytania liczb.

Arytmetyka (`PlanProgressBar.shares`) jest wydzielona z widoku i pokryta
testami: to jedyna czesc tego paska, ktora da sie sprawdzic inaczej niz
ogladaniem.

## Konsekwencje

- **Pozytywne:**
  - Trzy miejsca mowia tym samym jezykiem kolorow: zielone = miesci sie w planie,
    czerwone = ponad.
  - Nadwyzka jest widoczna proporcjonalnie, a nie binarnie.
  - Jeden widget zamiast trzech kopii `LinearProgressIndicator` z wlasnymi
    regulami koloru.
- **Negatywne / ryzyka:**
  - Po przekroczeniu **skala paska przestaje byc stala** — 100% dlugosci znaczy
    „tyle, ile wydano", nie „tyle, ile zaplanowano". Podpis nad paskiem podaje
    obie kwoty, wiec liczby zostaja jednoznaczne.
  - Przy bardzo duzym przebiciu zielona czesc robi sie cienka; to zamierzone
    (plan jest wtedy malym ulamkiem wydatku), ale przy 20-krotnym przebiciu
    bedzie ledwo widoczna.

## Rozwazane alternatywy

- **Zostawic pelny czerwony pasek** — odrzucone: nie niesie sily przekroczenia.
- **Pasek ponad 100% z podzialka** (np. do 200%) — odrzucone: wymaga skali i
  opisu osi, a to element wielkosci szesciu pikseli.
- **Sam procent tekstem** — odrzucone: liczba juz jest w podpisie, a pasek ma
  odpowiadac zanim ktos zacznie czytac.
