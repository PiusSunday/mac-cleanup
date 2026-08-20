#!/usr/bin/env bats
# tests/test_browsers.bats — Unit tests for lib/modules/user/browsers.sh

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP"
  
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/user/browsers.sh"

  export DRY_RUN=true
  export SKIP_CONFIRM=true
  export VERBOSE=false

  # Clean tracking arrays
  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_STATUS=()
  MODULE_FREED=()
  MODULE_SCANNED=()
  MODULE_PROJECTED=()
  _BROWSERS_TOTAL=0
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "safari_is_not_in_browser_list" {
  # grep the source file to ensure NO reference to com.apple.Safari exists as a target
  run grep "com.apple.Safari" "${BATS_TEST_DIRNAME}/../lib/modules/user/browsers.sh"
  [ "$status" -ne 0 ]
}

@test "arc_detects_its_application_support_caches" {
  # ~/Library/Caches/company.thebrowser.Browser is deliberately absent: it
  # belongs to caches::_user_caches, which owns everything under
  # ~/Library/Caches. Claiming it here too is what double-counted those bytes.
  mkdir -p "$HOME/Library/Application Support/Arc/User Data/Default/Cache/Cache_Data"
  mkdir -p "$HOME/Library/Application Support/Arc/User Data/Default/GPUCache"
  mkdir -p "$HOME/Library/Application Support/Arc/User Data/Default/Code Cache"
  mkdir -p "$HOME/Library/Application Support/Arc/User Data/ShaderCache"
  
  # Add some bytes to each
  echo "test" > "$HOME/Library/Application Support/Arc/User Data/Default/Cache/Cache_Data/f2"
  echo "test" > "$HOME/Library/Application Support/Arc/User Data/Default/GPUCache/f3"
  echo "test" > "$HOME/Library/Application Support/Arc/User Data/Default/Code Cache/f4"
  echo "test" > "$HOME/Library/Application Support/Arc/User Data/ShaderCache/f5"

  browsers::_arc >/dev/null 2>&1

  # Ensure total is greater than 0
  [ "$_BROWSERS_TOTAL" -gt 0 ]
}

@test "arc: the browser module no longer claims the shared user-cache path" {
  # Regression guard for the overlap removed in v0.5.0. Comments may still
  # explain the path, so only executable lines are checked.
  run bash -c "grep -v '^[[:space:]]*#' '$BATS_TEST_DIRNAME/../lib/modules/user/browsers.sh' \
    | grep -c 'Library/Caches/company.thebrowser.Browser'"
  [ "$output" = "0" ]
}

@test "browser_skip_does_not_crash_module" {
  mkdir -p "$HOME/Library/Safari/Favicon Cache"
  echo "locked" > "$HOME/Library/Safari/Favicon Cache/file"
  # Make it unwritable so rm -rf would fail in live mode
  chmod -w "$HOME/Library/Safari/Favicon Cache"
  
  export DRY_RUN=false
  # Let's run the function and assert it exits 0
  browsers::_safari_icons >/dev/null 2>&1
  local ret=$?
  
  # Restore permissions so teardown can rm -rf it properly
  chmod +w "$HOME/Library/Safari/Favicon Cache"
  
  # In safe_rm, if rm fails, log::error happens but the script DOES NOT crash since it is handled
  [ "$ret" -eq 0 ]
}

@test "browsers::clean: registers module with category 'Caches & Logs'" {
  browsers::clean >/dev/null 2>&1
  [[ "${MODULE_NAMES[0]}" == "Browsers" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "Caches & Logs" ]]
}
