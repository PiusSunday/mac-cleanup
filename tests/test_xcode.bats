#!/usr/bin/env bats
# tests/test_xcode.bats — Unit tests for Xcode module

setup() {
  # Use a temporary directory as fake home
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Use a temporary log file to avoid writing to the real user's HOME
  export LOG_FILE="${TEST_HOME}/.mac-cleanup/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/dev/xcode.sh"

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

@test "xcode::_derived_data: lists the path with its size and leaves it in place" {
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/TestApp"
  echo "fake data" > "$HOME/Library/Developer/Xcode/DerivedData/TestApp/build.log"
  DRY_RUN=true
  run xcode::_derived_data
  [ "$status" -eq 0 ]
  # One line per path, "<size>  <label>" — the old output repeated every path
  # as both a module line and a separate "[DRY-RUN] ..." line.
  [[ "$output" == *"KB"*"Xcode DerivedData"* ]]
  [ -d "$HOME/Library/Developer/Xcode/DerivedData/TestApp" ]
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

# ── Simulator runtimes and their devices ──────────────────────────────────────
# Deleting a superseded runtime orphans every device bound to it. v0.5.0 ran
# `simctl delete unavailable` before any runtime was deleted and again straight
# after — and since deletion is asynchronous, neither call ever found an
# orphaned device. The ~9.4 GB of devices on the development machine was
# reported as an aside and never reclaimed.

# Two iOS runtimes: 26.5 is current, 26.4 is superseded.
_fake_runtime_table() {
  cat <<'TABLE'
AAAA-0001|Ready|8000000000|26.5|iphonesimulator|com.apple.CoreSimulator.SimRuntime.iOS-26-5
AAAA-0002|Ready|7000000000|26.4|iphonesimulator|com.apple.CoreSimulator.SimRuntime.iOS-26-4
TABLE
}

_make_device() {
  local id="$1" runtime="$2" kb="$3"
  local dir="$HOME/Library/Developer/CoreSimulator/Devices/$id"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/data" bs=1024 count="$kb" 2>/dev/null
  cat > "$dir/device.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>runtime</key>
  <string>$runtime</string>
</dict>
</plist>
EOF
}

@test "xcode: devices bound to a superseded runtime are counted, current ones are not" {
  _make_device DEV-OLD com.apple.CoreSimulator.SimRuntime.iOS-26-4 512
  _make_device DEV-NEW com.apple.CoreSimulator.SimRuntime.iOS-26-5 512

  _XCODE_SUPERSEDED_RUNTIME_IDS=$'com.apple.CoreSimulator.SimRuntime.iOS-26-4\n'
  run xcode::_devices_bound_to_deleted_runtimes
  [ "$status" -eq 0 ]
  # Only the device on the superseded runtime, so well under both devices' size.
  [ "$output" -gt 0 ]
  [ "$output" -lt 1048576 ]
}

@test "xcode: no superseded runtimes means no devices are claimed" {
  _make_device DEV-NEW com.apple.CoreSimulator.SimRuntime.iOS-26-5 512
  _XCODE_SUPERSEDED_RUNTIME_IDS=""
  run xcode::_devices_bound_to_deleted_runtimes
  [ "$output" = "0" ]
}

@test "xcode: a runtime identifier shared with a kept runtime is not treated as superseded" {
  # 26.4 and 26.4.1 both report com.apple.CoreSimulator.SimRuntime.iOS-26-4.
  # If the kept runtime shares the identifier, its devices must not be counted.
  xcode::_runtime_table() {
    cat <<'TABLE'
AAAA-0001|Ready|8000000000|26.4.1|iphonesimulator|com.apple.CoreSimulator.SimRuntime.iOS-26-4
AAAA-0002|Ready|7000000000|26.4|iphonesimulator|com.apple.CoreSimulator.SimRuntime.iOS-26-4
TABLE
  }
  xcrun() { return 0; }
  TARGET_SIMULATORS=false
  DRY_RUN=true
  _XCODE_SUPERSEDED_RUNTIME_IDS=""

  run xcode::_simulator_runtimes
  [ "$status" -eq 0 ]
  # 26.4 is superseded by 26.4.1, but they share an identifier, so nothing is
  # recorded that would let the device matcher claim the kept runtime's devices.
  xcode::_simulator_runtimes >/dev/null 2>&1
  [ -z "$_XCODE_SUPERSEDED_RUNTIME_IDS" ]
}

@test "xcode: the advertised simulator figure includes the orphaned devices" {
  _make_device DEV-OLD com.apple.CoreSimulator.SimRuntime.iOS-26-4 2048

  xcode::_runtime_table() { _fake_runtime_table; }
  xcrun() { return 0; }
  TARGET_SIMULATORS=false
  DRY_RUN=true
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  xcode::_simulator_runtimes >/dev/null 2>&1

  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_LABELS[0]}" == *"devices bound to them"* ]]
  # Strictly more than the 7 GB runtime alone.
  [ "${ACTION_BYTES[0]}" -gt 7000000000 ]
  [[ "${ACTION_COMMANDS[0]}" == *"--simulators"* ]]
}

@test "xcode: waiting for runtime deletion gives up rather than hanging" {
  # simctl reports the runtime as still present forever; the wait must be bounded.
  xcrun() { echo '{"AAAA-0002": {}}'; return 0; }
  _XCODE_DELETED_RUNTIME_IDS=$'AAAA-0002\n'
  MAC_CLEANUP_RUNTIME_WAIT=3

  local start elapsed
  start=$(date +%s)
  run xcode::_await_runtime_deletion
  elapsed=$(( $(date +%s) - start ))

  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 15 ]
}

@test "xcode: waiting returns immediately when nothing was deleted" {
  _XCODE_DELETED_RUNTIME_IDS=""
  run xcode::_await_runtime_deletion
  [ "$status" -eq 0 ]
}
