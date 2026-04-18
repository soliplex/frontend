#!/usr/bin/env bash
# Runs MontyScriptEnvironment integration tests against demo.toughserv.com (WASM/Chrome).
#
# Requires Chrome and dart_monty_native.wasm.
# Usage: bash tool/test_integration_wasm.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WASM_ASSET="lib/wasm_assets/dart_monty_native.wasm"
if [[ ! -f "$WASM_ASSET" ]]; then
  echo "ERROR: $WASM_ASSET missing."
  echo "  Build: cd ~/.pub-cache/git/dart_monty-*/native && cargo build --release --target wasm32-wasip1"
  echo "  Copy:  cp target/wasm32-wasip1/release/dart_monty_native.wasm <plugin>/lib/wasm_assets/"
  exit 1
fi

echo "=== Integration Tests (WASM) ==="
dart test \
  test/integration/monty_env_chat_test.dart \
  --platform chrome \
  --run-skipped \
  --tags=integration \
  --reporter expanded
echo "=== Integration Tests (WASM) PASSED ==="
