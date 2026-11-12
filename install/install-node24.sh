#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_VERSION="24"

# Install NVM if missing.
if [[ ! -f "$NVM_DIR/nvm.sh" ]]; then
    echo "NVM not found. Installing..."
    "$SCRIPT_DIR/install-nvm.sh"
fi

# Load NVM without modifying shell configuration.
export NVM_DIR
. "$NVM_DIR/nvm.sh" --no-use

# Already installed? Do nothing.
INSTALLED_VERSION="$(nvm version "$NODE_VERSION" || true)"

if [[ "$INSTALLED_VERSION" == v24.* ]]; then
    echo "Node.js $INSTALLED_VERSION already installed."
    exit 0
fi

# Install the latest Node.js 24.x release.
nvm install "$NODE_VERSION"

echo "Node.js $(nvm version "$NODE_VERSION") installed successfully."
