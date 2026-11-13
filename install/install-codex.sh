#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$(cat "$root/pins/codex")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _installer_fail "Invalid Codex version pin."
platform=$(platform_string)
key="$version/$platform"
stage_codex_component() {
    local name=$1 asset archive
    source "$root/metadata/$name.sh"
    local -A archive_sha256=() binary_sha256=()
    archive_sha256[$key]=${checksums[archive/$key]:-}
    binary_sha256[$key]=${checksums[binary/$key]:-}
    [[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] ||
        _installer_fail "No pinned $name checksums for $key."
    binary_is_installed "$name" "${binary_sha256[$key]}" && return
    asset="$name-x86_64-unknown-linux-musl"
    archive="$DOWNLOAD_DIR/codex/$version/$asset.tar.gz"
    download_verified "https://github.com/openai/codex/releases/download/rust-v$version/$asset.tar.gz" "${archive_sha256[$key]}" "$archive"
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
printf 'Codex %s and code mode host are installed in %s\n' "$version" "$DEST_BIN_DIR"
