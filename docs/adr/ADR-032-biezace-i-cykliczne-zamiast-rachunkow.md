# ADR-032: „Bieżące" i „Cykliczne" zamiast „Rachunków" i „Wydatków"

Data: 2026-08-08
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — zakładki Bieżące i Cykliczne zniknęły; słownik nazw w zapisie (StorageKeys) nadal chroni odczyt starych danych

## Kontekst

Feedback od użytkowników: **„Rachunki" kojarzą się z opłatami stałymi** — prądem,
gazem, czynszem. Tymczasem w tej zakładce leżą zakupy, paliwo, kawa w mieście,
wyjścia, zajęcia dodatkowe dziecka i większe wydatki jednorazowe (naprawa auta).
Opłat stałych tam nie ma — te są kosztami cyklicznymi w drugiej zakładce.

Ten sam problem ma **koperta „Na rachunki"** (ADR-012). Przykład składu z samego
ADR-012 to „Paliwo 300 + Barber 120" — czyli dokładnie nie rachunki. Koperta
musi więc zmienić nazwę razem z zakładką, inaczej plan i realizacja rozjeżdżają
się nazewniczo, mimo że ADR-019 §1 celowo posadził je obok siebie.

Drugi, głębszy problem: **„Rachunki" i „Wydatki" nie tłumaczą się nawzajem.**
Obie zakładki trzymają wydatki, więc nazwa nie mówi, co gdzie wrzucić. Nazwa
szersza („Wydatki") zjada węższą, a użytkownik musi pamiętać regułę zamiast ją
przeczytać.

## Decyzja

Nazwy zakładek biorą się z **osi, która te sekcje naprawdę różni: sposobu
liczenia** (`docs/architecture.md`, „Reguła wyboru sekcji"; ADR-008, ADR-018).

| Dawna nazwa | Nowa nazwa | Znaczenie |
|---|---|---|
| Rachunki | **Bieżące** | Wydatek **datowany** — uderza w bilans konkretnego miesiąca |
| Wydatki (tytuł: „Wydatki cykliczne") | **Cykliczne** | Koszt **uśredniany** na miesiąc (kwota × liczba płatności ÷ 12) |
| Koperta „Na rachunki" | **„Na bieżące wydatki"** | Rezerwa planu na tę pierwszą pulę |

Pasek nawigacji: **Budżet · Wpływy · Bieżące · Cykliczne · Ustawienia**.

### 1. Dlaczego „Cykliczne", a nie „Stałe"

W tej zakładce są cztery rzeczy i tylko jedna jest stała:

- koszty stałe — ✅ stałe
- **raty** — mają koniec, znikają po ostatniej spłacie
- **subskrypcje** — ADR-019 nazywa je wprost *„kosztami uznaniowymi, świadomie
  oddzielonymi od kosztów stałych"*; Netflixa anuluje się jutro, prądu nie
- **przelew do domowego** — to nie koszt, tylko przesunięcie między budżetami

Wspólny mianownik całej czwórki to **uśrednianie na miesiąc**, nie stałość.
„Cykliczne" jest przy tym słowem, które w apce już było (tytuł ekranu brzmiał
„Wydatki cykliczne") — po zmianie pasek i ekran wreszcie mówią to samo.

Sekcja **„Wydatki stałe"** wewnątrz zakładki zostaje bez zmian — tam ta nazwa
jest prawdziwa.

### 2. Ikony

| Element | Ikona | Powód |
|---|---|---|
| Bieżące | `receiptText` (bez zmian) | Paragon — najczęstsze źródło pozycji |
| Cykliczne | `trendingDown` → **`repeat`** | Powtarzalność jest sednem tej sekcji; strzałka w dół znaczyła tylko „wydatek", czyli to samo co sąsiednia zakładka |
| Subskrypcje | `repeat` → **`badgeCheck`** | `repeat` przeszedł do zakładki; subskrypcja nie może mieć tej samej ikony co sekcja, w której mieszka |

**Dzwonek odrzucony** dla subskrypcji (choć kojarzy się z „subscribe" z YouTube):
`bell` to w tej apce **Powiadomienia** (Ustawienia). Subskrypcje są dokładnie
tym, co te powiadomienia generuje, więc dzwonek przy subskrypcji czytałby się
jako „ma ustawione przypomnienie", a nie „to jest subskrypcja".

**Reguła obowiązuje też WIERSZE list, nie tylko pasek:** ikona pozycji bez
własnej kategorii = ikona zakładki, do której ta pozycja należy. Zapisana raz,
w `budgetEntryIcon` (`widgets/category_icons.dart`), i używana przez kartę
pozycji, listę „Płatności" i „Podsumowanie miesiąca". Wcześniej reguła żyła
w dwóch miejscach i przy tej zmianie nazw się rozjechała — wydatek bieżący oraz
koszt cykliczny dostawały tę samą strzałkę kierunku, mimo różnych zakładek.
Żeby lista przepływów znała rodzaj pozycji, `CalendarItem` niesie `entryType`
(wyłącznie do ikony — grupowanie dalej idzie po `kind`). Pilnuje tego
`test/entry_icons_test.dart`.

### 3. Nazwy w kodzie idą za nazwami w UI

ADR-019 §3 mówił „nazwy tylko w UI" — tamta decyzja zostaje **odwrócona** dla tej
sekcji. Powód: w kodzie żyły **trzy** nazwy jednej rzeczy (`Rachunki*` po polsku,
`Bill*` i `Receipt*` po angielsku), a kontroler skanu nazywał się
`BillScanController`, choć parser obok niego `ReceiptTextParser`. To nie był
kosmetyczny rozjazd, tylko realne źródło pomyłek.

Dwa pojęcia, dwie rodziny nazw:

| Pojęcie | UI | Rodzina w kodzie |
|---|---|---|
| Wydatek datowany (pieniądze) | „Bieżące" | `Spending*` |
| Zdjęcie paragonu: skan, OCR, kadrowanie, archiwum | skan / „Archiwum paragonów" | `Receipt*` |
| Cykl rozliczeniowy subskrypcji | — | `BillingCycle` — **bez zmian**, to poprawna angielszczyzna |

Przemianowane pliki: `rachunki_screen` → `spending_screen`, `bills_planner_screen`
→ `spending_planner_screen`, `add_bill_payment_screen` → `add_spending_screen`,
`bills_allocation_item` → `spending_allocation_item`, `bills_allocation_editor` →
`spending_allocation_editor`, `pending_bill_scan` → `pending_receipt_scan`,
`bill_scan_controller` → `receipt_scan_controller`, `bill_scan_service` →
`receipt_scan_service`.

Przy okazji poprawiona **błędna** nazwa: `BillMonthOverride` →
`MonthAmountOverride`. Mimo „Bill" w nazwie klasa dotyczy korekt pozycji
**cyklicznych** i przelewu do domowego, nigdy wydatków bieżących.

### 4. Granica formatu zapisu

Nazwa **`'Rachunek'` w kolumnie „Typ" arkusza Excel zostaje rozpoznawana na
zawsze.** Eksport pisze dziś `'Wydatek bieżący'`, ale import rozumie oba warianty
(z polskimi znakami i bez) — starych arkuszy na dyskach użytkowników nikt nie
przepisze. Pilnuje tego test w `test/excel_budget_test.dart`.

**Nazwa w kodzie jest odcięta od wartości na dysku.** Kod mówi
`BudgetEntryType.spending`, a do pliku idzie `billPayment` — tłumaczy to jawna
mapa `_typeWireNames` w `budget_entry.dart` (wcześniej zapis brał `type.name`,
czyli identyfikator z kodu BYŁ wartością w bazie). Tak samo klucze pudełka
`settings`: kod woła `StorageKeys.spendingAllocationItems(scope)`, a pod spodem
stoi historyczne `billsAllocationItems|<zakres>`.

Dzięki temu stare słownictwo zostało w **dwóch opisanych miejscach**
(`storage_keys.dart` i mapa `_typeWireNames`) zamiast być rozsiane po 35 plikach.

Wartości nietykalne — wszystkie pilnowane przez `test/storage_format_guard_test.dart`:

| Wartość | Gdzie leży | Co psuje zmiana |
|---|---|---|
| `"type":"billPayment"` | Hive, kopie `.zostaje`, **paczki synchronizacji** | Telefon na starszej wersji przestaje czytać pozycje z nowszej |
| `billsAllocationItems\|<zakres>`, `billsAllocation\|<zakres>` | klucze `settings` | Utrata koperty bez napisanej migracji |
| `pendingBillScans` | klucz `settings` | Utrata kolejki skanów |
| `billsAllocation` | sekcja paczki sync **i** klucz w kopii `.zostaje` | Planner nie dojeżdża do drugiego telefonu / nie odtwarza się z kopii |
| `bill_scans` | nazwa katalogu na dysku | Osierocone zdjęcia czekające na zatwierdzenie |
| `{"rachunki":[...]}` | odpowiedź apki Lokalny Silnik AI | Skanowanie przestaje działać (osobne APK, osobne repo) |
| `'Rachunek'` w kolumnie „Typ" | arkusze `.xlsx` u użytkownika | Stare arkusze importują się z błędnym typem |

**Migracja tych nazw została świadomie odrzucona.** Kod migracji musiałby żyć
wiecznie (ktoś odtworzy dwuletnią kopię albo podniesie telefon z szuflady), więc
byłby droższy w utrzymaniu niż plik ze stałymi — a i tak nie objąłby paczki
synchronizacji, bo tej nie da się zmigrować z jednej strony.

### 5. Wniosek z wykonania: zamiana tekstem przecieka do formatu

Refaktor prowadzony zbiorczą zamianą nazw **czterokrotnie** trafił w wartości
formatu zamiast w kod: klucz `billsAllocation` w kopii i w paczce sync, klucz
`billsAllocationItems` w `settings`, klucz `rachunki` w protokole silnika AI
oraz słowo kluczowe `rachunek` w imporcie Excela. Każdy z tych przypadków
wyglądał w diffie jak zwykła zmiana nazwy.

Trzy wnioski na przyszłość:

1. **Strażnik formatu piszemy PRZED refaktorem, nie po.** Trzy z czterech wpadek
   złapały testy, nie przegląd kodu.
2. **Po pliku strażnika nie wolno puszczać zamian zbiorczych.** Czwarta wpadka
   (`billsAllocationItems`) przeszła niezauważona właśnie dlatego, że napis
   w teście zmienił się razem z napisem w kodzie: test świecił na zielono, a klucz
   w bazie był już inny. Wartości w strażniku muszą być wpisane wprost i ruszane
   wyłącznie ręcznie.
3. **Zamiana nazw musi rozróżniać wielkość liter.** `billsAllocationItems`
   ucierpiało, bo narzędzie domyślnie dopasowało je do `BillsAllocationItems` —
   klasy o tej samej nazwie w innej pisowni.

## Rozważane alternatywy

- **„Paragony"** (pierwotna propozycja). Odrzucone: nazwa jest **węższa niż
  zawartość** — przelew za usługę, faktura za naprawę auta czy zajęcia dziecka
  paragonu nie mają. Dobija to koperta: „Na paragony" nie znaczy nic, bo planuje
  się pieniądze na to, co się kupi, a nie na pokwitowania.
- **„Zakupy"**. Odrzucone po testach na realnej zawartości: kawa w mieście,
  wyjścia i zajęcia dodatkowe to **usługi**, nie zakupy.
- **„Jednorazowe"**. Najbliższe modelowi danych (wszystko tam to `billPayment`,
  czyli datowane jednorazowe), ale odrzucone: część tych wydatków powtarza się
  co miesiąc (kawa, zajęcia dziecka) i użytkownik nie myśli o nich jak
  o jednorazowych. Model danych mówi jedno, głowa użytkownika drugie — wygrywa
  głowa.
- **„Stałe"** dla drugiej zakładki. Odrzucone — patrz punkt 1.
- **Zmiana samej zakładki „Rachunki", bez ruszania „Wydatków".** Odrzucone:
  „Bieżące" obok „Wydatków" jest gorsze niż stan wyjściowy, bo szersza nazwa
  dalej zjada węższą. Ta para działa tylko jako para.

## Konsekwencje

- (+) Nazwy zakładek **tłumaczą się nawzajem**: datowane vs uśredniane. Pytanie
  „gdzie to wrzucić" ma odpowiedź w samej nazwie.
- (+) Znika fałszywe skojarzenie z opłatami stałymi, od którego zaczął się ten ADR.
- (+) Pasek nawigacji zgadza się z tytułem ekranu (dawniej „Wydatki" vs „Wydatki
  cykliczne").
- (−) Zmiana łamie pamięć mięśniową dwóch osób używających PROD. Jednorazowy koszt,
  ten sam, który ADR-019 świadomie już raz zapłacił.
- (−) „Bieżące" lekko zgrzyta przy dużym wydatku jednorazowym (nowa lodówka nie
  jest „bieżąca"). Przyjęte świadomie: to mniejsze naciągnięcie niż „Zakupy" przy
  usłudze, bo „bieżące" mówi o momencie, a nie o rodzaju.
- (−) Nazwa kanału powiadomień Androida zmienia się tylko dla nowych instalacji —
  istniejący kanał (`zostaje_scan`) zachowuje starą nazwę w ustawieniach systemu.
  ID kanału celowo zostaje, żeby nie skasować ustawień dźwięku i ważności.
- Starsze ADR (008, 011, 012, 018, 019) używają nazwy „Rachunki". To zapis
  historyczny — nie są przepisywane wstecz.
