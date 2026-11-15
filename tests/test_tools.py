"""Every tool descriptor parses and carries the settings its kind needs."""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lib'))
import tools  # noqa: E402

KINDS = {'bin', 'opt', 'scripted'}
HOOKS = {'scripted': 'tool_install()', 'opt': 'tool_validate()'}


class ToolDescriptorTests(unittest.TestCase):
    def test_descriptors_are_complete(self):
        for name in tools.names():
            with self.subTest(tool=name):
                settings = tools.load(name)
                kind = settings.get('kind')
                self.assertIn(kind, KINDS)
                if kind == 'bin':
                    self.assertTrue(settings.get('url') or settings.get('asset'), 'bin tools need url or asset')
                    self.assertTrue(settings['archive'] == 'binary' or settings.get('member'),
                                    'archived executables need a member')
                if kind == 'opt':
                    self.assertTrue(settings.get('url') and settings.get('root'))
                text = (ROOT / 'tools' / f'{name}.sh').read_text()
                if kind in HOOKS:
                    self.assertIn(HOOKS[kind], text)
                self.assertIn(settings['archive'], {'binary', 'tar.gz', 'zip'})
                if settings['discover'] != 'none' and kind != 'scripted':
                    self.assertTrue(settings.get('license'), 'discoverable tools record a license')
                    self.assertTrue(settings.get('repo') or 'tool_license()' in text)
                result = subprocess.run(['bash', '-n', ROOT / 'tools' / f'{name}.sh'], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_every_pin_has_a_descriptor_and_versions(self):
        for pin in (ROOT / 'pins').iterdir():
            with self.subTest(tool=pin.name):
                self.assertTrue((ROOT / 'tools' / f'{pin.name}.sh').is_file())
                self.assertIn(pin.read_text().strip(), tools.recorded_versions(pin.name))

    def test_component_aliases(self):
        self.assertEqual(tools.component_owner('codex-code-mode-host'), ('codex', 'host'))
        self.assertEqual(tools.component_owner('kind'), ('kind', ''))


if __name__ == '__main__':
    unittest.main()
