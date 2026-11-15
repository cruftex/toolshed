import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('artifact_metadata', ROOT / 'lib/artifact_metadata.py')
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ArtifactMetadataTests(unittest.TestCase):
    def test_migration_preserves_checksums_times_and_multiple_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / 'repo'
            for directory in ('lib', 'metadata', 'install'):
                shutil.copytree(ROOT / directory, repo / directory,
                                ignore=shutil.ignore_patterns('__pycache__'))
            # Reconstruct representative legacy checksum files for migration.
            for tool in ('bun', 'codex', 'vegeta'):
                records = metadata.read_artifacts(repo / 'metadata/artifacts' / f'{tool}.psv')
                for (version, artifact), row in records.items():
                    parts = artifact.split('/')
                    if parts[-1] == 'license':
                        continue
                    legacy_name = 'codex-code-mode-host' if tool == 'codex' and parts[0] == 'host' else tool
                    platform = parts[1]
                    if tool == 'vegeta':
                        platform = platform.replace('linux-', 'linux_').replace('darwin-', 'darwin_').replace('x64', 'amd64').replace('aarch64', 'arm64')
                    legacy = repo / 'metadata' / f'{legacy_name}.sh'
                    if not legacy.exists():
                        legacy.write_text('declare -A checksums=()\n')
                    with legacy.open('a') as stream:
                        stream.write(f'checksums[archive/{version}/{platform}]={row["sha256"]}\n')
            shutil.rmtree(repo / 'metadata/artifacts', ignore_errors=True)
            for _ in range(2):
                subprocess.run(['python3', repo / 'lib/migrate_artifacts.py', repo], check=True)
            codex = metadata.read_artifacts(repo / 'metadata/artifacts/codex.psv')
            self.assertEqual(len(codex), 2)
            self.assertEqual(codex[('0.169.0', 'host/linux-x64/archive/tar.gz')]['sha256'],
                             'cbed6a8d25e8268792b757767fbc76d4c62e84bcf8ee4a63f97547f0de3aaceb')
            bun = metadata.read_artifacts(repo / 'metadata/artifacts/bun.psv')
            self.assertEqual(bun[('1.4.4', '/linux-x64/archive/zip')]['discovered_at'], '2026-11-14T04:42:03Z')
            self.assertEqual(len(metadata.read_artifacts(repo / 'metadata/artifacts/vegeta.psv')), 4)

    def test_record_preserves_first_timestamp_and_rejects_conflicts(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'release.psv'
            digest = 'a' * 64
            metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', digest, '')
            metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', digest, '2026-01-01T00:00:00Z')
            metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', digest, '2026-02-01T00:00:00Z')
            self.assertEqual(metadata.read_artifacts(path)[('1.2.3', '/linux-x64/binary')]['discovered_at'], '2026-01-01T00:00:00Z')
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, 'conflicting'):
                metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', 'b' * 64, '')
            self.assertEqual(path.read_bytes(), before)

    def test_license_artifacts_per_component(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'tool.psv'
            for artifact, digest in (('/license', 'a' * 64), ('host/license', 'b' * 64)):
                metadata.record_artifact(path, '1.2.3', artifact, digest, '2026-01-01T00:00:00Z')
            records = metadata.read_artifacts(path)
            self.assertEqual(records[('1.2.3', '/license')]['sha256'], 'a' * 64)
            self.assertEqual(records[('1.2.3', 'host/license')]['sha256'], 'b' * 64)
            with self.assertRaisesRegex(ValueError, 'conflicting'):
                metadata.record_artifact(path, '1.2.3', '/license', 'c' * 64, '')
            with self.assertRaisesRegex(ValueError, 'invalid artifact key'):
                metadata.record_artifact(path, '1.2.3', '/licenses', 'a' * 64, '')

    def test_records_and_duplicate_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'release.psv'
            header = 'version|artifact|sha256|discovered_at\n'
            row = '1.2.3|/linux-x64/archive/zip|' + 'a' * 64 + '|2026-11-14T04:42:03Z\n'
            path.write_text(header + row)
            self.assertEqual(metadata.read_artifacts(path)[('1.2.3', '/linux-x64/archive/zip')]['sha256'], 'a' * 64)
            path.write_text(header + row + row)
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                metadata.read_artifacts(path)

    def test_invalid_values_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'release.psv'
            for row in ('1.2.3|/linux-x64/binary|bad|\n',
                        '1.2.3|/linux-x64/binary||2026-01-01\n',
                        '1.2.3|../linux-x64/binary||\n'):
                with self.subTest(row=row):
                    path.write_text('version|artifact|sha256|discovered_at\n' + row)
                    with self.assertRaises(ValueError):
                        metadata.read_artifacts(path)
