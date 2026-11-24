import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/shared/notice_pill.dart';

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

    expect(find.byType(SoliplexButton), findsNothing);
  });

  testWidgets('wraps a message too long for one line rather than cut it',
      (tester) async {
    // Two lines at the viewer's narrowest, in the test font's square glyphs.
    const message = 'Download failed now';
    await tester.pumpWidget(_wrap(Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 360,
        child: NoticePill(
          icon: Icons.error_outline,
          background: Colors.white,
          foreground: Colors.black,
          message: message,
          actionLabel: 'Retry',
          onAction: () {},
          onDismiss: () {},
        ),
      ),
    )));

    final text = tester.renderObject<RenderParagraph>(find.text(message));
    expect(text.size.height, greaterThan(text.preferredLineHeight));
    expect(text.didExceedMaxLines, isFalse);
  });

  testWidgets('names its dismiss to a screen reader', (tester) async {
    await tester.pumpWidget(_wrap(NoticePill(
      icon: Icons.check_circle_outline,
      background: Colors.white,
      foreground: Colors.black,
      message: 'Uploaded a.csv',
      onDismiss: () {},
    )));

    expect(find.byTooltip('Dismiss'), findsOneWidget);
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
