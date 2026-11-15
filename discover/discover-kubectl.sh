#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'kubectl discovery supports Linux x86_64 only.'
_installer_require python3 sha256sum
stage_directory staging
release_info kubernetes/kubernetes v "$staging/release"
version=$(cat "$staging/release")
url="https://dl.k8s.io/release/v$version/bin/linux/amd64/kubectl"
_installer_download "$url.sha256" "$staging/checksum"
checksum=$(cat "$staging/checksum")
[[ $checksum =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid kubectl publisher checksum.'
check_recorded_checksums kubectl "$version/linux-x64" "$checksum" "$checksum"
archive=$(cache_path "$url")
download_verified "$url" "$checksum" "$archive"
stage_executable "$archive" binary
actual=$("$binary" version --client) || _installer_fail 'Cannot execute kubectl.'
[[ $actual == "Client Version: v$version"$'\n'* || $actual == "Client Version: v$version" ]] || _installer_fail "Unexpected kubectl version: $actual"
record_checksums kubectl "$version/linux-x64" "$checksum" "$checksum"
record_provenance "kubectl" "$version/linux-x64" "$url.sha256" "$staging/checksum.peer"
printf '%s\n' "$version"
