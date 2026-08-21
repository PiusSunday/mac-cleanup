#!/usr/bin/env bash
# lib/modules/user/apps.sh — Deep cleaning for sandboxed apps and containers

_APPS_TOTAL=0

apps::clean() {
  log::section "Apps & Containers"

  _APPS_TOTAL=0
  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  apps::_clean_containers "$HOME/Library/Containers"
  apps::_clean_containers "$HOME/Library/Group Containers"

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  module_summary "Apps & Containers" "$_APPS_TOTAL"

  local status="clean"
  if (( _APPS_TOTAL > 0 )); then status="$_APPS_TOTAL"; fi
  utils::register_module "Apps & Containers" "Caches & Logs" "$_APPS_TOTAL" "$freed" "$status" "$projected"
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

# Apple ships sandboxes under three prefixes, and only one of them is
# "com.apple.". Group containers are named "group.com.apple.<service>" and
# used to slip straight past the guard below — which is how the StoreKit group
# container's live storeUser.db and its -wal/-shm sidecars ended up queued for
# deletion. Match the Apple namespace wherever it appears in the identifier.
apps::_is_apple_container() {
  local cname="$1"
  case "$cname" in
    com.apple.* | group.com.apple.* | *.com.apple.* | com.apple)
      return 0
      ;;
  esac
  return 1
}

apps::_clean_containers() {
  local base_dir="$1"
  [[ -d "$base_dir" ]] || return 0

  while IFS= read -r container; do
    [[ -n "$container" && -d "$container" ]] || continue

    local cname
    cname=$(basename "$container")

    # Skip Apple sandboxes to avoid breaking iCloud, StoreKit and system agents.
    if apps::_is_apple_container "$cname"; then
      log::verbose "  Skipping Apple container: ${cname}"
      continue
    fi

    # Never clear a running app's sandbox: it rewrites the files immediately,
    # so nothing is reclaimed, and open databases can be left inconsistent.
    if caches::_is_app_running "$cname"; then
      log::verbose "  Skipping container (app running): ${cname}"
      continue
    fi

    # Clean standard cache directories inside the container
    apps::_clean_container_target "$container/Data/Library/Caches" "$cname"
    apps::_clean_container_target "$container/Data/Library/Logs" "$cname"
    apps::_clean_container_target "$container/Data/tmp" "$cname"
    apps::_clean_container_target "$container/Library/Caches" "$cname"

  done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
}
