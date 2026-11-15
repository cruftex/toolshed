#!/usr/bin/env python3
"""Record first successful discovery and the checksum response's network peer."""
import datetime
import ipaddress
import json
import os
from pathlib import Path
import sys
import tempfile

path, key, source, peer_file, *timestamp = sys.argv[1:]
path = Path(path)
peer_file = Path(peer_file)
entries = json.loads(path.read_text()) if path.exists() else {}
authoritative = timestamp[0] if timestamp else None
if (key not in entries or any(not entries[key].get(field) for field in ('discovered_at', 'peer_ip', 'effective_url'))
        or (authoritative and entries[key].get('discovered_at') != authoritative)):
    lines = peer_file.read_text().splitlines() if peer_file.is_file() else []
    try:
        peer = str(ipaddress.ip_address(lines[0]))
    except (ValueError, IndexError):
        peer = None
    observed_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
    if key not in entries:
        entries[key] = {
        'discovered_at': authoritative or observed_at,
        'checksum_url': source,
        'effective_url': lines[1] if len(lines) > 1 and lines[1] else None,
        'peer_ip': peer,
    }
    else:
        entry = entries[key]
        if authoritative:
            entry['discovered_at'] = authoritative
        if not entry.get('discovered_at'):
            entry['discovered_at'] = observed_at
        if entry.get('checksum_url') in (None, source) and peer and len(lines) > 1 and lines[1] and (not entry.get('peer_ip') or not entry.get('effective_url')):
            entry['checksum_url'] = source
            entry['peer_ip'] = peer
            entry['effective_url'] = lines[1]
            entry['peer_observed_at'] = observed_at
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
