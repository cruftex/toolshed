kind=opt
repo=adoptium/temurin25-binaries
url='https://github.com/adoptium/temurin25-binaries/releases/download/jdk-{version}%2B{build}/OpenJDK25U-jdk_x64_linux_hotspot_{version}_{build}.tar.gz'
root='jdk-{version}+{build}'
links='bin/*'
executable=java
license=gpl-2.0-classpath
strategy='Eclipse Temurin; verified package in opt; entry points in bin'

# Temurin archive names carry a build number, pinned per version in metadata/java25-builds.
tool_vars() {
    [[ ${build:-} ]] || build=$(awk -v v="$1" '$1 == v { print $2 }' "$toolshed_root/metadata/java25-builds")
    [[ $build =~ ^[0-9]+$ ]] || _installer_fail "No pinned Temurin build for Java $1."
}

tool_validate() {
    java_is_installed "$1" "$2"
}

tool_latest() {
    local staging=$1 api='https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
    _installer_download "$api" "$staging/release.json"
    read -r version build 'discovered[linux-x64]' < <(python3 - "$staging/release.json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    assets = [a for a in json.load(f) if a['binary']['image_type'] == 'jdk' and a['binary']['os'] == 'linux'
              and a['binary']['architecture'] == 'x64' and a['binary']['heap_size'] == 'normal']
if len(assets) != 1:
    sys.exit('Cannot identify Temurin Java 25 release')
asset = assets[0]
match = re.fullmatch(r'(25\.\d+\.\d+)\+(\d+)(?:\.\d+)*(?:\.LTS)?', asset['version']['semver'])
package = asset['binary']['package']
if not match or not re.fullmatch(r'[0-9a-f]{64}', package['checksum']) or package['name'] != f'OpenJDK25U-jdk_x64_linux_hotspot_{match[1]}_{match[2]}.tar.gz':
    sys.exit('Invalid Temurin release metadata')
print(match[1], match[2], package['checksum'])
PY
)
    [[ ${version:-} =~ ^25\.[0-9]+\.[0-9]+$ && ${build:-} =~ ^[0-9]+$ ]] || _installer_fail 'Invalid Temurin release metadata.'
    provenance_url=$api
    provenance_peer="$staging/release.json.peer"
}

tool_license() {
    tar -xzOf "$3" "jdk-$1+$build/legal/java.base/LICENSE" > "$2" || _installer_fail 'Cannot extract Java license.'
}

tool_after_discovery() {
    grep -qxF "$1 $build" "$toolshed_root/metadata/java25-builds" ||
        printf '%s %s\n' "$1" "$build" >> "$toolshed_root/metadata/java25-builds"
}
