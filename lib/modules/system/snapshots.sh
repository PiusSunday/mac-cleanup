#!/usr/bin/env bash
# lib/snapshots.sh — Local Time Machine snapshots cleanup

# Public entry point
snapshots::clean() {
  log::section "Snapshots"

  if ! utils::require tmutil; then
    utils::register_module "Snapshots" "Storage Management" "0" "0" "skipped"
    return 0
  fi

  log::warn "Deleting local snapshots means losing 'Go Back' ability in Time Machine for local changes."

  local snapshots
  snapshots=$(tmutil listlocalsnapshots / 2>/dev/null)

  local disk_before
  disk_before=$(utils::get_free_bytes)

  if [[ -z "$snapshots" ]]; then
    log::info "No local snapshots found."
    snapshots::_in_progress
    module_summary "Snapshots" "0"
    utils::register_module "Snapshots" "Storage Management" "0" "0" "clean"
    return 0
  fi

  snapshots::list
  dry_run_or_exec tmutil deletelocalsnapshots /
  snapshots::_in_progress

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Snapshots" "$freed"

  local status
  if (( freed > 0 )); then
    status="$freed"
  else
    status="clean"
  fi

  utils::register_module "Snapshots" "Storage Management" "0" "$freed" "$status"
}

# List local snapshots with timestamps
snapshots::list() {
  tmutil listlocalsnapshots / 2>/dev/null | while IFS= read -r snap; do
    local date_str
    date_str=$(echo "$snap" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' || true)
    printf "  %s  (%s)\n" "$snap" "$date_str"
  done
}

snapshots::_in_progress() {
  local volume
  for volume in /Volumes/*; do
    [[ -d "$volume/Backups.backupdb" ]] || continue
    local in_progress
    in_progress=$(find "$volume/Backups.backupdb" -maxdepth 2 -name "*.inProgress" 2>/dev/null || true)
    [[ -n "$in_progress" ]] || continue

    while IFS= read -r ip; do
      [[ -d "$ip" ]] || continue
      # Check if modification time is older than 1 day
      local age_days
      age_days=$(( ( $(date +%s) - $(stat -f%m "$ip" 2>/dev/null || echo 0) ) / 86400 ))
      if (( age_days > 1 )); then
        local size
        size=$(utils::get_size_bytes "$ip")
        safe_rm "$ip" "Stale Time Machine inProgress backup" "sudo"
      fi
    done <<< "$in_progress"
  done
}
