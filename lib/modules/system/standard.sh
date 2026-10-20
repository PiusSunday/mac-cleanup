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

  module_summary "System" "$module_scanned" "$projected"

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
_SYS_TRASH_FREED=0
_SYS_TRASH_VERIFIED=false
_SYS_TRASH_REMAINING=""
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
  # -prune, not -not -path: a -not -path filter still descends into every
  # excluded directory and then throws the results away, which is the whole cost.
  #
  # Excluded trees, none of which Finder ever displays:
  #   $HOME/Library      application state — sandbox stores, caches, cloud
  #                      mounts, simulator data. This is the single biggest
  #                      walker and its .DS_Store files are all invisible.
  #   $HOME/.*           tool/state dirs (~/.dartServer alone cost ~10 s to
  #                      walk for zero results, plus ~/.pub-cache, ~/.vscode,
  #                      ~/.gradle, ~/.Trash, …)
  #   node_modules, .git build trees and object stores
  #
  # Together these turn a ~40 s whole-home walk into a couple of seconds while
  # keeping every location Finder actually shows.
  done < <(find "$HOME" -maxdepth 8 \
    \( -path "$HOME/Library" \
       -o -path "$HOME/.*" \
       -o -name node_modules \
       -o -name .git \) -prune -o \
    -name ".DS_Store" -type f -print 2>/dev/null || true)

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

# Items in ~/.Trash, read from the filesystem. One process (`ls`), no walk.
#   - missing directory   -> 0    (verifiably empty)
#   - present but unreadable -> "" (unknown; must never be read as "empty")
# This is the fallback for when Finder refuses to answer, so it has to be able
# to say "I don't know" — collapsing a permission error to 0 is the bug that let
# a full Trash be reported as empty.
system::_trash_fs_count() {
  local dir="${HOME}/.Trash"
  if [[ ! -e "$dir" ]]; then
    printf '0\n'
    return 0
  fi

  local listing
  if ! listing=$(ls -A "$dir" 2>/dev/null); then
    printf ''
    return 0
  fi

  if [[ -z "$listing" ]]; then
    printf '0\n'
    return 0
  fi

  local n=0 entry
  while IFS= read -r entry; do
    n=$(( n + 1 ))
  done <<< "$listing"
  printf '%s\n' "$n"
}

# Item count in the Trash, or empty when it is genuinely unknown.
#
# Finder is authoritative — it sees every mounted volume's trash, not just
# ~/.Trash — but it only answers when macOS has granted this process Automation
# permission for Finder. A refused or timed-out query now falls through to the
# filesystem count instead of being coerced to 0; and if the filesystem cannot
# be read either, the answer is empty, never a fabricated "0".
system::_trash_count() {
  local from_finder
  if from_finder=$(_osascript_timed 5 -e 'tell application "Finder" to count items in trash') \
     && [[ "$from_finder" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$from_finder"
    return 0
  fi

  system::_trash_fs_count
}

# Empty the Trash, then prove it. Sets:
#   _SYS_TRASH_FREED      bytes that actually left the disk (0 in a preview)
#   _SYS_TRASH_VERIFIED   true only when a re-query found the Trash empty
#   _SYS_TRASH_REMAINING  items the re-query still saw, or "" if unknowable
#
# `tell application "Finder" to empty trash` exits 0 even when items remain
# (locked files, a partially-refused Automation prompt, or an automation probe
# that simply does nothing), so success is measured rather than assumed: the
# count is re-queried afterwards, and anything still there is removed directly
# so the user's explicit --empty-trash is still honoured. Nothing is ever
# reported as emptied unless a re-query confirmed it.
system::_trash_empty() {
  local known_bytes="${1:-0}"
  local freed_before=$TOTAL_FREED

  _SYS_TRASH_FREED=0
  _SYS_TRASH_VERIFIED=false
  _SYS_TRASH_REMAINING=""

  if [[ "$DRY_RUN" == "true" ]]; then
    TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + known_bytes ))
    _SYS_TRASH_FREED="$known_bytes"
    return 0
  fi

  # Finder first — it respects locked files and macOS conventions.
  _osascript_timed 10 -e 'tell application "Finder" to empty trash' >/dev/null 2>&1 || true

  local after
  after="$(system::_trash_count)"
  local via_finder=true

  if [[ "$after" != "0" ]]; then
    via_finder=false
    safe_rm_contents "${HOME}/.Trash" "Trash"
    after="$(system::_trash_count)"
  fi

  if [[ "$via_finder" == "true" ]]; then
    # Finder never touches TOTAL_FREED, so credit the pre-measured size — it is
    # trustworthy now that a re-query proved the Trash empty.
    _SYS_TRASH_FREED="$known_bytes"
    TOTAL_FREED=$(( TOTAL_FREED + known_bytes ))
  else
    # The direct delete already recorded the real bytes through safe_rm.
    _SYS_TRASH_FREED=$(( TOTAL_FREED - freed_before ))
  fi

  if [[ "$after" == "0" ]]; then
    _SYS_TRASH_VERIFIED=true
  elif [[ -n "$after" ]]; then
    _SYS_TRASH_REMAINING="$after"
  fi

  # Let APFS settle so free-space reporting catches up.
  sleep 1
  return 0
}

