# Aurora — Design System

> **Powiązane:** [Architektura](architecture.md) | [Baza Danych](database.md) |
> [Design Review](standards/design-review.md) | [ADR-005 Aurora + jeden motyw](adr/ADR-005-aurora-jeden-ciemny-motyw.md)

> **Status:** ✅ wdrożone w kodzie (Faza 6, prod 0.5 — 2026-06-17). Tokeny i pełne pokrycie
> motywem pilnowane przez strażnika ([ADR-007](adr/ADR-007-design-tokens-jedyne-zrodlo-prawdy.md)).
>
> 🎨 **Aktualizacja (ADR-010, 2026-06-23):** aplikacja ma teraz **wiele motywów** —
> Tryb (jasny / ciemny / systemowy) × Kolor (Purple / Blue). Poniższa paleta opisuje
> wariant ciemny Purple (bazowy); pozostałe to ta sama mechanika z inną paletą.
> Przełącznik: Ustawienia → Wygląd. Patrz [ADR-010](adr/ADR-010-wiele-motywow-tryb-x-kolor.md).

---

## Filozofia

**„Spokojna precyzja w ciemności."**

Aurora to premium, ciemny interfejs finansowy: dane czytelne natychmiast, jeden moment „wow"
(gradient aurora w tle + gradientowa kwota-bohater), a reszta spokojna, oszczędna i — co kluczowe —
**wydajna**. Inspiracja: nowoczesne dashboardy fintech (typu MONEF), ale bez bankowego plastiku
i bez asystenta AI (zgodnie z DNA projektu).

### Co się zmienia względem Ledger Glass

| Aspekt | Ledger Glass (poprzedni) | Aurora (nowy) |
|--------|--------------------------|---------------|
| Motyw | Light + Dark + przełącznik | **Jeden uniwersalny ciemny** (bez przełącznika) |
| Tło | Płaskie białe / granat | Gradient aurora (indygo→fiolet→czerń) |
| Powierzchnie | Białe karty, 1px border | „Frost" — półprzezroczysta biel na ciemnym |
| Akcent | Deep Navy / Light Blue | Fiolet → cyan (gradient) |
| Gęstość | Wysoka (padding 12px) | Przestronna (padding 16–18px) |
| Charakter | Bloomberg Terminal | Premium fintech, spokojny |

### Dlaczego jeden ciemny motyw

- **Spójność i tożsamość** — jeden, rozpoznawalny wygląd zamiast dwóch kompromisów.
- **Mniej kodu** — jeden zestaw tokenów, brak gałęzi `isDark`, brak `ThemeProvider` toggle
  (mniej miejsc na błędy i regresje). Szczegóły i ryzyka:
  [ADR-005](adr/ADR-005-aurora-jeden-ciemny-motyw.md).
- **Znany minus:** gorsza czytelność w pełnym słońcu — zaakceptowany świadomie (apka używana
  głównie w domu/wieczorem).

### Zasady projektowe

| Zasada | Realizacja |
|--------|------------|
| Jeden motyw | Brak light/dark; brak przełącznika w Ustawieniach |
| Jeden „wow", reszta spokój | Gradient tła + kwota-bohater; pozostałe karty matowe i ciche |
| Wydajność ponad efekt | „Frost" zamiast prawdziwego rozmycia (patrz [Wydajność](#wydajność-twarde-reguły)) |
| Kolor = znaczenie | Zielony (zostaje/oszczędność), czerwony (przekroczenie), amber (ostrzeżenie) |
| Tabular figures | Monospaced cyfry dla wyrównania kwot w kolumnach |
| Precyzja geometryczna | Symetryczne radii, zero organic shapes |

---

## Paleta (jeden ciemny motyw)

### Tło

