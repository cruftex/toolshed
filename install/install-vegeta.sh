#!/usr/bin/env bash
# Releases: https://github.com/tsenart/vegeta/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=$(select_install_version vegeta "$@")

_installer_require uname
case $(uname -s) in
    Linux)
        _installer_require getconf
        getconf GNU_LIBC_VERSION >/dev/null 2>&1 || _installer_fail 'This installer requires glibc.'
        os=linux ;;
    Darwin) os=darwin ;;
    *) _installer_fail "Unsupported operating system: $(uname -s)" ;;
esac
case $(uname -m) in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) _installer_fail "Unsupported architecture: $(uname -m)" ;;
esac
platform="${os}_${arch}"
key="$version/$platform"
declare -A archive_sha256=() binary_sha256=()
cache_platform=$(platform_string)
archive_sha256[$key]=$(python3 "$_installer_library_dir/artifact_metadata.py" checksum \
    "$_installer_library_dir/../metadata/artifacts/vegeta.psv" "$version" "/$cache_platform/archive/tar.gz") ||
    _installer_fail "No pinned Vegeta checksums for $key."

url="https://github.com/tsenart/vegeta/releases/download/v$version/vegeta_${version}_${platform}.tar.gz"

archive=$(cache_path "$url")

download_verified "$url" "${archive_sha256[$key]}" "$archive"
stage_directory staging
_installer_require tar chmod
tar -xzf "$archive" -C "$staging" vegeta ||
    _installer_fail "Cannot extract vegeta from $archive"
[[ -s $staging/vegeta ]] || _installer_fail 'Extracted binary is empty.'
chmod 755 -- "$staging/vegeta"
binary="$staging/vegeta"
binary_sha256[$key]=$(sha256sum < "$binary"); binary_sha256[$key]=${binary_sha256[$key]%% *}
if ! binary_is_installed vegeta "${binary_sha256[$key]}"; then
    warn_if_modified vegeta "${binary_sha256[$key]}"
    actual=$("$binary" --version 2>&1) ||
        _installer_fail "Cannot execute staged binary: $binary"
    [[ $actual == *"Version: v$version"* ]] ||
        _installer_fail "Expected version $version, got: $actual"
    install_binary "$binary" vegeta
fi
printf 'Vegeta %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
