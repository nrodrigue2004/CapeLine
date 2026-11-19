# thumbs.py: the picture tiles of the creator, the Robux shop and the weapon list (2026-11-19). Plain python3 with
# PIL. Reads art/thumbs/pieces.json (`lune run art/thumbs/pieces.luau`) and the Blender renders in
# art/thumbs/cells/<set>/<kit>.png (THUMBS=1 runs of the art/blender scripts: the wear sets through
# wear.thumb_cells, `clothed.py thumbs` for suits, shirts, pants, the flat masks and the legs, capes.py and
# `weapons.py --thumbs`), draws the flat ones itself (emblems from the emblem set, flight trails from their strips,
# auras from the effects textures, the shop's effect tints and travel styles), frames every tile as a small comic
# card (a tinted card with halftone dots, the piece with a thick ink outline, an ink border) and packs them into
# 1024 x 1024 sheets of 128 px cells: art/export/thumbs/Thumbs_<n>.png. Writes src/config/Thumbs.luau (each key's
# cell; each sheet's uploaded image id, kept while the sheet's pixels are unchanged, else 0 until it is uploaded
# again: art/thumbs/sheets.json holds each sheet's hash and id) and the contact sheet art/preview/thumbs.png.
# The pose tiles (2026-11-19): every emote, landing pose and photo pose from `clothed.py poses` (the game's own
# Shared.EmotePoses on the plain blocky body) on a sheet of their own after the others.
# Catalog faces and hair are never drawn here (nate's rule: they come only from the Roblox catalog).
# Run from the repo root: python3 art/thumbs/thumbs.py
import hashlib
import json
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "art")
CELLS = os.path.join(ART, "thumbs", "cells")
OUT = os.path.join(ART, "export", "thumbs")
CELL = 128
PER = 8  # 8 x 8 cells a sheet
SS = 2  # draw at twice the size, then shrink (smooth edges)

INK = (17, 17, 17)
PAPER = (255, 247, 224)
PAL = {"p": (40, 110, 220), "s": (235, 60, 60), "a": (255, 210, 60), "dark": (34, 38, 52), "white": (240, 240, 245),
       "gold": (255, 210, 70), "ice": (200, 245, 255), "glowRed": (255, 80, 40)}
# card tints by body area (the creator's AREAS), light enough for the ink to read on
CARD = {"head": (255, 230, 196), "hat": (255, 230, 196), "ears": (255, 230, 196), "torso": (214, 232, 255),
        "arms": (220, 246, 220), "legs": (238, 224, 255), "back": (255, 222, 222), "emblem": (255, 247, 224),
        "fx": (40, 46, 70), "weapon": (226, 230, 240), "trail": (205, 228, 255),
        # the pose tiles (2026-11-19): emotes, landing poses, Photo Mode's poses
        "emote": (255, 236, 170), "landing": (255, 214, 186), "photo": (206, 238, 255)}
AREA = {"head": "head", "hat": "hat", "ears": "ears", "suit": "torso", "shirt": "torso", "neck": "torso",
        "shoulders": "torso", "emblem": "emblem", "arms": "arms", "hands": "arms", "wrist": "arms", "pants": "legs",
        "belt": "legs", "legs": "legs", "feet": "legs", "back": "back", "backpack": "back", "aura": "fx",
        "trail": "fx"}
# the creator tab's render set (art/thumbs/cells/<set>)
SETS = {"suit": ["suits"], "shirt": ["shirts"], "pants": ["pants"], "legs": ["legs"], "head": ["heads", "masks"],
        "hat": ["hats"], "hands": ["gloves"], "feet": ["boots"], "belt": ["belts"], "shoulders": ["shoulders"],
        "backpack": ["backs"], "ears": ["ears"], "neck": ["necks"], "wrist": ["wrists"], "arms": ["arms"],
        "back": ["capes", "coats"]}


def load(path):
    with open(path) as fh:
        return json.load(fh)


def render_cell(sets, kit):
    for s in sets:
        f = os.path.join(CELLS, s, kit.replace(":", "~") + ".png")
        if os.path.isfile(f):
            return Image.open(f).convert("RGBA")
    return None


# ---------------------------------------------------------------- the comic card
def rounded_mask(size, r, inset=0):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((inset, inset, size - 1 - inset, size - 1 - inset), r, fill=255)
    return m