| Token | Wartość | Opis |
|-------|---------|------|
| `--bg-gradient` | `linear-gradient(165°, #241B4B 0%, #16113A 52%, #0B0822 100%)` | Główne tło aplikacji (aurora) |
| `--bg-solid` | `#0E0A1F` | Fallback / ekrany pełnoekranowe bez gradientu |
| `--glow-violet` | `radial rgba(124,92,255,0.45)` | Statyczna poświata (dekoracja tła) |
| `--glow-cyan` | `radial rgba(34,211,238,0.25)` | Statyczna poświata (dekoracja tła) |

> Poświaty są **statyczne** (nie animowane) — zob. [Wydajność](#wydajność-twarde-reguły).

### Powierzchnie „frost" (półprzezroczyste, BEZ rozmycia)

| Token | Wartość | Użycie |
|-------|---------|--------|
| `--frost-1` | `rgba(255,255,255,0.07)` | Karty standardowe |
| `--frost-2` | `rgba(255,255,255,0.10)` | Kafle zagnieżdżone, chipy wewnątrz kart |
| `--frost-border` | `rgba(255,255,255,0.14)` | Obramowanie kart |
| `--frost-border-strong` | `rgba(255,255,255,0.20)` | Obramowanie elementu aktywnego/focus |
| `--nav-glass` | `rgba(255,255,255,0.10)` + blur(18) | **Jedyne prawdziwe szkło** — pasek nawigacji |

### Akcenty

| Token | HEX | Użycie |
|-------|-----|--------|
| `--accent-violet` | `#A78BFA` | Główny akcent (ikony, aktywne) |
| `--accent-cyan` | `#5EEAD4` | Akcent drugorzędny, druga końcówka gradientu |
| `--accent-gradient` | `linear-gradient(90°, #C4B5FD, #5EEAD4)` | Kwota-bohater, aktywne chipy/taby, „Dodaj" |
| `--accent-solid` | `#8B7BF7` | Gdy gradient niewskazany (np. pojedyncza ikona) |

### Tekst

| Token | HEX | Użycie |
|-------|-----|--------|
| `--text-primary` | `#F3F0FF` | Główny tekst, kwoty |
| `--text-secondary` | `#C2B9EC` | Etykiety, opisy |
| `--text-muted` | `#A99FD0` | Podpisy, daty, meta |

### Kolory semantyczne

Na ciemnym tle używamy jaśniejszych odcieni (shade 400) + tła jako kolor @ 14% alpha.

| Token | Foreground | Background | Cel |
|-------|-----------|-----------|-----|
| `--positive` | `#34D399` | `rgba(52,211,153,0.14)` | Zostaje, oszczędność, pod budżetem |
| `--negative` | `#F87171` | `rgba(248,113,113,0.14)` | Przekroczenie, deficyt |
| `--warning` | `#FBBF24` | `rgba(251,191,36,0.14)` | Zbliżające się odnowienie |
| `--trial` | `#60A5FA` | `rgba(96,165,250,0.14)` | Okres próbny (trial) |

### Kolory wykresów

| Token | HEX | Nazwa |
|-------|-----|-------|
| `--chart-1` | `#A78BFA` | Violet-400 (główna seria) |
| `--chart-2` | `#5EEAD4` | Teal-300 |
| `--chart-3` | `#60A5FA` | Blue-400 |
| `--chart-4` | `#FB923C` | Orange-400 |
| `--chart-5` | `#34D399` | Green-400 |
| `--chart-6` | `#F472B6` | Pink-400 |
| `--bar-idle` | `rgba(255,255,255,0.12)` | Słupek nieaktywny |
| `--bar-highlight` | `linear-gradient(180°, #A78BFA, #5EEAD4)` | Słupek podświetlony (bieżący okres) |

---

## Typografia

Skala bez zmian względem Ledger Glass. Kwoty finansowe nadal używają **tabular figures**.

| Rola | Rozmiar | Waga | Użycie |
|------|---------|------|--------|
| Display | 40px | 700 | Kwota-bohater („Zostaje w tym miesiącu") |
| Headline | 20px | 600 | Nagłówki sekcji |
| Title | 16px | 600 | Nazwy pozycji na kartach |
| Body | 14px | 400 | Opisy, etykiety |
| Label | 12px | 500 | Chipy, delta-pille, meta |
| Caption | 11px | 400 | Podpisy wykresów, daty osi |

**Znaki spoza fontu:** tekst idzie systemowym Roboto. Znaku, którego w nim nie ma
(np. strzałka „→"), telefon szuka w foncie zastępczym — wychodzi mniejszy i niżej
niż reszta linii. W Roboto są i stoją na jednej wysokości (środek cyfr): półpauza
„–", minus „−", plus, „·", „×". Strzałka w podpisie to ikona `planArrowSpan`
(Lucide `moveRight`, środek linii), nie znak.

### Kwota-bohater (gradientowa)

Główna liczba na Pulpicie jest wypełniona gradientem `--accent-gradient`.
W Flutterze: `ShaderMask` z `LinearGradient` na `Text` (koszt znikomy).

```dart
ShaderMask(
  shaderCallback: (b) => AppColors.accentGradient.createShader(b),
  child: Text('2 340 zł', style: heroAmountStyle), // tabular, w700, 40px
)
```

Pozostałe kwoty: pełny kolor `--text-primary` (bez gradientu) — gradient to akcent, nie reguła.

---

## Geometria i Layout

### Border Radius

| Element | Radius |
|---------|--------|
| Karty | 22px |
| Kafle metryk, chipy | 16px |
| Delta-pille, tagi | 20px (pełna pigułka) |
| Pasek nawigacji (pływający) | 30px (pełna pigułka) |
| Przyciski | 16px |
| Pola tekstowe | 12px |

### Spacing (8px Grid)

| Token | Wartość | Użycie |
|-------|---------|--------|
| `xs` | 4px | Gap ikon, wewnątrz chipów |
| `sm` | 8px | Gap między kaflami |
| `md` | 12px | Padding kompaktowych elementów |
| `base` | 16px | Standardowy padding kart i sekcji |
| `lg` | 20px | Padding kart-bohaterów, odstęp sekcji |
| `xl` | 28px | Odstęp między blokami ekranu |

> Aurora jest **przestronna**: padding kart 16–18px (Ledger Glass miał 12px).

---

## Wydajność (twarde reguły)

> **To jest sekcja kontraktowa.** Cel wybrany świadomie: **wygląd C2 za koszt ~zero**.

| Reguła | Realizacja |
|--------|------------|
| „Frost" = przezroczystość, **nie** rozmycie | Karty: `Container` z `color: white@0.07`. **Bez** `BackdropFilter`. Tło to gładki gradient, więc mleczna biel czyta się jak szkło. |
| Gradient tła = statyczny | `BoxDecoration(gradient: LinearGradient(...))`. Zero animacji. |
| Poświaty = statyczne | `RadialGradient` w `Stack`, nieanimowane. |
| Prawdziwy blur = **maks. 1 na ekran** | `BackdropFilter(blur 18)` dozwolony **tylko** na pływającym pasku nawigacji (tam blur ma sens — leży nad przewijaną treścią). |
| Zakazane | Animowane gradienty; `BackdropFilter` na kartach/listach; `Opacity` na dużych poddrzewach (użyj koloru z alpha); zbędne `saveLayer`. |

**Argument (dla celu pobocznego):** prawdziwe `BackdropFilter` rozmywa wszystko pod sobą i wymusza
`saveLayer` — wiele takich warstw na przewijanej liście gubi klatki na tańszym Androidzie.
Mleczne wypełnienie nad gładkim gradientem daje ~90% tego samego efektu wizualnego przy zerowym
koszcie GPU. Jedyny realny blur (pasek nawigacji) to jedna warstwa, statyczna pozycja — bezpieczny.

---

## Mapowanie komponentów na Flutter M3

| Komponent | Implementacja | Uwagi |
|-----------|---------------|-------|
| Tło ekranu | `Stack`: `Container(gradient)` + 2× `Positioned` glow (`RadialGradient`) + treść | `Scaffold(backgroundColor: Colors.transparent)` |
| Frost card | `Container(color: white@0.07, radius 22, border white@0.14)` | **Bez** BackdropFilter |
| Kafel metryki | Frost card: ikona (akcent) + liczba (`tnum`) + delta-pill | Siatka 2 kolumny (`GridView`/`Wrap`) |
| Delta-pill | `Container(color: semantic@0.14, radius 20)` + tekst semantic | `+4%`, `-2%` |
| Kwota-bohater | `ShaderMask` + `Text` (gradient) | Tylko główna liczba |
| Wykres słupkowy | `fl_chart BarChart`: 1 słupek w `--bar-highlight`, reszta `--bar-idle` + tooltip | Bieżący okres podświetlony |
| Pasek nawigacji | **Custom** pływająca pigułka: `ClipRRect` + `BackdropFilter(18)` + `Container(--nav-glass)` | Jedyne prawdziwe szkło |
| Przyciski główne | `FilledButton` | Tło `--accent-solid` lub gradient |
| Pola tekstowe | `TextField` + `OutlineInputBorder` (12px, `--frost-border`) | Tło `--frost-1` |
| Bottom sheets / dialogi | `showModalBottomSheet` / `AlertDialog` | Tło `--bg-solid`, border frost |
| Chipy filtrów | `FilterChip` | Tło `--frost-2`, aktywny `--accent-solid` |

### Nowe / zmienione custom widgety

| Widget | Cel |
|--------|-----|
| `AuroraBackground` | Tło aplikacji (gradient + poświaty), montowane RAZ w `MaterialApp.builder` pod Navigatorem; ekrany mają transparent Scaffold. NIE owijać ekranów — podwójne tło psuje animacje przejść. Przejścia tras: fade-through (`animations`, fillColor transparent) — domyślny zoom nakłada oba ekrany naraz i przy przezroczystych Scaffoldach treść prześwituje jak duch |
| `FrostCard` | Standardowa karta (przezroczystość, border) — bez blur |
| `GlassNavBar` | Pływająca pigułka nawigacji — **jedyny** `BackdropFilter` |
| `MetricTile` | Ikona + kwota + delta-pill |
| `GradientAmount` | Kwota-bohater przez `ShaderMask` |

---

## Stany kart

| Stan | Tło | Border | Ikona |
|------|-----|--------|-------|
| Standardowa | `--frost-1` | `--frost-border` | — |
| Odnowienie wkrótce | `--warning` @ 0.10 | `--warning` @ 0.30 | Zegar |
| Trial | `--trial` @ 0.10 | `--trial` @ 0.30 | Timer |
| Przekroczenie | `--negative` @ 0.10 | `--negative` @ 0.30 | Alert |
| Anulowana | `--frost-1` @ 0.5 opacity | `--frost-border` | Strikethrough |

---

## Ikony

Lucide Icons (`lucide_icons_flutter`) — **bez zmian** względem Ledger Glass. Kolor ikon akcentowych:
`--accent-violet`; ikon neutralnych: `--text-muted`.

---

## Dostępność (WCAG 2.1)

| Aspekt | Realizacja |
|--------|-----------|
| Jeden motyw | Zawsze ciemny — brak przełącznika |
| Kontrast tekstu | `#F3F0FF` na `#0E0A1F` ≈ 16:1 (AAA). `--text-muted` na frost ≥ 4.5:1 |
| Kwota-bohater (gradient) | Najjaśniejszy stop (`#5EEAD4`) na ciemnym ≥ 4.5:1 — bezpieczny |
| Kolory semantyczne | Nigdy sam kolor — zawsze ikona + label |
| Focus | Border `--frost-border-strong` (2px) |
| Touch targets | Min 48×48dp |
| Screen reader | Kwoty z semantycznym opisem („Zostaje 2340 złotych") |
| Znany kompromis | Czytelność w pełnym słońcu — zob. [ADR-005](adr/ADR-005-aurora-jeden-ciemny-motyw.md) |

---

## Migracja z Ledger Glass (kod — Faza 6)

> Zakres prac w przyszłej sesji implementacyjnej. **Ten dokument to specyfikacja, nie kod.**

| Plik / obszar | Zmiana |
|---------------|--------|
| `lib/theme/app_theme.dart` | Jeden ciemny `ThemeData`; nowe tokeny (gradient, frost, akcenty); usunięcie wariantu light |
| `lib/services/theme_provider.dart` | Usunięcie przełącznika Dark/Light/System (stała ciemna lub usunięcie providera) |
| `lib/screens/settings_screen.dart` | Usunięcie sekcji „Motyw" |
| Scaffoldy ekranów | Transparent Scaffold (tło daje globalny `AuroraBackground` z `MaterialApp.builder`) |
| Karty (`Card`, kontenery) | Zamiana na `FrostCard` |
| Pasek nawigacji (`NavigationBar`) | Zamiana na `GlassNavBar` (pływająca pigułka) |
| Dashboard | Siatka `MetricTile` + `GradientAmount` + wykres z podświetleniem |
| Logika / dane / backup | **Bez zmian** |

---

## Implementacja w Flutter (`AppColors` — jeden motyw)

```dart
class AppColors {
  AppColors._();

  // ── Tło ─────────────────────────────────────────────────────────────────
  static const Color bgSolid = Color(0xFF0E0A1F);
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF241B4B), Color(0xFF16113A), Color(0xFF0B0822)],
    stops: [0.0, 0.52, 1.0],
  );
  static final Color glowViolet = const Color(0xFF7C5CFF).withValues(alpha: 0.45);
  static final Color glowCyan = const Color(0xFF22D3EE).withValues(alpha: 0.25);

  // ── Frost (powierzchnie) ─────────────────────────────────────────────────
  static final Color frost1 = Colors.white.withValues(alpha: 0.07);
  static final Color frost2 = Colors.white.withValues(alpha: 0.10);
  static final Color frostBorder = Colors.white.withValues(alpha: 0.14);
  static final Color frostBorderStrong = Colors.white.withValues(alpha: 0.20);
  static final Color navGlass = Colors.white.withValues(alpha: 0.10);

  // ── Akcenty ──────────────────────────────────────────────────────────────
  static const Color accentViolet = Color(0xFFA78BFA);
  static const Color accentCyan = Color(0xFF5EEAD4);
  static const Color accentSolid = Color(0xFF8B7BF7);
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFC4B5FD), Color(0xFF5EEAD4)],
  );

  // ── Tekst ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF3F0FF);
  static const Color textSecondary = Color(0xFFC2B9EC);
  static const Color textMuted = Color(0xFFA99FD0);

  // ── Semantyczne (foreground) ──────────────────────────────────────────────
  static const Color positive = Color(0xFF34D399);
  static const Color negative = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);
  static const Color trial = Color(0xFF60A5FA);

  // ── Wykresy ──────────────────────────────────────────────────────────────
  static const List<Color> chartColors = [
    Color(0xFFA78BFA), Color(0xFF5EEAD4), Color(0xFF60A5FA),
    Color(0xFFFB923C), Color(0xFF34D399), Color(0xFFF472B6),
  ];
  static final Color barIdle = Colors.white.withValues(alpha: 0.12);
  static const LinearGradient barHighlight = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFFA78BFA), Color(0xFF5EEAD4)],
  );
}
```

> `AppSemanticColors` (`ThemeExtension`) pozostaje jako mechanizm dostępu (`context.semanticColors`),
> ale z **jednym** zestawem wartości (brak wariantu light) — zob. [ADR-002](adr/ADR-002-semantic-color-tokens.md).

---

## Makiety ekranow (Aurora) — sciaga do Fazy 6

> Podglad wizualny 4 ekranow na realnych danych: [`design-mockups/aurora-makiety.html`](design-mockups/aurora-makiety.html)
> (otworz w przegladarce). Ponizej mapowanie tresci ekranu → tokeny i komponenty Aurora.

### Wspolne (kazdy ekran)

- Tlo: `AuroraBackground` (`--bg-gradient` + 2 statyczne poswiaty)
- AppBar: tytul 20px/600, tlo transparentne; akcje jako ikona + etykieta (XLSX/PDF)
- Nawigacja: `GlassNavBar` (plywajaca pigulka, jedyny `BackdropFilter`); nieaktywna zakladka =
  sama ikona (`--text-secondary`), aktywna = pozioma pigulka (ikona + etykieta w kolorze
  `--accent-solid` na tincie akcentu @0.16); etykieta rozsuwa/zwija sie animacja (`AnimatedSize`,
  ~220 ms `easeOutCubic`). Pionowy separator oddziela ostatnia pozycje (Ustawienia) od funkcji
- Karty: `FrostCard` (`--frost-1`, border `--frost-border`, radius 22) — **bez blur**
- Kwoty: tabular figures; dodatnie `--positive`, ujemne `--negative`
- Przelacznik Osobisty/Domowy, chipy, aktywne taby: stan aktywny = `--accent-gradient`

### Dashboard

| Element | Realizacja Aurora |
|---------|-------------------|
| Karta „Saldo: zostaje miesiecznie" | jedna karta: `GradientAmount` + linia wplywy/koszty (trending-up/down) zawsze widoczna; tap rozwija/zwija opis „jak liczone jest saldo" + przypis subskrypcji |
| Karta Subskrypcje | `FrostCard`: header + „N aktywne"; Miesiecznie / Rocznie |
| Karta „Saldo" (Plan) | Zwinieta: kwota-bohater + wiersz wplywy/koszty. Rozwinieta: **pasek proporcji** (koszty cykliczne / Planner / zostaje, skala = `max(wplywy, koszty+rezerwa)`) nad **rozpisem jak na rachunku** (wplywy − koszty cykliczne, z wcietym „w tym subskrypcje: mies. · rocznie · aktywnych" − Planner = zostaje; kolorowe kropki wiaza wiersze z paskiem, procenty liczone od wplywow). Deficyt: pasek wypelniaja koszty, suma na czerwono |
| Lista pozycji budzetu | **Bez ramek i cieni** — wiersze rozdzielone cienkim separatorem (`BudgetEntryList`), styl listy maklerskiej. Kazda pozycja ma DWIE linie: `{nazwa} {kwota}`, pod spodem `{typ} · {data RRRR-MM-DD} · {sposob platnosci} · {kategoria}`. Kwota stoi w pierwszej linii (nie z boku obu), a kategoria w drugiej — obie decyzje z tego samego powodu: nazwa i data maja wtedy cala szerokosc i przestaja sie urywac. Ikona wiersza to **ikona kategorii**, gdy pozycja ja ma; bez kategorii zostaje strzalka kierunku (wplyw/wydatek), ktora i tak powtarza kolor kwoty. Powod: przy kilkudziesieciu rachunkach kazda ramka kosztowala pionowy ekran i rozbijala liste na osobne wyspy |
| Karta „Rzeczywisty bilans miesiaca" | Nad kalendarzem. Zwinieta: kwota bilansu (zielona/czerwona). Rozwinieta: pasek proporcji (koszty cykliczne / subskrypcje / rachunki / zostaje) + rozpis realnych strumieni. Przytrzymanie kwoty → bottom sheet z rozbiciem roznicy „bilans − saldo" (jednorazowe, korekty kwot, korekty rat) |
| Karta miesiaca (kalendarz) | prev/next + kalendarz 7 kol.; kwoty bilansu juz NIE powtarza (jest w sekcji wyzej) |
| Kropki w kalendarzu | wplyw `--positive`, wydatek `--negative` |
| Dzis / wybrany dzien | dzis = border `--accent-violet`; wybrany = tlo `--frost-2` |
| Szczegoly dnia | lista pod kalendarzem (ikona kierunku + nazwa + kwota semantic) |

### Subskrypcje

Nie maja wlasnego ekranu — sa trzecia sekcja „Wydatkow" (ADR-027), w tym samym
stylu wiersza co pozycje budzetu.

| Element | Realizacja Aurora |
|---------|-------------------|
| Wiersz subskrypcji | jak wiersz pozycji budzetu: ikona kategorii (lub `repeat`) + nazwa + kwota/cykl `--negative`; druga linia: `Subskrypcja · data · okres probny · /os. · metoda · kategoria` |
| Okres probny | kwota w kolorze `--trial`, w drugiej linii „probny · N dni"; koszty po okresie probnym w karcie na „Planie" |
| Anulowana | wiersz przygaszony (opacity 0.5) + token „anulowana"; domyslnie ukryta, odslania ja przelacznik przy filtrze czasu |
| Przypieta | ikona `pin` przed nazwa; zostaje na gorze sekcji niezaleznie od sortowania |
| Kolory kategorii | Streaming `#60A5FA`, Software `#FB923C`, Cloud `--accent-cyan`, Muzyka `--accent-violet` |

### Wydatki / Wplywy (listy pozycji)

| Element | Realizacja Aurora |
|---------|-------------------|
| Przelacznik Osobisty/Domowy | segmented frost w `WorkspaceTopBar`; aktywny = gradient |
| Pasek plan/realny | `PlanProgressBar` (ADR-030): w planie zielony odcinek na torze `--border`; ponad plan caly tor dzielony w proporcji do wydanej kwoty — zielone = plan, czerwone = nadwyzka |
| Filtry | chipy: kategorie, typy (z pseudo-chipem „Subskrypcje") oraz czas (rok → po wybraniu roku pasek miesiecy). Filtr czasu = snapshot: cykliczne i subskrypcje zawsze, jednorazowe danego miesiaca, raty w oknie |
| Akcje przy paskach | grupowanie po kategoriach przy kategoriach, sortowanie przy typach, „pokaz ukryte" (oko) przy czasie — przyklejone na koncu przewijanego paska |
| Naglowki sekcji | „Przelew wewnetrzny" / „Wydatki stale" / „Subskrypcje" / „Wplywy" — 15px/600 `--text-primary` + suma sekcji i chevron; tap zwija sekcje (suma zostaje) |
| Wiersz pozycji | ikona kategorii (`--kolor kategorii`) lub trending-up/down + nazwa + kwota (semantic); druga linia: typ · data · metoda · kategoria |
| „Dodaj" | pigulka `--accent-gradient`; menu: pozycja budzetu, subskrypcja, import z Excela |

### Ustawienia

| Element | Realizacja Aurora |
|---------|-------------------|
| Wiersze listy | `FrostCard` z ikona `--accent-violet` + chevron `--text-muted` |
| Naglowki sekcji | 11px, letter-spacing, `--text-muted`, wersaliki |
| Radio waluty | zaznaczony: pierscien + kropka `--accent-violet` |
| Toggle ON / OFF | tor ON `--accent-gradient` + biala galka; OFF tor `--frost-2` |
| Brak wiersza „Motyw" | jeden motyw — przelacznik usuniety (zob. [ADR-005](adr/ADR-005-aurora-jeden-ciemny-motyw.md)) |

---

> **Ostatnia aktualizacja:** 2026-08-01
