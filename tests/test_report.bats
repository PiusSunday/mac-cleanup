#!/usr/bin/env bats
# tests/test_report.bats — Summary report regression tests

setup() {
  TEST_HOME=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-report.XXXXXX")
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../bin/mac-cleanup"
}

# Sourcing core.sh from inside setup() scopes its `declare -a` arrays to that
# function, so the fixture has to be applied from the test body, where a plain
# assignment lands on the global the report actually reads.
fixture() {
  MODULE_NAMES=("System" "Deep System" "Caches" "Homebrew" "Orphans" "Docker")
  MODULE_CATEGORIES=("System" "System" "Caches & Logs" "Caches & Logs" "System" "Developer Tools")
  MODULE_SCANNED=(3072 0 1024 2048 512 0)
  MODULE_FREED=(0 0 0 0 0 0)
  MODULE_STATUS=("3072" "clean" "1024" "2048" "review" "skipped")
  MODULE_PROJECTED=(3072 0 1024 2048 0 0)
  MODULE_ITEMS=(4 0 2 0 0 0)
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()
  TOTAL_PROTECTED=0
  TOTAL_DEDUPED=0
  TOTAL_DRYRUN_BYTES=6144
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
  fi
}

@test "print_report: ranks modules by reclaimable size, largest first" {
  fixture
  DRY_RUN=true
  run print_report 12 10240 10240
  [ "$status" -eq 0 ]

  # System (3 KB) > Homebrew (2 KB) > Caches (1 KB)
  local sys hb caches
  sys=$(echo "$output" | grep -n '^  System ' | cut -d: -f1)
  hb=$(echo "$output" | grep -n '^  Homebrew ' | cut -d: -f1)
  caches=$(echo "$output" | grep -n '^  Caches ' | cut -d: -f1)
  [ "$sys" -lt "$hb" ]
  [ "$hb" -lt "$caches" ]
}

@test "print_report: totals the reclaimable column and the item counts" {
  fixture
  DRY_RUN=true
  run print_report 12 10240 10240
  [[ "$output" == *"RECLAIMABLE"* ]]
  [[ "$output" == *"Total"*"6 KB"*"6"* ]]
}

@test "print_report: modules with nothing to reclaim do not take a table row" {
  fixture
  DRY_RUN=true
  run print_report 12 10240 10240
  # Deep System is clean, Docker unavailable, Orphans needs review — all are
  # named on their own summary line rather than padding the table with dashes.
  [[ "$output" == *"Already clean"*"Deep System"* ]]
  [[ "$output" == *"Unavailable"*"Docker"* ]]
  [[ "$output" == *"Needs review"*"Orphans"* ]]
}

@test "print_report: a module cleaning through its own CLI shows no item count" {
  fixture
  DRY_RUN=true
  run print_report 12 10240 10240
  # Homebrew reclaims 2 KB but queues no paths, so "0" would misread as
  # "found nothing".
  [[ "$output" == *"Homebrew"*"2 KB"*"—"* ]]
}

@test "print_report: projects free space in dry run and reports actual in live" {
  fixture
  DRY_RUN=true
  # Dry run projects: 10 KB free now, plus the 6 KB the table totals.
  run print_report 12 10240 10240
  [[ "$output" == *"10 KB free"*"16 KB after cleanup"* ]]

  # Live run reports what df actually shows afterwards.
  DRY_RUN=false
  run print_report 12 10240 20480
  [[ "$output" == *"10 KB free"*"20 KB free"* ]]
  [[ "$output" != *"after cleanup"* ]]
}

@test "print_report: closes with the right call to action for the mode" {
  fixture
  DRY_RUN=true
  run print_report 12 10240 10240
  [[ "$output" == *"This was a preview"* ]]
  [[ "$output" == *"6 KB"* ]]

  DRY_RUN=false
  run print_report 12 10240 20480
  [[ "$output" == *"Reclaimed"* ]]
  [[ "$output" != *"This was a preview"* ]]
}

@test "print_report: says so plainly when there is nothing to reclaim" {
  fixture
  DRY_RUN=true
  MODULE_PROJECTED=(0 0 0 0 0 0)
  MODULE_STATUS=("clean" "clean" "clean" "clean" "clean" "clean")
  run print_report 3 10240 10240
  [[ "$output" == *"already clean"* ]]
}

@test "print_report: surfaces opt-in wins with their command" {
  fixture
  DRY_RUN=true
  ACTION_LABELS=("3 superseded Xcode simulator runtimes" "14 unused Docker images")
  ACTION_BYTES=(25000000000 15000000000)
  ACTION_COMMANDS=("mac-cleanup --simulators" "docker rmi <name>")

  run print_report 12 10240 10240
  [[ "$output" == *"NEEDS YOUR DECISION"* ]]
  [[ "$output" == *"superseded Xcode simulator runtimes"* ]]
  [[ "$output" == *"mac-cleanup --simulators"* ]]
  [[ "$output" == *"docker rmi <name>"* ]]

  # Largest opportunity first: Xcode (23.3 GB) above Docker (14.0 GB).
  local xcode docker
  xcode=$(echo "$output" | grep -n "superseded Xcode" | cut -d: -f1)
  docker=$(echo "$output" | grep -n "unused Docker" | cut -d: -f1)
  [ "$xcode" -lt "$docker" ]
}

@test "print_report: omits the decision block when there is nothing to decide" {
  fixture
  DRY_RUN=true
  run print_report 12 10240 10240
  [[ "$output" != *"NEEDS YOUR DECISION"* ]]
}

@test "print_report: reports protected and deduplicated path counts" {
  fixture
  DRY_RUN=true
  TOTAL_PROTECTED=6
  TOTAL_DEDUPED=4
  run print_report 12 10240 10240
  [[ "$output" == *"6 paths protected by policy"* ]]
  [[ "$output" == *"4 counted by another module"* ]]
}

@test "print_report: renders the log path relative to home without escaping it" {
  fixture
  DRY_RUN=true
  export LOG_FILE="$HOME/.mac-cleanup/cleanup.log"
  run print_report 12 10240 10240
  [[ "$output" == *"~/.mac-cleanup/cleanup.log"* ]]
  [[ "$output" != *'\~'* ]]
}

@test "print_report: formats durations over a minute as minutes and seconds" {
  fixture
  [ "$(report::_duration 45)" = "45s" ]
  [ "$(report::_duration 116)" = "1m 56s" ]
  [ "$(report::_duration 3600)" = "60m 00s" ]
}

@test "print_report: bar length is proportional and never empty for a non-zero size" {
  fixture
  # Largest module fills the bar; a tiny one still renders a sliver so
  # "small but present" never looks like "absent".
  local big small
  big=$(report::_bar 1000 1000 | tr -cd '█' | wc -c | tr -d ' ')
  small=$(report::_bar 1 1000)
  [ "$big" -gt 20 ]
  [ -n "$small" ]
  [ -z "$(report::_bar 0 1000)" ]
}

@test "print_report: survives having no modules at all" {
  fixture
  DRY_RUN=true
  MODULE_NAMES=(); MODULE_CATEGORIES=(); MODULE_SCANNED=()
  MODULE_FREED=(); MODULE_STATUS=(); MODULE_PROJECTED=(); MODULE_ITEMS=()
  run print_report 1 10240 10240
  [ "$status" -eq 0 ]
  [[ "$output" == *"no modules ran"* ]]
}
