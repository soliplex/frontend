import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/activity_record.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/message_state.dart';

/// Status of a conversation.
///
/// Use pattern matching for exhaustive handling:
/// ```dart
/// switch (status) {
///   case Idle():
///     // No active run
///   case Running(:final runId):
///     // Run is active
///   case Completed():
///     // Run finished successfully
///   case Failed(:final error):
///     // Run failed
///   case Cancelled(:final reason):
///     // Run was cancelled
/// }
/// ```
@immutable
sealed class ConversationStatus {
  const ConversationStatus();
}

/// No run is currently active.
@immutable
class Idle extends ConversationStatus {
  /// Creates an idle status.
  const Idle();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Idle;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'Idle()';
}

/// A run is currently executing.
@immutable
class Running extends ConversationStatus {
  /// Creates a running status with the given [runId].
  const Running({required this.runId});

  /// The ID of the current run.
  final String runId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Running && runId == other.runId;

  @override
  int get hashCode => Object.hash(runtimeType, runId);

  @override
  String toString() => 'Running(runId: $runId)';
}

/// The run completed successfully.
@immutable
class Completed extends ConversationStatus {
  /// Creates a completed status.
  const Completed();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Completed;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'Completed()';
}

/// The run failed with an error.
@immutable
class Failed extends ConversationStatus {
  /// Creates a failed status with the given [error] message.
  const Failed({required this.error});

  /// The error message.
  final String error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Failed && error == other.error;

  @override
  int get hashCode => Object.hash(runtimeType, error);

  @override
  String toString() => 'Failed(error: $error)';
}

/// The run was cancelled.
@immutable
class Cancelled extends ConversationStatus {
  /// Creates a cancelled status with the given [reason].
  const Cancelled({required this.reason});

  /// The reason for cancellation.
  final String reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Cancelled && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'Cancelled(reason: $reason)';
}

/// Aggregate root for the live state of a conversation within a thread.
///
/// A Conversation is 1:1 with a Thread and contains:
/// - Messages displayed to the user
/// - Tool calls (history, not displayed)
/// - Run status
///
/// Streaming state is managed separately in the application layer.
/// All mutation methods return a new instance (immutable).
@immutable
class Conversation {
  /// Creates a conversation with the given properties.
  const Conversation({
    required this.threadId,
    this.messages = const [],
    this.toolCalls = const [],
    this.status = const Idle(),
    this.aguiState = const {},
    this.messageStates = const {},
    this.activities = const [],
  });

  /// Creates an empty conversation for the given thread.
  factory Conversation.empty({required String threadId}) {
    return Conversation(threadId: threadId);
  }

  /// The ID of the thread this conversation belongs to.
  final String threadId;

  /// Messages displayed to the user.
  final List<ChatMessage> messages;

  /// Tool calls history (not displayed to user).
  final List<ToolCallInfo> toolCalls;

  /// Current status of the conversation.
  final ConversationStatus status;

  /// AG-UI state from STATE_SNAPSHOT and STATE_DELTA events.
  ///
  /// Contains application-specific state like citation history from RAG
  /// queries.
  final Map<String, dynamic> aguiState;

  /// Per-message state keyed by user message ID.
  ///
  /// Each entry contains source references (citations) associated with the
  /// assistant's response to that user message. Populated at run completion
  /// by correlating AG-UI state changes.
  final Map<String, MessageState> messageStates;

  /// Persisted activity snapshots from `ActivitySnapshotEvent`, keyed by
  /// `messageId`. One record per unique `messageId`; `replace:true` updates
  /// in place, `replace:false` is ignored if a record already exists.
  final List<ActivityRecord> activities;

  /// Whether a run is currently active.
  bool get isRunning => status is Running;

  /// Returns a new conversation with the message appended.
  Conversation withAppendedMessage(ChatMessage message) {
    return copyWith(messages: [...messages, message]);
  }

  /// Returns a new conversation with the tool call added.
  Conversation withToolCall(ToolCallInfo toolCall) {
    return copyWith(toolCalls: [...toolCalls, toolCall]);
  }

  /// Returns a new conversation with the given status.
  Conversation withStatus(ConversationStatus newStatus) {
    return copyWith(status: newStatus);
  }

  /// Returns a new conversation with the given message state added.
  Conversation withMessageState(String userMessageId, MessageState state) {
    return copyWith(messageStates: {...messageStates, userMessageId: state});
  }

  /// Creates a copy with the given fields replaced.
  Conversation copyWith({
    String? threadId,
    List<ChatMessage>? messages,
    List<ToolCallInfo>? toolCalls,
    ConversationStatus? status,
    Map<String, dynamic>? aguiState,
    Map<String, MessageState>? messageStates,
    List<ActivityRecord>? activities,
  }) {
    return Conversation(
      threadId: threadId ?? this.threadId,
      messages: messages ?? this.messages,
      toolCalls: toolCalls ?? this.toolCalls,
      status: status ?? this.status,
      aguiState: aguiState ?? this.aguiState,
      messageStates: messageStates ?? this.messageStates,
      activities: activities ?? this.activities,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Conversation) return false;
    const listEquals = ListEquality<ChatMessage>();
    const toolCallListEquals = ListEquality<ToolCallInfo>();
    const mapEquals = DeepCollectionEquality();
    const messageStateMapEquals = MapEquality<String, MessageState>();
    const activityListEquals = ListEquality<ActivityRecord>();
    return threadId == other.threadId &&
        listEquals.equals(messages, other.messages) &&
        toolCallListEquals.equals(toolCalls, other.toolCalls) &&
        status == other.status &&
        mapEquals.equals(aguiState, other.aguiState) &&
        messageStateMapEquals.equals(messageStates, other.messageStates) &&
        activityListEquals.equals(activities, other.activities);
  }

  @override
  int get hashCode => Object.hash(
        threadId,
        const ListEquality<ChatMessage>().hash(messages),
        const ListEquality<ToolCallInfo>().hash(toolCalls),
        status,
        const DeepCollectionEquality().hash(aguiState),
        const MapEquality<String, MessageState>().hash(messageStates),
        const ListEquality<ActivityRecord>().hash(activities),
      );

  @override
  String toString() => 'Conversation(threadId: $threadId, '
      'messages: ${messages.length}, '
      'toolCalls: ${toolCalls.length}, '
      'status: $status)';
}
