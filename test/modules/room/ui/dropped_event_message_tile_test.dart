import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/ui/dropped_event_message_tile.dart';

Future<void> _pump(WidgetTester tester, DroppedEventMessage message) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DroppedEventMessageTile(message: message),
      ),
    ),
  );
}

void main() {
  testWidgets('collapsed shows the one-liner with humanized source', (
    tester,
  ) async {
    final msg = DroppedEventMessage.create(
      id: 'dropped-run-1-3',
      source: DropSource.decode,
      reason: 'unknown event type',
      runId: 'run-1',
      rawPayload: const {'type': 'WIDGET'},
    );

    await _pump(tester, msg);

    expect(find.text("Couldn't process 1 event (decode)"), findsOneWidget);
    // Subtitle / payload are hidden until expanded.
    expect(find.text('run run-1 — unknown event type'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });

  testWidgets('eventProcessing source humanizes to "processing"', (
    tester,
  ) async {
    final msg = DroppedEventMessage.create(
      id: 'dropped-run-1-3',
      source: DropSource.eventProcessing,
      reason: 'cast failed',
      runId: 'run-1',
      rawPayload: const {},
    );

    await _pump(tester, msg);

    expect(
      find.text("Couldn't process 1 event (processing)"),
      findsOneWidget,
    );
  });

  testWidgets('tapping expands and reveals subtitle + JSON payload', (
    tester,
  ) async {
    final msg = DroppedEventMessage.create(
      id: 'dropped-run-1-3',
      source: DropSource.decode,
      reason: 'unknown event type',
      runId: 'run-1',
      rawPayload: const {'type': 'WIDGET', 'foo': 'bar'},
    );

    await _pump(tester, msg);
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('run run-1 — unknown event type'), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    // Both Map keys appear somewhere in the JSON tree.
    expect(find.textContaining('type'), findsWidgets);
    expect(find.textContaining('foo'), findsWidgets);
  });

  testWidgets('null rawPayload renders "(payload unavailable)"', (
    tester,
  ) async {
    final msg = DroppedEventMessage.create(
      id: 'dropped-pre-run-123',
      source: DropSource.decode,
      reason: 'top-level JSON parse failure',
    );

    await _pump(tester, msg);
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('(payload unavailable)'), findsOneWidget);
  });

  testWidgets('omits runId from subtitle when null', (tester) async {
    final msg = DroppedEventMessage.create(
      id: 'dropped-pre-run-123',
      source: DropSource.decode,
      reason: 'top-level parse failure',
    );

    await _pump(tester, msg);
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    // Subtitle is just the reason, no "run …" prefix.
    expect(find.text('top-level parse failure'), findsOneWidget);
  });

  testWidgets('String rawPayload renders the raw bytes verbatim', (
    tester,
  ) async {
    // Top-level JSON parse failures arrive with a String rawPayload —
    // the wire content the parser rejected. A user expanding the tile
    // should see exactly those bytes, not "(payload unavailable)".
    final msg = DroppedEventMessage.create(
      id: 'dropped-pre-run-456',
      source: DropSource.decode,
      reason: 'FormatException: Unexpected character',
      rawPayload: 'not valid json at all',
    );

    await _pump(tester, msg);
    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('not valid json at all'), findsOneWidget);
    // Belt-and-suspenders: not the unavailable fallback.
    expect(find.text('(payload unavailable)'), findsNothing);
  });
}
