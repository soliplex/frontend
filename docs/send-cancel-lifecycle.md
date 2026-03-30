# Send and Cancel Message Lifecycle

How message sending and cancellation work across the room module.

## Core principle

**Only the cancel button cancels work.** Navigation, dispose, backgrounding,
closing the app — none of these cancel a session or spawn. They only stop
observing. The backend run completes independently, and the user sees results
when they return.

## Components

| Component | Role |
| --------- | ---- |
| `RoomState` | Coordinates room-level state. Owns the no-thread send path (`sendToNewThread`). |
| `ThreadViewState` | State for a single thread. Owns the existing-thread send path (`sendMessage`). |
| `RunRegistry` | Holds sessions across navigation. Keyed by `ThreadKey`. One per app. |
| `AgentRuntime` | Spawns sessions. Owns session lifetime and thread history cache. |
| `ChatInput` | UI widget. Shows send or cancel button based on `sessionState` signal. |

## State machine

Both `RoomState` and `ThreadViewState` track `_sessionState: Signal<AgentSessionState?>`:

```text
null (idle) ──→ spawning ──→ running ──→ null (terminal)
                  │                        ↑
                  └── cancel / error ──────┘
```

`_sessionState` serves three roles:

1. **Concurrency guard** — `sendMessage`/`sendToNewThread` reject if non-null.
2. **UI signal** — `ChatInput` watches it to show the cancel button.
3. **Error suppression** — if null in the catch block, the spawn was cancelled
   and the error is swallowed.

## Two send paths

### New thread (`RoomState.sendToNewThread`)

No thread exists. The spawn creates one server-side.

```text
1. Guard: sessionState != null → reject
2. Set sessionState = spawning
3. runtime.spawn(roomId, prompt)  [no threadId]
4. Track _pendingSpawn for cancel detection
5. await spawn
6. Staleness check: _pendingSpawn != spawnFuture → cancelled, return
7. Null _pendingSpawn and _sessionState
8. Register session in RunRegistry
9. Check _isDisposed → return if disposed
10. Create ThreadViewState, attach session, navigate
```

### Existing thread (`ThreadViewState.sendMessage`)

Thread exists. The spawn continues an existing conversation.

```text
1. Guard: sessionState != null → reject
2. Set sessionState = spawning
3. runtime.spawn(roomId, prompt, threadId)
4. Track _pendingSpawn for cancel detection
5. await spawn
6. Staleness check: _pendingSpawn != spawnFuture → cancelled, return
7. Null _pendingSpawn
8. Register session in RunRegistry  [before _isDisposed check]
9. Check _isDisposed → return if disposed
10. Attach session (sets sessionState = session.state, subscribes to runState)
```

## Cancel paths

### Cancel during spawn (`cancelRun` / `cancelSpawn`)

User clicks the cancel button while the spawn is awaiting.

```text
1. Null _pendingSpawn (triggers staleness check in sendMessage/sendToNewThread)
2. Null _sessionState (unblocks UI, suppresses error in catch)
3. Fire-and-forget: when spawn completes, cancel and dispose the session
```

The `sendMessage`/`sendToNewThread` method resumes from await, sees
`_pendingSpawn != spawnFuture`, and returns early. The session is never
registered in the registry.

### Cancel during active run (`cancelRun`)

User clicks the cancel button while a session is streaming.

```text
1. _pendingSpawn is null → falls through
2. _activeSession?.cancel()
3. Session transitions to CancelledState
4. _onRunState handles CancelledState → detach, apply conversation
```

## Dispose behavior

### `ThreadViewState.dispose` (navigate between threads)

```text
1. _isDisposed = true
2. Cancel history HTTP fetch (_cancelToken)
3. Detach from session (stop observing runState)
4. Dispose tracker registry
```

Does NOT cancel spawns or sessions. If a spawn was in progress, it completes
naturally:

- `_registry.register` runs (session enters registry).
- `_isDisposed` check prevents `_attachSession`.
- Session runs in the background. Registry holds it.
- User navigates back → new `ThreadViewState` → `_restoreFromRegistry` finds it.

### `RoomState.dispose` (leave room)

```text
1. _isDisposed = true
2. Cancel room metadata HTTP fetch
3. Dispose ThreadListState
4. Dispose active ThreadViewState
```

Does NOT cancel `sendToNewThread` spawn. If in progress, the spawn completes:

- Session is registered in RunRegistry.
- `_isDisposed` check prevents navigation/UI updates.
- Thread is created on the server.
- When user returns, the thread appears in the thread list.

### `RunRegistry.dispose` (app shutdown)

Cancels all active sessions and clears entries. Only called on app termination
from the flavor's `onDispose` callback.

## Scenarios

### Send on thread A, navigate to thread B mid-run

1. ThreadViewState(A) has active session SA.
2. User navigates to B → ThreadViewState(A) disposed (detaches from SA).
3. SA continues running in RunRegistry.
4. ThreadViewState(B) created, independent.
5. User navigates back to A → new ThreadViewState(A) → restores SA from registry.

### Send on thread A, navigate away mid-spawn

1. ThreadViewState(A) spawning.
2. User navigates → ThreadViewState(A) disposed. `_pendingSpawn` untouched.
3. Spawn completes → session registered in registry → `_isDisposed` → return.
4. User navigates back → restores from registry.

### Multiple concurrent runs

1. Send on A → session SA registered and running.
2. Navigate to B → ThreadViewState(A) detaches from SA (SA keeps running).
3. Send on B → session SB registered and running.
4. SA and SB both active in registry, independent.

### Send to new thread, navigate to lobby mid-spawn

1. `sendToNewThread` spawning.
2. User goes to lobby → RoomState disposed. Spawn continues.
3. Spawn completes → session registered → `_isDisposed` → return.
4. Thread created on server. When user returns to room, thread list shows it.

### Cancel mid-spawn

1. User sends, spawn is awaiting.
2. User clicks cancel → `_pendingSpawn` nulled, `_sessionState` nulled.
3. Spawn completes → staleness check returns early → session NOT registered.
4. Fire-and-forget cleans up the session.

### Cancel mid-run

1. Session is streaming.
2. User clicks cancel → `_activeSession.cancel()`.
3. Session transitions to `CancelledState`.
4. `_onRunState` handles it → detach, apply partial conversation.

### Spawn error concurrent with cancel

1. User clicks cancel → `_sessionState` set to null.
2. Spawn fails (network error).
3. Catch block: `_sessionState.value == null` → return (error suppressed).
4. User sees clean cancel, no error banner.

### App closed during run

1. Session is running on the server.
2. App process terminates. No cleanup runs.
3. Server completes the run independently.
4. App reopens → thread list fetched → user sees completed results.

## Known limitations

### Rapid navigation miss

If the user sends on thread A, navigates away (ThreadViewState disposed), and
navigates back before the spawn completes, the new ThreadViewState checks the
registry once on construction. At that point the session isn't registered yet.
When the spawn completes and registers, the new ThreadViewState doesn't know.

The user sees a static screen until they navigate away and back again (or
refresh). Making `RunRegistry` observable would fix this but is tracked as a
separate enhancement.
