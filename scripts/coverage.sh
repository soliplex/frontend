#!/usr/bin/env bash
# Unified test coverage for the app and all packages.
#
# Usage:
#   ./scripts/coverage.sh          # run all, generate HTML
#   ./scripts/coverage.sh --no-html  # skip HTML generation
#
# Requires: lcov, genhtml (brew install lcov / apt install lcov)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COVERAGE_DIR="$ROOT/coverage"
MERGED="$COVERAGE_DIR/lcov.info"
HTML_DIR="$COVERAGE_DIR/html"
NO_HTML=false

for arg in "$@"; do
  case "$arg" in
    --no-html) NO_HTML=true ;;
  esac
done

rm -rf "$COVERAGE_DIR"
mkdir -p "$COVERAGE_DIR"

LCOV_FILES=()

# --- App-level (flutter test) ---
echo "==> Running app tests..."
cd "$ROOT"
flutter test --coverage 2>&1 | tail -1

# Strip package coverage from app report — packages have their own test suites
# that provide better coverage. Keeping both creates duplicate entries.
# Mockups are prototypes, excluded as in CI.
lcov --remove "$COVERAGE_DIR/lcov.info" 'packages/*' 'lib/src/mockups/*' \
  --output-file "$COVERAGE_DIR/app.lcov.info" --quiet --ignore-errors unused
LCOV_FILES+=("$COVERAGE_DIR/app.lcov.info")

# --- Pure Dart packages (dart test) ---
# --coverage-package pins each report to the package's own lib/; in the
# workspace it otherwise also counts the sibling packages it imports.
for pkg in soliplex_agent soliplex_client soliplex_logging; do
  pkg_dir="$ROOT/packages/$pkg"
  if [ ! -d "$pkg_dir/test" ]; then
    echo "==> Skipping $pkg (no test/ directory)"
    continue
  fi

  echo "==> Running $pkg tests..."
  cd "$pkg_dir"
  rm -rf coverage
  dart test --exclude-tags integration \
    --coverage-path=coverage/lcov.info --coverage-package="^$pkg\$" 2>&1 \
    | tail -1

  if [ -f coverage/lcov.info ]; then
    # Normalize absolute paths to relative (from project root)
    sed "s|^SF:$ROOT/|SF:|" coverage/lcov.info \
      > "$COVERAGE_DIR/${pkg}.lcov.info"
    LCOV_FILES+=("$COVERAGE_DIR/${pkg}.lcov.info")
    rm -rf coverage
  fi
done

# --- Flutter packages (flutter test) ---
for pkg in soliplex_client_native soliplex_design; do
  pkg_dir="$ROOT/packages/$pkg"
  if [ ! -d "$pkg_dir/test" ]; then
    echo "==> Skipping $pkg (no test/ directory)"
    continue
  fi

  echo "==> Running $pkg tests..."
  cd "$pkg_dir"
  flutter test --coverage 2>&1 | tail -1

  if [ -f coverage/lcov.info ]; then
    # Prefix package-relative paths (from project root)
    sed "s|^SF:lib/|SF:packages/$pkg/lib/|" coverage/lcov.info \
      > "$COVERAGE_DIR/${pkg}.lcov.info"
    LCOV_FILES+=("$COVERAGE_DIR/${pkg}.lcov.info")
    rm -rf coverage
  fi
done

# --- Merge all lcov files ---
echo ""
echo "==> Merging coverage from ${#LCOV_FILES[@]} sources..."
cd "$ROOT"

MERGE_ARGS=()
for f in "${LCOV_FILES[@]}"; do
  if [ -f "$f" ]; then
    MERGE_ARGS+=(--add-tracefile "$f")
  fi
done

lcov "${MERGE_ARGS[@]}" --output-file "$MERGED" --quiet --ignore-errors empty

# --- Summary ---
echo ""
echo "=== Coverage Summary ==="
lcov --summary "$MERGED" 2>&1 | grep -E "lines|source"

# --- HTML report ---
if [ "$NO_HTML" = false ]; then
  echo ""
  echo "==> Generating HTML report..."
  genhtml "$MERGED" --output-directory "$HTML_DIR" --quiet \
    --filter missing --ignore-errors unmapped
  echo "Report: $HTML_DIR/index.html"
fi
