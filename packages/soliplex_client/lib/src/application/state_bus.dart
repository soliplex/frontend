import 'package:meta/meta.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_client/src/domain/surface.dart';

/// Per-thread reactive bus that mirrors AG-UI agent state and runs
/// registered surface projections over it.
///
/// Pure-Dart, no Flutter. The Flutter widget layer subscribes to the
/// signals exposed here through `signals_flutter`.
///
/// Lifecycle: a host (typically the per-thread view state in the
/// app shell) constructs one `StateBus` per active thread, feeds
/// raw agent-state maps into [setAgentState] (or applies deltas
/// via [update]) as AG-UI events arrive, and disposes when the
/// thread is torn down. Surfaces register projections via [project]
/// and read the returned signal.
///
/// This is the M3 plumbing in the GenUI plan — the seam between the
/// AG-UI event pipeline (already wired through
/// `AguiEventProcessor`) and the Surface contract.
class StateBus {
  /// Construct a fresh bus. The initial agent state is empty; feed
  /// the first snapshot via [setAgentState] when one arrives.
  StateBus({Map<String, dynamic> initialAgentState = const {}})
      : _agentState = signal(_freeze(initialAgentState));

  final Signal<Map<String, dynamic>> _agentState;

  bool _disposed = false;

  /// Read-only feed of the current raw agent-state map.
  ///
  /// Identity changes on every replacement so listeners always fire,
  /// even when delta application produces structurally-equal maps.
  ReadonlySignal<Map<String, dynamic>> get agentState => _agentState.readonly();

  /// Replace the entire agent-state map. Call when an AG-UI
  /// `StateSnapshotEvent` arrives.
  void setAgentState(Map<String, dynamic> next) {
    if (_disposed) return;
    _agentState.value = _freeze(next);
  }

  /// Replace via a transform applied to the current map. Convenient
  /// for delta-applying code that wants to compute the next state in
  /// one step:
  ///
  /// ```dart
  /// bus.update((current) => applyJsonPatch(current, deltaOps));
  /// ```
  void update(
    Map<String, dynamic> Function(Map<String, dynamic> current) transform,
  ) {
    if (_disposed) return;
    _agentState.value = _freeze(transform(_agentState.value));
  }

  /// Register a [StateProjection] and receive a derived signal that
  /// recomputes on every agent-state change.
  ///
  /// The returned signal is owned by this bus; it is disposed when
  /// the bus is disposed. Callers should NOT call `.dispose()` on it.
  ReadonlySignal<S> project<S>(StateProjection<S> projection) {
    return computed<S>(() => projection.project(_agentState.value));
  }

  /// Tear down. Idempotent. Disposes the underlying signal so any
  /// derived projections produced via [project] also stop firing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _agentState.dispose();
  }

  /// True after [dispose] has run. Visible for tests so they can
  /// assert post-tear-down behaviour.
  @visibleForTesting
  bool get isDisposed => _disposed;

  /// Defensive shallow copy so callers can't mutate the value held
  /// by the signal. JSON-Patch–style consumers expect "snapshot
  /// semantics" — every value seen via [agentState] is a frozen
  /// view of the state at that instant.
  static Map<String, dynamic> _freeze(Map<String, dynamic> map) =>
      Map<String, dynamic>.unmodifiable(map);
}
