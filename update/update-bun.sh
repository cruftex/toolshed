#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Bun update supports Linux x86_64 only.'
_installer_require python3 unzip sha256sum
stage_directory staging
release_info oven-sh/bun bun-v "$staging/release"
version=$(cat "$staging/release")
asset=bun-linux-x64.zip
archive_sha=$(release_asset_digest "$staging/release" "$asset")
archive="$DOWNLOAD_DIR/bun-v$version-linux-x64.zip"
download_verified "https://github.com/oven-sh/bun/releases/download/bun-v$version/$asset" "$archive_sha" "$archive"
extract_zip_member "$archive" bun-linux-x64/bun binary
binary_sha=$(sha256sum < "$binary"); binary_sha=${binary_sha%% *}
verify_version "$binary" "$version"
record_checksums bun "$version/linux-x64" "$archive_sha" "$binary_sha"
write_version_pin bun "$version"
"$root/install/install-bun.sh"
