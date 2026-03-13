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
  docker::_volumes
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
  log::info "Removing stopped containers by ID..."
  local cid
  while IFS= read -r cid; do
    [[ -n "$cid" ]] || continue
    safe_rm_cmd docker rm "$cid" || true
  done < <(docker ps -a --filter status=exited --format '{{.ID}}' 2>/dev/null || true)
}

docker::_images() {
  log::info "Removing dangling images by ID..."
  local iid
  while IFS= read -r iid; do
    [[ -n "$iid" ]] || continue
    safe_rm_cmd docker rmi "$iid" || true
  done < <(docker images -f dangling=true --format '{{.ID}}' 2>/dev/null || true)
}

docker::_volumes() {
  log::info "Removing dangling volumes by name..."
  local vol
  while IFS= read -r vol; do
    [[ -n "$vol" ]] || continue
    safe_rm_cmd docker volume rm "$vol" || true
  done < <(docker volume ls -qf dangling=true 2>/dev/null || true)
}

docker::_build_cache() {
  log::info "Removing Docker build cache..."
  safe_rm_cmd docker builder prune -af || true
}

# Report current Docker disk usage (informational only)
docker::report_usage() {
  if utils::require docker; then
    docker system df 2>/dev/null || true
  fi
}
