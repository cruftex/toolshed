#!/usr/bin/env bash
# Releases: https://github.com/oven-sh/bun/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=$(select_install_version bun "$@")
platform=$(platform_string)
key="$version/$platform"
declare -A archive_sha256=() binary_sha256=()
archive_sha256[$key]=$(python3 "$_installer_library_dir/artifact_metadata.py" checksum \
    "$_installer_library_dir/../metadata/artifacts/bun.psv" "$version" "/$platform/archive/zip") ||
    _installer_fail "No pinned Bun checksums for $key."
url="https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-$platform.zip"

archive=$(cache_path "$url")

download_verified "$url" "${archive_sha256[$key]}" "$archive"
extract_zip_member "$archive" "bun-$platform/bun" binary
binary_sha256[$key]=$(sha256sum < "$binary"); binary_sha256[$key]=${binary_sha256[$key]%% *}
if ! binary_is_installed bun "${binary_sha256[$key]}"; then
    warn_if_modified bun "${binary_sha256[$key]}"
    verify_version "$binary" "$version"
    install_binary "$binary" bun
fi
install_symlink bun bunx
printf 'Bun %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
