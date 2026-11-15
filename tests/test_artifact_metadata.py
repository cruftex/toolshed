import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('artifact_metadata', ROOT / 'lib/artifact_metadata.py')
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ArtifactMetadataTests(unittest.TestCase):
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
