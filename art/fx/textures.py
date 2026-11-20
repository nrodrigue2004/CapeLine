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

    python3 art/fx/textures.py [--trails] [--moves] [--cracks] [--destruction] [--wrecks]   (--moves: only rune.png and scorch.png,
    Config.FxMoves; --cracks: only the landing crack decals crack_1..3.png, Config.Fx.crack.decals, preview
    art/preview/fx_cracks.png; --destruction: only crater.png and crack.png, Config.Destruction.decals; --wrecks: only
    bolt.png, the downed robots' nut, preview art/preview/fx_bolt.png; --chips: only chip.png, the throw and smash
    chip, preview art/preview/fx_chip.png; --scars: only the Crater's burn scars scar_1..3.png, preview
    art/preview/fx_scars.png; --rain: only the weather's rain.png and splash.png, preview art/preview/fx_rain.png)
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


def bolt(size=128):
    # a downed robot's loose hex nut (gap-wrecks, 2026-11-19: the wreck's pop, Config.Fx.lib.kinds.bolt): a
    # six-sided plate with a round hole, a lit top edge and an inked rim, so a tint reads as painted metal
    x, y = grid(size)
    ang = np.arctan2(y, x)
    r = np.sqrt(x * x + y * y)
    # the hexagon's edge distance (flat sides)
    sector = (ang + math.pi / 6) % (math.pi / 3) - math.pi / 6
    hexr = r * np.cos(sector)
    body = np.clip((0.84 - hexr) * 40, 0, 1)
    hole = np.clip((r - 0.34) * 40, 0, 1)
    ink = np.clip((hexr - 0.74) * 12, 0, 1) * 0.55 + np.clip((0.44 - r) * 12, 0, 1) * 0.55
    light = 0.78 + 0.22 * np.clip(-(x + y) * 0.8, -1, 1)
    a = body * hole
    shade = np.clip(light * (1 - ink), 0, 1)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = (shade[..., None] * 255).astype(np.uint8)
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def wrecks_main():
    """Only the wreck's nut (art/preview/fx_bolt.png on a dark background, in two tints)."""
    os.makedirs(OUT, exist_ok=True)
    im = bolt()
    im.save(os.path.join(OUT, "bolt.png"))
    prev = Image.new("RGB", (3 * 160, 160), (34, 36, 44))
    for i, tint in enumerate([(255, 255, 255), (200, 60, 50), (120, 130, 150)]):
        tinted = Image.fromarray((np.asarray(im.convert("RGB"), np.float32) * np.array(tint) / 255).astype(np.uint8))
        prev.paste(tinted, (i * 160 + 16, 16), im)
    prev.save(os.path.join(ROOT, "art", "preview", "fx_bolt.png"))
    print("wrote bolt.png to", OUT)


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


# ---------------------------------------------------------------------------
# the landing crack decals (gap polish 2026-11-19, MoveFx; Config.Fx.crack.decals): comic ground cracks in
# their own colours (not tinted): ink cracks with a pale chipped edge, a dark pit in the middle, spider-web
# rings between the rays and a few chips. Three variants so landings side by side differ; each is drawn at
# 2x and scaled down. Original procedural art.
# ---------------------------------------------------------------------------
CRACK = 512
INK = (24, 22, 28)
CHIP = (232, 226, 214)


def _crack_ray(r, cx, cy, ang, length, width, depth, out):
    # a jagged polyline from (cx, cy) along ang; returns its points and adds branches to out
    pts = [(cx, cy)]
    steps = 7
    x, y = cx, cy
    zig = r.choice((-1, 1))
    for i in range(1, steps + 1):
        seg = length / steps
        zig = -zig  # a sharp comic zig-zag, not a wandering twig
        a = ang + zig * r.uniform(0.25, 0.5)
        x += math.cos(a) * seg
        y += math.sin(a) * seg
        pts.append((x, y))
        if depth < 1 and i in (3, 5) and r.random() < 0.45:
            side = r.choice((-1, 1))
            out.append((x, y, ang + side * r.uniform(0.5, 0.95), length * r.uniform(0.25, 0.45),
                        width * 0.55, depth + 1))
    return pts


def crack_decal(seed):
    r = random.Random(seed)
    S = CRACK * 2
    c = S / 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hi = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(hi)
    rays = r.randint(6, 8)
    base = r.uniform(0, math.tau)
    lines = []
    todo = []
    ends = []
    for k in range(rays):
        ang = base + k / rays * math.tau + r.uniform(-0.25, 0.25)
        length = S * r.uniform(0.3, 0.47)
        todo.append((c, c, ang, length, S * 0.03, 0))
    while todo:
        x, y, ang, length, width, depth = todo.pop()
        pts = _crack_ray(r, x, y, ang, length, width, depth, todo)
        lines.append((pts, width))
        if depth == 0:
            ends.append(pts)
    # spider-web rings: short ink links between neighbouring rays at two radii
    for ring in (0.35, 0.62):
        for k in range(len(ends)):
            if r.random() < 0.7:
                a = ends[k][int(ring * 7)]
                b = ends[(k + 1) % len(ends)][int(ring * 7)]
                mid = ((a[0] + b[0]) / 2 + r.uniform(-12, 12), (a[1] + b[1]) / 2 + r.uniform(-12, 12))
                lines.append(([a, mid, b], S * 0.011))
    # the chipped pale edge first (offset up-left), then the ink over it
    for pts, w in lines:
        n = len(pts)
        for i in range(n - 1):
            t = i / max(1, n - 1)
            ww = max(2.0, w * (1 - t * 0.85))
            a, b = pts[i], pts[i + 1]
            o = max(2.0, ww * 0.35)
            dh.line([(a[0] - o, a[1] - o), (b[0] - o, b[1] - o)], fill=CHIP + (150,), width=int(ww))
    for pts, w in lines:
        n = len(pts)
        for i in range(n - 1):
            t = i / max(1, n - 1)
            ww = max(3.0, w * (1 - t * 0.8))
            d.line([pts[i], pts[i + 1]], fill=INK + (255,), width=int(ww))
            d.ellipse([pts[i + 1][0] - ww / 2, pts[i + 1][1] - ww / 2, pts[i + 1][0] + ww / 2,
                       pts[i + 1][1] + ww / 2], fill=INK + (255,))
    # the pit: a ragged ink blot with a pale rim, then a soft dent shadow under everything
    pit = []
    pr = S * r.uniform(0.08, 0.1)
    for i in range(18):
        a = i / 18 * math.tau
        rr = pr * r.uniform(0.75, 1.2)
        pit.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
    dh.polygon([(x - 6, y - 6) for x, y in pit], fill=CHIP + (210,))
    d.polygon(pit, fill=INK + (255,))
    # chips: small ink and pale shards thrown around the pit
    for i in range(r.randint(10, 16)):
        a = r.uniform(0, math.tau)
        dist = S * r.uniform(0.11, 0.3)
        x, y = c + math.cos(a) * dist, c + math.sin(a) * dist
        s = S * r.uniform(0.006, 0.014)
        poly = [(x + math.cos(a + j * 2.1 + r.uniform(-0.4, 0.4)) * s, y + math.sin(a + j * 2.1) * s) for j in range(3)]
        d.polygon(poly, fill=(INK if i % 3 else CHIP) + (255,))
    # dent: a soft dark ring of shade round the pit (alpha only, under the lines)
    x, y = grid(S)
    rad = np.sqrt(x * x + y * y)
    shade = np.clip(1 - rad / 0.42, 0, 1) ** 2 * 0.35
    dent = np.zeros((S, S, 4), np.uint8)
    dent[..., 0], dent[..., 1], dent[..., 2] = INK
    dent[..., 3] = (shade * 255).astype(np.uint8)
    out = Image.fromarray(dent, "RGBA")
    out = Image.alpha_composite(out, hi)
    out = Image.alpha_composite(out, img)
    return out.resize((CRACK, CRACK), Image.LANCZOS)


CRACKS = {"crack_1.png": 11, "crack_2.png": 23, "crack_3.png": 37}


def cracks_main():
    """The three landing crack decals into art/export/fx and a preview on asphalt, roof and grass tiles."""
    os.makedirs(OUT, exist_ok=True)
    grounds = [(92, 94, 100), (150, 140, 128), (96, 140, 80)]
    tile = 320
    prev = Image.new("RGB", (tile * len(CRACKS), tile * len(grounds)), (18, 20, 28))
    for i, (name, seed) in enumerate(CRACKS.items()):
        img = crack_decal(seed)
        img.save(os.path.join(OUT, name))
        t = img.resize((tile - 20, tile - 20), Image.LANCZOS)
        for j, g in enumerate(grounds):
            bg = Image.new("RGBA", (tile, tile), g + (255,))
            bg.alpha_composite(t, (10, 10))
            prev.paste(bg.convert("RGB"), (i * tile, j * tile))
    path = os.path.join(ROOT, "art", "preview", "fx_cracks.png")
    prev.save(path)
    print("wrote", len(CRACKS), "crack decals and", path)


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


# ---------------------------------------------------------------------------
# throws, rams and the Crater's burn scars (gap-fx3, 2026-11-19)
# chip.png: a chunk of rubble knocked off by a throw landing or a wall smash (Config.Fx.lib.kinds.chip): a
#   faceted chip with a lit top face, a shaded side and an inked rim, drawn white so a tint reads as the wall's
#   or the ground's own colour.
# scar_1..3.png: the Crater's burn scars (Config.World.crater.scars.decals), full colour, seen from above: a
#   long charred streak running out from the blast (the image's left end points at the lab), sooty and jagged,
#   with ash flecks, a few glassed cracks and an inked edge, fading out at its far end. Never blood: soot and ash.
# ---------------------------------------------------------------------------
def chip(size=128):
    r = random.Random(53)
    S = size * 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    pts = []
    n = 6
    for k in range(n):
        a = k / n * math.tau + r.uniform(-0.3, 0.3)
        rad = S * r.uniform(0.3, 0.42)
        pts.append((c + math.cos(a) * rad, c + math.sin(a) * rad))
    w = int(S * 0.05)
    d.polygon(pts, fill=(150, 150, 150, 255), outline=(40, 40, 40, 255), width=w)
    # the lit top face: the polygon's upper-left half, a ridge line to the opposite corner
    top = [pts[2], pts[3], pts[4], pts[5]]
    d.polygon(top, fill=(240, 240, 240, 255))
    d.line([pts[2], pts[5]], fill=(40, 40, 40, 255), width=int(S * 0.035))
    d.line(pts + [pts[0]], fill=(30, 30, 30, 255), width=w, joint="curve")
    # a crack across the shaded side and a couple of grit specks
    m = ((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2)
    d.line([(c, c), m], fill=(60, 60, 60, 255), width=int(S * 0.02))
    arr = np.asarray(img, np.float32)
    grain = 0.88 + 0.12 * noise(S, 10, 9)
    arr[..., :3] *= grain[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)


def scar(seed, w=1024, h=256):
    rr = random.Random(seed)
    S = 2
    W, H = w * S, h * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    u = x / W  # 0 at the blast end, 1 at the far end
    v = (y - H / 2) / (H / 2)  # -1..1 across

    def big(scale, sd):
        return np.asarray(Image.fromarray((noise(256, scale, sd) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255

    n1, n2, n3 = big(5, seed), big(16, seed + 1), big(3, seed + 2)
    # the streak's half width: a broad scorch at the blast end tapering to a ragged point, its edges bitten
    # into tongues by the noise and bent a little along its length
    taper = np.clip(1 - u, 0, 1) ** 0.75
    half = 0.86 * taper * (0.78 + 0.5 * (n1 - 0.5)) + 0.05
    bend = 0.18 * np.sin(u * (3 + seed % 3) + seed) * u
    inside = half - np.abs(v - bend)
    body = np.clip(inside / 0.05, 0, 1)
    core = np.clip((inside - 0.18 * taper) / (0.22 * taper + 0.02), 0, 1)
    edge = np.clip(1 - np.abs(inside) / 0.03, 0, 1)  # the inked rim
    fade = np.clip((0.97 - u) / 0.25, 0, 1) * np.clip(u / 0.1, 0, 1) ** 0.6
    # colours: a brown-grey soot halo outside, dark soot, a near-black char core
    ash = np.array([92, 82, 80], np.float32)
    soot = np.array([56, 50, 52], np.float32)
    char = np.array([28, 24, 28], np.float32)
    col = ash[None, None, :] * (1 - body[..., None]) + soot[None, None, :] * body[..., None]
    col = col * (1 - core[..., None]) + char[None, None, :] * core[..., None]
    col *= 0.85 + 0.3 * (n2[..., None] - 0.5)
    halo = np.clip((inside + 0.22) / 0.22, 0, 1) * (0.25 + 0.35 * n3)
    alpha = np.maximum(body, halo) * fade
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., :3] = col
    rgba[..., 3] = alpha * 255
    img = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    # glassed cracks only inside the char core (pale, thin, jagged), drawn on their own layer then masked
    cr = Image.new("L", (W, H), 0)
    dc = ImageDraw.Draw(cr)
    for _ in range(4 + seed % 2):
        x0 = rr.uniform(0.03, 0.3) * W
        pts = _crack_path(rr, x0, H / 2 + rr.uniform(-0.2, 0.2) * H, rr.uniform(-0.2, 0.2), W * rr.uniform(0.18, 0.32), 8, 0.4)
        dc.line(pts, fill=255, width=int(H * 0.012), joint="curve")
    crack = np.asarray(cr, np.float32) / 255 * core * fade
    arr = np.asarray(img, np.float32)
    arr[..., :3] = arr[..., :3] * (1 - crack[..., None] * 0.8) + np.array([150, 140, 156], np.float32) * crack[..., None] * 0.8
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    # ash flecks: dark soot spatter just past the edge, pale ash specks inside
    for _ in range(90):
        fx = rr.uniform(0.02, 0.8)
        side = rr.choice((-1, 1))
        hw = (0.86 * (1 - fx) ** 0.75 * 0.85 + 0.05)
        fy = H / 2 + side * (hw + abs(rr.gauss(0, 0.08))) * H / 2
        rad = H * rr.uniform(0.006, 0.018) * (1 - fx * 0.6)
        d.ellipse([fx * W - rad, fy - rad, fx * W + rad, fy + rad], fill=(44, 38, 42, int(230 * (1 - fx * 0.8))))
    for _ in range(70):
        fx = rr.uniform(0.03, 0.7)
        fy = H / 2 + rr.gauss(0, 0.15) * H / 2
        rad = H * rr.uniform(0.004, 0.01)
        d.ellipse([fx * W - rad, fy - rad, fx * W + rad, fy + rad], fill=(132, 124, 122, 200))
    arr = np.asarray(img, np.float32)
    ink = edge * fade * (0.6 + 0.4 * n2)
    arr[..., :3] = arr[..., :3] * (1 - ink[..., None]) + np.array(INK, np.float32)[None, None, :] * ink[..., None]
    arr[..., 3] = np.maximum(arr[..., 3], ink * 255)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS)


def chips_main():
    """Only the chip (art/preview/fx_chip.png: in a dust, a wall cream and a brick tint)."""
    os.makedirs(OUT, exist_ok=True)
    im = chip()
    im.save(os.path.join(OUT, "chip.png"))
    prev = Image.new("RGB", (4 * 160, 160), (34, 36, 44))
    for i, tint in enumerate([(255, 255, 255), (196, 186, 170), (226, 214, 190), (176, 84, 66)]):
        tinted = Image.fromarray((np.asarray(im.convert("RGB"), np.float32) * np.array(tint) / 255).astype(np.uint8))
        prev.paste(tinted, (i * 160 + 16, 16), im)
    prev.save(os.path.join(ROOT, "art", "preview", "fx_chip.png"))
    print("wrote chip.png to", OUT)


def scars_main():
    """Only the Crater's burn scars (art/preview/fx_scars.png on the Crater floor's ash grey)."""
    os.makedirs(OUT, exist_ok=True)
    made = []
    for k in (1, 2, 3):
        im = scar(60 + k)
        im.save(os.path.join(OUT, "scar_%d.png" % k))
        made.append(im)
    prev = Image.new("RGBA", (1024, 3 * 256 + 40), (128, 118, 108, 255))
    for i, im in enumerate(made):
        prev.paste(im, (0, 10 + i * 266), im)
    prev.convert("RGB").save(os.path.join(ROOT, "art", "preview", "fx_scars.png"))
    print("wrote", len(made), "burn scars to", OUT)


def rain_main():
    """The weather's rain (list-combat 2026-11-20, Everything Left 273): rain.png, a soft thin streak (64 x 256,
    white on transparent, brightest in its middle third) for the falling rain, and splash.png, a small crown of
    droplets for where it lands. Preview art/preview/fx_rain.png on a dusk-blue city colour."""
    os.makedirs(OUT, exist_ok=True)
    w, h = 64, 256
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    across = np.exp(-((x - (w - 1) / 2) / 3.2) ** 2)
    t = y / (h - 1)
    along = np.clip(np.sin(t * math.pi), 0, 1) ** 0.6 * (0.55 + 0.45 * t)
    streak = to_image(across * along * 0.9)
    streak.save(os.path.join(OUT, "rain.png"))
    size = 128
    gx, gy = grid(size)
    r = np.sqrt(gx ** 2 + gy ** 2)
    ring = np.exp(-((r - 0.62) / 0.07) ** 2) * (gy > -0.15)
    drops = np.zeros_like(r)
    for i in range(7):
        a = math.pi * (0.15 + 0.7 * i / 6)
        cx, cy = math.cos(a) * 0.75, -math.sin(a) * 0.75 - 0.1
        drops += np.exp(-(((gx - cx) ** 2 + (gy - cy) ** 2) / 0.006))
    splash = to_image(np.clip(ring * 0.8 + drops, 0, 1))
    splash.save(os.path.join(OUT, "splash.png"))
    pv = Image.new("RGBA", (420, 300), (46, 58, 86, 255))
    for i in range(14):
        pv.alpha_composite(streak.resize((16, 64)), (12 + i * 28, 20 + (i * 37) % 80))
    pv.alpha_composite(streak, (20, 30))
    pv.alpha_composite(splash, (250, 150))
    pv.save(os.path.join(ROOT, "art", "preview", "fx_rain.png"))
    print("wrote rain.png and splash.png to", OUT)


if __name__ == "__main__":
    import sys

    if "--rain" in sys.argv:  # only the weather's rain streak and splash (Config.Fx.weather)
        rain_main()
    elif "--cracks" in sys.argv:  # only the landing crack decals (Config.Fx.crack.decals)
        cracks_main()
    elif "--trails" in sys.argv:  # only the creator's trail strips (the library sheets above stay as uploaded)
        os.makedirs(OUT, exist_ok=True)
        trails_main()
    elif "--destruction" in sys.argv:  # only the crater and crack decals (BuildingFx)
        destruction_main()
    elif "--moves" in sys.argv:  # only the ability sheets (Config.FxMoves), not uploaded yet
        moves_main()
    elif "--wrecks" in sys.argv:  # only the wreck's nut (Config.Fx.lib.textures.bolt)
        wrecks_main()
    elif "--chips" in sys.argv:  # only the throw and smash chip (Config.Fx.lib.textures.chip)
        chips_main()
    elif "--scars" in sys.argv:  # only the Crater's burn scars (Config.World.crater.scars.decals)
        scars_main()
    else:
        main()
        trails_main()
        moves_main()
