#!/usr/bin/env bash
# tests/smoke_test.sh — Quick sanity check: does the CLI run without errors?
set -e

BIN="$(dirname "$0")/../bin/mac-cleanup"

if [[ ! -x "$BIN" ]]; then
  chmod +x "$BIN"
fi

echo "Testing --help..."
if "$BIN" --help > /dev/null; then
  echo "✔ --help works"
else
  echo "✘ --help failed"
  exit 1
fi

echo "Testing --dry-run --all --yes (should not delete anything)..."
if "$BIN" --dry-run --all --yes > /dev/null; then
  echo "✔ --dry-run --all --yes works"
else
  echo "✘ --dry-run --all --yes failed"
  exit 1
fi

echo "Testing unknown flag returns exit code 1..."
if "$BIN" --unknown-flag > /dev/null 2>&1; then
  echo "✘ should have failed"
  exit 1
else
  echo "✔ unknown flag correctly returns non-zero"
fi

echo "Testing --system --dry-run --yes..."
if "$BIN" --system --dry-run --yes > /dev/null; then
  echo "✔ --system --dry-run --yes works"
else
  echo "✘ --system --dry-run --yes failed"
  exit 1
fi

echo "Testing --devtools --dry-run --yes..."
if "$BIN" --devtools --dry-run --yes > /dev/null; then
  echo "✔ --devtools --dry-run --yes works"
else
  echo "✘ --devtools --dry-run --yes failed"
  exit 1
fi

echo "Testing --all --dry-run --yes contains Summary Report..."
output=$("$BIN" --all --dry-run --yes 2>&1)
if echo "$output" | grep -q "Summary Report"; then
  echo "✔ --all output contains 'Summary Report'"
else
  echo "✘ --all output missing 'Summary Report'"
  exit 1
fi

echo "Testing --help contains --live flag..."
output=$("$BIN" --help 2>&1)
if echo "$output" | grep -q "\-\-live"; then
  echo "✔ --help documents --live flag"
else
  echo "✘ --help missing --live flag"
  exit 1
fi

echo "All smoke tests passed."
