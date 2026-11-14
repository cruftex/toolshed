#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(read_version_pin codex)
platform=$(platform_string)
key="$version/$platform"
stage_codex_component() {
    local name=$1 asset archive
    load_binary_checksums "$name" "$key"
    [[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] ||
        _installer_fail "No pinned $name checksums for $key."
    binary_is_installed "$name" "${binary_sha256[$key]}" && return
    asset="$name-x86_64-unknown-linux-musl"
    local url="https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "${archive_sha256[$key]}" "$archive"
    tar -xOzf "$archive" "$asset" > "$staging/$name" || _installer_fail "Cannot extract $name."
    verify_sha256 "$staging/$name" "${binary_sha256[$key]}"
    chmod 755 "$staging/$name"
}
_installer_require tar
stage_directory staging
stage_codex_component codex
stage_codex_component codex-code-mode-host
if [[ -e $staging/codex ]]; then verify_version "$staging/codex" "codex-cli $version"; fi
if [[ -e $staging/codex-code-mode-host ]]; then install_binary "$staging/codex-code-mode-host" codex-code-mode-host; fi
if [[ -e $staging/codex ]]; then install_binary "$staging/codex" codex; fi
printf 'Codex %s and code mode host are installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
