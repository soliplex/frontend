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

A flavor's visual theme is a **`BrandTheme`** — the public customization contract
(colors per brightness, fonts, corner radii) built from plain Flutter types.
`standard()` takes a `BrandTheme` (defaulting to `const BrandTheme.soliplex()`), an
`AppIdentity` (app name + logos), and a `FontResolver`, then lowers the brand to
`ThemeData` via `lowerBrandTheme(theme, brightness)`. Whitelabel forks customize by
passing `BrandTheme.fromSeed(...)` / `.fromAccents(...)` or a fully-specified
`BrandTheme`; the internal token system stays private behind that lowering boundary.
Spacing and breakpoints are fixed. The brand tokens live in the `soliplex_design`
workspace package (`packages/soliplex_design/`) — see the **Design system** section
below and `packages/soliplex_design/README.md` before writing UI code.

### Flavors

Flavors are functions that construct `AppModule` instances and call
`ShellConfig.fromModules(...)`. Modules are included/excluded by presence in the
flavor — no enum or toggle framework.

## Design system

The design system is the **single source of truth** for color, type, spacing,
radii, breakpoints, and the core component library (button, badge, chip,
input, dropdown, date/time picker). It lives in the `soliplex_design`
workspace package (`packages/soliplex_design/`) and is documented in
`packages/soliplex_design/README.md` and the canonical reference bundle at
`design_system/` (tokens, swatches, type specimens, component demos). **Read
`packages/soliplex_design/README.md` before writing or modifying any widget
code** — it has the full accessor cheat sheet and the component inventory.

### Hard rules — do not violate without explicit user approval

1. **No hex color literals** (`Color(0x...)`, `Color.fromARGB`, `Color.fromRGBO`)
   outside `packages/soliplex_design/`. Use
   `Theme.of(context).colorScheme.<token>` or
   `SoliplexTheme.of(context).colors.<token>`.
2. **No `Colors.red|green|orange|blue|yellow`** (or their `.shadeN` variants) for
   status. Use the `SymbolicColors` extension on `BuildContext`:
   `context.danger`, `success`, `warning`, `info`. For errors *with* a
   container surface, use `colorScheme.errorContainer` /
   `onErrorContainer` — **not** `danger`.
3. **No magic `EdgeInsets` / `SizedBox` numbers.** Use `SoliplexSpacing.s1`
   (4) / `s2` (8) / `s3` (12) / `s4` (16) / `s6` (24). There is intentionally
   no `s5` — the scale steps from `s4` (16) straight to `s6` (24); use `s6`
   rather than reaching for 20. The only documented exception is chat bubble
   padding `14/10`.
4. **No raw `BorderRadius.circular(N)`.** Use `context.radii.{sm|md|lg|xl}`
   (or `SoliplexTheme.of(context).radii`). Default is `md` (12 px);
   `sm` (6 px) only for checkboxes and small hit-target wells.
5. **No `TextStyle(fontSize: ...)` or bare `fontSize:` in `.copyWith`.** Start
   from a `Theme.of(context).textTheme.<style>` entry and `.copyWith` only the
   delta you need. The shipped styles are `headlineMedium`, `titleLarge`,
   `titleMedium`, `titleSmall`, `bodyLarge`, `bodyMedium`, `bodySmall`,
   `labelMedium`, `labelSmall`.
6. **No `fontFamily: 'monospace'|'Roboto Mono'|'SF Mono'|'Menlo'`** string
   literals. Use `context.monospace` (from
   `packages/soliplex_design/lib/src/tokens/typography_x.dart`) — it picks the
   right family per platform.
7. **No hardcoded width breakpoints.** Use `SoliplexBreakpoints.mobile` (320),
   `tablet` (600), `desktop` (840).
8. **Destructive actions** use `colorScheme.error` / `errorContainer`. Never red
   hex.
9. **Prefer the branded component over its Material equivalent** when one
   exists. Use `SoliplexButton` over `FilledButton`/`OutlinedButton`/
   `TextButton`, `SoliplexBadge` for inline status pills, `SoliplexChip` over
   `Chip`/`ActionChip`/`FilterChip`, `SoliplexInput` over `TextField`/
   `TextFormField`, `SoliplexDropdown<T>` over `DropdownMenu<T>`,
   `SoliplexDatePickerField` / `SoliplexTimePickerField` over ad-hoc
   `showDatePicker` / `showTimePicker` wiring. Raw Material widgets are fine
   when no Soliplex wrapper exists — they still pick up the brand `ThemeData`.

### Accessor cheat sheet

