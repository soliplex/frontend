import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/stream_content_view.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/content/json_viewer.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// An SSE body carrying [events], one `data:` line each.
String _sseBody(List<Map<String, Object?>> events) =>
    events.map((event) => 'data: ${jsonEncode(event)}\n\n').join();

void main() {
  testWidgets('an expanded stream event shows Tree / Source', (tester) async {
    final body = _sseBody([
      {'type': 'RUN_STARTED', 'threadId': 't1', 'runId': 'r1'},
    ]);

    await tester.pumpWidget(_wrap(StreamContentView(body: body)));
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RUN_STARTED'));
    await tester.pumpAndSettle();

    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
  });

  testWidgets('tool-call arguments with 1e999 show without an error',
      (tester) async {
    final body = _sseBody([
      {'type': 'TOOL_CALL_START', 'toolCallId': 'tc1', 'toolCallName': 'calc'},
      {'type': 'TOOL_CALL_ARGS', 'toolCallId': 'tc1', 'delta': '{"x":1e999}'},
      {'type': 'TOOL_CALL_END', 'toolCallId': 'tc1'},
    ]);

    await tester.pumpWidget(_wrap(StreamContentView(body: body)));

    expect(tester.takeException(), isNull);
    expect(find.text('calc'), findsOneWidget);
    expect(
      tester.widget<CodeView>(find.byType(CodeView)).code,
      '{\n  "x": 1e999\n}',
    );
  });

  testWidgets('a STATE_SNAPSHOT shows its state as Tree / Source',
      (tester) async {
    final body = _sseBody([
      {
        'type': 'STATE_SNAPSHOT',
        'snapshot': {'cart': 3},
      },
    ]);

    await tester.pumpWidget(_wrap(StreamContentView(body: body)));

    expect(find.text('STATE_SNAPSHOT'), findsOneWidget);
    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.textContaining('cart: 3', findRichText: true), findsOneWidget);
  });

  testWidgets('a STATE_DELTA shows its JSON Patch as Tree / Source',
      (tester) async {
    final body = _sseBody([
      {
        'type': 'STATE_DELTA',
        'delta': [
          {'op': 'replace', 'path': '/cart', 'value': 4},
        ],
      },
    ]);

    await tester.pumpWidget(_wrap(StreamContentView(body: body)));

    expect(find.text('STATE_DELTA'), findsOneWidget);
    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(
      find.textContaining('replace', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a state event without data shows only its badge',
      (tester) async {
    final body = _sseBody([
      {'type': 'STATE_SNAPSHOT'},
    ]);

    await tester.pumpWidget(_wrap(StreamContentView(body: body)));

    expect(find.text('STATE_SNAPSHOT'), findsOneWidget);
    expect(find.byType(JsonViewer), findsNothing);
  });
}
