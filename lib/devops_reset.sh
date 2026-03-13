#!/usr/bin/env bash
# lib/devops_reset.sh — Nuclear cleanup mode for developer environments

devops_reset::run() {
  log::section "DevOps Reset Mode"
  log::warn "This mode performs deep cleanup across Docker and language toolchains."

  if [[ "$SKIP_CONFIRM" != "true" ]]; then
    utils::confirm "Proceed with DevOps Reset mode?" || return 0
  fi

  local disk_before
  disk_before=$(utils::get_free_bytes)

  devops_reset::_docker_full
  devops_reset::_node_deep
  devops_reset::_python_deep
  devops_reset::_ruby_deep
  devops_reset::_java_deep
  devops_reset::_rust_deep
  devops_reset::_ml_frameworks

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then
    freed=0
  fi

  module_summary "DevOps Reset" "$freed"

  local status="clean"
  if (( freed > 0 )); then
    status="$freed"
  fi

  utils::register_module "DevOps Reset" "Developer Tools" "$freed" "$freed" "$status"
}

devops_reset::_docker_full() {
  if ! utils::require docker; then
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    log::info "Docker daemon not running — skipping Docker reset."
    return 0
  fi

  log::info "Docker: enumerating stopped containers"
  local cid
  while IFS= read -r cid; do
    [[ -n "$cid" ]] || continue
    safe_rm_cmd docker rm "$cid" >/dev/null 2>&1 || true
  done < <(docker ps -a --filter status=exited --format '{{.ID}}' 2>/dev/null || true)

  log::info "Docker: enumerating dangling images"
  local iid
  while IFS= read -r iid; do
    [[ -n "$iid" ]] || continue
    safe_rm_cmd docker rmi "$iid" >/dev/null 2>&1 || true
  done < <(docker images -f dangling=true --format '{{.ID}}' 2>/dev/null || true)

  log::info "Docker: enumerating dangling volumes"
  local vid
  while IFS= read -r vid; do
    [[ -n "$vid" ]] || continue
    safe_rm_cmd docker volume rm "$vid" >/dev/null 2>&1 || true
  done < <(docker volume ls -qf dangling=true 2>/dev/null || true)

  log::info "Docker: pruning builder cache"
  safe_rm_cmd docker builder prune -af >/dev/null 2>&1 || true
}

devops_reset::_node_deep() {
  local -a paths=(
    "$HOME/.npm"
    "$HOME/.pnpm-store"
    "$HOME/.yarn/cache"
    "$HOME/.bun/install/cache"
    "$HOME/.tnpm/_cacache"
    "$HOME/.tnpm/_logs"
  )

  local p
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    safe_rm "$p" "Node ecosystem cache"
  done
}

devops_reset::_python_deep() {
  local -a paths=(
    "$HOME/Library/Caches/pip"
    "$HOME/.cache/pip"
    "$HOME/.cache/poetry"
    "$HOME/.cache/uv"
    "$HOME/.cache/mypy"
    "$HOME/.cache/ruff"
    "$HOME/.conda/pkgs"
    "$HOME/anaconda3/pkgs"
    "$HOME/.pyenv/cache"
    "$HOME/.pytest_cache"
  )

  local p
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    safe_rm "$p" "Python ecosystem cache"
  done
}

devops_reset::_ruby_deep() {
  local -a paths=(
    "$HOME/.bundle/cache"
    "$HOME/.gem/cache"
    "$HOME/.rbenv/cache"
  )

  local p
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    safe_rm "$p" "Ruby ecosystem cache"
  done
}

devops_reset::_java_deep() {
  local gradle_cache="$HOME/.gradle/caches"
  if [[ -d "$gradle_cache" ]]; then
    while IFS= read -r item; do
      [[ -e "$item" ]] || continue
      safe_rm "$item" "Gradle cache entry"
    done < <(find "$gradle_cache" -mindepth 1 -mtime +60 2>/dev/null || true)
  fi

  local maven_repo="$HOME/.m2/repository"
  if [[ -d "$maven_repo" ]]; then
    while IFS= read -r snapshot; do
      [[ -d "$snapshot" ]] || continue
      safe_rm "$snapshot" "Maven snapshot artifacts"
    done < <(find "$maven_repo" -type d -name "*SNAPSHOT*" 2>/dev/null || true)
  fi
}

devops_reset::_rust_deep() {
  local -a paths=(
    "$HOME/.cargo/registry/cache"
    "$HOME/.cargo/git"
    "$HOME/.rustup/downloads"
  )

  local p
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    safe_rm "$p" "Rust ecosystem cache"
  done
}

devops_reset::_ml_frameworks() {
  local -a safe_ml=(
    "$HOME/.cache/torch"
    "$HOME/.cache/tensorflow"
    "$HOME/.cache/wandb"
  )

  local p
  for p in "${safe_ml[@]}"; do
    [[ -e "$p" ]] || continue
    safe_rm "$p" "ML framework cache"
  done

  if [[ "$INCLUDE_ML_MODELS" == "true" ]]; then
    local -a model_caches=(
      "$HOME/.cache/huggingface"
      "$HOME/.ollama/models"
    )
    for p in "${model_caches[@]}"; do
      [[ -e "$p" ]] || continue
      safe_rm "$p" "ML model cache" "force"
    done
  else
    log::info "Skipping model caches (.cache/huggingface, .ollama/models). Use --include-ml-models to include them."
  fi
}
