#!/usr/bin/env bash

# Test script for mac-cleanup CLI flags
CLI="./bin/mac-cleanup"

echo "=== Testing --version ==="
$CLI --version

echo -e "\n=== Testing -V ==="
$CLI -V

echo -e "\n=== Testing --help ==="
$CLI --help | head -n 5

echo -e "\n=== Testing -h ==="
$CLI -h | head -n 5

echo -e "\n=== Testing --verbose (no targets) ==="
# Should run dry-run default, no prompt
echo "BAD_INPUT" | $CLI --verbose | head -n 10

echo -e "\n=== Testing --all --verbose ==="
# Should ask for prompt because -y or -n not specified
echo "N" | $CLI --all --verbose | head -n 10

echo -e "\n=== Testing --all --dry-run --verbose ==="
echo "BAD_INPUT" | $CLI --all --dry-run --verbose | head -n 10

echo -e "\n=== Testing --yes --all ==="
# Should NOT prompt
# We will just see if it starts running (don't want to actually delete anything, but we can kill it)
# Actually, no let's just use BATS tests
