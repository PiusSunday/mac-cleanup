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

  # `tmutil listlocalsnapshots /` always prints a "Snapshots for disk /:" header,
  # so a plain emptiness test reported snapshots on every machine and the tool
  # claimed it would run deletelocalsnapshots when there was nothing to delete.
  # Count only real snapshot identifiers.
  local snapshots
  snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep -E '^com\.apple\.TimeMachine\.' || true)

  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  if [[ -z "$snapshots" ]]; then
    log::info "No local snapshots found."
    snapshots::_in_progress
    module_summary "Snapshots" "0"
    utils::register_module "Snapshots" "Storage Management" "0" "0" "clean"
    return 0
  fi

  local count
  count=$(printf '%s\n' "$snapshots" | grep -c . || true)

  snapshots::list
  dry_run_or_exec tmutil deletelocalsnapshots /
  snapshots::_in_progress

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  # tmutil does not report how much a snapshot occupies, and the deletion runs
  # through the daemon rather than safe_rm, so there are no bytes to attribute
  # in either mode. Reporting on $freed made a preview announce "Nothing to
  # clean" while listing real snapshots — the same defect as the Trash gate.
  # Report the count and let the decisions block carry it.
  if (( count > 0 )); then
    log::success "  Snapshots → ${count} local snapshot(s)"
  else
    module_summary "Snapshots" "$projected"
  fi

  local status="clean"
  if (( projected > 0 )); then
    status="$projected"
  elif (( count > 0 )); then
    status="review"
    utils::register_action \
      "${count} local Time Machine snapshot(s) — size not reported by macOS" \
      "0" \
      "mac-cleanup --snapshots"
  fi

  utils::register_module "Snapshots" "Storage Management" "$projected" "$freed" "$status" "$projected"
}

# List local snapshots with timestamps
snapshots::list() {
  tmutil listlocalsnapshots / 2>/dev/null \
    | grep -E '^com\.apple\.TimeMachine\.' \
    | while IFS= read -r snap; do
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
