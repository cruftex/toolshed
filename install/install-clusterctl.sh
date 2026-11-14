#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version clusterctl "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums clusterctl "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned clusterctl checksums for $key."
url="https://github.com/kubernetes-sigs/cluster-api/releases/download/v$version/clusterctl-linux-amd64"
if ! binary_is_installed clusterctl "${binary_sha256[$key]}"; then
    archive=$(cache_path "$url")
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    stage_executable "$archive" binary
    verify_sha256 "$binary" "${binary_sha256[$key]}"
    actual=$(CLUSTERCTL_DISABLE_VERSIONCHECK=true "$binary" version -o short) || _installer_fail 'Cannot execute clusterctl.'
    [[ $actual == "v$version"* ]] || _installer_fail "Unexpected clusterctl version: $actual"
    install_binary "$binary" clusterctl
fi
printf 'clusterctl %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
