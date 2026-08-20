#!/usr/bin/env bash
# lib/system_deep.sh — Deep age-gated system cleanup

readonly DEEP_LOG_AGE_DAYS=14
readonly DEEP_TMP_AGE_DAYS=7
readonly DEEP_CRASH_AGE_DAYS=14

_SYSTEM_DEEP_TOTAL=0
_SYSTEM_DEEP_CAN_USE_SUDO=false

system_deep::clean() {
  log::section "Deep System Cleanup"

  _SYSTEM_DEEP_TOTAL=0
  _SYSTEM_DEEP_CAN_USE_SUDO=false
  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  if sudo -n true 2>/dev/null; then
    _SYSTEM_DEEP_CAN_USE_SUDO=true
  elif [[ "$DRY_RUN" == "true" ]]; then
    log::verbose "Deep System dry-run: skipping sudo authentication; protected items may be omitted."
  else
    log::info "Deep System cleanup targets require administrator privileges."
    log::info "If prompted, please authenticate to allow full log clearing."
    if sudo -v 2>/dev/null; then
      _SYSTEM_DEEP_CAN_USE_SUDO=true
    else
      log::warn "Sudo access denied/skipped. Protected items will be skipped."
    fi
  fi

  system_deep::_unified_logs
  system_deep::_power_logs
  system_deep::_memory_exception_reports
  system_deep::_var_log_rotated
  system_deep::_private_tmp
  system_deep::_os_installer_leftovers
  system_deep::_safari_content_cache
  system_deep::_browser_code_sign_caches

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  module_summary "Deep System" "$_SYSTEM_DEEP_TOTAL"

  local status="clean"
  if (( _SYSTEM_DEEP_TOTAL > 0 )); then
    status="$_SYSTEM_DEEP_TOTAL"
  fi

  utils::register_module "Deep System" "System" "$_SYSTEM_DEEP_TOTAL" "$freed" "$status" "$projected"
}

system_deep::_add_scanned() {
  local bytes="$1"
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    _SYSTEM_DEEP_TOTAL=$(( _SYSTEM_DEEP_TOTAL + bytes ))
  fi
}

# Age-gated bulk sweeps match hundreds of interchangeable files — 204 rotated
# temp files under /private/tmp on the development machine, every one labelled
# identically. Listing each is noise, not transparency, so the default is one
# rolled-up line per sweep and --verbose still prints every path. Nothing is
# truncated in either mode.
system_deep::_sweep_summary() {
  local label="$1"
  local count="$2"
  local bytes="$3"

  (( count > 0 )) || return 0
  if (( count == 1 )); then
    log::info "${label}: 1 file ($(utils::format_bytes "$bytes"))"
  else
    log::info "${label}: ${count} files ($(utils::format_bytes "$bytes"))"
  fi
}

