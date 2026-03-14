#!/usr/bin/env bash
# lib/optimize/optimize.sh — System optimization routines

_OPTIMIZE_COUNT=0

optimize::run() {
  log::category "Optimization"

  log::section "System Optimization"

  _OPTIMIZE_COUNT=0
  
  optimize::_flush_dns
  optimize::_vacuum_sqlite
  optimize::_rebuild_launchservices
  optimize::_clear_font_cache

  if (( _OPTIMIZE_COUNT == 0 )); then
    log::success "  Optimization → No tasks ran"
  else
    log::success "  Optimization → Completed $_OPTIMIZE_COUNT tasks"
  fi
  
  utils::register_module "Optimization" "System Optimization" "0" "0" "$_OPTIMIZE_COUNT tasks"
}

optimize::_add_task() {
  _OPTIMIZE_COUNT=$(( _OPTIMIZE_COUNT + 1 ))
}

optimize::_flush_dns() {
  log::verbose "Flushing DNS cache..."
  if utils::require dscacheutil; then
    dry_run_or_exec sudo dscacheutil -flushcache
    dry_run_or_exec sudo killall -HUP mDNSResponder
    optimize::_add_task
    log::info "Flushed DNS cache"
  fi
}

optimize::_vacuum_sqlite() {
  log::verbose "Vacuuming Safari and Messages SQLite databases..."
  if ! utils::require sqlite3; then return 0; fi

  local dbs=(
    "$HOME/Library/Safari/History.db"
    "$HOME/Library/Messages/chat.db"
  )

  local db
  for db in "${dbs[@]}"; do
    [[ -f "$db" ]] || continue
    # Skip if locked
    if lsof "$db" >/dev/null 2>&1; then continue; fi
    utils::with_spinner "Vacuum $(basename "$db")" dry_run_or_exec sqlite3 "$db" "VACUUM;"
    optimize::_add_task
  done
}

optimize::_rebuild_launchservices() {
  log::verbose "Rebuilding LaunchServices database..."
  local ls_cmd="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$ls_cmd" ]]; then
    utils::with_spinner "Rebuild LaunchServices" dry_run_or_exec "$ls_cmd" -kill -r -domain local -domain system -domain user
    optimize::_add_task
  fi
}

optimize::_clear_font_cache() {
  log::verbose "Clearing font caches..."
  if utils::require atsutil; then
    utils::with_spinner "Clear Font Caches" dry_run_or_exec sudo atsutil databases -remove
    optimize::_add_task
  fi
}
