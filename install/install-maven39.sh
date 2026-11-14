#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version maven39 "$@")
[[ $version == 3.9.* ]] || _installer_fail 'Invalid Maven 3.9 pin.'
install_pinned_maven "$version"
install_symlink "$TOOLSHED_OPT_DIR/maven/$version/bin/mvn" mvn39
