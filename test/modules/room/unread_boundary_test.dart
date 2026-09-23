import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

import '../../helpers/test_logger.dart';

TextMessage _msg(String id) =>
    TextMessage.create(id: id, user: ChatUser.assistant, text: id);

void main() {
  group('firstUnreadMessageId', () {
    final messages = [_msg('a'), _msg('b'), _msg('c')];

    test('returns the message after the anchor', () {
      expect(firstUnreadMessageId(messages, 'a'), 'b');
      expect(firstUnreadMessageId(messages, 'b'), 'c');
    });

    test('null when no anchor', () {
      expect(firstUnreadMessageId(messages, null), isNull);
    });

    test('null when anchor is the last message', () {
      expect(firstUnreadMessageId(messages, 'c'), isNull);
    });

    test('null when anchor is absent from the list', () {
      expect(firstUnreadMessageId(messages, 'zzz'), isNull);
    });

    test('null for an empty list', () {
      expect(firstUnreadMessageId(const [], 'a'), isNull);
    });

    test('null when the next message is the loading sentinel', () {
      final messages = [_msg('a'), LoadingMessage.create(id: loadingMessageId)];
      expect(firstUnreadMessageId(messages, 'a'), isNull);
    });
  });

  group('unreadScrollOffset', () {
    // anchorTop <= dividerTop always (the anchor sits above the divider, so a
    // smaller scroll offset brings it to the top). contextBudget caps how far
    // the divider may sit below the top.
    test('short anchor fits in the budget -> reveal the anchor at the top', () {
      // gap (dividerTop - anchorTop) = 100 <= budget 200.
      expect(
        unreadScrollOffset(
            anchorTop: 900, dividerTop: 1000, contextBudget: 200),
        900,
      );
    });

    test(
        'tall anchor exceeds the budget -> pin the divider one budget '
        'below the top so it stays visible', () {
      // gap = 500 > budget 200; divider pinned at dividerTop - budget.
      expect(
        unreadScrollOffset(
            anchorTop: 500, dividerTop: 1000, contextBudget: 200),
        800,
      );
    });

    test('anchor exactly fills the budget -> both rules agree', () {
      expect(
        unreadScrollOffset(
            anchorTop: 800, dividerTop: 1000, contextBudget: 200),
        800,
      );
    });

    test('anchor at the list top stays at the top (no negative offset)', () {
      expect(
        unreadScrollOffset(anchorTop: 0, dividerTop: 50, contextBudget: 200),
        0,
      );
    });

    test('asserts the anchor sits at or above the divider', () {
      expect(
        () => unreadScrollOffset(
          anchorTop: 100,
          dividerTop: 50,
          contextBudget: 200,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('lastShownMessageId', () {
    test('returns the last id', () {
      expect(
        lastShownMessageId(
          messages: [_msg('a'), _msg('b')],
          outcomes: const {},
          bands: const {},
          streaming: null,
          activeRunId: null,
        ),
        'b',
      );
    });

    test('the anchor is an id the divider can resolve', () {
      // A run that only opened a message to name a tool call leaves that
      // message committed and shows its outcome tile instead. Anchoring on the
      // message the timeline does not show resolves to nothing on reopen, and
      // the "New messages" line is silently not drawn.
      final messages = [
        TextMessage.create(id: 'u1', user: ChatUser.user, text: 'ask'),
        const TextMessage(
          id: 'm1',
          user: ChatUser.assistant,
          createdAt: null,
          text: '',
          runId: 'run-1',
          namedByToolCall: true,
        ),
      ];
      final outcomes = {
        'run-1': NoResponseTile.finished(
          runId: 'run-1',
          thinkingText: 'weighing it',
        ),
      };
      final shown = [
        for (final tile in layOutTimeline(
          messages: messages,
          bands: const {},
          outcomes: outcomes,
          streaming: null,
          activeRunId: null,
        ).tiles)
          tile.message,
      ];

      final anchor = lastShownMessageId(
        messages: messages,
        outcomes: outcomes,
        bands: const {},
        streaming: null,
        activeRunId: null,
      );

      expect(shown.map((m) => m.id), ['u1', noResponseMessageId('run-1')]);
      expect(anchor, equals(noResponseMessageId('run-1')));
      expect(firstUnreadMessageId(shown, anchor), isNull);
    });

    test("the anchor counts the tile a run's trailing work is given", () {
      // The run replied, then did more work that no message spoke for. The
      // timeline gives that work the run's outcome tile, after the reply, so
      // an anchor laid out without the bands would stop one tile short and
      // mark a tile the reader has already seen as new.
      final trailing = ExecutionTracker.historical(
        unfinishedAs: StepStatus.completed,
        events: const [(event: ThinkingStarted(), timestamp: null)],
        origin: null,
        activities: const [],
        logger: testLogger(),
      );
      addTearDown(trailing.dispose);

      final anchor = lastShownMessageId(
        messages: [
          TextMessage.create(id: 'u1', user: ChatUser.user, text: 'ask'),
          const TextMessage(
            id: 'm1',
            user: ChatUser.assistant,
            createdAt: null,
            text: 'Let me look.',
            runId: 'run-1',
          ),
        ],
        outcomes: {
          'run-1': NoResponseTile.finished(
            runId: 'run-1',
            thinkingText: '',
          ),
        },
        bands: {noResponseMessageId('run-1'): trailing},
        streaming: null,
        activeRunId: null,
      );

      expect(anchor, equals(noResponseMessageId('run-1')));
    });

    test('a run in flight anchors on what it has committed', () {
      // Laid out from the timeline's own inputs, so the open run's band goes to
      // the loading tile as it does on screen — and the loading tile, which
      // names no message that will still be there on reload, is not an anchor.
      final open = ExecutionTracker.historical(
        unfinishedAs: StepStatus.completed,
        events: const [(event: ThinkingStarted(), timestamp: null)],
        origin: null,
        activities: const [],
        logger: testLogger(),
      );
      addTearDown(open.dispose);

      final anchor = lastShownMessageId(
        messages: [
          const TextMessage(
            id: 'u1',
            user: ChatUser.user,
            createdAt: null,
            text: 'ask',
            runId: 'run-1',
          ),
        ],
        outcomes: const {},
        bands: {noResponseMessageId('run-1'): open},
        streaming: const AwaitingText(),
        activeRunId: 'run-1',
      );

      expect(anchor, equals('u1'));
    });

    test('a reply still streaming is not an anchor', () {
      // The reader has seen only part of it; anchoring on it would mark the
      // rest read when they come back.
      final anchor = lastShownMessageId(
        messages: [
          TextMessage.create(id: 'u1', user: ChatUser.user, text: 'ask'),
          const TextMessage(
            id: 'm1',
            user: ChatUser.assistant,
            createdAt: null,
            text: 'Let me look.',
            runId: 'run-1',
          ),
        ],
        outcomes: const {},
        bands: const {},
        streaming: const TextStreaming(
          messageId: 'm2',
          user: ChatUser.assistant,
          text: 'Both sources',
        ),
        activeRunId: 'run-1',
      );

      expect(anchor, equals('m1'));
    });

    test('null when the thread shows nothing', () {
      expect(
        lastShownMessageId(
          messages: const [],
          outcomes: const {},
          bands: const {},
          streaming: null,
          activeRunId: null,
        ),
        isNull,
      );
    });
  });
}
