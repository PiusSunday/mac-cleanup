#!/usr/bin/env bash
# lib/devtools.sh — Developer project artifacts: node_modules, Rust target,
#                   Python __pycache__, Gradle caches.

# Public entry point
devtools::clean() {
  log::section "Developer Artifacts"

  local module_scanned=0

  local disk_before
  disk_before=$(utils::get_free_bytes)

  devtools::_node_modules
  module_scanned=$(( module_scanned + _DEV_NODE_TOTAL ))

  devtools::_rust_targets
  module_scanned=$(( module_scanned + _DEV_RUST_TOTAL ))

  devtools::_python_cache
  module_scanned=$(( module_scanned + _DEV_PYTHON_TOTAL ))

  devtools::_gradle_cache
  module_scanned=$(( module_scanned + _DEV_GRADLE_TOTAL ))

  local disk_after
  disk_after=$(utils::get_free_bytes)
  local freed=$(( disk_after - disk_before ))
  if (( freed < 0 )); then freed=0; fi

  module_summary "Dev Artifacts" "$module_scanned"

  local status="clean"
  if (( module_scanned > 0 )); then
    status="$module_scanned"
  fi

  utils::register_module "Dev Artifacts" "Developer Tools" "$module_scanned" "$freed" "$status"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

_DEV_NODE_TOTAL=0
_DEV_RUST_TOTAL=0
_DEV_PYTHON_TOTAL=0
_DEV_GRADLE_TOTAL=0

# ── a) node_modules ──────────────────────────────────────────────────────────
devtools::_node_modules() {
  _DEV_NODE_TOTAL=0
  log::info "Scanning for node_modules directories..."

  local total_count=0
  local orphan_count=0
  local total_bytes=0

  while IFS= read -r nm_dir; do
    local parent_dir
    parent_dir=$(dirname "$nm_dir")
    local size_bytes
    size_bytes=$(utils::get_size_bytes "$nm_dir")
    (( total_count++ )) || true

    local size_fmt
    size_fmt=$(utils::format_bytes "$size_bytes")

    if [[ ! -f "${parent_dir}/package.json" ]]; then
      # Orphaned — no package.json
      (( orphan_count++ )) || true
      total_bytes=$(( total_bytes + size_bytes ))
      log::warn "  Orphaned: ${nm_dir} (${size_fmt})"

      # Extra safety: prompt per-directory if >500 MB even with --yes
      if (( size_bytes > 524288000 )); then
        if [[ "$DRY_RUN" != "true" ]]; then
          printf '%s%s  This directory is %s — confirm deletion [y/N]: %s' \
            "${YELLOW}" "${WARN}" "$size_fmt" "${RESET}"
          local response=""
          if [[ -t 0 ]] || [[ -t 1 ]]; then
            if [[ -r /dev/tty ]]; then
              read -r response < /dev/tty
            else
              read -r response
            fi
          else
            log::warn "  Non-interactive shell; skipping deletion of ${nm_dir} (>500 MB)."
            response="n"
          fi
          if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log::info "  Skipped: ${nm_dir}"
            continue
          fi
        fi
      fi

      dry_run_or_exec rm -rf "$nm_dir"
    else
      log::verbose "  Active: ${nm_dir} (${size_fmt})"
    fi
  done < <(find "$HOME" -maxdepth 6 -name "node_modules" -type d -prune 2>/dev/null || true)

  _DEV_NODE_TOTAL=$total_bytes

  if (( total_count > 0 )); then
    log::info "node_modules: ${total_count} found (${orphan_count} orphaned), total $(utils::format_bytes "$total_bytes")"
  else
    log::info "node_modules: none found."
  fi
}

# ── b) Rust target/ directories ──────────────────────────────────────────────
devtools::_rust_targets() {
  _DEV_RUST_TOTAL=0

  if ! command -v cargo &>/dev/null; then
    log::verbose "cargo not installed — skipping Rust target scan."
    return 0
  fi

  log::info "Scanning for Rust target/ directories..."

  local total_count=0
  local total_bytes=0

  while IFS= read -r target_dir; do
    local parent_dir
    parent_dir=$(dirname "$target_dir")
    # Only consider if sibling Cargo.toml exists (actual Rust project)
    if [[ ! -f "${parent_dir}/Cargo.toml" ]]; then
      continue
    fi

    local size_bytes
    size_bytes=$(utils::get_size_bytes "$target_dir")
    total_bytes=$(( total_bytes + size_bytes ))
    (( total_count++ )) || true

    local size_fmt
    size_fmt=$(utils::format_bytes "$size_bytes")
    log::info "  ${ARROW} ${size_fmt}  ${parent_dir}"

    if [[ "$DRY_RUN" == "true" ]]; then
      log::info "  [DRY-RUN] Would run: cargo clean  (in ${parent_dir})"
    else
      # shellcheck disable=SC2016
      utils::with_spinner "Running cargo clean in ${parent_dir}..." \
        bash -c 'cd "$1" && cargo clean' _ "$parent_dir"
    fi
  done < <(find "$HOME" -maxdepth 6 -name "target" -type d 2>/dev/null || true)

  _DEV_RUST_TOTAL=$total_bytes

  if (( total_count > 0 )); then
    log::info "Rust targets: ${total_count} projects, total $(utils::format_bytes "$total_bytes")"
  else
    log::info "Rust target/ directories: none found."
  fi
}

# ── c) Python __pycache__ ────────────────────────────────────────────────────
devtools::_python_cache() {
  _DEV_PYTHON_TOTAL=0
  log::info "Scanning for Python __pycache__ directories..."

  local count=0
  local total_bytes=0

  while IFS= read -r cache_dir; do
    local size_bytes
    size_bytes=$(utils::get_size_bytes "$cache_dir")
    total_bytes=$(( total_bytes + size_bytes ))
    (( count++ )) || true
    dry_run_or_exec rm -rf "$cache_dir"
  done < <(find "$HOME" -maxdepth 8 -type d -name "__pycache__" 2>/dev/null || true)

  _DEV_PYTHON_TOTAL=$total_bytes

  if (( count > 0 )); then
    log::info "__pycache__: ${count} directories ($(utils::format_bytes "$total_bytes"))"
  else
    log::info "__pycache__: none found."
  fi
}

# ── d) .gradle cache ────────────────────────────────────────────────────────
devtools::_gradle_cache() {
  _DEV_GRADLE_TOTAL=0
  local path="$HOME/.gradle/caches"
  if [[ ! -d "$path" ]]; then
    log::info "Gradle cache: not found — skipping."
    return 0
  fi

  local size_bytes
  size_bytes=$(utils::get_size_bytes "$path")
  _DEV_GRADLE_TOTAL=$size_bytes

  log::info "Gradle cache: $(utils::format_bytes "$size_bytes")"
  dry_run_or_exec rm -rf "$path"
}
