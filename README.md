# 🧹 mac-cleanup

> A modular, safe-by-default CLI tool for macOS developers to reclaim disk storage lost to Xcode, Docker, Homebrew, developer build artifacts, and system caches. Built in pure Bash. Installable via Homebrew.

![CI](https://github.com/PiusSunday/mac-cleanup/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/github/v/release/PiusSunday/mac-cleanup)
![License](https://img.shields.io/github/license/PiusSunday/mac-cleanup)
![macOS](https://img.shields.io/badge/macOS-12%2B-blue)

---

## Why mac-cleanup?

- **Xcode alone** can silently accumulate 50–100 GB in DerivedData, Archives, and DeviceSupport folders
- **Docker Desktop** builds up image layers, stopped containers, and build cache that are never automatically cleaned
- **System Data** in macOS Storage settings balloons with Time Machine local snapshots, crash reports, and `.DS_Store` files
- **Homebrew** keeps years of cached downloads even after packages are updated or removed
- **Developer tools** (npm, pip, Go, Rust, Gradle) scatter caches and build artifacts across your home directory

mac-cleanup gives you a single, safe command to reclaim all of it.

---

## What it cleans

| Flag          | Module        | What it targets                                                     | Typical Savings |
| ------------- | ------------- | ------------------------------------------------------------------- | --------------- |
| `--system`    | System        | Crash reports, `.DS_Store`, Trash, npm/pip/Go/pnpm caches           | 1–5 GB          |
| `--xcode`     | Xcode         | DerivedData, Archives (90d+), iOS DeviceSupport, Simulators         | 10–80 GB        |
| `--docker`    | Docker        | Stopped containers, unused images, build cache                      | 5–30 GB         |
| `--devtools`  | Dev Artifacts | `node_modules` (orphaned), Rust `target/`, `__pycache__`, `.gradle` | 5–50 GB         |
| `--snapshots` | Snapshots     | Local Time Machine snapshots                                        | 5–20 GB         |
| `--caches`    | Caches        | ~/Library/Caches, ~/Library/Logs, App Support caches                | 2–10 GB         |
| `--brew`      | Homebrew      | Cached downloads, outdated versions, unused dependencies            | 1–5 GB          |

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
./bin/mac-cleanup --all          # dry-run by default — safe to run anytime
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
# Preview all cleanups — safe to run anytime (DEFAULT: dry-run)
mac-cleanup --all --dry-run

# Preview Xcode + Docker cleanup
mac-cleanup --xcode --docker

# Scan system artifacts only
mac-cleanup --system

# Find orphaned build artifacts
mac-cleanup --devtools

# Actually clean everything (will prompt for confirmation)
mac-cleanup --all --live

# Actually clean everything, skip prompts
mac-cleanup --all --live --yes

# Show help
mac-cleanup --help
```

> **Note:** mac-cleanup runs in DRY-RUN mode by default and will NOT delete anything.
> Pass `--live` to perform actual cleanup. You will be prompted for confirmation unless `--yes` is also passed.

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

  Category           Module        Scanned    Status
  ──────────────────────────────────────────────────
  System             System        1.2 GB     🗑 1.2 GB
  Developer Tools    Xcode         42.3 GB    🗑 42.3 GB
  Developer Tools    Docker        —          ⚠ Skipped
  Developer Tools    Dev Artifacts 73.6 MB    🗑 73.6 MB
  Caches & Logs      Caches        345.5 MB   🗑 345.5 MB
  Caches & Logs      Homebrew      53.2 MB    🗑 53.2 MB
  Storage Mgmt       Snapshots     —          ✔ Clean
  ──────────────────────────────────────────────────
  TOTAL                            43.8 GB    🗑 43.8 GB

  Free space:  331 GB → 374.8 GB (projected)
  Log saved:   ~/.mac-cleanup/cleanup.log
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✔ Run complete. Total freed: 43.8 GB (DRY-RUN)
```

---

## Flag Reference

| Flag           | Short | Default  | Description                                       |
| -------------- | ----- | -------- | ------------------------------------------------- |
| `--system`     | `-S`  | false    | Scan crash reports, .DS_Store, Trash, dev caches  |
| `--xcode`      | `-x`  | false    | Clean Xcode artifacts                             |
| `--docker`     | `-d`  | false    | Clean Docker resources                            |
| `--devtools`   | `-D`  | false    | Clean orphaned node_modules, Rust, Python, Gradle |
| `--snapshots`  | `-s`  | false    | Remove local Time Machine snapshots               |
| `--caches`     | `-c`  | false    | Clear user/system caches                          |
| `--brew`       | `-b`  | false    | Run Homebrew cleanup                              |
| `--all`        | `-a`  | false    | Run all of the above                              |
| `--live`       | `-L`  | false    | Perform actual cleanup (DELETE files)             |
| `--no-dry-run` |       | false    | Alias for `--live`                                |
| `--dry-run`    | `-n`  | **true** | Preview only — no deletions                       |
| `--yes`        | `-y`  | false    | Skip confirmation prompts                         |
| `--verbose`    | `-v`  | false    | Show detailed output                              |
| `--help`       | `-h`  | —        | Show help message                                 |

> **Note:** The system module always runs first regardless of which flags are selected.

---

## Safety

⚠️ **By default, mac-cleanup runs in DRY-RUN mode and will NOT delete anything.**

To perform actual cleanup, pass `--live`. A prominent warning banner will appear, and you will be prompted for confirmation unless `--yes` is also passed.

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
2. Displays execution mode (root / non-root) in the system context header
3. Path existence check before every operation
4. Confirmation prompt before any live deletion (unless `--yes`)
5. Extra safety prompt for `node_modules` directories over 500 MB

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
