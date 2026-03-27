import 'package:soliplex_agent/soliplex_agent.dart';

/// Merges streaming state into the message list for unified rendering.
///
/// During [TextStreaming], the historical message with the same ID (if
/// present) is filtered out and replaced with a [TextMessage] built from
/// the streaming data. During [AwaitingText], a [LoadingMessage] is
/// appended.
List<ChatMessage> computeDisplayMessages(
  List<ChatMessage> messages,
  StreamingState? streaming,
) {
  if (streaming == null) return messages;
  return switch (streaming) {
    AwaitingText() => [...messages, LoadingMessage.create(id: '_loading')],
    TextStreaming(
      :final messageId,
      :final user,
      :final text,
      :final thinkingText,
    ) =>
      [
        ...messages.where((m) => m.id != messageId),
        TextMessage(
          id: messageId,
          user: user,
          createdAt: DateTime.now(),
          text: text,
          thinkingText: thinkingText,
        ),
      ],
  };
}
