#!/usr/bin/env bash
# Releases: https://github.com/oven-sh/bun/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

declare -Ar archive_sha256=(
    [1.4.4/linux-x64]=bf8ccbfb2b0b80159e0f9a6d15c55317add8077534dbc6130a3edb52fccb395c
)
declare -Ar binary_sha256=(
    [1.4.4/linux-x64]=10702245766b225e70bbf6235fd6b47214fd94b4760d00ffaed8ab0df57ac235
)
version=1.4.4
platform=$(platform_string)
key="$version/$platform"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] ||
    _installer_fail "No pinned Bun checksums for $key."
archive="$DOWNLOAD_DIR/bun-v$version-$platform.zip"
url="https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-$platform.zip"

if ! binary_is_installed bun "${binary_sha256[$key]}"; then
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    extract_zip_member "$archive" "bun-$platform/bun" binary
    verify_sha256 "$binary" "${binary_sha256[$key]}"
    verify_version "$binary" "$version"
    install_binary "$binary" bun
fi
install_symlink bun bunx
printf 'Bun %s is installed in %s\n' "$version" "$DEST_BIN_DIR"
