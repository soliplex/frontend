# Soliplex White-Label Theming — Elevator Pitch

> One platform. Every customer's brand. Zero forks.

## The 30-second version

Soliplex now ships a **configuration-driven white-label theming system**. Any
customer can run the full Soliplex AI experience under their own brand — their
colors, their fonts, their light and dark modes — without us forking the
codebase or shipping a custom build per account.

A partner hands us seven brand colors and a font name. We hand back a
pixel-complete, accessible, cross-platform app that looks like *their* product.
That used to be a services engagement. Now it's a config object.

## What changed

Before this release, branding meant editing source code: one theme, hardcoded,
baked into the app. Every new customer who wanted their own look meant a
developer, a branch, and a maintenance burden that compounded with every
account.

This release replaces that with a single `ThemeConfig` input:

- **Colors** — supply a handful of brand colors; the system generates a
  complete, professionally balanced color system (200+ derived values) for both
  light and dark mode automatically.
- **Fonts** — name any font. Bundled brand fonts load instantly; anything else
  is fetched and cached at runtime. No build step.
- **Consistency** — 40+ UI component types (buttons, dialogs, navigation,
  inputs, data tables, the works) are themed centrally, so the brand is applied
  everywhere, automatically, with no per-screen rework.
- **Dark mode** — built in, remembered between sessions, with a one-tap toggle.

## Why it matters

| For the customer | For us |
| ---------------- | ------ |
| Their brand, their identity — not a generic tool | New brand in hours, not weeks |
| Light + dark mode out of the box | One codebase to maintain, not N forks |
| Accessible and consistent on every screen | Theming sold as a feature, not a service |
| Works on web, iOS, macOS, and Android | Predictable, testable, low-risk delivery |

## The bottom line

We turned "custom branding" from a costly, per-customer engineering project into
a **repeatable, near-zero-marginal-cost product capability**. That changes our
unit economics, shortens our sales cycle, and lets us say "yes" to enterprise
branding requirements on the first call.
