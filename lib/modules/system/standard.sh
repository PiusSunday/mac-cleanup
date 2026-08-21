#!/usr/bin/env bash
# lib/system.sh — System-level scans: crash reports, logs, .DS_Store, Trash,
#                 dev tool caches, and System Data clues.
# Runs automatically as first step regardless of selected modules.

# Public entry point
system::clean() {
  log::section "System Scan"

  local module_scanned=0

  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  system::_crash_reports
  module_scanned=$(( module_scanned + _SYS_CRASH_TOTAL ))

  system::_ds_store
  module_scanned=$(( module_scanned + _SYS_DSSTORE_TOTAL ))

  system::_trash
  module_scanned=$(( module_scanned + _SYS_TRASH_TOTAL ))

  system::_dev_tool_caches
  module_scanned=$(( module_scanned + _SYS_DEVCACHE_TOTAL ))

  system::_var_folders
  module_scanned=$(( module_scanned + _SYS_VARFOLDERS_TOTAL ))

  system::_system_data_clues

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  module_summary "System" "$module_scanned"

  # Determine status
  local status="clean"

  # System Data clues are informational only. If the module also has real
  # cleanup candidates, it still behaves as a normal cleanable module.
  if (( module_scanned == 0 )) && [[ "${_SYS_HAS_CLUES:-false}" == "true" ]]; then
    status="review"
  elif (( projected > 0 )); then
    status="$projected"
  fi

  utils::register_module "System" "System" "$module_scanned" "$freed" "$status" "$projected"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

_SYS_CRASH_TOTAL=0
_SYS_DSSTORE_TOTAL=0
_SYS_TRASH_TOTAL=0
_SYS_DEVCACHE_TOTAL=0
_SYS_VARFOLDERS_TOTAL=0
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
      safe_rm "$file" "Crash report: $(basename "$file")" "silent"
      (( SAFE_RM_LAST_BYTES > 0 )) || continue
      (( count++ )) || true
      dir_bytes=$(( dir_bytes + SAFE_RM_LAST_BYTES ))
    done < <(find "$path" -maxdepth 1 \( -name "*.crash" -o -name "*.ips" -o -name "*.hang" \) -type f 2>/dev/null || true)

    total_count=$(( total_count + count ))
    total_bytes=$(( total_bytes + dir_bytes ))
  done

  _SYS_CRASH_TOTAL=$total_bytes

  if (( total_count == 1 )); then
    log::info "Crash reports: 1 file ($(utils::format_bytes "$total_bytes"))"
  elif (( total_count > 1 )); then
    log::info "Crash reports: ${total_count} files ($(utils::format_bytes "$total_bytes"))"
  else
    log::info "Crash reports: none found."
  fi
}

