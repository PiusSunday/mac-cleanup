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

  caches::_user_logs
  module_scanned=$(( module_scanned + _CACHES_LOGS_TOTAL ))

  caches::_app_support_caches
  module_scanned=$(( module_scanned + _CACHES_APPSUPPORT_TOTAL ))

  caches::_zsh_completion
  module_scanned=$(( module_scanned + _CACHES_ZSH_TOTAL ))

  caches::_spotify
  module_scanned=$(( module_scanned + _CACHES_SPOTIFY_TOTAL ))

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
_CACHES_LOGS_TOTAL=0
_CACHES_APPSUPPORT_TOTAL=0
_CACHES_ZSH_TOTAL=0
_CACHES_SPOTIFY_TOTAL=0

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
    dry_run_or_exec rm -rf "$cache_dir"
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
  dry_run_or_exec rm -rf "$path"
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
    dry_run_or_exec rm -rf "$cache_dir"
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

# ── Zsh completion cache ─────────────────────────────────────────────────────
caches::_zsh_completion() {
  _CACHES_ZSH_TOTAL=0
  local total=0

  while IFS= read -r zcomp; do
    local size
    size=$(utils::get_size_bytes "$zcomp")
    total=$(( total + size ))
    dry_run_or_exec rm -f "$zcomp"
  done < <(find "$HOME" -maxdepth 1 -name ".zcompdump*" -type f 2>/dev/null || true)

  _CACHES_ZSH_TOTAL=$total
  if (( total > 0 )); then
    log::info "Zsh completion cache: $(utils::format_bytes "$total")"
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
      dry_run_or_exec rm -rf "$spotify_cache"
    fi
  fi
}
