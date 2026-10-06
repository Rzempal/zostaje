# 🚀 Deployment

> **Powiązane:** [Architektura](architecture.md) | [Baza Danych](database.md) | [Roadmap](roadmap.md)

---

## 📋 Dokumentacja Wdrożenia

Ten dokument opisuje proces wdrożenia aplikacji mobilnej (APK) oraz webowej.

### Skrypty Deploymentu

- `scripts/deploy.ps1` – Główny (i jedyny) skrypt do budowania i wysyłania APK na serwer.

#### Terminal command

DEV (kanal `internal`) — build + upload, bez bumpu wersji, bez tagu:

```powershell
.\scripts\deploy.ps1 -Channel internal -BumpType patch -ReleaseNotes "- opis zmian"
```

PROD (kanal `production`) — z bumpem wersji (minor/major) i opcjonalnym tagiem:

```powershell
.\scripts\deploy.ps1 -Channel production -BumpType minor -ReleaseNotes "- opis zmian" -CreateTag
```

> Podanie `-BumpType` i `-ReleaseNotes` daje tryb w pelni automatyczny (bez pytan
> interaktywnych). Bez nich skrypt pyta o typ wersji i release notes.

---

## Architektura APK: tylko 64-bitowe ARM

Buildy **release** (czyli wszystko, co idzie na serwer OTA) zawierają biblioteki
natywne wyłącznie dla `arm64-v8a` — architektury każdego współczesnego telefonu.
Wymaga tego dwóch ustawień naraz:

- `--target-platform android-arm64` w `deploy.ps1` — przycina biblioteki Fluttera,
- `ndk { abiFilters += "arm64-v8a" }` w bloku `release` w `android/app/build.gradle.kts`
  — przycina biblioteki natywne **wtyczek** (ML Kit OCR), które przychodzą z paczek
  AAR i flagi Fluttera nie respektują.

Efekt: APK 43 MB zamiast 112 MB, czyli tyle samo mniej do pobrania przy każdej
aktualizacji OTA.

> ⚠️ Taki APK **nie zainstaluje się** na starym 32-bitowym telefonie ani na
> emulatorze x86/x86_64. Buildy `debug` (`flutter run`) zostają pełne, więc praca
> na emulatorze działa normalnie.

---

## Nazewnictwo APK i kontrola wersji

APK ma **stałą nazwę** zależną tylko od kanału — na serwerze i w `releases/` jest
**jeden plik na kanał**, nadpisywany przy każdym deployu (bez mnożenia kopii):

| Kanał | Plik APK | Plik wersji |
| --- | --- | --- |
| `internal` (DEV) | `zostaje-dev_latest.apk` | `version-internal.json` |
| `production` (PROD) | `zostaje_latest.apk` | `version.json` |

**Kontrola wersji nie zależy od nazwy pliku.** OTA porównuje `versionCode` z pliku
`version*.json` z wersją zainstalowaną. `versionName` to `Major.Minor.yyMMDDcc`,
a **`versionCode` = `2 000 000 000 + yyMMDDcc`** i NIE zależy już od Major/Minor
([ADR-031](adr/ADR-031-numeracja-wersji-i-przejscie-na-google-play.md) — poprzedni
wzór przekraczał limit Androida od wersji 0.21). Nazwa pliku jest stała, ale:

- **Cache-busting:** `apkUrl` w `version*.json` ma dopisek `?v=<versionCode>`, więc
  każda wersja ma unikalny URL — OTA zawsze pobiera świeży plik mimo stałej nazwy.
- Skrypt automatycznie usuwa stare, wersjonowane APK danego kanału (lokalnie i na
  serwerze), zostawiając wyłącznie `_latest`.

---

## Wydanie jednym poleceniem: `ship.ps1`

Wydanie ma pięć kroków, które **muszą** iść w tej kolejności — i to jest jedyny
sposób, w jaki wydajemy:

```bash
.\scripts\ship.ps1 -Channel internal -Message "Opis zmian" -Notes "- co nowego"
```

