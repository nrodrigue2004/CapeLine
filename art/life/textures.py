# textures.py: the living-world set's pictures (2026-11-19), plain python3 with PIL and numpy:
#   * Picket.png: the white picket fence the outskirts' fence boxes wear on both long faces (a Texture, 3 x 3 studs
#     a tile, transparent between the pickets; the box itself is hidden), Shared.LifeKit.
#   * Flag_<Name>.png: the roof and plaza flags (Fx.CityLife's cloth): Brightharbor's beacon star, Uptown's sunset,
#     the Docks' wave and Old Town's clock. Original designs, no real flags or brands.
#   * Tilled.png: the farm fields' tilled soil (MaterialVariant KitTilled, 8 studs a tile), and its three kit maps
#     in art/export/city/Tilled_<Color|Normal|Roughness>.png.
# Output: art/export/life/*.png and art/preview/life_textures.png.  Run: python3 art/life/textures.py
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "life")
os.makedirs(OUT, exist_ok=True)
INK = (28, 26, 34, 255)


def picket():
    W = H = 512
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    n, gap = 4, 0.34
    pw = W / n
    for k in range(n):
        x0 = k * pw + pw * gap / 2
        x1 = (k + 1) * pw - pw * gap / 2
        cx = (x0 + x1) / 2
        top = H * 0.06
        shoulder = H * 0.17
        poly = [(x0, H), (x0, shoulder), (cx, top), (x1, shoulder), (x1, H)]
        d.polygon(poly, fill=(246, 244, 236, 255), outline=INK)
        d.line(poly + [poly[0]], fill=INK, width=6)
        d.line([(x1 - 9, shoulder + 8), (x1 - 9, H)], fill=(212, 208, 198, 255), width=8)  # a shaded edge
    for y in (0.34, 0.78):
        y0, y1 = H * y - 18, H * y + 18
        d.rectangle([0, y0, W, y1], fill=(236, 233, 224, 255))
        d.line([(0, y0), (W, y0)], fill=INK, width=5)
        d.line([(0, y1), (W, y1)], fill=INK, width=5)
        d.line([(0, y1 - 6), (W, y1 - 6)], fill=(205, 200, 190, 255), width=5)
    im.save(os.path.join(OUT, "Picket.png"))
    return im


def star(d, cx, cy, r0, r1, n, fill, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r0 if i % 2 == 0 else r1
        a = rot + i * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(pts, fill=fill, outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=8)


def flag(name, draw):
    W, H = 768, 512
    im = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    d = ImageDraw.Draw(im)
    draw(d, W, H)
    d.rectangle([4, 4, W - 5, H - 5], outline=INK, width=10)
    im.save(os.path.join(OUT, "Flag_%s.png" % name))
    return im


def brightharbor(d, W, H):
    d.rectangle([0, 0, W, H], fill=(30, 52, 120, 255))
    d.rectangle([0, H * 0.72, W, H * 0.8], fill=(246, 244, 236, 255))
    d.rectangle([0, H * 0.86, W, H * 0.92], fill=(246, 244, 236, 255))
    star(d, W * 0.32, H * 0.38, H * 0.3, H * 0.12, 8, (250, 200, 50, 255))
    d.ellipse([W * 0.32 - 34, H * 0.38 - 34, W * 0.32 + 34, H * 0.38 + 34], fill=(255, 244, 200, 255), outline=INK, width=6)


def uptown(d, W, H):
    bands = [(240, 110, 90), (250, 150, 80), (252, 196, 92), (120, 90, 160)]
    for i, c in enumerate(bands):
        d.rectangle([0, H * i / 4, W, H * (i + 1) / 4], fill=c + (255,))
    d.pieslice([W * 0.5 - 150, H * 0.5 - 150, W * 0.5 + 150, H * 0.5 + 150], 180, 360, fill=(255, 246, 220, 255), outline=INK, width=8)
    for k in range(7):
        a = math.pi + (k + 0.5) * math.pi / 7
        d.line([(W / 2 + math.cos(a) * 170, H / 2 + math.sin(a) * 170), (W / 2 + math.cos(a) * 230, H / 2 + math.sin(a) * 230)],
               fill=(255, 246, 220, 255), width=14)


def docks(d, W, H):
    d.rectangle([0, 0, W, H], fill=(28, 128, 138, 255))
    pts = [(x, H * 0.62 + math.sin(x / W * math.pi * 4) * 34) for x in range(0, W + 8, 8)]
    d.polygon(pts + [(W, H), (0, H)], fill=(246, 244, 236, 255))
    d.line(pts, fill=INK, width=8)
    d.ellipse([W * 0.62, H * 0.12, W * 0.62 + 150, H * 0.12 + 150], fill=(250, 200, 50, 255), outline=INK, width=8)


def oldtown(d, W, H):
    d.rectangle([0, 0, W, H], fill=(128, 36, 48, 255))
    d.rectangle([0, 0, W * 0.16, H], fill=(236, 214, 160, 255))
    cx, cy, r = W * 0.58, H * 0.5, H * 0.32
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(246, 236, 210, 255), outline=INK, width=10)
    for k in range(12):
        a = k * math.pi / 6
        d.line([(cx + math.cos(a) * r * 0.78, cy + math.sin(a) * r * 0.78), (cx + math.cos(a) * r * 0.92, cy + math.sin(a) * r * 0.92)],
               fill=INK, width=10)
    d.line([(cx, cy), (cx, cy - r * 0.62)], fill=INK, width=14)
    d.line([(cx, cy), (cx + r * 0.42, cy + r * 0.1)], fill=INK, width=14)


