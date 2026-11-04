import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/notice_bubble.dart';

import '../../../helpers/replayed_band.dart';
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
    final orphan = replayedBand(
      unfinishedAs: StepStatus.completed,
      events: const [(event: ThinkingStarted(), timestamp: null)],
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

  testWidgets("a reply names an earlier turn's source by that turn's number",
      (tester) async {
    const earlier = 'e1e2e3e4-1111-4222-8333-944455556604';
    TextMessage text(String id, ChatUser user, String body) =>
        TextMessage(id: id, user: user, createdAt: null, text: body);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [
              text('u1', ChatUser.user, 'first'),
              text('a1', ChatUser.assistant, 'First [$earlier].'),
              text('u2', ChatUser.user, 'second'),
              text('a2', ChatUser.assistant, 'As before [$earlier].'),
            ],
            messageStates: {
              'u1': MessageState(
                userMessageId: 'u1',
                sourceReferences: const [
                  SourceReference(
                    documentId: 'doc-7',
                    documentUri: 'file:///docs/doc-7.pdf',
                    content: 'Passage 7',
                    chunkId: earlier,
                    index: 7,
                  ),
                ],
              ),
              'u2': MessageState(
                userMessageId: 'u2',
                sourceReferences: const [],
              ),
            },
          ),
        ),
      ),
    ));

    expect(
      find.textContaining('As before [7].', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a reply leaves an id whose source no list shows as written',
      (tester) async {
    // The first turn has citations but no reply, so no source list shows
    // them: a number for its id would name no badge on screen.
    const unshown = 'e1e2e3e4-1111-4222-8333-944455556604';
    TextMessage text(String id, ChatUser user, String body) =>
        TextMessage(id: id, user: user, createdAt: null, text: body);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [
              text('u1', ChatUser.user, 'first'),
              text('u2', ChatUser.user, 'second'),
              text('a2', ChatUser.assistant, 'As before [$unshown].'),
            ],
            messageStates: {
              'u1': MessageState(
                userMessageId: 'u1',
                sourceReferences: const [
                  SourceReference(
                    documentId: 'doc-7',
                    documentUri: 'file:///docs/doc-7.pdf',
                    content: 'Passage 7',
                    chunkId: unshown,
                    index: 7,
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    ));

    expect(
      find.textContaining('As before [$unshown].', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets(
      'a failed run that answered reports the failure beside the reply, '
      'under one author label', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [
              const TextMessage(
                id: 'u1',
                user: ChatUser.user,
                createdAt: null,
                text: 'ask',
                runId: 'run-0',
              ),
              const TextMessage(
                id: 'm1',
                user: ChatUser.assistant,
                createdAt: null,
                text: 'Here.',
                runId: 'run-0',
              ),
            ],
            messageStates: const {},
            runOutcomes: {
              'run-0': NoResponseTile.failed(
                runId: 'run-0',
                thinkingText: '',
                errorDetail: 'upstream said no',
              ),
            },
          ),
        ),
      ),
    ));

    expect(find.text('Run failed: upstream said no'), findsOneWidget);
    expect(find.text('Assistant'), findsOneWidget);
  });
}
