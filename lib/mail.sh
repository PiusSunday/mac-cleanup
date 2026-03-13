#!/usr/bin/env bash
# lib/mail.sh — Mail downloads and recent-item cleanup

readonly MAIL_ATTACHMENT_AGE_DAYS=30

_MAIL_TOTAL=0

mail::clean() {
  log::section "Mail & Communications"

  _MAIL_TOTAL=0
  local disk_before
  disk_before=$(utils::get_free_bytes)

  mail::_downloads
  mail::_recent_items

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then
    freed=0
  fi

  module_summary "Mail" "$_MAIL_TOTAL"

  local status="clean"
  if (( _MAIL_TOTAL > 0 )); then
    status="$_MAIL_TOTAL"
  fi

  utils::register_module "Mail" "Caches & Logs" "$_MAIL_TOTAL" "$freed" "$status"
}

mail::_downloads() {
  local -a mail_dirs=(
    "$HOME/Library/Mail Downloads"
    "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
  )

  local dir
  for dir in "${mail_dirs[@]}"; do
    [[ -d "$dir" ]] || continue

    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local size
      size=$(utils::get_size_bytes "$file")
      (( size > 0 )) || continue
      _MAIL_TOTAL=$(( _MAIL_TOTAL + size ))
      safe_rm "$file" "Mail attachment"
    done < <(find "$dir" -type f -mtime "+${MAIL_ATTACHMENT_AGE_DAYS}" 2>/dev/null || true)
  done
}

mail::_recent_items() {
  local shared="$HOME/Library/Application Support/com.apple.sharedfilelist"
  [[ -d "$shared" ]] || return 0

  while IFS= read -r f; do
    [[ -e "$f" ]] || continue
    local size
    size=$(utils::get_size_bytes "$f")
    _MAIL_TOTAL=$(( _MAIL_TOTAL + size ))
    safe_rm "$f" "Recent items list"
  done < <(find "$shared" -maxdepth 1 -type f -name "com.apple.LSSharedFileList.Recent*" 2>/dev/null || true)

  local pref_file="$HOME/Library/Preferences/com.apple.recentitems.plist"
  if [[ -f "$pref_file" ]]; then
    local size
    size=$(utils::get_size_bytes "$pref_file")
    _MAIL_TOTAL=$(( _MAIL_TOTAL + size ))
    safe_rm "$pref_file" "Recent items preferences"
  fi
}