# True when this process can read ~/.Trash. macOS returns EPERM to the owner
# when the terminal lacks Full Disk Access, even though Finder (which is
# granted access) can still list and empty the Trash. Every direct read or
# delete therefore fails while the Finder path works — the two failure modes
# need different messages, and "check for locked files" is wrong for this one.
system::_trash_readable() {
  [[ -d "${HOME}/.Trash" ]] || return 0
  [[ -r "${HOME}/.Trash" ]]
}

# The actionable half of a Full Disk Access denial. Without this the user is
# left with "Trash: 3 items remain — check for locked files", which sends them
# looking for a lock that does not exist.
system::_trash_fda_hint() {
  log::info "  Grant Full Disk Access to your terminal: System Settings → Privacy & Security → Full Disk Access"
}

system::_trash() {
  _SYS_TRASH_TOTAL=0

  # Item count first — works even without Terminal Full Disk Access, but must
  # never invent a number. An empty answer means "unknown", and saying "empty"
  # then would be a lie.
  local trash_count
  trash_count="$(system::_trash_count)"

  if [[ -z "$trash_count" ]]; then
    log::info "Trash: item count unavailable — Finder did not answer and ~/.Trash is not readable."
    if ! system::_trash_readable; then
      system::_trash_fda_hint
      utils::register_action \
        "The Trash cannot be inspected without Full Disk Access" \
        "0" \
        "open \"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles\""
    fi
    return
  fi

  if (( trash_count == 0 )); then
    # Finder is authoritative — a probe that trashes a known file makes it
    # report 1 — but when ~/.Trash itself is unreadable the two sources cannot
    # corroborate each other, and that is worth saying in the log if a user
    # ever asks why the count disagreed with what they saw.
    if ! system::_trash_readable; then
      log::verbose "  Trash: Finder reports empty; ~/.Trash is unreadable (no Full Disk Access), so the filesystem count could not confirm it."
    fi
    log::info "Trash: empty."
    return
  fi

  # Size is a best-effort upgrade over the count, never a precondition.
  local trash_size
  trash_size=$(system::_trash_size_bytes)

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
    # A Trash left alone frees nothing this run, so it must not inflate the
    # module's scanned total (it was double-counted in the summary before).
    # Gate on the count, not the size: Finder answers `get size of trash` with
    # the token `missing value` rather than a number, so a size-based gate
    # silently dropped the Trash out of the decisions summary entirely.
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
    return
  fi

  system::_trash_empty "${trash_size:-0}"
  _SYS_TRASH_TOTAL="$_SYS_TRASH_FREED"

  if [[ "$_SYS_TRASH_VERIFIED" == "true" ]]; then
    if (( _SYS_TRASH_FREED > 0 )); then
      log::success "Trash emptied (${trash_count} items, $(utils::format_bytes "$_SYS_TRASH_FREED") freed)"
    else
      log::success "Trash emptied (${trash_count} items)"
    fi
  elif [[ -n "$_SYS_TRASH_REMAINING" ]]; then
    if ! system::_trash_readable; then
      log::warn "Trash: $(system::_item_count_phrase "$_SYS_TRASH_REMAINING") remain — Finder could not delete them and removing them directly needs Full Disk Access."
      system::_trash_fda_hint
      utils::register_action \
        "$(system::_item_count_phrase "$_SYS_TRASH_REMAINING") stuck in the Trash — Full Disk Access required" \
        "0" \
        "open \"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles\""
    else
      log::warn "Trash: $(system::_item_count_phrase "$_SYS_TRASH_REMAINING") remain after emptying — check for locked files or Finder permissions"
    fi
  else
    log::warn "Trash: emptying was requested but could not be verified as empty"
    if ! system::_trash_readable; then
      system::_trash_fda_hint
    fi
  fi
}

