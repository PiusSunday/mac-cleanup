#!/usr/bin/env bats
# tests/test_system_deep.bats — Unit tests for lib/system_deep.sh

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/system-deep-home.XXXXXX")"
  export HOME="$TEST_HOME"

  mkdir -p "$HOME/Library/Preferences"
  mkdir -p "$HOME/Library/Caches/com.apple.Safari/fsCachedData"

  source "$BATS_TEST_DIRNAME/../lib/core/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/utils.sh"
  source "$BATS_TEST_DIRNAME/../lib/modules/system/deep.sh"

  DRY_RUN=false
  SKIP_CONFIRM=true
  VERBOSE=false
  LOG_FILE="/dev/null"
  TOTAL_FREED=0
  TOTAL_DRYRUN_BYTES=0
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "system_deep::_broken_preferences: removes invalid non-Apple plist" {
  local plist="$HOME/Library/Preferences/com.example.bad.plist"
  echo "not plist content" > "$plist"

  run system_deep::_broken_preferences
  [ "$status" -eq 0 ]
  [ ! -e "$plist" ]
}

@test "system_deep::_safari_content_cache: dry-run reports and preserves cache" {
  local cache_file="$HOME/Library/Caches/com.apple.Safari/fsCachedData/blob.cache"
  echo "cache" > "$cache_file"

  DRY_RUN=true
  TOTAL_DRYRUN_BYTES=0
  _SYSTEM_DEEP_TOTAL=0

  system_deep::_safari_content_cache > /dev/null 2>&1
  [ -e "$cache_file" ]
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}
