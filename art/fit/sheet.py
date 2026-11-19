# sheet.py: packs art/blender/fit.py's render passes into one labelled contact sheet: each kit becomes one tile
# with its views side by side (front, side, back; weapons: ready front and side, action front and side, grip
# close up), each view cropped from its pass at the box fit.py gives, and the kit's name under it.
# Plain python3 with PIL: python3 -I art/fit/sheet.py <spec.json>
#   spec: {"out": path, "tile": px, "names": [..], "passes": [{"path": png, "boxes": [[x0, y0, x1, y1], ...]}]}
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

spec = json.load(open(sys.argv[1]))
names, tile = spec["names"], spec["tile"]
passes = [(Image.open(p["path"]).convert("RGB"), p["boxes"]) for p in spec["passes"]]
lab, gap = 26, 6
tile_w = tile * len(passes)
per_row = max(1, min(len(names), 2600 // tile_w))
trow = (len(names) + per_row - 1) // per_row
sheet = Image.new("RGB", (per_row * tile_w + (per_row - 1) * gap, trow * (tile + lab) + (trow - 1) * gap),
                  (24, 25, 30))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
except OSError:
    font = ImageFont.load_default()
for i, n in enumerate(names):
    tr, tc = i // per_row, i % per_row
    x0, y0 = tc * (tile_w + gap), tr * (tile + lab + gap)
    for k, (im, boxes) in enumerate(passes):
        b = [int(round(v)) for v in boxes[i]]
        sheet.paste(im.crop(b).resize((tile, tile), Image.LANCZOS), (x0 + k * tile, y0))
        if k:
            d.line([(x0 + k * tile, y0), (x0 + k * tile, y0 + tile)], fill=(60, 62, 72), width=1)
    tw = d.textlength(n, font=font)
    d.text((x0 + (tile_w - tw) / 2, y0 + tile + 4), n, fill=(240, 240, 245), font=font)
sheet.save(spec["out"])
if not spec.get("keep"):
    for p in spec["passes"]:
        os.remove(p["path"])
print("wrote", spec["out"], sheet.size)
