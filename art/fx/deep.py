# deep.py (fx): the underwater areas' two images (the deep art pass, 2026-11-19), plain python3 with numpy and PIL:
# * caustics.png  a 256 x 256 tiling caustic web, white on clear (DeepClient draws two drifting layers on the floor
#                 round the camera: Config.Deep.art.caustics.image)
# * cache_marker.png  the sunken cache's comic marker: a gold starburst in ink with a hard shadow and a treasure
#                 chest (Config.Deep.art.marker; the old text label until uploaded)
# Preview: art/preview/deep_ui.png (both over an underwater blue, the caustics tiled 2 x 2).
# Run: python3 art/fx/deep.py
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "export", "fx")
INK = (31, 42, 68, 255)


def caustics(n=256, cells=7, seed=4):
    """A tileable caustic web: the bright rims between Voronoi cells (F2 - F1 small), softened."""
    rng = np.random.default_rng(seed)
    pts = rng.random((cells * cells, 2))
    pts = (pts + np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1).reshape(-1, 2)) / cells
    ys, xs = np.mgrid[0:n, 0:n] / n
    # a periodic warp so the rims wobble like light through waves (still tiles)
    xs, ys = (xs + 0.035 * np.sin(2 * math.pi * (3 * ys + 0.2)), ys + 0.035 * np.sin(2 * math.pi * (2 * xs + 0.7)))
    d = []
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for p in pts:
                dx = xs - (p[0] + ox)
                dy = ys - (p[1] + oy)
                d.append(np.sqrt(dx * dx + dy * dy))
    d = np.sort(np.stack(d, 0), axis=0)
    edge = (d[1] - d[0]) * cells
    b = np.clip(1 - edge / 0.3, 0, 1) ** 1.8
    # a little wobble of brightness so the web is not even
    b *= 0.75 + 0.25 * np.sin(xs * 2 * math.pi * 2 + 1.3) * np.sin(ys * 2 * math.pi * 3 + 0.4)
    a = (np.clip(b, 0, 1) * 255).astype(np.uint8)
    img = np.zeros((n, n, 4), np.uint8)
    img[..., 0] = 236
    img[..., 1] = 252
    img[..., 2] = 255
    img[..., 3] = a
    return Image.fromarray(img, "RGBA")


def burst(d, cx, cy, r_out, r_in, points, fill, outline=None, width=0):
    poly = []
    for i in range(points * 2):
        a = -math.pi / 2 + i * math.pi / points
        r = r_out if i % 2 == 0 else r_in
        poly.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(poly, fill=fill, outline=outline, width=width)
    return poly


def marker(n=512):
    """Drawn at 512 and scaled to 256 for clean edges."""
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    burst(d, c + 14, c + 16, 236, 168, 12, INK)  # the hard ink shadow
    burst(d, c, c, 236, 168, 12, INK)
    burst(d, c, c, 216, 152, 12, (255, 214, 60, 255))
    burst(d, c, c, 150, 120, 12, (255, 238, 140, 255))
    # the chest: body, domed lid, iron bands, gold lock
    bx0, bx1, by0, by1 = c - 112, c + 112, c - 6, c + 96
    d.rounded_rectangle((bx0 - 10, by0 - 10, bx1 + 10, by1 + 10), 22, fill=INK)
    d.rectangle((bx0, by0, bx1, by1), fill=(178, 108, 58, 255))
    for k in range(1, 3):
        y = by0 + k * (by1 - by0) / 3
        d.line((bx0, y, bx1, y), fill=(122, 70, 36, 255), width=6)
    d.pieslice((bx0 - 10, c - 120, bx1 + 10, c + 10), 180, 360, fill=INK)
    d.pieslice((bx0, c - 108, bx1, c - 2), 180, 360, fill=(196, 122, 66, 255))
    d.rectangle((bx0 - 10, c - 14, bx1 + 10, c + 2), fill=INK)
    for x in (bx0 + 34, bx1 - 34):
        d.rectangle((x - 13, c - 106, x + 13, by1), fill=INK)
        d.rectangle((x - 8, c - 100, x + 8, by1 - 4), fill=(92, 96, 108, 255))
    d.rounded_rectangle((c - 30, c - 24, c + 30, c + 40), 10, fill=INK)
    d.rounded_rectangle((c - 22, c - 16, c + 22, c + 32), 8, fill=(255, 206, 50, 255))
    d.ellipse((c - 7, c - 2, c + 7, c + 12), fill=INK)
    d.rectangle((c - 3, c + 8, c + 3, c + 22), fill=INK)
    # sparkles and bubbles
    for (x, y, r) in ((c + 120, c - 120, 26), (c - 128, c - 96, 18)):
        burst(d, x, y, r + 6, r * 0.35 + 3, 4, INK)
        burst(d, x, y, r, r * 0.35, 4, (255, 255, 255, 255))
    for (x, y, r) in ((c - 150, c + 120, 16), (c - 118, c + 160, 10), (c + 140, c + 126, 12)):
        d.ellipse((x - r - 5, y - r - 5, x + r + 5, y + r + 5), fill=INK)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(200, 240, 255, 255))
        d.ellipse((x - r * 0.5, y - r * 0.6, x - r * 0.1, y - r * 0.2), fill=(255, 255, 255, 255))
    return im.resize((256, 256), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    ca = caustics()
    ca.save(os.path.join(OUT, "caustics.png"))
    mk = marker()
    mk.save(os.path.join(OUT, "cache_marker.png"))
    prev = Image.new("RGBA", (512 + 300, 512), (40, 110, 150, 255))
    tile = Image.new("RGBA", (512, 512))
    for x in (0, 256):
        for y in (0, 256):
            tile.paste(ca, (x, y))
    prev.alpha_composite(tile, (0, 0))
    prev.alpha_composite(mk, (532, 128))
    prev.convert("RGB").save(os.path.join(ROOT, "preview", "deep_ui.png"))
    print("deep fx: caustics.png, cache_marker.png, preview deep_ui.png")


main()
