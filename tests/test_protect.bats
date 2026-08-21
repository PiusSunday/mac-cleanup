#!/usr/bin/env bats
# tests/test_protect.bats — Deletion-protection policy and the claim ledger.
#
# Each case here corresponds to something v0.4.x would have deleted or
# double-counted on a real machine.

setup() {
  TEST_LOG_DIR=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-protect.XXXXXX")
  export LOG_FILE="${TEST_LOG_DIR}/cleanup.log"
  export OPLOG_FILE="${TEST_LOG_DIR}/operations.log"

  # Sandbox HOME so the policy is exercised against a fake user tree.
  export REAL_HOME="$HOME"
  export HOME="${TEST_LOG_DIR}/home"
  mkdir -p "$HOME"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/protect.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"

  WHITELIST_PATTERNS=()
  INCLUDE_SYSTEM_CACHES=false
  protect::claim_reset
}

teardown() {
  protect::claim_release
  export HOME="${REAL_HOME:-$HOME}"
  if [ -n "${TEST_LOG_DIR:-}" ] && [ -d "$TEST_LOG_DIR" ]; then
    rm -rf "$TEST_LOG_DIR"
  fi
}

# ── System and user-data roots ────────────────────────────────────────────────

@test "protect: refuses core system paths" {
  for p in / /System /usr/bin /etc /private/etc /Library/Apple /Library/Keychains; do
    run protect::verdict "$p"
    [ "$status" -eq 0 ]
  done
}

@test "protect: refuses the user data directories themselves" {
  for d in Documents Desktop Pictures Movies Music Downloads Library; do
    run protect::verdict "$HOME/$d"
    [ "$status" -eq 0 ]
  done
}

@test "protect: still allows files inside user data directories" {
  mkdir -p "$HOME/Desktop"
  touch "$HOME/Desktop/.DS_Store"
  run protect::verdict "$HOME/Desktop/.DS_Store"
  [ "$status" -ne 0 ]
}

@test "protect: refuses relative paths and traversal" {
  run protect::verdict "relative/path"
  [ "$status" -eq 0 ]
  run protect::verdict "/tmp/../etc/passwd"
  [ "$status" -eq 0 ]
}

# ── Credentials ───────────────────────────────────────────────────────────────

@test "protect: refuses credential stores" {
  for p in "$HOME/.ssh" "$HOME/.ssh/id_rsa" "$HOME/.gnupg/secring.gpg" "$HOME/.aws/credentials" "$HOME/.netrc"; do
    run protect::verdict "$p"
    [ "$status" -eq 0 ]
  done
}

@test "protect: allows the AWS CLI token cache as an explicit exception" {
  run protect::verdict "$HOME/.aws/cli/cache"
  [ "$status" -ne 0 ]
}

# ── Live SQLite databases ─────────────────────────────────────────────────────

@test "protect: refuses a SQLite database with a live -shm sidecar" {
  # This is the group.com.apple.storekit/storeUser.db case: v0.4.x queued the
  # database and both sidecars of an open store for deletion.
  local dir="$HOME/Library/Group Containers/group.example/Library/Caches"
  mkdir -p "$dir"
  touch "$dir/storeUser.db" "$dir/storeUser.db-wal" "$dir/storeUser.db-shm"

  run protect::verdict "$dir/storeUser.db"
  [ "$status" -eq 0 ]
  run protect::verdict "$dir/storeUser.db-wal"
  [ "$status" -eq 0 ]
  run protect::verdict "$dir/storeUser.db-shm"
  [ "$status" -eq 0 ]
}

@test "protect: allows a closed SQLite database with no sidecars" {
  local dir="$HOME/Library/Caches/com.example.app"
  mkdir -p "$dir"
  touch "$dir/Cache.db"
  run protect::verdict "$dir/Cache.db"
  [ "$status" -ne 0 ]
}

@test "protect: is_sqlite_family recognises every sidecar suffix" {
  for f in a.db a.db-wal a.db-shm a.db-journal b.sqlite b.sqlite3; do
    run protect::is_sqlite_family "/tmp/$f"
    [ "$status" -eq 0 ]
  done
  run protect::is_sqlite_family "/tmp/notes.txt"
  [ "$status" -ne 0 ]
}

# ── OS service caches ─────────────────────────────────────────────────────────

@test "protect: refuses macOS service caches by default" {
  mkdir -p "$HOME/Library/Caches/com.apple.dataaccess.dataaccessd"
  mkdir -p "$HOME/Library/Caches/GeoServices"
  run protect::verdict "$HOME/Library/Caches/com.apple.dataaccess.dataaccessd"
  [ "$status" -eq 0 ]
  run protect::verdict "$HOME/Library/Caches/GeoServices"
  [ "$status" -eq 0 ]
}

@test "protect: allows macOS service caches with --include-system-caches" {
  mkdir -p "$HOME/Library/Caches/com.apple.dataaccess.dataaccessd"
  INCLUDE_SYSTEM_CACHES=true
  run protect::verdict "$HOME/Library/Caches/com.apple.dataaccess.dataaccessd"
  [ "$status" -ne 0 ]
}

