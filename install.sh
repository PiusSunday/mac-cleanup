#!/usr/bin/env bash
# install.sh — Standalone installer for mac-cleanup
set -euo pipefail

REPO="https://github.com/PiusSunday/mac-cleanup"
INSTALL_DIR="$HOME/.mac-cleanup"

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

# Pick the symlink directory. Homebrew installs to /opt/homebrew/bin on Apple
# Silicon and /usr/local/bin on Intel; those are the natural bins to prefer.
# Fall back to ~/.local/bin when neither is writable.
if [[ -d "/opt/homebrew/bin" && -w "/opt/homebrew/bin" ]]; then
  BIN_DIR="/opt/homebrew/bin"
elif [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]]; then
  BIN_DIR="/usr/local/bin"
else
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi

ln -sf "${INSTALL_DIR}/bin/mac-cleanup" "${BIN_DIR}/mac-cleanup"
echo "✔ Symlinked to ${BIN_DIR}/mac-cleanup"

# Warn only when the chosen bin is off PATH, which is the case that actually
# needs the user to act.
case ":$PATH:" in
  *":${BIN_DIR}:"*) ;;
  *) echo "  Add ${BIN_DIR} to your PATH to run 'mac-cleanup' directly." ;;
esac

# Read the version back from the installed tree. The path moved to
# lib/core/core.sh in the v0.4.0 refactor and this line was never updated, so
# every install since then has printed an empty version.
installed_version=$(grep -m1 '^VERSION=' "${INSTALL_DIR}/lib/core/core.sh" | cut -d'"' -f2)
echo "✔ mac-cleanup v${installed_version:-unknown} installed successfully!"
echo "  Run: mac-cleanup --help"
