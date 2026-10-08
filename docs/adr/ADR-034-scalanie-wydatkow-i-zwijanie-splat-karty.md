# ADR-034: Scalanie wydatków w jeden wpis i zwijanie spłat karty

Data: 2026-08-17
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — bez Bieżących nie ma scalania wydatków ani zwijania spłat

> **Powiązane:** [ADR-033 Karta kredytowa](ADR-033-karta-kredytowa-pozyczka-i-splata.md)
> | [ADR-032 „Bieżące" i „Cykliczne"](ADR-032-biezace-i-cykliczne-zamiast-rachunkow.md)

## Kontekst

Dwie potrzeby, które wyglądają na jedną, a wymagają rozłącznych rozwiązań.

**Pierwsza:** kilka wydatków opisuje jeden zakup (paragon rozbity na raty
płatności, kilka wpisów z tego samego wyjazdu) i na liście zajmują cztery
wiersze zamiast jednego. Użytkownik chce je złączyć w jeden wpis o sumie kwot.

**Druga:** przy intensywnym używaniu karty kredytowej lista „Bieżące" puchnie —
każdy zakup rodzi własną spłatę (ADR-033), a bank ściąga **jedną kwotę za cały
okres**. ADR-033 przewidział to wprost w konsekwencjach: „Jeden zakup to trzy
wiersze na liście (…) problem zostaje i może wymagać własnego grupowania".

Naiwne złączenie tych potrzeb w jedną funkcję **niszczy dane**. Spłata jest
spięta `creditLinkId` z zakupem i lustrzanym wpływem, a usunięcie dowolnej
z tych pozycji kasuje kaskadowo całą trójkę (ADR-033 §8). Scalenie czterech
spłat skasowałoby więc także cztery zakupy, których użytkownik nawet nie
zaznaczył, a nowy wpis z kartą jako metodą płatności odpaliłby automat po raz
drugi — trzy wiersze zamiast jednego i przekłamany bilans.

## Decyzja

### 1. Scalanie dotyczy WYŁĄCZNIE pozycji niespiętych

Akcja „Scal" w pasku zaznaczania na „Bieżących" odmawia, gdy w zaznaczeniu jest
pozycja z `creditLinkId` (karta) albo `linkId` (przelew między budżetami).
Blokada stoi w **dwóch miejscach**: ekran mówi dlaczego, a
`BudgetController.mergeSpendings` sprawdza to jeszcze raz przy zapisie —
między zaznaczeniem a zatwierdzeniem może wejść synchronizacja.

Odmowa jest jedynym uczciwym wyjściem: dopuszczenie karty oznaczałoby kasowanie
danych spoza zaznaczenia.

### 2. Data scalonego wpisu to data NAJSTARSZEJ pozycji

Przy płatnościach kartą termin najwcześniejszej pozycji mija pierwszy — data
późniejsza sugerowałaby więcej czasu, niż go realnie jest. Przy scalaniu przez
granicę miesiąca wpis ląduje więc we WCZEŚNIEJSZYM bilansie.

### 3. Wzorzec wybiera użytkownik, nie reguła

