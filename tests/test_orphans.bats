#!/usr/bin/env bats
# tests/test_orphans.bats — Unit tests for lib/orphans.sh

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/orphans-home.XXXXXX")"
  export HOME="$TEST_HOME"

  mkdir -p "$HOME/Library/Application Support"
  mkdir -p "$HOME/Library/Containers"
  mkdir -p "$HOME/Library/Preferences"

  source "$BATS_TEST_DIRNAME/../lib/core/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/utils.sh"
  source "$BATS_TEST_DIRNAME/../lib/modules/system/orphans.sh"

  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
  LOG_FILE="/dev/null"
  CLEAN_ORPHANS=false
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "orphans::clean: detects stale orphan candidate in Application Support" {
  local orphan_dir="$HOME/Library/Application Support/zzzzorphanapp"
  mkdir -p "$orphan_dir"
  echo "payload" > "$orphan_dir/data.bin"
  touch -t 202001010101 "$orphan_dir"

  orphans::clean > /dev/null 2>&1
  [ "${#ORPHAN_CANDIDATES[@]}" -ge 1 ]
}

@test "orphans::clean: deletes candidates only when CLEAN_ORPHANS=true" {
  local orphan_dir="$HOME/Library/Application Support/zzzzdeletecandidate"
  mkdir -p "$orphan_dir"
  echo "payload" > "$orphan_dir/data.bin"
  touch -t 202001010101 "$orphan_dir"

  DRY_RUN=false
  CLEAN_ORPHANS=true

  run orphans::clean
  [ "$status" -eq 0 ]
  [ ! -e "$orphan_dir" ]
}

@test "orphans::_broken_plists: detects corrupt plists" {
  local bad_plist="$HOME/Library/Preferences/com.example.bad.plist"
  echo "not valid xml or binary" > "$bad_plist"

  run orphans::_broken_plists

  [ "$status" -eq 0 ]
  [[ "$output" == *"Corrupt plist"* ]]
}

# ── Regressions fixed in v0.5.0 ───────────────────────────────────────────────

@test "orphans: an installed app's extensions are not orphans" {
  # net.whatsapp.WhatsApp.ServiceExtension extends an installed bundle id, but
  # v0.4.x normalized the full identifier and found no exact match, so every
  # extension of every installed app was reported as an orphan.
  local installed
  installed=$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/installed.XXXXXX")
  orphans::_normalize_name "net.whatsapp.WhatsApp" > "$installed"

  run orphans::_looks_installed "net.whatsapp.WhatsApp.ServiceExtension" "$installed"
  [ "$status" -eq 0 ]
  run orphans::_looks_installed "net.whatsapp.WhatsApp.Intents" "$installed"
  [ "$status" -eq 0 ]
  run orphans::_looks_installed "com.unrelated.Vendor.Thing" "$installed"
  [ "$status" -ne 0 ]
}

@test "orphans: system preference domains are never scanned as candidates" {
  local old_epoch stamp name
  old_epoch=$(( $(date +%s) - 86400 * 120 ))
  stamp=$(date -r "$old_epoch" +%Y%m%d%H%M.%S)

  for name in loginwindow .GlobalPreferences_m corespotlightd sharedfilelistd icdd; do
    printf 'payload' > "$HOME/Library/Preferences/${name}.plist"
    touch -t "$stamp" "$HOME/Library/Preferences/${name}.plist"
  done

  local installed
  installed=$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/installed.XXXXXX")
  : > "$installed"

  ORPHAN_CANDIDATES=()
  _ORPHAN_TOTAL=0
  run orphans::_scan_preferences "$installed"
  [ "$status" -eq 0 ]

  for name in loginwindow .GlobalPreferences_m corespotlightd sharedfilelistd icdd; do
    [[ "$output" != *"Orphan candidate: ${name}"* ]]
  done
}

@test "orphans: Apple group containers are skipped" {
  local old_epoch stamp
  old_epoch=$(( $(date +%s) - 86400 * 120 ))
  stamp=$(date -r "$old_epoch" +%Y%m%d%H%M.%S)

  mkdir -p "$HOME/Library/Containers/group.com.apple.storekit"
  echo payload > "$HOME/Library/Containers/group.com.apple.storekit/data"
  touch -t "$stamp" "$HOME/Library/Containers/group.com.apple.storekit"

  local installed
  installed=$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/installed.XXXXXX")
  : > "$installed"

  ORPHAN_CANDIDATES=()
  _ORPHAN_TOTAL=0
  run orphans::_scan_containers "$installed"
  [ "$status" -eq 0 ]
  [[ "$output" != *"group.com.apple.storekit"* ]]
}
