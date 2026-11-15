from pathlib import Path
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def write_tool(repo, name, body):
    """Replace a tool descriptor with a scripted test double."""
    (repo / 'tools' / f'{name}.sh').write_text('kind=scripted\n' + body)


class ToolshedCommandTests(unittest.TestCase):
    def test_update_installs_cached_release_without_network(self):
        with tempfile.TemporaryDirectory(prefix='shed offline ') as tmp:
            root = Path(tmp)
            repo = root / 'checkout with spaces'
            for directory in ('bin', 'tools', 'lib', 'metadata', 'pins'):
                shutil.copytree(ROOT / directory, repo / directory)
            bindir, cache = root / 'local bin', root / 'cache'
            bindir.mkdir()
            commands = root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text(f'#!/bin/sh\ntouch {shlex.quote(str(root / "network-called"))}\nexit 1\n')
            curl.chmod(0o755)
            (repo / 'env').write_text('\n'.join(
                f'{key}={shlex.quote(str(value))}' for key, value in (
                    ('TOOLSHED_BIN_DIR', bindir), ('TOOLSHED_OPT_DIR', root / 'opt'),
                    ('TOOLSHED_DOWNLOAD_DIR', cache), ('TOOLSHED_NVM_DIR', root / 'nvm'))) + '\n')
            old = bindir / 'bun'
            old.write_text('#!/bin/sh\necho 1.0.0\n')
            old.chmod(0o755)
            (repo / 'pins/bun').write_text('1.0.0\n')
            binary = b'#!/bin/sh\necho 9.9.9\n'
            archive = cache / 'github.com/oven-sh/bun/releases/download/bun-v9.9.9/bun-linux-x64.zip'
            archive.parent.mkdir(parents=True)
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('bun-linux-x64/bun', binary)
            provenance = repo / 'metadata/provenance/bun.json'
            provenance.parent.mkdir(exist_ok=True)
            provenance.write_text(json.dumps({'9.9.9/linux-x64': {'discovered_at': '2999-01-01T00:00:00Z'}}))
            artifacts = repo / 'metadata/artifacts/bun.psv'
            artifacts.parent.mkdir(exist_ok=True)
            artifacts.write_text('version|artifact|sha256|discovered_at\n1.0.0|/linux-x64/archive/zip|' + 'b' * 64 + '|\n9.9.9|/linux-x64/archive/zip|' + hashlib.sha256(archive.read_bytes()).hexdigest() + '|2999-01-01T00:00:00Z\n')
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}')
            result = subprocess.run([repo / 'bin/shed', 'update'], cwd=root, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/bun').read_text(), '1.0.0\n')
            self.assertFalse((root / 'network-called').exists())
            result = subprocess.run([repo / 'bin/shed', 'update', '--delay-days', '0'], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / 'pins/bun').read_text(), '9.9.9\n')
            old.write_text('#!/bin/sh\necho 1.0.0\n')
            (repo / 'pins/bun').write_text('1.0.0\n')
            provenance.write_text(json.dumps({'9.9.9/linux-x64': {'discovered_at': '2000-01-01T00:00:00Z'}}))
            artifacts.write_text('version|artifact|sha256|discovered_at\n1.0.0|/linux-x64/archive/zip|' + 'b' * 64 + '|\n9.9.9|/linux-x64/archive/zip|' + hashlib.sha256(archive.read_bytes()).hexdigest() + '|2000-01-01T00:00:00Z\n')
            provenance.unlink()
            result = subprocess.run([repo / 'bin/shed', 'update'], cwd=root, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(old.read_bytes(), binary)
            self.assertEqual((repo / 'pins/bun').read_text(), '9.9.9\n')
            self.assertFalse((root / 'network-called').exists())

    def test_list_from_another_directory(self):
        with tempfile.TemporaryDirectory(prefix='toolshed cli ') as cwd:
            result = subprocess.run(['shed', 'available'], cwd=cwd,
                                    env=dict(os.environ, PATH=f'{ROOT / "bin"}:{os.environ["PATH"]}'),
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('bun', result.stdout)
        self.assertIn((ROOT / 'pins/bun').read_text().strip(), result.stdout)

    def test_unknown_command_fails(self):
        result = subprocess.run([ROOT / 'bin/shed', 'missing'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stderr)
        result = subprocess.run([ROOT / 'bin/shed', 'update', '--delay-days', '-1'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('non-negative', result.stderr)

    def test_installed_and_updates_only_target_installed_tools(self):
        with tempfile.TemporaryDirectory(prefix='shed status ') as tmp:
            root = Path(tmp)
            repo = root / 'checkout'
            for directory in ('bin', 'tools', 'lib', 'pins', 'metadata'):
                shutil.copytree(ROOT / directory, repo / directory)
            (root / 'local bin').mkdir()
            (repo / 'env').write_text('\n'.join(
                f'{key}={shlex.quote(str(root / value))}' for key, value in (
                    ('TOOLSHED_BIN_DIR', 'local bin'), ('TOOLSHED_OPT_DIR', 'opt'),
                    ('TOOLSHED_DOWNLOAD_DIR', 'cache'), ('TOOLSHED_NVM_DIR', 'nvm'))) + '\n')
            (repo / 'pins/bun').write_text('2.0.0\n')
            provenance = repo / 'metadata/provenance/bun.json'
            provenance.parent.mkdir(exist_ok=True)
            provenance.write_text(json.dumps({'3.0.0/linux-x64': {'discovered_at': '2000-01-01T00:00:00Z'}}))
            artifacts = repo / 'metadata/artifacts/bun.psv'
            artifacts.parent.mkdir(exist_ok=True)
            artifacts.write_text('version|artifact|sha256|discovered_at\n2.0.0|/linux-x64/archive/zip|' + 'b' * 64 + '|\n3.0.0|/linux-x64/archive/zip|' + 'a' * 64 + '|2000-01-01T00:00:00Z\n')
            bun = root / 'local bin/bun'
            bun.write_text('#!/bin/sh\necho 1.0.0\n')
            bun.chmod(0o755)
            record = 'printf "%s" "${TOOLSHED_OVERRIDE_TOOL_VERSION-unset}" > ' + shlex.quote(str(root))
            write_tool(repo, 'bun', f'tool_install() {{ {record}/install; }}\n'
                                    f'tool_discover() {{ {record}/discover; printf "3.0.0\\n"; }}\n')
            shed = repo / 'bin/shed'
            commands = root / 'commands'
            commands.mkdir()
            git = commands / 'git'
            git.write_text('#!/bin/sh\nexit 0\n')
            git.chmod(0o755)
            env = dict(os.environ, TOOLSHED_OVERRIDE_TOOL_VERSION='9.9.9',
                       PATH=f'{commands}:{os.environ["PATH"]}')
            result = subprocess.run([shed, 'installed'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('1.0.0', result.stdout)
            self.assertIn('3.0.0', result.stdout)
            self.assertIn('yes', result.stdout)
            result = subprocess.run([shed, 'discover'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('3.0.0 available and cached', result.stdout)
            self.assertEqual((repo / 'pins/bun').read_text(), '2.0.0\n')
            self.assertIn('1.0.0', bun.read_text())
            self.assertFalse((root / 'install').exists())
            for command in ('update', 'discover'):
                result = subprocess.run([shed, command], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / 'install').read_text(), '3.0.0')
            self.assertEqual((root / 'discover').read_text(), 'unset')
            self.assertEqual((repo / 'pins/bun').read_text(), '3.0.0\n')
            self.assertIn('available and cached', result.stdout)
            self.assertNotIn('running discover-', result.stdout)
            (repo / 'pins/bun').write_text('2.0.0\n')
            write_tool(repo, 'bun', 'tool_install() { echo "WARNING: installed bun differs" >&2; }\n')
            result = subprocess.run([shed, 'update'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('WARNING: installed bun differs', result.stderr)
            (repo / 'pins/bun').write_text('2.0.0\n')
            write_tool(repo, 'bun', 'tool_install() { echo "install failed" >&2; exit 1; }\n')
            result = subprocess.run([shed, 'update'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('install failed', result.stderr)
            self.assertEqual((repo / 'pins/bun').read_text(), '2.0.0\n')
            write_tool(repo, 'bun', 'tool_install() { :; }\ntool_discover() { echo 3.0.0; }\n')
            nvm_dir = root / 'nvm'
            nvm_dir.mkdir()
            (nvm_dir / 'nvm.sh').write_text('nvm() { printf "0.1.0\\n"; }\n')
            write_tool(repo, 'nvm', 'detect=nvm\ndiscover=none\ntool_install() { :; }\n')
            result = subprocess.run([shed, 'update'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('nvm: installed', result.stdout)
            result = subprocess.run([shed, 'discover'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('nvm: no internet updater available', result.stdout)

    def test_discovery_pulls_before_running_and_stops_on_failure(self):
        with tempfile.TemporaryDirectory(prefix='shed pull ') as tmp:
            root = Path(tmp)
            repo = root / 'checkout with spaces'
            for directory in ('bin', 'tools', 'lib', 'pins', 'metadata'):
                shutil.copytree(ROOT / directory, repo / directory)
            bindir = root / 'local bin'
            bindir.mkdir()
            (repo / 'env').write_text('\n'.join(
                f'{key}={shlex.quote(str(value))}' for key, value in (
                    ('TOOLSHED_BIN_DIR', bindir), ('TOOLSHED_OPT_DIR', root / 'opt'),
                    ('TOOLSHED_DOWNLOAD_DIR', root / 'cache'), ('TOOLSHED_NVM_DIR', root / 'nvm'))) + '\n')
            bun = bindir / 'bun'
            bun.write_text('#!/bin/sh\necho 1.0.0\n')
            bun.chmod(0o755)
            write_tool(repo, 'bun', f'tool_discover() {{ test -f {shlex.quote(str(root / "pulled"))} || exit 1; echo 1.0.0; }}\n')
            commands = root / 'commands'
            commands.mkdir()
            git = commands / 'git'
            git.write_text(f'#!/bin/sh\n[ "$1" = -C ] && [ "$2" = {shlex.quote(str(repo))} ] && [ "$3" = pull ] && [ "$4" = --ff-only ] || exit 2\ntouch {shlex.quote(str(root / "pulled"))}\n')
            git.chmod(0o755)
            env = dict(os.environ, PATH=f'{commands}:{os.environ["PATH"]}')
            result = subprocess.run([repo / 'bin/shed', 'discover'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('no newer release', result.stdout)
            (root / 'pulled').unlink()
            git.write_text('#!/bin/sh\nexit 1\n')
            result = subprocess.run([repo / 'bin/shed', 'discover'], cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('checking for releases', result.stdout)

    def test_installer_link_and_existing_command(self):
        with tempfile.TemporaryDirectory(prefix='shed installer ') as tmp:
            root = Path(tmp)
            repo = root / 'checkout with spaces'
            for directory in ('bin', 'tools', 'lib', 'metadata', 'pins'):
                shutil.copytree(ROOT / directory, repo / directory)
            bindir = root / 'local bin'
            (repo / 'env').write_text('\n'.join(
                f'{key}={shlex.quote(str(root / value))}' for key, value in (
                    ('TOOLSHED_BIN_DIR', 'local bin'), ('TOOLSHED_OPT_DIR', 'opt'),
                    ('TOOLSHED_DOWNLOAD_DIR', 'cache'))) + '\n')
            installer = [repo / 'bin/shed', 'install', 'toolshed']
            for _ in range(2):
                result = subprocess.run(installer, cwd=root, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            command = bindir / 'shed'
            self.assertEqual(command.resolve(), repo / 'bin/shed')
            result = subprocess.run([command, 'available'], cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('bun', result.stdout)
            command.unlink()
            command.write_text('existing command')
            result = subprocess.run(installer, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(command.read_text(), 'existing command')
