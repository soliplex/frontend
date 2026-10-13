import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('the action label takes the pill foreground, not primary',
      (tester) async {
    // A brand accent as primary can fail contrast on the pill's container;
    // the foreground is the color derived to read on it.
    late Color foreground;
    late Color primary;
    await tester.pumpWidget(_wrap(Builder(builder: (context) {
      final colors = SoliplexTheme.of(context).colors;
      foreground = colors.onSuccessContainer;
      primary = Theme.of(context).colorScheme.primary;
      return NoticePill(
        icon: Icons.check_circle_outline,
        background: colors.successContainer,
        foreground: foreground,
        message: 'Added a.csv to the workspace',
        onDismiss: () {},
        actionLabel: 'Show',
        onAction: () {},
      );
    })));

    final label = tester.renderObject<RenderParagraph>(find.text('Show'));
    expect(label.text.style?.color, foreground);
    expect(foreground, isNot(primary), reason: 'the test must tell them apart');
  });
}
