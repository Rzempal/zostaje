# ADR-033: Karta kredytowa — pożyczka i spłata jako pozycje spięte `creditLinkId`

Data: 2026-08-09
Status: częściowo zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — automat karty w Bieżących usunięty; karta z okresem bezodsetkowym zostaje dla pożyczki z karty w planie

## Kontekst

Karta kredytowa nie wydaje pieniędzy — **pożycza je**. Zakup kartą nie zabiera
nic z konta w dniu zakupu; robi to spłata po okresie bezodsetkowym. Aplikacja
nie umiała tego wyrazić: zakup kartą wyglądał jak każdy inny wydatek i obciążał
bilans miesiąca, w którym nic z konta nie wyszło.

Pierwotna specyfikacja brzmiała: „zapłacę kartą → utwórz automatycznie wydatek
jednorazowy X dni później". Wzięta wprost **liczyłaby te same pieniądze dwa
razy**: zakup 200 zł w sierpniu plus spłata 200 zł we wrześniu to 400 zł
wydatków w budżecie, choć wydano 200.

## Decyzja

### 1. Karta to cecha metody płatności

`PaymentMethod` dostaje `isCreditCard` (toggle) i `graceDays` (dni bezodsetkowe).
Oba pola są **opcjonalne w JSON-ie**: metody jadą w paczce synchronizacji
(ADR-025), więc telefon na starszej wersji musi dalej czytać metodę, której
nowych pól nie zna. Zwykła metoda nie zapisuje ich wcale.

**Karta bez liczby dni jest odrzucana przy zapisie.** Bez terminu automat nie
miałby jak wyznaczyć daty spłaty i po cichu by nie zadziałał — lepiej powiedzieć
to od razu niż zostawić użytkownika z kartą, która „nic nie robi".

### 2. Operacja kartą to zestaw pozycji, nie jedna

Wszystkie powstają razem i noszą wspólny `creditLinkId`:

**Wpływ z karty** (pożyczka gotówkowa) — dwie pozycje:

| Kiedy | Co | Kwota |
|---|---|---|
| dzień pożyczki | wpływ, który wpisał użytkownik | +500 |
| +`graceDays` | „Spłata: …" | −500 |

Netto zero: wziąłeś i oddajesz.

**Zakup kartą** — trzy pozycje:

| Kiedy | Co | Kwota |
|---|---|---|
| dzień zakupu | zakup, który wpisał użytkownik | −200 |
| dzień zakupu | „Karta: …" — **wpływ**, karta pożycza | +200 |
| +`graceDays` | „Spłata: …" | −200 |

Miesiąc zakupu wychodzi na **zero**, koszt ląduje w miesiącu, w którym pieniądze
naprawdę wychodzą z konta. Widać przy tym obie daty: kiedy kupiłeś i kiedy
płacisz.

Lustrzany wpływ jest tu **konieczny, a nie ozdobny** — bez niego wraca podwójne
liczenie z „Kontekstu". Pilnuje tego `test/credit_card_automation_test.dart`.

### 3. Osobne pole `creditLinkId`, nie `linkId`

`linkId` spina przelew między **różnymi zakresami** (osobisty ↔ domowy), a jego
kaskady szukają partnera po przeciwnej stronie. Pozycje karty siedzą w **jednym**
zakresie. Wspólne pole gubiłoby jedną z dwóch relacji: usunięcie zakupu kartą nie
skasowałoby spłaty (partnera szukano by w drugim boxie), a `moveToScope`
odmawiałby przeniesienia z komunikatem o przelewie.

### 4. Zakres automatu: tylko wydatek bieżący i wpływ jednorazowy

