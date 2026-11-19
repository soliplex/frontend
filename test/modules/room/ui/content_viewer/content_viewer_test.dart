import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/content_viewer.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_body.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/content/json_viewer.dart';
import 'package:soliplex_frontend/src/shared/json_tree_view.dart';

Widget _inline(ContentViewer viewer) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: viewer)),
    );

void main() {
  testWidgets('plaintext shows no label', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'plaintext',
      content: 'just words',
      fill: false,
    )));

    expect(find.text('plaintext'), findsNothing);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(
        find.textContaining('just words', findRichText: true), findsOneWidget);
  });

  testWidgets('python shows its label and Copy code', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'python',
      content: 'print(1)',
      fill: false,
    )));

    expect(find.text('python'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
  });

  testWidgets('svg routes to SvgBody', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'svg',
      content: '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><circle cx="5" cy="5" r="4"/></svg>',
      fill: false,
    )));

    expect(find.byType(SvgBody), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^SVG image\n')), findsOneWidget);
  });

  testWidgets('json routes to JsonViewer, labelled JSON', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'json',
      content: '{"a": 1}',
      fill: false,
    )));

    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.byTooltip('Copy JSON'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^JSON\n')), findsOneWidget);
  });

  testWidgets('chat JSON shows as written, a workdir file formatted',
      (tester) async {
    const compact = '{"a":[1,2]}';
    Widget viewer({required bool fill}) => _inline(ContentViewer(
          language: 'json',
          content: compact,
          fill: fill,
        ));

    await tester.pumpWidget(viewer(fill: false));
    expect(tester.widget<CodeView>(find.byType(CodeView)).code, compact);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ContentViewer(language: 'json', content: compact, fill: true),
        ),
      ),
    ));
    expect(
      tester.widget<CodeView>(find.byType(CodeView)).code,
      '{\n  "a": [\n    1,\n    2\n  ]\n}',
    );
  });

  testWidgets('semantics label is Code block in python', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'python',
      content: 'print(1)',
      fill: false,
    )));

    // The header's label text merges into the block's label after it.
    expect(find.bySemanticsLabel(RegExp(r'^Code block in python\n')),
        findsOneWidget);
  });

  testWidgets('semantics label is Code block for plaintext', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'plaintext',
      content: 'just words',
      fill: false,
    )));

    expect(find.bySemanticsLabel(RegExp(r'^Code block$')), findsOneWidget);
  });

  group('filling a page', () {
    Widget page(String content) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ContentViewer(
                language: 'python',
                content: content,
                fill: true,
              ),
            ),
          ),
        );

    // The code's own background, painted by CodeView.
    Finder codeSurface() => find
        .descendant(
            of: find.byType(CodeView), matching: find.byType(ColoredBox))
        .first;

    testWidgets('a short file paints code down to the page bottom',
        (tester) async {
      await tester.pumpWidget(page('a = 1\nb = 2\nc = 3'));

      final surface = tester.getRect(codeSurface());
      final pageBottom = tester.getBottomLeft(find.byType(ContentViewer)).dy;
      expect(
          pageBottom - surface.bottom, lessThanOrEqualTo(SoliplexSpacing.s3));
    });

    testWidgets('a long file still scrolls under a pinned header',
        (tester) async {
      await tester.pumpWidget(
        page(List.generate(200, (i) => 'line_$i = $i').join('\n')),
      );
      final headerTop = tester.getTopLeft(find.byTooltip('Copy code')).dy;
      final codeTop = tester.getTopLeft(find.byType(CodeView)).dy;

      final body = tester.state<ScrollableState>(find
          .ancestor(
            of: find.byType(CodeView),
            matching: find.byType(Scrollable),
          )
          .first);
      body.position.jumpTo(400);
      await tester.pump();

      expect(tester.getTopLeft(find.byTooltip('Copy code')).dy, headerTop);
      expect(tester.getTopLeft(find.byType(CodeView)).dy, lessThan(codeTop));
    });
  });

  group('over maxHighlightedLength', () {
    const notice = 'Too large to highlight; showing plain text.';
    final overJson = '{"a": "${'x' * maxHighlightedLength}"}';
    // Pretty-printed, `{"a": "<x>"}` gains a newline before and after the
    // entry and a two-space indent.
    final prettyAtLimit = '{\n  "a": ""\n}'.length;
    final jsonPrettyAtLimit =
        '{"a": "${'x' * (maxHighlightedLength - prettyAtLimit)}"}';

    testWidgets(
        'json over the limit shows plain text, the notice and no switch',
        (tester) async {
      await tester.pumpWidget(_inline(ContentViewer(
        language: 'json',
        content: overJson,
        fill: false,
      )));

      expect(find.byType(JsonViewer), findsOneWidget);
      expect(find.text(notice), findsOneWidget);
      final body = tester.widget<CodeView>(find.byType(CodeView));
      expect(body.language, 'plaintext');
      expect(body.code, overJson);
      expect(find.text('Tree'), findsNothing);
      expect(find.text('json'), findsOneWidget);
      expect(find.byTooltip('Copy JSON'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^JSON\n')), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('the notice is a neutral bar in $brightness', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContentViewer(
                language: 'json',
                content: overJson,
                fill: false,
              ),
            ),
          ),
        ));
        final colors = Theme.of(tester.element(find.text(notice))).colorScheme;

        final bar = tester.widget<Container>(find
            .ancestor(of: find.text(notice), matching: find.byType(Container))
            .first);
        expect(bar.color, colors.surfaceContainerHighest);
        final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
        expect(icon.color, colors.onSurfaceVariant);
        expect(
          tester.widget<Text>(find.text(notice)).style?.color,
          colors.onSurfaceVariant,
        );
        expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
      });
    }

    testWidgets('json whose pretty-print is at the limit offers Tree / Source',
        (tester) async {
      expect(
        const JsonEncoder.withIndent('  ')
            .convert(jsonDecode(jsonPrettyAtLimit))
            .length,
        maxHighlightedLength,
      );
      await tester.pumpWidget(_inline(ContentViewer(
        language: 'json',
        content: jsonPrettyAtLimit,
        fill: false,
      )));

      expect(find.text(notice), findsNothing);
      expect(find.text('Tree'), findsOneWidget);
    });

    testWidgets('json over the limit shows the notice while streaming',
        (tester) async {
      await tester.pumpWidget(_inline(ContentViewer(
        language: 'json',
        content: overJson,
        fill: false,
        isStreaming: true,
      )));

      expect(find.text(notice), findsOneWidget);
    });

    testWidgets(
        'json crossing the limit and back keeps its State and its Tree view',
        (tester) async {
      const under = '{"a": 1}';
      await tester.pumpWidget(_inline(const ContentViewer(
        language: 'json',
        content: under,
        fill: false,
      )));
      final state = tester.state(find.byType(JsonViewer));
      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonTreeView), findsOneWidget);

      await tester.pumpWidget(_inline(ContentViewer(
        language: 'json',
        content: overJson,
        fill: false,
      )));

      expect(tester.state(find.byType(JsonViewer)), same(state));
      expect(find.text(notice), findsOneWidget);
      expect(find.byType(JsonTreeView), findsNothing);
      expect(find.text('Tree'), findsNothing);

      await tester.pumpWidget(_inline(const ContentViewer(
        language: 'json',
        content: under,
        fill: false,
      )));

      expect(tester.state(find.byType(JsonViewer)), same(state));
      expect(find.text(notice), findsNothing);
      expect(find.byType(JsonTreeView), findsOneWidget);
    });

    testWidgets('code at the limit is highlighted', (tester) async {
      await tester.pumpWidget(_inline(ContentViewer(
        language: 'python',
        content: '#' * maxHighlightedLength,
        fill: false,
      )));

      expect(find.text(notice), findsNothing);
      expect(tester.widget<CodeView>(find.byType(CodeView)).language, 'python');
    });

    testWidgets(
        'code over the limit is not highlighted and keeps its label '
        'and Copy code', (tester) async {
      await tester.pumpWidget(_inline(ContentViewer(
        language: 'python',
        content: '#' * (maxHighlightedLength + 1),
        fill: false,
      )));

      expect(find.text(notice), findsOneWidget);
      expect(
          tester.widget<CodeView>(find.byType(CodeView)).language, 'plaintext');
      expect(find.text('python'), findsOneWidget);
      expect(find.byTooltip('Copy code'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Code block in python\n')),
          findsOneWidget);
    });

    testWidgets('plaintext over the limit shows no notice and no label',
        (tester) async {
      await tester.pumpWidget(_inline(ContentViewer(
        language: 'plaintext',
        content: 'a' * (maxHighlightedLength + 1),
        fill: false,
      )));

      expect(find.text(notice), findsNothing);
      expect(
          tester.widget<CodeView>(find.byType(CodeView)).language, 'plaintext');
      expect(find.text('plaintext'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Code block$')), findsOneWidget);
    });
  });
}
