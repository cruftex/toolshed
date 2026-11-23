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
DIGEST = '27eda854481d20806d918b30cdd417c6bed4fd15882e24f3595dc8ae7fb5d095'
URL = 'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u514-b01/OpenJDK8U-jdk_x64_linux_hotspot_8u514b01.tar.gz'


def java8_archive(path, update='514', build='01', root='jdk8u514-b01'):
    """A fake Temurin 8 JDK whose tools report like Java 8: on stderr, with 1.8.0_UPDATE."""
    with tarfile.open(path, 'w:gz') as tar:
        for name, content in [
                ('bin/java', f'#!/bin/sh\n[ "$1" = -version ] || exit 2\necho \'openjdk version "1.8.0_{update}"\' >&2\n'
                             f'echo "OpenJDK Runtime Environment (Temurin)(build 1.8.0_{update}-b{build})" >&2\n'.encode()),
                ('bin/javac', f'#!/bin/sh\necho "javac 1.8.0_{update}" >&2\n'.encode()),
                ('LICENSE', b'The GNU General Public License (GPL) test text\n')]:
            info = tarfile.TarInfo(f'{root}/' + name)
            info.mode = 0o755
            info.size = len(content)
            tar.addfile(info, io.BytesIO(content))
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Java8InstallerTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='java8 installer ')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo = self.root / 'repository with spaces'
        for name in ('tools', 'lib', 'metadata', 'pins', 'profile.d'):
            shutil.copytree(ROOT / name, self.repo / name)
        self.cache, self.bin, self.opt = (self.root / name for name in ('cache dir', 'bin dir', 'opt dir'))
        (self.repo / 'env').write_text('\n'.join(f'{key}={shlex.quote(str(value))}' for key, value in [
            ('TOOLSHED_DOWNLOAD_DIR', self.cache), ('TOOLSHED_BIN_DIR', self.bin), ('TOOLSHED_OPT_DIR', self.opt)]) + '\n')
        self.archive = self.root / 'java8.tar.gz'
        self.digest = java8_archive(self.archive)
        self.table = self.repo / 'metadata/artifacts/java8.psv'
        self.table.write_text(''.join(row.replace(DIGEST, self.digest) for row in self.table.read_text().splitlines(True)
                                      if '|/license|' not in row))
        shutil.rmtree(self.repo / 'metadata/license')
        self.home = self.opt / 'java8/8.0.514'
        self.cached = self.cache / 'linux-x64' / URL.removeprefix('https://')
        commands = self.root / 'commands'
        commands.mkdir()
        curl = commands / 'curl'
        curl.write_text('''#!/bin/bash
while (($#)); do
 case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
 shift
done
echo "$url" >> "$TEST_LOG"
case $url in
 https://api.adoptium.net/*) printf '[{"version":{"semver":"8.0.514+1"},"binary":{"image_type":"jdk","os":"linux","architecture":"x64","heap_size":"normal","package":{"name":"OpenJDK8U-jdk_x64_linux_hotspot_8u514b01.tar.gz","checksum":"%s"}}}]' "$TEST_DIGEST" > "$out" ;;
 *) cp "$TEST_ARCHIVE" "$out" ;;
esac
''')
        curl.chmod(0o755)
        self.log = self.root / 'downloads.log'
        self.env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', TEST_ARCHIVE=str(self.archive),
                        TEST_DIGEST=self.digest, TEST_LOG=str(self.log))

    def run_tool(self, action, tool, **env):
        return subprocess.run([self.repo / f'lib/{action}-tool.sh', tool], cwd=self.root, env=dict(self.env, **env),
                              capture_output=True, text=True)

    def downloads(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_install_into_opt_without_links_and_reuse_cache(self):
        result = self.run_tool('install', 'java8')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / 'bin/javac').is_file())
        self.assertFalse(self.bin.exists())
        self.assertEqual(self.downloads(), [URL])
        result = self.run_tool('install', 'java8')
        self.assertEqual(result.returncode, 0, result.stderr)
        shutil.rmtree(self.home)
        self.archive.unlink()
        result = self.run_tool('install', 'java8')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / 'bin/java').is_file())
        self.assertEqual(self.downloads(), [URL])

    def test_corrupt_cache_is_rejected(self):
        self.assertEqual(self.run_tool('install', 'java8').returncode, 0)
        shutil.rmtree(self.home)
        self.cached.write_bytes(b'corrupt')
        self.archive.write_bytes(b'still corrupt')
        result = self.run_tool('install', 'java8')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.home.exists())
        self.assertEqual(list((self.opt / 'java8').iterdir()), [])

    def test_wrong_version_is_rejected(self):
        digest = java8_archive(self.archive, update='512')
        self.table.write_text(self.table.read_text().replace(self.digest, digest))
        result = self.run_tool('install', 'java8')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('validation failed', result.stderr)
        self.assertFalse(self.home.exists())

    def test_existing_java25_links_are_preserved(self):
        self.bin.mkdir()
        (self.bin / 'java').write_text('java 25')
        result = self.run_tool('install', 'java8')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(path.name for path in self.bin.iterdir()), ['java'])
        self.assertEqual((self.bin / 'java').read_text(), 'java 25')

    def test_profile_selects_java8(self):
        self.assertEqual(self.run_tool('install', 'java8').returncode, 0)
        output = subprocess.run(['bash', '-c', 'source "$1"; printf "%s\\n" "$JAVA_HOME"; java -version 2>&1 | head -n 1',
                                 '_', self.repo / 'profile.d/java8.sh'], cwd=self.root, env=self.env,
                                capture_output=True, text=True, check=True).stdout
        self.assertEqual(output, f'{self.home}\nopenjdk version "1.8.0_514"\n')

    def test_discover_uses_adoptium_metadata(self):
        result = self.run_tool('discover', 'java8')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '8.0.514\n')
        self.assertEqual((self.repo / 'pins/java8').read_text(), '8.0.514\n')
        self.assertEqual((self.repo / 'metadata/java8-builds').read_text(), '8.0.514 01\n')
        licenses = list((self.repo / 'metadata/license').glob('*.name.txt'))
        self.assertEqual([path.read_text() for path in licenses], ['gpl-2.0-classpath\n'])
        self.assertIn('8.0.514|/license|' + licenses[0].name.split('.')[0], self.table.read_text())
        self.assertFalse(self.bin.exists())

    def test_reject_unpinned_version_and_build(self):
        result = self.run_tool('install', 'java8', TOOLSHED_OVERRIDE_TOOL_VERSION='8.0.512')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No pinned', result.stderr)
        result = self.run_tool('install', 'java8', TOOLSHED_OVERRIDE_TOOL_VERSION='25.0.5')
        self.assertNotEqual(result.returncode, 0)
        (self.repo / 'metadata/java8-builds').write_text('')
        result = self.run_tool('install', 'java8')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No pinned Temurin build', result.stderr)
        self.assertFalse(self.opt.exists())
        self.assertEqual(self.downloads(), [])


if __name__ == '__main__':
    unittest.main()
