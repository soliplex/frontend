# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Soliplex Flutter frontend — both a **runnable app** and an **importable library**. Uses a modular shell architecture where each module is a function returning a `ModuleContribution` (routes + Riverpod overrides). See `docs/plans/0001-app-shell/proposal.md` for the full design proposal.

## Commands

Prefer Dart MCP tools over shell commands. All tools take `root` as `file:///absolute/path/to/project`.

| Task | MCP tool | Shell fallback |
|------|----------|----------------|
| Dependencies | `mcp__dart__pub` (command: `get`) | `flutter pub get` |
| Lint (must pass with zero warnings) | `mcp__dart__analyze_files` | `flutter analyze` |
| Run all tests | `mcp__dart__run_tests` with `testRunnerArgs.reporter: "failures-only"` | `flutter test --reporter failures-only` |
| Run a single test file | `mcp__dart__run_tests` with `paths`, `testRunnerArgs.reporter: "failures-only"` | `flutter test --reporter failures-only test/path.dart` |
| Run a single test by name | `mcp__dart__run_tests` with `testRunnerArgs.name`, `testRunnerArgs.reporter: "failures-only"` | `flutter test --reporter failures-only --name "test name"` |
| Run the app | `mcp__dart__launch_app` with `device` | `flutter run -d macos` |
| Check for outdated deps | `mcp__dart__pub` (command: `outdated`) | `flutter pub outdated` |
| Format code | `mcp__dart__dart_format` | `dart format .` |
| Apply fixes | `mcp__dart__dart_fix` | `dart fix --apply` |

## Architecture

### Module System

Entry point: `runSoliplexShell(ShellConfig)` boots the app from a `ShellConfig`.

Each module is a function that takes dependencies via constructor injection and returns a `ModuleContribution` (routes + Riverpod overrides). No base class, no registry. The compiler enforces dependency ordering. Flavor functions create concrete instances, inject them into module functions, and compose `ModuleContribution` values into a `ShellConfig`. The shell flattens modules and collects overrides into a single root `ProviderScope`.

### State Management

Riverpod is **DI/service locator only** — no AsyncNotifier or FutureProvider chains. Reactive state comes from `signals` (via `soliplex_agent`). The `signals` package bridges signal reactivity to Flutter widget rebuilds.

### Theming

`ShellConfig` takes `ThemeData` directly — Flutter's standard abstraction. Each flavor provides its own `ThemeData`. Custom palette abstractions deferred until multiple flavors need them.

### Flavors

Flavors are functions that compose module functions into a `ShellConfig`. Modules are included/excluded by presence in the flavor — no enum or toggle framework.

## Platform Identifiers

All platforms use `ai.soliplex.client` — this replaces the existing production app. Do not change these identifiers without discussion.

## Code Signing

iOS and macOS use gitignored `Local.xcconfig` files for `DEVELOPMENT_TEAM`. Templates at `{ios,macos}/Runner/Configs/Local.xcconfig.template`. See `docs/developer-setup.md`.
