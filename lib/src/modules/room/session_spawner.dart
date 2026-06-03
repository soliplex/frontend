import 'dart:async' show unawaited;
import 'dart:developer' as dev;

import 'package:soliplex_agent/soliplex_agent.dart';

import '../auth/auth_session.dart';
import 'send_error.dart';

/// Owns the pending-spawn state machine shared by [ThreadViewState] and
/// [RoomState].
///
/// Encapsulates:
/// - The concurrency guard — [spawn] is a no-op while another spawn is
///   in-flight.
/// - Pending-future tracking and race detection via [cancel].
/// - Cleanup of a spawn future that was abandoned by [cancel].
///
/// The lifecycle [Signal<AgentSessionState?>] is NOT owned by the spawner;
/// callers pass an `onStateTransition` callback and own the signal they
/// update from it. This keeps the spawner scoped to spawn-phase logic and
/// leaves session-level state (running, detached, etc.) to the caller.
///
/// Callback asymmetry: [spawn] notifies `onStateTransition` with
/// `spawning` on entry, and with `null` from its `finally` block on
/// any non-success path (spawn future failed, owner disposed, or
/// `onSpawned` threw). On success the spawner does not emit again —
/// the caller's `onSpawned` is expected to drive the next transition.
/// [cancel] deliberately does NOT call back into `onStateTransition`
/// — callers are responsible for clearing their lifecycle signal when
/// they invoke [cancel]. This asymmetry is intentional: the caller
/// already knows a cancel is happening and may want to bundle other
/// side-effects with the signal clear.
class SessionSpawner {
  SessionSpawner({required AuthSession auth}) : _auth = auth;

  final AuthSession _auth;
  Future<AgentSession>? _pendingSpawn;
  bool _cancelled = false;

  bool get isSpawning => _pendingSpawn != null;

  /// Runs the spawn state machine.
  ///
  /// - Guards against concurrent spawns (no-op if already spawning).
  /// - Clears [errorSignal] and emits
  ///   [AgentSessionState.spawning] via [onStateTransition].
  /// - Awaits the future returned by [spawnFn] with race detection.
  /// - On success, calls [onSpawned]; the callback is responsible for
  ///   checking whether the owner is disposed before attaching.
  /// - On error, surfaces via [errorSignal] unless cancelled or the owner
  ///   is disposed.
  /// - Emits `null` via [onStateTransition] when the spawn completes
  ///   without success (e.g. error path), so callers can clear their
  ///   lifecycle signal without duplicating bookkeeping.
  ///
  /// [onAuthExpired] fires on the AuthException branch with the original
  /// [prompt] just before [markSessionExpired] flips the session. Callers
  /// use it to persist state that won't survive the route guard's
  /// redirect. The spawner stays generic — what to persist is the
  /// caller's call.
  Future<void> spawn({
    required Future<AgentSession> Function() spawnFn,
    required Signal<SendError?> errorSignal,
    required String prompt,
    required bool Function() isDisposed,
    required void Function(AgentSession) onSpawned,
    required void Function(AgentSessionState?) onStateTransition,
    void Function(String prompt)? onAuthExpired,
  }) async {
    if (_pendingSpawn != null) return;
    _cancelled = false;
    errorSignal.value = null;
    onStateTransition(AgentSessionState.spawning);
    var succeeded = false;
    try {
      final future = spawnFn();
      _pendingSpawn = future;
      final session = await future;
      if (_cancelled) return;
      onSpawned(session); // Callback owns the dispose/attach decision.
      succeeded = true;
    } on PermissionDeniedException catch (error) {
      if (_cancelled || isDisposed()) return;
      dev.log(
        'Spawn forbidden (403)',
        error: error,
        name: 'SessionSpawner',
        level: 900,
      );
      errorSignal.value = SendError(error, unsentText: prompt);
    } on AuthException catch (error) {
      if (_cancelled || isDisposed()) return;
      dev.log(
        'Spawn hit AuthException; funneling to markSessionExpired',
        error: error,
        name: 'SessionSpawner',
        level: 900,
      );
      // The persistence callback runs first so the caller can save
      // state the redirect would otherwise drop, but a throw here must
      // not skip `markSessionExpired` — that funnel is load-bearing.
      try {
        onAuthExpired?.call(prompt);
      } catch (callbackError, st) {
        dev.log(
          'onAuthExpired callback threw; continuing to markSessionExpired',
          error: callbackError,
          stackTrace: st,
          name: 'SessionSpawner',
          level: 1000,
        );
      }
      _auth.markSessionExpired();
    } on Object catch (error) {
      if (_cancelled || isDisposed()) return;
      errorSignal.value = SendError(error, unsentText: prompt);
    } finally {
      _pendingSpawn = null;
      if (!_cancelled && !succeeded) {
        onStateTransition(null);
      }
    }
  }

  /// Cancels the pending spawn, if any. Returns `true` if a spawn was
  /// cancelled, `false` if there was nothing pending. Callers are
  /// responsible for clearing their lifecycle signal — the spawner does
  /// not call back into `onStateTransition` from here.
  bool cancel() {
    final pending = _pendingSpawn;
    if (pending == null) return false;
    _pendingSpawn = null;
    _cancelled = true;
    unawaited(
      pending.then((s) {
        s.cancel();
        s.dispose();
      }).then((_) {}, onError: (Object e, StackTrace st) {
        if (e is AuthException) {
          // A 401 arrived after the user cancelled the spawn. The
          // caller is gone, but the auth state machine is the
          // singleton funnel and still needs the signal — otherwise
          // the next interaction continues with a dead session.
          dev.log(
            'Cancelled spawn cleanup hit AuthException; '
            'funneling to markSessionExpired',
            error: e,
            stackTrace: st,
            name: 'SessionSpawner',
            level: 900,
          );
          _auth.markSessionExpired();
          return;
        }
        dev.log(
          'Cancelled spawn cleanup failed',
          error: e,
          stackTrace: st,
          name: 'SessionSpawner',
          level: 900,
        );
      }),
    );
    return true;
  }
}
