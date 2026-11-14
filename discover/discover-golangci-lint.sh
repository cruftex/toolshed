#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
discover_release_binary 'golangci-lint' 'golangci/golangci-lint' 'v' 'golangci-lint-{version}-linux-amd64.tar.gz' 'golangci-lint-{version}-linux-amd64/golangci-lint'
