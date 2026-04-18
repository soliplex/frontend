#!/usr/bin/env bash
# Runs MontyScriptEnvironment integration tests against demo.toughserv.com (FFI).
#
# Usage: bash tool/test_integration_ffi.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Integration Tests (FFI) ==="
dart test \
  test/integration/monty_env_chat_test.dart \
  --run-skipped \
  --tags=integration \
  --reporter expanded
echo "=== Integration Tests (FFI) PASSED ==="
