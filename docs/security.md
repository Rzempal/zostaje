# Bezpieczenstwo

> **Powiazane:** [Architektura](architecture.md) | [Baza Danych](database.md)

---

## Zasada glowna

**Dane finansowe nigdy nie opuszczaja urzadzenia w czytelnej formie.**

Aplikacja dziala domyslnie 100% offline. Nie ma kont ani logowania. Dane opuszczaja
urzadzenie tylko w swiadomie wlaczonych przypadkach:
1. **Eksport backupu** przez uzytkownika (`.zostaje`, dawniej `.subkarton`, AES-256-GCM).
2. **Kopia na koncie Google** (raz na dobe, zaszyfrowana — patrz nizej).
3. **Eksport arkusza** (XLSX/PDF) — JAWNY, na wyrazne zyczenie; tak udostepnia sie
   budzet drugiej osobie.

Synchronizacja budzetu domowego (relay E2E, ADR-009) zostala **usunieta** (ADR-035):
aplikacja nie laczy sie juz z serwerem relay.

---

## Przechowywanie danych

| Aspekt | Rozwiazanie |
|--------|-------------|
| Lokalna baza | Hive (NoSQL) -- pliki na urzadzeniu |
| Szyfrowanie at-rest | Hive nie szyfruje domyslnie -- dane w plaintext na dysku |
| Dostepu do danych | Sandboxing Androida/iOS -- inne aplikacje nie maja dostepu |
| Backup szyfrowany | AES-256-GCM z kluczem urzadzenia lub haslem uzytkownika |

### Wrazliwosc danych

Dane subskrypcji sa **umiarkowanie wrazliwe** -- nie sa to dane bankowe, ale zdradzaja wzorce wydatkow.

| Dane | Wrazliwosc | Ochrona |
|------|-----------|---------|
| Nazwy subskrypcji | Niska | Sandbox OS |
| Kwoty | Umiarkowana | Sandbox OS + szyfrowany backup |
| Daty odnowien | Niska | Sandbox OS |
| Historia uzycia | Niska | Sandbox OS |

---

## Szyfrowanie backupow

Referencja: `reference-code/services/backup_crypto_service.dart`

> **Zakres i semantyka importu ([ADR-021](adr/ADR-021-import-backupu-odtworzenie-vs-scalenie.md)):**
> plik (format v7) obejmuje subskrypcje, kategorie niedomyslne, metody platnosci,
> pozycje budzetu obu zakresow, stan odhaczonych platnosci, Planner („Na rachunki")
> oraz ustawienia uzytkownika z bialej listy (waluta, limit, tryb budzetu,
> powiadomienia, Asystent AI, archiwum, motyw). POZA plikiem: sciezki zdjec rachunkow
> (zdjec tam nie ma — byly by martwe linki), stan zwiniecia sekcji i pozycje
> oczekujace skanu.
> Import pyta o tryb: **Odtworz stan z pliku** (domyslny — czysci dane objete backupem)
> albo **Scal** (dokłada zawartosc pliku, pozycje spoza pliku zostaja). Haslo eksportu
> potwierdzane drugim polem — literowki nie da sie wykryc pozniej, bo plik otworzy sie
> tym blednym haslem.

### Format pliku backup

```
[4B Magic] [1B Version] [1B KeyType] [16B Salt] [12B IV] [NB Ciphertext] [16B GCM Auth Tag]
```

### Tryby szyfrowania ([ADR-024](adr/ADR-024-kopia-w-chmurze-google-i-kod-odzyskiwania.md))

| Tryb | Klucz | Przenosnosc | Uzycie |
|------|-------|-------------|--------|
| Kod odzyskiwania | 20 znakow, PBKDF2-SHA256 (100k) | Przenoszalny | **Domyslny eksport** i kopia w chmurze |
| Password | PBKDF2-SHA256 (100k iteracji) | Przenoszalny | Udostepnianie, migracja |
| Device Key | Android Keystore / iOS Keychain | Tylko to urzadzenie | **Tylko ODCZYT** starych plikow |

Kod odzyskiwania jest technicznie haslem (typ pliku `password`), wiec format sie
nie zmienil. Zastapil klucz urzadzenia, bo tamten ginal razem z telefonem — czyli
w jedynym scenariuszu, przed ktorym kopia ma chronic. Import probuje **cicho**
lokalnego kodu przed zapytaniem o haslo.

### Kopia na koncie Google — NIE jest E2E

| Aspekt | Opis |
|--------|------|
| **Co jedzie** | Ten sam zaszyfrowany plik `.zostaje` co kopia lokalna. **Bez zdjec rachunkow** |
| **Dokad** | Prywatna przestrzen aplikacji na Dysku (`appDataFolder`) — niewidoczna w interfejsie Dysku |
| **Sekret** | Kod odzyskiwania lezy **obok** kopii. Google technicznie ma klucz i szyfrogram — **swiadomy kompromis** na rzecz odzyskiwalnosci ([ADR-024](adr/ADR-024-kopia-w-chmurze-google-i-kod-odzyskiwania.md)) |
| **Sciezka prywatna** | Pozostaje: eksport „Eksportuj z haslem" |
| **Zakres OAuth** | `drive.appdata` — niewrazliwy, bez weryfikacji Google. Wiecej uprawnien nie prosimy |
| **Sejf na kod** | Block Store (uslugi Google Play), wymaga Androida 9+ i blokady ekranu |
| **Klucz podpisu APK** | Identyfikatory OAuth wisza na SHA-1 `debug.keystore` — utrata pliku zrywa polaczenie z Dyskiem u wszystkich |

Prywatnosc opisana dla uzytkownika: [privacy-policy.md](privacy-policy.md) pkt 5.

### Algorytm

- **Cipher:** AES-256-GCM (authenticated encryption)
- **Key derivation:** PBKDF2 z SHA-256, 100 000 iteracji, 32-byte key
- **IV:** 12 bajtow, losowy (SecureRandom)
- **Salt:** 16 bajtow, losowy

---

## Aktualizacje OTA

Referencja: `reference-code/services/update_service.dart`

| Aspekt | Rozwiazanie |
|--------|-------------|
| Zrodlo | Wlasny serwer (version.json + APK) |
| Weryfikacja | Porownanie versionCode |
| Transport | HTTPS |
| Integralnosc | Checksum w ota_update |

---

## Prywatnosc

### Co aplikacja NIE robi

- NIE zbiera danych analitycznych (zero telemetrii)
- NIE laczy sie z internetem (poza OTA check i opcjonalnym PDF exportem)
- NIE wymaga konta ani logowania
- NIE udostepnia danych podmiotom trzecim
- NIE uzywa reklam

### Uprawnienia Android

| Uprawnienie | Cel | Kiedy |
|-------------|-----|-------|
| `INTERNET` | Sprawdzanie aktualizacji OTA | Przy starcie (opcjonalne) |
| `REQUEST_INSTALL_PACKAGES` | Instalacja OTA update | Przy aktualizacji |
| `RECEIVE_BOOT_COMPLETED` | Wznowienie powiadomien po restarcie | Jesli notifications wlaczone |
| `POST_NOTIFICATIONS` | Przypomnienia o odnowieniach | Jesli notifications wlaczone |

---

## Disclaimer

> **Zostaje** jest narzedziem informacyjnym do sledzenia wydatkow na subskrypcje.
> Aplikacja NIE jest usluga finansowa, NIE udziela porad finansowych i NIE laczy sie
> z kontami bankowymi. Wszystkie dane sa wprowadzane recznie przez uzytkownika.

---

> **Ostatnia aktualizacja:** 2026-03-25
