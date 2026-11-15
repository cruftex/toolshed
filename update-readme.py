#!/usr/bin/env python3
"""Refresh the recorded tools table in README.md without network access."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'lib'))
import tools  # noqa: E402

START = '<!-- tools-table:start -->'
END = '<!-- tools-table:end -->'


def main():
    rows = ['| Tool | Latest recorded version | Install strategy |',
            '| --- | --- | --- |']
    for pin in sorted((ROOT / 'pins').iterdir()):
        name = pin.name
        if not pin.is_file() or name.startswith('.'):
            continue
        latest = tools.recorded_versions(name, ROOT)[-1]
        install_strategy = tools.load(name, ROOT)['strategy']
        profile = ROOT / 'profile.d' / f'{name}.sh'
        if profile.is_file():
            install_strategy += f'; source [`profile.d/{name}.sh`](profile.d/{name}.sh)'
        rows.append(f'| [{name}](tools/{name}.sh) | {latest} | {install_strategy} |')
    path = ROOT / 'README.md'
    content = path.read_text()
    if content.count(START) != 1 or content.count(END) != 1 or content.index(START) > content.index(END):
        raise ValueError('README must contain one ordered pair of tools table markers')
    before, rest = content.split(START, 1)
    _, after = rest.split(END, 1)
    path.write_text(before + START + '\n' + '\n'.join(rows) + '\n' + END + after)


if __name__ == '__main__':
    main()
