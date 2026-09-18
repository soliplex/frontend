import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/compute_display_messages.dart';

void main() {
  test('returns messages unchanged when not streaming', () {
    final messages = [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: 'Hello',
      ),
    ];

    final result = computeDisplayMessages(messages, null);
    expect(result, same(messages));
  });

  test('appends LoadingMessage during AwaitingText', () {
    final messages = [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: 'Hello',
      ),
    ];

    final result = computeDisplayMessages(
      messages,
      const AwaitingText(currentPhase: ThinkingPhase()),
    );

    expect(result.length, 2);
    expect(result.last, isA<LoadingMessage>());
  });

  test('deduplicates streaming message by ID', () {
    final messages = [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: 'Hello',
      ),
      TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: 'Partial response',
      ),
    ];

    final result = computeDisplayMessages(
      messages,
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'Full streaming response',
      ),
    );

    expect(result.length, 2);
    final streamingMsg = result.last as TextMessage;
    expect(streamingMsg.id, 'msg-2');
    expect(streamingMsg.text, 'Full streaming response');
  });

  test('adds streaming message when not in historical list', () {
    final messages = [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: 'Hello',
      ),
    ];

    final result = computeDisplayMessages(
      messages,
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'Response',
      ),
    );

    expect(result.length, 2);
    expect((result.last as TextMessage).text, 'Response');
  });

  test('streaming message carries no client-clock createdAt', () {
    final result = computeDisplayMessages(
      const [],
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Response',
      ),
    );

    // No server time exists mid-stream; the caption fills when the message
    // commits with the backend's event time, not a client clock.
    expect((result.single as TextMessage).createdAt, isNull);
  });

  test('preserves thinkingText from streaming state', () {
    final result = computeDisplayMessages(
      const [],
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Response',
        thinkingText: 'Let me think...',
      ),
    );

    final msg = result.first as TextMessage;
    expect(msg.thinkingText, 'Let me think...');
  });

  group('messages that said nothing', () {
    TextMessage assistant(
      String id,
      String text, {
      String thinking = '',
      bool named = false,
    }) =>
        TextMessage(
          id: id,
          user: ChatUser.assistant,
          createdAt: null,
          text: text,
          thinkingText: thinking,
          namedByToolCall: named,
        );

    test('an empty message a tool call named is dropped', () {
      final result = computeDisplayMessages(
        [assistant('m1', '', named: true), assistant('m2', 'The answer is 4.')],
        null,
      );

      expect(result.map((m) => m.id), equals(['m2']));
    });

    test('an empty message no tool call named is kept', () {
      final result = computeDisplayMessages([assistant('m1', '')], null);

      expect(
        result.map((m) => m.id),
        equals(['m1']),
        reason: 'a reply that genuinely said nothing is an anomaly to surface',
      );
    });

    test('a named message that spoke is kept', () {
      final result =
          computeDisplayMessages([assistant('m1', 'Here.', named: true)], null);

      expect(result.map((m) => m.id), equals(['m1']));
    });

    test('a named declaration that carried reasoning is dropped too', () {
      final result = computeDisplayMessages(
        [
          assistant('m1', '', thinking: 'Let me look.', named: true),
          assistant('m2', 'Done.'),
        ],
        null,
      );

      expect(result.map((m) => m.id), equals(['m2']));
    });

    test('named whitespace-only content is dropped', () {
      expect(
        computeDisplayMessages([assistant('m1', '  \n', named: true)], null),
        isEmpty,
      );
    });

    test('a user message with no text is kept', () {
      final empty = TextMessage.create(id: 'u1', user: ChatUser.user, text: '');

      expect(computeDisplayMessages([empty], null), equals([empty]));
    });

    test('a TextStreaming that has not spoken renders the sentinel', () {
      final result = computeDisplayMessages(
        [assistant('m0', 'Earlier.')],
        const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: '',
        ),
      );

      expect(result.map((m) => m.id), equals(['m0', loadingMessageId]));
    });

    test('a TextStreaming carrying only whitespace renders the sentinel', () {
      final result = computeDisplayMessages(
        const [],
        const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: '  ',
        ),
      );

      expect(result.single.id, equals(loadingMessageId));
    });

    test('a TextStreaming that has spoken renders its text', () {
      final result = computeDisplayMessages(
        const [],
        const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: 'Part',
        ),
      );

      expect((result.single as TextMessage).text, equals('Part'));
    });
  });
}
