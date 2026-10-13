import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/notice_pill.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders no action when none is given', (tester) async {
    await tester.pumpWidget(_wrap(NoticePill(
      icon: Icons.check_circle_outline,
      background: Colors.white,
      foreground: Colors.black,
      message: 'Uploaded a.csv',
      onDismiss: () {},
    )));

    expect(find.text('Uploaded a.csv'), findsOneWidget);
    expect(find.byType(SoliplexButton), findsNothing);
  });

  testWidgets('renders the action when given, and tapping it runs onAction',
      (tester) async {
    var actions = 0;
    await tester.pumpWidget(_wrap(NoticePill(
      icon: Icons.check_circle_outline,
      background: Colors.white,
      foreground: Colors.black,
      message: 'Added a.csv to the workspace',
      onDismiss: () {},
      actionLabel: 'Show',
      onAction: () => actions++,
    )));

    expect(
      find.descendant(
        of: find.byType(SoliplexButton),
        matching: find.text('Show'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Show'));

    expect(actions, 1);
  });
}
