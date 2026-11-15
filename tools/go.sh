kind=opt
repo=golang/go
tag=go
url='https://go.dev/dl/go{version}.linux-amd64.tar.gz'
root=go
links='bin/go bin/gofmt'
executable=go
version_args=version
version_env=GOTOOLCHAIN=local
license=bsd-3-clause

# Keep the installed toolchain from downloading other toolchains.
tool_prepare() {
    _installer_require sed grep
    grep -qx "GOTOOLCHAIN=auto" "$1/go.env" || _installer_fail 'Unexpected Go toolchain configuration.'
    sed -i 's/^GOTOOLCHAIN=auto$/GOTOOLCHAIN=local/' "$1/go.env"
}

tool_validate() {
    local directory=$1 version=$2 output
    [[ -x $directory/bin/go && -x $directory/bin/gofmt ]] || return 1
    output=$(GOTOOLCHAIN=local GOROOT="$directory" "$directory/bin/go" version) || return 1
    [[ $output == "go version go$version "* ]] || return 1
    output=$(printf 'package p\n' | "$directory/bin/gofmt") || return 1
    [[ $output == 'package p' ]]
}

tool_latest() {
    local staging=$1
    _installer_download 'https://go.dev/dl/?mode=json' "$staging/releases.json"
    read -r version 'discovered[linux-x64]' < <(python3 - "$staging/releases.json" <<'PY'
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
    [[ ${version:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && ${discovered[linux-x64]:-} =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid Go release metadata.'
    provenance_url='https://go.dev/dl/?mode=json'
    provenance_peer="$staging/releases.json.peer"
}
