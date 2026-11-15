#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'kind discovery supports Linux x86_64 only.'
_installer_require python3 sha256sum
stage_directory staging
release_info kubernetes-sigs/kind v "$staging/release"
version=$(cat "$staging/release")
asset=kind-linux-amd64
checksum=$(release_asset_digest "$staging/release" "$asset")
check_recorded_checksums kind "$version/linux-x64" "$checksum" "$checksum"
url="https://github.com/kubernetes-sigs/kind/releases/download/v$version/$asset"
archive=$(cache_path "$url")
download_verified "$url" "$checksum" "$archive"
stage_executable "$archive" binary
actual=$("$binary" version) || _installer_fail 'Cannot execute kind.'
[[ $actual == "kind v$version "* ]] || _installer_fail "Unexpected kind version: $actual"
record_checksums kind "$version/linux-x64" "$checksum" "$checksum"
record_provenance "kind" "$version/linux-x64" "https://api.github.com/repos/kubernetes-sigs/kind/releases/latest" "$staging/release.json.peer"
printf '%s\n' "$version"
