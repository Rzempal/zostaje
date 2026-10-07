# ADR-015: Przycinanie zdjęcia rachunku natywnym uCrop (bez Google Play Services)

Data: 2026-07-24
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — skan paragonów usunięty

## Kontekst

Zdjęcia rachunków (skan AI, ADR-013) trafiały do silnika i do archiwum w `Documents`
w takim kadrze, w jakim je zrobiono — często z ręką, blatem i tłem wokół paragonu.
Dwa realne koszty: (1) dla lokalnego silnika AI to szum utrudniający OCR, (2) dla
archiwum niepotrzebne megabajty (obserwowane pliki 5–8 MB przy udostępnieniu z galerii).

Potrzebny był krok docięcia zdjęcia do samego paragonu. Musiał działać jednakowo na
wszystkich źródłach (aparat, galeria, „Udostępnij", edycja) i — zgodnie z fundamentem
projektu (zero chmury, brak zależności od Google, offline-first) — pozostać w pełni
on-device i lekki.

## Decyzja

Docinanie realizuje **`image_cropper` (natywny silnik uCrop)** — ręczny kadr z uchwytami
rogów, wolne proporcje, wynik JPEG (kompresja + sufit 1600 px). Opakowane w
`ReceiptCropService` (motyw pod Aurorę, anulowanie/błąd zwraca oryginał — nigdy nie
blokuje przepływu).

Umiejscowienie (asymetryczne, zależne od źródła i stanu danych):

- **Aparat / galeria** — crop od razu po wyborze, przed `startScan`. Ponieważ `startScan`
  kopiuje zdjęcie raz, a OCR, prywatna kopia i archiwum czytają ten sam plik, docięcie
  na wejściu **dziedziczy się w cały łańcuch** (eliminacja przypadku szczególnego).
- **„Udostępnij → Zostaje"** — bez przerywania (fire-and-forget); docięcie dostępne
  później z poczekalni „Do zatwierdzenia" (tap w miniaturę → „Przytnij",
  `BillScanController.recrop` podmienia sam obraz, bez ponownego OCR).
- **Formularz edycji** — crop z podglądu miniatury. Skan przed zatwierdzeniem (brak
  `entryId`) zwraca przyciętą ścieżkę z formularza do `finalizeApproval`; zapisany
  rachunek (jest `entryId`) podmienia prywatną kopię od razu
  (`BillScanController.replaceReceiptPhoto`).

Miniatura po docięciu zapisywana jest zawsze pod **nową nazwą pliku** — Flutter cache'uje
obraz po ścieżce, więc nadpisanie w miejscu nie odświeżyłoby podglądu.

## Konsekwencje

- **Pozytywne:** czytelniejszy materiał dla OCR; wyraźnie mniejsze pliki w archiwum;
  jeden mechanizm docinania na wszystkie źródła; brak zależności od Google Play Services
  (spójne z ADR-013 „zero chmury"); nie blokuje przepływu przy anulowaniu.
- **Negatywne / ryzyka:** natywny ekran uCrop wymaga wpisu `UCropActivity` w manifeście
  (dodane) i osobnego stylowania pod motyw (nie dziedziczy Aurory z Fluttera). Docięcie
  **zapisanego** rachunku aktualizuje tylko kopię podglądu w apce — publiczny plik w
  `Documents` zapisany przy zatwierdzeniu **zostaje bez zmian** (ponowna archiwizacja
  tworzyłaby duplikat / wymagała przeliczenia nazwy — świadomie poza zakresem).

## Rozważane alternatywy

- **ML Kit Document Scanner (auto-detekcja krawędzi + korekcja perspektywy)** — odrzucona:
  ciągnie **Google Play Services** (łamie „zero chmury / brak zależności od Google"), ma
  własne UI aparatu, więc nie obsłużyłaby galerii ani udostępnienia jednolicie.
- **Crop tylko na wejściu, dla wszystkich źródeł** — odrzucona: przerywałoby
  fire-and-forget przy „Udostępnij" (dochodzi tam też wrażliwy warm-share), a rachunek
  i tak czeka w poczekalni, gdzie docięcie jest naturalne.
- **Nadpisywanie zdjęcia w miejscu (ta sama ścieżka)** — odrzucona: cache obrazu Fluttera
  po ścieżce nie odświeżyłby miniatury; ta sama miniatura bywa też współdzielona przez
  kilka pozycji z jednego kadru.
