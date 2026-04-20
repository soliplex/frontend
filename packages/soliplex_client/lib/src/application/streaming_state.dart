import 'package:meta/meta.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';

/// Current activity type during a run.
///
/// Represents what the backend is currently doing. Persists until the next
/// activity starts (not when the current one ends), ensuring the UI can
/// display activity even for rapid events.
@immutable
sealed class ActivityType {
  const ActivityType();
}

/// No specific activity - initial state or processing.
@immutable
class ProcessingActivity extends ActivityType {
  /// Creates a processing activity.
  const ProcessingActivity();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ProcessingActivity;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ProcessingActivity()';
}

/// Model is thinking/reasoning.
@immutable
class ThinkingActivity extends ActivityType {
  /// Creates a thinking activity.
  const ThinkingActivity();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ThinkingActivity;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ThinkingActivity()';
}

/// One or more tools are being called.
@immutable
class ToolCallActivity extends ActivityType {
  /// Creates a tool call activity with a single tool name.
  const ToolCallActivity({
    required String toolName,
    this.latestToolCallId,
    this.timestamp,
  }) : toolNames = const {},
       _singleToolName = toolName;

  /// Creates a tool call activity with multiple tool names.
  const ToolCallActivity.multiple({
    required this.toolNames,
    this.latestToolCallId,
    this.timestamp,
  }) : _singleToolName = null;

  /// Names of tools being/have been called in this phase.
  final Set<String> toolNames;

  /// Single tool name for backward compatibility constructor.
  final String? _singleToolName;

  /// ID of the most recent tool call that updated this activity.
  final String? latestToolCallId;

  /// Timestamp of the most recent event that updated this activity.
  final int? timestamp;

  /// All tool names (handles both constructors).
  Set<String> get allToolNames =>
      _singleToolName != null ? {_singleToolName} : toolNames;

  /// Creates a new activity with an additional tool name.
  ToolCallActivity withToolName(
    String name, {
    String? latestToolCallId,
    int? timestamp,
  }) {
    return ToolCallActivity.multiple(
      toolNames: {...allToolNames, name},
      latestToolCallId: latestToolCallId ?? this.latestToolCallId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallActivity &&
          _setEquals(allToolNames, other.allToolNames) &&
          latestToolCallId == other.latestToolCallId &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    Object.hashAll(allToolNames.toList()..sort()),
    latestToolCallId,
    timestamp,
  );

  @override
  String toString() =>
      'ToolCallActivity(toolNames: $allToolNames, '
      'latestToolCallId: $latestToolCallId, timestamp: $timestamp)';

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}

/// Model is responding with text.
@immutable
class RespondingActivity extends ActivityType {
  /// Creates a responding activity.
  const RespondingActivity();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RespondingActivity;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'RespondingActivity()';
}

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
    this.currentActivity = const ProcessingActivity(),
  });

  /// Thinking text buffered before text message started.
  final String bufferedThinkingText;

  /// Whether thinking is currently streaming.
  final bool isThinkingStreaming;

  /// Current activity type (persists until next activity starts).
  final ActivityType currentActivity;

  /// Whether there is any thinking content to display.
  bool get hasThinkingContent =>
      bufferedThinkingText.isNotEmpty || isThinkingStreaming;

  /// Creates a copy with modified properties.
  AwaitingText copyWith({
    String? bufferedThinkingText,
    bool? isThinkingStreaming,
    ActivityType? currentActivity,
  }) {
    return AwaitingText(
      bufferedThinkingText: bufferedThinkingText ?? this.bufferedThinkingText,
      isThinkingStreaming: isThinkingStreaming ?? this.isThinkingStreaming,
      currentActivity: currentActivity ?? this.currentActivity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AwaitingText &&
          runtimeType == other.runtimeType &&
          bufferedThinkingText == other.bufferedThinkingText &&
          isThinkingStreaming == other.isThinkingStreaming &&
          currentActivity == other.currentActivity;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    bufferedThinkingText,
    isThinkingStreaming,
    currentActivity,
  );

  @override
  String toString() =>
      'AwaitingText('
      'thinkingText: ${bufferedThinkingText.length} chars, '
      'isThinkingStreaming: $isThinkingStreaming, '
      'activity: $currentActivity)';
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
    this.currentActivity = const RespondingActivity(),
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

  /// Current activity type (persists until next activity starts).
  final ActivityType currentActivity;

  /// Creates a copy with the delta appended to text.
  TextStreaming appendDelta(String delta) {
    return TextStreaming(
      messageId: messageId,
      user: user,
      text: text + delta,
      thinkingText: thinkingText,
      isThinkingStreaming: isThinkingStreaming,
      currentActivity: currentActivity,
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
      currentActivity: currentActivity,
    );
  }

  /// Creates a copy with modified properties.
  TextStreaming copyWith({
    String? messageId,
    ChatUser? user,
    String? text,
    String? thinkingText,
    bool? isThinkingStreaming,
    ActivityType? currentActivity,
  }) {
    return TextStreaming(
      messageId: messageId ?? this.messageId,
      user: user ?? this.user,
      text: text ?? this.text,
      thinkingText: thinkingText ?? this.thinkingText,
      isThinkingStreaming: isThinkingStreaming ?? this.isThinkingStreaming,
      currentActivity: currentActivity ?? this.currentActivity,
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
          currentActivity == other.currentActivity;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    messageId,
    user,
    text,
    thinkingText,
    isThinkingStreaming,
    currentActivity,
  );

  @override
  String toString() =>
      'TextStreaming('
      'messageId: $messageId, user: $user, '
      'text: ${text.length} chars, thinkingText: ${thinkingText.length} chars, '
      'activity: $currentActivity)';
}