def halftone(size, colour):
    """Faint dots growing toward the lower right (the comic print look of Kit's panels)."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    step = 9 * SS
    for y in range(0, size + step, step):
        for x in range(0, size + step, step):
            t = (x + y) / (2 * size)
            r = max(0.0, (t - 0.45)) * 5.5 * SS
            if r > 0.4:
                ox = (step // 2) if (y // step) % 2 else 0
                d.ellipse((x + ox - r, y - r, x + ox + r, y + r), fill=colour)
    return im


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def outlined(art, width):
    """The art with a solid ink outline round its silhouette (alpha grown by `width`)."""
    a = art.split()[3].point(lambda v: 255 if v > 40 else 0)
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    base = Image.new("RGBA", art.size, INK + (0,))
    base.putalpha(grown)
    base.alpha_composite(art)
    return base


def card(art, bg, fit=0.86, outline=3):
    """One 128 px cell: the tinted card, the art (RGBA, any size) fitted and ink-outlined, the ink border."""
    S = CELL * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inner = Image.new("RGBA", (S, S), bg + (255,))
    dark = sum(bg) < 300
    inner.alpha_composite(halftone(S, shade(bg, 1.35 if dark else 0.9) + (255,)))
    if art is not None:
        box = int(S * fit)
        w, h = art.size
        k = box / max(w, h)
        a = art.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
        pad = outline * SS + 2
        canvas = Image.new("RGBA", (a.width + 2 * pad, a.height + 2 * pad), (0, 0, 0, 0))
        canvas.alpha_composite(a, (pad, pad))
        canvas = outlined(canvas, outline * SS)
        inner.alpha_composite(canvas, ((S - canvas.width) // 2, (S - canvas.height) // 2))
    border = 4 * SS
    radius = 16 * SS
    im.paste(Image.new("RGBA", (S, S), INK + (255,)), (0, 0), rounded_mask(S, radius))
    im.paste(inner, (0, 0), rounded_mask(S, radius - border // 2, border))
    return im.resize((CELL, CELL), Image.LANCZOS)


def framed_render(src, bg):
    """A Blender render cut to its frame (the body around a piece runs off the card's edge, as a comic panel)."""
    S = CELL * SS
    border = 4 * SS
    a = src.resize((S - 2 * border, S - 2 * border), Image.LANCZOS)
    pad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pad.alpha_composite(a, (border, border))
    pad = outlined(pad, 3 * SS)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inner = Image.new("RGBA", (S, S), bg + (255,))
    inner.alpha_composite(halftone(S, shade(bg, 0.9) + (255,)))
    inner.alpha_composite(pad)
    radius = 16 * SS
    im.paste(Image.new("RGBA", (S, S), INK + (255,)), (0, 0), rounded_mask(S, radius))
    im.paste(inner, (0, 0), rounded_mask(S, radius - border // 2, border))
    return im.resize((CELL, CELL), Image.LANCZOS)


# ---------------------------------------------------------------- the drawn ones
def tinted(path, rgb):
    im = Image.open(path).convert("RGBA")
    r, g, b, a = im.split()
    col = Image.merge("RGB", (r, g, b))
    col = ImageChops.multiply(col, Image.new("RGB", im.size, rgb))
    out = col.convert("RGBA")
    out.putalpha(a)
    return out


def emblem(kit):
    shape, _, backing = kit.partition(":")
    folder = os.path.join(ART, "export", "clothes", "emblems")
    S = 256
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mark = os.path.join(folder, "Emblem_%s.png" % shape)
    if not os.path.isfile(mark):
        return None
    if backing and backing != "none":
        im.alpha_composite(tinted(os.path.join(folder, "EmblemBack_%s.png" % backing), PAL["s"]).resize((S, S)))
        im.alpha_composite(tinted(os.path.join(folder, "EmblemRim_%s.png" % backing), PAL["a"]).resize((S, S)))
        m = tinted(mark, PAL["a"]).resize((int(S * 0.6), int(S * 0.6)), Image.LANCZOS)
        dy = int(-0.03 * S) if backing == "crest" else 0
        im.alpha_composite(m, ((S - m.width) // 2, (S - m.height) // 2 + dy))
    else:
        im.alpha_composite(tinted(mark, PAL["a"]).resize((S, S)))
    return im


def fx_tex(name):
    folder = os.path.join(ART, "export", "fx")
    alias = {"crackle": "electric_4x4", "smoke": "smoke_4x4", "fire": "fire_4x4"}
    n = alias.get(name, name)
    f = os.path.join(folder, n + ".png")
    if not os.path.isfile(f):
        f = os.path.join(folder, "glow.png")
    im = Image.open(f).convert("RGBA")
    if n.endswith("_4x4"):
        w = im.width // 4
        im = im.crop((0, 0, w, w))
    return im


def colour_of(role):
    return PAL.get(role, PAL["a"])


def hero_silhouette(S, colour=(70, 78, 100)):
    """The blocky hero from the front, flat, for the aura tiles."""
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = S / 7.0
    cx = S / 2
    top = S * 0.12
    d.rounded_rectangle((cx - 0.6 * u, top, cx + 0.6 * u, top + 1.25 * u), int(0.3 * u), fill=colour)
    d.rectangle((cx - 1.0 * u, top + 1.35 * u, cx + 1.0 * u, top + 3.35 * u), fill=colour)
    for s in (-1, 1):
        x0 = cx + s * 1.05 * u
        d.rectangle((min(x0, x0 + s * 0.95 * u), top + 1.35 * u, max(x0, x0 + s * 0.95 * u), top + 3.3 * u),
                    fill=colour)
        d.rectangle((min(cx, cx + s * 0.97 * u), top + 3.4 * u, max(cx, cx + s * 0.97 * u), top + 5.45 * u),
                    fill=colour)
    return im


def aura(kit, layers):
    S = 256
    rnd = random.Random(kit)
    back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for li, layer in enumerate(layers):
        tex = fx_tex(layer["tex"])
        cols = [colour_of(c) for c in layer.get("colors", ["a"])]
        big = layer["size"][0] > 1.2 or layer["size"][1] > 1.2
        n = 3 if big else 12
        for i in range(n):
            c = cols[i % len(cols)]
            size = int(S * (0.45 if big else rnd.uniform(0.08, 0.16)))
            p = tinted_img(tex, c).resize((size, size), Image.LANCZOS)
            if layer.get("low"):
                x, y = rnd.uniform(0.15, 0.85) * S, rnd.uniform(0.72, 0.92) * S
            else:
                x, y = rnd.uniform(0.15, 0.85) * S, rnd.uniform(0.12, 0.88) * S
            target = back if big or i % 2 == 0 else front
            target.alpha_composite(p, (int(x - size / 2), int(y - size / 2)))
    glow = back.filter(ImageFilter.GaussianBlur(6))
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    im.alpha_composite(glow)
    im.alpha_composite(back)
    im.alpha_composite(hero_silhouette(S))
    im.alpha_composite(front)
    return im


def tinted_img(im, rgb):
    r, g, b, a = im.split()
    col = ImageChops.multiply(Image.merge("RGB", (r, g, b)), Image.new("RGB", im.size, rgb)).convert("RGBA")
    col.putalpha(a)
    return col


def swoosh(strip, c1, c2, S=256, glow=True):
    """A trail as a thick band sweeping up an arc (thin at its tail, wide at its head), coloured c1 at the tail
    to c2 at the head, the strip's own pattern printed along it, and a bright head."""
    lum = strip.convert("L")
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(band)
    n = 90
    pts = []
    for i in range(n):
        t = i / (n - 1)
        ang = math.radians(205 - 160 * t)
        x = S * 0.5 + S * 0.4 * math.cos(ang)
        y = S * 0.66 - S * 0.36 * math.sin(ang) - S * 0.12 * t
        pts.append((t, x, y))
    for t, x, y in pts:
        r = S * (0.025 + 0.085 * t)
        # the strip's brightness along its length (its pattern: sparkles, smoke puffs, twin lines)
        u = min(strip.width - 1, int(t * (strip.width - 1)))
        k = lum.getpixel((u, strip.height // 2)) / 255.0
        k = 0.55 + 0.45 * k
        col = tuple(int((c1[j] + (c2[j] - c1[j]) * t) * k) for j in range(3))
        d.ellipse((x - r, y - r, x + r, y + r), fill=col + (int(255 * min(1.0, 0.35 + t)),))
    hx, hy = pts[-1][1], pts[-1][2]
    r = S * 0.07
    d.ellipse((hx - r, hy - r, hx + r, hy + r), fill=tuple(min(255, int(c * 0.4 + 255 * 0.6)) for c in c2) + (255,))
    if glow:
        band = Image.alpha_composite(band.filter(ImageFilter.GaussianBlur(5)), band)
    return band


def trail(kit):
    f = os.path.join(ART, "export", "fx", "trail_%s.png" % kit)
    if not os.path.isfile(f):
        return None
    return swoosh(Image.open(f).convert("RGBA"), PAL["p"], PAL["a"])


def burst(colour, rainbow=False, glow=None):
    """A comic power burst in one effect tint (the shop's Effects tab)."""
    S = 256
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts = []
    n = 12
    for i in range(n * 2):
        ang = math.pi * i / n
        r = S * (0.46 if i % 2 == 0 else 0.26)
        pts.append((S / 2 + r * math.cos(ang), S / 2 + r * math.sin(ang)))
    if rainbow:
        hues = [(255, 80, 80), (255, 170, 60), (255, 230, 80), (110, 230, 120), (90, 170, 255), (170, 110, 255)]
        for i in range(n):
            tri = [(S / 2, S / 2), pts[2 * i], pts[(2 * i + 1) % (2 * n)], pts[(2 * i + 2) % (2 * n)]]
            d.polygon(tri, fill=hues[i % len(hues)])
    else:
        d.polygon(pts, fill=tuple(colour))
    inner = []
    for i in range(n * 2):
        ang = math.pi * i / n + 0.12
        r = S * (0.27 if i % 2 == 0 else 0.16)
        inner.append((S / 2 + r * math.cos(ang), S / 2 + r * math.sin(ang)))
    core = tuple(glow) if glow else tuple(min(255, int(c * 0.55 + 255 * 0.45)) for c in colour)
    d.polygon(inner, fill=core)
    return im


def travel(style):
    kinds = {"ring": "trail_ribbon", "sparks": "trail_sparkle", "puff": "trail_smoke", "petals": "trail_twin",
             "ink": "trail_streak", "prism": "trail_neon"}
    strip = Image.open(os.path.join(ART, "export", "fx", kinds.get(style.get("burst"), "trail_streak") + ".png"))
    im = swoosh(strip.convert("RGBA"), tuple(style["c1"]), tuple(style["c2"]), glow=(style.get("glow") or 0) > 0)
    # the take-off burst's own marks round the trail's start (ring, sparks, puffs, petals, ink splats, shards)
    d = ImageDraw.Draw(im)
    S = im.width
    kind = style.get("burst")
    c1, c2 = tuple(style["c1"]), tuple(style["c2"])
    rnd = random.Random(style["id"])
    cx, cy = S * 0.2, S * 0.72
    if kind == "ring":
        d.ellipse((cx - S * 0.16, cy - S * 0.05, cx + S * 0.16, cy + S * 0.05), outline=c2, width=int(S * 0.03))
    for i in range(6 if kind != "ring" else 0):
        ang = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.06, 0.17) * S
        x, y = cx + r * math.cos(ang), cy + r * math.sin(ang) * 0.7
        c = c2 if i % 2 else c1
        if kind == "sparks":
            q = S * 0.03
            d.polygon([(x, y - 2 * q), (x + q * 0.5, y - q * 0.5), (x + 2 * q, y), (x + q * 0.5, y + q * 0.5),
                       (x, y + 2 * q), (x - q * 0.5, y + q * 0.5), (x - 2 * q, y), (x - q * 0.5, y - q * 0.5)], fill=c)
        elif kind == "puff":
            q = S * rnd.uniform(0.035, 0.06)
            d.ellipse((x - q, y - q, x + q, y + q), fill=tuple(min(255, int(v * 0.5 + 128)) for v in c))
        elif kind == "petals":
            q = S * 0.035
            d.ellipse((x - q * 1.6, y - q * 0.8, x + q * 1.6, y + q * 0.8), fill=c)
        elif kind == "ink":
            q = S * rnd.uniform(0.02, 0.05)
            d.ellipse((x - q, y - q, x + q, y + q), fill=c1)
        elif kind == "prism":
            q = S * 0.04
            hue = [(255, 90, 90), (255, 220, 80), (100, 220, 255), (190, 120, 255)][i % 4]
            d.polygon([(x, y - q * 1.6), (x + q, y), (x, y + q * 1.6), (x - q, y)], fill=hue)
    return im


# ---------------------------------------------------------------- every tile
def tiles(P):
    """[(key, image, caption, group)] in sheet order."""
    out = []
    seen = set()
    pieces = {}
    for p in P["creator"]:
        if p.get("key"):
            pieces.setdefault(p["key"], p)
    for key, p in pieces.items():
        if key in seen:
            continue
        tab, kit = p["tab"], p["kit"]
        bg = CARD.get(AREA.get(tab, "torso"), PAPER)
        im = None
        if tab in SETS:
            src = render_cell(SETS[tab], kit)
            im = framed_render(src, bg) if src is not None else None
        elif tab == "emblem":
            art = emblem(kit)
            im = card(art, bg, fit=0.8) if art else None
        elif tab == "trail":
            art = trail(kit)
            im = card(art, CARD["trail"], fit=0.9, outline=3) if art else None
        elif tab == "aura":
            layers = P["auras"].get(kit)
            im = card(aura(kit, layers), CARD["fx"], fit=0.92, outline=2) if layers else None
        if im is not None:
            seen.add(key)
            out.append((key, im, p["name"], tab))
    for w in P["weapons"]:
        src = render_cell(["weapons"], str(w["id"]))
        if src is not None:
            out.append((w["key"], card(src.crop(src.getbbox() or (0, 0, 1, 1)), CARD["weapon"], fit=0.84),
                        w["name"], "weapon"))
    have = {k for k, _, _, _ in out}
    images = {k: im for k, im, _, _ in out}
    tints = {t["i"]: t for t in P["tints"]}
    travels = {t["id"]: t for t in P["travel"]}
    packs = {p["i"]: p for p in P["packs"]}
    for item in P["shop"]:
        key, kind = "shop/" + item["key"], item.get("kind")
        im, caption = None, item["key"]
        if kind == "pack":
            pk = packs[item["pack"]]
            caption = pk["name"]
            # the pack's look: its suit (else its first piece with a picture) on a card in the pack's colour
            pick = next((q.get("key") for q in pk["pieces"] if q["tab"] == "suit" and q.get("key") in have), None)
            pick = pick or next((q.get("key") for q in pk["pieces"] if q.get("key") in have), None)
            if pick:
                src = None
                for s in SETS.get(pick.split("/")[0], []):
                    f = os.path.join(CELLS, s, pick.split("/", 1)[1].replace(":", "~") + ".png")
                    if os.path.isfile(f):
                        src = Image.open(f).convert("RGBA")
                bg = tuple(int(c * 0.45 + 255 * 0.55) for c in pk["color"])
                im = framed_render(src, bg) if src is not None else images[pick]
        elif kind == "tint":
            t = tints[item["tint"]]
            caption = t["name"]
            im = card(burst(t["color"], t.get("rainbow"), t.get("glow")), CARD["fx"], fit=0.84)
        elif kind == "travel":
            t = travels.get(item["style"])
            if t:
                caption = t["name"]
                im = card(travel(t), CARD["trail"], fit=0.9, outline=3)
        elif kind == "weapon":
            wk = "weapon/%d" % item["weapon"]
            if wk in images:
                im = images[wk]
                caption = next((w["name"] for w in P["weapons"] if w["key"] == wk), caption)
        if im is not None:
            out.append((key, im, caption, "shop"))
    return out


def spin_arrow(im):
    """A comic turn arrow round the hero's feet (the spin poses: the hero turns about as the pose plays; the tile
    shows them facing you)."""
    S = im.width
    d = ImageDraw.Draw(im)
    box = (S * 0.14, S * 0.8, S * 0.86, S * 0.95)
    w = max(3, S // 40)
    d.arc(box, 200, 340, fill=INK + (255,), width=w + 4)
    d.arc(box, 200, 340, fill=PAL["a"] + (255,), width=w)
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    rx, ry = (box[2] - box[0]) / 2, (box[3] - box[1]) / 2
    a = math.radians(340)
    x, y = cx + rx * math.cos(a), cy + ry * math.sin(a)
    q = S * 0.05
    tri = [(x + q, y + q * 0.2), (x - q * 0.7, y - q * 0.9), (x - q * 0.2, y + q * 1.0)]
    d.polygon(tri, fill=PAL["a"] + (255,), outline=INK + (255,))
    return im


def pose_tiles(P):
    """[(key, image, caption, group)]: every emote, landing pose and Photo Mode pose rendered on the plain blocky
    body from the game's own pose table (`clothed.py poses`: art/thumbs/cells/poses/<id>.png)."""
    out = []
    for p in P.get("poses", []):
        src = render_cell(["poses"], str(p["id"]))
        if src is None:
            continue
        bg = CARD[p["kind"]]
        im = framed_render(src, bg)
        root = p["joints"].get("Root")
        if root and abs(root[1]) >= 90:
            big = im.resize((CELL * SS, CELL * SS), Image.LANCZOS)
            im = spin_arrow(big).resize((CELL, CELL), Image.LANCZOS)
        out.append((p["key"], im, p["name"], p["kind"]))
    return out


def sheet_hash(im):
    return hashlib.sha256(im.tobytes()).hexdigest()[:16]


def main():
    P = load(os.path.join(ART, "thumbs", "pieces.json"))
    T = tiles(P)
    per_sheet = PER * PER
    # the pose tiles (2026-11-19) start on a sheet of their own, so adding them leaves the uploaded sheets as they were
    poses = pose_tiles(P)
    slots = list(range(len(T)))
    if poses:
        start = (len(T) + per_sheet - 1) // per_sheet * per_sheet
        slots += [start + i for i in range(len(poses))]
        T = T + poses
    os.makedirs(OUT, exist_ok=True)
    n_sheets = (slots[-1] + per_sheet) // per_sheet if slots else 0
    sheets = [Image.new("RGBA", (PER * CELL, PER * CELL), (0, 0, 0, 0)) for _ in range(n_sheets)]
    cells = {}
    for i, (key, im, _, _) in enumerate(T):
        s, k = divmod(slots[i], per_sheet)
        sheets[s].alpha_composite(im, ((k % PER) * CELL, (k // PER) * CELL))
        cells[key] = slots[i] + 1
    rec_path = os.path.join(ART, "thumbs", "sheets.json")
    rec = load(rec_path) if os.path.isfile(rec_path) else {}
    ids = []
    for s, im in enumerate(sheets):
        name = "Thumbs_%d.png" % (s + 1)
        im.save(os.path.join(OUT, name))
        h = sheet_hash(im)
        old = rec.get(name, {})
        if old.get("hash") != h:
            rec[name] = {"hash": h, "id": 0}
        ids.append(rec[name]["id"])
    for name in list(rec):
        if int(name.split("_")[1].split(".")[0]) > n_sheets:
            del rec[name]
    with open(rec_path, "w") as fh:
        json.dump(rec, fh, indent=1, sort_keys=True)
    write_config(ids, cells)
    # the local file of each uploaded sheet (tests/uishot.py --images draws picture tiles from it)
    with open(os.path.join(ART, "thumbs", "ids.json"), "w") as fh:
        json.dump({"rbxassetid://%d" % i: os.path.join("art", "export", "thumbs", "Thumbs_%d.png" % (s + 1))
                   for s, i in enumerate(ids) if i}, fh, indent=1, sort_keys=True)
    contact(T)
    print("thumbs: %d tiles on %d sheets (%d uploaded)" % (len(T), n_sheets, sum(1 for i in ids if i)))


def write_config(ids, cells):
    lines = [
        "-- GENERATED by art/thumbs/thumbs.py: do not edit by hand.",
        "-- The picture tiles (2026-11-19): the creator's pieces, the weapons and the shop's items as small comic",
        "-- cards, packed 8 x 8 into 1024 x 1024 sheets (art/export/thumbs/Thumbs_<n>.png, preview",
        "-- art/preview/thumbs.png). sheets: each sheet's uploaded image id (0 until uploaded: those tiles stay text).",
        "-- cells: each tile key (Shared.ThumbMap) to its cell, counted from 1 across the sheets, row by row.",
        "return {",
        "\ton = true,",
        "\tcell = %d," % CELL,
        "\tper = %d," % PER,
        "\tsheets = { %s }," % ", ".join(str(i) for i in ids),
        "\tcells = {",
    ]
    for key in sorted(cells, key=lambda k: cells[k]):
        lines.append('\t\t["%s"] = %d,' % (key, cells[key]))
    lines += ["\t},", "}", ""]
    path = os.path.join(ROOT, "src", "config", "Thumbs.luau")
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    import shutil
    import subprocess
    stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
    if os.path.exists(stylua):
        subprocess.run([stylua, "--config-path", os.path.join(ROOT, "stylua.toml"), path], check=False)


def contact(T):
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 11)
    except OSError:
        font = ImageFont.load_default()
    cols = 16
    lab = 16
    rows = (len(T) + cols - 1) // cols
    im = Image.new("RGB", (cols * (CELL + 4) + 4, rows * (CELL + lab + 4) + 4), (31, 42, 68))
    d = ImageDraw.Draw(im)
    for i, (key, cell, caption, _) in enumerate(T):
        x = 4 + (i % cols) * (CELL + 4)
        y = 4 + (i // cols) * (CELL + lab + 4)
        im.paste(cell, (x, y), cell)
        t = caption if d.textlength(caption, font=font) <= CELL else caption[:18] + "."
        d.text((x + (CELL - d.textlength(t, font=font)) / 2, y + CELL + 1), t, fill=(255, 247, 224), font=font)
    path = os.path.join(ART, "preview", "thumbs.png")
    im.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
