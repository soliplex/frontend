# Reactor Extensions — M7–M10

Three `StatefulSessionExtension` reactors that prove the full three-way signal
contract, plus a generic debug panel that consumes `statefulObservations()`.

---

## Context

M1–M6 established the plumbing:

- `StatefulSessionExtension<T>` — lifecycle unit owning a `Signal<T>`
- `SessionCoordinator` — priority-ordered attach/dispose, `statefulObservations()`
- `ExecutionTrackerExtension` — first reactor (wire → signal → UI)
- `AgentUiDelegate` — callback-based HITL interface (replaced in M9)

Three signal-flow directions remain unproven:

| Direction | Pattern | Milestone |
| --- | --- | --- |
| Wire event → UI | ag-ui state surfaces as reactive signal | M7 |
| Tool call → UI | tool status drives live activity tiles | M8 |
| UI action → session | user approval unblocks agent run | M9 |
| All → debug panel | `statefulObservations()` generic renderer | M10 |

---

## M7 — `ConversationStateExtension`

**Direction:** wire event → UI (+ eliminate `stateOverlay` threading)

### What it fixes

`StateSnapshotEvent` and `StateDeltaEvent` arrive from the server on every run but
are silently dropped in `bridgeBaseEvent` (agent_session.dart:516–517). `StateUpdated`
ExecutionEvent exists but is never emitted. Meanwhile, document filter state is
manually threaded through four call-sites as `stateOverlay` on every send.

### Design

**7a. Emit `StateUpdated` from the bridge**

`packages/soliplex_agent/lib/src/runtime/agent_session.dart`

```dart
StateSnapshotEvent(:final snapshot) => StateUpdated(snapshot),
StateDeltaEvent(:final delta)       => StateUpdated(_applyDelta(current, delta)),
```

`_applyDelta` does a shallow merge. The current state is read from
`getExtension<ConversationStateExtension>()?.state ?? {}`.

**7b. `ConversationStateExtension`**

New file: `packages/soliplex_agent/lib/src/extensions/conversation_state_extension.dart`

```dart
class ConversationStateExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, dynamic>> {

  ConversationStateExtension() {
    setInitialState(const {});
  }

  @override String get namespace => 'conversation_state';
  @override int get priority => 20;       // attaches before ExecutionTracker
  @override List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {
    session.lastExecutionEvent.subscribe((event) {
      if (event is StateUpdated) state = event.aguiState;
    });
  }
}
```

**7c. Seed next run from extension state**

`ThreadViewState.sendMessage` currently passes `stateOverlay` through four layers.
After M7, `RunOrchestrator` reads initial state from the attached extension:

```dart
// AgentRuntime._buildSession / RunOrchestrator:
final seedState = coordinator.getExtension<ConversationStateExtension>()?.state;
```

`stateOverlay` parameter stays at the `sendMessage` boundary for explicit
UI overrides (document filter picker), but the default is now extension-derived.
This removes the threading through `RoomState` → `ThreadViewState` → `AgentSession`.

**7d. `StatePanel` widget**

New file: `lib/src/modules/room/ui/state_panel.dart`

Watches `ext.stateSignal`, renders the state dict as formatted JSON. Initially shown
in the Network Inspector / diagnostics area; promoted to a main panel in M10.

**Files touched:**

- `packages/soliplex_agent/lib/src/runtime/agent_session.dart`
- `packages/soliplex_agent/lib/src/extensions/conversation_state_extension.dart` (new)
- `packages/soliplex_agent/lib/src/orchestration/execution_event.dart` (emit site)
- `lib/src/modules/room/thread_view_state.dart` (trim stateOverlay threading)
- `lib/src/modules/room/ui/state_panel.dart` (new)
- `lib/src/flavors/standard.dart` (register extension)

---

## M8 — `ToolCallsExtension`

**Direction:** wire event → UI (tool call status drives activity tiles)

### What it fixes

Tool call status is currently scattered across `ExecutionTracker` steps and raw
`lastExecutionEvent` subscriptions in UI widgets. No single signal tracks
"which tools are currently active, which completed, which failed" for a given run.

### Design

**8a. `ToolCallSnapshot` value type**

New file: `packages/soliplex_agent/lib/src/extensions/tool_call_snapshot.dart`

```dart
enum ToolCallStatus { executing, completed, failed }

@immutable
class ToolCallSnapshot {
  const ToolCallSnapshot({
    required this.toolCallId,
    required this.toolName,
    required this.status,
    this.result,
  });
  final String toolCallId;
  final String toolName;
  final ToolCallStatus status;
  final String? result;
}
```

**8b. `ToolCallsExtension`**

New file: `packages/soliplex_agent/lib/src/extensions/tool_calls_extension.dart`

