import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/notice_bubble.dart';

import '../../../helpers/test_logger.dart';

void main() {
  testWidgets('renders messages normally when non-empty', (tester) async {
    final message = TextMessage(
      id: 'msg-1',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'Hello',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [message],
            messageStates: const {},
            toolCallParentIds: const {},
          ),
        ),
      ),
    ));

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets(
      'the streaming reply keeps its shimmer while committed empty '
      'replies report they carried no text', (tester) async {
    // Two empty assistant replies: one is the message the run is streaming
    // into, the other no run is writing into. Only the live one may animate.
    final settled = TextMessage(
      id: 'msg-1',
      user: ChatUser.assistant,
      createdAt: DateTime(2026, 3, 1),
      text: '',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [settled],
            messageStates: const {},
            toolCallParentIds: const {},
            streamingState: const TextStreaming(
              messageId: 'msg-2',
              user: ChatUser.assistant,
              text: '',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Bound to position, not just to counts: computeDisplayMessages appends
    // the streaming reply after the settled one, so the notice must sit above
    // the shimmer. Counting one of each passes just as well when they swap.
    expect(
      tester.getTopLeft(find.byType(NoticeBubble)).dy,
      lessThan(tester.getTopLeft(find.byType(SoliplexShimmer)).dy),
    );
  });

  testWidgets('a declared parent is not shown as a message', (tester) async {
    // A response that began with a tool call leaves an empty message behind
    // purely to name that call's parent. Rendering it puts "This message has
    // no text" between the question and its answer.
    final messages = [
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Which transmitter?',
      ),
      TextMessage(
        id: 'decl-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: '',
      ),
      TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'The C-band one.',
      ),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: messages,
            messageStates: const {},
            toolCallParentIds: const {'decl-1'},
          ),
        ),
      ),
    ));

    expect(find.byType(NoticeBubble), findsNothing);
    expect(find.text('The C-band one.'), findsOneWidget);
  });

  testWidgets('a whitespace-only reply nothing claims still reports itself',
      (tester) async {
    // Rendering it as written is a bubble with nothing in it and no reason
    // given; the notice at least says what happened.
    final messages = [
      TextMessage.create(
        id: 'msg-1',
        user: ChatUser.assistant,
        text: '   ',
      ),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: messages,
            messageStates: const {},
            toolCallParentIds: const {},
          ),
        ),
      ),
    ));

    expect(find.byType(NoticeBubble), findsOneWidget);
  });

  testWidgets('the events block stays open when the reply arrives',
      (tester) async {
    // Opened while the run works, the block is keyed to the sentinel; the
    // reply then names itself and the tile remounts under a real id. Closing
    // it there discards the one thing the user asked to see.
    final tracker = ExecutionTracker.historical(
      events: const [
        (
          event: ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-1'),
          timestamp: null,
        ),
      ],
      origin: null,
      activities: const [],
      logger: testLogger(),
    );
    addTearDown(tracker.dispose);
    final expansions = MessageExpansions();

    Widget timeline(
      StreamingState streaming,
      Map<String, ExecutionTracker> trackers,
    ) =>
        ProviderScope(
          overrides: [
            messageExpansionsProvider.overrideWithValue(expansions),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MessageTimeline(
                roomId: 'r',
                messages: const [],
                messageStates: const {},
                toolCallParentIds: const {},
                streamingState: streaming,
                executionTrackers: trackers,
              ),
            ),
          ),
        );

    await tester.pumpWidget(
      timeline(const AwaitingText(), {awaitingTrackerKey: tracker}),
    );
    expect(find.text('search'), findsNothing);

    await tester.tap(find.text('1 event'));
    await tester.pump();
    expect(find.text('search'), findsOneWidget);

    await tester.pumpWidget(
      timeline(
        const TextStreaming(
          messageId: 'msg-1',
          user: ChatUser.assistant,
          text: 'The answer',
        ),
        {'msg-1': tracker},
      ),
    );
    await tester.pump();

    expect(find.text('search'), findsOneWidget);
  });
}
