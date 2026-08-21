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

# Runtime UUIDs this run actually deleted, awaited before pruning devices.
_XCODE_DELETED_RUNTIME_IDS=""
# Runtime identifiers (com.apple.CoreSimulator.SimRuntime.iOS-26-4) whose
# devices will be orphaned. Used only to size the dry-run estimate; a live run
# measures the devices directory before and after instead.
_XCODE_SUPERSEDED_RUNTIME_IDS=""

xcode::_derived_data() {
  local path="$HOME/Library/Developer/Xcode/DerivedData"
  if [[ ! -d "$path" ]]; then
    log::info "DerivedData not found — skipping."
    return 0
  fi
  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + size_bytes ))
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
  safe_rm "$path" "CoreSimulator caches"
}

# Device pruning has a single owner: xcode::_simulator_devices, which runs after
# the runtime sweep. Pruning here as well accomplished nothing — it ran before
# any runtime was deleted, so no device was orphaned yet — and hid the fact that
# the later call was firing too early too.
xcode::_simulators() {
  # Guard: simctl requires full Xcode, not just Command Line Tools
  if ! xcrun --find simctl &>/dev/null 2>&1; then
    log::info "simctl not available — skipping simulator cleanup."
    return 0
  fi
  return 0
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

  local id state bytes version platform ident
  local reclaimable=0
  local superseded=0
  local superseded_bytes=0

  # Two runtimes can share one identifier (26.4 and 26.4.1 are both iOS-26-4).
  # Collect the identifiers being kept so a superseded one is never credited
  # with devices that belong to a runtime that survives.
  local kept_idents=""
  while IFS='|' read -r id state bytes version platform ident; do
    [[ -n "$ident" ]] || continue
    if printf '%s\n' "$newest" | grep -qxF "${platform}|${version}"; then
      kept_idents="${kept_idents}${ident}"$'\n'
    fi
  done <<< "$runtimes"

  while IFS='|' read -r id state bytes version platform ident; do
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
    superseded_bytes=$(( superseded_bytes + bytes ))
    if ! printf '%s' "$kept_idents" | grep -qxF "$ident"; then
      _XCODE_SUPERSEDED_RUNTIME_IDS="${_XCODE_SUPERSEDED_RUNTIME_IDS}${ident}"$'\n'
    fi
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
    log::warn "  ${superseded} superseded runtime(s) found — not removed without --simulators."

    # Removing a runtime also orphans every device bound to it, and those
    # devices are often a third of the total. Advertise one combined figure so
    # what --simulators reclaims matches what the report promised.
    local orphaned label
    orphaned=$(xcode::_devices_bound_to_deleted_runtimes)
    label="${superseded} superseded Xcode simulator runtimes"
    if (( orphaned > 0 )); then
      label="${label} + the devices bound to them"
    fi
    utils::register_action \
      "$label" \
      "$(( superseded_bytes + orphaned ))" \
      "mac-cleanup --simulators"
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
    # ident is the runtime identifier device.plist records for each simulator.
    print("%s|%s|%s|%s|%s|%s" % (uuid, state, size, version, platform, ident))
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
    _XCODE_DELETED_RUNTIME_IDS="${_XCODE_DELETED_RUNTIME_IDS}${id}"$'\n'
    log::success "  Removed runtime ${label} ($(utils::format_bytes "$bytes"))"
    _oplog "REMOVED" "simruntime:${label}" "$(utils::format_bytes "$bytes")"
  else
    log::warn "  Could not remove runtime ${label} (in use?)"
  fi
}

