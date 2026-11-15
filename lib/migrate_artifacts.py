#!/usr/bin/env python3
"""Copy existing pinned source checksums and provenance times to artifact tables."""
import json
import re
import subprocess
import sys
from pathlib import Path

from artifact_metadata import record_artifact

DIRECT = {'clusterctl', 'controller-gen', 'cosign', 'kind', 'kubebuilder',
          'kubectl', 'setup-envtest', 'yq'}
SHELL = '''set -eu
declare -A checksums=() archive_sha256=()
source "$1"
for key in "${!checksums[@]}"; do
    [[ $key == archive/* ]] && printf '%s|%s\\n' "$key" "${checksums[$key]}"
done
for key in "${!archive_sha256[@]}"; do
    printf 'archive/%s|%s\\n' "$key" "${archive_sha256[$key]}"
done
true
'''


def migrate(root, only_name=None, only_key=None):
    metadata = root / 'metadata'
    target = metadata / 'artifacts'
    provenance = metadata / 'provenance'

    def timestamp(name, version, platform):
        path = provenance / f'{name}.json'
        if not path.exists():
            return ''
        records = json.loads(path.read_text())
        return records.get(f'{version}/{platform}', {}).get('discovered_at') or ''

    def save(name, version, platform, digest, source_name=None):
        source_name = source_name or name
        if only_name and (source_name != only_name or f'{version}/{platform}' != only_key):
            return
        canonical = platform.replace('linux_', 'linux-').replace('darwin_', 'darwin-')
        canonical = canonical.replace('amd64', 'x64').replace('arm64', 'aarch64')
        kind = 'binary' if source_name in DIRECT else ('archive/zip' if source_name == 'bun' else 'archive/tar.gz')
        component = 'host' if source_name == 'codex-code-mode-host' else ''
        time = timestamp(source_name, version, platform)
        if name == 'maven':
            time = timestamp('maven39' if version.startswith('3.9.') else 'maven310', version, platform)
        record_artifact(target / f'{name}.psv', version, f'{component}/{canonical}/{kind}', digest, time)

    for source in sorted(metadata.glob('*.sh')):
        name = source.stem
        if only_name and name != ('maven' if only_name in ('maven39', 'maven310') else only_name):
            continue
        output = subprocess.run(['bash', '-c', SHELL, '_', str(source)], capture_output=True, text=True, check=True).stdout
        for line in output.splitlines():
            key, digest = line.split('|')
            _, version, platform = key.split('/')
            source_name = only_name if name == 'maven' and only_name else name
            save('codex' if name == 'codex-code-mode-host' else name, version, platform, digest, source_name)

    for name in ('node24', 'mvnd'):
        if only_name and only_name != name:
            continue
        text = (root / 'install' / f'install-{name}.sh').read_text()
        for version, platform, digest in re.findall(r'\[([0-9.]+)/([^]]+)\]=([0-9a-f]{64})', text):
            save(name, version, platform, digest)

    claude = provenance / 'claude.json'
    if claude.exists() and (not only_name or only_name == 'claude'):
        for key, entry in json.loads(claude.read_text()).items():
            if only_key and key != only_key:
                continue
            version, platform = key.split('/')
            canonical = platform.replace('arm64', 'aarch64')
            record_artifact(target / 'claude.psv', version, f'/{canonical}/binary', '', entry.get('discovered_at') or '')


if __name__ == '__main__':
    migrate(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent,
            *(sys.argv[2:] if len(sys.argv) > 2 else []))
