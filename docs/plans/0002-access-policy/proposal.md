# Proposal: Access Control + HITL for Monty Scripting Sessions

**Status:** Implemented (M1–M4), off by default
**Date:** 2026-04-18
**Branch:** `feat/access-policy-m1`
**PR:** runyaga/soliplex-frontend#14

## Context

The Monty scripting environment gives Python code running in a room session
access to host functions (Soliplex tools), the HTTP stack, and the local VFS.
Before this change there was no enforcement layer — any Python tool call reached
any host and any OS path. This proposal introduces one coherent `AccessPolicy`
model that governs all four enforcement surfaces.

## Design

### One model, four enforcement surfaces

```text
AccessPolicy
  ├── toolFilter   → PolicyEnforcementMiddleware   (bridge layer)
  ├── allowHosts   → HostFilteringHttpClient        (HTTP layer)
  ├── denyHosts    → HostFilteringHttpClient        (HTTP layer)
  ├── osFilter     → PolicyOsCallHandler            (VFS layer)
  └── hitlPolicy   → RoomUiDelegate + dialog        (UI layer)
```

Each surface enforces independently. A request is denied as early as possible:
host filtering fires before a TCP connection opens; tool filtering fires before
the bridge dispatches to a handler.

### Policy sources (priority order)

1. Room server config — `room.clientPolicy` (not yet wired server-side)
2. Flavor defaults — `AccessPolicy.permissive` (fail-open)
3. User runtime grants — `AllowSession` (additive, never restrictive)

### Fail-open default

`AccessPolicy.permissive` allows everything. Existing rooms without a
`clientPolicy` field continue to work unchanged. Server config tightens the
policy; the client never loosens below permissive without an explicit
server-side grant.

## Enforcement layers

### Tool filter (M1)

`PolicyEnforcementMiddleware` implements `BridgeMiddleware` and is registered
on each `MontyScriptEnvironment` via `env.registerMiddleware(...)`.

Every Python-initiated tool call passes through `handle()` before reaching the
handler. Infrastructure calls (`InfraCall`: `__restore_state__`,
`__persist_state__`) always bypass — they are internal bridge orchestration and
must never be gated.

`ToolFilter` matches by exact tool name or namespace prefix (first segment
before `_`): `soliplex_list_rooms` → namespace `soliplex`.

```text
allowedTools: null   → all allowed (fail-open)
allowedTools: [...]  → only listed tools allowed
deniedTools:  [...]  → applied after allowlist
```

### Host filter (M2)

`HostFilteringHttpClient` is the outermost HTTP decorator (above
`ConcurrencyLimitingHttpClient`). It checks `uri.host` synchronously in both
`request()` and `requestStream()` before delegating to the inner client.

Denied hosts never consume a concurrency slot and never open a TCP connection.
Throws `PolicyException` (a `SoliplexException`) on violation.

The decorator is always present in the stack (even when `enableAccessPolicy` is
false) because its policy is mutable — room config can tighten it at runtime
without rebuilding the client stack.

### OS/VFS filter (M3)

`PolicyOsCallHandler` wraps `OsCallHandler`. Denied operations throw
`OsCallPermissionError`, which the bridge translates to a Python
`PermissionError` — the LLM sees a structured error, not a crash.

`OsFilter.readOnly` denies: `Path.write_text`, `Path.write_bytes`,
`Path.mkdir`, `Path.unlink`, `Path.rmdir`, `Path.rename`.

### HITL — Human-in-the-Loop (M4)

When a tool in `HitlPolicy.requireApprovalForTools` (or matching a required
namespace) is called:

1. `PolicyEnforcementMiddleware` suspends the bridge call and invokes
   `onHitl(toolName, args)`.
2. `RoomUiDelegate` (an `AgentUiDelegate` implementation) shows
   `ToolApprovalDialog` via `GlobalKey<NavigatorState>`.
3. The user chooses:
   - **Allow once** — proceeds; prompts again on the next call.
   - **Allow for session** — proceeds; tool added to `_sessionApproved`; no
     further prompts this session.
   - **Deny** — `onDeny` callback cancels the `AgentSession`; Python receives
     no result (session is gone, not an error string the LLM can retry).
4. `ExecutionTracker` exposes `awaitingApprovalFor: ReadonlySignal<String?>`
   so the chat timeline can show inline status while approval is pending.

`get_clipboard` uses `context.requestApproval()` directly (not the middleware)
because it is a client tool, not a Python-called bridge function. On native
platforms no OS permission dialog exists, so HITL is the approval mechanism.
On web the browser provides its own OS clipboard permission dialog.

## Feature flag

```dart
Future<ShellConfig> standard({
  // ...
  bool enableAccessPolicy = false,
})
```

| What | `false` (default) | `true` |
| --- | --- | --- |
| `HostFilteringHttpClient` | In stack, permissive policy — no-op | In stack, tightened by room config |
| `PolicyEnforcementMiddleware` | Not registered | Registered per `MontyScriptEnvironment` |
| `RoomUiDelegate` | `null` — dialog never shown | Created, passed to `AgentRuntimeManager` |

The flag is a parameter on `standard()`. Flavor entry points opt in explicitly.
Off by default so existing deployments are unaffected.

## Namespace convention

Tool names are split on `_` to derive a namespace:

- `soliplex_list_rooms` → `soliplex`
- `notify_show` → `notify`
- `get_clipboard` → `get`
- `__restore_state__` → always `InfraCall`, never filtered

## Files

### New

| File | Purpose |
| --- | --- |
| `lib/src/modules/room/access_policy.dart` | `AccessPolicy`, `ToolFilter`, `OsFilter`, `HitlPolicy` |
| `lib/src/modules/room/policy_enforcement_middleware.dart` | Bridge middleware |
| `lib/src/modules/room/host_filtering_http_client.dart` | HTTP decorator |
| `lib/src/modules/room/policy_os_call_handler.dart` | VFS wrapper |
| `lib/src/modules/room/ui/tool_approval_dialog.dart` | Approval dialog |
| `lib/src/modules/auth/room_ui_delegate.dart` | `AgentUiDelegate` impl |
| `test/modules/room/access_policy_test.dart` | Model unit tests |
| `test/modules/room/policy_enforcement_middleware_test.dart` | Middleware tests |
| `test/modules/room/host_filtering_http_client_test.dart` | HTTP decorator tests |
| `test/modules/room/policy_os_call_handler_test.dart` | VFS wrapper tests |

### Modified

| Package | Change |
| --- | --- |
| `soliplex_agent` | `ApprovalResult` sealed class; `requestToolApproval()` returns `Future<ApprovalResult>` |
| `soliplex_client` | `ToolCallStatus.awaitingApproval`, `.denied`; `PolicyException` |
| `soliplex_monty_plugin` | `MontyScriptEnvironment.registerMiddleware()` |

## Backlog

- **`modules/security/` refactor** — `access_policy`, `host_filtering_http_client`,
  `policy_os_call_handler`, `policy_enforcement_middleware` live under
  `modules/room/` today. They are cross-cutting security concerns and should
  move to a dedicated `modules/security/` directory.
- **Server-side `room.clientPolicy`** — the client model is ready; the server
  field is not yet wired. Policy stays permissive until that lands.
- **MontyBridge/SoliplexBridge ordering** — layer ordering must be verified
  when `SoliplexBridge` is introduced above the current bridge stack.
- **Programmable policy (M5)** — `AccessPolicy` eventually accepts a Python
  snippet evaluated in a sandboxed sub-interpreter. Return values: `"allow"`,
  `"deny"`, `"hitl"`.
