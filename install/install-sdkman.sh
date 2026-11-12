#!/usr/bin/env bash
# Releases: https://github.com/sdkman/sdkman-cli/releases
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

declare -Ar archive_sha256=(
    [5.24.0/linux-x64]=b765ef213c7b3dd731815e42f398b6e2eef1053b38d32ecc09a9f6d51c8ee948
    [0.8.0/linux-x64]=91cc56bce077fb605172d6bb3182ab2a1b1711d64f12a8bbb1910dc11d561397
)
version=5.24.0
native_version=0.8.0
platform=$(platform_string)
[[ ${archive_sha256[$version/$platform]:-} && ${archive_sha256[$native_version/$platform]:-} ]] ||
    _installer_fail "No pinned SDKMAN checksums for $platform."
bootstrap_sdkman "$version" "$native_version" "$platform" \
    "${archive_sha256[$version/$platform]}" "${archive_sha256[$native_version/$platform]}"
printf 'SDKMAN is available in %s\n' "$SDKMAN_DIR"
