#!/usr/bin/env bats
# tests/test_docker.bats — Unit tests for Docker module

setup() {
  # Use a temporary log file to avoid writing to the real user's HOME
  TEST_LOG_DIR=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-test.XXXXXX")
  export LOG_FILE="${TEST_LOG_DIR}/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../lib/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/docker.sh"

  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
}

teardown() {
  # Clean up temporary log directory after each test
  if [ -n "${TEST_LOG_DIR:-}" ] && [ -d "$TEST_LOG_DIR" ]; then
    rm -rf "$TEST_LOG_DIR"
  fi
}

@test "docker::clean: skips gracefully when docker is not available" {
  original_path="$PATH"
  export PATH="/usr/bin:/bin"
  run docker::clean
  export PATH="$original_path"
  [ "$status" -eq 0 ]
}

@test "docker::clean: skips when Docker daemon is not running" {
  # Mock docker to simulate daemon not running
  docker() {
    if [[ "$1" == "info" ]]; then
      return 1
    fi
    return 0
  }
  export -f docker

  run docker::clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"not running"* ]]
}

@test "docker::_containers: outputs DRY-RUN message when DRY_RUN=true" {
  DRY_RUN=true
  docker() {
    case "$1" in
      ps)
        echo "abc123"
        return 0
        ;;
      rm)
        return 0
        ;;
    esac
    return 0
  }
  export -f docker

  run docker::_containers
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "docker::_images: outputs DRY-RUN message when DRY_RUN=true" {
  DRY_RUN=true
  docker() {
    case "$1" in
      images)
        echo "img123"
        return 0
        ;;
      rmi)
        return 0
        ;;
    esac
    return 0
  }
  export -f docker

  run docker::_images
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "docker::_build_cache: outputs DRY-RUN message when DRY_RUN=true" {
  DRY_RUN=true
  run docker::_build_cache
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "docker::clean: parses float Docker sizes correctly" {
  # Mock docker to return realistic float sizes
  docker() {
    case "$1" in
      info) return 0 ;;
      system)
        if [[ "$2" == "df" ]]; then
          printf "1.5GB\n750.2MB\n4.3kB\n"
          return 0
        fi ;;
      container|image|builder)
        return 0 ;;
    esac
    return 0
  }
  export -f docker

  DRY_RUN=true
  run docker::clean
  [ "$status" -eq 0 ]
  # Should have parsed sizes without errors
  [[ "$output" != *"error"* ]]
}
