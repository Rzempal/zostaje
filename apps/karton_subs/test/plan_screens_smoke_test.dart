import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:karton_subs/controllers/budget_controller.dart';
import 'package:karton_subs/controllers/plan_controller.dart';
import 'package:karton_subs/controllers/subscription_controller.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/screens/card_loan_form_screen.dart';
import 'package:karton_subs/screens/dashboard_screen.dart';
import 'package:karton_subs/screens/plan_position_form_screen.dart';
import 'package:karton_subs/screens/plan_position_screen.dart';
import 'package:karton_subs/screens/planning_screen.dart';
import 'package:karton_subs/services/notification_service.dart';
import 'package:karton_subs/services/storage_service.dart';
import 'package:karton_subs/services/update_service.dart';
import 'package:karton_subs/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'support/hive_test_env.dart';

// Ekrany planu rocznego (ADR-035) rysowane z przykładowymi danymi na wąskim
// telefonie (360 × 800). Wyłapuje błędy, których testy logiki nie widzą:
// brakujący dostawca danych, tekst wychodzący poza wiersz, wyjątek przy
// budowaniu widoku miesiąca.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUpAll(() async {
    await initializeDateFormatting('pl');
    storage = await setUpHiveStorage();
  });
  tearDownAll(tearDownHiveStorage);

  setUp(() async {
    await resetStorage(storage);
    Subscription.devDateOverride = DateTime(2026, 10, 6);
  });
  tearDown(() => Subscription.devDateOverride = null);

  Map<String, PlanMonth> everyMonth(double amount, {int year = 2026}) => {
    for (var m = 1; m <= 12; m++)
      planMonthKey(year, m): PlanMonth(amount: amount),
  };

  Future<void> seed() async {
    PlanPosition pos(
      String id,
      PlanKind kind,
      Map<String, PlanMonth> months, {
      String? link,
      int? day,
    }) => PlanPosition(
      id: id,
      budgetId: kBudgetPersonal,
      name: 'Pozycja o dość długiej nazwie $id',
      kind: kind,
      currency: Currency.PLN,
      categoryId: 'cat_streaming',
      paymentMethod: 'Revolut',
      day: day,
      months: months,
      linkId: link,
      createdAt: DateTime(2026, 1, 1),
    );
    await storage.savePlanPosition(
      pos('pensja', PlanKind.income, everyMonth(12345.67), day: 10),
    );
    await storage.savePlanPosition(
      pos('czynsz', PlanKind.expense, everyMonth(2500), day: 5),
    );
    await storage.savePlanPosition(
      pos('poz', PlanKind.cardLoan, {
        '2026-10': const PlanMonth(amount: 3000, day: 7),
      }, link: 'L1'),
    );
    await storage.savePlanPosition(
      pos('spl', PlanKind.cardRepayment, {
        '2026-11': const PlanMonth(amount: 3090, day: 25),
      }, link: 'L1'),
    );
    await storage.saveSubscription(
      Subscription(
        id: 'netflix',
        name: 'Netflix',
        amount: 60,
        currency: Currency.PLN,
        billingCycle: BillingCycle.monthly,
        startDate: DateTime(2026, 1, 15),
        dataDodania: DateTime(2026, 1, 1),
      ),
    );
  }

  /// Domyślnie wąski telefon: 360 px szerokości. [height] wyższy, gdy test ma
  /// widzieć całą listę bez przewijania (lista buduje tylko to, co widać).
  /// [width] szerszy tylko dla istniejących nagłówków kalendarza — czcionka
  /// testowa ma litery jak kwadraty, więc „Październik 2026" zajmuje w teście
  /// dwa razy więcej miejsca niż na telefonie.
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    double width = 360,
    double height = 800,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final subs = SubscriptionController(storage, NotificationService());
    final budget = BudgetController(storage, subs);
    final plan = PlanController(storage, budget);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider.value(value: subs),
          ChangeNotifierProvider.value(value: budget),
          ChangeNotifierProvider.value(value: plan),
          ChangeNotifierProvider(create: (_) => UpdateService()),
        ],
        child: MaterialApp(
          theme: AppTheme.build(AppColors.active),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Planowanie: rok i miesiąc rysują się bez błędów', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await pump(tester, const PlanningScreen(), height: 1600);
    expect(find.text('Wpływy'), findsWidgets);
    expect(find.text('Karta kredytowa'), findsOneWidget);
    // Części grupy Wydatki: przełącznik z sumą jest zarazem ich nagłówkiem
    // (bez osobnego podtytułu z tą samą nazwą).
    expect(find.textContaining('Subskrypcje -'), findsOneWidget);
    expect(find.textContaining('Pozycje -'), findsOneWidget);
    expect(find.text('Subskrypcje'), findsNothing);

    // „Dzisiaj" = październik 2026 (data testowa); chip „paź" leży poza
    // widocznym fragmentem poziomego paska miesięcy.
    await tester.tap(find.text('Dzisiaj'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zostaje · paź 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pusty plan pokazuje zachętę zamiast list', (tester) async {
    await pump(tester, const PlanningScreen());
    expect(find.textContaining('Plan jest pusty'), findsOneWidget);
  });

  testWidgets('Szczegóły pozycji: siatka roku i szybkie wypełnianie', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await pump(
      tester,
      const PlanPositionScreen(positionId: 'czynsz', initialYear: 2026),
      height: 1400,
    );
    expect(find.text('paź'), findsOneWidget);
    expect(find.text('Szybkie wypełnianie'), findsOneWidget);

    // Rok bez planu — każdy miesiąc bez kwoty, „Puste" obejmie wszystkie.
    await tester.tap(find.byIcon(LucideIcons.chevronRight).first);
    await tester.pumpAndSettle();
    expect(find.text('brak kwoty'), findsNWidgets(12));
    expect(find.text('Puste (12)'), findsOneWidget);

    // „Puste" bez kwoty nie robi nic po cichu — mówi, czego brakuje.
    await tester.tap(find.text('Puste (12)'));
    await tester.pumpAndSettle();
    expect(find.text('Wpisz kwotę'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Szczegóły pozycji: miesiące poza okresem raty są zablokowane', (
    tester,
  ) async {
    await tester.runAsync(
      () => storage.savePlanPosition(
        PlanPosition(
          id: 'rata',
          budgetId: kBudgetPersonal,
          name: 'ING / Alior: Fold 8',
          kind: PlanKind.expense,
          currency: Currency.PLN,
          day: 28,
          months: {
            for (final m in [9, 10, 12])
              planMonthKey(2026, m): const PlanMonth(amount: 226.21),
          },
          periodStart: '2026-09',
          periodEnd: '2027-07',
          createdAt: DateTime(2026, 9, 1),
        ),
      ),
    );
    // Szerzej niż telefon: pasek zaznaczania („Zaznacz wszystkie") w czcionce
    // testowej (litery jak kwadraty) nie mieści się w 360 px, choć na
    // telefonie ma zapas. Siatkę i panel w 360 px sprawdza test obok.
    await pump(
      tester,
      const PlanPositionScreen(positionId: 'rata', initialYear: 2026),
      width: 480,
      height: 1400,
    );
    expect(find.textContaining('wrz 2026 – lip 2027 · 11 mies.'), findsOneWidget);
    expect(find.text('przed startem'), findsNWidgets(8));
    // Listopad bez kwoty to jedyny „pusty" miesiąc w okresie.
    expect(find.text('Puste (1)'), findsOneWidget);

    // Dotknięcie szarego miesiąca wyjaśnia, zamiast nic nie robić…
    await tester.tap(find.text('sty'));
    await tester.pumpAndSettle();
    expect(find.textContaining('przed startem pozycji'), findsOneWidget);

    // …a przytrzymanie go nie zaznacza.
    await tester.longPress(find.text('lut'));
    await tester.pumpAndSettle();
    expect(find.text('Zaznaczone (0)'), findsOneWidget);

    // Przytrzymanie zaczyna zaznaczanie, kolejne zaznacza zakres.
    await tester.longPress(find.text('wrz'));
    await tester.pumpAndSettle();
    expect(find.text('Zaznaczone (1)'), findsOneWidget);
    await tester.longPress(find.text('gru'));
    await tester.pumpAndSettle();
    expect(find.text('Zaznaczone (4)'), findsOneWidget);

    // Rok 2027: po lipcu rata się kończy.
    await tester.tap(find.byIcon(LucideIcons.chevronRight).first);
    await tester.pumpAndSettle();
    expect(find.text('po zakończeniu'), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Formularz pozycji i pożyczki z karty', (tester) async {
    await pump(tester, const PlanPositionFormScreen(initialYear: 2026));
    expect(find.textContaining('zaznaczone: 12'), findsOneWidget);

    await pump(tester, const CardLoanFormScreen());
    expect(find.text('Brak karty kredytowej'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Budżet: statystyki i kalendarz z planu', (tester) async {
    await tester.runAsync(seed);
    await pump(tester, const DashboardScreen(), width: 600);
    expect(find.text('Średnio miesięcznie'), findsOneWidget);

    await tester.tap(find.text('Kalendarz'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
