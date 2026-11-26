"""Give preview scripts content-based URLs so rebuilds bypass browser caches."""
import hashlib
from pathlib import Path
import sys
import re
import json
import shutil

root = Path(sys.argv[1])
main = root / 'main.dart.js'
version = hashlib.sha256(main.read_bytes() + Path(__file__).read_bytes()).hexdigest()[:12]
main_name = f'main.{version}.dart.js'
# Flutter tree-shakes Material glyphs per build. Version the font manifest and
# files together with the script so an older worker cannot serve stale glyphs.
manifest = json.loads((root / 'assets/FontManifest.json').read_text())
for family in manifest:
    for font in family['fonts']:
        original = Path(font['asset'])
        versioned = original.with_name(f'{original.stem}.{version}{original.suffix}')
        shutil.copyfile(root / 'assets' / original, root / 'assets' / versioned)
        font['asset'] = str(versioned)
manifest_name = f'FontManifest.{version}.json'
(root / 'assets' / manifest_name).write_text(json.dumps(manifest))
(root / main_name).write_bytes(main.read_bytes().replace(
    b'FontManifest.json', manifest_name.encode()
))
bootstrap = (root / 'flutter_bootstrap.js').read_text().replace(
    '"mainJsPath":"main.dart.js"', f'"mainJsPath":"{main_name}"'
)
bootstrap_name = f'flutter_bootstrap.{version}.js'
(root / bootstrap_name).write_text(bootstrap)
index = root / 'index.html'
index.write_text(re.sub(
    r'src="flutter_bootstrap(?:\.[a-f0-9]+)?\.js"',
    f'src="{bootstrap_name}"', index.read_text()
))
print(version)