# ── d) Developer tool caches ─────────────────────────────────────────────────
system::_dev_tool_caches() {
  _SYS_DEVCACHE_TOTAL=0

  # Each path is measured once — by safe_rm, whose result comes back in
  # SAFE_RM_LAST_BYTES. The old code ran `du` first and then let safe_rm run it
  # again, and it added the pre-measured size even when the path was whitelisted
  # or protected and nothing was freed, so the module over-reported.

  # npm cache
  local npm_cache="$HOME/.npm/_cacache"
  if [[ -d "$npm_cache" ]]; then
    safe_rm "$npm_cache" "npm cache"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  else
    log::verbose "npm cache not found — skipping."
  fi

  # npm npx cache
  local npx_cache="$HOME/.npm/_npx"
  if [[ -d "$npx_cache" ]]; then
    safe_rm "$npx_cache" "npm npx cache"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  fi

  # npm logs
  local npm_logs="$HOME/.npm/_logs"
  if [[ -d "$npm_logs" ]]; then
    safe_rm "$npm_logs" "npm logs"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  fi

  # pip cache
  local pip_cache="$HOME/Library/Caches/pip"
  if [[ -d "$pip_cache" ]]; then
    safe_rm "$pip_cache" "pip cache"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  else
    log::verbose "pip cache not found — skipping."
  fi

  # Go cache — deletion goes through `go clean -cache` rather than safe_rm, so
  # the bytes are measured here and credited explicitly. Two consequences worth
  # stating:
  #   * a live `--system` frees the cache but used to report none of it, so the
  #     module's figure disagreed with the report by the whole cache size;
  #   * `--all` reaches the same directory again in the Caches sweep, so the path
  #     is claimed first to keep it from being listed and counted twice.
  if command -v go &>/dev/null; then
    local go_cache
    go_cache=$(go env GOCACHE 2>/dev/null || true)
    if [[ -n "$go_cache" && -d "$go_cache" ]] && protect::claim "$go_cache"; then
      local go_bytes
      go_bytes=$(utils::get_size_bytes "$go_cache")
      _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + go_bytes ))
      log::info "Go build cache: $(utils::format_bytes "$go_bytes")"
      if [[ "$DRY_RUN" == "true" ]]; then
        TOTAL_DRYRUN_BYTES=$(( TOTAL_DRYRUN_BYTES + go_bytes ))
        log::info "[DRY-RUN] Would execute: go clean -cache"
      else
        dry_run_or_exec go clean -cache
        # Credit what actually left the disk rather than the pre-measured size.
        local go_after
        go_after=$(utils::get_size_bytes "$go_cache")
        local go_freed=$(( go_bytes - go_after ))
        (( go_freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + go_freed ))
      fi
    fi
  else
    log::verbose "Go not installed — skipping."
  fi

  # Google Cloud SDK logs
  local gcloud_logs="$HOME/.config/gcloud/logs"
  if [[ -d "$gcloud_logs" ]]; then
    safe_rm "$gcloud_logs" "Google Cloud logs"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  fi

  # Google Cloud SDK cache
  local gcloud_cache="$HOME/.config/gcloud/.cache"
  if [[ -d "$gcloud_cache" ]]; then
    safe_rm "$gcloud_cache" "Google Cloud cache"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  fi

  # Kubernetes client cache
  local kube_cache="$HOME/.kube/cache"
  if [[ -d "$kube_cache" ]]; then
    safe_rm "$kube_cache" "Kubernetes cache"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  fi

  # AWS CLI cache
  local aws_cache="$HOME/.aws/cli/cache"
  if [[ -d "$aws_cache" ]]; then
    safe_rm "$aws_cache" "AWS CLI cache"
    _SYS_DEVCACHE_TOTAL=$(( _SYS_DEVCACHE_TOTAL + SAFE_RM_LAST_BYTES ))
  fi
}

# ── e) var/folders temporary items ───────────────────────────────────────────
system::_var_folders() {
  _SYS_VARFOLDERS_TOTAL=0

  # Get the current user's var/folders prefix
  local user_tmp
  user_tmp=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)
  [[ -n "$user_tmp" && -d "$user_tmp" ]] || return 0
  user_tmp="${user_tmp%/}"

  local total=0

  # Only clean known-safe subdirs, never the root.
  #
  # Search is scoped to the current user's own DARWIN_USER_TEMP_DIR rather than
  # all of /private/var/folders — the old sweep walked every user's temp trees
  # (and anything else mounted there) for a path it was already told.
  local -a safe_subdirs=("TemporaryItems" "Cleanup At Startup" "-Tmp-")
  local skipped=0
  for subdir in "${safe_subdirs[@]}"; do
    while IFS= read -r target; do
      [[ -d "$target" ]] || continue
      safe_rm "$target" "var/folders temp ($subdir)" "silent"
      if (( SAFE_RM_LAST_BYTES > 0 )); then
        log::verbose "  var/folders temp: $(utils::format_bytes "$SAFE_RM_LAST_BYTES") ($target)"
        total=$(( total + SAFE_RM_LAST_BYTES ))
      elif [[ "$SAFE_RM_FAILED" == "true" ]]; then
        (( skipped++ )) || true
      fi
    done < <(find "$user_tmp" -maxdepth 2 -name "$subdir" -type d 2>/dev/null || true)
  done

  _SYS_VARFOLDERS_TOTAL=$total
  if (( total > 0 )); then
    log::info "var/folders temp: $(utils::format_bytes "$total")"
  fi
  # One line, not one per container. A busy app holds its TemporaryItems open
  # for the whole session, so the same "in use" result repeats for every
  # container the scan finds — fifty identical warnings say nothing the count
  # does not.
  if (( skipped > 0 )); then
    if (( total > 0 )); then
      log::verbose "  var/folders temp: $(system::_item_count_phrase "$skipped") in use — skipped"
    else
      log::info "var/folders temp: $(system::_item_count_phrase "$skipped") in use — skipped"
    fi
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
