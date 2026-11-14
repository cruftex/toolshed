import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import io
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]

class UpdateTests(unittest.TestCase):
    def test_bun_update_and_repeat(self):
        with tempfile.TemporaryDirectory(prefix='bun update ') as temp:
            root = Path(temp)
            repo = root / 'repo with spaces'
            for directory in ('install', 'lib', 'metadata', 'pins', 'discover'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('TOOLSHED_DOWNLOAD_DIR','cache'), ('TOOLSHED_BIN_DIR','bin'), ('TOOLSHED_OPT_DIR','opt')]) + '\n')
            binary = b"#!/bin/sh\nprintf '1.5.0\\n'\n"
            archive = root / 'bun-linux-x64.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('bun-linux-x64/bun', binary)
            release = {'tag_name':'bun-v1.5.0', 'draft':False, 'prerelease':False, 'assets':[{'name':archive.name, 'digest':'sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest()}]}
            (root / 'release.json').write_text(json.dumps(release))
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
if [[ $url == */latest ]]; then cp "$FIXTURE/release.json" "$out"; else cp "$FIXTURE/bun-linux-x64.zip" "$out"; fi
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURE=str(root))
            old_pin = (repo / 'pins/bun').read_text()
            for _ in range(2):
                result = subprocess.run([repo / 'discover/discover-bun.sh'], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/bun').read_text(), old_pin)
            self.assertFalse((root / 'bin/bun').exists())
            self.assertEqual(result.stdout.strip(), '1.5.0')
            metadata = (repo / 'metadata/bun.sh').read_text()
            self.assertEqual(metadata.count('archive/1.5.0/linux-x64'), 1)
            self.assertEqual(metadata.count('binary/1.5.0/linux-x64'), 1)

    def test_kubernetes_discovery_and_install_from_cache(self):
        with tempfile.TemporaryDirectory(prefix='kubernetes discovery ') as temp:
            root = Path(temp)
            repo = root / 'repo'
            for directory in ('install', 'lib', 'metadata', 'pins', 'discover'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('TOOLSHED_DOWNLOAD_DIR', 'cache'), ('TOOLSHED_BIN_DIR', 'bin'), ('TOOLSHED_OPT_DIR', 'opt')]) + '\n')
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text("""#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
if [[ $url == */latest ]]; then cp "$FIXTURE/release.json" "$out"; else cp "$FIXTURE/${url##*/}" "$out"; fi
""")
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURE=str(root))
            for tool, version in [('kubectl', '1.35.1'), ('helm', '3.20.1')]:
                with self.subTest(tool=tool):
                    (root / 'release.json').write_text(json.dumps({'tag_name': 'v' + version, 'draft': False, 'prerelease': False}))
                    if tool == 'kubectl':
                        asset = 'kubectl'
                        (root / asset).write_bytes(f"#!/bin/sh\nprintf 'Client Version: v{version}\\n'\n".encode())
                    else:
                        asset = f'helm-v{version}-linux-amd64.tar.gz'
                        binary = f"#!/bin/sh\nprintf 'v{version}+test\\n'\n".encode()
                        with tarfile.open(root / asset, 'w:gz') as tar:
                            member = tarfile.TarInfo('linux-amd64/helm')
                            member.size = len(binary)
                            tar.addfile(member, io.BytesIO(binary))
                    digest = hashlib.sha256((root / asset).read_bytes()).hexdigest()
                    checksum_name = asset + ('.sha256' if tool == 'kubectl' else '.sha256sum')
                    (root / checksum_name).write_text(digest + ('' if tool == 'kubectl' else '  ' + asset) + '\n')
                    pin = (repo / 'pins' / tool).read_text()
                    for _ in range(2):
                        result = subprocess.run([repo / 'discover' / f'discover-{tool}.sh'], env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.strip(), version)
                    self.assertEqual((repo / 'pins' / tool).read_text(), pin)
                    metadata = (repo / 'metadata' / f'{tool}.sh').read_text()
                    self.assertEqual(metadata.count(f'archive/{version}/linux-x64'), 1)
                    env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = version
                    curl.rename(commands / 'curl.disabled')
                    result = subprocess.run([repo / 'install' / f'install-{tool}.sh'], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue((root / 'bin' / tool).is_file())
                    (commands / 'curl.disabled').rename(curl)
                    del env['TOOLSHED_OVERRIDE_TOOL_VERSION']
                    (root / checksum_name).write_text('0' * 64 + ('' if tool == 'kubectl' else '  ' + asset) + '\n')
                    before = (repo / 'metadata' / f'{tool}.sh').read_bytes()
                    result = subprocess.run([repo / 'discover' / f'discover-{tool}.sh'], env=env, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual((repo / 'metadata' / f'{tool}.sh').read_bytes(), before)
                    self.assertEqual((repo / 'pins' / tool).read_text(), pin)

    def test_kind_and_clusterctl_discovery(self):
        with tempfile.TemporaryDirectory(prefix='cluster discovery ') as temp:
            root = Path(temp)
            repo = root / 'repo'
            for directory in ('install', 'lib', 'metadata', 'pins', 'discover'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('TOOLSHED_DOWNLOAD_DIR', 'cache'), ('TOOLSHED_BIN_DIR', 'bin'), ('TOOLSHED_OPT_DIR', 'opt')]) + '\n')
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text("""#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
if [[ $url == */latest ]]; then cp "$FIXTURE/release.json" "$out"; else cp "$FIXTURE/${url##*/}" "$out"; fi
""")
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURE=str(root))
            for tool, version in [('kind', '0.31.0'), ('clusterctl', '1.12.0')]:
                with self.subTest(tool=tool):
                    asset = f'{tool}-linux-amd64'
                    output = f'kind v{version} go1.24 linux/amd64' if tool == 'kind' else f'v{version}'
                    (root / asset).write_bytes(f"#!/bin/sh\nprintf '{output}\\n'\n".encode())
                    digest = hashlib.sha256((root / asset).read_bytes()).hexdigest()
                    release = {'tag_name': 'v' + version, 'draft': False, 'prerelease': False, 'assets': [{'name': asset, 'digest': 'sha256:' + digest}]}
                    (root / 'release.json').write_text(json.dumps(release))
                    pin = (repo / 'pins' / tool).read_text()
                    for _ in range(2):
                        result = subprocess.run([repo / 'discover' / f'discover-{tool}.sh'], env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.strip(), version)
                    self.assertEqual((repo / 'pins' / tool).read_text(), pin)
                    self.assertEqual((repo / 'metadata' / f'{tool}.sh').read_text().count(f'archive/{version}/linux-x64'), 1)
                    env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = version
                    curl.rename(commands / 'curl.disabled')
                    result = subprocess.run([repo / 'install' / f'install-{tool}.sh'], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    (commands / 'curl.disabled').rename(curl)
                    del env['TOOLSHED_OVERRIDE_TOOL_VERSION']
                    release['assets'][0]['digest'] = 'sha256:' + '0' * 64
                    (root / 'release.json').write_text(json.dumps(release))
                    before = (repo / 'metadata' / f'{tool}.sh').read_bytes()
                    result = subprocess.run([repo / 'discover' / f'discover-{tool}.sh'], env=env, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual((repo / 'metadata' / f'{tool}.sh').read_bytes(), before)

    def test_controller_release_discovery_verifies_and_installs(self):
        with tempfile.TemporaryDirectory(prefix='controller discovery ') as temp:
            root = Path(temp)
            repo = root / 'repo'
            for directory in ('install', 'lib', 'metadata', 'pins', 'discover'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('TOOLSHED_DOWNLOAD_DIR', 'cache'), ('TOOLSHED_BIN_DIR', 'bin'), ('TOOLSHED_OPT_DIR', 'opt')]) + '\n')
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text("""#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
if [[ $url == */latest ]]; then cp "$FIXTURE/release.json" "$out"; else cp "$FIXTURE/${url##*/}" "$out"; fi
""")
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURE=str(root))
            version = '0.24.0'
            asset = 'controller-gen-linux-amd64'
            (root / asset).write_bytes(b"#!/bin/sh\nprintf 'Version: v0.24.0\\n'\n")
            digest = hashlib.sha256((root / asset).read_bytes()).hexdigest()
            release = {'tag_name': 'v' + version, 'draft': False, 'prerelease': False, 'assets': [{'name': asset, 'digest': 'sha256:' + digest}]}
            (root / 'release.json').write_text(json.dumps(release))
            pin = (repo / 'pins/controller-gen').read_text()
            for _ in range(2):
                result = subprocess.run([repo / 'discover/discover-controller-gen.sh'], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/controller-gen').read_text(), pin)
            self.assertEqual((repo / 'metadata/controller-gen.sh').read_text().count('archive/0.24.0/linux-x64'), 1)
            env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = version
            curl.rename(commands / 'curl.disabled')
            result = subprocess.run([repo / 'install/install-controller-gen.sh'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            (commands / 'curl.disabled').rename(curl)
            del env['TOOLSHED_OVERRIDE_TOOL_VERSION']
            release['assets'][0]['digest'] = 'sha256:' + '0' * 64
            (root / 'release.json').write_text(json.dumps(release))
            before = (repo / 'metadata/controller-gen.sh').read_bytes()
            result = subprocess.run([repo / 'discover/discover-controller-gen.sh'], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((repo / 'metadata/controller-gen.sh').read_bytes(), before)

    def test_vegeta_update_records_all_platforms(self):
        with tempfile.TemporaryDirectory(prefix='vegeta update ') as temp:
            root = Path(temp)
            repo = root / 'repo'
            for directory in ('install', 'lib', 'metadata', 'pins', 'discover'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('TOOLSHED_DOWNLOAD_DIR','cache'), ('TOOLSHED_BIN_DIR','bin'), ('TOOLSHED_OPT_DIR','opt')]) + '\n')
            binary = b"#!/bin/sh\nprintf 'Version: v12.14.0\\n'\n"
            assets = []
            for platform in ('linux_amd64', 'linux_arm64', 'darwin_amd64', 'darwin_arm64'):
                archive = root / f'vegeta_12.14.0_{platform}.tar.gz'
                with tarfile.open(archive, 'w:gz') as tar:
                    member = tarfile.TarInfo('vegeta')
                    member.size = len(binary)
                    tar.addfile(member, io.BytesIO(binary))
                assets.append({'name':archive.name, 'digest':'sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest()})
            (root / 'release.json').write_text(json.dumps({'tag_name':'v12.14.0', 'draft':False, 'prerelease':False, 'assets':assets}))
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
if [[ $url == */latest ]]; then cp "$FIXTURE/release.json" "$out"; else cp "$FIXTURE/${url##*/}" "$out"; fi
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURE=str(root))
            old_pin = (repo / 'pins/vegeta').read_text()
            result = subprocess.run([repo / 'discover/discover-vegeta.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/vegeta').read_text(), old_pin)
            self.assertFalse((root / 'bin/vegeta').exists())
            for platform in ('linux_amd64', 'linux_arm64', 'darwin_amd64', 'darwin_arm64'):
                self.assertIn(f'archive/12.14.0/{platform}', (repo / 'metadata/vegeta.sh').read_text())
            metadata = repo / 'metadata/vegeta.sh'
            lines = metadata.read_text().splitlines(keepends=True)
            lines = [line for line in lines if '12.14.0/linux_amd64' not in line]
            lines = [line.replace(next(a['digest'][7:] for a in assets if 'darwin_arm64' in a['name']), '0' * 64)
                     if 'archive/12.14.0/darwin_arm64' in line else line for line in lines]
            metadata.write_text(''.join(lines))
            before = metadata.read_bytes()
            pin = (repo / 'pins/vegeta').read_bytes()
            self.assertFalse((root / 'bin/vegeta').exists())
            result = subprocess.run([repo / 'discover/discover-vegeta.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Conflicting archive metadata', result.stderr)
            self.assertEqual(metadata.read_bytes(), before)
            self.assertEqual((repo / 'pins/vegeta').read_bytes(), pin)
            self.assertFalse((root / 'bin/vegeta').exists())
