# Roadmap

> **Powiazane:** [Architektura](architecture.md) | [Baza Danych](database.md) | [Design](design.md)

---

## Fazy rozwoju

| Faza | Nazwa | Status |
|------|-------|--------|
| 1 | MVP -- CRUD + Dashboard | ✅ Ukonczona (2026-03-26) |
| 1b | Szablony, backup, OTA, deploy | ✅ Ukonczona (2026-03-28) |
| 2 | Analytics + Wykresy | ✅ Ukonczona (2026-03-29) |
| 3 | Powiadomienia + Usage Tracking | 🟡 Czesciowo (przypomnienia gotowe; sledzenie uzycia porzucone; kalendarz otwarty) |
| 4 | Polish + Release | 🟡 Czesciowo (testy logiki gotowe; reszta otwarta) |
| 5 | Budzet domowy | ✅ Ukonczona (2026-06-17), poza „Powiadomieniami budzetu" |
| 6 | Redesign Aurora | ✅ Ukonczona (2026-06-17, prod 0.5); „jeden motyw" zastapiony w Fazie 6c |
| 7 | Synchronizacja budzetu domowego (relay E2E) | 🟡 Dziala w codziennym uzyciu, formalnie nadal PREVIEW |
| 8 | Rachunki jako realny log + koperta „Planner" | ✅ Ukonczona (2026-07-13) |
| 9 | Skanowanie rachunkow i paragonow | ✅ Ukonczona (2026-07-27, uzupelnienia do 2026-08-23) |
| 10 | Przebudowa sekcji aplikacji | ✅ Ukonczona (2026-08-09) |
| 11 | Kopia w chmurze + rozbudowa synchronizacji | ✅ Ukonczona (2026-08-04) |
| 12 | Wygoda i gestosc interfejsu | ✅ Ukonczona (2026-08-14) |
| 13 | Karta kredytowa + scalanie wydatkow | ✅ Ukonczona (2026-08-18) |
| 14 | Proces wydawania wersji | ✅ Ukonczona (2026-08-02) |
| 15 | Przejscie na Google Play | Planowana (kierunek bez terminu — ADR-031) |
| 16 | Przebudowa: plan roczny (ADR-035) | ✅ Na PROD od 0.27 (2026-10-08); zostaje E7 (Supabase) |

> **Stan na 2026-10-08:** przebudowa scalona do `main` i wydana na PROD (0.27).
> Ostatnia wersja sprzed przebudowy to `v0.26.26100600` — punkt powrotu (zbudowac
> te rewizje z wyzszym numerem wersji, ADR-035 §5). Zadania z „Nastepnych krokow"
> dotyczace synchronizacji, korekt i porownan plan/realne straciły sens — do
> przejrzenia.

---

## Faza 16: Przebudowa — plan roczny 🚧

**Cel:** budzet planowany rocznie jak arkusz (pozycje × miesiace), bez cykli,
korekt, przelewow wewnetrznych i porownan plan/realne — [ADR-035](adr/ADR-035-plan-roczny-pozycje-z-miesiacami.md).

