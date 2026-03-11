# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-03-11

### Added

- Flutter/Dart build cache detection (`build/`, `.dart_tool/`, `~/.pub-cache`) in devtools module
- npm `_npx` cache and `_logs` scanning in system module
- Zsh completion cache (`.zcompdump*`) scanning in caches module
- Spotify cache (`com.spotify.client`) scanning in caches module
- JetBrains IDE cache cleanup (Caches, Logs, Application Support) in caches module
- BATS tests for `system.sh` (9 tests) and `devtools.sh` (10 tests) — total: 51 tests

### Fixed

- Homebrew `brew cleanup -n` / `brew autoremove -n` no longer run during dry-run mode
- Summary TOTAL status, footer free space, and "Run complete" line all derive from the same value
- Header and footer free space now consistently display in GB (was showing GiB in header)
- `dry_run_or_exec` gracefully handles SIP permission errors instead of crashing
- `utils::with_spinner` no longer leaks `trap RETURN` into calling function scope

### Changed

- **BREAKING**: Removed `--live` / `--no-dry-run` / `-L` flags — replaced with standard confirmation flow:
  - Default behavior is dry-run (no flags needed)
  - `--yes` without `--dry-run` triggers live cleanup (skips prompt)
  - Running without `--dry-run` in a terminal prompts for confirmation
- `devtools.sh`: node_modules and `__pycache__` scans now only search conventional project dirs
  (`~/Developer`, `~/Projects`, `~/Code`, etc.) — excludes `.nvm`, `.vscode`, `.cursor`, `~/Library`
- Improved orphan node_modules detection: checks parent AND grandparent for `package.json`
- `.DS_Store` skip label changed from "protected by macOS" to "permission denied"
- `CONTRIBUTING.md` — develop-branch workflow, fork+upstream instructions
- `ci.yml` — triggers on `develop` branch, runs all test files via `bats tests/`
- README: updated flags table, examples, and safety notes for new confirmation flow

## [0.2.0] - 2026-03-04

### Added

- `lib/system.sh` — new module: crash reports, `.DS_Store`, Trash, dev tool caches (npm/pip/Go/pnpm), System Data clues (informational only — never deletes)
- `lib/devtools.sh` — new module: orphaned `node_modules`, Rust `target/` (via `cargo clean`), Python `__pycache__`, `.gradle/caches`
- `--system` / `-S` flag to run system scans in isolation
- `--devtools` / `-D` flag to scan developer build artifacts
- System context header at startup: architecture, macOS version, free disk, user/sudo mode
- Category-grouped output: System → Developer Tools → Caches & Logs → Storage Management
- `log::category` — visually distinct top-level category headers (`▶ Developer Tools`)
- `module_summary` — one-line result at end of each module (`✔ Xcode → 34.2 GB reclaimable`)
- Summary report: Category and Status columns, run duration, projected free space footer
- Extra safety prompt for `node_modules` directories over 500 MB (even with `--yes`)
- 3 new smoke tests: `--system`, `--devtools`, Summary Report output check
- Docker float size parsing test

### Changed

- `utils::register_module` now accepts 5 params: name, category, scanned, freed, status
- Summary header no longer repeats version or macOS (already shown at startup)
- Module section titles shortened (e.g., "Xcode Cleanup" → "Xcode")
- README updated with new modules, flags, category-grouped sample output, System Data clues section
- `Formula/mac-cleanup.rb` bumped to v0.2.0

## [0.1.0] - 2026-02-28

- Initial release of mac-cleanup CLI
- `lib/core.sh` — global state variables (DRY_RUN, VERBOSE, SKIP_CONFIRM, targets)
- `lib/utils.sh` — logging, colors, dry_run_or_exec, format_bytes, spinner, confirm
- `lib/xcode.sh` — Xcode DerivedData, Archives (90-day retention), DeviceSupport, Simulator caches
- `lib/docker.sh` — Docker stopped containers, dangling/unused images, build cache
- `lib/snapshots.sh` — Local Time Machine snapshot deletion via tmutil
- `lib/caches.sh` — ~/Library/Caches, ~/Library/Logs, Application Support caches
- `lib/brew.sh` — Homebrew cleanup --prune=all and autoremove
- `bin/mac-cleanup` — CLI entry point with full flag parsing and orchestration
- Dry-run mode as default — no files deleted without explicit opt-out
- Before/after free-space reporting
- Structured log file at `~/.mac-cleanup/cleanup.log`
- Bats unit tests for utils, xcode, and docker modules
- Smoke test for basic CLI sanity checking
- GitHub Actions CI: ShellCheck lint + Bats tests + smoke test
- `install.sh` standalone installer
- Homebrew formula skeleton
