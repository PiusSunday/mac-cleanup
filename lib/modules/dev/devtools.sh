#!/usr/bin/env bash
# lib/devtools.sh — Developer project artifacts: node_modules, Rust target,
#                   Python __pycache__, Gradle caches, Flutter/Dart build.
#
# NOTE: The scan dirs and exclusion lists below apply ONLY to devtools.sh.
# They do NOT restrict caches.sh, system.sh, or any other module.

# ── Scan scope — only conventional project roots ─────────────────────────────
DEVTOOLS_SCAN_DIRS=(
  "$HOME/Developer"
  "$HOME/Projects"
  "$HOME/Code"
  "$HOME/src"
  "$HOME/workspace"
  "$HOME/repos"
  "$HOME/dev"
  "$HOME/Desktop"
  "$HOME/Documents"
)

# Hard exclusions for devtools.sh project artifact scans ONLY.
# These are tool-managed directories, not user project roots.
# caches.sh and system.sh still clean paths inside ~/Library, ~/.npm, etc.
DEVTOOLS_EXCLUDE_PATHS=(
  "$HOME/.nvm"
  "$HOME/.vscode"
  "$HOME/.antigravity"
  "$HOME/.cursor"
  "$HOME/.windsurf"
  "$HOME/Library"
  "$HOME/.config"
  "$HOME/.cache"
  "$HOME/.npm"
  "$HOME/.pnpm"
  "$HOME/.yarn"
  "$HOME/.pyenv"
  "$HOME/.rbenv"
  "$HOME/.asdf"
)

