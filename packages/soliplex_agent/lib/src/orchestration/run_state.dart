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
    ThreadKey? threadKey,
    String? runId,
    Conversation? conversation,
    StreamingState? streaming,
  }) {
    return RunningState(
      threadKey: threadKey ?? this.threadKey,
      runId: runId ?? this.runId,
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
///
/// Construct via [FailedState.preRun] (failure before any backend run
/// started — [runId] is null) or [FailedState.duringRun] (failure during
/// an in-flight run — [runId] is required). The link between [runId] and
/// the pre/during disposition is enforced at the type level.
@immutable
class FailedState extends RunState {
  /// Constructs a [FailedState] for a failure that happened before any
  /// backend run started.
  const FailedState.preRun({
    required ThreadKey threadKey,
    required FailureReason reason,
    required String error,
    Conversation? conversation,
  }) : this._(
         threadKey: threadKey,
         reason: reason,
         error: error,
         conversation: conversation,
       );

  /// Constructs a [FailedState] for a failure that happened during a run.
  /// [runId] is required.
  const FailedState.duringRun({
    required ThreadKey threadKey,
    required String runId,
    required FailureReason reason,
    required String error,
    Conversation? conversation,
  }) : this._(
         threadKey: threadKey,
         runId: runId,
         reason: reason,
         error: error,
         conversation: conversation,
       );

  const FailedState._({
    required this.threadKey,
    required this.reason,
    required this.error,
    this.runId,
    this.conversation,
  });

  /// The thread this run belonged to.
  final ThreadKey threadKey;

  /// The backend run ID, if a run was in flight at the time of failure.
  /// Null iff the failure happened before any backend run started; see
  /// [FailedState.preRun] / [FailedState.duringRun].
  final String? runId;

  /// Classification of why the run failed.
  final FailureReason reason;

  /// Human-readable error description.
  final String error;

  /// Conversation state at time of failure, if available.
  final Conversation? conversation;

  /// Whether a backend run was in flight at the time of failure.
  bool get startedRun => runId != null;

  /// Returns [runId] when a backend run was in flight, otherwise throws
  /// [StateError].
  String requireRunId() {
    final id = runId;
    if (id == null) {
      throw StateError(
        'FailedState.requireRunId() called on a pre-run failure '
        '(reason: $reason).',
      );
    }
    return id;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FailedState &&
          threadKey == other.threadKey &&
          runId == other.runId &&
          reason == other.reason &&
          error == other.error &&
          conversation == other.conversation;

  @override
  int get hashCode =>
      Object.hash(threadKey, runId, reason, error, conversation);

  @override
  String toString() =>
      'FailedState(reason: $reason, error: $error, '
      'runId: ${runId ?? '<pre-run>'}, threadKey: $threadKey)';
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
///
/// Construct via [CancelledState.preRun] (cancel before any backend run
/// started — [runId] is null) or [CancelledState.duringRun] (cancel during
/// an in-flight run — [runId] is required). The link between [runId] and
/// the pre/during disposition is enforced at the type level.
@immutable
class CancelledState extends RunState {
  /// Constructs a [CancelledState] for a cancel that happened before any
  /// backend run started.
  const CancelledState.preRun({
    required ThreadKey threadKey,
    Conversation? conversation,
  }) : this._(threadKey: threadKey, conversation: conversation);

  /// Constructs a [CancelledState] for a cancel that happened during a
  /// run. [runId] is required.
  const CancelledState.duringRun({
    required ThreadKey threadKey,
    required String runId,
    Conversation? conversation,
  }) : this._(threadKey: threadKey, runId: runId, conversation: conversation);

  const CancelledState._({
    required this.threadKey,
    this.runId,
    this.conversation,
  });

  /// The thread this run belonged to.
  final ThreadKey threadKey;

  /// The backend run ID, if a run was in flight at the time of cancellation.
  /// Null iff cancellation happened before any backend run started; see
  /// [CancelledState.preRun] / [CancelledState.duringRun].
  final String? runId;

  /// Conversation state at time of cancellation, if available.
  final Conversation? conversation;

  /// Whether a backend run was in flight at the time of cancellation.
  bool get startedRun => runId != null;

  /// Returns [runId] when a backend run was in flight, otherwise throws
  /// [StateError].
  String requireRunId() {
    final id = runId;
    if (id == null) {
      throw StateError(
        'CancelledState.requireRunId() called on a pre-run cancel.',
      );
    }
    return id;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancelledState &&
          threadKey == other.threadKey &&
          runId == other.runId &&
          conversation == other.conversation;

  @override
  int get hashCode => Object.hash(threadKey, runId, conversation);

  @override
  String toString() =>
      'CancelledState(runId: ${runId ?? '<pre-run>'}, threadKey: $threadKey)';
}
