import 'dart:async' show unawaited;

import 'package:soliplex_agent/soliplex_agent.dart';

/// Terminal outcome of an agent run.
sealed class RunOutcome {
  const RunOutcome();
}

/// The run completed successfully.
class CompletedRun extends RunOutcome {
  const CompletedRun(this.conversation, {required this.runId});
  final Conversation conversation;
  final String runId;
}

/// The run failed.
class FailedRun extends RunOutcome {
  const FailedRun(this.conversation, this.error);
  final Conversation? conversation;
  final Object error;
}

/// The run was cancelled.
class CancelledRun extends RunOutcome {
  const CancelledRun(this.conversation);
  final Conversation? conversation;
}

/// Tracks active agent runs across rooms and threads.
///
/// Sessions registered here survive navigation — the registry holds
/// them alive and captures terminal outcomes. When the user returns
/// to a thread, [ThreadViewState] checks the registry for an active
/// session to reattach to or a completed outcome to display.
class RunRegistry {
  final Map<ThreadKey, _TrackedRun> _runs = {};
  final Signal<Set<ThreadKey>> _activeKeys = Signal({});
  bool _isDisposed = false;

  /// Reactive set of keys that currently have an active (non-terminal) session.
  ReadonlySignal<Set<ThreadKey>> get activeKeys => _activeKeys.readonly();

  /// Register a session for the given thread.
  ///
  /// If there is an existing active session for this key, it is
  /// cancelled first (at most one run per thread).
  void register(ThreadKey key, AgentSession session) {
    if (_isDisposed) {
      // Cancel rather than leak the session — the registry can no
      // longer manage it and would otherwise drop it silently.
      session.cancel();
      return;
    }
    final existing = _runs[key];
    if (existing != null && existing.session != null) {
      existing.session!.cancel();
    }
    final run = _TrackedRun(session: session);
    _runs[key] = run;
    _activeKeys.value = {..._activeKeys.value, key};

    unawaited(session.result.then((result) {
      if (_isDisposed) return;
      // Bail if a newer registration replaced this run. Removing the
      // key here would clear it while the new session is still active,
      // and the orphan's outcome is intentionally discarded.
      if (!identical(_runs[key], run)) return;
      final terminalState = session.runState.value;
      run.outcome = _outcomeFrom(terminalState, result);
      run.session = null;
      _activeKeys.value = _activeKeys.value.difference({key});
    }));
  }

  /// Returns the active (non-terminal) session for a thread.
  AgentSession? activeSession(ThreadKey key) {
    return _runs[key]?.session;
  }

  /// Returns the terminal outcome for a thread's last run.
  ///
  /// Persists until replaced by a new run or the registry is disposed.
  RunOutcome? completedOutcome(ThreadKey key) {
    return _runs[key]?.outcome;
  }

  /// Cancels all active sessions and releases resources. Idempotent.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final run in _runs.values) {
      run.session?.cancel();
    }
    _runs.clear();
    _activeKeys.dispose();
  }

  static RunOutcome _outcomeFrom(RunState state, AgentResult result) {
    return switch (state) {
      CompletedState(:final conversation, :final runId) =>
        CompletedRun(conversation, runId: runId),
      FailedState(:final conversation, :final error) =>
        FailedRun(conversation, error),
      CancelledState(:final conversation) => CancelledRun(conversation),
      _ => FailedRun(null, 'Unexpected terminal state: ${state.runtimeType}'),
    };
  }
}

class _TrackedRun {
  _TrackedRun({required this.session});
  AgentSession? session;
  RunOutcome? outcome;
}
