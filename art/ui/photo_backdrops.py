# art/ui/photo_backdrops.py: Photo Mode's backdrop overlays (list-combat 2026-11-20, Everything Left 354: "Photo Mode
# backdrops are plain frames"). Five see-through 1280 x 720 pictures laid over the whole screen (the middle stays
# clear for the hero): COMIC a printed comic page's panel border with halftone corners and a burst behind the
# caption corner; SPEED inked anime speed lines from the edges; SUNSET a warm glare from the upper right with a lens
# streak; NOIR a heavy vignette, slanting rain and film grain; NEON glowing magenta and cyan edge bars over a
# perspective grid at the bottom. No words (the caption stays the game's own label).
# Output: art/export/ui/photo/<Name>.png and art/preview/photo_backdrops.png (each over a sample grey scene).
# Run: python3 art/ui/photo_backdrops.py   (PIL only)
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "ui", "photo")
os.makedirs(OUT, exist_ok=True)
W, H = 1280, 720
INK = (22, 20, 34, 255)


def blank():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def comic():
    im = blank()
    d = ImageDraw.Draw(im)
    # halftone dots growing into each corner
    for (cx, cy) in ((0, 0), (W, 0), (0, H), (W, H)):
        for y in range(0, H, 14):
            for x in range(0, W, 14):
                dist = math.hypot(x - cx, y - cy)
                r = max(0.0, 6.5 - dist / 42)
                if r > 0.5:
                    d.ellipse([x - r, y - r, x + r, y + r], fill=(22, 20, 34, 150))
    # a starburst behind the top-left caption corner
    cx, cy = 150, 52
    pts = []
    for k in range(28):
        a = k * math.pi / 14
        rr = 150 if k % 2 == 0 else 95
        pts.append((cx + math.cos(a) * rr * 1.5, cy + math.sin(a) * rr * 0.7))
    d.polygon(pts, fill=(255, 214, 64, 230), outline=INK)
    # the panel border: a thick ink frame with a white gutter and an inner ink line
    d.rectangle([0, 0, W - 1, H - 1], outline=(250, 248, 240, 255), width=26)
    d.rectangle([0, 0, W - 1, H - 1], outline=INK, width=10)
    d.rectangle([24, 24, W - 25, H - 25], outline=INK, width=6)
    return im


def speed():
    im = blank()
    d = ImageDraw.Draw(im)
    rnd = random.Random(4)
    cx, cy = W / 2, H / 2
    for k in range(150):
        a = rnd.uniform(0, math.pi * 2)
        r0 = rnd.uniform(0.34, 0.5) * W
        r1 = W
        w = rnd.uniform(0.004, 0.016)
        p0 = (cx + math.cos(a) * r0, cy + math.sin(a) * r0 * 0.62)
        pa = (cx + math.cos(a - w) * r1, cy + math.sin(a - w) * r1 * 0.62)
        pb = (cx + math.cos(a + w) * r1, cy + math.sin(a + w) * r1 * 0.62)
        d.polygon([p0, pa, pb], fill=(250, 250, 255, 210) if k % 3 else (22, 20, 34, 200))
    return im


def sunset():
    im = blank()
    glow = Image.new("L", (W, H), 0)
    gd = ImageDraw.Draw(glow)
    for r in range(520, 0, -8):
        gd.ellipse([W * 0.86 - r, -r * 0.6, W * 0.86 + r, r * 0.6 + 60], fill=int(220 * (1 - r / 520) ** 1.6))
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    sun = Image.new("RGBA", (W, H), (255, 190, 110, 0))
    sun.putalpha(glow)
    im = Image.alpha_composite(im, sun)
    d = ImageDraw.Draw(im)
    # a lens streak and three ghost rings toward the middle
    d.line([(W * 0.55, 40), (W, 92)], fill=(255, 236, 200, 90), width=6)
    for k, t in enumerate((0.55, 0.42, 0.3)):
        x, y = W * 0.86 + (W * 0.5 - W * 0.86) * (1 - t) * 1.6, 60 + (H * 0.5 - 60) * (1 - t) * 1.6
        r = 26 + k * 14
        d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 220, 170, 80), width=4)
    # warm bottom haze
    for y in range(H - 160, H):
        a = int(110 * (y - (H - 160)) / 160)
        d.line([(0, y), (W, y)], fill=(255, 140, 90, a))
    return im


