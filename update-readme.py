#!/usr/bin/env python3
"""Refresh the recorded tools table in README.md without network access."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent
START = '<!-- tools-table:start -->'
END = '<!-- tools-table:end -->'


def strategy(name):
    if name == 'claude':
        return 'Signed manifest; executable in bin'
    if name == 'codex':
        return 'Verified executables in bin'
    if name == 'nvm':
        return 'Verified Git archive in NVM directory'
    if name == 'node24':
        return 'Verified archive in NVM directory'
    if name in {'go', 'java25', 'maven39', 'maven310', 'mvnd'}:
        return 'Verified package in opt; entry points in bin'
    return 'Verified executable in bin'


def main():
    listing = subprocess.check_output([str(ROOT / 'list-tools.sh')], text=True)
    rows = ['| Tool | Latest recorded version | Install strategy |',
            '| --- | --- | --- |']
    for line in listing.splitlines()[1:]:
        name, _, recorded = line.split()
        versions = recorded.split(',')
        if not all(re.fullmatch(r'\d+\.\d+\.\d+', version) for version in versions):
            raise ValueError(f'Invalid recorded versions for {name}: {recorded}')
        latest = max(versions, key=lambda version: tuple(map(int, version.split('.'))))
        install_strategy = strategy(name)
        profile = ROOT / 'profile.d' / f'{name}.sh'
        if profile.is_file():
            install_strategy += f'; source [`profile.d/{name}.sh`](profile.d/{name}.sh)'
        rows.append(f'| [{name}](install/install-{name}.sh) | {latest} | {install_strategy} |')
    path = ROOT / 'README.md'
    content = path.read_text()
    if content.count(START) != 1 or content.count(END) != 1 or content.index(START) > content.index(END):
        raise ValueError('README must contain one ordered pair of tools table markers')
    before, rest = content.split(START, 1)
    _, after = rest.split(END, 1)
    path.write_text(before + START + '\n' + '\n'.join(rows) + '\n' + END + after)


if __name__ == '__main__':
    main()
