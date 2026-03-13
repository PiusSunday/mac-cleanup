#!/usr/bin/env bash
# lib/orphans.sh — Detect and optionally remove orphaned app data

readonly ORPHAN_AGE_DAYS=30

_ORPHAN_TOTAL=0

declare -a ORPHAN_CANDIDATES=()

orphans::clean() {
  log::section "Orphaned App Data"

  _ORPHAN_TOTAL=0
  ORPHAN_CANDIDATES=()

  local disk_before
  disk_before=$(utils::get_free_bytes)

  local installed_tmp
  installed_tmp=$(mktemp "${TMPDIR:-/tmp}/mac-cleanup-installed.XXXXXX")
  orphans::_collect_installed_names "$installed_tmp"

  orphans::_scan_application_support "$installed_tmp"
  orphans::_scan_containers "$installed_tmp"
  orphans::_scan_preferences "$installed_tmp"

  safe_rm_internal "$installed_tmp"

  if [[ "$CLEAN_ORPHANS" == "true" ]]; then
    orphans::_delete_confirmed_candidates
  else
    log::info "Orphan detection is report-only by default. Use --clean-orphans to delete candidates."
  fi

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then
    freed=0
  fi

  module_summary "Orphans" "$_ORPHAN_TOTAL"

  local status="clean"
  if (( _ORPHAN_TOTAL > 0 )); then
    status="review"
  fi

  utils::register_module "Orphans" "System" "$_ORPHAN_TOTAL" "$freed" "$status"
}

orphans::_normalize_name() {
  local name="$1"
  name="${name#com.}"
  name="${name#org.}"
  name="${name#net.}"
  name="${name#io.}"
  echo "$name" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'
}

orphans::_collect_installed_names() {
  local outfile="$1"
  : > "$outfile"

  local cache_file="$HOME/.mac-cleanup/installed_apps_cache.txt"
  local now
  now=$(date +%s)
  if [[ -f "$cache_file" ]]; then
    local cache_mtime
    cache_mtime=$(stat -f%m "$cache_file" 2>/dev/null || echo 0)
    local cache_age=$(( now - cache_mtime ))
    if (( cache_age < 600 )); then
      cat "$cache_file" > "$outfile"
      return 0
    fi
  fi

  local -a app_dirs=(
    "/Applications"
    "$HOME/Applications"
  )

  local app_dir
  for app_dir in "${app_dirs[@]}"; do
    [[ -d "$app_dir" ]] || continue
    while IFS= read -r app_bundle; do
      [[ -d "$app_bundle" ]] || continue
      local app_name
      app_name=$(basename "$app_bundle" .app)
      orphans::_normalize_name "$app_name" >> "$outfile"

      local plist="$app_bundle/Contents/Info.plist"
      if [[ -f "$plist" ]]; then
        local bundle_id
        bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
        [[ -n "$bundle_id" ]] && orphans::_normalize_name "$bundle_id" >> "$outfile"
      fi
    done < <(find "$app_dir" -maxdepth 2 -type d -name "*.app" -prune 2>/dev/null || true)
  done

  sort -u "$outfile" -o "$outfile"
  mkdir -p "$(dirname "$cache_file")"
  cat "$outfile" > "$cache_file"
}

orphans::_is_recent() {
  local path="$1"
  local mtime
  mtime=$(stat -f%m "$path" 2>/dev/null || echo 0)
  local age_days=$(( ( $(date +%s) - mtime ) / 86400 ))
  (( age_days < ORPHAN_AGE_DAYS ))
}

orphans::_looks_installed() {
  local name="$1"
  local installed_file="$2"
  local normalized
  normalized=$(orphans::_normalize_name "$name")
  [[ -z "$normalized" ]] && return 0

  if grep -Fxq "$normalized" "$installed_file"; then
    return 0
  fi

  if grep -q "$normalized" "$installed_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

orphans::_record_candidate() {
  local path="$1"
  local name="$2"

  local size
  size=$(utils::get_size_bytes "$path")
  (( size > 0 )) || return 0

  _ORPHAN_TOTAL=$(( _ORPHAN_TOTAL + size ))
  ORPHAN_CANDIDATES+=("$path|$name|$size")
  log::warn "Orphan candidate: ${name} ($(utils::format_bytes "$size"))"
}

orphans::_scan_application_support() {
  local installed_file="$1"
  local base="$HOME/Library/Application Support"
  [[ -d "$base" ]] || return 0

  while IFS= read -r dir; do
    local name
    name=$(basename "$dir")

    case "$name" in
      Apple|com.apple.*|MobileSync|Caches|Xcode|JetBrains|SyncServices|CallHistoryDB)
        continue
        ;;
    esac

    orphans::_looks_installed "$name" "$installed_file" && continue
    orphans::_is_recent "$dir" && continue
    orphans::_record_candidate "$dir" "$name"
  done < <(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
}

orphans::_scan_containers() {
  local installed_file="$1"
  local base="$HOME/Library/Containers"
  [[ -d "$base" ]] || return 0

  while IFS= read -r dir; do
    local name
    name=$(basename "$dir")
    [[ "$name" == com.apple.* ]] && continue

    orphans::_looks_installed "$name" "$installed_file" && continue
    orphans::_is_recent "$dir" && continue
    orphans::_record_candidate "$dir" "$name"
  done < <(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
}

orphans::_scan_preferences() {
  local installed_file="$1"
  local base="$HOME/Library/Preferences"
  [[ -d "$base" ]] || return 0

  while IFS= read -r plist; do
    local name
    name=$(basename "$plist" .plist)
    [[ "$name" == com.apple.* ]] && continue

    orphans::_looks_installed "$name" "$installed_file" && continue
    orphans::_is_recent "$plist" && continue
    orphans::_record_candidate "$plist" "$name"
  done < <(find "$base" -maxdepth 1 -name "*.plist" -type f 2>/dev/null || true)
}

orphans::_delete_confirmed_candidates() {
  if (( ${#ORPHAN_CANDIDATES[@]} == 0 )); then
    return 0
  fi

  log::warn "--clean-orphans enabled: confirmation required per item"

  local candidate
  for candidate in "${ORPHAN_CANDIDATES[@]}"; do
    local path name size
    IFS='|' read -r path name size <<< "$candidate"

    if [[ "$SKIP_CONFIRM" == "true" ]]; then
      safe_rm "$path" "Orphan: $name"
      continue
    fi

    if utils::confirm "Delete orphan candidate '$name' ($(utils::format_bytes "$size"))?"; then
      safe_rm "$path" "Orphan: $name"
    else
      log::info "Skipped orphan candidate: $name"
    fi
  done
}
