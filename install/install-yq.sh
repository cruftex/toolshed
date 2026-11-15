#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
name=${BASH_SOURCE[0]##*/}
name=${name#install-}; name=${name%.sh}
install_defined_release "$name" "$@"
