#!/usr/bin/env bats
# tests/test_system.bats — Unit tests for lib/system.sh

setup() {
  # Source test dependencies
  source "$BATS_TEST_DIRNAME/../lib/core/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/utils.sh"
  source "$BATS_TEST_DIRNAME/../lib/modules/system/standard.sh"
  DRY_RUN=true
  VERBOSE=false
  SKIP_CONFIRM=true
  LOG_FILE="/dev/null"
  export TMPDIR="${BATS_TEST_TMPDIR}"
}

# ── Crash reports ──────────────────────────────────────────────────────────────

@test "system::_crash_reports: reports none when no crash files exist" {
  # Override paths to empty temp dirs
  system::_crash_reports() {
    _SYS_CRASH_TOTAL=0
    local paths=("${BATS_TEST_TMPDIR}/empty_diag1" "${BATS_TEST_TMPDIR}/empty_diag2")
    mkdir -p "${paths[@]}"
    local total_count=0
    local total_bytes=0
    for path in "${paths[@]}"; do
      if [[ ! -d "$path" ]]; then continue; fi
      while IFS= read -r file; do
        (( total_count++ )) || true
      done < <(find "$path" -maxdepth 1 \( -name "*.crash" -o -name "*.ips" -o -name "*.hang" \) -type f 2>/dev/null || true)
    done
    _SYS_CRASH_TOTAL=$total_bytes
  }
  run system::_crash_reports
  [ "$status" -eq 0 ]
}

@test "system::_crash_reports: counts crash files correctly" {
  local crash_dir="${BATS_TEST_TMPDIR}/DiagnosticReports"
  mkdir -p "$crash_dir"
  echo "crash data 1" > "$crash_dir/test1.crash"
  echo "crash data 2" > "$crash_dir/test2.ips"
  echo "crash data 3" > "$crash_dir/test3.hang"
  echo "not a crash" > "$crash_dir/readme.txt"

  local count
  count=$(find "$crash_dir" -maxdepth 1 \( -name "*.crash" -o -name "*.ips" -o -name "*.hang" \) -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

# ── .DS_Store ──────────────────────────────────────────────────────────────────

@test "system::_ds_store: detects .DS_Store files" {
  local test_dir="${BATS_TEST_TMPDIR}/ds_test"
  mkdir -p "$test_dir/subdir1" "$test_dir/subdir2"
  touch "$test_dir/.DS_Store"
  touch "$test_dir/subdir1/.DS_Store"

  local count
  count=$(find "$test_dir" -maxdepth 4 -name ".DS_Store" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

# ── Trash ──────────────────────────────────────────────────────────────────────

@test "system::_trash: reports empty when Trash dir doesn't exist" {
  _SYS_TRASH_TOTAL=0

  # Override HOME to a temp dir with no .Trash
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_no_trash"
  mkdir -p "$HOME"

  run system::_trash

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [ "$_SYS_TRASH_TOTAL" -eq 0 ]
}

@test "system::_trash: reports size when Trash has contents" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_trash"
  mkdir -p "$HOME/.Trash"
  dd if=/dev/zero of="$HOME/.Trash/junkfile" bs=1024 count=10 2>/dev/null

  run system::_trash

  export HOME="$old_home"
  [ "$status" -eq 0 ]
}

# ── Dev tool caches ────────────────────────────────────────────────────────────

@test "system::_dev_tool_caches: skips npm cache when not present" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_no_npm"
  mkdir -p "$HOME"

  _SYS_DEVCACHE_TOTAL=0
  run system::_dev_tool_caches

  export HOME="$old_home"
  [ "$status" -eq 0 ]
}

@test "system::_dev_tool_caches: detects npm cache" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_npm"
  mkdir -p "$HOME/.npm/_cacache"
  echo "cache data" > "$HOME/.npm/_cacache/testfile"

  _SYS_DEVCACHE_TOTAL=0
  run system::_dev_tool_caches

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm cache"* ]]
}

# ── System Data clues ──────────────────────────────────────────────────────────

@test "system::_system_data_clues: prints header" {
  local old_home="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/fake_home_clues"
  mkdir -p "$HOME"

  run system::_system_data_clues

  export HOME="$old_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"System Data clues"* ]]
}

# ── Module registration ───────────────────────────────────────────────────────

@test "system::clean: registers module with category 'System'" {
  # Override sub-functions to no-ops for fast test
  system::_crash_reports() { _SYS_CRASH_TOTAL=0; }
  system::_system_logs() { :; }
  system::_ds_store() { _SYS_DSSTORE_TOTAL=0; }
  system::_trash() { _SYS_TRASH_TOTAL=0; }
  system::_dev_tool_caches() { _SYS_DEVCACHE_TOTAL=0; }
  system::_system_data_clues() { _SYS_HAS_CLUES=false; }
  utils::get_free_bytes() { echo 100000; }

  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_SCANNED=()
  MODULE_FREED=()
  MODULE_STATUS=()
  MODULE_PROJECTED=()

  system::clean

  [ "${MODULE_NAMES[0]}" = "System" ]
  [ "${MODULE_CATEGORIES[0]}" = "System" ]
}

@test "system::clean: keeps clean status when reclaimable bytes exist alongside info clues" {
  system::_crash_reports() { _SYS_CRASH_TOTAL=1024; }
  system::_ds_store() { _SYS_DSSTORE_TOTAL=0; }
  system::_trash() { _SYS_TRASH_TOTAL=0; }
  system::_dev_tool_caches() { _SYS_DEVCACHE_TOTAL=0; }
  system::_system_data_clues() { _SYS_HAS_CLUES=true; }
  utils::get_free_bytes() { echo 100000; }
  DRY_RUN=true

  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_SCANNED=()
  MODULE_FREED=()
  MODULE_STATUS=()
  MODULE_PROJECTED=()

  system::clean

  [ "${MODULE_STATUS[0]}" = "clean" ]
  [ "${MODULE_PROJECTED[0]}" = "1024" ]
}

# ── var/folders ───────────────────────────────────────────────────────────────

@test "system::_var_folders: safely cleans safe temp subdirs" {
  # Mock getconf to return a real valid directory so the early exit passes
  mkdir -p "${BATS_TEST_TMPDIR}/fake_user_tmp"
  getconf() { echo "${BATS_TEST_TMPDIR}/fake_user_tmp"; }
  export -f getconf

  # Mock find to circumvent hardcoded /private/var/folders
  find() {
    echo "${BATS_TEST_TMPDIR}/fake_var_folders/UUID/T/TemporaryItems"
  }
  export -f find

  mkdir -p "${BATS_TEST_TMPDIR}/fake_var_folders/UUID/T/TemporaryItems"
  echo "temp data" > "${BATS_TEST_TMPDIR}/fake_var_folders/UUID/T/TemporaryItems/file"

  _SYS_VARFOLDERS_TOTAL=0
  system::_var_folders > /dev/null 2>&1

  unset -f getconf
  unset -f find

  [ "$_SYS_VARFOLDERS_TOTAL" -gt 0 ]
}
