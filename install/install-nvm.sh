#!/usr/bin/env bash
set -euo pipefail

NVM_VERSION="v0.41.0"
NVM_DIR="$HOME/.nvm"

# Already installed? Do nothing.
if [[ -f "$NVM_DIR/nvm.sh" ]]; then
    echo "NVM already installed."
    exit 0
fi

# Don't overwrite an existing incomplete installation.
if [[ -e "$NVM_DIR" ]]; then
    echo "Error: $NVM_DIR exists but NVM is incomplete." >&2
    exit 1
fi

# Clone a pinned release.
git clone --depth 1 --branch "$NVM_VERSION" \
    https://github.com/nvm-sh/nvm.git "$NVM_DIR"

