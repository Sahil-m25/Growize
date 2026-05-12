#!/usr/bin/env bash
# G.T10: Aggregate red-team test runner
# Runs all automated tests in sequence (01–07). Skips 08 (demo-bypass) as it's manual.
# Run this from the tests/redteam/ directory.

set -e
cd "$(dirname "$0")"

echo "Starting red-team test suite..."
echo ""

for script in 0[1-7]_*.sh; do
  echo "=========================================="
  echo "Running: $script"
  echo "=========================================="
  bash "$script" || { echo "FAIL: Suite failed at $script"; exit 1; }
  echo ""
done

echo "=========================================="
echo "PASS: All red-team tests passed"
echo "=========================================="
