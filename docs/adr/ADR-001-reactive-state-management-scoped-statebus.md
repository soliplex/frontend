# ADR-001: Reactive State Management via Scoped StateBus and Ownership-Based Discovery

- **Status:** Accepted
- **Date:** 2026-04-28
- **Authors:** Alan Runyan, William Karol Di Cioccio
- **Supersedes:** —
- **Superseded by:** —

---

## 1. Context and Problem Statement

### The surface proliferation problem

Soliplex streams structured agent state to the client as a live JSON document.
As GenUI surfaces multiply — maps, narration panels, HUDs, interactive
widgets — each surface needs a reactive, typed slice of that document. Without
a shared contract, each view independently subscribes to the raw AG-UI event
stream, re-parses the state, and manages its own lifecycle. The resulting
duplication is not merely redundant: it distributes the risk of subscription
leaks and mismatched parse logic across every surface implementor.

### The reactivity gap in the existing pipeline

`processEvent()` in `soliplex_client` already applies `StateSnapshotEvent`
(full replacement) and `StateDeltaEvent` (RFC 6902 JSON Patch) into
`Conversation.aguiState`. However, `Conversation.aguiState` was a plain
`Map<String, dynamic>` field — a value, not an observable. View layers had
no standard mechanism to watch it for changes. The only production read of
the field happened at run quiescence (citation extraction), which is a
pull-at-boundary pattern, not a reactive one.

Any surface that wanted live updates had to subscribe to `_runStateSignal`
directly, pattern-match the sealed `RunState` hierarchy, and extract
`aguiState` manually — per-variant boilerplate that each implementor wrote
differently.

### No per-thread bus slot, and a latent key-collision bug

Beyond the reactivity gap, the prior `_threadHistories: Map<String, ThreadHistory>`
cache in `AgentRuntime` had two problems:

1. **Wrong key type:** The cache was keyed by bare `threadId` (a `String`). In
   a multi-room runtime, two rooms could issue the same `threadId` and the
   entries would collide silently. Today `AgentRuntime` is per-server so the
   bug is masked, but the typing provided no enforcement.
2. **No slot for a per-thread bus:** The `StateBus` design requires a bus that
   survives session boundaries within a thread's lifetime. A plain
   `ThreadHistory` value had no field for it.

### Lifecycle management without RAII

Dart is a garbage-collected language with no deterministic destructors. There
is no language-level analogue to C++'s RAII or Swift's `deinit` that fires
the moment a scope exits. This creates a structural risk for reactive
systems: subscriptions and derived signals outlive their intended scope unless
explicitly torn down.

In a multi-surface, multi-thread application where buses are created and
destroyed as threads open and close, the two failure modes are symmetric:

- **Too early:** A surface reads a bus that has been disposed; it observes
  stale or empty state, or receives an exception on signal access.
- **Too late:** A bus that should have been disposed is retained by a
  lingering projection or subscriber; listeners continue to fire, and heap
  pressure accumulates silently.

Because the language provides no mechanistic guarantee, the design must
establish a contractual one.

---

## 2. Proposed Solution: The Reactive Chain

The solution is a three-layer reactive chain with clear ownership at each
level. Together the layers carry agent state from the server event stream
to a typed Flutter widget rebuild.

