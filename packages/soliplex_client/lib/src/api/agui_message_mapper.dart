import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';

import 'package:soliplex_client/src/domain/chat_message.dart';

/// Converts a list of [ChatMessage]s to AG-UI protocol [Message]s.
///
/// This mapper handles the conversion of internal chat message types to the
/// AG-UI protocol format required by the backend. The conversion rules are:
///
/// - [TextMessage] with [ChatUser.user] → [UserMessage]
/// - [TextMessage] with [ChatUser.assistant] → [AssistantMessage]
/// - [TextMessage] with [ChatUser.system] → [SystemMessage]
/// - [ToolCallMessage] → [AssistantMessage] with toolCalls, followed by
///   [ToolMessage]s for completed tool calls
/// - [GenUiMessage] → [AssistantMessage] with descriptive content
/// - [NoResponseTile] is skipped — round-tripping a synthesized empty
///   assistant tile would re-send it as a real assistant reply on the
///   next continuation run.
/// - [ErrorMessage], [LoadingMessage], [DroppedEventMessage] are skipped
///   (transient or frontend-only messages).
List<Message> convertToAgui(List<ChatMessage> chatMessages) {
  final result = <Message>[];

  for (final message in chatMessages) {
    switch (message) {
      case TextMessage():
        result.add(_convertTextMessage(message));

      case ToolCallMessage():
        result.addAll(_convertToolCallMessage(message));

      case GenUiMessage():
        result.add(_convertGenUiMessage(message));

      case ErrorMessage():
      case LoadingMessage():
      case DroppedEventMessage():
      case NoResponseTile():
        // Skip transient or frontend-only messages
        continue;
    }
  }

  return result;
}

Message _convertTextMessage(TextMessage message) {
  switch (message.user) {
    case ChatUser.user:
      final multimodalParts = _multimodalParts(message.parts);
      if (multimodalParts == null) {
        return UserMessage(id: message.id, content: message.text);
      }
      return UserMessage.multimodal(id: message.id, parts: multimodalParts);
    case ChatUser.assistant:
      return AssistantMessage(id: message.id, content: message.text);
    case ChatUser.system:
      return SystemMessage(id: message.id, content: message.text);
  }
}

/// Content parts for a multimodal `UserMessage`, or null when [parts] has
/// nothing the bare-string form cannot carry.
///
/// The multimodal arm of `content` is only worth using when a part isn't text;
/// a text-only list buys nothing the bare string does not already give us. An
/// *empty* array is worse than useless: `pydantic_ai`'s AG-UI adapter builds
/// the user's prompt only when the decoded content is non-empty, so an empty
/// array discards the turn with no error anywhere. Empty text runs are dropped
/// for the same reason in miniature — the OpenAI paths forward them verbatim
/// as empty text blocks instead of skipping them.
List<InputContent>? _multimodalParts(List<MessagePart>? parts) {
  if (parts == null) return null;

  final content = <InputContent>[];
  var hasNonTextPart = false;
  for (final part in parts) {
    switch (part) {
      case TextPart(:final text):
        if (text.isEmpty) continue;
      case ImagePart():
        hasNonTextPart = true;
    }
    content.add(_convertMessagePart(part));
  }

  return hasNonTextPart ? content : null;
}

InputContent _convertMessagePart(MessagePart part) {
  switch (part) {
    case TextPart():
      return TextInputContent(part.text);
    case ImagePart():
      return ImageInputContent(
        source: DataSource(
          value: base64Encode(part.bytes),
          mimeType: part.mimeType,
        ),
      );
  }
}

List<Message> _convertToolCallMessage(ToolCallMessage message) {
  final toolCalls = message.toolCalls
      .map(
        (tc) => ToolCall(
          id: tc.id,
          function: FunctionCall(
            name: tc.name,
            arguments: tc.arguments.isEmpty ? '{}' : tc.arguments,
          ),
        ),
      )
      .toList();

  final result = <Message>[
    AssistantMessage(id: message.id, toolCalls: toolCalls),
  ];

  // Add ToolMessage for each completed or failed tool call.
  // Failed tool calls send their error to the model so it can respond.
  for (final tc in message.toolCalls) {
    if (tc.status == ToolCallStatus.completed ||
        tc.status == ToolCallStatus.failed) {
      result.add(
        ToolMessage(
          id: 'tool_result_${tc.id}',
          toolCallId: tc.id,
          content: tc.result,
        ),
      );
    }
  }

  return result;
}

Message _convertGenUiMessage(GenUiMessage message) {
  final dataJson = jsonEncode(message.data);
  final content =
      'Displayed ${message.widgetName} component with data: $dataJson';

  return AssistantMessage(id: message.id, content: content);
}
