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

# Public entry point
devtools::clean() {
  log::section "Developer Artifacts"

  local module_scanned=0

  local freed_before=$TOTAL_FREED
  local dryrun_before=$TOTAL_DRYRUN_BYTES

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

  devtools::_android
  module_scanned=$(( module_scanned + _DEV_ANDROID_TOTAL ))

  devtools::_vscode
  module_scanned=$(( module_scanned + _DEV_VSCODE_TOTAL ))

  local freed=$(( TOTAL_FREED - freed_before ))
  local dryrun_freed=$(( TOTAL_DRYRUN_BYTES - dryrun_before ))
  local projected=0
  if [[ "$DRY_RUN" == "true" ]]; then
    projected="$dryrun_freed"
  else
    projected="$freed"
  fi

  module_summary "Dev Artifacts" "$module_scanned"

  local status="clean"
  if (( module_scanned > 0 )); then
    status="$module_scanned"
  fi

  utils::register_module "Dev Artifacts" "Developer Tools" "$module_scanned" "$freed" "$status" "$projected"
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
_DEV_ANDROID_TOTAL=0
_DEV_VSCODE_TOTAL=0

# ── a) node_modules ──────────────────────────────────────────────────────────
# ── a) Stale project build artifacts ─────────────────────────────────────────
# Until v0.5.1 this scanned for node_modules with no nearby package.json and
# deleted those. A node_modules directory sits next to its package.json by
# definition, so the condition essentially never held: on the development
# machine the scan walked $HOME for ~30 seconds and reported
# "7 found (0 orphaned), total 0 B" every time.
#
# Staleness is the question worth asking. Build artifacts in a project nobody
# has touched for months are reclaimable and often large; the same artifacts in
# an active project are not. Deletion stays behind --purge-stale, matching how
# orphans and simulator runtimes are handled.
PROJECT_ARTIFACT_DIRS=(
  "node_modules"
  "target"
  "build"
  "dist"
  ".next"
  ".nuxt"
  ".dart_tool"
  ".gradle"
)

# Markers that identify the root of a real project.
PROJECT_ROOT_MARKERS=(
  "package.json" "pubspec.yaml" "Cargo.toml" "go.mod" "pyproject.toml"
  "setup.py" "Gemfile" "build.gradle" "build.gradle.kts" "pom.xml"
  "composer.json" "Package.swift" ".git"
)

# An artifact's parent directory is not always the project root: a Flutter app's
# android/.gradle sits two levels below the pubspec.yaml that dates the project.
# Judging staleness from the wrong directory is how the first cut of this scan
# reported build artifacts as "untouched 20685d" — 56 years, i.e. no source file
# was found and the mtime fell back to the epoch.
devtools::_project_root() {
  local dir="$1"
  local depth=0
  local marker

  while (( depth < 4 )) && [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    for marker in "${PROJECT_ROOT_MARKERS[@]}"; do
      if [[ -e "$dir/$marker" ]]; then
        printf '%s\n' "$dir"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
    (( depth++ )) || true
  done

  return 1
}

# Files whose mtime represents real work, as opposed to build output.
devtools::_project_last_touched() {
  local project="$1"
  local newest=0
  local f mtime

  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    mtime=$(stat -f%m "$f" 2>/dev/null || echo 0)
    (( mtime > newest )) && newest=$mtime
  done < <(
    find "$project" -maxdepth 2 -type f \
      \( -name "*.json" -o -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \
         -o -name "*.lock" -o -name "*.md" -o -name "*.ts" -o -name "*.js" \
         -o -name "*.py" -o -name "*.rs" -o -name "*.go" -o -name "*.dart" \
         -o -name "*.swift" -o -name "*.rb" \) \
      -not -path "*/node_modules/*" -not -path "*/target/*" \
      -not -path "*/build/*" -not -path "*/dist/*" 2>/dev/null | head -200
  )

  # A project whose git HEAD moved recently is active even if no file changed.
  if [[ -d "$project/.git" ]]; then
    mtime=$(stat -f%m "$project/.git" 2>/dev/null || echo 0)
    (( mtime > newest )) && newest=$mtime
  fi

  printf '%s\n' "$newest"
}

devtools::_node_modules() {
  _DEV_NODE_TOTAL=0
  log::info "Scanning for stale project build artifacts (untouched ${STALE_PROJECT_DAYS}+ days)..."

  local exclude_args=()
  while IFS= read -r -d '' arg; do
    exclude_args+=("$arg")
  done < <(devtools::_build_exclude_args DEVTOOLS_EXCLUDE_PATHS)

  local now cutoff
  now=$(date +%s)
  cutoff=$(( now - STALE_PROJECT_DAYS * 86400 ))

  local seen="|"
  local stale_count=0
  local active_count=0
  local total_bytes=0
  local scan_dir artifact project canonical

  for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue

    local name_args=()
    local first=true
    local d
    for d in "${PROJECT_ARTIFACT_DIRS[@]}"; do
      if [[ "$first" == "true" ]]; then
        name_args+=(-name "$d")
        first=false
      else
        name_args+=(-o -name "$d")
      fi
    done

    while IFS= read -r artifact; do
      [[ -n "$artifact" ]] || continue

      canonical="$(cd "$artifact" 2>/dev/null && pwd -P)" || continue
      [[ "$seen" == *"|$canonical|"* ]] && continue
      seen="${seen}${canonical}|"

      # Anchor on the nearest ancestor that actually looks like a project.
      project="$(devtools::_project_root "$(dirname "$artifact")")" || {
        log::verbose "  No project root above ${artifact} — skipping."
        continue
      }

      local touched
      touched=$(devtools::_project_last_touched "$project")
      if (( touched <= 0 )); then
        # Nothing datable. Refusing to guess beats reporting a 56-year age.
        log::verbose "  Cannot date ${project} — skipping."
        continue
      fi
      if (( touched > cutoff )); then
        (( active_count++ )) || true
        log::verbose "  Active: ${project}"
        continue
      fi

      local size_bytes
      size_bytes=$(utils::get_size_bytes "$artifact")
      (( size_bytes > 0 )) || continue

      (( stale_count++ )) || true
      total_bytes=$(( total_bytes + size_bytes ))

      local age_days=$(( (now - touched) / 86400 ))
      # Relative to home: eleven "android/.gradle" rows are indistinguishable,
      # and the project they belong to is the thing the user recognises.
      local label="${artifact/#$HOME\//}"
      if [[ "$PURGE_STALE" == "true" ]]; then
        safe_rm "$artifact" "stale build artifact: ${label} (${age_days}d)"
      else
        log::item "$size_bytes" "${label}  ${DIM}(untouched ${age_days}d)${RESET}"
      fi
    done < <(find "$scan_dir" -maxdepth 6 "${exclude_args[@]}" \( "${name_args[@]}" \) -type d -prune 2>/dev/null || true)
  done

  if [[ "$PURGE_STALE" == "true" ]]; then
    _DEV_NODE_TOTAL=$total_bytes
  else
    # Report-only: these bytes are not part of this run's reclaimable total.
    _DEV_NODE_TOTAL=0
    if (( stale_count > 0 )); then
      utils::register_action \
        "${stale_count} build artifacts in projects untouched for ${STALE_PROJECT_DAYS}+ days" \
        "$total_bytes" \
        "mac-cleanup --purge-stale"
    fi
  fi

  if (( stale_count > 0 )); then
    log::info "Stale artifacts: ${stale_count} in inactive projects ($(utils::format_bytes "$total_bytes")); ${active_count} active projects untouched"
  else
    log::info "Stale artifacts: none — all ${active_count} projects are active."
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

  local _seen_rust_targets="|"

  for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue

    while IFS= read -r target_dir; do
      [[ -n "$target_dir" ]] || continue
      
      local canonical
      canonical="$(cd "$target_dir" 2>/dev/null && pwd -P)" || continue
      if [[ "$_seen_rust_targets" == *"|$canonical|"* ]]; then
        continue
      fi
      _seen_rust_targets="${_seen_rust_targets}${canonical}|"

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
  local daemon_path="$HOME/.gradle/daemon"
  
  if [[ ! -d "$path" ]] && [[ ! -d "$daemon_path" ]]; then
    log::info "Gradle cache: not found — skipping."
    return 0
  fi

  local total=0

  # ~/.gradle/caches is not one cache. modules-2/ holds every downloaded
  # dependency jar and is expensive to refetch; build-cache-*, transforms-*,
  # journal-* and the versioned jar directories are regenerated build state.
  # v0.4.x deleted the whole tree, which forced a full re-download of every
  # dependency on the next build — space reclaimed, hours lost.
  if [[ -d "$path" ]]; then
    local -a gradle_disposable=()
    local entry
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      case "$(basename "$entry")" in
        build-cache-* | transforms-* | journal-* | jars-* | modules-2/files-2.1/*.lock)
          gradle_disposable+=("$entry")
          ;;
      esac
    done < <(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null || true)

    local g
    for g in "${gradle_disposable[@]}"; do
      local size_bytes
      size_bytes=$(utils::get_size_bytes "$g")
      (( size_bytes > 0 )) || continue
      safe_rm "$g" "Gradle $(basename "$g")"
      total=$(( total + size_bytes ))
    done

    local kept
    kept=$(utils::get_size_bytes "$path/modules-2")
    if (( kept > 0 )); then
      log::info "Gradle dependency cache kept: $(utils::format_bytes "$kept") (modules-2)"
    fi
  fi

  if [[ -d "$daemon_path" ]]; then
    local daemon_bytes
    daemon_bytes=$(utils::get_size_bytes "$daemon_path")
    if (( daemon_bytes > 0 )); then
      log::info "Gradle daemon logs: $(utils::format_bytes "$daemon_bytes")"
      safe_rm "$daemon_path" "Gradle daemon logs"
      total=$(( total + daemon_bytes ))
    fi
  fi

  _DEV_GRADLE_TOTAL=$total
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
    # `pnpm store prune` drops only packages no project references. Reporting
    # the whole store as reclaimable — which is what v0.4.x did — overstated
    # this by the size of every package still in use.
    _DEV_PNPM_TOTAL=0
    return 0
  fi

  utils::with_spinner "Running pnpm store prune..." pnpm store prune

  local size_after
  size_after=$(utils::get_size_bytes "$pnpm_path")
  if (( size_before > size_after )); then
    _DEV_PNPM_TOTAL=$(( size_before - size_after ))
    TOTAL_FREED=$(( TOTAL_FREED + _DEV_PNPM_TOTAL ))
    log::success "  pnpm store pruned ($(utils::format_bytes "$_DEV_PNPM_TOTAL"))"
  else
    _DEV_PNPM_TOTAL=0
  fi
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
  local _seen_flutter_projects="|"

  # Find Flutter projects by locating pubspec.yaml in scan dirs
  while IFS= read -r pubspec; do
    [[ -n "$pubspec" ]] || continue
    local project_dir
    project_dir="$(dirname "$pubspec")"

    local canonical
    canonical="$(cd "$project_dir" 2>/dev/null && pwd -P)" || continue
    if [[ "$_seen_flutter_projects" == *"|$canonical|"* ]]; then
      continue
    fi
    _seen_flutter_projects="${_seen_flutter_projects}${canonical}|"

    # build/ directory
    if [[ -d "${project_dir}/build" ]]; then
      local build_size
      build_size=$(utils::get_size_bytes "${project_dir}/build")
      total_bytes=$(( total_bytes + build_size ))
      safe_rm "${project_dir}/build" "Flutter build: ${project_dir##*/}"
    fi

    # .dart_tool/ directory
    if [[ -d "${project_dir}/.dart_tool" ]]; then
      local dt_size
      dt_size=$(utils::get_size_bytes "${project_dir}/.dart_tool")
      total_bytes=$(( total_bytes + dt_size ))
      safe_rm "${project_dir}/.dart_tool" "Flutter .dart_tool: ${project_dir##*/}"
    fi

  done < <(
    for scan_dir in "${DEVTOOLS_SCAN_DIRS[@]}"; do
      [[ -d "$scan_dir" ]] && \
        find "$scan_dir" -maxdepth 8 -name "pubspec.yaml" -not -path "*/build/*" 2>/dev/null
    done
  )

  if [[ -d "$HOME/.pub-cache" ]]; then
    local pub_size
    pub_size=$(utils::get_size_bytes "$HOME/.pub-cache")
    if (( pub_size > 0 )); then
      log::info "  Pub cache: $(utils::format_bytes "$pub_size") at ~/.pub-cache"
      log::warn "  Cleaning pub cache forces re-download of all packages on next build."
      if [[ "$DRY_RUN" == "true" ]]; then
        # utils::confirm now declines during a preview instead of blocking on
        # stdin, which is what made `--dry-run` hang here waiting for input.
        log::info "  A live run will ask before removing it; not counted as reclaimable."
      elif utils::confirm "Clean pub cache (~/.pub-cache)?"; then
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

# ── j) Android SDK Caches ────────────────────────────────────────────────────
devtools::_android() {
  _DEV_ANDROID_TOTAL=0
  local total=0

  if [[ ! -d "$HOME/.android" ]] && [[ ! -d "$HOME/Library/Android/sdk" ]]; then
    log::verbose "Android paths not found — skipping."
    return 0
  fi

  local -a android_paths=(
    "$HOME/.android/cache"
    "$HOME/Library/Android/sdk/.downloadIntermediates"
    "$HOME/Library/Android/sdk/system-images/.download"
  )

  for p in "${android_paths[@]}"; do
    [[ -d "$p" ]] || continue
    local size
    size=$(utils::get_size_bytes "$p")
    (( size > 0 )) || continue
    total=$(( total + size ))
    safe_rm "$p" "Android SDK cache: $(basename "$p")"
  done

  # Process AVD snapshots
  local avd_dir="$HOME/.android/avd"
  if [[ -d "$avd_dir" ]]; then
    while IFS= read -r snapshot_dir; do
      [[ -n "$snapshot_dir" ]] || continue
      local size
      size=$(utils::get_size_bytes "$snapshot_dir")
      (( size > 0 )) || continue
      total=$(( total + size ))
      safe_rm "$snapshot_dir" "Android AVD snapshot"
    done < <(find "$avd_dir" -mindepth 2 -maxdepth 4 -type d -name "snapshots" 2>/dev/null || true)
  fi

  _DEV_ANDROID_TOTAL=$total
}

# ── k) VS Code / Editor Caches ───────────────────────────────────────────────
devtools::_vscode() {
  _DEV_VSCODE_TOTAL=0
  local total=0

  local -a subdirs=(
    "logs"
    "Cache"
    "CachedData"
    "CachedExtensionVSIXs"
    "CachedExtensions"
  )

  for editor in "Code" "Code - Insiders" "Cursor" "Windsurf" "Zed" "VSCodium" "Antigravity IDE"; do
    local base="$HOME/Library/Application Support/$editor"
    [[ -d "$base" ]] || continue

    for sub in "${subdirs[@]}"; do
      local p="$base/$sub"
      [[ -d "$p" ]] || continue
      local size
      size=$(utils::get_size_bytes "$p")
      (( size > 0 )) || continue
      total=$(( total + size ))
      safe_rm "$p" "$editor cache/log: $sub"
    done

    # Workspace storage older than 30 days
    local storage="$base/User/workspaceStorage"
    if [[ -d "$storage" ]]; then
      while IFS= read -r stale_dir; do
        [[ -n "$stale_dir" ]] || continue
        local size
        size=$(utils::get_size_bytes "$stale_dir")
        (( size > 0 )) || continue
        total=$(( total + size ))
        safe_rm "$stale_dir" "$editor stale workspace: $(basename "$stale_dir")"
      done < <(find "$storage" -mindepth 1 -maxdepth 1 -type d -mtime +30 2>/dev/null || true)
    fi
  done

  _DEV_VSCODE_TOTAL=$total
}

