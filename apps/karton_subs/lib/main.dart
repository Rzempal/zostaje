import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'controllers/subscription_controller.dart';
import 'controllers/budget_controller.dart';
import 'controllers/plan_controller.dart';
import 'screens/dashboard_screen.dart';
import 'screens/planning_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_logger.dart';
import 'models/budget_entry.dart';
import 'services/backup_service.dart';
import 'services/cloud_backup_service.dart';
import 'services/excel_service.dart';
import 'services/plan_conversion.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/theme_provider.dart';
import 'services/update_service.dart';
import 'services/notification_service.dart';
import 'models/subscription.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass_nav_bar.dart';
import 'widgets/section_info_badge.dart';
import 'widgets/workspace_top_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl');

  AppLogger().init();

  final storage = StorageService();
  await storage.init();

  // Dev-only: restore date override
  if (AppConfig.isInternal) {
    Subscription.devDateOverride = storage.getDevDateOverride();
  }

  // Plan roczny (ADR-035): jednorazowa konwersja starych pozycji budżetu.
  // Stare dane zostają nietknięte, więc błąd konwersji nie może zablokować
  // startu — aplikacja działa dalej na starym zapisie, a błąd ląduje w logu.
  try {
    final runner = PlanConversionRunner(storage);
    final today = Subscription.devDateOverride ?? DateTime.now();
    await runner.ensureConverted(today);
    // Planner „Na bieżące wydatki" → zwykłe pozycje planu (dokładane do planu,
    // który już istnieje — bez przeliczania całości).
    await runner.ensureEnvelopeMigrated(today);
  } catch (e, st) {
    AppLogger.get('PlanConversion')
        .severe('Konwersja planu nie powiodla sie', e, st);
  }

  // Synchronizacja budzetu domowego (relay E2E, ADR-009) — wczytaj sparowanie.
  final syncService = SyncService(storage);
  await syncService.init();

  final updateService = UpdateService();
  // OTA check w tle — nie blokujemy startu
  updateService.init();

  // Local notifications (non-blocking — app works without them)
  const notificationService = NotificationService();
  await notificationService.init();
  notificationService.rescheduleAll(storage.getSubscriptions(), storage: storage);

  runApp(
    // DynamicColorBuilder dostarcza systemowy ColorScheme (Material You,
    // Android 12+). null na starszych/iOS → Material You niedostepny (kafelek ukryty).
    DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MultiProvider(
      providers: [
        Provider.value(value: storage),
        ChangeNotifierProvider(
          create: (_) => SubscriptionController(storage, notificationService),
        ),
        ChangeNotifierProxyProvider<SubscriptionController, BudgetController>(
          create: (ctx) => BudgetController(
            storage,
            ctx.read<SubscriptionController>(),
          ),
          // Kontroler trzyma własną referencję do SubscriptionController
          // (przez konstruktor) i nasłuchuje go — nie tworzymy nowej instancji
          // przy każdej zmianie, tylko zwracamy istniejącą.
          update: (_, _, budget) => budget!,
        ),
        // Plan roczny (ADR-035) — słucha BudgetController (aktywny budżet,
        // koperta, subskrypcje zakresu), więc też nie powstaje od nowa.
        ChangeNotifierProxyProvider<BudgetController, PlanController>(
          create: (ctx) => PlanController(storage, ctx.read<BudgetController>()),
          update: (_, _, plan) => plan!,
        ),
        ChangeNotifierProvider.value(value: updateService),
        ChangeNotifierProvider.value(value: syncService),
        ChangeNotifierProvider(create: (_) => ThemeProvider(storage)),
        Provider(create: (_) => BackupService(storage)),
        Provider(create: (_) => ExcelService(storage)),
        Provider.value(value: notificationService),
      ],
      child: _ThemeDynamicBridge(
        lightDynamic: lightDynamic,
        darkDynamic: darkDynamic,
        child: const KartonApp(),
      ),
      ),
    ),
  );
}

