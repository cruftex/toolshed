#!/usr/bin/env python3
"""Report and update tools installed in Toolshed's configured locations."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
bin_dir, opt_dir, nvm_dir = map(Path, sys.argv[2:5])
command = sys.argv[1]
version_re = re.compile(r'(?<![\d.])(\d+\.\d+\.\d+)(?![\d.])')
node_versions = []


def parse_version(text):
    match = version_re.search(text)
    return match.group(1) if match else None


def version_tuple(version):
    return tuple(map(int, version.split('.')))


def executable_version(path, args=('--version',)):
    if not path.is_file() or not os.access(path, os.X_OK):
        return None
    try:
        result = subprocess.run([str(path), *args], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=15)
        return (parse_version(result.stdout) or '?') if result.returncode == 0 else '?'
    except (OSError, subprocess.TimeoutExpired):
        return '?'


def installed_tools():
    result = {}
    for name, filename in [('bun', 'bun'), ('claude', 'claude'), ('codex', 'codex'),
                           ('vegeta', 'vegeta'), ('helm', 'helm'), ('kubectl', 'kubectl'), ('java25', 'java'),
                           ('maven39', 'mvn39'), ('maven310', 'mvn310')]:
        version = executable_version(bin_dir / filename, ('version', '--client') if name == 'kubectl' else (('version', '--short') if name == 'helm' else ('--version',)))
        if version is not None:
            result[name] = version
    mvnd = bin_dir / 'mvnd'
    if mvnd.is_file() and os.access(mvnd, os.X_OK):
        # Avoid starting a daemon merely to display status.
        resolved = mvnd.resolve()
        try:
            relative = resolved.relative_to(opt_dir.resolve() / 'mvnd')
            result['mvnd'] = relative.parts[0] if len(relative.parts) == 3 and parse_version(relative.parts[0]) == relative.parts[0] else '?'
        except ValueError:
            result['mvnd'] = '?'
    nvm = nvm_dir / 'nvm.sh'
    if nvm.is_file():
        try:
            run = subprocess.run(['bash', '-c', 'source "$1" --no-use; nvm --version', '_', str(nvm)],
                                 env=dict(os.environ, NVM_DIR=str(nvm_dir)), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, timeout=15)
            result['nvm'] = parse_version(run.stdout) if run.returncode == 0 else '?'
            result['nvm'] = result['nvm'] or '?'
        except (OSError, subprocess.TimeoutExpired):
            result['nvm'] = '?'
    node_root = nvm_dir / 'versions/node'
    if node_root.is_dir():
        versions = []
        for path in node_root.iterdir():
            if re.fullmatch(r'v24\.\d+\.\d+', path.name):
                value = executable_version(path / 'bin/node')
                if value is not None:
                    versions.append(value)
                    node_versions.append(value)
        known = [v for v in versions if v != '?']
        if versions:
            result['node24'] = max(known, key=version_tuple) if known else '?'
    return result


def recorded_versions(name):
    pin = (root / 'pins' / name).read_text().strip()
    if name == 'claude':
        registry = root / 'metadata/claude-versions'
        versions = registry.read_text().splitlines() if registry.is_file() else []
        return [v for v in set(versions + [pin]) if re.fullmatch(r'\d+\.\d+\.\d+', v)]
    metadata_name = 'maven' if name in ('maven39', 'maven310') else name
    metadata = root / 'metadata' / f'{metadata_name}.sh'
    if not metadata.is_file():
        return [pin]
    try:
        platform = subprocess.run([str(root / 'lib/platform.sh')], capture_output=True,
                                  text=True, check=True).stdout.strip()
        if name == 'vegeta':
            platform = platform.replace('linux-', 'linux_').replace('darwin-', 'darwin_')
            platform = platform.replace('x64', 'amd64').replace('aarch64', 'arm64')
        def keys(path):
            script = '''declare -A checksums=() archive_sha256=(); source "$1"
for key in "${!checksums[@]}"; do printf '%s\\n' "$key"; done
for key in "${!archive_sha256[@]}"; do printf 'archive/%s\\n' "$key"; done'''
            output = subprocess.run(['bash', '-c', script, '_', str(path)],
                                    capture_output=True, text=True, check=True).stdout
            return set(output.splitlines())
        entries = keys(metadata)
        host_entries = keys(root / 'metadata/codex-code-mode-host.sh') if name == 'codex' else None
        versions = []
        for key in entries:
            parts = key.split('/')
            if len(parts) != 3 or parts[0] != 'archive' or parts[2] != platform:
                continue
            version = parts[1]
            if not re.fullmatch(r'\d+\.\d+\.\d+', version):
                continue
            if name == 'maven39' and not version.startswith('3.9.'):
                continue
            if name == 'maven310' and not version.startswith('3.10.'):
                continue
            if name in ('bun', 'vegeta', 'codex', 'helm', 'kubectl') and f'binary/{version}/{platform}' not in entries:
                continue
            if host_entries is not None and not {f'archive/{version}/{platform}', f'binary/{version}/{platform}'} <= host_entries:
                continue
            versions.append(version)
        return versions
    except (OSError, subprocess.CalledProcessError):
        return []


def target(name):
    versions = recorded_versions(name)
    return max(versions, key=version_tuple) if versions else None


def status(version, known):
    if version == '?' or known is None:
        return 'unknown'
    installed, available = version_tuple(version), version_tuple(known)
    return 'yes' if installed < available else ('newer' if installed > available else 'no')


def move_pin(name, version):
    path = root / 'pins' / name
    fd, temporary = tempfile.mkstemp(prefix=f'.{name}.', dir=path.parent)
    try:
        os.fchmod(fd, path.stat().st_mode & 0o777)
        with os.fdopen(fd, 'w') as output:
            output.write(version + '\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


installed = installed_tools()
if command == 'installed':
    print(f'{"TOOL":12} {"INSTALLED":16} {"KNOWN":16} UPDATE')
    for name, version in sorted(installed.items()):
        pin = target(name)
        shown = ','.join(sorted(node_versions, key=lambda v: version_tuple(v) if v != '?' else (0, 0, 0), reverse=True)) if name == 'node24' else version
        print(f'{name:12} {shown:16} {pin or "unavailable":16} {status(version, pin)}')
    if not installed:
        print('No installed tools found in configured locations.')
elif command in ('update', 'discover'):
    failures = False
    if not installed:
        print('No installed tools found in configured locations.')
    for name in sorted(installed, key=lambda item: (item != "nvm", item)):
        version = installed[name]
        if version == '?':
            print(f'{name}: version unknown; skipped', file=sys.stderr)
            failures = True
            continue
        if command == 'update':
            known = target(name)
            if known is None:
                print(f'{name}: no compatible recorded version; skipped', file=sys.stderr)
                failures = True
                continue
            comparison = status(version, known)
            if comparison == 'newer':
                print(f'{name}: {version} is newer than recorded {known}; unchanged')
                continue
            if comparison == 'no' and (root / 'pins' / name).read_text().strip() == known:
                print(f'{name}: {version} is current')
                continue
            if name == 'node24' and installed.get('nvm') != target('nvm'):
                print('node24: configured NVM version must be repaired or upgraded first; skipped', file=sys.stderr)
                failures = True
                continue
            script = root / 'install' / f'install-{name}.sh'
        else:
            script = root / 'discover' / f'discover-{name}.sh'
            if not script.is_file():
                print(f'{name}: no internet updater available; skipped')
                continue
        print(f'{name}: {"checking for releases" if command == "discover" else f"installing {known}"}...', flush=True)
        env = os.environ.copy()
        env.pop('TOOLSHED_OVERRIDE_TOOL_VERSION', None)
        if command == 'update':
            env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = known
        result = subprocess.run([str(script)], env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        if result.returncode:
            print(f'{name}: failed', file=sys.stderr)
            if result.stderr.strip():
                print(result.stderr.strip(), file=sys.stderr)
            failures = True
            continue
        if command == 'update':
            try:
                move_pin(name, known)
            except OSError as error:
                print(f'{name}: installed {known}, but could not update pin: {error}', file=sys.stderr)
                failures = True
                continue
            installed[name] = known
            print(f'{name}: installed {known}; pin updated')
        else:
            found = result.stdout.strip()
            if not re.fullmatch(r'\d+\.\d+\.\d+', found):
                print(f'{name}: updater returned an invalid version', file=sys.stderr)
                failures = True
            elif version_tuple(found) > version_tuple(version):
                print(f'{name}: {found} available and cached (installed {version})')
            else:
                print(f'{name}: no newer release (installed {version}, latest {found})')
    sys.exit(1 if failures else 0)
