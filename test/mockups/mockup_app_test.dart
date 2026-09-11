import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/mockups/mockup.dart';
import 'package:soliplex_frontend/src/mockups/mockup_app.dart';
import 'package:soliplex_frontend/src/mockups/mockups.dart';

void main() {
  final probe = Mockup(
    name: 'Probe',
    build: (context) => Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => Text(
          'box=${constraints.maxWidth.round()} '
          'media=${MediaQuery.sizeOf(context).width.round()} '
          'brightness=${Theme.of(context).brightness.name}',
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MockupApp(mockups: [probe]));
    await tester.tap(find.text('Probe'));
    await tester.pumpAndSettle();
  }

  testWidgets('a mockup opens in the brand theme, filling the window',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);

    expect(find.text('box=1000 media=1000 brightness=light'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('Probe')));
    expect(theme.extension<SoliplexTheme>(), isNotNull);
  });

  testWidgets('the viewport knob pins both the box and MediaQuery',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);

    await tester.tap(find.text('600'));
    await tester.pumpAndSettle();
    expect(find.text('box=600 media=600 brightness=light'), findsOneWidget);

    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    expect(find.text('box=1000 media=1000 brightness=light'), findsOneWidget);
  });

  testWidgets('the brightness knob flips the theme', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);

    await tester.tap(find.byTooltip('Switch to dark'));
    await tester.pumpAndSettle();
    expect(find.textContaining('brightness=dark'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to light'));
    await tester.pumpAndSettle();
    expect(find.textContaining('brightness=light'), findsOneWidget);
  });

  testWidgets('every registered mockup builds', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MockupApp(mockups: mockups));
    for (final mockup in mockups) {
      await tester.tap(find.text(mockup.name));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: mockup.name);
      await tester.tap(find.byTooltip('Back to mockups'));
      await tester.pumpAndSettle();
    }
  });
}
