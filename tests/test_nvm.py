import hashlib
import io
import os
import runpy
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class NvmUpgradeTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='nvm upgrade ')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo = self.root / 'checkout with spaces'
        for name in ('install', 'lib', 'pins', 'metadata'):
            shutil.copytree(ROOT / name, self.repo / name)
        self.nvm = self.root / 'nvm with spaces'
        self.nvm.mkdir()
        (self.nvm / 'nvm.sh').write_text('nvm() { echo 0.39.3; }\n')
        (self.nvm / 'nvm-exec').write_text('old executable')
        (self.nvm / 'bash_completion').write_text('old completion')
        (self.nvm / 'versions/node/v24.0.0/bin').mkdir(parents=True)
        (self.nvm / 'versions/node/v24.0.0/bin/node').write_text('node data')
        (self.nvm / 'alias').mkdir()
        (self.nvm / 'alias/default').write_text('24')
        (self.nvm / '.npmrc').write_text('custom settings')
        (self.nvm / '.git').mkdir()
        (self.nvm / '.git/config').write_text('git data')
        self.git_cache = self.root / 'git cache'
        self.git_cache.mkdir()
        self.cache = self.root / 'cache/nvm/0.41.0/nvm-0.41.0.tar.gz'
        self.cache.parent.mkdir(parents=True)
        with tarfile.open(self.cache, 'w:gz') as tar:
            for name, data in [('nvm.sh', b'nvm() { echo 0.41.0; }\n'), ('nvm-exec', b'new executable'), ('bash_completion', b'new completion')]:
                item = tarfile.TarInfo('nvm-0.41.0/' + name)
                item.size = len(data)
                item.mode = 0o755
                tar.addfile(item, io.BytesIO(data))
        digest = hashlib.sha256(self.cache.read_bytes()).hexdigest()
        metadata = self.repo / 'metadata/nvm.sh'
        metadata.write_text(metadata.read_text().replace('6601b5bbd0af01a2faf17267e73e02b0e44f3b4fcdb85cf8f4602c6a0791909b', digest))
        (self.repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(value))}' for key, value in (
            ('TOOLSHED_NVM_DIR', self.nvm), ('TOOLSHED_NVM_GIT_DIR', self.git_cache), ('TOOLSHED_DOWNLOAD_DIR', self.root / 'cache'),
            ('TOOLSHED_OPT_DIR', self.root / 'opt'), ('TOOLSHED_BIN_DIR', self.root / 'bin'))) + '\n')
        commands = self.root / 'commands'
        commands.mkdir()
        curl = commands / 'curl'
        curl.write_text('#!/bin/sh\nexit 42\n')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}')

    def run_installer(self):
        return subprocess.run([self.repo / 'install/install-nvm.sh'], cwd=self.root, env=self.env, capture_output=True, text=True)

    def test_cached_upgrade_preserves_user_data_and_backups(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('0.41.0', (self.nvm / 'nvm.sh').read_text())
        self.assertEqual((self.nvm / 'versions/node/v24.0.0/bin/node').read_text(), 'node data')
        self.assertEqual((self.nvm / 'alias/default').read_text(), '24')
        self.assertEqual((self.nvm / '.npmrc').read_text(), 'custom settings')
        self.assertFalse((self.nvm / '.git').exists())
        backup_git, = (self.git_cache / 'legacy-checkouts').glob('nvm-*/.git/config')
        self.assertEqual(backup_git.read_text(), 'git data')
        backup, = self.nvm.glob('.toolshed-nvm-backup-*')
        self.assertIn('0.39.3', (backup / 'nvm.sh').read_text())
        self.assertEqual(self.run_installer().returncode, 0)

    def test_bad_cache_leaves_original_untouched(self):
        self.cache.write_bytes(b'corrupt')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('0.39.3', (self.nvm / 'nvm.sh').read_text())
        self.assertEqual((self.nvm / 'nvm-exec').read_text(), 'old executable')
        self.assertFalse(list(self.nvm.glob('.toolshed-nvm-backup-*')))

    def test_replacement_error_restores_old_files(self):
        source = self.root / 'new files'
        source.mkdir()
        for name in ('nvm.sh', 'nvm-exec', 'bash_completion'):
            (source / name).write_text('new ' + name)
        original_replace = os.replace
        calls = 0

        def fail_second(src, dst):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('simulated replacement failure')
            return original_replace(src, dst)

        with patch('sys.argv', ['replace-nvm.py', str(source), str(self.nvm), str(self.git_cache)]), \
                patch('os.replace', side_effect=fail_second), patch('signal.signal'):
            with self.assertRaises(OSError):
                runpy.run_path(str(self.repo / 'lib/replace-nvm.py'), run_name='__main__')
        self.assertEqual((self.nvm / 'nvm-exec').read_text(), 'old executable')
        self.assertEqual((self.nvm / 'bash_completion').read_text(), 'old completion')
        self.assertIn('0.39.3', (self.nvm / 'nvm.sh').read_text())
        self.assertFalse(list(self.nvm.glob('.toolshed-nvm-*-*')))
