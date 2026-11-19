# prologue.py: the Ceremony prologue's props as Blender meshes (gap-prologue, 2026-11-19). The prologue (lore step 3,
# PrologueFx) built its scene from plain parts; once ReplicatedStorage.Art.Prologue holds a look's meshes the game
# draws them over those parts and hides the parts, which stay exactly as they were (the deck, the steps and the
# rubble keep colliding the same; Shared.PrologueArtKit). Looks only: no beat, position, timing or collision moves.
# Cartoon kit style (bright comic colours, chunky bevelled shapes, low poly for phones) with one baked texture set a
# look (art/blender/vkit.py: colour, normal, roughness, metalness; opaque, so the part colour never shows through).
# Looks (each built in Roblox studs about the plain part it dresses: x, up, z, front at -z):
# * on the stage's deck (44 x 4 x 14, front toward the crowd; the deck's centre is the frame):
#   Stage (planked deck with a navy skirt, gold rim and stars, swags, footlights, the two steps with a red carpet
#   up to the podium, brass handrails), Podium (Crane's lectern: navy panels, gold crest, a microphone),
#   Spotlights (two truss towers beside the deck with spot cans aimed at the podium and soft light beams) and
#   Barriers (six crowd barriers in front of the crowd, either side of the steps; they never collide)
# * HallBanner: a gold rod frame, fringe, side pennants and a star medallion around the Hall's banner (the banner
#   cloth itself is the part, showing the printed art/prologue/ads.py HallBanner image)
# * Scanner: the scanner drone (white shell, four rotor ducts with red rings, the red lens underneath)
# * FallingSign: the donut shop sign that shakes loose over the kid (both faces alike)
# * Slab and Rubble: the subway ceiling slab as it falls (rebar, tiles underneath) and the pile it leaves
# * Billboard: the frame, catwalk, struts and lamps round the Crane Industries ad (the board itself is the part,
#   showing the printed CraneBillboard image; Silas Crane stands on the catwalk as his real rig, PrologueFx)
# Output: art/export/Prologue.fbx (textures embedded), art/export/prologue/<Look>_{Color,Normal,Roughness,
# Metalness}.png, src/config/PrologueArt.luau; with --preview, art/preview/prologue.png (every look, the staged
# ceremony stage, the billboard and the subway) and art/preview/prologue_stage.png (the stage alone, large).
# Run: python art/blender/prologue.py [--preview] [--fast]   (with the `bpy` module, Blender 5.0; python3 art/prologue/ads.py
# first for the printed images the preview shows)
import math
import os
import random
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()

import vkit  # noqa: E402
from vkit import R, P, rbox, rings_mesh, bend  # noqa: E402
from studs import rb, C, S, T, TOR, turn, shift, copy, star  # noqa: E402

FAST = "--fast" in sys.argv
vkit.OUT = os.path.join(kit.ROOT, "export", "prologue")

# ---------------------------------------------------------------- the plain parts' numbers (Config.Story.opening;
# tests/prologue_art_test.luau checks they still match)
DECK = (44.0, 4.0, 14.0)  # plaza.stage width, height, depth
STEPS = ((10.0, 2.0, 4.0), (0.0, -1.0, -9.0))  # the steps' size and centre on the deck's frame
PODIUM = (0.0, 4.0, -0.5)  # the podium's centre on the deck's frame (3 x 4 x 2)
BANNER = (44.0, 16.0, 1.0)
SIGN = (8.0, 3.0, 1.0)
SLAB = (25.0, 3.0, 10.0)  # subway width - 1, falling thickness, slab depth
RUBBLE = (25.0, 4.0, 10.0)
BOARD = (70.0, 40.0, 1.0)
GROUND = -DECK[1] / 2  # the plaza floor on the deck's frame

# ---------------------------------------------------------------- paint regions (vkit: one material each)
GOLD = R("gold", (244, 192, 58), 0.3, 0.9, "brushed")
GOLDD = R("goldd", (214, 150, 40), 0.35, 0.85)
WOODD = R("deck", (182, 118, 66), 0.72, 0.0, "planks")
SKIRT = R("skirt", (30, 38, 94), 0.85, 0.0, "drape")
NAVY = R("navy", (34, 44, 104), 0.5, 0.1)
KICK = R("kick", (30, 30, 38), 0.6, 0.2)
CARPET = R("carpet", (196, 30, 48), 0.9, 0.0, "fabric")
SWAG = R("swag", (176, 24, 44), 0.8, 0.0, "drape")
STEEL = R("steel", (60, 64, 76), 0.4, 0.75, "brushed")
BLACK = R("black", (26, 26, 32), 0.5, 0.3)
SILVER = R("silver", (196, 202, 214), 0.3, 0.85, "brushed")
WHITE = R("shell", (238, 240, 246), 0.28, 0.05)
DKGLASS = R("dglass", (16, 18, 26), 0.08, 0.3)
PANEL = R("panel", (32, 40, 96), 0.8, 0.0, ("band", 1, -1.45, -0.95, (244, 192, 58)))
SIGNF = R("signface", (255, 246, 232), 0.5, 0.0, ("candy", (255, 120, 170)))
SIGNR = R("signrim", (92, 52, 168), 0.45, 0.1)
DOUGH = R("dough", (222, 158, 88), 0.7, 0.0)
ICING = R("icing", (255, 112, 168), 0.35, 0.0, "sprinkles")
YELLOW = R("yellow", (255, 214, 60), 0.45, 0.0)
CONCRETE = R("concrete", (150, 144, 136), 0.92, 0.0, "concrete")
TILES = R("tiles", (226, 222, 210), 0.5, 0.0, "tiles")
REBAR = R("rebar", (146, 76, 46), 0.65, 0.5)
GRATE = R("grate", (78, 84, 98), 0.5, 0.7, "grate")
BFRAME = R("bframe", (38, 42, 62), 0.4, 0.6)
LAMPH = R("lamph", (52, 56, 66), 0.45, 0.7)


# ---------------------------------------------------------------- custom texture patterns (on top of vkit's)
_base_pattern = vkit._pattern