| What                  | How                                                                                                  |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| Color                 | `Theme.of(context).colorScheme.<token>` or `SoliplexTheme.of(context).colors.<token>`                |
| Status color          | `context.{danger,success,warning,info}` (via `SymbolicColors` on `BuildContext`)                     |
| Spacing               | `SoliplexSpacing.{s1,s2,s3,s4,s6}` (4/8/12/16/24)                                                    |
| Radius                | `context.radii.{sm,md,lg,xl}` (6/12/16/24)                                                           |
| Text style            | `Theme.of(context).textTheme.{headlineMedium,titleLarge,titleMedium,titleSmall,bodyLarge,bodyMedium,bodySmall,labelMedium,labelSmall}` |
| Monospace             | `context.monospace`                                                                                  |
| Breakpoint            | `SoliplexBreakpoints.{mobile,tablet,desktop}`                                                        |
| Action button         | `SoliplexButton.{filled,outlined,text}` with `intent: ButtonIntent.{primary,danger}` and optional `isLoading` / `isCompact` / `icon` (set `iconAlignment: IconAlignment.end` for a trailing icon; `.text` also takes `alignment: Alignment.centerLeft` for full-width left-aligned nav rows) |
| Inline status pill    | `SoliplexBadge(label, intent, icon)` — `BadgeIntent.{neutral,info,success,warning,danger}`           |
| Chip                  | `SoliplexChip` (display), `.action`, `.filter` — same status intents as badge                        |
| Text input            | `SoliplexInput(label, isPassword, isLoading, ...)` — eye toggle built in                             |
| Select menu           | `SoliplexDropdown<T>(entries, onSelected, isLoading, ...)`                                           |
| Date / time picker    | `SoliplexDatePickerField` / `SoliplexTimePickerField`, or imperative `showSoliplexDatePicker()` / `showSoliplexTimePicker()` |

Import surface: `import 'package:soliplex_design/soliplex_design.dart';`

### Components

The package ships six interactive families with a shared axis vocabulary —
`intent` (per-component enum, see table above), `isLoading` (disables
interaction and paints a spinner *in the existing slot* so the widget doesn't
shift size between idle/loading), and `enabled` (disables without spinner).
Each wrapper delegates to its Material counterpart so any `ThemeData`
override the host app sets still applies; the wrapper only customises the
axes Material leaves to the caller.

A runnable gallery of every variant lives at
`packages/soliplex_design/example/lib/main.dart`. Golden snapshots of every
gallery in both themes live under
`packages/soliplex_design/test/components/*/goldens/` — skim these for a
static visual reference when you're picking between variants. **These goldens
are a Linux baseline** (CI renders them on `ubuntu-latest`); on macOS they
always show ~1% text-edge diffs from font rendering, which is not a
regression. Never run `--update-goldens` off Linux, and skip them locally
with `flutter test --exclude-tags golden`.

### Adding a new token

Don't, without explicit user approval. If a value is genuinely missing:

1. Stop. Raise the case in the relevant PR before writing code.
2. Add the token to `packages/soliplex_design/lib/src/tokens/` **and** to
   `design_system/tokens.{dart,css,jsx}` in the same change.
3. Update `design_system/README.md` so the table stays accurate.

### Adoption checklist (run before opening a PR that touches UI)

- [ ] Colors come from `Theme.of(context).colorScheme` (or `SoliplexTheme`), not hex literals.
- [ ] Padding values come from `SoliplexSpacing`.
- [ ] Corner radii come from `context.radii`.
- [ ] Text styles come from `Theme.of(context).textTheme`.
- [ ] Monospace uses `context.monospace`.
- [ ] Status colors go through `context.{danger,success,warning,info}`.
- [ ] Interactive widgets use the branded `SoliplexX` wrapper when one exists
      (button, badge, chip, input, dropdown, date/time picker).
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

Five internal packages under `packages/`:

- `soliplex_agent` — Agent orchestration (runtime, sessions, tool registry, execution events)
- `soliplex_client` — Backend HTTP/AG-UI API client, domain models, citation extraction
- `soliplex_client_native` — Native HTTP client (iOS/macOS via cupertino_http)
- `soliplex_design` — Core design system: tokens, theme factories, branded component library (button / badge / chip / input / dropdown / date+time picker), `SoliplexGlow`, `SoliplexShimmer` (animated skeleton placeholder), `SoliplexShimmerText` (light-sweep on running labels), shared visual primitives
- `soliplex_logging` — Structured logging with memory, console, disk, and backend sinks

## CI

GitHub Actions runs lint, test, and web build. Tests require 80% coverage. See `.github/workflows/flutter.yaml`.

## Platform Identifiers

All platforms use `ai.soliplex.client` — this replaces the existing production app. Do not change these identifiers without discussion.

## Code Signing

iOS and macOS use gitignored `Local.xcconfig` files for `DEVELOPMENT_TEAM`. Templates at `{ios,macos}/Runner/Configs/Local.xcconfig.template`. See `docs/developer-setup.md`.
