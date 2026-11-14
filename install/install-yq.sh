#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version yq "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums yq "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned yq checksums for $key."
url="https://github.com/mikefarah/yq/releases/download/v$version/yq_linux_amd64"
install_release_binary yq "$version" "$url" "" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'yq %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
