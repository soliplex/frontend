import 'package:soliplex_agent/soliplex_agent.dart';

/// Sentinel id for the placeholder [LoadingMessage] appended during
/// [AwaitingText]. It is reused across runs, so it must never be used
/// as a persistence key — state written under it would leak into the
/// next response.
const loadingMessageId = '_loading';

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
    AwaitingText() => [
        ...messages,
        LoadingMessage.create(id: loadingMessageId)
      ],
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
