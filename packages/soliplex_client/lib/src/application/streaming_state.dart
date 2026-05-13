import 'package:meta/meta.dart';
import 'package:soliplex_client/src/application/run_phase.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';

/// Ephemeral streaming state (application layer, not domain).
///
/// Streaming is operation state that exists only during active streaming.
/// When streaming completes, the text becomes a domain message.
///
/// Use pattern matching for exhaustive handling:
/// ```dart
/// switch (streaming) {
///   case AwaitingText():
///     // Waiting for text to start (may have thinking content)
///   case TextStreaming(:final messageId, :final text):
///     // Text message is streaming
/// }
/// ```
@immutable
sealed class StreamingState {
  const StreamingState();
}

/// No message is currently streaming.
///
/// May contain buffered thinking text that arrived before the text message
/// started.
@immutable
class AwaitingText extends StreamingState {
  /// Creates a not streaming state.
  const AwaitingText({
    this.bufferedThinkingText = '',
    this.isThinkingStreaming = false,
    this.currentPhase = const ProcessingPhase(),
  });

  /// Thinking text buffered before text message started.
  final String bufferedThinkingText;

  /// Whether thinking is currently streaming.
  final bool isThinkingStreaming;

  /// Current run phase (persists until next phase starts).
  final RunPhase currentPhase;

  /// Whether there is any thinking content to display.
  bool get hasThinkingContent =>
      bufferedThinkingText.isNotEmpty || isThinkingStreaming;

  /// Creates a copy with modified properties.
  AwaitingText copyWith({
    String? bufferedThinkingText,
    bool? isThinkingStreaming,
    RunPhase? currentPhase,
  }) {
    return AwaitingText(
      bufferedThinkingText: bufferedThinkingText ?? this.bufferedThinkingText,
      isThinkingStreaming: isThinkingStreaming ?? this.isThinkingStreaming,
      currentPhase: currentPhase ?? this.currentPhase,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AwaitingText &&
          runtimeType == other.runtimeType &&
          bufferedThinkingText == other.bufferedThinkingText &&
          isThinkingStreaming == other.isThinkingStreaming &&
          currentPhase == other.currentPhase;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        bufferedThinkingText,
        isThinkingStreaming,
        currentPhase,
      );

  @override
  String toString() => 'AwaitingText('
      'thinkingText: ${bufferedThinkingText.length} chars, '
      'isThinkingStreaming: $isThinkingStreaming, '
      'phase: $currentPhase)';
}

/// Text is currently streaming.
@immutable
class TextStreaming extends StreamingState {
  /// Creates a streaming state with the given [messageId], [user], and
  /// accumulated [text].
  const TextStreaming({
    required this.messageId,
    required this.user,
    required this.text,
    this.thinkingText = '',
    this.isThinkingStreaming = false,
    this.currentPhase = const RespondingPhase(),
  });

  /// The ID of the message being streamed.
  final String messageId;

  /// The user role for this message.
  final ChatUser user;

  /// The text accumulated so far.
  final String text;

  /// The thinking text accumulated so far.
  final String thinkingText;

  /// Whether thinking is currently streaming.
  final bool isThinkingStreaming;

  /// Current run phase (persists until next phase starts).
  final RunPhase currentPhase;

  /// Creates a copy with the delta appended to text.
  TextStreaming appendDelta(String delta) {
    return TextStreaming(
      messageId: messageId,
      user: user,
      text: text + delta,
      thinkingText: thinkingText,
      isThinkingStreaming: isThinkingStreaming,
      currentPhase: currentPhase,
    );
  }

  /// Creates a copy with the delta appended to thinking text.
  TextStreaming appendThinkingDelta(String delta) {
    return TextStreaming(
      messageId: messageId,
      user: user,
      text: text,
      thinkingText: thinkingText + delta,
      isThinkingStreaming: isThinkingStreaming,
      currentPhase: currentPhase,
    );
  }

  /// Creates a copy with modified properties.
  TextStreaming copyWith({
    String? messageId,
    ChatUser? user,
    String? text,
    String? thinkingText,
    bool? isThinkingStreaming,
    RunPhase? currentPhase,
  }) {
    return TextStreaming(
      messageId: messageId ?? this.messageId,
      user: user ?? this.user,
      text: text ?? this.text,
      thinkingText: thinkingText ?? this.thinkingText,
      isThinkingStreaming: isThinkingStreaming ?? this.isThinkingStreaming,
      currentPhase: currentPhase ?? this.currentPhase,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextStreaming &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId &&
          user == other.user &&
          text == other.text &&
          thinkingText == other.thinkingText &&
          isThinkingStreaming == other.isThinkingStreaming &&
          currentPhase == other.currentPhase;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        messageId,
        user,
        text,
        thinkingText,
        isThinkingStreaming,
        currentPhase,
      );

  @override
  String toString() => 'TextStreaming('
      'messageId: $messageId, user: $user, '
      'text: ${text.length} chars, thinkingText: ${thinkingText.length} chars, '
      'phase: $currentPhase)';
}
