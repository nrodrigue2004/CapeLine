# hitstar.py: the comic hit star (list-combat 2026-11-20, Everything Left 381: a Comic hit was a flat ring and two
# crossed bars). One particle (FxLib kind "hitstar", Config.Fx.lib) pops on every Comic-style hit: a jagged comic
# starburst, white so the hit colour tints it, inside a thick black ink outline that stays black (the kind's light
# is 0), with a smaller inner burst for depth. 256 x 256. Output: art/export/fx/hitstar.png, preview
# art/preview/hitstar.png. Run: python3 art/fx/hitstar.py
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "fx")
os.makedirs(OUT, exist_ok=True)
N, S = 256, 4


def burst(rnd, cx, cy, r_out, r_in, points):
    pts = []
    for i in range(points * 2):
        a = math.pi * i / points + rnd.uniform(-0.08, 0.08)
        r = (r_out * rnd.uniform(0.78, 1.0)) if i % 2 == 0 else (r_in * rnd.uniform(0.85, 1.1))
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def draw():
    rnd = random.Random(381)
    w = N * S
    c = w / 2
    img = Image.new("RGBA", (w, w), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    outer = burst(rnd, c, c, w * 0.48, w * 0.27, 11)
    d.polygon(outer, fill=(18, 18, 22, 255))
    # the white body: the same burst pulled in (the ink rim left round it)
    body = [(c + (x - c) * 0.86, c + (y - c) * 0.86) for x, y in outer]
    d.polygon(body, fill=(255, 255, 255, 255))
    # an inner burst outlined thinly, for depth
    inner = burst(rnd, c, c, w * 0.26, w * 0.15, 9)
    d.polygon(inner, fill=(18, 18, 22, 255))
    d.polygon([(c + (x - c) * 0.82, c + (y - c) * 0.82) for x, y in inner], fill=(255, 255, 255, 255))
    return img.resize((N, N), Image.LANCZOS)


img = draw()
img.save(os.path.join(OUT, "hitstar.png"))
prev = Image.new("RGB", (N * 4, N), (70, 74, 88))
for k, tint in enumerate(((255, 255, 255), (255, 210, 60), (120, 210, 255), (255, 110, 90))):
    r, g, b, a = img.split()
    t = Image.merge("RGBA", (r.point(lambda v, q=tint[0]: v * q // 255), g.point(lambda v, q=tint[1]: v * q // 255),
                             b.point(lambda v, q=tint[2]: v * q // 255), a))
    prev.paste(t, (k * N, 0), t)
prev.save(os.path.join(ROOT, "preview", "hitstar.png"))
print("hitstar: art/export/fx/hitstar.png")
