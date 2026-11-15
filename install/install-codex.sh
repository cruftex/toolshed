#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(select_install_version codex "$@")
platform=$(platform_string)
key="$version/$platform"
declare -A archive_sha256=() binary_sha256=() install_required=()
for name in codex codex-code-mode-host; do
    component=''
    [[ $name != codex-code-mode-host ]] || component=host
    archive_sha256[$name]=$(python3 "$_installer_library_dir/artifact_metadata.py" checksum \
        "$_installer_library_dir/../metadata/artifacts/codex.psv" "$version" "$component/$platform/archive/tar.gz") ||
        _installer_fail "No pinned $name checksum for $key."
done
stage_codex_component() {
    local name=$1 asset archive
    asset="$name-x86_64-unknown-linux-musl"
    local url="https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "${archive_sha256[$name]}" "$archive"
    tar -xOzf "$archive" "$asset" > "$staging/$name" || _installer_fail "Cannot extract $name."
    [[ -s $staging/$name ]] || _installer_fail "Empty $name executable."
    chmod 755 "$staging/$name"
    binary_sha256[$name]=$(sha256sum < "$staging/$name"); binary_sha256[$name]=${binary_sha256[$name]%% *}
    if ! binary_is_installed "$name" "${binary_sha256[$name]}"; then
        warn_if_modified "$name" "${binary_sha256[$name]}"
        install_required[$name]=1
    fi
}
_installer_require tar
stage_directory staging
stage_codex_component codex
stage_codex_component codex-code-mode-host
if [[ ${install_required[codex]:-} ]]; then verify_version "$staging/codex" "codex-cli $version"; fi
for name in codex-code-mode-host codex; do
    if [[ ${install_required[$name]:-} ]]; then
        install_binary "$staging/$name" "$name"
    fi
done
printf 'Codex %s and code mode host are installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
