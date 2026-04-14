import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/soliplex_client.dart';

const _deepEq = DeepCollectionEquality();

/// Granular execution events for UI observability.
///
/// Emitted by `AgentSession` via the `lastExecutionEvent` signal so that
/// UI layers can react to fine-grained progress (text streaming, tool
/// execution, terminal states) without polling `RunState`.
@immutable
sealed class ExecutionEvent {
  const ExecutionEvent();
}

/// A delta of streamed assistant text.
class TextDelta extends ExecutionEvent {
  const TextDelta({required this.delta});

  /// The incremental text fragment.
  final String delta;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextDelta && delta == other.delta;

  @override
  int get hashCode => delta.hashCode;
}

/// The model has started a thinking/reasoning phase.
class ThinkingStarted extends ExecutionEvent {
  const ThinkingStarted();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ThinkingStarted;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A delta of streamed thinking content.
class ThinkingContent extends ExecutionEvent {
  const ThinkingContent({required this.delta});

  /// The incremental thinking text fragment.
  final String delta;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThinkingContent && delta == other.delta;

  @override
  int get hashCode => delta.hashCode;
}

/// A server-side tool call has started (observed, not executed locally).
class ServerToolCallStarted extends ExecutionEvent {
  const ServerToolCallStarted({
    required this.toolName,
    required this.toolCallId,
  });

  final String toolName;
  final String toolCallId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerToolCallStarted &&
          toolName == other.toolName &&
          toolCallId == other.toolCallId;

  @override
  int get hashCode => Object.hash(toolName, toolCallId);
}

/// A server-side tool call has completed.
class ServerToolCallCompleted extends ExecutionEvent {
  const ServerToolCallCompleted({
    required this.toolCallId,
    required this.result,
  });

  final String toolCallId;
  final String result;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerToolCallCompleted &&
          toolCallId == other.toolCallId &&
          result == other.result;

  @override
  int get hashCode => Object.hash(toolCallId, result);
}

/// A client-side tool execution has started.
class ClientToolExecuting extends ExecutionEvent {
  const ClientToolExecuting({required this.toolName, required this.toolCallId});

  final String toolName;
  final String toolCallId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientToolExecuting &&
          toolName == other.toolName &&
          toolCallId == other.toolCallId;

  @override
  int get hashCode => Object.hash(toolName, toolCallId);
}

/// A client-side tool execution has completed.
class ClientToolCompleted extends ExecutionEvent {
  const ClientToolCompleted({
    required this.toolCallId,
    required this.result,
    required this.status,
  });

  final String toolCallId;
  final String result;
  final ToolCallStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientToolCompleted &&
          toolCallId == other.toolCallId &&
          result == other.result &&
          status == other.status;

  @override
  int get hashCode => Object.hash(toolCallId, result, status);
}

/// The run completed successfully.
class RunCompleted extends ExecutionEvent {
  const RunCompleted();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RunCompleted;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The run failed with an error.
class RunFailed extends ExecutionEvent {
  const RunFailed({required this.error});

  final String error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RunFailed && error == other.error;

  @override
  int get hashCode => error.hashCode;
}

/// The run was cancelled.
class RunCancelled extends ExecutionEvent {
  const RunCancelled();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RunCancelled;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// AG-UI state update received from the backend.
class StateUpdated extends ExecutionEvent {
  const StateUpdated({required this.aguiState});

  final Map<String, dynamic> aguiState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateUpdated && _deepEq.equals(aguiState, other.aguiState);

  @override
  int get hashCode => _deepEq.hash(aguiState);
}

/// Step progress event for multi-step pipelines.
class StepProgress extends ExecutionEvent {
  const StepProgress({required this.stepName});

  final String stepName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepProgress && stepName == other.stepName;

  @override
  int get hashCode => stepName.hashCode;
}

/// A client-side tool is about to trigger a platform-level consent dialog.
///
/// Emitted immediately before tool execution when the tool's
/// `platformConsentNote` callback returns a non-null string on the current
/// platform.
///
/// Unlike [AwaitingApproval], this does NOT suspend execution — it is purely
/// informational so the UI can warn the user before the OS dialog appears
/// (e.g. "This tool will request clipboard access from the browser").
class PlatformConsentNotice extends ExecutionEvent {
  const PlatformConsentNotice({
    required this.toolCallId,
    required this.toolName,
    required this.note,
  });

  /// The tool call that will trigger the OS consent dialog.
  final String toolCallId;

  /// Name of the tool.
  final String toolName;

  /// Human-readable description of the platform consent that will be requested
  /// (e.g. "Clipboard access requires browser permission on web").
  final String note;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlatformConsentNotice &&
          toolCallId == other.toolCallId &&
          toolName == other.toolName &&
          note == other.note;

  @override
  int get hashCode => Object.hash(toolCallId, toolName, note);
}

/// A tool is awaiting user approval before executing a sensitive action.
///
/// Emitted by `AgentSession.requestApproval` so UI layers can display
/// an approval prompt. The event carries enough context for the UI to
/// render a meaningful description of what the tool wants to do.
class AwaitingApproval extends ExecutionEvent {
  const AwaitingApproval({
    required this.toolCallId,
    required this.toolName,
    required this.rationale,
  });

  /// The tool call that triggered the approval request.
  final String toolCallId;

  /// Name of the tool requesting approval.
  final String toolName;

  /// Human-readable explanation of what the tool wants to do.
  final String rationale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AwaitingApproval &&
          toolCallId == other.toolCallId &&
          toolName == other.toolName &&
          rationale == other.rationale;

  @override
  int get hashCode => Object.hash(toolCallId, toolName, rationale);
}

/// A sub-agent activity snapshot from the backend.
class ActivitySnapshot extends ExecutionEvent {
  const ActivitySnapshot({
    required this.activityType,
    required this.content,
  });

  /// The kind of activity (e.g. `'skill_tool_call'`).
  final String activityType;

  /// Payload from the backend (e.g. `{'tool_name': 'search'}`).
  final Map<String, dynamic> content;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivitySnapshot &&
          activityType == other.activityType &&
          _deepEq.equals(content, other.content);

  @override
  int get hashCode => Object.hash(activityType, _deepEq.hash(content));
}

/// Extension point for third-party plugins to emit custom events.
///
/// Use this when a `SessionExtension` needs to communicate
/// domain-specific progress to the UI without modifying the core
/// sealed class hierarchy.
class CustomExecutionEvent extends ExecutionEvent {
  const CustomExecutionEvent({required this.type, required this.payload});

  /// Identifier for the event kind (e.g. `'monty.execution_started'`).
  final String type;

  /// Arbitrary event payload.
  final Map<String, dynamic> payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomExecutionEvent &&
          type == other.type &&
          _deepEq.equals(payload, other.payload);

  @override
  int get hashCode => Object.hash(type, _deepEq.hash(payload));
}
