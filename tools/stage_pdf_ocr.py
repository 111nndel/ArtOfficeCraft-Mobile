"""Stage immutable OCR inputs for Android builds; the app never fetches them."""

import hashlib
import os
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "android" / "app" / "ocr_runtime"
MODELS = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/65727574dfcd264acbb0c3e07860e4e9e9b22185"
WRAPPER = "https://raw.githubusercontent.com/adaptech-cz/Tesseract4Android/15c534717b1cb58261b58d4e4c1200c7f81f668c"
CPP = f"{WRAPPER}/tesseract4android/src/main/cpp"
AAR = "https://jitpack.io/cz/adaptech/tesseract4android/tesseract4android/4.9.0/tesseract4android-4.9.0.aar"

# Path, origin, exact size, SHA-256.
FILES = (
    ("tesseract4android-4.9.0.aar", AAR, 12848454,
     "bce5d6413a1a5ae3d7240033fbbc851ba3217d0a08d9769400e17a077f42cb2a"),
    ("assets/ocr/tessdata/eng.traineddata", f"{MODELS}/eng.traineddata", 4113088,
     "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"),
    ("assets/ocr/tessdata/rus.traineddata", f"{MODELS}/rus.traineddata", 3861738,
     "e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225"),
    ("assets/ocr/licenses/Tesseract4Android.txt", f"{WRAPPER}/LICENSE", 11357,
     "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"),
    ("assets/ocr/licenses/Tesseract-and-models.txt", f"{MODELS}/LICENSE", 11358,
     "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"),
    ("assets/ocr/licenses/Leptonica.txt", f"{CPP}/leptonica/src/leptonica-license.txt", 1521,
     "87829abb5bbb00b55a107365da89e9a33f86c4250169e5a1e5588505be7d5806"),
    ("assets/ocr/licenses/libpng.txt", f"{CPP}/libpng/src/LICENSE", 5345,
     "16d9daaafbf63a31a5bdc91d4600972548fef5aaa1244202393288dbd079c49a"),
    ("assets/ocr/licenses/IJG-libjpeg.txt", f"{CPP}/libjpeg/src/README", 18719,
     "7c25493a9f64fed34d01445467341bda77bc1cdbeccbe33558659ef173fb9ff2"),
)


def checked(data, size, digest):
    return len(data) == size and hashlib.sha256(data).hexdigest() == digest


def fetch(name, url, size, digest):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read(size + 1)
            if checked(data, size, digest):
                return data
        except OSError:
            if attempt == 2:
                raise
        if attempt < 2:
            time.sleep(2 ** attempt)
    raise ValueError(f"OCR input failed hash or size verification: {name}")


def stage():
    for name, url, size, digest in FILES:
        path = OUTPUT / name
        if path.is_file() and path.stat().st_size == size:
            if checked(path.read_bytes(), size, digest):
                continue
        data = fetch(name, url, size, digest)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
            pending = Path(out.name)
            out.write(data)
        try:
            os.replace(pending, path)
        finally:
            pending.unlink(missing_ok=True)
    print("Pinned offline PDF OCR files verified")


def verify_apk(apk):
    with zipfile.ZipFile(apk) as archive:
        for name, _, size, digest in FILES:
            if name.startswith("assets/") and not checked(archive.read(name), size, digest):
                raise ValueError(f"Unexpected OCR asset in APK: {name}")
        if "lib/arm64-v8a/libtesseract.so" not in archive.namelist():
            raise ValueError("APK is missing the ARM64 OCR engine")


if __name__ == "__main__":
    stage()
