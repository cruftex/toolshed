#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version kubectl "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums kubectl "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned kubectl checksums for $key."
url="https://dl.k8s.io/release/v$version/bin/linux/amd64/kubectl"
if ! binary_is_installed kubectl "${binary_sha256[$key]}"; then
    archive=$(cache_path "$url")
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    stage_executable "$archive" binary
    verify_sha256 "$binary" "${binary_sha256[$key]}"
    actual=$("$binary" version --client) || _installer_fail 'Cannot execute kubectl.'
    [[ $actual == "Client Version: v$version"$'\n'* || $actual == "Client Version: v$version" ]] || _installer_fail "Unexpected kubectl version: $actual"
    install_binary "$binary" kubectl
fi
printf 'kubectl %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
