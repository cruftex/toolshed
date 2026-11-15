"""Offline helper tests; set BUN_TEST_ARCHIVE for the real Bun smoke test."""

import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="installer tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repository with spaces"
        for directory in ("install", "lib", "metadata", "pins", "discover"):
            shutil.copytree(ROOT / directory, self.repo / directory)
        self.downloads = self.root / "download cache"
        self.bin = self.root / "destination bin"
        self.staging = self.root / "temporary staging"
        self.staging.mkdir()
        (self.repo / "env").write_text(
            f"TOOLSHED_DOWNLOAD_DIR={shlex.quote(str(self.downloads))}\n"
            f"TOOLSHED_BIN_DIR={shlex.quote(str(self.bin))}\n"
            f"TOOLSHED_OPT_DIR={shlex.quote(str(self.root / 'opt'))}\n"
            f"TOOLSHED_CLAUDE_SETTINGS={shlex.quote(str(self.root / 'home/.claude/settings.json'))}\n"
        )
        self.archive = self.root / "fixture.zip"
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("tool/bin/tool", "#!/bin/sh\nprintf '1.2.3\\n'\n")
            archive.writestr("../must-not-extract", "unrelated member")
        self.sha = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.cache = self.downloads / "tool-1.2.3.zip"
        self.commands = self.root / "mock commands"
        self.commands.mkdir()
        curl = self.commands / "curl"
        curl.write_text(
            "#!/bin/bash\n"
            "printf 'called\\n' >> \"$CURL_CALLS\"\n"
            "while (( $# )); do\n"
            "  if [[ $1 == https://* ]]; then url=$1; fi\n"
            "  if [[ $1 == --output ]]; then output=$2; shift; fi\n"
            "  shift\n"
            "done\n"
            "source=$TEST_ARCHIVE\n"
            "if [[ ${SIGNED_RELEASE:-} ]]; then\n"
            "  case $url in\n"
            "    */latest) source=$SIGNED_RELEASE/latest ;;\n"
            "    */manifest.json) source=$SIGNED_RELEASE/manifest.json ;;\n"
            "    */manifest.json.sig) source=$SIGNED_RELEASE/manifest.json.sig ;;\n"
            "    */claude-code.asc) source=$SIGNED_RELEASE/key.asc ;;\n"
            "  esac\n"
            "fi\n"
            "mode=${DOWNLOAD_MODE:-valid}\n"
            "if [[ ${DOWNLOAD_MATCH:-} && $url != *\"$DOWNLOAD_MATCH\" ]]; then mode=valid; fi\n"
            "case $mode in\n"
            " valid) cp -- \"$source\" \"$output\" ;;\n"
            " corrupt) printf 'corrupt' > \"$output\" ;;\n"
            " fail) printf 'partial' > \"$output\"; exit 22 ;;\n"
            " interrupt) printf 'partial' > \"$output\"; kill -TERM \"$PPID\"; exit 143 ;;\n"
            "esac\n"
        )
        curl.chmod(0o755)
        self.calls = self.root / "curl calls"
        self.env = dict(
            os.environ,
            PATH=f"{self.commands}:{os.environ['PATH']}",
            TMPDIR=str(self.staging),
            TEST_LIBRARY=str(self.repo / "lib/install.sh"),
            TEST_ARCHIVE=str(self.archive),
            TEST_CACHE=str(self.cache),
            TEST_SHA=self.sha,
            CURL_CALLS=str(self.calls),
        )

    def run_helper(self, script, **environment):
        return subprocess.run(
            ["bash", "-c", 'set -euo pipefail; source "$TEST_LIBRARY"; ' + script],
            cwd=self.root,
            env=dict(self.env, **environment),
            capture_output=True,
            text=True,
            timeout=30,
        )

    def download(self, **environment):
        return self.run_helper(
            'download_verified https://example.invalid/tool.zip "$TEST_SHA" "$TEST_CACHE"',
            **environment,
        )

    def assert_no_temporary_files(self):
        self.assertEqual(list(self.staging.iterdir()), [])
        for directory in (self.downloads, self.bin):
            if directory.exists():
                self.assertFalse([p for p in directory.iterdir() if p.name.startswith(".")])
                self.assertFalse([p for p in directory.rglob("*") if p.name.startswith(
                    (".download.", ".install.", ".link.", "dev-environment.")
                )])

    def test_download_and_cache_reuse(self):
        first = self.download()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(self.cache.read_bytes(), self.archive.read_bytes())
        second = self.download(DOWNLOAD_MODE="fail")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["called"])
        self.assert_no_temporary_files()

    def test_corrupt_cache_is_rejected_without_downloading(self):
        self.downloads.mkdir()
        self.cache.write_bytes(b"corrupt")
        result = self.download()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 verification failed", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_platform_cache_migrates_verified_legacy_file_offline(self):
        legacy = self.downloads / 'example.com/releases/1.2.3/archive.zip'
        legacy.parent.mkdir(parents=True)
        legacy.write_bytes(self.archive.read_bytes())
        result = self.run_helper(
            'url=https://example.com/releases/1.2.3/archive.zip; '
            'destination=$(cache_path "$url"); '
            f'download_verified "$url" {self.sha} "$destination"',
            DOWNLOAD_MODE='fail')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.downloads / 'linux-x64/example.com/releases/1.2.3/archive.zip').read_bytes(), legacy.read_bytes())
        self.assertFalse(self.calls.exists())

    def test_failed_downloads_are_never_cached(self):
        for mode in ("corrupt", "fail", "interrupt"):
            with self.subTest(mode=mode):
                result = self.download(DOWNLOAD_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.cache.exists())
                self.assert_no_temporary_files()

    def test_staged_install_and_relative_symlink(self):
        result = self.run_helper(
            'extract_zip_member "$TEST_ARCHIVE" tool/bin/tool binary; '
            'verify_version "$binary" 1.2.3; '
            'install_binary "$binary" tool; install_symlink tool toolx'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.bin / "toolx"), "tool")
        self.assertTrue(os.access(self.bin / "tool", os.X_OK))
        self.assertEqual(subprocess.check_output([self.bin / "toolx"], text=True), "1.2.3\n")
        self.assertFalse((self.root / "must-not-extract").exists())
        self.assert_no_temporary_files()

    def test_extraction_and_version_errors_preserve_existing_binary(self):
        self.bin.mkdir()
        existing = self.bin / "tool"
        existing.write_text("existing installation")
        for member, version in (("missing-member", "1.2.3"), ("tool/bin/tool", "9.9.9")):
            with self.subTest(member=member, version=version):
                result = self.run_helper(
                    f'extract_zip_member "$TEST_ARCHIVE" {member} binary; '
                    f'verify_version "$binary" {version}; install_binary "$binary" tool'
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(existing.read_text(), "existing installation")
                self.assert_no_temporary_files()

    def test_atomic_replacement_does_not_follow_destination_symlink(self):
        self.bin.mkdir()
        other = self.root / "other executable"
        other.write_text("leave alone")
        (self.bin / "tool").symlink_to(other)
        result = self.run_helper(
            'extract_zip_member "$TEST_ARCHIVE" tool/bin/tool binary; '
            'install_binary "$binary" tool'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.bin / "tool").is_symlink())
        self.assertEqual(other.read_text(), "leave alone")
        self.assert_no_temporary_files()

    def test_unsupported_platform_is_rejected(self):
        result = self.run_helper("require_platform UnsupportedOS x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires UnsupportedOS x86_64", result.stderr)
        self.assertFalse(self.downloads.exists())

    def test_platform_asset_names_and_unsupported_hosts(self):
        uname = self.commands / "uname"
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo "$MOCK_OS";; -m) echo "$MOCK_ARCH";; esac\n')
        uname.chmod(0o755)
        getconf = self.commands / "getconf"
        getconf.write_text('#!/bin/sh\nexit "${MOCK_LIBC_STATUS:-0}"\n')
        getconf.chmod(0o755)
        cases = (
            ("Linux", "x86_64", "0", "linux-x64"),
            ("Linux", "amd64", "0", "linux-x64"),
            ("Linux", "aarch64", "0", "linux-aarch64"),
            ("Darwin", "arm64", "0", "darwin-aarch64"),
            ("Darwin", "x86_64", "0", "darwin-x64"),
            ("Linux", "riscv64", "0", None),
            ("UnknownOS", "x86_64", "0", None),
            ("Linux", "x86_64", "1", None),
        )
        for system, arch, libc_status, expected in cases:
            with self.subTest(system=system, arch=arch, libc_status=libc_status):
                result = self.run_helper(
                    "platform_string", MOCK_OS=system, MOCK_ARCH=arch,
                    MOCK_LIBC_STATUS=libc_status,
                )
                if expected:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), expected)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")

    def test_unpinned_bun_platform_fails_before_download(self):
        uname = self.commands / "uname"
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo aarch64;; esac\n')
        uname.chmod(0o755)
        result = subprocess.run(
            [self.repo / "install/install-bun.sh"], cwd=self.root,
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No pinned Bun checksums for 1.4.4/linux-aarch64", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.bin.exists())

    def test_unpinned_bun_version_fails_before_download(self):
        installer = self.repo / "install/install-bun.sh"
        (self.repo / "pins/bun").write_text("9.9.9\n")
        result = subprocess.run(
            [installer], cwd=self.root, env=self.env,
            capture_output=True, text=True, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No pinned Bun checksums for 9.9.9/linux-x64", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.bin.exists())

    def test_additional_checksum_pair_selects_version_platform_and_binary(self):
        # A synthetic release tests table lookup without claiming a real ARM pin.
        binary = b"#!/bin/sh\nprintf '9.9.9\\n'\n"
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("bun-linux-aarch64/bun", binary)
        archive_digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        binary_digest = hashlib.sha256(binary).hexdigest()
        installer = self.repo / "install/install-bun.sh"
        original_pin = (self.repo / "pins/bun").read_text()
        with (self.repo / 'metadata/artifacts/bun.psv').open('a') as f:
            f.write(f'9.9.9|/linux-aarch64/archive/zip|{archive_digest}|\n')
        uname = self.commands / "uname"
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo aarch64;; esac\n')
        uname.chmod(0o755)
        result = subprocess.run(
            [installer], cwd=self.root, env=dict(self.env, TOOLSHED_OVERRIDE_TOOL_VERSION='9.9.9'),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / "pins/bun").read_text(), original_pin)
        self.assertEqual((self.bin / "bun").read_bytes(), binary)
        self.assertEqual((self.downloads / "linux-aarch64/github.com/oven-sh/bun/releases/download/bun-v9.9.9/bun-linux-aarch64.zip").read_bytes(), self.archive.read_bytes())
        self.assertEqual(subprocess.check_output([self.bin / "bunx", "--version"], text=True), "9.9.9\n")
        self.assert_no_temporary_files()

    def test_binary_identity_uses_digest_and_executable_permission(self):
        self.bin.mkdir()
        installed = self.bin / "tool"
        with zipfile.ZipFile(self.archive) as archive:
            installed.write_bytes(archive.read("tool/bin/tool"))
        digest = hashlib.sha256(installed.read_bytes()).hexdigest()
        installed.chmod(0o755)
        result = self.run_helper(f"binary_is_installed tool {digest}")
        self.assertEqual(result.returncode, 0, result.stderr)
        installed.chmod(0o644)
        self.assertNotEqual(self.run_helper(f"binary_is_installed tool {digest}").returncode, 0)
        installed.chmod(0o755)
        with installed.open("a") as binary:
            binary.write("# modified, same version output\n")
        self.assertEqual(subprocess.check_output([installed], text=True), "1.2.3\n")
        self.assertNotEqual(self.run_helper(f"binary_is_installed tool {digest}").returncode, 0)

    def test_version_selection_and_invalid_override(self):
        default = (self.repo / "pins/bun").read_text().strip()
        result = self.run_helper('select_install_version bun')
        self.assertEqual(result.stdout.strip(), default)
        result = self.run_helper('select_install_version bun', TOOLSHED_OVERRIDE_TOOL_VERSION='9.9.9')
        self.assertEqual(result.stdout.strip(), '9.9.9')
        self.assertEqual((self.repo / 'pins/bun').read_text().strip(), default)
        for invalid in ('', '../1.2.3', 'latest'):
            result = self.run_helper('select_install_version bun', TOOLSHED_OVERRIDE_TOOL_VERSION=invalid)
            self.assertNotEqual(result.returncode, 0)

    def test_override_without_recorded_checksum_rejected_before_download(self):
        result = subprocess.run([self.repo / 'install/install-bun.sh'], cwd=self.root,
                                env=dict(self.env, TOOLSHED_OVERRIDE_TOOL_VERSION='9.9.9'),
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No pinned Bun checksums', result.stderr)
        self.assertFalse(self.calls.exists())

    def test_binary_digest_failure_prevents_execution_and_replacement(self):
        self.bin.mkdir()
        installed = self.bin / "tool"
        installed.write_text("existing executable")
        result = self.run_helper(
            'extract_zip_member "$TEST_ARCHIVE" tool/bin/tool binary; '
            'verify_sha256 "$binary" ' + "0" * 64 + '; '
            'verify_version "$binary" 1.2.3; install_binary "$binary" tool'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 verification failed", result.stderr)
        self.assertEqual(installed.read_text(), "existing executable")
        self.assert_no_temporary_files()

    def test_missing_prerequisite_is_reported(self):
        result = self.run_helper("_installer_require nonexistent-installer-utility")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Required utility not found", result.stderr)

    def test_cache_paths_distinguish_hosts_and_vendors_and_reject_unsafe_urls(self):
        for url in ("https://github.com/vendor-one/tool/releases/v1/file.zip",
                    "https://github.com/vendor-two/tool/releases/v1/file.zip",
                    "https://example.com/vendor-one/tool/releases/v1/file.zip"):
            result = self.run_helper(f"cache_path {url}")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.downloads / "linux-x64" / url.removeprefix("https://")))
        for url in ("https://example.com/a/../file", "https://example.com/a/file?x=1", "http://example.com/a/file"):
            result = self.run_helper(f"cache_path '{url}'")
            self.assertNotEqual(result.returncode, 0)

    def test_bun_checksum_failure_preserves_existing_installation(self):
        self.downloads.mkdir()
        cache = self.downloads / "github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip"
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"corrupt")
        self.bin.mkdir()
        (self.bin / "bun").write_text("previous Bun")
        result = subprocess.run(
            [self.repo / "install/install-bun.sh"], cwd=self.root,
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 verification failed", result.stderr)
        self.assertEqual((self.bin / "bun").read_text(), "previous Bun")
        self.assert_no_temporary_files()

    def prepare_claude_fixture(self):
        # Installer integration uses a signature mock; publisher signatures are
        # verified by the separate real-GPG test below, without private keys.
        release = self.root / "signed release"
        release.mkdir()
        binary = b"#!/bin/sh\nprintf '2.1.322 (Claude Code)\\n'\n"
        (release / "claude").write_bytes(binary)
        (release / "latest").write_text("2.1.322")
        (self.repo / "pins/claude").write_text("2.1.322\n")
        (release / "key.asc").write_text("31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE")
        digest = hashlib.sha256(binary).hexdigest()
        self.write_mock_manifest(release, {"version": "2.1.322", "platforms": {
            platform: {"checksum": digest} for platform in ("linux-x64", "linux-arm64")
        }})
        gpg = self.commands / "gpg"
        gpg.write_text("""#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import sys
if '--show-keys' in sys.argv:
    print('fpr:::::::::' + Path(sys.argv[-1]).read_text() + ':')
elif '--verify' in sys.argv:
    expected = Path(sys.argv[-2]).read_text()
    actual = hashlib.sha256(Path(sys.argv[-1]).read_bytes()).hexdigest()
    print('[GNUPG:] VALIDSIG ' + os.environ.get('GPG_SIGNER', '31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE'))
    sys.exit(0 if actual == expected else 1)
elif '--import' not in sys.argv:
    sys.exit(2)
""")
        gpg.chmod(0o755)
        self.env.update(HOME=str(self.root / "home"), SIGNED_RELEASE=str(release),
                        TEST_ARCHIVE=str(release / "claude"))
        return self.repo / "install/install-claude.sh", release, binary

    def write_mock_manifest(self, release, manifest):
        data = json.dumps(manifest).encode()
        (release / "manifest.json").write_bytes(data)
        (release / "manifest.json.sig").write_text(hashlib.sha256(data).hexdigest())

    def run_claude(self, **environment):
        return subprocess.run(
            [self.repo / "install/install-claude.sh"], cwd=self.root,
            env=dict(self.env, **environment), capture_output=True, text=True, timeout=30,
        )

    def test_real_gpg_signature_and_tampering_without_agent(self):
        fixtures = ROOT / "tests/fixtures/claude"
        data = self.root / "manifest.json"
        data.write_bytes((fixtures / "manifest.json").read_bytes())
        script = ('verify_gpg_signature "$MANIFEST" "$FIXTURES/manifest.json.sig" '
                  '"$FIXTURES/key.asc" "$FINGERPRINT"')
        environment = dict(MANIFEST=str(data), FIXTURES=str(fixtures),
                           FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE")
        valid = self.run_helper(script, **environment)
        self.assertEqual(valid.returncode, 0, valid.stderr)
        wrong_key = self.run_helper(script, **dict(environment, FINGERPRINT="0" * 40))
        self.assertNotEqual(wrong_key.returncode, 0)
        self.assertIn("Invalid signing key fingerprint", wrong_key.stderr)
        data.write_bytes(data.read_bytes() + b" ")
        tampered = self.run_helper(script, **environment)
        self.assertNotEqual(tampered.returncode, 0)
        self.assertIn("signature verification failed", tampered.stderr)
        self.assert_no_temporary_files()

    def test_claude_rejects_signature_from_extra_key(self):
        self.prepare_claude_fixture()
        result = self.run_claude(GPG_SIGNER="0" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not signed by the expected key", result.stderr)
        self.assertFalse(self.bin.exists())
        self.assert_no_temporary_files()

    def test_claude_latest_install_repeat_cache_and_modified_binary(self):
        _, _, binary = self.prepare_claude_fixture()
        settings = Path(self.env["HOME"]) / ".claude/settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text('{"theme": "dark", "env": {"OTHER": "keep"}}')
        settings.chmod(0o640)
        first = self.run_claude()
        self.assertEqual(first.returncode, 0, first.stderr)
        installed = self.bin / "claude"
        self.assertEqual(installed.read_bytes(), binary)
        self.assertTrue(os.access(installed, os.X_OK))
        self.assertEqual(json.loads(settings.read_text()), {
            "theme": "dark", "env": {"OTHER": "keep", "DISABLE_UPDATES": "1"},
        })
        self.assertEqual(settings.stat().st_mode & 0o777, 0o640)
        cache = self.downloads / "linux-x64/downloads.claude.ai/claude-code-releases/2.1.322/linux-x64/claude"
        self.assertEqual(cache.read_bytes(), binary)
        # Reinstall modified bytes from cache without downloading metadata/binary.
        self.calls.unlink()
        installed.write_bytes(binary + b"# modified, same version\n")
        reinstall = self.run_claude()
        self.assertEqual(reinstall.returncode, 0, reinstall.stderr)
        self.assertEqual(installed.read_bytes(), binary)
        self.assertFalse(self.calls.exists())
        # A matching installation does not need the binary download cache.
        cache.unlink()
        before = installed.stat()
        repeat = self.run_claude()
        self.assertEqual(repeat.returncode, 0, repeat.stderr)
        self.assertEqual(installed.stat().st_ino, before.st_ino)
        self.assertFalse(self.calls.exists())
        self.assert_no_temporary_files()

    def test_claude_verification_failures_preserve_existing_binary(self):
        installer, release, binary = self.prepare_claude_fixture()
        self.bin.mkdir()
        installed = self.bin / "claude"
        installed.write_text("existing installation")
        original_script = installer.read_text()
        original_manifest = (release / "manifest.json").read_bytes()
        original_signature = (release / "manifest.json.sig").read_bytes()
        cases = (
            ("fingerprint", "Invalid signing key fingerprint"),
            ("signature", "signature verification failed"),
            ("manifest version", "Signed manifest version"),
            ("manifest digest", "Invalid SHA-256"),
            ("binary", "SHA-256 verification failed"),
            ("version", "Expected version"),
        )
        for failure, message in cases:
            with self.subTest(failure=failure):
                shutil.rmtree(self.downloads, ignore_errors=True)
                script = original_script
                (release / "manifest.json").write_bytes(original_manifest)
                (release / "manifest.json.sig").write_bytes(original_signature)
                (release / "claude").write_bytes(binary)
                if failure == "fingerprint":
                    script = script.replace("31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE", "0" * 40)
                elif failure == "signature":
                    (release / "manifest.json").write_bytes(original_manifest + b" ")
                elif failure.startswith("manifest"):
                    manifest = json.loads(original_manifest)
                    if failure == "manifest version":
                        manifest["version"] = "0.0.0"
                    else:
                        manifest["platforms"]["linux-x64"]["checksum"] = "invalid"
                    self.write_mock_manifest(release, manifest)
                elif failure == "binary":
                    (release / "claude").write_bytes(b"corrupt")
                elif failure == "version":
                    script = script.replace('"$version (Claude Code)"', '"unexpected version"')
                installer.write_text(script)
                result = self.run_claude()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertEqual(installed.read_text(), "existing installation")
                self.assert_no_temporary_files()

    def test_claude_corrupt_metadata_and_binary_caches_are_rejected(self):
        self.prepare_claude_fixture()
        first = self.run_claude()
        self.assertEqual(first.returncode, 0, first.stderr)
        installed = self.bin / "claude"
        installed.write_text("existing installation")
        cache = self.downloads / "linux-x64/downloads.claude.ai/claude-code-releases/2.1.322"
        manifest = cache / "manifest/manifest.json"
        original = manifest.read_bytes()
        for target in (manifest, cache / "linux-x64/claude"):
            with self.subTest(target=target.name):
                target.write_bytes(b"corrupt")
                result = self.run_claude()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(installed.read_text(), "existing installation")
                manifest.write_bytes(original)
                self.assert_no_temporary_files()

    def test_claude_fresh_install_uses_complete_cache_offline(self):
        self.prepare_claude_fixture()
        first = self.run_claude()
        self.assertEqual(first.returncode, 0, first.stderr)
        installed = self.bin / 'claude'
        original = installed.read_bytes()
        installed.unlink()
        self.calls.unlink()
        offline = self.run_claude(DOWNLOAD_MODE='fail')
        self.assertEqual(offline.returncode, 0, offline.stderr)
        self.assertEqual(installed.read_bytes(), original)
        self.assertFalse(self.calls.exists())

    def test_claude_latest_version_validation_and_upgrade(self):
        _, release, _ = self.prepare_claude_fixture()
        for version in ("../escape", "latest", "2.1.322/../../escape"):
            (release / "latest").write_text(version)
            result = subprocess.run([self.repo / "discover/discover-claude.sh"], cwd=self.root, env=self.env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Invalid latest release version", result.stderr)
            self.assertFalse(self.bin.exists())
        (release / "latest").write_text("2.1.322")
        first = self.run_claude()
        self.assertEqual(first.returncode, 0, first.stderr)
        (release / "latest").write_text("2.1.323")
        binary = b"#!/bin/sh\nprintf '2.1.323 (Claude Code)\\n'\n"
        (release / "claude").write_bytes(binary)
        self.write_mock_manifest(release, {"version": "2.1.323", "platforms": {
            "linux-x64": {"checksum": hashlib.sha256(binary).hexdigest()},
        }})
        upgrade = subprocess.run([self.repo / "discover/discover-claude.sh"], cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(upgrade.returncode, 0, upgrade.stderr)
        self.assertNotEqual((self.bin / "claude").read_bytes(), binary)
        self.assertEqual((self.repo / "pins/claude").read_text(), "2.1.322\n")
        self.assertIn("2.1.323", (self.repo / "metadata/claude-versions").read_text())
        self.assertTrue((self.downloads / "linux-x64/downloads.claude.ai/claude-code-releases/2.1.322/linux-x64/claude").exists())
        self.assertTrue((self.downloads / "linux-x64/downloads.claude.ai/claude-code-releases/2.1.323/linux-x64/claude").exists())

    def test_claude_download_failure_and_interrupt_cleanup(self):
        self.prepare_claude_fixture()
        self.bin.mkdir()
        installed = self.bin / "claude"
        installed.write_text("existing installation")
        for asset in ("manifest.json", "manifest.json.sig", "claude-code.asc", "/linux-x64/claude"):
            for mode in ("fail", "interrupt"):
                with self.subTest(asset=asset, mode=mode):
                    shutil.rmtree(self.downloads, ignore_errors=True)
                    result = self.run_claude(DOWNLOAD_MODE=mode, DOWNLOAD_MATCH=asset)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(installed.read_text(), "existing installation")
                    self.assert_no_temporary_files()

    def test_claude_updater_rejects_invalid_manifest_without_changing_pin(self):
        _, release, _ = self.prepare_claude_fixture()
        (release / "latest").write_text("2.1.323")
        (release / "manifest.json.sig").write_text("invalid")
        result = subprocess.run([self.repo / "discover/discover-claude.sh"], cwd=self.root,
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.repo / "pins/claude").read_text(), "2.1.322\n")
        self.assertFalse((self.bin / "claude").exists())

    def test_claude_platform_mapping_and_unsupported_hosts(self):
        self.prepare_claude_fixture()
        uname = self.commands / "uname"
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo "$MOCK_OS";; -m) echo "$MOCK_ARCH";; esac\n')
        uname.chmod(0o755)
        for system, arch in (("Linux", "aarch64"), ("Darwin", "arm64")):
            with self.subTest(system=system, arch=arch):
                result = self.run_claude(MOCK_OS=system, MOCK_ARCH=arch)
                if system == "Linux":
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue((self.downloads / "linux-aarch64/downloads.claude.ai/claude-code-releases/2.1.322/linux-arm64/claude").exists())
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Unsupported Claude platform", result.stderr)

    @unittest.skipUnless(os.environ.get("BUN_TEST_ARCHIVE"), "Set BUN_TEST_ARCHIVE to a real Bun archive")
    def test_real_bun_installation_and_repeat(self):
        self.downloads.mkdir()
        cache = self.downloads / "github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip"
        cache.parent.mkdir(parents=True)
        shutil.copyfile(os.environ["BUN_TEST_ARCHIVE"], cache)
        binary_stat = None
        for _ in range(2):
            result = subprocess.run(
                [self.repo / "install/install-bun.sh"], cwd=self.root,
                env=self.env, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('WARNING:', result.stderr)
            self.assert_no_temporary_files()
            current_stat = (self.bin / "bun").stat()
            if binary_stat is not None:
                self.assertEqual(current_stat.st_ino, binary_stat.st_ino)
                self.assertEqual(current_stat.st_mtime_ns, binary_stat.st_mtime_ns)
                self.assertFalse(cache.exists())
            binary_stat = current_stat
            # A matching installed binary must work without its cache or alias.
            cache.unlink(missing_ok=True)
            if _ == 0:
                (self.bin / "bunx").unlink()
        for name in ("bun", "bunx"):
            self.assertEqual(subprocess.check_output([self.bin / name, "--version"], text=True), "1.4.4\n")
        self.assertEqual(subprocess.check_output([self.bin / "bun", "-e", "console.log(1 + 1)"], text=True), "2\n")
        self.assertFalse(self.calls.exists())

        # An archive-backed install needs a verified archive even if Bun matches.
        migrated = self.downloads / 'linux-x64/github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip'
        migrated.unlink()
        before = (self.bin / 'bun').read_bytes()
        unavailable = subprocess.run([self.repo / 'install/install-bun.sh'], cwd=self.root,
                                     env=dict(self.env, DOWNLOAD_MODE='fail'), capture_output=True, text=True)
        self.assertNotEqual(unavailable.returncode, 0)
        self.assertEqual((self.bin / 'bun').read_bytes(), before)

        # Tampering must trigger reinstallation, even with an unchanged version.
        installed = self.bin / "bun"
        with installed.open("ab") as binary:
            binary.write(b"\nmodified\n")
        self.assertEqual(subprocess.check_output([installed, "--version"], text=True), "1.4.4\n")
        cache.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(os.environ["BUN_TEST_ARCHIVE"], cache)
        result = subprocess.run(
            [self.repo / "install/install-bun.sh"], cwd=self.root,
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('WARNING: installed bun differs', result.stderr)
        self.assertEqual(
            hashlib.sha256(installed.read_bytes()).hexdigest(),
            "10702245766b225e70bbf6235fd6b47214fd94b4760d00ffaed8ab0df57ac235",
        )
        self.assert_no_temporary_files()
