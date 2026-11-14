#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version crane "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums crane "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned crane checksums for $key."
url="https://github.com/google/go-containerregistry/releases/download/v$version/go-containerregistry_Linux_x86_64.tar.gz"
install_release_binary crane "$version" "$url" "crane" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'crane %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
