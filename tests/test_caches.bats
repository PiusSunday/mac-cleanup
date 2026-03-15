#!/usr/bin/env bats
# tests/test_caches.bats — Unit tests for caches module

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP"
  
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/user/standard.sh"

  export DRY_RUN=true
  export SKIP_CONFIRM=true
  export VERBOSE=false
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "caches::_app_support_caches: detects expanded patterns" {
  mkdir -p "$HOME/Library/Application Support/Foo/Cache"
  echo "d" > "$HOME/Library/Application Support/Foo/Cache/f"

  mkdir -p "$HOME/Library/Application Support/Foo/Logs"
  echo "d" > "$HOME/Library/Application Support/Foo/Logs/f"
  
  mkdir -p "$HOME/Library/Application Support/Foo/logs"
  echo "d" > "$HOME/Library/Application Support/Foo/logs/f"
  
  mkdir -p "$HOME/Library/Application Support/Foo/log"
  echo "d" > "$HOME/Library/Application Support/Foo/log/f"

  mkdir -p "$HOME/Library/Application Support/Foo/tmp"
  echo "d" > "$HOME/Library/Application Support/Foo/tmp/f"

  mkdir -p "$HOME/Library/Application Support/Foo/Temp"
  echo "d" > "$HOME/Library/Application Support/Foo/Temp/f"
  
  _CACHES_APPSUPPORT_TOTAL=0
  caches::_app_support_caches >/dev/null 2>&1
  
  # Ensure all 6 items were counted
  local expected_size
  expected_size=$(utils::get_size_bytes "$HOME/Library/Application Support")
  [ "$_CACHES_APPSUPPORT_TOTAL" -eq "$expected_size" ]
}

@test "caches::_app_support_caches: skips com.apple.* system packages" {
  mkdir -p "$HOME/Library/Application Support/com.apple.CloudDocs/Cache"
  echo "data" > "$HOME/Library/Application Support/com.apple.CloudDocs/Cache/f"

  _CACHES_APPSUPPORT_TOTAL=0
  caches::_app_support_caches >/dev/null 2>&1
  [ "$_CACHES_APPSUPPORT_TOTAL" -eq 0 ]
}

@test "caches::_user_caches: handles actual directory contents without mocking" {
  mkdir -p "$HOME/Library/Caches/com.test.app"
  echo "cache content" > "$HOME/Library/Caches/com.test.app/cache_file"
  
  _CACHES_USER_TOTAL=0
  caches::_user_caches >/dev/null 2>&1
  [ "$_CACHES_USER_TOTAL" -gt 0 ]
}