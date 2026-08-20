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
  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  xcode::_derived_data
  xcode::_archives
  xcode::_device_support
  xcode::_simulator_caches
  xcode::_simulators
  xcode::_simulator_runtimes
  xcode::_simulator_devices
  xcode::_documentation_cache
  xcode::_device_logs

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  module_summary "Xcode" "$MODULE_XCODE_SCANNED"

  local status="clean"
  if (( MODULE_XCODE_SCANNED > 0 )); then
    status="$MODULE_XCODE_SCANNED"
  fi
  utils::register_module "Xcode" "Developer Tools" "$MODULE_XCODE_SCANNED" "$freed" "$status" "$projected"
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

# Only archives older than 90 days are removed, so only those are counted.
# v0.4.x measured the whole Archives tree — including shipped builds it would
# never touch — and reported it as reclaimable.
xcode::_archives() {
  local path="$HOME/Library/Developer/Xcode/Archives"
  if [[ ! -d "$path" ]]; then
    log::info "Archives not found — skipping."
    return 0
  fi

  local total_bytes=0
  local eligible=0
  while IFS= read -r archive; do
    [[ -n "$archive" ]] || continue
    local size
    size=$(utils::get_size_bytes "$archive")
    total_bytes=$(( total_bytes + size ))
    (( eligible++ )) || true
    safe_rm "$archive" "Xcode archive: $(basename "$archive")"
  done < <(find "$path" -name "*.xcarchive" -mtime +90 -print 2>/dev/null || true)

  MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + total_bytes ))

  local kept
  kept=$(utils::get_size_bytes "$path")
  if (( eligible > 0 )); then
    log::info "Archives: ${eligible} older than 90 days ($(utils::format_bytes "$total_bytes")); $(utils::format_bytes "$kept") total on disk"
  else
    log::info "Archives: none older than 90 days ($(utils::format_bytes "$kept") kept)"
  fi
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

# ── Simulator runtimes ────────────────────────────────────────────────────────
# Downloaded iOS/watchOS/tvOS runtimes are the largest developer artifact on a
# typical Mac — four iOS runtimes is over 30 GB — and each superseded point
# release stays on disk forever. v0.4.x listed them under "System Data clues"
# with an instruction to sort it out by hand, which is exactly the work the tool
# exists to do.
#
# Deleting a runtime means re-downloading gigabytes, so this only removes:
#   - runtimes macOS has marked unusable, always
#   - superseded runtimes, behind --simulators and a per-runtime confirmation
xcode::_simulator_runtimes() {
  command -v xcrun >/dev/null 2>&1 || return 0
  xcrun simctl runtime list >/dev/null 2>&1 || return 0

  local runtimes
  runtimes=$(xcode::_runtime_table) || return 0
  [[ -n "$runtimes" ]] || return 0

  local newest
  newest=$(printf '%s\n' "$runtimes" | xcode::_newest_per_platform)

  local line id state bytes version platform
  local reclaimable=0
  local superseded=0

  while IFS='|' read -r id state bytes version platform; do
    [[ -n "$id" ]] || continue

    local is_newest=false
    if printf '%s\n' "$newest" | grep -qxF "${platform}|${version}"; then
      is_newest=true
    fi

    if [[ "$state" != "Ready" ]]; then
      log::warn "  Unusable runtime: ${platform} ${version} ($(utils::format_bytes "$bytes"))"
      reclaimable=$(( reclaimable + bytes ))
      xcode::_delete_runtime "$id" "${platform} ${version}" "$bytes"
      continue
    fi

    if [[ "$is_newest" == "true" ]]; then
      log::verbose "  Keeping current runtime: ${platform} ${version}"
      continue
    fi

    (( superseded++ )) || true
    log::info "  Superseded runtime: ${platform} ${version} ($(utils::format_bytes "$bytes"))"

    if [[ "$TARGET_SIMULATORS" != "true" ]]; then
      continue
    fi

    reclaimable=$(( reclaimable + bytes ))
    if [[ "$DRY_RUN" == "true" ]]; then
      MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + bytes ))
      TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + bytes ))
      log::info "[DRY-RUN] $(utils::format_bytes "$bytes") Simulator runtime ${platform} ${version}"
      continue
    fi

    if utils::confirm "Delete superseded runtime ${platform} ${version} ($(utils::format_bytes "$bytes"))?"; then
      xcode::_delete_runtime "$id" "${platform} ${version}" "$bytes"
    else
      log::info "  Kept: ${platform} ${version}"
    fi
  done <<< "$runtimes"

  if (( superseded > 0 )) && [[ "$TARGET_SIMULATORS" != "true" ]]; then
    log::warn "  ${superseded} superseded runtime(s) found. Run with --simulators to reclaim them."
  fi
}

