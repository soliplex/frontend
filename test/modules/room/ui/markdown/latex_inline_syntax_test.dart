import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/latex_inline_syntax.dart';

/// The `latex` elements [source] parses into, as `(equation, MathStyle)`.
List<(String, String?)> _latexIn(String source) {
  final nodes =
      md.Document(inlineSyntaxes: [LatexInlineSyntax()]).parseInline(source);
  final found = <(String, String?)>[];
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'latex') {
      found.add((node.textContent, node.attributes['MathStyle']));
    }
    node.children?.forEach(visit);
  }

  nodes.forEach(visit);
  return found;
}

// `flutter_math_fork` is not a direct dependency, so match its widget by name.
final _math = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Math');

void main() {
  group('LatexInlineSyntax', () {
    test(r'$…$ is text math', () {
      expect(_latexIn(r'area is $\pi r^2$ here'), [(r'\pi r^2', 'text')]);
    });

    test(r'$$…$$ is display math', () {
      expect(_latexIn(r'$$x^2$$'), [('x^2', 'display')]);
    });

    test(r'\(…\) is text math', () {
      expect(_latexIn(r'so \(a+b\) holds'), [('a+b', 'text')]);
    });

    test(r'\[…\] is display math', () {
      expect(_latexIn(r'\[a+b\]'), [('a+b', 'display')]);
    });

    test('a parenthesis followed by a space is prose', () {
      expect(
        _latexIn('M/H/C-130H/J ( Note 2&5 ) Length 3,000 ft ; Width 60 ft'),
        isEmpty,
      );
    });

    test('a square bracket followed by a space is prose', () {
      expect(_latexIn('see [ Note 1 ] below'), isEmpty);
    });

    test(r'\ce{…} and \pu{…} are prose', () {
      expect(_latexIn(r'\ce{H2O} and \pu{1 mol}'), isEmpty);
    });

    test('dollar amounts are prose', () {
      expect(_latexIn(r'costs $5 and $10 today'), isEmpty);
    });
  });

  group('FlutterMarkdownPlusRenderer with LaTeX', () {
    testWidgets('renders a parenthesised note as text, not math',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '* M/H/C-130H/J ( Note 2&5 ) Length 3,000 ft ; '
                  'Width 60 ft',
            ),
          ),
        ),
      );

      expect(_math, findsNothing);
      expect(find.textContaining('( Note 2&5 )'), findsOneWidget);
    });

    testWidgets(r'renders $…$ as math', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(data: r'area $\pi r^2$ here'),
          ),
        ),
      );

      expect(_math, findsOneWidget);
    });
  });
}
