#!/usr/bin/env python3
"""Store license texts as metadata/license/<sha256>.txt with the short name in <sha256>.name.txt."""
import hashlib
import os
import re
import sys
import tempfile
from pathlib import Path

NAME = re.compile(r'[a-z0-9][a-z0-9.+-]*\Z')


def write_atomic(path, data):
    fd, temporary = tempfile.mkstemp(prefix='.license.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def store(root, text_file, name):
    if not NAME.fullmatch(name):
        raise ValueError(f'Invalid license name: {name}')
    data = Path(text_file).read_bytes()
    if not data.strip():
        raise ValueError('Empty license text')
    digest = hashlib.sha256(data).hexdigest()
    directory = Path(root) / 'metadata/license'
    text, label = directory / f'{digest}.txt', directory / f'{digest}.name.txt'
    if label.exists() and label.read_text().strip() != name:
        raise ValueError(f'License {digest} already stored as {label.read_text().strip()}')
    if text.exists() and hashlib.sha256(text.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Stored license is corrupt: {text.name}')
    directory.mkdir(parents=True, exist_ok=True)
    if not text.exists():
        write_atomic(text, data)
    if not label.exists():
        write_atomic(label, f'{name}\n'.encode())
    return digest


if __name__ == '__main__':
    try:
        action, root, *args = sys.argv[1:]
        if action != 'store' or len(args) != 2:
            raise ValueError('Usage: license_store.py store ROOT TEXT_FILE NAME')
        print(store(root, *args))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
