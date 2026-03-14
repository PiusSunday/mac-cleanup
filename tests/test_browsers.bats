#!/usr/bin/env bats
# tests/test_browsers.bats — Unit tests for lib/modules/user/browsers.sh

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/user/browsers.sh"

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

@test "browsers::clean: registers module with category 'Caches & Logs'" {
  browsers::clean
  [[ "${MODULE_NAMES[0]}" == "Browsers" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "Caches & Logs" ]]
}
