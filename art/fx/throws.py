"""Capeline: the throw and smash particles side by side (gap-fx3, 2026-11-19).

Reads art/export/fx/throws.json (written by `lune run art/fx/throws.luau` from Config.Fx.lib.throw through
Shared.FxPlan) and the effect sheets in art/export/fx, and draws art/preview/fx_throws.png: one row per preset
(low, medium, high), one tile per moment (the lift puff, the light, medium and heavy landings, the wall smash and
the prop coming home), seen from the side a third of a second in: each particle flown on its kind's speed,
spread, drag and fall, tinted the way FxLib tints it (dust and chips in the ground's or wall's colour). A 2D
stand-in for judging counts and looks, not a render of the game.

    lune run art/fx/throws.luau && python3 art/fx/throws.py
"""

import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FX = os.path.join(ROOT, "art", "export", "fx")
OUT = os.path.join(ROOT, "art", "preview", "fx_throws.png")
TILE = 260
PX = 9  # pixels a stud
MOMENTS = ["grab", "land_light", "land_medium", "land_heavy", "smash", "back"]
GROUND = (112, 108, 104)
DUST = (196, 186, 170)
WALL = (226, 214, 190)


def font(size):
    for name in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def frame(sheet, flip):
    if not flip:
        return sheet
    w = sheet.width // flip
    return sheet.crop((w, 0, w * 2, w))


def tinted(img, color, alpha):
    rgb = Image.new("RGBA", img.size, tuple(color) + (0,))
    # keep the sheet's own shading (the chip's lit face) times the tint
    base = img.convert("RGBA")
    px = base.load()
    out = rgb.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            out[x, y] = (r * color[0] // 255, g * color[1] // 255, b * color[2] // 255, int(a * alpha))
    return rgb


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_tile(data, sheets, cache, moment, counts, rng):
    tile = Image.new("RGBA", (TILE, TILE), (96, 120, 156, 255))
    d = ImageDraw.Draw(tile)
    floor = int(TILE * 0.72)
    smash = moment == "smash"
    if smash:
        d.rectangle([0, 0, int(TILE * 0.22), floor], fill=WALL + (255,), outline=(30, 28, 34), width=3)
    d.rectangle([0, floor, TILE, TILE], fill=GROUND + (255,))
    ox, oy = (int(TILE * 0.22), floor - 5 * PX) if smash else (TILE // 2, floor - 4)
    color = WALL if smash else (lerp(GROUND, DUST, 0.5) if moment != "back" else (200, 240, 255))
    radius = {"land_light": 6, "land_medium": 8, "land_heavy": 10}.get(moment, 4)
    radius = data["radius"].get(moment.replace("land_", ""), radius)
    t = 0.33
    for kind in sorted(counts):
        n = counts[kind]
        k = data["kinds"][kind]
        if kind == "shock":
            # the flat ring seen from the side: a squashed ellipse at the floor, grown most of the way
            r = radius * PX * 0.8
            im = tinted(cache(k), color, 0.6).resize((int(r * 2), max(4, int(r * 0.35))), Image.LANCZOS)
            tile.alpha_composite(im, (int(ox - r), int(floor - im.height / 2)))
            continue
        img = cache(k)
        for i in range(n):
            if kind == "dust":
                a = (i + rng.random()) / max(1, n) * math.tau
                side = math.cos(a)
                dirx, diry = (0.6 + 0.4 * rng.random(), 0.3 * side) if smash else (side, 0.35)
            else:
                spread = math.radians(k["spread"])
                ang = rng.uniform(-spread, spread)
                if smash:
                    dirx, diry = math.cos(ang), math.sin(ang)
                else:
                    dirx, diry = math.sin(ang), math.cos(ang)
            speed = rng.uniform(*k["speed"])
            drag = k["drag"]
            dist = speed * (1 - math.exp(-drag * t)) / drag if drag > 0 else speed * t
            x = ox + dirx * dist * PX
            y = oy - (diry * dist + 0.5 * k["rise"] * t * t) * PX
            y = min(y, floor - 2)
            life = rng.uniform(*k["life"])
            f = min(1, t / life)
            size = (k["size"][0] + (k["size"][1] - k["size"][0]) * f) * PX * rng.uniform(0.8, 1.2)
            if size < 2:
                continue
            alpha = (1 - f) * 0.9 + 0.1 if kind != "dust" else (1 - f) * 0.65
            c = color if k["light"] == 0 else lerp(color, (255, 255, 255), 0.3)
            im = tinted(img, c, alpha).resize((int(size), int(size)), Image.LANCZOS).rotate(rng.uniform(0, 360), resample=Image.BICUBIC)
            tile.alpha_composite(im, (int(x - size / 2), int(y - size / 2)))
    d = ImageDraw.Draw(tile)
    total = sum(counts.values())
    d.text((8, TILE - 26), "%s  (%d)" % (moment, total), fill=(250, 250, 250), font=font(16))
    return tile


def main():
    data = json.load(open(os.path.join(FX, "throws.json")))
    sheets = {}

    def cache(k):
        key = k["file"]
        if key not in sheets:
            sheets[key] = frame(Image.open(os.path.join(FX, key)).convert("RGBA"), k.get("flip")).resize((64, 64), Image.LANCZOS)
        return sheets[key]

    presets = ["low", "medium", "high"]
    label = 90
    img = Image.new("RGB", (label + TILE * len(MOMENTS) + 10 * len(MOMENTS), TILE * 3 + 30), (20, 22, 30))
    d = ImageDraw.Draw(img)
    for r, preset in enumerate(presets):
        rng = random.Random(7 + r)
        d.text((10, 10 + r * (TILE + 10) + TILE // 2 - 10), preset, fill=(240, 240, 240), font=font(20))
        for c, m in enumerate(MOMENTS):
            tile = draw_tile(data, sheets, cache, m, data["plans"][preset][m], rng)
            img.paste(tile.convert("RGB"), (label + c * (TILE + 10), 10 + r * (TILE + 10)))
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
