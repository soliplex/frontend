import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:ui_plugin/ui_plugin.dart';

/// Merges streaming state and ephemeral injected messages into the message
/// list for unified rendering.
///
/// During [TextStreaming], the historical message with the same ID (if
/// present) is filtered out and replaced with a [TextMessage] built from
/// the streaming data. During [AwaitingText], a [LoadingMessage] is
/// appended. [injected] messages are appended last as [ChatUser.system]
/// bubbles — they are client-only and not persisted.
List<ChatMessage> computeDisplayMessages(
  List<ChatMessage> messages,
  StreamingState? streaming, {
  List<InjectedMessage> injected = const [],
}) {
  final base = _mergeStreaming(messages, streaming);
  if (injected.isEmpty) return base;
  return [
    ...base,
    ...injected.map(
      (m) => SystemInfoMessage(
        id: m.id,
        createdAt: m.createdAt,
        text: m.content,
        format: m.format,
      ),
    ),
  ];
}

List<ChatMessage> _mergeStreaming(
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
