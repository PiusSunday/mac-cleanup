#!/usr/bin/env bats
# tests/test_preflight.bats — Unit tests for lib/preflight.sh

setup() {
  source "$BATS_TEST_DIRNAME/../lib/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/utils.sh"
  source "$BATS_TEST_DIRNAME/../lib/preflight.sh"

  DRY_RUN=false
  SKIP_CONFIRM=true
  VERBOSE=false
  LOG_FILE="/dev/null"
}

teardown() {
  unset -f tmutil 2>/dev/null || true
  unset -f pmset 2>/dev/null || true
  unset -f csrutil 2>/dev/null || true
  unset -f utils::get_free_bytes 2>/dev/null || true
}

@test "preflight::_disk_space: warns on low disk" {
  utils::get_free_bytes() { echo $((4 * 1024 * 1024 * 1024)); }
  run preflight::_disk_space
  [ "$status" -eq 0 ]
  [[ "$output" == *"Low disk space"* ]]
}

@test "preflight::_time_machine: warns when backup is running" {
  tmutil() {
    if [[ "$1" == "status" ]]; then
      echo '"Running" = 1'
      return 0
    fi
    return 0
  }
  export -f tmutil

  run preflight::_time_machine
  [ "$status" -eq 0 ]
  [[ "$output" == *"Time Machine backup is currently running"* ]]
}

@test "preflight::_battery: warns on low battery without AC" {
  pmset() {
    if [[ "$1" == "-g" && "$2" == "batt" ]]; then
      echo "Now drawing from 'Battery Power'"
      echo " -InternalBattery-0 (id=1234567)    12%; discharging;"
      return 0
    fi
    return 0
  }
  export -f pmset

  run preflight::_battery
  [ "$status" -eq 0 ]
  [[ "$output" == *"Battery is low"* ]]
}

@test "preflight::_sip_status: reports SIP enabled" {
  csrutil() {
    if [[ "$1" == "status" ]]; then
      echo "System Integrity Protection status: enabled."
      return 0
    fi
    return 0
  }
  export -f csrutil

  run preflight::_sip_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIP: enabled"* ]]
}