# simctl returns from `runtime delete` before the disk image is unmounted, and a
# device only becomes "unavailable" once its runtime is gone. Waiting is what
# makes the follow-up prune actually reclaim anything.
xcode::_await_runtime_deletion() {
  [[ -n "$_XCODE_DELETED_RUNTIME_IDS" ]] || return 0

  local deadline=$(( $(date +%s) + ${MAC_CLEANUP_RUNTIME_WAIT:-60} ))
  local remaining
  while (( $(date +%s) < deadline )); do
    remaining=0
    local id
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      if xcrun simctl runtime list -j 2>/dev/null | grep -qF "$id"; then
        remaining=$(( remaining + 1 ))
      fi
    done <<< "$_XCODE_DELETED_RUNTIME_IDS"

    (( remaining == 0 )) && return 0
    sleep 2
  done

  log::verbose "Runtime deletion still settling after the wait window; pruning anyway."
  return 0
}

# ── Simulator devices ─────────────────────────────────────────────────────────
# Each created device carries its own writable data volume. They accumulate
# across Xcode upgrades and are only reported here unless --simulators is set.
# Every device carries its own data volume, and a device bound to a runtime that
# has just been deleted becomes unavailable — so removing superseded runtimes
# frees the runtimes *and* their devices. On the development machine that second
# part was 22 devices and 9.4 GB, which v0.5.0 mentioned in passing and never
# offered to reclaim.
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

  command -v xcrun >/dev/null 2>&1 || return 0

  if [[ "$DRY_RUN" == "true" ]]; then
    # Devices bound to the runtimes queued for deletion above will be orphaned.
    local orphaned
    orphaned=$(xcode::_devices_bound_to_deleted_runtimes)
    if (( orphaned > 0 )); then
      MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + orphaned ))
      TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + orphaned ))
      log::info "  Simulator devices: ${count} devices, $(utils::format_bytes "$size")"
      log::info "[DRY-RUN] $(utils::format_bytes "$orphaned") simulator devices orphaned by the runtime removals above"
    else
      log::info "  Simulator devices: ${count} devices, $(utils::format_bytes "$size") (none orphaned)"
    fi
    return 0
  fi

  xcode::_await_runtime_deletion

  local before
  before=$(utils::get_size_bytes "$devices")
  utils::with_spinner "Deleting simulator devices orphaned by removed runtimes..." \
    xcrun simctl delete unavailable || true

  local after
  after=$(utils::get_size_bytes "$devices")
  local reclaimed=$(( before - after ))
  if (( reclaimed > 0 )); then
    MODULE_XCODE_SCANNED=$(( MODULE_XCODE_SCANNED + reclaimed ))
    TOTAL_FREED=$(( TOTAL_FREED + reclaimed ))
    local now
    now=$(find "$devices" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    log::success "  Removed $(( count - now )) orphaned devices ($(utils::format_bytes "$reclaimed"))"
    _oplog "REMOVED" "simdevices" "$(utils::format_bytes "$reclaimed")"
  else
    log::info "  Simulator devices: none orphaned"
  fi
}

# Total bytes held by devices whose runtime is queued for deletion.
xcode::_devices_bound_to_deleted_runtimes() {
  local devices="$HOME/Library/Developer/CoreSimulator/Devices"
  local total=0

  if [[ -z "$_XCODE_SUPERSEDED_RUNTIME_IDS" || ! -d "$devices" ]]; then
    printf '0\n'
    return 0
  fi

  local device_dir plist runtime
  while IFS= read -r device_dir; do
    [[ -d "$device_dir" ]] || continue
    plist="$device_dir/device.plist"
    [[ -f "$plist" ]] || continue
    runtime=$(/usr/libexec/PlistBuddy -c "Print :runtime" "$plist" 2>/dev/null || true)
    [[ -n "$runtime" ]] || continue
    # device.plist stores the runtime identifier, e.g.
    # com.apple.CoreSimulator.SimRuntime.iOS-26-4
    if printf '%s' "$_XCODE_SUPERSEDED_RUNTIME_IDS" | grep -qxF "$runtime"; then
      total=$(( total + $(utils::get_size_bytes "$device_dir") ))
    fi
  done < <(find "$devices" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

  printf '%s\n' "$total"
}
