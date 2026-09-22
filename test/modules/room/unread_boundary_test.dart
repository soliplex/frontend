import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
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
          logger: testLogger(),
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
          id: noResponseMessageId('run-1'),
          thinkingText: 'weighing it',
          runId: 'run-1',
        ),
      };
      final shown = [
        for (final tile in layOutTimeline(
          messages: messages,
          bands: const {},
          outcomes: outcomes,
          streaming: null,
          activeRunId: null,
          logger: testLogger(),
        ))
          tile.message,
      ];

      final anchor = lastShownMessageId(
        messages: messages,
        outcomes: outcomes,
        logger: testLogger(),
      );

      expect(shown.map((m) => m.id), ['u1', noResponseMessageId('run-1')]);
      expect(anchor, equals(noResponseMessageId('run-1')));
      expect(firstUnreadMessageId(shown, anchor), isNull);
    });

    test('null when the thread shows nothing', () {
      expect(
        lastShownMessageId(
          messages: const [],
          outcomes: const {},
          logger: testLogger(),
        ),
        isNull,
      );
    });
  });
}
