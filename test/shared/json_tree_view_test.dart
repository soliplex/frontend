import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/json_tree_model.dart';
import 'package:soliplex_frontend/src/shared/json_tree_view.dart';

Future<void> _pumpTree(
  WidgetTester tester,
  List<JsonNode> nodes, {
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: JsonTreeView(nodes: nodes)),
    ),
  );
}

/// The colour [text] renders in: each on-screen text leaf with the colour it
/// inherits from the spans above it, including the ambient style.
Color? _colorOf(WidgetTester tester, String text) {
  final colors = <Color?>[];
  void visit(InlineSpan span, Color? inherited) {
    if (span is! TextSpan) return;
    final color = span.style?.color ?? inherited;
    if (span.text == text) colors.add(color);
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, color);
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(rich.text, null);
  }
  expect(colors, hasLength(1), reason: 'expected one leaf "$text"');
  return colors.single;
}

void main() {
  group('JsonTreeView', () {
    testWidgets('shows empty state for empty node list', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: [])),
        ),
      );
      expect(find.text('(empty)'), findsOneWidget);
    });

    testWidgets('the empty state is as large as a row, italic and muted',
        (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'a', value: 1)]);
      final rowSize =
          tester.widget<RichText>(find.byType(RichText)).text.style?.fontSize;

      await _pumpTree(tester, const []);
      final empty = tester.widget<RichText>(find.byType(RichText)).text.style;
      final context = tester.element(find.text('(empty)'));

      expect(rowSize, isNotNull);
      expect(empty?.fontSize, rowSize);
      expect(empty?.fontStyle, FontStyle.italic);
      expect(empty?.color, Theme.of(context).colorScheme.onSurfaceVariant);
    });

    testWidgets('shows value node text inline', (tester) async {
      const nodes = [ValueNode(key: 'name', value: 'Alice')];
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: nodes)),
        ),
      );
      expect(find.textContaining('Alice'), findsOneWidget);
    });

    testWidgets('tapping a row in a selectable tree still collapses it',
        (tester) async {
      final nodes = [
        ObjectNode(
          key: 'user',
          children: [const ValueNode(key: 'id', value: 1)],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: nodes)),
        ),
      );

      // Initially expanded: child value visible
      expect(find.textContaining('1'), findsOneWidget);

      // Tap the key text, which the selection area could swallow
      await tester.tap(
        find.textContaining('user'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // After collapse, child is hidden
      expect(find.textContaining('1'), findsNothing);
      expect(find.textContaining('{…}'), findsOneWidget);
    });

    testWidgets('array node shows item count in collapsed label',
        (tester) async {
      final nodes = [
        ArrayNode(
          key: 'items',
          children: [
            const ValueNode(key: '[0]', value: 'a'),
            const ValueNode(key: '[1]', value: 'b'),
            const ValueNode(key: '[2]', value: 'c'),
          ],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: nodes)),
        ),
      );

      // Collapse the array
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();

      // Collapsed label includes item count
      expect(find.textContaining('[3]'), findsOneWidget);
    });

    testWidgets('string values are quoted', (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'a', value: '42')]);

      expect(find.textContaining('"42"'), findsOneWidget);
    });

    testWidgets('number values are not quoted', (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'a', value: 42)]);

      expect(find.textContaining('42'), findsOneWidget);
      expect(find.textContaining('"42"'), findsNothing);
    });

    testWidgets('string "42" and number 42 get different colours',
        (tester) async {
      await _pumpTree(tester, const [
        ValueNode(key: 's', value: '42'),
        ValueNode(key: 'n', value: 42),
      ]);

      expect(_colorOf(tester, '"42"'), githubTheme['string']!.color);
      expect(_colorOf(tester, '42'), githubTheme['number']!.color);
    });

    testWidgets('booleans and null are coloured as literals', (tester) async {
      await _pumpTree(tester, const [
        ValueNode(key: 'b', value: true),
        ValueNode(key: 'n', value: null),
      ]);

      expect(_colorOf(tester, 'true'), githubTheme['literal']!.color);
      expect(_colorOf(tester, 'null'), githubTheme['literal']!.color);
    });

    testWidgets(
        'keys are coloured as attributes and brackets as plain text, '
        'on value and expandable rows', (tester) async {
      await _pumpTree(
        tester,
        [
          ObjectNode(
            key: 'user',
            children: [const ValueNode(key: 'id', value: 1)],
          ),
        ],
        theme: ThemeData(brightness: Brightness.dark),
      );

      final attr = vs2015Theme['attr']!.color;
      final root = vs2015Theme['root']!.color;
      expect(attr, isNot(root));
      expect(_colorOf(tester, 'user'), attr);
      expect(_colorOf(tester, 'id'), attr);
      expect(_colorOf(tester, '{'), root);
      expect(_colorOf(tester, '}'), root);
    });

    testWidgets('a key is coloured as an attribute in the light theme',
        (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'id', value: 1)]);

      expect(_colorOf(tester, 'id'), githubTheme['attribute']!.color);
    });

    testWidgets(
        "a value is drawn in the theme's own entry, so its weight and slant "
        'carry over as in the Source view', (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'a', value: '42')]);

      final rich = tester.widget<RichText>(find.byType(RichText));
      final spans = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '"42"') spans.add(span);
        return true;
      });
      expect(spans.single.style, same(githubTheme['string']));
    });

    testWidgets("a key gets no background", (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'id', value: 1)]);

      expect(githubTheme['attribute']!.backgroundColor, isNull);
      expect(githubTheme['root']!.backgroundColor, isNotNull);
      final rich = tester.widget<RichText>(find.byType(RichText));
      final backgrounds = <Color?>[];
      rich.text.visitChildren((span) {
        backgrounds.add(span.style?.backgroundColor);
        return true;
      });
      expect(backgrounds, everyElement(isNull));
    });

    testWidgets("a string's line break is shown, not escaped", (tester) async {
      await _pumpTree(tester, const [ValueNode(key: 'a', value: 'x\ny')]);

      expect(find.textContaining('"x\ny"'), findsOneWidget);
      expect(find.textContaining(r'\n'), findsNothing);
    });

    testWidgets('strings and keys are escaped so any string renders',
        (tester) async {
      final decoded = jsonDecode(
        r'{"k\ud800": "a\"b\ud800", "e": "\ud83d\ude00", "l": "\udc00"}',
      );
      await _pumpTree(tester, buildJsonTree(decoded));

      expect(tester.takeException(), isNull);
      expect(find.textContaining(r'k\uD800: "a\"b\uD800"'), findsOneWidget);
      expect(find.textContaining('e: "😀"'), findsOneWidget);
      expect(find.textContaining(r'l: "\uDC00"'), findsOneWidget);
    });

    testWidgets('a selectable tree selects across rows', (tester) async {
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
      await _pumpTree(tester, const [
        ValueNode(key: 'first', value: 'alpha'),
        ValueNode(key: 'last', value: 'omega'),
      ]);

      final start = tester.getRect(find.textContaining('first'));
      final end = tester.getRect(find.textContaining('omega'));
      final drag = await tester.startGesture(
        start.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag.moveTo(end.centerRight - const Offset(1, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(
        () => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();

      expect(copied, contains('first'));
      expect(copied, contains('omega'));
    });

    testWidgets('a selectable tree has one SelectionArea', (tester) async {
      await _pumpTree(tester, [
        ObjectNode(
          key: 'user',
          children: [const ValueNode(key: 'id', value: 1)],
        ),
      ]);

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('keyboard traversal skips a selectable tree with no controls',
        (tester) async {
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  focusNode: first,
                  onPressed: () {},
                  child: const Text('one'),
                ),
                const JsonTreeView(nodes: [ValueNode(key: 'a', value: 1)]),
                TextButton(
                  focusNode: second,
                  onPressed: () {},
                  child: const Text('two'),
                ),
              ],
            ),
          ),
        ),
      );

      first.requestFocus();
      await tester.pump();
      expect(primaryFocus, first);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(primaryFocus, second);
    });

    testWidgets(
        'a non-selectable tree inside a SelectionArea adds no '
        'SelectionArea of its own', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: JsonTreeView(
                nodes: [
                  ObjectNode(
                    key: 'user',
                    children: [const ValueNode(key: 'id', value: 1)],
                  ),
                ],
                selectable: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    for (final selectable in [true, false]) {
      testWidgets(
          'with selectable $selectable a row is as tall as a CodeView line '
          'under a tall ambient line height', (tester) async {
        final theme = ThemeData(
          textTheme: const TextTheme(
            bodyMedium: TextStyle(height: 1.5, letterSpacing: 0.5),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  JsonTreeView(
                    nodes: const [ValueNode(key: 'a', value: 1)],
                    selectable: selectable,
                  ),
                  const CodeView(code: 'a: 1', language: 'plaintext'),
                ],
              ),
            ),
          ),
        );

        expect(
          tester.getSize(find.byType(JsonTreeView)).height,
          tester.getSize(find.byType(CodeView)).height,
        );
      });
    }
  });
}