```
[0/5] kontrola   gałąź (PROD tylko z main), token GitHuba, poprzedni release
                 opublikowany, flutter analyze, flutter test
[1/5] deploy     build + wysyłka na serwer (podbija pubspec, changelog, version.json)
[2/5] commit
[3/5] push
[4/5] release    tag na HEAD + GitHub Release z APK
[5/5] gotowe     „sprawdź na telefonie"
```

**Kontrola idzie PRZED czymkolwiek**, bo nieudany build po podbiciu wersji
zostawia repozytorium w połowie drogi, a brak tokenu wyszedłby dopiero po kilku
minutach kompilacji. Testy i analiza są jedyną bramką jakości przed telefonem —
gdy nie przechodzą, wydania nie ma.

| Parametr | Po co |
| --- | --- |
| `-BumpType patch\|minor\|major\|changelog` | domyślnie `patch` |
| `-DryRun` | wykonuje same kontrole, nic nie zmienia |
| `-SkipChecks` | pomija analizę i testy (świadomie) |
| `-SkipRelease` | wydaje bez publikacji na GitHubie (gdy GitHub nie odpowiada) |

### Blokady, które nie zależą od pamięci

- **Poprzednie wydanie PROD bez release'u na GitHubie → deploy się nie zaczyna.**
  Inaczej GitHub zostaje w tyle, a Obtainium proponuje aktualizację wstecz.
  DEV tylko ostrzega (bywa wypuszczany kilka razy pod rząd i tak nadpisuje sam siebie).
- **„GitHub nieosiągalny" ≠ „release nieopublikowany"** — skrypt rozróżnia te
  stany, bo mylenie ich albo blokuje wydanie bez powodu, albo przepuszcza rozjazd.
  „Nieopublikowany" to wyłącznie odpowiedź 404; brak odpowiedzi w limicie czasu
  jest ponawiany (3 próby), a gdy dalej nic — to „nieosiągalny". Do 2026-10-06
  pojedynczy przestój łącza blokował PROD komunikatem o braku release'u.
