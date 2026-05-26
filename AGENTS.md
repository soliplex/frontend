# AGENTS.md

Instructions for AI coding agents working with the Soliplex Flutter frontend.

## Project Overview

Soliplex Flutter frontend -- a runnable app and importable library built on a
modular shell architecture. Each feature module is a function returning a
`ModuleContribution` (routes, Riverpod overrides, optional redirect). Flavors
compose modules into a `ShellConfig` that boots the app via
`runSoliplexShell()`.

## Setup

```bash
flutter pub get
flutter run -d chrome --web-port 59001
```

## Build and Test

```bash
# Run all tests
flutter test --reporter failures-only

# Run a single test file
flutter test --reporter failures-only test/path_test.dart

# Run a single test by name
flutter test --reporter failures-only --name "test name"

# Lint (zero warnings required)
flutter analyze

# Format
dart format .

# Apply fixes
dart fix --apply

# Lint markdown (must pass)
markdownlint-cli2 "**/*.md" "#node_modules"

# Coverage report (app + all packages)
bash scripts/coverage.sh
```

After any implementation step, run format, analyze, and markdown lint before
presenting work for review.

## Modules

Five feature modules composed in the standard flavor (`lib/src/flavors/standard.dart`):

- **auth** (`lib/src/modules/auth/`) -- Multi-server OIDC authentication with
  token refresh, secure storage, consent notices, and platform-specific OAuth
  flows (native and web). Routes: `/`, `/servers`, `/auth/callback`.
- **lobby** (`lib/src/modules/lobby/`) -- Server and room discovery with
  responsive wide/narrow layouts, user profile display, and server sidebar.
  Route: `/lobby`.
- **room** (`lib/src/modules/room/`) -- Chat interface with thread management,
  agent session lifecycle (spawn, stream, cancel), file upload, RAG document
  filtering, source citations with chunk visualization, message feedback,
  execution step tracking with thinking blocks, and markdown rendering with
  syntax highlighting. Routes: `/room/:serverAlias/:roomId`,
  `/room/:serverAlias/:roomId/thread/:threadId`,
  `/room/:serverAlias/:roomId/info`.
- **quiz** (`lib/src/modules/quiz/`) -- Interactive quiz sessions with
  multiple-choice and free-text input, per-answer feedback with explanations,
  scoring, and retake support. Route:
  `/room/:serverAlias/:roomId/quiz/:quizId`.
- **diagnostics** (`lib/src/modules/diagnostics/`) -- Network inspector for
  HTTP request/response observation, event filtering by run, and SSE stream
  parsing. Route: `/diagnostics/network`.

## Architecture

- **Modules**: Functions taking dependencies via constructor injection,
  returning `ModuleContribution`. No base class, no registry.
- **Flavors**: Functions that compose module functions into `ShellConfig`.
  Add/remove a module by adding/removing a function call.
- **State management**: Riverpod for DI/service locator only. Reactive state
  via `signals` (from `soliplex_agent` package). No AsyncNotifier or
  FutureProvider chains.
- **Routing**: GoRouter assembled from module contributions. Route validation
  detects duplicate paths and parameterized shadowing. Module order determines
  redirect priority (first non-null wins).
- **Theming**: `ShellConfig` takes `ThemeData` directly. Design tokens
  (colors, spacing, radii, typography, breakpoints) live in the
  `soliplex_design` package (`packages/soliplex_design/lib/src/tokens/`).
  Material 3 with `SoliplexTheme` and `MarkdownThemeExtension` extensions.

## Workspace Packages

Five internal packages under `packages/`:

- `soliplex_agent` -- Agent orchestration: runtime lifecycle, session state
  machine (spawning, running, completed, failed, cancelled), tool registry
  with aliasing, execution events (text streaming, thinking, tool calls),
  parent-child session spawning, platform-aware concurrency limits.
- `soliplex_client` -- Backend HTTP/AG-UI API client: rooms, threads, runs,
  feedback, quizzes, documents. Domain models for conversations, messages,
  citations. AG-UI event processing with citation extraction. HTTP transport
  with token refresh, cancel tokens, and observable clients.
- `soliplex_client_native` -- Native HTTP client for iOS/macOS via
  cupertino_http. Stub on other platforms.
- `soliplex_design` -- Core design system: tokens (colors, spacing, radii,
  typography, breakpoints), theme factories, `SoliplexGlow`, and shared visual
  primitives. Depends only on `flutter`.
- `soliplex_logging` -- Structured logging with levels (trace through fatal),
  sinks (memory with circular buffer, console, disk queue, backend POST),
  distributed tracing support (spanId, traceId).

## Code Style

- Dart 3.6+, Flutter 3.27+
- Linting: `package:flutter_lints/flutter.yaml`
- Testing: `mocktail` for mocks, TDD approach
- Module pattern: each module in `lib/src/modules/<name>/`
- UI files in `ui/` subdirectory per module
- Tests mirror `lib/` structure under `test/`

## CI

GitHub Actions (`.github/workflows/flutter.yaml`) runs three jobs:

- **lint** -- dart format, flutter analyze, dart doc, markdown lint
- **test** -- App and package tests with random seed ordering. 80% coverage
  threshold enforced. Slack notification on failure.
- **build-web** -- Web release build with artifact upload.

## Pre-commit Hooks

Configured via `.pre-commit-config.yaml`:

- dart format, flutter analyze, markdownlint-cli2
- gitleaks (secret detection), no-commit-to-branch (main/master)
- check-merge-conflict, check-toml, check-yaml

## Platform Identifiers

All platforms use `ai.soliplex.client`. Do not change without discussion.

## Code Signing

iOS and macOS require `Local.xcconfig` for `DEVELOPMENT_TEAM`. Templates at
`{ios,macos}/Runner/Configs/Local.xcconfig.template`. These files are
gitignored. See `docs/developer-setup.md` for full setup.

## Key Documentation

- `docs/developer-setup.md` -- Platform-specific build instructions
- `docs/send-cancel-lifecycle.md` -- Message send/cancel state machine
- `docs/plans/0001-app-shell/proposal.md` -- Shell architecture design
- `docs/plans/citations-ui/` -- Citations feature design and data flow
