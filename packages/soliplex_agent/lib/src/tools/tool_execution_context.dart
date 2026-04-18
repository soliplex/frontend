import 'dart:async' show TimeoutException;

import 'package:soliplex_agent/src/orchestration/execution_event.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/agent_ui_delegate.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Context available to tools during execution.
///
/// Provides access to cancellation, child spawning, event emission,
/// and session-scoped extensions. Implemented by [AgentSession].
///
/// Tool executors MUST be cooperative with Dart's event loop:
/// - Insert `await Future<void>.delayed(Duration.zero)` in tight loops
/// - Use streaming/chunked processing for large data
/// - Check [cancelToken] at natural yield points
abstract interface class ToolExecutionContext {
  /// Cancellation token for the current run.
  CancelToken get cancelToken;

  /// Spawn a child agent session linked to the current session.
  ///
  /// When [roomId] is omitted, the child inherits the parent session's room.
  Future<AgentSession> spawnChild({required String prompt, String? roomId});

  /// Emit a granular execution event for UI observation.
  void emitEvent(ExecutionEvent event);

  /// Access a session-scoped extension by type.
  T? getExtension<T extends SessionExtension>();

  /// Suspend execution until the UI delegate approves.
  ///
  /// Denies if no delegate is set (headless/testing). Tools call this before
  /// performing sensitive actions (clipboard, file I/O, shell). The delegate
  /// receives the [rationale] to display to the user.
  ///
  /// Returns [AllowOnce] or [AllowSession] to proceed, [Deny] to block.
  /// On [Deny] the tool should return an error message to the LLM — do NOT
  /// throw, as that causes unconditional LLM retries.
  Future<ApprovalResult> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  });

  /// Spawn a child session, wait for completion, and return the output.
  ///
  /// Convenience wrapper around [spawnChild] + [AgentSession.awaitResult].
  /// Throws [StateError] on child failure, [TimeoutException] on timeout.
  /// When [roomId] is omitted, the child inherits the parent session's room.
  Future<String> delegateTask({
    required String prompt,
    String? roomId,
    Duration? timeout,
  });
}