Koszt cykliczny i rata rozkładają się na miesiące i wchodzą do planu
(„zostaje/mies"). Doklejenie do nich spłaty rozjechałoby plan, a nie tylko bilans
miesiąca. Subskrypcja płacona kartą zostaje więc zwykłą subskrypcją.

### 5. „Wpływ z karty" bez nowego typu w formacie zapisu

Zamiast nowej wartości `BudgetEntryType` — istniejący `oneTimeIncome` ze
wskazaną kartą jako metodą płatności. Formularz wpływu jednorazowego pokazuje
pole „Pożyczone z karty" **tylko wtedy, gdy istnieje karta z warunkami**, i
pozwala wybrać wyłącznie karty (pensja żadnej metody płatności nie ma).

Zysk: zero zmian w formacie zapisu, czyli zero ryzyka dla synchronizacji
i starszych kopii (ADR-032 §4).

### 6. Dwa przełączniki metody opisują dwa różne momenty

Metoda płatności ma teraz dwa toggle i trzeba powiedzieć wprost, czego dotyczą:

- **„Karta kredytowa"** mówi o **zakupie** — karta pożycza pieniądze.
- **„Automatyczna"** mówi o **spłacie** — czy schodzi sama, czy trzeba ją zrobić.

Zakup kartą schodzi natychmiast zawsze, więc pytanie „czy automatyczna" ma sens
tylko wobec spłaty — i to ją można przegapić. Dlatego pozycja spłaty **dziedziczy
kartę jako metodę płatności**: przy karcie automatycznej trafia do „Płatności
automatycznych", przy manualnej — na listę do odhaczenia.

Ikona metody: **kształt mówi, skąd pieniądze, kolor — kto płaci**.

| metoda | ikona | kolor |
|---|---|---|
| zwykła manualna | rączka | domyślny |
| zwykła automatyczna | piorun | domyślny |
| kredytowa manualna | karta | czerwony |
| kredytowa automatyczna | karta | żółty |

Żółty i czerwony to ta sama para, którą kalendarz oznacza płatność automatyczną
i manualną — nie wprowadzamy drugiego języka kolorów. Reguła siedzi w jednym
miejscu (`paymentMethodIcon` / `paymentMethodIconColor`), bo przy ADR-032 ta
sama reguła zduplikowana w dwóch miejscach zdążyła się już raz rozjechać.

### 7. Automat mówi, co zrobił

Po zapisie pozycji z kartą pojawia się komunikat: co dołożono i na kiedy.
Użytkownik wpisał JEDEN zakup, a na liście przybyły trzy pozycje — bez
komunikatu wyglądałoby to na błąd aplikacji.

### 8. Kaskady

- **Usunięcie dowolnej pozycji** kasuje całą resztę zestawu. Sama spłata bez
  zakupu to wydatek znikąd; sam wpływ z karty to pieniądze, których nikt nie
  oddaje.
- **Zmiana kwoty** źródła przechodzi na pozostałe pozycje — inaczej zakup
  poprawiony z 200 na 300 zostawiłby pożyczkę 200 i miesiąc przestałby wychodzić
  na zero.
- **Zmiana daty NIE przelicza terminu spłaty.** Bank liczy okres bezodsetkowy od
  rozliczenia cyklu, nie od pojedynczej transakcji, więc automatyczne przesuwanie
  byłoby zgadywaniem. Termin zostaje widoczny i do poprawienia ręcznie.

## Konsekwencje

- (+) Zakup kartą przestaje kłamać o tym, kiedy pieniądze wychodzą z konta.
- (+) Suma dalej daje się policzyć ręcznie — zasada z ADR-023 zostaje spełniona.
- (+) Nic w formacie zapisu się nie zmienia poza dwoma opcjonalnymi polami metody
  i jednym opcjonalnym polem pozycji; starsze wersje czytają dane jak dotąd.
- (−) Jeden zakup to trzy wiersze na liście. Przy intensywnym używaniu karty
  „Bieżące" robią się gęste. Łagodzi to zwijanie bieżących do sumy (ADR-032),
  ale problem zostaje i może wymagać własnego grupowania.
- (−) Termin spłaty jest liczony od daty zakupu, a nie od cyklu rozliczeniowego
  karty. Dla kart z jednym terminem w miesiącu to przybliżenie — świadome, patrz
  punkt 6.
- (−) Automat działa przy DODAWANIU. Zmiana metody płatności istniejącej pozycji
  na kartę nie utworzy zestawu wstecz.

## Rozważane alternatywy

- **Sam dodatkowy wydatek X dni później** (specyfikacja wprost). Odrzucone:
  podwaja koszty, patrz „Kontekst".
- **Przesunięcie daty zakupu na termin spłaty** (jedna pozycja zamiast trzech).
  Odrzucone: gubi informację, kiedy zakup się wydarzył, a to jedyna rzecz, którą
  użytkownik pamięta w chwili wpisywania.
- **Osobny typ pozycji „karta kredytowa"**. Odrzucone: nowa wartość w formacie
  zapisu psułaby synchronizację ze starszym telefonem, a cała potrzebna
  informacja mieści się w metodzie płatności.
- **Saldo karty jako osobne konto.** Odrzucone jako nadmiar na tym etapie —
  aplikacja nie ma pojęcia „konto", a wprowadzenie go dotknęłoby całego silnika
  bilansu.
