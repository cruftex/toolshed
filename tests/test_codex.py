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
PINS = [
    ("codex", "9af4d751fce183faedea629437d5252dbf458eeb04130cf4f97be844621ea985", "b452ca20f838a8855a88a41050ee4a694033fff4ea3ecdad5633e6e0e8d13f2b"),
    ("codex-code-mode-host", "cbed6a8d25e8268792b757767fbc76d4c62e84bcf8ee4a63f97547f0de3aaceb", "e9f2ef68671b2b6ac68902d19e8dafda3f5928e678ecf3f30c74b203a2c403ed"),
]

class CodexInstallerTests(unittest.TestCase):
    def test_install_reuse_corruption_and_staging(self):
        with tempfile.TemporaryDirectory(prefix="codex test ") as tmp:
            root = Path(tmp)
            repo = root / "repo with spaces"
            shutil.copytree(ROOT / "install", repo / "install")
            shutil.copytree(ROOT / "lib", repo / "lib")
            shutil.copytree(ROOT / "metadata", repo / "metadata")
            shutil.copytree(ROOT / "pins", repo / "pins")
            cache, dest = root / "cache", root / "bin"
            (repo / "env").write_text(f"TOOLSHED_DOWNLOAD_DIR={shlex.quote(str(cache))}\nTOOLSHED_BIN_DIR={shlex.quote(str(dest))}\nTOOLSHED_OPT_DIR={shlex.quote(str(root / 'opt'))}\n")
            installer = repo / "install/install-codex.sh"
            script = installer.read_text()
            binaries = {}
            for name, archive_pin, binary_pin in PINS:
                asset = name + "-x86_64-unknown-linux-musl"
                binary = ("#!/bin/sh\necho 'codex-cli 0.169.0'\n# " + name + "\n").encode()
                binaries[name] = binary
                archive = root / (asset + ".tar.gz")
                with tarfile.open(archive, "w:gz") as tar:
                    member = tarfile.TarInfo(asset)
                    member.size = len(binary)
                    tar.addfile(member, io.BytesIO(binary))
                metadata = repo / "metadata" / (name + ".sh")
                contents = metadata.read_text().replace(archive_pin, hashlib.sha256(archive.read_bytes()).hexdigest())
                contents = contents.replace(binary_pin, hashlib.sha256(binary).hexdigest())
                metadata.write_text(contents)
            installer.write_text(script)
            commands = root / "commands"
            commands.mkdir()
            curl = commands / "curl"
            curl.write_text("""#!/bin/bash
while (($#)); do
  case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
  shift
done
cp "$FIXTURES/${url##*/}" "$out"
""")
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURES=str(root))
            def run():
                return subprocess.run([installer], cwd=root, env=env, capture_output=True, text=True)
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in binaries:
                self.assertEqual((dest / name).read_bytes(), binaries[name])
            shutil.rmtree(cache)
            for name, *_ in PINS:
                (root / (name + "-x86_64-unknown-linux-musl.tar.gz")).unlink()
            self.assertEqual(run().returncode, 0)
            (dest / "codex-code-mode-host").write_bytes(b"modified")
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual((dest / "codex").read_bytes(), binaries["codex"])

    def test_update_records_verified_release_and_installs(self):
        import json
        with tempfile.TemporaryDirectory(prefix="codex update ") as tmp:
            root = Path(tmp)
            repo = root / "repo"
            for directory in ("install", "lib", "metadata", "pins", "update"):
                shutil.copytree(ROOT / directory, repo / directory)
            cache, dest = root / "cache", root / "bin"
            (repo / "env").write_text(f"TOOLSHED_DOWNLOAD_DIR={shlex.quote(str(cache))}\nTOOLSHED_BIN_DIR={shlex.quote(str(dest))}\nTOOLSHED_OPT_DIR={shlex.quote(str(root / 'opt'))}\n")
            assets = []
            binaries = {}
            for name, *_ in PINS:
                asset = name + "-x86_64-unknown-linux-musl"
                binary = ("#!/bin/sh\necho 'codex-cli 0.170.0'\n# " + name + "\n").encode()
                binaries[name] = binary
                archive = root / (asset + ".tar.gz")
                with tarfile.open(archive, "w:gz") as tar:
                    member = tarfile.TarInfo(asset)
                    member.size = len(binary)
                    tar.addfile(member, io.BytesIO(binary))
                assets.append({"name": archive.name, "digest": "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest()})
            (root / "release.json").write_text(json.dumps({"tag_name": "rust-v0.170.0", "draft": False, "prerelease": False, "assets": assets}))
            commands = root / "commands"
            commands.mkdir()
            curl = commands / "curl"
            curl.write_text("""#!/bin/bash
while (($#)); do
  case $1 in https://*) url=$1 ;; --output) out=$2; shift ;; esac
  shift
done
if [[ $url == */latest ]]; then cp "$FIXTURES/release.json" "$out"; else cp "$FIXTURES/${url##*/}" "$out"; fi
""")
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}', FIXTURES=str(root))
            result = subprocess.run([repo / "update/update-codex.sh"], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / "pins/codex").read_text(), "0.170.0\n")
            for name in binaries:
                self.assertEqual((dest / name).read_bytes(), binaries[name])
                self.assertIn("0.170.0/linux-x64", (repo / "metadata" / (name + ".sh")).read_text())
            again = subprocess.run([repo / "update/update-codex.sh"], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(again.returncode, 0, again.stderr)
