#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version controller-gen "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums controller-gen "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned controller-gen checksums for $key."
url="https://github.com/kubernetes-sigs/controller-tools/releases/download/v$version/controller-gen-linux-amd64"
install_release_binary controller-gen "$version" "$url" "" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'controller-gen %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
