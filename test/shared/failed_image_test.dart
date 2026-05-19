import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/failed_image.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('FailedImage', () {
    testWidgets('renders a broken-image icon when source is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const FailedImage(label: 'Avatar')));

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(find.text('Avatar'), findsOneWidget);
    });

    testWidgets('hides the source toggle and copy button when source is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const FailedImage(label: 'Avatar')));

      expect(find.byIcon(Icons.code), findsNothing);
      expect(find.byIcon(Icons.image), findsNothing);
      expect(find.byIcon(Icons.copy), findsNothing);
    });

    testWidgets(
        'falls back to a default label when no label is provided and source is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const FailedImage()));

      // Some descriptive label is rendered for accessibility / display.
      expect(find.byType(Semantics), findsWidgets);
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    testWidgets('shows source toggle and copy button when source is provided',
        (tester) async {
      await tester.pumpWidget(_wrap(const FailedImage(
        source: 'https://example.com/foo.png',
        label: 'Cover',
      )));

      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      // Source view is not visible until toggled.
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('toggling reveals the source as selectable monospace text',
        (tester) async {
      await tester.pumpWidget(_wrap(const FailedImage(
        source: 'https://example.com/foo.png',
        label: 'Cover',
      )));

      await tester.tap(find.byIcon(Icons.code));
      await tester.pump();

      // Preview is hidden, source view is shown.
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('https://example.com/foo.png'), findsOneWidget);

      // Toggle icon swaps to "show preview".
      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.byIcon(Icons.code), findsNothing);
    });

    testWidgets('toggling back returns to the preview', (tester) async {
      await tester.pumpWidget(_wrap(const FailedImage(
        source: 'https://example.com/foo.png',
        label: 'Cover',
      )));

      await tester.tap(find.byIcon(Icons.code));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.image));
      await tester.pump();

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets(
        'source view is bounded — a long source does not blow up the layout',
        (tester) async {
      // A long data URI (~2KB of base64-shaped chars). Without the bounded
      // ConstrainedBox + SingleChildScrollView, the SelectableText would lay
      // out at its natural height and the widget would exceed the viewport.
      final longSource = 'data:image/png;base64,${'A' * 2000}';
      await tester.pumpWidget(_wrap(SizedBox(
        height: 400,
        child: FailedImage(source: longSource, label: 'big'),
      )));

      await tester.tap(find.byIcon(Icons.code));
      await tester.pump();

      // The selectable text exists, but a scroll view bounds it.
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
