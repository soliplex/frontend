import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/models/failure_reason.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';

/// Result of a completed agent session.
///
/// Use pattern matching for exhaustive handling:
/// ```dart
/// switch (result) {
///   case AgentSuccess(:final output, :final runId):
///     // Handle success
///   case AgentFailure(:final reason, :final error):
///     // Handle failure by reason
///   case AgentTimedOut(:final elapsed):
///     // Handle timeout
/// }
/// ```
@immutable
sealed class AgentResult {
  const AgentResult({required this.threadKey});

  /// The thread this result belongs to.
  final ThreadKey threadKey;
}

/// The agent run completed successfully.
@immutable
class AgentSuccess extends AgentResult {
  /// Creates a successful result.
  const AgentSuccess({
    required super.threadKey,
    required this.output,
    required this.runId,
  });

  /// The final output text from the agent.
  final String output;

  /// The backend run ID for this completed run.
  final String runId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentSuccess &&
          threadKey == other.threadKey &&
          output == other.output &&
          runId == other.runId;

  @override
  int get hashCode => Object.hash(threadKey, output, runId);

  @override
  String toString() => 'AgentSuccess(runId: $runId, threadKey: $threadKey)';
}

/// The agent run failed.
@immutable
class AgentFailure extends AgentResult {
  /// Creates a failure result.
  const AgentFailure({
    required super.threadKey,
    required this.reason,
    required this.error,
    this.partialOutput,
  });

  /// Classification of why the run failed.
  final FailureReason reason;

  /// Human-readable error description.
  final String error;

  /// Any output received before the failure occurred.
  final String? partialOutput;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentFailure &&
          threadKey == other.threadKey &&
          reason == other.reason &&
          error == other.error &&
          partialOutput == other.partialOutput;

  @override
  int get hashCode => Object.hash(threadKey, reason, error, partialOutput);

  @override
  String toString() =>
      'AgentFailure(reason: $reason, error: $error, '
      'threadKey: $threadKey)';
}

/// The agent run timed out.
@immutable
class AgentTimedOut extends AgentResult {
  /// Creates a timeout result.
  const AgentTimedOut({required super.threadKey, required this.elapsed});

  /// How long the run was active before timing out.
  final Duration elapsed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentTimedOut &&
          threadKey == other.threadKey &&
          elapsed == other.elapsed;

  @override
  int get hashCode => Object.hash(threadKey, elapsed);

  @override
  String toString() =>
      'AgentTimedOut(elapsed: $elapsed, threadKey: $threadKey)';
}
