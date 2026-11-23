kind=opt
repo=adoptium/temurin25-binaries
url=recorded
root='*'
links='bin/*'
executable=java
version_scheme=jdk-jep322
license=gpl-2.0-classpath
strategy='Eclipse Temurin; verified package in opt; entry points in bin'

# Versions follow JEP 322 and may have four parts (25.0.5.1); GA releases are recorded as 25.0.0. Temurin archive
# names carry a build number, so the download URL is recorded with the checksum.

tool_validate() {
    java_is_installed "$1" "$2"
}

# Adoptium's `semver` cannot hold a fourth part (25.0.5.1+2 is 25.0.5+100000002), so the version comes from the
# numeric fields and must agree with `openjdk_version`, the release name, the package name and the download link.
tool_latest() {
    local staging=$1 major minor security patch build openjdk release package link short
    local api='https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
    _installer_download "$api" "$staging/release.json"
    _installer_require jq
    read -r major minor security patch build openjdk release package link 'discovered[linux-x64]' < <(jq -r '
        [.[] | .binary as $b | select($b.image_type == "jdk" and $b.os == "linux" and $b.architecture == "x64"
        and $b.heap_size == "normal")] | if length == 1 then .[0] else error("ambiguous") end
        | [.version.major, .version.minor, .version.security, (.version.patch // 0), .version.build,
           .version.openjdk_version, .release_name, .binary.package.name, .binary.package.link, .binary.package.checksum]
        | map(tostring) | join(" ")' "$staging/release.json") || true
    [[ ${major:-} == 25 && ${minor:-} =~ ^[0-9]+$ && ${security:-} =~ ^[0-9]+$ && ${patch:-} =~ ^[0-9]+$ &&
        ${build:-} =~ ^[0-9]+$ ]] || _installer_fail 'Cannot identify Temurin Java 25 release.'
    short=$(jdk_display_version "$major.$minor.$security.$patch")
    version=$(jdk_recorded_version "$short")
    [[ ($openjdk == "$short+$build" || $openjdk == "$short+$build-"*) && $release == "jdk-$short+$build" &&
        $package == "OpenJDK25U-jdk_x64_linux_hotspot_${short}_$build.tar.gz" &&
        $link == "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-$short%2B$build/$package" &&
        ${discovered[linux-x64]} =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid Temurin release metadata.'
    discovered_url[linux-x64]=$link
    provenance_url=$api
    provenance_peer="$staging/release.json.peer"
}

tool_license() {
    local root
    root=$(tar -tzf "$3" | head -n 1) || true
    root=${root%%/*}
    [[ $root =~ ^jdk-25(\.[0-9]+){0,4}\+[0-9]+$ ]] || _installer_fail 'Unexpected Java archive layout.'
    tar -xzOf "$3" "$root/legal/java.base/LICENSE" > "$2" || _installer_fail 'Cannot extract Java license.'
}
