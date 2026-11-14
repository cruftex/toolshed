#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(read_version_pin maven310)
[[ $version == 3.10.* ]] || _installer_fail 'Invalid Maven 3.10 pin.'
install_pinned_maven "$version"
install_symlink "$TOOLSHED_OPT_DIR/maven/$version/bin/mvn" mvn310
