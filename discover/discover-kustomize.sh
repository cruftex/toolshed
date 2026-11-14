#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
discover_release_binary 'kustomize' 'kubernetes-sigs/kustomize' 'kustomize/v' 'kustomize_v{version}_linux_amd64.tar.gz' 'kustomize'
