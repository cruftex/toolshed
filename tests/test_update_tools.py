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
            for directory in ('install', 'lib', 'metadata', 'pins', 'update'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('DOWNLOAD_DIR','cache'), ('DEST_BIN_DIR','bin'), ('DEST_OPT_DIR','opt')]) + '\n')
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
            for _ in range(2):
                result = subprocess.run([repo / 'update/update-bun.sh'], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/bun').read_text(), '1.5.0\n')
            self.assertEqual((root / 'bin/bun').read_bytes(), binary)
            self.assertEqual((root / 'bin/bunx').readlink(), Path('bun'))
            metadata = (repo / 'metadata/bun.sh').read_text()
            self.assertEqual(metadata.count('archive/1.5.0/linux-x64'), 1)
            self.assertEqual(metadata.count('binary/1.5.0/linux-x64'), 1)

    def test_vegeta_update_records_all_platforms(self):
        with tempfile.TemporaryDirectory(prefix='vegeta update ') as temp:
            root = Path(temp)
            repo = root / 'repo'
            for directory in ('install', 'lib', 'metadata', 'pins', 'update'):
                shutil.copytree(ROOT / directory, repo / directory)
            (repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(root / value))}' for key, value in [('DOWNLOAD_DIR','cache'), ('DEST_BIN_DIR','bin'), ('DEST_OPT_DIR','opt')]) + '\n')
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
            result = subprocess.run([repo / 'update/update-vegeta.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/vegeta').read_text(), '12.14.0\n')
            self.assertEqual((root / 'bin/vegeta').read_bytes(), binary)
            for platform in ('linux_amd64', 'linux_arm64', 'darwin_amd64', 'darwin_arm64'):
                self.assertIn(f'archive/12.14.0/{platform}', (repo / 'metadata/vegeta.sh').read_text())
