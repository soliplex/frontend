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
  /// linger until the whole registry is disposed. Eviction is driven entirely by
  /// the signal, so a signal that never changes simply never evicts.
  RunRegistry({required ReadonlySignal<Map<String, ServerEntry>> servers})
      : _servers = servers {
    _unsubscribe = servers.subscribe(_evictRemoved);
  }

  final ReadonlySignal<Map<String, ServerEntry>> _servers;
  final Map<ThreadKey, _TrackedRun> _runs = {};
  final Signal<Set<ThreadKey>> _activeKeys = Signal({});
  late final void Function() _unsubscribe;
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
      // Above the supersession bail: a superseded run that had already
      // failed is exactly a run whose failure should be recorded, and
      // filing touches neither _runs nor _activeKeys.
      _autoFileFailure(key, terminalState);
      // Bail if a newer registration superseded this run. The
      // superseded run can only resolve as cancelled-by-replacement;
      // the new session owns the key and produces its own outcome.
      if (!identical(_runs[key], run)) return;
      run.outcome = _outcomeFrom(terminalState, result);
      run.session = null;
      _activeKeys.value = _activeKeys.value.difference({key});
    }));
  }

  /// Files a thumbs-down for a run the backend failed, so that failure becomes
  /// discoverable: the backend writes `RUN_ERROR` to its event log but keeps no
  /// queryable run status, and feedback is the only table an application-level
  /// query reaches.
  ///
  /// This lives in the registry rather than the UI because a view unmounts. A
  /// run that fails after the user navigates away must still be recorded, and
  /// the registry outlives that navigation.
  ///
  /// Filing needs no dedup flag: one `result.then` per [register] call, and
  /// each session is registered once, at spawn. That is exact at dispatch, not
  /// at record existence — the record appears only when the POST lands, so
  /// within one round trip a reader can still find nothing.
  ///
  /// A run whose session was disposed before publishing a terminal state
  /// arrives here with [terminalState] null and goes unfiled. [_outcomeFrom]
  /// recovers that case from the [AgentResult], but nothing can be filed
  /// against it: [AgentFailure] carries no runId.
  void _autoFileFailure(ThreadKey key, RunState? terminalState) {
    if (terminalState is! FailedState) return;
    final runId = terminalState.runId;
    // Null iff the failure preceded any backend run, leaving no row to
    // attach feedback to.
    if (runId == null) return;
    final recording = _recordingFor(terminalState.reason);
    final failure = recording.filedAs;
    if (failure == null) {
      final attributes = {
        'key': key.toString(),
        'runId': runId,
        'reason': terminalState.reason.name,
      };
      if (recording.logUnfiled) {
        // Not the backend's run outcome, so not filed — but still a run the
        // user got no answer from, and the orchestrator's own 'Run failed'
        // record names no run. This is what ties it to one.
        _logger.warning(
          'Run failed without filing feedback',
          attributes: attributes,
        );
      } else {
        // One line per failure the whitelist declines, so which failures file
        // is answerable from a running installation and not only from tests.
        _logger.info('Not filing feedback for a failed run',
            attributes: attributes);
      }
      return;
    }
    final api = _servers.value[key.serverId]?.connection.api;
    // The server was removed while the run was in flight, so there is nothing
    // left to POST to. Signing out does not reach here — it leaves the entry
    // in place, so that path files and meets a 401 below.
    if (api == null) return;

    unawaited(
      api
          .submitFeedback(
        key.roomId,
        key.threadId,
        runId,
        FeedbackType.thumbsDown,
        reason: '[auto] Run failed: $failure',
      )
          .then((_) {
        _logger.info(
          'Auto-filed feedback for a failed run',
          attributes: {
            'key': key.toString(),
            'runId': runId,
            'reason': terminalState.reason.name,
          },
        );
      }, onError: (Object error, StackTrace stackTrace) {
        // At most once, attempted: the record is best-effort and a lost POST
        // leaves the failure unrecorded rather than crashing the run that
        // already failed.
        //
        // This request carries a body, and that body is generated text that
        // a later edit replaces with the user's own, so an exception echoing
        // what the server rejected would render it into the exportable log
        // buffer. Only a NetworkException — whose host and OS error are the
        // whole diagnosis — is forwarded whole; anything else keeps its shape
        // plus the status code, a protocol constant rather than a value the
        // server chose.
        _logger.warning(
          error is AuthException
              ? 'Auto-filing feedback hit AuthException; '
                  'funneling to markSessionExpired'
              : 'Failed to auto-file feedback for a failed run',
          error: error is NetworkException ? error : null,
          stackTrace: stackTrace,
          attributes: {
            'key': key.toString(),
            'runId': runId,
            if (error is ApiException) 'statusCode': error.statusCode,
            if (error is! NetworkException) 'failure': describeFailure(error),
          },
        );
        if (error is AuthException) {
          // The grant is dead, so send the user to re-auth now rather than
          // leaving them on a signed-in UI until their next action fails.
          // Only on a 401: flipping the session for a recoverable failure
          // would lock them out (see AuthSession.refreshIfExpiringSoon).
          // Re-read rather than capture: an eviction in the interval means
          // there is no session left to expire, which is the right answer.
          _servers.value[key.serverId]?.auth.markSessionExpired();
        }
      }),
    );
  }

  /// How a failed run is recorded: [filedAs] is the failure description filed
  /// as feedback, or null when the failure is not filed, and [logUnfiled] asks
  /// for a log line naming the run when it is not.
  ///
  /// Auto-filing needs a whitelist because filing the wrong thing writes wrong
  /// data into a human triage queue. Manual filing needs no equivalent: a
  /// human choosing to report something is the judgement we wanted.
  static ({String? filedAs, bool logUnfiled}) _recordingFor(
    FailureReason reason,
  ) {
    return switch (reason) {
      // The backend said it failed, so it is the backend's run outcome.
      FailureReason.serverError => (filedAs: 'server error', logUnfiled: false),
      // The orchestrator gave up after exhausting tool retries; the run is
      // dead either way.
      FailureReason.toolExecutionFailed => (
          filedAs: 'tool execution failed',
          logUnfiled: false
        ),
      // `classifyError`'s fallback, so it names a client-side or as-yet
      // unclassified failure rather than a backend run outcome — and the
      // client disconnects, which the backend answers by keeping the run
      // alive, so it may well complete. Filing would send a reviewer to a
      // run that succeeded. Logged instead, because it is still a run the
      // user got no answer from.
      FailureReason.internalError => (filedAs: null, logUnfiled: true),
      // Unreachable on a FailedState — a cancel publishes CancelledState,
      // which the guard above drops. Present for exhaustiveness.
      FailureReason.cancelled => (filedAs: null, logUnfiled: false),
      // Session expiry and authz verdicts, not run quality.
      FailureReason.authExpired || FailureReason.permissionDenied => (
          filedAs: null,
          logUnfiled: false
        ),
      // The backend deliberately keeps a run alive across a client
      // disconnect so the client can reconnect and watch it finish. Filing
      // would record successfully-completed runs as failed.
      FailureReason.networkLost || FailureReason.streamResumeFailed => (
          filedAs: null,
          logUnfiled: false
        ),
      // Capacity, not answer quality. Nothing reaches these runs afterwards
      // either: a 429 surfaces as a transient send-error banner, never as a
      // tile, so there is no manual path to fall back on.
      FailureReason.rateLimited => (filedAs: null, logUnfiled: false),
    };
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
    final liveIds = snapshot.keys.toSet();
    _evictWhere((key) => !liveIds.contains(key.serverId));
  }

  /// Cancels and drops every tracked run for [serverId], so a different user
  /// signing in on that server can't reattach to the prior user's runs or read
  /// their captured outcomes. No-op if the server has no tracked runs.
  void evictServer(String serverId) {
    _evictWhere((key) => key.serverId == serverId);
  }

  void _evictWhere(bool Function(ThreadKey key) shouldEvict) {
    if (_isDisposed) return;
    final dead = _runs.keys.where(shouldEvict).toList();
    if (dead.isEmpty) return;
    for (final key in dead) {
      final session = _runs.remove(key)?.session;
      if (session != null) _cancelQuietly(key, session);
    }
    final nextActive =
        _activeKeys.value.where((key) => !shouldEvict(key)).toSet();
    if (nextActive.length != _activeKeys.value.length) {
      _activeKeys.value = nextActive;
    }
  }

  /// Cancels [session], swallowing and logging any throw. [cancel] runs real
  /// teardown that can throw; both callers cancel in a loop where one throw must
  /// not strand the rest. Eviction also runs synchronously inside a signal
  /// write, where an escape would unwind the caller: on server removal, aborting
  /// `removeServer` before it deletes the persisted session; on a user switch
  /// mid-login, unwinding the sign-in.
  void _cancelQuietly(ThreadKey key, AgentSession session) {
    try {
      session.cancel();
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Failed to cancel run',
        error: error,
        stackTrace: stackTrace,
        attributes: {'key': key.toString()},
      );
    }
  }

  /// Cancels all active sessions and releases resources. Idempotent.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
    for (final entry in _runs.entries) {
      final session = entry.value.session;
      if (session != null) _cancelQuietly(entry.key, session);
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
