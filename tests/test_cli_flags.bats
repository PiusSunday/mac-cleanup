#!/usr/bin/env bats
# tests/test_cli_flags.bats — CLI flag parsing regression tests

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
}

# Bound a command's runtime portably.
#
# `timeout` is GNU coreutils and is NOT present on macOS — it only exists on a
# developer machine that installed it via Homebrew, which is why these tests
# passed locally and failed on a clean macos-latest runner with exit 127. Use
# perl's alarm(), the same mechanism utils::run_timed uses in the tool itself.
_timed() {
  local secs="$1"
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@"
}

@test "parse_flags: --verbose alone defaults to safe all dry-run" {
  run bash -c '
    source "$1/bin/mac-cleanup"
    parse_flags --verbose >/dev/null 2>&1
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$VERBOSE" "$DRY_RUN" "$TARGET_SYSTEM" "$TARGET_XCODE" "$TARGET_CACHES" "$TARGET_SYSTEM_DEEP"
  ' _ "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "true|true|true|true|true|true" ]
}

@test "parse_flags: --yes alone does not trigger implicit live mode" {
  run bash -c '
    source "$1/bin/mac-cleanup"
    parse_flags --yes >/dev/null 2>&1
    printf "%s|%s|%s\n" "$SKIP_CONFIRM" "$DRY_RUN" "$TARGET_SYSTEM"
  ' _ "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "true|true|true" ]
}

@test "parse_flags: --clean-orphans alone keeps modifier and defaults safely" {
  run bash -c '
    source "$1/bin/mac-cleanup"
    parse_flags --clean-orphans >/dev/null 2>&1
    printf "%s|%s|%s\n" "$CLEAN_ORPHANS" "$DRY_RUN" "$TARGET_SYSTEM"
  ' _ "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "true|true|true" ]
}

@test "cli: --version prints version and exits" {
  run "$PROJECT_ROOT/bin/mac-cleanup" --version

  [ "$status" -eq 0 ]
  [ "$output" = "mac-cleanup v0.5.0" ]
}

@test "cli: -V prints version and exits" {
  run "$PROJECT_ROOT/bin/mac-cleanup" -V

  [ "$status" -eq 0 ]
  [ "$output" = "mac-cleanup v0.5.0" ]
}
# ── Target gating ─────────────────────────────────────────────────────────────
# system::clean and orphans::clean used to run above the gating, so any target
# also swept crash reports, .DS_Store, npm caches and emptied the Trash.

@test "cli: --docker runs Docker only, with no System pass" {
  run _timed 300 "$PROJECT_ROOT/bin/mac-cleanup" --docker --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"System Scan"* ]]
  [[ "$output" != *"Orphaned App Data"* ]]
  [[ "$output" != *"Crash reports"* ]]
  [[ "$output" != *"npm cache"* ]]
  [[ "$output" == *"Docker"* ]]
}

@test "cli: --brew does not drag in the System pass either" {
  run _timed 300 "$PROJECT_ROOT/bin/mac-cleanup" --brew --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"System Scan"* ]]
  [[ "$output" != *"Orphaned App Data"* ]]
  [[ "$output" == *"Homebrew"* ]]
}

@test "cli: --system does run the System pass" {
  run _timed 600 "$PROJECT_ROOT/bin/mac-cleanup" --system --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"System Scan"* ]]
  [[ "$output" == *"Orphaned App Data"* ]]
}

@test "cli: --all still covers System" {
  run _timed 900 "$PROJECT_ROOT/bin/mac-cleanup" --all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"System Scan"* ]]
}

@test "cli: --empty-trash is documented and implies the system target" {
  run "$PROJECT_ROOT/bin/mac-cleanup" --help
  [[ "$output" == *"--empty-trash"* ]]
  [[ "$output" == *"--yes alone never reaches it"* ]]
  [[ "$output" == *"Prompts unless --yes is also passed"* ]]
}
