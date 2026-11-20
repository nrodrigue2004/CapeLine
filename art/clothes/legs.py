# art/clothes/legs.py: the hero creator's Legs tab (Config.Creator tabs.legs, 30 pieces) as classic Pants overlays
# (list-combat 2026-11-20, Everything Left 101: "Legs slot: still needs its own art (pants, shorts, greaves, skirts,
# hakama)"). Same method as the suits (art/clothes/suits.py, whose Tpl layers and helpers this reuses): a legs piece
# still paints the upper and lower legs in its two colour roles (Shared.PieceKits legs[kit].paint); this template is
# mostly clear, so that paint shows through, and adds what blocks cannot: ink edges, cel shading, seams, creases,
# pockets, stitching, cuffs, rips, camo, checks and bandages. One tint per template (Clothing.Color3 multiplies the
# opaque light greys): the role in LEGS below, picked from the hero's legs colours (Config.Creator.legsArt).
# parts False: the drawing replaces the kit's flat part-built bits (stripes, pockets, patches, cuffs), so LookKit
# leaves them off once the template is uploaded; True keeps the kit's real 3D parts (skirts, hakama, greaves, pads,
# glow strips, padding) and the template dresses the legs under them.
# Every design is original. Output: art/export/clothes/legs/LegsPants_<kit>.png, preview.json (for
# art/blender/clothed.py legs <page>) and art/preview/legs_templates.png (every template over its paint).
# Run: python3 art/clothes/legs.py   (PIL only)
import json
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from suits import (  # noqa: E402
    Tpl, F, B, belt, pocket, camo, clip, tone, tinted, role_rgb, SAMPLE_SETS,
    FULL, LITE, MIDT, DEEP, INK, CLEAR, HEM, HAND, ELBOW,
)
from trooper import TORSO, RIGHT, LEFT, SIDES4, W, H  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "legs")
os.makedirs(OUT, exist_ok=True)
SOFT = (20, 20, 30, 150)  # a soft ink line (seams, creases)
KNEE = ELBOW


# ---------------------------------------------------------------- shared bits for legs
def legs_of(t):
    """(x, y, w, h) of every leg face."""
    return [r for _, _, r in t.limb_faces()]


def waistband(t, fill=FULL, h=8, loops=True):
    t.torso_band(t.acc, HEM, HEM + h, fill)
    t.torso_band(t.ink, HEM + h - 1, HEM + h + 1, INK)
    if loops:
        for s in SIDES4:
            x, y, w, _ = TORSO[s]
            for k in range(1, 4 if w > 64 else 2):
                cx = x + k * w // (4 if w > 64 else 2)
                t.inked_rect([cx - 2, y + HEM, cx + 2, y + HEM + h + 3], fill, width=1)


def fly(t, a=SOFT):
    fx, fy, _, _ = F()
    t.ink.d.line([(fx + 64, fy + HEM + 9), (fx + 64, fy + 126)], fill=a, width=2)
    t.ink.d.arc([fx + 52, fy + 104, fx + 76, fy + 140], 0, 90, fill=a, width=1)


