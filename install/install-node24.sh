#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version node24 "$@")
platform=$(platform_string)
load_archive_checksum node24 "$version" "$platform" || _installer_fail "No pinned Node archive for $version/$platform."
checksum=${archive_sha256[$version/$platform]}
env -u TOOLSHED_OVERRIDE_TOOL_VERSION "$_installer_library_dir/../install/install-nvm.sh"
destination="$TOOLSHED_NVM_DIR/versions/node/v$version"
if [[ ! -e $destination && ! -L $destination ]]; then
    url="https://nodejs.org/dist/v$version/node-v$version-linux-x64.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "$checksum" "$archive"
    mkdir -p -- "$TOOLSHED_NVM_DIR/versions/node"
    stage_directory staging "$TOOLSHED_NVM_DIR/versions/node"
    tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Node archive.'
    verify_version "$staging/node-v$version-linux-x64/bin/node" "v$version"
    [[ ! -e $destination && ! -L $destination ]] || _installer_fail 'Node destination appeared during staging.'
    mv -T -- "$staging/node-v$version-linux-x64" "$destination"
else
    [[ -x $destination/bin/node && -x $destination/bin/npm ]] || _installer_fail "Incomplete Node installation: $destination"
    verify_version "$destination/bin/node" "v$version"
fi
printf 'Node %s is installed in %s\n' "$version" "$destination"
