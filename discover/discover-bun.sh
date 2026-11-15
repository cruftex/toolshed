#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Bun update supports Linux x86_64 only.'
_installer_require python3 unzip sha256sum
stage_directory staging
github_release_info oven-sh/bun bun-v "$staging/release"
version=$(cat "$staging/release")
asset=bun-linux-x64.zip
archive_sha=$(github_release_asset_digest "$staging/release" "$asset")
url="https://github.com/oven-sh/bun/releases/download/bun-v$version/$asset"
archive=$(cache_path "$url")
download_verified "$url" "$archive_sha" "$archive"
extract_zip_member "$archive" bun-linux-x64/bun binary
verify_version "$binary" "$version"
record_checksums bun "$version/linux-x64" "$archive_sha"
record_provenance "bun" "$version/linux-x64" "https://api.github.com/repos/oven-sh/bun/releases/latest" "$staging/release.json.peer"
printf "%s\n" "$version"
