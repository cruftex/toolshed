import hashlib
import io
import json
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
RELEASES = 'https://github.com/adoptium/temurin25-binaries/releases/download'
API = 'https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'


def jdk_archive(path, short, build):
    """A fake Temurin 25 JDK archive whose tools print SHORT, the JEP 322 version without trailing zeros."""
    with tarfile.open(path, 'w:gz') as tar:
        for name, content in [('bin/java', f'#!/bin/sh\necho "openjdk {short} 2026-11-18 LTS"\n'.encode()),
                              ('bin/javac', f'#!/bin/sh\necho "javac {short}"\n'.encode()),
                              ('legal/java.base/LICENSE', b'GNU GENERAL PUBLIC LICENSE test text\n')]:
            info = tarfile.TarInfo(f'jdk-{short}+{build}/' + name)
            info.mode = 0o755
            info.size = len(content)
            tar.addfile(info, io.BytesIO(content))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adoptium_release(short, build, digest, security, patch=0, semver=None, **override):
    """One Adoptium API v3 asset as the latest-release endpoint returns it."""
    package = f'OpenJDK25U-jdk_x64_linux_hotspot_{short}_{build}.tar.gz'
    release = {
        'release_name': f'jdk-{short}+{build}',
        'version': {'major': 25, 'minor': 0, 'security': security, 'patch': patch, 'build': build,
                    'openjdk_version': f'{short}+{build}-LTS', 'optional': 'LTS',
                    'semver': semver or f'25.0.{security}+{build}.0.LTS'},
        'binary': {'image_type': 'jdk', 'os': 'linux', 'architecture': 'x64', 'heap_size': 'normal',
                   'package': {'name': package, 'link': f'{RELEASES}/jdk-{short}%2B{build}/{package}', 'checksum': digest}}}
    for key, value in override.items():
        target = release['binary']['package'] if key in ('link', 'name') else release['version']
        target[key] = value
    return [release]


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
        self.digest = jdk_archive(self.archive, '25.0.5', 8)
        # Keep only the pinned release, with the fake archive's digest and without its license.
        self.table = self.repo / 'metadata/artifacts/java25.psv'
        lines = self.table.read_text().splitlines(True)
        self.table.write_text(lines[0] + ''.join(
            re.sub(r'\|[0-9a-f]{64}\|', f'|{self.digest}|', row) for row in lines[1:]
            if row.startswith('25.0.5|/linux-x64/')))
        shutil.rmtree(self.repo / 'metadata/license')
        (self.repo / 'pins/java25').write_text('25.0.5\n')
        self.api = self.root / 'api.json'
        self.set_api(adoptium_release('25.0.5', 8, self.digest, security=5))
        commands = self.root / 'commands'
        commands.mkdir()
        curl = commands / 'curl'
        curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
case $url in
 https://api.adoptium.net/*) cp "$TEST_API" "$out" ;;
 *) cp "$TEST_ARCHIVE" "$out" ;;