```mermaid
flowchart LR
    subgraph AGUI["AG-UI events (server → client) — peer event types"]
        Snap[StateSnapshotEvent]
        Delta[StateDeltaEvent]
        Act[ActivitySnapshot]
    end

    subgraph BUS["StateBus (per-thread, owned by AgentRuntime)"]
        AgentState[("agentState<br/>Signal of Map")]
    end

    subgraph EXISTING["Existing paths (unchanged)"]
        Conv["Conversation.activities<br/>+ ExecutionTracker"]
    end

    subgraph PROJ["Projections (typed views)"]
        P1[MarkersProjection]
        P2[NarrationProjection]
        P3[CustomProjection]
    end

    subgraph TGT["Surfaces (Surface of S impls)"]
        T1["MapExtension<br/>Surface of MapState"]
        T2["NarrationController<br/>Surface of List of Narration"]
        T3["Custom controller<br/>Surface of S"]
    end

    subgraph WID["Widgets (watch Surface.state)"]
        W1[MapView]
        W2[NarrationPanel]
        W3[Custom widget]
    end

    Runtime[AgentRuntime]

    Snap -- "setAgentState(...)" --> AgentState
    Delta -- "update(applyJsonPatch)" --> AgentState
    Act -- "consumed today" --> Conv

    AgentState -- "project(...)" --> P1
    AgentState -- "project(...)" --> P2
    AgentState -- "project(...)" --> P3

    P1 -- "forwards into Surface.state" --> T1
    P2 -- "forwards into Surface.state" --> T2
    P3 -- "forwards into Surface.state" --> T3

    T1 -- "watch Surface.state" --> W1
    T2 -- "watch Surface.state" --> W2
    T3 -- "watch Surface.state" --> W3

    W3 -. "Surface.emit(SurfaceEvent)" .-> AgentState
    AgentState -. "events stream" .-> Runtime
    Runtime -. "forward to agent" .-> Snap
```

### Layer 1 — Source: `_onStateChange` → `bus.setAgentState`

`AgentSession._onStateChange` is called on every `RunState` transition. It
extracts the `aguiState` map via an exhaustive switch over the sealed
`RunState` hierarchy and writes it into the per-thread bus:

```dart
void _onStateChange(RunState runState) {
  if (_disposed) return;
  _runStateSignal.value = runState;
  final next = _aguiStateOf(runState);
  if (next != null) {
    bus.setAgentState(next);
  }
  // ... session-state bookkeeping
}

static Map<String, dynamic>? _aguiStateOf(RunState state) =>
    switch (state) {
      IdleState()                             => null,
      RunningState(:final conversation)       => conversation.aguiState,
      ToolYieldingState(:final conversation)  => conversation.aguiState,
      CompletedState(:final conversation)     => conversation.aguiState,
      FailedState(:final conversation)        => conversation?.aguiState,
      CancelledState(:final conversation)     => conversation?.aguiState,
    };
```

The switch is exhaustive over the sealed `RunState` hierarchy. Adding a new
variant forces a compile error here, so the bus-write path stays correct as
the state machine evolves — correctness is structural, not documentary.

`AgentSession.agentState` is a direct alias for `bus.agentState`:

```dart
late final ReadonlySignal<Map<String, dynamic>> agentState = bus.agentState;
```

This gives widgets a stable per-session signal handle while ensuring they
see the exact same data as any `bus.project(...)` consumer.

```mermaid
flowchart LR
    Snap["StateSnapshotEvent / StateDeltaEvent"]
    Proc["processEvent()"]
    Conv["Conversation.aguiState"]
    Run["_runStateSignal"]
    OnChange["_onStateChange"]
    Bus[("bus.agentState<br/>signal of Map")]
    AgentState[".agentState getter<br/>= bus.agentState"]
    Watch["widget.watch(...)"]
    Project["bus.project(...)"]

    Snap --> Proc --> Conv --> Run --> OnChange
    OnChange -- "bus.setAgentState(next)" --> Bus
    Bus --> AgentState
    AgentState --> Watch
    Bus --> Project
```

### Layer 2 — Transport: `StateBus` owned by `ThreadState`

`StateBus` is a scope-agnostic reactive document with four operations:

| Operation | Purpose |
| --------- | ------- |
| `setAgentState(map)` | Full snapshot replacement |
| `update(fn)` | Delta application (JSON Patch) |
| `project<S>(projection)` | Derive a typed `ReadonlySignal<S>` |
| `emit(event)` | Write-back path (surface → agent) |

Two invariants are enforced internally:

- **Snapshot semantics on read:** `agentState`'s value is always
  `Map.unmodifiable(...)`. Callers cannot mutate what they read, preventing
  aliasing bugs across projections.
- **Identity change on every replacement:** Even structurally equal maps
  produce a new wrapping identity, so `Signal` listeners always fire.
  Equality optimisation is explicitly out of scope; correctness is preferred
  over efficiency until profiling proves otherwise.

