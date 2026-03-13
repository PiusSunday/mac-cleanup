#!/usr/bin/env bash
# lib/system_deep.sh — Deep age-gated system cleanup

readonly DEEP_LOG_AGE_DAYS=30
readonly DEEP_TMP_AGE_DAYS=7
readonly DEEP_CRASH_AGE_DAYS=14

_SYSTEM_DEEP_TOTAL=0

system_deep::clean() {
  log::section "Deep System Cleanup"

  _SYSTEM_DEEP_TOTAL=0
  local disk_before
  disk_before=$(utils::get_free_bytes)

  system_deep::_unified_logs
  system_deep::_power_logs
  system_deep::_memory_exception_reports
  system_deep::_var_log_rotated
  system_deep::_private_tmp
  system_deep::_os_installer_leftovers
  system_deep::_broken_preferences
  system_deep::_safari_content_cache

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then
    freed=0
  fi

  module_summary "Deep System" "$_SYSTEM_DEEP_TOTAL"

  local status="clean"
  if (( _SYSTEM_DEEP_TOTAL > 0 )); then
    status="$_SYSTEM_DEEP_TOTAL"
  fi

  utils::register_module "Deep System" "System" "$_SYSTEM_DEEP_TOTAL" "$freed" "$status"
}

system_deep::_add_scanned() {
  local bytes="$1"
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    _SYSTEM_DEEP_TOTAL=$(( _SYSTEM_DEEP_TOTAL + bytes ))
  fi
}

system_deep::_delete_by_find() {
  local base="$1"
  local label="$2"
  local age_days="$3"
  local use_sudo="${4:-false}"
  shift 4

  [[ -d "$base" ]] || return 0

  local find_cmd=(find "$base" -type f)
  if (( $# > 0 )); then
    find_cmd+=("$@")
  fi
  find_cmd+=(-mtime "+${age_days}" -print)

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local size
    size=$(utils::get_size_bytes "$file")
    system_deep::_add_scanned "$size"
    if [[ "$use_sudo" == "true" ]]; then
      safe_rm "$file" "$label" "sudo"
    else
      safe_rm "$file" "$label"
    fi
  done < <("${find_cmd[@]}" 2>/dev/null || true)
}

system_deep::_unified_logs() {
  local base="/private/var/db/diagnostics"
  [[ -d "$base" ]] || return 0
  log::info "Unified logs: scanning trace archives older than ${DEEP_LOG_AGE_DAYS} days"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local size
    size=$(utils::get_size_bytes "$file")
    system_deep::_add_scanned "$size"
    safe_rm "$file" "Unified log archive" "sudo"
  done < <(find "$base" -type f \( -name "*.tracev3" -o -name "*.logdata" \) -mtime "+${DEEP_LOG_AGE_DAYS}" -print 2>/dev/null || true)
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

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local size
    size=$(utils::get_size_bytes "$file")
    system_deep::_add_scanned "$size"
    safe_rm "$file" "Rotated system log" "sudo"
  done < <(find "$base" -type f \( -name "*.gz" -o -name "*.asl" -o -name "*.log" \) -mtime "+${DEEP_LOG_AGE_DAYS}" -print 2>/dev/null || true)
}

system_deep::_private_tmp() {
  system_deep::_delete_by_find "/private/tmp" "Private tmp" "$DEEP_TMP_AGE_DAYS" true
}

system_deep::_os_installer_leftovers() {
  local installer
  for installer in /Applications/Install\ macOS*.app; do
    [[ -d "$installer" ]] || continue

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
    safe_rm "$installer" "Old macOS installer"
  done

  if [[ -d "/macOS Install Data" ]]; then
    local age_days
    age_days=$(( ( $(date +%s) - $(stat -f%m "/macOS Install Data" 2>/dev/null || echo 0) ) / 86400 ))
    if (( age_days >= 14 )); then
      local size
      size=$(utils::get_size_bytes "/macOS Install Data")
      system_deep::_add_scanned "$size"
      safe_rm "/macOS Install Data" "macOS Install Data" "sudo"
    fi
  fi
}

system_deep::_broken_preferences() {
  local prefs="$HOME/Library/Preferences"
  [[ -d "$prefs" ]] || return 0

  while IFS= read -r plist; do
    [[ -f "$plist" ]] || continue
    local name
    name=$(basename "$plist")
    case "$name" in
      com.apple.*|.GlobalPreferences*|loginwindow.plist)
        continue
        ;;
    esac

    if plutil -lint "$plist" >/dev/null 2>&1; then
      continue
    fi

    local size
    size=$(utils::get_size_bytes "$plist")
    system_deep::_add_scanned "$size"
    safe_rm "$plist" "Corrupted preference"
  done < <(find "$prefs" -maxdepth 1 -name "*.plist" -type f 2>/dev/null || true)
}

system_deep::_safari_content_cache() {
  local safari_cache="$HOME/Library/Caches/com.apple.Safari/fsCachedData"
  [[ -d "$safari_cache" ]] || return 0

  local size
  size=$(utils::get_size_bytes "$safari_cache")
  system_deep::_add_scanned "$size"
  safe_rm "$safari_cache" "Safari content cache"
}