```dart
class ToolCallsExtension extends SessionExtension
    with StatefulSessionExtension<List<ToolCallSnapshot>> {

  ToolCallsExtension() {
    setInitialState(const []);
  }

  @override String get namespace => 'tool_calls';
  @override int get priority => 15;
  @override List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {
    session.lastExecutionEvent.subscribe((event) {
      state = _reduce(state, event);
    });
  }

  static List<ToolCallSnapshot> _reduce(
    List<ToolCallSnapshot> current,
    ExecutionEvent? event,
  ) => switch (event) {
    ClientToolExecuting(:final toolCallId, :final toolName) => [
        ...current,
        ToolCallSnapshot(
          toolCallId: toolCallId,
          toolName: toolName,
          status: ToolCallStatus.executing,
        ),
      ],
    ClientToolCompleted(:final toolCallId, :final result, :final status) => [
        for (final s in current)
          if (s.toolCallId == toolCallId)
            ToolCallSnapshot(
              toolCallId: toolCallId,
              toolName: s.toolName,
              status: status == ToolCallStatus.completed
                  ? ToolCallStatus.completed
                  : ToolCallStatus.failed,
              result: result,
            )
          else
            s,
      ],
    ServerToolCallStarted(:final toolCallId, :final toolName) => [
        ...current,
        ToolCallSnapshot(
          toolCallId: toolCallId,
          toolName: toolName,
          status: ToolCallStatus.executing,
        ),
      ],
    ServerToolCallCompleted(:final toolCallId, :final result) => [
        for (final s in current)
          if (s.toolCallId == toolCallId)
            ToolCallSnapshot(
              toolCallId: toolCallId,
              toolName: s.toolName,
              status: ToolCallStatus.completed,
              result: result,
            )
          else
            s,
      ],
    _ => current,
  };
}
```

**8c. Wire into ActivityLog / timeline**

`ThreadViewState` exposes `toolCallsSignal` via:

```dart
ReadonlySignal<List<ToolCallSnapshot>> get toolCalls =>
    _activeSession?.getExtension<ToolCallsExtension>()?.stateSignal
    ?? const Signal(const []).readonly();
```

Existing `ActivityLog` and `ExecutionTimeline` widgets watch this signal directly
instead of deriving status from raw execution events.

**Files touched:**

- `packages/soliplex_agent/lib/src/extensions/tool_call_snapshot.dart` (new)
- `packages/soliplex_agent/lib/src/extensions/tool_calls_extension.dart` (new)
- `lib/src/modules/room/thread_view_state.dart` (expose toolCalls signal)
- `lib/src/modules/room/ui/message_timeline.dart` (watch signal)
- `lib/src/flavors/standard.dart` (register extension)

---

## M9 — `HumanApprovalExtension`

**Direction:** UI action → session (replaces `AgentUiDelegate`)

### What it fixes

`AgentUiDelegate` is a callback interface — the agent run blocks on a `Future<bool>`
from an abstract method. This couples the approval mechanism to a single injected
object rather than making it a first-class reactive signal. There is no typed signal
that UI can watch for pending requests.

### Design

**9a. Remove `AgentUiDelegate`**

Delete: `packages/soliplex_agent/lib/src/runtime/agent_ui_delegate.dart`

Remove `_uiDelegate` field from `AgentSession`. Remove `uiDelegate` constructor
parameter from `AgentSession` and `AgentRuntime._buildSession`.

**9b. `ApprovalRequest` value type**

New file: `packages/soliplex_agent/lib/src/extensions/approval_request.dart`

```dart
@immutable
class ApprovalRequest {
  const ApprovalRequest({required this.toolName, required this.args});
  final String toolName;
  final Map<String, dynamic> args;
}
```

**9c. `HumanApprovalExtension`**

New file: `packages/soliplex_agent/lib/src/extensions/human_approval_extension.dart`

```dart
class HumanApprovalExtension extends SessionExtension
    with StatefulSessionExtension<ApprovalRequest?> {

  HumanApprovalExtension() {
    setInitialState(null);
  }

  @override String get namespace => 'human_approval';
  @override int get priority => 50;   // must attach before tools execute
  @override List<ClientTool> get tools => const [];

  Completer<bool>? _pending;

  // Called by AgentSession.requestApproval() instead of the delegate.
  Future<bool> requestApproval(String toolName, Map<String, dynamic> args) {
    _pending?.complete(false);  // cancel any stale request
    _pending = Completer<bool>();
    state = ApprovalRequest(toolName: toolName, args: args);
    return _pending!.future;
  }

  // Called by UI (approve/deny buttons).
  void respond(bool approved) {
    _pending?.complete(approved);
    _pending = null;
    state = null;
  }

  @override
  void onDispose() {
    _pending?.complete(false);
    _pending = null;
    super.onDispose();
  }
}
```

