#!/usr/bin/env python3
"""Select, check, and record source-artifact metadata during discovery."""
import sys
from pathlib import Path

from artifact_metadata import read_artifacts, record_artifact

DIRECT = {'clusterctl', 'controller-gen', 'cosign', 'kind', 'kubebuilder',
          'kubectl', 'setup-envtest', 'yq', 'claude'}


def location(root, name, key):
    version, platform = key.split('/')
    canonical = platform.replace('linux_', 'linux-').replace('darwin_', 'darwin-')
    canonical = canonical.replace('amd64', 'x64').replace('arm64', 'aarch64')
    component = 'host' if name == 'codex-code-mode-host' else ''
    table = 'codex' if component else ('maven' if name in ('maven39', 'maven310') else name)
    kind = 'binary' if name in DIRECT else ('archive/zip' if name == 'bun' else 'archive/tar.gz')
    return root / 'metadata/artifacts' / f'{table}.psv', version, f'{component}/{canonical}/{kind}'


if __name__ == '__main__':
    action, root, name, key, *args = sys.argv[1:]
    path, version, artifact = location(Path(root), name, key)
    try:
        records = read_artifacts(path) if path.exists() else {}
        existing = records.get((version, artifact))
        if action == 'check':
            if existing and existing['sha256'] != args[0]:
                raise ValueError(f'Conflicting archive metadata: {name} {key}')
        elif action == 'record':
            record_artifact(path, version, artifact, args[0], args[1])
        elif action == 'timestamp':
            if not existing or not existing['discovered_at']:
                raise ValueError(f'Missing discovery timestamp: {name} {key}')
            print(existing['discovered_at'])
        else:
            raise ValueError('Unknown discovery metadata action')
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
