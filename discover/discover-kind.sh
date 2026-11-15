#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/update.sh"
name=${BASH_SOURCE[0]##*/}
name=${name#discover-}; name=${name%.sh}
discover_github_defined_release "$name"