def tilled():
    S = 512
    rng = np.random.default_rng(7)
    y = np.arange(S)[:, None] * np.ones((1, S))
    x = np.ones((S, 1)) * np.arange(S)[None, :]
    base = np.array([112, 80, 54], float)
    ridge = (np.sin(y / S * 2 * math.pi * 6) * 0.5 + 0.5)  # six soft ridges a tile (8 studs)
    n = rng.normal(0, 1, (S // 8, S // 8))
    n = np.kron(n, np.ones((8, 8)))
    img = Image.fromarray(np.uint8(np.clip(n * 40 + 128, 0, 255))).filter(ImageFilter.GaussianBlur(3))
    n = (np.asarray(img, float) - 128) / 40
    shade = 0.72 + ridge * 0.38 + n * 0.07
    col = np.clip(base[None, None, :] * shade[:, :, None], 0, 255)
    clods = rng.random((S, S)) > 0.9975
    for (cy, cx) in zip(*np.nonzero(clods)):
        r = rng.integers(3, 7)
        col[max(cy - r, 0):cy + r, max(cx - r, 0):cx + r] *= 0.78
    Image.fromarray(np.uint8(col)).save(os.path.join(OUT, "Tilled.png"))
    # the kit's three maps (art/export/city/Tilled_<map>.png, like art/city/materials.py's): colour, a normal map
    # from the ridges and clods, an even dull roughness
    city = os.path.join(ROOT, "export", "city")
    Image.fromarray(np.uint8(col)).save(os.path.join(city, "Tilled_Color.png"))
    h = ridge * 0.8 + n * 0.12
    gy, gx = np.gradient(h)
    k = 6.0
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    Image.fromarray(np.uint8(nrm * 255)).save(os.path.join(city, "Tilled_Normal.png"))
    Image.fromarray(np.uint8(np.full((S, S), 236))).save(os.path.join(city, "Tilled_Roughness.png"))
    del x


pk = picket()
fl = [flag(n, f) for n, f in (("Brightharbor", brightharbor), ("Uptown", uptown), ("Docks", docks), ("OldTown", oldtown))]
tilled()
sheet = Image.new("RGBA", (512 + 4 * 400 + 512 + 60, 560), (120, 130, 140, 255))
sheet.alpha_composite(pk.resize((512, 512)), (10, 24))
for i, f in enumerate(fl):
    sheet.alpha_composite(f.resize((384, 256)), (532 + i * 400, 150))
sheet.paste(Image.open(os.path.join(OUT, "Tilled.png")).convert("RGBA"), (532 + 4 * 400, 24))
sheet.save(os.path.join(ROOT, "preview", "life_textures.png"))
print("life textures written")
