#!/usr/bin/env bats
# tests/test_devtools.bats — Unit tests for lib/modules/dev/devtools.sh

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP"
  
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/dev/devtools.sh"

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

  export DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  export DEVTOOLS_EXCLUDE_PATHS=()
  export PYCACHE_EXCLUDE_PATHS=()
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "devtools::_node_modules: detects orphaned node_modules (no package.json)" {
  mkdir -p "$HOME/Developer/orphan/node_modules"
  echo "data" > "$HOME/Developer/orphan/node_modules/t1"

  _DEV_NODE_TOTAL=0
  devtools::_node_modules >/dev/null 2>&1
  [ "$_DEV_NODE_TOTAL" -gt 0 ]
}

@test "devtools::_node_modules: does not count active node_modules" {
  mkdir -p "$HOME/Developer/active/node_modules"
  echo "{}" > "$HOME/Developer/active/package.json"
  echo "data" > "$HOME/Developer/active/node_modules/t1"

  _DEV_NODE_TOTAL=0
  devtools::_node_modules >/dev/null 2>&1
  [ "$_DEV_NODE_TOTAL" -eq 0 ]
}

@test "devtools::_rust_targets: skips target/ without Cargo.toml" {
  if ! command -v cargo &>/dev/null; then skip "cargo not installed"; fi

  mkdir -p "$HOME/Developer/fake_rust/target"
  echo "data" > "$HOME/Developer/fake_rust/target/file"

  _DEV_RUST_TOTAL=0
  devtools::_rust_targets >/dev/null 2>&1
  [ "$_DEV_RUST_TOTAL" -eq 0 ]
}

@test "devtools::_rust_targets: detects target with Cargo.toml" {
  if ! command -v cargo &>/dev/null; then skip "cargo not installed"; fi

  mkdir -p "$HOME/Developer/real_rust/target"
  touch "$HOME/Developer/real_rust/Cargo.toml"
  echo "data" > "$HOME/Developer/real_rust/target/file"

  _DEV_RUST_TOTAL=0
  devtools::_rust_targets >/dev/null 2>&1
  [ "$_DEV_RUST_TOTAL" -gt 0 ]
}

@test "devtools::_python_cache: detects __pycache__ directories" {
  mkdir -p "$HOME/Developer/pyapp/__pycache__"
  echo "data" > "$HOME/Developer/pyapp/__pycache__/module.pyc"

  _DEV_PYTHON_TOTAL=0
  devtools::_python_cache >/dev/null 2>&1
  [ "$_DEV_PYTHON_TOTAL" -gt 0 ]
}

@test "devtools::_gradle_cache: detects gradle caches and daemon" {
  mkdir -p "$HOME/.gradle/caches/mock"
  echo "data" > "$HOME/.gradle/caches/mock/file"
  
  mkdir -p "$HOME/.gradle/daemon/7.0"
  echo "log" > "$HOME/.gradle/daemon/7.0/file"

  _DEV_GRADLE_TOTAL=0
  devtools::_gradle_cache >/dev/null 2>&1
  [ "$_DEV_GRADLE_TOTAL" -gt 0 ]
}

@test "devtools::_android: detects android sdk cache" {
  mkdir -p "$HOME/.android/cache"
  echo "data" > "$HOME/.android/cache/file"

  # Also add avd snapshots
  mkdir -p "$HOME/.android/avd/nexus5.avd/snapshots/default_boot"
  echo "snap" > "$HOME/.android/avd/nexus5.avd/snapshots/default_boot/snap.img"

  _DEV_ANDROID_TOTAL=0
  devtools::_android >/dev/null 2>&1
  [ "$_DEV_ANDROID_TOTAL" -gt 0 ]
}

@test "devtools::_vscode: detects vscode and cursor cache" {
  mkdir -p "$HOME/Library/Application Support/Code/logs/2023"
  echo "log" > "$HOME/Library/Application Support/Code/logs/2023/main.log"

  mkdir -p "$HOME/Library/Application Support/Cursor/Cache"
  echo "data" > "$HOME/Library/Application Support/Cursor/Cache/data.v"

  # Workspace storage stale
  mkdir -p "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1"
  echo "data" > "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1/state.json"
  # Touch it to be older than 30 days securely using touch
  touch -t 202001010101 "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1/state.json"
  touch -t 202001010101 "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1"

  _DEV_VSCODE_TOTAL=0
  devtools::_vscode >/dev/null 2>&1
  [ "$_DEV_VSCODE_TOTAL" -gt 0 ]
}

@test "devtools::_bun_tnpm: skips if not installed" {
  if command -v bun &>/dev/null; then skip "bun is installed natively"; fi
  
  _DEV_BUNTNPM_TOTAL=0
  devtools::_bun_tnpm >/dev/null 2>&1
  [ "$_DEV_BUNTNPM_TOTAL" -eq 0 ]
}

@test "devtools::clean: registers module properly" {
  # To avoid full disk scan, we just test that calling devtools::clean adds the module to report arrays
  # We do not mock. We will just let it run on our small $TEST_TMP environment
  devtools::clean >/dev/null 2>&1
  [[ "${MODULE_NAMES[0]}" == "Dev Artifacts" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "Developer Tools" ]]
}
