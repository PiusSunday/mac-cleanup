#!/usr/bin/env bash
# lib/modules/system/assetcache.sh — Apple Content Caching store

# Apple's Content Caching service (System Settings → General → Sharing →
# Content Caching) keeps a copy of software updates, App Store downloads and
# iCloud content this Mac has already fetched, so other devices on the network
# can pull them from here instead of from Apple.
#
# The store lives in /Library, not in $HOME, which is why no other module looked
# at it, and reclaiming it needs admin rights. Flushing is safe — macOS
# re-fetches whatever it needs — but the store may be serving other devices, so
# it is never touched without --content-cache. A run without the flag measures
# the store and hands over the decision, the same shape as Orphans. When the flag
# is passed, admin rights are requested the way the deep sweep requests them.
readonly ASSETCACHE_DEFAULT_PATH="/Library/Application Support/com.apple.AssetCache"

assetcache::clean() {
  log::section "Content Caching"

  if ! utils::require AssetCacheManagerUtil; then
    utils::register_module "Content Caching" "System" "0" "0" "skipped"
    return 0
  fi

  local status_json
  status_json=$(AssetCacheManagerUtil -j status 2>/dev/null || true)

  # Not activated means the user never turned Content Caching on, so there is no
  # store here. Say that rather than reporting a fabricated empty cache.
  if ! printf '%s' "$status_json" | grep -q '"Activated"[[:space:]]*:[[:space:]]*true'; then
    log::info "Content Caching is not activated on this Mac."
    module_summary "Content Caching" 0 0
    utils::register_module "Content Caching" "System" "0" "0" "skipped"
    return 0
  fi

  local base found
  base=$(assetcache::_cache_path "$status_json")
  # Measure the store on disk so the figure matches what a flush frees. The
  # service's own byte count is the fallback for a store this user cannot walk.
  found=$(utils::get_size_bytes "$base")
  if (( found == 0 )); then
    found=$(assetcache::_reported_used "$status_json")
  fi

  if (( found == 0 )); then
    log::info "Content Caching store is empty: ${base}"
    module_summary "Content Caching" 0 0
    utils::register_module "Content Caching" "System" "0" "0" "clean"
    return 0
  fi

  log::info "Content Caching store: $(utils::format_bytes "$found") at ${base}"

  if [[ "${TARGET_CONTENT_CACHE:-false}" != "true" ]]; then
    assetcache::_offer "$base" "$found"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    module_summary "Content Caching" "$found" "$found"
    utils::register_module "Content Caching" "System" "$found" "0" "$found" "$found"
    return 0
  fi

  # Flushing is a root operation on a system-owned store, so ask for admin rights
  # the way the deep sweep does — interactively, and never during a preview. If
  # they are not granted, the store is left alone and the decision block carries
  # the command that works non-interactively, rather than reporting a flush that
  # never happened.
  if ! sudo -n true 2>/dev/null; then
    log::info "Flushing the Content Caching store requires administrator privileges."
    if ! sudo -v 2>/dev/null; then
      log::warn "Admin rights not granted; the Content Caching store is left alone."
      assetcache::_offer "$base" "$found"
      return 0
    fi
  fi

  dry_run_or_exec sudo AssetCacheManagerUtil flushCache

  # Trust the measurement, not the exit code: re-walk the store and credit what
  # actually went away, so a flush that frees nothing reports nothing.
  local after freed
  after=$(utils::get_size_bytes "$base")
  freed=$(( found - after ))
  (( freed < 0 )) && freed=0

  if (( freed > 0 )); then
    TOTAL_FREED=$(( TOTAL_FREED + freed ))
    log::info "Flushed $(utils::format_bytes "$freed") from the Content Caching store."
  else
    log::warn "The Content Caching store did not shrink; macOS may have refilled it."
  fi

  module_summary "Content Caching" "$found" "$freed"
  utils::register_module "Content Caching" "System" "$found" "$freed" "$freed" "$freed"
}

# Report-only path: the store is real and this run will not touch it.
assetcache::_offer() {
  local base="$1"
  local bytes="$2"
  log::verbose "Content Caching store left alone: ${base}"
  module_summary "Content Caching" "$bytes" 0
  utils::register_module "Content Caching" "System" "$bytes" "0" "review" "0"
  utils::register_action \
    "Content Caching — $(utils::format_bytes "$bytes") of updates cached for other devices" \
    "$bytes" \
    "sudo mac-cleanup --content-cache --yes"
}

# CachePath from `AssetCacheManagerUtil -j status`, falling back to the documented
# location when the service does not report one.
assetcache::_cache_path() {
  local json="$1"
  local path=""
  path=$(printf '%s' "$json" \
    | sed -n 's/.*"CachePath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  printf '%s' "${path:-$ASSETCACHE_DEFAULT_PATH}"
}

# The service's own byte count, for a store that cannot be walked on disk. It is
# never used to invent a size: only an activated store reaches this, and a store
# that reports nothing stays at zero.
assetcache::_reported_used() {
  local json="$1"
  local used=""
  used=$(printf '%s' "$json" \
    | sed -n 's/.*"CacheUsed"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
  printf '%s' "${used:-0}"
}
