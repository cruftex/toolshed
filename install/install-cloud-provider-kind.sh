#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version cloud-provider-kind "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums cloud-provider-kind "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned cloud-provider-kind checksums for $key."
url="https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/v$version/cloud-provider-kind_${version}_linux_amd64.tar.gz"
install_release_binary cloud-provider-kind "$version" "$url" "cloud-provider-kind" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'cloud-provider-kind %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
