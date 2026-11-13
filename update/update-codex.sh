#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Codex update supports Linux x86_64 only.'
_installer_require python3 tar sha256sum
stage_directory staging
_installer_download https://api.github.com/repos/openai/codex/releases/latest "$staging/release.json"
python3 - "$staging/release.json" > "$staging/release" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    release = json.load(f)
tag = release['tag_name']
if not re.fullmatch(r'rust-v[0-9]+\.[0-9]+\.[0-9]+', tag) or release['draft'] or release['prerelease']:
    sys.exit('Invalid Codex release metadata')
print(tag[6:])
for name in ('codex', 'codex-code-mode-host'):
    asset = name + '-x86_64-unknown-linux-musl.tar.gz'
    matches = [a for a in release['assets'] if a['name'] == asset]
    if len(matches) != 1 or not re.fullmatch(r'sha256:[0-9a-f]{64}', matches[0].get('digest') or ''):
        sys.exit('Missing or invalid release digest for ' + asset)
    print(matches[0]['digest'][7:])
PY
mapfile -t release < "$staging/release"
version=${release[0]}
for index in 0 1; do
    if (( index == 0 )); then name=codex; else name=codex-code-mode-host; fi
    asset="$name-x86_64-unknown-linux-musl"
    archive="$DOWNLOAD_DIR/codex/$version/$asset.tar.gz"
    download_verified "https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz" "${release[index+1]}" "$archive"
    tar -xOzf "$archive" "$asset" > "$staging/$name" || _installer_fail "Cannot extract $name."
    [[ -s $staging/$name ]] || _installer_fail "Empty $name executable."
    chmod 755 "$staging/$name"
    sha256sum < "$staging/$name" | cut -d ' ' -f 1 > "$staging/$name.sha256"
done
verify_version "$staging/codex" "codex-cli $version"
# Validate existing entries before changing either metadata file.
for index in 0 1; do
    if (( index == 0 )); then name=codex; else name=codex-code-mode-host; fi
    (
        source "$root/metadata/$name.sh"
        key="$version/linux-x64"
        binary=$(cat "$staging/$name.sha256")
        [[ ! ${checksums[archive/$key]+present} || ${checksums[archive/$key]} == "${release[index+1]}" ]] || _installer_fail "Conflicting archive metadata for $name $key."
        [[ ! ${checksums[binary/$key]+present} || ${checksums[binary/$key]} == "$binary" ]] || _installer_fail "Conflicting binary metadata for $name $key."
    )
done
for index in 0 1; do
    if (( index == 0 )); then name=codex; else name=codex-code-mode-host; fi
    key="$version/linux-x64"
    binary=$(cat "$staging/$name.sha256")
    if ! ( source "$root/metadata/$name.sh"; [[ ${checksums[archive/$key]+present} && ${checksums[binary/$key]+present} ]] ); then
        printf '\nchecksums[archive/%s]=%s\nchecksums[binary/%s]=%s\n' "$key" "${release[index+1]}" "$key" "$binary" >> "$root/metadata/$name.sh"
    fi
done
printf '%s\n' "$version" > "$root/pins/.codex.tmp"
mv -fT -- "$root/pins/.codex.tmp" "$root/pins/codex"
"$root/install/install-codex.sh"
