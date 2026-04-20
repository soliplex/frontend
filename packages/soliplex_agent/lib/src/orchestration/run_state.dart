import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/models/failure_reason.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// State of a single agent run lifecycle.
///
/// Use pattern matching for exhaustive handling:
/// ```dart
/// switch (state) {
///   case IdleState():
///     // No active run
///   case RunningState(:final threadKey, :final runId):
///     // Stream connected
///   case CompletedState(:final threadKey, :final runId):
///     // RunFinished received
///   case ToolYieldingState(:final pendingToolCalls):
///     // Waiting for client-side tool execution
///   case FailedState(:final reason, :final error):
///     // Error occurred
///   case CancelledState(:final threadKey):
///     // User cancelled
/// }
/// ```
@immutable
sealed class RunState {
  const RunState();
}

/// No active run.
@immutable
class IdleState extends RunState {
  /// Creates an [IdleState].
  const IdleState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is IdleState;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'IdleState()';
}

/// Stream connected and receiving events.
@immutable
class RunningState extends RunState {
  /// Creates a [RunningState].
  const RunningState({
    required this.threadKey,
    required this.runId,
    required this.conversation,
    required this.streaming,
  });

  /// The thread this run belongs to.
  final ThreadKey threadKey;

  /// The backend run ID.
  final String runId;

  /// Current domain state of the conversation.
  final Conversation conversation;

  /// Current ephemeral streaming state.
  final StreamingState streaming;

  /// Creates a copy with the given fields replaced.
  RunningState copyWith({
    Conversation? conversation,
    StreamingState? streaming,
  }) {
    return RunningState(
      threadKey: threadKey,
      runId: runId,
      conversation: conversation ?? this.conversation,
      streaming: streaming ?? this.streaming,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunningState &&
          threadKey == other.threadKey &&
          runId == other.runId &&
          conversation == other.conversation &&
          streaming == other.streaming;

  @override
  int get hashCode => Object.hash(threadKey, runId, conversation, streaming);

  @override
  String toString() => 'RunningState(runId: $runId, threadKey: $threadKey)';
}

/// Run completed successfully (RunFinished received).
@immutable
class CompletedState extends RunState {
  /// Creates a [CompletedState].
  const CompletedState({
    required this.threadKey,
    required this.runId,
    required this.conversation,
  });

  /// The thread this run belonged to.
  final ThreadKey threadKey;

  /// The backend run ID.
  final String runId;

  /// Final conversation state at completion.
  final Conversation conversation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompletedState &&
          threadKey == other.threadKey &&
          runId == other.runId &&
          conversation == other.conversation;

  @override
  int get hashCode => Object.hash(threadKey, runId, conversation);

  @override
  String toString() => 'CompletedState(runId: $runId, threadKey: $threadKey)';
}

/// Run failed with a classified error.
@immutable
class FailedState extends RunState {
  /// Creates a [FailedState].
  const FailedState({
    required this.threadKey,
    required this.reason,
    required this.error,
    this.conversation,
  });

  /// The thread this run belonged to.
  final ThreadKey threadKey;

  /// Classification of why the run failed.
  final FailureReason reason;

  /// Human-readable error description.
  final String error;

  /// Conversation state at time of failure, if available.
  final Conversation? conversation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FailedState &&
          threadKey == other.threadKey &&
          reason == other.reason &&
          error == other.error &&
          conversation == other.conversation;

  @override
  int get hashCode => Object.hash(threadKey, reason, error, conversation);

  @override
  String toString() =>
      'FailedState(reason: $reason, error: $error, '
      'threadKey: $threadKey)';
}

/// Run yielded pending tool calls for client-side execution.
///
/// The orchestrator transitions here when `RunFinishedEvent` arrives with
/// tool calls that are registered in the `ToolRegistry` (client-side tools).
/// Server-side tool calls are not included in [pendingToolCalls].
///
/// The caller should:
/// 1. Execute each tool in [pendingToolCalls] via `ToolRegistry.execute()`.
/// 2. Build executed results with `ToolCallStatus.completed` or `.failed`.
/// 3. Call `RunOrchestrator.submitToolOutputs(executedTools)` to resume.
///
/// Calling `cancelRun()` during this state transitions to [CancelledState].
/// Calling `startRun()` during this state throws [StateError].
@immutable
class ToolYieldingState extends RunState {
  /// Creates a [ToolYieldingState].
  const ToolYieldingState({
    required this.threadKey,
    required this.runId,
    required this.conversation,
    required this.pendingToolCalls,
    required this.toolDepth,
  });

  /// The thread this run belongs to.
  final ThreadKey threadKey;

  /// The backend run ID.
  final String runId;

  /// Conversation state at yield point.
  final Conversation conversation;

  /// Client-side tool calls ready to execute.
  final List<ToolCallInfo> pendingToolCalls;

  /// Number of yield/resume cycles completed (0 = first yield).
  final int toolDepth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolYieldingState &&
          threadKey == other.threadKey &&
          runId == other.runId &&
          conversation == other.conversation &&
          toolDepth == other.toolDepth &&
          _listEquals(pendingToolCalls, other.pendingToolCalls);

  @override
  int get hashCode => Object.hash(threadKey, runId, conversation, toolDepth);

  @override
  String toString() =>
      'ToolYieldingState(runId: $runId, '
      'pending: ${pendingToolCalls.length}, depth: $toolDepth)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Run was cancelled by the user.
@immutable
class CancelledState extends RunState {
  /// Creates a [CancelledState].
  const CancelledState({required this.threadKey, this.conversation});

  /// The thread this run belonged to.
  final ThreadKey threadKey;

  /// Conversation state at time of cancellation, if available.
  final Conversation? conversation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancelledState &&
          threadKey == other.threadKey &&
          conversation == other.conversation;

  @override
  int get hashCode => Object.hash(threadKey, conversation);

  @override
  String toString() => 'CancelledState(threadKey: $threadKey)';
}
