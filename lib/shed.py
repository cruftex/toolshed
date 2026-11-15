#!/usr/bin/env python3
"""Report and update tools installed in Toolshed's configured locations."""
import os
import hashlib
import argparse
import datetime
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from artifact_metadata import read_artifacts
import tools

root = Path(__file__).resolve().parent.parent
bin_dir, opt_dir, nvm_dir = map(Path, sys.argv[2:5])
command = sys.argv[1]
parser = argparse.ArgumentParser(prog='shed update')
parser.add_argument('--delay-days', type=int, default=8, metavar='DAYS')
args = parser.parse_args(sys.argv[5:])
if args.delay_days < 0:
    parser.error('--delay-days must be non-negative')
version_re = re.compile(r'(?<![\d.])(\d+\.\d+\.\d+)(?![\d.])')
node_versions = []


def parse_version(text):
    match = version_re.search(text)
    return match.group(1) if match else None


def version_tuple(version):
    return tuple(map(int, version.split('.')))


def executable_version(path, args=('--version',), env=None):
    if not path.is_file() or not os.access(path, os.X_OK):
        return None
    try:
        result = subprocess.run([str(path), *args], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=15,
                                env=dict(os.environ, **(env or {})))
        return (parse_version(result.stdout) or '?') if result.returncode == 0 else '?'
    except (OSError, subprocess.TimeoutExpired):
        return '?'


def detect_version(name, settings):
    """The installed version of a tool, None when absent, or '?' when it cannot be determined."""
    detect = settings['detect']
    executable = bin_dir / settings['executable']
    if detect == 'run':
        env = dict(item.split('=', 1) for item in settings['version_env'].split())
        return executable_version(executable, tuple(settings['version_args'].split()), env)
    if detect == 'digest':
        # No version flag; identify the verified bytes by their recorded digest.
        if not executable.is_file() or not os.access(executable, os.X_OK):
            return None
        try:
            with executable.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            records = read_artifacts(root / 'metadata/artifacts' / f'{settings["table"]}.psv')
            matches = [version for (version, artifact), row in records.items()
                       if artifact == '/linux-x64/binary' and row['sha256'] == digest]
            return max(matches, key=version_tuple) if matches else '?'
        except (OSError, ValueError):
            return '?'
    if detect == 'link':
        # Read the version from the linked package directory instead of running the tool.
        if not executable.is_file() or not os.access(executable, os.X_OK):
            return None
        try:
            relative = executable.resolve().relative_to(opt_dir.resolve() / settings['table'])
        except ValueError:
            return '?'
        return relative.parts[0] if len(relative.parts) == 3 and parse_version(relative.parts[0]) == relative.parts[0] else '?'
    if detect == 'dirs':
        home = opt_dir / settings['table']
        versions = [path.name for path in home.iterdir()
                    if parse_version(path.name) == path.name] if home.is_dir() else []
        return max(versions, key=version_tuple) if versions else None
    if detect == 'nvm':
        nvm = nvm_dir / 'nvm.sh'
        if not nvm.is_file():
            return None
        try:
            run = subprocess.run(['bash', '-c', 'source "$1" --no-use; nvm --version', '_', str(nvm)],
                                 env=dict(os.environ, NVM_DIR=str(nvm_dir)), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, timeout=15)
            return (parse_version(run.stdout) if run.returncode == 0 else None) or '?'
        except (OSError, subprocess.TimeoutExpired):
            return '?'
    if detect == 'node':
        node_root = nvm_dir / 'versions/node'
        prefix = 'v' + settings['name'].removeprefix('node')
        versions = [value for path in (node_root.iterdir() if node_root.is_dir() else [])
                    if re.fullmatch(re.escape(prefix) + r'\.\d+\.\d+', path.name)
                    for value in [executable_version(path / 'bin/node')] if value is not None]
        node_versions.extend(versions)
        known = [v for v in versions if v != '?']
        return (max(known, key=version_tuple) if known else '?') if versions else None
    return None


def installed_tools():
    result = {}
    for name in tools.names(root):
        version = detect_version(name, tools.load(name, root))
        if version is not None:
            result[name] = version
    return result


def descriptor_rows(name):
    """Recorded download rows for the host platform, grouped by version as {version: [rows]}."""
    settings = tools.load(name, root)
    platform = subprocess.run([str(root / 'lib/platform.sh')], capture_output=True,
                              text=True, check=True).stdout.strip()
    records = read_artifacts(root / 'metadata/artifacts' / f'{settings["table"]}.psv')
    grouped = {}
    for (version, artifact), row in records.items():
        if artifact.split('/')[1] == platform and row['sha256'] and version.startswith(settings['version_prefix']):
            grouped.setdefault(version, []).append(row)
    required = {''} | {pair.split('=', 1)[0] for pair in settings['components'].split()}
    return {version: rows for version, rows in grouped.items()
            if required <= {row['artifact'].split('/')[0] for row in rows}}


def recorded_versions(name):
    pin = (root / 'pins' / name).read_text().strip()
    if name == 'claude':
        registry = root / 'metadata/claude-versions'
        versions = registry.read_text().splitlines() if registry.is_file() else []
        return [v for v in set(versions + [pin]) if re.fullmatch(r'\d+\.\d+\.\d+', v)]
    try:
        return list(descriptor_rows(name))
    except (OSError, subprocess.CalledProcessError, ValueError):
        return []


def target(name, delay_days=None):
    versions = recorded_versions(name)
    if delay_days is not None and delay_days > 0:
        pin = (root / 'pins' / name).read_text().strip()
        try:
            rows = descriptor_rows(name)
        except (OSError, subprocess.CalledProcessError, ValueError):
            rows = {}
        cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=delay_days)
        eligible = []
        for version in versions:
            if version == pin:
                eligible.append(version)
                continue
            try:
                stamps = [datetime.datetime.fromisoformat(row['discovered_at'].replace('Z', '+00:00'))
                          for row in rows.get(version, [])]
                if stamps and all(stamp.tzinfo is not None and stamp <= cutoff for stamp in stamps):
                    eligible.append(version)
            except (KeyError, TypeError, ValueError):
                continue
        versions = eligible
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
            known = target(name, args.delay_days)
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
            if name == 'node24' and installed.get('nvm') != target('nvm', args.delay_days):
                print('node24: configured NVM version must be repaired or upgraded first; skipped', file=sys.stderr)
                failures = True
                continue
            script = [str(root / 'lib/install-tool.sh'), name]
        else:
            script = [str(root / 'lib/discover-tool.sh'), name]
            if tools.load(name, root)['discover'] == 'none':
                print(f'{name}: no internet updater available; skipped')
                continue
        print(f'{name}: {"checking for releases" if command == "discover" else f"installing {known}"}...', flush=True)
        env = os.environ.copy()
        env.pop('TOOLSHED_OVERRIDE_TOOL_VERSION', None)
        if command == 'update':
            env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = known
        result = subprocess.run(script, env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        if result.returncode:
            print(f'{name}: failed', file=sys.stderr)
            if result.stderr.strip():
                print(result.stderr.strip(), file=sys.stderr)
            failures = True
            continue
        if result.stderr.strip():
            print(result.stderr.strip(), file=sys.stderr)
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
