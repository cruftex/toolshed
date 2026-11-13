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
ASSET = 'codex-x86_64-unknown-linux-musl'


class CodexInstallerTests(unittest.TestCase):
    def test_install_reuse_and_corruption(self):
        with tempfile.TemporaryDirectory(prefix='codex test ') as tmp:
            root = Path(tmp)
            repo = root / 'repo with spaces'
            shutil.copytree(ROOT / 'install', repo / 'install')
            shutil.copytree(ROOT / 'lib', repo / 'lib')
            cache, dest = root / 'cache', root / 'bin'
            (repo / 'env').write_text(f'DOWNLOAD_DIR={shlex.quote(str(cache))}\nDEST_BIN_DIR={shlex.quote(str(dest))}\nDEST_OPT_DIR={shlex.quote(str(root / "opt"))}\n')
            archive = root / 'archive.tar.gz'
            binary = b"#!/bin/sh\necho 'codex-cli 1.2.3'\n"
            with tarfile.open(archive, 'w:gz') as tar:
                member = tarfile.TarInfo(ASSET)
                member.size = len(binary)
                tar.addfile(member, io.BytesIO(binary))
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            metadata = root / 'release.json'
            metadata.write_text(json.dumps({'tag_name': 'rust-v1.2.3', 'draft': False, 'prerelease': False, 'assets': [{'name': ASSET + '.tar.gz', 'digest': 'sha256:' + digest}]}))
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text('''#!/bin/bash
while (($#)); do
  case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
  shift
done
if [[ $url == */latest ]]; then cp "$METADATA" "$out"; else cp "$ARCHIVE" "$out"; fi
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', METADATA=str(metadata), ARCHIVE=str(archive))
            def run():
                return subprocess.run([repo / 'install/install-codex.sh'], cwd=root, env=env, capture_output=True, text=True)
            first = run()
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual((dest / 'codex').read_bytes(), binary)
            archive.unlink()
            self.assertEqual(run().returncode, 0)
            (dest / 'codex').write_text('modified')
            self.assertEqual(run().returncode, 0)
            self.assertEqual((dest / 'codex').read_bytes(), binary)
            (cache / 'codex/1.2.3' / (ASSET + '.tar.gz')).write_bytes(b'bad')
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual((dest / 'codex').read_bytes(), binary)
