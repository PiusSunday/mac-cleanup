#!/usr/bin/env bats
# tests/test_utils.bats — Unit tests for utility functions

setup() {
  # Use a temporary log file to avoid writing to the real user's HOME
  TEST_LOG_DIR=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-test.XXXXXX")
  export LOG_FILE="${TEST_LOG_DIR}/cleanup.log"

  # Source required files
  source "${BATS_TEST_DIRNAME}/../lib/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/utils.sh"
}

teardown() {
  # Clean up temporary log directory after each test
  if [ -n "${TEST_LOG_DIR:-}" ] && [ -d "$TEST_LOG_DIR" ]; then
    rm -rf "$TEST_LOG_DIR"
  fi
}

# ── format_bytes ──────────────────────────────────────────────────────────────

@test "format_bytes: returns GB for values >= 1 GB" {
  result=$(utils::format_bytes 2147483648)
  [ "$result" = "2.0 GB" ]
}

@test "format_bytes: returns MB for values >= 1 MB" {
  result=$(utils::format_bytes 10485760)
  [ "$result" = "10.0 MB" ]
}

@test "format_bytes: returns KB for values >= 1 KB" {
  result=$(utils::format_bytes 2048)
  [ "$result" = "2 KB" ]
}

@test "format_bytes: returns B for values < 1 KB" {
  result=$(utils::format_bytes 512)
  [ "$result" = "512 B" ]
}

# ── dry_run_or_exec ───────────────────────────────────────────────────────────

@test "dry_run_or_exec: does not execute command when DRY_RUN=true" {
  DRY_RUN=true
  VERBOSE=false
  test_file="${BATS_TEST_TMPDIR}/dry_run_should_not_create"
  [ ! -e "$test_file" ]
  run dry_run_or_exec touch "$test_file"
  [ "$status" -eq 0 ]
  [ ! -e "$test_file" ]
}

@test "dry_run_or_exec: executes command when DRY_RUN=false" {
  DRY_RUN=false
  VERBOSE=false
  local test_file="${BATS_TEST_TMPDIR}/exec_test_file"
  run dry_run_or_exec touch "$test_file"
  [ "$status" -eq 0 ]
  [ -e "$test_file" ]
}

@test "dry_run_or_exec: shows DRY-RUN message when DRY_RUN=true" {
  DRY_RUN=true
  VERBOSE=false
  run dry_run_or_exec rm -rf /some/path
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

# ── safe_rm ─────────────────────────────────────────────────────────────────

@test "safe_rm: rejects relative paths" {
  DRY_RUN=true
  run safe_rm "relative/path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"relative path rejected"* ]]
}

@test "safe_rm: dry-run does not delete and updates TOTAL_DRYRUN_BYTES" {
  DRY_RUN=true
  TOTAL_DRYRUN_BYTES=0
  local target_dir="${BATS_TEST_TMPDIR}/safe_rm_dry_dir"
  mkdir -p "$target_dir"
  echo "payload" > "$target_dir/file.txt"

  safe_rm "$target_dir" "test dir"
  [ -d "$target_dir" ]
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "safe_rm: live mode deletes target and updates TOTAL_FREED" {
  DRY_RUN=false
  TOTAL_FREED=0
  local target_dir="${BATS_TEST_TMPDIR}/safe_rm_live_dir"
  mkdir -p "$target_dir"
  echo "payload" > "$target_dir/file.txt"

  safe_rm "$target_dir" "live dir"
  [ ! -e "$target_dir" ]
  [ "$TOTAL_FREED" -gt 0 ]
}

# ── utils::require ────────────────────────────────────────────────────────────

@test "utils::require: returns 0 for existing command" {
  run utils::require bash
  [ "$status" -eq 0 ]
}

@test "utils::require: returns 1 for non-existent command" {
  run utils::require __nonexistent_cmd_xyz__
  [ "$status" -eq 1 ]
}

# ── utils::get_size_bytes ─────────────────────────────────────────────────────

@test "utils::get_size_bytes: returns 0 for non-existent path" {
  result=$(utils::get_size_bytes "/tmp/__nonexistent_path_xyz__")
  [ "$result" -eq 0 ]
}

@test "utils::get_size_bytes: returns positive number for existing directory" {
  test_dir="${BATS_TEST_TMPDIR:-/tmp}/notempty"
  mkdir -p "$test_dir"
  echo "test content" > "$test_dir/file"
  result=$(utils::get_size_bytes "$test_dir")
  [ "$result" -gt 0 ]
}

# ── utils::confirm ────────────────────────────────────────────────────────────

@test "utils::confirm: returns 0 immediately when SKIP_CONFIRM=true" {
  SKIP_CONFIRM=true
  run utils::confirm "Are you sure?"
  [ "$status" -eq 0 ]
}

# ── utils::register_module ────────────────────────────────────────────────────

@test "utils::register_module: stores module data in arrays" {
  # Reset arrays
  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_SCANNED=()
  MODULE_FREED=()
  MODULE_STATUS=()

  utils::register_module "TestModule" "System" "1024" "512" "clean"

  [ "${#MODULE_NAMES[@]}" -eq 1 ]
  [ "${MODULE_NAMES[0]}" = "TestModule" ]
  [ "${MODULE_CATEGORIES[0]}" = "System" ]
  [ "${MODULE_SCANNED[0]}" = "1024" ]
  [ "${MODULE_FREED[0]}" = "512" ]
  [ "${MODULE_STATUS[0]}" = "clean" ]
}

@test "utils::register_module: appends multiple modules" {
  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_SCANNED=()
  MODULE_FREED=()
  MODULE_STATUS=()

  utils::register_module "Xcode" "Developer Tools" "100" "50" "clean"
  utils::register_module "Docker" "Developer Tools" "200" "100" "skipped"

  [ "${#MODULE_NAMES[@]}" -eq 2 ]
  [ "${MODULE_NAMES[0]}" = "Xcode" ]
  [ "${MODULE_NAMES[1]}" = "Docker" ]
  [ "${MODULE_CATEGORIES[1]}" = "Developer Tools" ]
  [ "${MODULE_SCANNED[1]}" = "200" ]
  [ "${MODULE_FREED[1]}" = "100" ]
  [ "${MODULE_STATUS[1]}" = "skipped" ]
}

# ── Terminal-aware colors ─────────────────────────────────────────────────────

@test "colors are empty when stdout is not a TTY" {
  # BATS runs in a non-TTY context, so colors should be empty
  [ -z "$RED" ]
  [ -z "$GREEN" ]
  [ -z "$BOLD" ]
  [ -z "$RESET" ]
}

# ── utils::with_spinner ──────────────────────────────────────────────────────

@test "utils::with_spinner: non-TTY fallback runs command and returns success" {
  run utils::with_spinner "Testing echo" echo "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Testing echo"* ]]
}

