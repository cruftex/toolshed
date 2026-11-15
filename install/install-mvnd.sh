#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version mvnd "$@")
platform=$(platform_string)
load_archive_checksum mvnd "$version" "$platform" || _installer_fail "No pinned Maven Daemon archive for $version/$platform."
checksum=${archive_sha256[$version/$platform]}
asset="maven-mvnd-$version-linux-amd64"
url="https://archive.apache.org/dist/maven/mvnd/$version/$asset.tar.gz"
install_maven_package mvnd "$version" "$url" "$checksum" "$asset" mvnd "Apache Maven Daemon (mvnd) $version"
