#!/usr/bin/env bats
# tests/test_devtools.bats — Unit tests for lib/devtools.sh

setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/utils.sh"
  source "$BATS_TEST_DIRNAME/../lib/modules/dev/devtools.sh"
  DRY_RUN=true
  VERBOSE=false
  SKIP_CONFIRM=true
  LOG_FILE="/dev/null"
  export TMPDIR="${BATS_TEST_TMPDIR}"
}

# ── node_modules ──────────────────────────────────────────────────────────────

@test "devtools::_node_modules: detects orphaned node_modules (no package.json)" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_orphan"
  mkdir -p "$HOME/Developer/orphan/node_modules"
  echo "module data" > "$HOME/Developer/orphan/node_modules/testfile"
  # No package.json — this is orphaned
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  DEVTOOLS_EXCLUDE_PATHS=()

  _DEV_NODE_TOTAL=0
  devtools::_node_modules > /dev/null 2>&1

  export HOME="$old_home"
  [ "$_DEV_NODE_TOTAL" -gt 0 ]
}

@test "devtools::_node_modules: does not count active node_modules" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_active"
  mkdir -p "$HOME/Developer/active/node_modules"
  echo '{"name":"test"}' > "$HOME/Developer/active/package.json"
  echo "module data" > "$HOME/Developer/active/node_modules/testfile"
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")

  _DEV_NODE_TOTAL=0
  run devtools::_node_modules

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  # Active node_modules should NOT be in total reclaimable
  [ "$_DEV_NODE_TOTAL" -eq 0 ]
}

@test "devtools::_node_modules: reports none when no node_modules exist" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_empty_nm"
  mkdir -p "$HOME/Developer"
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")

  _DEV_NODE_TOTAL=0
  run devtools::_node_modules

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"none found"* ]]
}

# ── Rust targets ──────────────────────────────────────────────────────────────

@test "devtools::_rust_targets: skips when cargo not installed" {
  # Override command check
  command() { return 1; }
  export -f command

  _DEV_RUST_TOTAL=0
  run devtools::_rust_targets

  unset -f command
  [ "$status" -eq 0 ]
  [ "$_DEV_RUST_TOTAL" -eq 0 ]
}

@test "devtools::_rust_targets: skips target/ without Cargo.toml" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_rust_no_cargo"
  mkdir -p "$HOME/Developer/fake_rust/target"
  echo "build data" > "$HOME/Developer/fake_rust/target/testfile"
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  # No Cargo.toml — should be skipped

  _DEV_RUST_TOTAL=0
  run devtools::_rust_targets

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [ "$_DEV_RUST_TOTAL" -eq 0 ]
}

# ── Python __pycache__ ────────────────────────────────────────────────────────

@test "devtools::_python_cache: detects __pycache__ directories" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_python"
  mkdir -p "$HOME/Developer/pyapp/__pycache__"
  echo "bytecode" > "$HOME/Developer/pyapp/__pycache__/module.pyc"
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  PYCACHE_EXCLUDE_PATHS=()

  _DEV_PYTHON_TOTAL=0
  devtools::_python_cache > /dev/null 2>&1

  export HOME="$old_home"
  (( _DEV_PYTHON_TOTAL > 0 ))
}

@test "devtools::_python_cache: reports none when no __pycache__ exists" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_no_python"
  mkdir -p "$HOME/Developer"
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  PYCACHE_EXCLUDE_PATHS=()

  _DEV_PYTHON_TOTAL=0
  run devtools::_python_cache

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"none found"* ]]
}

# ── Gradle cache ──────────────────────────────────────────────────────────────

@test "devtools::_gradle_cache: skips when .gradle/caches doesn't exist" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_no_gradle"
  mkdir -p "$HOME"

  _DEV_GRADLE_TOTAL=0
  run devtools::_gradle_cache

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "devtools::_gradle_cache: detects gradle cache" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_gradle"
  mkdir -p "$HOME/.gradle/caches"
  echo "cache data" > "$HOME/.gradle/caches/testfile"

  _DEV_GRADLE_TOTAL=0
  devtools::_gradle_cache > /dev/null 2>&1

  export HOME="$old_home"
  (( _DEV_GRADLE_TOTAL > 0 ))
}

# ── Module registration ───────────────────────────────────────────────────────

@test "devtools::clean: registers module with category 'Developer Tools'" {
  # Override sub-functions to no-ops
  devtools::_node_modules() { _DEV_NODE_TOTAL=0; }
  devtools::_rust_targets() { _DEV_RUST_TOTAL=0; }
  devtools::_python_cache() { _DEV_PYTHON_TOTAL=0; }
  devtools::_gradle_cache() { _DEV_GRADLE_TOTAL=0; }
  devtools::_flutter() { _DEV_FLUTTER_TOTAL=0; }
  utils::get_free_bytes() { echo 100000; }

  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_SCANNED=()
  MODULE_FREED=()
  MODULE_STATUS=()

  devtools::clean > /dev/null 2>&1

  [ "${MODULE_NAMES[0]}" = "Dev Artifacts" ]
  [ "${MODULE_CATEGORIES[0]}" = "Developer Tools" ]
}
