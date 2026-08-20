# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.5.2] - 2026-08-20

Three data-loss defects. v0.5.1 made the report trustworthy; these made the deletion targets
wrong, which is the more dangerous half.

### Fixed

- **CRITICAL — `--devtools` deleted live editor state.** Editor workspaceStorage directories were
  selected with `find -mtime +30` alone, which answers "not opened recently", not "no longer
  needed". `--devtools` runs as part of `--all` with no opt-in and no prompt. On the development
  machine the rule flagged 27 workspaces whose project folders still existed — 862 MB, including
  the workspace for the repository open at the time — against 3 that were genuinely dead. Each
  directory now has its `workspace.json` parsed, the `file://` URI percent-decoded, and is removed
  only if the project folder is provably gone. Anything undatable — no json, unparseable, or a
  remote URI — is kept, and mtime survives only as an additional gate.
- **CRITICAL — `--clean-orphans` would have deleted a running browser's database.** Ownership was
  decided by matching directory names against installed app names, so any directory whose name did
  not look like an app was fair game. `firestore` is Arc's local database
  (`firestore/Arc/bcny-arc-server`) at 40.5 MB — 97% of the reported orphan total — and it was
  growing while Arc ran. Ownership is now attributed by directory *contents*, anything whose owning
  process is running is kept, a shared publisher counts as installed (`zoom.us` ships as
  `us.zoom.xos`, so `us.zoom.updater` is covered), and entries must look like an application's data
  at all, which excludes toolchain state such as `go`, `pypoetry`, `virtualenv` and `iCloud`. The
  reported total on this machine drops from 41.5 MB to nothing — all of it was false positives —
  while a synthetic `com.deadvendor.DeadApp` fixture confirms genuine orphans are still found.
- **CRITICAL — every target ran the system scan.** `system::clean` and `orphans::clean` were called
  above the target gating, so `mac-cleanup --docker` swept crash reports, `.DS_Store` and npm
  caches, and emptied the Trash. Both are now gated behind `--system`. `--docker --dry-run` went
  from 55 s to 2 s as a side effect.

### Changed

- **The Trash needs `--empty-trash`**, and confirms even with the flag. It holds files the user
  chose to delete but has not committed to losing; `--yes` means "do not ask me about cleanup", not
  "destroy recoverable user data". Reported as a decision otherwise.
- **`~/.pub-cache` is skipped under `--yes`** for the same reason — removing it re-downloads every
  Flutter package, so it requires an interactive confirmation.

## [v0.5.1] - 2026-08-20

Accuracy follow-up. A real cleanup run against the v0.5.0 report showed its Docker figures were
inflated roughly 4×, and that the tool was leaving a third of the simulator win on the table.

### Fixed

- **CRITICAL — Docker sizes were inflated by shared layers.** The report advertised 14.9 GB of
  unused images; deleting all 17 reclaimed 3.56 GB. `docker images --format '{{.Size}}'` reports
  each image's *full* size including shared base layers, so summing it counts every shared layer
  once per image that references it — with a Supabase stack sharing Postgres and Debian bases, a
  dozen times over. `docker system df`'s own `Reclaimable` column has the same basis, so the
  "honest Docker numbers" change in v0.5.0 did not fix this.

  Sizes now come from `docker system df -v`'s `UniqueSize`, which excludes layers shared with
  images you keep, and images are classified unused via Docker's own `Containers` reference count
  rather than by matching container ancestry — which also fixes images being called unused because
  a running container referenced them under a different tag. Reproduced end to end with three
  throwaway images sharing a 64 MB base: the old code reported 284.4 MB, the new code reports
  28.3 MB, and `docker rmi` actually freed 91.6 MB. The figure is now a floor rather than a ceiling,
  and is labelled "frees at least".
- **Simulator devices orphaned by runtime deletion were never reclaimed.** Removing a superseded
  runtime orphans every device bound to it — 22 devices and ~9.4 GB on the development machine,
  more than a third of the total simulator win. `simctl delete unavailable` ran once before any
  runtime was deleted and again immediately after; since deletion is asynchronous, neither call
  ever found an orphaned device. Device pruning now has a single owner, waits (bounded) for the
  runtimes to finish unmounting, measures what it reclaimed, and the report advertises runtimes and
  their dependent devices as one combined figure.
