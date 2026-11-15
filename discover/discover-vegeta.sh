#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
_installer_require python3 tar sha256sum
stage_directory staging
release_info tsenart/vegeta v "$staging/release"
version=$(cat "$staging/release")
for platform in linux_amd64 linux_arm64 darwin_amd64 darwin_arm64; do
    asset="vegeta_${version}_${platform}.tar.gz"
    archive_sha=$(release_asset_digest "$staging/release" "$asset")
    url="https://github.com/tsenart/vegeta/releases/download/v$version/$asset"
    archive=$(cache_path "$url")
    download_verified "$url" "$archive_sha" "$archive"
    tar -xOzf "$archive" vegeta > "$staging/$platform" || _installer_fail "Cannot extract $asset."
    [[ -s $staging/$platform ]] || _installer_fail "Empty vegeta binary: $platform"
    binary_sha=$(sha256sum < "$staging/$platform"); binary_sha=${binary_sha%% *}
    printf '%s %s %s\n' "$platform" "$archive_sha" "$binary_sha" >> "$staging/checksums"
done
while read -r platform archive_sha binary_sha; do
    check_recorded_checksums vegeta "$version/$platform" "$archive_sha" "$binary_sha"
done < "$staging/checksums"
while read -r platform archive_sha binary_sha; do
    record_checksums vegeta "$version/$platform" "$archive_sha" "$binary_sha"
done < "$staging/checksums"
for platform in linux_amd64 linux_arm64 darwin_amd64 darwin_arm64; do
    record_provenance vegeta "$version/$platform" "https://api.github.com/repos/tsenart/vegeta/releases/latest" "$staging/release.json.peer"
done
printf "%s\n" "$version"
