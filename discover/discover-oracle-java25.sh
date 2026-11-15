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
record_checksums oracle-java25 "$key" "$checksum"
_installer_download https://www.oracle.com/downloads/licenses/no-fee-license.html "$staging/license.html"
python3 - "$staging/license.html" > "$staging/license.txt" <<'PY' || _installer_fail 'Cannot read Oracle license.'
import html.parser, sys
from pathlib import Path
class Text(html.parser.HTMLParser):
    skip = 0
    def __init__(self):
        super().__init__(); self.lines = []
    def handle_starttag(self, tag, attrs):
        self.skip += tag in ('script', 'style')
    def handle_endtag(self, tag):
        self.skip -= tag in ('script', 'style')
        if tag in ('p', 'li', 'h1', 'h2', 'h3', 'div', 'br'): self.lines.append('\n')
    def handle_data(self, data):
        if not self.skip: self.lines.append(' '.join(data.split()))
parser = Text(); parser.feed(Path(sys.argv[1]).read_text())
text = '\n'.join(line.strip() for line in ' '.join(parser.lines).split('\n') if line.strip())
lines = text.split('\n')
start = next((i for i, line in enumerate(lines) if line.startswith('Your use of this Program is governed')), None)
end = next((i for i, line in enumerate(lines) if line.startswith('Last updated:')), None)
if start is None or end is None or end < start or 'Oracle No-Fee Terms and Conditions (NFTC)' not in lines[start:end]:
    sys.exit('Unexpected Oracle license page')
print('\n'.join(lines[start:end + 1]))
PY
record_license oracle-java25 "$version" "$staging/license.txt" oracle-nftc
record_provenance "oracle-java25" "$version/linux-x64" "$url.sha256" "$staging/checksum.peer"
printf "%s\n" "$version"
