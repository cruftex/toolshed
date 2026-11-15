kind=scripted
repo=openai/codex
tag=rust-v
components=host=codex-code-mode-host
license=apache-2.0
strategy='Verified executables in bin'

# Codex ships two executables, each in its own archive: codex and the code mode host (component "host").
codex_url() {
    printf 'https://github.com/openai/codex/releases/download/rust-v%s/%s-x86_64-unknown-linux-musl.tar.gz' "$1" "$2"
}

tool_install() {
    local version platform name component url archive binary
    local -A archive_sha256=() binary_sha256=() staged=()
    version=$(select_tool_version "$@")
    platform=$(platform_string)
    for name in codex codex-code-mode-host; do
        component=''
        [[ $name == codex ]] || component=host
        archive_sha256[$name]=$(tool_checksum "$version" "$platform" "$component") ||
            _installer_fail "No pinned $name checksum for $version/$platform."
        url=$(codex_url "$version" "$name")
        archive=$(cache_path "$url")
        download_verified "$url" "${archive_sha256[$name]}" "$archive"
        extract_tar_member "$archive" "$name-x86_64-unknown-linux-musl" binary
        binary_sha256[$name]=$(sha256sum < "$binary")
        binary_sha256[$name]=${binary_sha256[$name]%% *}
        if ! binary_is_installed "$name" "${binary_sha256[$name]}"; then
            warn_if_modified "$name" "${binary_sha256[$name]}"
            staged[$name]=$binary
        fi
    done
    [[ -z ${staged[codex]:-} ]] || verify_version "${staged[codex]}" "codex-cli $version"
    for name in codex-code-mode-host codex; do
        [[ -z ${staged[$name]:-} ]] || install_binary "${staged[$name]}" "$name"
    done
    printf 'Codex %s and code mode host are installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
    print_tool_license "$version"
}

tool_discover() {
    local version staging name url archive binary
    local -A checksums=()
    _installer_require python3 jq tar sha256sum
    [[ $(platform_string) == linux-x64 ]] || _installer_fail 'Codex discovery supports Linux x86_64 only.'
    stage_directory staging
    github_release_info openai/codex rust-v "$staging/release"
    version=$(cat "$staging/release")
    for name in codex codex-code-mode-host; do
        url=$(codex_url "$version" "$name")
        checksums[$name]=$(github_release_asset_digest "$staging/release" "${url##*/}")
        archive=$(cache_path "$url")
        download_verified "$url" "${checksums[$name]}" "$archive"
        extract_tar_member "$archive" "$name-x86_64-unknown-linux-musl" binary
        [[ $name != codex ]] || verify_version "$binary" "codex-cli $version"
        check_recorded_checksums "$name" "$version/linux-x64" "${checksums[$name]}"
    done
    for name in codex codex-code-mode-host; do
        record_checksums "$name" "$version/linux-x64" "${checksums[$name]}"
        record_tool_license "$name" "$version"
        record_provenance "$name" "$version/linux-x64" "https://api.github.com/repos/openai/codex/releases/latest" "$staging/release.json.peer"
    done
    printf '%s\n' "$version"
}
