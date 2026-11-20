# art/ui/wanted_paper.py: the WANTED poster's paper (list-combat 2026-11-20, Everything Left 397: "The WANTED
# poster's paper and SurfaceGui ... are plain parts"). An old printed bill, 700 x 800 (the 7 x 8 stud poster at
# 100 px a stud): warm aged paper with torn, ragged edges (clear outside, so the board shows), a fold cross, foxing
# spots and a coffee ring, an inked double border, a halftone band behind the WANTED heading and a ruled frame
# where the nemesis's bust sits. No words: the heading, name, rank, Intel and note stay the game's own labels
# (HqClient's SurfaceGui), and the bust stays its ViewportFrame.
# Output: art/export/ui/wanted/Paper.png and art/preview/wanted_paper.png. Run: python3 art/ui/wanted_paper.py
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "ui", "wanted")
os.makedirs(OUT, exist_ok=True)
W, H = 700, 800
INK = (52, 36, 26)
random.seed(11)


def ragged(n_side=60, jag=10):
    """The torn outline: points round the sheet, each pushed in a random amount."""
    pts = []
    m = 14
    for i in range(n_side):  # top
        pts.append((m + (W - 2 * m) * i / n_side, m + random.uniform(0, jag)))
    for i in range(n_side):  # right
        pts.append((W - m - random.uniform(0, jag), m + (H - 2 * m) * i / n_side))
    for i in range(n_side):  # bottom
        pts.append((W - m - (W - 2 * m) * i / n_side, H - m - random.uniform(0, jag)))
    for i in range(n_side):  # left
        pts.append((m + random.uniform(0, jag), H - m - (H - 2 * m) * i / n_side))
    # a corner torn off (bottom right) and a notch on the left
    pts = [(x, y) if not (x > W - 110 and y > H - 90 and (x - (W - 110)) / 110 + (y - (H - 90)) / 90 > 1)
           else (min(x, W - 110 + 110 * (1 - (y - (H - 90)) / 90)), y) for (x, y) in pts]
    return pts


def paper():
    base = Image.new("RGB", (W, H), (236, 220, 180))
    px = base.load()
    # mottled ageing: low-frequency blotches plus fine grain
    blot = Image.effect_noise((W // 20, H // 20), 40).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(8))
    grain = Image.effect_noise((W, H), 18)
    for y in range(H):
        for x in range(W):
            b = blot.getpixel((x, y)) - 128
            g = grain.getpixel((x, y)) - 128
            r0, g0, b0 = px[x, y]
            # darker towards the edges
            e = min(x, y, W - x, H - y)
            edge = max(0, 40 - e) * 0.9
            k = b * 0.14 + g * 0.08 - edge
            px[x, y] = (int(max(0, min(255, r0 + k))), int(max(0, min(255, g0 + k * 1.05))),
                        int(max(0, min(255, b0 + k * 1.3))))
    d = ImageDraw.Draw(base, "RGBA")
    # foxing spots and a coffee ring
    for _ in range(26):
        x, y, r = random.uniform(30, W - 30), random.uniform(30, H - 30), random.uniform(2, 7)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(170, 120, 70, 50))
    cx, cy, r = 560, 690, 62
    for k in range(5):
        d.ellipse([cx - r - k, cy - r - k, cx + r + k, cy + r + k], outline=(150, 100, 60, 34), width=2)
    # the fold cross: a light line and a shadow line
    for (a, b) in (((W / 2, 20), (W / 2, H - 20)), ((20, H / 2), (W - 20, H / 2))):
        d.line([a, b], fill=(255, 248, 225, 90), width=3)
        off = (2, 0) if a[0] == b[0] else (0, 2)
        d.line([(a[0] + off[0], a[1] + off[1]), (b[0] + off[0], b[1] + off[1])], fill=(120, 90, 60, 60), width=2)
    # the inked double border
    d.rectangle([40, 40, W - 40, H - 40], outline=INK + (255,), width=7)
    d.rectangle([54, 54, W - 54, H - 54], outline=INK + (255,), width=2)
    # a halftone band behind the heading (the game's WANTED sits at the top 15 %)
    for y in range(64, int(H * 0.165)):
        for x in range(64, W - 64, 9):
            if (y - 64) % 9 == 0:
                rr = 2.2 + 1.4 * math.sin((x - 64) / (W - 128) * math.pi)
                d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(150, 30, 30, 70))
    # the bust's ruled frame (the ViewportFrame sits at 10..90 % across, 17..61 % down)
    d.rectangle([W * 0.1 - 8, H * 0.17 - 8, W * 0.9 + 8, H * 0.61 + 8], outline=INK + (255,), width=4)
    # rules under the name and over the note
    for fy in (0.715, 0.855):
        d.line([(90, H * fy), (W - 90, H * fy)], fill=INK + (200,), width=2)
    # stars in the corners of the border
    for (x, y) in ((40, 40), (W - 40, 40), (40, H - 40), (W - 40, H - 40)):
        st = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            rr = 14 if i % 2 == 0 else 6
            st.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
        d.polygon(st, fill=INK + (255,))
    # the torn outline: clear outside, a soft brown burn just inside
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(ragged(), fill=255)
    burn = mask.filter(ImageFilter.GaussianBlur(5))
    edge = ImageChops.subtract(mask, burn)
    out = base.convert("RGBA")
    shade = Image.new("RGBA", (W, H), (120, 80, 40, 255))
    out = Image.composite(shade, out, edge.point(lambda v: min(255, v * 2)))
    out.putalpha(mask)
    return out


im = paper()
im.save(os.path.join(OUT, "Paper.png"))
prev = Image.new("RGBA", (W + 80, H + 80), (110, 72, 40, 255))
prev.alpha_composite(im, (40, 40))
prev.save(os.path.join(ROOT, "preview", "wanted_paper.png"))
print("wanted paper:", im.size)
