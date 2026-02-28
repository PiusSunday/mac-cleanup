# Contributing to mac-cleanup

Thank you for your interest in contributing! This project welcomes bug reports, feature requests, and pull requests.

## Development Setup

```bash
# Clone the repo
git clone https://github.com/PiusSunday/mac-cleanup.git
cd mac-cleanup

# Install development tools (macOS)
brew install shellcheck bats-core

# Make the CLI executable
chmod +x bin/mac-cleanup
```

## Running Tests

```bash
# Run all Bats unit tests
bats tests/test_utils.bats tests/test_xcode.bats tests/test_docker.bats

# Run smoke test
bash tests/smoke_test.sh

# Run ShellCheck (static analysis)
shellcheck bin/mac-cleanup lib/*.sh install.sh tests/smoke_test.sh
```

## Code Style

- All shell scripts must pass `shellcheck` with zero warnings
- Use `set -euo pipefail` in scripts that are entry points
- All destructive operations **must** go through `dry_run_or_exec`
- Namespace functions: `<module>::<function_name>` (e.g., `xcode::_derived_data`)
- Log all user-visible output through the `log::*` functions in `lib/utils.sh`

## Adding a New Cleanup Module

1. Create `lib/<module>.sh` following the existing module pattern
2. Export a single public function: `<module>::clean()`
3. Call `utils::require <tool>` at the start if the module depends on an external tool
4. Wrap all destructive operations with `dry_run_or_exec`
5. Source the new module in `bin/mac-cleanup`
6. Add a `TARGET_<MODULE>` flag to `lib/core.sh`
7. Wire up the flag in `bin/mac-cleanup`'s `parse_flags` function
8. Add Bats tests in `tests/test_<module>.bats`

## Pull Request Guidelines

- Keep PRs focused — one feature or fix per PR
- Update `CHANGELOG.md` with your changes under an `[Unreleased]` section
- Ensure CI passes before requesting review
- Add or update tests for any new functionality

## Safety Rules

Never add code that:

- Touches `/System/*`, `/usr/*`, `/bin/*`, `/sbin/*`, or `/private/etc/*`
- Deletes iPhone backups (`~/Library/Application Support/MobileSync/Backup/*`)
- Deletes Keychain files (`~/Library/Keychains/*`)
- Runs destructive operations without going through `dry_run_or_exec`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
