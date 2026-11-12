"""Isolated tests for SDKMAN bootstrap and the Java wrapper."""
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INIT = '''#!/bin/bash
unused=$SDKMAN_TEST_UNSET
sdk() {
    if [[ $1 == version ]]; then echo 'SDKMAN 5.24.0'; return; fi
    [[ $* == 'install java 25.0.5.0-oracle' ]] || return 1
    [[ $USE == n && $sdkman_checksum_enable == true && $sdkman_selfupdate_feature == false ]] || return 1
    echo install >> "$SDKMAN_DIR/calls"
    [[ ${JAVA_FAIL:-} != true ]] || return 22
    local jdk_home="$SDKMAN_DIR/candidates/java/$3"
    mkdir -p "$jdk_home/bin"
    printf '#!/bin/sh\\nprintf "java 25.0.5 2026-10-20\\\\n"\\n' > "$jdk_home/bin/java"
    printf '#!/bin/sh\\nprintf "javac 25.0.5\\\\n"\\n' > "$jdk_home/bin/javac"
    chmod +x "$jdk_home/bin/"*
}
'''


class SDKMANTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='sdkman tests ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / 'repository with spaces'
        for folder in ('install', 'lib'):
            shutil.copytree(ROOT / folder, self.repo / folder)
        self.sdkman = self.root / 'sdkman home'
        self.cache = self.root / 'download cache'
        self.staging = self.root / 'staging'
        self.staging.mkdir()
        (self.repo / 'env').write_text(
            '\n'.join(f'{key}={shlex.quote(str(value))}' for key, value in {
                'DOWNLOAD_DIR': self.cache, 'SDKMAN_DIR': self.sdkman,
                'DEST_BIN_DIR': self.root / 'bin', 'DEST_OPT_DIR': self.root / 'opt',
            }.items()) + '\n')
        self.environment = dict(os.environ, TMPDIR=str(self.staging))
        self.environment.pop('SDKMAN_TEST_UNSET', None)
        self.script_zip = self.root / 'scripts.zip'
        self.native_zip = self.root / 'native.zip'
        with zipfile.ZipFile(self.script_zip, 'w') as z:
            for name, content in {'bin/sdkman-init.sh': INIT, 'src/sdkman-main.sh': '# main\n'}.items():
                z.writestr('sdkman-5.24.0/' + name, content)
        with zipfile.ZipFile(self.native_zip, 'w') as z:
            z.writestr('sdkman-cli-native-0.8.0-x86_64-unknown-linux-gnu/libexec/placeholder', 'native')
        installer = self.repo / 'install/install-sdkman.sh'
        text = installer.read_text()
        for original, fixture in [
            ('b765ef213c7b3dd731815e42f398b6e2eef1053b38d32ecc09a9f6d51c8ee948', self.script_zip),
            ('91cc56bce077fb605172d6bb3182ab2a1b1711d64f12a8bbb1910dc11d561397', self.native_zip),
        ]:
            text = text.replace(original, hashlib.sha256(fixture.read_bytes()).hexdigest())
        installer.write_text(text)
        self.commands = self.root / 'commands'
        self.commands.mkdir()
        curl = self.commands / 'curl'
        curl.write_text('''#!/bin/bash
while (( $# )); do
    if [[ $1 == https://* ]]; then url=$1; fi
    if [[ $1 == --output ]]; then output=$2; shift; fi
    shift
done
mode=${DOWNLOAD_MODE:-valid}
if [[ ${CATALOG_ONLY:-} && $url != */candidates/all ]]; then mode=valid; fi
case $mode in
 fail) exit 22 ;;
 interrupt) kill -TERM "$PPID"; exit 143 ;;
esac
case $url in
 */candidates/all) printf 'java,maven,gradle' > "$output" ;;
 *sdkman-cli-native*) cp "$NATIVE_ZIP" "$output" ;;
 *) cp "$SCRIPT_ZIP" "$output" ;;
esac
''')
        curl.chmod(0o755)
        self.environment.update(PATH=f"{self.commands}:{os.environ['PATH']}",
                                NATIVE_ZIP=str(self.native_zip), SCRIPT_ZIP=str(self.script_zip))

    def run_installer(self, name='java25', **env):
        return subprocess.run([self.repo / f'install/install-{name}.sh'], cwd=self.root,
                              env=dict(self.environment, **env), text=True,
                              capture_output=True, timeout=30)

    def test_fresh_install_repeat_and_no_default(self):
        first = self.run_installer()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertFalse((self.sdkman / 'candidates/java/current').exists())
        second = self.run_installer(DOWNLOAD_MODE='fail')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.sdkman / 'calls').read_text(), 'install\n')
        self.assertEqual(list(self.staging.iterdir()), [])
        self.assertFalse(list(self.root.glob('dev-environment.*')))

    def test_preserve_existing_default_and_manager(self):
        self.assertEqual(self.run_installer('sdkman').returncode, 0)
        version = self.sdkman / 'var/version'
        version.write_text('5.19.0\n')
        current = self.sdkman / 'candidates/java/current'
        current.parent.mkdir()
        current.symlink_to('old-version')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(current), 'old-version')
        self.assertEqual(version.read_text(), '5.19.0\n')

    def test_download_failure_and_interrupt_leave_no_install(self):
        for mode in ('fail', 'interrupt'):
            with self.subTest(mode=mode):
                result = self.run_installer('sdkman', DOWNLOAD_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.sdkman.exists())
                self.assertFalse(list(self.cache.rglob('.download.*')))

    def test_corrupt_cached_archive_is_rejected(self):
        cached = self.cache / 'sdkman/5.24.0/linux-x64/sdkman-cli.zip'
        cached.parent.mkdir(parents=True)
        cached.write_bytes(b'corrupt')
        result = self.run_installer('sdkman')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SHA-256 verification failed', result.stderr)
        self.assertFalse(self.sdkman.exists())

    def test_late_failure_cleans_staging(self):
        for mode in ('fail', 'interrupt'):
            with self.subTest(mode=mode):
                result = self.run_installer('sdkman', DOWNLOAD_MODE=mode, CATALOG_ONLY='true')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.sdkman.exists())
                self.assertFalse(list(self.root.glob('dev-environment.*')))

    def test_invalid_zip_with_matching_digest_is_not_promoted(self):
        previous = hashlib.sha256(self.script_zip.read_bytes()).hexdigest()
        self.script_zip.write_bytes(b'not a zip')
        digest = hashlib.sha256(self.script_zip.read_bytes()).hexdigest()
        installer = self.repo / 'install/install-sdkman.sh'
        installer.write_text(installer.read_text().replace(previous, digest))
        result = self.run_installer('sdkman')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cannot extract', result.stderr)
        self.assertFalse(self.sdkman.exists())
        self.assertFalse(list(self.root.glob('dev-environment.*')))

    def test_partial_manager_and_partial_java_are_preserved(self):
        self.sdkman.mkdir()
        marker = self.sdkman / 'marker'
        marker.write_text('keep')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), 'keep')
        marker.unlink()
        self.sdkman.rmdir()
        self.assertEqual(self.run_installer('sdkman').returncode, 0)
        home = self.sdkman / 'candidates/java/25.0.5.0-oracle'
        home.mkdir(parents=True)
        (home / 'marker').write_text('keep')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((home / 'marker').read_text(), 'keep')

    def test_sdk_install_failure_is_propagated(self):
        result = self.run_installer(JAVA_FAIL='true')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.sdkman / 'candidates/java/current').exists())

    def test_unsupported_platform_fails_before_download(self):
        uname = self.commands / 'uname'
        uname.write_text('#!/bin/sh\necho unsupported\n')
        uname.chmod(0o755)
        result = self.run_installer('sdkman')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.cache.exists())

