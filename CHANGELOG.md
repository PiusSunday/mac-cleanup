# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.5.0] - 2026-08-21

The accuracy and safety release. Every deletion now routes through one policy, the dry-run preview
reports the number a live run actually frees, and several deletion targets that were simply wrong
have been corrected.

### Breaking

Behaviour that scripts and habits from v0.4.x may depend on:

- **A target flag now means only that target.** `mac-cleanup --docker` cleans Docker and nothing
  else. Previously the system scan and orphan pass ran on every invocation regardless of the flag,
  so any single target also swept crash reports, `.DS_Store`, npm caches and the Trash. Add
  `--system` if you were relying on that.
- **The Trash is no longer emptied** by `--system` or by `--all`. It needs `--empty-trash`, and
  `--yes` alone can never reach it.
- **`~/.pub-cache` is no longer removed under `--yes`.** It requires an interactive confirmation,
  because deleting it re-downloads every Flutter package.
- **`--devtools` no longer deletes editor workspace storage by age.** A workspace is removed only
  when its project folder no longer exists.
- **`--clean-orphans` proposes far fewer candidates.** Ownership is now established from directory
  contents, running processes and installed publishers, so live application data is no longer
  offered.
- **Reported reclaimable figures are much smaller, and that is the fix.** v0.4.3 counted the same
  bytes once per module that walked them and sized Docker images including their shared base
  layers; a machine that read "21.2 GB reclaimable" was never going to free that. The number now
  reflects what a live run actually frees, and Docker sizes are a floor rather than a ceiling.

### Fixed

#### Data loss

- **Live databases were deleted.** Apple sandboxes were matched with a `com.apple.` prefix test,
  which Apple's *group* containers do not have. That queued
  `group.com.apple.storekit/Library/Caches/storeUser.db` and its `-wal`/`-shm` sidecars; removing
  the sidecars of an open SQLite database corrupts it. Apple sandboxes are now matched under every
  prefix Apple uses, and the protection policy refuses any `*.db` / `*.sqlite*` family member that
  is open.
- **`--devtools` deleted live editor state.** Editor `workspaceStorage` directories were selected
  with `find -mtime +30` alone, which answers "not opened recently", not "no longer needed" — and
  `--devtools` runs as part of `--all` with no prompt. On the development machine that flagged 27
  workspaces whose projects still existed (862 MB, including the repository open at the time)
  against 3 genuinely dead. Each directory's `workspace.json` is now parsed and the `file://` URI
  percent-decoded; a workspace is removed only when its folder is provably gone, and anything
  undatable is kept.
- **`--clean-orphans` would have deleted a running browser's database.** Ownership was decided by
  matching directory names against installed app names, so `firestore` — Arc's local database at
  `firestore/Arc/bcny-arc-server`, 40.5 MB, growing while Arc ran — was 97% of the reported orphan
  total. Ownership is now attributed by directory contents, anything whose owning process is running
  is kept, a shared publisher counts as installed (`zoom.us` ships as `us.zoom.xos`), and entries
  must look like an application's data at all, which excludes toolchain state such as `go`,
  `pypoetry` and `virtualenv`.
- **`--clean-orphans --yes` deleted macOS system preferences.** Only `com.apple.*` domains were
  filtered, so bare-named ones (`loginwindow`, `.GlobalPreferences_m`, `corespotlightd`) were
  offered and removed without prompting.
- **Every target ran the system scan.** `system::clean` and `orphans::clean` were called above the
  target gating, so `mac-cleanup --docker` swept crash reports, `.DS_Store` and npm caches, and
  emptied the Trash. Both are now gated behind `--system`; `--docker --dry-run` went from 55 s to
  under 2 s.
- **`--dry-run` could block waiting for input** at the Flutter pub-cache prompt.

#### Accuracy

- **The preview never matched a live run.** Overlapping sweeps counted the same bytes repeatedly. A
  per-run claim ledger now counts each path once. On an identical fixture v0.4.3 previewed
  1,232,896 B and freed 1,028,096 B; this release previews and frees 512,000 B.
- **Docker sizes were inflated by shared layers.** `docker images --format '{{.Size}}'` reports each
  image's full size including shared base layers, so summing it counted every shared layer once per
  referencing image — 14.9 GB advertised against 3.56 GB actually freed. Sizes now come from
  `docker system df -v`'s `UniqueSize`, and unused is decided by Docker's own `Containers` count.
  Reproduced with three images sharing a 64 MB base: 284.4 MB reported before, 28.3 MB now,
  91.6 MB actually freed — the figure is a floor rather than a ceiling.
- **The "Found" column overstated what could be reclaimed** — a real machine read "21.2 GB found /
  848.5 MB reclaimable". pnpm reported its whole store, Xcode its whole Archives tree, and the
  user-log scan measured a SIP-protected directory it never queued.
- **The Trash never reached the decisions summary.** Finder answers `get size of trash` with the
  token `missing value`, so a size-based gate suppressed the entry entirely. It is now gated on the
  item count, with size as a best-effort upgrade.
- **The developer-artifact scan reported `0 B` on every run**, walking `$HOME` for ~30 s to find
  nothing, because the "orphaned node_modules" condition can essentially never hold.
- **Orphan detection matched almost nothing:** `tr -cd '[:alnum:]'` stripped the trailing newline,
  collapsing the installed-apps file to a single line so the exact lookup never matched.
- **Snapshot detection always claimed snapshots existed** — `tmutil` prints a header even when there
  are none.
- **`~/.gradle/caches` was deleted wholesale**, forcing a full dependency re-download. Only
  regenerated build state is removed now.
