#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version setup-envtest "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums setup-envtest "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned setup-envtest checksums for $key."
url="https://github.com/kubernetes-sigs/controller-runtime/releases/download/v$version/setup-envtest-linux-amd64"
install_release_binary setup-envtest "$version" "$url" "" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'setup-envtest %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
