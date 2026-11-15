#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
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
archive=$(cache_path "$url")
download_verified "$url" "$checksum" "$archive"
tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract Java archive.'
java_is_installed "$staging/jdk-$version" "$version" || _installer_fail "Java $version validation failed."
key="$version/linux-x64"
record_checksums java25 "$key" "$checksum"
record_provenance "java25" "$version/linux-x64" "$url.sha256" "$staging/checksum.peer"
printf "%s\n" "$version"
