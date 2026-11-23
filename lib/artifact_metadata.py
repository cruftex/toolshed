"""Read and write versioned, pipe-separated source-artifact metadata.

Usage: artifact_metadata.py record PATH VERSION ARTIFACT SHA256 DISCOVERED_AT [URL]

Tables have the columns version|artifact|sha256|discovered_at and, once a row records its download URL, a fifth
column url; tables without URLs keep four columns.
"""

import csv
import datetime
import io
import os
import re
import sys
import tempfile
from pathlib import Path

HEADER = ['version', 'artifact', 'sha256', 'discovered_at']
URL_HEADER = HEADER + ['url']
VERSION = re.compile(r'\d+\.\d+\.\d+\Z')
ARTIFACT = re.compile(r'(?:[a-zA-Z0-9._-]+)?/(?:license|[a-z0-9]+(?:[-_][a-z0-9]+)+/(?:binary|archive(?:/[a-z0-9._-]+)?))\Z')
DIGEST = re.compile(r'[0-9a-f]{64}\Z')
URL = re.compile(r'https://[^\s|]+\Z')


def _read_artifacts(stream, path):
    """Return the header and the records indexed by (version, artifact)."""
    records = {}
    reader = csv.DictReader(stream, delimiter='|')
    if reader.fieldnames not in (HEADER, URL_HEADER):
        raise ValueError(f'{path}: invalid artifact metadata header')
    for row in reader:
        if None in row or any(row[field] is None for field in reader.fieldnames):
            raise ValueError(f'{path}:{reader.line_num}: invalid field count')
        version, artifact, digest, timestamp = (row[field] for field in HEADER)
        if (not VERSION.fullmatch(version) or not ARTIFACT.fullmatch(artifact)
                or any(part in ('.', '..') for part in artifact.split('/'))):
            raise ValueError(f'{path}:{reader.line_num}: invalid artifact key')
        if digest and not DIGEST.fullmatch(digest):
            raise ValueError(f'{path}:{reader.line_num}: invalid SHA-256')
        if timestamp:
            try:
                parsed = datetime.datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                if parsed.tzinfo is None:
                    raise ValueError('timestamp has no timezone')
            except ValueError as error:
                raise ValueError(f'{path}:{reader.line_num}: invalid timestamp') from error
        if row.get('url') and not URL.fullmatch(row['url']):
            raise ValueError(f'{path}:{reader.line_num}: invalid URL')
        key = (version, artifact)
        if key in records:
            raise ValueError(f'{path}:{reader.line_num}: duplicate artifact')
        records[key] = row
    return reader.fieldnames, records


def read_artifacts(path):
    """Return records indexed by (version, artifact), rejecting ambiguity."""
    with Path(path).open(newline='', encoding='utf-8') as stream:
        return _read_artifacts(stream, path)[1]


def record_artifact(path, version, artifact, sha256, discovered_at, url=''):
    """Add an artifact, or fill in its empty checksum, discovery time or URL; never change a recorded value."""
    path = Path(path)
    header, records = HEADER, {}
    if path.exists():
        with path.open(newline='', encoding='utf-8') as stream:
            header, records = _read_artifacts(stream, path)
    key = (version, artifact)
    if key in records:
        old = records[key]
        # An empty digest or URL means "not yet recorded" and may be filled once; recorded values never change.
        if old['sha256'] not in ('', sha256):
            raise ValueError(f'{path}: conflicting artifact checksum for {version}/{artifact}')
        if url and old.get('url', '') not in ('', url):
            raise ValueError(f'{path}: conflicting artifact URL for {version}/{artifact}')
        if old['sha256'] == sha256 and (old['discovered_at'] or not discovered_at) and old.get('url', '') == (url or old.get('url', '')):
            return old
        row = dict(old, sha256=sha256, discovered_at=old['discovered_at'] or discovered_at)
    else:
        row = dict(zip(HEADER, (version, artifact, sha256, discovered_at)))
    if url:
        row['url'] = url
        header = URL_HEADER
    records[key] = row
    output = io.StringIO(newline='')
    writer = csv.DictWriter(output, fieldnames=header, delimiter='|', lineterminator='\n', restval='')
    writer.writeheader()
    writer.writerows(records[key] for key in sorted(records))
    content = output.getvalue()
    _read_artifacts(io.StringIO(content), path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='') as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return row


if __name__ == '__main__':
    if len(sys.argv) not in (7, 8) or sys.argv[1] != 'record':
        sys.exit('Usage: artifact_metadata.py record PATH VERSION ARTIFACT SHA256 DISCOVERED_AT [URL]')
    try:
        record_artifact(*sys.argv[2:])
    except (OSError, ValueError) as error:
        sys.exit(str(error))
