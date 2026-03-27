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
      const AwaitingText(currentActivity: ThinkingActivity()),
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
}
