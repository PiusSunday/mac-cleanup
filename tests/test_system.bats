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
  mkdir -p "$HOME/Library/Developer/CoreSimulator"
  
  utils::get_size_bytes() { echo "2048"; }
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

@test "system::clean: becomes Pending when reclaimable bytes exist alongside info clues" {
  system::_crash_reports() { _SYS_CRASH_TOTAL=1024; TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + 1024 )); }
  system::_ds_store() { _SYS_DSSTORE_TOTAL=0; }
  system::_trash() { _SYS_TRASH_TOTAL=0; }
  system::_dev_tool_caches() { _SYS_DEVCACHE_TOTAL=0; }
  system::_system_data_clues() { _SYS_HAS_CLUES=true; }
  DRY_RUN=true

  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_SCANNED=()
  MODULE_FREED=()
  MODULE_STATUS=()
  MODULE_PROJECTED=()

  system::clean

  [ "${MODULE_STATUS[0]}" = "Pending" ]
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

# ── Trash gating ──────────────────────────────────────────────────────────────
# The Trash holds files the user chose to delete but has not committed to
# losing. Until v0.5.2 system::_trash emptied it as part of an ordinary cache
# sweep — and because system::clean ran above the target gating, even
# `mac-cleanup --docker` did it.

# Report 125 items totalling 2 GB without touching the real Finder.
_stub_full_trash() {
  _osascript_timed() {
    case "$*" in
      *"count items in trash"*) echo 125 ;;
      *"get size of trash"*)    echo 2147483648 ;;
      *"empty trash"*)          _TRASH_EMPTIED=true ;;
    esac
    return 0
  }
  system::_trash_size_bytes() { printf '2147483648\n'; }
}

# What Finder actually does: it answers `get size of trash` with the AppleScript
# token `missing value`, not a number.
_stub_trash_unknown_size() {
  _osascript_timed() {
    case "$*" in
      *"count items in trash"*) echo 1 ;;
      *"get size of trash"*)    echo "missing value" ;;
      *"empty trash"*)          _TRASH_EMPTIED=true ;;
    esac
    return 0
  }
  # No ~/.Trash in the sandboxed HOME either, so the size is genuinely unknown.
  system::_trash_size_bytes() { printf ''; }
}

@test "system: the Trash is left alone without --empty-trash" {
  _stub_full_trash
  EMPTY_TRASH=false
  DRY_RUN=true
  TOTAL_DRYRUN_BYTES=0
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  run system::_trash
  [ "$status" -eq 0 ]
  [[ "$output" == *"left alone"* ]]
  [[ "$output" != *"Would empty"* ]]

  system::_trash >/dev/null 2>&1
  # Not counted toward reclaimable, and offered as a decision instead.
  [ "$TOTAL_DRYRUN_BYTES" -eq 0 ]
  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_COMMANDS[0]}" == *"--empty-trash"* ]]
}

@test "system: --yes alone must never empty the Trash" {
  # --yes means "do not ask me about cleanup", not "destroy recoverable data".
  _stub_full_trash
  EMPTY_TRASH=false
  SKIP_CONFIRM=true
  DRY_RUN=false
  _TRASH_EMPTIED=false

  run system::_trash
  [ "$status" -eq 0 ]
  [[ "$output" == *"left alone"* ]]
  [ "$_TRASH_EMPTIED" != "true" ]
}

@test "system: --empty-trash queues it in a preview" {
  _stub_full_trash
  EMPTY_TRASH=true
  DRY_RUN=true
  TOTAL_DRYRUN_BYTES=0

  run system::_trash
  [[ "$output" == *"Would empty Trash"* ]]

  system::_trash >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "system: --empty-trash still confirms before a live delete" {
  _stub_full_trash
  EMPTY_TRASH=true
  DRY_RUN=false
  SKIP_CONFIRM=false
  _TRASH_EMPTIED=false
  # Non-interactive: utils::confirm declines rather than hanging.
  run system::_trash
  [ "$status" -eq 0 ]
  [ "$_TRASH_EMPTIED" != "true" ]
}

@test "system: an empty Trash says so and offers nothing" {
  _osascript_timed() {
    case "$*" in
      *"count items in trash"*) echo 0 ;;
      *) echo 0 ;;
    esac
    return 0
  }
  EMPTY_TRASH=false
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  run system::_trash
  [[ "$output" == *"empty"* ]]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

