#!/usr/bin/env bash
# Runs all @monty integration tests against Chrome (WASM backend).
#
# dart_monty_native.wasm is a binary build artifact and gitignored.
# Build it once before running:
#
#   CORE=$(dart pub deps --json 2>/dev/null | \
#     python3 -c "import sys,json; d=json.load(sys.stdin); \
#     [print(p['rootUri'].replace('file://','')) \
#     for p in d['packages'] if p['name']=='dart_monty_core']")
#   cargo build --release --target wasm32-wasip1 --manifest-path "$CORE/native/Cargo.toml"
#   cp "$CORE/native/target/wasm32-wasip1/release/dart_monty_native.wasm" lib/wasm_assets/
#
# Usage: bash tool/test_integration_wasm.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WASM_ASSET="lib/wasm_assets/dart_monty_native.wasm"
if [[ ! -f "$WASM_ASSET" ]]; then
  echo "ERROR: $WASM_ASSET missing. See comments at top of this script for build instructions."
  exit 1
fi

echo "=== Integration Tests (WASM / Chrome) ==="
dart test \
  test/integration/ \
  --platform chrome \
  --tags=monty \
  --reporter failures-only
echo "=== Integration Tests (WASM) PASSED ==="
