#!/usr/bin/env bats
# tests/test_devops.bats — DevOps Reset, the most destructive mode in the tool.
#
# It had no test coverage at all. Per CONTRIBUTING, every detector that can
# report "nothing found" ships with a fixture proving it fires — and that
# matters most for the mode a user reaches for when they want everything gone.

setup() {
  TEST_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/devops-home.XXXXXX")"
  export HOME="$TEST_HOME"
  export LOG_FILE="$TEST_HOME/cleanup.log"
  export OPLOG_FILE="$TEST_HOME/operations.log"
  export WHITELIST_FILE="$TEST_HOME/whitelist"

  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/protect.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/dev/devops.sh"

  utils::load_whitelist
  protect::claim_reset

  DRY_RUN=true
  SKIP_CONFIRM=true
  VERBOSE=false
  INCLUDE_ML_MODELS=false
  TOTAL_FREED=0
  TOTAL_DRYRUN_BYTES=0

  # Docker is not exercised here; stub it out so these stay hermetic.
  docker() { return 1; }
}

teardown() {
  protect::claim_release
  [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

_blob() {
  mkdir -p "$(dirname "$1")"
  dd if=/dev/zero of="$1" bs=1024 count="${2:-512}" 2>/dev/null
}

# ── The detectors fire ────────────────────────────────────────────────────────

@test "devops: node ecosystem caches are found" {
  _blob "$HOME/.npm/_cacache/blob"
  _blob "$HOME/.pnpm-store/blob"
  _blob "$HOME/.yarn/cache/blob"

  TOTAL_DRYRUN_BYTES=0
  devops_reset::_node_deep >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "devops: python ecosystem caches are found" {
  _blob "$HOME/Library/Caches/pip/blob"
  _blob "$HOME/.cache/uv/blob"
  _blob "$HOME/.conda/pkgs/blob"

  TOTAL_DRYRUN_BYTES=0
  devops_reset::_python_deep >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "devops: ruby ecosystem caches are found" {
  _blob "$HOME/.bundle/cache/blob"
  _blob "$HOME/.gem/cache/blob"

  TOTAL_DRYRUN_BYTES=0
  devops_reset::_ruby_deep >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "devops: rust ecosystem caches are found" {
  _blob "$HOME/.cargo/registry/cache/blob"
  _blob "$HOME/.rustup/downloads/blob"

  TOTAL_DRYRUN_BYTES=0
  devops_reset::_rust_deep >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "devops: aged gradle entries and maven snapshots are found" {
  _blob "$HOME/.gradle/caches/build-cache-1/blob"
  touch -t "$(date -r "$(( $(date +%s) - 200 * 86400 ))" +%Y%m%d%H%M.%S)" \
    "$HOME/.gradle/caches/build-cache-1"
  _blob "$HOME/.m2/repository/com/example/1.0-SNAPSHOT/blob"

  TOTAL_DRYRUN_BYTES=0
  devops_reset::_java_deep >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
}

@test "devops: a recent gradle entry is left alone" {
  _blob "$HOME/.gradle/caches/build-cache-1/blob"

  TOTAL_DRYRUN_BYTES=0
  devops_reset::_java_deep >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -eq 0 ]
}

# ── Model caches stay behind their own flag ───────────────────────────────────

@test "devops: model caches are skipped without --include-ml-models" {
  _blob "$HOME/.cache/huggingface/blob" 2048
  _blob "$HOME/.ollama/models/blob" 2048

  INCLUDE_ML_MODELS=false
  DRY_RUN=false
  devops_reset::_ml_frameworks >/dev/null 2>&1

  [ -e "$HOME/.cache/huggingface/blob" ]
  [ -e "$HOME/.ollama/models/blob" ]
}

@test "devops: --include-ml-models overrides the whitelist that protects them" {
  _blob "$HOME/.cache/huggingface/blob" 2048
  _blob "$HOME/.ollama/models/blob" 2048

  INCLUDE_ML_MODELS=true
  DRY_RUN=false
  devops_reset::_ml_frameworks >/dev/null 2>&1

  [ ! -e "$HOME/.cache/huggingface/blob" ]
  [ ! -e "$HOME/.ollama/models/blob" ]
}

# ── The mode can be previewed and reports honestly ────────────────────────────

@test "devops: a dry run previews without asking for confirmation" {
  # utils::confirm declines during a preview by design. Gating the whole body on
  # it made `--devops-reset --dry-run` print "(no modules ran)", so the most
  # destructive mode could only be discovered by running it live.
  _blob "$HOME/.npm/_cacache/blob"

  DRY_RUN=true
  SKIP_CONFIRM=false
  TOTAL_DRYRUN_BYTES=0

  # Called once: `run` uses a subshell, but the claim ledger is a file, so a
  # second invocation would correctly find the path already accounted for.
  devops_reset::run >/dev/null 2>&1
  [ "$TOTAL_DRYRUN_BYTES" -gt 0 ]
  [ -e "$HOME/.npm/_cacache/blob" ]
}

@test "devops: a live run still asks before deleting anything" {
  _blob "$HOME/.npm/_cacache/blob"

  DRY_RUN=false
  SKIP_CONFIRM=false
  # Non-interactive: utils::confirm declines rather than hanging.
  run devops_reset::run
  [ "$status" -eq 0 ]
  [ -e "$HOME/.npm/_cacache/blob" ]
}

@test "devops: a preview does not report itself as clean while queueing bytes" {
  # TOTAL_FREED never moves during a preview, so reporting on it made a dry run
  # announce "Nothing to clean" and register Clean with gigabytes queued.
  _blob "$HOME/.npm/_cacache/blob" 2048

  MODULE_NAMES=(); MODULE_CATEGORIES=(); MODULE_SCANNED=()
  MODULE_FREED=(); MODULE_STATUS=(); MODULE_PROJECTED=(); MODULE_ITEMS=()
  DRY_RUN=true
  SKIP_CONFIRM=true

  devops_reset::run >/dev/null 2>&1

  [ "${#MODULE_NAMES[@]}" -eq 1 ]
  [ "${MODULE_NAMES[0]}" = "DevOps Reset" ]
  [ "${MODULE_PROJECTED[0]}" -gt 0 ]
  [ "${MODULE_SCANNED[0]}" -gt 0 ]
  [ "${MODULE_STATUS[0]}" != "clean" ]
}

@test "devops: an actually-empty environment still reports clean" {
  # The negative case, so "clean" means something.
  MODULE_NAMES=(); MODULE_CATEGORIES=(); MODULE_SCANNED=()
  MODULE_FREED=(); MODULE_STATUS=(); MODULE_PROJECTED=(); MODULE_ITEMS=()
  DRY_RUN=true
  SKIP_CONFIRM=true

  devops_reset::run >/dev/null 2>&1
  [ "${MODULE_STATUS[0]}" = "clean" ]
}

# ── The protection policy still applies in nuclear mode ───────────────────────

@test "devops: credentials are refused even here" {
  mkdir -p "$HOME/.ssh"
  echo key > "$HOME/.ssh/id_rsa"
  mkdir -p "$HOME/.aws"
  echo secret > "$HOME/.aws/credentials"

  DRY_RUN=false
  SKIP_CONFIRM=true
  devops_reset::run >/dev/null 2>&1

  [ -e "$HOME/.ssh/id_rsa" ]
  [ -e "$HOME/.aws/credentials" ]
}
