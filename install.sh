#!/usr/bin/env bash
# install.sh — Standalone installer for mac-cleanup
set -euo pipefail

REPO="https://github.com/PiusSunday/mac-cleanup"
INSTALL_DIR="$HOME/.mac-cleanup"
BIN_DIR="/usr/local/bin"

echo "Installing mac-cleanup..."

# Check macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: mac-cleanup only supports macOS." >&2
  exit 1
fi

# Check for git
if ! command -v git &>/dev/null; then
  echo "Error: git is required to install mac-cleanup." >&2
  exit 1
fi

# Clone or update
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "Cloning repository..."
  git clone --quiet "$REPO" "$INSTALL_DIR"
fi

# Make executable
chmod +x "${INSTALL_DIR}/bin/mac-cleanup"

# Symlink — fall back to ~/.local/bin if /usr/local/bin is not writable
if [[ -w "$BIN_DIR" ]]; then
  ln -sf "${INSTALL_DIR}/bin/mac-cleanup" "${BIN_DIR}/mac-cleanup"
  echo "✔ Symlinked to ${BIN_DIR}/mac-cleanup"
else
  LOCAL_BIN="$HOME/.local/bin"
  mkdir -p "$LOCAL_BIN"
  ln -sf "${INSTALL_DIR}/bin/mac-cleanup" "${LOCAL_BIN}/mac-cleanup"
  echo "✔ Symlinked to ${LOCAL_BIN}/mac-cleanup"
  echo "  Add ${LOCAL_BIN} to your PATH if it is not already there."
fi

# Read the version back from the installed tree. The path moved to
# lib/core/core.sh in the v0.4.0 refactor and this line was never updated, so
# every install since then has printed an empty version.
installed_version=$(grep -m1 '^VERSION=' "${INSTALL_DIR}/lib/core/core.sh" | cut -d'"' -f2)
echo "✔ mac-cleanup v${installed_version:-unknown} installed successfully!"
echo "  Run: mac-cleanup --help"