**9d. Update `AgentSession.requestApproval()`**

```dart
Future<bool> requestApproval({
  required String toolName,
  required Map<String, dynamic> args,
}) async {
  final ext = getExtension<HumanApprovalExtension>();
  if (ext == null) return false;   // no extension = auto-deny (safe default)
  emitEvent(AwaitingApproval(toolName: toolName, args: args));
  final approved = await ext.requestApproval(toolName, args);
  emitEvent(approved ? ApprovalGranted() : ApprovalDenied());
  return approved;
}
```

**9e. `ApprovalBanner` widget**

New file: `lib/src/modules/room/ui/approval_banner.dart`

Watches `ext.stateSignal`. When non-null, shows a dismissible banner with tool name,
args summary, and Approve / Deny buttons. On tap: `ext.respond(approved)`.

Positioned above the chat input in `room_screen.dart` so it's always visible
regardless of which thread is active.

**Migration note:** `AutoApproveUiDelegate` was only used in tests. Replace test
usages with `HumanApprovalExtension` configured to auto-approve via a
`_autoRespond` flag in a test subclass or by not registering the extension at all
(the `null` path auto-denies — tests that want auto-approve register the extension
and call `respond(true)` in a `Future.microtask`).

**Files touched:**

- `packages/soliplex_agent/lib/src/runtime/agent_ui_delegate.dart` (deleted)
- `packages/soliplex_agent/lib/src/runtime/agent_session.dart`
- `packages/soliplex_agent/lib/src/runtime/agent_runtime.dart`
- `packages/soliplex_agent/lib/src/extensions/approval_request.dart` (new)
- `packages/soliplex_agent/lib/src/extensions/human_approval_extension.dart` (new)
- `lib/src/modules/room/ui/approval_banner.dart` (new)
- `lib/src/modules/room/ui/room_screen.dart`
- `lib/src/flavors/standard.dart`
- Test files that use `AutoApproveUiDelegate`

---

## M10 — `ExtensionStatePanel` (statefulObservations debug panel)

**Direction:** all extensions → generic debug UI

### Design

`SessionCoordinator.statefulObservations()` already yields
`Iterable<(String namespace, ReadonlySignal<Object?>)>`. Nothing in the UI uses
it yet.

**10a. `ExtensionStatePanel` widget**

New file: `lib/src/modules/room/ui/extension_state_panel.dart`

```dart
class ExtensionStatePanel extends StatelessWidget {
  const ExtensionStatePanel({super.key, required this.session});
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final observations = session.statefulObservations().toList();
    if (observations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (namespace, signal) in observations)
          _ExtensionStateTile(namespace: namespace, signal: signal),
      ],
    );
  }
}

class _ExtensionStateTile extends StatelessWidget {
  const _ExtensionStateTile({required this.namespace, required this.signal});
  final String namespace;
  final ReadonlySignal<Object?> signal;

  @override
  Widget build(BuildContext context) {
    final value = signal.watch(context);
    return ExpansionTile(
      title: Text(namespace, style: Theme.of(context).textTheme.labelMedium),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
```

**10b. Wire into Network Inspector**

`DiagnosticsAppModule` exposes the inspector. Add an "Extensions" tab alongside
the existing HTTP request list. When a thread is active, passes
`_state.activeThreadView?.activeSession` to `ExtensionStatePanel`.

This gives developers a live view of every extension's signal state without any
coupling to concrete types — `conversation_state` shows the ag-ui dict,
`tool_calls` shows the list, `human_approval` shows the pending request or null,
`execution_tracker` shows the snapshot.

**Files touched:**

- `lib/src/modules/room/ui/extension_state_panel.dart` (new)
- `lib/src/modules/diagnostics/ui/` (add Extensions tab)
- `lib/src/modules/room/thread_view_state.dart` (expose `activeSession`)

---

## Delivery order

| Milestone | Depends on | Standalone value |
| --- | --- | --- |
| M7 `ConversationStateExtension` | M1–M2 (already merged) | Fixes dropped state events; enables state panel |
| M8 `ToolCallsExtension` | M1–M2 | Typed tool status signal for activity UI |
| M9 `HumanApprovalExtension` | M1–M2 | Replaces delegate; reactive HITL |
| M10 `ExtensionStatePanel` | M7–M9 | Debug panel showing all extension state |

M7 and M8 are independent and can ship in parallel branches.
M9 requires care around test migration (delegate removal).
M10 caps the set and should land after M7–M9 are all registered in `standard.dart`.

---

## What this is NOT

- No partial JSON accumulation for streaming tool args (deferred to a later milestone)
- No `statefulObservations()` type-narrowing / custom renderers per namespace
- No removal of `stateOverlay` parameter from public API (kept for explicit UI
  overrides; only the default threading is eliminated)
