kind=opt
repo=adoptium/temurin8-binaries
url='https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u{update}-b{build}/OpenJDK8U-jdk_x64_linux_hotspot_8u{update}b{build}.tar.gz'
root='jdk8u{update}-b{build}'
links=
detect=dirs
version_prefix=8.0.
license=gpl-2.0-classpath
strategy='Eclipse Temurin; verified package in opt; activate with profile'

# Versions are recorded as 8.0.UPDATE (Adoptium's semver); archive names carry the update and a two-digit build
# number, pinned per version in metadata/java8-builds. No entry points are linked, so Java 25's links stay.
tool_vars() {
    local update
    [[ $1 =~ ^8\.0\.([0-9]+)$ ]] || _installer_fail "Invalid Java 8 version: $1"
    update=${BASH_REMATCH[1]}
    [[ ${build:-} ]] || build=$(awk -v v="$1" '$1 == v { print $2 }' "$toolshed_root/metadata/java8-builds")
    [[ $build =~ ^[0-9]{2}$ ]] || _installer_fail "No pinned Temurin build for Java $1."
    tool[url]=${tool[url]//\{update\}/$update}
    tool[root]=${tool[root]//\{update\}/$update}
}

tool_validate() {
    java8_is_installed "$1" "$2"
}

tool_latest() {
    local staging=$1 semver package api='https://api.adoptium.net/v3/assets/latest/8/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
    _installer_download "$api" "$staging/release.json"
    _installer_require jq
    read -r semver package 'discovered[linux-x64]' < <(jq -r '[.[] | .binary as $b | select($b.image_type == "jdk" and $b.os == "linux"
        and $b.architecture == "x64" and $b.heap_size == "normal")] | if length == 1 then .[0] else error("ambiguous") end
        | "\(.version.semver) \(.binary.package.name) \(.binary.package.checksum)"' "$staging/release.json") || true
    [[ ${semver:-} =~ ^(8\.0\.([0-9]+))\+([0-9]+)(\.[0-9]+)*(\.LTS)?$ ]] || _installer_fail 'Cannot identify Temurin Java 8 release.'
    version=${BASH_REMATCH[1]}
    printf -v build '%02d' "$((10#${BASH_REMATCH[3]}))"
    [[ $package == "OpenJDK8U-jdk_x64_linux_hotspot_8u${version##*.}b$build.tar.gz" && ${discovered[linux-x64]} =~ ^[0-9a-f]{64}$ ]] ||
        _installer_fail 'Invalid Temurin release metadata.'
    provenance_url=$api
    provenance_peer="$staging/release.json.peer"
}

tool_license() {
    tar -xzOf "$3" "$(tool_expand "${tool[root]}" "$1")/LICENSE" > "$2" || _installer_fail 'Cannot extract Java license.'
}

tool_after_discovery() {
    grep -qxF "$1 $build" "$toolshed_root/metadata/java8-builds" 2>/dev/null ||
        printf '%s %s\n' "$1" "$build" >> "$toolshed_root/metadata/java8-builds"
}
