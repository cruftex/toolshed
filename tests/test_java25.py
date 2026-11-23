import hashlib
import io
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class JavaInstallerTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='java installer ')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo = self.root / 'repository with spaces'
        for name in ('tools', 'lib', 'metadata', 'pins', 'profile.d'):
            shutil.copytree(ROOT / name, self.repo / name)
        self.cache, self.bin, self.opt = (self.root / name for name in ('cache', 'bin', 'opt'))
        (self.repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(value))}' for key, value in [('TOOLSHED_DOWNLOAD_DIR', self.cache), ('TOOLSHED_BIN_DIR', self.bin), ('TOOLSHED_OPT_DIR', self.opt)]) + '\n')
        self.archive = self.root / 'java.tar.gz'
        with tarfile.open(self.archive, 'w:gz') as tar:
            for name, content in [('bin/java', b'#!/bin/sh\necho "openjdk 25.0.5 2026-10-20"\n'), ('bin/javac', b'#!/bin/sh\necho "javac 25.0.5"\n'),
                                  ('legal/java.base/LICENSE', b'GNU GENERAL PUBLIC LICENSE test text\n')]:
                info = tarfile.TarInfo('jdk-25.0.5+8/' + name)
                info.mode = 0o755
                info.size = len(content)
                tar.addfile(info, io.BytesIO(content))
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        artifact_table = self.repo / 'metadata/artifacts/java25.psv'
        artifact_table.write_text(artifact_table.read_text().replace('68982529869257d0ee6b824ec5aa270ff8b118bb438670da0b97ebdab178d7fb', digest))
        artifact_table.write_text(''.join(row for row in artifact_table.read_text().splitlines(True) if '|/license|' not in row))
        shutil.rmtree(self.repo / 'metadata/license')
        commands = self.root / 'commands'
        commands.mkdir()
        curl = commands / 'curl'
        curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
case $url in
 https://api.adoptium.net/*) printf '[{"version":{"semver":"25.0.5+8.0.LTS"},"binary":{"image_type":"jdk","os":"linux","architecture":"x64","heap_size":"normal","package":{"name":"OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz","link":"%s","checksum":"%s"}}}]' "${TEST_LINK:-https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz}" "$TEST_DIGEST" > "$out" ;;
 *) cp "$TEST_ARCHIVE" "$out" ;;
esac
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', TEST_ARCHIVE=str(self.archive), TEST_DIGEST=digest)

    def run_tool(self, action, tool):
        return subprocess.run([self.repo / f'lib/{action}-tool.sh', tool], cwd=self.root, env=self.env, capture_output=True, text=True)

    def test_install_repeat_and_repair_entry_points(self):
        result = self.run_tool('install', 'java25')
        self.assertEqual(result.returncode, 0, result.stderr)
        java = self.opt / 'java25/25.0.5/bin/java'
        self.assertTrue(java.is_file())
        self.assertEqual((self.bin / 'java').resolve(), java)
        self.archive.unlink()
        (self.bin / 'java').unlink()
        result = self.run_tool('install', 'java25')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.bin / 'java').resolve(), java)

    def test_bad_archive_preserves_existing_links(self):
        self.bin.mkdir()
        (self.bin / 'java').write_text('existing')
        self.archive.write_bytes(b'corrupt')
        result = self.run_tool('install', 'java25')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.bin / 'java').read_text(), 'existing')
        self.assertFalse((self.opt / 'java25/25.0.5').exists())

    def test_update_uses_adoptium_metadata(self):
        result = self.run_tool('discover', 'java25')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / 'pins/java25').read_text(), '25.0.5\n')
        self.assertFalse((self.bin / 'javac').exists())
        licenses = list((self.repo / 'metadata/license').glob('*.name.txt'))
        self.assertEqual(len(licenses), 1)
        self.assertEqual(licenses[0].read_text(), 'gpl-2.0-classpath\n')
        rows = (self.repo / 'metadata/artifacts/java25.psv').read_text()
        self.assertIn('25.0.5|/license|' + licenses[0].name.split('.')[0], rows)
        self.assertIn('|https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/'
                      'OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz\n', rows)
        self.assertFalse((self.repo / 'metadata/java25-builds').exists())

    def test_discovery_rejects_unexpected_download_link(self):
        table = self.repo / 'metadata/artifacts/java25.psv'
        before = table.read_text()
        self.env['TEST_LINK'] = 'https://example.com/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz'
        result = self.run_tool('discover', 'java25')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Invalid Temurin release metadata', result.stderr)
        self.assertEqual(table.read_text(), before)

    def test_install_needs_recorded_url(self):
        table = self.repo / 'metadata/artifacts/java25.psv'
        table.write_text(re.sub(r'\|https://[^\n]*', '|', table.read_text()))
        result = self.run_tool('install', 'java25')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No recorded URL for java25 25.0.5/linux-x64', result.stderr)
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.opt.exists())

    def test_reject_unpinned_version(self):
        (self.repo / 'pins/java25').write_text('25.0.6\n')
        result = self.run_tool('install', 'java25')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No pinned', result.stderr)
        self.assertFalse(self.bin.exists())
