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

  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

  # What this module can actually free, object by object.
  #
  # v0.4.x summed the Size column of `docker system df`, which counts every
  # running container's image and every mounted volume. On a machine with a few
  # active stacks that reads "20.4 GB found" next to "0 B reclaimable" — real
  # numbers, but none of it cleanable, presented as if it were.
  #
  # `docker system df` Reclaimable is closer but still over-reports: it counts
  # every *unused* image, while this module only removes *dangling* ones. So the
  # estimate is built from the exact objects the helpers below will delete.
  local docker_usage=0
  docker_usage=$(( docker_usage + $(docker::_sum_sizes "$(docker images -f dangling=true --format '{{.Size}}' 2>/dev/null || true)") ))
  docker_usage=$(( docker_usage + $(docker::_sum_sizes "$(docker ps -a --filter status=exited --size --format '{{.Size}}' 2>/dev/null || true)") ))
  docker_usage=$(( docker_usage + $(docker::_build_cache_reclaimable) ))

  docker::_containers
  docker::_images
  docker::_volumes
  docker::_build_cache

  docker::_report_unused_images
  local unused_bytes="$_DOCKER_UNUSED_BYTES"

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    # Docker cleanup runs through the daemon, not safe_rm, so no bytes flow into
    # TOTAL_DRYRUN_BYTES. The object-level estimate above is the projection.
    projected=$(( dryrun_freed + docker_usage ))
  else
    projected="$freed"
  fi

  if (( docker_usage > 0 )); then
    log::info "Docker reclaimable: $(utils::format_bytes "$docker_usage")"
  fi
  module_summary "Docker" "$docker_usage"

  local status="clean"
  if (( docker_usage > 0 )); then
    status="$docker_usage"
  elif (( unused_bytes > 0 )); then
    # Nothing to auto-remove, but there are unused images worth a look.
    status="review"
  fi
  utils::register_module "Docker" "Developer Tools" "$docker_usage" "$freed" "$status" "$projected"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Sum a newline-separated list of Docker-formatted sizes ("1.2GB", "9.7MB") into
# bytes. Docker reports decimal units, so kB is 1000 and not 1024.
docker::_sum_sizes() {
  local lines="$1"
  local total=0
  local size num unit mult bytes

  while IFS= read -r size; do
    # Container sizes look like "1.2GB (virtual 340MB)" — keep the leading value.
    size=${size%% *}
    [[ -z "$size" ]] && continue
    if [[ "$size" =~ ^([0-9]+(\.[0-9]+)?)([kKMGT]?B)$ ]]; then
      num="${BASH_REMATCH[1]}"
      unit="${BASH_REMATCH[3]}"
      case "$unit" in
        B) mult=1 ;;
        kB|KB) mult=1000 ;;
        MB) mult=1000000 ;;
        GB) mult=1000000000 ;;
        TB) mult=1000000000000 ;;
        *) mult=1 ;;
      esac
      bytes=$(awk -v n="$num" -v m="$mult" 'BEGIN { printf "%.0f\n", n * m }')
      [[ "$bytes" =~ ^[0-9]+$ ]] && total=$(( total + bytes ))
    fi
  done <<< "$lines"

  printf '%s\n' "$total"
}

# Build cache is reported only as a `docker system df` row.
docker::_build_cache_reclaimable() {
  local row
  row=$(docker system df --format '{{.Type}}|{{.Reclaimable}}' 2>/dev/null \
    | awk -F'|' '$1 ~ /Build Cache/ {print $2; exit}') || row=""
  [[ -n "$row" ]] || { printf '0\n'; return 0; }
  row=${row%%(*}
  docker::_sum_sizes "$row"
}

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

# ── Unused but tagged images ──────────────────────────────────────────────────
# `docker system df` counts every image no running container references as
# "reclaimable", which is where its headline number comes from. This module will
# not delete them: a tagged image is something the user pulled or built on
# purpose, and `docker image prune -a` has no way to tell a stale base layer from
# the image behind a stack they start once a month. Report them individually
# with the exact command instead of quietly removing them.
_DOCKER_UNUSED_BYTES=0

docker::_report_unused_images() {
  _DOCKER_UNUSED_BYTES=0
  local -a unused=()
  local line

  while IFS=$'\t' read -r id repo tag size; do
    [[ -n "$id" ]] || continue
    [[ "$repo" == "<none>" ]] && continue
    if docker ps -a --filter "ancestor=${id}" --format '{{.ID}}' 2>/dev/null | grep -q .; then
      continue
    fi
    unused+=("${repo}:${tag}|${id}|${size}")
  done < <(docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null || true)

  (( ${#unused[@]} > 0 )) || return 0

  local total=0
  total=$(docker::_sum_sizes "$(printf '%s\n' "${unused[@]}" | awk -F'|' '{print $3}')")

  _DOCKER_UNUSED_BYTES="$total"

  printf '\n  %s%sUnused images%s %s(not removed — review and delete by name)%s\n' \
    "${BOLD}" "${YELLOW}" "${RESET}" "${DIM}" "${RESET}"
  for line in "${unused[@]}"; do
    local name id size
    IFS='|' read -r name id size <<< "$line"
    printf '  • %-48s %10s  %s\n' "$name" "$size" "$id"
  done
  printf '    Total: %s\n' "$(utils::format_bytes "$total")"

  utils::register_action \
    "${#unused[@]} unused Docker images (listed above)" \
    "$total" \
    "docker rmi <name>"
}