- **The developer-artifact scan reported `0 B` on every run.** It looked for `node_modules` with no
  nearby `package.json`, a condition that essentially never holds, so it walked `$HOME` for ~30 s
  and found nothing. Replaced with staleness: build artifacts (`node_modules`, `target`, `build`,
  `dist`, `.next`, `.nuxt`, `.dart_tool`, `.gradle`) in projects untouched for 90+ days, anchored on
  the nearest real project root so a Flutter app's `android/.gradle` is dated by its `pubspec.yaml`
  rather than reported as untouched since the epoch. Anything that cannot be dated is skipped rather
  than guessed at. Deletion is opt-in behind `--purge-stale`; `--stale-days N` tunes the threshold.
- **`install.sh` printed an empty version** — it read `lib/core.sh`, a path that moved to
  `lib/core/core.sh` in the v0.4.0 refactor.

### Added

- `--purge-stale` and `--stale-days N` for dormant-project build artifacts.
- Live runs now print the projection alongside the measured free-space delta and flag a material
  shortfall, so an estimate that drifts is visible rather than silent — which is how the Docker
  over-reporting went unnoticed in the first place.
- 19 tests covering image-size accounting, device orphaning, the bounded runtime wait, project-root
  anchoring, and the projection-drift warning.

## [v0.5.0] - 2026-08-20

A correctness and safety release. Every deletion now routes through a single policy, the dry-run
preview reports the number a live run actually frees, and the largest reclaimable artifact on a
developer Mac — superseded Xcode simulator runtimes — is finally handled instead of just mentioned.

### Fixed

- **CRITICAL — live databases were deleted.** `apps.sh` skipped Apple sandboxes by testing for a
  `com.apple.` prefix, which Apple's *group* containers do not have. On a normal machine that put
  `group.com.apple.storekit/Library/Caches/storeUser.db` and its `-wal`/`-shm` sidecars into the
  delete queue; removing the sidecars of an open SQLite database corrupts it. Apple sandboxes are
  now matched under every prefix Apple uses, and the protection policy refuses any `*.db` /
  `*.sqlite*` family member that is open (verified via a live `-shm` or `lsof`).
- **CRITICAL — `--clean-orphans --yes` deleted macOS system preferences.** The orphan scanner
  filtered only `com.apple.*` domains, so bare-named ones (`loginwindow`, `.GlobalPreferences_m`,
  `corespotlightd`, `sharedfilelistd`, `icdd`) were offered as orphan candidates and removed
  without prompting under `--yes`.
- **CRITICAL — installed apps' extensions were reported as orphans.** Identifiers such as
  `net.whatsapp.WhatsApp.ServiceExtension` extend an installed bundle id, but the matcher only
  looked for an exact normalized line. Matching now walks the identifier from the outside in, so a
  match on any ancestor counts as installed.
- **`--dry-run` could block waiting for input.** The Flutter pub-cache prompt called
  `utils::confirm` during a preview. `utils::confirm` now declines without prompting in dry-run,
  and declines instead of hanging in a non-interactive shell.
- **The preview never matched a live run.** The user-cache sweep, the browser sweep, the Spotify
  and Apple-media sweeps and the container sweep all walked overlapping paths, and every pass added
  the same bytes again. `~/Library/Caches` now has exactly one owner, and a per-run claim ledger
  guarantees each path is counted once. Measured on an identical fixture: v0.4.3 previewed
  1,232,896 B and freed 1,028,096 B; v0.5.0 previews and frees 512,000 B.