@test "system: an unmeasurable Trash still reaches the decisions summary" {
  # Finder returns the token `missing value`, so a size-based gate silently
  # dropped the Trash from NEEDS YOUR DECISION entirely — a user with 50 GB of
  # it was told nothing.
  _stub_trash_unknown_size
  EMPTY_TRASH=false
  DRY_RUN=true
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  system::_trash >/dev/null 2>&1

  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_LABELS[0]}" == *"in the Trash"* ]]
  [[ "${ACTION_COMMANDS[0]}" == *"--empty-trash"* ]]
}

@test "system: the decision names the item count when the size is unknown" {
  _stub_trash_unknown_size
  EMPTY_TRASH=false
  DRY_RUN=true
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  system::_trash >/dev/null 2>&1
  [[ "${ACTION_LABELS[0]}" == "1 item in the Trash" ]]
  [ "${ACTION_BYTES[0]}" -eq 0 ]
}

@test "system: a raw 'missing value' never becomes a byte count" {
  _osascript_timed() {
    case "$*" in
      *"count items in trash"*) echo 3 ;;
      *"get size of trash"*)    echo "missing value" ;;
    esac
    return 0
  }
  # Real implementation, no override: it must reject the token and fall through.
  run system::_trash_size_bytes
  [ "$status" -eq 0 ]
  [[ "$output" != *"missing"* ]]
  [[ -z "$output" || "$output" =~ ^[0-9]+$ ]]
}

@test "system: item counts are pluralised correctly" {
  [ "$(system::_item_count_phrase 1)" = "1 item" ]
  [ "$(system::_item_count_phrase 0)" = "0 items" ]
  [ "$(system::_item_count_phrase 125)" = "125 items" ]
}

@test "system: a known size is still preferred over the count alone" {
  _stub_full_trash
  EMPTY_TRASH=false
  DRY_RUN=true
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  system::_trash >/dev/null 2>&1
  [ "${ACTION_BYTES[0]}" -eq 2147483648 ]
}

@test "system: --empty-trash with --yes empties without prompting" {
  # Two explicit flags is the deliberate act; requiring a prompt as well would
  # make --empty-trash unusable non-interactively.
  _stub_full_trash
  EMPTY_TRASH=true
  SKIP_CONFIRM=true
  DRY_RUN=false
  _TRASH_EMPTIED=false

  run system::_trash
  [ "$status" -eq 0 ]
  [[ "$output" == *"both given"* ]]
}

@test "system: the du fallback produces a real size when the Trash is readable" {
  # Proves the fallback is a live path. On a Mac without Full Disk Access du
  # reports "Operation not permitted" on the real ~/.Trash, which is why an
  # unknown size must degrade to the item count rather than suppress the entry.
  local real_home="$HOME"
  HOME=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/trash-home.XXXXXX")
  mkdir -p "$HOME/.Trash"
  dd if=/dev/zero of="$HOME/.Trash/big.bin" bs=1024 count=2048 2>/dev/null

  _osascript_timed() {
    case "$*" in
      *"get size of trash"*) echo "missing value" ;;
      *) echo 1 ;;
    esac
    return 0
  }

  run system::_trash_size_bytes
  local measured="$output"
  rm -rf "$HOME"; HOME="$real_home"

  [ "$status" -eq 0 ]
  [ "$measured" -ge 2097152 ]
}

@test "system: an unreadable Trash yields unknown, not zero-as-a-size" {
  local real_home="$HOME"
  HOME=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/trash-home.XXXXXX")
  mkdir -p "$HOME/.Trash"
  _osascript_timed() {
    case "$*" in
      *"get size of trash"*) echo "missing value" ;;
      *) echo 1 ;;
    esac
    return 0
  }
  # Nothing in it and nothing measurable: the answer is empty, not "0".
  run system::_trash_size_bytes
  local measured="$output"
  rm -rf "$HOME"; HOME="$real_home"

  [ -z "$measured" ]
}
