#!/usr/bin/env bash
# lib/modules/user/browsers.sh — Deep cleaning for web browsers

_BROWSERS_TOTAL=0

browsers::clean() {
  log::section "Browsers"

  _BROWSERS_TOTAL=0
  local disk_before
  disk_before=$(utils::get_free_bytes)

  browsers::_chrome_versions
  browsers::_edge_versions
  browsers::_safari_icons
  browsers::_safari_cache
  browsers::_arc
  browsers::_zen

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Browsers" "$_BROWSERS_TOTAL"

  local status="clean"
  if (( _BROWSERS_TOTAL > 0 )); then status="$_BROWSERS_TOTAL"; fi
  utils::register_module "Browsers" "Caches & Logs" "$_BROWSERS_TOTAL" "$freed" "$status"
}

browsers::_add_scanned() {
  local bytes="$1"
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    _BROWSERS_TOTAL=$(( _BROWSERS_TOTAL + bytes ))
  fi
}

browsers::_cleanup_framework_versions() {
  local app_dir="$1"
  local framework_dir="$2"
  local label="$3"

  [[ -d "$framework_dir" ]] || return 0

  # Get the current version
  local current_version
  current_version=$(defaults read "${app_dir}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "")
  [[ -z "$current_version" ]] && return 0

  # Find version directories
  while IFS= read -r version_dir; do
    [[ -n "$version_dir" ]] || continue
    local vname
    vname=$(basename "$version_dir")
    if [[ "$vname" != "$current_version" && "$vname" =~ ^[0-9]+\.[0-9]+ ]]; then
      local size
      size=$(utils::get_size_bytes "$version_dir")
      browsers::_add_scanned "$size"
      safe_rm "$version_dir" "Old ${label} version ($vname)"
    fi
  done < <(find "$framework_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
}

browsers::_chrome_versions() {
  browsers::_cleanup_framework_versions "/Applications/Google Chrome.app" "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions" "Google Chrome"
}

browsers::_edge_versions() {
  browsers::_cleanup_framework_versions "/Applications/Microsoft Edge.app" "/Applications/Microsoft Edge.app/Contents/Frameworks/Microsoft Edge Framework.framework/Versions" "Microsoft Edge"
}

browsers::_safari_icons() {
  local cache="$HOME/Library/Safari/Favicon Cache"
  [[ -d "$cache" ]] || return 0
  local size
  size=$(utils::get_size_bytes "$cache")
  browsers::_add_scanned "$size"
  safe_rm_contents "$cache" "Safari Favicon Cache"
}

browsers::_safari_cache() {
  local cache="$HOME/Library/Caches/com.apple.Safari"
  [[ -d "$cache" ]] || return 0
  local size
  size=$(utils::get_size_bytes "$cache")
  browsers::_add_scanned "$size"
  safe_rm "$cache" "Safari Cache"
}

browsers::_arc() {
  local -a arc_paths=(
    "$HOME/Library/Caches/company.thebrowser.Browser"
    "$HOME/Library/Application Support/Arc/User Data/Default/Cache/Cache_Data"
    "$HOME/Library/Application Support/Arc/User Data/Default/GPUCache"
    "$HOME/Library/Application Support/Arc/User Data/Default/Code Cache"
    "$HOME/Library/Application Support/Arc/User Data/ShaderCache"
  )

  for cache in "${arc_paths[@]}"; do
    [[ -d "$cache" ]] || continue
    local size
    size=$(utils::get_size_bytes "$cache")
    browsers::_add_scanned "$size"
    safe_rm "$cache" "Arc Browser Cache"
  done
}

browsers::_zen() {
  local base="$HOME/Library/Caches/Zen"
  [[ -d "$base" ]] || return 0
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    local cache="$profile/cache2"
    [[ -d "$cache" ]] || continue
    local size
    size=$(utils::get_size_bytes "$cache")
    browsers::_add_scanned "$size"
    safe_rm "$cache" "Zen Browser Cache ($(basename "$profile"))"
  done < <(find "$base/Profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
}