def _pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise):
    kind = pat[0] if isinstance(pat, tuple) else pat
    p = Pp[m]
    n = Nn[m]
    c = col[m]
    h = height[m]
    if kind == "drape":  # fabric pleats: soft light and shade bands across the cloth
        a = np.where(np.abs(n[:, 2]) > np.abs(n[:, 0]), p[:, 0], p[:, 2])
        w = np.sin(a * 2 * math.pi / 1.7)
        c *= (0.84 + 0.16 * (w * 0.5 + 0.5))[:, None]
        h += w * 0.35
    elif kind == "brushed":  # brushed metal: fine streaks
        a = p[:, 0] + p[:, 2]
        c *= (0.93 + 0.07 * np.sin(a * 47 + noise[m] * 9))[:, None]
    elif kind == "band":  # a coloured band where one coordinate is between lo and hi (barrier panels' gold trims)
        _, ax, lo, hi, rgb2 = pat
        v = p[:, ax]
        edge = (np.abs(v - lo) < 0.12) | (np.abs(v - hi) < 0.12)
        c[edge] = np.array(rgb2, np.float32) / 255
        star_ = (np.abs(((p[:, 0] + 0.75) % 1.5) - 0.75) < 0.22) & (np.abs(v - (lo + hi) / 2) < 0.12)
        c[star_] = np.array(rgb2, np.float32) / 255
    elif kind == "candy":  # a shop sign's diagonal candy stripes
        rgb2 = np.array(pat[1], np.float32) / 255
        s = (((p[:, 0] + p[:, 1]) / 0.55) % 2) < 1
        face = np.abs(n[:, 2]) > 0.6
        c[s & face] = rgb2
    elif kind == "concrete":  # speckle, darker blotches and a few cracks
        q = np.floor(p * 1.7)
        hsh = np.sin(q[:, 0] * 12.9898 + q[:, 1] * 78.233 + q[:, 2] * 37.719) * 43758.5453
        hsh = hsh - np.floor(hsh)
        soft = 0.5 + 0.25 * (np.sin(p[:, 0] * 1.7 + p[:, 2] * 0.9) + np.sin(p[:, 1] * 2.3 - p[:, 0] * 1.1 + p[:, 2] * 0.6))
        c *= (0.84 + 0.16 * soft)[:, None] * (0.93 + 0.07 * hsh)[:, None]
        crack = np.abs(np.sin(p[:, 0] * 0.9 + np.sin(p[:, 2] * 1.3 + p[:, 1]) * 1.6)) < 0.035
        c[crack] *= 0.45
        h[crack] -= 0.6
    elif kind == "tiles":  # the tunnel ceiling's white tiles (on the slab's underside), concrete elsewhere
        under = n[:, 1] < -0.6
        grout = (np.abs((p[:, 0] / 1.5) % 1 - 0.5) > 0.46) | (np.abs((p[:, 2] / 1.0) % 1 - 0.5) > 0.44)
        soft = 0.5 + 0.25 * (np.sin(p[:, 0] * 1.7 + p[:, 2] * 0.9) + np.sin(p[:, 1] * 2.3 - p[:, 0] * 1.1 + p[:, 2] * 0.6))
        c *= (0.95 + 0.05 * soft)[:, None]
        c[under & grout] = (0.42, 0.4, 0.38)
        h[under & grout] -= 0.5
        c[~under] = np.array((150, 144, 136), np.float32) / 255 * (0.84 + 0.16 * soft[~under])[:, None]
    elif kind == "grate":  # a catwalk's open grid
        top = np.abs(n[:, 1]) > 0.6
        hole = top & (np.abs((p[:, 0] * 2.2) % 1 - 0.5) < 0.34) & (np.abs((p[:, 2] * 2.2) % 1 - 0.5) < 0.34)
        c[hole] *= 0.28
        h[hole] -= 0.7
    else:
        return _base_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise)
    col[m] = c
    height[m] = h


vkit._pattern = _pattern


# ---------------------------------------------------------------- helpers
def bar(a, b, r, segs=8):
    """A straight tube between two Roblox points."""
    return T([a, b], r, segs=segs)


def aim(ob, origin, target):
    """Turn a mesh built along Roblox -z about the origin so it points from origin at target, then move it there."""
    kit.apply_all(ob)
    d = Vector(rb(*target)) - Vector(rb(*origin))
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    M = q.to_matrix()
    for v in ob.data.vertices:
        v.co = M @ v.co
    ob.data.update()
    return shift(ob, rb(*origin))


def jitter(ob, amt, seed, octant=True):
    """Knock a block about (broken concrete). octant: each corner of a box built about the origin moves as one, so
    its bevel stays whole (per-vertex jitter folds a small bevel inside out); else every vertex on its own."""
    rnd = random.Random(seed)
    cache = {}

    def fn(x, y, z):
        k = ((x > 0, y > 0, z > 0) if octant else (round(x, 3), round(y, 3), round(z, 3)))
        if k not in cache:
            cache[k] = (rnd.uniform(-amt, amt), rnd.uniform(-amt, amt), rnd.uniform(-amt, amt))
        dx, dy, dz = cache[k]
        return x + dx, y + dy, z + dz
    return bend(ob, fn)


def look(name, body, det=None, extra=None, res=512):
    lk = vkit.Look(name, name, False, body_rgb=(200, 200, 200), detail_rgb=(200, 200, 200))
    lk.res = res
    lk.add("Body", body)
    if det:
        lk.add("Detail", det)
    for (role, parts, rgb, mat, alpha) in extra or []:
        lk.add(role, parts, rgb, mat, alpha)
    return lk


# ================================================================ the stage on the deck (frame: the deck's centre)
W, H, D = DECK
body = [
    P(rbox(W, 0.45, D, 0, H / 2 - 0.225, 0, bev=0.06), WOODD),  # the planked top, flush with the deck's top
    P(rbox(W - 0.3, H - 0.8, D - 0.3, 0, -0.225, 0, bev=0.05), SKIRT),
    P(rbox(W - 0.1, 0.4, D - 0.1, 0, GROUND + 0.2, 0, bev=0.04), KICK),
]
(sw, sh, sd), (sx, sy, sz) = STEPS
body += [
    P(rbox(sw, sh, sd, sx, sy, sz, bev=0.06), NAVY),  # the step up from the plaza (the deck is the second)
    P(rbox(4.4, 0.06, sd, 0, sy + sh / 2 + 0.03, sz), CARPET),
    P(rbox(4.4, sh, 0.06, 0, sy, sz - sd / 2 - 0.03), CARPET),
    P(rbox(4.4, H / 2, 0.06, 0, H / 4, -D / 2 - 0.03), CARPET),
    P(rbox(4.4, 0.05, 5.4, 0, H / 2 + 0.025, -D / 2 + 2.7), CARPET),  # the runner up to the podium
]
det = []
# the gold rim round the deck's top edge and gold nosing on the step
for zz in (-D / 2 + 0.25, D / 2 - 0.25):
    det.append(P(rbox(W + 0.3, 0.28, 0.5, 0, H / 2 + 0.06, zz, bev=0.08), GOLD))
