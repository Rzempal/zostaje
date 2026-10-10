import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karton_subs/theme/app_theme.dart';
import 'package:karton_subs/widgets/aurora_chip.dart';
import 'package:karton_subs/widgets/plan_widgets.dart';

// Grupa planu z pigułkami (Wydatki, Pożyczki): „Razem" pokazuje listy części
// jedna pod drugą, pigułka części — tylko jej listę. Wybór trzyma tu zwykły
// stan widżetu (bez bazy), więc pigułki da się klikać w teście.
void main() {
  PlanGroupPart part(String id, String label, double amount, String row) =>
      PlanGroupPart(
        id: id,
        label: label,
        amount: amount,
        color: Colors.red,
        children: [Text(row)],
      );

  Future<void> pump(
    WidgetTester tester,
    List<PlanGroupPart> parts, {
    String? initial,
  }) async {
    var only = initial;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppColors.active),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListView(
              children: [
                PlanGroup(
                  title: 'Wydatki',
                  total: -150,
                  collapsed: false,
                  onToggle: () {},
                  parts: parts,
                  only: only,
                  onShow: (id) => setState(() => only = id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool lit(WidgetTester tester, String label) => tester
      .widget<AuroraChip>(
        find.ancestor(
          of: find.textContaining(label),
          matching: find.byType(AuroraChip),
        ),
      )
      .selected;

  testWidgets('„Razem" zapala wszystkie pigułki i pokazuje obie listy, '
      'pigułka części — tylko swoją', (tester) async {
    await pump(tester, [
      part('pos', 'Pozycje', -100, 'Czynsz'),
      part('sub', 'Subskrypcje', -50, 'Netflix'),
    ]);
    expect(find.text('Czynsz'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(
      [
        lit(tester, 'Razem'),
        lit(tester, 'Pozycje'),
        lit(tester, 'Subskrypcje'),
      ],
      [true, true, true],
    );

    await tester.tap(find.textContaining('Subskrypcje'));
    await tester.pumpAndSettle();
    expect(find.text('Czynsz'), findsNothing);
    expect(find.text('Netflix'), findsOneWidget);
    expect(
      [
        lit(tester, 'Razem'),
        lit(tester, 'Pozycje'),
        lit(tester, 'Subskrypcje'),
      ],
      [false, false, true],
    );

    await tester.tap(find.text('Razem'));
    await tester.pumpAndSettle();
    expect(find.text('Czynsz'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });

  testWidgets('Jedna część: bez pigułek; zapamiętana nieobecna część = '
      '„Razem"', (tester) async {
    await pump(tester, [
      part('pos', 'Pozycje', -100, 'Czynsz'),
    ], initial: 'sub');
    expect(find.text('Razem'), findsNothing);
    expect(find.text('Czynsz'), findsOneWidget);
  });
}