- **Empty arrays aborted the run on bash 3.2**, which is what macOS ships.
- **`du` could hang the run and over-count** — probes now use `du -skPx` and are time-boxed.
- **`--devops-reset --dry-run` did nothing at all.** The mode gated its entire body on a
  confirmation, and confirmations decline during a preview by design, so it printed
  "(no modules ran)" — the most destructive mode in the tool could only be discovered by running it
  live. It now previews without asking, and still asks before a live run.
- **`--devops-reset` reported a preview as clean.** It measured `TOTAL_FREED`, which never moves
  during a dry run, so it announced "Nothing to clean" and registered as Clean while queueing
  gigabytes. It now reports on the same basis as every other module.
- **Local snapshots were announced as clean.** macOS reports no size for a snapshot and the deletion
  runs through `tmutil` rather than `safe_rm`, so there were no bytes to attribute and the module
  reported "Nothing to clean" while listing real snapshots. It now reports the count and surfaces
  them as a decision.
- **`install.sh` printed an empty version**, reading a path that moved in the v0.4.0 refactor.

### Added

- `lib/core/protect.sh` — one deletion-protection policy for the whole tool: system paths, user data
  roots, credential stores, open SQLite families, macOS service caches, the Neural Engine compiled
  model cache, and macOS preference domains.
- `--simulators` — removes superseded Xcode simulator runtimes and the devices orphaned with them
  (23.6 GB + 9.4 GB on the development machine, previously listed as "informational").
- `--purge-stale` / `--stale-days N` — build artifacts in projects untouched for 90+ days.
- `--empty-trash` — the Trash is user data and `--yes` alone never reaches it.
- `--include-system-caches` — opt in to `~/Library/Caches/com.apple.*`, off by default because those
  are rebuilt within minutes.
- Docker lists unused but tagged images individually with the `docker rmi` command rather than
  prune-deleting them.

### Changed

- **Rewrote the summary report.** Modules ranked by reclaimable size with a proportional bar, a
  `NEEDS YOUR DECISION` block collecting everything the tool found but will not remove on its own,
  and one line per path instead of the duplicated pairs and `0 B` rows. A full `--all --dry-run`
  went from 266 lines to 223 while carrying more information.
- Live runs print the projection beside the measured free-space delta and flag a material shortfall.
- Editor cache coverage extended to VS Code Insiders, Windsurf, Zed, VSCodium and Antigravity IDE.

### Development

- A standing rule in `CONTRIBUTING.md`: every detector that can report "nothing found" ships with a
  positive fixture proving it fires. Four defects in this release were silent no-matches that each
  read as a passing result.
- 211 bats tests, up from 84. `--devops-reset`, previously the only module with no coverage at
  all, now has fixtures for every ecosystem it touches plus the model-cache opt-in.

## [v0.4.3] - 2026-03-15

### Fixed

- **CRITICAL**: Hardcoded `LC_NUMERIC=C` internally to force standard POSIX formatting across all background `printf` and `bc` calculations. This fixes a widespread terminal crash where `mac-cleanup` would throw `printf: invalid number` if a user's macOS host region (like French or German) was set to use commas instead of periods for decimals.
- **Reporting**: Added explicit instructions to the `Needs review` legend in the summary report and the warning prompt inside the `Orphans` module to clarify that users must specifically execute `mac-cleanup --clean-orphans` to delete those suspected candidates.

## [v0.4.2] - 2026-03-14

- **CLI**: Added `--version` flag.
- **Developer**: Added targeting for Android SDK caches (`~/.android`, `.downloadIntermediates`) and AVD snapshots.
- **Developer**: Added targeting for VS Code and Cursor logs, caches, and `workspaceStorage` older than 30 days.

### Changed

- **CLI**: `--verbose` flag now correctly behaves as a modifier and no longer forces the tool into unexpected prompts.
- **System**: DevTools cache sweeping (Node, Rust, Flutter) uses path deduplication to significantly reduce duplicate log output.
- **System**: Expanded the Application Support cache sweep to match case-insensitive variants of `log/logs/tmp/temp` while strictly skipping `com.apple.*` system boundaries.
- **Developer**: Reverted the Gradle age-gate to clean the entire `~/.gradle/caches` folder and expanded coverage to include `~/.gradle/daemon` logs.
- **Developer**: Downgraded logs from `warning` to `verbose` when optional tooling binaries (like Ruby, Rust, Dart) are not found.

### Fixed

- **CRITICAL**: Fixed a terminal crash where SIP/TCC permissions on `com.apple.Safari` would immediately abort the entire script inside `browsers.sh`. Safari cache cleanup was removed to comply with macOS privacy controls, and module wrapping logic was implemented to guarantee isolated failures don't halt other modules.
- **Reporting**: Rewrote the entire background calculation tracking to eliminate an APFS race condition `macOS` created when responding to `df -k`. The summary report table's `Found` and `Reclaimable` byte volumes will now mathematically sync exactly 1:1 using the new internal `TOTAL_FREED` accumulator across all 11 cleaning modules.
- **Reporting**: Dry run table output no longer marks `Clean` for everything containing `0 bytes` deleted. Output now reads `Pending` to clarify what exactly is waiting to be processed in live environments.
- **Testing**: Complete overhaul of `test_browsers.bats`, `test_caches.bats`, and `test_devtools.bats` to rely on actual local temporary file structures rather than error-prone mock function overrides. Addressed multiple bugs in the test suite isolated to `set -e` behavior and Bash 3.2 compatibility.

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
