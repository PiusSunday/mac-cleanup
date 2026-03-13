#!/usr/bin/env bash
# lib/utils.sh — Logging, colors, disk size, confirmation, dry-run handler

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

log::section() {
  local title="$1"
  local width=50
  local pad
  pad=$(printf '━%.0s' $(seq 1 $((width - ${#title} - 5))))
  printf "\n${BOLD}${BLUE}━━━ %s %s${RESET}\n" "$title" "$pad"
  _log_to_file "MODULE" "$title"
}

# ── Disk size utilities ───────────────────────────────────────────────────────

# Get size of a path in bytes
utils::get_size_bytes() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  # On macOS, use 'du -sk' to get kilobytes, convert to bytes.
  local size
  size=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
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

# Format bytes to human-readable (B, KB, MB, GB)
utils::format_bytes() {
  local bytes=$1
  if (( bytes >= 1073741824 )); then
    printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
  elif (( bytes >= 1048576 )); then
    printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
  elif (( bytes >= 1024 )); then
    printf "%d KB" "$(( bytes / 1024 ))"
  else
    printf "%d B" "$bytes"
  fi
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
  local pattern
  for pattern in "${WHITELIST_PATTERNS[@]}"; do
    if [[ "$path" == "$pattern" || "$path" == "${pattern}/"* ]]; then
      return 0
    fi
  done
  return 1
}

_safe_rm_check_system_path() {
  local p="$1"
  case "$p" in
    /|/System|/System/*|/bin|/bin/*|/sbin|/sbin/*|/usr/bin|/usr/bin/*|/usr/sbin|/usr/sbin/*|/usr/lib|/usr/lib/*|/etc|/etc/*|/private/etc|/private/etc/*|/Library/Extensions|/Library/Extensions/*)
      return 1
      ;;
  esac
  return 0
}

safe_rm() {
  local path="$1"
  local label="${2:-$path}"
  local options="${3:-}"
  local use_force=false
  local use_sudo=false
  local use_internal=false

  if [[ "$options" == *"force"* ]]; then
    use_force=true
  fi
  if [[ "$options" == *"sudo"* ]]; then
    use_sudo=true
  fi
  if [[ "$options" == *"internal"* ]]; then
    use_internal=true
  fi

  if [[ -z "$path" ]]; then
    log::warn "safe_rm: empty path rejected"
    return 1
  fi

  if [[ "$path" != /* ]]; then
    log::warn "safe_rm: relative path rejected: $path"
    return 1
  fi

  if [[ "$path" =~ (^|/)\.\.(/|$) ]]; then
    log::error "safe_rm: path traversal rejected: $path"
    return 1
  fi

  if [[ "$path" == *$'\n'* ]]; then
    log::error "safe_rm: control character rejected"
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

  if ! _safe_rm_check_system_path "$resolved"; then
    log::warn "safe_rm: protected system path rejected: $resolved"
    return 1
  fi

  if [[ "$use_force" != "true" ]] && utils::is_whitelisted "$resolved"; then
    log::verbose "safe_rm: whitelisted path skipped: $resolved"
    _oplog "SKIPPED" "$resolved" "whitelist"
    return 0
  fi

  if [[ "$use_sudo" != "true" ]]; then
    local parent
    parent="$(dirname "$resolved")"
    if [[ ! -w "$parent" ]]; then
      log::verbose "safe_rm: non-writable path skipped: $resolved"
      _oplog "SKIPPED" "$resolved" "permission"
      return 1
    fi
  fi

  if [[ ! -e "$resolved" ]]; then
    return 0
  fi

  local bytes
  bytes=$(utils::get_size_bytes "$resolved")
  local bytes_fmt
  bytes_fmt=$(utils::format_bytes "$bytes")

  if [[ "$DRY_RUN" == "true" && "$use_internal" != "true" ]]; then
    TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + bytes ))
    log::info "[DRY-RUN] ${bytes_fmt} ${label}"
    _oplog "DRYRUN" "$resolved" "$bytes_fmt"
    return 0
  fi

  if [[ "$use_sudo" == "true" ]]; then
    sudo rm -rf -- "$resolved" 2>/dev/null || {
      log::verbose "safe_rm: deletion failed: $resolved"
      _oplog "SKIPPED" "$resolved" "delete-failed"
      return 1
    }
  else
    rm -rf -- "$resolved" 2>/dev/null || {
      log::verbose "safe_rm: deletion failed: $resolved"
      _oplog "SKIPPED" "$resolved" "delete-failed"
      return 1
    }
  fi

  if [[ "$use_internal" == "true" ]]; then
    return 0
  fi

  TOTAL_FREED=$(( TOTAL_FREED + bytes ))
  log::success "${label} ($(utils::format_bytes "$bytes"))"
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

# Returns 0 (true) if the path is safe to attempt deletion, 1 if it should be skipped
utils::is_deletable() {
  local target="$1"

  if [[ "$target" != /* ]]; then
    return 1
  fi

  if ! _safe_rm_check_system_path "$target"; then
    log::verbose "Skipping protected path: ${target}"
    return 1
  fi

  if utils::is_whitelisted "$target"; then
    log::verbose "Skipping whitelisted path: ${target}"
    return 1
  fi

  # Check against SIP protected list
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
utils::confirm() {
  local message="$1"
  if [[ "$SKIP_CONFIRM" == "true" ]]; then
    return 0
  fi
  printf "${YELLOW}${WARN} %s [y/N]: ${RESET}" "$message"
  read -r response
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
utils::register_module() {
  local name="$1"
  local category="${2:-}"
  local scanned="${3:-0}"
  local freed="${4:-0}"
  local status="${5:-clean}"
  MODULE_NAMES+=("$name")
  MODULE_CATEGORIES+=("$category")
  MODULE_SCANNED+=("$scanned")
  MODULE_FREED+=("$freed")
  MODULE_STATUS+=("$status")
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