for xx in (-W / 2 + 0.25, W / 2 - 0.25):
    det.append(P(rbox(0.5, 0.28, D - 0.6, xx, H / 2 + 0.06, 0, bev=0.08), GOLD))
det.append(P(rbox(sw + 0.1, 0.14, 0.3, sx, sy + sh / 2 - 0.05, sz - sd / 2 + 0.1, bev=0.04), GOLD))
# gold stars on the skirt's front and sides, clear of the steps
for xx in (-19.0, -14.5, -10.0, 10.0, 14.5, 19.0):
    det.append(P(star(0.78, 0.33, 0.14, xx, 0.15, -D / 2 + 0.08), GOLD))
for zz in (-3.5, 3.5):
    for s_ in (-1, 1):
        st_ = star(0.78, 0.33, 0.14, 0, 0.15, 0)
        turn(st_, "up", 90)
        det.append(P(shift(st_, rb(s_ * (W / 2 - 0.08), 0, zz)), GOLD))
# red swags along the front skirt's top (both sides of the steps), each hung from gold rosettes
for x0, x1 in ((-21.6, -15.0), (-15.0, -8.4), (8.4, 15.0), (15.0, 21.6)):
    pts = []
    for i in range(9):
        t = i / 8
        pts.append((x0 + (x1 - x0) * t, 1.5 - math.sin(t * math.pi) * 0.9, -D / 2 + 0.05 - math.sin(t * math.pi) * 0.12))
    det.append(P(T(pts, [0.16, 0.24, 0.3, 0.33, 0.34, 0.33, 0.3, 0.24, 0.16], segs=8), SWAG))
    for xx in (x0, x1):
        det.append(P(C(0.3, 0.18, xx, 1.5, -D / 2 - 0.02, segs=10, axis="z"), GOLD))
# gold-capped corner posts and brass handrails up the steps
for xx in (-W / 2 + 0.05, W / 2 - 0.05):
    for zz in (-D / 2 + 0.05, D / 2 - 0.05):
        det += [P(C(0.32, H + 0.9, xx, 0.45, zz, segs=10), NAVY), P(S(0.42, xx, H / 2 + 1.05, zz, segs=10, rings=6), GOLD)]
for s_ in (-1, 1):
    x = s_ * (sw / 2 - 0.35)
    det += [
        P(bar((x, sy - sh / 2 + 0.1, sz - sd / 2 + 0.3), (x, sy + sh / 2 + 2.8, sz - sd / 2 + 0.3), 0.09), GOLD),
        P(bar((x, H / 2, -D / 2 - 0.3), (x, H / 2 + 2.8, -D / 2 - 0.3), 0.09), GOLD),
        P(bar((x, sy + sh / 2 + 2.8, sz - sd / 2 + 0.3), (x, H / 2 + 2.8, -D / 2 - 0.3), 0.11), GOLD),
    ]
lamps = []
for i in range(17):
    xx = -20 + i * 2.5
    if abs(xx) > 6:
        lamps.append(S(0.36, xx, GROUND + 0.75, -D / 2 - 0.02, sc=(1, 1, 0.45), segs=8, rings=4))
STAGE = look("Stage", body, det, [("Lamps", lamps, (255, 232, 170), "Neon", 0.0)], res=1024)

# ---------------------------------------------------------------- Crane's podium (deck frame; over the 3 x 4 x 2 box)
px, py, pz = PODIUM
bot, top = py - 2, py + 2
shell = vkit.rbox(2.9, 3.1, 1.6, px, bot + 0.35 + 1.55, pz, bev=0.12)
bend(shell, lambda x, y, z: (px + (x - px) * (0.82 + 0.18 * (y - bot) / 4), y, pz + (z - pz) * (0.85 + 0.15 * (y - bot) / 4)))
pbody = [
    P(rbox(3.0, 0.35, 2.0, px, bot + 0.175, pz, bev=0.08), BLACK),
    P(shell, NAVY),
]
desk = rbox(3.1, 0.28, 2.0, 0, 0, 0, bev=0.08)
turn(desk, "x", -14)
pbody.append(P(shift(desk, rb(px, top - 0.35, pz + 0.05)), R("desk", (96, 56, 34), 0.6, 0.0, "planks")))
pdet = [
    P(rbox(2.95, 0.16, 1.65, px, bot + 0.45, pz, bev=0.05), GOLD),
    P(rbox(2.95, 0.16, 1.65, px, top - 0.62, pz, bev=0.05), GOLD),
    P(TOR(0.66, 0.11, px, py + 0.1, pz - 0.82, axis="z", segs=20, csegs=6), GOLD),
    P(star(0.48, 0.2, 0.16, px, py + 0.1, pz - 0.84), GOLD),
]
# the microphone on a gooseneck, leaning toward where Crane stands (behind, +z)
neck = [(px + 0.7, top - 0.2, pz + 0.3), (px + 0.68, top + 0.2, pz + 0.45), (px + 0.55, top + 0.55, pz + 0.75),
        (px + 0.4, top + 0.72, pz + 1.0)]
pdet += [P(T(neck, 0.05, segs=6), BLACK), P(S(0.17, px + 0.36, top + 0.76, pz + 1.08, sc=(1, 1.3, 1), segs=10, rings=6), SILVER),
         P(C(0.14, 0.12, px + 0.7, top - 0.24, pz + 0.3, segs=8), BLACK)]
PODIUM_LK = look("Podium", pbody, pdet)

