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

  testWidgets('a band that stays dropped is reported once, not per update',
      (tester) async {
    // Every streaming delta rebuilds the timeline. A report per rebuild would
    // bury the one record that says a run's work vanished.
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
    await tester.pumpWidget(timeline(const [ask, answer]));
    await tester.pumpWidget(timeline(const [answer, ask]));

    expect(
      sink.records.where(
        (r) =>
            r.loggerName == 'soliplex_frontend.message_timeline' &&
            r.message.contains('Execution band gone has no tile'),
      ),
      hasLength(1),
    );
  });

  testWidgets(
      "a user tile's actions reach the last segment of its turn, not the "
      'run that opened it', (tester) async {
    // A turn that runs a client tool spans runs. The user message carries the
    // run it opened, and its message state follows the turn to its last run.
    const ask = TextMessage(
      id: 'u1',
      user: ChatUser.user,
      createdAt: null,
      text: 'ask',
      runId: 'segment-1',
    );
    String? inspected;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: const [ask],
            messageStates: {
              'u1': MessageState(
                userMessageId: 'u1',
                sourceReferences: const [],
                runId: 'segment-2',
              ),
            },
            onInspect: (runId) => inspected = runId,
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('Inspect HTTP traffic'));

    expect(inspected, 'segment-2');
  });
}
