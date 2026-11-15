#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=$(select_install_version java25 "$@")
platform=$(platform_string)
load_archive_checksum java25 "$version" "$platform" || _installer_fail "No pinned Java checksums for $version/$platform."
checksum=${archive_sha256[$version/$platform]}
build=$(awk -v v="$version" '$1 == v { print $2 }' "$_installer_library_dir/../metadata/java25-builds")
[[ $build =~ ^[0-9]+$ ]] || _installer_fail "No pinned Temurin build for Java $version."
jdk_home="$TOOLSHED_OPT_DIR/java25/$version"
if ! java_is_installed "$jdk_home" "$version"; then
    [[ ! -e $jdk_home && ! -L $jdk_home ]] || _installer_fail "Incomplete Java installation: $jdk_home"
    url="https://github.com/adoptium/temurin25-binaries/releases/download/jdk-$version%2B$build/OpenJDK25U-jdk_x64_linux_hotspot_${version}_$build.tar.gz"
    archive=$(cache_path "$url")
    download_verified "$url" "$checksum" "$archive"
    _installer_require tar mkdir mv
    mkdir -p -- "$TOOLSHED_OPT_DIR/java25"
    stage_directory staging "$TOOLSHED_OPT_DIR/java25"
    tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Java archive.'
    java_is_installed "$staging/jdk-$version+$build" "$version" || _installer_fail "Java $version validation failed."
    [[ ! -e $jdk_home && ! -L $jdk_home ]] || _installer_fail "Java destination appeared during staging: $jdk_home"
    mv -T -- "$staging/jdk-$version+$build" "$jdk_home"
fi
for executable in "$jdk_home"/bin/*; do
    [[ -f $executable && -x $executable ]] || continue
    install_symlink "$executable" "${executable##*/}"
done
printf 'Java %s is installed in %s\n' "$version" "$jdk_home"
