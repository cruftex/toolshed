#!/usr/bin/env bash
# Releases: https://github.com/tsenart/vegeta/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=$(read_version_pin vegeta)

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
load_binary_checksums vegeta "$key"

[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] ||
    _installer_fail "No pinned Vegeta checksums for $key."

archive="$DOWNLOAD_DIR/vegeta-v$version-$platform.tar.gz"
url="https://github.com/tsenart/vegeta/releases/download/v$version/vegeta_${version}_${platform}.tar.gz"

if ! binary_is_installed vegeta "${binary_sha256[$key]}"; then
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    stage_directory staging
    _installer_require tar chmod
    tar -xzf "$archive" -C "$staging" vegeta ||
        _installer_fail "Cannot extract vegeta from $archive"
    [[ -s $staging/vegeta ]] || _installer_fail 'Extracted binary is empty.'
    chmod 755 -- "$staging/vegeta"
    binary="$staging/vegeta"
    verify_sha256 "$binary" "${binary_sha256[$key]}"
    actual=$("$binary" --version 2>&1) ||
        _installer_fail "Cannot execute staged binary: $binary"
    [[ $actual == *"Version: v$version"* ]] ||
        _installer_fail "Expected version $version, got: $actual"
    install_binary "$binary" vegeta
fi
printf 'Vegeta %s is installed in %s\n' "$version" "$DEST_BIN_DIR"