def side_seams(t, fill=SOFT, width=1):
    for x, y, w, h in t.outer() + t.inner():
        t.ink.d.line([(x + w // 2, y), (x + w // 2, y + HAND - 1)], fill=fill, width=width)


def creases(t):
    """Front creases down each leg and the knee wrinkles."""
    for x, y, w, _ in t.fronts():
        t.ink.d.line([(x + w // 2, y + 4), (x + w // 2, y + HAND - 4)], fill=(20, 20, 30, 80), width=1)
        for k in range(3):
            yy = y + KNEE - 6 + k * 5
            t.ink.d.line([(x + 12 + k * 3, yy), (x + w - 14 - k * 2, yy + 2)], fill=(20, 20, 30, 90), width=1)


def hem(t, at=HAND, fill=None, h=6):
    """A turned hem: a tone band just above `at` and an ink line."""
    t.limb_band(t.tone, at - h, at, tone(55))
    t.limb_line(t.ink, at - h, INK if fill is None else fill, 2)


def clear_below(t, row):
    """Nothing of the template under `row` on the legs (bare skin or the kit's own lower part shows)."""
    keep = Image.new("L", (W, H), 255)
    kd = ImageDraw.Draw(keep)
    for x, y, w, h in legs_of(t):
        kd.rectangle([x, y + row, x + w - 1, y + h - 1], fill=0)
    for layer in (t.tone, t.acc, t.ink):
        layer.im.putalpha(Image.composite(layer.im.getchannel("A"), Image.new("L", (W, H), 0), keep))


def stitch(t, pts, fill=FULL, dash=4, gap=3, width=2):
    """A dashed stitch line along pts (drawn in the opaque accent: takes the tint)."""
    import math
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) // (dash + gap)))
        for k in range(n):
            a, b = k / n, (k + dash / (dash + gap)) / n
            t.acc.d.line([(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a), (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)],
                         fill=fill, width=width)


def rag(rnd, x, y, w, h, n=10):
    """A ragged hole's outline inside (x, y, w, h)."""
    import math
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        r = rnd.uniform(0.7, 1.0)
        pts.append((int(x + w / 2 + math.cos(a) * w / 2 * r), int(y + h / 2 + math.sin(a) * h / 2 * r)))
    return pts


# ---------------------------------------------------------------- the 30 legs pieces
def pants():
    # tinted white: a dark leather belt with a steel buckle, front pockets, a fly, seams and creases
    p = Tpl("pants")
    belt(p, fill=(70, 50, 36, 255), buckle=(210, 214, 222, 255))
    fx, fy, _, _ = F()
    for x0 in (fx + 8, fx + 92):
        p.ink.d.arc([x0 - 4, fy + HEM + 4, x0 + 32, fy + HEM + 40], 0 if x0 > fx + 64 else 90, 180 if x0 < fx + 64 else 90, fill=SOFT, width=2)
    fly(p)
    side_seams(p)
    creases(p)
    hem(p)
    return p


def shorts():
    # tinted s (the shorts' own colour): a drawstring waist, a rolled hem above the knee, bare shins below
    p = Tpl("pants")
    waistband(p, fill=LITE, loops=False)
    fx, fy, _, _ = F()
    for dx in (-6, 6):
        p.inked_rect([fx + 62 + dx, fy + HEM + 8, fx + 64 + dx, fy + HEM + 22], (250, 250, 250, 255), width=1)
    side_seams(p)
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + KNEE - 14, x + w - 1, y + KNEE - 4], LITE, width=2)
    for x, y, w, _ in p.outer():
        pocket(p, x + 12, y + 8, w - 24, 22)
    clear_below(p, KNEE - 2)
    return p


def joggers():
    # tinted white: ribbed white cuffs at the ankles and waist, a drawstring, soft side seams, baggy knee folds
    p = Tpl("pants")
    WH = (246, 246, 248, 255)
    waistband(p, fill=WH, h=10, loops=False)
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + HAND - 16, x + w - 1, y + HAND - 1], WH, width=2)
        for k in range(x + 5, x + w - 2, 6):
            p.ink.d.line([(k, y + HAND - 14), (k, y + HAND - 3)], fill=(20, 20, 30, 70), width=1)
        for k in range(3):
            p.ink.d.arc([x + 6, y + 70 + k * 9, x + w - 6, y + 84 + k * 9], 200, 340, fill=(20, 20, 30, 80), width=1)
    fx, fy, _, _ = F()
    p.ink.d.line([(fx + 58, fy + HEM + 10), (fx + 54, fy + HEM + 24)], fill=INK, width=2)
    p.ink.d.line([(fx + 70, fy + HEM + 10), (fx + 74, fy + HEM + 24)], fill=INK, width=2)
    side_seams(p)
    return p


def track():
    # tinted a: a bold accent stripe down each outer and inner leg, piped in ink, and a ribbed waist
    p = Tpl("pants")
    for x, y, w, _ in p.outer():
        p.inked_rect([x + w // 2 - 8, y, x + w // 2 + 7, y + HAND - 1], FULL, width=2)
        p.inked_rect([x + w // 2 - 2, y, x + w // 2 + 1, y + HAND - 1], (40, 40, 44, 255), width=1)
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        p.inked_rect([x + w // 2 - 8, y + HEM, x + w // 2 + 7, y + 127], FULL, width=2)
    p.torso_band(p.tone, HEM, HEM + 10, tone(50))
    hem(p, h=8)
    return p


def cargo():
    # tinted white: big flapped thigh pockets on the outer legs, knee seams, a webbing belt, boot cuffs
    p = Tpl("pants")
    belt(p, fill=(90, 92, 80, 255), buckle=MIDT)
    for x, y, w, _ in p.outer():
        pocket(p, x + 6, y + 16, w - 12, 36)
        p.inked_rect([x + 22, y + 16, x + 41, y + 22], (40, 40, 40, 255), width=1)
    for x, y, w, _ in p.fronts():
        p.ink.d.line([(x + 4, y + KNEE - 2), (x + w - 4, y + KNEE - 2)], fill=SOFT, width=2)
        p.ink.d.line([(x + 4, y + KNEE + 12), (x + w - 4, y + KNEE + 12)], fill=SOFT, width=2)
        p.tone.d.rectangle([x + 4, y + KNEE - 2, x + w - 4, y + KNEE + 12], fill=tone(30))
    side_seams(p)
    hem(p, h=10)
    return p


def kneepads():
    # tinted white: the kit's pads stay; under them a work trouser with reinforced knees and straps behind
    p = Tpl("pants")
    belt(p, fill=(50, 50, 56, 255), buckle=MIDT)
    for x, y, w, _ in p.backs():
        for r in (KNEE + 6, KNEE + 20):
            p.inked_rect([x, y + r, x + w - 1, y + r + 5], (40, 40, 46, 255), width=1)
    side_seams(p)
    creases(p)
    hem(p)
    return p


def ripped():
    # tinted skin: ragged rips (skin through them, frayed white threads) on the thigh and shin, faded denim
    p = Tpl("pants")
    rnd = random.Random(7)
    fx, fy, _, _ = F()
    belt(p, fill=(80, 56, 40, 255), buckle=(220, 190, 90, 255), shape="round")
    holes = [(RIGHT["F"], 14, 20, 34, 18), (LEFT["F"], 18, 66, 26, 14), (LEFT["F"], 10, 22, 22, 10),
             (RIGHT["F"], 20, 74, 22, 10)]
    for (x, y, w, _), dx, dy, hw, hh in holes:
        pts = rag(rnd, x + dx, y + dy, hw, hh)
        p.inked_poly(pts, FULL, width=2)
        for k in range(4):
            yy = y + dy + 3 + k * hh // 4
            p.ink.d.line([(x + dx + 2, yy), (x + dx + hw - 2, yy + rnd.randint(-1, 1))], fill=(250, 250, 250, 200),
                         width=1)
    fly(p)
    side_seams(p)
    hem(p)
    return p


def skirt():
    # tinted white: the kit's skirt stays; under it dark tights with a sheen down the front and a seam behind
    p = Tpl("pants")
    for x, y, w, _ in p.fronts():
        p.acc.d.rectangle([x + 10, y + 4, x + 16, y + HAND - 4], fill=(90, 92, 104, 255))
    for x, y, w, _ in p.backs():
        p.ink.d.line([(x + w // 2, y), (x + w // 2, y + HAND - 1)], fill=SOFT, width=2)
    waistband(p, fill=(40, 40, 50, 255), loops=False)
    return p


def hakama():
    # tinted white: the kit's hakama stays; the pleats and ties that show between its panels
    p = Tpl("pants")
    WH = (240, 240, 244, 255)
    waistband(p, fill=WH, h=12, loops=False)
    fx, fy, _, _ = F()
    p.inked_poly([(fx + 48, fy + HEM + 12), (fx + 64, fy + HEM + 22), (fx + 80, fy + HEM + 12)], WH)
    for x, y, w, _ in legs_of(p):
        for k in range(1, 4):
            p.ink.d.line([(x + k * w // 4, y + 2), (x + k * w // 4 + (k - 2) * 3, y + HAND - 2)], fill=SOFT, width=2)
    hem(p, h=4)
    return p


def greaves():
    # tinted white: the kit's greaves stay; padded under-trousers with knee straps and a sword belt
    p = Tpl("pants")
    belt(p, fill=(90, 64, 40, 255), buckle=(220, 190, 90, 255), shape="diamond")
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + KNEE - 10, x + w - 1, y + KNEE - 4], (90, 64, 40, 255), width=1)
        for k in range(y + 14, y + KNEE - 12, 10):
            p.ink.d.line([(x + 2, k), (x + w - 2, k)], fill=(20, 20, 30, 60), width=1)
    side_seams(p)
    return p


def legwraps():
    # tinted white: the kit's wraps stay on the shins; light trousers tied at the knee with cord above them
    p = Tpl("pants")
    WH = (236, 232, 222, 255)
    waistband(p, fill=WH, loops=False)
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + KNEE - 8, x + w - 1, y + KNEE - 2], (150, 110, 70, 255), width=1)
        for k in range(3):
            p.ink.d.arc([x + 4, y + 20 + k * 9, x + w - 4, y + 32 + k * 9], 200, 340, fill=(20, 20, 30, 70), width=1)
    side_seams(p)
    return p


def armored():
    # tinted white: the kit's plates stay; a dark padded undersuit with quilting and rivets at the knee
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        for k in range(y + 6, y + HAND - 4, 9):
            p.ink.d.line([(x + 2, k), (x + w - 2, k)], fill=(255, 255, 255, 30), width=1)
    belt(p, fill=(60, 62, 70, 255), buckle=(200, 204, 214, 255))
    for x, y, w, _ in p.fronts():
        for dx in (10, w - 10):
            p.inked_ellipse([x + dx - 3, y + KNEE - 3, x + dx + 3, y + KNEE + 3], LITE, width=1)
    return p


def jeans():
    # tinted gold: gold topstitching down the seams, round the pockets and the fly, a gold rivet and button
    p = Tpl("pants")
    fx, fy, _, _ = F()
    p.torso_band(p.tone, HEM, HEM + 8, tone(40))
    p.torso_band(p.ink, HEM + 7, HEM + 9, SOFT)
    stitch(p, [(fx + 8, fy + HEM + 10), (fx + 30, fy + HEM + 30)], width=1)
    stitch(p, [(fx + 120, fy + HEM + 10), (fx + 98, fy + HEM + 30)], width=1)
    stitch(p, [(fx + 70, fy + HEM + 10), (fx + 70, fy + 120), (fx + 64, fy + 126)], width=1)
    p.inked_ellipse([fx + 60, fy + HEM + 1, fx + 68, fy + HEM + 7], FULL, width=1)
    for x, y, w, h in p.outer() + p.inner():
        stitch(p, [(x + w // 2 - 3, y + 2), (x + w // 2 - 3, y + HAND - 4)], width=1)
    bx, by, _, _ = B()
    for px in (bx + 14, bx + 80):
        p.ink.d.polygon([(px, by + HEM + 10), (px + 34, by + HEM + 10), (px + 34, by + HEM + 22),
                         (px + 17, by + 127), (px, by + HEM + 22)], outline=SOFT)
        stitch(p, [(px + 6, by + HEM + 16), (px + 17, by + HEM + 20), (px + 28, by + HEM + 16)], width=1)
    creases(p)
    hem(p)
    return p


def cuffed():
    # tinted s: deep rolled cuffs at the ankles (two folds, inked), slim legs, a fly and pockets
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + HAND - 20, x + w - 1, y + HAND - 11], LITE, width=2)
        p.inked_rect([x, y + HAND - 11, x + w - 1, y + HAND - 1], MIDT, width=2)
    fly(p)
    side_seams(p)
    creases(p)
    p.torso_band(p.tone, HEM, HEM + 8, tone(40))
    return p


def capri():
    # tinted s: the trouser stops mid-shin with a buttoned vent; bare skin below
    p = Tpl("pants")
    end = KNEE + 26
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + end - 8, x + w - 1, y + end - 1], LITE, width=2)
    for x, y, w, _ in p.outer():
        p.ink.d.line([(x + w // 2, y + end - 14), (x + w // 2, y + end - 1)], fill=INK, width=2)
        for k in (0, 6):
            p.inked_ellipse([x + w // 2 + 3, y + end - 13 + k, x + w // 2 + 7, y + end - 9 + k], FULL, width=1)
    fly(p)
    side_seams(p)
    p.torso_band(p.tone, HEM, HEM + 8, tone(40))
    clear_below(p, end + 1)
    return p


def flared():
    # tinted white: the kit's flares stay; a high waist with big buttons, a patch pocket behind, seams
    p = Tpl("pants")
    fx, fy, _, _ = F()
    p.torso_band(p.tone, HEM, HEM + 14, tone(40))
    p.torso_band(p.ink, HEM + 13, HEM + 15, INK)
    for dx in (44, 84):
        p.inked_ellipse([fx + dx - 5, fy + HEM + 2, fx + dx + 5, fy + HEM + 12], (236, 210, 120, 255), width=1)
    bx, by, _, _ = B()
    pocket(p, bx + 16, by + HEM + 16, 30, 10, flap=False)
    pocket(p, bx + 82, by + HEM + 16, 30, 10, flap=False)
    side_seams(p)
    creases(p)
    return p


def pleated():
    # tinted white: the kit's skirt stays; striped knee socks with a band on bare legs
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + 70, x + w - 1, y + HAND - 1], (248, 248, 250, 255), width=2)
        p.acc.d.rectangle([x, y + 74, x + w - 1, y + 78], fill=(40, 60, 140, 255))
        p.acc.d.rectangle([x, y + 82, x + w - 1, y + 85], fill=(200, 40, 50, 255))
    p.form = True
    return p


def leggings():
    # tinted a: the kit's glow strips stay; a sleek suit with accent panel lines and a sheen
    p = Tpl("pants")
    for x, y, w, _ in p.fronts():
        p.inked_poly([(x + 6, y + 20), (x + 14, y + 20), (x + 26, y + KNEE), (x + 14, y + 100), (x + 6, y + 100)],
                     FULL, width=1)
        p.acc.d.rectangle([x + w - 18, y + 4, x + w - 14, y + HAND - 4], fill=(120, 120, 126, 255))
    p.torso_band(p.acc, HEM, HEM + 5, FULL)
    return p


def camo_legs():
    # tinted white: a three-tone camo of tone blots, a webbing belt and pockets
    p = Tpl("pants")
    camo(p, 11, layer_alpha=(40, 70, 100), n=120)
    belt(p, fill=(90, 92, 70, 255), buckle=MIDT)
    for x, y, w, _ in p.outer():
        pocket(p, x + 8, y + 18, w - 16, 28)
    hem(p, h=8)
    return p


def ski():
    # tinted white: the kit's padding stays; quilted baffles and a bib's straps on the waist
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        for k in range(y + 8, y + HAND - 4, 12):
            p.ink.d.line([(x + 2, k), (x + w - 2, k)], fill=SOFT, width=2)
    fx, fy, _, _ = F()
    for dx in (24, 92):
        p.inked_rect([fx + dx, fy + HEM, fx + dx + 10, fy + 127], (40, 40, 46, 255), width=1)
    return p


def harem():
    # tinted gold: the kit's billows stay; a gold-trimmed sash with a knot and drape folds
    p = Tpl("pants")
    p.torso_band(p.acc, HEM, HEM + 14, FULL)
    p.torso_band(p.ink, HEM - 1, HEM + 1, INK)
    p.torso_band(p.ink, HEM + 13, HEM + 15, INK)
    fx, fy, _, _ = F()
    p.inked_ellipse([fx + 82, fy + HEM + 2, fx + 96, fy + HEM + 14], FULL)
    p.inked_poly([(fx + 86, fy + HEM + 14), (fx + 94, fy + HEM + 14), (fx + 98, fy + 126), (fx + 84, fy + 126)], FULL)
    for x, y, w, _ in legs_of(p):
        for k in range(3):
            p.ink.d.arc([x + 2, y + 10 + k * 20, x + w - 2, y + 30 + k * 20], 20, 160, fill=SOFT, width=1)
    return p


def chaps():
    # tinted white: brown leather chaps over the outer legs with a fringe and conchos, jeans between
    p = Tpl("pants")
    LEA = (110, 70, 40, 255)
    for x, y, w, _ in p.outer():
        p.inked_rect([x + 4, y, x + w - 5, y + HAND - 1], LEA)
        for k in range(y + 4, y + HAND - 4, 6):
            p.ink.d.line([(x + w - 5, k), (x + w + 0, k + 3)], fill=INK, width=1)
        for k in (20, 64):
            p.inked_ellipse([x + w // 2 - 5, y + k - 5, x + w // 2 + 5, y + k + 5], (210, 210, 220, 255), width=1)
    for x, y, w, _ in p.fronts():
        p.inked_rect([x + w - 14, y, x + w - 1, y + HAND - 1], LEA, width=1)
    belt(p, fill=LEA, buckle=(214, 190, 120, 255), shape="round")
    side_seams(p)
    return p


def shinguards():
    # tinted white: the kit's guards stay; team socks to the knee with stripes, shorts above
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + KNEE, x + w - 1, y + HAND - 1], (246, 246, 248, 255), width=2)
        for k in (KNEE + 4, KNEE + 10):
            p.acc.d.rectangle([x, y + k, x + w - 1, y + k + 3], fill=(30, 30, 36, 255))
    for x, y, w, _ in legs_of(p):
        p.ink.d.line([(x, y + KNEE - 16), (x + w - 1, y + KNEE - 16)], fill=INK, width=2)
    side_seams(p)
    return p


def checkered():
    # tinted dark: a bold check over the white legs, inked
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        sq = w // 4
        for r in range(0, HAND // sq + 1):
            for c in range(4):
                if (r + c) % 2 == 0:
                    y0 = y + r * sq
                    if y0 < y + HAND:
                        p.acc.d.rectangle([x + c * sq, y0, x + c * sq + sq - 1, min(y0 + sq - 1, y + HAND - 1)],
                                          fill=FULL)
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        p.acc.d.rectangle([x, y + HEM, x + w - 1, y + HEM + 7], fill=FULL)
    hem(p)
    return p


def bandaged():
    # tinted white: off-white bandage strips wound at angles over the thigh and shin, with taped ends
    p = Tpl("pants")
    rnd = random.Random(5)
    WH = (242, 238, 226, 255)
    for i, (x, y, w, _) in enumerate(legs_of(p)):
        for r0 in (12, 34, KNEE + 8, KNEE + 30):
            dy = rnd.randint(-4, 4)
            slope = 6 if i % 2 else -6
            pts = [(x, y + r0 + dy), (x + w - 1, y + r0 + dy + slope), (x + w - 1, y + r0 + dy + slope + 9),
                   (x, y + r0 + dy + 9)]
            p.inked_poly(pts, WH, width=1)
            p.ink.d.line([(x, y + r0 + dy + 4), (x + w - 1, y + r0 + dy + slope + 4)], fill=(20, 20, 30, 50), width=1)
    side_seams(p)
    return p


def glowlines():
    # tinted a: the kit's glow lines stay; a dark tech suit with accent circuit traces and knee nodes
    p = Tpl("pants")
    for x, y, w, _ in p.outer():
        pts = [(x + 10, y), (x + 10, y + 30), (x + 22, y + 40), (x + 22, y + 90), (x + 12, y + 100), (x + 12, y + HAND)]
        p.acc.d.line(pts, fill=FULL, width=3)
    for x, y, w, _ in p.fronts():
        p.inked_ellipse([x + w // 2 - 6, y + KNEE - 6, x + w // 2 + 6, y + KNEE + 6], FULL, width=1)
    p.torso_band(p.acc, HEM + 2, HEM + 5, FULL)
    return p


def scaled():
    # tinted white: the kit's metal bands stay; overlapping scales drawn over every leg face
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        for r, yy in enumerate(range(y, y + HAND, 9)):
            off = 5 if r % 2 else 0
            for xx in range(x - 5 + off, x + w, 10):
                p.tone.d.chord([xx, yy - 4, xx + 10, yy + 10], 0, 180, fill=tone(36 if r % 2 else 22))
                p.ink.d.arc([xx, yy - 4, xx + 10, yy + 10], 0, 180, fill=(20, 20, 30, 120), width=1)
    clip(p, p.tone, legs_of(p))
    clip(p, p.ink, legs_of(p) + [(x, y + HEM, w, 128 - HEM) for _, (x, y, w, _) in p.torso_faces()])
    return p


def sarong():
    # tinted white: the kit's sarong stays; light wrapped trousers with a knot of cord at each ankle
    p = Tpl("pants")
    for x, y, w, _ in legs_of(p):
        p.inked_rect([x, y + HAND - 10, x + w - 1, y + HAND - 4], (170, 120, 70, 255), width=1)
        for k in range(3):
            p.ink.d.line([(x + 4, y + 30 + k * 18), (x + w - 4, y + 38 + k * 18)], fill=(20, 20, 30, 70), width=1)
    side_seams(p)
    return p


def sweats():
    # tinted white: the kit's baggy thighs stay; a thick ribbed waist, white drawcords, pocket seams, cuffs
    p = Tpl("pants")
    p.torso_band(p.tone, HEM, HEM + 12, tone(45))
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        for k in range(x + 3, x + w - 2, 5):
            p.ink.d.line([(k, y + HEM + 1), (k, y + HEM + 11)], fill=(20, 20, 30, 60), width=1)
    for x, y, w, _ in p.outer():
        p.ink.d.line([(x + 14, y + 4), (x + 22, y + 34)], fill=SOFT, width=2)
    for x, y, w, _ in legs_of(p):
        p.limb_band(p.tone, HAND - 10, HAND, tone(45))
    return p


def moto():
    # tinted a: the kit's knee armour and stripe stay; padded racing leather with accent panels and vents
    p = Tpl("pants")
    for x, y, w, _ in p.fronts():
        p.inked_poly([(x + 4, y + 8), (x + w - 6, y + 8), (x + w - 12, y + 38), (x + 10, y + 38)], FULL)
        for k in range(3):
            p.ink.d.line([(x + 18 + k * 8, y + 16), (x + 18 + k * 8, y + 30)], fill=INK, width=2)
    for x, y, w, _ in p.backs():
        for k in range(y + KNEE + 4, y + KNEE + 20, 5):
            p.ink.d.line([(x + 8, k), (x + w - 8, k)], fill=SOFT, width=2)
    p.torso_band(p.acc, HEM, HEM + 6, FULL)
    side_seams(p)
    return p


# kit -> (drawing, tint role, keep the kit's parts, preview leg paint (upper, lower))
LEGS = {
    "pants": (pants, "white", False, ("s", "s")),
    "shorts": (shorts, "s", False, ("s", "skin")),
    "joggers": (joggers, "white", False, ("s", "s")),
    "track": (track, "a", False, ("s", "s")),
    "cargo": (cargo, "white", False, ("s", "s")),
    "kneepads": (kneepads, "white", True, ("s", "s")),
    "ripped": (ripped, "skin", False, ("s", "s")),
    "skirt": (skirt, "white", True, ("dark", "dark")),
    "hakama": (hakama, "white", True, ("p", "p")),
    "greaves": (greaves, "white", True, ("s", "s")),
    "legwraps": (legwraps, "white", True, ("s", "s")),
    "armored": (armored, "white", True, ("dark", "dark")),
    "jeans": (jeans, "gold", False, ("s", "s")),
    "cuffed": (cuffed, "s", False, ("s", "s")),
    "capri": (capri, "s", False, ("s", "skin")),
    "flared": (flared, "white", True, ("s", "s")),
    "pleated": (pleated, "white", True, ("skin", "skin")),
    "leggings": (leggings, "a", True, ("dark", "dark")),
    "camo": (camo_legs, "white", False, ("s", "s")),
    "ski": (ski, "white", True, ("p", "p")),
    "harem": (harem, "gold", True, ("p", "p")),
    "chaps": (chaps, "white", False, ("s", "s")),
    "shinguards": (shinguards, "white", True, ("s", "s")),
    "checkered": (checkered, "dark", False, ("white", "white")),
    "bandaged": (bandaged, "white", False, ("s", "s")),
    "glowlines": (glowlines, "a", True, ("dark", "dark")),
    "scaled": (scaled, "white", True, ("dark", "dark")),
    "sarong": (sarong, "white", True, ("s", "s")),
    "sweats": (sweats, "white", True, ("s", "s")),
    "moto": (moto, "a", True, ("dark", "dark")),
}


def body_under(paint, pal):
    """The pants' regions filled with the leg paint (upper and lower legs) and a plain torso under them."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    up, lo = (role_rgb(r, pal) for r in paint)
    for s in list(SIDES4) + ["U", "D"]:
        x, y, w, h = TORSO[s]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(*role_rgb("p", pal), 255))
    for slots in (RIGHT, LEFT):
        for s in list(SIDES4) + ["U", "D"]:
            x, y, w, h = slots[s]
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=(*up, 255))
            if s in SIDES4:
                d.rectangle([x, y + KNEE, x + w - 1, y + h - 1], fill=(*lo, 255))
    return im


if __name__ == "__main__":
    tiles, pages = [], []
    prev = os.path.join(OUT, "preview")
    os.makedirs(prev, exist_ok=True)
    for i, (kit, (fn, tint, parts, paint)) in enumerate(LEGS.items()):
        p = fn()
        im = p.image()
        im.save(os.path.join(OUT, "LegsPants_%s.png" % kit))
        pal = SAMPLE_SETS[i % len(SAMPLE_SETS)]
        tinted(im, role_rgb(tint, pal)).save(os.path.join(prev, "%s_Pants.png" % kit))
        pages.append({"name": "legs/preview/" + kit, "kit": kit, "pal": [list(c) for c in pal],
                      "paint": [role_rgb(r, pal) for r in paint], "parts": parts, "tint": tint})
        under = body_under(paint, pal)
        under.alpha_composite(tinted(im, role_rgb(tint, pal)))
        tiles.append(under)
    with open(os.path.join(OUT, "preview.json"), "w") as f:
        json.dump([pages[i:i + 8] for i in range(0, len(pages), 8)], f, indent=1)
    cols = 6
    tw, th = W // 2, H // 2
    sheet = Image.new("RGB", (tw * cols, th * ((len(tiles) + cols - 1) // cols)), (120, 120, 126))
    for i, im in enumerate(tiles):
        sheet.paste(im.convert("RGB").resize((tw - 4, th - 4)), ((i % cols) * tw + 2, (i // cols) * th + 2))
    sheet.save(os.path.join(ROOT, "preview", "legs_templates.png"))
    print("wrote", len(LEGS), "legs")
