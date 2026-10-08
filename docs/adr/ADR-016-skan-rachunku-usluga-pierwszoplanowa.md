# ADR-016: Skan rachunku w usłudze pierwszoplanowej + wybudzanie uśpionego silnika

Data: 2026-07-25
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — skan paragonów usunięty, usługa pierwszoplanowa zniknęła

## Kontekst

Skan rachunku (ADR-013) miał dwie wady widoczne w codziennym użyciu:

1. **Silnik nie startował sam.** Przy pierwszym zdjęciu trzeba było ręcznie odpalić apkę
   „Lokalny Silnik AI" — dopiero potem rozpoznawanie działało. Android trzyma apkę
   w stanie *zatrzymana* (świeża instalacja, „wymuś zatrzymanie", uśpienie nieużywanej
   aplikacji przez system) i **nie dopasowuje jej komponentów** do intencji bez flagi
   `FLAG_INCLUDE_STOPPED_PACKAGES`. Bindowanie po cichu nie dochodziło do skutku, a
   ponieważ limit czasu na połączenie był wspólny z limitem na pracę silnika (180 s),
   wyglądało to jak trzyminutowe zawieszenie.

2. **Rozpoznawanie w tle gubiło skany.** Cały przepływ napędzała warstwa Dart w procesie
   Zostaje: zlecenie, oczekiwanie ~45 s, odbiór wyniku. Gdy użytkownik wyszedł z apki,
   jej proces stawał się zbuforowany — a silnik ładował właśnie model liczony
   w gigabajtach, czyli sam wywoływał presję pamięci, przez którą system ubijał
   najlepszego kandydata: zbuforowane Zostaje. Skan przepadał, pozycja wracała po
   restarcie jako „Rozpoznawanie przerwane — ponów". Powiadomienie „Rozpoznaję rachunek…"
   było zwykłym powiadomieniem lokalnym i **niczego nie chroniło**.

## Decyzja

### 1. Bindowanie budzi uśpiony silnik

Intencja wpięcia do usługi AIDL dostaje `FLAG_INCLUDE_STOPPED_PACKAGES`, a limit czasu
na samo połączenie (25 s) jest osobny od limitu na pracę silnika (180 s). Nieudane
połączenie kończy się czytelnym komunikatem („Lokalny Silnik AI nie odpowiada — otwórz
apkę silnika i ponów"), nie ciszą. Wspólny kod bindowania mieszka w `EngineClient`.

### 2. Rozpoznawanie prowadzi natywna usługa pierwszoplanowa

`BillScanService` (typ `dataSync`, powiadomienie „Rozpoznaję rachunek…") przejmuje bind,
wywołanie `recognizeBill` i odbiór wyniku. Proces Zostaje przestaje być kandydatem do
ubicia, a `BIND_IMPORTANT` podnosi priorytet procesu silnika na czas wnioskowania.
Kolejka jest po stronie usługi — jeden skan naraz, jak dotąd.

Gdy system odmówi startu usługi (Android 12+ blokuje start usługi pierwszoplanowej
z tła), mostek robi skan po staremu, w procesie aplikacji — gorzej chronione, ale
lepsze niż odmowa skanowania.

### 3. Wynik przez skrzynkę, nie przez żywy kanał

`ScanResultStore` zapisuje surową odpowiedź silnika na dysk (`commit`, nie `apply`)
i budzi warstwę Dart. Odbiór jest jednorazowy: aplikacja przy starcie i przy pingu
opróżnia skrzynkę i nanosi wyniki na pozycje oczekujące. Dzięki temu skan kończy się
poprawnie także wtedy, gdy w międzyczasie zniknął ekran aplikacji (zmiecenie z listy
ostatnich). Skany nadal przetwarzane są raportowane osobno (`inFlight`), żeby nie
zostały omyłkowo uznane za sieroty po ubitym procesie.

Powiadomienie końcowe wystawia ta strona, która żyje: Dart (z nazwą rachunku) albo
usługa natywna (ogólne), gdy warstwy Flutter już nie ma.

### 4. Rok w dacie: kotwica po stronie aplikacji

Silnik nie ma zegara — gdy na dokumencie jest sam dzień i miesiąc (paragon, zrzut
z Google Pay), model musi rok zmyślić i trafia w lata ze swojego treningu. `BillScanParser`
dokłada więc rok wiarygodny wobec „dzisiaj": data spoza okna (−15 miesięcy … +12 miesięcy)
zachowuje dzień i miesiąc, a rok dostaje ten najbliższy dzisiejszej dacie (remis → rok
bieżący). Parser przyjmuje przy okazji zapisy nie-ISO („12.03.2026", „12.03").

## Konsekwencje

- (+) Skan działa bez ręcznego odpalania silnika i przeżywa wyjście z aplikacji.
- (+) Wynik rozpoznania nie ginie razem z ekranem aplikacji.
- (−) Na czas rozpoznawania widać stałe powiadomienie systemowe — warunek pracy usługi
  pierwszoplanowej, nie da się go ukryć.
- (−) Dwa uprawnienia więcej w manifeście (`FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_DATA_SYNC`) — systemowe, bez pytania użytkownika.
- (−) Kotwica roku przesunie datę **naprawdę** starego rachunku (ponad ~15 miesięcy) do
  bieżącego roku — trzeba ją wtedy poprawić ręcznie przed zatwierdzeniem. Docelowo
  właściwe miejsce naprawy to prompt silnika (podanie modelowi dzisiejszej daty w repo
  `karton-ai`) — wymaga osobnego wdrożenia produkcyjnego silnika i dotyka też APPteczki.

## Uzupełnienie (2026-07-27): kolejka rozpoznań należy do usługi, nie do Darta

Pierwotnie kolejkę trzymała warstwa Dart: `BillScanController` czekał na wynik
jednego skanu, zanim zlecił następny. Usługa miała własną kolejkę, ale nigdy nie
było w niej więcej niż jednej pozycji — i to psuło dokładnie ten scenariusz, dla
którego powstała usługa. Drugi skan ruszał po ~45 s, czyli zwykle przy schowanym
już telefonie, więc Android 12+ odmawiał startu usługi pierwszoplanowej z tła
i zlecenie lądowało na ścieżce awaryjnej w procesie apki, skąd system wymiatał
je razem z procesem.

Teraz Dart przepuszcza zdjęcia przez szybką ścieżkę pojedynczo (OCR na miejscu),
ale **nietrafione zleca usłudze od razu i nie czeka na wynik** — serializacją
zajmuje się `BillScanService`. Dzięki temu każde zlecenie wychodzi, gdy apka jest
jeszcze na wierzchu. `activeScanId` to pierwszy z listy zleconych (kolejność
`ScanResultStore.inFlightIds()` odpowiada kolejności pracy usługi), a limit czasu
pilnuje wyłącznie skanu aktualnie liczonego — liczony od zlecenia zabijałby
pozycje, które po prostu czekają w kolejce.

Ścieżka awaryjna w `AiEngineBridge` zostaje, ale wraca do roli prawdziwego
wyjątku (np. zlecenie z „Udostępnij", gdy apka nie zdążyła wyjść na wierzch).