# ── b) .DS_Store files ───────────────────────────────────────────────────────
system::_ds_store() {
  _SYS_DSSTORE_TOTAL=0
  log::info "Scanning for .DS_Store files..."

  local count=0
  local total_bytes=0
  local skipped=0
  while IFS= read -r file; do
    (( count++ )) || true
    # SAFE_RM_LAST_BYTES is 0 whenever the file was whitelisted, protected,
    # unwritable or already claimed. The old add-then-subtract dance only saw
    # a non-zero return, which safe_rm does not use for those cases.
    safe_rm "$file" ".DS_Store" "silent"
    if (( SAFE_RM_LAST_BYTES > 0 )); then
      total_bytes=$(( total_bytes + SAFE_RM_LAST_BYTES ))
    else
      (( skipped++ )) || true
    fi
  done < <(find "$HOME" \
    -name ".DS_Store" \
    -maxdepth 8 \
    -not -path "$HOME/Library/Containers/*" \
    -not -path "$HOME/.Trash/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -type f 2>/dev/null || true)

  _SYS_DSSTORE_TOTAL=$total_bytes

  if (( count > 0 )); then
    local msg
    if (( skipped > 0 )); then
      local deleted=$(( count - skipped ))
      msg=".DS_Store: ${deleted} of ${count} files ($(utils::format_bytes "$total_bytes")) — ${skipped} skipped (protected or unwritable)"
    else
      msg=".DS_Store: ${count} files ($(utils::format_bytes "$total_bytes"))"
    fi
    log::info "$msg"
  else
    log::info ".DS_Store: none found."
  fi
}

# ── c) Trash ─────────────────────────────────────────────────────────────────

# "1 item" / "2 items"
system::_item_count_phrase() {
  local n="${1:-0}"
  if (( n == 1 )); then
    printf '1 item'
  else
    printf '%s items' "$n"
  fi
}

# Bytes in the Trash, or empty when it cannot be determined.
#
# Finder returns the AppleScript token `missing value` for `get size of trash`
# far more often than it returns a number, so the Finder answer is only ever an
# opportunistic first try. `du` on ~/.Trash is the fallback; it needs Full Disk
# Access for some items and does not see other volumes' trash, which is why an
# unknown size must never suppress the finding.
system::_trash_size_bytes() {
  local from_finder
  from_finder=$(_osascript_timed 5 -e 'tell application "Finder" to get size of trash') || from_finder=""
  if [[ "$from_finder" =~ ^[0-9]+$ ]] && (( from_finder > 0 )); then
    printf '%s\n' "$from_finder"
    return 0
  fi

  if [[ -d "$HOME/.Trash" ]]; then
    local kb
    kb=$(utils::run_timed "${MAC_CLEANUP_DU_TIMEOUT:-20}" du -skPx "$HOME/.Trash" 2>/dev/null | awk 'NR==1 {print $1}')
    if [[ "$kb" =~ ^[0-9]+$ ]] && (( kb > 0 )); then
      printf '%s\n' "$(( kb * 1024 ))"
      return 0
    fi
  fi

  # Unknown. Callers must still report the item count.
  printf ''
  return 0
}

# Run osascript with a timeout (seconds). Returns 1 on timeout or failure.
# Uses perl alarm() — available on all macOS versions, no background processes.
_osascript_timed() {
  local secs=$1
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV' "$secs" osascript "$@" 2>/dev/null
}

system::_trash() {
  _SYS_TRASH_TOTAL=0

  # Query item count via Finder — works even without Terminal Full Disk Access
  # Timeout after 5 s so CI / headless runners don't hang
  local trash_count=0
  trash_count=$(_osascript_timed 5 -e 'tell application "Finder" to count items in trash') || trash_count=0
  [[ "$trash_count" =~ ^[0-9]+$ ]] || trash_count=0

  if (( trash_count == 0 )); then
    log::info "Trash: empty."
    return
  fi

  # Size is a best-effort upgrade over the count, never a precondition.
  local trash_size
  trash_size=$(system::_trash_size_bytes)
  _SYS_TRASH_TOTAL=${trash_size:-0}

  local size_note=""
  if [[ -n "$trash_size" ]]; then
    size_note=" ($(utils::format_bytes "$trash_size"))"
  fi

  # The Trash is user data: files the user chose to delete but has not committed
  # to losing, which macOS keeps recoverable on purpose. Emptying it is not part
  # of a cache sweep, and --yes must not be able to trigger it — that flag means
  # "do not ask me about cleanup", not "destroy recoverable data".
  if [[ "${EMPTY_TRASH:-false}" != "true" ]]; then
    log::info "Trash: $(system::_item_count_phrase "$trash_count")${size_note} — left alone"
    # Gate on the count, not the size. Finder answers `get size of trash` with
    # the token `missing value` rather than a number, so a size-based gate
    # silently dropped the Trash out of the decisions summary entirely — a user
    # with 50 GB of it was told nothing.
    utils::register_action \
      "$(system::_item_count_phrase "$trash_count") in the Trash" \
      "${trash_size:-0}" \
      "mac-cleanup --empty-trash"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + ${trash_size:-0} ))
    log::info "[DRY-RUN] Would empty Trash ($(system::_item_count_phrase "$trash_count"))"
    return
  fi

  # Deleting recoverable user data is confirmed explicitly. --empty-trash plus
  # --yes is two deliberate flags, and is honoured without a prompt: requiring
  # one anyway would make --empty-trash unusable non-interactively, where
  # utils::confirm always declines. --yes on its own still cannot reach here.
  if [[ "$SKIP_CONFIRM" == "true" ]]; then
    log::warn "Emptying the Trash ($(system::_item_count_phrase "$trash_count")${size_note}) — --empty-trash and --yes both given."
  elif ! utils::confirm "Permanently empty the Trash ($(system::_item_count_phrase "$trash_count")${size_note})?"; then
    log::info "Trash: left alone."
    _SYS_TRASH_TOTAL=0
    return
  fi

  # Capture disk state before emptying
  local freed_before_trash=$TOTAL_FREED
  local dryrun_before_trash=$TOTAL_DRYRUN_BYTES

  # Empty via Finder — respects locked files and macOS conventions
  if _osascript_timed 10 -e 'tell application "Finder" to empty trash'; then
    # Allow APFS to update free space reporting
    sleep 1
    # Since we can't capture bytes via safe_rm for the Finder AppleScript,
    # we must default to adding the computed size manually.
    if [[ "$DRY_RUN" != "true" ]]; then
      TOTAL_FREED=$(( TOTAL_FREED + ${trash_size:-0} ))
    fi
    local disk_delta=${trash_size:-0}

    # Use whichever is larger: Finder-reported size or actual disk delta
    local known=${trash_size:-0}
    local actual_freed=$(( known > disk_delta ? known : disk_delta ))
    _SYS_TRASH_TOTAL=$actual_freed

    if (( actual_freed > 0 )); then
      log::success "Trash emptied (${trash_count} items, $(utils::format_bytes "$actual_freed") freed)"
    else
      log::success "Trash emptied (${trash_count} items)"
    fi
  else
    # Fallback: direct delete if Finder call fails or times out
    local freed_before_fallback=$TOTAL_FREED
    local dryrun_before_fallback=$TOTAL_DRYRUN_BYTES
    safe_rm_contents "${HOME}/.Trash" "Trash"
    sleep 1
    local fallback_freed=$(( TOTAL_FREED - freed_before_fallback ))
    if [[ "$DRY_RUN" == "true" ]]; then
      fallback_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before_fallback ))
    fi
    
    _SYS_TRASH_TOTAL=$fallback_freed

    if (( fallback_freed > 0 )); then
      log::success "Trash emptied (${trash_count} items, $(utils::format_bytes "$fallback_freed") freed)"
    else
      log::success "Trash emptied (${trash_count} items)"
    fi
  fi
}

