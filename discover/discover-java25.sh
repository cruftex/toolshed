#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Java discovery supports Linux x86_64 only.'
_installer_require python3 sha256sum tar
stage_directory staging
api='https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
_installer_download "$api" "$staging/release.json"
read -r version build checksum < <(python3 - "$staging/release.json" <<'PY'
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
[[ ${version:-} =~ ^25\.[0-9]+\.[0-9]+$ && ${build:-} =~ ^[0-9]+$ && ${checksum:-} =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid Temurin release metadata.'
key="$version/linux-x64"
check_recorded_checksums java25 "$key" "$checksum"
url="https://github.com/adoptium/temurin25-binaries/releases/download/jdk-$version%2B$build/OpenJDK25U-jdk_x64_linux_hotspot_${version}_$build.tar.gz"
archive=$(cache_path "$url")
download_verified "$url" "$checksum" "$archive"
tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Java archive.'
java_is_installed "$staging/jdk-$version+$build" "$version" || _installer_fail "Java $version validation failed."
record_checksums java25 "$key" "$checksum"
tar -xzOf "$archive" "jdk-$version+$build/legal/java.base/LICENSE" > "$staging/license.txt" || _installer_fail 'Cannot extract Java license.'
record_license java25 "$version" "$staging/license.txt" gpl-2.0-classpath
grep -qxF "$version $build" "$root/metadata/java25-builds" || printf '%s %s\n' "$version" "$build" >> "$root/metadata/java25-builds"
record_provenance java25 "$key" "$api" "$staging/release.json.peer"
printf '%s\n' "$version"