- **The "Found" column overstated what could be reclaimed.** On a real machine v0.4.3 reported
  "21.2 GB found / 848.5 MB reclaimable". Docker summed the *Size* column of `docker system df`
  (every running container's image and every mounted volume); pnpm reported the whole store rather
  than what `pnpm store prune` drops; Xcode reported the whole Archives tree while removing only
  archives older than 90 days; the user-logs scan measured a SIP-protected directory it never
  queued. Each now reports only what it will actually remove.
- **Snapshots always claimed snapshots existed.** `tmutil listlocalsnapshots /` prints a header
  even when there are none, and the emptiness test matched that header. Only real
  `com.apple.TimeMachine.*` identifiers are counted now.
- **`~/.gradle/caches` was deleted wholesale**, forcing a full re-download of every dependency.
  Only regenerated build state (`build-cache-*`, `transforms-*`, `journal-*`, `jars-*`) is removed;
  `modules-2` is kept and its retained size is reported.
- **`install.sh` printed an empty version.** It read the version from `lib/core.sh`, a path that
  moved to `lib/core/core.sh` in the v0.4.0 refactor, so every script install since then has
  reported `mac-cleanup v installed successfully!`.
- **Empty arrays aborted the run on bash 3.2.** macOS ships bash 3.2, where `"${arr[@]}"` on an
  empty array is an unbound variable under `set -u`. Guarded the arrays that can be empty.
- **`du` could hang the run and over-count.** Size probes now use `du -skPx` — never following
  symlinks, never crossing into a mounted volume or network share — and are time-boxed.
- **Orphan detection matched almost nothing.** `orphans::_normalize_name` piped through
  `tr -cd '[:alnum:]'`, which strips the trailing newline along with the punctuation, so every
  name was appended to the installed-apps file without one and the whole file collapsed to a
  single concatenated line. `sort -u` had nothing to dedupe and the exact `grep -Fxq` lookup
  could never match, leaving detection to a loose substring search. Fixing it cut the false
  positives on the development machine from 32 candidates to 18.
- **`utils::format_bytes` no longer forks `bc`** or parses floats, removing the last locale-sensitive
  arithmetic; it also gained TB support and returns `0 B` for malformed input.

### Added

- `lib/core/protect.sh` — one deletion-protection policy for the whole tool: system paths, user
  data roots, credential stores, open SQLite families, macOS service caches, the Neural Engine
  compiled-model cache, and macOS preference domains.
- `--simulators` — deletes superseded Xcode simulator runtimes (keeping the newest per platform)
  and prunes unavailable simulator devices. Runtimes macOS has marked unusable are always removed;
  superseded ones ask per runtime. On the development machine this surfaced 23.6 GB that v0.4.3
  listed as "informational — never auto-deleted".
- `--include-system-caches` — opt in to purging `~/Library/Caches/com.apple.*`, off by default
  because those caches are rebuilt by background daemons within minutes.
- Docker now lists unused but *tagged* images individually, with size, ID and the `docker rmi`
  command, instead of either ignoring them or prune-deleting them.
- The summary report shows how many paths were skipped by policy and how many were already counted
  by another module.
- `tests/test_protect.bats` — 23 cases covering the policy and the ledger, including a test that
  asserts the dry-run and live totals are equal.

### Changed

- **Rewrote the summary report.** Modules are ranked by what they can reclaim with a
  proportional bar, so the biggest win is the top row. The duplicated `Found` column is gone
  now that Found and Reclaimable are always equal. Modules with nothing to do are named on one
  line instead of taking a table row each, and an `ITEMS` column reports how many paths were
  actually queued (`—` for modules that clean through their own CLI).
- **Added a "needs your decision" block.** Everything the tool found but will not remove on its
  own — superseded simulator runtimes, unused Docker images, orphan candidates — is collected
  with its size and the exact command that would remove it. On the development machine that is
  38.5 GB, against 1.3 GB of automatic cleanup; previously it was scattered through the log or
  invisible.
- **Halved the run log without hiding anything.** Modules used to print a `→ size path` line and
  then safe_rm printed a second `[DRY-RUN] size label` line for the same path, padded with 0 B
  entries. There is now one line per path, and age-gated bulk sweeps (rotated logs, `.DS_Store`,
  temp files) roll up into a single line — `--verbose` still lists every path, and nothing is
  truncated in either mode. A full `--all --dry-run` went from 266 lines to 223 while carrying
  more information.
- Editor cache coverage extended to VS Code Insiders, Windsurf, Zed, VSCodium and Antigravity IDE.
- The running-app check no longer greps the whole `launchctl list` output for a substring (which
  matched almost anything); it resolves known cache-directory owners, tries the bundle id's leaf
  component, and matches launchd labels exactly.
- Orphan detection also reads `/System/Applications` and `/Applications/Setapp`.
- A full `--all --dry-run` on the development machine went from 154 s to 117 s.

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
