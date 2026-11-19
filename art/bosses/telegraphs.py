"""telegraphs.py: draws the boss telegraphs from above (build/boss_telegraphs.json, which art/bosses/telegraphs.luau
writes by running Fx.BossTelegraph headless) as art/preview/boss_telegraphs.png: one row a shape, at 25%, 60% and 95%
of its warning (the fill reaches the edge at 100%, the hit). The boss pass's render check, 2026-11-19.
Run: python3 art/bosses/telegraphs.py"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = json.load(open(os.path.join(ROOT, "build", "boss_telegraphs.json")))
CELL, LABEL = 360, 28
GROUND = (92, 96, 104)


def font(size):
    p = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    return ImageFont.truetype(p, size) if os.path.exists(p) else ImageFont.load_default()


F = font(16)
rows = len(DATA)
sheet = Image.new("RGB", (3 * CELL, rows * (CELL + LABEL)), (30, 32, 38))
d0 = ImageDraw.Draw(sheet)
for r, case in enumerate(DATA):
    for c, fr in enumerate(case["frames"]):
        img = Image.new("RGBA", (CELL, CELL), GROUND + (255,))
        span = case["radius"] * 2.3
        k = CELL / span

        def px(x, z):
            return (CELL / 2 + x * k, CELL / 2 + z * k)

        # draw lowest first (floor tints, fills, then edges, chevrons, cracks)
        for p in sorted(fr["parts"], key=lambda p: p["pos"][1]):
            layer = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            dl = ImageDraw.Draw(layer)
            col = tuple(int(v * 255) for v in p["color"]) + (int(max(0, min(1, p["alpha"])) * 255),)
            x, z = p["pos"][0], p["pos"][2]
            if p["shape"] == "tri":
                dl.polygon([px(v[0], v[1]) for v in p["tri"]], fill=col)
            elif p["shape"] == "disc":
                rr = p["size"][1] / 2 * k
                cx, cz = px(x, z)
                dl.ellipse((cx - rr, cz - rr, cx + rr, cz + rr), fill=col)
            else:
                lx, lz = p["look"]
                n = math.hypot(lx, lz) or 1
                lx, lz = lx / n, lz / n
                sx, sz = -lz, lx
                hw, hl = p["size"][0] / 2, p["size"][2] / 2
                pts = [px(x + lx * hl * a + sx * hw * b, z + lz * hl * a + sz * hw * b) for a, b in ((1, 1), (1, -1), (-1, -1), (-1, 1))]
                dl.polygon(pts, fill=col)
            img = Image.alpha_composite(img, layer)
        # the boss's spot
        dd = ImageDraw.Draw(img)
        cx, cz = px(0, 0)
        dd.ellipse((cx - 4, cz - 4, cx + 4, cz + 4), fill=(20, 20, 20, 255))
        sheet.paste(img.convert("RGB"), (c * CELL, r * (CELL + LABEL)))
        d0.text((c * CELL + 8, r * (CELL + LABEL) + CELL + 5), "%s  %d%%" % (case["name"], fr["f"] * 100), fill=(240, 240, 240), font=F)
out = os.path.join(ROOT, "art", "preview", "boss_telegraphs.png")
sheet.save(out)
print("wrote", out)
