#!/usr/bin/env bash
# lib/docker.sh — Docker containers, images, volumes, build cache cleanup

# Public entry point
docker::clean() {
  if ! utils::require docker; then
    utils::register_module "Docker" "Developer Tools" "0" "0" "skipped"
    return 0
  fi
  log::section "Docker"

  # Check Docker daemon is running
  if ! docker info &>/dev/null; then
    log::warn "Docker daemon is not running. Skipping."
    utils::register_module "Docker" "Developer Tools" "0" "0" "skipped"
    return 0
  fi

  local disk_before
  disk_before=$(utils::get_free_bytes)

  # Get Docker's pre-cleanup disk usage for scanning estimate
  local docker_usage=0
  local size_lines
  if size_lines=$(docker system df --format '{{.Size}}' 2>/dev/null); then
    log::verbose "Querying Docker disk usage..."
    # Sum reported Docker disk usage (images, containers, volumes, cache) in bytes
    while IFS= read -r size; do
      # Some formats may include extra columns; take the last whitespace-separated field
      size=${size##* }
      [[ -z "$size" ]] && continue
      if [[ "$size" =~ ^([0-9]+(\.[0-9]+)?)([kMGT]?B)$ ]]; then
        local num unit mult bytes
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[3]}"
        case "$unit" in
          B)     mult=1 ;;
          kB) mult=1000 ;;
          MB)    mult=1000000 ;;
          GB)    mult=1000000000 ;;
          TB)    mult=1000000000000 ;;
          *)     mult=1 ;;
        esac
        bytes=$(awk -v n="$num" -v m="$mult" 'BEGIN { printf "%.0f\n", n * m }')
        if [[ "$bytes" =~ ^[0-9]+$ ]]; then
          docker_usage=$(( docker_usage + bytes ))
        fi
      fi
    done <<< "$size_lines"
  fi

  docker::_containers
  docker::_images
  docker::_build_cache

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Docker" "$docker_usage"

  local status="clean"
  if (( docker_usage > 0 )); then
    status="$docker_usage"
  fi
  utils::register_module "Docker" "Developer Tools" "$docker_usage" "$freed" "$status"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

docker::_containers() {
  log::info "Removing stopped containers..."
  if [[ "$DRY_RUN" == "true" ]]; then
    dry_run_or_exec docker container prune -f
  else
    utils::with_spinner "Removing stopped containers..." docker container prune -f
  fi
}

docker::_images() {
  log::info "Removing dangling images..."
  if [[ "$DRY_RUN" == "true" ]]; then
    dry_run_or_exec docker image prune -f
  else
    utils::with_spinner "Removing dangling images..." docker image prune -f
  fi
  log::info "Removing unused images..."
  if [[ "$DRY_RUN" == "true" ]]; then
    dry_run_or_exec docker image prune -af
  else
    utils::with_spinner "Removing unused images..." docker image prune -af
  fi
}

docker::_build_cache() {
  log::info "Removing Docker build cache..."
  if [[ "$DRY_RUN" == "true" ]]; then
    dry_run_or_exec docker builder prune -af
  else
    utils::with_spinner "Removing Docker build cache..." docker builder prune -af
  fi
}

# Report current Docker disk usage (informational only)
docker::report_usage() {
  if utils::require docker; then
    docker system df 2>/dev/null || true
  fi
}
