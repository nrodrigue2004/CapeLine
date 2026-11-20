# litwindows.py: the city's lit windows at night (shapes-2, 2026-11-19; nate: "World needs to feel way more alive").
# For each kit front with windows (art/city/materials.py), a 48 x 48 stud picture (4 x 4 of its 12-stud storey bays)
# that is clear everywhere but the window glass, where about half the windows glow warm (a few cool TV-blue, some with
# a blind half down). The window rectangles are the same ones materials.py paints (glass = the window inset by its
# 0.22 frame), so the light lands on the painted glass. Fx.LitWindows tiles the picture over a building's faces after
# dusk in an unlit SurfaceGui, starting a tile at the face's centre like the kit texture (object space from the
# part's centre: art/blender/block.py renders it the same way; `--night` there draws the proof).
# Output: art/export/city/lit/Lit<Front>.png (512 px), preview art/preview/litwindows.png.
# Run: python3 art/city/litwindows.py
import os
import random

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "export", "city", "lit")
os.makedirs(OUT, exist_ok=True)
N = 512
BLOCK = 48  # studs a picture covers (4 x 4 bays)
FW = 0.22  # materials.py's window frame


def w(x0, y0, x1, y1):
    return (x0 + FW, y0 + FW, x1 - FW, y1 - FW)


# the glass of each front's windows in one 12-stud bay (studs from its bottom-left, y up)
WINDOWS = {
    "Brick": [w(wx - 1.6, 3.4, wx + 1.6, 9.0) for wx in (3.0, 9.0)],
    "Office": [w(3 * k + 0.1, 3.8, 3 * k + 2.9, 8.6) for k in range(4)],
    "Curtain": [(k * 3.0 + 0.11, y0 + 0.09, k * 3.0 + 2.89, y1 - 0.09) for k in range(4) for (y0, y1) in ((1.1, 4.0), (4.0, 8.0), (8.0, 12.0))],
    "Stone": [w(wx - 1.5, 3.3, wx + 1.5, 9.0) for wx in (3.0, 9.0)],
    "Deco": [w(wx - 1.6, 2.6, wx + 1.6, 11.2) for wx in (3.0, 9.0)],
    "Panel": [w(0.6, 3.6, 5.4, 10.6), w(6.6, 3.6, 11.4, 10.6)],
    "Warehouse": [w(0.6 + 4 * k, 8.6, 3.4 + 4 * k, 10.6) for k in range(3)],
    "DockBrick": [w(wx - 1.9, 2.2, wx + 1.9, 9.6) for wx in (3.0, 9.0)],
    "OldBrick": [w(wx - 1.5, 3.25, wx + 1.5, 9.0) for wx in (3.0, 9.0)],
    "Plaster": [w(wx - 1.2, 3.3, wx + 1.2, 9.1) for wx in (3.0, 9.0)],
    "Timber": [w(wx - 1.1, 7.0, wx + 1.1, 10.4) for wx in (2.0, 6.0, 10.0)] + [w(0.9, 1.6, 3.1, 4.6)],
    "Siding": [w(wx - 1.45, 3.4, wx + 1.45, 9.0) for wx in (3.0, 9.0)],
    "Ribbon": [(k * 3.0 + 0.09, 3.6, k * 3.0 + 2.91, 10.4) for k in range(4)],
}
WARM = [(255, 214, 140), (255, 196, 120), (255, 230, 170), (250, 206, 150)]
COOL = [(170, 210, 255), (200, 225, 255)]


def draw(front, wins, seed):
    rng = random.Random(seed)
    img = np.zeros((N, N, 4), np.float32)
    s = N / BLOCK
    Y, X = np.mgrid[0:N, 0:N].astype(np.float32)
    lit_share = {"Warehouse": 0.35, "Curtain": 0.3}.get(front, 0.5)  # glass walls read as a checkerboard when half lit
    for by in range(BLOCK // 12):
        floor_lit = rng.random() < 0.85  # a dark floor now and then
        for bx in range(BLOCK // 12):
            for (x0, y0, x1, y1) in wins:
                if not floor_lit or rng.random() > lit_share:
                    continue
                c = rng.choice(COOL) if rng.random() < 0.12 else rng.choice(WARM)
                gx0, gx1 = (bx * 12 + x0) * s, (bx * 12 + x1) * s
                gy0, gy1 = N - (by * 12 + y1) * s, N - (by * 12 + y0) * s  # image rows from the top
                m = (X >= gx0) & (X < gx1) & (Y >= gy0) & (Y < gy1)
                v = np.clip((Y - gy0) / max(gy1 - gy0, 1), 0, 1)  # 0 at the top of the glass
                glow = 0.82 + 0.18 * v  # a little brighter low, where the lamp is
                img[m, 0] = c[0] / 255 * glow[m]
                img[m, 1] = c[1] / 255 * glow[m]
                img[m, 2] = c[2] / 255 * glow[m]
                img[m, 3] = 0.92
                if rng.random() < 0.3:  # a blind part way down
                    b = gy0 + (gy1 - gy0) * rng.uniform(0.25, 0.55)
                    mb = m & (Y < b)
                    img[mb, :3] *= 0.55
                    stripes = mb & (((Y - gy0) % 6) < 1.5)
                    img[stripes, :3] *= 0.8
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


sheet = []
for i, (front, wins) in enumerate(sorted(WINDOWS.items())):
    im = draw(front, wins, 20261119 + i)
    im.save(os.path.join(OUT, "Lit%s.png" % front))
    sheet.append((front, im))

# preview: each picture over its own front texture (dark, as at night), 4 to a row
cols = 5
rows = (len(sheet) + cols - 1) // cols
pv = Image.new("RGB", (cols * 260, rows * 260), (20, 22, 30))
for k, (front, im) in enumerate(sheet):
    base_path = os.path.join(ROOT, "export", "city", "%s_Color.png" % front)
    if os.path.exists(base_path):
        base = Image.open(base_path).convert("RGB").resize((128, 128))
        tile = Image.new("RGB", (512, 512))
        for a in range(4):
            for b in range(4):
                tile.paste(base, (a * 128, b * 128))
        tile = Image.eval(tile, lambda c: int(c * 0.35))
    else:
        tile = Image.new("RGB", (512, 512), (40, 40, 50))
    tile.paste(im, (0, 0), im)
    pv.paste(tile.resize((250, 250)), ((k % cols) * 260 + 5, (k // cols) * 260 + 5))
pv.save(os.path.join(ROOT, "preview", "litwindows.png"))
print("lit windows:", ", ".join(f for f, _ in sheet))
