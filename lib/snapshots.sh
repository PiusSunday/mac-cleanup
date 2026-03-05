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
    module_summary "Snapshots" "0"
    utils::register_module "Snapshots" "Storage Management" "0" "0" "clean"
    return 0
  fi

  snapshots::list
  dry_run_or_exec tmutil deletelocalsnapshots /

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