# ---------------------------------------------------------------- spotlight towers (deck frame)
TARGET = (PODIUM[0], PODIUM[1] + 2.5, PODIUM[2] + 1.6)  # Crane's face behind the podium
TOWER_X, TOWER_Z, TOWER_H = W / 2 + 3.2, 4.5, 21.0
sbody, slens, sbeam = [], [], []
for s_ in (-1, 1):
    cx = s_ * TOWER_X
    a = 0.6
    y0, y1 = GROUND, GROUND + TOWER_H
    sbody.append(P(rbox(2.6, 0.3, 2.6, cx, y0 + 0.15, TOWER_Z, bev=0.05), STEEL))
    for dx in (-a, a):
        for dz in (-a, a):
            sbody.append(P(bar((cx + dx, y0 + 0.3, TOWER_Z + dz), (cx + dx, y1, TOWER_Z + dz), 0.1, segs=6), BLACK))
    step = 1.6
    n = int((y1 - y0 - 0.5) / step)
    for i in range(n):
        ya, yb = y0 + 0.4 + i * step, y0 + 0.4 + (i + 1) * step
        for (ax_, az_, bx_, bz_) in ((-a, -a, a, -a), (a, -a, a, a), (a, a, -a, a), (-a, a, -a, -a)):
            if i % 2:
                ax_, az_, bx_, bz_ = bx_, bz_, ax_, az_
            sbody.append(P(bar((cx + ax_, ya, TOWER_Z + az_), (cx + bx_, yb, TOWER_Z + bz_), 0.05, segs=4), BLACK))
    sbody.append(P(rbox(1.6, 0.25, 1.6, cx, y1, TOWER_Z, bev=0.04), STEEL))
    # two spot cans: the top one at Crane's face, the lower one across the stage's front
    for (cy_, tgt) in ((y1 + 0.9, TARGET), (y1 - 5.5, (s_ * -6.0, H / 2 + 2.0, -3.0))):
        o = (cx - s_ * 0.2, cy_, TOWER_Z - 0.3)
        can = [C(0.62, 1.7, 0, 0, 0, segs=14, axis="z"), C(0.7, 0.22, 0, 0, -0.85, segs=14, axis="z"),
               rbox(0.5, 0.8, 0.5, 0, 0, 0.95, bev=0.05)]
        for p_ in can:
            aim(p_, o, tgt)
        sbody += [P(can[0], BLACK), P(can[1], SILVER), P(can[2], BLACK)]
        sbody.append(P(bar((cx, cy_ - 0.9, TOWER_Z), o, 0.12, segs=6), STEEL))
        lens = C(0.55, 0.08, 0, 0, -0.98, segs=14, axis="z")
        slens.append(aim(lens, o, tgt))
        dist_ = (Vector(tgt) - Vector(o)).length
        # r at -z: the wide end toward the stage; it fades out short of the lit face so no glow sits on it
        beam = C(2.0, dist_ * 0.6, 0, 0, 0, segs=18, r2=0.5, axis="z")
        shift(beam, rb(0, 0, -1.0 - dist_ * 0.3))
        sbeam.append(aim(beam, o, tgt))
SPOTS = look("Spotlights", sbody, None, [("Lens", slens, (255, 246, 220), "Neon", 0.0),
                                         ("Beam", sbeam, (255, 236, 180), "Neon", 0.86)])

# ---------------------------------------------------------------- crowd barriers (deck frame; never collide)
BZ = -D / 2 - 5.0
bbody = []
for s_ in (-1, 1):
    for k in range(3):
        cx = s_ * (8.6 + k * 6.6)
        w2 = 3.05
        g = GROUND
        bbody += [P(bar((cx - w2, g + 0.25, BZ), (cx - w2, g + 3.3, BZ), 0.09), SILVER),
                  P(bar((cx + w2, g + 0.25, BZ), (cx + w2, g + 3.3, BZ), 0.09), SILVER),
                  P(bar((cx - w2, g + 3.3, BZ), (cx + w2, g + 3.3, BZ), 0.09), SILVER),
                  P(bar((cx - w2, g + 0.55, BZ), (cx + w2, g + 0.55, BZ), 0.07), SILVER)]
        for i in range(1, 9):
            x = cx - w2 + i * (2 * w2) / 9
            if i not in (4, 5):
                bbody.append(P(bar((x, g + 0.55, BZ), (x, g + 3.3, BZ), 0.035, segs=5), SILVER))
        bbody.append(P(rbox(2 * w2 * 0.38, 1.0, 0.08, cx, g + 2.2, BZ - 0.06, bev=0.02),
                       R("bpanel", (32, 40, 96), 0.8, 0.0, ("band", 1, g + 1.78, g + 2.62, (244, 192, 58)))))
        for x in (cx - w2 + 0.1, cx + w2 - 0.1):
            bbody.append(P(rbox(0.35, 0.16, 2.3, x, g + 0.08, BZ, bev=0.04), STEEL))
BARRIERS = look("Barriers", bbody)

# ---------------------------------------------------------------- the Hall's banner frame (frame: the banner part)
BW, BH, BD = BANNER
nbody, ndet = [], []
ndet += [P(C(0.42, BW + 3.2, 0, BH / 2 + 0.45, -0.15, segs=14, axis="x"), GOLD),
         P(C(0.3, BW + 1.0, 0, -BH / 2 - 0.3, -0.15, segs=12, axis="x"), GOLDD)]
for s_ in (-1, 1):
    ndet += [P(S(0.72, s_ * (BW / 2 + 1.9), BH / 2 + 0.45, -0.15, segs=12, rings=8), GOLD),
             P(C(0.32, 1.1, s_ * (BW / 2 + 3.0), BH / 2 + 0.45, -0.15, segs=10, r2=0.0, axis="x"), GOLD)]
    # the side pennants: navy, a swallow tail, a gold star, hung from the rod
    x = s_ * (BW / 2 + 1.35)
    pen = rings_mesh([[(x - 1.25, BH / 2 + 0.1, z), (x + 1.25, BH / 2 + 0.1, z), (x + 1.25, -BH / 2 + 1.2, z),
                       (x, -BH / 2 + 2.6, z), (x - 1.25, -BH / 2 + 1.2, z)] for z in (-0.28, -0.08)])
    nbody.append(P(pen, SKIRT))
    ndet.append(P(star(0.85, 0.36, 0.1, x, BH / 2 - 4.0, -0.33), GOLD))
    ndet.append(P(rbox(2.5, 0.25, 0.24, x, BH / 2 - 1.0, -0.18), GOLD))
