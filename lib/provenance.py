#!/usr/bin/env python3
"""Record first successful discovery and the checksum response's network peer."""
import datetime
import ipaddress
import json
import os
from pathlib import Path
import sys
import tempfile

path, key, source, peer_file = sys.argv[1:]
path = Path(path)
peer_file = Path(peer_file)
entries = json.loads(path.read_text()) if path.exists() else {}
if key not in entries:
    lines = peer_file.read_text().splitlines() if peer_file.is_file() else []
    try:
        peer = str(ipaddress.ip_address(lines[0]))
    except (ValueError, IndexError):
        peer = None
    entries[key] = {
        'discovered_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
        'checksum_url': source,
        'effective_url': lines[1] if len(lines) > 1 and lines[1] else None,
        'peer_ip': peer,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(entries, output, indent=2, sort_keys=True)
            output.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
