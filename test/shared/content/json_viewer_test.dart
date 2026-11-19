import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/content/content_frame.dart';
import 'package:soliplex_frontend/src/shared/content/json_viewer.dart';
import 'package:soliplex_frontend/src/shared/json_tree_view.dart';
import 'package:soliplex_frontend/src/shared/log_once.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

const _notice = "This isn't valid JSON; showing the source.";
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

/// Debug records captured while the test runs; LogManager is reset after it.
MemorySink _captureDebugLogs() {
  final sink = MemorySink();
  LogManager.instance
    ..minimumLevel = LogLevel.debug
    ..addSink(sink);
  addTearDown(LogManager.instance.reset);
  addTearDown(forgetOccurrences);
  return sink;
}

void main() {
  group('valid source', () {
    testWidgets('starts in the requested view: Tree', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.rendered,
        fill: false,
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
      )));

      expect(find.textContaining('  "a": 1'), findsOneWidget);
    });

    testWidgets('the Tree sits on the same surface as the Source',
        (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": 1}',
        initialView: ContentView.rendered,
        fill: false,
      )));

      final surface = githubTheme['root']!.backgroundColor;
      expect(surface, isNotNull);
      expect(
        find.ancestor(
          of: find.byType(JsonTreeView),
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.color == surface,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets("a collapsible row's ink paints on the Tree's surface",
        (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": {"b": 1}}',
        initialView: ContentView.rendered,
        fill: false,
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
      expect(inkMaterial.elevation, 0);
      expect(inkMaterial.shape, isNull);
      expect(inkMaterial.borderRadius, isNull);
    });
  });

  group('invalid source', () {
    testWidgets('shows the raw text and notice, no switch', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": raw',
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(find.textContaining('{"a": raw'), findsOneWidget);
      expect(find.text(_notice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);
      expect(find.byType(JsonTreeView), findsNothing);
    });

    testWidgets('notice is an error bar', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '{"a": broken',
        initialView: ContentView.rendered,
        fill: false,
      )));
      final colors = Theme.of(tester.element(find.text(_notice))).colorScheme;

      final bar = tester.widget<Container>(find
          .ancestor(of: find.text(_notice), matching: find.byType(Container))
          .first);
      expect(bar.color, colors.errorContainer);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined)).color,
        colors.onErrorContainer,
      );
    });

    testWidgets('empty source is invalid', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        '',
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(tester.takeException(), isNull);
      expect(find.text(_notice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);
      expect(find.byType(CodeView), findsOneWidget);
    });

    testWidgets('while streaming shows no notice and logs nothing',
        (tester) async {
      final sink = _captureDebugLogs();
      const source = '{"streamed": "hunter2-partial';
      Widget viewer({required bool isStreaming}) => _inline(JsonViewer.source(
            source,
            initialView: ContentView.source,
            fill: false,
            isStreaming: isStreaming,
          ));

      await tester.pumpWidget(viewer(isStreaming: true));

      expect(find.text(_notice), findsNothing);
      expect(sink.records, isEmpty);

      await tester.pumpWidget(viewer(isStreaming: false));

      expect(find.text(_notice), findsOneWidget);
      final record = sink.records.single;
      expect(record.level, LogLevel.debug);
      expect(record.attributes['length'], source.length);
      expect(record.attributes['label'], 'json');
      expect(record.attributes['failure'], startsWith('FormatException: '));
      for (final part in ['streamed', 'hunter2', 'partial']) {
        expect(record.message, isNot(contains(part)));
        expect('${record.attributes}', isNot(contains(part)));
        expect('${record.error}', isNot(contains(part)));
      }
    });

    testWidgets('the same invalid source logs once across rebuilds',
        (tester) async {
      final sink = _captureDebugLogs();
      Widget viewer(ContentView view) => _inline(JsonViewer.source(
            '{"rebuilt": ',
            initialView: view,
            fill: false,
          ));

      await tester.pumpWidget(viewer(ContentView.source));
      await tester.pumpWidget(viewer(ContentView.rendered));
      // A second mount of the same content, as when a tile scrolls back in.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(viewer(ContentView.source));

      expect(sink.records, hasLength(1));
    });

    testWidgets('showFailureNotice false hides the notice', (tester) async {
      await tester.pumpWidget(_inline(const JsonViewer.source(
        'not json',
        initialView: ContentView.rendered,
        fill: false,
        showFailureNotice: false,
      )));

      expect(find.text(_notice), findsNothing);
      expect(find.textContaining('not json'), findsOneWidget);
    });
  });

  group('rendering budget', () {
    testWidgets('invalid JSON over the limit shows plain text, unlogged',
        (tester) async {
      final sink = _captureDebugLogs();
      final source = '{' * (maxHighlightedLength + 1);
      await tester.pumpWidget(_inline(JsonViewer.source(
        source,
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(find.text(_sizeNotice), findsOneWidget);
      expect(find.text(_notice), findsNothing);
      expect(_viewSwitch(), findsNothing);
      expect(_codeView(tester).language, 'plaintext');
      expect(_codeView(tester).code, source);
      expect(sink.records, isEmpty);
    });

    testWidgets(
        'valid JSON whose pretty-print is over the limit shows it plain',
        (tester) async {
      final source = '[${List.filled(40000, '1').join(',')}]';
      expect(source.length, lessThan(maxHighlightedLength));
      final pretty = const JsonEncoder.withIndent('  ').convert(
        jsonDecode(source),
      );
      expect(pretty.length, greaterThan(maxHighlightedLength));
      await tester.pumpWidget(_inline(JsonViewer.source(
        source,
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(find.text(_sizeNotice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);
      expect(find.byType(JsonTreeView), findsNothing);
      expect(_codeView(tester).language, 'plaintext');
      expect(_codeView(tester).code, pretty);
    });

    testWidgets('nesting deeper than maxJsonDepth shows the source',
        (tester) async {
      final source = _nestedSource(maxJsonDepth + 1);
      await tester.pumpWidget(_inline(JsonViewer.source(
        source,
        initialView: ContentView.rendered,
        fill: false,
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
      )));

      expect(find.text(_depthNotice), findsNothing);
      expect(_viewSwitch(), findsOneWidget);

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(JsonTreeView), findsOneWidget);
    });

    testWidgets('nesting 5,000 deep shows the depth notice', (tester) async {
      await tester.pumpWidget(_inline(JsonViewer.source(
        _nestedSource(5000),
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(tester.takeException(), isNull);
      expect(find.text(_depthNotice), findsOneWidget);
    });

    testWidgets('a decoded value nested too deep shows the depth notice',
        (tester) async {
      Object? value = <Object?>[];
      for (var i = 0; i < maxJsonDepth; i++) {
        value = [value];
      }
      await tester.pumpWidget(_inline(JsonViewer.decoded(
        value,
        initialView: ContentView.rendered,
        fill: false,
      )));

      expect(tester.takeException(), isNull);
      expect(find.text(_depthNotice), findsOneWidget);
      expect(_viewSwitch(), findsNothing);
      expect(_codeView(tester).code, isEmpty);
    });
  });

  testWidgets('label Body gives Copy Body', (tester) async {
    await tester.pumpWidget(_inline(const JsonViewer.source(
      '{"a": 1}',
      initialView: ContentView.rendered,
      label: 'Body',
      fill: false,
    )));

    expect(find.text('Body'), findsOneWidget);
    expect(find.byTooltip('Copy Body'), findsOneWidget);
  });

  testWidgets('copy copies the pretty-print for decoded input', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(_inline(const JsonViewer.decoded(
      {
        'a': [1, true],
      },
      initialView: ContentView.rendered,
      fill: false,
    )));

    expect(find.byType(JsonTreeView), findsOneWidget);
    await tester.tap(find.byTooltip('Copy JSON'));
    await tester.pump();
    // Lets the copy button's feedback revert so no timer is left pending.
    await tester.pump(const Duration(seconds: 2));

    expect(copied, '{\n  "a": [\n    1,\n    true\n  ]\n}');
  });
}
