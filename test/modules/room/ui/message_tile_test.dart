import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/activity_indicator.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';
import 'package:soliplex_frontend/src/modules/room/ui/loading_message_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/text_message_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/tool_call_tile.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('TextMessageTile', () {
    testWidgets('shows user label for user messages', (tester) async {
      final msg = TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Hello',
      );
      await tester
          .pumpWidget(_wrap(TextMessageTile(roomId: 'r', message: msg)));
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows assistant label for assistant messages', (tester) async {
      final msg = TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'Response',
      );
      await tester
          .pumpWidget(_wrap(TextMessageTile(roomId: 'r', message: msg)));
      expect(find.text('Assistant'), findsOneWidget);
    });

    testWidgets('shows thinking text when present', (tester) async {
      final msg = TextMessage(
        id: 'msg-3',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'Response',
        thinkingText: 'Thinking about this...',
      );
      await tester
          .pumpWidget(_wrap(TextMessageTile(roomId: 'r', message: msg)));
      expect(find.text('Thinking...'), findsOneWidget);
    });

    testWidgets(
        'renders ExecutionTimeline and ThinkingBlock when tracker provided',
        (tester) async {
      final events = Signal<ExecutionEvent?>(null);
      final tracker = ExecutionTracker(executionEvents: events);

      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'reasoning...');
      events.value = const ServerToolCallStarted(
        toolName: 'search',
        toolCallId: 'tc-1',
      );

      final msg = TextMessage(
        id: 'msg-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: 'Response',
      );

      await tester.pumpWidget(_wrap(TextMessageTile(
        roomId: 'r',
        message: msg,
        executionTracker: tracker,
      )));

      expect(find.byType(ExecutionTimeline), findsOneWidget);
      expect(find.byType(ExecutionThinkingBlock), findsOneWidget);

      tracker.dispose();
    });

    testWidgets('renders ActivityIndicator when streamingActivity provided',
        (tester) async {
      final msg = TextMessage(
        id: 'msg-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: 'Response',
      );

      await tester.pumpWidget(_wrap(TextMessageTile(
        roomId: 'r',
        message: msg,
        streamingActivity: const RespondingActivity(),
      )));

      expect(find.byType(ActivityIndicator), findsOneWidget);
      expect(find.text('Responding...'), findsOneWidget);
    });

    testWidgets('renders placeholder for empty assistant text', (tester) async {
      final msg = TextMessage(
        id: 'msg-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: '',
      );

      await tester.pumpWidget(
        _wrap(TextMessageTile(roomId: 'r', message: msg)),
      );

      expect(find.text('...'), findsOneWidget);
    });

    testWidgets('prefers ExecutionThinkingBlock over message thinkingText',
        (tester) async {
      final events = Signal<ExecutionEvent?>(null);
      final tracker = ExecutionTracker(executionEvents: events);

      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'live thinking');

      final msg = TextMessage(
        id: 'msg-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: 'Response',
        thinkingText: 'persisted thinking',
      );

      await tester.pumpWidget(_wrap(TextMessageTile(
        roomId: 'r',
        message: msg,
        executionTracker: tracker,
      )));

      // ExecutionThinkingBlock is rendered, not the _ThinkingBlock
      expect(find.byType(ExecutionThinkingBlock), findsOneWidget);
      // The persisted "Thinking..." ExpansionTile label should not appear
      expect(find.byType(ExpansionTile), findsNothing);

      tracker.dispose();
    });
  });

  group('LoadingMessageTile', () {
    testWidgets('renders spinner fallback without tracker', (tester) async {
      await tester.pumpWidget(_wrap(const LoadingMessageTile(
        roomId: 'r',
        messageId: '_loading',
      )));

      expect(find.text('Thinking...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders execution widgets with tracker', (tester) async {
      final events = Signal<ExecutionEvent?>(null);
      final tracker = ExecutionTracker(executionEvents: events);

      events.value = const ThinkingStarted();
      events.value = const ThinkingContent(delta: 'working...');

      await tester.pumpWidget(_wrap(LoadingMessageTile(
        roomId: 'r',
        messageId: '_loading',
        executionTracker: tracker,
        streamingActivity: const ThinkingActivity(),
      )));

      expect(find.byType(ActivityIndicator), findsOneWidget);
      expect(find.byType(ExecutionTimeline), findsOneWidget);
      expect(find.byType(ExecutionThinkingBlock), findsOneWidget);

      tracker.dispose();
    });
  });

  group('ToolCallTile', () {
    testWidgets('shows tool name and status', (tester) async {
      final msg = ToolCallMessage(
        id: 'msg-tc',
        createdAt: DateTime(2026, 3, 1),
        toolCalls: [
          ToolCallInfo(
            id: 'tc-1',
            name: 'get_weather',
            status: ToolCallStatus.completed,
            result: '{"temp": 68}',
          ),
        ],
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ToolCallTile(message: msg))));
      expect(find.text('get_weather'), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);
    });

    testWidgets('expands to show args and result on tap', (tester) async {
      final msg = ToolCallMessage(
        id: 'msg-tc',
        createdAt: DateTime(2026, 3, 1),
        toolCalls: [
          ToolCallInfo(
            id: 'tc-1',
            name: 'search',
            arguments: '{"query": "test"}',
            status: ToolCallStatus.completed,
            result: 'Found results',
          ),
        ],
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ToolCallTile(message: msg))));
      expect(find.text('Found results'), findsNothing);
      await tester.tap(find.text('search'));
      await tester.pumpAndSettle();
      expect(find.text('Found results'), findsOneWidget);
    });
  });
}
