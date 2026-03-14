#!/usr/bin/env bats
# tests/test_orphans.bats — Unit tests for lib/orphans.sh

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/orphans-home.XXXXXX")"
  export HOME="$TEST_HOME"

  mkdir -p "$HOME/Library/Application Support"
  mkdir -p "$HOME/Library/Containers"
  mkdir -p "$HOME/Library/Preferences"

  source "$BATS_TEST_DIRNAME/../lib/core/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/utils.sh"
  source "$BATS_TEST_DIRNAME/../lib/modules/system/orphans.sh"

  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
  LOG_FILE="/dev/null"
  CLEAN_ORPHANS=false
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "orphans::clean: detects stale orphan candidate in Application Support" {
  local orphan_dir="$HOME/Library/Application Support/zzzzorphanapp"
  mkdir -p "$orphan_dir"
  echo "payload" > "$orphan_dir/data.bin"
  touch -t 202001010101 "$orphan_dir"

  orphans::clean > /dev/null 2>&1
  [ "${#ORPHAN_CANDIDATES[@]}" -ge 1 ]
}

@test "orphans::clean: deletes candidates only when CLEAN_ORPHANS=true" {
  local orphan_dir="$HOME/Library/Application Support/zzzzdeletecandidate"
  mkdir -p "$orphan_dir"
  echo "payload" > "$orphan_dir/data.bin"
  touch -t 202001010101 "$orphan_dir"

  DRY_RUN=false
  CLEAN_ORPHANS=true

  run orphans::clean
  [ "$status" -eq 0 ]
  [ ! -e "$orphan_dir" ]
}
