"""Offline helper tests; set BUN_TEST_ARCHIVE for the real Bun smoke test."""

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


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="installer tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repository with spaces"
        for directory in ("install", "lib"):
            shutil.copytree(ROOT / directory, self.repo / directory)
        self.downloads = self.root / "download cache"
        self.bin = self.root / "destination bin"
        self.staging = self.root / "temporary staging"
        self.staging.mkdir()
        (self.repo / "env").write_text(
            f"DOWNLOAD_DIR={shlex.quote(str(self.downloads))}\n"
            f"DEST_BIN_DIR={shlex.quote(str(self.bin))}\n"
            f"DEST_OPT_DIR={shlex.quote(str(self.root / 'opt'))}\n"
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
            "  if [[ $1 == --output ]]; then output=$2; shift; fi\n"
            "  shift\n"
            "done\n"
            "case ${DOWNLOAD_MODE:-valid} in\n"
            " valid) cp -- \"$TEST_ARCHIVE\" \"$output\" ;;\n"
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
        installer.write_text(installer.read_text().replace("version=1.4.4", "version=9.9.9"))
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
        script = installer.read_text().replace("version=1.4.4", "version=9.9.9")
        for name, digest in (("archive_sha256", archive_digest), ("binary_sha256", binary_digest)):
            script = script.replace(
                f"declare -Ar {name}=(\n",
                f"declare -Ar {name}=(\n    [9.9.9/linux-aarch64]={digest}\n",
            )
        installer.write_text(script)
        uname = self.commands / "uname"
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo aarch64;; esac\n')
        uname.chmod(0o755)
        result = subprocess.run(
            [installer], cwd=self.root, env=self.env,
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.bin / "bun").read_bytes(), binary)
        self.assertEqual((self.downloads / "bun-v9.9.9-linux-aarch64.zip").read_bytes(), self.archive.read_bytes())
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

    def test_bun_checksum_failure_preserves_existing_installation(self):
        self.downloads.mkdir()
        (self.downloads / "bun-v1.4.4-linux-x64.zip").write_bytes(b"corrupt")
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

    @unittest.skipUnless(os.environ.get("BUN_TEST_ARCHIVE"), "Set BUN_TEST_ARCHIVE to a real Bun archive")
    def test_real_bun_installation_and_repeat(self):
        self.downloads.mkdir()
        cache = self.downloads / "bun-v1.4.4-linux-x64.zip"
        shutil.copyfile(os.environ["BUN_TEST_ARCHIVE"], cache)
        binary_stat = None
        for _ in range(2):
            result = subprocess.run(
                [self.repo / "install/install-bun.sh"], cwd=self.root,
                env=self.env, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
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

        # Tampering must trigger reinstallation, even with an unchanged version.
        installed = self.bin / "bun"
        with installed.open("ab") as binary:
            binary.write(b"\nmodified\n")
        self.assertEqual(subprocess.check_output([installed, "--version"], text=True), "1.4.4\n")
        shutil.copyfile(os.environ["BUN_TEST_ARCHIVE"], cache)
        result = subprocess.run(
            [self.repo / "install/install-bun.sh"], cwd=self.root,
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            hashlib.sha256(installed.read_bytes()).hexdigest(),
            "10702245766b225e70bbf6235fd6b47214fd94b4760d00ffaed8ab0df57ac235",
        )
        self.assert_no_temporary_files()
