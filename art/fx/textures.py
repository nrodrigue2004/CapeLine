"""Capeline effects library textures (overhaul plan step 3).

Draws every particle texture Config.Fx.lib names (the `file` fields) as white-on-transparent PNGs, so the
game tints them per element: art/export/fx/<file>. Sheets named *_4x4 are 4x4 flipbooks (16 frames, left to
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
    }
    for name, img in made.items():
        img.save(os.path.join(OUT, name))
    # contact sheet: each texture on a dark tile, tinted like in game
    tints = [(120, 210, 255), (255, 255, 255), (255, 170, 80), (120, 210, 255), (190, 120, 255), (255, 120, 40), (110, 255, 230), (200, 200, 205), (255, 120, 40), (120, 210, 255)]
    tile = 256
    prev = Image.new("RGB", (tile * 5, tile * 2), (18, 20, 28))
    for i, (name, img) in enumerate(made.items()):
        t = img.resize((tile, tile), Image.LANCZOS)
        col = Image.new("RGBA", (tile, tile), tints[i] + (255,))
        col.putalpha(t.getchannel("A"))
        prev.paste(col, ((i % 5) * tile, (i // 5) * tile), col)
    prev.save(PREVIEW)
    print("wrote", len(made), "textures to", OUT, "and", PREVIEW)


if __name__ == "__main__":
    main()
