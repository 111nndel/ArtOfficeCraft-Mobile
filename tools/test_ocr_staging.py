import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import stage_pdf_ocr as ocr


class OcrStagingTests(unittest.TestCase):
    def test_verified_inputs_replace_stale_native_files_and_remove_legacy_models(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = root / 'runtime'
            aar = io.BytesIO()
            with zipfile.ZipFile(aar, 'w') as z:
                for abi in ocr.ABIS:
                    for library in ocr.LIBRARIES:
                        z.writestr(f'jni/{abi}/{library}', f'{abi}/{library}'.encode())
                z.writestr('../outside.txt', b'must never extract')
                z.writestr('classes.jar', b'must never package')
            data = {'tesseract4android-4.9.0.aar': aar.getvalue(),
                    'assets/ocr/tessdata/eng.traineddata': b'English model',
                    'assets/ocr/tessdata/rus.traineddata': b'Russian model'}
            pins = tuple((name, 'unused', len(content), hashlib.sha256(content).hexdigest())
                         for name, content in data.items())
            with patch.object(ocr, 'ROOT', root), patch.object(ocr, 'OUTPUT', output), \
                    patch.object(ocr, 'FILES', pins), patch.object(ocr, 'fetch', side_effect=AssertionError('network forbidden')):
                for name, content in data.items():
                    target = ocr.destination(name)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(content)
                legacy = output / 'assets/ocr/tessdata/eng.traineddata'
                legacy.parent.mkdir(parents=True)
                legacy.write_bytes(b'obsolete duplicate')
                extra = output / 'jni/arm64-v8a/libunexpected.so'
                extra.parent.mkdir(parents=True)
                extra.write_bytes(b'not approved')
                ocr.stage()
                self.assertFalse(legacy.exists())
                self.assertFalse(extra.exists())
                self.assertFalse((output / 'outside.txt').exists())
                self.assertFalse((output / 'classes.jar').exists())
                target = output / 'jni/arm64-v8a/libtesseract.so'
                target.write_bytes(b'damaged')
                ocr.stage()
                self.assertEqual(target.read_bytes(), b'arm64-v8a/libtesseract.so')
                self.assertEqual((root / 'assets/ocr/tessdata/eng.traineddata').read_bytes(), b'English model')

    def test_apk_rejects_a_legacy_duplicate_even_if_flutter_model_is_valid(self):
        content = b'pinned model'
        name = 'assets/ocr/tessdata/eng.traineddata'
        pin = (name, 'unused', len(content), hashlib.sha256(content).hexdigest())
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / 'app.apk'
            with zipfile.ZipFile(apk, 'w') as z:
                z.writestr('assets/flutter_assets/' + name, content)
                z.writestr(name, content)
            with patch.object(ocr, 'FILES', (pin,)):
                with self.assertRaisesRegex(ValueError, 'Duplicate legacy'):
                    ocr.verify_apk(apk)


if __name__ == '__main__':
    unittest.main()
