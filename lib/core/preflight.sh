#!/usr/bin/env bash
# lib/preflight.sh — Safety gates before any destructive operation

preflight::run() {
  log::section "Pre-Flight Checks"

  preflight::_disk_space
  preflight::_time_machine
  preflight::_battery
  preflight::_sip_status
}

preflight::_disk_space() {
  local free_bytes
  free_bytes=$(utils::get_free_bytes)
  local free_gb=$(( free_bytes / 1073741824 ))

  if (( free_gb < 5 )); then
    log::warn "Low disk space: ${free_gb} GB free. Cleanup may be unstable."
    if [[ "$SKIP_CONFIRM" != "true" ]]; then
      utils::confirm "Continue with low disk space?" || exit 0
    fi
  else
    log::success "Disk space: ${free_gb} GB free"
  fi
}

preflight::_time_machine() {
  if ! command -v tmutil >/dev/null 2>&1; then
    log::verbose "Time Machine status check unavailable (tmutil missing)."
    return 0
  fi

  local tm_status
  tm_status=$(tmutil status 2>/dev/null || true)
  if [[ "$tm_status" == *'"Running" = 1'* ]]; then
    log::warn "Time Machine backup is currently running."
    if [[ "$SKIP_CONFIRM" != "true" ]]; then
      utils::confirm "Continue while Time Machine is running?" || exit 0
    fi
  else
    log::success "Time Machine: no backup currently running"
  fi
}

preflight::_battery() {
  if ! command -v pmset >/dev/null 2>&1; then
    log::verbose "Battery check unavailable (pmset missing)."
    return 0
  fi

  local battery_info
  battery_info=$(pmset -g batt 2>/dev/null || true)
  local battery_pct
  battery_pct=$(echo "$battery_info" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
  local on_ac=0

  if [[ "$battery_info" == *"AC Power"* ]]; then
    on_ac=1
  fi

  if [[ -n "$battery_pct" && "$on_ac" -eq 0 && "$battery_pct" -lt 20 ]]; then
    log::warn "Battery is low (${battery_pct}%) and not on AC power."
    if [[ "$SKIP_CONFIRM" != "true" ]]; then
      utils::confirm "Continue on low battery?" || exit 0
    fi
  elif [[ -n "$battery_pct" ]]; then
    log::success "Battery: ${battery_pct}%"
  fi
}

preflight::_sip_status() {
  if ! command -v csrutil >/dev/null 2>&1; then
    log::verbose "SIP status check unavailable (csrutil missing)."
    return 0
  fi

  local sip_status
  sip_status=$(csrutil status 2>/dev/null || true)
  if [[ "$sip_status" == *"enabled"* ]]; then
    log::success "SIP: enabled"
  else
    log::warn "SIP: disabled"
  fi
}
