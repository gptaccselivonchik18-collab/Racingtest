"""Pinned official llama.cpp binary. No floating releases or unverified downloads."""
from pathlib import Path
import hashlib, urllib.request, zipfile, subprocess, sys
root = Path(__file__).resolve().parents[1]
cache = root / 'build' / 'llama-b5046.zip'
sha = 'c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab'
cache.parent.mkdir(parents=True, exist_ok=True)
if not cache.exists():
    urllib.request.urlretrieve('https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip', cache)
assert hashlib.sha256(cache.read_bytes()).hexdigest() == sha, 'llama binary checksum mismatch'
vendor = root / 'Vendor'
vendor.mkdir(exist_ok=True)
with zipfile.ZipFile(cache) as z:
    for name in z.namelist():
        assert not name.startswith('/') and '..' not in Path(name).parts
    if sys.platform == "darwin":
        subprocess.run(["ditto", "-x", "-k", str(cache), str(vendor)], check=True)
    else:
        z.extractall(vendor)
frameworks = list(vendor.rglob('llama.xcframework'))
assert len(frameworks) == 1
if frameworks[0] != vendor / 'llama.xcframework':
    frameworks[0].rename(vendor / 'llama.xcframework')
print('Verified llama.cpp b5046 XCFramework')
