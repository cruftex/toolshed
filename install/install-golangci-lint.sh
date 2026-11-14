#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version golangci-lint "$@")
platform=$(platform_string)
key="$version/$platform"
load_binary_checksums golangci-lint "$key"
[[ ${archive_sha256[$key]:-} && ${binary_sha256[$key]:-} ]] || _installer_fail "No pinned golangci-lint checksums for $key."
url="https://github.com/golangci/golangci-lint/releases/download/v$version/golangci-lint-${version}-linux-amd64.tar.gz"
install_release_binary golangci-lint "$version" "$url" "golangci-lint-${version}-linux-amd64/golangci-lint" "${archive_sha256[$key]}" "${binary_sha256[$key]}"
printf 'golangci-lint %s is installed in %s\n' "$version" "$TOOLSHED_BIN_DIR"
