import 'package:soliplex_agent/soliplex_agent.dart';

/// Sentinel id for the placeholder [LoadingMessage] appended during
/// [AwaitingText]. It is reused across runs, so it must never be used
/// as a persistence key — state written under it would leak into the
/// next response.
const loadingMessageId = '_loading';

/// Merges streaming state into the message list for unified rendering.
///
/// A message opened only to name a tool call's parent is left out — there is
/// nothing in it to read, and its events and reasoning are on whichever tile
/// speaks next ([existsOnlyForToolCall]). An empty message no tool call named
/// is a reply that genuinely carried no text, which stays: that is an anomaly
/// worth showing, and the bubble reports it.
///
/// A [TextStreaming] that has yet to say anything — the window between
/// `TEXT_MESSAGE_START` and the first delta, which such a message closes
/// without ever leaving — renders as the [LoadingMessage] sentinel. No claim
/// has arrived yet at that point, and it need not: a reply mid-stream has
/// nothing to show either way, and the sentinel keeps the run's band under
/// `awaitingTrackerKey` where that tile reads it, so the events already on
/// screen stay on screen. Which of the two it turns out to be is settled when
/// it commits.
///
/// During [TextStreaming], the historical message with the same ID (if
/// present) is filtered out and replaced with a [TextMessage] built from
/// the streaming data. During [AwaitingText], a [LoadingMessage] is
/// appended.
List<ChatMessage> computeDisplayMessages(
  List<ChatMessage> messages,
  StreamingState? streaming,
) {
  // Rebuilt only when something is actually left out, so the common case
  // hands back the same list it was given.
  final shown = messages.any(existsOnlyForToolCall)
      ? [
          for (final message in messages)
            if (!existsOnlyForToolCall(message)) message,
        ]
      : messages;
  if (streaming == null) return shown;
  return switch (streaming) {
    AwaitingText() => [...shown, LoadingMessage.create(id: loadingMessageId)],
    TextStreaming(:final messageId, :final text) when text.trim().isEmpty => [
        ...shown.where((m) => m.id != messageId),
        LoadingMessage.create(id: loadingMessageId),
      ],
    TextStreaming(
      :final messageId,
      :final user,
      :final text,
      :final thinkingText,
    ) =>
      [
        ...shown.where((m) => m.id != messageId),
        TextMessage(
          id: messageId,
          user: user,
          // No server time exists mid-stream; the caption fills when the
          // message commits with the backend's event time on TextMessageEnd,
          // rather than flashing a client clock.
          createdAt: null,
          text: text,
          thinkingText: thinkingText,
        ),
      ],
  };
}
