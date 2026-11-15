#!/usr/bin/env bash
set -euo pipefail
unset TOOLSHED_OVERRIDE_TOOL_VERSION
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
base_url=https://downloads.claude.ai/claude-code-releases
platform=$(platform_string)
platform=${platform/aarch64/arm64}
case $platform in linux-x64|linux-arm64) ;; *) _installer_fail "Unsupported Claude platform: $platform" ;; esac
resolve_latest_version "$base_url/latest" version
cache=$(cache_path "$base_url/$version")
download_signed_manifest "$base_url/$version/manifest.json" https://downloads.claude.ai/keys/claude-code.asc \
    31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE "$cache/manifest"
checksum=$(manifest_checksum "$cache/manifest/manifest.json" "$version" "$platform")
download_verified "$base_url/$version/$platform/claude" "$checksum" "$cache/$platform/claude"
stage_executable "$cache/$platform/claude" binary
verify_sha256 "$binary" "$checksum"
verify_version "$binary" "$version (Claude Code)"
registry="$root/metadata/claude-versions"
touch "$registry"
if ! grep -Fxq -- "$version" "$registry"; then
    printf '%s\n' "$version" >> "$registry"
fi
record_provenance "claude" "$version/$platform" "$base_url/$version/manifest.json" "$cache/manifest/manifest.json.peer"
printf '%s\n' "$version"
