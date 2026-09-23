import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
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

  testWidgets('an update lays the timeline out once', (tester) async {
    // A band with no tile to render on is reported each time the timeline is
    // laid out, so the reports per update count the layouts.
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    final orphan = ExecutionTracker.historical(
      unfinishedAs: StepStatus.completed,
      events: const [(event: ThinkingStarted(), timestamp: null)],
      origin: null,
      activities: const [],
      logger: testLogger(),
    );
    addTearDown(orphan.dispose);

    Widget timeline(List<ChatMessage> messages) => ProviderScope(
          overrides: [
            messageExpansionsProvider.overrideWithValue(MessageExpansions()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MessageTimeline(
                roomId: 'r',
                messages: messages,
                messageStates: const {},
                executionTrackers: {'gone': orphan},
              ),
            ),
          ),
        );
    const ask = TextMessage(
      id: 'u1',
      user: ChatUser.user,
      createdAt: null,
      text: 'ask',
    );
    const answer = TextMessage(
      id: 'a1',
      user: ChatUser.assistant,
      createdAt: null,
      text: 'answer',
    );

    await tester.pumpWidget(timeline(const [ask]));
    final before = sink.records.length;
    await tester.pumpWidget(timeline(const [ask, answer]));

    expect(
      sink.records.skip(before).where(
            (r) =>
                r.loggerName == 'soliplex_frontend.message_timeline' &&
                r.message.contains('Execution band gone has no tile'),
          ),
      hasLength(1),
    );
  });
}
