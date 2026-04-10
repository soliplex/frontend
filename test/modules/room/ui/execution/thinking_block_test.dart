import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ExecutionThinkingBlock', () {
    late Signal<ExecutionEvent?> events;
    late ExecutionTracker tracker;

    setUp(() {
      events = Signal<ExecutionEvent?>(null);
      tracker = ExecutionTracker(executionEvents: events);
    });

    tearDown(() {
      tracker.dispose();
    });

    testWidgets('returns empty when no blocks and not streaming',
        (tester) async {
      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('Thinking'), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('shows header when blocks exist', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Some thoughts');

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('shows streaming indicator when isThinkingStreaming',
        (tester) async {
      events.value = const ThinkingStarted();

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does not show streaming indicator when not streaming',
        (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Some thoughts');
      events.value = const RunCompleted();

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tap expands thinking content', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Let me think about this');

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
      await tester.pump();

      expect(find.text('Let me think about this'), findsNothing);

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(find.text('Let me think about this'), findsOneWidget);
    });

    testWidgets('tap again collapses content', (tester) async {
      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'Let me think about this');

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(find.text('Let me think about this'), findsOneWidget);

      await tester.tap(find.byType(GestureDetector));
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

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
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

      await tester.pumpWidget(wrap(ExecutionThinkingBlock(tracker: tracker)));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      // Only the non-empty block should appear
      expect(find.text('Second thought'), findsOneWidget);
      // The empty first block should not produce any extra Text widget beyond the header
      final textWidgets = tester.widgetList<Text>(find.byType(Text)).toList();
      // Header "Thinking (2)" + "Second thought" = 2 text widgets
      expect(textWidgets.length, 2);
    });
  });
}
