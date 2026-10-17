#!/usr/bin/env bats
# tests/test_trash.bats — Trash correctness.
#
# Up to v0.5.0 the Trash module trusted Finder's exit codes. `empty trash`
# returns 0 even when it leaves items behind (locked files, a partially-refused
# Automation prompt, or a probe that simply does nothing), and a refused count
# query was coerced to 0 — so a fully-stocked Trash was reported as "empty" and
# "emptied." Every case here pins down that neither exit code is believed: the
# count is re-queried, and only a verified-empty Trash is ever reported.

setup() {
  TEST_DIR=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-trash.XXXXXX")
  export REAL_HOME="$HOME"
  # Scratch HOME so nothing here can reach the real user's Trash.
  export HOME="${TEST_DIR}/home"
  mkdir -p "$HOME"
  export LOG_FILE="${TEST_DIR}/cleanup.log"
  export OPLOG_FILE="${TEST_DIR}/operations.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/protect.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/system/standard.sh"

  WHITELIST_PATTERNS=()
  INCLUDE_SYSTEM_CACHES=false
  DRY_RUN=false
  VERBOSE=false
  EMPTY_TRASH=false
  SKIP_CONFIRM=true
  TOTAL_FREED=0
  TOTAL_DRYRUN_BYTES=0
  protect::claim_reset
}

teardown() {
  protect::claim_release
  export HOME="${REAL_HOME:-$HOME}"
  if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# ── Filesystem count ──────────────────────────────────────────────────────────

@test "trash: filesystem count sees items in ~/.Trash" {
  mkdir -p "$HOME/.Trash"
  touch "$HOME/.Trash/a" "$HOME/.Trash/b"

  run system::_trash_fs_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "trash: a missing ~/.Trash is 0, not unknown" {
  rm -rf "$HOME/.Trash"

  run system::_trash_fs_count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "trash: an unreadable ~/.Trash yields unknown, never 0" {
  mkdir -p "$HOME/.Trash"
  # A chmod 000 directory is still readable by root, so a failing `ls` is the
  # deterministic stand-in for a permission denial.
  ls() { return 1; }

  run system::_trash_fs_count
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Count query ───────────────────────────────────────────────────────────────

@test "trash: Finder's count is used when it answers" {
  _osascript_timed() { echo 7; return 0; }

  run system::_trash_count
  [ "$output" = "7" ]
}

@test "trash: the count falls back to the filesystem when Finder refuses" {
  mkdir -p "$HOME/.Trash"
  touch "$HOME/.Trash/a" "$HOME/.Trash/b" "$HOME/.Trash/c"
  _osascript_timed() { return 1; }

  run system::_trash_count
  [ "$output" = "3" ]
}

@test "trash: the 'missing value' token is rejected and the filesystem is used" {
  mkdir -p "$HOME/.Trash"
  touch "$HOME/.Trash/a"
  _osascript_timed() { echo "missing value"; return 0; }

  run system::_trash_count
  [ "$output" = "1" ]
}

# ── Never invent an "empty" ───────────────────────────────────────────────────

@test "trash: an unreadable Trash with no Finder answer is reported unknown, not empty" {
  mkdir -p "$HOME/.Trash"
  _osascript_timed() { return 1; }
  ls() { return 1; }
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  run system::_trash
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable"* ]]
  [[ "$output" != *"Trash: empty"* ]]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

# ── Emptied is measured, never assumed ────────────────────────────────────────

@test "trash: Finder exiting 0 without deleting is not trusted" {
  mkdir -p "$HOME/.Trash"
  dd if=/dev/zero of="$HOME/.Trash/junk" bs=1024 count=4 2>/dev/null
  # `empty trash` succeeds but does nothing — the probe that fooled v0.5.0.
  # The count query refuses, forcing real verification on the filesystem.
  _osascript_timed() {
    case "$*" in
      *"count items in trash"*) return 1 ;;
    esac
    return 0
  }

  system::_trash_empty 4096 >/dev/null 2>&1

  # The exit code was ignored: the leftover file was removed directly and only
  # then was the Trash declared empty.
  [ "$_SYS_TRASH_VERIFIED" = "true" ]
  [ ! -e "$HOME/.Trash/junk" ]
  [ "$_SYS_TRASH_FREED" -gt 0 ]
}

@test "trash: a verified empty is credited and reported" {
  mkdir -p "$HOME/.Trash"
  echo x > "$HOME/.Trash/a"
  _osascript_timed() {
    case "$*" in
      *"empty trash"*) rm -rf "$HOME/.Trash"/*; return 0 ;;
      *) return 1 ;;
    esac
  }

  TOTAL_FREED=0
  system::_trash_empty 4096 >/dev/null 2>&1

  [ "$_SYS_TRASH_VERIFIED" = "true" ]
  [ "$_SYS_TRASH_FREED" -eq 4096 ]
  [ "$TOTAL_FREED" -eq 4096 ]
}

@test "trash: emptying that stays non-empty is never reported as emptied" {
  mkdir -p "$HOME/.Trash"
  echo x > "$HOME/.Trash/stuck"
  _osascript_timed() { return 0; }   # `empty trash` always "succeeds"...
  system::_trash_count() { echo 3; } # ...and the count never shrinks
  EMPTY_TRASH=true
  SKIP_CONFIRM=true
  TOTAL_FREED=0
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  run system::_trash
  [ "$status" -eq 0 ]
  [[ "$output" != *"emptied"* ]]
  [[ "$output" == *"remain after emptying"* ]]
}

@test "trash: --empty-trash on a verifiable Trash reports success" {
  mkdir -p "$HOME/.Trash"
  echo x > "$HOME/.Trash/a"
  _osascript_timed() {
    case "$*" in
      *"count items in trash"*) return 1 ;;
      *"empty trash"*) rm -rf "$HOME/.Trash"/*; return 0 ;;
    esac
    return 1
  }
  EMPTY_TRASH=true
  SKIP_CONFIRM=true
  TOTAL_FREED=0
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  run system::_trash
  [ "$status" -eq 0 ]
  [[ "$output" == *"Trash emptied"* ]]
}
