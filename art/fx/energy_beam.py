# energy_beam.py: the held energy beams' strip (list-combat 2026-11-20, Everything Left 381: "the bolts, beams and
# path heads are part-built neon shapes"). A tileable strip for a camera-facing Beam that scrolls along the beam
# (Fx.CombatFx beamHold and the bolts' glow; Config.Fx.energyBeam): an original rippling energy column, a white-hot
# core, a glow that swells in waves, fine streaks racing along it and sparks off its edges, drawn white on clear so
# the path colour tints it. 512 x 128, tiles along its length. Output: art/export/fx/EnergyBeam.png, preview
# art/preview/energy_beam.png. Run: python3 art/fx/energy_beam.py
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "fx")
os.makedirs(OUT, exist_ok=True)
W, H = 512, 128
S = 4
WAVES = 3  # whole swells along the tile, so its ends meet


def draw():
    rnd = random.Random(381)
    w, h = W * S, H * S
    cy = h / 2
    glow = Image.new("L", (w, h), 0)
    g = ImageDraw.Draw(glow)
    for x in range(0, w + 1, S):
        t = x / w * WAVES * 2 * math.pi
        half = (0.2 + 0.07 * math.sin(t)) * h
        g.line([(x, cy - half), (x, cy + half)], fill=105, width=S + 1)
    glow = glow.filter(ImageFilter.GaussianBlur(10 * S))
    body = Image.new("L", (w, h), 0)
    b = ImageDraw.Draw(body)
    for x in range(0, w + 1, S):
        t = x / w * WAVES * 2 * math.pi
        half = (0.1 + 0.035 * math.sin(t + 0.6)) * h
        b.line([(x, cy - half), (x, cy + half)], fill=140, width=S + 1)
    body = body.filter(ImageFilter.GaussianBlur(2 * S))
    core = Image.new("L", (w, h), 0)
    c = ImageDraw.Draw(core)
    c.rectangle([0, cy - 0.035 * h, w, cy + 0.035 * h], fill=255)
    core = core.filter(ImageFilter.GaussianBlur(1.2 * S))
    # streaks racing along the beam (wrapped so the tile joins)
    streaks = Image.new("L", (w, h), 0)
    s = ImageDraw.Draw(streaks)
    for _ in range(26):
        y = cy + rnd.uniform(-0.16, 0.16) * h
        x0 = rnd.uniform(0, w)
        ln = rnd.uniform(0.08, 0.25) * w
        for dx in (0, -w):
            s.line([(x0 + dx, y), (x0 + dx + ln, y)], fill=rnd.randint(150, 240), width=int(rnd.uniform(1.2, 2.6) * S))
    # sparks off the edges
    for _ in range(18):
        x = rnd.uniform(0, w)
        side = rnd.choice((-1, 1))
        y = cy + side * rnd.uniform(0.14, 0.3) * h
        r = rnd.uniform(1.2, 2.6) * S
        for dx in (0, -w, w):
            s.ellipse([x + dx - r, y - r, x + dx + r, y + r], fill=230)
    streaks = streaks.filter(ImageFilter.GaussianBlur(0.8 * S))
    a = ImageChops.add(ImageChops.add(glow, body), ImageChops.add(core, streaks))
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    img.putalpha(a)
    return img.resize((W, H), Image.LANCZOS)


img = draw()
img.save(os.path.join(OUT, "EnergyBeam.png"))
prev = Image.new("RGB", (W * 2, H * 4), (40, 40, 52))
ImageDraw.Draw(prev).rectangle([0, H * 2, W * 2, H * 4], fill=(120, 170, 230))
for row, tint in enumerate(((255, 140, 60), (120, 255, 200), (190, 120, 255), (255, 230, 90))):
    r, g, b, a = img.split()
    t = Image.merge("RGBA", (r.point(lambda v, q=tint[0]: v * q // 255), g.point(lambda v, q=tint[1]: v * q // 255),
                             b.point(lambda v, q=tint[2]: v * q // 255), a))
    for k in range(2):
        prev.paste(t, (k * W, row * H), t)
prev.save(os.path.join(ROOT, "preview", "energy_beam.png"))
print("energy_beam: art/export/fx/EnergyBeam.png")
