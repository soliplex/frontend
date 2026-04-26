# `AgentSession.agentState` — reactive view of agent state

A read-only signal on `AgentSession` that exposes the most recent
`Conversation.aguiState` map, updated reactively on every run-state
transition.

```dart
/// Reactive view of the current agent-state map. Derived from
/// `_runStateSignal`; updates on every RunState change. Empty map
/// when the session is idle or in a terminal state with no captured
/// conversation.
ReadonlySignal<Map<String, dynamic>> get agentState;
```

## What problem this solves

`processEvent()` in `soliplex_client` already applies AG-UI's
`StateSnapshotEvent` and `StateDeltaEvent` (RFC 6902 patches) into
`Conversation.aguiState`. But `Conversation.aguiState` was a plain
`Map<String, dynamic>` field — view layers couldn't watch it for
changes. The only existing read happened at run quiescence (citation
extraction).

This commit closes the gap: `AgentSession.agentState` is a
`ReadonlySignal<Map<String, dynamic>>` that fires on every run-state
change. Widgets can now `.watch` it, or pass it into the new
`StateBus` via `bus.setAgentState(session.agentState.value)` from a
host listener.

## Audit before this commit

There was no existing reactive exposure of `aguiState` anywhere:

- `agui_event_processor.dart` mutates `aguiState` but emits no signal.
- `Conversation` is immutable but plain — no signal layer.
- `RunState` variants carry the conversation by value; they're
  emitted on `_runStateSignal` but consumers had to write
  per-variant boilerplate to extract `aguiState`.

This commit centralizes that boilerplate behind one signal.

## How it's wired

```dart
late final ReadonlySignal<Map<String, dynamic>> agentState = computed(
  () => _aguiStateOf(_runStateSignal.value) ?? const {},
);

static Map<String, dynamic>? _aguiStateOf(RunState state) =>
    switch (state) {
      RunningState(:final conversation) => conversation.aguiState,
      ToolYieldingState(:final conversation) => conversation.aguiState,
      CompletedState(:final conversation) => conversation.aguiState,
      FailedState(:final conversation) => conversation?.aguiState,
      CancelledState(:final conversation) => conversation?.aguiState,
      IdleState() => null,
    };
```

Behavior:

- **Idle** → empty map.
- **Running / ToolYielding / Completed** → the conversation's current
  `aguiState`.
- **Failed / Cancelled with conversation captured** → that conversation's
  `aguiState`.
- **Failed / Cancelled with `conversation == null`** → empty map.

The switch is exhaustive over the sealed `RunState` hierarchy; adding
a new variant forces a compile error here, ensuring the signal stays
correct as the state machine evolves.

## How a host uses it

Today's path (until follow-up PRs add per-thread `StateBus`
ownership):

```dart
final session = await runtime.spawn(...);

// Watch reactively in a Flutter widget:
final stateMap = session.agentState.watch(context);

// Or feed into a StateBus the host owns:
session.agentState.subscribe((next) {
  bus.setAgentState(next);
});
```

The follow-up redesign moves bus ownership onto a per-thread
`ThreadState` so the manual subscription becomes implicit. This PR
just exposes the signal — the wiring is the consumer's responsibility
for now.

## What this PR ships

- `agentState` getter on `AgentSession` (~30 LOC including the
  exhaustive switch and doc comment).
- 3 new tests in `agent_session_signal_test.dart`:
  - Idle state → empty map.
  - StateSnapshotEvent → full replacement.
  - StateDeltaEvent → RFC 6902 patch applied.
- Plus signal-disposal coverage merged into the existing
  signal-disposal group.

13/13 tests pass in the file. Existing tests unaffected.

## What this PR explicitly does NOT ship

- No `StateBus` integration. That's a follow-up — the host (typically
  a per-thread view) decides when to push `session.agentState`'s
  values into a bus it owns.
- No bus-write path inside `RunOrchestrator`. AG-UI events still
  feed `Conversation.aguiState` exactly as before; this signal just
  exposes the result reactively.
- No deletion or refactoring of `Conversation.aguiState`. The field
  remains the source of truth; this signal is a read view of it.

## Stack position

Base: `feat/genui-state-bus-types` (the `StateBus` / `Surface` /
`StateProjection` foundation PR). Depends on that PR's
`soliplex_client` types being available.

Plan reference: this is GenUI P1 in the foundation series. Follow-up
foundation PRs will introduce per-thread `StateBus` ownership on
`AgentRuntime` and route AG-UI state events through the bus directly.
