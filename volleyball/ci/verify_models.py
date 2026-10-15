"""Verify the original athlete assets before every cloud export."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
inventory = json.loads((root / "docs/model-inventory.json").read_text(encoding="utf-8-sig"))
for entry in inventory["preserved_files"]:
    path = root.parent / entry["path"]
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual == entry["sha256"], f"Protected original resource changed: {entry['path']}"
print("Original source assets, scene and stats are unchanged; the additive limb rig refines runtime geometry.")
