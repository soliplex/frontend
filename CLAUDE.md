# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Soliplex Flutter frontend — both a **runnable app** and an **importable library**. Uses a modular shell architecture where each module is an `AppModule` subclass that contributes routes, Riverpod overrides, and lifecycle hooks.

## Commands

Prefer Dart MCP tools over shell commands. All tools take `root` as `file:///absolute/path/to/project`.

| Task | MCP tool | Shell fallback |
| ---- | -------- | -------------- |
| Dependencies | `mcp__dart__pub` (command: `get`) | `flutter pub get` |
| Lint (must pass with zero warnings) | `mcp__dart__analyze_files` | `flutter analyze` |
| Run all tests | `mcp__dart__run_tests` with `testRunnerArgs.reporter: "failures-only"` | `flutter test --reporter failures-only` |
| Run a single test file | `mcp__dart__run_tests` with `paths`, `testRunnerArgs.reporter: "failures-only"` | `flutter test --reporter failures-only test/path.dart` |
| Run a single test by name | `mcp__dart__run_tests` with `testRunnerArgs.name`, `testRunnerArgs.reporter: "failures-only"` | `flutter test --reporter failures-only --name "test name"` |
| Run the app | `mcp__dart__launch_app` with `device` | `flutter run -d macos` |
| Check for outdated deps | `mcp__dart__pub` (command: `outdated`) | `flutter pub outdated` |
| Format code | `mcp__dart__dart_format` | `dart format .` |
| Apply fixes | `mcp__dart__dart_fix` | `dart fix --apply` |
| Lint markdown (must pass) | — | `markdownlint-cli2 "**/*.md" "#node_modules"` |

**Markdown lint is mandatory.** Always run the markdown linter after creating or editing any `.md` file. All diagnostics must be resolved before work is considered complete.

**After finishing any implementation step**, always run `mcp__dart__dart_format`, `mcp__dart__analyze_files` (zero warnings required), and markdown lint (if `.md` files were touched) before presenting work for review.

## Architecture

### Module System

Entry point: `runSoliplexShell(ShellConfig)` boots the app from a `ShellConfig`.

Each module subclasses `AppModule` and implements:

- `String get namespace` — unique identifier (validated at startup)
- `ModuleRoutes build()` — returns routes, Riverpod overrides, and an optional
  redirect
- `Future<void> onDispose()` — resource cleanup (optional)

Flavor functions construct concrete `AppModule` instances and pass them to
`ShellConfig.fromModules(...)`. Modules are built in registration order and
disposed in reverse. The shell flattens routes and collects overrides into a
single root `ProviderScope`.

### State Management

Riverpod is **DI/service locator only** — no AsyncNotifier or FutureProvider chains.
Reactive state comes from `signals` (via `soliplex_agent`). The `signals` package
bridges signal reactivity to Flutter widget rebuilds.

### Theming

`ShellConfig` takes `ThemeData` directly — Flutter's standard abstraction. Each flavor
provides its own `ThemeData`. Custom palette abstractions deferred until multiple
flavors need them.

### Flavors

Flavors are functions that construct `AppModule` instances and call
`ShellConfig.fromModules(...)`. Modules are included/excluded by presence in the
flavor — no enum or toggle framework.

### Adding custom client-side session extensions

`standard()` takes an optional `extraExtensions: SessionExtensionFactory?`
parameter. The factory is invoked once per `AgentSession` and its output is
appended after the framework's built-in extensions (execution tracker, tool
calls, human approval). Use this to register custom `SessionExtension`s —
including ones that expose `ClientTool`s — without forking the flavor.

Example — a consumer adding a `get_current_time` tool:

```dart
class ClockExtension extends SessionExtension {
  @override
  String get namespace => 'clock';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void onDispose() {}

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'get_current_time',
          description: 'Returns the current device time as ISO 8601.',
          executor: (_, __) async => DateTime.now().toIso8601String(),
        ),
      ];
}

// In main.dart:
runSoliplexShell(
  await standard(
    extraExtensions: () async => [ClockExtension()],
  ),
);
```

The framework's own `main.dart` uses the same hook to gate the on-device
Python runtime (`MontyRuntimeExtension` from `soliplex_agent_monty`) behind
the compile-time `MONTY_ENABLED` flag:

```sh
flutter build macos --dart-define=MONTY_ENABLED=true
```

The flag is a tree-shake boundary — with `MONTY_ENABLED=false` (default)
the `dart_monty` bytes do not reach the release binary.

## Modules

Five feature modules composed in the standard flavor:

- **auth** — Multi-server OIDC authentication, token refresh, secure storage
- **lobby** — Server/room discovery with responsive layout
- **room** — Chat interface, threads, agent execution, file upload, citations, document filtering, feedback
- **quiz** — Interactive quizzes with multiple-choice and free-text input
- **diagnostics** — Network inspector for HTTP request/response debugging

## Workspace Packages

Internal packages under `packages/`:

- `soliplex_agent` — Agent orchestration (runtime, sessions, tool registry, execution events)
- `soliplex_agent_monty` — Bridge that wraps `dart_monty`'s Python sandbox in a `SessionExtension` and exposes the `run_python_on_device` `ClientTool`. Optional; enabled via `--dart-define=MONTY_ENABLED=true`.
- `soliplex_client` — Backend HTTP/AG-UI API client, domain models, citation extraction
- `soliplex_client_native` — Native HTTP client (iOS/macOS via cupertino_http)
- `soliplex_logging` — Structured logging with memory, console, disk, and backend sinks

## CI

GitHub Actions runs lint, test, and web build. Tests require 80% coverage. See `.github/workflows/flutter.yaml`.

## Platform Identifiers

All platforms use `ai.soliplex.client` — this replaces the existing production app. Do not change these identifiers without discussion.

## Code Signing

iOS and macOS use gitignored `Local.xcconfig` files for `DEVELOPMENT_TEAM`. Templates at `{ios,macos}/Runner/Configs/Local.xcconfig.template`. See `docs/developer-setup.md`.
