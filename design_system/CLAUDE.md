# Soliplex Design System Rules (Claude Code)

A design system lives in this folder (or wherever this file's parent directory is). It is the **single source of truth** for color, type, spacing, radii, breakpoints, and component styling.

## Read these first
- `README.md` — full token + component documentation.
- `tokens.dart` — Flutter records (`SoliplexColors`, `SoliplexSpacing`, `SoliplexRadii`, `SoliplexBreakpoints`). Use these in any Flutter code.
- `tokens.css` — CSS custom properties. Use these in any web surface.
- `Soliplex Design System.html` — visual reference; open in a browser to verify your output matches.

## Hard rules — do not violate without explicit user approval

1. **No hex literals in feature code.** Color values come from:
   - Flutter: `Theme.of(context).colorScheme.<token>` or `SoliplexTheme.of(context).colors.<token>`.
   - Web: `var(--sp-<token>)` from `tokens.css`.
2. **No magic numbers for padding/margin.** Use `SoliplexSpacing.s1..s6` (Flutter) or `var(--sp-space-1..6)` (web).
3. **No magic numbers for border-radius.** Use `soliplexRadii.{sm,md,lg,xl}` or `var(--sp-radius-{sm,md,lg,xl})`.
4. **No new font families.** Platform-native sans + `SF Mono` / `Roboto Mono` for code only. Pull monospace via `context.monospace` in Flutter.
5. **No new text styles.** Use `Theme.of(context).textTheme.<style>` (`headlineMedium`, `titleLarge`, `titleMedium`, `titleSmall`, `bodyLarge`, `bodyMedium`, `bodySmall`, `labelMedium`, `labelSmall`).
6. **Status colors go through `SymbolicColors`** — `info`, `success`, `warning`, `danger`. Don't reach for raw `Colors.red` etc.
7. **Errors with a container surface** use `colorScheme.errorContainer` / `onErrorContainer`, not the symbolic `danger`.
8. **Default radius is `md` (12px)**. Use `sm` only for checkboxes and small hit-target wells.
9. **Three breakpoints: 320 / 600 / 840.** Sidebar becomes persistent at 840.

## Component conventions
- **Cards** wrap most list/detail surfaces. Default background = `inputBackground`. Radius `md`.
- **Inputs** are filled (`inputBackground`), 1px `border` on `enabledBorder`, 2px `border` on `focusedBorder`, `destructive` on `errorBorder`. Radius `md`.
- **Chips**: `inputBackground` bg, 1px `border` side, radius `md`, padding `s2/s1`.
- **Buttons**: filled (primary), outlined (secondary), text (tertiary), destructive (red). All radius `md`.
- **Chat bubbles**: user = `primaryContainer`, assistant = `surfaceContainerLow`. Radius 12.
- **Markdown** renders via `flutter_markdown_plus` with the `MarkdownThemeExtension` shipped in the standard flavor.

## When adding a new token
If a value you need is genuinely missing from the system:
1. Stop. Ask the user before proceeding.
2. Add the token to `tokens.dart` and `tokens.css` in the same change.
3. Update `README.md` so the table stays accurate.

## When in doubt
- Read `README.md` end-to-end before introducing UI.
- Match the production codebase patterns at `lib/src/design/` — production is canonical, this folder mirrors it.
- Run the adoption checklist at the bottom of `README.md` before submitting a PR.