@test "protect: never releases the Neural Engine compiled model cache" {
  # Rebuilding it recompiles every CoreML model on the machine.
  mkdir -p "$HOME/Library/Caches/com.apple.e5rt.e5bundlecache"
  INCLUDE_SYSTEM_CACHES=true
  run protect::verdict "$HOME/Library/Caches/com.apple.e5rt.e5bundlecache"
  [ "$status" -eq 0 ]
}

@test "protect: third-party caches stay eligible" {
  mkdir -p "$HOME/Library/Caches/com.spotify.client"
  run protect::verdict "$HOME/Library/Caches/com.spotify.client"
  [ "$status" -ne 0 ]
}

# ── System preference domains ─────────────────────────────────────────────────

@test "protect: recognises bare-named system preference domains" {
  # `--clean-orphans --yes` on v0.4.x deleted these.
  for name in loginwindow .GlobalPreferences .GlobalPreferences_m corespotlightd sharedfilelistd icdd com.apple.finder; do
    run protect::is_system_pref_domain "$name"
    [ "$status" -eq 0 ]
  done
}

@test "protect: leaves genuine third-party preference domains alone" {
  for name in com.example.OldApp us.zoom.xos ZoomChat; do
    run protect::is_system_pref_domain "$name"
    [ "$status" -ne 0 ]
  done
}

# ── Claim ledger ──────────────────────────────────────────────────────────────

@test "claim ledger: a path can only be claimed once" {
  run protect::claim "/tmp/example"
  [ "$status" -eq 0 ]
  run protect::claim "/tmp/example"
  [ "$status" -ne 0 ]
}

@test "claim ledger: descendants of a claimed path are already accounted for" {
  protect::claim "/tmp/parent"
  run protect::claim "/tmp/parent/child"
  [ "$status" -ne 0 ]
}

@test "claim ledger: siblings are independent" {
  protect::claim "/tmp/parent"
  run protect::claim "/tmp/parent-other"
  [ "$status" -eq 0 ]
}

@test "safe_rm: overlapping modules count shared bytes exactly once" {
  # The browser sweep, the container sweep and the user-cache sweep all used to
  # reach the same directory, so the dry-run preview reported it three times.
  local target="$HOME/Library/Caches/com.example.shared"
  mkdir -p "$target"
  dd if=/dev/zero of="$target/blob" bs=1024 count=64 2>/dev/null

  DRY_RUN=true
  TOTAL_DRYRUN_BYTES=0
  TOTAL_DEDUPED=0

  safe_rm "$target" "first pass" >/dev/null 2>&1
  local after_first="$TOTAL_DRYRUN_BYTES"
  [ "$after_first" -gt 0 ]

  safe_rm "$target" "second pass" >/dev/null 2>&1
  safe_rm "$target/blob" "third pass, nested" >/dev/null 2>&1

  [ "$TOTAL_DRYRUN_BYTES" -eq "$after_first" ]
  [ "$TOTAL_DEDUPED" -eq 2 ]
}

@test "safe_rm: refuses a protected path and counts it as protected" {
  mkdir -p "$HOME/.ssh"
  echo key > "$HOME/.ssh/id_rsa"

  DRY_RUN=false
  TOTAL_PROTECTED=0
  safe_rm "$HOME/.ssh/id_rsa" "ssh key" >/dev/null 2>&1

  [ -e "$HOME/.ssh/id_rsa" ]
  [ "$TOTAL_PROTECTED" -eq 1 ]
}

@test "safe_rm: dry run and live run agree on the reclaimable total" {
  local a="$HOME/Library/Caches/com.example.one"
  local b="$HOME/Library/Caches/com.example.two"
  mkdir -p "$a" "$b"
  dd if=/dev/zero of="$a/blob" bs=1024 count=32 2>/dev/null
  dd if=/dev/zero of="$b/blob" bs=1024 count=48 2>/dev/null

  DRY_RUN=true
  TOTAL_DRYRUN_BYTES=0
  safe_rm "$a" "a" >/dev/null 2>&1
  safe_rm "$b" "b" >/dev/null 2>&1
  safe_rm "$a" "a again" >/dev/null 2>&1
  local previewed="$TOTAL_DRYRUN_BYTES"

  protect::claim_reset
  DRY_RUN=false
  TOTAL_FREED=0
  safe_rm "$a" "a" >/dev/null 2>&1
  safe_rm "$b" "b" >/dev/null 2>&1
  safe_rm "$a" "a again" >/dev/null 2>&1

  [ "$previewed" -eq "$TOTAL_FREED" ]
  [ ! -e "$a" ]
  [ ! -e "$b" ]
}

# ── Formatting ────────────────────────────────────────────────────────────────

@test "format_bytes: handles terabytes and rounds half-up" {
  [ "$(utils::format_bytes 1099511627776)" = "1.0 TB" ]
  [ "$(utils::format_bytes 1610612736)" = "1.5 GB" ]
  [ "$(utils::format_bytes 0)" = "0 B" ]
}

@test "format_bytes: survives non-numeric input instead of crashing" {
  [ "$(utils::format_bytes "")" = "0 B" ]
  [ "$(utils::format_bytes "abc")" = "0 B" ]
}
