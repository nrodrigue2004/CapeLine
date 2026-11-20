# decals.py: the road pictures for shapes-2 (2026-11-19): a zebra crossing (white bars on clear, a little worn), a
# storm drain grate, the pools' water ripples and the lane dashes' worn paint, drawn with PIL into
# art/export/shapes/Zebra.png, Drain.png, Water.png and Dash.png (uploaded as Images; ids in Config.Life.shapes). The crossing's picture runs across its street left to right (the strip's own x), so
# its bars lie along the traffic. Preview: art/preview/shapes_decals.png.  Run: python3 art/shapes/decals.py
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "export", "shapes")
os.makedirs(OUT, exist_ok=True)
rng = random.Random(20261119)

# ---------------------------------------------------------------- zebra: 28 studs across x 5 deep, 36 px a stud
W, H = 1008, 180
z = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(z)
bar, gap = 1.6 * 36, 1.2 * 36
n = int((W + gap) // (bar + gap))
x0 = (W - (n * bar + (n - 1) * gap)) / 2
for k in range(n):
    x = x0 + k * (bar + gap)
    d.rounded_rectangle([x, 8, x + bar, H - 8], radius=6, fill=(242, 240, 232, 255))
# wear: tyre-polished speckles and scuffs knocked out of the paint
px = z.load()
for _ in range(1400):
    x, y = rng.randrange(W), rng.randrange(H)
    if px[x, y][3]:
        r = rng.choice((1, 1, 2, 3))
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if 0 <= x + dx < W and 0 <= y + dy < H and dx * dx + dy * dy <= r * r and px[x + dx, y + dy][3]:
                    c = px[x + dx, y + dy]
                    px[x + dx, y + dy] = (c[0], c[1], c[2], rng.choice((90, 160, 200)))
for k in range(2):  # two wheel tracks along the traffic
    y = int(H * (0.3 + 0.4 * k))
    for x in range(W):
        for dy in range(-6, 7):
            c = px[x, y + dy]
            if c[3]:
                px[x, y + dy] = (int(c[0] * 0.86), int(c[1] * 0.86), int(c[2] * 0.84), c[3])
z = z.filter(ImageFilter.SMOOTH)
z.save(os.path.join(OUT, "Zebra.png"))

# ---------------------------------------------------------------- drain: a cast-iron grate 3 x 1.4 studs, 80 px a stud
W2, H2 = 240, 112
g = Image.new("RGBA", (W2, H2), (64, 66, 70, 255))
d = ImageDraw.Draw(g)
d.rounded_rectangle([2, 2, W2 - 3, H2 - 3], radius=8, fill=(78, 80, 84, 255), outline=(40, 42, 46, 255), width=4)
for k in range(9):
    x = 22 + k * 22
    d.rounded_rectangle([x, 18, x + 10, H2 - 18], radius=4, fill=(16, 16, 18, 255))
d.rectangle([10, H2 // 2 - 3, W2 - 10, H2 // 2 + 3], fill=(78, 80, 84, 255))
for _ in range(600):
    x, y = rng.randrange(W2), rng.randrange(H2)
    c = g.getpixel((x, y))
    g.putpixel((x, y), (min(255, c[0] + 18), min(255, c[1] + 14), c[2], 255) if rng.random() < 0.5 else (c[0] // 2 + 50, c[1] // 2 + 30, c[2] // 2 + 10, 255))
g.save(os.path.join(OUT, "Drain.png"))

# ---------------------------------------------------------------- water ripples (nate: "pools need to look better as
# well"): a seamless caustic net, bright lines on clear, 512 px a tile (Config.Life.shapes.water.studs)
import numpy as np  # noqa: E402

R = 512
yy, xx = np.mgrid[0:R, 0:R].astype(np.float32) / R * 2 * np.pi
f = np.zeros((R, R), np.float32)
nr = np.random.default_rng(7)
for k in range(7):  # whole-number frequencies keep it seamless
    a, b = int(nr.integers(1, 5)), int(nr.integers(1, 5))
    ph = nr.uniform(0, 6.28)
    f += np.sin(a * xx + b * yy + ph + 0.9 * np.sin(b * xx - a * yy + ph * 2))
f /= 7
lines = np.clip(1 - np.abs(f) * 9, 0, 1) ** 2
glint = np.clip(1 - np.abs(f - 0.35) * 14, 0, 1) ** 3 * 0.6
alpha = np.clip(lines * 0.85 + glint, 0, 1)
rgba = np.dstack([np.full_like(alpha, 0.92), np.full_like(alpha, 0.98), np.ones_like(alpha), alpha])
ripple = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
ripple.save(os.path.join(OUT, "Water.png"))

# ---------------------------------------------------------------- lane dash: worn road paint (own rng, so the pictures
# above never change). It fills the whole picture, so the stretch onto any dash, either way round, still reads as
# paint: soft ragged ends, tyre-polished streaks and knocked-out flecks.
dr = random.Random(20261120)
DW, DH = 256, 32
dash = Image.new("RGBA", (DW, DH), (0, 0, 0, 0))
dp = dash.load()
for x in range(DW):
    for y in range(DH):
        edge = min(x, DW - 1 - x, y * 4, (DH - 1 - y) * 4)
        a = 255 if edge > 6 else int(255 * max(0, edge - dr.random() * 3) / 6)
        v = 236 - dr.randrange(0, 14)
        dp[x, y] = (v, v - 2, v - 8, a)
for _ in range(90):
    x, y = dr.randrange(DW), dr.randrange(DH)
    ln = dr.randrange(6, 40)
    for k in range(ln):
        if 0 <= x + k < DW:
            c = dp[x + k, y]
            dp[x + k, y] = (c[0], c[1], c[2], int(c[3] * dr.choice((0.35, 0.55, 0.7))))
dash = dash.filter(ImageFilter.SMOOTH)
dash.save(os.path.join(OUT, "Dash.png"))

# ---------------------------------------------------------------- the preview: both on asphalt
pv = Image.new("RGBA", (1100, 420), (70, 72, 76, 255))
for _ in range(20000):
    x, y = rng.randrange(1100), rng.randrange(420)
    v = rng.randrange(50, 100)
    pv.putpixel((x, y), (v, v, v + 2, 255))
pv.alpha_composite(z, (46, 40))
pv.alpha_composite(g, (430, 280))
water = Image.new("RGBA", (300, 300), (70, 160, 210, 255))
water.alpha_composite(ripple.resize((300, 300)))
pv.alpha_composite(water.resize((160, 160)), (900, 240))
for k in range(3):
    pv.alpha_composite(dash.resize((216, 18)), (40, 250 + k * 50))
pv.convert("RGB").save(os.path.join(ROOT, "art", "preview", "shapes_decals.png"))
print("decals: Zebra.png, Drain.png, Water.png, Dash.png")
