#!/usr/bin/env bash
# lib/system.sh — System-level scans: crash reports, logs, .DS_Store, Trash,
#                 dev tool caches, and System Data clues.
# Runs automatically as first step regardless of selected modules.

# Public entry point
system::clean() {
  log::section "System Scan"

  local module_scanned=0

  local disk_before
  disk_before=$(utils::get_free_bytes)

  system::_crash_reports
  module_scanned=$(( module_scanned + _SYS_CRASH_TOTAL ))

  system::_system_logs

  system::_ds_store
  module_scanned=$(( module_scanned + _SYS_DSSTORE_TOTAL ))

  system::_trash
  module_scanned=$(( module_scanned + _SYS_TRASH_TOTAL ))

  system::_dev_tool_caches
  module_scanned=$(( module_scanned + _SYS_DEVCACHE_TOTAL ))

  system::_system_data_clues

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "System" "$module_scanned"

  # Determine status
  local status="clean"
  if (( module_scanned > 0 )); then
    status="$module_scanned"
  fi
  # If system data clues were found, add review status
  if [[ "${_SYS_HAS_CLUES:-false}" == "true" ]]; then
    status="review"
  fi

  utils::register_module "System" "System" "$module_scanned" "$freed" "$status"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

_SYS_CRASH_TOTAL=0
_SYS_DSSTORE_TOTAL=0
_SYS_TRASH_TOTAL=0
_SYS_DEVCACHE_TOTAL=0
_SYS_HAS_CLUES=false

# ── a) Crash reports ─────────────────────────────────────────────────────────
system::_crash_reports() {
  _SYS_CRASH_TOTAL=0
  local total_count=0
  local total_bytes=0

  local paths=(
    "/Library/Logs/DiagnosticReports"
    "$HOME/Library/Logs/DiagnosticReports"
  )

  for path in "${paths[@]}"; do
    if [[ ! -d "$path" ]]; then
      log::verbose "Crash reports dir not found: ${path}"
      continue
    fi

    local count=0
    local dir_bytes=0
    while IFS= read -r file; do
      local fbytes
      fbytes=$(utils::get_size_bytes "$file")
      dir_bytes=$(( dir_bytes + fbytes ))
      (( count++ )) || true
      dry_run_or_exec rm -f "$file"
    done < <(find "$path" -maxdepth 1 \( -name "*.crash" -o -name "*.ips" -o -name "*.hang" \) -type f 2>/dev/null || true)

    total_count=$(( total_count + count ))
    total_bytes=$(( total_bytes + dir_bytes ))
  done

  _SYS_CRASH_TOTAL=$total_bytes

  if (( total_count > 0 )); then
    log::info "Crash reports: ${total_count} files ($(utils::format_bytes "$total_bytes"))"
  else
    log::info "Crash reports: none found."
  fi
}

# ── b) System logs ───────────────────────────────────────────────────────────
system::_system_logs() {
  local path="/private/var/log"
  if [[ ! -r "$path" ]]; then
    log::info "System logs: not accessible (requires sudo) — skipping."
    return 0
  fi

  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  local size_fmt
  size_fmt=$(utils::format_bytes "$size_bytes")
  log::info "System logs: ${size_fmt} (read-only report — cleaning via this tool is not supported)"
}

# ── c) .DS_Store files ───────────────────────────────────────────────────────
system::_ds_store() {
  _SYS_DSSTORE_TOTAL=0
  log::info "Scanning for .DS_Store files..."

  local count=0
  local total_bytes=0
  local skipped=0
  while IFS= read -r file; do
    local fbytes
    fbytes=$(utils::get_size_bytes "$file")
    total_bytes=$(( total_bytes + fbytes ))
    (( count++ )) || true
    if [[ "$DRY_RUN" == "true" ]]; then
      log::info "[DRY-RUN] Would execute: rm -f ${file}"
    else
      if ! rm -f "$file" 2>/dev/null; then
        log::verbose "  Skipped (permission denied): $file"
        (( skipped++ )) || true
      fi
    fi
  done < <(find "$HOME" -maxdepth 4 -name ".DS_Store" -type f 2>/dev/null || true)

  _SYS_DSSTORE_TOTAL=$total_bytes

  if (( count > 0 )); then
    local msg
    msg=".DS_Store: ${count} files ($(utils::format_bytes "$total_bytes"))"
    if (( skipped > 0 )); then
      msg="${msg} — ${skipped} skipped (protected by macOS)"
    fi
    log::info "$msg"
  else
    log::info ".DS_Store: none found."
  fi
}

# ── d) Trash ─────────────────────────────────────────────────────────────────
system::_trash() {
  _SYS_TRASH_TOTAL=0
  local path="$HOME/.Trash"
  if [[ ! -d "$path" ]]; then
    log::info "Trash: empty."
    return 0
  fi

  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  _SYS_TRASH_TOTAL=$size_bytes

  if (( size_bytes == 0 )); then
    log::info "Trash: empty."
    return 0
  fi

  log::info "Trash: $(utils::format_bytes "$size_bytes")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log::info "[DRY-RUN] Would empty Trash via Finder"
  else
    utils::with_spinner "Emptying Trash via Finder..." \
      osascript -e 'tell application "Finder" to empty trash'
  fi
}

# ── e) Developer tool caches ─────────────────────────────────────────────────
system::_dev_tool_caches() {
  _SYS_DEVCACHE_TOTAL=0

  # npm cache
  local npm_cache="$HOME/.npm/_cacache"
  if [[ -d "$npm_cache" ]]; then
    local npm_bytes
    npm_bytes=$(utils::get_size_bytes "$npm_cache")
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + npm_bytes ))
    log::info "npm cache: $(utils::format_bytes "$npm_bytes")"
    dry_run_or_exec rm -rf "$npm_cache"
  else
    log::verbose "npm cache not found — skipping."
  fi

  # pnpm store
  if command -v pnpm &>/dev/null; then
    local pnpm_path
    pnpm_path=$(pnpm store path 2>/dev/null || true)
    if [[ -n "$pnpm_path" && -d "$pnpm_path" ]]; then
      local pnpm_bytes
      pnpm_bytes=$(utils::get_size_bytes "$pnpm_path")
      log::info "pnpm store (not auto-cleaned): $(utils::format_bytes "$pnpm_bytes")"
      log::info "  → Run: pnpm store prune"
    fi
  else
    log::verbose "pnpm not installed — skipping."
  fi

  # pip cache
  local pip_cache="$HOME/Library/Caches/pip"
  if [[ -d "$pip_cache" ]]; then
    local pip_bytes
    pip_bytes=$(utils::get_size_bytes "$pip_cache")
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + pip_bytes ))
    log::info "pip cache: $(utils::format_bytes "$pip_bytes")"
    dry_run_or_exec rm -rf "$pip_cache"
  else
    log::verbose "pip cache not found — skipping."
  fi

  # Go cache
  if command -v go &>/dev/null; then
    local go_cache
    go_cache=$(go env GOCACHE 2>/dev/null || true)
    if [[ -n "$go_cache" && -d "$go_cache" ]]; then
      local go_bytes
      go_bytes=$(utils::get_size_bytes "$go_cache")
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + go_bytes ))
      log::info "Go build cache: $(utils::format_bytes "$go_bytes")"
      dry_run_or_exec go clean -cache
    fi
  else
    log::verbose "Go not installed — skipping."
  fi
}

