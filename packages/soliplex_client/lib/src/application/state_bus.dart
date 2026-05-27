import 'package:meta/meta.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_client/src/domain/surface.dart';

/// Callback invoked after every successful [StateBus] commit.
///
/// [tag] is the optional source label passed to [StateBus.setAgentState]
/// or [StateBus.update]; `null` when the writer did not provide one.
/// [snapshot] is the frozen post-commit agent-state map.
typedef BusObserver = void Function(
  String? tag,
  Map<String, dynamic> snapshot,
);

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
  final List<BusObserver> _observers = [];

  bool _disposed = false;

  /// Read-only feed of the current raw agent-state map.
  ///
  /// Identity changes on every replacement so listeners always fire,
  /// even when delta application produces structurally-equal maps.
  ReadonlySignal<Map<String, dynamic>> get agentState => _agentState.readonly();

  /// Register [observer] to be invoked after every successful commit.
  /// Returns a disposer that detaches [observer] when called.
  /// Adding an observer to a disposed bus is a no-op; the returned
  /// disposer is then a no-op too.
  void Function() addObserver(BusObserver observer) {
    if (_disposed) return () {};
    _observers.add(observer);
    return () => _observers.remove(observer);
  }

  /// Replace the entire agent-state map. Call when an AG-UI
  /// `StateSnapshotEvent` arrives. Pass [tag] to label the source of
  /// this write (e.g. `'agui.snapshot'`); observers receive the tag.
  void setAgentState(Map<String, dynamic> next, {String? tag}) {
    if (_disposed) return;
    final frozen = _freeze(next);
    _agentState.value = frozen;
    _notifyObservers(tag, frozen);
  }

  /// Replace via a transform applied to the current map. Convenient
  /// for delta-applying code that wants to compute the next state in
  /// one step:
  ///
  /// ```dart
  /// bus.update((current) => applyJsonPatch(current, deltaOps));
  /// ```
  ///
  /// Pass [tag] to label the source of this write; observers receive
  /// the tag.
  void update(
    Map<String, dynamic> Function(Map<String, dynamic> current) transform, {
    String? tag,
  }) {
    if (_disposed) return;
    final frozen = _freeze(transform(_agentState.value));
    _agentState.value = frozen;
    _notifyObservers(tag, frozen);
  }

  void _notifyObservers(String? tag, Map<String, dynamic> snapshot) {
    if (_observers.isEmpty) return;
    // Iterate over a snapshot so an observer detaching itself during
    // dispatch (e.g. via the returned disposer) does not skip siblings.
    for (final observer in List<BusObserver>.of(_observers)) {
      observer(tag, snapshot);
    }
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
    _observers.clear();
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
