#!/usr/bin/env bash
#
# audit.sh — scan a target directory for soliplex_design hard-rule violations.
#
# Usage:
#   .claude/skills/adopt-design-system/audit.sh [path]
#
# `path` defaults to `lib` (a fork's own UI). The soliplex_design package is
# always excluded — hex literals and raw radii are legal *inside* the design
# system, only banned in consumers. Generated files (*.g.dart, *.freezed.dart,
# *.gen.dart) are skipped too.
#
# Uses plain `grep` so it runs on any machine with no extra tooling. Exit
# status is non-zero when any violation is found, so the script doubles as a
# CI gate. Each finding prints `file:line:match`; review every hit and migrate
# it per the mapping table in SKILL.md.

set -uo pipefail

TARGET="${1:-lib}"

if [[ ! -e "$TARGET" ]]; then
  echo "error: target path '$TARGET' does not exist." >&2
  exit 2
fi

GREP=(grep -rEn --include='*.dart'
  --exclude-dir=soliplex_design
  --exclude='*.g.dart' --exclude='*.freezed.dart' --exclude='*.gen.dart')

found=0

# Each entry: "Human-readable rule|extended-regex pattern".
# Patterns are deliberately conservative — they over-report rather than miss,
# so treat the output as candidates for review, not guaranteed violations.
RULES=(
  "Hex color literal (use colorScheme/SoliplexTheme tokens)|Color\(0x|Color\.fromARGB|Color\.fromRGBO"
  "Material status color (use SymbolicColors: danger/success/warning/info)|Colors\.(red|green|orange|blue|yellow)"
  "Raw border radius (use SoliplexTheme.of(context).radii.*)|BorderRadius\.circular\("
  "Hardcoded font size (start from textTheme + copyWith)|fontSize:"
  "Font-family string literal (use context.monospace)|fontFamily: *['\"](monospace|Roboto Mono|SF Mono|Menlo)"
  "Material widget with a Soliplex wrapper (prefer SoliplexX)|\b(FilledButton|OutlinedButton|TextButton|ActionChip|FilterChip|TextField|TextFormField|DropdownMenu)\b"
)

for rule in "${RULES[@]}"; do
  label="${rule%%|*}"
  pattern="${rule#*|}"
  echo "── ${label}"
  if "${GREP[@]}" -e "$pattern" "$TARGET"; then
    found=1
  else
    echo "   (none)"
  fi
  echo
done

# Raw EdgeInsets / SizedBox numbers and width breakpoints need human eyes —
# the numbers overlap with legitimate token values, so we only point at them.
echo "── Manual review: spacing, breakpoints"
echo "   Padding/SizedBox must come from SoliplexSpacing (s1=4, s2=8, s3=12,"
echo "   s4=16, s6=24 — no s5). Width thresholds must use SoliplexBreakpoints"
echo "   (mobile=320, tablet=600, desktop=840). Grep candidates:"
"${GREP[@]}" \
  -e 'EdgeInsets\.(all|symmetric|only|fromLTRB)\( *[0-9]' \
  -e 'SizedBox\((width|height): *[0-9]' \
  -e 'MediaQuery.*\.width *[<>]' "$TARGET" || echo "   (none)"
echo

if [[ "$found" -ne 0 ]]; then
  echo "Violations found. Migrate each per .claude/skills/adopt-design-system/SKILL.md."
  exit 1
fi

echo "No hard-rule violations detected. Still complete the manual review above."
exit 0
