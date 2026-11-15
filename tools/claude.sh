kind=scripted
repo=anthropics/claude-code
tag=v
archive=binary
license=proprietary
license_file=LICENSE.md
strategy='Signed manifest; executable in bin'
base_url=https://downloads.claude.ai/claude-code-releases
key_url=https://downloads.claude.ai/keys/claude-code.asc
fingerprint=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# Claude's platform names use arm64, and only Linux builds are supported here.
claude_platform() {
    local platform
    platform=$(platform_string)
    platform=${platform/aarch64/arm64}
    case $platform in linux-x64|linux-arm64) ;; *) _installer_fail "Unsupported Claude platform: $platform" ;; esac
    printf '%s\n' "$platform"
}

# Read the executable's checksum from the authenticated, versioned manifest; call directly.
claude_checksum() {
    local version=$1 platform=$2 cache
    local -n _claude_checksum=$3
    cache=$(cache_path "${tool[base_url]}/$version")
    download_signed_manifest "${tool[base_url]}/$version/manifest.json" "${tool[key_url]}" "${tool[fingerprint]}" "$cache/manifest"
    _claude_checksum=$(manifest_checksum "$cache/manifest/manifest.json" "$version" "$platform")
}

# Download and verify the executable before it is executed; call directly so cleanup tracks it.
claude_stage() {
    local version=$1 platform=$2 checksum=$3 cache
    local -n _claude_binary=$4
    cache=$(cache_path "${tool[base_url]}/$version")
    download_verified "${tool[base_url]}/$version/$platform/claude" "$checksum" "$cache/$platform/claude"
    stage_executable "$cache/$platform/claude" _claude_binary
    verify_sha256 "$_claude_binary" "$checksum"
    verify_version "$_claude_binary" "$version (Claude Code)"
}

tool_install() {
    local version platform binary checksum
    version=$(select_tool_version "$@")
    platform=$(claude_platform)
    claude_checksum "$version" "$platform" checksum
    if ! binary_is_installed claude "$checksum"; then
        warn_if_modified claude "$checksum"
        claude_stage "$version" "$platform" "$checksum" binary
        install_binary "$binary" claude
    fi
    set_json_env "$TOOLSHED_CLAUDE_SETTINGS" DISABLE_UPDATES 1
    printf 'Claude Code %s is installed in %s; built-in updates disabled.\n' "$version" "$TOOLSHED_BIN_DIR"
    print_tool_license "$version"
}

tool_discover() {
    local version platform binary checksum registry cache
    platform=$(claude_platform)
    resolve_latest_version "${tool[base_url]}/latest" version
    claude_checksum "$version" "$platform" checksum
    claude_stage "$version" "$platform" "$checksum" binary
    registry="$toolshed_root/metadata/claude-versions"
    touch "$registry"
    grep -Fxq -- "$version" "$registry" || printf '%s\n' "$version" >> "$registry"
    record_tool_license claude "$version"
    cache=$(cache_path "${tool[base_url]}/$version")
    record_provenance claude "$version/$platform" "${tool[base_url]}/$version/manifest.json" "$cache/manifest/manifest.json.peer"
    printf '%s\n' "$version"
}
