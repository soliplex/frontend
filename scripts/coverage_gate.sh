#!/usr/bin/env bash
# Fail when an lcov report's line coverage is below a minimum.
#
# Usage:
#   ./scripts/coverage_gate.sh <name> <lcov.info> <min-percent>

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <name> <lcov.info> <min-percent>" >&2
  exit 2
fi

NAME="$1"
LCOV="$2"
MIN="$3"

if [ ! -s "$LCOV" ]; then
  echo "::error::$NAME: no coverage report at $LCOV"
  exit 1
fi

read -r HIT FOUND < <(awk -F: '
  /^LH:/ { hit += $2 }
  /^LF:/ { found += $2 }
  END { print hit + 0, found + 0 }
' "$LCOV")

if [ "$FOUND" -eq 0 ]; then
  echo "::error::$NAME: $LCOV has no instrumented lines"
  exit 1
fi

COVERAGE=$(awk -v h="$HIT" -v f="$FOUND" 'BEGIN { printf "%.2f", 100 * h / f }')

# Compare in hundredths so 84.99 does not round up past an 85 minimum.
if [ $((HIT * 10000 / FOUND)) -lt $((MIN * 100)) ]; then
  echo "::error::$NAME: coverage ${COVERAGE}% is below minimum ${MIN}%"
  exit 1
fi

echo "::notice::$NAME: coverage ${COVERAGE}% (minimum ${MIN}%)"