for x in (-BW / 2 + 4, 0.0, BW / 2 - 4):  # wall brackets behind the rod (the Hall's face is 0.8 behind the centre)
    ndet.append(P(rbox(0.35, 0.35, 0.95, x, BH / 2 + 0.45, 0.32, bev=0.04), GOLDD))
for i in range(29):  # the gold fringe along the bottom
    x = -BW / 2 + 0.75 + i * (BW - 1.5) / 28
    ndet.append(P(C(0.2, 0.75, x, -BH / 2 - 0.85, -0.15, segs=6, r2=0.04), GOLDD))
# the star medallion over the middle
ndet += [P(TOR(2.0, 0.2, 0, BH / 2 + 2.6, -0.2, axis="z", segs=24, csegs=6), GOLD),
         P(star(1.7, 0.75, 0.3, 0, BH / 2 + 2.6, -0.25), GOLD),
         P(C(1.85, 0.2, 0, BH / 2 + 2.6, 0.0, segs=24, axis="z"), NAVY)]
BANNER_LK = look("HallBanner", nbody, ndet)

# ---------------------------------------------------------------- the scanner drone (frame: the old 4-stud ball)
cbody = [P(S(1.85, 0, 0, 0, sc=(1.15, 0.72, 1.15), segs=20, rings=12), WHITE),
         P(TOR(2.12, 0.2, 0, -0.05, 0, segs=24, csegs=6), STEEL),
         P(S(0.95, 0, 1.12, 0, sc=(1, 0.5, 1), segs=14, rings=7), STEEL),
         P(bar((0, 1.4, 0), (0, 2.3, 0), 0.06, segs=6), BLACK),
         P(S(0.98, 0, -1.0, 0, sc=(1, 0.75, 1), segs=16, rings=8), DKGLASS)]
cglow, clens = [], []
for k in range(4):
    a = math.radians(45 + k * 90)
    dx, dz = math.cos(a), math.sin(a)
    r0, r1 = 1.9, 3.0
    arm = rbox(r1 - r0 + 0.4, 0.26, 0.42, 0, 0, 0, bev=0.06)
    turn(arm, "up", -math.degrees(a))
    cbody.append(P(shift(arm, rb(dx * (r0 + r1) / 2, 0.1, dz * (r0 + r1) / 2)), STEEL))
    cx, cz = dx * r1, dz * r1
    duct = TOR(0.92, 0.2, cx, 0.15, cz, segs=20, csegs=6)
    cbody.append(P(duct, WHITE))
    for ang in (0, 90):
        blade = rbox(1.5, 0.05, 0.24, 0, 0, 0, bev=0)
        turn(blade, "up", ang + 20 * k)
        cbody.append(P(shift(blade, rb(cx, 0.2, cz)), BLACK))
    cbody.append(P(C(0.13, 0.3, cx, 0.2, cz, segs=8), STEEL))
    cglow.append(TOR(0.92, 0.07, cx, -0.2, cz, segs=20, csegs=4))
clens += [S(0.55, 0, -1.42, 0, sc=(1, 0.6, 1), segs=14, rings=7), S(0.14, 0, 2.38, 0, segs=8, rings=5)]
SCANNER = look("Scanner", cbody, None, [("Lens", clens, (255, 40, 40), "Neon", 0.0),
                                        ("Glow", cglow, (255, 60, 60), "Neon", 0.0)])

# ---------------------------------------------------------------- the falling sign (frame: the old 8 x 3 x 1 box)
gw, gh, gd = SIGN
gbody = [P(rbox(gw - 0.5, gh - 0.5, 0.5, 0, 0, 0, bev=0.1), SIGNF)]
for (w_, h_, x_, y_) in ((gw, 0.38, 0, gh / 2 - 0.19), (gw, 0.38, 0, -gh / 2 + 0.19), (0.38, gh, -gw / 2 + 0.19, 0),
                         (0.38, gh, gw / 2 - 0.19, 0)):
    gbody.append(P(rbox(w_, h_, 0.72, x_, y_, 0, bev=0.1), SIGNR))
gdet = []
for s_ in (-1, 1):  # a donut and three stars on each face (the sign is seen from any side)
    z = s_ * 0.38
    dn = TOR(0.78, 0.36, -2.05, 0, z, axis="z", segs=20, csegs=10)
    gdet.append(P(dn, DOUGH))
    ic = TOR(0.78, 0.3, -2.05, 0, z + s_ * 0.14, axis="z", segs=20, csegs=10)
    gdet.append(P(ic, ICING))
    for i, xx in enumerate((0.25, 1.55, 2.85)):
        gdet.append(P(star(0.5 - 0.06 * (i % 2), 0.22, 0.12, xx, 0.1 + 0.25 * (i % 2), z + s_ * 0.05), YELLOW))
# the brackets it hung from: one chain still on, one snapped short
for (x, links) in ((-2.8, 4), (2.8, 1)):
    for i in range(links):
        lk_ = TOR(0.18, 0.05, x, gh / 2 + 0.3 + i * 0.3, 0, axis="z" if i % 2 == 0 else "x", segs=10, csegs=4)
        gdet.append(P(lk_, STEEL))
SIGN_LK = look("FallingSign", gbody, gdet)

# ---------------------------------------------------------------- the subway slab, falling (frame: its 25 x 3 x 10 box)
lw, lh, ld = SLAB
slab = rbox(lw - 0.6, lh - 0.4, ld - 0.6, 0, 0, 0, bev=0.15)
slab_parts = [P(jitter(slab, 0.22, 3), TILES)]
lrebar = []
rnd = random.Random(7)
for i in range(14):
    side = i % 4
    if side < 2:
        x = (lw / 2 - 0.4) * (1 if side == 0 else -1)
        z = rnd.uniform(-ld / 2 + 1, ld / 2 - 1)
        e = (x + (0.9 if side == 0 else -0.9), rnd.uniform(-0.6, 0.6), z + rnd.uniform(-0.3, 0.3))
    else:
        z = (ld / 2 - 0.4) * (1 if side == 2 else -1)
        x = rnd.uniform(-lw / 2 + 1, lw / 2 - 1)
        e = (x + rnd.uniform(-0.3, 0.3), rnd.uniform(-0.6, 0.6), z + (0.9 if side == 2 else -0.9))
    lrebar.append(P(bar((x * 0.97, 0, z * 0.97), e, 0.08, segs=5), REBAR))
