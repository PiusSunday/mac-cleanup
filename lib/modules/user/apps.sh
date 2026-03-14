#!/usr/bin/env bash
# lib/modules/user/apps.sh — Deep cleaning for sandboxed apps and containers

_APPS_TOTAL=0

apps::clean() {
  log::section "Apps & Containers"

  _APPS_TOTAL=0
  local disk_before
  disk_before=$(utils::get_free_bytes)

  apps::_clean_containers "$HOME/Library/Containers"
  apps::_clean_containers "$HOME/Library/Group Containers"

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Apps & Containers" "$_APPS_TOTAL"

  local status="clean"
  if (( _APPS_TOTAL > 0 )); then status="$_APPS_TOTAL"; fi
  utils::register_module "Apps & Containers" "Caches & Logs" "$_APPS_TOTAL" "$freed" "$status"
}

apps::_add_scanned() {
  local bytes="$1"
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 )); then
    _APPS_TOTAL=$(( _APPS_TOTAL + bytes ))
  fi
}

apps::_clean_container_target() {
  local target_dir="$1"
  local app_name="$2"

  [[ -d "$target_dir" ]] || return 0

  local size
  size=$(utils::get_size_bytes "$target_dir")
  
  if (( size > 0 )); then
    apps::_add_scanned "$size"
    safe_rm_contents "$target_dir" "Container Cache | ${app_name}"
  fi
}

apps::_clean_containers() {
  local base_dir="$1"
  [[ -d "$base_dir" ]] || return 0

  while IFS= read -r container; do
    [[ -n "$container" && -d "$container" ]] || continue
    
    local cname
    cname=$(basename "$container")

    # Skip core Apple sandboxes to avoid breaking iCloud/System processes
    if [[ "$cname" == com.apple.* && "$cname" != com.apple.dt.Xcode* && "$cname" != com.apple.Safari* ]]; then
      continue
    fi

    # Clean standard cache directories inside the container
    apps::_clean_container_target "$container/Data/Library/Caches" "$cname"
    apps::_clean_container_target "$container/Data/Library/Logs" "$cname"
    apps::_clean_container_target "$container/Library/Caches" "$cname"
    
  done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
}
