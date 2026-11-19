"""Capeline effects library textures (overhaul plan step 3).

Draws every particle texture Config.Fx.lib names (the `file` fields) as white-on-transparent PNGs, so the
game tints them per element: art/export/fx/<file>. The second row of the preview (overhaul plan step 6) is
each path's own shape: snowflake, bubble, stone, leaf, sigil, crescent cut, twinkle, hex plate, ink blot. Sheets named *_4x4 are 4x4 flipbooks (16 frames, left to
right, top to bottom) for ParticleEmitter.FlipbookLayout Grid4x4. Original procedural art, no source images.
Also writes a contact sheet to art/preview/fx.png (on a dark background). The creator's flight trails' strips
(creator art round 2, 2026-11-18: trail_<kit>.png, Config.Creator.trailFx) go to the same folder with their own
preview art/preview/fx_trails.png; `--trails` draws only those.

nate uploads the PNGs (Studio Asset Manager, bulk import), then puts each id in Config.Fx.lib.textures.
Until then the game uses Roblox's built-in particle images.

    python3 art/fx/textures.py [--trails] [--moves] [--destruction]   (--moves: only rune.png and scorch.png,
    Config.FxMoves; --destruction: only crater.png and crack.png, Config.Destruction.decals)
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "export", "fx")
PREVIEW = os.path.join(ROOT, "art", "preview", "fx.png")
rng = random.Random(7)


def grid(size):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    return (x - c) / c, (y - c) / c


def to_image(alpha):
    a = np.clip(alpha, 0, 1)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def glow(size=128):
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    return to_image(np.exp(-(r**2) * 5.5) * (r < 1))


def spark(size=128):
    # a bright core with a long and a short cross streak (VelocityParallel stretches it along its flight)
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r**2) * 30)
    streak = np.exp(-(x**2) * 400) * np.exp(-(y**2) * 2.5) + np.exp(-(y**2) * 400) * np.exp(-(x**2) * 9) * 0.6
    return to_image(np.clip(core + streak, 0, 1))


def core(size=256):
    # an explosion flash: a soft disc with ragged rays
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    a = np.arctan2(y, x)
    rays = np.zeros_like(r)
    for _ in range(14):
        ang = rng.uniform(-math.pi, math.pi)
        width = rng.uniform(0.04, 0.12)
        length = rng.uniform(0.6, 1.0)
        d = np.angle(np.exp(1j * (a - ang)))
        rays += np.exp(-(d**2) / (width**2)) * np.clip(1 - r / length, 0, 1)
    disc = np.exp(-(r**2) * 6)
    return to_image(np.clip(disc + rays * 0.8, 0, 1) * (r < 1))


def ring(size=256, thick=0.08, soft=0.06, inner_glow=0.25):
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    band = np.exp(-((r - (0.92 - thick)) ** 2) / (soft**2))
    fill = np.clip((r - 0.3) / 0.6, 0, 1) ** 2 * inner_glow * (r < 0.92)
    return to_image(np.clip(band + fill, 0, 1))


def implode(size=256):
    # lines rushing to the centre
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    for _ in range(40):
        ang = rng.uniform(0, math.tau)
        r0 = rng.uniform(0.25, 0.5) * size / 2
        r1 = rng.uniform(0.75, 1.0) * size / 2
        w = rng.randint(1, 3)
        d.line([(c + math.cos(ang) * r0, c + math.sin(ang) * r0), (c + math.cos(ang) * r1, c + math.sin(ang) * r1)], fill=255, width=w)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(img, np.float32) / 255
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    a = a * np.clip(r * 1.6, 0, 1) * (r < 1) + np.exp(-(r**2) * 25) * 0.8
    return to_image(a)


def ember(size=64):
    x, y = grid(size)
    r = np.sqrt(x * x + (y * 0.6) ** 2)
    return to_image(np.exp(-(r**2) * 9) * (r < 1))


def vortex(size=256):
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    a = np.arctan2(y, x)
    arms = 0.5 + 0.5 * np.cos(3 * a + r * 9)
    return to_image(arms**3 * np.clip(1 - r, 0, 1) * np.clip(r * 3, 0, 1))


def noise(size, scale, seed):
    r = np.random.default_rng(seed)
    out = np.zeros((size, size), np.float32)
    amp = 1.0
    total = 0.0
    for octave in range(4):
        n = max(2, int(scale * 2**octave))
        small = r.random((n, n)).astype(np.float32)
        layer = np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC), np.float32) / 255
        out += layer * amp
        total += amp
        amp *= 0.5
    return out / total


def sheet(frames, cell):
    s = Image.new("RGBA", (cell * 4, cell * 4), (255, 255, 255, 0))
    for i, f in enumerate(frames):
        s.paste(f, ((i % 4) * cell, (i // 4) * cell))
    return s


def smoke_sheet(cell=128):
    frames = []
    base = noise(cell, 3, 11)
    x, y = grid(cell)
    r = np.sqrt(x * x + y * y)
    for i in range(16):
        t = i / 15
        radius = 0.7 + 0.28 * t
        shape = np.clip(1 - r / radius, 0, 1) ** 0.6
        n = np.roll(base, int(t * 20), axis=0)
        a = shape * (0.7 + 0.9 * n) * (1 - t) ** 1.1 * 1.3
        frames.append(to_image(np.clip(a, 0, 1)))
    return sheet(frames, cell)


def fire_sheet(cell=128):
    frames = []
    x, y = grid(cell)
    for i in range(16):
        t = i / 15
        n = noise(cell, 4, 100 + i)
        # a teardrop: wide at the bottom, licking up
        # y grows downward: the wide base sits low, the tip licks up
        width = 0.6 * np.clip((y + 1.0) / 1.7, 0, 1) ** 0.7
        body = np.clip(1 - np.abs(x) / np.maximum(width, 1e-3), 0, 1) * np.clip((0.85 - y) * 1.5, 0, 1) * np.clip((y + 0.95) * 1.2, 0, 1)
        a = body * (0.6 + 0.8 * n) * (1 - t * 0.85)
        frames.append(to_image(np.clip(a, 0, 1)))
    return sheet(frames, cell)


def bolt_path(cell, r):
    pts = [(cell * 0.1, cell * r.uniform(0.42, 0.58))]
    steps = 7
    y = pts[0][1] / cell
    for k in range(1, steps + 1):
        y = min(0.68, max(0.32, y + r.uniform(-0.14, 0.14)))
        pts.append((cell * (0.1 + 0.8 * k / steps), cell * y))
    return pts


def electric_sheet(cell=128):
    frames = []
    for i in range(16):
        r = random.Random(500 + i)
        img = Image.new("L", (cell, cell), 0)
        d = ImageDraw.Draw(img)
        fade = 1 - (i / 15) * 0.7
        for branch in range(3):
            pts = bolt_path(cell, r)
            w = 4 if branch == 0 else 2
            d.line(pts, fill=int(255 * fade), width=w)
        img = img.filter(ImageFilter.GaussianBlur(1.5))
        sharp = Image.new("L", (cell, cell), 0)
        ds = ImageDraw.Draw(sharp)
        ds.line(bolt_path(cell, random.Random(500 + i)), fill=int(255 * fade), width=2)
        a = np.maximum(np.asarray(img, np.float32), np.asarray(sharp, np.float32)) / 255
        frames.append(to_image(np.clip(a * 1.4, 0, 1)))
    return sheet(frames, cell)


# ---------------------------------------------------------------------------
# the other paths (overhaul plan step 6): each path's own particle shape
# ---------------------------------------------------------------------------


def flake(size=128):
    # a six-armed snowflake with side branches (Frost)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    arm = size * 0.44
    for k in range(6):
        a = k * math.pi / 3
        ex, ey = c + math.cos(a) * arm, c + math.sin(a) * arm
        d.line([(c, c), (ex, ey)], fill=255, width=max(2, size // 32))
        for t, blen in ((0.45, 0.22), (0.72, 0.15)):
            bx, by = c + math.cos(a) * arm * t, c + math.sin(a) * arm * t
            for side in (-1, 1):
                b = a + side * math.pi / 4
                d.line([(bx, by), (bx + math.cos(b) * arm * blen, by + math.sin(b) * arm * blen)], fill=255, width=max(1, size // 48))
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    a = np.asarray(img, np.float32) / 255
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    return to_image(np.clip(a * 1.3 + np.exp(-(r**2) * 30) * 0.8, 0, 1))


def bubble(size=128):
    # a thin rim with a bright highlight and a faint inside (Tide)
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    rim = np.exp(-((r - 0.82) ** 2) / 0.004)
    inside = np.clip(1 - r / 0.85, 0, 1) * 0.12 * (r < 0.85)
    hx, hy = x + 0.35, y + 0.35
    hl = np.exp(-(hx**2 * 18 + hy**2 * 40)) * 0.9
    return to_image(np.clip(rim + inside + hl, 0, 1))


def rock(size=128):
    # a chunky faceted stone silhouette with some shading (Earth, Colossus, Titan)
    r = random.Random(31)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    pts = []
    n = 7
    for k in range(n):
        a = k / n * math.tau + r.uniform(-0.25, 0.25)
        rad = size * r.uniform(0.32, 0.45)
        pts.append((c + math.cos(a) * rad, c + math.sin(a) * rad))
    d.polygon(pts, fill=255)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    x, y = grid(size)
    shade = 0.75 + 0.25 * np.clip(-(x + y) * 0.7, -1, 1)
    grain = 0.85 + 0.3 * noise(size, 8, 5)
    return to_image(np.clip(a * shade * grain, 0, 1))


def leaf(size=128):
    # a pointed leaf with a centre vein (Earth's vines)
    x, y = grid(size)
    # rotate 35 degrees so the leaf sits diagonally
    a = math.radians(35)
    u = x * math.cos(a) + y * math.sin(a)
    v = -x * math.sin(a) + y * math.cos(a)
    width = 0.42 * np.clip(1 - u**2 / 0.8, 0, 1) ** 0.8
    body = np.clip(1 - np.abs(v) / np.maximum(width, 1e-3), 0, 1) ** 0.5 * (np.abs(u) < 0.9)
    vein = np.exp(-(v**2) / 0.0012) * (np.abs(u) < 0.85) * 0.5
    return to_image(np.clip(body * 0.85 - vein + 0.15 * body, 0, 1))


def glyph(size=256):
    # an original sigil (Mind, Spirit): an outer ring with twelve ticks, an inner ring, one triangle with a
    # small ring at each corner, and a little eye ring at the heart. Plain geometry, no real-world symbol.
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    w = max(2, size // 90)

    def circle(cx, cy, R, fill=255, width=w):
        d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=fill, width=width)

    circle(c, c, 0.46 * size)
    circle(c, c, 0.34 * size, 200)
    for k in range(12):
        a = k * math.tau / 12
        r0, r1 = (0.40 if k % 3 else 0.37) * size, 0.46 * size
        d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)], fill=255, width=w)
    R = 0.34 * size
    pts = [(c + math.cos(-math.pi / 2 + k * math.tau / 3) * R, c + math.sin(-math.pi / 2 + k * math.tau / 3) * R) for k in range(3)]
    d.line(pts + [pts[0]], fill=230, width=w)
    for px, py in pts:
        circle(px, py, 0.05 * size)
    circle(c, c, 0.08 * size, 255, w + 1)
    img = img.filter(ImageFilter.GaussianBlur(1.0))
    a = np.asarray(img, np.float32) / 255
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    return to_image(np.clip(a * 1.2 + np.exp(-(r**2) * 20) * 0.4, 0, 1))


def slash(size=256):
    # a thin crescent cut, bright at the middle and tapering at both tips (Blade)
    x, y = grid(size)
    r = np.sqrt((x + 0.25) ** 2 + y * y)
    ang = np.arctan2(y, x + 0.25)
    span = np.clip(1 - np.abs(ang) / 1.3, 0, 1)
    band = np.exp(-((r - 0.85) ** 2) / (0.0006 + 0.004 * span))
    return to_image(np.clip(band * span**0.6 * 1.4, 0, 1))


def star(size=128):
    # a four-point twinkle with a soft core (Light, Martial, Gunslinger, Titan)
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    ax = np.exp(-np.abs(y) * 40) * np.clip(1 - np.abs(x), 0, 1) ** 2
    ay = np.exp(-np.abs(x) * 40) * np.clip(1 - np.abs(y), 0, 1) ** 2
    d1 = np.exp(-np.abs(x - y) * 60) * np.clip(1 - r * 1.6, 0, 1)
    d2 = np.exp(-np.abs(x + y) * 60) * np.clip(1 - r * 1.6, 0, 1)
    core = np.exp(-(r**2) * 40)
    return to_image(np.clip(ax + ay + (d1 + d2) * 0.5 + core, 0, 1))


def hexplate(size=128):
    # a hexagon plate with a bright rim (Gadgeteer)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    for rad, fill in ((0.44, 255), (0.34, 90)):
        pts = [(c + math.cos(k * math.pi / 3) * rad * size, c + math.sin(k * math.pi / 3) * rad * size) for k in range(6)]
        d.polygon(pts, fill=fill)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    return to_image(np.asarray(img, np.float32) / 255)


def ink(size=128):
    # an ink blot: a lumpy splat with drops around it (Shadow)
    r = random.Random(77)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    for _ in range(9):
        a = r.uniform(0, math.tau)
        dist = r.uniform(0, 0.16) * size
        rad = r.uniform(0.12, 0.22) * size
        x0, y0 = c + math.cos(a) * dist, c + math.sin(a) * dist
        d.ellipse([x0 - rad, y0 - rad, x0 + rad, y0 + rad], fill=255)
    for _ in range(7):
        a = r.uniform(0, math.tau)
        dist = r.uniform(0.3, 0.42) * size
        rad = r.uniform(0.025, 0.06) * size
        x0, y0 = c + math.cos(a) * dist, c + math.sin(a) * dist
        d.ellipse([x0 - rad, y0 - rad, x0 + rad, y0 + rad], fill=255)
    img = img.filter(ImageFilter.GaussianBlur(1.5))
    a = np.asarray(img, np.float32) / 255
    return to_image(np.clip((a - 0.3) * 2.2, 0, 1))


# ---------------------------------------------------------------------------
# every ability's own look (nate's playtest 2026-11-19, Config.FxMoves): two flat ground sheets. Not uploaded
# yet: the game uses built-in images until their ids are in Config.Fx.lib.textures (PLACEHOLDER ART).
# ---------------------------------------------------------------------------
def rune(size=256):
    # a ground rune circle: two rings, eight small diamonds between them and a four-point star inside. Plain
    # geometry of our own (no real-world script or symbol).
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    w = max(2, size // 80)
    for R, fill in ((0.47, 255), (0.36, 220), (0.12, 200)):
        d.ellipse([c - R * size, c - R * size, c + R * size, c + R * size], outline=fill, width=w)
    for k in range(8):
        a = k * math.tau / 8 + math.tau / 16
        r0 = 0.415 * size
        px, py = c + math.cos(a) * r0, c + math.sin(a) * r0
        s = 0.03 * size
        d.polygon([(px, py - s), (px + s, py), (px, py + s), (px - s, py)], fill=255)
    for k in range(4):
        a = k * math.tau / 4
        tip = (c + math.cos(a) * 0.33 * size, c + math.sin(a) * 0.33 * size)
        l = (c + math.cos(a + 0.5) * 0.1 * size, c + math.sin(a + 0.5) * 0.1 * size)
        r = (c + math.cos(a - 0.5) * 0.1 * size, c + math.sin(a - 0.5) * 0.1 * size)
        d.line([l, tip, r], fill=230, width=w)
    img = img.filter(ImageFilter.GaussianBlur(1.0))
    return to_image(np.clip(np.asarray(img, np.float32) / 255 * 1.2, 0, 1))


def scorch(size=256):
    # a scorch mark: a soft dark blot with a ragged edge and a few streaks out (white here; the game tints it
    # dark, LightEmission 0)
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    n = noise(size, 6, 31)
    edge = 0.62 + 0.12 * np.sin(ang * 7 + 1.3) + 0.1 * (n - 0.5)
    body = np.clip((edge - r) / 0.18, 0, 1) ** 0.7
    streaks = np.clip(np.cos(ang * 11) ** 24 * np.clip(1 - np.abs(r - 0.7) / 0.25, 0, 1), 0, 1) * 0.6
    return to_image(np.clip(body * (0.75 + 0.25 * n) + streaks, 0, 1))


MOVES = {"rune.png": rune, "scorch.png": scorch}


def moves_main():
    """Only the ability sheets (the uploaded library sheets stay as they are)."""
    os.makedirs(OUT, exist_ok=True)
    for name, fn in MOVES.items():
        fn().save(os.path.join(OUT, name))
    print("wrote", len(MOVES), "ability sheets to", OUT)


# ---------------------------------------------------------------------------
# the creator's flight trails (creator art round 2, 2026-11-18): strips for Roblox Trails, 512 x 128, u along
# the trail (u = 0 the newest end), v across it; white on transparent so the trail's colours tint them
# (Config.Creator.trailFx: Stretch strips fade along their length, Wrap strips repeat)
# ---------------------------------------------------------------------------
TW, TH = 512, 128


def strip_grid():
    v, u = np.mgrid[0:TH, 0:TW].astype(np.float32)
    return u / (TW - 1), (v - (TH - 1) / 2) / ((TH - 1) / 2)


def trail_ribbon():
    # a soft band with two bright edges, fading toward its tail
    u, v = strip_grid()
    band = np.clip((0.92 - np.abs(v)) * 8, 0, 1)
    edges = np.exp(-((np.abs(v) - 0.78) ** 2) * 300)
    a = (0.55 * band + 0.6 * edges) * (1 - u) ** 0.8
    return to_image(np.clip(a, 0, 1))


def trail_streak():
    # a thin white-hot core line with a soft glow, tapering to the tail
    u, v = strip_grid()
    w = 0.25 * (1 - u) + 0.03
    core = np.exp(-(v / w) ** 2 * 6)
    glow_ = np.exp(-(v / (w * 3)) ** 2 * 2) * 0.45
    return to_image(np.clip((core + glow_) * (1 - u) ** 0.6, 0, 1))


def trail_twin():
    # a narrower ribbon for the hands: a bright core in a soft band
    u, v = strip_grid()
    a = np.exp(-(v**2) * 3) * 0.55 + np.exp(-(v**2) * 40) * 0.8
    return to_image(np.clip(a * (1 - u) ** 0.9, 0, 1))


def trail_sparkle():
    # twinkles strewn along a faint band (Wrap: repeats along the trail)
    img = np.zeros((TH, TW), np.float32)
    u, v = strip_grid()
    img += np.exp(-(v**2) * 4) * 0.18
    r = random.Random(41)
    st = np.asarray(star(64).getchannel("A"), np.float32) / 255
    for _ in range(8):
        s = r.choice((44, 60, 76, 96))
        x = r.randint(0, TW - s)
        y = r.randint(8, TH - s - 8) if s < TH - 16 else (TH - s) // 2
        piece = np.asarray(Image.fromarray((st * 255).astype(np.uint8)).resize((s, s), Image.LANCZOS),
                           np.float32) / 255
        img[y:y + s, x:x + s] = np.maximum(img[y:y + s, x:x + s], piece)
    return to_image(np.clip(img, 0, 1))


def trail_comet():
    # a blazing head, flame tongues streaming back and thinning out
    u, v = strip_grid()
    n = noise(TW, 6, 23)[:TH, :]
    w = 0.95 * (1 - u) ** 0.7 + 0.05
    body = np.clip(1 - np.abs(v) / w, 0, 1) ** 0.8
    flick = np.clip(n * 1.6 - 0.3 + (1 - u) * 0.6, 0, 1)
    head = np.exp(-(u / 0.08) ** 2) * np.exp(-(v**2) * 2)
    return to_image(np.clip(body * flick * (1 - u) ** 0.5 + head, 0, 1))


def trail_smoke():
    # soft puffs along the trail (Wrap)
    u, v = strip_grid()
    n = noise(TW, 4, 61)[:TH, :]
    n2 = noise(TW, 9, 62)[:TH, :]
    a = np.clip((n * 0.8 + n2 * 0.4) * 1.5 - 0.45, 0, 1) * np.clip(1 - np.abs(v) ** 2, 0, 1)
    a = 0.5 * (a + a[:, ::-1])  # the two ends match, so the strip repeats without a seam
    return to_image(np.clip(a, 0, 1))


def trail_storm():
    # a crackling bolt running the trail's length inside a faint glow (Wrap)
    img = Image.new("L", (TW, TH), 0)
    d = ImageDraw.Draw(img)
    r = random.Random(77)
    for branch, width in ((0, 7), (1, 3), (2, 3)):
        pts = []
        y = TH / 2
        for k in range(13):
            y = min(TH * 0.85, max(TH * 0.15, y + r.uniform(-24, 24)))
            pts.append((k * TW / 12, y if 0 < k < 12 else TH / 2))  # both ends mid-strip: no seam
        d.line(pts, fill=255 if branch == 0 else 170, width=width)
    blur = img.filter(ImageFilter.GaussianBlur(5))
    u, v = strip_grid()
    a = np.maximum(np.asarray(img, np.float32), np.asarray(blur, np.float32) * 1.4) / 255
    a = a + np.exp(-(v**2) * 3) * 0.12
    return to_image(np.clip(a, 0, 1))


def trail_neon():
    # a hard-edged bright band with chevrons running along it (Wrap)
    u, v = strip_grid()
    band = (np.abs(v) < 0.7).astype(np.float32) * 0.35 + (np.abs(np.abs(v) - 0.78) < 0.08).astype(np.float32)
    phase = (u * 4) % 1.0
    chev = (np.abs(phase - 0.5 - np.abs(v) * 0.25) < 0.08).astype(np.float32) * (np.abs(v) < 0.6)
    img = Image.fromarray((np.clip(band + chev, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))
    return to_image(np.asarray(img, np.float32) / 255)


TRAILS = {
    "trail_ribbon.png": trail_ribbon, "trail_streak.png": trail_streak, "trail_twin.png": trail_twin,
    "trail_sparkle.png": trail_sparkle, "trail_comet.png": trail_comet, "trail_smoke.png": trail_smoke,
    "trail_storm.png": trail_storm, "trail_neon.png": trail_neon,
}


def trails_main():
    """The trail strips into art/export/fx and a preview (each strip on a dark row, tinted, with its name)."""
    from PIL import ImageFont
    tints = [(80, 200, 255), (255, 255, 255), (255, 110, 200), (255, 230, 120), (255, 140, 50), (190, 190, 200),
             (140, 170, 255), (90, 255, 160)]
    pad, label = 10, 26
    prev = Image.new("RGB", (TW + 2 * pad, len(TRAILS) * (TH + label + pad) + pad), (18, 20, 28))
    d = ImageDraw.Draw(prev)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for i, (name, fn) in enumerate(TRAILS.items()):
        img = fn()
        img.save(os.path.join(OUT, name))
        y = pad + i * (TH + label + pad)
        d.text((pad, y), name[6:-4], fill=(235, 235, 240), font=font)
        col = Image.new("RGBA", (TW, TH), tints[i] + (255,))
        col.putalpha(img.getchannel("A"))
        prev.paste(col, (pad, y + label), col)
    path = os.path.join(ROOT, "art", "preview", "fx_trails.png")
    prev.save(path)
    print("wrote", len(TRAILS), "trail strips and", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    made = {
        "spark.png": spark(),
        "glow.png": glow(),
        "core.png": core(),
        "shock.png": ring(),
        "implode.png": implode(),
        "ember.png": ember(),
        "vortex.png": vortex(),
        "smoke_4x4.png": smoke_sheet(),
        "fire_4x4.png": fire_sheet(),
        "electric_4x4.png": electric_sheet(),
        "flake.png": flake(),
        "bubble.png": bubble(),
        "rock.png": rock(),
        "leaf.png": leaf(),
        "glyph.png": glyph(),
        "slash.png": slash(),
        "star.png": star(),
        "hex.png": hexplate(),
        "ink.png": ink(),
    }
    for name, img in made.items():
        img.save(os.path.join(OUT, name))
    # contact sheet: each texture on a dark tile, tinted like in game
    tints = [(120, 210, 255), (255, 255, 255), (255, 170, 80), (120, 210, 255), (190, 120, 255), (255, 120, 40), (110, 255, 230), (200, 200, 205), (255, 120, 40), (120, 210, 255),
             (190, 235, 255), (40, 150, 255), (150, 115, 70), (120, 190, 90), (255, 110, 210), (255, 70, 90), (255, 250, 200), (90, 230, 160), (120, 80, 200)]
    tile = 256
    rows = (len(made) + 4) // 5
    prev = Image.new("RGB", (tile * 5, tile * rows), (18, 20, 28))
    for i, (name, img) in enumerate(made.items()):
        t = img.resize((tile, tile), Image.LANCZOS)
        col = Image.new("RGBA", (tile, tile), tints[i] + (255,))
        col.putalpha(t.getchannel("A"))
        prev.paste(col, ((i % 5) * tile, (i // 5) * tile), col)
    prev.save(PREVIEW)
    print("wrote", len(made), "textures to", OUT, "and", PREVIEW)


# ---------------------------------------------------------------------------
# destruction decals (2026-11-19, the props gap): BuildingFx's crater and facade crack in comic ink, full colour
# (not tinted). The crater is seen from above: a dark pit with an inked rim, light rock chips round it and cracks
# running out; the crack is a branching inked split with a pale chipped edge, for any wall colour. Previews
# art/preview/destruction.png (on a street grey and a wall cream).
# ---------------------------------------------------------------------------
INK = (24, 22, 30)


def _jag(d, pts, width, fill):
    d.line(pts, fill=fill, width=width, joint="curve")


def _crack_path(rr, x, y, ang, length, steps, spread):
    pts = [(x, y)]
    for _ in range(steps):
        ang += rr.uniform(-spread, spread)
        x += math.cos(ang) * length / steps
        y += math.sin(ang) * length / steps
        pts.append((x, y))
    return pts


def crater(size=512):
    rr = random.Random(41)
    S = size * 2  # drawn at twice the size, then smoothed down
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    n = noise(S, 5, 12)
    # cracks out from the rim (under the pit)
    for k in range(9):
        a = k * math.tau / 9 + rr.uniform(-0.2, 0.2)
        pts = _crack_path(rr, c + math.cos(a) * S * 0.28, c + math.sin(a) * S * 0.28, a, S * rr.uniform(0.13, 0.2), 5, 0.5)
        _jag(d, pts, int(S * 0.012), INK + (255,))
        if k % 2 == 0:
            m = pts[2]
            _jag(d, _crack_path(rr, m[0], m[1], a + rr.choice((-0.9, 0.9)), S * 0.07, 3, 0.4), int(S * 0.007), INK + (255,))
    # the rim: a ragged ring of light rock with ink round it
    ring = []
    for k in range(64):
        a = k * math.tau / 64
        r = S * (0.31 + 0.025 * math.sin(a * 5 + 1) + rr.uniform(-0.012, 0.012))
        ring.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(ring, fill=(150, 140, 128, 255), outline=INK + (255,), width=int(S * 0.012))
    pit = []
    for k in range(48):
        a = k * math.tau / 48
        r = S * (0.22 + 0.02 * math.sin(a * 4 + 0.5) + rr.uniform(-0.01, 0.01))
        pit.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pit, fill=(58, 50, 52, 255), outline=INK + (255,), width=int(S * 0.012))
    d.ellipse([c - S * 0.12, c - S * 0.1, c + S * 0.12, c + S * 0.12], fill=(36, 30, 36, 255))
    # chips on the rim: light faces with an ink edge
    for k in range(16):
        a = k * math.tau / 16 + rr.uniform(-0.15, 0.15)
        r = S * rr.uniform(0.27, 0.36)
        w = S * rr.uniform(0.02, 0.035)
        px, py = c + math.cos(a) * r, c + math.sin(a) * r
        poly = [(px + math.cos(a + j * math.tau / 5 + rr.uniform(-0.3, 0.3)) * w, py + math.sin(a + j * math.tau / 5) * w) for j in range(5)]
        d.polygon(poly, fill=(196, 186, 172, 255), outline=INK + (255,), width=int(S * 0.006))
    # comic shading: a little speckle
    arr = np.asarray(img, np.float32)
    shade = 0.88 + 0.12 * n
    arr[..., :3] *= shade[..., None]
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return out.resize((size, size), Image.LANCZOS)


def crack(size=512):
    rr = random.Random(23)
    S = size * 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    arms = []
    for k in range(5):
        a = k * math.tau / 5 + rr.uniform(-0.35, 0.35)
        arms.append(_crack_path(rr, c, c, a, S * rr.uniform(0.33, 0.46), 6, 0.55))
    # the pale chipped edge first (offset a little up and left), then the ink split over it
    for pts in arms:
        _jag(d, [(x - S * 0.006, y - S * 0.006) for (x, y) in pts], int(S * 0.03), (236, 228, 214, 230))
    for pts in arms:
        for i in range(len(pts) - 1):
            w = int(S * (0.028 * (1 - i / len(pts)) + 0.006))
            d.line([pts[i], pts[i + 1]], fill=INK + (255,), width=w, joint="curve")
            q = pts[i + 1]
            d.ellipse([q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2], fill=INK + (255,))
        for j in (2, 4):
            if j < len(pts) and rr.random() < 0.8:
                m = pts[j]
                ang = math.atan2(m[1] - c, m[0] - c) + rr.choice((-0.8, 0.8))
                br = _crack_path(rr, m[0], m[1], ang, S * 0.1, 3, 0.4)
                _jag(d, br, int(S * 0.008), INK + (255,))
    # a little dark star where it was hit
    star_ = []
    for k in range(10):
        a = k * math.tau / 10
        r = S * (0.06 if k % 2 == 0 else 0.03)
        star_.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(star_, fill=INK + (255,))
    return img.resize((size, size), Image.LANCZOS)


DESTRUCTION = {"crater.png": crater, "crack.png": crack}


def destruction_main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for name, fn in DESTRUCTION.items():
        im = fn()
        im.save(os.path.join(OUT, name))
        made.append(im)
    tile = 384
    prev = Image.new("RGBA", (tile * 2, tile), (0, 0, 0, 255))
    for i, (im, bg) in enumerate(zip(made, ((118, 118, 124), (226, 214, 190)))):
        cell = Image.new("RGBA", (tile, tile), bg + (255,))
        t = im.resize((tile, tile), Image.LANCZOS)
        cell.paste(t, (0, 0), t)
        prev.paste(cell, (i * tile, 0))
    prev.save(os.path.join(ROOT, "art", "preview", "destruction.png"))
    print("wrote", len(made), "destruction decals to", OUT)


if __name__ == "__main__":
    import sys

    if "--trails" in sys.argv:  # only the creator's trail strips (the library sheets above stay as uploaded)
        os.makedirs(OUT, exist_ok=True)
        trails_main()
    elif "--destruction" in sys.argv:  # only the crater and crack decals (BuildingFx)
        destruction_main()
    elif "--moves" in sys.argv:  # only the ability sheets (Config.FxMoves), not uploaded yet
        moves_main()
    else:
        main()
        trails_main()
        moves_main()
