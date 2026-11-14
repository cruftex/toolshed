#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"
version=$(select_install_version go "$@")
platform=$(platform_string)
source "$_installer_library_dir/../metadata/go.sh"
checksum=${checksums[archive/$version/$platform]:-}
[[ $checksum ]] || _installer_fail "No pinned Go archive for $version/$platform."
go_home="$TOOLSHED_OPT_DIR/go/$version"
if [[ ! -e $go_home && ! -L $go_home ]]; then
    url="https://go.dev/dl/go${version}.linux-amd64.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "$checksum" "$archive"
    _installer_require tar mkdir mv sed grep
    mkdir -p -- "$TOOLSHED_OPT_DIR/go"
    stage_directory staging "$TOOLSHED_OPT_DIR/go"
    tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Go archive.'
    grep -qx "GOTOOLCHAIN=auto" "$staging/go/go.env" || _installer_fail 'Unexpected Go toolchain configuration.'
    sed -i 's/^GOTOOLCHAIN=auto$/GOTOOLCHAIN=local/' "$staging/go/go.env"
    verify_go_toolchain "$staging/go" "$version"
    [[ ! -e $go_home && ! -L $go_home ]] || _installer_fail "Go destination appeared during staging: $go_home"
    mv -T -- "$staging/go" "$go_home"
else
    verify_go_toolchain "$go_home" "$version"
fi
install_symlink "$go_home/bin/go" go
install_symlink "$go_home/bin/gofmt" gofmt
printf 'Go %s is installed in %s\n' "$version" "$go_home"
