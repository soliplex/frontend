# soliplex_agent

Pure Dart agent orchestration for Soliplex AI runtime.

## Quick Start

```bash
cd packages/soliplex_agent
dart pub get
dart test
dart format . --set-exit-if-changed
dart analyze --fatal-infos
```

## Architecture

### Runtime

- `AgentRuntime` -- top-level facade; spawns and manages `AgentSession` instances
- `AgentSession` -- single autonomous interaction; automates the tool-execution loop
- `AgentSessionState` -- enum representing the public lifecycle (spawning, running, completed, ...)

### Run (single-run state machine)

- `RunOrchestrator` -- drives one AG-UI run: starts the SSE stream, processes events, yields for tool calls
- `RunState` -- sealed hierarchy (Idle, Running, ToolYielding, Completed, Failed, Cancelled)
- `ErrorClassifier` -- maps low-level exceptions to `FailureReason`

### Models

- `AgentResult` -- sealed result (AgentSuccess, AgentFailure, AgentTimedOut)
- `FailureReason` -- categorised failure enum (network, timeout, cancelled, ...)
- `ThreadKey` -- typedef record `(serverId, roomId, threadId)` identifying a conversation

### Host

- `HostApi` -- abstract interface for platform callbacks (e.g. data-frame, chart)
- `PlatformConstraints` -- abstract interface describing platform limits
- `NativePlatformConstraints` / `WebPlatformConstraints` -- concrete implementations
- `FakeHostApi` -- test double

### Tools

- `ToolRegistryResolver` -- typedef for a factory function that returns a `ToolRegistry` per room

## Dependencies

- `soliplex_client` -- REST API, AG-UI client, domain models
- `soliplex_logging` -- structured logging
- `meta` -- annotations

## Example

```dart
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

Future<void> main() async {
  // 1. Build dependencies
  final api = SoliplexApi(/* ... */);
  final agUiClient = AgUiClient(/* ... */);
  final logger = LogManager.instance.getLogger('example');

  // 2. Create runtime
  final runtime = AgentRuntime(
    connection: ServerConnection(
      serverId: 'default',
      api: api,
      agUiStreamClient: agUiClient,
    ),
    toolRegistryResolver: (_) async => const ToolRegistry(),
    platform: const NativePlatformConstraints(),
    logger: logger,
  );

  // 3. Spawn a session and await the result
  final session = await runtime.spawn(
    roomId: 'plain',
    prompt: [const TextPart('Hello!')],
  );

  final result = await session.result;
  switch (result) {
    case AgentSuccess(:final output):
      print('Success: $output');
    case AgentFailure(:final reason):
      print('Failed: $reason');
    case AgentTimedOut():
      print('Timed out');
  }

  await runtime.dispose();
}
```

### Multi-turn conversations

To carry conversation history across turns, pass `cachedHistory` when
spawning subsequent sessions. The orchestrator prepends the cached messages
before the new user message in the AG-UI payload.

```dart
// Turn 1
final s1 = await runtime.spawn(
  roomId: 'chat',
  prompt: [const TextPart('Hi!')],
);
final r1 = await s1.result;

// Build history from the completed conversation
final history = ThreadHistory(
  messages: (s1.runState.value as CompletedState).conversation.messages,
);

// Turn 2 — carries forward turn 1 context
final s2 = await runtime.spawn(
  roomId: 'chat',
  prompt: [const TextPart('What did I just say?')],
  threadId: s1.threadKey.threadId,
  cachedHistory: history,
);
final r2 = await s2.result;
```

`ThreadHistory` is defined in `soliplex_client` and contains:

- `messages` -- prior `ChatMessage`s in chronological order
- `aguiState` -- AG-UI state (e.g. citation history) to restore
- `messageStates` -- per-message metadata (sources/citations)
