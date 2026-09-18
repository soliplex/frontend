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

    final result =
        computeDisplayMessages(messages, null, toolCallParentIds: const {});
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
      toolCallParentIds: const {},
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
      toolCallParentIds: const {},
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
      toolCallParentIds: const {},
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
      toolCallParentIds: const {},
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
      toolCallParentIds: const {},
    );

    final msg = result.first as TextMessage;
    expect(msg.thinkingText, 'Let me think...');
  });

  test('drops a message opened only to declare a tool call\'s parent', () {
    final messages = [
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: 'Which transmitter?',
      ),
      TextMessage(
        id: 'decl-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: '',
      ),
      TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: 'The C-band one.',
      ),
    ];

    final result = computeDisplayMessages(
      messages,
      null,
      toolCallParentIds: const {'decl-1'},
    );

    expect(result.map((m) => m.id), ['user-1', 'msg-2']);
  });

  test('keeps an empty reply that no tool call claims', () {
    // A turn that genuinely produced nothing is an anomaly the bubble's
    // notice reports; only a declaration is an artifact worth hiding.
    final messages = [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: '',
      ),
    ];

    final result = computeDisplayMessages(
      messages,
      null,
      toolCallParentIds: const {'decl-1'},
    );

    expect(result.map((m) => m.id), ['msg-1']);
  });

  // Between TEXT_MESSAGE_START and its first delta there is nothing to show,
  // and a declaration never gets one. Rendering the sentinel keeps the run's
  // events on screen instead of blinking the band out.
  //
  // Whitespace has to count as nothing here for the same reason it does
  // everywhere else: the backend guards its content events with a truthiness
  // check, so a declaration can carry a space. Reading it as text puts a blank
  // bubble on screen and drops the band off it until real text arrives.
  for (final (name, text) in [
    ('has not spoken yet', ''),
    ('says only whitespace', ' ')
  ]) {
    test('a message that $name shows as the loading sentinel', () {
      final result = computeDisplayMessages(
        const [],
        TextStreaming(
          messageId: 'msg-1',
          user: ChatUser.assistant,
          text: text,
        ),
        toolCallParentIds: const {},
      );

      expect(result.single, isA<LoadingMessage>());
    });
  }
}
