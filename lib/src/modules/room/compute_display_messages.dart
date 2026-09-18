import 'package:soliplex_agent/soliplex_agent.dart';

/// Sentinel id for the placeholder [LoadingMessage] appended during
/// [AwaitingText]. It is reused across runs, so it must never be used
/// as a persistence key — state written under it would leak into the
/// next response.
const loadingMessageId = '_loading';

/// Merges streaming state into the message list for unified rendering.
///
/// Two kinds of message are left out, both of them things a reader would
/// have nothing to read:
///
/// - A committed message whose id is in [toolCallParentIds] and that carries
///   no text was opened only to name that call's parent
///   (`isToolCallDeclaration`); it is dropped, and its events and thinking
///   are on whichever tile speaks for the run — the reply that followed it,
///   or the one synthesized for a run that never replied. An empty message no
///   tool call claims is a reply that genuinely said nothing, and stays —
///   that is an anomaly worth showing, and the bubble reports it.
/// - A [TextStreaming] that has yet to say anything — the window between
///   `TEXT_MESSAGE_START` and the first delta, which a declaration closes
///   without ever leaving — renders as the [LoadingMessage] sentinel. The
///   run's execution tracker is still under `awaitingTrackerKey`, which that
///   tile reads, so the events on screen stay on screen. Whitespace counts as
///   nothing said, matching the committed case above.
///
/// During [TextStreaming] with text, the historical message with the same ID
/// (if present) is filtered out and replaced with a [TextMessage] built from
/// the streaming data. During [AwaitingText], a [LoadingMessage] is appended.
List<ChatMessage> computeDisplayMessages(
  List<ChatMessage> messages,
  StreamingState? streaming, {
  required Set<String> toolCallParentIds,
}) {
  final shown = toolCallParentIds.isEmpty
      ? messages
      : [
          for (final message in messages)
            if (!isToolCallDeclaration(message, toolCallParentIds)) message,
        ];
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
