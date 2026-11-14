#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version helm "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums helm "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned Helm checksums for $key."
url="https://get.helm.sh/helm-v${version}-linux-amd64.tar.gz"
if ! binary_is_installed helm "${binary_sha256[$key]}"; then
    archive=$(cache_path "$url")
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    stage_directory staging
    _installer_require tar chmod
    tar -xzf "$archive" -C "$staging" linux-amd64/helm || _installer_fail 'Cannot extract Helm.'
    binary="$staging/linux-amd64/helm"
    chmod 755 -- "$binary"
    verify_sha256 "$binary" "${binary_sha256[$key]}"
    actual=$("$binary" version --short) || _installer_fail 'Cannot execute Helm.'
    [[ $actual == "v$version" || $actual == "v$version"+* ]] || _installer_fail "Unexpected Helm version: $actual"
    install_binary "$binary" helm
fi
printf 'Helm %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
