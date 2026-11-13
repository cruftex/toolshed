#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Codex supports Linux x86_64 only.'
stage_directory metadata
_installer_download https://api.github.com/repos/openai/codex/releases/latest "$metadata/release.json"
read -r version checksum < <(python3 - "$metadata/release.json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    release = json.load(f)
tag = release['tag_name']
if not re.fullmatch(r'rust-v[0-9]+\.[0-9]+\.[0-9]+', tag) or release['draft'] or release['prerelease']:
    sys.exit('Invalid Codex release metadata')
assets = [a for a in release['assets'] if a['name'] == 'codex-x86_64-unknown-linux-musl.tar.gz']
if len(assets) != 1 or not re.fullmatch(r'sha256:[0-9a-f]{64}', assets[0]['digest'] or ''):
    sys.exit('Invalid Codex release checksum')
print(tag[6:], assets[0]['digest'][7:])
PY
) || _installer_fail 'Cannot parse Codex release metadata.'
[[ ${version:-} && ${checksum:-} ]] || _installer_fail 'Cannot parse Codex release metadata.'
asset=codex-x86_64-unknown-linux-musl
archive="$DOWNLOAD_DIR/codex/$version/$asset.tar.gz"
download_verified "https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz" "$checksum" "$archive"
_installer_require tar sha256sum
stage_directory staging
tar -xOzf "$archive" "$asset" > "$staging/binary" || _installer_fail 'Cannot extract Codex.'
[[ -s $staging/binary ]] || _installer_fail 'Extracted Codex is empty.'
chmod 755 "$staging/binary"
binary_checksum=$(sha256sum < "$staging/binary")
if ! binary_is_installed codex "${binary_checksum%% *}"; then
    verify_version "$staging/binary" "codex-cli $version"
    install_binary "$staging/binary" codex
fi
printf 'Codex %s is installed in %s\n' "$version" "$DEST_BIN_DIR"
