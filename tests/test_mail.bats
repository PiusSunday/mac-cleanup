#!/usr/bin/env bats
# tests/test_mail.bats — Mail downloads and recent-item metadata.
#
# Per CONTRIBUTING: a detector that can report "nothing found" ships with a
# fixture proving it fires. Both detectors here depend on find patterns that
# could silently never match, and neither had a positive fixture.

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mail-home.XXXXXX")"
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"
  export OPLOG_FILE="$TEST_HOME/operations.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/protect.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/user/mail.sh"

  WHITELIST_PATTERNS=()
  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
  protect::claim_reset
}

teardown() {
  protect::claim_release
  [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

_aged() { date -r "$(( $(date +%s) - $1 * 86400 ))" +%Y%m%d%H%M.%S; }

@test "mail: an old attachment is detected" {
  local dir="$HOME/Library/Mail Downloads"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/old.pdf" bs=1024 count=512 2>/dev/null
  touch -t "$(_aged 90)" "$dir/old.pdf"

  _MAIL_TOTAL=0
  mail::_downloads >/dev/null 2>&1
  [ "$_MAIL_TOTAL" -gt 0 ]
}

@test "mail: a recent attachment is left alone" {
  local dir="$HOME/Library/Mail Downloads"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/new.pdf" bs=1024 count=512 2>/dev/null

  _MAIL_TOTAL=0
  mail::_downloads >/dev/null 2>&1
  [ "$_MAIL_TOTAL" -eq 0 ]
}

@test "mail: the sandboxed Mail container path is covered too" {
  local dir="$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/old.pdf" bs=1024 count=512 2>/dev/null
  touch -t "$(_aged 90)" "$dir/old.pdf"

  _MAIL_TOTAL=0
  mail::_downloads >/dev/null 2>&1
  [ "$_MAIL_TOTAL" -gt 0 ]
}

@test "mail: a recent-items list is detected" {
  # The pattern matches com.apple.LSSharedFileList.Recent* — a name shape that
  # would be easy to get wrong and never notice.
  local dir="$HOME/Library/Application Support/com.apple.sharedfilelist"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/com.apple.LSSharedFileList.RecentDocuments.sfl3" bs=1024 count=64 2>/dev/null

  _MAIL_TOTAL=0
  mail::_recent_items >/dev/null 2>&1
  [ "$_MAIL_TOTAL" -gt 0 ]
}

@test "mail: an unrelated sharedfilelist entry is not touched" {
  local dir="$HOME/Library/Application Support/com.apple.sharedfilelist"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/com.apple.LSSharedFileList.FavoriteItems.sfl3" bs=1024 count=64 2>/dev/null

  _MAIL_TOTAL=0
  mail::_recent_items >/dev/null 2>&1
  [ "$_MAIL_TOTAL" -eq 0 ]
}

@test "mail: clean registers the module" {
  MODULE_NAMES=(); MODULE_CATEGORIES=(); MODULE_SCANNED=()
  MODULE_FREED=(); MODULE_STATUS=(); MODULE_PROJECTED=(); MODULE_ITEMS=()

  # Called directly, not through `run`: bats runs `run` in a subshell, so array
  # mutations made by the function would not reach the assertions.
  mail::clean >/dev/null 2>&1
  [ "${#MODULE_NAMES[@]}" -eq 1 ]
  [ "${MODULE_NAMES[0]}" = "Mail" ]
}
