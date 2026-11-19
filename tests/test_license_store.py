import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / 'lib/update.sh'


class LicenseStoreTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='license store ')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def store(self, text, name):
        source = self.root / 'source.txt'
        source.write_bytes(text)
        script = 'source "$1"; toolshed_init; toolshed_root=$2; store_license "$3" "$4" digest; printf "%s\\n" "$digest"'
        return subprocess.run(['bash', '-c', script, '_', LIBRARY, self.root, source, name], capture_output=True, text=True)

    def test_store_is_deduplicated_by_content(self):
        digest = hashlib.sha256(b'MIT text\n').hexdigest()
        for _ in range(2):
            result = self.store(b'MIT text\n', 'mit')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), digest)
        files = sorted(path.name for path in (self.root / 'metadata/license').iterdir())
        self.assertEqual(files, [f'{digest}.name.txt', f'{digest}.txt'])
        self.assertEqual((self.root / f'metadata/license/{digest}.name.txt').read_text(), 'mit\n')

    def test_same_content_with_other_name_is_rejected(self):
        self.assertEqual(self.store(b'text\n', 'mit').returncode, 0)
        result = self.store(b'text\n', 'apache-2.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(list((self.root / 'metadata/license').iterdir())), 2)

    def test_invalid_name_and_empty_text_are_rejected(self):
        for text, name in ((b'text', '../x'), (b'text', 'MIT'), (b'text', ''), (b'  \n', 'mit')):
            with self.subTest(name=name):
                self.assertNotEqual(self.store(text, name).returncode, 0)
        self.assertFalse((self.root / 'metadata/license').exists())

    def test_corrupt_stored_license_is_detected(self):
        digest = self.store(b'text\n', 'mit').stdout.strip()
        (self.root / f'metadata/license/{digest}.txt').write_bytes(b'tampered')
        self.assertNotEqual(self.store(b'text\n', 'mit').returncode, 0)
        self.assertEqual((self.root / f'metadata/license/{digest}.txt').read_bytes(), b'tampered')

    def test_no_temporary_files_left(self):
        self.store(b'text\n', 'mit')
        self.assertEqual(len(list((self.root / 'metadata/license').iterdir())), 2)


if __name__ == '__main__':
    unittest.main()