# ── f) System Data clues (informational only — NEVER delete) ─────────────────
system::_system_data_clues() {
  _SYS_HAS_CLUES=false
  local found_any=false

  printf '\n  %s%sSystem Data clues%s %s(informational — never auto-deleted)%s\n' \
    "${BOLD}" "${YELLOW}" "${RESET}" "${DIM}" "${RESET}"

  # Simulator devices
  local sim_devices="$HOME/Library/Developer/CoreSimulator/Devices"
  if [[ -d "$sim_devices" ]]; then
    local sim_bytes
    sim_bytes=$(utils::get_size_bytes "$sim_devices")
    if (( sim_bytes > 0 )); then
      found_any=true
      local item_count
      item_count=$(find "$sim_devices" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      printf '  • Simulator devices: %s (%s items)\n' "$(utils::format_bytes "$sim_bytes")" "$item_count"
      printf '    Path: %s\n' "$sim_devices"
      printf '    → Run: mac-cleanup --xcode to address this\n'
    fi
  fi

  # Rosetta translation cache
  local rosetta="/private/var/db/oah"
  if [[ -r "$rosetta" && -d "$rosetta" ]]; then
    local ros_bytes
    ros_bytes=$(utils::get_size_bytes "$rosetta")
    if (( ros_bytes > 0 )); then
      found_any=true
      printf '  • Rosetta translation cache: %s\n' "$(utils::format_bytes "$ros_bytes")"
      printf '    Path: %s\n' "$rosetta"
      printf '    → Investigate manually if Rosetta is no longer needed\n'
    fi
  fi

  # Xcode runtime volumes
  local runtime_vols="/Library/Developer/CoreSimulator/Volumes"
  if [[ -d "$runtime_vols" ]]; then
    local vol_bytes
    vol_bytes=$(utils::get_size_bytes "$runtime_vols")
    if (( vol_bytes > 0 )); then
      found_any=true
      printf '  • Xcode runtime volumes: %s\n' "$(utils::format_bytes "$vol_bytes")"
      printf '    Path: %s\n' "$runtime_vols"
      printf '    → Manage via: xcrun simctl runtime list / delete\n'
    fi
  fi

  # iOS firmware files (legacy)
  local ios_sim="$HOME/Library/iPhone Simulator"
  if [[ -d "$ios_sim" ]]; then
    local ios_bytes
    ios_bytes=$(utils::get_size_bytes "$ios_sim")
    if (( ios_bytes > 0 )); then
      found_any=true
      printf '  • Legacy iOS Simulator data: %s\n' "$(utils::format_bytes "$ios_bytes")"
      printf '    Path: %s\n' "$ios_sim"
      printf '    → Safe to delete if you no longer use old Xcode versions\n'
    fi
  fi

  if [[ "$found_any" == "true" ]]; then
    _SYS_HAS_CLUES=true
  else
    printf '  %s(no system data clues found)%s\n' "${DIM}" "${RESET}"
  fi
}
