import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';

/// Each text leaf with the colour it renders in, inherited from its parents.
Iterable<({String text, Color? color})> _leaves(
  Iterable<InlineSpan> spans, [
  Color? inherited,
]) sync* {
  for (final span in spans.whereType<TextSpan>()) {
    final color = span.style?.color ?? inherited;
    if (span.text != null) yield (text: span.text!, color: color);
    yield* _leaves(span.children ?? const [], color);
  }
}

String _text(Iterable<InlineSpan> spans) =>
    _leaves(spans).map((leaf) => leaf.text).join();

void main() {
  group('highlightSpans', () {
    test("colours a JSON string with the theme's string style", () {
      final spans = highlightSpans('{"a": "b"}', 'json', githubTheme);

      final string = _leaves(spans).where((leaf) => leaf.text == '"b"');
      expect(string, hasLength(1));
      expect(string.single.color, githubTheme['string']!.color);
    });

    test('falls back to plain text for an unknown language', () {
      final spans = highlightSpans('graph TD', 'mermaid', githubTheme);

      expect(_text(spans), 'graph TD');
    });

    test('of empty code is empty text', () {
      expect(_text(highlightSpans('', 'json', githubTheme)), '');
    });
  });

  group('CodeView', () {
    testWidgets('is selectable by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodeView(code: '{"a": 1}', language: 'json')),
        ),
      );

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('with selectable false joins a SelectionArea', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: CodeView(
                code: '{"a": 1}',
                language: 'json',
                selectable: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('"a"', findRichText: true), findsOneWidget);
    });
  });
}
