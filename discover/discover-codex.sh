#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Codex update supports Linux x86_64 only.'
_installer_require python3 tar sha256sum
stage_directory staging
github_release_info openai/codex rust-v "$staging/release"
version=$(cat "$staging/release")
for index in 0 1; do
    if (( index == 0 )); then name=codex; else name=codex-code-mode-host; fi
    asset="$name-x86_64-unknown-linux-musl"
    url="https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz"
    archive=$(cache_path "$url")
    archive_sha=$(github_release_asset_digest "$staging/release" "$asset.tar.gz")
    download_verified "$url" "$archive_sha" "$archive"
    printf '%s\n' "$archive_sha" > "$staging/$name.archive-sha256"
    tar -xOzf "$archive" "$asset" > "$staging/$name" || _installer_fail "Cannot extract $name."
    [[ -s $staging/$name ]] || _installer_fail "Empty $name executable."
    chmod 755 "$staging/$name"
done
verify_version "$staging/codex" "codex-cli $version"
for name in codex codex-code-mode-host; do
    check_recorded_checksums "$name" "$version/linux-x64" "$(cat "$staging/$name.archive-sha256")"
done
for name in codex codex-code-mode-host; do
    record_checksums "$name" "$version/linux-x64" "$(cat "$staging/$name.archive-sha256")"
done
for name in codex codex-code-mode-host; do
    record_github_license "$name" "$version" openai/codex "rust-v$version" LICENSE apache-2.0
done
for name in codex codex-code-mode-host; do
    record_provenance "$name" "$version/linux-x64" "https://api.github.com/repos/openai/codex/releases/latest" "$staging/release.json.peer"
done
printf "%s\n" "$version"
