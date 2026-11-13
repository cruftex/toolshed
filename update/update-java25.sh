#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/install.sh"
source "$root/lib/update.sh"
[[ $(platform_string) == linux-x64 ]] || _installer_fail 'Java update supports Linux x86_64 only.'
_installer_require python3 sha256sum tar
stage_directory staging
_installer_download https://www.oracle.com/java/technologies/downloads/ "$staging/downloads.html"
version=$(python3 - "$staging/downloads.html" <<'PY'
import re, sys
from pathlib import Path
html = Path(sys.argv[1]).read_text()
matches = re.findall(r'<h3\s+id="java25"[^>]*>\s*Java SE Development Kit (25\.\d+\.\d+)(?:\.\d+)* downloads\s*</h3>', html)
if len(matches) != 1:
    sys.exit('Cannot identify Oracle Java 25 release')
print(matches[0])
PY
)
url="https://download.oracle.com/java/25/archive/jdk-${version}_linux-x64_bin.tar.gz"
_installer_download "$url.sha256" "$staging/checksum"
checksum=$(cat "$staging/checksum")
[[ $checksum =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Invalid Oracle checksum.'
archive="$DOWNLOAD_DIR/java25/$version/jdk-$version-linux-x64.tar.gz"
download_verified "$url" "$checksum" "$archive"
tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Java archive.'
java_is_installed "$staging/jdk-$version" "$version" || _installer_fail "Java $version validation failed."
source "$root/metadata/java25.sh"
key="archive/$version/linux-x64"
[[ ! ${checksums[$key]+present} || ${checksums[$key]} == "$checksum" ]] || _installer_fail "Conflicting Java checksum: $version"
if [[ ! ${checksums[$key]+present} ]]; then
    printf '\nchecksums[%s]=%s\n' "$key" "$checksum" >> "$root/metadata/java25.sh"
fi
write_version_pin java25 "$version"
"$root/install/install-java25.sh"
