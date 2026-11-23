"""Assemble the Vesper Gambit site from locally available, pinned inputs."""
import base64
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

base = Path(__file__).resolve().parent
sys.path.insert(0, str(base / 'src'))
from build_assets import build_engine_assets

stockfish, net, chess, rules, target = (Path(arg) for arg in sys.argv[1:6])
target.mkdir(parents=True, exist_ok=True)
src = base / 'src'
engines = {}
for kind, suffix in [('full', '-single'), ('multi', ''), ('lite', '-lite-single')]:
    binary = stockfish / ('stockfish-19' + suffix)
    engines[kind] = (binary.with_suffix('.js'), binary.with_suffix('.wasm'))
manifest = build_engine_assets(target / 'engine', net.read_bytes(), engines)
chess_script = chess.read_text().split('//# sourceMappingURL')[0]
rules_wasm = base64.b64encode(rules.read_bytes()).decode()
index = (src / 'index.html').read_text()
replacements = {
    '/*THEME*/': (src / 'theme.css').read_text(),
    '<!--SYMBOLS-->': (src / 'pieces.svg').read_text(),
    '/*RULES*/': 'const {Chess}=(()=>{const exports={};\n'+chess_script+'\nreturn exports;})();',
    '/*ENGINE*/': (src / 'engine.js').read_text().replace('/*MANIFEST*/', json.dumps(manifest)),
    '/*APP*/': (src / 'app.js').read_text(),
    '/*CHESSCOM_PROFILE*/': (src / 'chesscom-profile.js').read_text(),
    '/*CHESSCOM_VISION*/': (src / 'chesscom-vision.js').read_text(),
    '/*SCREEN_COACH*/': (src / 'screen-coach.js').read_text(),
    '<!--PAYLOAD-->': '<script type="application/octet-stream" id="deadwasm">'+rules_wasm+'</script>',
    '<!--PWA-->': '<link rel="manifest" href="./manifest.webmanifest">'
                 '<link rel="apple-touch-icon" href="./icon-192.png">'
                 '<link rel="icon" href="./icon-192.png">',
}
for marker, content in replacements.items():
    index = index.replace(marker, content)
(target / 'index.html').write_text(index)
worker = (src / 'sw.js').read_text().replace('/*MULTI_SHELL*/', "'engine/multi.js',")
version = hashlib.sha256((index + worker).encode()).hexdigest()[:14]
(target / 'sw.js').write_text(worker.replace('@VERSION@', version))
icons = []
for size in (192, 512):
    name = f'icon-{size}.png'
    shutil.copyfile(base / name, target / name)
    icons.append({'src': './'+name, 'sizes': f'{size}x{size}', 'type': 'image/png'})
(target / 'manifest.webmanifest').write_text(json.dumps({
    'name': 'Vesper Gambit', 'short_name': 'Vesper Gambit',
    'id': './', 'start_url': './', 'scope': './', 'display': 'standalone',
    'background_color': '#f9f7f3', 'theme_color': '#f9f7f3', 'icons': icons,
}))
with zipfile.ZipFile(target / 'Vesper-source.zip', 'w', zipfile.ZIP_DEFLATED) as bundle:
    for folder in ('src', 'licenses', 'adjudicator'):
        for path in sorted((base / folder).rglob('*')):
            if path.is_file() and not {'__pycache__', 'target'}.intersection(path.relative_to(base).parts):
                bundle.write(path, path.relative_to(base))
    for name in ('build.py', 'prepare.sh', 'icon-192.png', 'icon-512.png'):
        bundle.write(base / name, name)
