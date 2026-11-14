#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=0.41.0
platform=$(platform_string)
declare -A archive_sha256=([0.41.0/linux-x64]=532560c9ecc6ef484279fcc1c600e9346537bc7913b891ffd0ec0caca5072694)
checksum=${archive_sha256[$version/$platform]:-}
[[ $checksum ]] || _installer_fail "No pinned NVM archive for $version/$platform."
if [[ -e $TOOLSHED_NVM_DIR || -L $TOOLSHED_NVM_DIR ]]; then
    [[ -f $TOOLSHED_NVM_DIR/nvm.sh ]] || _installer_fail "Incomplete NVM installation: $TOOLSHED_NVM_DIR"
    actual=$(NVM_DIR="$TOOLSHED_NVM_DIR" bash -c 'source "$NVM_DIR/nvm.sh" --no-use; nvm --version')
    [[ $actual == "$version" ]] || _installer_fail "Existing NVM version differs: $actual"
else
    url="https://github.com/nvm-sh/nvm/archive/refs/tags/v$version.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "$checksum" "$archive"
    mkdir -p -- "$(dirname -- "$TOOLSHED_NVM_DIR")"
    stage_directory staging "$(dirname -- "$TOOLSHED_NVM_DIR")"
    tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract NVM archive.'
    actual=$(NVM_DIR="$staging/nvm-$version" bash -c 'source "$NVM_DIR/nvm.sh" --no-use; nvm --version')
    [[ $actual == "$version" ]] || _installer_fail 'Unexpected NVM version.'
    [[ ! -e $TOOLSHED_NVM_DIR && ! -L $TOOLSHED_NVM_DIR ]] || _installer_fail 'NVM destination appeared during staging.'
    mv -T -- "$staging/nvm-$version" "$TOOLSHED_NVM_DIR"
fi
printf 'NVM %s is installed in %s\n' "$version" "$TOOLSHED_NVM_DIR"
