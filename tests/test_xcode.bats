#!/usr/bin/env bats
# tests/test_xcode.bats — Unit tests for Xcode module

setup() {
  # Use a temporary directory as fake home
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Use a temporary log file to avoid writing to the real user's HOME
  export LOG_FILE="${TEST_HOME}/.mac-cleanup/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../lib/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/xcode.sh"

  # Default to dry-run and skip confirm
  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "xcode::clean: skips gracefully when xcodebuild is not available" {
  # Override PATH so xcodebuild is not found
  original_path="$PATH"
  export PATH=""
  run xcode::clean
  export PATH="$original_path"
  [ "$status" -eq 0 ]
}

@test "xcode::_derived_data: skips when DerivedData does not exist" {
  run xcode::_derived_data
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "xcode::_derived_data: reports size and dry-run message when path exists" {
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/TestApp"
  echo "fake data" > "$HOME/Library/Developer/Xcode/DerivedData/TestApp/build.log"
  DRY_RUN=true
  run xcode::_derived_data
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "xcode::_archives: skips when Archives does not exist" {
  run xcode::_archives
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "xcode::_device_support: skips when iOS DeviceSupport does not exist" {
  run xcode::_device_support
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "xcode::_simulator_caches: skips when Simulator caches do not exist" {
  run xcode::_simulator_caches
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "xcode::_documentation_cache: dry-run reports and preserves docs cache" {
  mkdir -p "$HOME/Library/Developer/Xcode/DocumentationCache"
  echo "doc cache" > "$HOME/Library/Developer/Xcode/DocumentationCache/index.db"

  DRY_RUN=true
  run xcode::_documentation_cache
  [ "$status" -eq 0 ]
  [ -d "$HOME/Library/Developer/Xcode/DocumentationCache" ]
}
