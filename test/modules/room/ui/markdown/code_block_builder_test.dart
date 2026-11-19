import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_body.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/code_block_builder.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/json_tree_view.dart';

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

    testWidgets('fence language JSON is labelled json', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '```JSON\n{"a": 1}\n```',
            ),
          ),
        ),
      );

      expect(find.text('json'), findsOneWidget);
      expect(find.text('JSON'), findsNothing);
    });

    testWidgets('a json fence starts in Source and offers Tree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '```json\n{"a":1}\n```',
            ),
          ),
        ),
      );

      expect(find.byType(CodeView), findsOneWidget);
      expect(find.byType(JsonTreeView), findsNothing);
      expect(find.text('Tree'), findsOneWidget);

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      expect(find.byType(JsonTreeView), findsOneWidget);
    });

    testWidgets('a partial json fence in a streaming message shows no notice',
        (tester) async {
      const notice = "This isn't valid JSON; showing the source.";
      Widget renderer({required bool streaming}) => MaterialApp(
            home: Scaffold(
              body: FlutterMarkdownPlusRenderer(
                data: '```json\n{"partial-fence-streaming": [1, 2\n```',
                isStreaming: streaming,
              ),
            ),
          );

      await tester.pumpWidget(renderer(streaming: true));
      await tester.pumpAndSettle();
      expect(find.text(notice), findsNothing);

      await tester.pumpWidget(renderer(streaming: false));
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('SVG block shows preview/source switch and copy button',
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

      expect(find.byType(SvgBody), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.byTooltip('Copy SVG'), findsOneWidget);
    });

    testWidgets('SVG block switches to source view', (tester) async {
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

      expect(find.byType(SvgPicture), findsOneWidget);

      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNothing);
      expect(
          find.textContaining('<circle', findRichText: true), findsOneWidget);
    });

    testWidgets('chat code joins the transcript selection', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: FlutterMarkdownPlusRenderer(
                data: '```dart\nvoid main() {}\n```',
                selectable: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SelectableText), findsNothing);
      final code = find.textContaining('void main', findRichText: true);
      expect(code, findsOneWidget);
      // A paragraph joins the area's selection only when it is registered
      // with the area.
      final paragraph = tester.renderObject<RenderParagraph>(code);
      expect(paragraph.registrar, isNotNull);
    });

    testWidgets('a json fence joins the transcript selection in both views',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: FlutterMarkdownPlusRenderer(
                data: '```json\n{"needle": 1}\n```',
                selectable: false,
              ),
            ),
          ),
        ),
      );

      void expectJoinsTranscriptArea() {
        expect(find.byType(SelectionArea), findsOneWidget);
        final text = find.textContaining('needle', findRichText: true);
        expect(text, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.registrar, isNotNull);
      }

      expect(find.byType(CodeView), findsOneWidget);
      expectJoinsTranscriptArea();

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      expect(find.byType(JsonTreeView), findsOneWidget);
      expectJoinsTranscriptArea();
    });

    testWidgets('outside FenceStreaming, a fence is treated as complete',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownBody(
              data: '```svg\nnot valid <svg outside fence streaming\n```',
              builders: {'pre': CodeBlockBuilder(selectable: true)},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't render this SVG."), findsOneWidget);
    });
  });
}
