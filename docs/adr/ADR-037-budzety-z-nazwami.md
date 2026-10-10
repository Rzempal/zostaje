# ADR-037: Budżety z własnymi nazwami i ikonami

Data: 2026-10-09
Status: zaakceptowany

> **Powiązane:** [ADR-035 Plan roczny](ADR-035-plan-roczny-pozycje-z-miesiacami.md)
> (§2 budżety jako identyfikatory) | [ADR-014 Tryb budżetu](ADR-014-tryb-budzetu-osobisty-domowy-oba.md)
> | [ADR-036 Pożyczki ratalne](ADR-036-pozyczki-ratalne.md)

## Kontekst

Plan od ADR-035 przypisuje pozycje do budżetu identyfikatorem (`budgetId`),
ale reszta aplikacji znała tylko dwa zakresy: przełącznik „Osobisty |
Domowy", gest przesunięcia, subskrypcje („osobista/domowa"), „tryb budżetu"
(osobisty / domowy / oba), arkusz subskrypcji. Właściciel chce kilku
budżetów z własnymi nazwami.

## Decyzja

1. **Lista budżetów** (`Budget`: identyfikator, nazwa, ikona, ukrycie)
   w ustawieniach (`budgets`, także w kopii zapasowej). Kolejność listy =
   kolejność w przełączniku. Dwa pierwsze to dawne zakresy z tymi samymi
   identyfikatorami (`personal` „Osobisty", `household` „Domowy"), więc plan,
   odhaczone płatności (klucz `budżet|pozycja|data`) i pożyczki nie wymagały
   przeróbki. Budżety są **oddzielne** — bez widoku „wszystkie razem".
2. **Ikona** z katalogu ikon kategorii, poszerzonego o osobę, rodzinę,
   teczkę i skarbonkę (dostępne też dla kategorii).
3. **Przełącznik**: przycisk z ikoną i nazwą aktywnego budżetu, dotknięcie
   rozwija listę widocznych budżetów i „Zarządzaj budżetami" (miejsce stałe
   przy dowolnej liczbie budżetów). Gest przesunięcia: kolejny / poprzedni
   budżet z listy. Ostatnio wybrany budżet pamięta się lokalnie.
4. **Ukrywanie** zastępuje „tryb budżetu" (ADR-014): ukryty budżet znika
   z przełącznika, dane zostają. Jeden budżet musi zostać widoczny. Stary
   tryb przenosi się sam przy pierwszym uruchomieniu (np. „tylko osobisty" =
   domowy ukryty).
5. **Subskrypcje** mają `budgetId`; stare pole `scope` zostaje w zapisie dla
   wersji sprzed tej decyzji (budżet spoza dwóch pierwszych to tam
   „osobista"). Arkusz subskrypcji: kolumna „Zakres" = nazwa budżetu (import
   dopasowuje po nazwie; „Osobiste/Domowe" ze starych arkuszy — do dwóch
   pierwszych; reszta — do aktywnego).
6. **Przenieś do / Kopiuj do** innego budżetu:
   - całość budżetu (Ustawienia → Budżety, menu ⋮), przy kopiowaniu
     z wyborem „z subskrypcjami" (domyślnie tak; kopia ma własne
     przypomnienia);
   - zaznaczone pozycje (Planowanie, jedna akcja „do innego budżetu" →
     przenieś / kopiuj), pojedyncza pozycja, pożyczka i subskrypcja (menu ⋮
     w ich ekranach).
   Przeniesienie zabiera odhaczone płatności; kopia ma nowe identyfikatory
   i nie kopiuje odhaczeń. Pożyczka idzie zawsze w całości (wypłata, raty,
   zakup).
   Formularze nie mają wyboru budżetu — także formularz subskrypcji: nowa
   subskrypcja trafia do aktywnego budżetu, jak pozycja i pożyczka, a zmiana
   budżetu to tylko „Przenieś do / Kopiuj do" w menu ⋮.
   Obok jest **„Duplikuj"** — kopia w tym samym budżecie (pozycja, pożyczka
   w całości, subskrypcja, zaznaczone pozycje) z dopiskiem „(kopia)" w nazwie;
   pojedyncza otwiera się od razu do poprawienia.
7. **Usuwanie** budżetu: ostrzeżenie z liczbą pozycji i subskrypcji, że
   zniknie razem z nimi, z podpowiedzią przeniesienia — przyciski „Anuluj",
   „Przenieś i usuń…", „Usuń". Ostatniego budżetu usunąć się nie da.

## Konsekwencje

- **Pozytywne:** dowolna liczba budżetów bez zmian w danych dwóch
  istniejących; przenoszenie i kopiowanie zastępuje dawne przelewy między
  budżetami tam, gdzie trzeba przesunąć plan.
- **Negatywne / ryzyka:** wersja sprzed tej decyzji zna tylko „Osobisty"
  i „Domowy" — pozycje nowych budżetów zostają tam w danych, ale ich nie
  widać, a subskrypcje nowych budżetów pokazują się jako osobiste.
- Pasek zaznaczania: „Zaznacz wszystkie" skraca się wielokropkiem, gdy brak
  miejsca (więcej akcji niż wcześniej).

## Rozważane alternatywy

- **Segmenty jak dotąd / przewijane chipy** jako przełącznik — odrzucone:
  przy 3+ budżetach ciasno albo drugi rząd chipów nad filtrem kategorii.
- **Widok wszystkich budżetów razem** — odrzucony przez właściciela
  (budżety są osobne).
- **Kopiowanie całości bez subskrypcji** — odrzucone: właściciel chce móc
  skopiować wszystko; wybór zostaje w okienku kopiowania.
- **Wybór budżetu w formularzu subskrypcji** (chipy, pierwsza wersja DEV)
  — usunięty po teście: dublował „Przenieś do" z menu ⋮ i działał inaczej
  (zmiana dopiero z zapisem formularza, „Przenieś" — od razu).
