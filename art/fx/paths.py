"""Capeline: every power path's look side by side (overhaul plan step 6).

Reads art/export/fx/paths.json (written by `lune run art/fx/paths.luau` from Config.Fx) and the effect sheets
in art/export/fx, and draws art/preview/fx_paths.png: one row per path, with
  * the path's colour, accent and super tint swatches, its element and its signature names,
  * a Comic tile and an Anime tile of a hit: the element's impact particles (the real textures, tinted the way
    FxLib tints them: Comic chunkier and fuller colour, Anime thinner, whiter and wider),
  * a burst tile: the element's burst and super particles together (the super's big moment),
  * the Comic sound words.
It is a 2D stand-in for judging palettes and particle mixes, not a render of the game.

    lune run art/fx/paths.luau && python3 art/fx/paths.py
"""

import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FX = os.path.join(ROOT, "art", "export", "fx")
OUT = os.path.join(ROOT, "art", "preview", "fx_paths.png")

TILE = 150
LABEL = 300
WORDS = 220
ROW = TILE + 10
BG = (16, 18, 26)


def font(size):
    for name in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def frame(sheet, flip):
    """the first cell of a flipbook (or the whole image)"""
    if not flip:
        return sheet
    w = sheet.width // flip
    return sheet.crop((w, 0, w * 2, w))  # the second frame reads better than the first


def tinted(img, color, alpha=1.0):
    out = Image.new("RGBA", img.size, tuple(color) + (0,))
    a = img.getchannel("A").point(lambda v: int(v * alpha))
    out.putalpha(a)
    return out


def paste(canvas, img, cx, cy, size, rot, stretch=1.0):
    if size < 2:
        return
    # streak kinds (VelocityParallel in game) are drawn stretched along their flight
    im = img.resize((max(2, int(size * stretch)), int(size)), Image.LANCZOS).rotate(rot, expand=True, resample=Image.BICUBIC)
    canvas.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def scatter(canvas, data, sheets, counts, color, accent, style, rng, spread):
    """draw a moment's particles around the tile centre, like FxLib.emit would"""
    cx = cy = TILE / 2
    comic = style == "Comic"
    for kind in sorted(counts):
        n = counts[kind]
        k = data["kinds"][kind]
        img = sheets[k["file"]]
        for i in range(n):
            if n == 1:
                r, a = 0, 0
            else:
                r = spread * math.sqrt(rng.random()) * (1.25 if not comic else 1)
                a = rng.random() * math.tau
            px, py = cx + math.cos(a) * r, cy + math.sin(a) * r
            # studs to pixels: a particle shows at about the middle of its size over life
            size = (k["size"][0] + k["size"][1]) / 2 * 9 * (1.25 if comic else 0.85) * rng.uniform(0.7, 1.2)
            size = min(size, TILE * 0.9)
            light = k["light"] > 0
            c = color
            if light and not comic:
                c = lerp(color, (255, 255, 255), 0.45 if i % 2 == 0 else 0.15)
            elif light:
                c = lerp(color, (255, 255, 255), 0.2)
            rot = math.degrees(a) if k.get("face") == "streak" else rng.uniform(0, 360)
            streak = k.get("face") == "streak"
            if streak:
                size = max(size, 6)
            paste(canvas, tinted(img, c, 0.95 if light else 0.85), px, py, size, -rot, 4.0 if streak else 1.0)


def main():
    data = json.load(open(os.path.join(FX, "paths.json")))
    sheets = {}
    flips = {}
    for k in data["kinds"].values():
        f = k["file"]
        if f not in sheets:
            img = Image.open(os.path.join(FX, f)).convert("RGBA")
            flip = 4 if "_4x4" in f else None
            sheets[f] = frame(img, flip)
            flips[f] = flip
    order = data["order"]
    width = LABEL + TILE * 3 + 40 + WORDS
    height = ROW * len(order) + 40
    canvas = Image.new("RGBA", (width, height), BG + (255,))
    d = ImageDraw.Draw(canvas)
    big, small = font(18), font(12)
    d.text((LABEL + 10, 10), "Comic hit", fill=(200, 200, 210), font=small)
    d.text((LABEL + TILE + 20, 10), "Anime hit", fill=(200, 200, 210), font=small)
    d.text((LABEL + TILE * 2 + 30, 10), "Super moment", fill=(200, 200, 210), font=small)
    for row_i, set_name in enumerate(order):
        p = data["paths"][set_name]
        y = 30 + row_i * ROW
        color, accent = tuple(p["color"]), tuple(p["accent"])
        el = data["elements"][p["element"]]
        d.text((10, y + 6), set_name, fill=color, font=big)
        for i, sw in enumerate((color, accent, tuple(p["tint"]))):
            d.rectangle([10 + i * 26, y + 34, 32 + i * 26, y + 56], fill=sw, outline=(255, 255, 255))
        lines = [
            "element " + p["element"],
            "head " + p["head"] + ", mark " + p["mark"],
            "cast " + p["cast"] + ", piece " + p["piece"],
            "super " + p["super"] + " (" + str(p["superName"]) + ")",
        ]
        for i, text in enumerate(lines):
            d.text((10, y + 64 + i * 18), text, fill=(190, 195, 205), font=small)
        rng = random.Random(hash(set_name) % 1000)
        for col, (style, moment) in enumerate((("Comic", "impact"), ("Anime", "impact"), ("Anime", "super"))):
            tile = Image.new("RGBA", (TILE, TILE), (24, 27, 38, 255))
            counts = dict(el[moment])
            if moment == "super":
                for kind, n in el["burst"].items():
                    counts[kind] = counts.get(kind, 0) + n
                counts = {k: max(1, n // 2) if n > 1 else n for k, n in counts.items()}
            scatter(tile, data, sheets, counts, color, accent, style, rng, 30 if moment == "impact" else 50)
            canvas.alpha_composite(tile, (LABEL + col * (TILE + 10), y))
        words = p["words"] or []
        for i, w in enumerate(words):
            d.text((LABEL + TILE * 3 + 40, y + 20 + i * 34), w, fill=(255, 235, 80) if i == 2 else (255, 255, 255), font=big)
    canvas.convert("RGB").save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