/// Most dostarczajacy systemowe ColorScheme (Material You) do ThemeProvider.
/// dynamic_color wczytuje kolory ASYNCHRONICZNIE — ten widget aktualizuje
/// providera, gdy kolory dotra (po pierwszym renderze z null).
class _ThemeDynamicBridge extends StatefulWidget {
  final ColorScheme? lightDynamic;
  final ColorScheme? darkDynamic;
  final Widget child;
  const _ThemeDynamicBridge({
    this.lightDynamic,
    this.darkDynamic,
    required this.child,
  });

  @override
  State<_ThemeDynamicBridge> createState() => _ThemeDynamicBridgeState();
}

class _ThemeDynamicBridgeState extends State<_ThemeDynamicBridge> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(covariant _ThemeDynamicBridge old) {
    super.didUpdateWidget(old);
    if (old.lightDynamic != widget.lightDynamic ||
        old.darkDynamic != widget.darkDynamic) {
      _apply();
    }
  }

  void _apply() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context
            .read<ThemeProvider>()
            .setDynamic(widget.lightDynamic, widget.darkDynamic);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class KartonApp extends StatelessWidget {
  const KartonApp({super.key});

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    // Motyw w 2 wymiarach (ADR-010): tryb (jasny/ciemny/system) x kolor.
    final tp = context.watch<ThemeProvider>();
    final platform = MediaQuery.platformBrightnessOf(context);
    // Faktyczna paleta (uwzglednia system) dla globalnych getterow AppColors.
    final palette = tp.effectivePalette(platform);
    AppColors.active = palette;
    return MaterialApp(
      title: 'Zostaje',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: tp.lightTheme,
      darkTheme: tp.darkTheme,
      themeMode: tp.effectiveThemeMode,
      // Widgety Materiala (kalendarz `showDatePicker`, przyciski „Anuluj/OK",
      // pierwszy dzien tygodnia) biora jezyk STAD, a nie z `DateFormat` —
      // aplikacja pisana po polsku otwierala okna po angielsku.
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Tło Aurora renderowane RAZ, pod Navigatorem: przejścia ekranów animują
      // wyłącznie treść (tło stoi nieruchomo), a ekrany mają przezroczyste
      // Scaffoldy. Wcześniej każdy ekran niósł własną kopię tła, przez co
      // animacja powrotu „pompowała" gradientem i poświatami.
      // Styl paskow systemowych deklarowany RAZ, nad Navigatorem: ekrany
      // robocze nie maja paskow tytulu (ADR-026), wiec nikt inny nie mowi
      // systemowi, czy ikony stanu maja byc ciemne czy biale. Deklaratywnie,
      // a nie przez SystemChrome — ekran z wlasnym AppBarem nadpisze styl na
      // czas swojego zycia, a po powrocie znow obowiazuje ten.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlayStyleFor(palette),
        child: AuroraBackground(child: child!),
      ),
      home: const _MainShell(),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-synchronizacja po zmianie budzetu domowego (debounced).
    context.read<BudgetController>().onHouseholdChanged = _scheduleSync;
    // Synchronizacja budzetu domowego przy starcie (jesli sparowane).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncThenMaybeBackup();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncThenMaybeBackup();
    }
  }

  /// Scalanie budzetu domowego, a po nim kopia w chmurze (jesli czas na nia).
  /// Kolejnosc ma znaczenie: kopia zrobiona przed scaleniem zapisalaby
  /// w chmurze uboższą migawkę (telefon po dluzszym offline).
  Future<void> _syncThenMaybeBackup() async {
    final sync = context.read<SyncService>();
    if (sync.isPaired) {
      final result = await sync.syncNow();
      if (result.changedLocal && mounted) {
        context.read<BudgetController>().refresh();
      }
    }
    if (mounted) _maybeCloudBackup();
  }

  /// Kopia na koncie Google - najwyzej raz na dobe, po cichu i bez okien.
  ///
  /// Pusty budzet NIGDY nie jedzie do chmury: kopia bez subskrypcji i bez
  /// pozycji budzetu nie ma wartosci, a nadpisalaby te dobra po wyczyszczeniu
  /// danych albo na swiezej instalacji, zanim uzytkownik zdazy cokolwiek
  /// przywrocic.
  void _maybeCloudBackup() {
    final storage = context.read<StorageService>();
    final hasData =
        storage.getSubscriptions().isNotEmpty ||
        storage.getPlanPositions().isNotEmpty ||
        storage.getBudgetEntries(BudgetScope.personal).isNotEmpty ||
        storage.getBudgetEntries(BudgetScope.household).isNotEmpty;
    if (!hasData) return;

    final backup = context.read<BackupService>();
    CloudBackupService.instance.maybeBackupDaily(
      backup.buildEncryptedSnapshot,
      now: DateTime.now(),
    );
  }

  /// Synchronizacja z opóźnieniem — seria szybkich zmian = jeden sync.
  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final sync = context.read<SyncService>();
      if (!sync.isPaired) return;
      final result = await sync.syncNow();
      if (result.changedLocal && mounted) {
        context.read<BudgetController>().refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncDebounce?.cancel();
    super.dispose();
  }

  /// Kolejnosc zakladek (ADR-035): przeglad (statystyki i kalendarz), plan
  /// roczny — wpływy, wydatki, karta i subskrypcje na jednym ekranie — na
  /// koncu ustawienia. „Wplywy" i „Cykliczne" zlaly sie w „Planowanie",
  /// a „Biezace" (dziennik wydatkow, skan paragonow) odpadly: zaplanowany
  /// wydatek to zwykla pozycja planu.
  static const _screens = [
    DashboardScreen(),
    PlanningScreen(),
    SettingsScreen(),
  ];

  static const _navItems = [
    GlassNavItem(icon: LucideIcons.wallet, label: 'Budżet'),
    GlassNavItem(icon: LucideIcons.calendarRange, label: 'Planowanie'),
    GlassNavItem(icon: LucideIcons.settings, label: 'Ustawienia'),
  ];

  /// Opis sekcji dla wspolnego paska — kolejnosc jak w [_screens].
  /// Ustawienia (ostatnia zakladka) opisu nie maja: to nie jest sekcja budzetu,
  /// a i zakres nie ma tam czego przelaczac.
  static SectionInfo? _sectionInfoFor(int index) => switch (index) {
    0 => SectionInfo.budget,
    1 => SectionInfo.planning,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    // Zaleznosc od motywu: zmiana palety przebudowuje shell (nawigacja),
    // a KeyedSubtree z kluczem motywu wymusza rebuild zawartosci zakladek —
    // AppColors to globalne gettery (nie InheritedWidget), wiec same nie reaguja.
    // Tlo Aurora maluje MaterialApp.builder (raz, pod Navigatorem).
    final tp = context.watch<ThemeProvider>();
    final themeId = tp.effectivePalette(MediaQuery.platformBrightnessOf(context)).id;
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Treść przewija się za pływającym paskiem nawigacji.
      extendBody: true,
      // SafeArea u gory, bo ekrany nie maja juz wlasnych paskow tytulu —
      // bez tego tresc wchodzilaby pod pasek stanu telefonu.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Zakres i opis sekcji: jeden pasek dla calej aplikacji zamiast
            // paska tytulu + przelacznika na kazdym ekranie z osobna.
            WorkspaceTopBar(
              info: _sectionInfoFor(_currentIndex),
              // Ustawienia to ostatnia zakladka — zakresu tam nie ma czego tyczyc.
              showScope: _currentIndex != _screens.length - 1,
            ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(themeId),
                child: IndexedStack(
                  index: _currentIndex,
                  children: _screens,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: GlassNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: _navItems,
        isDev: AppConfig.isInternal,
      ),
    );
  }
}
