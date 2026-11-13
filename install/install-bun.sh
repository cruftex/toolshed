#!/usr/bin/env bash
# Releases: https://github.com/oven-sh/bun/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=$(read_version_pin bun)
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums bun "$key"
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
