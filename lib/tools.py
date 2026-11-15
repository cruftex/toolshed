#!/usr/bin/env python3
"""Read tool descriptors (tools/<tool>.sh): their top-level key=value lines; hook functions are ignored."""
import re
import shlex
import sys
from pathlib import Path

from artifact_metadata import read_artifacts

ROOT = Path(__file__).resolve().parent.parent
SETTING = re.compile(r'([a-z_][a-z0-9_]*)=(.*)')
VERSION = re.compile(r'\d+\.\d+\.\d+')
DEFAULTS = {'archive': 'tar.gz', 'version_args': '--version', 'version_env': '', 'detect': 'run',
            'component': '', 'components': '', 'version_prefix': '', 'discover': ''}
STRATEGIES = {'bin': 'Verified executable in bin', 'opt': 'Verified package in opt; entry points in bin'}


def load(name, root=ROOT):
    """Return a descriptor's settings with defaults; raises OSError for an unknown tool."""
    settings = dict(DEFAULTS, name=name, executable=name, table=name)
    for line in (Path(root) / 'tools' / f'{name}.sh').read_text().splitlines():
        match = SETTING.fullmatch(line)
        if match:
            values = shlex.split(match[2])
            if len(values) > 1:
                raise ValueError(f'tools/{name}.sh: {match[1]} must be a single shell word')
            settings[match[1]] = values[0] if values else ''
    settings.setdefault('strategy', STRATEGIES.get(settings.get('kind'), ''))
    return settings


def names(root=ROOT):
    return sorted(path.stem for path in (Path(root) / 'tools').glob('*.sh'))


def component_owner(name, root=ROOT):
    """Map a component alias such as codex-code-mode-host to its (tool, component)."""
    for tool in names(root):
        for pair in load(tool, root)['components'].split():
            component, alias = pair.split('=', 1)
            if alias == name:
                return tool, component
    return name, ''


def artifact_kind(settings):
    return 'binary' if settings['archive'] == 'binary' else f'archive/{settings["archive"]}'


def recorded_versions(name, root=ROOT):
    """The pin plus every version with a recorded download (or Claude release) for the tool."""
    root = Path(root)
    settings = load(name, root)
    versions = {(root / 'pins' / name).read_text().strip()}
    if name == 'claude' and (root / 'metadata/claude-versions').is_file():
        versions.update((root / 'metadata/claude-versions').read_text().split())
    table = root / 'metadata/artifacts' / f'{settings["table"]}.psv'
    if table.is_file():
        versions.update(version for version, artifact in read_artifacts(table)
                        if not artifact.endswith('/license'))
    return sorted((v for v in versions if VERSION.fullmatch(v) and v.startswith(settings['version_prefix'])),
                  key=lambda v: tuple(map(int, v.split('.'))))


def available(root=ROOT):
    root = Path(root)
    print(f'{"TOOL":12} {"DEFAULT":16} RECORDED VERSIONS')
    for pin in sorted((root / 'pins').iterdir()):
        if pin.is_file() and not pin.name.startswith('.'):
            print(f'{pin.name:12} {pin.read_text().strip():16} {",".join(recorded_versions(pin.name, root))}')


if __name__ == '__main__':
    command, root = (sys.argv[1:2] or [''])[0], Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT
    if command == 'available':
        available(root)
    elif command == 'discoverable':
        print('\n'.join(name for name in names(root) if load(name, root)['discover'] != 'none'))
    else:
        sys.exit('Usage: tools.py {available|discoverable} [ROOT]')