- **PROD tylko z `main`, DEV także z gałęzi roboczej.** Na gałęzi trwa większa
  przebudowa (Faza 16), a telefon testowy (osobna aplikacja „Zostaje DEV") musi
  dostawać jej wersje bez scalania do `main`, który w tym czasie zostaje wersją
  PROD. Push idzie na bieżącą gałąź, tag `dev-v…` wskazuje commit gałęzi.
  Uwaga na licznik dnia w numerze wersji: gałąź ma własną kopię
  `releases/version-internal.json`, więc DEV z `main` i z gałęzi tego samego dnia
  dostałyby ten sam numer — w czasie przebudowy DEV wydajemy tylko z gałęzi.
- **`publish-release.ps1` odmawia przy niezacommitowanych zmianach** — tag musi
  wskazywać commit, który zawiera wydaną wersję.
- **`deploy.ps1` przerywa, gdy `versionCode` przekroczyłby limit Androida**
  (ADR-031) — zamiast błędu Gradle po kilku minutach builda.

---

## GitHub Releases — źródło dla Obtainium

Stała nazwa pliku jest wygodna dla naszego OTA (wersję niesie `version*.json`),
ale **zewnętrzne instalatory nie mają skąd wziąć numeru wersji**. Obtainium
wpada wtedy w tryb „pseudo-wersji": liczy skrót pliku i pokazuje liczbę w rodzaju
`920366876` zamiast `0.21.26080210` — nie wie, co jest nowsze, tylko że plik się
zmienił.

Dlatego każde wydanie trafia dodatkowo do **GitHub Releases**, gdzie wersja stoi
w tagu, a APK jest załącznikiem z wersją w nazwie:

```bash
.\scripts\publish-release.ps1 -Channel production
```

| Kanał | Tag | Załącznik | Typ |
| --- | --- | --- | --- |
| `production` | `v0.21.26080210` | `zostaje_0.21.26080210.apk` | zwykłe wydanie |
| `internal` | `dev-v0.21.26080210` | `zostaje-dev_0.21.26080210.apk` | **pre-release** |

DEV jako pre-release, bo Obtainium domyślnie je pomija — kto śledzi PROD, nie
dostanie wydania testowego.

### Kolejność jest twarda

```
deploy.ps1  →  commit  →  publish-release.ps1
```

`deploy.ps1` podbija wersję w `pubspec.yaml`, changelog i `version*.json`, więc
release utworzony w środku deployu wskazywałby commit **sprzed** wydania. Skrypt
publikujący tworzy tag na `HEAD`, czyli dokładnie na kodzie, który poszedł do
użytkowników. (To ta sama pułapka, przez którą nie używamy `-CreateTag`
w `deploy.ps1`.)

### Ustawienie w Obtainium

- Źródło: adres repozytorium na GitHubie (typ „GitHub").
- **PROD:** pre-relesy wyłączone.
- **DEV:** pre-relesy włączone + filtr APK `zostaje-dev_`.
- Repozytorium prywatne wymaga tokenu w ustawieniach Obtainium.

### OTA i Obtainium działają obok siebie

Przy źródle GitHub **oba mechanizmy mówią tym samym numerem**: Obtainium
porównuje wersję z tagu z wersją zainstalowaną, którą czyta **z systemu**
(nie z własnej pamięci), a OTA porównuje `versionCode` z `version*.json`.
Kto by nie zaktualizował aplikacji — drugi mechanizm widzi zgodny stan. Wbudowane
OTA zostaje włączone.

To nie działało przy źródle „bezpośredni link do APK": stała nazwa pliku nie
niesie wersji, więc Obtainium liczył pseudo-wersję z hasza i porównywał liczbę
bez związku z `versionName` — stąd wieczna „dostępna aktualizacja".

> ⚠️ **Publikuj release od razu po deployu.** Jeśli GitHub zostanie w tyle za
> tym, co serwuje OTA, Obtainium zobaczy w systemie wersję nowszą niż ostatni
> release i może zaproponować aktualizację **wstecz**. `deploy.ps1` przypomina
> o tym na końcu.

> Przy przejściu na Google Play wbudowane OTA znika całkiem — zasady sklepu
> zabraniają samodzielnego instalowania kodu (ADR-031).

## Wdrożenie Mobile (Android)

### Wymagania

- **Flutter SDK**
- **WinSCP** (do automatycznego uploadu)
- Konfiguracja w pliku `.env`

### Konfiguracja .env

Stwórz plik `.env` w root projektu:

```ini
# --- Deployment Config ---
DEPLOY_HOST=your-server.example.com
DEPLOY_USER=your_username
DEPLOY_PASS=your_password
DEPLOY_PROTOCOL=sftp
DEPLOY_REMOTE_PATH=/home/your_username/domains/your-domain.example.com/public_html/releases/
DEPLOY_PUBLIC_URL=https://your-domain.example.com/releases
```

### Uruchomienie deploymentu

```powershell
./scripts/deploy.ps1
```

Parametry opcjonalne:

- `-Channel internal` / `-Channel production` (kanal `internal` = DEV)
- `-SkipBuild`
- `-SkipUpload`
- `-BumpType patch|minor|major|changelog` — pomija interaktywne pytanie o typ wersji
- `-ReleaseNotes "..."` — pomija interaktywne pytanie o release notes (wieloliniowe: `"- A`n- B"`)
- `-CreateTag` — tworzy tag git (tylko dla `production`)

Podanie `-BumpType` i `-ReleaseNotes` daje tryb w pelni automatyczny (bez `Read-Host`),
np. deploy na DEV jednym poleceniem:

```powershell
./scripts/deploy.ps1 -Channel internal -BumpType minor -ReleaseNotes "- Import/eksport Excel"
```

---

## Wdrożenie Web (Next.js)

### Platforma: Vercel

Aplikacja webowa jest wdrażana automatycznie po pushu na branch `main` przez integrację z Vercel.

---

## Checklist Przed Wdrożeniem

- [ ] Zaktualizowano `versionName` i `versionCode` w `pubspec.yaml`.
- [ ] Przeprowadzono testy manualne na urządzeniu fizycznym.
- [ ] Sprawdzono połączenie z API (jeśli dotyczy).

---

> 📅 **Ostatnia aktualizacja:** 2026-06-17