esac
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', TEST_ARCHIVE=str(self.archive),
                        TEST_API=str(self.api))

    def set_api(self, assets):
        self.api.write_text(json.dumps(assets))

    def run_tool(self, action, tool, **env):
        return subprocess.run([self.repo / f'lib/{action}-tool.sh', tool], cwd=self.root, env=dict(self.env, **env),
                              capture_output=True, text=True)

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
        self.assertEqual(result.stdout, '25.0.5\n')
        self.assertEqual((self.repo / 'pins/java25').read_text(), '25.0.5\n')
        self.assertFalse((self.bin / 'javac').exists())
        licenses = list((self.repo / 'metadata/license').glob('*.name.txt'))
        self.assertEqual(len(licenses), 1)
        self.assertEqual(licenses[0].read_text(), 'gpl-2.0-classpath\n')
        rows = self.table.read_text()
        self.assertIn('25.0.5|/license|' + licenses[0].name.split('.')[0], rows)
        self.assertIn(f'|{RELEASES}/jdk-25.0.5%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz\n', rows)
        self.assertFalse((self.repo / 'metadata/java25-builds').exists())

    def test_patch_release_is_recorded_with_four_parts(self):
        """Adoptium's semver folds the patch into the build (25.0.5+100000002); the JEP 322 version is recorded."""
        digest = jdk_archive(self.archive, '25.0.5.1', 2)
        self.set_api(adoptium_release('25.0.5.1', 2, digest, security=5, patch=1, semver='25.0.5+100000002.0.LTS'))
        result = self.run_tool('discover', 'java25')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '25.0.5.1\n')
        url = f'{RELEASES}/jdk-25.0.5.1%2B2/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5.1_2.tar.gz'
        self.assertIn(f'25.0.5.1|/linux-x64/archive/tar.gz|{digest}|', self.table.read_text())
        self.assertIn(f'|{url}\n', self.table.read_text())
        self.assertEqual(list(json.loads((self.repo / 'metadata/provenance/java25.json').read_text()))[0],
                         '25.0.5.1/linux-x64')
        # The recorded release installs by override and validates against `openjdk 25.0.5.1`.
        result = self.run_tool('install', 'java25', TOOLSHED_OVERRIDE_TOOL_VERSION='25.0.5.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.bin / 'java').resolve(), self.opt / 'java25/25.0.5.1/bin/java')

    def test_ga_release_is_recorded_with_three_parts(self):
        digest = jdk_archive(self.archive, '25', 36)
        self.set_api(adoptium_release('25', 36, digest, security=0))
        result = self.run_tool('discover', 'java25')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '25.0.0\n')
        self.assertIn(f'25.0.0|/linux-x64/archive/tar.gz|{digest}|', self.table.read_text())
        self.assertIn(f'|{RELEASES}/jdk-25%2B36/OpenJDK25U-jdk_x64_linux_hotspot_25_36.tar.gz\n', self.table.read_text())
        result = self.run_tool('install', 'java25', TOOLSHED_OVERRIDE_TOOL_VERSION='25.0.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.opt / 'java25/25.0.0/bin/java').is_file())

    def test_discovery_rejects_inconsistent_metadata(self):
        before = self.table.read_text()
        for override in ({'link': 'https://example.com/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz'},
                         {'openjdk_version': '25.0.5.1+8-LTS'},
                         {'patch': 1},
                         {'major': 26},
                         {'name': 'OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_9.tar.gz'}):
            with self.subTest(override=override):
                self.set_api(adoptium_release('25.0.5', 8, self.digest, security=5, **override))
                result = self.run_tool('discover', 'java25')
                self.assertNotEqual(result.returncode, 0)
                self.assertRegex(result.stderr, 'Invalid Temurin release metadata|Cannot identify Temurin Java 25')
        self.assertEqual(self.table.read_text(), before)

    def test_install_needs_recorded_url(self):
        self.table.write_text(re.sub(r'\|https://[^\n]*', '|', self.table.read_text()))
        result = self.run_tool('install', 'java25')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No recorded URL for java25 25.0.5/linux-x64', result.stderr)
        self.assertFalse(self.cache.exists())
        self.assertFalse(self.opt.exists())

    def test_reject_unpinned_and_invalid_versions(self):
        (self.repo / 'pins/java25').write_text('25.0.6\n')
        result = self.run_tool('install', 'java25')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No pinned', result.stderr)
        for version in ('25', '25.0', '25.0.5.1.0.1', '25.0.5-ea'):
            with self.subTest(version=version):
                result = self.run_tool('install', 'java25', TOOLSHED_OVERRIDE_TOOL_VERSION=version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Invalid TOOLSHED_OVERRIDE_TOOL_VERSION', result.stderr)
        result = self.run_tool('install', 'java8', TOOLSHED_OVERRIDE_TOOL_VERSION='8.0.514.1')
        self.assertIn('Invalid TOOLSHED_OVERRIDE_TOOL_VERSION', result.stderr)
        self.assertFalse(self.bin.exists())