# ── d) Developer tool caches ─────────────────────────────────────────────────
system::_dev_tool_caches() {
  _SYS_DEVCACHE_TOTAL=0

  # npm cache
  local npm_cache="$HOME/.npm/_cacache"
  if [[ -d "$npm_cache" ]]; then
    local npm_bytes
    npm_bytes=$(utils::get_size_bytes "$npm_cache")
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + npm_bytes ))
    safe_rm "$npm_cache" "npm cache"
  else
    log::verbose "npm cache not found — skipping."
  fi

  # npm npx cache
  local npx_cache="$HOME/.npm/_npx"
  if [[ -d "$npx_cache" ]]; then
    local npx_bytes
    npx_bytes=$(utils::get_size_bytes "$npx_cache")
    if (( npx_bytes > 0 )); then
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + npx_bytes ))
        safe_rm "$npx_cache" "npm npx cache"
    fi
  fi

  # npm logs
  local npm_logs="$HOME/.npm/_logs"
  if [[ -d "$npm_logs" ]]; then
    local npm_logs_bytes
    npm_logs_bytes=$(utils::get_size_bytes "$npm_logs")
    if (( npm_logs_bytes > 0 )); then
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + npm_logs_bytes ))
        safe_rm "$npm_logs" "npm logs"
    fi
  fi

  # pip cache
  local pip_cache="$HOME/Library/Caches/pip"
  if [[ -d "$pip_cache" ]]; then
    local pip_bytes
    pip_bytes=$(utils::get_size_bytes "$pip_cache")
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + pip_bytes ))
    safe_rm "$pip_cache" "pip cache"
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

  # Google Cloud SDK logs
  local gcloud_logs="$HOME/.config/gcloud/logs"
  if [[ -d "$gcloud_logs" ]]; then
    local gcloud_logs_bytes
    gcloud_logs_bytes=$(utils::get_size_bytes "$gcloud_logs")
    if (( gcloud_logs_bytes > 0 )); then
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + gcloud_logs_bytes ))
        safe_rm "$gcloud_logs" "Google Cloud logs"
    fi
  fi

  # Google Cloud SDK cache
  local gcloud_cache="$HOME/.config/gcloud/.cache"
  if [[ -d "$gcloud_cache" ]]; then
    local gcloud_cache_bytes
    gcloud_cache_bytes=$(utils::get_size_bytes "$gcloud_cache")
    if (( gcloud_cache_bytes > 0 )); then
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + gcloud_cache_bytes ))
        safe_rm "$gcloud_cache" "Google Cloud cache"
    fi
  fi

  # Kubernetes client cache
  local kube_cache="$HOME/.kube/cache"
  if [[ -d "$kube_cache" ]]; then
    local kube_bytes
    kube_bytes=$(utils::get_size_bytes "$kube_cache")
    if (( kube_bytes > 0 )); then
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + kube_bytes ))
        safe_rm "$kube_cache" "Kubernetes cache"
    fi
  fi

  # AWS CLI cache
  local aws_cache="$HOME/.aws/cli/cache"
  if [[ -d "$aws_cache" ]]; then
    local aws_bytes
    aws_bytes=$(utils::get_size_bytes "$aws_cache")
    if (( aws_bytes > 0 )); then
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + aws_bytes ))
        safe_rm "$aws_cache" "AWS CLI cache"
    fi
  fi
}

# ── e) var/folders temporary items ───────────────────────────────────────────
system::_var_folders() {
  _SYS_VARFOLDERS_TOTAL=0

  # Get the current user's var/folders prefix
  local user_tmp
  user_tmp=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)
  [[ -n "$user_tmp" && -d "$user_tmp" ]] || return 0

  local total=0

  # Only clean known-safe subdirs, never the root
  local -a safe_subdirs=("TemporaryItems" "Cleanup At Startup" "-Tmp-")
  for subdir in "${safe_subdirs[@]}"; do
    # Find matching dirs under var/folders (one level of UUID dirs)
    while IFS= read -r target; do
      [[ -d "$target" ]] || continue
      local size
      size=$(utils::get_size_bytes "$target")
      (( size > 0 )) || continue
      log::verbose "  var/folders temp: $(utils::format_bytes "$size") ($subdir)"
      safe_rm "$target" "var/folders temp ($subdir)" "silent"
      total=$(( total + SAFE_RM_LAST_BYTES ))
    done < <(find /private/var/folders -maxdepth 4 -name "$subdir" -type d 2>/dev/null || true)
  done

  _SYS_VARFOLDERS_TOTAL=$total
  if (( total > 0 )); then
    log::info "var/folders temp: $(utils::format_bytes "$total")"
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
