#!/usr/bin/env bats
# tests/test_optimize.bats — Unit tests for lib/optimize/optimize.sh

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/optimize/optimize.sh"

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

teardown() {
  :
}

@test "optimize::run: registers module with category 'Option'" {
  optimize::run
  [[ "${MODULE_NAMES[0]}" == "Optimization" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "System Optimization" ]]
}

@test "optimize::_add_task: increments optimize task counter" {
  _OPTIMIZE_COUNT=0
  optimize::_add_task
  optimize::_add_task
  [[ "$_OPTIMIZE_COUNT" -eq 2 ]]
}
