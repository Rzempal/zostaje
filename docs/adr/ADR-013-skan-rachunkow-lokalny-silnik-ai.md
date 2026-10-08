# ADR-013: Skanowanie rachunków lokalnym silnikiem AI (zero chmury)

Data: 2026-07-18
Status: zastąpiony przez [ADR-035](ADR-035-plan-roczny-pozycje-z-miesiacami.md) (2026-10-07) — skan paragonów usunięty razem z zakładką Bieżące (kod w tagu v0.26.26100600)

## Kontekst

Właściciel chce dodawać rachunki ze zdjęcia (aparat, galeria, systemowe
„Udostępnij → Zostaje") bez ręcznego przepisywania. Filozofia projektu jest
twarda: **dane finansowe nigdy nie opuszczają urządzenia** — chmurowe OCR/AI
odpada. Równolegle istnieje **Lokalny Silnik AI** (repo `karton-ai`): osobna
apka trzymająca model Gemma 4 E4B (LiteRT-LM) na urządzeniu i wystawiająca OCR
innym aplikacjom właściciela przez usługę AIDL ze strażnikiem podpisu
(Mechanizm 2 — jedna kopia modelu, wielu klientów; pierwszy klient: APPteczka).

Brama jakości (test promptu rachunkowego na realnych dokumentach w Developer
tools silnika) dała poprawne kwoty/daty/JSON przy czasie ~40 s na zdjęcie
(wizja tylko na CPU — ograniczenie LiteRT-LM).

## Decyzja

### 1. Zostaje zostaje bez chmury — AI wyłącznie przez lokalny silnik

Zostaje NIE integruje się z żadnym API AI w sieci. Skan rachunku = wywołanie
usługi AIDL silnika na tym samym telefonie (`recognizeBill`, prompt `BILL_OCR`
mieszka w silniku — jeden punkt aktualizacji). Deklaracja „dane nie opuszczają
urządzenia" pozostaje prawdziwa.

### 2. Klienci bindują wyłącznie PRODUKCYJNY pakiet silnika

Zawsze `app.michalrapala.ai_engine` — także build dev Zostaje. Kanał DEV
silnika (`app.michalrapala.ai_engine.dev`, osobna apka) służy tylko do testów
samego silnika. Nowe metody AIDL docierają do klientów dopiero z produkcyjnym
deployem silnika.

### 3. Opt-in dotyczy SILNIKA, nie skanowania

Pierwotnie (wzorzec z APPteczki) jeden przełącznik „Asystent AI" rządził całym
skanowaniem: wyłączony ukrywał opcje w menu „Dodaj rachunek" i odrzucał zdjęcia
z systemowego „Udostępnij".

**Skorygowane po wprowadzeniu ADR-017.** Odkąd odczyt paragonów i potwierdzeń
płatności robi model OCR wbudowany w APK, ta bramka zamykała działającą,
lokalną funkcję za pytaniem o zewnętrzną aplikację z modelem językowym — czyli
o coś, czego ta funkcja w ogóle nie potrzebuje.

Dziś: **skanowanie działa zawsze** (zwykła funkcja apki, bez przełącznika),
a przełącznik „Asystent AI" (domyślnie **wyłączony**) decyduje wyłącznie o tym,
czy dokument nierozpoznany regułami trafia do silnika. Bez silnika taka pozycja
kończy jako „Uzupełnij ręcznie" — zostaje w „Do zatwierdzenia" ze zdjęciem
i przyciskiem edycji, więc rachunek da się dokończyć bez żadnego automatu.
Ekran „Asystent AI" mówi to wprost i trzyma link do pobrania/uruchomienia apki
silnika.

### 4. OCR w tle + pozycje „Do zatwierdzenia" (nie pełny automat, nie modal)

Rozpoznawanie trwa ~30–45 s, więc: zdjęcie → kopia w katalogu apki → pozycja
oczekująca (`PendingBillScan`, status processing) → OCR w tle → pozycja „done"
z rozpoznanymi polami i **miniaturą zdjęcia** (punkt odniesienia) w sekcji
„Do zatwierdzenia" na ekranie Rachunki. Zatwierdzenie tworzy zwykły
`billPayment`; edycja prowadzi przez prefill formularza; odrzucenie kasuje
pozycję i miniaturę.

### 5. Pozycje oczekujące są lokalne i poza bilansem

Przechowywane w `settings` (`pendingBillScans`, JSON) jak koperta — poza
synchronizacją domową, backupem i całą matematyką budżetu. Do budżetu (i syncu)
wchodzą dopiero po zatwierdzeniu. Miniatury żyją w katalogu apki
(`bill_scans/`) i giną razem z pozycją.

### 5a. Archiwum rachunków — opcjonalne, lokalne, poza sync

Osobna funkcja (opt-in, toggle „Archiwum rachunków" w Asystencie AI): przy
**zatwierdzeniu** rachunku jego zdjęcie jest trwale kopiowane do publicznego
katalogu `Documents/<podfolder>` (default `Zostaje`) przez **MediaStore**
(Android 10+, bez uprawnień; starsze — zapis bezpośredni). Nazwa pliku
`RRRR-MM-DD_Wystawca_Kwota.jpg`. Archiwum to **worek plików** do przeglądania
w Plikach/Galerii — celowo NIE podpięty do pozycji budżetu, bo lokalna ścieżka
nie miałaby sensu na drugim urządzeniu. **Synchronizacja nadal nie przesyła
żadnych obrazów** (świadoma decyzja: brak obciążenia serwera).

### 6. Kontrakt danych silnik→klient

`{"rachunki":[{wystawca, tytul, kwota, waluta, terminPlatnosci,
dataWystawienia, rodzaj}]}` — kilka dokumentów na zdjęciu = kilka pozycji.
Parsowanie defensywne (`BillScanParser`): zepsuty JSON → pusta lista, kwoty
"1 234,56 zł" → liczba; `rodzaj` (prad/gaz/woda/...) mapowany na kategorię
użytkownika po słowach-kluczach nazwy.

## Konsekwencje

- (+) Zero chmury, zero kosztów za wywołanie, zero kluczy API.
- (+) Rachunek z błędną kwotą nie wejdzie do bilansu bez akceptacji człowieka.
- (−) Wymaga zainstalowanego silnika z modelem (3,4 GB) — bez niego przyciski
  skanowania prowadzą do instrukcji.
- (−) ~30–45 s na zdjęcie (CPU); GPU czeka na poprawkę w LiteRT-LM.
- (−) Duplikaty plików AIDL w kliencie muszą być identyczne z silnikiem
  (nowe metody tylko na końcu interfejsu).
- Wymóg trwały: silnik i wszyscy klienci na TYM SAMYM kluczu podpisu
  (dziś debug; przejście na release — wszystkie apki naraz).
