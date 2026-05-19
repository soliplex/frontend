# Soliplex Design System — Reference

## Overview
This bundle is the **single source of truth** for visual design in the Soliplex Flutter frontend (v0.83.1). It documents tokens (color, type, spacing, radii, breakpoints), components, and adoption rules so an engineer working with Claude Code can pull values directly into the codebase without inventing new ones.

The design system is **Flutter-first** — production tokens live in `lib/src/design/`. This bundle provides:
- `tokens.css` — CSS custom properties (framework-agnostic; useful for any web previews, marketing pages, or non-Flutter surfaces).
- `tokens.dart` — Flutter `SoliplexColors`, `SoliplexSpacing`, `SoliplexRadii`, `SoliplexBreakpoints` records (drop-in for any Flutter target).
- `Soliplex Design System.html` — Static reference doc with live swatches, typography specimens, and component demos. Open it locally to visually verify.
- `tokens.jsx` — JS shape used in HTML mockups, identical hex values; useful only if you also need to render React/HTML mockups.

## About these files
These files describe an **existing, shipped design system**. They are not prototypes to recreate — they are the canonical values. When implementing a feature:
- If you are working in the **Soliplex Flutter repo**, use the existing Dart tokens at `lib/src/design/`. Treat this bundle as documentation only.
- If you are bootstrapping a **new surface** (web preview, internal tool, sister Flutter app), copy `tokens.css` or `tokens.dart` into the new project and route every color/spacing/radius/font through these tokens.
- **Never** hardcode hex values, pixel paddings, or font sizes in feature code.

## Fidelity
**High-fidelity**: every color, spacing, radius, and type style listed here is the production value. Match exactly.

## Design Tokens

### Color — Light
| Token                       | Hex                  |
|-----------------------------|----------------------|
| background                  | `#ffffff`            |
| foreground                  | `#0A0A0A`            |
| primary                     | `#030213`            |
| onPrimary                   | `#ffffff`            |
| primaryContainer            | `#E0DDDA`            |
| onPrimaryContainer          | `#0A0A0A`            |
| secondary                   | `#F3F3FA`            |
| onSecondary                 | `#030213`            |
| tertiary                    | `#6B7280`            |
| onTertiary                  | `#FFFFFF`            |
| tertiaryContainer           | `#F3F4F6`            |
| onTertiaryContainer         | `#374151`            |
| accent                      | `#E9EBEF`            |
| onAccent                    | `#030213`            |
| muted                       | `#ECECF0`            |
| mutedForeground             | `#595968`            |
| destructive                 | `#D4183D`            |
| onDestructive               | `#ffffff`            |
| errorContainer              | `#FEE2E2`            |
| onErrorContainer            | `#991B1B`            |
| border                      | `rgba(0,0,0,0.10)`   |
| outline                     | `#C0C0C4`            |
| outlineVariant              | `#E0E0E2`            |
| inputBackground             | `#F3F3F5`            |
| hintText                    | `#666666`            |
| surfaceContainerLowest      | `#FFFFFF`            |
| surfaceContainerLow         | `#EFEFEF`            |
| surfaceContainerHigh        | `#ECECEC`            |
| surfaceContainerHighest     | `#E4E4E4`            |
| inversePrimary              | `#B0B0B0`            |
| link                        | `#2563EB`            |

### Color — Dark
| Token                       | Hex                  |
|-----------------------------|----------------------|
| background                  | `#111111`            |
| foreground                  | `#FAFAFA`            |
| primary                     | `#FAFAFA`            |
| onPrimary                   | `#222222`            |
| primaryContainer            | `#2A2A2A`            |
| onPrimaryContainer          | `#FAFAFA`            |
| secondary                   | `#2A2A2A`            |
| onSecondary                 | `#FFFFFF`            |
| tertiary                    | `#9CA3AF`            |
| onTertiary                  | `#1F1F1F`            |
| tertiaryContainer           | `#2A2A2A`            |
| onTertiaryContainer         | `#D1D5DB`            |
| accent                      | `#2A2A2A`            |
| onAccent                    | `#FFFFFF`            |
| muted                       | `#444444`            |
| mutedForeground             | `#AAAAAA`            |
| destructive                 | `#D4183D`            |
| onDestructive               | `#FFFFFF`            |
| errorContainer              | `#3D1A1A`            |
| onErrorContainer            | `#FCA5A5`            |
| border                      | `#2A2A2A`            |
| outline                     | `#555555`            |
| outlineVariant              | `#3A3A3A`            |
| inputBackground             | `#333333`            |
| hintText                    | `#A3A3A3`            |
| surfaceContainerLowest      | `#0E0E0E`            |
| surfaceContainerLow         | `#1A1A1A`            |
| surfaceContainerHigh        | `#2A2A2A`            |
| surfaceContainerHighest     | `#333333`            |
| inversePrimary              | `#555555`            |
| link                        | `#60A5FA`            |