SLAB_LK = look("Slab", slab_parts, lrebar)

# ---------------------------------------------------------------- the rubble it leaves (frame: its 25 x 4 x 10 box)
rw, rh, rd = RUBBLE
g = -rh / 2
rbody = []
mound = S(1.0, 0, 0, 0, sc=(rw / 2 - 0.4, 3.0, rd / 2 - 0.4), segs=18, rings=10)
kit.cut(mound, (0, 0, 1), keep_positive=True)  # only the half above the tunnel floor
jitter(mound, 0.07, 11, octant=False)
rbody.append(P(shift(mound, rb(0, g, 0)), CONCRETE))
rnd = random.Random(21)
for i in range(13):
    sx_, sy_, sz_ = rnd.uniform(2.2, 4.6), rnd.uniform(1.2, 2.4), rnd.uniform(2.0, 3.8)
    x = rnd.uniform(-rw / 2 + 2.5, rw / 2 - 2.5)
    z = rnd.uniform(-rd / 2 + 2.0, rd / 2 - 2.0)
    hump = 3.2 * max(0.0, 1 - (x / (rw / 2)) ** 2 - (z / (rd / 2)) ** 2) ** 0.5
    y = g + hump * 0.8 + sy_ * 0.2
    ch = rbox(sx_, sy_, sz_, 0, 0, 0, bev=0.12)
    turn(ch, "x", rnd.uniform(-25, 25))
    turn(ch, "z", rnd.uniform(-25, 25))
    turn(ch, "up", rnd.uniform(0, 180))
    jitter(ch, 0.2, 100 + i)
    rbody.append(P(shift(ch, rb(x, y, z)), TILES if i % 4 == 0 else CONCRETE))
for (x, ang, yaw) in ((-6.5, 17, 8), (6.0, -14, -12)):  # two broken slab pieces leaning on the heap
    pc = rbox(8.5, 1.1, 5.2, 0, 0, 0, bev=0.12)
    jitter(pc, 0.2, int(x * 10) + 400)
    turn(pc, "z", ang)
    turn(pc, "up", yaw)
    rbody.append(P(shift(pc, rb(x, g + 1.55, 0.6 if x < 0 else -0.8)), TILES))
rdet = []
for i in range(9):
    x = rnd.uniform(-rw / 2 + 2, rw / 2 - 2)
    z = rnd.uniform(-rd / 2 + 1.5, rd / 2 - 1.5)
    hump = 2.4 * max(0.0, 1 - (x / (rw / 2)) ** 2 - (z / (rd / 2)) ** 2) ** 0.5
    y = g + hump * 0.8
    pts = [(x, y, z), (x + rnd.uniform(-0.6, 0.6), y + 1.0, z + rnd.uniform(-0.4, 0.4)),
           (x + rnd.uniform(-1.2, 1.2), y + 1.5, z + rnd.uniform(-0.8, 0.8))]
    rdet.append(P(T(pts, 0.08, segs=5), REBAR))
RUBBLE_LK = look("Rubble", rbody, rdet, res=1024)

# ---------------------------------------------------------------- the billboard frame (frame: the board, wall 1.5 behind)
ow, oh, od = BOARD
kbody, kdet, klens = [], [], []
fz = 0.05
kbody += [P(rbox(ow + 2.8, 1.4, 1.6, 0, oh / 2 + 0.7, fz, bev=0.18), BFRAME),
          P(rbox(ow + 2.8, 1.4, 1.6, 0, -oh / 2 - 0.7, fz, bev=0.18), BFRAME),
          P(rbox(1.4, oh, 1.6, -ow / 2 - 0.7, 0, fz, bev=0.18), BFRAME),
          P(rbox(1.4, oh, 1.6, ow / 2 + 0.7, 0, fz, bev=0.18), BFRAME)]
for (w_, h_, x_, y_) in ((ow + 0.6, 0.3, 0, oh / 2 + 0.15), (ow + 0.6, 0.3, 0, -oh / 2 - 0.15),
                         (0.3, oh, -ow / 2 - 0.15, 0), (0.3, oh, ow / 2 + 0.15, 0)):
    kdet.append(P(rbox(w_, h_, 0.3, x_, y_, -0.72, bev=0.05), GOLD))
for x in (-ow / 2 - 0.7, ow / 2 + 0.7):  # bolts on the corners
    for y in (-oh / 2 - 0.7, oh / 2 + 0.7):
        kdet.append(P(C(0.32, 0.25, x, y, -0.8, segs=10, axis="z"), GOLD))
CW_Y, CW_D = -oh / 2 - 1.55, 5.6  # the catwalk under the board (Crane stands on it)
kbody.append(P(rbox(ow + 2.0, 0.26, CW_D, 0, CW_Y, -0.25 - CW_D / 2, bev=0.04), GRATE))
for i in range(13):
    x = -ow / 2 - 0.5 + i * (ow + 1.0) / 12
    kbody.append(P(bar((x, CW_Y, -CW_D - 0.1), (x, CW_Y + 3.0, -CW_D - 0.1), 0.08, segs=6), STEEL))
    if i % 2 == 0:  # struts down to the wall
        kbody.append(P(bar((x, CW_Y - 0.1, -CW_D + 0.3), (x, CW_Y - 5.0, 1.3), 0.14, segs=6), STEEL))
kbody += [P(bar((-ow / 2 - 0.5, CW_Y + 3.0, -CW_D - 0.1), (ow / 2 + 0.5, CW_Y + 3.0, -CW_D - 0.1), 0.1, segs=8), STEEL),
          P(bar((-ow / 2 - 0.5, CW_Y + 1.5, -CW_D - 0.1), (ow / 2 + 0.5, CW_Y + 1.5, -CW_D - 0.1), 0.06, segs=6), STEEL),
          P(rbox(ow + 2.0, 0.4, 0.08, 0, CW_Y + 0.33, -CW_D - 0.1), GOLD)]
