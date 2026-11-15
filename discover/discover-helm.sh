#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Helm discovery supports Linux x86_64 only.'
_installer_require python3 sha256sum tar chmod
stage_directory staging
github_release_info helm/helm v "$staging/release"
version=$(cat "$staging/release")
asset="helm-v${version}-linux-amd64.tar.gz"
url="https://get.helm.sh/$asset"
_installer_download "$url.sha256sum" "$staging/checksum"
read -r checksum filename extra < "$staging/checksum"
[[ $checksum =~ ^[0-9a-f]{64}$ && $filename == "$asset" && -z ${extra:-} ]] || _installer_fail 'Invalid Helm publisher checksum.'
archive=$(cache_path "$url")
download_verified "$url" "$checksum" "$archive"
tar -xzf "$archive" -C "$staging" linux-amd64/helm || _installer_fail 'Cannot extract Helm.'
binary="$staging/linux-amd64/helm"
[[ -s $binary ]] || _installer_fail 'Empty Helm binary.'
chmod 755 -- "$binary"
actual=$("$binary" version --short) || _installer_fail 'Cannot execute Helm.'
[[ $actual == "v$version" || $actual == "v$version"+* ]] || _installer_fail "Unexpected Helm version: $actual"
record_checksums helm "$version/linux-x64" "$checksum"
record_github_license helm "$version" helm/helm "v$version" LICENSE apache-2.0
record_provenance "helm" "$version/linux-x64" "$url.sha256sum" "$staging/checksum.peer"
printf '%s\n' "$version"
