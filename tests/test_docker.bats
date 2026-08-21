#!/usr/bin/env bats
# tests/test_docker.bats — Unit tests for Docker module

setup() {
  # Use a temporary log file to avoid writing to the real user's HOME
  TEST_LOG_DIR=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mac-cleanup-test.XXXXXX")
  export LOG_FILE="${TEST_LOG_DIR}/cleanup.log"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/dev/docker.sh"

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

# ── Image size accounting ─────────────────────────────────────────────────────
# A run against a real Supabase stack advertised 14.9 GB of unused images and
# freed 3.56 GB. `docker images --format '{{.Size}}'` reports each image's full
# size *including shared base layers*, so summing that column counts every
# shared layer once per image referencing it.

# Three unused images (Containers=0) plus one in use. All three unused images
# share a 500MB base: Size = SharedSize + UniqueSize.
#   sum of Size   = 1GB + 800MB + 600MB      = 2.4GB   <- what v0.5.0 reported
#   sum of Unique = 500MB + 300MB + 100MB    = 900MB   <- what deleting frees
_fake_docker_df() {
  cat <<'TABLE'
sha256:aaaaaaaaaaaaaaaa|example/one|v1|500MB|500MB|1GB|0
sha256:bbbbbbbbbbbbbbbb|example/two|v2|300MB|500MB|800MB|0
sha256:cccccccccccccccc|example/three|v3|100MB|500MB|600MB|0
sha256:dddddddddddddddd|example/inuse|v4|900MB|0B|900MB|2
TABLE
}

@test "docker: unused image total uses unique size, not size including shared layers" {
  docker() {
    if [[ "$1" == "system" && "$2" == "df" ]]; then _fake_docker_df; return 0; fi
    return 0
  }

  run docker::_report_unused_images
  [ "$status" -eq 0 ]

  docker::_report_unused_images >/dev/null 2>&1

  # 500MB + 300MB + 100MB, decimal units as Docker reports them.
  [ "$_DOCKER_UNUSED_BYTES" -eq 900000000 ]

  # The pre-fix behaviour summed Size and would have produced 2.4 GB.
  [ "$_DOCKER_UNUSED_BYTES" -ne 2400000000 ]
}

@test "docker: an image referenced by a container is never listed as unused" {
  # Docker's own Containers count is authoritative. Matching by tag or by
  # `--filter ancestor=` misses containers that reference an image under a
  # different tag.
  docker() {
    if [[ "$1" == "system" && "$2" == "df" ]]; then _fake_docker_df; return 0; fi
    return 0
  }

  run docker::_report_unused_images
  [[ "$output" == *"example/one"* ]]
  [[ "$output" != *"example/inuse"* ]]
}

@test "docker: reports the unused total as a floor, not an exact figure" {
  # Layers shared only among the unused set also free up, so sum-of-unique
  # under-reports. The wording must not promise an exact number.
  docker() {
    if [[ "$1" == "system" && "$2" == "df" ]]; then _fake_docker_df; return 0; fi
    return 0
  }

  run docker::_report_unused_images
  [[ "$output" == *"at least"* ]]
}

@test "docker: no unused images means no action and no output" {
  docker() {
    if [[ "$1" == "system" && "$2" == "df" ]]; then
      echo 'sha256:dddddddddddddddd|example/inuse|v4|900MB|0B|900MB|2'
      return 0
    fi
    return 0
  }

  run docker::_report_unused_images
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
