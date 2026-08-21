#!/usr/bin/env bash
# lib/utils.sh — Logging, colors, disk size, confirmation, dry-run handler

# safe_rm is unusable without the protection policy, so guarantee it is loaded
# even when utils.sh is sourced directly (tests, one-off scripts).
if [[ -z "${MAC_CLEANUP_PROTECT_LOADED:-}" ]]; then
  # shellcheck source=./protect.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protect.sh"
fi

# ── ANSI Colors (terminal-aware) ──────────────────────────────────────────────
# Disable colors when stdout is not a TTY (piped or redirected)
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  CYAN=$'\033[0;36m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  BOLD=''
  DIM=''
  RESET=''
fi

# ── Symbols ───────────────────────────────────────────────────────────────────
CHECK="✔"
CROSS="✘"
ARROW="→"
INFO="ℹ"
WARN="⚠"
TRASH="🗑"

# ── v0.4.0 safety primitives ────────────────────────────────────────────────
WHITELIST_FILE="${WHITELIST_FILE:-$HOME/.config/mac-cleanup/whitelist}"
OPLOG_FILE="${OPLOG_FILE:-$HOME/.mac-cleanup/operations.log}"
LOG_FILE="${LOG_FILE:-$HOME/.mac-cleanup/cleanup.log}"

declare -a WHITELIST_PATTERNS=()

# ── Internal log-to-file helper ───────────────────────────────────────────────
_log_to_file() {
  local level="$1"
  local message="$2"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf "[%s] [%-8s] %s\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$LOG_FILE"
}

_oplog() {
  local action="$1"
  local path="$2"
  local size="$3"
  mkdir -p "$(dirname "$OPLOG_FILE")"
  printf "[%s] [%s] %s (%s)\n" \
    "$(date '+%Y-%m-%dT%H:%M:%S')" "$action" "$path" "$size" >> "$OPLOG_FILE"
}

# ── Logging functions ─────────────────────────────────────────────────────────
log::info() {
  printf "${CYAN}${INFO} %s${RESET}\n" "$1"
  _log_to_file "INFO" "$1"
}

log::success() {
  printf "${GREEN}${CHECK} %s${RESET}\n" "$1"
  _log_to_file "SUCCESS" "$1"
}

log::warn() {
  printf "${YELLOW}${WARN} %s${RESET}\n" "$1"
  _log_to_file "WARN" "$1"
}

log::error() {
  printf "${RED}${CROSS} %s${RESET}\n" "$1" >&2
  _log_to_file "ERROR" "$1"
}

log::verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    printf "${DIM}... %s${RESET}\n" "$1"
  fi
  _log_to_file "VERBOSE" "$1"
}

# One line per path that will be (or was) removed:  "   20.5 MB  Spotify cache".
#
# Modules used to print their own "→ size path" line and then safe_rm printed a
# second "[DRY-RUN] size label" line for the same path, so a full run was ~250
# lines of mostly duplicated text padded with 0 B entries. A preview has to show
# every path it would delete, so nothing is truncated — only the noise is gone.
log::item() {
  local bytes="${1:-0}"
  local label="$2"
  local silent="${3:-false}"

  # A zero-byte path frees nothing; listing it only buries the real findings.
  (( bytes > 0 )) || return 0
  [[ "$silent" == "true" && "$VERBOSE" != "true" ]] && return 0

  # A live run marks each line as done; a preview leaves the mark blank. Both
  # keep the size column in the same place so the two modes line up visually.
  local mark="  "
  [[ "$DRY_RUN" != "true" ]] && mark="${GREEN}${CHECK}${RESET} "

  printf '  %s%s%10s%s  %s\n' "$mark" "${CYAN}" "$(utils::format_bytes "$bytes")" "${RESET}" "$label"
  _log_to_file "ITEM" "$(utils::format_bytes "$bytes") ${label}"
}

