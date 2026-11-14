#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
target="$_installer_library_dir/../bin/shed"
[[ -x $target ]] || _installer_fail "Missing executable: $target"
if [[ -e $TOOLSHED_BIN_DIR/shed || -L $TOOLSHED_BIN_DIR/shed ]]; then
    [[ -L $TOOLSHED_BIN_DIR/shed && $(readlink -- "$TOOLSHED_BIN_DIR/shed") == "$target" ]] ||
        _installer_fail "Destination already exists: $TOOLSHED_BIN_DIR/shed"
fi
install_symlink "$target" shed
printf 'Toolshed command is installed in %s\n' "$TOOLSHED_BIN_DIR"
