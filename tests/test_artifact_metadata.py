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

    def test_record_command_line(self):
        """artifact_metadata.py record writes one row and reports invalid input without a traceback."""
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'tool.psv'
            command = ['python3', ROOT / 'lib/artifact_metadata.py', 'record', path, '1.2.3', '/linux-x64/binary']
            subprocess.run(command + ['c' * 64, '2026-01-01T00:00:00Z'], check=True)
            self.assertEqual(path.read_text(), 'version|artifact|sha256|discovered_at\n'
                             '1.2.3|/linux-x64/binary|' + 'c' * 64 + '|2026-01-01T00:00:00Z\n')
            result = subprocess.run(command + ['d' * 64, ''], capture_output=True, text=True)
            self.assertEqual((result.returncode, result.stderr.count('Traceback')), (1, 0))
            self.assertIn('conflicting artifact checksum', result.stderr)
            usage = subprocess.run(['python3', ROOT / 'lib/artifact_metadata.py'], capture_output=True, text=True)
            self.assertNotEqual(usage.returncode, 0)

    def test_empty_checksum_is_filled_once(self):
        """An empty digest means not yet recorded: it is filled once, keeping the discovery time."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'tool.psv'
            metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', '', '2026-01-01T00:00:00Z')
            metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', 'a' * 64, '2026-02-01T00:00:00Z')
            row = metadata.read_artifacts(path)[('1.2.3', '/linux-x64/binary')]
            self.assertEqual((row['sha256'], row['discovered_at']), ('a' * 64, '2026-01-01T00:00:00Z'))
            with self.assertRaisesRegex(ValueError, 'conflicting'):
                metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', 'b' * 64, '')
            with self.assertRaisesRegex(ValueError, 'conflicting'):
                metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', '', '')

    def test_url_column_is_optional(self):
        """Tables without URLs keep four columns; recording a URL adds the url column for every row."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'tool.psv'
            url = 'https://example.com/tool-1.2.3%2B4.tar.gz'
            metadata.record_artifact(path, '1.2.3', '/license', 'a' * 64, '2026-01-01T00:00:00Z')
            metadata.record_artifact(path, '1.2.3', '/linux-x64/archive/tar.gz', 'b' * 64, '2026-01-01T00:00:00Z')
            self.assertEqual(path.read_text().splitlines()[0], 'version|artifact|sha256|discovered_at')
            metadata.record_artifact(path, '1.2.3', '/linux-x64/archive/tar.gz', 'b' * 64, '2026-02-01T00:00:00Z', url)
            self.assertEqual(path.read_text(), 'version|artifact|sha256|discovered_at|url\n'
                             '1.2.3|/license|' + 'a' * 64 + '|2026-01-01T00:00:00Z|\n'
                             '1.2.3|/linux-x64/archive/tar.gz|' + 'b' * 64 + '|2026-01-01T00:00:00Z|' + url + '\n')
            before = path.read_bytes()
            metadata.record_artifact(path, '1.2.3', '/linux-x64/archive/tar.gz', 'b' * 64, '2026-02-01T00:00:00Z', url)
            metadata.record_artifact(path, '1.2.3', '/linux-x64/archive/tar.gz', 'b' * 64, '2026-02-01T00:00:00Z')
            metadata.record_artifact(path, '1.2.4', '/license', 'a' * 64, '2026-02-01T00:00:00Z')
            self.assertEqual(path.read_text().splitlines()[-1], '1.2.4|/license|' + 'a' * 64 + '|2026-02-01T00:00:00Z|')
            self.assertTrue(path.read_bytes().startswith(before))
            with self.assertRaisesRegex(ValueError, 'conflicting artifact URL'):
                metadata.record_artifact(path, '1.2.3', '/linux-x64/archive/tar.gz', 'b' * 64, '', url + 'x')
            with self.assertRaisesRegex(ValueError, 'conflicting artifact checksum'):
                metadata.record_artifact(path, '1.2.3', '/linux-x64/archive/tar.gz', 'c' * 64, '', url)

    def test_invalid_urls_and_field_counts_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'release.psv'
            row = '1.2.3|/linux-x64/binary|' + 'a' * 64 + '|2026-01-01T00:00:00Z'
            for content in ('version|artifact|sha256|discovered_at\n' + row + '|https://example.com/x\n',
                            'version|artifact|sha256|discovered_at|url\n' + row + '\n',
                            'version|artifact|sha256|discovered_at|url\n' + row + '|http://example.com/x\n',
                            'version|artifact|sha256|discovered_at|url\n' + row + '|https://example.com/a b\n',
                            'version|artifact|sha256|discovered_at|url\n' + row + '|https://\n',
                            'version|artifact|sha256|discovered_at|mirror\n' + row + '|https://example.com/x\n'):
                with self.subTest(content=content):
                    path.write_text(content)
                    with self.assertRaises(ValueError):
                        metadata.read_artifacts(path)
            path.unlink()
            for url in ('http://example.com/x', 'https://example.com/a|b', 'https://example.com/a b'):
                with self.subTest(url=url), self.assertRaises(ValueError):
                    metadata.record_artifact(path, '1.2.3', '/linux-x64/binary', 'a' * 64, '', url)
            self.assertFalse(path.exists())