@test "utils::with_spinner: non-TTY propagates failure exit code" {
  run utils::with_spinner "Failing command" false
  [ "$status" -ne 0 ]
  [[ "$output" == *"command failed"* ]]
}

@test "utils::with_spinner: non-TTY executes the actual command" {
  local marker_file="${BATS_TEST_TMPDIR}/spinner_marker"
  run utils::with_spinner "Creating marker" touch "$marker_file"
  [ "$status" -eq 0 ]
  [ -f "$marker_file" ]
}

# ── utils::with_spinner TTY path (via pseudo-TTY) ────────────────────────────

@test "utils::with_spinner: TTY path propagates success exit code" {
  local wrapper="${BATS_TEST_TMPDIR}/tty_success.sh"
  cat > "$wrapper" <<'SCRIPT'
#!/usr/bin/env bash
source "${1}/lib/core.sh"
source "${1}/lib/utils.sh"
utils::with_spinner "TTY success test" true
SCRIPT
  chmod +x "$wrapper"
  local project_root="${BATS_TEST_DIRNAME}/.."
  # Use python3 pty module for macOS-compatible pseudo-TTY.
  # pty.spawn returns raw waitpid status; decode with os.WEXITSTATUS.
  run python3 -c "
import pty, os, sys
status = pty.spawn(['bash', '$wrapper', '$project_root'])
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
"
  [ "$status" -eq 0 ]
}

@test "utils::with_spinner: TTY path propagates failure exit code and shows stderr" {
  local wrapper="${BATS_TEST_TMPDIR}/tty_fail.sh"
  cat > "$wrapper" <<'SCRIPT'
#!/usr/bin/env bash
source "${1}/lib/core.sh"
source "${1}/lib/utils.sh"
utils::with_spinner "TTY fail test" bash -c 'echo "oops" >&2; exit 42'
SCRIPT
  chmod +x "$wrapper"
  local project_root="${BATS_TEST_DIRNAME}/.."
  run python3 -c "
import pty, os, sys
status = pty.spawn(['bash', '$wrapper', '$project_root'])
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
"
  [ "$status" -ne 0 ]
  [[ "$output" == *"oops"* ]] || [[ "$output" == *"command failed"* ]]
}


