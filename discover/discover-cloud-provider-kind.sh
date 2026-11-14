#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
discover_release_binary 'cloud-provider-kind' 'kubernetes-sigs/cloud-provider-kind' 'v' 'cloud-provider-kind_{version}_linux_amd64.tar.gz' 'cloud-provider-kind'