for x in (-28.0, -14.0, 0.0, 14.0, 28.0):  # lamp arms over the top, the heads tilted down at the ad
    arm = [(x, oh / 2 + 1.2, 0.4), (x, oh / 2 + 3.3, 0.0), (x, oh / 2 + 3.9, -2.4), (x, oh / 2 + 3.6, -5.0)]
    kbody.append(P(T(arm, 0.14, segs=6), STEEL))
    head = rbox(2.4, 0.75, 1.3, 0, 0, 0, bev=0.12)
    turn(head, "x", 28)
    kbody.append(P(shift(head, rb(x, oh / 2 + 3.25, -5.4)), LAMPH))
    ln = rbox(2.0, 0.08, 0.9, 0, 0, 0, bev=0)
    turn(ln, "x", 28)
    klens.append(shift(ln, rb(x, oh / 2 + 2.85, -5.55)))
BOARD_LK = look("Billboard", kbody, kdet, [("Lamps", klens, (255, 240, 200), "Neon", 0.0)], res=1024)

LOOKS = vkit.LOOKS


# ================================================================ bake, the fit table and the export
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


MAPS = {}
for name, lk in LOOKS.items():
    print("baking", name, flush=True)
    vkit.RES = 512 if FAST else lk.res
    MAPS[name] = vkit.bake_look(lk, ao_samples=8 if FAST else 24)

TRIS = {}
total = 0
rows = []
for name in sorted(LOOKS):
    lk = LOOKS[name]
    rows.append("\t%s = {" % name)
    for mname in sorted(lk.meshes):
        ob = lk.meshes[mname]
        lo, hi = bounds(ob)
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        t = kit.tris(ob)
        TRIS[mname] = t
        total += t
        textured = ob in lk.textured()
        if textured:
            rgb, mat, alpha = (200, 200, 200), "SmoothPlastic", 0.0
        else:
            rgb, mat, alpha = lk.extra[mname]
        extra = (", alpha = %g" % alpha) if alpha else ""
        extra += ", maps = true" if textured else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (mname, max(size[0], 0.05), max(size[2], 0.05), max(size[1], 0.05), c[0], c[2], -c[1], rgb[0], rgb[1],
                       rgb[2], mat, extra, t))
    rows.append("\t},")
