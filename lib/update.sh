#!/usr/bin/env bash
# Shared helpers for explicit release updates. The caller sources install.sh.
release_info() {
    local repository=$1 tag_prefix=$2 output=$3
    _installer_download "https://api.github.com/repos/$repository/releases/latest" "$output.json"
    python3 - "$output.json" "$tag_prefix" > "$output" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    release = json.load(f)
tag, prefix = release['tag_name'], sys.argv[2]
if not tag.startswith(prefix) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', tag[len(prefix):]) or release['draft'] or release['prerelease']:
    sys.exit('Invalid release metadata')
print(tag[len(prefix):])
PY
}
release_asset_digest() {
    python3 - "$1.json" "$2" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    assets = [a for a in json.load(f)['assets'] if a['name'] == sys.argv[2]]
if len(assets) != 1 or not re.fullmatch(r'sha256:[0-9a-f]{64}', assets[0].get('digest') or ''):
    sys.exit('Missing or invalid release digest for ' + sys.argv[2])
print(assets[0]['digest'][7:])
PY
}
record_checksums() {
    local name=$1 key=$2 archive=$3 binary=$4
    local -A checksums=()
    source "$_installer_library_dir/../metadata/$name.sh"
    [[ ! ${checksums[archive/$key]+present} || ${checksums[archive/$key]} == "$archive" ]] || _installer_fail "Conflicting archive metadata: $name $key"
    [[ ! ${checksums[binary/$key]+present} || ${checksums[binary/$key]} == "$binary" ]] || _installer_fail "Conflicting binary metadata: $name $key"
    if [[ ! ${checksums[archive/$key]+present} || ! ${checksums[binary/$key]+present} ]]; then
        printf '\nchecksums[archive/%s]=%s\nchecksums[binary/%s]=%s\n' "$key" "$archive" "$key" "$binary" >> "$_installer_library_dir/../metadata/$name.sh"
    fi
}
write_version_pin() {
    local name=$1 value=$2
    printf '%s\n' "$value" > "$_installer_library_dir/../pins/.$name.tmp"
    mv -fT -- "$_installer_library_dir/../pins/.$name.tmp" "$_installer_library_dir/../pins/$name"
}
