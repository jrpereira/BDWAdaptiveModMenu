import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package_mod', ROOT / 'tools/package.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)

class PackageTests(unittest.TestCase):
    def test_allowlist_checksum_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'repo'
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns('.git', 'dist', '__pycache__'))
            (root / 'config.ini').write_text('PERSONAL_CONFIGURATION_MUST_NOT_SHIP')
            (root / 'crash.dmp').write_bytes(b'PRIVATE_DUMP')
            (root / 'Scripts/temporary_probe.lua').write_text('TEMPORARY_PROBE')
            archive = pack.build(root)
            before = archive.read_bytes()
            self.assertEqual(before, pack.build(root).read_bytes())
            self.assertEqual(archive.with_suffix('.zip.sha256').read_text().split()[0], hashlib.sha256(before).hexdigest())
            with ZipFile(archive) as bundle:
                names = bundle.namelist()
                self.assertIn(pack.MODULE + '/Scripts/main.lua', names)
                self.assertNotIn(pack.MODULE + '/enabled.txt', names)
                self.assertNotIn(pack.MODULE + '/Scripts/temporary_probe.lua', names)
                self.assertEqual(len([n for n in names if '/Scripts/' in n]), 15)
                self.assertIn('AdaptiveModMenu/Scripts/dmm_extension.lua', names)
                self.assertFalse(any('/dlls/' in n or n.lower().endswith('.dll') for n in names))
                self.assertIn('AdaptiveModMenu/Scripts/dirty_labels.lua', names)
                self.assertIn('AdaptiveModMenu/Scripts/init_config.lua', names)
                self.assertIn('AdaptiveModMenu/Scripts/fixes.lua', names)
                self.assertNotIn('AdaptiveModMenu/templates/fixes.lua', names)
                self.assertIn('AdaptiveModMenu/Scripts/settings_api.lua', names)
                self.assertFalse(any(n.endswith('/config.ini') or n.endswith('.dmp') or '/tests/' in n for n in names))
                if pack.MODULE == 'QuickslotsForever':
                    self.assertEqual(bundle.read(pack.MODULE + '/config.example.ini'), (root / 'distribution/config.ini').read_bytes())
                for name in names:
                    self.assertNotIn(b'PERSONAL_CONFIGURATION_MUST_NOT_SHIP', bundle.read(name))

    def test_release_version_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            pack.build(expected='999.0.0')

    def test_release_candidate_version(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'Scripts').mkdir()
            (root / 'Scripts/main.lua').write_text("local VERSION='0.1.31-rc.1'")
            shutil.copy2(ROOT / 'release-manifest.json', root / 'release-manifest.json')
            self.assertEqual(pack.version(root), '0.1.31-rc.1')

    def test_invalid_source_version_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'Scripts').mkdir()
            (root / 'Scripts/main.lua').write_text('local VERSION="invalid"')
            shutil.copy2(ROOT / 'release-manifest.json', root / 'release-manifest.json')
            with self.assertRaises(ValueError):
                pack.version(root)

if __name__ == '__main__':
    unittest.main()