print("prologue: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for name in sorted(LOOKS):
    lk = LOOKS[name]
    print("  %-12s %5d tris  (%s)" % (name, sum(TRIS[n] for n in lk.meshes), ", ".join(
        "%s %d" % (n[len(lk.prefix):], TRIS[n]) for n in sorted(lk.meshes))))

text = "\n".join([
    "-- GENERATED by art/blender/prologue.py: do not edit by hand.",
    "-- The Ceremony prologue's props in Blender meshes (ReplicatedStorage.Art.Prologue; Shared.PrologueArtKit, PrologueFx):",
    "-- look -> mesh -> its size and its centre from the centre of the plain part the look dresses, in that part's studs",
    "-- (x, up, z; front at -z), its colour, material, transparency, maps (a baked texture set in its SurfaceAppearance)",
    "-- and triangles. %d meshes in %d looks, %d triangles." % (len(TRIS), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "PrologueArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)

export = []
for name, lk in LOOKS.items():
    pm = vkit.export_material(lk, MAPS[name])
    for mname, ob in lk.meshes.items():
        cp = copy(ob)
        cp.name = mname + "_x"
        kit.centre(cp)
        cp.name = mname
        cp.data.name = mname
        cp.data.materials.clear()
        if ob in lk.textured():
            cp.data.materials.append(pm)
        else:
            rgb, mat, alpha = lk.extra[mname]
            cp.data.materials.append(kit.material(mname + "Mat", rgb))
        export.append(cp)
bpy.ops.object.select_all(action="DESELECT")
for o in export:
    o.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(kit.ROOT, "export", "Prologue.fbx"), use_selection=True,
    apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
    use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
    path_mode="COPY", embed_textures=True)
for cp in export:
    bpy.data.objects.remove(cp, do_unlink=True)

# ================================================================ previews
if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402

    PREV = os.path.join(kit.ROOT, "preview")
    vp._scene(FAST, (640, 400) if FAST else (1100, 660))
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    mats = {name: vp._mat_textured(name, MAPS[name]) for name in LOOKS}

    def flat(rgb, kind="SmoothPlastic", alpha=0.0):
        return vp._mat_flat(tuple(rgb), kind, alpha)

    def blk(sx, sy, sz, x, y, z, rgb, kind="SmoothPlastic", alpha=0.0):
        o = vp._keep(kit.box("blk", sx, sz, sy, at=rb(x, y, z)))
        o.data.materials.append(flat(rgb, kind, alpha))
        return o

    def picture(path, w, h, x, y, z, yaw=0.0):
        """A printed image on a plane facing -z (the board's and banner's art)."""
        bpy.ops.mesh.primitive_plane_add(size=1)
        o = bpy.context.active_object
        o.scale = (-w, h, 1)  # seen from the front (Roblox -z), not mirrored
        o.rotation_euler = (math.radians(90), 0, math.radians(yaw))
        o.location = rb(x, y, z)
        m = bpy.data.materials.new("pic")
        m.use_nodes = True
        nt = m.node_tree
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(path)
        p = nt.nodes["Principled BSDF"]
        nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.6
        o.data.materials.append(m)
        return vp._keep(o)

    def person(x, z, shirt, pants=(40, 44, 70), scale=1.0, yaw=0.0, y=0.0, arms_up=False):
        """A blocky figure for scale (the game's people are real rigs with catalog faces and hair)."""
        a = math.radians(yaw)
        parts = [((2, 2, 1), (0, 3.0, 0), shirt), ((1.2, 1.2, 1.2), (0, 4.6, 0), (240, 196, 150)),
                 ((0.95, 2, 1), (-0.5, 1.0, 0), pants), ((0.95, 2, 1), (0.5, 1.0, 0), pants)]
        if arms_up:
            parts += [((1, 2, 1), (-1.5, 4.6, 0), shirt), ((1, 2, 1), (1.5, 4.6, 0), shirt)]
        else:
            parts += [((1, 2, 1), (-1.5, 3.0, 0), shirt), ((1, 2, 1), (1.5, 3.0, 0), shirt)]
        for (s_, c, rgb) in parts:
            cx = c[0] * math.cos(a) + c[2] * math.sin(a)
            cz = -c[0] * math.sin(a) + c[2] * math.cos(a)
            o = vp._keep(kit.box("p", s_[0] * scale, s_[2] * scale, s_[1] * scale))
            o.rotation_euler = (0, 0, a)  # about the block's own centre
            o.location = rb(x + cx * scale, y + c[1] * scale, z + cz * scale)
            o.data.materials.append(flat(rgb))

    def place(name, at=(0, 0, 0), ry=0.0):
        vp._place(LOOKS[name], mats, at=at, ry=ry)

    ADS = os.path.join(kit.ROOT, "export", "prologue")
    shots = []

    def stage_scene():
        """The ceremony as the game sets it: deck centre at (0, 2, 0) (the plaza at 0), the Hall's face 11 behind."""
        vp._ground(500, (150, 150, 146))
        hall_z = D / 2 + 4.0
        blk(120, 70, 4, 0, 35, hall_z + 2, (196, 202, 214), "Concrete")
        for i in range(-5, 6):  # the Hall's windows
            for j in range(1, 6):
                blk(5.5, 6, 0.3, i * 10.5, 9 + j * 11, hall_z - 0.1, (112, 160, 210), "Glass")
        bc = (0, 20, hall_z - 0.8)
        blk(BW, BH, 1, bc[0], bc[1], bc[2], (30, 34, 60))
        picture(os.path.join(ADS, "HallBanner.png"), BW, BH, bc[0], bc[1], bc[2] - 0.52)
        place("HallBanner", bc)
        for n in ("Stage", "Podium", "Spotlights", "Barriers"):
            place(n, (0, H / 2, 0))
        person(0, 2.0, (34, 36, 44), (34, 36, 44), y=H, yaw=180)  # Crane behind the podium
        for (x, rgb) in ((-15, (250, 210, 70)), (5, (120, 130, 150)), (16, (110, 210, 255))):
            person(x, 5.0, rgb, rgb, y=H, yaw=180, arms_up=(x == 5))
        rnd_ = random.Random(5)
        cols = [(235, 90, 80), (80, 150, 235), (250, 200, 70), (120, 200, 120), (200, 120, 220), (255, 150, 60)]
        for row in range(4):
            for i in range(8):
                x = (i - 3.5) * 6.9 + (row % 2) * 2.5
                person(x, -D / 2 - 8 - row * 8.7, cols[(i + row) % len(cols)], yaw=rnd_.uniform(-12, 12),
                       arms_up=rnd_.random() < 0.5)
        place("Scanner", (0, H + 18, 0))

    stage_scene()
    vp._camera((26, 16, -50), (0, 7, 0), lens=28)
    out = os.path.join(PREV, "prologue_stage.png")
    kit.render(out)
    shots.append(out)
    vp._camera((-10, 7, -27), (2, 6, 0), lens=24)
    out = os.path.join(PREV, "prologue_stage_crowd.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    # every small look side by side
    vp._ground(300, (120, 124, 132))
    place("Scanner", (-15, 4, 0))
    place("FallingSign", (-4, 3, 0))
    place("Podium", (6, -2, 0.5))
    place("Slab", (0, 3, 18))
    place("Rubble", (0, 2, 32), ry=0)
    person(9.5, -1, (60, 90, 200))
    vp._camera((10, 14, -26), (-1, 3, 12), lens=30)
    out = os.path.join(PREV, "prologue_gallery.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    # the billboard on a tall building's face, with Silas Crane standing on the catwalk (blocky stand-in at 5x)
    vp._ground(600, (110, 112, 118))
    blk(110, 160, 40, 0, 80, 21.5, (176, 168, 156), "Concrete")
    bcy = 70
    blk(ow, oh, 1, 0, bcy, 0, (240, 240, 240))
    picture(os.path.join(ADS, "CraneBillboard.png"), ow, oh, 0, bcy, -0.52)
    place("Billboard", (0, bcy, 0))
    # (PrologueArtKit.CRANE: the picture's left is the board's +x seen from the front; turned 25 toward the words)
    person(22, -0.25 - CW_D / 2, (34, 36, 44), (34, 36, 44), scale=5.0, y=bcy + CW_Y + 0.13, yaw=25)
    vp._camera((30, 50, -120), (0, bcy - 2, 0), lens=34)
    out = os.path.join(PREV, "prologue_billboard.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    # the subway lane: a slab coming down, the rubble behind the hero
    vp._ground(200, (70, 70, 76))
    tw, th = 26.0, 24.0
    blk(1, th, 120, -tw / 2 - 0.5, th / 2, 0, (88, 92, 104), "Concrete")
    blk(1, th, 120, tw / 2 + 0.5, th / 2, 0, (96, 100, 112), "Concrete")
    blk(tw, 0.6, 120, 0, -0.3, 0, (60, 60, 66), "Concrete")
    place("Rubble", (0, RUBBLE[1] / 2, 10))
    place("Rubble", (0, RUBBLE[1] / 2, 40))
    place("Slab", (0, 13.0, -14), ry=0)
    person(3, -6, (60, 90, 200), yaw=160)
    for zz in (-30, 0, 30):  # the tunnel's work lamps
        L = bpy.data.lights.new("lamp", "POINT")
        L.energy = 9000
        lo_ = bpy.data.objects.new("lamp", L)
        lo_.location = rb(0, 20, zz)
        bpy.context.scene.collection.objects.link(lo_)
        vp._keep(lo_)
    vp._camera((9, 7, -42), (0, 5, 0), lens=26)
    out = os.path.join(PREV, "prologue_subway.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    # one sheet, 2 across (python3 with PIL)
    code = (
        "import sys\nfrom PIL import Image\n"
        "ims=[Image.open(p).convert('RGB') for p in sys.argv[2:]]\n"
        "w,h=ims[0].size; cols=2; rows=(len(ims)+1)//2\n"
        "sheet=Image.new('RGB',(cols*w,rows*h),(24,26,32))\n"
        "for i,im in enumerate(ims): sheet.paste(im.resize((w,h)),((i%cols)*w,(i//cols)*h))\n"
        "sheet.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-c", code, os.path.join(PREV, "prologue.png")] + shots, check=True)
    for p_ in shots[1:]:
        os.remove(p_)
    print("preview:", os.path.join(PREV, "prologue.png"), shots[0])
