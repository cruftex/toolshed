#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version mvnd "$@")
platform=$(platform_string)
declare -A archive_sha256=([1.0.6/linux-x64]=88fd474fd3f21b33ec1e6a75950f6abbe493d63a5e2b429475f5230b3ee6cb24)
checksum=${archive_sha256[$version/$platform]:-}
[[ $checksum ]] || _installer_fail "No pinned Maven Daemon archive for $version/$platform."
asset="maven-mvnd-$version-linux-amd64"
url="https://archive.apache.org/dist/maven/mvnd/$version/$asset.tar.gz"
install_maven_package mvnd "$version" "$url" "$checksum" "$asset" mvnd "Apache Maven Daemon (mvnd) $version"
