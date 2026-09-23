import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../../helpers/test_logger.dart';

import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart'
    show loadingMessageId;
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';

const _roomId = 'r1';
const _messageId = 'm1';

void main() {
  group('ExecutionThinkingBlock', () {
    late ExecutionTracker tracker;
    late MessageExpansions store;

    setUp(() {
      tracker = ExecutionTracker(
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
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'Some thoughts'));

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('shows streaming indicator when isThinkingStreaming',
        (tester) async {
      tracker.observe(const ThinkingStarted());

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does not show streaming indicator when not streaming',
        (tester) async {
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'Some thoughts'));
      tracker.observe(const RunCompleted());

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tap expands thinking content', (tester) async {
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'Let me think about this'));

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.text('Let me think about this'), findsNothing);

      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();

      expect(find.text('Let me think about this'), findsOneWidget);
    });

    testWidgets('tap again collapses content', (tester) async {
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'Let me think about this'));

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
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'First thought'));
      tracker.observe(const ServerToolCallStarted(
        toolName: 'search',
        toolCallId: 'tc-1',
      ));
      tracker.observe(const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
      ));
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'Second thought'));

      await tester.pumpWidget(wrap(build()));
      await tester.pump();

      expect(find.text('Thinking (2)'), findsOneWidget);
    });

    testWidgets('skips empty blocks in expanded view', (tester) async {
      tracker.observe(const ThinkingStarted());
      // No ThinkingContent — block stays empty
      tracker.observe(const ServerToolCallStarted(
        toolName: 'search',
        toolCallId: 'tc-1',
      ));
      tracker.observe(const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
      ));
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'Second thought'));

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
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'A deep thought'));

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
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'A deep thought'));

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

    testWidgets('does not write to store during loading phase', (tester) async {
      tracker.observe(const ThinkingStarted());
      tracker.observe(const ThinkingContent(delta: 'transient'));

      await tester.pumpWidget(wrap(build(messageId: loadingMessageId)));
      await tester.pump();
      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      expect(find.text('transient'), findsOneWidget);

      // Local state flipped, but nothing written to the store.
      expect(store.debugHasStateFor(_roomId, loadingMessageId), isFalse);
    });
  });
}
