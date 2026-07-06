import 'dart:async' show unawaited;

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.run_registry');

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
  const FailedRun(this.conversation, this.error, {required this.reason});
  final Conversation? conversation;
  final Object error;
  final FailureReason reason;
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
  /// [servers] wires the removal-eviction path: when a server disappears from
  /// the signal, its tracked runs are cancelled and dropped so they don't
  /// linger until the whole registry is disposed. Null in tests that don't
  /// exercise eviction.
  RunRegistry({ReadonlySignal<Map<String, ServerEntry>>? servers}) {
    _unsubscribe = servers?.subscribe(_evictRemoved);
  }

  final Map<ThreadKey, _TrackedRun> _runs = {};
  final Signal<Set<ThreadKey>> _activeKeys = Signal({});
  void Function()? _unsubscribe;
  bool _isDisposed = false;

  /// Reactive set of keys that currently have an active (non-terminal) session.
  ReadonlySignal<Set<ThreadKey>> get activeKeys => _activeKeys.readonly();

  /// Register a session for the given thread.
  ///
  /// If there is an existing active session for this key, it is
  /// cancelled first (at most one run per thread).
  ///
  /// If the registry has been disposed, the session is cancelled and
  /// the call asserts in debug / no-ops in release.
  void register(ThreadKey key, AgentSession session) {
    if (_isDisposed) {
      // Caller bug: a disposed registry can no longer manage the
      // session. Cancel first so the session is never leaked even
      // if the assert fires, log so the bug is observable in release,
      // then assert so it's loud in debug.
      session.cancel();
      _logger.error(
        'register called on disposed RunRegistry; cancelling session',
        attributes: {'key': key.toString()},
      );
      assert(false, 'register called on disposed RunRegistry for $key');
      return;
    }
    final existing = _runs[key];
    if (existing != null && existing.session != null) {
      existing.session!.cancel();
    }
    final run = _TrackedRun(session: session);
    _runs[key] = run;
    _activeKeys.value = {..._activeKeys.value, key};

    // Cache the terminal RunState as it arrives — session.runState becomes
    // unreadable once session.dispose() runs, which can happen before this
    // future's .then microtask fires (autoDispose flow, or external dispose).
    RunState? terminalState;
    final unsubscribe = session.runState.subscribe((state) {
      if (state is CompletedState ||
          state is FailedState ||
          state is CancelledState) {
        terminalState = state;
      }
    });

    unawaited(session.result.then((result) {
      unsubscribe();
      if (_isDisposed) return;
      // Bail if a newer registration superseded this run. The
      // superseded run can only resolve as cancelled-by-replacement;
      // the new session owns the key and produces its own outcome.
      if (!identical(_runs[key], run)) return;
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

  /// Cancels and drops every tracked run for a server no longer present in
  /// [snapshot], so a removed server's live session is cancelled and its
  /// captured outcome released instead of lingering until [dispose].
  void _evictRemoved(Map<String, ServerEntry> snapshot) {
    if (_isDisposed) return;
    final liveIds = snapshot.keys.toSet();
    final dead =
        _runs.keys.where((key) => !liveIds.contains(key.serverId)).toList();
    if (dead.isEmpty) return;
    for (final key in dead) {
      final session = _runs.remove(key)?.session;
      if (session == null) continue;
      // This runs inside the servers-signal batch: a throwing cancel would
      // otherwise abort the loop and unwind removeServer before it deletes the
      // stored session. Log and keep evicting the rest.
      try {
        session.cancel();
      } on Object catch (error, stackTrace) {
        _logger.error(
          'Failed to cancel run for removed server',
          error: error,
          stackTrace: stackTrace,
          attributes: {'key': key.toString()},
        );
      }
    }
    final nextActive = _activeKeys.value
        .where((key) => liveIds.contains(key.serverId))
        .toSet();
    if (nextActive.length != _activeKeys.value.length) {
      _activeKeys.value = nextActive;
    }
  }

  /// Cancels all active sessions and releases resources. Idempotent.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe?.call();
    for (final run in _runs.values) {
      run.session?.cancel();
    }
    _runs.clear();
    _activeKeys.dispose();
  }

  static RunOutcome _outcomeFrom(RunState? state, AgentResult result) {
    return switch (state) {
      CompletedState(:final conversation, :final runId) =>
        CompletedRun(conversation, runId: runId),
      FailedState(:final conversation, :final error, :final reason) =>
        FailedRun(conversation, error, reason: reason),
      CancelledState(:final conversation) => CancelledRun(conversation),
      // No terminal RunState was captured (external dispose ran before
      // any terminal state arrived) — derive the outcome from result.
      null => switch (result) {
          AgentFailure(:final reason) when reason == FailureReason.cancelled =>
            CancelledRun(null),
          AgentFailure(:final error, :final reason) =>
            FailedRun(null, error, reason: reason),
          AgentTimedOut() => FailedRun(
              null,
              'Session timed out',
              reason: FailureReason.internalError,
            ),
          AgentSuccess() => FailedRun(
              null,
              'Completed without terminal state',
              reason: FailureReason.internalError,
            ),
        },
      IdleState() || RunningState() || ToolYieldingState() => FailedRun(
          null,
          'Session result arrived in non-terminal state '
          '${state.runtimeType}: $result',
          reason: FailureReason.internalError,
        ),
    };
  }
}

class _TrackedRun {
  _TrackedRun({required this.session});
  AgentSession? session;
  RunOutcome? outcome;
}
