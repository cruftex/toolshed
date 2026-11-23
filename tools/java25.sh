kind=opt
repo=adoptium/temurin25-binaries
url=recorded
root='*'
links='bin/*'
executable=java
license=gpl-2.0-classpath
strategy='Eclipse Temurin; verified package in opt; entry points in bin'

# Temurin archive names carry a build number, so the download URL is recorded with the checksum.

tool_validate() {
    java_is_installed "$1" "$2"
}

tool_latest() {
    local staging=$1 semver package link build api='https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
    _installer_download "$api" "$staging/release.json"
    _installer_require jq
    read -r semver package link 'discovered[linux-x64]' < <(jq -r '[.[] | .binary as $b | select($b.image_type == "jdk" and $b.os == "linux"
        and $b.architecture == "x64" and $b.heap_size == "normal")] | if length == 1 then .[0] else error("ambiguous") end
        | "\(.version.semver) \(.binary.package.name) \(.binary.package.link) \(.binary.package.checksum)"' "$staging/release.json") || true
    [[ ${semver:-} =~ ^(25\.[0-9]+\.[0-9]+)\+([0-9]+)(\.[0-9]+)*(\.LTS)?$ ]] || _installer_fail 'Cannot identify Temurin Java 25 release.'
    version=${BASH_REMATCH[1]} build=${BASH_REMATCH[2]}
    [[ $package == "OpenJDK25U-jdk_x64_linux_hotspot_${version}_$build.tar.gz" &&
        $link == "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-$version%2B$build/$package" &&
        ${discovered[linux-x64]} =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid Temurin release metadata.'
    discovered_url[linux-x64]=$link
    provenance_url=$api
    provenance_peer="$staging/release.json.peer"
}

tool_license() {
    local root
    root=$(tar -tzf "$3" | head -n 1) || true
    root=${root%%/*}
    [[ $root =~ ^jdk-25\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || _installer_fail 'Unexpected Java archive layout.'
    tar -xzOf "$3" "$root/legal/java.base/LICENSE" > "$2" || _installer_fail 'Cannot extract Java license.'
}
