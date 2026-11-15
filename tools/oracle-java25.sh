kind=opt
url='https://download.oracle.com/java/25/archive/jdk-{version}_linux-x64_bin.tar.gz'
root='jdk-{version}'
links=
detect=dirs
checksum=suffix:.sha256
license=oracle-nftc
strategy='Oracle JDK; verified package in opt; activate with profile'

tool_validate() {
    java_is_installed "$1" "$2"
}

tool_latest() {
    local staging=$1
    local -a matches=()
    _installer_download https://www.oracle.com/java/technologies/downloads/ "$staging/downloads.html"
    mapfile -t matches < <(grep -zoP '<h3\s+id="java25"[^>]*>\s*Java SE Development Kit \K25\.\d+\.\d+(?=(?:\.\d+)* downloads\s*</h3>)' \
        "$staging/downloads.html" | tr '\0' '\n')
    (( ${#matches[@]} == 1 )) || _installer_fail 'Cannot identify Oracle Java 25 release.'
    version=${matches[0]}
}

# The Oracle No-Fee Terms and Conditions, reduced to the plain text of the agreement itself.
tool_license() {
    local text=$2
    _installer_download https://www.oracle.com/downloads/licenses/no-fee-license.html "$text.html"
    python3 - "$text.html" > "$text" <<'PY' || _installer_fail 'Cannot read Oracle license.'
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
}
