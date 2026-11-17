"""Capeline effects library textures (overhaul plan step 3).

Draws every particle texture Config.Fx.lib names (the `file` fields) as white-on-transparent PNGs, so the
game tints them per element: art/export/fx/<file>. The second row of the preview (overhaul plan step 6) is
each path's own shape: snowflake, bubble, stone, leaf, sigil, crescent cut, twinkle, hex plate, ink blot. Sheets named *_4x4 are 4x4 flipbooks (16 frames, left to
right, top to bottom) for ParticleEmitter.FlipbookLayout Grid4x4. Original procedural art, no source images.
Also writes a contact sheet to art/preview/fx.png (on a dark background).

nate uploads the PNGs (Studio Asset Manager, bulk import), then puts each id in Config.Fx.lib.textures.
Until then the game uses Roblox's built-in particle images.

    python3 art/fx/textures.py
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


if __name__ == "__main__":
    main()
