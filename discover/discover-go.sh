#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Go discovery supports Linux x86_64 only.'
_installer_require python3 tar sha256sum
stage_directory staging
_installer_download 'https://go.dev/dl/?mode=json' "$staging/releases.json"
read -r version checksum < <(python3 - "$staging/releases.json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    releases = json.load(f)
for release in releases:
    match = re.fullmatch(r'go(\d+\.\d+\.\d+)', release.get('version', ''))
    if release.get('stable') and match:
        version = match.group(1)
        assets = [a for a in release['files'] if a.get('filename') == f'go{version}.linux-amd64.tar.gz' and a.get('kind') == 'archive']
        if len(assets) != 1 or not re.fullmatch(r'[0-9a-f]{64}', assets[0].get('sha256', '')):
            sys.exit('Invalid Go archive metadata')
        print(version, assets[0]['sha256'])
        break
else:
    sys.exit('No stable Go release found')
PY
)
[[ ${version:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && ${checksum:-} =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid Go release metadata.'
key="$version/linux-x64"
check_recorded_checksums go "$key" "$checksum"
url="https://go.dev/dl/go${version}.linux-amd64.tar.gz"
archive=$(cache_path "$url")
download_verified "$url" "$checksum" "$archive"
tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Go archive.'
verify_go_toolchain "$staging/go" "$version"
record_checksums go "$key" "$checksum"
record_github_license go "$version" golang/go "go$version" LICENSE bsd-3-clause
record_provenance "go" "$version/linux-x64" "https://go.dev/dl/?mode=json" "$staging/releases.json.peer"
printf '%s\n' "$version"
