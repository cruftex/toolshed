import hashlib
import io
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MavenTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='maven installer ')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo = self.root / 'repository with spaces'
        for name in ('install', 'lib', 'metadata', 'pins', 'update'):
            shutil.copytree(ROOT / name, self.repo / name)
        self.cache, self.bin, self.opt = (self.root / name for name in ('cache', 'bin', 'opt'))
        (self.repo / 'env').write_text('\n'.join(f'{k}={shlex.quote(str(v))}' for k, v in [('TOOLSHED_DOWNLOAD_DIR', self.cache), ('TOOLSHED_BIN_DIR', self.bin), ('TOOLSHED_OPT_DIR', self.opt)]) + '\n')
        self.archive = self.root / 'archive.tar.gz'
        body = b'#!/bin/sh\necho "Apache Maven 3.9.17 (test)"\n'
        with tarfile.open(self.archive, 'w:gz') as archive:
            entry = tarfile.TarInfo('apache-maven-3.9.17/bin/mvn')
            entry.mode, entry.size = 0o755, len(body)
            archive.addfile(entry, io.BytesIO(body))
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.sha512 = hashlib.sha512(self.archive.read_bytes()).hexdigest()
        commands = self.root / 'commands'
        commands.mkdir()
        curl = commands / 'curl'
        curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
case $url in
 *maven-metadata.xml) printf '%s' '<metadata><versioning><versions><version>3.9.16</version><version>3.9.17</version><version>3.9.99-rc-1</version><version>3.10.4</version></versions></versioning></metadata>' > "$out" ;;
 *.sha512) printf '%s' "$TEST_SHA512" > "$out" ;;
 *) cp "$TEST_ARCHIVE" "$out" ;;
esac
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', TEST_ARCHIVE=str(self.archive), TEST_SHA512=self.sha512)

    def run_script(self, path):
        return subprocess.run([self.repo / path], cwd=self.root, env=self.env, capture_output=True, text=True)

    def test_updater_selects_latest_patch_and_installs(self):
        result = self.run_script('update/update-maven39.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / 'pins/maven39').read_text(), '3.9.17\n')
        self.assertEqual((self.repo / 'pins/maven310').read_text(), '3.10.0\n')
        self.assertIn(self.digest, (self.repo / 'metadata/maven.sh').read_text())
        self.assertEqual((self.bin / 'mvn').resolve(), self.opt / 'maven/3.9.17/bin/mvn')
        self.assertEqual((self.bin / 'mvn39').resolve(), self.opt / 'maven/3.9.17/bin/mvn')
        (self.bin / 'mvn').unlink()
        (self.bin / 'mvn39').unlink()
        self.archive.unlink()
        result = self.run_script('install/install-maven39.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.bin / 'mvn').is_symlink())
        self.assertTrue((self.bin / 'mvn39').is_symlink())

    def test_both_tracks_keep_their_own_entry_points(self):
        for pin, version, installer in [('maven39', '3.9.16', 'install-maven39.sh'),
                                        ('maven310', '3.10.0', 'install-maven310.sh')]:
            executable = self.opt / 'maven' / version / 'bin/mvn'
            executable.parent.mkdir(parents=True)
            executable.write_text(f'#!/bin/sh\necho "Apache Maven {version} (test)"\n')
            executable.chmod(0o755)
            result = self.run_script('install/' + installer)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.bin / 'mvn39').resolve(), self.opt / 'maven/3.9.16/bin/mvn')
        self.assertEqual((self.bin / 'mvn310').resolve(), self.opt / 'maven/3.10.0/bin/mvn')
        self.assertEqual((self.bin / 'mvn').resolve(), self.opt / 'maven/3.10.0/bin/mvn')

    def test_bad_publisher_checksum_preserves_pin_and_executable(self):
        self.bin.mkdir()
        (self.bin / 'mvn').write_text('existing')
        self.env['TEST_SHA512'] = '0' * 128
        result = self.run_script('update/update-maven39.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.repo / 'pins/maven39').read_text(), '3.9.16\n')
        self.assertEqual((self.bin / 'mvn').read_text(), 'existing')

    def test_missing_archive_pin_rejected(self):
        (self.repo / 'pins/maven39').write_text('3.9.17\n')
        result = self.run_script('install/install-maven39.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No pinned Maven archive', result.stderr)


if __name__ == '__main__':
    unittest.main()
