#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version kind "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums kind "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned kind checksums for $key."
url="https://github.com/kubernetes-sigs/kind/releases/download/v$version/kind-linux-amd64"
if ! binary_is_installed kind "${binary_sha256[$key]}"; then
    archive=$(cache_path "$url")
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    stage_executable "$archive" binary
    verify_sha256 "$binary" "${binary_sha256[$key]}"
    actual=$("$binary" version) || _installer_fail 'Cannot execute kind.'
    [[ $actual == "kind v$version "* ]] || _installer_fail "Unexpected kind version: $actual"
    install_binary "$binary" kind
fi
printf 'kind %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
