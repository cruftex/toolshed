#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=$(read_version_pin java25)
platform=$(platform_string)
source "$_installer_library_dir/../metadata/java25.sh"
checksum=${checksums[archive/$version/$platform]:-}
[[ $checksum ]] || _installer_fail "No pinned Java checksums for $version/$platform."
jdk_home="$TOOLSHED_OPT_DIR/java25/$version"
if ! java_is_installed "$jdk_home" "$version"; then
    [[ ! -e $jdk_home && ! -L $jdk_home ]] || _installer_fail "Incomplete Java installation: $jdk_home"
    url="https://download.oracle.com/java/25/archive/jdk-${version}_linux-x64_bin.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "$checksum" "$archive"
    _installer_require tar mkdir mv
    mkdir -p -- "$TOOLSHED_OPT_DIR/java25"
    stage_directory staging "$TOOLSHED_OPT_DIR/java25"
    tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Java archive.'
    java_is_installed "$staging/jdk-$version" "$version" || _installer_fail "Java $version validation failed."
    [[ ! -e $jdk_home && ! -L $jdk_home ]] || _installer_fail "Java destination appeared during staging: $jdk_home"
    mv -T -- "$staging/jdk-$version" "$jdk_home"
fi
for executable in "$jdk_home"/bin/*; do
    [[ -f $executable && -x $executable ]] || continue
    install_symlink "$executable" "${executable##*/}"
done
printf 'Java %s is installed in %s\n' "$version" "$jdk_home"
