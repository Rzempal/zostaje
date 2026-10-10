import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:karton_subs/controllers/budget_controller.dart';
import 'package:karton_subs/controllers/plan_controller.dart';
import 'package:karton_subs/controllers/subscription_controller.dart';
import 'package:karton_subs/models/plan_position.dart';
import 'package:karton_subs/models/subscription.dart';
import 'package:karton_subs/screens/add_subscription_screen.dart';
import 'package:karton_subs/screens/budgets_screen.dart';
import 'package:karton_subs/screens/card_loan_form_screen.dart';
import 'package:karton_subs/screens/dashboard_screen.dart';
import 'package:karton_subs/screens/installment_loan_form_screen.dart';
import 'package:karton_subs/screens/plan_position_form_screen.dart';
import 'package:karton_subs/screens/plan_position_screen.dart';
import 'package:karton_subs/screens/planning_screen.dart';
import 'package:karton_subs/services/notification_service.dart';
import 'package:karton_subs/services/storage_service.dart';
import 'package:karton_subs/services/update_service.dart';
import 'package:karton_subs/theme/app_theme.dart';
import 'package:karton_subs/widgets/workspace_top_bar.dart';
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
      pos('poz', PlanKind.loan, {
        '2026-10': const PlanMonth(amount: 3000, day: 7),
      }, link: 'L1'),
    );
    await storage.savePlanPosition(
      pos('spl', PlanKind.loanRepayment, {
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

  /// Czy element widać w całości w poziomie ekranu [width] (domyślny telefon).
  bool onScreen(WidgetTester tester, Finder finder, {double width = 360}) {
    final rect = tester.getRect(finder);
    return rect.left >= 0 && rect.right <= width;
  }

  testWidgets('Planowanie: rok i miesiąc rysują się bez błędów', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await pump(tester, const PlanningScreen(), height: 1600);
    // Start na bieżącym miesiącu (data testowa: październik 2026); chip „paź"
    // sam wjechał na widok paska miesięcy.
    expect(find.textContaining('Zostaje · paź 2026'), findsOneWidget);
    expect(onScreen(tester, find.text('paź')), isTrue);
    expect(find.text('Wpływy'), findsWidgets);
    expect(find.text('Pożyczki'), findsOneWidget);
    // Pigułki grupy Wydatki: „Razem" i części z sumami (bez podtytułów
    // z tą samą nazwą).
    expect(find.text('Razem'), findsOneWidget);
    expect(find.textContaining('Subskrypcje -'), findsOneWidget);
    expect(find.textContaining('Pozycje -'), findsOneWidget);
    expect(find.text('Subskrypcje'), findsNothing);

    // Cały rok, a „Dzisiaj" w rogu paska wraca do bieżącego miesiąca.
    await tester.ensureVisible(find.text('Cały rok'));
    await tester.tap(find.text('Cały rok'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zostaje · paź 2026'), findsNothing);
    await tester.tap(find.text('Dzisiaj'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zostaje · paź 2026'), findsOneWidget);
    expect(onScreen(tester, find.text('paź')), isTrue);
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
    expect(
      find.textContaining('wrz 2026 – lip 2027 · 11 mies.'),
      findsOneWidget,
    );
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

  testWidgets('Formularz subskrypcji: budżet zmienia tylko menu ⋮', (
    tester,
  ) async {
    await tester.runAsync(seed);
    // Szerzej niż telefon: pasek szablonów i listy rozwijane w czcionce
    // testowej (litery jak kwadraty) nie mieszczą się w 360 px.
    // Jak pozycja i pożyczka: nowa subskrypcja trafia do aktywnego budżetu,
    // formularz nie ma wyboru budżetu (ADR-037)…
    await pump(tester, const AddSubscriptionScreen(), width: 600, height: 1600);
    expect(find.text('BUDŻET'), findsNothing);

    // …a w edycji przeniesienie i kopia są w menu ⋮ — jedno miejsce.
    final netflix = storage.getSubscription('netflix')!;
    await pump(
      tester,
      AddSubscriptionScreen(existing: netflix),
      width: 600,
      height: 1600,
    );
    expect(find.text('BUDŻET'), findsNothing);
    await tester.tap(find.byTooltip('Więcej'));
    await tester.pumpAndSettle();
    expect(find.text('Przenieś do budżetu…'), findsOneWidget);
    expect(find.text('Kopiuj do budżetu…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pożyczki: karta i pożyczka ratalna w jednej sekcji', (
    tester,
  ) async {
    await tester.runAsync(seed);
    final terms = PlanLoanTerms(
      principal: 2000,
      count: 12,
      installment: 166.67,
      rrso: 0,
      drawdown: DateTime(2026, 9, 13),
      firstMonth: '2026-10',
      day: 13,
    );
    PlanPosition part(String id, PlanKind kind, Map<String, PlanMonth> m) =>
        PlanPosition(
          id: id,
          budgetId: kBudgetPersonal,
          name: 'Odkurzacz',
          kind: kind,
          currency: Currency.PLN,
          months: m,
          linkId: 'L2',
          day: kind == PlanKind.loanRepayment ? 13 : null,
          periodStart: kind == PlanKind.loanRepayment ? '2026-10' : null,
          periodEnd: kind == PlanKind.loanRepayment ? '2027-09' : null,
          loanTerms: kind == PlanKind.loanRepayment ? terms : null,
          createdAt: DateTime(2026, 9, 13),
        );
    await tester.runAsync(() async {
      await storage.savePlanPosition(
        part('w', PlanKind.loan, {
          '2026-09': const PlanMonth(amount: 2000, day: 13),
        }),
      );
      await storage.savePlanPosition(
        part('r', PlanKind.loanRepayment, {
          for (var i = 0; i < 12; i++)
            planMonthKey(2026 + (9 + i) ~/ 12, (9 + i) % 12 + 1):
                const PlanMonth(amount: 166.67),
        }),
      );
      await storage.savePlanPosition(
        part('z', PlanKind.expense, {
          '2026-09': const PlanMonth(amount: 2000, day: 13),
        }),
      );
    });
    // Start na bieżącym miesiącu (październik 2026): rata 1, wypłata we wrześniu.
    await pump(tester, const PlanningScreen(), height: 2000);

    expect(find.text('Pożyczki'), findsOneWidget);
    expect(find.text('Karta kredytowa'), findsNothing);
    // Pigułki grupy „Pożyczki" — „Razem" i części z sumami, jak w „Wydatkach".
    expect(find.text('Razem'), findsNWidgets(2));
    expect(find.textContaining('Karta kredytowa '), findsOneWidget);
    expect(find.textContaining('Kredyty ratalne '), findsOneWidget);
    expect(find.textContaining('rata 1 z 12'), findsOneWidget);
    expect(find.textContaining('Pożyczki netto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pożyczka ratalna: trzy wartości liczą czwartą, cztery — '
      'sprawdzane', (tester) async {
    await pump(tester, const InstallmentLoanFormScreen(), height: 1800);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kwota wypłacona'),
      '2000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Liczba rat'),
      '12',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'RRSO %'), '0');
    await tester.pumpAndSettle();

    // Rata policzona i oznaczona jako wyliczona.
    expect(find.text('166,67'), findsOneWidget);
    expect(find.text('wyliczone'), findsOneWidget);
    expect(find.textContaining('rata wyliczona'), findsOneWidget);

    // Wpisana inna rata — cztery wartości się nie zgadzają.
    await tester.enterText(find.widgetWithText(TextFormField, 'Rata'), '170');
    await tester.pumpAndSettle();
    expect(find.textContaining('Dane się nie zgadzają'), findsOneWidget);
    expect(find.text('Przyjmij ratę 166,67'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Budżety: przełącznik z listą i ostrzeżenie przy usuwaniu', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await pump(
      tester,
      const Scaffold(body: Column(children: [WorkspaceTopBar()])),
    );
    // Przełącznik pokazuje aktywny budżet; lista — pozostałe i zarządzanie.
    await tester.tap(find.text('Osobisty'));
    await tester.pumpAndSettle();
    expect(find.text('Domowy'), findsOneWidget);
    expect(find.text('Zarządzaj budżetami'), findsOneWidget);
    // Bez wyboru: zmiana budżetu zapisuje się w bazie, a zapisy w czasie
    // testu ekranu się nie kończą (logikę wyboru sprawdza budgets_test).
    await tester.tapAt(const Offset(5, 790));
    await tester.pumpAndSettle();

    await pump(tester, const BudgetsScreen());
    expect(find.text('Nowy budżet'), findsOneWidget);
    await tester.tap(find.byTooltip('Więcej').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń budżet'));
    await tester.pumpAndSettle();
    // Osobisty ma pozycje i subskrypcję — ostrzeżenie i podpowiedź przeniesienia.
    expect(find.textContaining('Tego nie da się cofnąć'), findsOneWidget);
    expect(find.text('Przenieś i usuń…'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Budżet: statystyki i kalendarz z planu', (tester) async {
    await tester.runAsync(seed);
    await pump(tester, const DashboardScreen(), width: 600);
    expect(find.text('Średnio miesięcznie'), findsOneWidget);
    // Zakładki w jednej linii z przełącznikiem budżetu (pasek ekranu).
    expect(find.text('Statystyki'), findsOneWidget);
    expect(find.text('Osobisty'), findsOneWidget);

    await tester.tap(find.text('Kalendarz'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
