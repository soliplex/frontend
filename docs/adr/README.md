# Architecture Decision Records

An ADR records one decision that is costly to reverse: the context, what
was decided, what was rejected and why, and what it costs. Write one when a
change does any of the following:

- binds people outside this repo: forks consuming the library, the backend
  team, deployers or IdP operators;
- sets a rule every contributor must follow, such as a layering rule, a
  logging rule or a state-management idiom;
- has security impact;
- settles something that has been rewritten or argued about more than once.

A rule in `CLAUDE.md` says *what* to do. The ADR behind it says *why*, so
that the rule can be changed deliberately rather than eroded.

## Index

| ADR | Title | Status | Date |
| --- | ----- | ------ | ---- |
| [ADR-001](ADR-001-reactive-state-management-scoped-statebus.md) | Reactive state management via scoped `StateBus` and ownership-based discovery | Accepted | 2026-04-28 |
| [ADR-002](ADR-002-customizable-brand-theme.md) | Customizable `BrandTheme` via a façade and a lowering buffer | Accepted, amended by ADR-003 §1.3 | 2026-06-24 |
| [ADR-003](ADR-003-flavor-object.md) | Reify the `Flavor`: a declaration object between composition and boot | Accepted, amended by #536 | 2026-07-16 |

The repo-wide rule "Riverpod is DI only; signals carry state" is argued in
ADR-001 §5.3, among the rejected alternatives.

## Conventions

- **File name.** `ADR-NNN-kebab-case-title.md`, three-digit and sequential.
  Numbers are never reused.
- **Status.**
  - `Proposed`: under discussion, not yet in code.
  - `Accepted`: decided, and the code follows it.
  - `Superseded`: replaced by a later ADR, linked in `Superseded by`.
  - `Deprecated`: no longer applies and not replaced.

  Move an ADR to `Accepted` in the PR that implements it.
- **Changing an accepted ADR.**
  - Do not rewrite the decision. For a narrower change, add a dated
    `> **Amended by <ADR or PR> (YYYY-MM-DD):** ...` note at the affected
    section, and list it in the header's `Amended by`.
  - When the change reverses the decision, write a new ADR and mark the old
    one `Superseded`.
- **Scope.** One decision per ADR. A record that settles several independent
  axes should list them in a "Decisions by axis" section, or be split.
- **Update this index** in the same PR that adds or changes an ADR's status.

## Template

```markdown
# ADR-NNN: <Decision, stated as an outcome>

- **Status:** Proposed
- **Date:** YYYY-MM-DD
- **Authors:** <names>
- **Supersedes:** —
- **Superseded by:** —
- **Amends:** — <optional: ADR-NNN §x>

---

## 1. Context and Problem Statement

What forces the decision. Cite code paths, issues and PRs.

## 2. Decision

The decision in a few sentences, plus a sketch or code shape if it helps.

## 3. The Decisions, by Axis

Optional. One subsection per independent sub-decision, each with its reason.

## 4. Consequences

What gets easier, what gets harder, and who is bound (forks, backend,
deployers, contributors). Name how the decision is enforced: a test, a lint,
a CI check, or review only.

## 5. Known Limitations and Open Questions

## 6. Migration

Omit for a retroactive record of a decision already in code.

## 7. Alternatives Considered

| Alternative | Why rejected |
| ----------- | ------------ |
```
