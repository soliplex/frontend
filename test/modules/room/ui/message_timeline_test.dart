import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart'
    show awaitingTrackerKey;
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';
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
          ),
        ),
      ),
    ));

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets(
      'a message that only names a tool call is not shown, and only the '
      'live one animates', (tester) async {
    // Two empty assistant replies: one was opened only to name a tool call,
    // the other is the message the run is streaming into. Neither has anything
    // to read, so neither takes a bubble - and only the live one may animate.
    const named = TextMessage(
      id: 'msg-1',
      user: ChatUser.assistant,
      createdAt: null,
      text: '',
      namedByToolCall: true,
    );
    final spoken = TextMessage(
      id: 'msg-0',
      user: ChatUser.assistant,
      createdAt: DateTime(2026, 2, 1),
      text: 'An earlier answer.',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [spoken, named],
            messageStates: const {},
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

    expect(find.byType(NoticeBubble), findsNothing);
    // Bound to position, not just to counts: the reply that spoke is the only
    // bubble, and the live run's shimmer sits below it. Counting one of each
    // passes just as well when they swap.
    expect(
      tester.getTopLeft(find.text('An earlier answer.')).dy,
      lessThan(tester.getTopLeft(find.byType(SoliplexShimmer)).dy),
    );
  });

  testWidgets(
      'a reply that no tool call named still reports it carried no text',
      (tester) async {
    final empty = TextMessage(
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
            messages: [empty],
            messageStates: const {},
          ),
        ),
      ),
    ));

    expect(find.byType(NoticeBubble), findsOneWidget);
  });

  testWidgets('the events group stays on screen while a reply has yet to speak',
      (tester) async {
    // A message that only names a tool call never claims the run's band, so it
    // stays under awaitingTrackerKey - which only the loading tile reads. Show
    // a bubble for that message instead and the group the user is watching
    // disappears until the next reply speaks.
    final band = ExecutionTracker.historical(
      events: [
        (
          event: const ServerToolCallStarted(
            toolName: 'search',
            toolCallId: 'c1',
          ),
          timestamp: null,
        ),
      ],
      origin: null,
      activities: const [],
      logger: testLogger(),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: const [],
            messageStates: const {},
            executionTrackers: {awaitingTrackerKey: band},
            streamingState: const TextStreaming(
              messageId: 'm1',
              user: ChatUser.assistant,
              text: '',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(ExecutionTimeline), findsOneWidget);
  });
}
