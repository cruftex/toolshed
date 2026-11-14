#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version kustomize "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums kustomize "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned kustomize checksums for $key."
url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v$version/kustomize_v${version}_linux_amd64.tar.gz"
install_release_binary kustomize "$version" "$url" "kustomize" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'kustomize %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
