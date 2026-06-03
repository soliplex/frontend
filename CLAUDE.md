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

`signals_flutter` offers two ways to subscribe a widget to a signal. They are not
interchangeable — pick by rebuild scope:

- **`signal.watch(context)`** — extension method. Subscribes the calling element;
  the whole widget's `build()` re-runs on every change. Use at the top of a
  screen-level `build()` when most of the tree depends on the signal anyway.
  Auto-unsubscribes when the element is unmounted.
- **`Watch((context) => ...)`** — wrapper widget. Subscribes only the closure's
  subtree. Use for surgical reactivity inside an otherwise-static widget (e.g.,
  a spinner inside a list tile). Auto-unsubscribes deterministically on
  element unmount. Prefer this when most of the surrounding widget does not
  depend on the signal.

Mental model: `Watch` is to signals what `StreamBuilder` is to streams.

### Theming

`ShellConfig` takes `ThemeData` directly — Flutter's standard abstraction. Each flavor
provides its own `ThemeData`. Custom palette abstractions deferred until multiple
flavors need them. The brand tokens that build those `ThemeData` instances live in
`lib/src/design/` — see the **Design system** section below before writing UI code.

### Flavors

Flavors are functions that construct `AppModule` instances and call
`ShellConfig.fromModules(...)`. Modules are included/excluded by presence in the
flavor — no enum or toggle framework.

## Design system

The design system is the **single source of truth** for color, type, spacing,
radii, and breakpoints. It lives in `lib/src/design/` (production code) and is
documented in `lib/src/design/README.md` and the canonical reference bundle at
`design_system/` (tokens, swatches, type specimens, component demos). **Read
`lib/src/design/README.md` before writing or modifying any widget code** — it
has the full accessor cheat sheet.

### Hard rules — do not violate without explicit user approval

1. **No hex color literals** (`Color(0x...)`, `Color.fromARGB`, `Color.fromRGBO`)
   outside `lib/src/design/`. Use
   `Theme.of(context).colorScheme.<token>` or
   `SoliplexTheme.of(context).colors.<token>`.
2. **No `Colors.red|green|orange|blue|yellow`** (or their `.shadeN` variants) for
   status. Use the `SymbolicColors` extension on `ColorScheme`:
   `colorScheme.danger`, `success`, `warning`, `info`. For errors *with* a
   container surface, use `colorScheme.errorContainer` /
   `onErrorContainer` — **not** `danger`.
3. **No magic `EdgeInsets` / `SizedBox` numbers.** Use `SoliplexSpacing.s1`
   (4) / `s2` (8) / `s3` (12) / `s4` (16) / `s6` (24). There is intentionally
   no `s5` — the scale steps from `s4` (16) straight to `s6` (24); use `s6`
   rather than reaching for 20. The only documented exception is chat bubble
   padding `14/10`.
4. **No raw `BorderRadius.circular(N)`.** Use
   `SoliplexTheme.of(context).radii.{sm|md|lg|xl}`. Default is `md` (12 px);
   `sm` (6 px) only for checkboxes and small hit-target wells.
5. **No `TextStyle(fontSize: ...)` or bare `fontSize:` in `.copyWith`.** Start
   from a `Theme.of(context).textTheme.<style>` entry and `.copyWith` only the
   delta you need. The shipped styles are `headlineMedium`, `titleLarge`,
   `titleMedium`, `titleSmall`, `bodyLarge`, `bodyMedium`, `bodySmall`,
   `labelMedium`, `labelSmall`.
6. **No `fontFamily: 'monospace'|'Roboto Mono'|'SF Mono'|'Menlo'`** string
   literals. Use `context.monospace` (bodyMedium base) or
   `SoliplexTheme.withCodeFont(context, base)` for a specific text style — both
   pick the right family and fallback chain per platform.
7. **No hardcoded width breakpoints.** Use `SoliplexBreakpoints.mobile` (320),
   `tablet` (600), `desktop` (840).
8. **Destructive actions** use `colorScheme.error` / `errorContainer`. Never red
   hex.

### Accessor cheat sheet

| What                  | How                                                                                                  |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| Color                 | `Theme.of(context).colorScheme.<token>` or `SoliplexTheme.of(context).colors.<token>`                |
| Status color          | `colorScheme.{danger,success,warning,info}` (via `SymbolicColors`)                                   |
| Spacing               | `SoliplexSpacing.{s1,s2,s3,s4,s6}` (4/8/12/16/24)                                                    |
| Radius                | `SoliplexTheme.of(context).radii.{sm,md,lg,xl}` (6/12/16/24)                                         |
| Text style            | `Theme.of(context).textTheme.{headlineMedium,titleLarge,titleMedium,titleSmall,bodyLarge,bodyMedium,bodySmall,labelMedium,labelSmall}` |
| Monospace             | `context.monospace` (bodyMedium base) or `SoliplexTheme.withCodeFont(context, base)`                 |
| Breakpoint            | `SoliplexBreakpoints.{mobile,tablet,desktop}`                                                        |

Import surface: `import 'package:soliplex_frontend/src/design/design.dart';`

### Adding a new token

Don't, without explicit user approval. If a value is genuinely missing:

1. Stop. Raise the case in the relevant PR before writing code.
2. Add the token to `lib/src/design/tokens/` **and** to
   `design_system/tokens.{dart,css,jsx}` in the same change.
3. Update `design_system/README.md` so the table stays accurate.

### Adoption checklist (run before opening a PR that touches UI)

- [ ] Colors come from `Theme.of(context).colorScheme` (or `SoliplexTheme`), not hex literals.
- [ ] Padding values come from `SoliplexSpacing`.
- [ ] Corner radii come from `SoliplexTheme.of(context).radii`.
- [ ] Text styles come from `Theme.of(context).textTheme`.
- [ ] Monospace uses `context.monospace` or `SoliplexTheme.withCodeFont(context, base)`.
- [ ] Status colors go through the `SymbolicColors` extension.
- [ ] Screen behaves at all three `SoliplexBreakpoints`.
- [ ] Both light and dark palettes look correct.
- [ ] Destructive actions use `colorScheme.error`; never red hex.

## Modules

Five feature modules composed in the standard flavor:

- **auth** — Multi-server OIDC authentication, token refresh, secure storage
- **lobby** — Server/room discovery with responsive layout
- **room** — Chat interface, threads, agent execution, file upload, citations, document filtering, feedback
- **quiz** — Interactive quizzes with multiple-choice and free-text input
- **diagnostics** — Network inspector for HTTP request/response debugging

## Workspace Packages

Four internal packages under `packages/`:

- `soliplex_agent` — Agent orchestration (runtime, sessions, tool registry, execution events)
- `soliplex_client` — Backend HTTP/AG-UI API client, domain models, citation extraction
- `soliplex_client_native` — Native HTTP client (iOS/macOS via cupertino_http)
- `soliplex_logging` — Structured logging with memory, console, disk, and backend sinks

## CI

GitHub Actions runs lint, test, and web build. Tests require 80% coverage. See `.github/workflows/flutter.yaml`.

## Platform Identifiers

All platforms use `ai.soliplex.client` — this replaces the existing production app. Do not change these identifiers without discussion.

## Code Signing

iOS and macOS use gitignored `Local.xcconfig` files for `DEVELOPMENT_TEAM`. Templates at `{ios,macos}/Runner/Configs/Local.xcconfig.template`. See `docs/developer-setup.md`.
