#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/install.sh"
version=$(read_version_pin nvm)
platform=$(platform_string)
source "$_installer_library_dir/../metadata/nvm.sh"
commit=${git_commit[$version]:-}
load_archive_checksum nvm "$version" "$platform" || _installer_fail "No pinned NVM archive for $version/$platform."
checksum=${archive_sha256[$version/$platform]}
[[ $commit && $checksum && ${git_tag[$version]:-} ]] || _installer_fail "No pinned NVM Git metadata for $version/$platform."
_installer_require git tar sha256sum mkdir mv
cache_dir="$TOOLSHED_DOWNLOAD_DIR/$platform/nvm/$version"
mkdir -p -- "$(dirname -- "$TOOLSHED_NVM_GIT_DIR")" "$cache_dir"
mirror=$TOOLSHED_NVM_GIT_DIR
if [[ ! -e $mirror ]]; then
    stage_directory staging "$(dirname -- "$TOOLSHED_NVM_GIT_DIR")"
    git clone --mirror https://github.com/nvm-sh/nvm.git "$staging/mirror"
    mirror="$staging/mirror"
fi
[[ $(git -C "$mirror" rev-parse "refs/tags/v$version") == "${git_tag[$version]}" ]] || _installer_fail 'NVM tag object does not match pin.'
[[ $(git -C "$mirror" rev-parse "refs/tags/v$version^{}") == "$commit" ]] || _installer_fail 'NVM tag does not match pinned commit.'
stage_directory bundle_stage "$cache_dir"
git -C "$mirror" archive --format=tar.gz --prefix="nvm-$version/" "$commit" --output "$bundle_stage/archive"
verify_sha256 "$bundle_stage/archive" "$checksum"
if [[ $mirror != "$TOOLSHED_NVM_GIT_DIR" ]]; then
    [[ ! -e $TOOLSHED_NVM_GIT_DIR && ! -L $TOOLSHED_NVM_GIT_DIR ]] || _installer_fail 'NVM Git cache appeared during staging.'
    mv -T -- "$mirror" "$TOOLSHED_NVM_GIT_DIR"
fi
archive="$cache_dir/nvm-$version.tar.gz"
if [[ -e $archive || -L $archive ]]; then
    verify_sha256 "$archive" "$checksum"
else
    mv -T -- "$bundle_stage/archive" "$archive"
fi
printf 'Prepared NVM %s archive in %s\n' "$version" "$cache_dir"
