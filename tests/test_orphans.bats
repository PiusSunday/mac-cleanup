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
  # Reverse-DNS name: a real app writes its data under its bundle identifier,
  # and since v0.5.0 only such names are eligible.
  local orphan_dir="$HOME/Library/Application Support/com.zzzzvendor.OrphanApp"
  mkdir -p "$orphan_dir"
  echo "payload" > "$orphan_dir/data.bin"
  touch -t 202001010101 "$orphan_dir"

  orphans::clean > /dev/null 2>&1
  [ "${#ORPHAN_CANDIDATES[@]}" -ge 1 ]
}

@test "orphans::clean: deletes candidates only when CLEAN_ORPHANS=true" {
  local orphan_dir="$HOME/Library/Application Support/com.zzzzvendor.DeleteCandidate"
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

# ── Live-software attribution ─────────────────────────────────────────────────
# v0.4.3 matched directory names against installed app names, so generic dirs
# were flagged regardless of who owned them. `firestore` is Arc's local database
# (firestore/Arc/bcny-arc-server), 40.5 MB, growing during an active session,
# and it was 97% of the reported orphan total.

_old_stamp() { date -r "$(( $(date +%s) - 200 * 86400 ))" +%Y%m%d%H%M.%S; }

_installed_with() {
  local f
  f=$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/installed.XXXXXX")
  : > "$f"
  local n
  for n in "$@"; do orphans::_normalize_name "$n" >> "$f"; done
  printf '%s\n' "$f"
}

@test "orphans: a genuine orphan is still detected" {
  # The check that everything else here must not break.
  local dir="$HOME/Library/Application Support/com.deadvendor.DeadApp"
  mkdir -p "$dir"; echo payload > "$dir/data"
  touch -t "$(_old_stamp)" "$dir"

  local installed
  installed=$(_installed_with "com.other.LiveApp")

  ORPHAN_CANDIDATES=(); _ORPHAN_TOTAL=0
  run orphans::_scan_application_support "$installed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.deadvendor.DeadApp"* ]]
}

@test "orphans: a generic directory is attributed by its contents" {
  # firestore/Arc/... belongs to Arc, whatever the top-level name says.
  local dir="$HOME/Library/Application Support/firestore"
  mkdir -p "$dir/Arc/bcny-arc-server"
  echo payload > "$dir/Arc/bcny-arc-server/db"
  touch -t "$(_old_stamp)" "$dir"

  local installed
  installed=$(_installed_with "Arc")

  ORPHAN_CANDIDATES=(); _ORPHAN_TOTAL=0
  run orphans::_scan_application_support "$installed"
  [[ "$output" != *"Orphan candidate"* ]] || [[ "$output" != *"firestore"* ]]
  [ "$_ORPHAN_TOTAL" -eq 0 ]
}

@test "orphans: command line tool state is never an app orphan" {
  # go/, pypoetry/, virtualenv/ and iCloud/ have no bundle and no app to remove.
  local n
  for n in go pypoetry virtualenv iCloud; do
    mkdir -p "$HOME/Library/Application Support/$n"
    echo x > "$HOME/Library/Application Support/$n/conf"
    touch -t "$(_old_stamp)" "$HOME/Library/Application Support/$n"
  done

  local installed
  installed=$(_installed_with "SomeApp")

  ORPHAN_CANDIDATES=(); _ORPHAN_TOTAL=0
  run orphans::_scan_application_support "$installed"
  for n in go pypoetry virtualenv iCloud; do
    [[ "$output" != *"Orphan candidate: ${n}"* ]]
  done
  [ "$_ORPHAN_TOTAL" -eq 0 ]
}

@test "orphans: a helper sharing a publisher with an installed app is kept" {
  # zoom.us installs as us.zoom.xos; us.zoom.updater is the same publisher.
  local installed
  installed=$(_installed_with "us.zoom.xos")

  run orphans::_vendor_is_installed "us.zoom.updater" "$installed"
  [ "$status" -eq 0 ]
  run orphans::_vendor_is_installed "us.zoom.updater.config" "$installed"
  [ "$status" -eq 0 ]

  # A different publisher must not match.
  run orphans::_vendor_is_installed "com.unrelated.Thing" "$installed"
  [ "$status" -ne 0 ]
}

@test "orphans: a single-label vendor is too weak to grant a pass" {
  local installed
  installed=$(_installed_with "com.example.App")
  # "com" alone must never be treated as a publisher match.
  run orphans::_vendor_is_installed "com.other" "$installed"
  [ "$status" -ne 0 ]
}

@test "orphans: anything whose process is running is kept" {
  # Use a process certain to exist in the test environment.
  local self
  self=$(basename "$(ps -o comm= -p $$ | tr -d ' ')")
  run orphans::_owner_is_running "$self"
  [ "$status" -eq 0 ]

  run orphans::_owner_is_running "definitely-not-a-running-process-xyz"
  [ "$status" -ne 0 ]
}

@test "orphans: bundle-id preference domains are eligible, bare names are not" {
  local installed
  installed=$(_installed_with "com.other.LiveApp")

  run orphans::_looks_like_app_data "com.deadvendor.DeadApp" "$installed"
  [ "$status" -eq 0 ]

  # Helpers, agents and tools write bare-named plists.
  for n in ZoomChat MiniLauncher git-credential-manager; do
    run orphans::_looks_like_app_data "$n" "$installed"
    [ "$status" -ne 0 ]
  done
}

@test "orphans: inner owners are read from a nested layout" {
  local dir="$HOME/Library/Application Support/generic"
  mkdir -p "$dir/Vendor/product"
  run orphans::_inner_owners "$dir"
  [[ "$output" == *"Vendor"* ]]
  [[ "$output" == *"product"* ]]
}
