"""styles_sheet.py: pack weapons.py --styles cells into art/preview/weapon_styles.png (list-combat 2026-11-20).

    python3 art/weapons/styles_sheet.py [ids]    (default: every weapon with cells)

One row a weapon: its Classic, 2nd and 3rd style (Config.Weapons.styles names them per family).
"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CELLS = os.path.join(ROOT, "art", "export", "weapons", "styles")
ids = [int(x) for x in sys.argv[1].split(",")] if len(sys.argv) > 1 else sorted(
    {int(os.path.basename(f).split("_")[0]) for f in glob.glob(os.path.join(CELLS, "*_c.png"))})
PX, LAB, PER = 200, 26, 2  # two weapons a row (6 cells)
rows = (len(ids) + PER - 1) // PER
sheet = Image.new("RGB", (PER * 3 * PX, rows * (PX + LAB)), (38, 40, 48))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
except OSError:
    font = ImageFont.load_default()
for i, wid in enumerate(ids):
    r, c0 = i // PER, (i % PER) * 3
    for k, st in enumerate(("c", "b", "j")):
        cell = Image.open(os.path.join(CELLS, "%d_%s.png" % (wid, st))).convert("RGB").resize((PX, PX))
        x = (c0 + k) * PX
        sheet.paste(cell, (x, r * (PX + LAB)))
        t = "%d %s" % (wid, {"c": "1", "b": "2", "j": "3"}[st])
        d.text((x + 6, r * (PX + LAB) + PX + 4), t, fill=(240, 240, 245), font=font)
out = os.path.join(ROOT, "art", "preview", "weapon_styles.png")
sheet.save(out)
print("wrote", out)