Each bus lives inside a `ThreadState`, which is owned by `AgentRuntime`:

```mermaid
flowchart LR
    subgraph CALLERS["External callers"]
        UI["UI 'new thread' button"]
        History["Thread history fetch"]
        Session["spawn() / _captureThreadHistory()"]
    end

    subgraph RUNTIME["AgentRuntime"]
        States[("_threadStates<br/>Map of ThreadKey to ThreadState")]
        Seed["seedThreadState(key, ...)<br/>seedThreadHistory(key, ...)"]
    end

    subgraph TS["ThreadState (per thread)"]
        Bus["StateBus bus<br/>(survives session boundary)"]
        Hist["ThreadHistory? history<br/>(messages + aguiState)"]
    end

    UI -- "seedThreadState(key, agui)" --> Seed
    History -- "seedThreadHistory(key, hist)" --> Seed
    Session -- "_threadStates[key]?.history" --> States
    Session -. "captureThreadHistory" .-> States

    Seed --> States
    States --> Bus
    States --> Hist
```

`AgentSession` accesses its thread's bus through a plain (non-cached) getter:

```dart
StateBus get bus => _runtime.ensureThreadState(threadKey).bus;
```

Late-evaluated — a session that never reads `bus` never causes a `StateBus`
to be allocated.

### Layer 3 — Consumption: `StateProjection<S>`

```dart
abstract class StateProjection<S> {
  S project(Map<String, dynamic> agentState);
}
```

A pure, idempotent transform. Projections must be tolerant: malformed or
partial state (common during streaming) must produce a sensible empty or null
value, never throw. The bus owns derived signals returned by `project<S>`;
callers must not dispose them manually.

---

## 3. Key Design Decisions

### 3.1 `ThreadKey` over bare `threadId`

```dart
// Before — bare String key
final Map<String, ThreadHistory> _threadHistories = {};

// After — full record key
final Map<ThreadKey, ThreadState> _threadStates = {};
```

`ThreadKey` is the existing typedef record
`(String serverId, String roomId, String threadId)`. Dart's record
value-equality makes it a valid `Map` key out of the box. This closes the
latent multi-room collision bug (two rooms issuing the same `threadId` no
longer collide) and provides a future-safe foundation for multi-server and
multi-room runtimes.

### 3.2 `@immutable ThreadState` with a mutable `bus`

```dart
@immutable
class ThreadState {
  ThreadState({StateBus? bus, this.history}) : bus = bus ?? StateBus();

  final StateBus bus;
  final ThreadHistory? history;

  ThreadState withHistory(ThreadHistory? next) =>
      ThreadState(bus: bus, history: next);

  void dispose() => bus.dispose();
}
```

The container is value-typed; the bus inside it is mutable. `withHistory`
returns a new container with updated history while **preserving the same
`bus` instance**. This is a load-bearing invariant: any code path that
constructed a fresh `ThreadState` for an existing key would silently destroy
all live signal subscriptions. The `@immutable` annotation and
`withHistory` pattern make the safe update path the only obvious one.

### 3.3 `ensureThreadState` vs `threadStateOf`

Two public accessors with deliberately separated semantics:

| Accessor | Semantics | Caller |
| -------- | --------- | ------ |
| `ensureThreadState(key)` | Create-on-demand; never returns null | `AgentSession.bus` |
| `threadStateOf(key)` | Read-only; returns null if unregistered | External consumers |

`threadStateOf` returning null is the liveness check — it means the thread
has not been registered or has been disposed. Callers must treat that as a
terminal condition.

### 3.4 No global registry

`StateBus` has no `all` static list, no `BusRegistry`, and no app-wide
observable of active buses. This was a deliberate rejection, not an
oversight.

A global registry introduces two failure modes that are difficult to reason
about in a GC language:

