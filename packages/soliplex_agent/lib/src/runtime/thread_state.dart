import 'package:meta/meta.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show StateBus, ThreadHistory;

/// Per-thread state owned by `AgentRuntime` and keyed by `ThreadKey`.
///
/// Replaces the old `_threadHistories: Map<String, ThreadHistory>`
/// cache with a richer per-thread bundle that survives session
/// boundaries.
///
/// Phase 1 step 3a introduces this type. Subsequent steps evolve its
/// fields:
///
/// - 3a (this commit): introduces `bus` and keeps `history` so the
///   existing resume-from-prior-session pathway keeps working.
/// - 3c–3d: `bus` becomes the canonical writer/reader for AG-UI
///   state events.
/// - 3e–3f: `Conversation` (currently transient on the session) moves
///   here, so `history` is replaced by a per-thread `Conversation`
///   reference.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 3).
@immutable
class ThreadState {
  /// Constructs a per-thread bundle with a fresh [bus] and no history.
  ///
  /// The [bus] is owned by the [ThreadState]; disposing the state
  /// disposes the bus.
  ThreadState({StateBus? bus, this.history}) : bus = bus ?? StateBus();

  /// Per-thread reactive document. AG-UI events feed in via
  /// [StateBus.setAgentState] and [StateBus.update]; surfaces read
  /// via [StateBus.project].
  final StateBus bus;

  /// Cached AG-UI state + messages from a prior session on this
  /// thread, used to seed a new session's resume path. Step 3e
  /// removes the `aguiState` field (the bus is canonical); step 3f
  /// folds the remaining fields into a per-thread `Conversation`.
  final ThreadHistory? history;

  /// Returns a copy with a different [history]. The underlying [bus]
  /// is preserved across mutations because it carries the live
  /// signal subscriptions.
  ThreadState withHistory(ThreadHistory? next) =>
      ThreadState(bus: bus, history: next);

  /// Tear down. Disposes the underlying [bus]. Idempotent — the bus's
  /// own [StateBus.dispose] guards against double-dispose internally.
  void dispose() {
    bus.dispose();
  }
}
