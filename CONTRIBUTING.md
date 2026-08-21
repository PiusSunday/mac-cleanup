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

## Every detector ships with a fixture that proves it fires

A detector that reports "nothing found" is indistinguishable from a detector that is broken, and
this project has shipped that bug four separate times:

| Detector | Looked like | Actually was |
| --- | --- | --- |
| Orphan name matcher | no false positives | `tr -cd '[:alnum:]'` ate the newline, so the installed-apps file was one line and the exact lookup never matched |
| Editor workspace check | keeping everything, safely | BSD `sed` has no BRE alternation, so the parse captured nothing and every workspace looked unparseable |
| `node_modules` scan | a clean machine | the orphan condition can never hold, so a 30-second `$HOME` walk always returned `0 B` |
| Trash decision | no Trash worth reporting | Finder answers `get size of trash` with `missing value`, and a size-based gate suppressed the entry |

Each read as a passing result. So:

- Any detector that can return "nothing found" needs a test with a **positive** fixture proving it
  fires, not only negative fixtures proving it stays quiet.
- When a real positive cannot be reproduced on the developer's machine, build a synthetic one —
  see `tests/test_devtools.bats` (a workspace whose folder was deleted) and `tests/test_orphans.bats`
  (`com.deadvendor.DeadApp`).
- Never treat an empty result during manual verification as confirmation. Plant a positive, confirm
  it is caught, then remove it.
- Prefer a probe you control over the developer's real data: a throwaway image, a scratch `$HOME`,
  a file you created in the Trash yourself.

The same applies to the environment the tests themselves assume. `timeout` is GNU coreutils and is
not present on macOS, so four tests that used it passed on a developer machine with Homebrew
coreutils installed and failed on a clean `macos-latest` runner with exit 127. Prefer the portable
mechanisms the tool already uses — `perl -e 'alarm ...'` rather than `timeout`, `sed -E` rather than
BRE alternation, and `stat -f` rather than `stat -c`.

The same applies to fallbacks. A fallback that never runs is dead code with a comment claiming
otherwise, so exercise it directly — `system::_trash_size_bytes` has a test for the `du` path even
though Full Disk Access usually stops it running on a real machine.

## Releasing a New Version

mac-cleanup uses an automated GitHub Actions workflow for releases. To publish a new version:

1. Update the `VERSION` variable in `lib/core/core.sh`.
2. Update `CHANGELOG.md`, including a `### Breaking` section whenever behaviour that existing
   scripts or habits depend on has changed — a reclaimable total that drops sharply counts, because
   users will otherwise read the improvement as a regression.
3. Verify locally with the same commands CI runs, not looser ones:

   ```bash
   bats tests/
   shellcheck $(find lib -type f -name "*.sh") bin/mac-cleanup
   bash tests/smoke_test.sh          # ~6 minutes; runs --all three times
   ```

4. Merge into `main` and push both branches.
5. Create and push an annotated tag matching the version:

   ```bash
   git tag -a v0.2.1 -m "v0.2.1 — summary"
   git push origin v0.2.1
   ```

6. **Back-merge `main` into `develop`.** Merging `develop` into `main` with `--no-ff` puts the merge
   commit on `main` only, so `develop` falls one commit behind per release and the gap compounds:

   ```bash
   git checkout develop && git merge --ff-only main && git push origin develop
   ```

Pushing the tag triggers the Release workflow, which runs validations, creates a GitHub Release with the tarball SHA-256, and updates the Homebrew tap.

If validation fails, no release is published and the tap is untouched — check with
`gh release view <tag>` before deciding how to recover. When nothing was published, deleting and
re-pushing the tag on a fixed commit rewrites nothing anyone has seen:

```bash
git push origin :refs/tags/v0.2.1 && git tag -d v0.2.1
```

After the release, confirm the published tarball's SHA-256 matches the formula and that the tap
commit landed — the workflow reports success for the release job even though the tap update is a
separate job.

### Required Secrets

The release workflow requires the following repository secret in GitHub Settings:

- `TAP_GITHUB_TOKEN`: A Personal Access Token (PAT) with `repo` scope, used to automatically push Formula updates to the `homebrew-mac-cleanup` tap repository.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
