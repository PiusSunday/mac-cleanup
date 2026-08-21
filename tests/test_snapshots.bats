#!/usr/bin/env bats
# tests/test_snapshots.bats — Local Time Machine snapshots.
#
# macOS reports no size for a snapshot and the deletion runs through tmutil
# rather than safe_rm, so there are never bytes to attribute. Reporting on bytes
# made a preview announce "Nothing to clean" while listing real snapshots — the
# same defect as the Trash gate. Per CONTRIBUTING, both branches get a fixture.

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/snap-home.XXXXXX")"
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"
  export OPLOG_FILE="$TEST_HOME/operations.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/protect.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/system/snapshots.sh"

  WHITELIST_PATTERNS=()
  protect::claim_reset
  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false

  MODULE_NAMES=(); MODULE_CATEGORIES=(); MODULE_SCANNED=()
  MODULE_FREED=(); MODULE_STATUS=(); MODULE_PROJECTED=(); MODULE_ITEMS=()
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()
}

teardown() {
  protect::claim_release
  [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# tmutil always prints a header; only the com.apple.TimeMachine.* lines are real.
_stub_snapshots() {
  tmutil() {
    case "$1" in
      listlocalsnapshots)
        echo "Snapshots for disk /:"
        echo "com.apple.TimeMachine.2026-08-19-101500.local"
        echo "com.apple.TimeMachine.2026-08-20-093000.local"
        ;;
      deletelocalsnapshots) touch "$TEST_HOME/deleted" ;;
    esac
    return 0
  }
}

_stub_no_snapshots() {
  tmutil() {
    case "$1" in
      listlocalsnapshots) echo "Snapshots for disk /:" ;;
      deletelocalsnapshots) touch "$TEST_HOME/deleted" ;;
    esac
    return 0
  }
}

@test "snapshots: existing snapshots are reported, not announced as clean" {
  _stub_snapshots
  snapshots::clean >/dev/null 2>&1

  [ "${MODULE_STATUS[0]}" != "clean" ]
  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_LABELS[0]}" == *"2 local Time Machine snapshot"* ]]
  [[ "${ACTION_COMMANDS[0]}" == *"--snapshots"* ]]
}

@test "snapshots: the header alone is not mistaken for a snapshot" {
  _stub_no_snapshots
  run snapshots::clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"No local snapshots found"* ]]

  snapshots::clean >/dev/null 2>&1
  [ "${MODULE_STATUS[0]}" = "clean" ]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

@test "snapshots: a preview does not run the deletion" {
  _stub_snapshots
  DRY_RUN=true

  run snapshots::clean
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/deleted" ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "snapshots: a live run does delete them" {
  _stub_snapshots
  DRY_RUN=false

  snapshots::clean >/dev/null 2>&1
  [ -e "$TEST_HOME/deleted" ]
}

@test "snapshots: each identifier is listed with its timestamp" {
  _stub_snapshots
  run snapshots::list
  [[ "$output" == *"2026-08-19-101500"* ]]
  [[ "$output" == *"2026-08-20-093000"* ]]
  [[ "$output" != *"Snapshots for disk"* ]]
}

@test "snapshots: a missing tmutil is reported as unavailable, not clean" {
  # Stub the requirement check rather than emptying PATH, which would take rm
  # and date with it.
  utils::require() { return 1; }

  snapshots::clean >/dev/null 2>&1
  [ "${MODULE_STATUS[0]}" = "skipped" ]
}