log::section() {
  local title="$1"
  local width=50
  local pad
  pad=$(printf '━%.0s' $(seq 1 $((width - ${#title} - 5))))
  printf "\n${BOLD}${BLUE}━━━ %s %s${RESET}\n" "$title" "$pad"
  _log_to_file "MODULE" "$title"
}

# ── Disk size utilities ───────────────────────────────────────────────────────

# Run a command with a wall-clock limit. Uses perl's alarm(), which is present
# on every macOS install — coreutils `timeout` is not.
# Returns 124 on timeout, mirroring GNU timeout.
utils::run_timed() {
  local secs="$1"
  shift
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@"
    return $?
  fi
  "$@"
}

# Get size of a path in bytes.
#   -P  never follow symlinks (a symlinked cache must not bill its target)
#   -x  stay on one filesystem (never walk into a mounted volume or network share)
# A stalled network mount used to hang the whole run here, so du is time-boxed.
utils::get_size_bytes() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi

  local size
  size=$(utils::run_timed "${MAC_CLEANUP_DU_TIMEOUT:-20}" du -skPx "$path" 2>/dev/null | awk 'NR==1 {print $1}')
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    log::verbose "size probe timed out or failed: ${path}"
    echo 0
    return 0
  fi
  echo $((size * 1024))
}

utils::realpath() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null && return 0
  fi
  if [[ -e "$path" ]]; then
    local dir base
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    (cd "$dir" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "$base") && return 0
  fi
  return 1
}

# Get free disk bytes on /
utils::get_free_bytes() {
  df -k / | awk 'NR==2 {print $4 * 1024}'
}

# Format bytes to human-readable (B, KB, MB, GB, TB).
# Pure integer arithmetic — no bc fork and no locale-sensitive float parsing,
# which is what made this crash on hosts with comma decimal separators.
utils::format_bytes() {
  local bytes=${1:-0}
  [[ "$bytes" =~ ^-?[0-9]+$ ]] || bytes=0

  local unit div
  if   (( bytes >= 1099511627776 )); then unit="TB"; div=1099511627776
  elif (( bytes >= 1073741824 ));    then unit="GB"; div=1073741824
  elif (( bytes >= 1048576 ));       then unit="MB"; div=1048576
  elif (( bytes >= 1024 ));          then printf "%d KB" "$(( bytes / 1024 ))"; return
  else                                    printf "%d B" "$bytes"; return
  fi

  # One decimal place, rounded half-up, entirely in integer math.
  local scaled=$(( (bytes * 10 + div / 2) / div ))
  printf "%d.%d %s" "$(( scaled / 10 ))" "$(( scaled % 10 ))" "$unit"
}

utils::load_whitelist() {
  WHITELIST_PATTERNS=(
    "$HOME/Library/Caches/com.apple.FontRegistry"
    "$HOME/Library/Caches/com.apple.Spotlight"
    "$HOME/Library/Caches/com.apple.spotlight"
    "$HOME/Library/Caches/CloudKit"
    "$HOME/Library/Caches/com.apple.finder"
    "$HOME/Library/Mobile Documents"
    "$HOME/.ollama/models"
    "$HOME/.cache/huggingface"
  )

  if [[ -f "$WHITELIST_FILE" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      line="${line/#\~/$HOME}"
      WHITELIST_PATTERNS+=("$line")
    done < "$WHITELIST_FILE"
  fi
}

utils::is_whitelisted() {
  local path="$1"

  # macOS ships bash 3.2, where "${arr[@]}" on an empty array is an unbound
  # variable under `set -u` and aborts the run. The whitelist is empty whenever
  # utils::load_whitelist has not run yet.
  (( ${#WHITELIST_PATTERNS[@]} > 0 )) || return 1

  local pattern
  for pattern in "${WHITELIST_PATTERNS[@]}"; do
    if [[ "$path" == "$pattern" || "$path" == "${pattern}/"* ]]; then
      return 0
    fi
  done
  return 1
}

# Retained for backwards compatibility with older module code and tests.
# The authoritative policy now lives in lib/core/protect.sh.
_safe_rm_check_system_path() {
  protect::_is_system_path "$1" && return 1
  return 0
}

# Bytes the most recent safe_rm accepted; 0 when the path was protected,
# whitelisted, already claimed by another module, or unwritable. Modules add
# this to their scanned total instead of their own du result, which is what
# keeps the report's Found column equal to Reclaimable.
SAFE_RM_LAST_BYTES=0

# Counters surfaced in the summary report.
TOTAL_PROTECTED=0
TOTAL_PROTECTED_BYTES=0
TOTAL_DEDUPED=0

safe_rm() {
  local path="$1"
  local label="${2:-$path}"
  local options="${3:-}"
  local use_force=false
  local use_sudo=false
  local use_internal=false
  local use_silent=false

  SAFE_RM_LAST_BYTES=0

  if [[ "$options" == *"force"* ]]; then
    use_force=true
  fi
  if [[ "$options" == *"sudo"* ]]; then
    use_sudo=true
  fi
  if [[ "$options" == *"internal"* ]]; then
    use_internal=true
  fi
  if [[ "$options" == *"silent"* ]]; then
    use_silent=true
  fi

  if [[ -z "$path" ]]; then
    log::warn "safe_rm: empty path rejected"
    return 1
  fi

  if [[ "$path" != /* ]]; then
    log::warn "safe_rm: relative path rejected: $path"
    return 1
  fi

  local resolved="$path"
  if [[ -L "$path" ]]; then
    resolved="$(utils::realpath "$path" || echo "")"
    if [[ -z "$resolved" ]]; then
      log::warn "safe_rm: unresolved symlink rejected: $path"
      return 1
    fi
  fi

  if [[ ! -e "$resolved" ]]; then
    return 0
  fi

  # Internal bookkeeping deletions (temp files this tool created) bypass the
  # policy and the ledger entirely — they are never user data and never counted.
  if [[ "$use_internal" == "true" ]]; then
    rm -rf -- "$resolved" 2>/dev/null || true
    return 0
  fi

  # ── Protection policy ──
  # Runs before the size probe so a protected path costs no du walk.
  if ! protect::verdict "$resolved"; then
    : # eligible
  else
    local reason="$PROTECT_REASON"
    TOTAL_PROTECTED=$(( TOTAL_PROTECTED + 1 ))
    log::verbose "safe_rm: protected (${reason}): $resolved"
    _oplog "PROTECTED" "$resolved" "$reason"
    if [[ "$VERBOSE" == "true" ]]; then
      log::info "  ${DIM}Protected (${reason}): ${label}${RESET}"
    fi
    return 0
  fi

  if [[ "$use_force" != "true" ]] && utils::is_whitelisted "$resolved"; then
    log::verbose "safe_rm: whitelisted path skipped: $resolved"
    _oplog "SKIPPED" "$resolved" "whitelist"
    TOTAL_PROTECTED=$(( TOTAL_PROTECTED + 1 ))
    return 0
  fi

  # ── Claim ledger ──
  # Modules overlap on purpose; the bytes must only be counted once so the
  # dry-run preview matches what a live run can actually free.
  if ! protect::claim "$resolved"; then
    TOTAL_DEDUPED=$(( TOTAL_DEDUPED + 1 ))
    log::verbose "safe_rm: already accounted for this run: $resolved"
    return 0
  fi

  local bytes
  bytes=$(utils::get_size_bytes "$resolved")
  local bytes_fmt
  bytes_fmt=$(utils::format_bytes "$bytes")

  if [[ "$use_sudo" != "true" ]]; then
    local parent
    parent="$(dirname "$resolved")"
    if [[ ! -w "$parent" ]]; then
      log::verbose "safe_rm: non-writable path skipped: $resolved"
      _oplog "SKIPPED" "$resolved" "permission"
      if [[ "$DRY_RUN" == "true" ]]; then
        log::info "[DRY-RUN] ${bytes_fmt} ${label} (Skipped: Permission Denied)"
      fi
      return 0
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + bytes ))
    SAFE_RM_LAST_BYTES=$bytes
    log::item "$bytes" "$label" "$use_silent"
    _oplog "DRYRUN" "$resolved" "$bytes_fmt"
    return 0
  fi

  if [[ "$use_sudo" == "true" ]]; then
    sudo rm -rf -- "$resolved" 2>/dev/null || {
      log::verbose "safe_rm: deletion failed: $resolved"
      _oplog "SKIPPED" "$resolved" "delete-failed"
      if [[ "$DRY_RUN" != "true" ]]; then
        log::warn "Skipped: ${label} (deletion failed/in use)"
      fi
      return 0
    }
  else
    rm -rf -- "$resolved" 2>/dev/null || {
      log::verbose "safe_rm: deletion failed: $resolved"
      _oplog "SKIPPED" "$resolved" "delete-failed"
      if [[ "$DRY_RUN" != "true" ]]; then
        log::warn "Skipped: ${label} (deletion failed/in use)"
      fi
      return 0
    }
  fi

  TOTAL_FREED=$(( TOTAL_FREED + bytes ))
  SAFE_RM_LAST_BYTES=$bytes
  log::item "$bytes" "$label" "$use_silent"
  _oplog "REMOVED" "$resolved" "$bytes_fmt"
  return 0
}

safe_rm_internal() {
  local path="$1"
  safe_rm "$path" "internal" "internal"
}

safe_rm_contents() {
  local dir="$1"
  local label_prefix="${2:-$dir}"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r item; do
    safe_rm "$item" "${label_prefix}: $(basename "$item")"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null || true)
}

safe_rm_cmd() {
  local pretty_cmd
  pretty_cmd="$(printf "%q " "$@")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log::info "[DRY-RUN] Would execute: ${pretty_cmd}"
    _oplog "DRYRUN" "$pretty_cmd" "command"
    return 0
  fi
  "$@"
}

# ── Dry-run handler ───────────────────────────────────────────────────────────
# Every destructive operation must go through this function.
dry_run_or_exec() {
  # Build a safely-escaped representation of the command for logging only.
  local pretty_cmd
  pretty_cmd="$(printf "%q " "$@")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log::info "[DRY-RUN] Would execute: ${DIM}${pretty_cmd}${RESET}"
    return 0
  fi
  log::verbose "Executing: ${pretty_cmd}"
  # Execute and capture stderr — only surface non-permission errors
  local stderr_output
  stderr_output=$("$@" 2>&1 >/dev/null) || {
    if [[ "$stderr_output" != *"Operation not permitted"* && \
          "$stderr_output" != *"Permission denied"* ]]; then
      log::warn "Command failed: $stderr_output"
    else
      log::verbose "Skipped (permission denied): $pretty_cmd"
    fi
  }
}

# Returns 0 (true) if the path is safe to attempt deletion, 1 if it should be skipped.
# This is the cheap pre-filter modules use to avoid sizing a path they can never
# remove; safe_rm re-checks the same policy before it deletes anything.
utils::is_deletable() {
  local target="$1"

  if protect::verdict "$target"; then
    log::verbose "Skipping protected path (${PROTECT_REASON}): ${target}"
    return 1
  fi

  if utils::is_whitelisted "$target"; then
    log::verbose "Skipping whitelisted path: ${target}"
    return 1
  fi

  local protected
  (( ${#SIP_PROTECTED_PATHS[@]} > 0 )) || return 0
  for protected in "${SIP_PROTECTED_PATHS[@]}"; do
    if [[ "$target" == "$protected" || "$target" == "${protected}/"* ]]; then
      log::verbose "Skipping SIP-protected path: ${target}"
      return 1
    fi
  done

  # Check write permission on the parent directory
  local parent
  parent="$(dirname "$target")"
  if [[ ! -w "$parent" ]]; then
    log::verbose "Skipping non-writable path: ${target}"
    return 1
  fi

  return 0
}

utils::show_operation_log() {
  if [[ ! -f "$OPLOG_FILE" ]]; then
    log::info "No operation log found at ${OPLOG_FILE}"
    return 0
  fi
  cat "$OPLOG_FILE"
}

# ── Confirmation prompt ───────────────────────────────────────────────────────
# A preview must never block on input, so dry-run answers "no" without asking.
# Modules still report what a live run would offer to remove.
# A non-interactive shell also declines rather than hanging a CI job forever.
utils::confirm() {
  local message="$1"

  if [[ "$DRY_RUN" == "true" ]]; then
    log::verbose "confirm skipped in dry-run: ${message}"
    return 1
  fi

  if [[ "$SKIP_CONFIRM" == "true" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]] && [[ ! -r /dev/tty ]]; then
    log::warn "Non-interactive shell — declining: ${message}"
    return 1
  fi

  printf "${YELLOW}${WARN} %s [y/N]: ${RESET}" "$message"
  local response=""
  if [[ -t 0 ]]; then
    read -r response
  else
    read -r response < /dev/tty
  fi
  [[ "$response" =~ ^[Yy]$ ]]
}

# ── Dependency checker ────────────────────────────────────────────────────────
utils::require() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    log::warn "${cmd} not found — skipping ${cmd}-dependent operations."
    return 1
  fi
  return 0
}

# ── macOS version check ───────────────────────────────────────────────────────
utils::check_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log::error "mac-cleanup only supports macOS."
    exit 1
  fi

  local macos_version
  macos_version=$(sw_vers -productVersion)
  local major
  major=$(echo "$macos_version" | cut -d. -f1)

  if (( major < 12 )); then
    log::warn "macOS ${macos_version} may not be fully supported. Recommend macOS 12+."
  fi
}

# ── Spinner for long-running operations ───────────────────────────────────────
utils::spinner() {
  local pid=$1
  local msg="$2"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${CYAN}${spin:$((i % ${#spin})):1}${RESET} %s" "$msg"
    (( i++ )) || true
    sleep 0.1
  done
  printf "\r\033[K"  # Clear the spinner line
}

# Run a command with a spinner. Falls back to plain log if not a TTY.
utils::with_spinner() {
  local msg="$1"
  shift

  # Non-TTY: run command normally, preserve exit code but suppress output.
  if [[ ! -t 1 ]]; then
    log::info "$msg"
    local exit_code=0
    if "$@" >/dev/null 2>&1; then
      log::success "$msg"
      return 0
    else
      exit_code=$?
      log::error "$msg (command failed with exit code ${exit_code})"
      return "$exit_code"
    fi
  fi

  # TTY: show spinner while command runs; capture stderr so it can be shown on failure.
  local stderr_file
  stderr_file=$(mktemp "${TMPDIR:-/tmp}/with_spinner_stderr.XXXXXX") || {
    # If we cannot create a temp file, fall back to running without a spinner.
    log::info "$msg"
    local exit_code=0
    if "$@" >/dev/null; then
      log::success "$msg"
      return 0
    else
      exit_code=$?
      log::error "$msg (command failed with exit code ${exit_code})"
      return "$exit_code"
    fi
  }

  "$@" > /dev/null 2>"$stderr_file" &
  local pid=$!
  utils::spinner "$pid" "$msg"

  local exit_code=0
  if wait "$pid"; then
    exit_code=0
  else
    exit_code=$?
  fi

  if (( exit_code == 0 )); then
    safe_rm_internal "$stderr_file"
    log::success "$msg"
    return 0
  else
    if [[ -s "$stderr_file" ]]; then
      cat "$stderr_file" >&2
    fi
    safe_rm_internal "$stderr_file"
    log::error "$msg (command failed with exit code ${exit_code})"
    return "$exit_code"
  fi
}

# ── Per-module tracking ───────────────────────────────────────────────────────
# Each module calls this at the end of its ::clean function to register results.
# Category: "System", "Developer Tools", "Caches & Logs", "Storage Management"
# Status: "clean", "skipped", "review", or byte count (means reclaimable)
# Claim count at the point the previous module registered. The delta is how
# many paths this module actually queued, which is the honest "items" figure —
# it excludes anything protected, whitelisted or already counted elsewhere.
_LAST_MODULE_CLAIM_MARK=0

utils::register_module() {
  local name="$1"
  local category="${2:-}"
  local scanned="${3:-0}"
  local freed="${4:-0}"
  local status="${5:-clean}"
  local projected="${6:-}"
  local items="${7:-}"

  if [[ -z "$items" ]]; then
    items=$(( PROTECT_CLAIM_COUNT - _LAST_MODULE_CLAIM_MARK ))
    (( items < 0 )) && items=0
  fi
  _LAST_MODULE_CLAIM_MARK=$PROTECT_CLAIM_COUNT

  if [[ -z "$projected" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      if [[ "$status" =~ ^[0-9]+$ ]]; then
        projected="$status"
      else
        projected="0"
      fi
    else
      projected="$freed"
    fi
  fi

  # Support mode-aware status conversion
  if [[ "$status" =~ ^[0-9]+$ ]]; then
    if (( status > 0 )); then
      if [[ "$DRY_RUN" == "true" ]]; then
        status="Pending"
      else
        status="done"
      fi
    else
      status="clean"
    fi
  fi

  MODULE_NAMES+=("$name")
  MODULE_CATEGORIES+=("$category")
  MODULE_SCANNED+=("$scanned")
  MODULE_FREED+=("$freed")
  MODULE_STATUS+=("$status")
  MODULE_PROJECTED+=("$projected")
  MODULE_ITEMS+=("$items")
}

# Record something the user could reclaim but that needs an explicit opt-in.
# Rendered as the report's "needs your decision" block.
utils::register_action() {
  local label="$1"
  local bytes="${2:-0}"
  local command="${3:-}"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0

  ACTION_LABELS+=("$label")
  ACTION_BYTES+=("$bytes")
  ACTION_COMMANDS+=("$command")
}

# ── Category header ──────────────────────────────────────────────────────────
# Top-level grouping header, visually distinct from module log::section.
log::category() {
  local title="$1"
  printf '\n%s%s▶ %s%s\n' "${BOLD}" "${CYAN}" "$title" "${RESET}"
  _log_to_file "CATEGORY" "$title"
}

# ── Module summary line ──────────────────────────────────────────────────────
# Print a one-line result at the end of each module's output.
module_summary() {
  local name="$1"
  local bytes="${2:-0}"
  if (( bytes == 0 )); then
    log::success "  ${name} → Nothing to clean"
  else
    log::success "  ${name} → $(utils::format_bytes "$bytes") reclaimable"
  fi
}

# ── System context header ────────────────────────────────────────────────────
# Replaces the bare version line with a rich context block.
utils::print_system_context() {
  local arch
  case "$(uname -m)" in
    arm64) arch="Apple Silicon" ;;
    x86_64) arch="Intel" ;;
    *) arch="$(uname -m)" ;;
  esac

  local macos_ver
  macos_ver=$(sw_vers -productVersion 2>/dev/null || echo "unknown")

  local free_space
  free_space=$(utils::format_bytes "$(utils::get_free_bytes)")

  local user_mode="User mode"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    user_mode="${YELLOW}Admin (sudo)${RESET}"
  fi

  printf '\n%s🧹 mac-cleanup v%s%s\n' "${BOLD}" "$VERSION" "${RESET}"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '%s%s  DRY-RUN mode — no files will be deleted%s\n' "${YELLOW}" "${WARN}" "${RESET}"
  fi
  printf '\n  %s  |  macOS %s  |  Free: %s  |  %s\n' "$arch" "$macos_ver" "$free_space" "$user_mode"
}
