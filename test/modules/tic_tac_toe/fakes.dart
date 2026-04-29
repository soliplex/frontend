import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';

/// Minimal AgentSession stub for controller tests. `awaitResult` blocks
/// until [completeSuccess] or [cancel]. `cancel` completes with an
/// AgentFailure (the sealed AgentResult does not include AgentCancelled
/// as a subtype here — failures cover the cancel/error branches the
/// controller cares about).
class FakeAgentSession implements AgentSession {
  final Completer<AgentResult> _completer = Completer<AgentResult>();

  void completeSuccess() {
    if (_completer.isCompleted) return;
    _completer.complete(
      const AgentSuccess(
        runId: 'fake-run',
        threadKey: (
          serverId: 's',
          roomId: 'r',
          threadId: 't',
        ),
        output: '',
      ),
    );
  }

  @override
  Future<AgentResult> awaitResult({Duration? timeout}) => _completer.future;

  @override
  void cancel() {
    if (_completer.isCompleted) return;
    _completer.complete(
      const AgentFailure(
        reason: FailureReason.cancelled,
        error: 'Session cancelled',
        threadKey: (
          serverId: 's',
          roomId: 'r',
          threadId: 't',
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
