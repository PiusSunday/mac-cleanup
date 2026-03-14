#!/usr/bin/env bash
# lib/xcode.sh — Xcode DerivedData, Archives, DeviceSupport, Simulators cleanup

# Public entry point
xcode::clean() {
  if ! utils::require xcodebuild; then
    utils::register_module "Xcode" "Developer Tools" "0" "0" "skipped"
    return 0
  fi
  log::section "Xcode"

  MODULE_XCODE_SCANNED=0
  local disk_before
  disk_before=$(utils::get_free_bytes)

  xcode::_derived_data
  xcode::_archives
  xcode::_device_support
  xcode::_simulator_caches
  xcode::_simulators
  xcode::_documentation_cache
  xcode::_device_logs

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Xcode" "$MODULE_XCODE_SCANNED"

  local status="clean"
  if (( MODULE_XCODE_SCANNED > 0 )); then
    status="$MODULE_XCODE_SCANNED"
  fi
  utils::register_module "Xcode" "Developer Tools" "$MODULE_XCODE_SCANNED" "$freed" "$status"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Module-level scanned counter (accumulated by helpers)
MODULE_XCODE_SCANNED=0

xcode::_derived_data() {
  local path="$HOME/Library/Developer/Xcode/DerivedData"
  if [[ ! -d "$path" ]]; then
    log::info "DerivedData not found — skipping."
    return 0
  fi
  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size_bytes ))
  local size
  size=$(utils::format_bytes "$size_bytes")
  log::info "DerivedData: ${size}"
  safe_rm "$path" "Xcode DerivedData"
}

xcode::_archives() {
  local path="$HOME/Library/Developer/Xcode/Archives"
  if [[ ! -d "$path" ]]; then
    log::info "Archives not found — skipping."
    return 0
  fi
  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size_bytes ))
  local size
  size=$(utils::format_bytes "$size_bytes")
  log::info "Archives: ${size}"

  # Only remove archives older than 90 days by default
  log::info "Removing Xcode archives older than 90 days..."
  while IFS= read -r archive; do
    safe_rm "$archive" "Xcode archive"
  done < <(find "$path" -name "*.xcarchive" -mtime +90 -print 2>/dev/null || true)
}

xcode::_device_support() {
  local path="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  if [[ ! -d "$path" ]]; then
    log::info "iOS DeviceSupport not found — skipping."
    return 0
  fi
  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size_bytes ))
  local size
  size=$(utils::format_bytes "$size_bytes")
  log::info "iOS DeviceSupport: ${size}"
  safe_rm "$path" "Xcode DeviceSupport"
}

xcode::_simulator_caches() {
  local path="$HOME/Library/Developer/CoreSimulator/Caches"
  if [[ ! -d "$path" ]]; then
    log::info "Simulator caches not found — skipping."
    return 0
  fi
  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size_bytes ))
  local size
  size=$(utils::format_bytes "$size_bytes")
  log::info "Simulator caches: ${size}"
  safe_rm "$path" "CoreSimulator caches"
}

xcode::_simulators() {
  # Guard: simctl requires full Xcode, not just Command Line Tools
  if ! xcrun --find simctl &>/dev/null 2>&1; then
    log::info "simctl not available — skipping simulator cleanup."
    return 0
  fi

  log::info "Removing unavailable simulators..."
  if [[ "$DRY_RUN" == "true" ]]; then
    dry_run_or_exec xcrun simctl delete unavailable
  else
    utils::with_spinner "Removing unavailable simulators..." \
      xcrun simctl delete unavailable
  fi
}

xcode::_documentation_cache() {
  local -a doc_paths=(
    "$HOME/Library/Developer/Xcode/DocumentationCache"
    "$HOME/Library/Developer/Xcode/DocumentationIndex"
  )
  local p
  for p in "${doc_paths[@]}"; do
    [[ -d "$p" ]] || continue
    local size
    size=$(utils::get_size_bytes "$p")
    MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size ))
    safe_rm "$p" "Xcode $(basename "$p")"
  done
}

xcode::_device_logs() {
  local -a log_paths=(
    "$HOME/Library/Developer/Xcode/iOS Device Logs"
    "$HOME/Library/Developer/Xcode/watchOS Device Logs"
    "$HOME/Library/Logs/CoreSimulator"
    "$HOME/Library/Developer/Xcode/Products"
  )
  local p
  for p in "${log_paths[@]}"; do
    [[ -d "$p" ]] || continue
    local size
    size=$(utils::get_size_bytes "$p")
    MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size ))
    safe_rm "$p" "Xcode $(basename "$p")"
  done
}
