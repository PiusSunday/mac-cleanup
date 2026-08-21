# 🧹 mac-cleanup

<!-- markdownlint-disable MD060 -->

> A modular, safe-by-default CLI tool for macOS developers to reclaim disk storage lost to Xcode, Docker, Homebrew, developer build artifacts, and system caches. Built in pure Bash. Installable via Homebrew.

![CI](https://github.com/PiusSunday/mac-cleanup/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/github/v/release/PiusSunday/mac-cleanup)
![License](https://img.shields.io/github/license/PiusSunday/mac-cleanup)
![macOS](https://img.shields.io/badge/macOS-12%2B-blue)

---

## Why mac-cleanup?

Macs aren't designed to naturally tidy up after developers. Whether you're building apps, managing containers, or experimenting with new environments, your local storage silently shoulders the burden of massive hidden dependencies.

- **Xcode Environments**: DerivedData, old project Archives, and iOS DeviceSupport files can quietly swell to consume over 50-100 GB in forgotten storage.
- **Container Ecosystems**: Docker Desktop frequently orphans dangling images, ghost containers, and multi-gigabyte build caching layers over time without auto-pruning.
- **Toolchain Leftovers**: Every runtime from Node (`node_modules`) and Python (`__pycache__`) to Gradle and Rust (`target/`) leaves behind hundreds of stale cache fragments scattered across your home directory.
- **Deceptive System Data**: The ambiguous "System Data" block in macOS Storage settings often hides gigabytes of abandoned Time Machine local snapshots, browser frameworks lacking clean deletion patterns, and old `.pkg` payloads.

**mac-cleanup** stops you from running dozens of frantic `rm -rf` commands and obscure terminal invocations. It replaces chaos with a single, safe, open-source command engineered meticulously through a Domain-Driven architecture to isolate exactly what is stale, age-gated, and safe to delete—empowering you to seamlessly recover your Mac's performance.

---

## What it cleans

| Flag             | Module        | What it targets                                                                                                                | Typical Savings |
| ---------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| `--system`       | System        | Crash reports, `.DS_Store`, Trash, Dev caches (npm, pip)                                                                       | 1–5 GB          |
| `--system-deep`  | Deep System   | Age-gated unified logs (14d), diagnostic logs, MacOS Installer payloads (14d), Safari content cache, `com.apple.nsurlsessiond` | 1–12 GB         |
| `--clean-orphans`| Orphans       | Deletes suspected orphaned App containers and plists using per-item confirmation. Defaults to report-only (`Needs review`) without this flag.  | 1–10 GB         |
| `--xcode`        | Xcode         | DerivedData, Archives (90d+), iOS DeviceSupport, Simulators, CoreSimulator logs                                                | 10–90 GB        |
| `--simulators`   | Xcode         | Superseded simulator runtimes (keeps the newest per platform) and unavailable simulator devices                                | 8–40 GB         |
| `--docker`       | Docker        | Precision cleanup of stopped containers, dangling images, dangling volumes, build cache                                        | 5–30 GB         |
| `--devtools`     | Dev Artifacts | Rust `target/`, Python `__pycache__`, Flutter, Gradle, Ruby, editor caches; reports stale project artifacts | 5–60 GB         |
| `--purge-stale`  | Dev Artifacts | `node_modules`, `target`, `build`, `dist`, `.next`, `.dart_tool` in projects untouched 90+ days | 1–50 GB         |
| `--snapshots`    | Snapshots     | Local Time Machine snapshots & stale `.inProgress` backups                                                                     | 5–20 GB         |
| `--caches`       | Caches        | ~/Library/Caches, Application Support caches/logs, Saved App State, Zsh, JetBrains                                             | 2–15 GB         |
| `--mail`         | Mail          | Old Mail Downloads attachments and recent-item metadata                                                                        | 0.5–10 GB       |
| `--brew`         | Homebrew      | Cached downloads, outdated versions, unused dependencies                                                                       | 1–5 GB          |
| `--devops-reset` | DevOps Reset  | Cross-ecosystem deep cleanup for Docker and language toolchains; optional model caches with `--include-ml-models`              | 10–120+ GB      |
| `--optimize`     | Optimization  | DNS flush (`dscacheutil`), LaunchServices rebuild, SQLite VACUUM for Safari/Messages, Font cache clear                         | N/A             |

### System Data clues

The `--system` module also surfaces paths that contribute to the "System Data" bar in macOS Storage settings — but **never deletes them**. These include the Rosetta translation cache and legacy iOS firmware files. Each finding includes the path and a suggestion for how to investigate.

Simulator runtimes are no longer only reported: `--simulators` removes the ones macOS has superseded, keeping the newest runtime for every platform.

---

## Supported macOS Versions

macOS 12 Monterey and later (Apple Silicon + Intel).

---

## Installation

### Homebrew (recommended)

```bash
brew tap PiusSunday/mac-cleanup
brew install mac-cleanup
```

### One-line installer

```bash
curl -fsSL https://raw.githubusercontent.com/PiusSunday/mac-cleanup/main/install.sh | bash
```

### Run from source (local clone)

If you prefer to clone the repository and run directly — no installation required:

```bash
git clone https://github.com/PiusSunday/mac-cleanup.git
cd mac-cleanup
chmod +x bin/mac-cleanup
./bin/mac-cleanup          # Runs safe --all --dry-run by default
```

Optionally, symlink it so you can run `mac-cleanup` from anywhere:

```bash
ln -sf "$(pwd)/bin/mac-cleanup" /usr/local/bin/mac-cleanup
```

> **Note:** If `/usr/local/bin` is not writable, use `~/.local/bin` instead and ensure it is on your `PATH`.

### Running the tests

```bash
# Quick smoke test
chmod +x tests/smoke_test.sh
bash tests/smoke_test.sh

# Full unit test suite (requires bats-core: brew install bats-core)
bats tests/
```

---

## Usage

```bash
# Preview all cleanups — safe to run anytime (Implies --all --dry-run)
mac-cleanup

# Preview specific targets
mac-cleanup --all --dry-run
mac-cleanup --xcode --docker --dry-run

# Interactive live cleanup (asks for confirmation)
mac-cleanup --all

# Actually clean everything, skip prompts (live mode)
mac-cleanup --all --yes

# Show help
mac-cleanup --help

# Deep system cleanup only
mac-cleanup --system-deep --yes

# Detect orphaned app data and remove confirmed candidates
mac-cleanup --all --clean-orphans --yes

# Show operation log
mac-cleanup --show-log

# Show current version
mac-cleanup --version
```

> **Note:** If you run `mac-cleanup` with **no cleanup targets** selected, it defaults to a safe `--all --dry-run` preview.
> Modifier-only flags like `--verbose` and `--clean-orphans` keep that safe preview behavior. If you specify cleanup targets (like `--all` or `--system`) _without_ passing `--dry-run`, it enters **Interactive Mode** and will prompt you for confirmation before deleting any files. Pass `--yes` to skip the prompt.

### Expected output

```text
🧹 mac-cleanup v0.5.0
⚠  DRY-RUN mode — no files will be deleted

  Apple Silicon  |  macOS 26.5  |  Free: 203.4 GB  |  User mode

▶ System
━━━ System Scan ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ Crash reports: 1 file (356 KB)
ℹ .DS_Store: 3 of 9 files (32 KB) — 6 skipped (protected or unwritable)
ℹ Trash: 41 items — left alone
       21.6 MB  npm cache
       36.0 MB  npm npx cache
✔   System → 58.0 MB reclaimable

━━━ Deep System Cleanup ━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ Private tmp: 204 files (2.7 MB)
✔   Deep System → 2.7 MB reclaimable

▶ Developer Tools
━━━ Xcode ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ   Superseded runtime: iphonesimulator 26.4 (7.9 GB)
⚠   3 superseded runtime(s) found — not removed without --simulators.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🧹 mac-cleanup v0.5.0  ·  dry run  ·  1m 36s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  MODULE                  RECLAIMABLE   ITEMS
  Dev Artifacts               67.1 MB       7  ██████████████████████████
  System                      58.0 MB       6  ██████████████████████
  Homebrew                    36.8 MB       1  ██████████████
  Caches                      12.7 MB      31  ████
  Browsers                     5.6 MB       1  ██
  Deep System                  2.7 MB     204  █
  Xcode                        964 KB       2  ▏
  ──────────────────────────────────────────────────────────────────────────
  Total                      183.4 MB     252

  Already clean   Orphans, Docker, Apps & Containers, Mail, Snapshots
  Skipped         6 paths protected by policy, 4 counted by another module

  NEEDS YOUR DECISION
     23.6 GB   3 superseded Xcode simulator runtimes + the devices bound to them
               mac-cleanup --simulators
    574.5 MB   Flutter pub cache (every package re-downloads on next build)
               mac-cleanup --devtools  (asks before removing)
    128.6 MB   5 build artifacts in projects untouched for 90+ days
               mac-cleanup --purge-stale
    size n/a   41 items in the Trash
               mac-cleanup --empty-trash

  Disk            203.4 GB free  →  203.6 GB after cleanup
  Log             ~/.mac-cleanup/cleanup.log

  This was a preview. Re-run without --dry-run to reclaim 183.4 MB.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Modules are ranked by what they can reclaim, largest first, so the biggest win is
always the top row. `ITEMS` is how many paths the module queued — a module that
cleans through its own CLI, like Homebrew, shows `—` rather than a misleading `0`.

Sizes are floors, not ceilings. Docker images are measured by their *unique* size — the space that
actually comes back — because an image's headline size includes base layers shared with images you
keep. Summing those headline sizes is what made an earlier version advertise 14.9 GB against
3.56 GB actually freed.

**NEEDS YOUR DECISION** is the part worth reading. It collects everything the tool
found but will not remove on its own, each with the command that would remove it.
On the machine above that is over 24 GB against 183 MB of automatic cleanup, and
none of it is touched without an explicit flag. `size n/a` means the size could
not be measured — macOS will not report the size of the Trash — not that the
entry is empty.

Every path that will be deleted is printed. Bulk age-gated sweeps (rotated logs,
`.DS_Store`, temp files) are rolled up into one line by default; `--verbose` lists
each one individually. Nothing is ever truncated.

---

## Flag Reference

| Flag                  | Short | Default | Description                                                                                     |
| --------------------- | ----- | ------- | ----------------------------------------------------------------------------------------------- |
| `--system`            | `-S`  | false   | Scan crash reports, .DS_Store, Trash, and common dev caches                                     |
| `--system-deep`       | `-z`  | false   | Deep age-gated system cleanup for diagnostic logs and stale installer artifacts                 |
| `--xcode`             | `-x`  | false   | Clean Xcode artifacts                                                                           |
| `--docker`            | `-d`  | false   | Clean Docker resources by explicit IDs/names                                                    |
| `--devtools`          | `-D`  | false   | Clean node_modules, Rust, Cargo, Python, Gradle, Ruby, pnpm, Bun/tnpm, Flutter                  |
| `--mail`              | `-m`  | false   | Clean old Mail Downloads and recent-item metadata                                               |
| `--snapshots`         | `-s`  | false   | Remove local Time Machine snapshots                                                             |
| `--caches`            | `-c`  | false   | Clear user caches/logs, browser caches, container caches, Saved App State, media and IDE caches |
| `--brew`              | `-b`  | false   | Run Homebrew cleanup                                                                            |
| `--optimize`          | `-O`  | false   | Run non-destructive system tuning operations (DNS flush, LS rebuild, SQLite VACUUM)             |
| `--all`               | `-a`  | false   | Run all cleanup targets                                                                         |
| `--clean-orphans`     | —     | false   | Delete orphan candidates after per-item confirmation                                            |
| `--devops-reset`      | —     | false   | Run nuclear cleanup mode across Docker and developer ecosystems                                 |
| `--include-ml-models` | —     | false   | Include `.cache/huggingface` and `.ollama/models` in DevOps reset                               |
| `--simulators`        | —     | false   | Delete superseded Xcode simulator runtimes and prune unavailable devices                        |
| `--include-system-caches` | — | false   | Also purge `~/Library/Caches/com.apple.*` (rebuilt by macOS; off by default)                    |
| `--purge-stale`       | —     | false   | Delete build artifacts in projects untouched for 90+ days                                        |
| `--empty-trash`       | —     | false   | Empty the Trash — user data; `--yes` alone never reaches it                                      |
| `--stale-days`        | —     | 90      | Days of inactivity before a project's build artifacts count as stale                             |
| `--show-log`          | —     | false   | Print operation log from `~/.mac-cleanup/operations.log` and exit                               |
| `--version`           | `-V`  | false   | Print the current mac-cleanup version and exit                                                  |
| `--dry-run`           | `-n`  | —       | Preview only — no deletions (implicitly true when run without any target flags)                 |
| `--yes`               | `-y`  | false   | Skip confirmation and run live cleanup                                                          |
| `--verbose`           | `-v`  | false   | Show detailed output                                                                            |
| `--help`              | `-h`  | —       | Show help message                                                                               |

> **Note:** The system scan and orphan detection pass run first to surface high-risk data and stale artifacts early.

---

## Safety

⚠️ **Interactive by Default**
If you pass targets (e.g. `--all`) to mac-cleanup, it will **prompt you for confirmation** before doing any live deletion.
If you run `mac-cleanup` entirely without flags, it defaults to a safe `--all --dry-run` preview.

To skip prompts and force live cleanup, pass `--yes`.

### What it will NEVER touch

Every deletion in every module is routed through one policy in `lib/core/protect.sh`, so a path
cannot be protected by one module and removed by another.

```bash
# System
/System/*  /usr/*  /bin/*  /sbin/*  /private/etc/*  /private/var/db/*  /Library/Apple/*

# User data roots (the directories themselves — their contents stay eligible)
~/Documents  ~/Desktop  ~/Pictures  ~/Movies  ~/Music  ~/Downloads  ~/Library

# Credentials and keys
~/.ssh/*  ~/.gnupg/*  ~/.aws/*  ~/.netrc  ~/.config/gh/*  ~/Library/Keychains/*
*.pem  *.p12  id_rsa*  id_ed25519*  *credential*

# Live databases
*.db / *.sqlite / *.sqlite3 and their -wal / -shm / -journal sidecars,
whenever any member of the family is open

# macOS service caches (opt in with --include-system-caches)
~/Library/Caches/com.apple.*  ~/Library/Caches/GeoServices  ~/Library/Caches/CloudKit

# Never released, even with --include-system-caches
~/Library/Caches/com.apple.e5rt.e5bundlecache   (Neural Engine compiled models)

# macOS preference domains, including the ones with no com.apple. prefix
loginwindow  .GlobalPreferences  corespotlightd  sharedfilelistd  ...
```

### The preview matches the live run

Modules overlap on purpose — the user-cache sweep, the editor-cache sweep and the container
sweep all reach some of the same directories. A per-run claim ledger accounts for each path
exactly once, so `--dry-run` reports the number a live run actually frees rather than a total
inflated by every module that walked the same bytes.

### Recoverable user data needs its own flag

`--yes` means "do not ask me about cleanup", not "destroy recoverable data". Two things are
therefore never reachable through it:

- **The Trash** needs `--empty-trash`. Files there were deleted but not committed to being lost —
  macOS keeps them recoverable on purpose. `--empty-trash` prompts on its own; passing `--yes`
  alongside it skips the prompt, since two explicit flags is already a deliberate act and requiring
  an unanswerable prompt would make the flag unusable non-interactively. `--yes` by itself can
  never reach the Trash.
- **`~/.pub-cache`** is skipped under `--yes`; removing it re-downloads every Flutter package, so
  it only happens on an interactive confirmation.

Both are reported as decisions instead, with the command that would act on them. macOS will not
report the size of the Trash — Finder answers `get size of trash` with `missing value` — so the
decision names the item count and shows `size n/a` rather than dropping the entry.

### Targets mean what they say

`mac-cleanup --docker` cleans Docker. Until v0.5.0 the system scan and orphan pass ran above the
target gating, so any target also swept crash reports, `.DS_Store`, npm caches and emptied the
Trash.

### Value over vanity

A cache macOS rebuilds within minutes is not reclaimed space. Service caches are protected by
default and the summary reports how many paths were skipped and why, instead of counting them
toward a larger headline number.

### System Data clues — informational only

The system module reports paths contributing to macOS "System Data" (Rosetta cache, legacy
firmware) but **never modifies or deletes** them, regardless of flags. Docker's unused-but-tagged
images are listed the same way — individually, with the `docker rmi` command — because a tagged
image is something you pulled or built on purpose.

### Validation before any cleanup

1. macOS detection (`uname -s` must return `Darwin`)
2. Whitelist loading from `~/.config/mac-cleanup/whitelist` with safe defaults for sensitive paths
3. Live-mode preflight checks: disk space, Time Machine activity, battery state, and SIP status
4. Displays execution mode (root / non-root) in the system context header
5. Path validation and deletion routing through centralized `safe_rm`
6. Confirmation prompt before any live deletion (unless `--yes`)
7. Extra safety prompt for `node_modules` directories over 500 MB
8. `--dry-run` never prompts and never blocks on input — a preview declines every optional deletion

### Operation logging

- Every delete, skip, and dry-run command record is written to `~/.mac-cleanup/operations.log`
- View the log anytime with:

```bash
mac-cleanup --show-log
```

---

## Uninstall

### Homebrew

```bash
brew uninstall mac-cleanup
brew untap PiusSunday/mac-cleanup
```

### Manual

```bash
rm -rf ~/.mac-cleanup
rm -f /usr/local/bin/mac-cleanup
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding new modules, running tests, and submitting pull requests.

---

## License

MIT — see [LICENSE](LICENSE).
