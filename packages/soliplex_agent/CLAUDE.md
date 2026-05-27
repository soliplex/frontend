# soliplex_agent

Pure Dart agent orchestration for Soliplex AI runtime.

## Quick Reference

```bash
dart pub get
dart format . --set-exit-if-changed
dart analyze --fatal-infos
dart test
dart test --coverage
```

## Directory Structure

```text
lib/src/
  host/           # Platform callbacks (HostApi, PlatformConstraints)
  models/         # AgentResult, FailureReason, ThreadKey
  orchestration/  # RunOrchestrator, RunState, ErrorClassifier
  runtime/        # AgentRuntime, AgentSession, ServerConnection, ServerRegistry
  tools/          # ToolRegistry, ToolRegistryResolver
```

## Architecture

### Runtime (`src/runtime/`)

- `AgentRuntime` -- top-level facade; spawns and manages `AgentSession` instances
- `AgentSession` -- single autonomous interaction; automates the tool-execution loop
- `AgentSessionState` -- enum (spawning, running, completed, ...)

### Orchestration (`src/orchestration/`)

- `RunOrchestrator` -- drives one AG-UI run: SSE stream, event processing, tool yielding
- `RunState` -- sealed hierarchy: Idle, Running, ToolYielding, Completed, Failed, Cancelled
- `ErrorClassifier` -- maps exceptions to `FailureReason`

### Models (`src/models/`)

- `AgentResult` -- sealed: AgentSuccess, AgentFailure, AgentTimedOut
- `FailureReason` -- categorised failure enum
- `ThreadKey` -- typedef record `(serverId, roomId, threadId)`

### Host (`src/host/`)

- `HostApi` -- abstract platform callback interface
- `PlatformConstraints` -- abstract platform limits
- `NativePlatformConstraints` / `WebPlatformConstraints` -- concrete implementations
- `FakeHostApi` -- test double

### Tools (`src/tools/`)

- `ToolRegistry` -- immutable registry of tool definitions and executors
- `ToolRegistryResolver` -- typedef factory returning `ToolRegistry` per room

## Dependencies

- `soliplex_client` -- REST API, AG-UI client, domain models, and the
  AG-UI protocol types (events, tool definitions) re-exported from its
  barrel
- `soliplex_logging` -- structured logging
- `signals_core` -- reactive signals for session and run state
- `collection` -- collection utilities
- `meta` -- annotations

## Rules

- Follow KISS, YAGNI, SOLID
- No `// ignore:` directives
- Match surrounding code style
- Use `very_good_analysis` linting
- Pure Dart only -- no Flutter imports
- All types immutable where possible