Nazwa, kategoria i metoda płatności pochodzą z **jednej wskazanej pozycji**,
wybieranej z listy zaznaczonych. Reguła automatyczna („największa kwota",
„pierwsza") trafiałaby w intencję przypadkiem: przy zaznaczeniu 500 / 200 / 500
data i największa kwota to różne wiersze, a nazwa decyduje, czy wpis da się
później rozpoznać.

Kwota to zawsze suma zaznaczonych, a notatka dostaje **spis scalonych pozycji** —
po zapisie to jedyny ślad po tym, co zniknęło z listy.

### 4. Scalenie to jedna operacja: najpierw zapis, potem kasowanie

`mergeSpendings` tworzy scaloną pozycję i dopiero potem usuwa źródła. Gdyby
kasowanie padło w połowie, na liście zostaje **nadmiar wierszy** — widoczny
i do posprzątania ręcznie. Odwrotna kolejność gubiłaby pieniądze bez śladu.

Formularz jest podglądem propozycji: **Anuluj nie rusza niczego**, a przycisk
zapisu nazywa się „Scal", bo zapis tutaj KASUJE dane. Przełącznik zakresu jest
w tym trybie schowany — zapis do drugiego budżetu zostawiłby źródła nietknięte
i te same pieniądze policzyłyby się dwa razy.

Zdjęcia paragonów pozycji źródłowych znikają razem z nimi (kopia prywatna);
publiczne archiwum zostaje, bo to trwały ślad (ADR-013).

### 5. Pozycje karty zwijamy w widoku, danych nie ruszamy

Dotyczy **obu stron** automatu karty, bo problem jest ten sam po obu:

- **„Bieżące"** — spłaty („Spłata: …"),
- **„Wpływy"** — lustrzane wpływy „karta pożycza na ten zakup" („Karta: …")
  oraz, w OSOBNEJ grupie, pożyczki gotówkowe z karty.

Lustro i pożyczka gotówkowa nie trafiają do jednego worka, choć oba są wpływami
z tej samej karty: lustro znosi się z zakupem w tym samym miesiącu, a pożyczka
to pieniądze, które naprawdę wpłynęły. Wspólna suma nie odpowiadałaby na żadne
sensowne pytanie.

Pozycje **tej samej karty, z tego samego miesiąca i w tej samej walucie** rysują
się jako jeden wiersz z sumą składników; tapnięcie rozwija oryginalne pozycje,
które zachowują pełne zachowanie (edycja, odhaczenie, zaznaczanie). Sumy sekcji,
bilans i wykresy pozostają bez zmian — to sposób rysowania listy, nie operacja
na budżecie.

Szczegóły reguł:

- **Próg 2 pozycje.** Jedna spłata „zwinięta w grupę" dokładałaby tapnięcie, nie
  oszczędzając ani jednego wiersza.
- **Grupa staje w miejscu swojej pierwszej pozycji**, więc zwijanie nie miesza
  aktywnego sortowania.
- **Stan rozwinięcia nie jest zapamiętywany** między wejściami: grupy powstają
  i znikają razem z filtrami.
- **W trybie zaznaczania grupy są rozwinięte na sztywno.** „Zaznacz wszystkie"
  obejmuje pozycje w grupach, więc muszą być widoczne — inaczej licznik paska
  mówiłby o czymś, czego nie widać.
- **Wiersz grupy nie jest pozycją budżetu**: nie da się go edytować, zaznaczyć
  ani usunąć przesunięciem (usunięcie spłaty kasuje kaskadą zakup).

### 6. Role rozpoznajemy z układu pozycji, bez nowego pola w danych

W danych nie ma znacznika „to jest spłata" ani „to jest lustro" — wszystko spina
wspólny `creditLinkId`. Rozstrzyga więc układ pozycji w obrębie jednej operacji:

- **Spłata** — zakup i jego spłata są wydatkami z tą samą metodą płatności,
  ale spłata stoi o `graceDays` PÓŹNIEJ, więc spłatą jest wydatek
  o najpóźniejszej dacie. Przy remisie dat (po ręcznej edycji terminu) nie
  wskazujemy żadnej pozycji — lepiej nie zwinąć niczego, niż zwinąć zakup
  i udawać, że to spłata.
- **Lustro albo pożyczka** — zakup kartą daje DWA wydatki (zakup i spłatę) plus
  wpływ, a pożyczka gotówkowa tylko jeden wydatek (spłatę) plus wpływ. Liczba
  wydatków w operacji rozstrzyga więc, czy wpływ jest zapisem technicznym, czy
  pieniędzmi, które użytkownik naprawdę wziął — i do której z dwóch grup trafi.

Nazwę karty dla grupy bierzemy z **wydatków** operacji — lustrzany wpływ powstaje
bez metody płatności, więc sam z siebie nie wie, do której karty należy.

Nowego pola „rola" świadomie NIE dokładamy: pozycje jadą między telefonami
(ADR-009), a telefon ze starszą wersją skasowałby nieznane pole po cichu przy
pierwszym zapisie tej pozycji. W PROD są dwa telefony aktualizowane w różnym
czasie.

## Konsekwencje

- (+) Lista „Bieżące" przestaje puchnąć od spłat karty, a historia zakupów
  zostaje nietknięta.
- (+) Scalanie nie ma jak zjeść danych spoza zaznaczenia — blokada stoi
  w dwóch miejscach i jest objęta testami.
- (−) **Scalenia nie da się cofnąć.** Pozycje źródłowe znikają razem ze
  zdjęciami; zostaje po nich tylko spis w notatce.
- (−) Scalanie omija dokładnie ten przypadek, od którego zaczęła się rozmowa
  (spłaty karty) — tam odpowiedzią jest zwijanie w widoku, nie łączenie danych.
- (−) Reguła „najpóźniejsza data = spłata" jest heurystyką. Ręczne cofnięcie
  terminu spłaty przed datę zakupu wyłącza zwijanie dla tej trójki (nic się nie
  psuje, wiersze wracają do postaci sprzed zwijania).
- (−) Reguła lustra opiera się na tym, że operacja ma dwa wydatki. Ręczne
  usunięcie… jest niemożliwe (kaskada), ale ręczne DODANIE wydatku z tym samym
  `creditLinkId` nie jest przewidziane żadnym ekranem — gdyby kiedyś było,
  regułę trzeba przemyśleć.

## Rozważane alternatywy

- **Spłata zbiorcza (jedna spłata pokrywa N zakupów).** Wymagałaby zamiany
  `creditLinkId` na relację wiele-do-jednego: migracja danych, przerobienie
  kaskad, zmiana formatu synchronizacji i kopii. Odrzucone także **merytorycznie**:
  w banku spłaca się DOWOLNĄ kwotę (albo okres rozliczeniowy, albo całość
  zadłużenia), więc sztywna „jedna spłata za wszystko" i tak nie odwzorowałaby
  rzeczywistości — kupowalibyśmy dużą zmianę za model, który dalej byłby
  przybliżeniem.
- **Scalanie zakupów zamiast spłat** (automat wygeneruje jedną spłatę).
  Działa bez zmian w modelu, ale skleja „Microsoft Office" z bezimiennymi
  zakupami i gubi informację, za co się płaciło.
- **Wskaźnik „suma zadłużenia karty"** jako osobny kafelek. Odłożone: sumę widać
  w zwiniętym wierszu, a osobna liczba wymagałaby rozstrzygnięcia, czy dotyczy
  całego zadłużenia, czy tylko kwoty wymagalnej.
- **Blokada scalania tylko w interfejsie.** Odrzucone: między zaznaczeniem
  a zapisem może wejść synchronizacja, więc regułę musi znać także kontroler.
