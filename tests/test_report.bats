#!/usr/bin/env bats
# tests/test_report.bats — Summary report regression tests

setup() {
  TEST_HOME=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-report.XXXXXX")
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../bin/mac-cleanup"
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
  fi
}

@test "print_report: shows found, reclaimable, status, grouped categories, and totals" {
  DRY_RUN=true
  MODULE_NAMES=("System" "Deep System" "Caches" "Homebrew" "Orphans")
  MODULE_CATEGORIES=("System" "System" "Caches & Logs" "Caches & Logs" "System")
  MODULE_SCANNED=(3072 0 1024 2048 512)
  MODULE_FREED=(0 0 0 0 0)
  MODULE_STATUS=("3072" "clean" "1024" "2048" "review")
  MODULE_PROJECTED=(3072 0 1024 2048 0)
  TOTAL_DRYRUN_BYTES=6144

  run print_report 12 10240 10240

  [ "$status" -eq 0 ]
  [[ "$output" == *"Category           Module                Found   Reclaimable   Status"* ]]
  [[ "$output" == *"System             System                 3 KB          3 KB   Clean"* ]]
  [[ "$output" == *"                   Deep System              -            -   Clean"* ]]
  [[ "$output" == *"Caches & Logs      Caches                 1 KB          1 KB   Clean"* ]]
  [[ "$output" == *"                   Homebrew               2 KB          2 KB   Clean"* ]]
  [[ "$output" == *"System             Orphans              512 B          0 B   Needs review"* ]]
  [[ "$output" == *"TOTALS                                  6.5 KB        6 KB"* ]]
  [[ "$output" == *"Free space:  10.0 KB → 16.0 KB (projected)"* ]]
  [[ "$output" == *"Status legend:"* ]]
  [[ "$output" != *"Dry-run total:"* ]]
  [[ "$output" == *"Run complete."* ]]
}