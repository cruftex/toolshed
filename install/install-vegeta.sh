#!/usr/bin/env bash
# Releases: https://github.com/tsenart/vegeta/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

declare -Ar archive_sha256=(
    [12.13.0/linux_amd64]=e8759ce45c14e18374bdccd3ba6068197bc3a9f9b7e484db3837f701b9d12e61
    [12.13.0/linux_arm64]=950381173a5575e25e8e086f36fc03bf65d61a2433329b48e41e1cb5e4133bba
    [12.13.0/darwin_amd64]=4e912c83ce07db4e1e394e1cbb657f2396dff2f7ed90f03869a184cc17d0f994
    [12.13.0/darwin_arm64]=fc408e242c4f4839e6fe536dbf1130bb02f430134827f6d831bf367a0929a799
)
declare -Ar binary_sha256=(
    [12.13.0/linux_amd64]=c54d905541485153542dfcb850f9ab8ef801e7ab1a652d2cfc69cafdd4a5363f
    [12.13.0/linux_arm64]=2355df87f054ddbee28bee0b31c741836fa35619f329f664af29fa80910420c4
    [12.13.0/darwin_amd64]=dae9dfe4b1b84745764d96248b7285c90200d9f92d6e9095b23b10286208a5c0
    [12.13.0/darwin_arm64]=15d6cd01fc412e70a11243006de4e5fd68d505a13848ae3312d83d49b64fd087
)
version=12.13.0

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
