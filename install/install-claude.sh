#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

base_url=https://downloads.claude.ai/claude-code-releases
platform=$(platform_string)
platform=${platform/aarch64/arm64}
case $platform in linux-x64|linux-arm64) ;; *) _installer_fail "Unsupported Claude platform: $platform" ;; esac
resolve_latest_version "$base_url/latest" version
cache="$DOWNLOAD_DIR/claude/$version"
download_signed_manifest "$base_url/$version/manifest.json" https://downloads.claude.ai/keys/claude-code.asc \
    31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE "$cache/manifest"
checksum=$(manifest_checksum "$cache/manifest/manifest.json" "$version" "$platform")

if ! binary_is_installed claude "$checksum"; then
    download_verified "$base_url/$version/$platform/claude" "$checksum" "$cache/$platform/claude"
    stage_executable "$cache/$platform/claude" binary
    verify_sha256 "$binary" "$checksum"
    verify_version "$binary" "$version (Claude Code)"
    install_binary "$binary" claude
fi
set_json_env "$HOME/.claude/settings.json" DISABLE_UPDATES 1
printf 'Claude Code %s is installed in %s; built-in updates disabled.\n' "$version" "$DEST_BIN_DIR"
