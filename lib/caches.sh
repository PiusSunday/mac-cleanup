#!/usr/bin/env bash
# lib/caches.sh — ~/Library/Caches and app caches cleanup

# Public entry point
caches::clean() {
  log::section "Caches"

  local module_scanned=0
  local disk_before
  disk_before=$(utils::get_free_bytes)

  caches::_user_caches
  module_scanned=$(( module_scanned + _CACHES_USER_TOTAL ))

  caches::_browsers
  module_scanned=$(( module_scanned + _CACHES_BROWSERS_TOTAL ))

  caches::_containers
  module_scanned=$(( module_scanned + _CACHES_CONTAINERS_TOTAL ))

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

  caches::_spotify
  module_scanned=$(( module_scanned + _CACHES_SPOTIFY_TOTAL ))

  caches::_podcasts
  module_scanned=$(( module_scanned + _CACHES_PODCASTS_TOTAL ))

  caches::_apple_media
  module_scanned=$(( module_scanned + _CACHES_APPLEMEDIA_TOTAL ))

  caches::_jetbrains
  module_scanned=$(( module_scanned + _CACHES_JETBRAINS_TOTAL ))

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Caches" "$module_scanned"

  local status="clean"
  if (( module_scanned > 0 )); then
    status="$module_scanned"
  fi
  utils::register_module "Caches" "Caches & Logs" "$module_scanned" "$freed" "$status"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Sub-module scanned totals (set by each helper, read by caches::clean)
_CACHES_USER_TOTAL=0
_CACHES_BROWSERS_TOTAL=0
_CACHES_CONTAINERS_TOTAL=0
_CACHES_SAVEDSTATE_TOTAL=0
_CACHES_ANTIGRAVITY_TOTAL=0
_CACHES_LOGS_TOTAL=0
_CACHES_APPSUPPORT_TOTAL=0
_CACHES_ZSH_TOTAL=0
_CACHES_SPOTIFY_TOTAL=0
_CACHES_JETBRAINS_TOTAL=0
_CACHES_PODCASTS_TOTAL=0
_CACHES_APPLEMEDIA_TOTAL=0

caches::_user_caches() {
  _CACHES_USER_TOTAL=0
  local path="$HOME/Library/Caches"
  if [[ ! -d "$path" ]]; then
    log::info "User caches directory not found — skipping."
    return 0
  fi

  log::info "Scanning user caches (${path})..."

  # Enumerate subdirectories with sizes; skip caches of running apps
  local total=0
  while IFS= read -r cache_dir; do
    local app_name
    app_name=$(basename "$cache_dir")
    # Skip JetBrains — handled exclusively by caches::_jetbrains
    [[ "$app_name" == "JetBrains" ]] && continue
    if ! utils::is_deletable "$cache_dir"; then
      log::verbose "  Skipping protected: $(basename "$cache_dir")"
      continue
    fi
    if caches::_is_app_running "$app_name"; then
      log::verbose "Skipping active app cache: ${app_name}"
      continue
    fi
    local size_bytes
    size_bytes=$(utils::get_size_bytes "$cache_dir")
    total=$(( total + size_bytes ))
    local size_fmt
    size_fmt=$(utils::format_bytes "$size_bytes")
    log::info "  ${ARROW} ${size_fmt}  ${cache_dir}"
    safe_rm "$cache_dir" "User cache: ${app_name}"
  done < <(find "$path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

  _CACHES_USER_TOTAL=$total
  local total_fmt
  total_fmt=$(utils::format_bytes "$total")
  log::info "User caches total: ${total_fmt}"
}

caches::_user_logs() {
  _CACHES_LOGS_TOTAL=0
  local path="$HOME/Library/Logs"
  if [[ ! -d "$path" ]]; then
    log::info "User logs directory not found — skipping."
    return 0
  fi
  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  _CACHES_LOGS_TOTAL=$size_bytes
  local size
  size=$(utils::format_bytes "$size_bytes")
  log::info "User logs: ${size}"
  if ! utils::is_deletable "$path"; then
    log::verbose "Skipping protected: ${path}"
    return 0
  fi
  safe_rm_contents "$path" "User logs"
}

caches::_app_support_caches() {
  _CACHES_APPSUPPORT_TOTAL=0
  local base="$HOME/Library/Application Support"
  if [[ ! -d "$base" ]]; then
    return 0
  fi

  log::info "Scanning Application Support caches..."
  local total=0
  while IFS= read -r cache_dir; do
    local app_name
    app_name=$(basename "$(dirname "$cache_dir")")
    if caches::_is_app_running "$app_name"; then
      log::verbose "Skipping active app cache: ${app_name}"
      continue
    fi
    local size_bytes
    size_bytes=$(utils::get_size_bytes "$cache_dir")
    total=$(( total + size_bytes ))
    local size_fmt
    size_fmt=$(utils::format_bytes "$size_bytes")
    log::info "  ${ARROW} ${size_fmt}  ${cache_dir}"
    safe_rm "$cache_dir" "App Support Cache: ${app_name}"
  done < <(find "$base" -mindepth 2 -maxdepth 2 -type d -name "Cache" 2>/dev/null || true)
  _CACHES_APPSUPPORT_TOTAL=$total
}

# Check if an application is currently running (by process name).
# Uses pgrep -x for exact match; falls back to checking launchctl if available.
caches::_is_app_running() {
  local app_name="$1"
  # Try exact process name match first
  if pgrep -xi "$app_name" &>/dev/null; then
    return 0
  fi
  # Check if any macOS .app with this name is running via launchctl
  if command -v launchctl &>/dev/null; then
    if launchctl list 2>/dev/null | grep -qi "$app_name"; then
      return 0
    fi
  fi
  return 1
}

# ── Browser caches ───────────────────────────────────────────────────────────
caches::_browsers() {
  _CACHES_BROWSERS_TOTAL=0
  local total=0

  # Map of: process_name | cache_path | label
  local -a browser_entries=(
    "Google Chrome|$HOME/Library/Caches/Google/Chrome|Chrome cache"
    "Google Chrome|$HOME/Library/Application Support/Google/Chrome/Default/Application Cache|Chrome app cache"
    "Google Chrome|$HOME/Library/Application Support/Google/Chrome/Default/GPUCache|Chrome GPU cache"
    "Google Chrome|$HOME/Library/Application Support/Google/GoogleUpdater/crx_cache|GoogleUpdater CRX cache"
    "Firefox|$HOME/Library/Caches/Firefox|Firefox cache"
    "Microsoft Edge|$HOME/Library/Caches/com.microsoft.edgemac|Edge cache"
    "Arc|$HOME/Library/Caches/company.thebrowser.Browser|Arc cache"
    "Brave Browser|$HOME/Library/Caches/BraveSoftware/Brave-Browser|Brave cache"
    "Opera|$HOME/Library/Caches/com.operasoftware.Opera|Opera cache"
    "Vivaldi|$HOME/Library/Caches/com.vivaldi.Vivaldi|Vivaldi cache"
  )

  for entry in "${browser_entries[@]}"; do
    IFS='|' read -r process cache_path label <<< "$entry"

    [[ -d "$cache_path" ]] || continue

    # Skip if browser is currently running
    if pgrep -x "$process" &>/dev/null; then
      log::verbose "Skipping ${label} — ${process} is running"
      continue
    fi

    utils::is_deletable "$cache_path" || continue

    local size
    size=$(utils::get_size_bytes "$cache_path")
    if (( size > 0 )); then
      log::info "  ${label}: $(utils::format_bytes "$size")"
      safe_rm "$cache_path" "$label"
      total=$(( total + size ))
    fi
  done

  _CACHES_BROWSERS_TOTAL=$total
  if (( total > 0 )); then
    log::info "Browser caches: $(utils::format_bytes "$total")"
  fi
}

# ── Sandboxed app container caches ───────────────────────────────────────────
caches::_containers() {
  _CACHES_CONTAINERS_TOTAL=0
  local containers_dir="$HOME/Library/Containers"
  [[ -d "$containers_dir" ]] || return 0

  local total=0

  while IFS= read -r container_dir; do
    local bundle_id
    bundle_id=$(basename "$container_dir")

    # Never touch Apple system containers
    [[ "$bundle_id" == com.apple.* ]] && continue

    local -a candidate_dirs=(
      "${container_dir}/Data/Library/Caches"
      "${container_dir}/Data/tmp"
    )

    local cache_dir
    for cache_dir in "${candidate_dirs[@]}"; do
      [[ -d "$cache_dir" ]] || continue

      utils::is_deletable "$cache_dir" || continue

      # Skip if the owning app is currently running
      if pgrep -xi "$bundle_id" &>/dev/null; then
        log::verbose "  Skipping container cache (app running): ${bundle_id}"
        continue
      fi

      local size
      size=$(utils::get_size_bytes "$cache_dir")
      (( size > 0 )) || continue

      log::verbose "  Container cache: ${bundle_id} ($(utils::format_bytes "$size"))"
      safe_rm "$cache_dir" "Container cache: ${bundle_id}"
      total=$(( total + size ))
    done
  done < <(find "$containers_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

  _CACHES_CONTAINERS_TOTAL=$total
  if (( total > 0 )); then
    log::info "Sandboxed app container caches: $(utils::format_bytes "$total")"
  fi
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
    safe_rm "$zcomp" "zsh completion cache"
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

# ── Spotify cache ────────────────────────────────────────────────────────────
caches::_spotify() {
  _CACHES_SPOTIFY_TOTAL=0
  local spotify_cache="$HOME/Library/Caches/com.spotify.client"
  if [[ -d "$spotify_cache" ]]; then
    local size
    size=$(utils::get_size_bytes "$spotify_cache")
    if (( size > 0 )); then
      _CACHES_SPOTIFY_TOTAL=$size
      log::info "Spotify cache: $(utils::format_bytes "$size")"
      safe_rm "$spotify_cache" "Spotify cache"
    fi
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
    safe_rm "$streamed_media" "Podcasts streamed media"
  fi

  while IFS= read -r f; do
    local size
    size=$(utils::get_size_bytes "$f")
    total=$(( total + size ))
    safe_rm "$f" "Podcasts tmp"
  done < <(find "$container" -maxdepth 1 -type f \
    \( -name "*.heic" -o -name "*.img" -o -name "*CFNetworkDownload*.tmp" \) 2>/dev/null || true)

  _CACHES_PODCASTS_TOTAL=$total
}

# ── Apple media streaming caches ─────────────────────────────────────────────
caches::_apple_media() {
  _CACHES_APPLEMEDIA_TOTAL=0
  local total=0
  local -a media_caches=(
    "$HOME/Library/Caches/com.apple.Music"
    "$HOME/Library/Caches/com.apple.TV"
    "$HOME/Library/Caches/com.apple.podcasts"
  )

  local p
  for p in "${media_caches[@]}"; do
    [[ -d "$p" ]] || continue
    local size
    size=$(utils::get_size_bytes "$p")
    (( size > 0 )) || continue
    total=$(( total + size ))
    safe_rm "$p" "Apple media cache: $(basename "$p")"
  done

  _CACHES_APPLEMEDIA_TOTAL=$total
}