| Etap | Zakres | Status |
|------|--------|--------|
| E0 | Galaz, wydanie DEV z galezi, odpornosc skryptu na przestoje GitHuba | ✅ 2026-10-06 |
| E1 | Model pozycji z miesiacami, konwersja (stare dane nietkniete), raport w Developer Tools | ✅ 2026-10-06 (do sprawdzenia na DEV) |
| E2 | Zakladka „Planowanie" (wplywy + wydatki + karta + subskrypcje), miesiace pozycji z zaznaczaniem, plan na kolejny rok; bez „Wplywow" i „Cyklicznych" | ✅ 2026-10-06 (do sprawdzenia na DEV) |
| E3 | „Budzet" = statystyki roku (srednie, trend, kategorie) + kalendarz platnosci | ✅ 2026-10-06 (do sprawdzenia na DEV) |
| E3b | Bez Biezacych i Plannera: koperta → pozycje planu, usuniety skan paragonow (ML Kit, silnik AI, usluga w tle), nawigacja Budzet / Planowanie / Ustawienia; APK 44,7 → 32,0 MB | ✅ 2026-10-07 (do sprawdzenia na DEV) |
| E4 | Kopia zapasowa v8, Excel jako tabela roku, usuniecie synchronizacji | ✅ |
| E5 | Sprzatanie kodu, testow i dokumentacji; statusy zastapionych ADR | ✅ |
| E6 | Przelaczenie PROD po akceptacji testow na DEV (0.27, 2026-10-08) | ✅ |
| E7 | Po migracji PROD: usuniecie danych synchronizacji domowej z Supabase (projekt „karton", wspoldzielony — tylko obiekty sync tej aplikacji, za zgoda wlasciciela) | ⏳ |

---

## Faza 1: MVP ✅

**Cel:** Dzialajaca aplikacja z podstawowym CRUD i podsumowaniem miesiecznym.

| Zadanie | Opis | Status |
|---------|------|--------|
| Setup projektu | Flutter, Hive, struktura katalogow, Ledger Glass theme | ✅ |
| Model danych | Subscription, Category, UsageEvent (Hive JSON) | ✅ |
| StorageService | CRUD subskrypcji + cache + analytics helpers | ✅ |
| Ekran: Dashboard | Total miesieczny, breakdown kategorii, ghost alert | ✅ |
| Ekran: Dodaj subskrypcje | Formularz dodaj/edytuj (nazwa, kwota, cykl, kategoria) | ✅ |
| Ekran: Lista subskrypcji | Sortowanie, filtrowanie po kategorii, pin/anuluj/usun | ✅ |
| Ekran: Ustawienia | Motyw (dark/light/system), waluta domyslna | ✅ |
| Quick log usage | Przycisk "Uzylem dzisiaj" na kartach | ✅ |
| Ghost detection | Algorytm: aktywna + >30 dni bez uzycia | ✅ |
| Quick Add | Predefiniowane szablony (Netflix, Spotify...) — `quick_add_templates.dart` | ✅ Faza 1b |
| Backup | Szyfrowany eksport/import (.zostaje) — `backup_crypto_service.dart` | ✅ Faza 1b |
| OTA | Aktualizacje z wlasnego serwera — `update_service.dart`, [ota-update-setup](ota-update-setup/) | ✅ Faza 1b |
| Deploy | Adaptacja deploy.ps1 (od 2026-08-02 nadrzedny `ship.ps1`, Faza 14) | ✅ Faza 1b |

---

## Faza 2: Analytics + Wykresy ✅

**Cel:** Wizualizacja wydatkow i inteligentne insighty.

| Zadanie | Opis | Status |
|---------|------|--------|
| AnalyticsService | Engine obliczen (monthly total, category breakdown, trends) | ✅ |
| Ekran: Analytics | Wykresy (fl_chart): spending over time, category pie/bar | ✅ |
| Yearly projection | "W tym tempie wydasz X PLN/rok" | ✅ |
| PDF raport | Eksport tabeli subskrypcji do PDF (Roboto TTF, polskie znaki) | ✅ |
| Multi-waluta | Przelicznik walut (statyczne kursy PLN/EUR/USD/GBP) | ✅ |
| Budget limit | Opcjonalny prog ostrzezen z UI w Ustawieniach | ✅ |
| Wspolna subskrypcja | Dzielenie kosztow na X osob | ✅ Bonus |
| Metoda platnosci | Przelew, Revolut, Karta, PayPal, BLIK... | ✅ Bonus |
| Zarzadzanie kategoriami | Edycja/dodawanie/usuwanie kategorii | ✅ Bonus |
| Status dot | Zielony/szary/czerwony zamiast ghost badge | ✅ Bonus |
| Developer Tools | Override daty (kanaly dev) do testowania ghost detection | ✅ Bonus |

---

## Faza 3: Powiadomienia + Usage Tracking 🟡

**Cel:** Proaktywne alerty i sledzenie uzycia.

> Sledzenie uzycia (log „Uzylem", koszt za uzycie, ghost) zostalo **usuniete** w Fazie 5b
> jako przerost formy — te pozycje sa porzucone, nie zalegle.

| Zadanie | Opis | Status |
|---------|------|--------|
| NotificationService | flutter_local_notifications (`notification_service.dart`) | ✅ (2026-04-05) |
| Renewal reminders | "Spotify odnowi sie za 3 dni" + przypomnienia o koncu triala; przelaczniki w Ustawienia → Powiadomienia | ✅ (2026-04-05) |
| Usage logging | Przycisk "Uzylem dzisiaj" (quick log) | ❌ Porzucone (Faza 5b) |
| Cost per use | Ranking: najdrozszy koszt za jedno uzycie | ❌ Porzucone (Faza 5b) |
| Ghost detection | "Nie korzystales z Amazon Prime od 45 dni" | ❌ Porzucone (Faza 5b) |
| Smart alerts | Tygodniowy przeglad ghost subscriptions | ❌ Porzucone (Faza 5b) |
| Calendar integration | Dodanie dat odnowien do kalendarza systemowego | ⏳ Otwarte (brak w kodzie) |

---

## Faza 4: Polish + Release 🟡

**Cel:** Produkcyjna jakosc, przygotowanie do publikacji.

| Zadanie | Opis | Status |
|---------|------|--------|
| Testy | Testy logiki: 45 plikow, ok. 400 przypadkow (budzet, sync, backup na prawdziwej bazie Hive, odczyt paragonow) | ✅ czesciowo — brak testow ekranow i testow calosciowych |
| Performance | Profilowanie; dluga lista Biezacych przy „Wszystkie lata" buduje sie w calosci | ⏳ Do obserwacji |
| Accessibility | WCAG 2.1 AA audit; wiersz listy ~44 px (ponizej zalecanych 48 px) | ⏳ Otwarte |
| Onboarding | Ekran powitalny z kluczowymi funkcjami | ⏳ Otwarte (brak w kodzie) |
| Landing page | Strona `/aplikacje/zostaje` w repo `com` (dzis 404; wskazywana tez przez Google Cloud) | ⏳ Otwarte |
| Polityka prywatnosci | [privacy-policy.md](privacy-policy.md) | ✅ szkic w repo |
| Google Play | Przeniesione do Fazy 15 (ADR-031) | ➡️ Faza 15 |

---

## Faza 5: Budzet domowy

**Cel:** Rozszerzenie z trackera subskrypcji na menedzer budzetu domowego —
wplywy, koszty stale (rachunki), koszty cykliczne, wieksze wydatki jednorazowe.

> **ADR:** [ADR-004 Model budzetu domowego](adr/ADR-004-model-budzetu-domowego.md)
> — jeden model `BudgetEntry`, osobno od subskrypcji, hybryda czasu.

| Zadanie | Opis | Status |
|---------|------|--------|
| Model BudgetEntry | 4 typy: income/bill/recurringCost/oneTimeExpense | ✅ |
| cycle_math.dart | Wspolna normalizacja cyklu (dedup z Subscription) | ✅ |
| Storage + box | `budget_entries` + CRUD (wzorzec istniejacy) | ✅ |
| BudgetService | Wplywy, koszty (+subskrypcje), surplus, bilans miesiaca | ✅ |
| BudgetController | Stan + nasluch SubscriptionController | ✅ |
| Zakladka Budzet | Hero "zostaje/mies", wplywy/koszty, listy pozycji | ✅ B1 |
| Wydatki jednorazowe | Selektor miesiaca + bilans + lista per miesiac | ✅ B2 |
| Backup v3 | Eksport/import obejmuje `budgetEntries` | ✅ |
| Testy BudgetService | Normalizacja, surplus, bilans, konwersja walut | ✅ |
| Kategorie budzetu | Oznaczanie wydatkow + filtr listy (wspolna lista kategorii) | ✅ B3 (Faza 5e) |
| Powiadomienia budzetu | Alert przekroczenia / nadchodzacy duzy wydatek (w kodzie brak; jest tylko wizualny pasek plan vs realny, ADR-030) | ⏳ Otwarte |

### Faza 5b: Restrukturyzacja nawigacji + Excel budzetu (2026-06-16)

| Zadanie | Opis | Status |
|---------|------|--------|
| 4 zakladki | Dashboard / Subskrypcje / Budzet / Ustawienia (usunieto Analitykę) | ✅ |
| Nowy Dashboard | Pelny przeglad budzet + subskrypcje | ✅ |
| Subskrypcje | Pod-zakladki Lista / Statystyki (hero, trend, kategorie, limit, triale) | ✅ |
| Excel w domenach | Eksport = CTA w naglowku; import pod „Dodaj" (subskrypcje + budzet) | ✅ |
| Excel budzetu | Nowy arkusz + parser (typ, miesiac) + testy | ✅ |
| Usuniete funkcje | ghost, koszt-za-uzycie, prognoza-karta, log „Uzylem" (przerost formy) | ✅ |

> Pola modelu `usageLog`/`isGhost` pozostaja uspione (zgodnosc danych); pelna czystka — opcjonalnie pozniej.
> Uklad zakladek z tej fazy jest historyczny — obecny uklad patrz Faza 10.

### Faza 5c: Kalendarz przeplywow + jednorazowy wplyw (2026-06-17)

| Zadanie | Opis | Status |
|---------|------|--------|
| Reorder Dashboardu | Subskrypcje nad widokiem miesiaca | ✅ |
| Kalendarz przeplywow | Siatka miesiaca z kropkami wplyw/wydatek; tap dnia → pozycje dnia | ✅ |
| Kotwica daty | Reuse `startDate`; formularz zbiera date (jednorazowy dokladna, cykliczny opcjonalna) | ✅ |
| Rzutowanie wystapien | `occurrencesInRange` (clamp dnia 31, fix DST); subskrypcje z `startDate`+cyklu | ✅ |
| Jednorazowy wplyw | Typ `oneTimeIncome` (premia/bonus) z data; podnosi bilans miesiaca | ✅ |
| Testy | `occurrencesInRange`, `calendarForMonth`, bilans z jednorazowym wplywem | ✅ |

> Migracja: stare pozycje budzetu bez `startDate` nie pojawia sie na kalendarzu do czasu edycji.
> Excel pozycji jednorazowych pozostaje na poziomie miesiaca (import → dzien 1.).

### Faza 5d: Budzet domowy (osobisty + wspolny) (2026-06-17)

**Cel:** Wspolna kasa domowa obok osobistej; przyszla synchronizacja tylko domowego.

> **ADR:** [ADR-006 Budzet domowy jako osobny zbior](adr/ADR-006-budzet-domowy-osobny-zbior.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Osobny box domowy | `household_budget_entries` + `BudgetScope`; storage/controller per zakres | ✅ |
| Przelacznik Osobisty/Domowy | Budzet + Dashboard; jeden silnik liczy oba | ✅ |
| Przelew do domowego | Typ `householdTransfer` + lustro `income` (para `linkId`, kaskada) | ✅ |
| Czlonek rodziny | Recznie jako wplyw w domowym („Wklad — imie") | ✅ |
| Subskrypcje per zakres | `SubscriptionScope` + filtr w Liscie i Statystykach + formularz | ✅ |
| Backup v4 + Excel | `householdBudgetEntries` + kolumna „Zakres"; testy | ✅ |
| Synchronizacja online domowego | Relay w chmurze + E2E, BEZ kont (parowanie QR + haslo) | ✅ Faza 7 (preview) |

> Niesymetria swiadoma: budzet = osobny box (wymog sync), subskrypcje = pole `scope`.
> Synchronizacja: relay E2E bez kont (nie backend z kontami) — patrz Faza 7.

---

### Faza 5e: Kategorie wydatkow + rachunek zmienny (2026-06-17)

**Cel:** Domkniecie kategorii budzetu (B3) oraz rozdzielenie zdublowanych typow
`bill` i `recurringCost`.

> **ADR:** [ADR-008 Rachunek zmienny: surplus (plan) vs bilans miesiaca (realny)](adr/ADR-008-rachunek-zmienny-surplus-vs-bilans.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Kategorie wydatkow budzetu | Wspolna lista kategorii; oznaczanie wydatkow + filtr listy budzetu | ✅ B3 (prod 0.6) |
| Kategoria w Excelu budzetu | Kolumna „Kategoria" w eksporcie/imporcie (dopasowanie po nazwie) | ✅ |
| Rachunek zmienny | `bill`: kwota bazowa + korekty per miesiac (`monthOverrides`: inna data/kwota) | ✅ (dev 0.6) |
| Rozdzielenie bill vs recurringCost | `recurringCost` = staly; `bill` = zmienny; podpowiedzi w UI | ✅ |
| Strażnik invariantu | Test: korekta zmienia bilans miesiaca, NIE surplus (ADR-008) | ✅ |

> Korekty rachunku NIE wplywaja na „zostaje/mies" (plan = kwota bazowa) — tylko na
> bilans danego miesiaca i kalendarz. Excel niesie tylko kwote bazowa (1. iteracja).

---

### Faza 5g: Sortowanie/filtr/grupowanie + sekcja przelewu + zwijanie Dashboardu (2026-06-17)

> **ADR:** [ADR-008](adr/ADR-008-rachunek-zmienny-surplus-vs-bilans.md) (aktualizacja)

| Zadanie | Opis | Status |
|---------|------|--------|
| Sortowanie | Ikona A→Z / kwota malejaco (przelacznik w AppBar) | ✅ |
| Filtr typu | Pasek chipow (jak kategorie), linijke nizej | ✅ |
| Grupowanie | Ikona wł/wył; pod-naglowki wg typu w kubelkach z >1 typem | ✅ |
| Sekcja „Przelew wewnetrzny" | Przelew do domowego wydzielony z Kosztow | ✅ |
| Korekta przelewu | `monthOverrides` dla przelewu; kaskada do lustra; delta ze znakiem (wplyw +, wydatek −) | ✅ |
| Sumy sekcji | Naglowek z suma (po filtrach), znormalizowana przez cykl, wyrownana do prawej | ✅ |
| Zwijanie Dashboardu | Kalendarz i lista Platnosci full/kompakt (trwale) | ✅ |

---

### Faza 5f: Platnosci, rata, lossless Excel/backup (2026-06-17)

> **ADR:** [ADR-008](adr/ADR-008-rachunek-zmienny-surplus-vs-bilans.md) (aktualizacja)

| Zadanie | Opis | Status |
|---------|------|--------|
| Metoda platnosci auto/manual | `PaymentMethod.isAutomatic` + przelacznik; `BudgetEntry.paymentMethod` | ✅ |
| Kolor kalendarza | Wydatek auto = zolty, manual = czerwony, wplyw = zielony | ✅ |
| Sekcja „Platnosci" | Manualne wydatki miesiaca, checkbox + przekreslenie (stan lokalny per miesiac) | ✅ |
| Typ „Rata" (`installment`) | Start + liczba rat / data ostatniej; koszt mies. z koncem; znika z surplus po splacie | ✅ |
| Lossless Excel budzetu | Kolumny Metoda / Data startu / Liczba rat / Korekty (JSON) | ✅ |
| Backup v5 | Obejmuje stan „wykonane" platnosci (`payment_done`) | ✅ |
| Wiecej ikon kategorii | dziecko, pies, zakupy, jedzenie, rachunki, prezent | ✅ |

---

## Faza 6: Redesign Aurora

**Cel:** Przejscie z systemu „Ledger Glass" (light + dark + przelacznik) na **„Aurora"** —
jeden uniwersalny ciemny motyw, premium fintech, gradient aurora + powierzchnie „frost".

> **ADR:** [ADR-005 Aurora — jeden ciemny motyw](adr/ADR-005-aurora-jeden-ciemny-motyw.md)
> &middot; **Spec:** [design.md](design.md) (gotowy 2026-06-17). Zakres: tylko prezentacja, logika bez zmian.
>
> ⚠️ Decyzja „jeden ciemny motyw" zastapiona 2026-06-23 przez
> [ADR-010](adr/ADR-010-wiele-motywow-tryb-x-kolor.md) — patrz Faza 6c. Estetyka Aurora zostaje.

| Zadanie | Opis | Status |
|---------|------|--------|
| design.md Aurora | Pelna specyfikacja tokenow + reguly wydajnosci | ✅ |
| ADR-005 | Decyzja: jeden ciemny motyw, „frost" zamiast blur | ✅ |
| app_theme.dart | Jeden ciemny ThemeData; tokeny gradient/frost/akcenty | ✅ |
| theme_provider | Usuniecie przelacznika Dark/Light/System | ✅ |
| Ustawienia | Usuniecie sekcji „Motyw" + wiersze jako karty frost | ✅ |
| AuroraBackground | Wrapper Scaffoldu: gradient + poswiaty | ✅ |
| FrostCard | Karty bez BackdropFilter (przezroczystosc + border) | ✅ |
| GlassNavBar | Plywajaca pigulka — jedyny prawdziwy blur | ✅ |
| MetricTile + GradientAmount | Siatka metryk + kwota-bohater (ShaderMask) | ✅ |
| Menu „Dodaj" | Wysuwane w gore nad przyciskiem (AuroraAddMenu) zamiast bottom sheet | ✅ |
| Wykresy | Paleta Aurora + dymki (trend liniowy, breakdown, limit) | ✅ |
| Tokeny + straznik | AppColors.onAccent/AppRadii, pelne pokrycie motywem, check_design_tokens.ps1 | ✅ ADR-007 |

### Faza 6b: Personalizacja Dashboardu (2026-06-17)

| Zadanie | Opis | Status |
|---------|------|--------|
| Sekcje full/compact | Klik w „Podsumowanie" / „Subskrypcje" zwija/rozwija (chevron, animacja) | ✅ |
| Trwalosc | 2 flagi w StorageService — stan zostaje po restarcie | ✅ |

### Faza 6c: Motywy, Dashboard Saldo, nowy navbar (2026-06-20 – 2026-07-09)

> **ADR:** [ADR-010 Wiele motywow — Tryb x Kolor](adr/ADR-010-wiele-motywow-tryb-x-kolor.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Rebranding | Nowa nazwa „Zostaje", ikona, identyfikator `app.michalrapala.zostaje` | ✅ (2026-06-20) |
| Baner aktualizacji | Dashboard informuje o nowej wersji (OTA) | ✅ |
| System motywow | Tryb (ciemny/jasny/systemowy) x kolor + Material You; ekran Wyglad | ✅ |
| Dashboard Saldo | Karta Saldo, rozbicie bilansu, filtr czasu w Budzecie | ✅ |
| Navbar | Animowana pigulka aktywnej zakladki, separator Ustawien | ✅ |
| Podsumowanie miesiaca | Pelna lista wplywow/wydatkow miesiaca; sekcja „Platnosci automatyczne" | ✅ (2026-07-09) |
| Naprawa animacji | Tlo montowane raz, przejscia ekranow bez „ducha" tresci | ✅ |

---

## Faza 7: Synchronizacja budzetu domowego (relay E2E)

**Status: 🟡 Dziala w codziennym uzyciu, formalnie nadal PREVIEW.** Budzet domowy jest
realnie synchronizowany miedzy dwoma telefonami gospodarstwa (handoff 2026-08-04 opisuje
parowanie z telefonem zony i scenariusz wymiany telefonu). Mimo to w kodzie nadal jest
badge „PREVIEW" w Ustawieniach i ostrzezenie „Funkcja w wersji preview" na ekranie
synchronizacji, a nigdzie nie zapisano formalnego zaliczenia listy z handoffu 2026-06-18
(skan QR kamera, obieg A↔B, zgoda na kamere, potwierdzenie, ze budzet osobisty sie NIE
synchronizuje). Do zrobienia: odhaczyc te liste i zdjac oznaczenie (zadanie 11).

**Cel:** Wspoldzielenie budzetu domowego miedzy urzadzeniami czlonkow gospodarstwa,
bez kont, z parowaniem QR + haslo. Tylko box domowy; osobiste zostaja lokalne.

> **ADR:** [ADR-009 Synchronizacja budzetu domowego — relay E2E](adr/ADR-009-synchronizacja-budzetu-domowego-relay-e2e.md)
> &middot; **Bezpieczenstwo:** [security.md](security.md) (sekcja „Synchronizacja budzetu domowego")

| # | Zadanie | Opis | Status |
|---|---------|------|--------|
| 0 | ADR + security.md | Decyzja na papierze: relay E2E, wyjatek od „zero cloud" | ✅ |
| 1 | Model danych | `BudgetEntry`: `updatedAt` + `deleted` (nagrobek); addytywnie | ✅ |
| 2 | Klucz z hasla | `SyncCryptoService` (PBKDF2 + AES-256-GCM, klucz wspolny) | ✅ |
| 3 | Parowanie UI | „Dodaj czlonka" (QR + haslo) / „Dolacz" (skan + haslo) | ✅ |
| 4 | SyncService + scalanie | `SyncMerge` (LWW + nagrobki) + `SyncService` (pull/scal/push CAS) | ✅ |
| 5 | Skrzynka Supabase | Tabela `sync_envelopes` zamknieta RLS + RPC `sync_pull`/`sync_push` | ✅ |
| 6 | Wyzwalacze | Po zmianie domowego (debounce 2s) + przy starcie + reczny | ✅ |
| 7 | Przelew / lustro | Lustro wkladu synchronizuje sie jak pozycja; read-only u partnera (`isLinked`) | ✅ |
| 8 | Sync w interfejsie | Przycisk/gest przeciagniecia w dol; czytelny komunikat „serwer nie odpowiada" | ✅ (2026-07-09, gest 2026-07-31) |
| 9 | Planner i slowniki w sync | ADR-022, ADR-025 — patrz Faza 11 | ✅ |
| 10 | Kod QR po sparowaniu | Kazdy sparowany telefon moze pokazac kod QR (wymiana telefonu bez zakladania gospodarstwa od nowa) | ✅ (2026-08-04) |
| 11 | Formalny test 2 urzadzen + zdjecie PREVIEW | Lista z handoffu 2026-06-18, usuniecie badge i ostrzezenia | ⏳ Otwarte |

**Swiadome granice v1:** scalanie „ostatnia zmiana wygrywa" per pozycja (bez CRDT);
brak historii „kto co zmienil"; dostep do skrzynki po sekrecie, nie po koncie;
darmowy tier Supabase uspia projekt po ~tygodniu i **nie budzi sie sam** (objaw: „Serwer
nie odpowiada"; budzenie recznie w panelu Supabase).

> **Zaleznosc — APPteczka („Karton z lekami"):** relay korzysta z tego samego, darmowego
> projektu Supabase co synchronizacja APPteczki. Przekroczenie darmowego limitu przez jedna
> aplikacje zablokuje obie. Roadmapa APPteczki (`APPteczka/docs/roadmap.md`, etap E2)
> planuje: osobne projekty Supabase dla Kartona i Zostaje, limity i alarm zuzycia, „budzik"
> dla usypiajacego sie projektu, docelowo wlasny przekaznik na Hostido
> (`sync.michalrapala.app`) z nowym formatem paczki. Zmiana adresu lub formatu po stronie
> APPteczki wymaga odpowiadajacej zmiany i wydania Zostaje.

**Komponenty (kod):** `lib/services/sync_crypto_service.dart` (szyfrowanie),
`lib/services/sync_merge.dart` (scalanie + snapshot), `lib/services/sync_service.dart`
(orkiestracja + RPC + przechowywanie pary), `lib/screens/household_sync_screen.dart`
(UI parowania). Testy: `sync_crypto_test`, `sync_merge_test`, `sync_service_test`,
`budget_sync_fields_test`.

---

## Faza 8: Rachunki jako realny log + koperta „Planner" ✅ (2026-07-09 – 2026-07-13)

> **ADR:** [ADR-011](adr/ADR-011-rachunki-realny-log-i-scalenie-typow-cyklicznych.md),
> [ADR-012](adr/ADR-012-koperta-na-rachunki-lista-pozycji.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Rachunek = realny log | Nowy typ `billPayment` — datowany, juz oplacony wydatek | ✅ |
| Scalenie typow cyklicznych | Jeden typ kosztu cyklicznego z korektami miesiecznymi | ✅ |
| Koperta „Na rachunki" | Lista pozycji (nazwa + kwota + metoda); pozniej nazwana „Planner" | ✅ |
| Statystyki w Planie, kompaktowe platnosci | Razem z edycja „w miejscu" | ✅ |
| Swipe zakresu, kaskady slownikow, kolory kategorii | Przelaczanie Osobisty/Domowy gestem | ✅ |

---

## Faza 9: Skanowanie rachunkow i paragonow ✅ (2026-07-24 – 2026-08-23)

**Cel:** Zdjecie / zrzut ekranu / „Udostepnij" z innej aplikacji → gotowy wydatek do
zatwierdzenia. Wszystko lokalnie na telefonie (zero chmury).

> **ADR:** [ADR-013](adr/ADR-013-skan-rachunkow-lokalny-silnik-ai.md) (lokalny silnik AI),
> [ADR-014](adr/ADR-014-tryb-budzetu-osobisty-domowy-oba.md) (tryb budzetu),
> [ADR-015](adr/ADR-015-przycinanie-zdjecia-rachunku-ucrop.md) (przycinanie),
> [ADR-016](adr/ADR-016-skan-rachunku-usluga-pierwszoplanowa.md) (skan w tle),
> [ADR-017](adr/ADR-017-szybka-sciezka-ocr-przed-silnikiem-ai.md) (OCR + reguly przed AI)

| Zadanie | Opis | Status |
|---------|------|--------|
| Skan lokalnym silnikiem AI | Asystent AI (wlaczany w Ustawieniach), silnik w osobnej aplikacji `karton-ai` | ✅ |
| Tryb budzetu | Osobisty / Domowy / oba — steruje przelacznikiem i swipe | ✅ |
| Przycinanie zdjecia | Na wejsciu, w poczekalni i w edycji | ✅ |
| Skan w tle | Usluga pierwszoplanowa, wybudzanie uspionego silnika, kotwica roku w dacie | ✅ |
| Szybka sciezka OCR | Zwykly odczyt tekstu + reguly przed AI; faktury czytane bez silnika AI | ✅ |
| Archiwum rachunkow | Osobna sekcja Ustawien, zdjecia w `Documents` | ✅ |
| Poprawki odczytu paragonow | Stawka VAT nie jest kwota, numer nie jest nazwa; naprawa regresji skanu | ✅ (2026-08-10) |
| Potwierdzenia z portfela telefonu | Szybkie czytanie potwierdzen platnosci (uklad dwukolumnowy); podglad surowego odczytu w Developer Tools | ✅ (prod 0.26.26082300) |

---

## Faza 10: Przebudowa sekcji aplikacji ✅ (2026-07-26 – 2026-08-09)

**Cel:** Jasny podzial „co gdzie jest". Obecne zakladki: **Budzet · Wplywy · Biezace ·
Cykliczne · Ustawienia**; subskrypcje sa sekcja w „Cyklicznych", Planner ma wlasny ekran.

> **ADR:** [ADR-018](adr/ADR-018-scalenie-wydatku-jednorazowego-z-rachunkiem.md),
> [ADR-019](adr/ADR-019-podzial-sekcji-aplikacji.md),
> [ADR-020](adr/ADR-020-cykl-wybrane-miesiace-roku.md),
> [ADR-023](adr/ADR-023-rozlaczne-strumienie-wydatkow.md),
> [ADR-027](adr/ADR-027-subskrypcje-jako-sekcja-wydatkow.md),
> [ADR-028](adr/ADR-028-plan-vs-rzeczywistosc-na-wykresach.md),
> [ADR-029](adr/ADR-029-podsumowanie-roczne-i-poczatek-ewidencji.md),
> [ADR-030](adr/ADR-030-pasek-plan-vs-realny-sila-przekroczenia.md),
> [ADR-032](adr/ADR-032-biezace-i-cykliczne-zamiast-rachunkow.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Scalenie wydatku jednorazowego z rachunkiem | Jeden datowany wydatek (ADR-018) | ✅ |
| Podzial sekcji, Wplywy jako zakladka | ADR-019 — wszystkie 3 etapy | ✅ |
| Cykl „wybrane miesiace roku" | Zamiast „co N miesiecy"; cykle niedzielace 12 swiadomie niedostepne | ✅ |
| Przebudowa Planu i bilansu miesiaca | Rozlaczne strumienie wydatkow jako podstawa wykresow (ADR-023) | ✅ |
| Subskrypcje jako sekcja wydatkow | Bez osobnej zakladki (ADR-027) | ✅ |
| Plan vs rzeczywistosc, podsumowanie roczne | Wykresy, poczatek ewidencji, pasek sily przekroczenia | ✅ |
| Grupy okresow w Planie, tryb Oba na trendzie | Zwijane grupy | ✅ |
| „Biezace" i „Cykliczne" zamiast „Rachunkow" | Nowe nazwy zakladek i ikon (ADR-032) | ✅ (prod 0.22) |
| Sortowanie po kwocie, trwaly widok sekcji miesiaca | | ✅ (prod 0.24) |

---

## Faza 11: Kopia w chmurze + rozbudowa synchronizacji ✅ (2026-07-26 – 2026-08-04)

> **ADR:** [ADR-021](adr/ADR-021-import-backupu-odtworzenie-vs-scalenie.md),
> [ADR-022](adr/ADR-022-planner-w-synchronizacji-domowej.md),
> [ADR-024](adr/ADR-024-kopia-w-chmurze-google-i-kod-odzyskiwania.md),
> [ADR-025](adr/ADR-025-slowniki-w-synchronizacji-domowej.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Import backupu: odtworzenie vs scalenie | Uzytkownik wybiera; odtworzenie czysci tylko obszary obecne w pliku | ✅ |
| Ustawienia w backupie | Format v7 | ✅ |
| Planner w synchronizacji | ADR-022 | ✅ |
| Kopia na koncie Google | Kopia na Dysku + kod odzyskiwania zamiast klucza urzadzenia | ✅ (prod 0.13) |
| Slowniki w synchronizacji | Kategorie i metody platnosci wspolne w gospodarstwie | ✅ |
| Przenoszenie rachunku Osobisty ↔ Domowy | | ✅ |
| Testy backupu na prawdziwej bazie | Odtworzenie vs scalanie, wersje formatu, szyfrowanie | ✅ |
| Eksport XLSX/PDF i import Excela w Ustawieniach | | ✅ (prod 0.23) |
| Kod QR po sparowaniu | Patrz Faza 7, zadanie 10 | ✅ |

---

## Faza 12: Wygoda i gestosc interfejsu ✅ (2026-08-01 – 2026-08-14)

> **ADR:** [ADR-026 Gestosc interfejsu](adr/ADR-026-gestosc-interfejsu-bez-paskow-tytulu.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Bez paskow tytulu | Wiecej miejsca na tresc, wspolny pasek zakresu | ✅ (prod 0.15) |
| Listy dwuliniowe | Separatory zamiast kart, kategoria w drugiej linii | ✅ |
| Filtry na Biezacych | Rok/miesiac, kategorie, sortowanie w pasku filtrow | ✅ |
| Polskie okna systemowe | Wybor daty itp. po polsku | ✅ |
| Zaznaczanie wielu pozycji | Dlugie przytrzymanie → kategoria / metoda / data / usuniecie naraz | ✅ (2026-08-02) — **bez subskrypcji** |
| Zwijanie biezacych do sumy | W Bilansie miesiaca | ✅ |
| Pigulka „Anuluj / Zapisz" | Stale miejsce zapisu w formularzach | ✅ (prod 0.26.26081400) |

---

## Faza 13: Karta kredytowa + scalanie wydatkow ✅ (2026-08-09 – 2026-08-18)

> **ADR:** [ADR-033](adr/ADR-033-karta-kredytowa-pozyczka-i-splata.md),
> [ADR-034](adr/ADR-034-scalanie-wydatkow-i-zwijanie-splat-karty.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| Karta kredytowa jako metoda platnosci | Zakup karta = pozyczka + splata, spiete ze soba | ✅ (prod 0.25) |
| Jedna ikona metody platnosci wszedzie | | ✅ |
| Scalanie wydatkow w jeden wpis | Z zaznaczenia wielu pozycji | ✅ (prod 0.26.26081800) |
| Zwijanie splat karty | Jeden wiersz z suma; osobna grupa pozyczek gotowkowych | ✅ |
| Splata czesciowa | Odhaczenie jest „wszystko albo nic" per pozycja | ❌ Swiadome ograniczenie (ADR-034) |
| Wskaznik „suma zadluzenia karty" | Wymaga decyzji: cale zadluzenie czy kwota wymagalna | ⏳ Odlozone |

---

## Faza 14: Proces wydawania wersji ✅ (2026-07-26 – 2026-08-02)

> **ADR:** [ADR-031 Numeracja wersji i przejscie na Google Play](adr/ADR-031-numeracja-wersji-i-przejscie-na-google-play.md)
> &middot; [deployment.md](deployment.md)

| Zadanie | Opis | Status |
|---------|------|--------|
| APK tylko pod 64-bitowe ARM | 43 MB zamiast 112 MB | ✅ |
| Nowa numeracja wersji | `versionCode = 2 000 000 000 + rrMMDDnn` (ominiecie limitu Androida) | ✅ |
| Jedno polecenie wydania | `ship.ps1` z kontrolami i ponawianiem operacji sieciowych | ✅ |
| GitHub Releases + Obtainium | Wydania widoczne dla zewnetrznego instalatora, obok wlasnego OTA | ✅ |

---

## Faza 15: Przejscie na Google Play (planowana)

**Cel:** Publikacja w sklepie. Kierunek przyjety w ADR-031, **bez harmonogramu**.
Przejscie oznacza instalacje od zera (inny podpis), wiec kolejnosc krokow chroni dane.

| Zadanie | Opis | Status |
|---------|------|--------|
| Klucz podpisu release | Dzis APK aplikacji i silnika AI sa na kluczu debug; zmiana musi objac obie naraz | ⏳ |
| Konto dewelopera Google Play | Oplata jednorazowa; wspolne z APPteczka | ⏳ |
| Polityka prywatnosci + formularz danych (Data safety) | Szkic: [privacy-policy.md](privacy-policy.md); opisac kopie na Dysku i relay | ⏳ |
| Wylaczenie OTA w buildzie sklepowym | Wymog zasad Play | ⏳ |
| Komunikat migracyjny | Ostatnie wydanie OTA: kopia → instalacja z Play → odtworzenie | ⏳ |
| Reset numeracji | `1.0.0`, versionCode od 1 | ⏳ |
| Silnik AI a sklep | Decyzja wspolna z APPteczka (jej etap E3): wspolny kod czy `karton-ai` poza sklepem | ⏳ |
| Synchronizacja po migracji | Wspolnie z APPteczka E2: osobny projekt Supabase / nowy przekaznik | ⏳ |

---

## Nastepne kroki (stan na 2026-10-04)

Zebrane z handoffow sesji, ADR-ow i weryfikacji kodu. Kolejnosc = sugerowany priorytet.

**Domkniecie rozpoczetego**
1. Formalny test synchronizacji na 2 telefonach + zdjecie oznaczenia PREVIEW (Faza 7).
2. Odciazenie wspolnego Supabase z APPteczka — osobny projekt dla Zostaje albo przekaznik
   z etapu E2 APPteczki; do tego czasu reczne budzenie uspionego projektu.
3. Sprzatniecie osieroconej skrzynki starego gospodarstwa na relayu (nieszkodliwa, ale smiec).

**Funkcje**
4. Powiadomienia budzetu — alert przekroczenia planu / nadchodzacy duzy wydatek (Faza 5).
5. Daty odnowien subskrypcji w kalendarzu systemowym (Faza 3).
6. Zaznaczanie wielu pozycji takze dla subskrypcji (ADR-027).
7. Wskaznik „suma zadluzenia karty" (Faza 13) — po decyzji, co ma pokazywac.

**Jakosc**
8. Odczyt faktur sprawdzony na zdjeciach z aparatu, nie tylko na tekscie z PDF.
9. Polaczenie zdublowanego widoku rozpisu (Saldo vs Bilans miesiaca, ~90 linii).
10. Sprawdzenie Material You + paska stanu na telefonie w obu trybach.
11. Dostepnosc: wiersz listy ~44 px vs zalecane 48 px; audyt WCAG (Faza 4).
12. Onboarding — ekran powitalny (Faza 4).

**Publikacja**
13. Strona `/aplikacje/zostaje` w repo `com` ze zrzutami ekranu.
14. Przejscie na Google Play (Faza 15).

---

## Backlog (przyszlosc)

| Pomysl | Priorytet |
|--------|-----------|
| ~~Eksport do CSV/Excel~~ | ✅ Zrealizowane (Excel w Fazie 5b, XLSX/PDF w Ustawieniach — Faza 11) |
| Widgety home screen | Sredni — brak w kodzie |
| Wear OS companion | Niski |
| Grupowanie subskrypcji (np. "Rodzina") | Sredni — czesciowo pokrywa podzial Osobisty/Domowy |
| ~~Shared subscriptions (split costs)~~ | ✅ Zrealizowane w Fazie 2 |
| Auto-detect z SMS/email (parsowanie potwierdzen) | Niski (prywatnosc!) — zamiast tego skan i „Udostepnij" (Faza 9) |
| ~~SelectionController (multi-select batch operations)~~ | ✅ Zrealizowane dla Biezacych i Cyklicznych (Faza 12); **otwarte: subskrypcje** (wlasny model i menu, ADR-027) |
| Miesieczne migawki kosztow | Do decyzji — dzis historia „Realne" jest odtwarzana z obecnych kosztow (ADR-028) |
| Koperta Planner zawezona do kategorii | Do decyzji, gdyby duze zakupy zaburzaly porownanie plan/realny |
| Natywny odbior „Udostepnij" i cala kolejka skanow w warstwie natywnej | Tylko gdy pojawi sie gubienie udostepnien / drugi skan w tle |
| Dzisiejsza data w poleceniu dla silnika AI (repo `karton-ai`) | Niski — wymaga wydania silnika, dotyka tez APPteczki |
| Czystka uspionych pol `usageLog`/`isGhost` | Niski |
| Scalenie dwoch list nazw miesiecy | Niski — gdy pojawi sie trzecia |
| Tagi DEV `dev-v…` vs `v…-dev` (kosmetyka w Obtainium) | Niski |

---

> **Ostatnia aktualizacja:** 2026-10-04