### Brand palette (mark only — not UI chrome)
| Token            | Hex       |
|------------------|-----------|
| mark/background  | `#2F3337` |
| mark/ring        | `#60C7D8` |
| mark/bar         | `#333335` |
| mark/diamond     | `#E6F1F3` |

### Typography
Platform-native sans (Roboto on Android, SF on iOS/macOS, system on web/desktop). No bundled font family. All styles use `height: 1.5` except `headlineMedium` which uses `1.3`.

| Style          | Size | Weight | Line height | Use for                            |
|----------------|------|--------|-------------|------------------------------------|
| headlineMedium | 28   | w400   | 1.3         | Top-of-screen titles               |
| titleLarge     | 24   | w500   | 1.5         | Markdown H1, section titles        |
| titleMedium    | 20   | w500   | 1.5         | Markdown H2, dialog headings       |
| titleSmall     | 16   | w500   | 1.5         | Markdown H3, list titles           |
| bodyLarge      | 18   | w400   | 1.5         | Markdown body in messages          |
| bodyMedium     | 16   | w400   | 1.5         | Default UI body                    |
| bodySmall      | 13   | w400   | 1.5         | Helper text, metadata              |
| labelMedium    | 16   | w500   | 1.5         | Button labels                      |
| labelSmall     | 12   | w500   | 1.5         | Chip labels, timestamps            |

**Monospace**: `SF Mono` on Cupertino, `Roboto Mono` everywhere else. Use for code blocks, inline code, and the network inspector.

### Spacing
Five values only. Larger gaps are multiples of these — do **not** add new values without team review.

| Name | Value |
|------|-------|
| s1   | 4 px  |
| s2   | 8 px  |
| s3   | 12 px |
| s4   | 16 px |
| s6   | 24 px |

Conventions:
- Chat bubbles: `padding: 14/10` (the only 14 in the system)
- Chat input wrapper: `EdgeInsets.all(8)` (= s2)
- App bar actions: `symmetric(horizontal: s2)`
- Chips: `symmetric(horizontal: s2, vertical: s1)`

### Radii
| Name | Value | Use for                           |
|------|-------|-----------------------------------|
| sm   | 6 px  | Checkboxes, hit-target wells      |
| md   | 12 px | **Default** for almost every control |
| lg   | 16 px | Larger cards                      |
| xl   | 24 px | Sheets, splash surfaces           |

### Breakpoints
| Name    | Min width | Layout                                 |
|---------|-----------|----------------------------------------|
| mobile  | ≥ 320 px  | Single column, drawer nav              |
| tablet  | ≥ 600 px  | Two columns; master/detail             |
| desktop | ≥ 840 px  | Persistent sidebar + main + detail     |

The tablet/desktop boundary (840) is where the sidebar becomes persistent instead of a drawer.

## Components

### Buttons
- **Filled** (primary CTA) — `colors.primary` background, `colors.onPrimary` text, radius `md`, 1px `colors.border` side.
- **Outlined** (secondary) — transparent background, `colors.border` 1px side, radius `md`.
- **Text** — no border, link-style for tertiary actions.
- **Destructive** — `colors.destructive` background.
- **Icon button** — 40×40 hit target, no fill.

### Inputs
- `filled: true` with `colors.inputBackground`.
- Border collapses to none on the unfocused state but reappears as a 1px hairline on `enabledBorder` (`colors.border`).
- Focus doubles border to 2px, same color.
- Error border uses `colors.destructive`.
- Hint uses `colors.hintText`.
- Radius `md`.

### Cards & List Tiles
- Default `Card` background = `colors.inputBackground`.
- Radius `md`.
- ListTiles inside cards: title `titleSmall`, subtitle `bodySmall` muted.
- Trailing supports a status icon row + an `IconButton`.

### Chips & Badges
- Chip background `colors.inputBackground`; selected = `primary @ 10% alpha`.
- Border 1px `colors.border`, radius `md`.
- Padding `symmetric(horizontal: s2, vertical: s1)`.
- Badges (custom `SoliplexBadgeThemeData`): foreground @ 6% blended on background; `labelMedium`.

### Chat & Messages
- User bubble: `primaryContainer` bg, `onPrimaryContainer` text, radius `12`.
- Assistant bubble: `surfaceContainerLow` bg, default text, radius `12`.
- Markdown rendered via `flutter_markdown_plus`; H1/H2/H3 map to titleLarge/Medium/Small; code blocks use `surfaceContainerHighest`.
- "Thinking…" prefix sits above streaming responses in `bodySmall` italic muted.

### Feedback buttons
- Thumbs up/down with a 5s countdown ring after press.
- "Tell us why!" link appears during countdown — opens a reason dialog before submission.
- Phases: `idle → countdown → modal? → submitted`.