# Additional exclusions for __pycache__ scans
PYCACHE_EXCLUDE_PATHS=(
  "$HOME/.pyenv"
  "$HOME/.venv"
  "$HOME/.virtualenvs"
  "$HOME/.config/gcloud"
  "$HOME/.vscode/extensions"
  "$HOME/.antigravity/extensions"
  "$HOME/.cursor/extensions"
  "$HOME/Library"
  "$HOME/.nvm"
)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Build find exclusion args securely into a caller's array
# Usage: while read args from NUL stream and append to local array
devtools::_build_exclude_args() {
  local in_array="$1[@]"
  local -a tmp=()
  local p
  for p in "${!in_array}"; do
    if [[ -d "$p" ]]; then
      tmp+=("-path" "$p" "-prune" "-o")
    fi
  done
  if (( ${#tmp[@]} == 0 )); then
    return 0
  fi
  printf '%s\0' "${tmp[@]}"
}

# Check if a node_modules has a nearby package.json (parent or grandparent)
devtools::_has_nearby_package_json() {
  local dir="$1"
  local parent
  parent="$(dirname "$dir")"
  local grandparent
  grandparent="$(dirname "$parent")"
  [[ -f "$parent/package.json" ]] || \
  [[ -f "$grandparent/package.json" ]]
}

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

  devtools::_cargo_cache
  module_scanned=$(( module_scanned + _DEV_CARGO_TOTAL ))

  devtools::_python_cache
  module_scanned=$(( module_scanned + _DEV_PYTHON_TOTAL ))

  devtools::_python_modern
  module_scanned=$(( module_scanned + _DEV_PYMODERN_TOTAL ))

  devtools::_gradle_cache
  module_scanned=$(( module_scanned + _DEV_GRADLE_TOTAL ))

  devtools::_ruby
  module_scanned=$(( module_scanned + _DEV_RUBY_TOTAL ))

  devtools::_pnpm
  module_scanned=$(( module_scanned + _DEV_PNPM_TOTAL ))

  devtools::_bun_tnpm
  module_scanned=$(( module_scanned + _DEV_BUNTNPM_TOTAL ))

  devtools::_flutter
  module_scanned=$(( module_scanned + _DEV_FLUTTER_TOTAL ))

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

# ── Internal state ────────────────────────────────────────────────────────────

_DEV_NODE_TOTAL=0
_DEV_RUST_TOTAL=0
_DEV_CARGO_TOTAL=0
_DEV_PYTHON_TOTAL=0
_DEV_GRADLE_TOTAL=0
_DEV_RUBY_TOTAL=0
_DEV_PNPM_TOTAL=0
_DEV_FLUTTER_TOTAL=0
_DEV_PYMODERN_TOTAL=0
_DEV_BUNTNPM_TOTAL=0

# ── a) node_modules ──────────────────────────────────────────────────────────
devtools::_node_modules() {
  _DEV_NODE_TOTAL=0
  log::info "Scanning for node_modules directories..."

  local total_count=0
  local orphan_count=0
  local total_bytes=0

  # Build exclusion args
  local exclude_args=()
  while IFS= read -r -d '' arg; do
    exclude_args+=("$arg")
  done < <(devtools::_build_exclude_args DEVTOOLS_EXCLUDE_PATHS)

  for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue

    while IFS= read -r nm_dir; do
      [[ -n "$nm_dir" ]] || continue
      local size_bytes
      size_bytes=$(utils::get_size_bytes "$nm_dir")
      (( total_count++ )) || true

      local size_fmt
      size_fmt=$(utils::format_bytes "$size_bytes")

      if ! devtools::_has_nearby_package_json "$nm_dir"; then
        # Orphaned — no nearby package.json
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

        safe_rm "$nm_dir" "orphaned node_modules"
      else
        log::verbose "  Active: ${nm_dir} (${size_fmt})"
      fi
    done < <(find "$scan_dir" -maxdepth 6 "${exclude_args[@]}" -name "node_modules" -type d -prune 2>/dev/null || true)
  done

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

  local exclude_args=()
  while IFS= read -r -d '' arg; do
    exclude_args+=("$arg")
  done < <(devtools::_build_exclude_args DEVTOOLS_EXCLUDE_PATHS)

  for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue

    while IFS= read -r target_dir; do
      [[ -n "$target_dir" ]] || continue
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
    done < <(find "$scan_dir" -maxdepth 6 "${exclude_args[@]}" -name "target" -type d 2>/dev/null || true)
  done

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

  # Build exclusion args from pycache-specific list
  local exclude_args=()
  while IFS= read -r -d '' arg; do
    exclude_args+=("$arg")
  done < <(devtools::_build_exclude_args PYCACHE_EXCLUDE_PATHS)

  for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue

    while IFS= read -r cache_dir; do
      [[ -n "$cache_dir" ]] || continue
      local size_bytes
      size_bytes=$(utils::get_size_bytes "$cache_dir")
      total_bytes=$(( total_bytes + size_bytes ))
      (( count++ )) || true
      safe_rm "$cache_dir" "python __pycache__"
    done < <(find "$scan_dir" -maxdepth 8 "${exclude_args[@]}" -type d -name "__pycache__" \
      -not -path "*/venv/*" \
      -not -path "*/.venv/*" \
      -not -path "*/env/*" \
      -not -path "*/.env/*" \
      -not -path "*/site-packages/*" \
      2>/dev/null || true)
  done

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
  [[ -d "$path" ]] || { log::info "Gradle cache: not found — skipping."; return 0; }

  local total=0
  # Age-gate: only delete version cache dirs older than 30 days
  while IFS= read -r cache_dir; do
    [[ -n "$cache_dir" ]] || continue
    local size
    size=$(utils::get_size_bytes "$cache_dir")
    (( size > 0 )) || continue
    log::info "  Gradle cache (stale): $(basename "$cache_dir") — $(utils::format_bytes "$size")"
    safe_rm "$cache_dir" "Gradle cache: $(basename "$cache_dir")"
    total=$(( total + size ))
  done < <(find "$path" -mindepth 1 -maxdepth 1 -type d -mtime +30 2>/dev/null || true)

  _DEV_GRADLE_TOTAL=$total
  if (( total == 0 )); then
    log::info "Gradle cache: no stale entries (all < 30 days old)."
  fi
}

# ── e) Ruby Bundler + Gem cache ───────────────────────────────────────────────
devtools::_ruby() {
  _DEV_RUBY_TOTAL=0

  if ! utils::require ruby && ! utils::require gem && ! utils::require bundle; then
    log::verbose "Ruby not installed — skipping Ruby cache scan."
    return 0
  fi

  log::info "Scanning for Ruby caches..."
  local total=0

  # Bundler cache — downloaded gem tarballs, safe to delete
  local bundler_cache="$HOME/.bundle/cache"
  if [[ -d "$bundler_cache" ]]; then
    local size
    size=$(utils::get_size_bytes "$bundler_cache")
    if (( size > 0 )); then
      log::info "  Ruby Bundler cache: $(utils::format_bytes "$size")"
      safe_rm "$bundler_cache" "Ruby Bundler cache"
      total=$(( total + size ))
    fi
  fi

  # RubyGems cache subdirectory only — never delete ~/.gem itself
  local gem_cache="$HOME/.gem/cache"
  if [[ -d "$gem_cache" ]]; then
    local size
    size=$(utils::get_size_bytes "$gem_cache")
    if (( size > 0 )); then
      log::info "  RubyGems cache: $(utils::format_bytes "$size")"
      safe_rm "$gem_cache" "RubyGems cache"
      total=$(( total + size ))
    fi
  fi

  # rbenv cache
  if utils::require rbenv; then
    local rbenv_cache="$HOME/.rbenv/cache"
    if [[ -d "$rbenv_cache" ]]; then
      local size
      size=$(utils::get_size_bytes "$rbenv_cache")
      if (( size > 0 )); then
        log::info "  rbenv cache: $(utils::format_bytes "$size")"
        safe_rm "$rbenv_cache" "rbenv cache"
        total=$(( total + size ))
      fi
    fi
  fi

  _DEV_RUBY_TOTAL=$total
  if (( total == 0 )); then
    log::verbose "Ruby caches: nothing to clean."
  fi
}

# ── f) Cargo registry cache ──────────────────────────────────────────────────
devtools::_cargo_cache() {
  _DEV_CARGO_TOTAL=0

  if ! utils::require cargo; then
    log::verbose "cargo not installed — skipping Cargo cache scan."
    return 0
  fi

  local total=0

  local cargo_registry="$HOME/.cargo/registry/cache"
  if [[ -d "$cargo_registry" ]]; then
    local size
    size=$(utils::get_size_bytes "$cargo_registry")
    if (( size > 0 )); then
      log::info "  Cargo registry cache: $(utils::format_bytes "$size")"
      safe_rm "$cargo_registry" "Cargo registry cache"
      total=$(( total + size ))
    fi
  fi

  local cargo_git="$HOME/.cargo/git/db"
  if [[ -d "$cargo_git" ]]; then
    local size
    size=$(utils::get_size_bytes "$cargo_git")
    if (( size > 0 )); then
      log::info "  Cargo git cache: $(utils::format_bytes "$size")"
      safe_rm "$cargo_git" "Cargo git cache"
      total=$(( total + size ))
    fi
  fi

  _DEV_CARGO_TOTAL=$total
  if (( total > 0 )); then
    log::info "Cargo cache: $(utils::format_bytes "$total")"
  fi
}

# ── g) pnpm store prune ──────────────────────────────────────────────────────
devtools::_pnpm() {
  _DEV_PNPM_TOTAL=0

  if ! utils::require pnpm; then
    log::verbose "pnpm not installed — skipping."
    return 0
  fi

  local pnpm_path
  pnpm_path=$(pnpm store path 2>/dev/null || true)
  [[ -n "$pnpm_path" && -d "$pnpm_path" ]] || return 0

  local size_before
  size_before=$(utils::get_size_bytes "$pnpm_path")
  log::info "  pnpm store: $(utils::format_bytes "$size_before") at ${pnpm_path}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log::info "[DRY-RUN] Would run: pnpm store prune"
  else
    utils::with_spinner "Running pnpm store prune..." pnpm store prune
  fi

  _DEV_PNPM_TOTAL=$size_before
}

# ── e) Flutter/Dart build artifacts ──────────────────────────────────────────
devtools::_flutter() {
  _DEV_FLUTTER_TOTAL=0

  if ! command -v flutter &>/dev/null; then
    log::verbose "Flutter not installed — skipping Flutter artifact scan."
    return 0
  fi

  log::info "Scanning for Flutter build artifacts..."

  local total_bytes=0

  # Find Flutter projects by locating pubspec.yaml in scan dirs
  while IFS= read -r pubspec; do
    [[ -n "$pubspec" ]] || continue
    local project_dir
    project_dir="$(dirname "$pubspec")"

    # build/ directory
    if [[ -d "${project_dir}/build" ]]; then
      local build_size
      build_size=$(utils::get_size_bytes "${project_dir}/build")
      total_bytes=$(( total_bytes + build_size ))
      log::info "  ${ARROW} $(utils::format_bytes "$build_size")  ${project_dir}/build"
      safe_rm "${project_dir}/build" "Flutter build directory"
    fi

    # .dart_tool/ directory
    if [[ -d "${project_dir}/.dart_tool" ]]; then
      local dt_size
      dt_size=$(utils::get_size_bytes "${project_dir}/.dart_tool")
      total_bytes=$(( total_bytes + dt_size ))
      log::info "  ${ARROW} $(utils::format_bytes "$dt_size")  ${project_dir}/.dart_tool"
      safe_rm "${project_dir}/.dart_tool" "Flutter .dart_tool"
    fi

  done < <(
    for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
      [[ -d "$scan_dir" ]] && \
        find "$scan_dir" -maxdepth 8 -name "pubspec.yaml" -not -path "*/build/*" 2>/dev/null
    done
  )

  # ~/.pub-cache — report and prompt separately
  if [[ -d "$HOME/.pub-cache" ]]; then
    local pub_size
    pub_size=$(utils::get_size_bytes "$HOME/.pub-cache")
    if (( pub_size > 0 )); then
      log::info "  Pub cache: $(utils::format_bytes "$pub_size") at ~/.pub-cache"
      log::warn "  Cleaning pub cache forces re-download of all packages on next build."
      if utils::confirm "Clean pub cache (~/.pub-cache)?"; then
        safe_rm "$HOME/.pub-cache" "Flutter pub cache"
        total_bytes=$(( total_bytes + pub_size ))
      fi
    fi
  fi

  _DEV_FLUTTER_TOTAL=$total_bytes

  if (( total_bytes > 0 )); then
    log::info "Flutter artifacts: $(utils::format_bytes "$total_bytes") reclaimable"
  else
    log::info "Flutter artifacts: none found."
  fi
}

# ── h) Modern Python ecosystem caches ───────────────────────────────────────
devtools::_python_modern() {
  _DEV_PYMODERN_TOTAL=0
  local total=0
  local -a paths=(
    "$HOME/.cache/uv"
    "$HOME/.cache/ruff"
    "$HOME/.cache/mypy"
    "$HOME/.cache/poetry"
    "$HOME/.cache/wandb"
    "$HOME/.cache/torch"
    "$HOME/.cache/tensorflow"
    "$HOME/.conda/pkgs"
    "$HOME/anaconda3/pkgs"
    "$HOME/.pyenv/cache"
  )

  local p
  for p in "${paths[@]}"; do
    [[ -d "$p" ]] || continue
    local size
    size=$(utils::get_size_bytes "$p")
    (( size > 0 )) || continue
    total=$(( total + size ))
    safe_rm "$p" "Python modern cache: $(basename "$p")"
  done

  _DEV_PYMODERN_TOTAL=$total
}

# ── i) Bun and tnpm caches ──────────────────────────────────────────────────
devtools::_bun_tnpm() {
  _DEV_BUNTNPM_TOTAL=0
  local total=0

  # Bun
  if command -v bun &>/dev/null; then
    local -a bun_paths=(
      "$HOME/Library/Caches/bun"
      "$HOME/.bun/install/cache"
    )
    for p in "${bun_paths[@]}"; do
      [[ -d "$p" ]] || continue
      local size
      size=$(utils::get_size_bytes "$p")
      (( size > 0 )) || continue
      total=$(( total + size ))
      safe_rm "$p" "Bun cache: $(basename "$p")"
    done
  fi

  # tnpm
  local -a tnpm_paths=(
    "$HOME/.tnpm/_cacache"
    "$HOME/.tnpm/_logs"
  )

  local p
  for p in "${tnpm_paths[@]}"; do
    [[ -d "$p" ]] || continue
    local size
    size=$(utils::get_size_bytes "$p")
    (( size > 0 )) || continue
    total=$(( total + size ))
    safe_rm "$p" "JS runtime cache: $(basename "$p")"
  done

  _DEV_BUNTNPM_TOTAL=$total
}
