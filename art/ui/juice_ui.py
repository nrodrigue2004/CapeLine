# art/ui/juice_ui.py: the juice table's screen pictures (list-combat 2026-11-20, Everything Left 386: "stamps,
# level badge ... confetti are plain frames"). Drawn in white or gold so the game can tint them:
#   Stamp     520 x 220: a rubber stamp's worn double frame with notched corners and speckled ink gaps, white on clear
#             (Fx.JuiceFx tints it the stamp's colour; the word stays the game's own label)
#   Badge     320 x 320: the level badge: a gold scalloped medallion with an inked edge, an inner ring of dots, a
#             shine and two ribbon tails (the number and LEVEL stay the game's labels)
#   Confetti  256 x 64: four white paper shapes in 64 x 64 cells (a curled ribbon, a star, a dot, a triangle),
#             each piece tinted its own colour
# Output: art/export/ui/juice/<Name>.png and art/preview/juice_ui.png. Run: python3 art/ui/juice_ui.py (PIL only)
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "ui", "juice")
os.makedirs(OUT, exist_ok=True)
INK = (22, 20, 34, 255)
WHITE = (255, 255, 255, 255)
random.seed(7)
SS = 3  # supersampling


def stamp():
    W, H = 520 * SS, 220 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    n = 18 * SS  # notch

    def frame(inset, width):
        x0, y0, x1, y1 = inset, inset, W - inset, H - inset
        k = n - inset // 3
        pts = [(x0 + k, y0), (x1 - k, y0), (x1, y0 + k), (x1, y1 - k), (x1 - k, y1), (x0 + k, y1), (x0, y1 - k),
               (x0, y0 + k)]
        d.line(pts + [pts[0]], fill=WHITE, width=width, joint="curve")

    frame(6 * SS, 12 * SS)
    frame(26 * SS, 4 * SS)
    # worn ink: speckled gaps knocked out of the frame
    mask = Image.new("L", (W, H), 255)
    md = ImageDraw.Draw(mask)
    for _ in range(160):
        x, y = random.uniform(0, W), random.uniform(0, H)
        r = random.uniform(0.8, 3.0) * SS
        md.ellipse([x - r, y - r, x + r, y + r], fill=0)
    for _ in range(6):  # a few scuffs along the edge
        x = random.uniform(0.1, 0.9) * W
        y = random.choice((8 * SS, H - 8 * SS))
        md.line([(x - 18 * SS, y - 1.5 * SS), (x + 18 * SS, y + 1.5 * SS)], fill=0, width=int(2 * SS))
    a = im.getchannel("A")
    a = Image.composite(a, Image.new("L", (W, H), 0), mask)
    im.putalpha(a)
    return im.resize((520, 220), Image.LANCZOS)


def badge():
    W = 320 * SS
    c = W / 2
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # ribbon tails behind
    for sx in (-1, 1):
        x = c + sx * 52 * SS
        pts = [(x - 30 * SS, c + 40 * SS), (x + 30 * SS, c + 40 * SS), (x + 30 * SS + sx * 14 * SS, W - 8 * SS),
               (x + sx * 8 * SS, W - 34 * SS), (x - 30 * SS + sx * 14 * SS, W - 8 * SS)]
        d.polygon(pts, fill=(220, 60, 60, 255), outline=INK)
        d.line(pts + [pts[0]], fill=INK, width=6 * SS)
    # the scalloped medallion: 24 bumps
    R, bump = 128 * SS, 14 * SS
    pts = []
    for i in range(240):
        a = 2 * math.pi * i / 240
        r = R + bump * (0.5 + 0.5 * math.cos(24 * a))
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=INK)
    pts2 = []
    for i in range(240):
        a = 2 * math.pi * i / 240
        r = R - 8 * SS + bump * (0.5 + 0.5 * math.cos(24 * a))
        pts2.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts2, fill=(255, 200, 60, 255))
    # the face: a slightly deeper gold disc, its ring of dots, an inked edge
    r = 104 * SS
    d.ellipse([c - r, c - r, c + r, c + r], fill=(246, 178, 40, 255), outline=INK, width=5 * SS)
    for i in range(32):
        a = 2 * math.pi * i / 32
        x, y = c + math.cos(a) * 92 * SS, c + math.sin(a) * 92 * SS
        q = 3.2 * SS
        d.ellipse([x - q, y - q, x + q, y + q], fill=(255, 236, 150, 255))
    # a shine across the upper left
    shine = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(shine)
    sd.ellipse([c - 80 * SS, c - 84 * SS, c + 20 * SS, c - 10 * SS], fill=110)
    shine = shine.filter(ImageFilter.GaussianBlur(16 * SS))
    disc = Image.new("L", (W, W), 0)
    ImageDraw.Draw(disc).ellipse([c - 98 * SS, c - 98 * SS, c + 98 * SS, c + 98 * SS], fill=255)
    shine = Image.composite(shine, Image.new("L", (W, W), 0), disc)
    im.paste((255, 255, 230, 255), (0, 0), shine)
    return im.resize((320, 320), Image.LANCZOS)


def confetti():
    S = 64 * SS
    im = Image.new("RGBA", (S * 4, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # a curled ribbon
    pts = []
    for k in range(60):
        t = k / 59
        x = 10 * SS + t * 44 * SS
        y = S / 2 + math.sin(t * math.pi * 2) * 14 * SS
        pts.append((x, y))
    d.line(pts, fill=WHITE, width=9 * SS, joint="curve")
    # a star
    cx = S + S / 2
    st = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = (27 if i % 2 == 0 else 12) * SS
        st.append((cx + math.cos(a) * r, S / 2 + 2 * SS + math.sin(a) * r))
    d.polygon(st, fill=WHITE)
    # a dot
    cx = 2 * S + S / 2
    d.ellipse([cx - 18 * SS, S / 2 - 18 * SS, cx + 18 * SS, S / 2 + 18 * SS], fill=WHITE)
    # a triangle
    cx = 3 * S + S / 2
    d.polygon([(cx, 10 * SS), (cx + 24 * SS, S - 12 * SS), (cx - 24 * SS, S - 12 * SS)], fill=WHITE)
    return im.resize((256, 64), Image.LANCZOS)


pics = {"Stamp": stamp(), "Badge": badge(), "Confetti": confetti()}
for name, im in pics.items():
    im.save(os.path.join(OUT, name + ".png"))

# the preview: each over a dark screen, tinted as the game would
prev = Image.new("RGBA", (1200, 400), (40, 44, 60, 255))
st = pics["Stamp"]
tint = Image.new("RGBA", st.size, (255, 200, 60, 255))
tint.putalpha(st.getchannel("A"))
prev.alpha_composite(tint, (40, 90))
prev.alpha_composite(pics["Badge"], (600, 40))
cf = pics["Confetti"]
for k, col in enumerate(((255, 90, 90), (90, 200, 255), (255, 220, 80), (140, 255, 140))):
    cell = cf.crop((k * 64, 0, k * 64 + 64, 64))
    t = Image.new("RGBA", cell.size, col + (255,))
    t.putalpha(cell.getchannel("A"))
    prev.alpha_composite(t.resize((96, 96)), (960 + (k % 2) * 110, 60 + (k // 2) * 120))
prev.save(os.path.join(ROOT, "preview", "juice_ui.png"))
print("juice_ui:", ", ".join(pics))
