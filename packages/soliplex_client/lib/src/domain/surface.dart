import 'package:meta/meta.dart';
import 'package:signals_core/signals_core.dart';

/// A long-lived UI surface driven by reactive state.
///
/// A [Surface] is the unifying abstraction for everything we render
/// from agent state — maps, narration logs, HUD overlays, sprites,
/// charts, future JS-bridged widgets. It owns:
///
/// - a stable [id] (so views can be looked up across mount cycles),
/// - a [state] signal of type [S] that views subscribe to,
/// - an [emit] write-back channel for surface-originated events
///   (drag, edit, click, etc.). Default is a no-op so non-interactive
///   surfaces (figlet, narration log) don't have to override.
///
/// Inputs to a Surface come from one of three places:
///
/// 1. Imperative mutators on the concrete controller class (today's
///    `narrate_say`, `map_add_marker`, `map_add_hud` etc.). These are
///    the bulk of v1 — the existing demo path.
/// 2. A [StateProjection] over agent state (AG-UI `StateSnapshotEvent`
///    / `StateDeltaEvent`). When a projection is registered the
///    surface's state is driven by the projection. This is the GenUI
///    direction — agents emit typed state, the projection turns it
///    into typed surface state, and views render.
/// 3. (Future) [emit] called by the view layer on user interaction;
///    the [SurfaceEvent] is fed back to the agent so it can update
///    its own state in response. Reserved for P6.
///
/// The contract intentionally leaves the lifecycle of the underlying
/// reactive primitive to the implementation. Some surfaces own a
/// `Signal<S>` directly; some derive `S` from a projection over the
/// agent-state bus; some merge both.
abstract class Surface<S> {
  /// Stable identity for this surface. Views look up surfaces by id
  /// across mount cycles; the id outlives any rendered widget.
  String get id;

  /// Reactive state the views subscribe to. Re-renders on every
  /// change.
  ReadonlySignal<S> get state;

  /// Push an event from the view layer back toward the agent.
  ///
  /// v1 default: no-op. Interactive surfaces (drag a marker, edit a
  /// JS-rendered widget) override this to enqueue a [SurfaceEvent]
  /// onto the StateBus's write-back channel. P6 wires the channel
  /// through to AG-UI.
  void emit(SurfaceEvent event) {}

  /// Tear down whatever the surface owns. Called when the host
  /// (room, thread, app shell) unmounts. Idempotent.
  void dispose();
}

/// Pure projection from raw agent state to a typed surface state.
///
/// Implementations must be **pure functions** — no side effects, no
/// captured mutable state — and **idempotent**, since the runtime may
/// re-run them on every state change (snapshot replacement or delta
/// application). The output is what the surface signal carries.
///
/// Example:
///
/// ```dart
/// class NarrationProjection extends StateProjection<List<Narration>> {
///   @override
///   List<Narration> project(Map<String, dynamic> agentState) {
///     final raw = agentState['ui']?['narrations'];
///     if (raw is! List) return const [];
///     return raw
///         .whereType<Map<String, dynamic>>()
///         .map(Narration.fromJson)
///         .toList(growable: false);
///   }
/// }
/// ```
// ignore: one_member_abstracts
abstract class StateProjection<S> {
  /// Const constructor so subclasses can be const-instantiated.
  const StateProjection();

  /// Compute surface state from raw agent state. Must be pure and
  /// idempotent.
  S project(Map<String, dynamic> agentState);
}

/// An event emitted by a surface back toward the agent.
///
/// Carried through [Surface.emit] → StateBus write-back queue →
/// (P6) AG-UI client→server message. v1 stores them locally so
/// future wire-up doesn't require contract changes.
@immutable
class SurfaceEvent {
  /// Construct an event tagged with a surface id and a kind.
  const SurfaceEvent({
    required this.surfaceId,
    required this.kind,
    this.data = const <String, dynamic>{},
  });

  /// The id of the surface that produced this event.
  final String surfaceId;

  /// Event category — `'click'`, `'edit'`, `'select'`, `'drag.end'`,
  /// or any custom string the surface and the agent agree on.
  final String kind;

  /// Free-form payload. Whatever the surface wants the agent to see.
  final Map<String, dynamic> data;

  /// Wire-format encoding for transports that carry plain JSON.
  Map<String, dynamic> toJson() => {
        'surfaceId': surfaceId,
        'kind': kind,
        'data': data,
      };
}
