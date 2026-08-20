#!/usr/bin/env bash
# lib/core.sh — Global state: DRY_RUN, VERBOSE, SKIP_CONFIRM flags
# Sourced first by bin/mac-cleanup; never modified after initial parse.

export DRY_RUN=${DRY_RUN:-true}
export VERBOSE=${VERBOSE:-false}
export SKIP_CONFIRM=${SKIP_CONFIRM:-false}

# ── Global Constants ───────────────────────────────────────────────────────────
VERSION="0.5.0"
LOG_DIR="$HOME/.mac-cleanup"
LOG_FILE="$LOG_DIR/cleanup.log"

# Enforce standard C locale for numerical operations to prevent comma/period
# decimal mismatches in utilities like printf and bc on European machines.
export LC_NUMERIC=C

export LOG_FILE
export VERSION

# Cleanup targets (default: all false, set by CLI flags)
export TARGET_SYSTEM=false
export TARGET_XCODE=false
export TARGET_DOCKER=false
export TARGET_DEVTOOLS=false
export TARGET_SNAPSHOTS=false
export TARGET_CACHES=false
export TARGET_BREW=false
export TARGET_MAIL=false
export TARGET_SYSTEM_DEEP=false

# Tracking — accumulate bytes freed across modules
export TOTAL_FREED=0
export TOTAL_DRYRUN_BYTES=0

# Feature flags
export CLEAN_ORPHANS=${CLEAN_ORPHANS:-false}
export INCLUDE_ML_MODELS=${INCLUDE_ML_MODELS:-false}
export DEVOPS_RESET_MODE=${DEVOPS_RESET_MODE:-false}
export SHOW_OPERATION_LOG=${SHOW_OPERATION_LOG:-false}
export SHOW_VERSION=${SHOW_VERSION:-false}
export TARGET_OPTIMIZE=${TARGET_OPTIMIZE:-false}

# Opt-in to purging macOS service caches under ~/Library/Caches/com.apple.*.
# Off by default: those caches are rebuilt by background daemons within minutes,
# so removing them inflates the reported total without freeing durable space.
export INCLUDE_SYSTEM_CACHES=${INCLUDE_SYSTEM_CACHES:-false}

# Opt-in to deleting unusable Xcode simulator runtimes and stale simulator
# devices. Off by default: runtimes are multi-gigabyte downloads.
export TARGET_SIMULATORS=${TARGET_SIMULATORS:-false}

# Per-module reporting arrays
# Each module registers: name, category, scanned bytes, freed bytes, status,
# and projected reclaimable bytes for the summary report.
declare -a MODULE_NAMES=()
declare -a MODULE_CATEGORIES=()
declare -a MODULE_SCANNED=()
declare -a MODULE_FREED=()
declare -a MODULE_STATUS=()
declare -a MODULE_PROJECTED=()
declare -a MODULE_ITEMS=()

# Opt-in wins surfaced in the report's "needs your decision" block: things the
# tool found but will not remove without an explicit flag.
declare -a ACTION_LABELS=()
declare -a ACTION_BYTES=()
declare -a ACTION_COMMANDS=()

# Paths that macOS SIP or system ownership protects — never attempt deletion
# Adding a path here prevents all modules from queuing it for rm
readonly SIP_PROTECTED_PATHS=(
  "$HOME/Library/Caches/com.apple.HomeKit"
  "$HOME/Library/Caches/CloudKit"
  "$HOME/Library/Caches/com.apple.Safari"
  "$HOME/Library/Caches/com.apple.spotlight"
  "$HOME/Library/Caches/com.apple.Spotlight"
  "$HOME/Library/Caches/com.apple.FontRegistry"
  "$HOME/Library/Caches/com.apple.finder"
  "$HOME/Library/Caches/com.apple.homed"
  "$HOME/Library/Caches/com.apple.bird"
  "$HOME/Library/Caches/com.apple.nsurlsessiond"
  "$HOME/Library/Caches/com.apple.WebKit.Networking"
  "$HOME/Library/Caches/com.apple.ap.adprivacyd"
  "$HOME/Library/Logs"
  "/Library/Logs"
)
