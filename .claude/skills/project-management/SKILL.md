---
name: project-management
description: >-
  Use when starting work on an issue, opening or updating an issue or PR,
  triaging, or asked what goes into the next release. Covers checking an issue
  still applies, labels, PR descriptions, release milestones, and the GitHub
  project. Triggers: "triage", "file an issue", "open a PR", "what's in the
  next release", "milestone", "project board".
---

# Project management

Do what a careful colleague does with the tracker, so the team's picture of
the work stays current without anyone asking.

## Whose items you may change

- **Items you or the person you work for opened, or are assigned:** label,
  set milestones and update the project without asking.
- **Anyone else's:** propose the change in the session (what and why, with
  evidence) and let the person you work for apply it. A label or milestone
  change notifies people.
- **Security issues:** no details in public issues, PRs, commits or labels.
  They go through a private GitHub security advisory, and the fixing PR is
  worded neutrally.

## Before starting work on an issue

1. Check it still applies on `origin/main`, citing `file:line`. An issue's
   line numbers and paths go stale; re-locate them. If it is fixed or
   obsolete, propose closing it with the evidence instead.
2. Look for an open PR that already addresses it
   (`gh pr list --state open --search <number>`) and for who touched the
   files recently (`git log --since=<4 weeks ago> -- <files>`). If someone
   else is active there, ask before claiming it.
3. Claim it: assign the person you work for. Say in a comment which part you
   take when the issue proposes several steps.

## Triage

An issue is triaged when it has one `Type:`, one priority (`P1`–`P4`), and a
`Module:` or `Package:` label, plus a `Department:` label where one fits. Then
add `Status: Triaged`. Read what each label means with `gh label list`; the
descriptions are the definitions. When work waits on something else, add
`Status: Blocked` and a comment naming the blocker by link.

## Pull requests

- Title in the conventional-commit form `git log` uses, e.g.
  `fix(room): …`.
- Body follows `.github/PULL_REQUEST_TEMPLATE.md`. A stacked PR starts with
  "Stacked on #N; merge that first." and targets that PR's branch. End with
  `Closes #N` for each issue it resolves.
- The same `Type:` and `Module:`/`Package:` labels as its issue, and the
  next release milestone.
- A `CHANGELOG.md` entry under `[Unreleased]` for anything a user or a
  library consumer would notice.

## Milestones: one per release, closed by criteria, not dates

- Named `Version X.Y.Z`, the version the release will carry. There is one
  open milestone for the next release. If there is none, propose creating
  it. Set no due date.
- **What goes in:** PRs open for review, and P1 bugs. Not drafts, not
  `Status: Blocked` items, not ideas.
- **The number:** a minor bump when `[Unreleased]` has an Added, Changed or
  Removed entry, otherwise a patch (`dart run tool/bump_version.dart`).
- **Ready to release** when every item in it is closed. An item that will
  not make it moves to the next milestone with a one-line comment saying
  why.
- When the release is tagged, close its milestone and open the next.
- To report status: `gh issue list --milestone "Version X.Y.Z"` and
  `gh pr list --search 'milestone:"Version X.Y.Z"'`, open and closed.

## The GitHub project

Frontend and backend work share one project under the `soliplex`
organization; find it with `gh project list --owner soliplex`. This needs the
`project` token scope: when `gh` says it is missing, ask the person you work
for to run `gh auth refresh -s read:project,project`.

- Add every issue and PR you open:
  `gh project item-add <number> --owner soliplex --url <url>`.
- Keep its status in step with the work: claimed is in progress, a PR open
  for review is in review, merged or closed is done.
