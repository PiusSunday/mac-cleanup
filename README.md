# 🧹 mac-cleanup

<!-- markdownlint-disable MD060 -->

> A modular, safe-by-default CLI tool for macOS developers to reclaim disk storage lost to Xcode, Docker, Homebrew, developer build artifacts, and system caches. Built in pure Bash. Installable via Homebrew.

![CI](https://github.com/PiusSunday/mac-cleanup/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/github/v/release/PiusSunday/mac-cleanup)
![License](https://img.shields.io/github/license/PiusSunday/mac-cleanup)
![macOS](https://img.shields.io/badge/macOS-12%2B-blue)

---

## Why mac-cleanup?

- **Xcode alone** can silently accumulate 50–100 GB in DerivedData, Archives, and DeviceSupport folders
- **Docker Desktop** builds up image layers, stopped containers, and build cache that are never automatically cleaned
- **System Data** in macOS Storage settings balloons with Time Machine local snapshots, crash reports, and old installer payloads
- **Browser Frameworks** (Chrome, Edge) leave Gigabytes of abandoned framework versions hiding in your Application Support
- **Homebrew** keeps years of cached downloads even after packages are updated or removed
- **Developer tools** (npm, pip, Go, Rust, Gradle) scatter caches and build artifacts across your home directory

mac-cleanup gives you a single, safe command to reclaim all of it, beautifully organized into a Domain-Driven architecture.

---

## What it cleans

| Flag             | Module        | What it targets                                                                                                                | Typical Savings |
| ---------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| `--system`       | System        | Crash reports, `.DS_Store`, Trash, Dev caches (npm, pip)                                                                       | 1–5 GB          |
| `--system-deep`  | Deep System   | Age-gated unified logs (14d), diagnostic logs, MacOS Installer payloads (14d), Safari content cache, `com.apple.nsurlsessiond` | 1–12 GB         |
| `--xcode`        | Xcode         | DerivedData, Archives (90d+), iOS DeviceSupport, Simulators, CoreSimulator logs                                                | 10–90 GB        |
| `--docker`       | Docker        | Precision cleanup of stopped containers, dangling images, dangling volumes, build cache                                        | 5–30 GB         |
| `--devtools`     | Dev Artifacts | `node_modules` (orphaned), Rust `target/`, Python `__pycache__`, Flutter, Gradle, Ruby caches                                  | 5–60 GB         |
| `--snapshots`    | Snapshots     | Local Time Machine snapshots & stale `.inProgress` backups                                                                     | 5–20 GB         |
| `--caches`       | Caches        | ~/Library/Caches, sandboxed app containers (safe skip of `com.apple.*`), Zsh, Spotify, JetBrains                               | 2–15 GB         |
| `--mail`         | Mail          | Old Mail Downloads attachments and recent-item metadata                                                                        | 0.5–10 GB       |
| `--brew`         | Homebrew      | Cached downloads, outdated versions, unused dependencies                                                                       | 1–5 GB          |
| `--devops-reset` | DevOps Reset  | Cross-ecosystem deep cleanup for Docker and language toolchains; optional model caches with `--include-ml-models`              | 10–120+ GB      |
| `--optimize`     | Optimization  | DNS flush (`dscacheutil`), LaunchServices rebuild, SQLite VACUUM for Safari/Messages, Font cache clear                         | N/A             |

### System Data clues

The `--system` module also surfaces paths that contribute to the "System Data" bar in macOS Storage settings — but **never deletes them**. These include Simulator devices, Rosetta translation cache, Xcode runtime volumes, and legacy iOS firmware files. Each finding includes the path and a suggestion for how to investigate.

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
```

> **Note:** If you run `mac-cleanup` with **no flags**, it defaults to a safe `--all --dry-run` preview.
> If you specify target flags (like `--all` or `--system`) _without_ passing `--dry-run`, it enters **Interactive Mode** and will prompt you for confirmation before deleting any files. Pass `--yes` to skip the prompt.

### Expected output

```yaml
🧹 mac-cleanup vX.Y.Z
⚠  DRY-RUN mode — no files will be deleted

  Apple Silicon  |  macOS XX.X  |  Free: 331 GB  |  User mode

▶ System
━━━ System Scan ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ Crash reports: 3 files (412 KB)
ℹ .DS_Store: 47 files (188 KB)
ℹ Trash: 1.2 GB
...
✔   System → 1.2 GB reclaimable

▶ Developer Tools
━━━ Xcode ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ DerivedData: 42.3 GB
...
✔   Xcode → 42.3 GB reclaimable

━━━ Docker ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ Docker daemon is not running. Skipping.

▶ Caches & Logs
━━━ Caches ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🧹 mac-cleanup — Summary Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Mode: DRY-RUN  |  Duration: 3s

  Category           Module                Found   Reclaimable   Status
  ─────────────────────────────────────────────────────────────────────────────
  System             System               1.2 GB        1.2 GB   Clean
                     Deep System               -             -   Clean
                     Orphans                   -             -   Clean
  Developer Tools    Xcode                42.3 GB       42.3 GB   Clean
                     Docker                    -             -   Skipped
                     Dev Artifacts         73.6 MB       73.6 MB   Clean
  Caches & Logs      Caches              345.5 MB      345.5 MB   Clean
                     Homebrew             53.2 MB       53.2 MB   Clean
  Storage Management Snapshots                 -             -   Clean
  ─────────────────────────────────────────────────────────────────────────────
  TOTALS                                   43.8 GB       43.8 GB

  Free space:  331 GB → 374.8 GB (projected)
  Log saved:   ~/.mac-cleanup/cleanup.log

  Status legend:
  - Needs review: found items are excluded from projected reclaimable bytes.
  - Clean: module will be cleaned automatically in a real run.
  - Skipped: prerequisite unavailable.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✔ Run complete.
```

`Found` is what each module detected. `Reclaimable` is what the current run would remove, or project to remove in dry-run mode. `Status` explains whether the module will run automatically, is waiting on user action, or was skipped.

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
| `--show-log`          | —     | false   | Print operation log from `~/.mac-cleanup/operations.log` and exit                               |
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

```bash
/System/*
/usr/*
/bin/*
/sbin/*
/private/etc/*
~/Library/Application Support/MobileSync/Backup/*   (iPhone backups)
~/Library/Keychains/*
```

### System Data clues — informational only

The system module reports paths contributing to macOS "System Data" (Simulator devices, Rosetta cache, runtime volumes) but **never modifies or deletes** them, regardless of flags.

### Validation before any cleanup

1. macOS detection (`uname -s` must return `Darwin`)
2. Whitelist loading from `~/.config/mac-cleanup/whitelist` with safe defaults for sensitive paths
3. Live-mode preflight checks: disk space, Time Machine activity, battery state, and SIP status
4. Displays execution mode (root / non-root) in the system context header
5. Path validation and deletion routing through centralized `safe_rm`
6. Confirmation prompt before any live deletion (unless `--yes`)
7. Extra safety prompt for `node_modules` directories over 500 MB

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