system_deep::_delete_by_find() {
  local base="$1"
  local label="$2"
  local age_days="$3"
  local use_sudo="${4:-false}"
  shift 4

  [[ -d "$base" ]] || return 0

  local find_cmd=()
  if [[ "$use_sudo" == "true" && "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
    find_cmd=(sudo find "$base" -type f)
  else
    find_cmd=(find "$base" -type f)
  fi
  
  if (( $# > 0 )); then
    find_cmd+=("$@")
  fi
  find_cmd+=(-mtime "+${age_days}" -print)

  local count=0
  local bytes=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ "$use_sudo" == "true" && "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
      safe_rm "$file" "${label}: $(basename "$file")" "sudo silent"
    else
      safe_rm "$file" "${label}: $(basename "$file")" "silent"
    fi
    (( SAFE_RM_LAST_BYTES > 0 )) || continue
    system_deep::_add_scanned "$SAFE_RM_LAST_BYTES"
    bytes=$(( bytes + SAFE_RM_LAST_BYTES ))
    (( count++ )) || true
  done < <("${find_cmd[@]}" 2>/dev/null || true)

  system_deep::_sweep_summary "$label" "$count" "$bytes"
}

system_deep::_unified_logs() {
  local base="/private/var/db/diagnostics"
  [[ -d "$base" ]] || return 0
  log::info "Unified logs: scanning trace archives older than ${DEEP_LOG_AGE_DAYS} days"

  local count=0
  local bytes=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
      safe_rm "$file" "Unified log: $(basename "$file")" "sudo silent"
    else
      safe_rm "$file" "Unified log: $(basename "$file")" "silent"
    fi
    (( SAFE_RM_LAST_BYTES > 0 )) || continue
    system_deep::_add_scanned "$SAFE_RM_LAST_BYTES"
    bytes=$(( bytes + SAFE_RM_LAST_BYTES ))
    (( count++ )) || true
  done < <(
    if [[ "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
      sudo find "$base" -type f \( -name "*.tracev3" -o -name "*.logdata" \) -mtime "+${DEEP_LOG_AGE_DAYS}" -print 2>/dev/null || true
    else
      find "$base" -type f \( -name "*.tracev3" -o -name "*.logdata" \) -mtime "+${DEEP_LOG_AGE_DAYS}" -print 2>/dev/null || true
    fi
  )

  system_deep::_sweep_summary "Unified logs" "$count" "$bytes"
}

system_deep::_power_logs() {
  system_deep::_delete_by_find "/private/var/db/powerlog" "Power log" "$DEEP_LOG_AGE_DAYS" true
}

system_deep::_memory_exception_reports() {
  system_deep::_delete_by_find "/private/var/db/reportmemoryexception" "Memory exception report" "$DEEP_LOG_AGE_DAYS" true
}

system_deep::_var_log_rotated() {
  local base="/private/var/log"
  [[ -d "$base" ]] || return 0

  local count=0
  local bytes=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
      safe_rm "$file" "Rotated log: $(basename "$file")" "sudo silent"
    else
      safe_rm "$file" "Rotated log: $(basename "$file")" "silent"
    fi
    (( SAFE_RM_LAST_BYTES > 0 )) || continue
    system_deep::_add_scanned "$SAFE_RM_LAST_BYTES"
    bytes=$(( bytes + SAFE_RM_LAST_BYTES ))
    (( count++ )) || true
  done < <(
    if [[ "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
      sudo find "$base" -type f \( -name "*.gz" -o -name "*.asl" -o -name "*.log" \) -mtime "+${DEEP_LOG_AGE_DAYS}" -print 2>/dev/null || true
    else
      find "$base" -type f \( -name "*.gz" -o -name "*.asl" -o -name "*.log" \) -mtime "+${DEEP_LOG_AGE_DAYS}" -print 2>/dev/null || true
    fi
  )

  system_deep::_sweep_summary "Rotated system logs" "$count" "$bytes"
}

system_deep::_private_tmp() {
  system_deep::_delete_by_find "/private/tmp" "Private tmp" "$DEEP_TMP_AGE_DAYS" true
}

system_deep::_os_installer_leftovers() {
  local installer
  # Enable nullglob to avoid literal output if no match
  shopt -s nullglob
  for installer in /Applications/Install\ macOS*.app ~/Downloads/Install\ macOS*.app ~/Downloads/Install*.pkg; do
    [[ -e "$installer" ]] || continue

    if pgrep -f "$installer" >/dev/null 2>&1; then
      continue
    fi

    local age_days
    age_days=$(( ( $(date +%s) - $(stat -f%m "$installer" 2>/dev/null || echo 0) ) / 86400 ))
    if (( age_days < 14 )); then
      continue
    fi

    local size
    size=$(utils::get_size_bytes "$installer")
    system_deep::_add_scanned "$size"
    safe_rm "$installer" "Old macOS installer: $(basename "$installer")"
  done
  shopt -u nullglob

  if [[ -d "/macOS Install Data" ]]; then
    local age_days
    age_days=$(( ( $(date +%s) - $(stat -f%m "/macOS Install Data" 2>/dev/null || echo 0) ) / 86400 ))
    if (( age_days >= 14 )); then
      local size
      size=$(utils::get_size_bytes "/macOS Install Data")
      system_deep::_add_scanned "$size"
      if [[ "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
        safe_rm "/macOS Install Data" "macOS Install Data" "sudo"
      else
        safe_rm "/macOS Install Data" "macOS Install Data"
      fi
    fi
  fi
}

system_deep::_safari_content_cache() {
  local safari_cache="$HOME/Library/Caches/com.apple.Safari/fsCachedData"
  [[ -d "$safari_cache" ]] || return 0

  local size
  size=$(utils::get_size_bytes "$safari_cache")
  system_deep::_add_scanned "$size"
  safe_rm "$safari_cache" "Safari content cache"
}

system_deep::_browser_code_sign_caches() {
  local base="/Library/Caches/com.apple.nsurlsessiond/Downloads"
  [[ -d "$base" ]] || return 0

  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    local size
    size=$(utils::get_size_bytes "$dir")
    system_deep::_add_scanned "$size"
    if [[ "${_SYSTEM_DEEP_CAN_USE_SUDO:-false}" == "true" ]]; then
      safe_rm "$dir" "Browser code sign cache ($dir)" "sudo"
    else
      safe_rm "$dir" "Browser code sign cache ($dir)"
    fi
  done < <(find "$base" -maxdepth 2 -type d \( -name "com.google.Chrome" -o -name "com.microsoft.edgemac" \) 2>/dev/null || true)
}
