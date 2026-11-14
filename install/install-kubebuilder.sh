#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version kubebuilder "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums kubebuilder "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned kubebuilder checksums for $key."
url="https://github.com/kubernetes-sigs/kubebuilder/releases/download/v$version/kubebuilder_linux_amd64"
install_release_binary kubebuilder "$version" "$url" "" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'kubebuilder %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
