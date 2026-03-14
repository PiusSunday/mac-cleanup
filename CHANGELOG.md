# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.4.1] - 2026-03-14

### Added

- **Deep Clean**: `/private/var/folders` temporary item cleanup.
- **Deep Clean**: MacOS Installer (`.app` and `.pkg`) abandoned payload sweeping (age-gated >14 days).
- **System**: Broken `.plist` preferences detection via `plutil -lint`.
- **Browsers**: Expanded Arc browser targets and added Safari cache cleaning.
- **Developer**: Bun / `tnpm` cache support.
- **Developer**: Gradle caches now age-gated to >30 days.

### Changed

- **CLI**: Unified Logs `sudo` prompt now provides explicit explanation before elevating access.
- **CLI**: Pre-flight checks correctly follow the mode banner and system context.
- **CLI**: Summary table columns standardized to fixed widths for alignment.
- **CLI**: Status labels are mode-aware (`Clean` vs `✔ Done`).

### Fixed

- **Core**: Dry-run reporting bug where skipped bytes artificially bloated the projected totals.
- **System**: `.DS_Store` verbose output spam suppressed to a single summary line.

## [0.4.0] - 2026-03-14

### Added

- **Domain-Driven Architecture Refactor**: The monolithic `lib/` directory has been restructured into `core/`, `modules/system/`, `modules/user/`, `modules/dev/`, and `optimize/` for better scalability.
- **Advanced Application Cleaning**: Iterates safely through User Containers to clear caches while skipping critical `com.apple.*` sandboxes to protect iCloud usage.
- **Deep Browser Frameworks Cleanup**: Detects and purges abandoned older framework payloads for Google Chrome and Microsoft Edge. Also cleans Safari Favicon caches, Arc, and Zen browsers.
- **Time Machine Cleanup Expansions**: Detects and deletes stale orphaned `.inProgress` backups older than 1 day.
- **macOS Installer Leftovers**: Purges abandoned macOS Installer applications (`/Applications/Install macOS*.app`) and `macOS Install Data` folders older than 14 days.
- **Deep System Diagnostics**: Added code-signing download cache clearing (`com.apple.nsurlsessiond/Downloads`).
- **Optimization Target (`--optimize` / `-O`)**: New flag that triggers DNS cache flushing, LaunchServices rebuilding, Safari/Messages SQLite Vacuuming, and font cache deletion.

### Changed

- Lowered `DEEP_LOG_AGE_DAYS` threshold for unified trace archives and diagnostic power logs from 30 days down to 14 days.
- Adjusted deep find queries using `sudo find` to reliably reach diagnostic and container targets without permission false negatives.

### Fixed

- Fixed Homebrew formula installation block for multi-level `lib/` directory structures.

## [0.3.2] - 2026-03-13

### Added

- New safety-first preflight module (`lib/preflight.sh`) with checks for free disk space, Time Machine active backup state, battery level, and SIP status
- New deep system cleanup module (`lib/system_deep.sh`) for age-gated cleanup of unified logs, power logs, memory exception reports, rotated system logs, stale installer leftovers, broken user preferences, and Safari content cache
- New orphan detection module (`lib/orphans.sh`) that automatically scans for stale app data in Application Support, Containers, and Preferences; deletion is opt-in via `--clean-orphans`
- New mail cleanup module (`lib/mail.sh`) for old Mail Downloads and shared recent-item metadata
- New DevOps reset module (`lib/devops_reset.sh`) with broad ecosystem cleanup across Docker, Node, Python, Ruby, Java, Rust, and optional model caches via `--include-ml-models`
- New CLI flags:
  - `--system-deep` / `-z`
  - `--mail` / `-m`
  - `--clean-orphans`
  - `--devops-reset`
  - `--include-ml-models`
  - `--show-log`
- New operation log viewer command path through `--show-log`
- New tests:
  - `tests/test_preflight.bats`
  - `tests/test_orphans.bats`
  - `tests/test_system_deep.bats`

### Changed

- Centralized file deletion through hardened `safe_rm` primitives in `lib/utils.sh`
- Added configurable whitelist loading (`~/.config/mac-cleanup/whitelist`) with safe defaults for sensitive/system-impacting cache paths
- Added operation log recording to `~/.mac-cleanup/operations.log`
- Dry-run accounting now tracks measured deletion candidates via `TOTAL_DRYRUN_BYTES`
- `system.sh`, `caches.sh`, `devtools.sh`, and `xcode.sh` now use centralized safe deletion flow
- Docker cleanup moved from broad prune approach to precision cleanup by explicit IDs/names
- `devtools.sh` exclusion builder no longer uses `eval`

### Fixed

- `caches::_user_logs` now deletes contents safely instead of removing the whole log directory root
- Container cleanup in caches module narrowed to cache/temp paths instead of broad container root deletion
- Added deeper and safer Xcode cleanup targets (documentation cache/index and device/core simulator logs)
- Expanded SIP-protected path list in core safeguards

### Test

- BATS suite passing: 63 tests, 0 failures
- Smoke test script passing end-to-end (`tests/smoke_test.sh`)

## [0.3.1] - 2026-03-12

### Fixed

- `xcode::_simulators` now checks `xcrun --find simctl` before calling `simctl delete unavailable`, preventing exit code 72 crashes on machines without full Xcode
- `brew::clean` cache detection uses explicit fallback when `brew --cache` returns empty or non-existent path, and logs the detected cache path and size
- `system::_trash` uses disk delta measurement after emptying Trash to capture actual freed bytes when Finder reports 0 B (e.g., Terminal lacks Full Disk Access); includes APFS `sleep 1` for space reporting accuracy

## [0.3.0] - 2026-03-12

### Added

- Browser cache cleaning (Chrome, Firefox, Edge, Arc, Brave, Opera, Vivaldi) — skips if browser is running
- Sandboxed app container cache cleaning (`~/Library/Containers/*/Data/Library/Caches`) — skips `com.apple.*` containers
- Saved Application State (`~/Library/Saved Application State`) cleaning
- Antigravity GPU/Dawn/WebGPU/code/extension cache cleaning
- Oh My Zsh cache contents cleaning (preserves directory); renamed `_zsh_completion` → `_shell_caches`
- Ruby Bundler cache, RubyGems cache, and rbenv cache cleaning in devtools module
- Cargo registry and git cache cleaning in devtools module
- pnpm store prune in devtools module (moved from system reporting-only block)
- Google Cloud SDK logs and cache cleaning in system module
- Kubernetes client cache (`~/.kube/cache`) cleaning in system module
- AWS CLI cache (`~/.aws/cli/cache`) cleaning in system module

### Removed

- pnpm reporting-only block from `system::_dev_tool_caches` (replaced by `devtools::_pnpm` with actual cleanup)

## [0.2.2] - 2026-03-12

### Fixed

- Trash detection now uses Finder/osascript for item counting and size queries — fixes false "empty" reports caused by Terminal lacking Full Disk Access to read `~/.Trash`; omits size display when Finder returns 0 (known Finder quirk)
- SIP-protected paths (`~/Library/Caches/com.apple.HomeKit`, `CloudKit`, etc.) are now excluded from deletion attempts — eliminates raw `rm:` permission errors in output
- `.DS_Store` scan depth increased from 4 to 8 levels — finds files in deeper project directories; prunes `node_modules/`, `.git/`, and `Library/Containers/`
- Added `SIP_PROTECTED_PATHS` exclusion list in `lib/core.sh` and `utils::is_deletable` guard in `lib/utils.sh`
- `dry_run_or_exec` now captures and filters stderr — permission errors logged at verbose level only

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
