import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/svg_preview.dart';

void main() {
  group('CodeBlockBuilder', () {
    testWidgets('renders fenced code block with copy button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '```dart\nvoid main() {}\n```',
            ),
          ),
        ),
      );

      expect(find.byTooltip('Copy code'), findsOneWidget);
    });

    testWidgets('shows language label for non-plaintext language',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '```dart\nvoid main() {}\n```',
            ),
          ),
        ),
      );

      expect(find.text('dart'), findsOneWidget);
    });

    testWidgets('does not show language label for plain fenced code block',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '```\nsome plain text\n```',
            ),
          ),
        ),
      );

      // Copy button is still present
      expect(find.byTooltip('Copy code'), findsOneWidget);
      // No language label rendered
      expect(find.text('plaintext'), findsNothing);
    });

    testWidgets('SVG block shows preview/source toggle and copy button',
        (tester) async {
      const svgCode = '<svg xmlns="http://www.w3.org/2000/svg">'
          '<circle cx="50" cy="50" r="40"/>'
          '</svg>';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FlutterMarkdownPlusRenderer(
                data: '```svg\n$svgCode\n```',
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Show source'), findsOneWidget);
      expect(find.byTooltip('Copy SVG'), findsOneWidget);
    });

    testWidgets('SVG block toggles to source view', (tester) async {
      const svgCode = '<svg xmlns="http://www.w3.org/2000/svg">'
          '<circle cx="50" cy="50" r="40"/>'
          '</svg>';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FlutterMarkdownPlusRenderer(
                data: '```svg\n$svgCode\n```',
              ),
            ),
          ),
        ),
      );

      // Initially shows the preview toggle
      expect(find.byTooltip('Show source'), findsOneWidget);
      expect(find.byTooltip('Show preview'), findsNothing);

      await tester.tap(find.byTooltip('Show source'));
      await tester.pump();

      // After tap, shows preview toggle (source is now visible)
      expect(find.byTooltip('Show preview'), findsOneWidget);
      expect(find.byTooltip('Show source'), findsNothing);
    });

    testWidgets('tapping the SVG preview opens a zoomable dialog',
        (tester) async {
      const svgCode = '<svg xmlns="http://www.w3.org/2000/svg">'
          '<circle cx="50" cy="50" r="40"/>'
          '</svg>';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FlutterMarkdownPlusRenderer(
                data: '```svg\n$svgCode\n```',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The inline preview is not itself the full-size viewer.
      expect(find.byType(SvgPreview), findsNothing);

      // The preview is laid out at zero size until the SVG rasterizes, so a
      // hit-test tap misses; invoke the wrapper's onTap directly.
      final gesture = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.byType(SvgPicture),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      gesture.onTap!();
      await tester.pumpAndSettle();

      // The dialog frames the SVG in the shared zoomable SVG viewer, which owns
      // its own parse-failure fallback (no zoom/rotate chrome over a failure).
      expect(find.byType(SvgPreview), findsOneWidget);
    });
  });
}