def noir():
    im = blank()
    vig = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vig)
    for k in range(60):
        t = k / 60
        vd.ellipse([-W * 0.25 + t * W * 0.3, -H * 0.3 + t * H * 0.3, W * 1.25 - t * W * 0.3, H * 1.3 - t * H * 0.3],
                   fill=int(235 * (1 - t) ** 0.5))
    vig = vig.filter(ImageFilter.GaussianBlur(40))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dark.putalpha(vig)
    im = Image.alpha_composite(im, dark)
    d = ImageDraw.Draw(im)
    rnd = random.Random(9)
    for _ in range(420):
        x, y = rnd.uniform(-100, W), rnd.uniform(-60, H)
        l = rnd.uniform(18, 46)
        d.line([(x, y), (x + l * 0.3, y + l)], fill=(220, 225, 235, rnd.randint(40, 90)), width=1)
    for _ in range(5000):
        x, y = rnd.randrange(W), rnd.randrange(H)
        g = rnd.randint(0, 255)
        d.point((x, y), fill=(g, g, g, 40))
    # letterbox bars
    d.rectangle([0, 0, W, 46], fill=(0, 0, 0, 255))
    d.rectangle([0, H - 46, W, H], fill=(0, 0, 0, 255))
    return im


def neon():
    im = blank()
    glow = blank()
    gd = ImageDraw.Draw(glow)
    for (c, inset) in (((255, 60, 200, 255), 18), ((60, 230, 255, 255), 34)):
        gd.rounded_rectangle([inset, inset, W - inset, H - inset], radius=30, outline=c, width=6)
    blur = glow.filter(ImageFilter.GaussianBlur(10))
    im = Image.alpha_composite(im, blur)
    im = Image.alpha_composite(im, blur)
    im = Image.alpha_composite(im, glow)
    d = ImageDraw.Draw(im)
    # a perspective grid along the bottom
    hy = H * 0.74
    for k in range(-14, 15):
        d.line([(W / 2 + k * 18, hy), (W / 2 + k * 150, H)], fill=(255, 60, 200, 120), width=2)
    y = hy
    step = 6
    while y < H:
        d.line([(0, y), (W, y)], fill=(60, 230, 255, int(60 + 100 * (y - hy) / (H - hy))), width=2)
        y += step
        step *= 1.35
    return im


SETS = {"Comic": comic, "Speed": speed, "Sunset": sunset, "Noir": noir, "Neon": neon}
shots = []
for name, fn in SETS.items():
    im = fn()
    im.save(os.path.join(OUT, name + ".png"))
    bg = Image.new("RGBA", (W, H), (120, 130, 150, 255))
    bd = ImageDraw.Draw(bg)
    bd.rectangle([0, H * 0.7, W, H], fill=(80, 84, 96, 255))
    bd.rectangle([W * 0.46, H * 0.3, W * 0.54, H * 0.72], fill=(214, 36, 52, 255))  # a stand-in hero
    bd.ellipse([W * 0.47, H * 0.2, W * 0.53, H * 0.31], fill=(250, 210, 170, 255))
    shots.append(Image.alpha_composite(bg, im).resize((W // 2, H // 2)))
sheet = Image.new("RGB", (W + 30, (H // 2 + 10) * 3 + 10), (40, 40, 48))
for i, s in enumerate(shots):
    sheet.paste(s.convert("RGB"), (10 + (i % 2) * (W // 2 + 10), 10 + (i // 2) * (H // 2 + 10)))
sheet.save(os.path.join(ROOT, "preview", "photo_backdrops.png"))
print("backdrops:", len(shots))
