#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version trivy "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums trivy "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned trivy checksums for $key."
url="https://github.com/aquasecurity/trivy/releases/download/v$version/trivy_${version}_Linux-64bit.tar.gz"
install_release_binary trivy "$version" "$url" "trivy" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'trivy %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