- **Lifetime coupling:** A registry must either retain disposed buses (memory
  leak) or require each bus to deregister on disposal (cross-ownership cleanup
  that races against the owning scope's teardown).
- **Implicit dependency surface:** A `BusRegistry.all` observable invites
  consumers to subscribe to "every bus, any change" — a dependency that is
  invisible in the type system and impossible to trace statically.

Debug introspection — the only legitimate use case for a flat list — is a
separate concern. A diagnostic tool that walks ownership at a point in time is
the correct solution; it should not be a runtime cost paid by every bus in
production.

### 3.5 Ownership-based discovery

Discovery follows ownership. The rule is:

> To find a bus, walk to its owner. To find a thread's bus, call
> `runtime.threadStateOf(key)?.bus`. Do not search; navigate.

This policy is the contractual substitute for RAII. Because Dart cannot
enforce "the bus dies when its owner dies" at the language level, the design
makes ownership explicit and observable:

| Bus scope | Owner | Discovery path |
| --------- | ----- | -------------- |
| App | Shell | `shell.appBus` |
| Server | `AgentRuntime` | `runtime.serverBus[serverId]` |
| Room | Per-room view state | `runtime.roomStateOf(key)?.bus` |
| Thread | `AgentRuntime` via `ThreadState` | `runtime.threadStateOf(key)?.bus` |

Code that holds a `StateBus` reference obtained via a direct constructor call
— rather than via ownership navigation — is in violation of this policy and
should be treated as a defect in review.

### 3.6 Runtime-owned disposal cascade

`AgentRuntime.dispose()` is the single trigger for the full cleanup cascade:

```dart
for (final state in _threadStates.values) {
  state.dispose(); // → bus.dispose()
}
_threadStates.clear();
```

`bus.dispose()` is idempotent. No surface, projection, or widget should call
it directly. The invariant: **the entity that constructed the bus is the
entity that disposes it** — and that entity is always `AgentRuntime`.

### 3.7 Exhaustive state mapping

The `_aguiStateOf` switch in `AgentSession._onStateChange` is over a sealed
class. Adding a new `RunState` variant forces a compile error here, ensuring
the bus-write path handles every variant. Correctness is enforced
structurally, not by convention.

---

## 4. Consequences and Caveats

### 4.1 Lifecycle is runtime-owned

The bus lifecycle is not managed by an abstract "host" — it is fully owned
by `AgentRuntime` through the `ThreadState` container. No caller outside
the runtime is responsible for bus disposal.

```mermaid
sequenceDiagram
    participant Runtime as AgentRuntime
    participant TS as ThreadState
    participant Bus as StateBus
    participant Session as AgentSession
    participant Surf as Surface / Widget

    Runtime->>TS: new ThreadState() [via seedThreadState or ensureThreadState]
    TS->>Bus: new StateBus()

    Note over Runtime,Bus: thread becomes active
    Runtime->>Session: spawn(key, ...)
    Session->>Bus: bus.setAgentState(next) [via _onStateChange]
    Bus-->>Surf: signal updates, widget rebuilds

    Note over Surf: user interacts
    Surf->>Bus: emit(SurfaceEvent)
    Bus-->>Runtime: events stream
    Runtime->>Runtime: forward to agent

    Note over Runtime,Bus: runtime tears down
    Runtime->>TS: state.dispose()
    TS->>Bus: bus.dispose()
    Bus-->>Surf: derived signals stop firing
```

The contract reduces to: **do not call `bus.dispose()` from session,
surface, projection, or widget code.**

### 4.2 `agentState` is bound once; `bus` resolves on every access

`agentState` is `late final` — bound to `bus.agentState` on first access
and never re-evaluated. `bus` is a plain getter — it resolves through
`_runtime.ensureThreadState(threadKey).bus` on every call.

In production this is safe because `ThreadState.withHistory` always preserves
the same `bus` instance — the runtime never replaces a `ThreadState` with a
fresh one for an existing key. But the safety is contractual, not mechanical.
A future code path that constructed a new `ThreadState` for an existing key
would silently strand `agentState` on a disposed bus while `_onStateChange`
writes into the new one, with no compile-time or runtime error at the point
of the mistake.

### 4.3 Cross-scope projection composition (opt-in risk)

The architecture explicitly supports projections that compose state from
multiple buses at different scopes (e.g., a summary widget that reads the
server-bus thread list and the active thread-bus's last message). This
capability is opt-in and carries a non-trivial risk:

- Each composed bus has an independent owner and lifetime. A projection that
  holds references to two buses may observe one disposed and one active.
- Projections must defensively handle the case where a composed bus has been
  disposed. The `null`-returning pattern for missing state is the correct
  model.

Cross-scope composition bypasses the standard isolation boundary. Treat it as
an advanced capability requiring explicit justification in code review.

### 4.4 Stale references without RAII

Because Dart provides no deterministic destruction, there is no language
guarantee that a `StateBus` reference becomes unreachable the moment its owner
is torn down. Code that obtains a bus reference through a mechanism other than
ownership navigation (e.g., captured in a closure, stored in a widget's
`State`) must verify liveness before use:

```dart
// Prefer: navigate ownership each time
final bus = runtime.threadStateOf(key)?.bus;
if (bus == null) return; // owner gone

// Avoid: long-lived capture of a bus reference
final _bus = widget.bus; // may be disposed when widget rebuilds
```

The `?.bus` navigation pattern is not merely ergonomic — it is the liveness
check. A null return from ownership navigation means the thread has been
torn down; callers must treat that as a terminal condition, not a transient
error.

---

## 5. Alternatives Considered

### 5.1 Global event bus

A single app-wide `StreamController<AgentStateEvent>` that all surfaces
subscribe to. Rejected because:

- Lifetime is unbounded — subscribers from a closed thread continue to
  receive events from all other threads until manually unsubscribed.
- The event stream carries no scope identity by default, requiring every
  subscriber to filter by thread key — a filtering step each implementor
  would write differently.
- Disposal becomes a coordination problem: who closes the stream, and when?

### 5.2 Central bus registry (`StateBus.all`)

A static `Map<ScopeKey, StateBus>` maintained by the framework. Rejected
for the reasons in §3.4: lifetime coupling and implicit dependency surface.
The registry either leaks disposed buses or requires cross-ownership cleanup
that races. Neither failure mode is acceptable in a multi-thread UI.

### 5.3 Riverpod `AsyncNotifier` / `FutureProvider` chains

Riverpod is used in this codebase as a DI/service locator only — no
`AsyncNotifier` or `FutureProvider` chains. Extending Riverpod to own reactive
state would blur the architectural boundary between DI and reactivity, and
would couple the state layer to Riverpod's invalidation semantics, which are
designed for async data fetching rather than streaming patch application.
`signals` is the chosen reactivity primitive; `StateBus` is its
domain-specific wrapper.

### 5.4 `ChangeNotifier` / `ValueNotifier`

Flutter's built-in notifiers are listener-list based and have no notion of
derived signals or projection composition. They also leak if `removeListener`
is not called, which replicates the exact problem the ownership policy is
designed to prevent. Rejected in favour of the `signals` package, whose
computed-signal model supports projection composition natively.

---

## 6. Summary

| Property | Decision |
| -------- | -------- |
| Reactivity primitive | `signals` computed signal |
| State write path | `AgentSession._onStateChange` → `_aguiStateOf` → `bus.setAgentState` |
| Per-session read path | `session.agentState` = `bus.agentState` (direct alias, `late final`) |
| Transport | `StateBus` (per-thread, owned by `ThreadState`) |
| Container | `@immutable ThreadState` — value-typed wrapper, mutable bus inside |
| Bus owner | `AgentRuntime` via `_threadStates: Map<ThreadKey, ThreadState>` |
| Map key | `ThreadKey` record `(serverId, roomId, threadId)` — value-equality safe |
| Projection | `StateProjection<S>` (pure, tolerant, idempotent) |
| Discovery policy | Ownership navigation; `runtime.threadStateOf(key)?.bus` |
| Disposal contract | `AgentRuntime.dispose()` cascades → `ThreadState.dispose()` → `bus.dispose()` |
| State correctness guarantee | Exhaustive sealed-class switch in `_aguiStateOf` feeds bus on every transition |
| Cross-scope composition | Opt-in; caller accepts dual-lifetime risk |
| RAII substitute | Ownership-based discovery + `@immutable ThreadState.withHistory` invariant |
