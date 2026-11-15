#!/usr/bin/env bash
# Usage: lib/install-tool.sh TOOL — install the pinned (or TOOLSHED_OVERRIDE_TOOL_VERSION) release of tools/TOOL.sh.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install.sh"
source "$_installer_library_dir/tool.sh"
(( $# >= 1 )) || _installer_fail 'Usage: install-tool.sh TOOL'
install_tool "$@"
