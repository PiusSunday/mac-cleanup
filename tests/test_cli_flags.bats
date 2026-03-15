#!/usr/bin/env bats
# tests/test_cli_flags.bats — CLI flag parsing regression tests

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
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
  [ "$output" = "mac-cleanup v0.4.3" ]
}

@test "cli: -V prints version and exits" {
  run "$PROJECT_ROOT/bin/mac-cleanup" -V

  [ "$status" -eq 0 ]
  [ "$output" = "mac-cleanup v0.4.3" ]
}