### Status & Symbolic colors
Read via the `SymbolicColors` extension on `ColorScheme`:
- `info` — blue (light: `Colors.blue`, dark: `Colors.blue.shade300`)
- `success` — green
- `warning` — orange
- `danger` — red

Errors that need a container use `errorContainer` / `onErrorContainer` from the scheme, **not** the symbolic `danger`.

### Execution timeline (Call → Events → Event Details)
The room view's "answering" area renders agent execution as nested swim-lanes:
- **Call** — top-level skill invocation (e.g. `retrieve_docs`, `execute_skill`). Rendered as a horizontal duration bar on a shared time axis. Color-coded per call: teal `#60C7D8` for retrieval, violet `#a78bfa` for execution.
- **Event** — sub-step under a call (Thinking, tool invocation, result). Rendered indented under the parent call with status dot + duration bar. Thinking events use a dashed bar; tool events use a solid bar in the call's color.
- **Event Detail** — inline drawer beneath a focused event. Italic text for thoughts; `args` + `result` JSON blocks for tool calls. Border-left in the call's color.

### Citations
Rendered as numbered chips beneath assistant messages. Each chip shows: number badge, title (`bodyMedium 500`), source (`labelSmall mono muted`), confidence pct (`labelSmall mono muted`).

### Document picker
List of doc rows with checkbox + filename + page count + last-modified. Selected docs surface as chips in the chat input.

## Interactions & Behavior
- **Theme switching**: `SoliplexTheme` is a `ThemeExtension` that interpolates radii during transitions — animations are smooth. No instant snap.
- **Streaming**: assistant bubbles render markdown incrementally as tokens arrive. The "Thinking…" caption only shows while no body text has streamed yet.
- **Citations**: clicking a `[1]` superscript scrolls to and highlights the matching citation chip (`primary @ 10%` flash, 200ms ease).
- **Quiz**: lock icon on rooms with quizzes; submit reveals correctness + explanation + 3 sources.

## State Management
Riverpod throughout. Each feature module exposes a `ModuleContribution { routes, providers, redirect? }`. Providers are overridden at the shell level — never inside the module — so flavors can swap implementations.

## Architecture
- `runSoliplexShell(ShellConfig)` boots the app from a single config object.
- Modules: `auth`, `lobby`, `room`, `quiz`, `diagnostics`.
- Targets: Android, iOS, macOS, Linux, Windows, Web.
- Theming: `tokens/colors.dart` → `soliplexLightTheme` / `soliplexDarkTheme` → `ThemeExtension<SoliplexTheme>`.

### Theming flow
1. `SoliplexColors` record (31 fields) declared in `tokens/colors.dart`.
2. `soliplexLightTheme(colors)` maps the record into a Material 3 `ThemeData` — app bar, buttons, inputs, list tiles, chips, cards, expansion tiles, dropdowns, popup menus.
3. A `SoliplexTheme` `ThemeExtension` carries the raw record + `SoliplexRadii` + `SoliplexBadgeThemeData` so code paths that need the record (not just the scheme) can read `Theme.of(context).extension<SoliplexTheme>()`.
4. The `standard()` flavor adds a `MarkdownThemeExtension` for chat-message rendering.

## Adoption checklist (run before opening a PR)
- [ ] Colors come from `Theme.of(context).colorScheme`, not hex literals.
- [ ] Padding values come from `SoliplexSpacing` (`s1..s6`).
- [ ] Corner radii come from `soliplexRadii` via `SoliplexTheme.of(context).radii`.
- [ ] Text styles come from `Theme.of(context).textTheme`.
- [ ] Monospace uses `context.monospace`, not a hardcoded font family.
- [ ] Status colors go through the `SymbolicColors` extension.
- [ ] Screen behaves at all three `SoliplexBreakpoints`.
- [ ] Both light and dark palettes look correct.
- [ ] Destructive actions use `colorScheme.error`; never red hex.

## Files in this bundle
- `README.md` — this file.
- `CLAUDE.md` — instructions read by Claude Code automatically when run inside the repo.
- `tokens.css` — CSS custom properties for both light and dark palettes plus type/spacing/radii.
- `tokens.dart` — Flutter records: `SoliplexColors`, `SoliplexSpacing`, `SoliplexRadii`, `SoliplexBreakpoints`.
- `Soliplex Design System.html` — visual reference doc (open in a browser).
- `tokens.jsx` — JS shape (only needed if rendering JS/React mockups).
- `assets/` — brand assets (logo, favicon).

## How to use with Claude Code
1. Drop this folder into your repo at `design/` (or any path you prefer).
2. Either move `CLAUDE.md` to your repo root, **or** ensure your repo's existing `CLAUDE.md` references this folder. Claude Code reads `CLAUDE.md` automatically on every session.
3. Reference tokens by importing `tokens.dart` (Flutter) or `@import "tokens.css"` (web).
4. When asking Claude Code to add a feature, reference this folder explicitly: *"Use the tokens in `design/tokens.dart` — do not introduce new colors."*