# Emit "id|state|bytes|version|platform" per installed runtime.
xcode::_runtime_table() {
  local json
  json=$(xcrun simctl runtime list -j 2>/dev/null) || return 1
  [[ -n "$json" ]] || return 1

  printf '%s' "$json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for entry in data.values():
    # simctl deletes by the runtime UUID, and refuses anything not marked
    # deletable (a runtime bundled with Xcode itself).
    uuid = entry.get("identifier") or ""
    if not uuid or not entry.get("deletable", False):
        continue
    ident = entry.get("runtimeIdentifier") or ""
    build = entry.get("build") or ""
    state = entry.get("state") or "Unknown"
    size = entry.get("sizeBytes") or 0
    version = entry.get("version") or build
    platform = entry.get("platformIdentifier") or ""
    platform = platform.rsplit(".", 1)[-1] or ident.rsplit(".", 1)[-1]
    print("%s|%s|%s|%s|%s" % (uuid, state, size, version, platform))
' 2>/dev/null || return 1
}

# Highest version per platform, as "platform|version" lines.
xcode::_newest_per_platform() {
  python3 -c '
import sys
best = {}
def key(v):
    parts = []
    for chunk in v.split("."):
        digits = "".join(c for c in chunk if c.isdigit())
        parts.append(int(digits) if digits else 0)
    return parts
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    fields = line.split("|")
    if len(fields) < 5:
        continue
    version, platform = fields[3], fields[4]
    cur = best.get(platform)
    if cur is None or key(version) > key(cur):
        best[platform] = version
for platform, version in best.items():
    print("%s|%s" % (platform, version))
' 2>/dev/null || true
}

xcode::_delete_runtime() {
  local id="$1"
  local label="$2"
  local bytes="$3"

  if [[ "$DRY_RUN" == "true" ]]; then
    MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + bytes ))
    TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + bytes ))
    log::info "[DRY-RUN] $(utils::format_bytes "$bytes") Simulator runtime ${label}"
    _oplog "DRYRUN" "simruntime:${label}" "$(utils::format_bytes "$bytes")"
    return 0
  fi

  if xcrun simctl runtime delete "$id" >/dev/null 2>&1; then
    MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + bytes ))
    TOTAL_FREED=$(( TOTAL_FREED + bytes ))
    log::success "  Removed runtime ${label} ($(utils::format_bytes "$bytes"))"
    _oplog "REMOVED" "simruntime:${label}" "$(utils::format_bytes "$bytes")"
  else
    log::warn "  Could not remove runtime ${label} (in use?)"
  fi
}

# ── Simulator devices ─────────────────────────────────────────────────────────
# Each created device carries its own writable data volume. They accumulate
# across Xcode upgrades and are only reported here unless --simulators is set.
xcode::_simulator_devices() {
  local devices="$HOME/Library/Developer/CoreSimulator/Devices"
  [[ -d "$devices" ]] || return 0

  local size
  size=$(utils::get_size_bytes "$devices")
  (( size > 0 )) || return 0

  local count
  count=$(find "$devices" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$TARGET_SIMULATORS" != "true" ]]; then
    log::info "  Simulator devices: ${count} devices, $(utils::format_bytes "$size") (use --simulators to prune)"
    return 0
  fi

  log::info "  Simulator devices: ${count} devices, $(utils::format_bytes "$size")"
  if command -v xcrun >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log::info "[DRY-RUN] Would run: xcrun simctl delete unavailable"
    else
      utils::with_spinner "Deleting unavailable simulator devices..." \
        xcrun simctl delete unavailable || true
    fi
  fi
}
