import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/compute_display_messages.dart'
    show loadingMessageId;

const _roomId = 'r1';
const _messageId = 'm1';

void main() {
  late Signal<ExecutionEvent?> events;
  late ExecutionTracker tracker;
  late MessageExpansions store;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    tracker = ExecutionTracker(executionEvents: events);
    store = MessageExpansions();
  });

  tearDown(() => tracker.dispose());

  Widget wrap(Widget child, {MessageExpansions? storeOverride}) =>
      ProviderScope(
        overrides: [
          messageExpansionsProvider.overrideWithValue(storeOverride ?? store),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  ExecutionTimeline build({
    String roomId = _roomId,
    String messageId = _messageId,
    ExecutionTracker? t,
  }) =>
      ExecutionTimeline(
        roomId: roomId,
        messageId: messageId,
        tracker: t ?? tracker,
      );

  testWidgets('renders nothing for empty timeline', (tester) async {
    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('header counts step + nested activities', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'execute_script', 'args': '{}'},
      timestamp: 100,
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_2',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'list_environments', 'args': '{}'},
      timestamp: 101,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.text('3 events'), findsOneWidget);
  });

  testWidgets('singular label when only one event', (tester) async {
    events.value = const ThinkingStarted();

    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.text('1 event'), findsOneWidget);
  });

  testWidgets('tap expands to show step and nested activity', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'execute_script', 'args': '{}'},
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.text('execute_skill'), findsNothing);
    expect(find.text('execute_script'), findsNothing);

    await tester.tap(find.text('2 events'));
    await tester.pump();

    expect(find.text('execute_skill'), findsOneWidget);
    expect(find.text('execute_script'), findsOneWidget);
  });

  testWidgets('activity row expands to show script source', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'execute_script',
        'args': '{"script":"print(42)"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('2 events'));
    await tester.pump();

    expect(find.text('print(42)'), findsNothing);

    await tester.tap(find.text('execute_script'));
    await tester.pump();

    expect(find.text('print(42)'), findsOneWidget);
  });

  testWidgets('activity with no args has no source chevron', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'noop', 'args': '{}'},
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    // Only the header chevron should be visible, not a per-row one.
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('generic args fall back to JSON preview', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'lookup',
        'args': '{"doc_id":"abc"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();
    await tester.tap(find.text('lookup'));
    await tester.pump();

    expect(find.textContaining('"doc_id"'), findsOneWidget);
  });

  testWidgets('completed step shows check_circle icon', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-1',
      result: 'ok',
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('orphan activity rendered when no active step', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'execute_script',
        'args': '{"script":"x=1"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    expect(find.text('execute_script'), findsOneWidget);
  });

  group('MessageExpansions persistence', () {
    testWidgets('header expansion persists across parent-key swap',
        (tester) async {
      events.value = const ThinkingStarted();

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);

      // Force State destruction by swapping the parent key; store is the
      // same across pumps, so the re-mounted widget seeds _expanded=true.
      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('source expansion persists across parent-key swap',
        (tester) async {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'execute_script',
          'args': '{"script":"print(42)"}',
        },
        timestamp: 100,
      );

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      await tester.tap(find.text('2 events'));
      await tester.pump();
      await tester.tap(find.text('execute_script'));
      await tester.pump();
      expect(find.text('print(42)'), findsOneWidget);

      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('print(42)'), findsOneWidget);
    });

    testWidgets('state is keyed by both roomId and messageId', (tester) async {
      events.value = const ThinkingStarted();

      final events2 = Signal<ExecutionEvent?>(null);
      final tracker2 = ExecutionTracker(executionEvents: events2);
      addTearDown(tracker2.dispose);
      events2.value = const ThinkingStarted();

      final events3 = Signal<ExecutionEvent?>(null);
      final tracker3 = ExecutionTracker(executionEvents: events3);
      addTearDown(tracker3.dispose);
      events3.value = const ThinkingStarted();

      // Three widgets: (r1, m1), (r1, other-msg), (other-room, m1).
      // Tapping the first must not affect the other two.
      await tester.pumpWidget(wrap(Column(
        children: [
          build(),
          build(messageId: 'other-msg', t: tracker2),
          build(roomId: 'other-room', t: tracker3),
        ],
      )));
      await tester.pump();
      expect(find.text('1 event'), findsNWidgets(3));

      await tester.tap(find.text('1 event').first);
      await tester.pump();

      // Only the first expands; isolation holds across messageId AND roomId.
      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('collapse persists across parent-key swap', (tester) async {
      events.value = const ThinkingStarted();

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      // Expand, then collapse.
      await tester.tap(find.text('1 event'));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      expect(find.text('Thinking'), findsNothing);

      // Remount — the collapsed state must survive. This pins the decision
      // to write every transition (not just expansion).
      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('Thinking'), findsNothing);
    });

    testWidgets('header toggle in loading phase uses local state only',
        (tester) async {
      events.value = const ThinkingStarted();

      await tester.pumpWidget(wrap(build(messageId: loadingMessageId)));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);

      // Sentinel messageId must not leak into the store — it is reused
      // across runs and state written under it would leak to the next
      // response.
      expect(store.debugHasStateFor(_roomId, loadingMessageId), isFalse);
    });

    testWidgets('source toggle in loading phase uses local state only',
        (tester) async {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'execute_script',
          'args': '{"script":"print(42)"}',
        },
        timestamp: 100,
      );

      await tester.pumpWidget(wrap(build(messageId: loadingMessageId)));
      await tester.pump();
      await tester.tap(find.text('2 events'));
      await tester.pump();
      await tester.tap(find.text('execute_script'));
      await tester.pump();
      expect(find.text('print(42)'), findsOneWidget);

      // Collapse pins the "remove from local set" branch. A regression
      // that only adds and never removes would silently break the
      // loading-phase collapse path.
      await tester.tap(find.text('execute_script'));
      await tester.pump();
      expect(find.text('print(42)'), findsNothing);

      // Safety invariant for source rows — no writes to the store.
      expect(store.debugHasStateFor(_roomId, loadingMessageId), isFalse);
    });
  });
}
