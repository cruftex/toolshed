import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GoInstallerTests(unittest.TestCase):
    def test_discover_install_repeat_and_corruption(self):
        with tempfile.TemporaryDirectory(prefix='go install ') as temp:
            root = Path(temp)
            repo = root / 'repo'
            for name in ('install', 'lib', 'metadata', 'pins', 'discover'):
                shutil.copytree(ROOT / name, repo / name)
            values = [('TOOLSHED_DOWNLOAD_DIR', 'cache'), ('TOOLSHED_BIN_DIR', 'bin'), ('TOOLSHED_OPT_DIR', 'opt')]
            (repo / 'env').write_text('\n'.join(f'{k}={shlex.quote(str(root / v))}' for k, v in values) + '\n')
            archive = root / 'go1.28.1.linux-amd64.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name, data in [('go/bin/go', b'#!/bin/sh\nprintf "go version go1.28.1 linux/amd64\\n"\n'),
                                   ('go/bin/gofmt', b'#!/bin/sh\ncat\n'), ('go/go.env', b'GOTOOLCHAIN=auto\n')]:
                    member = tarfile.TarInfo(name)
                    member.mode = 0o755
                    member.size = len(data)
                    tar.addfile(member, io.BytesIO(data))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            release = [{'version': 'go1.28.1', 'stable': True, 'files': [{'filename': archive.name, 'kind': 'archive', 'sha256': digest}]}]
            (root / 'release.json').write_text(json.dumps(release))
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
if [[ $url == *'?'* ]]; then cp "$FIXTURE/release.json" "$out"; else cp "$FIXTURE/${url##*/}" "$out"; fi
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURE=str(root))
            pin = (repo / 'pins/go').read_text()
            for _ in range(2):
                result = subprocess.run([repo / 'discover/discover-go.sh'], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), '1.28.1')
            self.assertEqual((repo / 'pins/go').read_text(), pin)
            self.assertEqual((repo / 'metadata/go.sh').read_text().count('archive/1.28.1/linux-x64'), 1)
            env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = '1.28.1'
            curl.rename(commands / 'disabled-curl')
            result = subprocess.run([repo / 'install/install-go.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / 'bin/go').is_symlink())
            self.assertEqual((root / 'opt/go/1.28.1/go.env').read_text(), 'GOTOOLCHAIN=local\n')
            (root / 'bin/gofmt').unlink()
            result = subprocess.run([repo / 'install/install-go.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / 'bin/gofmt').is_symlink())
            original = (root / 'bin/go').readlink()
            with (repo / 'metadata/go.sh').open('a') as metadata:
                metadata.write(f'\nchecksums[archive/1.29.0/linux-x64]={digest}\n')
            (root / 'cache/go.dev/dl/go1.29.0.linux-amd64.tar.gz').write_bytes(b'bad')
            env['TOOLSHED_OVERRIDE_TOOL_VERSION'] = '1.29.0'
            result = subprocess.run([repo / 'install/install-go.sh'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((root / 'bin/go').readlink(), original)
