"""Export the original theme PNG artwork as uncompressed RGBA WoW TGA files.
Requires Pillow. Run from any directory; source artwork stays untouched.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/art/theme-flourishes"
TARGET = ROOT / "media/themes"
TARGET.mkdir(parents=True, exist_ok=True)
for name, size in (("ledger-grain", 256), ("ledger-corner", 128)):
    with Image.open(SOURCE / (name + ".png")) as image:
        image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS).save(
            TARGET / (name + ".tga"), compression=None)
    print(name + ".tga")
