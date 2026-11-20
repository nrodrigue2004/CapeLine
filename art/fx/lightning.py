# lightning.py: the Storm path's lightning strip (list-combat 2026-11-20, Everything Left 167 and 381: "the bolts,
# beams and lightning are part-built neon shapes"). A tileable strip for a camera-facing Beam (Fx.CombatFx
# lightning(): Zap Bolt, Chain Lightning, Bolt Ride; TextureMode Stretch per tile): an original jagged bolt with a
# white-hot core, a soft glow and short forks, drawn white on clear so the caster's path colour tints it. Its two
# ends sit on the strip's centre line so tiles join. FRAMES variants, one image each (a Beam shows a whole image
# across its width), 512 x 96, so the device can flick between them for the flicker (Config.Fx.lightning.frames).
# Output: art/export/fx/Lightning_<1-4>.png, preview art/preview/lightning.png. Run: python3 art/fx/lightning.py
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "fx")
os.makedirs(OUT, exist_ok=True)
W, H, FRAMES = 512, 96, 4
S = 4  # supersample


def bolt_points(rnd, x0, y0, x1, y1, rough, depth):
    """Midpoint displacement: a jagged line from (x0, y0) to (x1, y1)"""
    pts = [(x0, y0), (x1, y1)]
    amp = rough
    for _ in range(depth):
        out = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            mx, my = (ax + bx) / 2, (ay + by) / 2 + rnd.uniform(-amp, amp)
            out += [(mx, my), (bx, by)]
        pts = out
        amp *= 0.62
    return pts


def frame(seed):
    rnd = random.Random(seed)
    w, h = W * S, H * S
    cy = h / 2
    lines = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(lines)
    main = bolt_points(rnd, 0, cy, w, cy, h * 0.5, 6)
    # fit the zigzag inside the strip (scaled, not clipped flat)
    most = max(abs(y - cy) for _, y in main) or 1
    k = min(1.0, h * 0.34 / most)
    main = [(x, cy + (y - cy) * k) for x, y in main]
    forks = []
    for _ in range(3):
        i = rnd.randrange(len(main) // 8, len(main) * 7 // 8)
        x, y = main[i]
        ln = rnd.uniform(0.12, 0.22) * w
        up = rnd.choice((-1, 1))
        ex, ey = x + ln, y + up * rnd.uniform(0.18, 0.32) * h
        ey = max(8 * S, min(h - 8 * S, ey))
        forks.append(bolt_points(rnd, x, y, ex, ey, h * 0.08, 5))
    # glow: wide soft lines
    d.line(main, fill=120, width=int(16 * S))
    for f in forks:
        d.line(f, fill=70, width=int(9 * S))
    glow = lines.filter(ImageFilter.GaussianBlur(7 * S))
    core = Image.new("L", (w, h), 0)
    c = ImageDraw.Draw(core)
    c.line(main, fill=255, width=int(4.2 * S))
    for f in forks:
        c.line(f, fill=230, width=int(2.2 * S))
    a = ImageChops.add(glow, core)
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    img.putalpha(a)
    return img.resize((W, H), Image.LANCZOS)


sheet = Image.new("RGBA", (W, H * FRAMES), (255, 255, 255, 0))
for k in range(FRAMES):
    f = frame(167 + k * 31)
    f.save(os.path.join(OUT, "Lightning_%d.png" % (k + 1)))
    sheet.alpha_composite(f, (0, k * H))
prev = Image.new("RGB", (W * 2, H * FRAMES * 2), (40, 40, 52))
ImageDraw.Draw(prev).rectangle([0, H * FRAMES, W * 2, H * FRAMES * 2], fill=(120, 170, 230))
for half, tint in enumerate(((120, 210, 255), (255, 230, 90))):
    r, g, b, a = sheet.split()
    t = Image.merge("RGBA", (r.point(lambda v, q=tint[0]: v * q // 255), g.point(lambda v, q=tint[1]: v * q // 255),
                             b.point(lambda v, q=tint[2]: v * q // 255), a))
    for k in range(2):
        prev.paste(t, (k * W, half * H * FRAMES), t)
prev.save(os.path.join(ROOT, "preview", "lightning.png"))
print("lightning: art/export/fx/Lightning_1..%d.png" % FRAMES)
