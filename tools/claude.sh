kind=bin
repo=anthropics/claude-code
tag=v
archive=binary
url=https://downloads.claude.ai/claude-code-releases/{version}/{platform}/claude
platforms='linux-x64 linux-aarch64'
platform_names='linux-aarch64=linux-arm64'
version_match='{version} (Claude Code)'
license=proprietary
license_file=LICENSE.md
strategy='Verified executable in bin; checksums from the signed manifest'
base_url=https://downloads.claude.ai/claude-code-releases
key_url=https://downloads.claude.ai/keys/claude-code.asc
fingerprint=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# Discovery: the latest release's checksums come from its versioned manifest, authenticated with Anthropic's
# pinned key; the generic flow then downloads and verifies every platform's executable and records them.
tool_latest() {
    local cache platform
    resolve_latest_version "${tool[base_url]}/latest" version
    cache=$(cache_path "${tool[base_url]}/$version")
    download_signed_manifest "${tool[base_url]}/$version/manifest.json" "${tool[key_url]}" "${tool[fingerprint]}" "$cache/manifest"
    for platform in ${tool[platforms]}; do
        discovered[$platform]=$(manifest_checksum "$cache/manifest/manifest.json" "$version" "$(tool_expand '{platform}' "$version" "$platform")")
    done
    provenance_url="${tool[base_url]}/$version/manifest.json"
    provenance_peer="$cache/manifest/manifest.json.peer"
}

# Upgrades happen through the verified installer only.
tool_after_install() {
    set_json_env "$TOOLSHED_CLAUDE_SETTINGS" DISABLE_UPDATES 1
    printf 'Claude Code built-in updates disabled in %s.\n' "$TOOLSHED_CLAUDE_SETTINGS"
}
