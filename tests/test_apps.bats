#!/usr/bin/env bats
# tests/test_apps.bats — Unit tests for lib/modules/user/apps.sh

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/user/apps.sh"

  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false

  # Clean tracking arrays
  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_STATUS=()
  MODULE_FREED=()
  MODULE_SCANNED=()
  MODULE_PROJECTED=()
}

@test "apps::clean: registers module with category 'Caches & Logs'" {
  # Mock functions that perform expensive I/O operations
  utils::get_size_bytes() { echo "1024"; }
  safe_rm_contents() { TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + 1024 )); }
  find() { echo "/mock/dir"; }

  apps::clean
  [[ "${MODULE_NAMES[0]}" == "Apps & Containers" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "Caches & Logs" ]]
}

# ── Regressions fixed in v0.5.0 ───────────────────────────────────────────────

@test "apps: recognises Apple sandboxes under every prefix Apple uses" {
  # "group.com.apple.storekit" does not start with "com.apple.", so v0.4.x let
  # it through and queued the live storeUser.db plus its -wal/-shm sidecars.
  for cname in com.apple.mail group.com.apple.storekit 6N38VWS5BX.com.apple.oneup; do
    run apps::_is_apple_container "$cname"
    [ "$status" -eq 0 ]
  done
}

@test "apps: third-party containers remain eligible" {
  for cname in com.tinyspeck.slackmacgap net.whatsapp.WhatsApp group.com.example.app; do
    run apps::_is_apple_container "$cname"
    [ "$status" -ne 0 ]
  done
}
