# Contributing to mac-cleanup

Thank you for your interest in contributing! This project welcomes bug reports, feature requests, and pull requests.

## Branching Model

```text
main       ← stable releases only (protected)
  └── develop   ← integration branch (PRs go here)
        ├── feature/your-feature
        └── fix/your-bugfix
```

- **`main`** is the release branch — only merged from `develop` when stable
- **`develop`** is the integration branch — all contributions target this branch
- Create feature/fix branches off `develop`, open PRs back to `develop`

## Development Setup

```bash
# Fork the repo on GitHub, then clone your fork
git clone https://github.com/<your-username>/mac-cleanup.git
cd mac-cleanup

# Add upstream remote
git remote add upstream https://github.com/PiusSunday/mac-cleanup.git

# Install development tools (macOS)
brew install shellcheck bats-core

# Make the CLI executable
chmod +x bin/mac-cleanup

# Create a feature branch off develop
git checkout develop
git pull upstream develop
git checkout -b feature/your-feature
```

## Running Tests

All tests must pass before submitting a PR:

```bash
# ShellCheck (static analysis) — must report 0 errors
shellcheck lib/*.sh bin/mac-cleanup

# Bats unit tests
bats tests/

# Smoke test
bash tests/smoke_test.sh
```

## Code Style

- All shell scripts must pass `shellcheck` with zero warnings
- Use `set -euo pipefail` in scripts that are entry points
- All destructive operations **must** go through `dry_run_or_exec`
- Namespace functions: `<module>::<function_name>` (e.g., `xcode::_derived_data`)
- Log all user-visible output through the `log::*` functions in `lib/utils.sh`
- Use `utils::register_module` to register category, scanned, freed, and status

## Adding a New Cleanup Module

1. Create `lib/<module>.sh` following the existing module pattern
2. Export a single public function: `<module>::clean()`
3. Call `utils::require <tool>` at the start if the module depends on an external tool
4. Wrap all destructive operations with `dry_run_or_exec`
5. Register the module: `utils::register_module "Name" "Category" "$scanned" "$freed" "$status"`
6. Add `module_summary "Name" "$scanned"` at the end
7. Source the new module in `bin/mac-cleanup`
8. Add a `TARGET_<MODULE>` flag to `lib/core.sh`
9. Wire up the flag in `bin/mac-cleanup`'s `parse_flags` function
10. Add Bats tests in `tests/test_<module>.bats`

## Pull Request Guidelines

- **Target the `develop` branch** — not `main`
- Keep PRs focused — one feature or fix per PR
- Update `CHANGELOG.md` with your changes under an `[Unreleased]` section
- Ensure CI passes (ShellCheck + Bats + smoke tests) before requesting review
- Add or update tests for any new functionality

## Safety Rules

Never add code that:

- Touches `/System/*`, `/usr/*`, `/bin/*`, `/sbin/*`, or `/private/etc/*`
- Deletes iPhone backups (`~/Library/Application Support/MobileSync/Backup/*`)
- Deletes Keychain files (`~/Library/Keychains/*`)
- Runs destructive operations without going through `dry_run_or_exec`
- Auto-deletes anything in "System Data clues" — those are informational only

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
