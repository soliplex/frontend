import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../../helpers/test_logger.dart';

import 'package:soliplex_frontend/src/modules/room/compute_display_messages.dart'
    show loadingMessageId;
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';

const _roomId = 'r1';
const _messageId = 'm1';

void main() {
  group('ExecutionThinkingBlock', () {
    late Signal<ExecutionEvent?> events;
    late ExecutionTracker tracker;
    late MessageExpansions store;

    setUp(() {
      events = Signal<ExecutionEvent?>(null);
      tracker = ExecutionTracker(
        executionEvents: events,
        activities: Signal<List<ActivityRecord>>(const []),
        logger: testLogger(),
      );
      store = MessageExpansions();
    });

    tearDown(() {
      tracker.dispose();
    });

    Widget wrap(Widget child) => ProviderScope(
          overrides: [
            messageExpansionsProvider.overrideWithValue(store),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    ExecutionThinkingBlock build({
      String roomId = _roomId,
      String messageId = _messageId,
    }) =>
        ExecutionThinkingBlock(
          roomId: roomId,
          messageId: messageId,
          tracker: tracker,
        );

    testWidgets('returns empty when no blocks and not streaming',
        (tester) async {
      await tester.pumpWidget(wrap(build()));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('Thinking'), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('shows header when blocks exist', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Some thoughts');

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('shows streaming indicator when isThinkingStreaming',
        (tester) async {
      events.value = const ThinkingStarted();

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does not show streaming indicator when not streaming',
        (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Some thoughts');
      events.value = const RunCompleted();

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tap expands thinking content', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Let me think about this');

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.text('Let me think about this'), findsNothing);

      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();

      expect(find.text('Let me think about this'), findsOneWidget);
    });

    testWidgets('tap again collapses content', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Let me think about this');

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();

      expect(find.text('Let me think about this'), findsOneWidget);

      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();

      expect(find.text('Let me think about this'), findsNothing);
    });

    testWidgets('shows block count when multiple blocks', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'First thought');
      events.value = const ServerToolCallStarted(
        toolName: 'search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
      );
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Second thought');

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.text('Thinking (2)'), findsOneWidget);
    });

    testWidgets('skips empty blocks in expanded view', (tester) async {
      events.value = const ThinkingStarted();
      // No ThinkingContent — block stays empty
      events.value = const ServerToolCallStarted(
        toolName: 'search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
      );
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Second thought');

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();

      // Only the non-empty block should appear
      expect(find.text('Second thought'), findsOneWidget);
      // The empty first block should not produce any extra Text widget beyond the header
      final textWidgets = tester.widgetList<Text>(find.byType(Text)).toList();
      // Header "Thinking (2)" + "Second thought" = 2 text widgets
      expect(textWidgets.length, 2);
    });

    testWidgets('expansion persists across parent-key swap', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'A deep thought');

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      expect(find.text('A deep thought'), findsOneWidget);

      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('A deep thought'), findsOneWidget);
    });

    testWidgets('collapse persists across parent-key swap', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'A deep thought');

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      expect(find.text('A deep thought'), findsNothing);

      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('A deep thought'), findsNothing);
    });

    testWidgets('never keys state to the sentinel the loading phase uses',
        (tester) async {
      // The sentinel id is reused by every run, so state written under it
      // would open the next run's block. What the user opens while the reply
      // is unnamed is held in the room's pending slot instead.
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'transient');

      await tester.pumpWidget(wrap(build(messageId: loadingMessageId)));
      await tester.pump();
      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      expect(find.text('transient'), findsOneWidget);

      expect(store.debugHasStateFor(_roomId, loadingMessageId), isFalse);
    });

    testWidgets('an open block survives the reply naming itself',
        (tester) async {
      // Opened while the run works, the block belongs to the pending slot;
      // the first delta remounts this widget under a real id (MessageTimeline
      // keys tiles per id, as the KeyedSubtree does here). Closing it there
      // would discard the one thing the user asked to see.
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'A deep thought');

      Widget tile(String messageId) => wrap(
            KeyedSubtree(
              key: ValueKey(messageId),
              child: build(messageId: messageId),
            ),
          );

      await tester.pumpWidget(tile(loadingMessageId));
      await tester.pump();
      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      expect(find.text('A deep thought'), findsOneWidget);

      await tester.pumpWidget(tile(_messageId));
      await tester.pump();

      expect(find.text('A deep thought'), findsOneWidget);
    });
  });
}
