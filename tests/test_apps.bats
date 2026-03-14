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
  apps::clean
  [[ "${MODULE_NAMES[0]}" == "Apps & Containers" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "Caches & Logs" ]]
}
