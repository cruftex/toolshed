#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
discover_release_binary 'crane' 'google/go-containerregistry' 'v' 'go-containerregistry_Linux_x86_64.tar.gz' 'crane'
