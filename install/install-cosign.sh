#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version cosign "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums cosign "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned cosign checksums for $key."
url="https://github.com/sigstore/cosign/releases/download/v$version/cosign-linux-amd64"
install_release_binary cosign "$version" "$url" '' "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'cosign %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
