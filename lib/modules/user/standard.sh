#!/usr/bin/env bash
# lib/caches.sh — ~/Library/Caches and app caches cleanup

# Public entry point
caches::clean() {
  log::section "Caches"

  local module_scanned=0
  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  # ~/Library/Caches has exactly one owner: caches::_user_caches. The browser,
  # Spotify, Apple-media and container sweeps that used to re-walk it lived here
  # too, so every shared directory was measured two or three times and the
  # preview total could never be reached by a live run.
  caches::_user_caches
  module_scanned=$(( module_scanned + _CACHES_USER_TOTAL ))

  caches::_saved_app_state
  module_scanned=$(( module_scanned + _CACHES_SAVEDSTATE_TOTAL ))

  caches::_antigravity
  module_scanned=$(( module_scanned + _CACHES_ANTIGRAVITY_TOTAL ))

  caches::_user_logs
  module_scanned=$(( module_scanned + _CACHES_LOGS_TOTAL ))

  caches::_app_support_caches
  module_scanned=$(( module_scanned + _CACHES_APPSUPPORT_TOTAL ))

  caches::_shell_caches
  module_scanned=$(( module_scanned + _CACHES_ZSH_TOTAL ))

  caches::_podcasts
  module_scanned=$(( module_scanned + _CACHES_PODCASTS_TOTAL ))

  caches::_jetbrains
  module_scanned=$(( module_scanned + _CACHES_JETBRAINS_TOTAL ))

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  module_summary "Caches" "$module_scanned"

  local status="clean"
  if (( module_scanned > 0 )); then
    status="$module_scanned"
  fi
  utils::register_module "Caches" "Caches & Logs" "$module_scanned" "$freed" "$status" "$projected"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Sub-module scanned totals (set by each helper, read by caches::clean)
_CACHES_USER_TOTAL=0
_CACHES_SAVEDSTATE_TOTAL=0
_CACHES_ANTIGRAVITY_TOTAL=0
_CACHES_LOGS_TOTAL=0
_CACHES_APPSUPPORT_TOTAL=0
_CACHES_ZSH_TOTAL=0
_CACHES_JETBRAINS_TOTAL=0
_CACHES_PODCASTS_TOTAL=0

caches::_user_caches() {
  _CACHES_USER_TOTAL=0
  local path="$HOME/Library/Caches"
  if [[ ! -d "$path" ]]; then
    log::info "User caches directory not found — skipping."
    return 0
  fi

  # Enumerate subdirectories with sizes; skip caches of running apps
  local total=0
  while IFS= read -r cache_dir; do
    local app_name
    app_name=$(basename "$cache_dir")
    # Skip JetBrains — handled exclusively by caches::_jetbrains
    [[ "$app_name" == "JetBrains" ]] && continue
    # Skip Homebrew — handled exclusively by brew::clean
    [[ "$app_name" == "Homebrew" ]] && continue
    if ! utils::is_deletable "$cache_dir"; then
      log::verbose "  Skipping protected: $(basename "$cache_dir")"
      continue
    fi
    if caches::_is_app_running "$app_name"; then
      log::verbose "Skipping active app cache: ${app_name}"
      continue
    fi
    safe_rm "$cache_dir" "$app_name"
    total=$(( total + SAFE_RM_LAST_BYTES ))
  done < <(find "$path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

  _CACHES_USER_TOTAL=$total
}

# ~/Library/Logs itself is SIP-protected, so the directory is never removed.
# Its per-app subdirectories are ordinary files and are cleaned individually.
# v0.4.x measured the whole tree and reported it as "found" even though nothing
# was ever queued, which is why Found never matched Reclaimable.
caches::_user_logs() {
  _CACHES_LOGS_TOTAL=0
  local path="$HOME/Library/Logs"
  if [[ ! -d "$path" ]]; then
    log::info "User logs directory not found — skipping."
    return 0
  fi

  local total=0
  local entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    utils::is_deletable "$entry" || continue
    local size
    size=$(utils::get_size_bytes "$entry")
    (( size > 0 )) || continue
    total=$(( total + size ))
    safe_rm "$entry" "User log: $(basename "$entry")" "silent"
  done < <(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null || true)

  _CACHES_LOGS_TOTAL=$total
  if (( total > 0 )); then
    log::info "User logs: $(utils::format_bytes "$total")"
  fi
}

caches::_app_support_caches() {
  _CACHES_APPSUPPORT_TOTAL=0
  local base="$HOME/Library/Application Support"
  if [[ ! -d "$base" ]]; then
    return 0
  fi

  local total=0
  while IFS= read -r cache_dir; do
    [[ -n "$cache_dir" ]] || continue

    local app_name
    app_name=$(basename "$(dirname "$cache_dir")")

    if [[ "$app_name" == com.apple.* ]]; then
      log::verbose "Skipping system app support: ${app_name}"
      continue
    fi

    if caches::_is_app_running "$app_name"; then
      log::verbose "Skipping active app cache: ${app_name}"
      continue
    fi

    safe_rm "$cache_dir" "${app_name}/$(basename "$cache_dir")"
    # Count only what safe_rm accepted. The editor-cache sweep in devtools.sh
    # reaches several of these paths first, and adding the du result here
    # regardless is what made Found exceed Reclaimable.
    total=$(( total + SAFE_RM_LAST_BYTES ))
  done < <(find "$base" -mindepth 2 -maxdepth 2 -type d \( -iname "cache" -o -iname "logs" -o -iname "log" -o -iname "tmp" -o -iname "temp" \) 2>/dev/null || true)
  _CACHES_APPSUPPORT_TOTAL=$total
}

# Check if the owner of a cache directory is currently running.
#
# Cache directory names are either a plain app name ("Slack") or a bundle id
# ("com.tinyspeck.slackmacgap"). pgrep matches process names, so a bundle id
# needs its trailing component tried as well — that is what the daemon or
# helper binary is usually called.
#
# The previous implementation grepped the whole `launchctl list` output for the
# name, which matched almost every substring and silently skipped real work.
# Cache directory names whose owning process cannot be derived from the name.
# Wiping a browser's cache while it runs makes it rewrite the files immediately
# (so nothing is reclaimed) and can corrupt its on-disk profile.
CACHE_OWNER_PROCESSES=(
  "Google|Google Chrome"
  "Firefox|firefox"
  "com.microsoft.edgemac|Microsoft Edge"
  "BraveSoftware|Brave Browser"
  "company.thebrowser.Browser|Arc"
  "com.operasoftware.Opera|Opera"
  "com.vivaldi.Vivaldi|Vivaldi"
  "com.spotify.client|Spotify"
  "com.tinyspeck.slackmacgap|Slack"
  "com.hnc.Discord|Discord"
  "com.microsoft.VSCode|Code"
  "com.todesktop.230313mzl4w4u92|Cursor"
  "Zen|zen"
)

caches::_cache_owner_process() {
  local dir_name="$1"
  local entry key value
  (( ${#CACHE_OWNER_PROCESSES[@]} > 0 )) || return 1
  for entry in "${CACHE_OWNER_PROCESSES[@]}"; do
    key="${entry%%|*}"
    value="${entry#*|}"
    if [[ "$dir_name" == "$key" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

# Process and launchd snapshots, taken once per run. The old per-app check
# forked `pgrep` up to three times plus a `launchctl list | awk | grep` pipeline
# for every candidate — hundreds of spawns for one sweep.
_CACHES_SNAPSHOT_READY=false
_CACHES_PROC_SNAPSHOT=""
_CACHES_LAUNCHD_LABELS=""

caches::_snapshot_processes_once() {
  [[ "$_CACHES_SNAPSHOT_READY" == "true" ]] && return 0
  _CACHES_SNAPSHOT_READY=true

  # Executable basenames, lowercased — mirrors `pgrep -xi`.
  _CACHES_PROC_SNAPSHOT="$(ps -Ao comm= 2>/dev/null | sed 's#.*/##' | tr '[:upper:]' '[:lower:]')"

  # Launchd labels are the third column of `launchctl list`.
  if command -v launchctl >/dev/null 2>&1; then
    _CACHES_LAUNCHD_LABELS="$(launchctl list 2>/dev/null | awk '{print $3}')"
  fi
  return 0
}

# Case-insensitive exact process-name match (mirrors `pgrep -xi`). nocasematch
# is toggled with bash builtins so there is no `tr` fork per candidate app.
caches::_process_running() {
  local needle="$1"
  [[ -n "$needle" ]] || return 1

  local restore=false
  shopt -q nocasematch || restore=true
  shopt -s nocasematch

  local line
  while IFS= read -r line; do
    if [[ "$line" == "$needle" ]]; then
      [[ "$restore" == "true" ]] && shopt -u nocasematch
      return 0
    fi
  done <<< "$_CACHES_PROC_SNAPSHOT"

  [[ "$restore" == "true" ]] && shopt -u nocasematch
  return 1
}

# Exact launchd-label match (mirrors `grep -qxF`).
caches::_launchd_has() {
  [[ -n "$1" ]] || return 1
  [[ $'\n'"$_CACHES_LAUNCHD_LABELS"$'\n' == *$'\n'"$1"$'\n'* ]]
}

caches::_is_app_running() {
  local app_name="$1"
  [[ -n "$app_name" ]] || return 1
  caches::_snapshot_processes_once

  # Known owners first — the directory name rarely matches the process name.
  local owner
  if owner=$(caches::_cache_owner_process "$app_name"); then
    caches::_process_running "$owner" && return 0
  fi

  caches::_process_running "$app_name" && return 0

  # Bundle-id form: try the last dot-separated component.
  if [[ "$app_name" == *.* ]]; then
    local leaf="${app_name##*.}"
    if [[ -n "$leaf" && ${#leaf} -ge 4 ]] && caches::_process_running "$leaf"; then
      return 0
    fi
  fi

  # A registered launchd label is an exact match, not a substring.
  caches::_launchd_has "$app_name" && return 0

  return 1
}



# ── Saved Application State ──────────────────────────────────────────────────
caches::_saved_app_state() {
  _CACHES_SAVEDSTATE_TOTAL=0
  local state_dir="$HOME/Library/Saved Application State"
  [[ -d "$state_dir" ]] || return 0

  local size
  size=$(utils::get_size_bytes "$state_dir")
  (( size > 0 )) || return 0

  log::info "Saved Application State: $(utils::format_bytes "$size")"
  safe_rm "$state_dir" "Saved Application State"
  _CACHES_SAVEDSTATE_TOTAL=$size
}

# ── Antigravity caches ───────────────────────────────────────────────────────
caches::_antigravity() {
  _CACHES_ANTIGRAVITY_TOTAL=0
  local antigravity_support="$HOME/Library/Application Support/Antigravity"
  [[ -d "$antigravity_support" ]] || return 0

  local total=0
  local -a cache_subdirs=(
    "GPUCache"
    "DawnGraphiteCache"
    "DawnWebGPUCache"
    "Code Cache"
    "Cache"
    "CachedData"
    "CachedExtensions"
  )

  for subdir in "${cache_subdirs[@]}"; do
    local full_path="${antigravity_support}/${subdir}"
    [[ -d "$full_path" ]] || continue
    local size
    size=$(utils::get_size_bytes "$full_path")
    (( size > 0 )) || continue
    log::info "  Antigravity ${subdir}: $(utils::format_bytes "$size")"
    safe_rm "$full_path" "Antigravity ${subdir}"
    total=$(( total + size ))
  done

  _CACHES_ANTIGRAVITY_TOTAL=$total
  if (( total > 0 )); then
    log::info "Antigravity caches: $(utils::format_bytes "$total")"
  fi
}

# ── Shell caches (zsh + Oh My Zsh) ───────────────────────────────────────────
caches::_shell_caches() {
  _CACHES_ZSH_TOTAL=0
  local total=0

  # Zsh completion cache files
  while IFS= read -r zcomp; do
    local size
    size=$(utils::get_size_bytes "$zcomp")
    total=$(( total + size ))
    safe_rm "$zcomp" "zsh completion cache" "" "$size"
  done < <(find "$HOME" -maxdepth 1 -name ".zcompdump*" -type f 2>/dev/null || true)

  # Oh My Zsh cache — delete contents, not the directory itself
  local omz_cache="$HOME/.oh-my-zsh/cache"
  if [[ -d "$omz_cache" ]]; then
    local omz_size
    omz_size=$(utils::get_size_bytes "$omz_cache")
    if (( omz_size > 0 )); then
      log::info "  Oh My Zsh cache: $(utils::format_bytes "$omz_size")"
      # Delete contents only — Oh My Zsh expects the directory to exist
      safe_rm_contents "$omz_cache" "Oh My Zsh cache"
      total=$(( total + omz_size ))
    fi
  fi

  _CACHES_ZSH_TOTAL=$total
  if (( total > 0 )); then
    log::info "Shell caches: $(utils::format_bytes "$total")"
  fi
}


# ── JetBrains IDE caches ──────────────────────────────────────────────────────
caches::_jetbrains() {
  _CACHES_JETBRAINS_TOTAL=0
  local total=0

  # Per-IDE system caches (~/Library/Caches/JetBrains/<IDEName><version>/)
  local jetbrains_cache_root="$HOME/Library/Caches/JetBrains"
  if [[ -d "$jetbrains_cache_root" ]]; then
    while IFS= read -r ide_cache_dir; do
      local size
      size=$(utils::get_size_bytes "$ide_cache_dir")
      if (( size > 0 )); then
        local dirname
        dirname="$(basename "$ide_cache_dir")"
        log::info "  JetBrains ${dirname}: $(utils::format_bytes "$size")"
        safe_rm "$ide_cache_dir" "JetBrains ${dirname} cache"
        total=$(( total + size ))
      fi
    done < <(find "$jetbrains_cache_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
  fi

  # Per-IDE log directories
  local jetbrains_log_root="$HOME/Library/Logs/JetBrains"
  if [[ -d "$jetbrains_log_root" ]]; then
    local logs_size
    logs_size=$(utils::get_size_bytes "$jetbrains_log_root")
    if (( logs_size > 0 )); then
      log::info "  JetBrains logs: $(utils::format_bytes "$logs_size")"
      safe_rm "$jetbrains_log_root" "JetBrains logs"
      total=$(( total + logs_size ))
    fi
  fi

  # Application Support leftovers (skip Toolbox itself — it stores installed IDEs)
  local jetbrains_support_root="$HOME/Library/Application Support/JetBrains"
  if [[ -d "$jetbrains_support_root" ]]; then
    while IFS= read -r support_dir; do
      local dirname
      dirname="$(basename "$support_dir")"
      [[ "$dirname" == "Toolbox" ]] && continue
      local size
      size=$(utils::get_size_bytes "$support_dir")
      if (( size > 0 )); then
        log::info "  JetBrains AppSupport ${dirname}: $(utils::format_bytes "$size")"
        safe_rm "$support_dir" "JetBrains AppSupport ${dirname}"
        total=$(( total + size ))
      fi
    done < <(find "$jetbrains_support_root" -mindepth 1 -maxdepth 1 -type d \
      -not -name "Toolbox" 2>/dev/null || true)
  fi

  _CACHES_JETBRAINS_TOTAL=$total
}

# ── Podcast tmp artifacts ────────────────────────────────────────────────────
caches::_podcasts() {
  _CACHES_PODCASTS_TOTAL=0
  local container="$HOME/Library/Containers/com.apple.podcasts/Data/tmp"
  [[ -d "$container" ]] || return 0

  local total=0

  local streamed_media="$container/StreamedMedia"
  if [[ -d "$streamed_media" ]]; then
    local size
    size=$(utils::get_size_bytes "$streamed_media")
    total=$(( total + size ))
    safe_rm "$streamed_media" "Podcasts streamed media" "" "$size"
  fi

  while IFS= read -r f; do
    local size
    size=$(utils::get_size_bytes "$f")
    total=$(( total + size ))
    safe_rm "$f" "Podcasts tmp" "" "$size"
  done < <(find "$container" -maxdepth 1 -type f \
    \( -name "*.heic" -o -name "*.img" -o -name "*CFNetworkDownload*.tmp" \) 2>/dev/null || true)

  _CACHES_PODCASTS_TOTAL=$total
}

