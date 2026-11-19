import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/content/content_frame.dart';
import 'package:soliplex_frontend/src/shared/content/json_text.dart';
import 'package:soliplex_frontend/src/shared/content/json_viewer.dart';
import 'package:soliplex_frontend/src/shared/json_tree_view.dart';

const _notice = "This isn't valid JSON; showing the source.";
const _emptyNotice = 'This JSON is empty.';
const _sizeNotice = 'Too large to highlight; showing plain text.';
const _depthNotice = 'Too deeply nested for a tree; showing the source.';

/// JSON text nesting [depth] arrays deep: `[[]]` for 2.
String _nestedSource(int depth) => '${'[' * depth}${']' * depth}';

CodeView _codeView(WidgetTester tester) =>
    tester.widget<CodeView>(find.byType(CodeView));

Widget _inline(JsonViewer viewer) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: viewer)),
    );

Finder _viewSwitch() => find.byType(SegmentedButton<ContentView>);

void main() {
  group('valid source', () {
    testWidgets('starts in the requested view: Tree', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      expect(find.byType(JsonTreeView), findsOneWidget);
      expect(find.byType(CodeView), findsNothing);
      expect(find.text('Tree'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
    });

    testWidgets('starts in the requested view: Source', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(find.byType(CodeView), findsOneWidget);
      expect(find.byType(JsonTreeView), findsNothing);
      expect(_viewSwitch(), findsOneWidget);
    });

    testWidgets('switching to Tree shows the tree', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      expect(find.byType(JsonTreeView), findsOneWidget);
      expect(find.byType(CodeView), findsNothing);
    });

    testWidgets('Source shows the pretty-print', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a":1}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(find.textContaining('  "a": 1'), findsOneWidget);
    });

    testWidgets('a number beyond double range shows as written',
        (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a":1e999}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('Tree'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(_codeView(tester).code, '{\n  "a": 1e999\n}');
    });

    testWidgets("a collapsible row's ink paints on the Tree's surface",
        (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": {"b": 1}}',
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      // An InkWell paints on its nearest Material; any opaque surface between
      // the two would hide the hover and splash.
      final rowInk = find.descendant(
        of: find.byType(JsonTreeView),
        matching: find.byType(InkWell),
      );
      final ancestors = tester
          .widgetList(find.ancestor(
              of: rowInk.first, matching: find.byWidgetPredicate((_) => true)))
          .toList();
      final inkMaterial = ancestors.whereType<Material>().first;
      final between = ancestors.takeWhile((widget) => widget is! Material);
      expect(between.whereType<ColoredBox>(), isEmpty);
      expect(inkMaterial.color, githubTheme['root']!.backgroundColor);
    });
  });

  group('content change', () {
    testWidgets(
        'invalid then valid content offers the switch and drops the notice',
        (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": ',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));
      expect(find.text(_notice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);

      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(find.text(_notice), findsNothing);
      expect(_viewSwitch(), findsOneWidget);
      expect(_codeView(tester).code, '{\n  "a": 1\n}');
    });

    testWidgets('valid then different valid shows the new content',
        (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"b": 2}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(_codeView(tester).code, '{\n  "b": 2\n}');
      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();
      expect(find.textContaining('b: 2', findRichText: true), findsOneWidget);
      expect(find.textContaining('a: 1', findRichText: true), findsNothing);
    });

    testWidgets('a different decoded value shows the new content',
        (tester) async {
      await tester.pumpWidget(_inline(JsonViewer.decoded(
        <String, Object?>{'a': 1},
        initialView: ContentView.source,
        fill: false,
      )));

      await tester.pumpWidget(_inline(JsonViewer.decoded(
        <String, Object?>{'a': 2},
        initialView: ContentView.source,
        fill: false,
      )));

      expect(_codeView(tester).code, '{\n  "a": 2\n}');
    });

    testWidgets('the chosen view survives new content', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));
      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"b": 2}',
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(find.byType(JsonTreeView), findsOneWidget);
      expect(find.byType(CodeView), findsNothing);
    });
  });

  group('invalid source', () {
    testWidgets('shows the raw text and notice, no switch', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": raw',
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      expect(find.textContaining('{"a": raw'), findsOneWidget);
      expect(find.text(_notice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);
      expect(find.byType(JsonTreeView), findsNothing);
    });

    testWidgets('notice is a neutral bar', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": broken',
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));
      final colors = Theme.of(tester.element(find.text(_notice))).colorScheme;

      final bar = tester.widget<Container>(find
          .ancestor(of: find.text(_notice), matching: find.byType(Container))
          .first);
      expect(bar.color, colors.surfaceContainerHighest);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.info_outline)).color,
        colors.onSurfaceVariant,
      );
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    });

    testWidgets('empty source says it is empty', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '',
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      expect(tester.takeException(), isNull);
      expect(find.text(_emptyNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
      expect(_viewSwitch(), findsNothing);
      expect(find.byType(CodeView), findsOneWidget);
    });

    testWidgets('whitespace-only source says nothing while streaming',
        (tester) async {
      Widget viewer({required bool isStreaming}) => _inline(JsonViewer.source(
            ' \n\t ',
            initialView: ContentView.rendered,
            fill: false,
            formatSource: true,
            isStreaming: isStreaming,
          ));

      await tester.pumpWidget(viewer(isStreaming: true));

      expect(find.text(_emptyNotice), findsNothing);
      expect(find.text(_notice), findsNothing);

      await tester.pumpWidget(viewer(isStreaming: false));

      expect(find.text(_emptyNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('while streaming shows no notice until it ends',
        (tester) async {
      const source = '{"streamed": "partial';
      Widget viewer({required bool isStreaming}) => _inline(JsonViewer.source(
            source,
            initialView: ContentView.source,
            fill: false,
            formatSource: true,
            isStreaming: isStreaming,
          ));

      await tester.pumpWidget(viewer(isStreaming: true));

      expect(find.text(_notice), findsNothing);

      await tester.pumpWidget(viewer(isStreaming: false));

      expect(find.text(_notice), findsOneWidget);
    });

    testWidgets('showFailureNotice false hides the notice', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        'not json',
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
        showFailureNotice: false,
      )));

      expect(find.text(_notice), findsNothing);
      expect(find.textContaining('not json'), findsOneWidget);
    });
  });

  group('rendering budget', () {
    testWidgets('invalid JSON over the limit shows plain text', (tester) async {
      final source = '{' * (maxHighlightedLength + 1);
      await tester.pumpWidget(_inline(JsonViewer.source(
        source,
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      expect(find.text(_sizeNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
      expect(_viewSwitch(), findsNothing);
      expect(_codeView(tester).language, 'plaintext');
      expect(_codeView(tester).code, source);
    });

    testWidgets(
        'text shown as written whose laid-out form is over the limit gets '
        'no tree', (tester) async {
      final source = '[${List.filled(21000, '[]').join(',')}]';
      expect(source.length, lessThan(maxHighlightedLength));
      expect(formatJson(source).length, greaterThan(maxHighlightedLength));
      await tester.pumpWidget(_inline(JsonViewer.source(
        source,
        initialView: ContentView.rendered,
        fill: false,
        formatSource: false,
      )));

      expect(find.text(_sizeNotice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);
      expect(find.byType(JsonTreeView), findsNothing);
      expect(_codeView(tester).language, 'plaintext');
      expect(_codeView(tester).code, source);
    });

    testWidgets('nesting deeper than maxJsonDepth shows the source',
        (tester) async {
      final source = _nestedSource(maxJsonDepth + 1);
      await tester.pumpWidget(_inline(JsonViewer.source(
        source,
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      expect(tester.takeException(), isNull);
      expect(find.text(_depthNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
      expect(_viewSwitch(), findsNothing);
      expect(_codeView(tester).language, 'json');
      expect(_codeView(tester).code, source);
    });

    testWidgets('nesting exactly maxJsonDepth deep offers the Tree',
        (tester) async {
      await tester.pumpWidget(_inline(JsonViewer.source(
        _nestedSource(maxJsonDepth),
        initialView: ContentView.source,
        fill: false,
        formatSource: true,
      )));

      expect(find.text(_depthNotice), findsNothing);
      expect(_viewSwitch(), findsOneWidget);

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(JsonTreeView), findsOneWidget);
    });

    testWidgets('unclosed nesting too deep gets the depth notice, unparsed',
        (tester) async {
      await tester.pumpWidget(_inline(JsonViewer.source(
        '[' * (maxJsonDepth + 1),
        initialView: ContentView.rendered,
        fill: false,
        formatSource: true,
      )));

      expect(find.text(_depthNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
    });
  });

  group('decoded value', () {
    for (final initialView in ContentView.values) {
      testWidgets(
          'a value JSON cannot encode shows its tree, '
          'starting in ${initialView.name}', (tester) async {
        await tester.pumpWidget(_inline(JsonViewer.decoded(
          const {'a': double.infinity},
          initialView: initialView,
          fill: false,
        )));

        expect(tester.takeException(), isNull);
        expect(find.byType(JsonTreeView), findsOneWidget);
        expect(find.textContaining('a: Infinity'), findsOneWidget);
        expect(find.byType(CodeView), findsNothing);
        expect(find.byType(ContentInfoNotice), findsNothing);
        expect(_viewSwitch(), findsNothing);
        expect(
          tester.widget<ContentHeader>(find.byType(ContentHeader)).copyText,
          '{a: Infinity}',
        );
      });
    }

    testWidgets('an unencodable value over the limit shows plain text',
        (tester) async {
      final value = {'a': double.infinity, 'b': 'x' * maxHighlightedLength};
      await tester.pumpWidget(_inline(JsonViewer.decoded(
        value,
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(find.text(_sizeNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
      expect(_codeView(tester).language, 'plaintext');
      expect(_codeView(tester).code, value.toString());
    });
  });

  testWidgets('label Body gives Copy Body', (tester) async {
    await tester.pumpWidget(_inline(const JsonViewer.source(
      '{"a": 1}',
      initialView: ContentView.rendered,
      label: 'Body',
      fill: false,
      formatSource: true,
    )));

    expect(find.text('Body'), findsOneWidget);
    expect(find.byTooltip('Copy Body'), findsOneWidget);
  });
}
