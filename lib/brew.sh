#!/usr/bin/env bash
# lib/brew.sh — Homebrew cleanup and autoremove

# Public entry point
brew::clean() {
  if ! utils::require brew; then
    utils::register_module "Homebrew" "Caches & Logs" "0" "0" "skipped"
    return 0
  fi
  log::section "Homebrew"

  local disk_before
  disk_before=$(utils::get_free_bytes)

  # Measure cache size before cleanup — use brew --cache with fallback
  local brew_cache_size=0
  local brew_cache_dir
  brew_cache_dir="$(brew --cache 2>/dev/null)" || brew_cache_dir=""

  # Fallback to known default if brew --cache fails or returns empty
  if [[ -z "$brew_cache_dir" || ! -d "$brew_cache_dir" ]]; then
    brew_cache_dir="$HOME/Library/Caches/Homebrew"
  fi

  if [[ -d "$brew_cache_dir" ]]; then
    brew_cache_size=$(utils::get_size_bytes "$brew_cache_dir")
  fi

  log::info "Homebrew cache: $(utils::format_bytes "$brew_cache_size") at ${brew_cache_dir}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log::info "[DRY-RUN] Would run: brew cleanup --prune=all"
    log::info "[DRY-RUN] Would run: brew autoremove"
  else
    utils::with_spinner "Running brew cleanup --prune=all..." brew cleanup --prune=all
    utils::with_spinner "Running brew autoremove..." brew autoremove
  fi

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Homebrew" "$brew_cache_size"

  local status="clean"
  if (( brew_cache_size > 0 )); then
    status="$brew_cache_size"
  fi
  utils::register_module "Homebrew" "Caches & Logs" "$brew_cache_size" "$freed" "$status"
}
