#!/usr/bin/env bats
# tests/test_assetcache.bats — Apple Content Caching store.
#
# The store lives in /Library, is system-owned and is flushed through
# AssetCacheManagerUtil rather than safe_rm, so every branch needs a fixture:
# the report-only path, the dry-run projection, the flush, and the run that
# cannot get admin rights. A module that quietly declines to flush is exactly
# how a cleaner ends up reporting work it never did — the same defect class as
# the Trash gate and the snapshot byte count.

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/assetcache-home.XXXXXX")"
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"
  export OPLOG_FILE="$TEST_HOME/operations.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/protect.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/system/assetcache.sh"

  WHITELIST_PATTERNS=()
  protect::claim_reset
  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
  TARGET_CONTENT_CACHE=false
  TOTAL_FREED=0
  TOTAL_DRYRUN_BYTES=0

  MODULE_NAMES=(); MODULE_CATEGORIES=(); MODULE_SCANNED=()
  MODULE_FREED=(); MODULE_STATUS=(); MODULE_PROJECTED=(); MODULE_ITEMS=()
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()
}

teardown() {
  protect::claim_release
  [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
  return 0
}

# A store holding 3 MB, the way the service lays one out.
_seed_store() {
  STORE="$TEST_HOME/com.apple.AssetCache"
  mkdir -p "$STORE/Content"
  dd if=/dev/zero of="$STORE/Content/blob" bs=1024 count=3072 2>/dev/null
}

# `AssetCacheManagerUtil -j status`, as the service answers it.
#
# The JSON is built here and lives in a global: a mock that closed over the
# helper's locals would read them after the helper returned and report "not
# activated" for every case, which is exactly the silent-empty-probe defect the
# module is written to avoid.
_stub_status() {
  local activated="$1"
  local used="${2:-0}"
  STATUS_JSON=$(printf '{"name":"status","result":{"Activated":%s,"Active":%s,"CacheDetails":{"CachePath":"%s"},"CacheUsed":%s}}' \
    "$activated" "$activated" "$STORE" "$used")
  AssetCacheManagerUtil() {
    if [[ "${1:-}" == "-j" && "${2:-}" == "status" ]]; then
      printf '%s\n' "$STATUS_JSON"
    fi
    return 0
  }
}

_stub_no_sudo() {
  sudo() { return 1; }
}

_stub_sudo_flush() {
  sudo() {
    case "$*" in
      "-n true") return 0 ;;
      *flushCache*) rm -rf "$STORE"; return 0 ;;
    esac
    return 0
  }
}

@test "assetcache: an activated store without the flag is reported, not flushed" {
  _seed_store
  _stub_status true
  DRY_RUN=false

  assetcache::clean >/dev/null 2>&1

  [ -d "$STORE" ]
  [ "${MODULE_SCANNED[0]}" -gt 0 ]
  [ "${MODULE_PROJECTED[0]}" -eq 0 ]
  [ "${MODULE_STATUS[0]}" = "review" ]
  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_COMMANDS[0]}" == *"--content-cache"* ]]
}

@test "assetcache: --content-cache in dry-run projects the size and removes nothing" {
  _seed_store
  _stub_status true
  DRY_RUN=true
  TARGET_CONTENT_CACHE=true

  assetcache::clean >/dev/null 2>&1

  [ -d "$STORE" ]
  [ "${MODULE_PROJECTED[0]}" -gt 0 ]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

@test "assetcache: a live flush credits the bytes that actually went away" {
  _seed_store
  _stub_status true
  _stub_sudo_flush
  DRY_RUN=false
  TARGET_CONTENT_CACHE=true

  local expected
  expected=$(utils::get_size_bytes "$STORE")

  assetcache::clean >/dev/null 2>&1

  [ ! -d "$STORE" ]
  [ "${MODULE_FREED[0]}" -eq "$expected" ]
  [ "${MODULE_PROJECTED[0]}" -eq "$expected" ]
  [ "$TOTAL_FREED" -eq "$expected" ]
}

@test "assetcache: a live run without admin rights claims nothing and offers the command" {
  _seed_store
  _stub_status true
  _stub_no_sudo
  DRY_RUN=false
  TARGET_CONTENT_CACHE=true

  assetcache::clean >/dev/null 2>&1

  [ -d "$STORE" ]
  [ "${MODULE_PROJECTED[0]}" -eq 0 ]
  [ "${MODULE_STATUS[0]}" = "review" ]
  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_COMMANDS[0]}" == *"--content-cache"* ]]
}

@test "assetcache: admin rights granted at the prompt still flush" {
  _seed_store
  _stub_status true
  DRY_RUN=false
  TARGET_CONTENT_CACHE=true
  # A cold sudo fails the non-interactive probe but the interactive one succeeds,
  # which is the path a user gets by passing the flag on its own.
  sudo() {
    case "$*" in
      "-n true") return 1 ;;
      *flushCache*) rm -rf "$STORE"; return 0 ;;
    esac
    return 0
  }

  assetcache::clean >/dev/null 2>&1

  [ ! -d "$STORE" ]
  [ "${MODULE_FREED[0]}" -gt 0 ]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

@test "assetcache: Content Caching switched off reads as unavailable, not empty" {
  STORE="$TEST_HOME/com.apple.AssetCache"
  _stub_status false

  assetcache::clean >/dev/null 2>&1

  [ "${MODULE_STATUS[0]}" = "skipped" ]
  [ "${MODULE_PROJECTED[0]}" -eq 0 ]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

@test "assetcache: an activated store with nothing in it is clean" {
  STORE="$TEST_HOME/com.apple.AssetCache"
  _stub_status true

  assetcache::clean >/dev/null 2>&1

  [ "${MODULE_STATUS[0]}" = "clean" ]
  [ "${MODULE_PROJECTED[0]}" -eq 0 ]
  [ "${#ACTION_LABELS[@]}" -eq 0 ]
}

@test "assetcache: falls back to the service byte count when the store cannot be walked" {
  STORE="$TEST_HOME/store-that-does-not-exist"
  _stub_status true 5242880

  assetcache::clean >/dev/null 2>&1

  [ "${MODULE_SCANNED[0]}" -eq 5242880 ]
  [ "${MODULE_PROJECTED[0]}" -eq 0 ]
  [ "${#ACTION_LABELS[@]}" -eq 1 ]
}

@test "assetcache: cache path falls back to the documented location" {
  run assetcache::_cache_path '{"result":{"Activated":true,"CacheDetails":{}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "/Library/Application Support/com.apple.AssetCache" ]

  run assetcache::_cache_path '{"result":{"CacheDetails":{"CachePath":"/tmp/elsewhere"}}}'
  [ "$output" = "/tmp/elsewhere" ]
}

@test "assetcache: a store with no reported byte count stays at zero" {
  run assetcache::_reported_used '{"result":{"CacheUsed":0}}'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run assetcache::_reported_used '{"result":{"CacheUsed":1234567890}}'
  [ "$output" = "1234567890" ]
}
