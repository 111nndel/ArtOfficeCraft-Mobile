import tempfile
import unittest
from pathlib import Path

from sync_native_pins import pdf_patch_block, install_patch_block


class NativePatchTests(unittest.TestCase):
    def source(self, root, *, path='vendor/hayro-jbig2', name='hayro-jbig2'):
        root.mkdir(parents=True, exist_ok=True)
        (root / 'Cargo.toml').write_text('[patch.crates-io]\nhayro-jbig2 = {path = "' + path + '"}\n')
        package = root / 'vendor/hayro-jbig2'
        package.mkdir(parents=True)
        (package / 'Cargo.toml').write_text(f'[package]\nname = "{name}"\nversion = "0.3.0"\n')

    def test_patch_is_exactly_inside_verified_source_and_updates_idempotently(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'source'
            self.source(root)
            block = pdf_patch_block(root, '../../upstream/pdf-v018/')
            original = '[package]\nname = "app"\nversion = "1.0.0"\n\n[dependencies]\nserde = "1"\n'
            once = install_patch_block(original, block)
            self.assertEqual(once, install_patch_block(once, block))
            self.assertIn('../../upstream/pdf-v018/vendor/hayro-jbig2', once)
            newer = install_patch_block(once, block.replace('pdf-v018', 'pdf-v019'))
            self.assertIn('version = "1.0.0"', newer)
            self.assertNotIn('pdf-v018', newer)

    def test_path_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'source'
            self.source(root, path='../outside')
            with self.assertRaisesRegex(RuntimeError, 'escapes'):
                pdf_patch_block(root, 'upstream/')

    def test_wrong_package_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'source'
            self.source(root, name='different-package')
            with self.assertRaisesRegex(RuntimeError, 'mismatch'):
                pdf_patch_block(root, 'upstream/')

    def test_changed_patch_kind_requires_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'Cargo.toml').write_text('[patch.crates-io]\nhayro-jbig2 = {git = "https://invalid.example/repo"}\n')
            with self.assertRaisesRegex(RuntimeError, 'review required'):
                pdf_patch_block(root, 'upstream/')

    def test_existing_unknown_or_broken_patch_sections_are_preserved_by_rejection(self):
        for cargo in ['[patch.crates-io]\nother = "1"', '# BEGIN ArtOfficeCraft reviewed PDF dependency patches']:
            with self.assertRaises(RuntimeError):
                install_patch_block(cargo, 'new block')


if __name__ == '__main__':
    unittest.main()
