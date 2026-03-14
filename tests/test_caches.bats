#!/usr/bin/env bats
# tests/test_caches.bats — Unit tests for caches module

setup() {
  TEST_HOME=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-home.XXXXXX")
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/user/standard.sh"
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
  fi
}

@test "caches::_user_caches: skips Homebrew cache handled by brew module" {
  mkdir -p "$HOME/Library/Caches/Homebrew"
  mkdir -p "$HOME/Library/Caches/RegularCache"
  echo "homebrew" > "$HOME/Library/Caches/Homebrew/file.txt"
  echo "regular" > "$HOME/Library/Caches/RegularCache/file.txt"

  safe_rm() { :; }
  utils::is_deletable() { return 0; }
  caches::_is_app_running() { return 1; }

  local expected_total
  expected_total=$(utils::get_size_bytes "$HOME/Library/Caches/RegularCache")

  caches::_user_caches

  [ "$_CACHES_USER_TOTAL" -eq "$expected_total" ]
}