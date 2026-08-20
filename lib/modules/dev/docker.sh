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
  docker_usage=$(( docker_usage + $(docker::_dangling_reclaimable) ))
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

# One row per image: id|repository|tag|unique|shared|size|containers
#
# `docker images` cannot answer either question this module needs. Its Size
# column is the image's *full* size including shared base layers, so summing it
# counts each shared layer once per image that references it — a Supabase stack
# reported 14.9 GB against 3.56 GB actually freed. And deciding "unused" by
# matching container ancestry misses containers referencing an image under a
# different tag.
#
# `docker system df -v` answers both: UniqueSize is the space that actually
# comes back, and Containers is Docker's own reference count. The Go template
# keeps this dependency-free — no jq, and no python3, which is not present on a
# Mac without the Xcode command line tools.
docker::_image_table() {
  docker system df -v --format \
    '{{range .Images}}{{.ID}}|{{.Repository}}|{{.Tag}}|{{.UniqueSize}}|{{.SharedSize}}|{{.Size}}|{{.Containers}}
{{end}}' 2>/dev/null || true
}

# Docker prints ids as a full sha256 digest here; everywhere else it shows 12 hex chars.
docker::_short_id() {
  local id="${1#sha256:}"
  printf '%s\n' "${id:0:12}"
}

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

  local id repo tag unique shared size containers
  while IFS='|' read -r id repo tag unique shared size containers; do
    [[ -n "$id" ]] || continue
    [[ "$repo" == "<none>" ]] && continue
    # Containers is Docker's own reference count, and it counts stopped
    # containers too — a stopped container can be restarted at any time.
    [[ "$containers" == "0" ]] || continue
    unused+=("${repo}:${tag}|$(docker::_short_id "$id")|${unique}")
  done < <(docker::_image_table)

  (( ${#unused[@]} > 0 )) || return 0

  # Sum of unique sizes is a floor: layers shared only among the unused set also
  # come back once the last of them goes. Under-reporting is the safe direction.
  local total=0
  total=$(docker::_sum_sizes "$(printf '%s\n' "${unused[@]}" | awk -F'|' '{print $3}')")

  _DOCKER_UNUSED_BYTES="$total"

  printf '\n  %s%sUnused images%s %s(not removed — review and delete by name)%s\n' \
    "${BOLD}" "${YELLOW}" "${RESET}" "${DIM}" "${RESET}"
  local name short unique_fmt
  for line in "${unused[@]}"; do
    IFS='|' read -r name short unique_fmt <<< "$line"
    printf '  • %-48s %10s  %s\n' "$name" "$unique_fmt" "$short"
  done
  printf '    Frees at least %s %s(sizes exclude layers shared with images you keep)%s\n' \
    "$(utils::format_bytes "$total")" "${DIM}" "${RESET}"

  utils::register_action \
    "${#unused[@]} unused Docker images (listed above)" \
    "$total" \
    "docker rmi <name>"
}

# Dangling images are the untagged leftovers of a rebuild. Size them from the
# same sharing-aware table as everything else.
docker::_dangling_reclaimable() {
  local id repo tag unique shared size containers
  local total=0
  local sizes=""

  while IFS='|' read -r id repo tag unique shared size containers; do
    [[ -n "$id" ]] || continue
    [[ "$repo" == "<none>" ]] || continue
    [[ "$containers" == "0" ]] || continue
    sizes="${sizes}${unique}"$'\n'
  done < <(docker::_image_table)

  if [[ -n "$sizes" ]]; then
    total=$(docker::_sum_sizes "$sizes")
  fi
  printf '%s\n' "$total"
}
