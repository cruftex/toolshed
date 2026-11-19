#!/usr/bin/env bash
# Usage: lib/discover-tool.sh TOOL — find, verify and record the latest release of tools/TOOL.sh; prints its version.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/update.sh"
discovery_init
(( $# == 1 )) || _installer_fail 'Usage: discover-tool.sh TOOL'
discover_tool "$1"
