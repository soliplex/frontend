import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart';

import 'send_error.dart';

/// Owns the pending-spawn state machine shared by [ThreadViewState] and
/// [RoomState].
///
/// Encapsulates:
/// - The concurrency guard (`sessionState` is non-null while a spawn or
///   active session is in progress).
/// - Pending-future tracking and race detection via [cancel].
/// - Cleanup of a spawn future that was abandoned by [cancel].
///
/// Callers drive non-spawn lifecycle updates via [updateState].
///
/// **Dispose vs cancel semantics**: [dispose] only marks the spawner as
/// disposed; it does NOT cancel in-flight spawns. This preserves the
/// invariant that a session is always registered in the registry even if
/// the owning view is disposed before the spawn resolves. Use [cancel]
/// (via `cancelRun`/`cancelSpawn`) to explicitly abort a pending spawn.
class SessionSpawner {
  final Signal<AgentSessionState?> _sessionState = Signal(null);
  Future<AgentSession>? _pendingSpawn;

  ReadonlySignal<AgentSessionState?> get sessionState =>
      _sessionState.readonly();

  /// Updates the session state from outside the spawn lifecycle —
  /// e.g. running, completed, or cleared after detach.
  void updateState(AgentSessionState? state) => _sessionState.value = state;

  /// Runs the spawn state machine.
  ///
  /// - Guards against concurrent spawns (no-op if [sessionState] is
  ///   non-null).
  /// - Clears [errorSignal] and sets state to [AgentSessionState.spawning].
  /// - Awaits the future returned by [spawnFn] with race detection.
  /// - On success, calls [onSpawned]; the callback is responsible for
  ///   checking whether the owner is disposed before attaching.
  /// - On error, calls [isDisposed] (or checks `_sessionState == null`
  ///   for cancellation) before surfacing the error in [errorSignal].
  /// - Always cleans up pending state in the `finally` block.
  Future<void> spawn({
    required Future<AgentSession> Function() spawnFn,
    required Signal<SendError?> errorSignal,
    required String prompt,
    required bool Function() isDisposed,
    required void Function(AgentSession) onSpawned,
  }) async {
    if (_sessionState.value != null) return;
    errorSignal.value = null;
    _sessionState.value = AgentSessionState.spawning;
    Future<AgentSession>? future;
    try {
      future = spawnFn();
      _pendingSpawn = future;
      final session = await future;
      if (_pendingSpawn != future) return; // Cancelled via cancel().
      _pendingSpawn = null;
      onSpawned(session); // Callback owns the dispose/attach decision.
    } on Object catch (error) {
      // Suppress errors when cancelled (_sessionState cleared by cancel())
      // or when the owning view is disposed.
      if (isDisposed() || _sessionState.value == null) return;
      errorSignal.value = SendError(error, unsentText: prompt);
    } finally {
      if (_pendingSpawn == future) {
        _pendingSpawn = null;
        _sessionState.value = null;
      }
    }
  }

  /// Cancels the pending spawn, if any. Returns `true` if a spawn was
  /// cancelled, `false` if there was nothing pending.
  bool cancel() {
    final pending = _pendingSpawn;
    if (pending == null) return false;
    _pendingSpawn = null;
    _sessionState.value = null;
    unawaited(
      pending.then((s) {
        s.cancel();
        s.dispose();
      }).catchError((Object e) {
        debugPrint('SessionSpawner: cancelled spawn cleanup failed: $e');
      }),
    );
    return true;
  }

  /// No-op. In-flight spawns complete normally so sessions are always
  /// registered. Use [cancel] to explicitly abort a pending spawn.
  void dispose() {}
}
