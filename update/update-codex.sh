#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Codex update supports Linux x86_64 only.'
_installer_require python3 tar sha256sum
stage_directory staging
release_info openai/codex rust-v "$staging/release"
version=$(cat "$staging/release")
for index in 0 1; do
    if (( index == 0 )); then name=codex; else name=codex-code-mode-host; fi
    asset="$name-x86_64-unknown-linux-musl"
    archive="$DOWNLOAD_DIR/codex/$version/$asset.tar.gz"
    archive_sha=$(release_asset_digest "$staging/release" "$asset.tar.gz")
    download_verified "https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz" "$archive_sha" "$archive"
    printf '%s\n' "$archive_sha" > "$staging/$name.archive-sha256"
    tar -xOzf "$archive" "$asset" > "$staging/$name" || _installer_fail "Cannot extract $name."
    [[ -s $staging/$name ]] || _installer_fail "Empty $name executable."
    chmod 755 "$staging/$name"
    sha256sum < "$staging/$name" | cut -d ' ' -f 1 > "$staging/$name.sha256"
done
verify_version "$staging/codex" "codex-cli $version"
for name in codex codex-code-mode-host; do
    record_checksums "$name" "$version/linux-x64" "$(cat "$staging/$name.archive-sha256")" "$(cat "$staging/$name.sha256")"
done
write_version_pin codex "$version"
"$root/install/install-codex.sh"
