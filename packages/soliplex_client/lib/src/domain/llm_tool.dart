import 'package:meta/meta.dart';

/// Tool definition to pass to an LLM provider.
///
/// Maps to provider-specific tool formats internally.
@immutable
class LlmToolDef {
  /// Creates an [LlmToolDef].
  const LlmToolDef({
    required this.name,
    required this.description,
    this.parameters,
  });

  /// The tool name.
  final String name;

  /// Description of what the tool does.
  final String description;

  /// JSON Schema for the tool parameters.
  final Map<String, dynamic>? parameters;
}

/// A tool call made by the LLM.
@immutable
class LlmToolCall {
  /// Creates an [LlmToolCall].
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The call ID.
  final String id;

  /// The tool name.
  final String name;

  /// The arguments as a JSON string.
  final String arguments;
}

/// Message in a tool-aware conversation.
///
/// These are Soliplex domain types for representing chat history
/// when calling LLM providers. Provider implementations map these
/// to their SDK-specific message formats.
@immutable
sealed class LlmChatMessage {
  /// Creates an [LlmChatMessage].
  const LlmChatMessage();
}

/// A user message.
@immutable
class LlmUserMessage extends LlmChatMessage {
  /// Creates an [LlmUserMessage].
  const LlmUserMessage(this.content);

  /// The message text, or `null` when the source message has no plain-text
  /// projection — AG-UI reports null for a `content` encoded as a list of
  /// parts, even one holding only text.
  ///
  /// This type carries text only, so a null says nothing about what the message
  /// held. It is distinct from `''`, which is a sendable empty message: a
  /// consumer substitutes a placeholder or rejects the turn.
  final String? content;
}

/// An assistant message, optionally with tool calls.
@immutable
class LlmAssistantMessage extends LlmChatMessage {
  /// Creates an [LlmAssistantMessage].
  const LlmAssistantMessage({this.content, this.toolCalls});

  /// The message text (may be null if only tool calls).
  final String? content;

  /// Tool calls made in this turn.
  final List<LlmToolCall>? toolCalls;
}

/// A tool result message.
@immutable
class LlmToolResultMessage extends LlmChatMessage {
  /// Creates an [LlmToolResultMessage].
  const LlmToolResultMessage({required this.callId, required this.output});

  /// The call ID this result corresponds to.
  final String callId;

  /// The tool output.
  final String output;
}

/// A system message.
@immutable
class LlmSystemMessage extends LlmChatMessage {
  /// Creates an [LlmSystemMessage].
  const LlmSystemMessage(this.content);

  /// The system instruction text.
  final String content;
}
