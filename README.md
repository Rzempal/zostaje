# Zostaje

Mobilny tracker subskrypcji cyfrowych **oraz menedzer budzetu domowego**.
Zero logowania, 100% prywatnosci, offline-first.

---

## Czym jest Zostaje

Aplikacja mobilna do zarzadzania domowymi finansami: subskrypcje cyfrowe + budzet domowy. Cel: pokazac dokladnie gdzie ida pieniadze i ile zostaje na koniec miesiaca.

**Kluczowe funkcje:**
- Zero logowania, zero rejestracji -- 100% prywatnosci, wszystko na urzadzeniu
- **Plan roczny jak arkusz (ADR-035):** zakladka "Planowanie" — wiersz = pozycja
  (wplyw albo wydatek), kolumny = 12 miesiecy. Kazdy miesiac ma wlasna kwote,
  edytowana pojedynczo albo dla kilku zaznaczonych miesiecy naraz. Pozycja nie jest
  przypieta do roku (rata 09.2026–08.2027 to jedna pozycja); nowy rok powstaje
  z kopii poprzedniego. Filtr na rok pokazuje srednia miesieczna, na miesiac —
  kwoty tego miesiaca
- **Subskrypcje:** osobny modul z okresami probnymi, przypomnieniami i limitem;
  w planie sa sekcja liczona z ich cyklu (miesiac odnowienia = pelna kwota)
- **Pozyczki:** z karty kredytowej (wplyw w dniu uzycia, splata po okresie
  bezodsetkowym) i ratalne (wplyw w dniu wyplaty, raty; kwota, liczba rat, rata
  i RRSO — z trzech liczy sie czwarta; opcjonalny zakup tego dnia jako wydatek);
  liczone osobno jako "pozyczki netto" (ADR-036)
- **Budzet:** zakladka ze statystykami roku (srednio miesiecznie, wykres 12 miesiecy,
  kategorie, limity subskrypcji) i kalendarzem platnosci do odhaczania
- **Budzet osobisty i domowy:** dwa niezalezne plany, przelaczane jednym gestem;
  subskrypcje z przynaleznoscia osobista/domowa
- Przypomnienia o odnowieniach i trialach
- **Excel (.xlsx):** subskrypcje oraz plan jako tabela roku (zakladka na rok,
  wydatki jako liczby ujemne) — tak udostepnia sie budzet drugiej osobie;
  import dokleja pozycje
- Szyfrowany backup `.zostaje` (format v8: plan roczny + subskrypcje + stan
  platnosci); import pyta, czy **odtworzyc stan z pliku** czy **scalic** (ADR-021).
  Kopia automatycznie raz na dobe na koncie Google (ADR-024)

**Usuniete w przebudowie (ADR-035):** dziennik wydatkow "Biezace", skan paragonow
z lokalnym AI, Planner "Na biezace wydatki", przelewy miedzy budzetami, porownanie
planu z rzeczywistoscia i synchronizacja budzetu domowego. Dane sprzed przebudowy
leza nietkniete w bazie (powrot do poprzedniej wersji = zwykla aktualizacja
starszej rewizji z wyzszym numerem wersji).

**Filozofia:**
- Baza z "Karton z lekami" (APPteczka) -- ta sama architektura, inna domena
- Ewolucja wygladu: neumorfizm -> "Ledger Glass" (flat M3) -> "Aurora" (premium)
- Offline-first, dane lokalne

---

## Stack technologiczny

| Warstwa | Technologia |
|---------|-------------|
| Framework | Flutter (Dart) |
| UI | Material Design 3 -- "Aurora" (jeden ciemny motyw; wdrozenie Faza 6) |
| Baza danych | Hive (NoSQL, offline) |
| Szyfrowanie | AES-256-GCM (pointycastle) |
| Aktualizacje | OTA (ota_update) |
| Wykresy | fl_chart |
| Powiadomienia | flutter_local_notifications |
| Excel | excel (import/eksport .xlsx) |
| Platformy | Android (iOS w przyszlosci) |

---

## Struktura repozytorium

```
karton-subs/
├── apps/
│   └── karton_subs/            # Aplikacja Flutter (Faza 1 MVP gotowa)
│       ├── lib/
│       │   ├── main.dart
│       │   ├── config/         # AppConfig (build channels)
│       │   ├── models/         # Subscription, Category, UsageEvent, BudgetEntry
│       │   ├── services/       # StorageService (Hive), AnalyticsService, BudgetService
│       │   ├── controllers/    # SubscriptionController, BudgetController
│       │   ├── utils/          # cycle_math (normalizacja cyklu), expenses_filter (filtry list)
│       │   ├── theme/          # Motyw (AppTheme, AppColors) -- Aurora od Fazy 6
│       │   ├── screens/        # Budzet (statystyki + kalendarz), Planowanie (plan roczny), Ustawienia
│       │   └── widgets/        # Wspolne widgety list, wykresow i nawigacji
│       └── pubspec.yaml
├── docs/
│   ├── architecture.md         # Architektura systemu
│   ├── database.md             # Model danych
│   ├── design.md               # "Aurora" design system
│   ├── roadmap.md              # Plan rozwoju (Fazy 1-4)
│   ├── adr/                    # Architecture Decision Records
│   └── standards/              # Standardy kodu i procesu
├── reference-code/             # Wzorce z APPteczka (zrodlo Fazy 1)
└── scripts/
    └── deploy.ps1              # Deploy pipeline (build + version + upload OTA)
```

---

## Jak uruchomic

```bash
cd apps/karton_subs
flutter pub get
flutter run
# lub build APK:
flutter build apk --debug
```

---

## Dokumentacja

| Dokument | Opis |
|----------|------|
| [Design System](docs/design.md) | Paleta "Aurora", typografia, komponenty, reguly wydajnosci |
| [Architektura](docs/architecture.md) | Stack, warstwy, przeplywy danych |
| [Baza Danych](docs/database.md) | Model subskrypcji, kategorie, usage tracking |
| [Bezpieczenstwo](docs/security.md) | Prywatnosc danych, szyfrowanie backupow |
| [Roadmap](docs/roadmap.md) | Plan rozwoju (MVP -> Analytics -> Notifications) |
| [Wdrozenie](docs/deployment.md) | OTA pipeline, deploy script |

---

## Zrodlo

Ten seed kit pochodzi z projektu [APPteczka](https://github.com/Rzempal/APPteczka) -- "Karton z lekami".
Reusable infrastructure: ~40% kodu (serwisy, kontrolery, konfiguracja).

---

> **Ostatnia aktualizacja:** 2026-08-01
