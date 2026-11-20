# alive.py: round 3 of the living world (alive-world, 2026-11-20, nate 2026-11-19: "too many simple shapes and
# untextured parts ... the world must feel alive"). Blender looks over the plain boxes a player sees most that the
# first two rounds left (art/city/audit.luau, art/preview/city_audit.txt; ranked by how often a player sees them):
# * the safehouses (16, where every hero spawns, respawns, banks and changes loadout): the five terminals (bank,
#   loadout, respawn, contract board, weapon rack) were neon boxes, the canopy a plain slab, the pad a plain tile:
#   TermBank, TermLoadout, TermRespawn, TermContracts, TermWeapons (frame 3 x 5 x 2, the front +z toward the pad),
#   SafeCanopy (28 x 1.5 x 18, with its two front posts down to the pad) and SafePadRing (36 x 1.2 x 36, a painted
#   ring and chevrons on the pad's top)
# * the Docks' gantry cranes (3, the tallest things on the harbour, seen from all over the city): CraneLeg
#   (4 x 100 x 4, a lattice leg on its rail bogie), CraneBeam (40 x 6 x 6, the top girder with the operator's cab and
#   machine house) and CraneBoom (4 x 4 x 70, the lattice boom over the water with its trolley, cable and hook)
# * the Foundry's chimneys (3, 170 tall): FoundryChimney (16 x 170 x 16), sooty brick with steel bands and a ladder
# * Uptown's roof gardens (25 flat green slabs seen from every flight): RoofGarden (28 x 1.2 x 29), a concrete planter
#   rim, shrubs, flower beds, a small tree and a bench over the bed (the bed box stays)
# Every look is drawn in Roblox studs about the middle of the box it dresses (x, up, z back); Shared.LifeKit scales
# each mesh by the real box over the frame. The boxes stay as they were (collisions, queries, prompts, breaking); the
# meshes are visual only, and the terminals', canopy's, cranes' and chimneys' boxes are hidden under them
# (Config.Life.alive.hide). The big pieces carry a baked texture set (paint wear and rust, brick courses and soot,
# panel seams and bolts); thin details are flat colours. Low poly for phones.
# Output: art/export/Alive.fbx (textures embedded), art/export/alive/*.png, src/config/AliveArt.luau (generated);
# --preview renders art/preview/alive_safehouse.png, alive_docks.png and alive_garden.png.
# Run: ~/tools/bpyenv/bin/python art/blender/alive.py [--preview] [--fast] [--no-bake] [--no-export]
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

kit.reset()

import vkit  # noqa: E402
from vkit import R, P, rbox, join, smooth_shade  # noqa: E402
from studs import rb, B, C, S, T, TOR, turn, shift, copy, star, extrude_up  # noqa: E402

FAST = "--fast" in sys.argv
vkit.OUT = os.path.join(kit.ROOT, "export", "alive")


class Grp:
    """One baked texture set (vkit.bake_look's look): its textured meshes share one UV atlas."""

    def __init__(self, name, res=1024):
        self.name, self.prefix, self.res = name, "", res
        self.meshes, self.tex, self.extra = {}, [], {}
        self.paint, self.seams, self.wheels, self.rings = None, [], [], []
        GROUPS[name] = self

    def textured(self):
        return [self.meshes[n] for n in self.tex]


GROUPS = {}
LOOKS = {}  # look -> [mesh names]
FRAMES = {}  # look -> (sx, sy, sz)
INFO = {}


def look(name, frame):
    FRAMES[name] = frame
    LOOKS.setdefault(name, [])


def add(g, lk, name, parts, rgb=None, mat="SmoothPlastic", alpha=0.0, tint=False):
    """A mesh of a look: baked into g's texture set (rgb None: its parts carry vkit regions) or one flat colour."""
    parts = [p for p in (parts if isinstance(parts, (list, tuple)) else [parts]) if p is not None]
    if rgb is not None:
        for p in parts:
            p.data.materials.clear()
    ob = join(parts, name)
    smooth_shade(ob)
    assert name not in INFO, "mesh names are unique: " + name
    g.meshes[name] = ob
    if rgb is None:
        g.tex.append(name)
    LOOKS[lk].append(name)
    INFO[name] = dict(group=g.name, rgb=tuple(int(c) for c in (rgb or (255, 255, 255))), mat=mat, alpha=alpha,
                      maps=rgb is None, tint=tint)
    return ob


# ================================================================ the patterns (texture space: each texel's baked
# position p and normal n in studs about the look's frame)
def _hash(*a):
    x = np.zeros_like(a[0], dtype=np.float64)
    for k, v in zip((12.9898, 78.233, 37.719), a):
        x = x + v * k
    h = np.sin(x) * 43758.5453
    return (h - np.floor(h)).astype(np.float32)


def vnoise(p, f, seed=0.0):
    q = p * f + seed
    i = np.floor(q)
    t = q - i
    t = t * t * (3 - 2 * t)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (t[:, 0] if dx else 1 - t[:, 0]) * (t[:, 1] if dy else 1 - t[:, 1]) * (t[:, 2] if dz else 1 - t[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out.astype(np.float32)


def fbm(p, f, seed=0.0):
    return 0.5 * vnoise(p, f, seed) + 0.3 * vnoise(p, f * 2.1, seed + 7) + 0.2 * vnoise(p, f * 4.3, seed + 13)


def rgbf(c):
    return np.array(c, dtype=np.float32) / 255


_orig = vkit._pattern
KINDS = ("paint", "brick", "panel", "hazard", "seam", "concrete")


def alive_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise_):
    if not (isinstance(pat, tuple) and pat and pat[0] in KINDS):
        return _orig(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise_)
    p, n = Pp[m], Nn[m]
    c, r, h = col[m], rough[m], height[m]
    kind = pat[0]
    if kind == "paint":  # weathered paint on steel: soft mottling, chips to bare metal, rust runs down the faces
        rust = pat[1] if len(pat) > 1 else 0.5
        k = fbm(p, 0.35)
        c = c * (0.88 + 0.16 * k)[:, None]
        chip = fbm(p, 2.6, 4.0) > 0.70 - 0.06 * rust
        c[chip] = c[chip] * 0.35 + rgbf((96, 92, 88)) * 0.65
        r = np.where(chip, 0.45, r)
        side = np.abs(n[:, 1]) < 0.5
        run = vnoise(p * np.array([3.0, 0.08, 3.0], np.float32), 1.0, 9.0)
        streak = side & (run > 1.0 - 0.32 * rust)
        c[streak] = c[streak] * 0.6 + rgbf((150, 74, 40)) * 0.4
        h = h - chip * 0.35
    elif kind == "brick":  # brick courses round a stack: staggered bricks, mortar lines, soot up top
        bh, bl = 0.75, 1.9
        ang = np.arctan2(p[:, 2], p[:, 0])
        rad = np.sqrt(p[:, 0] ** 2 + p[:, 2] ** 2)
        u = ang * np.maximum(rad, 1.0)
        row = np.floor(p[:, 1] / bh)
        off = (row % 2) * bl / 2
        fu = ((u + off) / bl) % 1
        fv = (p[:, 1] / bh) % 1
        mortar = (fu < 0.06) | (fv < 0.12)
        tone = 0.82 + 0.3 * _hash(np.floor((u + off) / bl), row, row * 0.0 + 3.0)
        c = c * tone[:, None]
        c[mortar] = rgbf(pat[1])
        h = h - mortar * 0.6
        top = pat[2]
        soot = np.clip((p[:, 1] - (top - 60)) / 60, 0, 1) * (0.6 + 0.4 * fbm(p, 0.2, 2.0))
        c = c * (1 - 0.72 * soot)[:, None]
        r = np.where(mortar, 0.95, 0.85)
    elif kind == "panel":  # a cabinet's painted panels: seams every `pat[1]` studs, screws at the corners, scuffs low
        step = pat[1]
        a = np.where(np.abs(n[:, 0]) > 0.6, p[:, 2], p[:, 0])
        su = np.abs(((a / step) % 1) - 0.5) > 0.47
        sv = np.abs(((p[:, 1] / step) % 1) - 0.5) > 0.48
        seam = (su | sv) & (np.abs(n[:, 1]) < 0.6)
        c[seam] *= 0.45
        h = h - seam * 0.6
        fa, fb = (a / step) % 1, (p[:, 1] / step) % 1
        screw = ((np.abs(fa - 0.08) < 0.025) | (np.abs(fa - 0.92) < 0.025)) & (
            (np.abs(fb - 0.1) < 0.025) | (np.abs(fb - 0.9) < 0.025))
        c[screw] = rgbf((200, 204, 210))
        h = h + screw * 0.5
        scuff = (p[:, 1] < pat[2]) & (fbm(p, 3.0, 1.0) > 0.62)
        c[scuff] *= 0.72
        c = c * (0.93 + 0.1 * fbm(p, 1.2))[:, None]
    elif kind == "hazard":  # yellow and black diagonal stripes
        rgb2 = rgbf(pat[1])
        w = pat[2]
        s = ((p[:, 0] + p[:, 1] + p[:, 2]) / w) % 2 < 1
        c[s] = rgb2
        c = c * (0.9 + 0.12 * fbm(p, 1.5, 3.0))[:, None]
    elif kind == "seam":  # a canopy's painted standing-seam sheet: ribs every pat[1] studs, rain streaks
        rib = np.abs(((p[:, 0] / pat[1]) % 1) - 0.5) > 0.44
        c[rib] *= 0.8
        h = h + rib * 0.4
        c = c * (0.9 + 0.12 * vnoise(p * np.array([0.6, 1.0, 0.05], np.float32), 1.0, 5.0))[:, None]
    elif kind == "concrete":  # cast concrete: pores, a darker drip band, board marks
        k = fbm(p, 0.8)
        c = c * (0.85 + 0.16 * k)[:, None]
        pore = _hash(np.floor(p[:, 0] * 11), np.floor(p[:, 1] * 11), np.floor(p[:, 2] * 11)) > 0.95
        c[pore] *= 0.7
        h = h + k * 0.3 - pore * 0.4
    col[m], rough[m], height[m] = c, r, h


vkit._pattern = alive_pattern

# ---------------------------------------------------------------- colours
NAVY = (44, 58, 92)
DARK = (40, 42, 48)
STEEL = (150, 156, 164)
GOLD = (236, 190, 58)
CREAM = (246, 238, 214)
WOODC = (166, 112, 66)
CRANE = (240, 168, 36)  # gantry safety orange-yellow
BRICK = (150, 64, 48)
MORTAR = (120, 110, 100)
CONCRETE = (196, 192, 184)
WHITE = (244, 244, 240)
SAFE = (236, 240, 245)

# regions (baked)
R_CAB = R("Cabinet", NAVY, 0.55, 0.35, pat=("panel", 1.0, -1.6))
R_CABD = R("CabinetDark", (34, 38, 50), 0.6, 0.3, pat=("panel", 1.0, -1.6))
R_STEEL = R("Steel", STEEL, 0.45, 0.8, pat=("paint", 0.2))
R_GOLD = R("Gold", GOLD, 0.35, 0.85)
R_CORK = R("Cork", (186, 140, 92), 0.95, pat=("concrete",))
R_WOOD = R("Wood", WOODC, 0.8, pat=("planks",))
R_ROOF = R("CanopyRoof", (116, 128, 146), 0.5, 0.6, pat=("seam", 1.0))
R_FASCIA = R("Fascia", (52, 96, 170), 0.5, 0.3, pat=("paint", 0.1))
R_POST = R("Post", (70, 76, 86), 0.5, 0.7, pat=("paint", 0.3))
R_HAZ = R("Hazard", (246, 200, 40), 0.6, 0.1, pat=("hazard", (30, 30, 34), 0.6))
R_CRANE = R("CranePaint", CRANE, 0.55, 0.4, pat=("paint", 0.8))
R_CRANED = R("CraneDark", (64, 66, 72), 0.6, 0.6, pat=("paint", 0.9))
R_CRANEW = R("CraneWhite", (232, 232, 226), 0.55, 0.3, pat=("paint", 0.7))
R_BRICK = R("Brick", BRICK, 0.85, pat=("brick", MORTAR, 85.0))
R_BAND = R("Band", (58, 60, 64), 0.5, 0.8, pat=("paint", 1.0))
R_CONC = R("Concrete", CONCRETE, 0.9, pat=("concrete",))


def lat(points_a, points_b, rad, segs=4):
    """Tubes between matching points (a lattice's members)."""
    return [T([a, b], rad, segs=segs) for a, b in zip(points_a, points_b)]


# ================================================================ the safehouse terminals (frame 3 x 5 x 2: foot at y
# -2.5, the front at +z toward the pad). Each: a baked body, a glowing screen in its kind's colour (tint), trims.
TW, TH, TD = 3.0, 5.0, 2.0
FOOT = -TH / 2


def plinth():
    return P(rbox(3.0, 0.35, 2.0, 0, FOOT + 0.175, 0, bev=0.06), R_CABD)


# ---------------------------------------------------------------- the bank: an armoured cash machine with a coin crest
look("TermBank", (TW, TH, TD))
G = Grp("TermBank", 512)
body = [plinth(),
        P(rbox(2.6, 3.4, 1.5, 0, FOOT + 0.35 + 1.7, -0.15, bev=0.12), R_CAB),
        P(rbox(2.8, 0.8, 1.9, 0, FOOT + 3.75 + 0.4, 0.0, bev=0.1), R_CAB),  # the hood over the screen
        P(rbox(1.9, 1.3, 0.2, 0, FOOT + 3.05, 0.62, bev=0.05), R_CABD),  # the screen's bezel
        P(rbox(1.6, 0.14, 0.62, 0, FOOT + 1.95, 0.9, bev=0.03), R_STEEL),  # the keypad tray
        P(rbox(0.9, 0.12, 0.08, 0.0, FOOT + 2.55, 0.62, bev=0.02), R_STEEL),  # the card slot
        P(rbox(1.2, 0.35, 0.08, 0.0, FOOT + 1.25, 0.62, bev=0.02), R_STEEL)]  # the cash slot
add(G, "TermBank", "TermBankBody", body)
keys = [B(0.32, 0.1, 0.16, -0.45 + i * 0.45, FOOT + 2.06, 0.72 + j * 0.2) for i in range(3) for j in range(3)]
coin = [C(0.42, 0.12, 0, FOOT + 4.15, 0.97, segs=18, axis="z"), TOR(0.42, 0.05, 0, FOOT + 4.15, 1.04, axis="z", segs=18, csegs=4)]
add(G, "TermBank", "TermBankTrim", keys + coin + [B(2.9, 0.08, 0.08, 0, FOOT + 3.72, 0.96)], GOLD, "Metal")
add(G, "TermBank", "TermBankGlow", [B(1.6, 1.0, 0.06, 0, FOOT + 3.05, 0.74), B(1.0, 0.06, 0.06, 0, FOOT + 1.25, 0.67)],
    (255, 205, 70), "Neon", tint=True)

# ---------------------------------------------------------------- the loadout: a hero's suit-up locker console
look("TermLoadout", (TW, TH, TD))
G = Grp("TermLoadout", 512)
body = [plinth(),
        P(rbox(2.8, 4.3, 1.4, 0, FOOT + 0.35 + 2.15, -0.25, bev=0.12), R_CAB),
        P(rbox(2.2, 3.0, 0.2, 0, FOOT + 2.6, 0.5, bev=0.05), R_CABD),  # the screen's frame
        P(rbox(2.9, 0.3, 1.6, 0, FOOT + 4.75, -0.15, bev=0.08), R_STEEL)]  # the crown
for sx in (-1, 1):
    body.append(P(rbox(0.22, 3.6, 0.3, sx * 1.32, FOOT + 2.4, 0.5, bev=0.05), R_STEEL))  # the hinge rails
add(G, "TermLoadout", "TermLoadoutBody", body)
st = star(0.62, 0.27, 0.08, 0, FOOT + 2.75, 0.68, points=5, axis="z")
add(G, "TermLoadout", "TermLoadoutTrim",
    [st, B(1.4, 0.1, 0.06, 0, FOOT + 1.6, 0.66), B(1.0, 0.1, 0.06, 0, FOOT + 1.4, 0.66)], (250, 250, 255), "SmoothPlastic")
add(G, "TermLoadout", "TermLoadoutGlow", [B(1.9, 2.6, 0.05, 0, FOOT + 2.6, 0.62), B(2.6, 0.08, 0.06, 0, FOOT + 4.55, 0.66)],
    (110, 190, 255), "Neon", tint=True)

# ---------------------------------------------------------------- the respawn: a beacon pod with floating halo rings
look("TermRespawn", (TW, TH, TD))
G = Grp("TermRespawn", 512)
body = [P(C(1.0, 0.45, 0, FOOT + 0.225, 0, segs=20), R_CABD),
        P(C(0.72, 0.3, 0, FOOT + 0.6, 0, segs=20, r2=0.55), R_STEEL),
        P(C(0.45, 2.6, 0, FOOT + 2.05, 0, segs=16, r2=0.32), R_CAB),
        P(C(0.62, 0.3, 0, FOOT + 3.5, 0, segs=18, r2=0.44), R_STEEL)]
for k in range(3):
    a = k * math.tau / 3 + math.pi / 2
    fin = P(rbox(0.12, 1.4, 0.55, 0, FOOT + 1.4, 0, bev=0.03), R_STEEL)
    shift(fin, rb(math.cos(a) * 0.55, 0, math.sin(a) * 0.55))
    body.append(fin)
add(G, "TermRespawn", "TermRespawnBody", body)
add(G, "TermRespawn", "TermRespawnTrim", [TOR(0.47, 0.05, 0, FOOT + y, 0, segs=18, csegs=4) for y in (1.2, 2.0, 2.8)],
    GOLD, "Metal")
add(G, "TermRespawn", "TermRespawnGlow",
    [TOR(1.2, 0.09, 0, FOOT + 3.9, 0, segs=28, csegs=5), TOR(0.95, 0.08, 0, FOOT + 4.35, 0, segs=24, csegs=5),
     S(0.36, 0, FOOT + 4.25, 0, segs=12, rings=8)]
    + [B(0.08, 2.2, 0.06, math.cos(a) * 0.4, FOOT + 2.05, math.sin(a) * 0.4) for a in (math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6)],
    (120, 230, 150), "Neon", tint=True)

# ---------------------------------------------------------------- the contract board: a cork notice board on posts
look("TermContracts", (TW, TH, TD))
G = Grp("TermContracts", 512)
body = [P(rbox(2.9, 0.3, 1.2, 0, FOOT + 0.15, 0, bev=0.05), R_CABD)]
for sx in (-1, 1):
    body.append(P(rbox(0.28, 4.6, 0.28, sx * 1.3, FOOT + 2.4, -0.2, bev=0.05), R_STEEL))
body.append(P(rbox(2.9, 2.5, 0.25, 0, FOOT + 2.9, -0.2, bev=0.05), R_CAB))  # the board's frame
body.append(P(rbox(2.5, 2.1, 0.1, 0, FOOT + 2.9, -0.04), R_CORK))  # the cork
body.append(P(rbox(3.0, 0.3, 0.7, 0, FOOT + 4.45, -0.2, bev=0.08), R_CABD))  # the cap
add(G, "TermContracts", "TermContractsBody", body)
papers = []
for (x, y, w, h, a) in ((-0.75, 3.35, 0.7, 0.9, -6), (0.15, 3.45, 0.8, 0.7, 4), (0.85, 3.2, 0.55, 0.75, -3),
                        (-0.6, 2.35, 0.8, 0.6, 5), (0.45, 2.4, 0.9, 0.8, -5)):
    pp = B(w, h, 0.03, 0, 0, 0)
    turn(pp, "z", a)
    shift(pp, rb(x, FOOT + y, 0.03))
    papers.append(pp)
add(G, "TermContracts", "TermContractsPaper", papers, CREAM, "SmoothPlastic")
pins = [S(0.07, x, FOOT + y, 0.1, segs=6, rings=4) for (x, y) in ((-0.75, 3.75), (0.15, 3.78), (0.85, 3.55), (-0.6, 2.62), (0.45, 2.77))]
add(G, "TermContracts", "TermContractsTrim", pins, (220, 50, 50), "SmoothPlastic")
add(G, "TermContracts", "TermContractsGlow", [B(2.5, 0.32, 0.06, 0, FOOT + 4.45, 0.17)], (255, 140, 60), "Neon", tint=True)

# ---------------------------------------------------------------- the weapon rack: a steel frame with weapons on hooks
look("TermWeapons", (TW, TH, TD))
G = Grp("TermWeapons", 512)
body = [plinth()]
for sx in (-1, 1):
    body.append(P(rbox(0.3, 4.4, 0.5, sx * 1.3, FOOT + 2.55, -0.3, bev=0.06), R_CAB))
body.append(P(rbox(2.9, 0.35, 0.6, 0, FOOT + 4.6, -0.3, bev=0.06), R_CAB))
body.append(P(rbox(2.4, 3.8, 0.12, 0, FOOT + 2.5, -0.5), R_WOOD))  # the back boards
body.append(P(rbox(2.4, 0.15, 0.4, 0, FOOT + 1.0, -0.25), R_STEEL))  # the foot rail
add(G, "TermWeapons", "TermWeaponsBody", body)
arms = []
# a sword (blade, guard, grip, pommel), a hammer, a staff
arms += [B(0.18, 2.1, 0.06, -0.75, FOOT + 2.7, -0.3), B(0.65, 0.12, 0.14, -0.75, FOOT + 1.62, -0.3),
         C(0.07, 0.55, -0.75, FOOT + 1.3, -0.3, segs=6), S(0.1, -0.75, FOOT + 1.0, -0.3, segs=6, rings=4)]
arms += [C(0.07, 2.6, 0.05, FOOT + 2.4, -0.3, segs=6), B(0.75, 0.42, 0.42, 0.05, FOOT + 3.75, -0.3)]
arms += [C(0.06, 3.3, 0.8, FOOT + 2.65, -0.3, segs=6), S(0.16, 0.8, FOOT + 4.35, -0.3, segs=8, rings=6)]
arms += [B(0.08, 0.08, 0.3, x, FOOT + 4.0, -0.32) for x in (-0.75, 0.05, 0.8)]  # the hooks
add(G, "TermWeapons", "TermWeaponsArms", arms, (70, 76, 88), "Metal")
add(G, "TermWeapons", "TermWeaponsGlow", [B(2.3, 0.1, 0.06, 0, FOOT + 4.45, 0.02), B(2.3, 0.1, 0.06, 0, FOOT + 0.6, 0.12)],
    (200, 205, 215), "Neon", tint=True)

# ================================================================ the canopy (frame 28 x 1.5 x 18; its front edge +z
# over the terminals; the pad's top is 12.75 under its middle, where its front posts stand)
look("SafeCanopy", (28.0, 1.5, 18.0))
G = Grp("SafeCanopy", 1024)
roof = [P(rbox(27.6, 0.45, 17.6, 0, 0.42, 0, bev=0.08), R_ROOF)]
fascia = [P(rbox(28.2, 0.9, 0.3, 0, 0.05, 8.95, bev=0.06), R_FASCIA), P(rbox(28.2, 0.9, 0.3, 0, 0.05, -8.95, bev=0.06), R_FASCIA),
          P(rbox(0.3, 0.9, 18.2, 14.0, 0.05, 0, bev=0.06), R_FASCIA), P(rbox(0.3, 0.9, 18.2, -14.0, 0.05, 0, bev=0.06), R_FASCIA)]
ribs = [P(rbox(0.6, 0.3, 17.0, x, -0.2, 0, bev=0.04), R_POST) for x in (-10.5, -3.5, 3.5, 10.5)]
posts = []
for sx in (-1, 1):
    posts.append(P(C(0.32, 12.6, sx * 13.0, -12.75 + 6.3 + 0.35, 8.1, segs=12), R_POST))
    posts.append(P(C(0.55, 0.35, sx * 13.0, -12.75 + 0.175, 8.1, segs=12), R_HAZ))  # the foot collar
    posts.append(P(rbox(1.2, 0.12, 1.2, sx * 13.0, -12.75 + 0.06, 8.1, bev=0.03), R_POST))  # the base plate
    posts.append(P(T([(sx * 13.0, -4.0, 8.1), (sx * 9.0, -0.3, 8.1)], 0.16, segs=6), R_POST))  # a knee brace
add(G, "SafeCanopy", "CanopyRoof", roof + ribs)
add(G, "SafeCanopy", "CanopyFascia", fascia)
add(G, "SafeCanopy", "CanopyPosts", posts)
add(G, "SafeCanopy", "CanopyLights", [B(24.0, 0.08, 0.35, 0, -0.38, z) for z in (-4.0, 1.5, 6.5)], (236, 248, 255), "Neon")
add(G, "SafeCanopy", "CanopyStripe", [B(28.25, 0.18, 0.06, 0, 0.3, 9.13), B(28.25, 0.18, 0.06, 0, -0.2, 9.13)], GOLD, "SmoothPlastic")

# ================================================================ the pad's painted ring (frame 36 x 1.2 x 36: drawn on
# its top face, 0.6 over its middle)
look("SafePadRing", (36.0, 1.2, 36.0))
G = Grp("SafePadFlat")
ring = [TOR(13.0, 0.5, 0, 0.6, 0, segs=56, csegs=4)]
for k in range(4):
    a = k * math.pi / 2 + math.pi / 4
    ca, sa = math.cos(a), math.sin(a)
    for d in (9.5, 6.8):
        # a chevron pointing in at the pad's middle: two flat arms meeting at the tip (u out, v across)
        for s in (-1, 1):
            quad = [(0.0, 0.0), (1.3, s * 1.5), (1.85, s * 1.5), (0.55, 0.0)]
            if s < 0:
                quad = quad[::-1]
            pts = [((d + u) * ca - v * sa, (d + u) * sa + v * ca) for (u, v) in quad]
            ring.append(extrude_up(pts, 0.58, 0.66))
add(G, "SafePadRing", "PadPaint", ring, GOLD, "SmoothPlastic")

# ================================================================ the gantry crane
# ---------------------------------------------------------------- a leg (frame 4 x 100 x 4: a lattice tower on its
# rail bogie; LifeKit stretches it to the leg's real height)
look("CraneLeg", (4.0, 100.0, 4.0))
G = Grp("CraneLeg", 1024)
H2 = 50.0
corners = [(-1.6, -1.6), (1.6, -1.6), (1.6, 1.6), (-1.6, 1.6)]
frame = [P(C(0.28, 96.0, x, 0.5, z, segs=6), R_CRANE) for (x, z) in corners]
NP = 12
for i in range(NP + 1):
    y = -H2 + 3.5 + i * (96.0 - 3.5) / NP
    for k in range(4):
        (xa, za), (xb, zb) = corners[k], corners[(k + 1) % 4]
        frame.append(P(T([(xa, y, za), (xb, y, zb)], 0.14, segs=4), R_CRANE))
        if i < NP:
            y2 = y + (96.0 - 3.5) / NP
            if (i + k) % 2 == 0:
                frame.append(P(T([(xa, y, za), (xb, y2, zb)], 0.1, segs=4), R_CRANE))
            else:
                frame.append(P(T([(xb, y, zb), (xa, y2, za)], 0.1, segs=4), R_CRANE))
frame.append(P(rbox(4.2, 1.0, 4.2, 0, H2 - 0.5, 0, bev=0.08), R_CRANED))  # the head plate under the beam
add(G, "CraneLeg", "CraneLegFrame", frame)
bog = [P(rbox(4.6, 2.2, 7.0, 0, -H2 + 2.4, 0, bev=0.15), R_HAZ),
       P(rbox(3.6, 1.0, 4.0, 0, -H2 + 4.0, 0, bev=0.1), R_CRANED)]
for z in (-2.4, 2.4):
    for x in (-1.6, 1.6):
        bog.append(P(C(0.75, 0.5, x, -H2 + 0.8, z, segs=14, axis="x"), R_CRANED))
add(G, "CraneLeg", "CraneLegBogie", bog)

# ---------------------------------------------------------------- the top beam (frame 40 x 6 x 6: a box girder along x
# with walkway rails, the operator's cab under it at +z and the machine house on top)
look("CraneBeam", (40.0, 6.0, 6.0))
G = Grp("CraneBeam", 1024)
beam = [P(rbox(40.0, 1.0, 5.6, 0, 2.4, 0, bev=0.1), R_CRANE), P(rbox(40.0, 1.0, 5.6, 0, -2.4, 0, bev=0.1), R_CRANE)]
for i in range(11):
    x = -19.5 + i * 3.9
    for z in (-2.6, 2.6):
        beam.append(P(rbox(0.3, 3.8, 0.3, x, 0, z), R_CRANE))
        if i < 10:
            beam.append(P(T([(x, -1.9, z), (x + 3.9, 1.9, z)] if i % 2 == 0 else [(x, 1.9, z), (x + 3.9, -1.9, z)], 0.12, segs=4), R_CRANE))
house = [P(rbox(9.0, 4.0, 5.0, -12.0, 4.9, 0, bev=0.15), R_CRANEW), P(rbox(9.6, 0.4, 5.6, -12.0, 7.1, 0, bev=0.08), R_CRANED)]
for k in range(4):
    house.append(P(rbox(1.2, 1.4, 0.1, -15.0 + k * 2.0, 5.2, -2.55), R_CRANED))  # louvres
add(G, "CraneBeam", "CraneBeamGirder", beam)
add(G, "CraneBeam", "CraneBeamHouse", house)
cab = [P(rbox(4.0, 3.6, 3.6, 6.0, -4.9, 2.2, bev=0.15), R_CRANEW), P(rbox(4.3, 0.4, 3.9, 6.0, -3.0, 2.2, bev=0.06), R_CRANED)]
add(G, "CraneBeam", "CraneCab", cab)
add(G, "CraneBeam", "CraneCabGlass", [B(3.4, 1.6, 0.08, 6.0, -4.5, 4.03), B(0.08, 1.6, 2.6, 8.02, -4.5, 2.2), B(0.08, 1.6, 2.6, 3.98, -4.5, 2.2)],
    (150, 200, 225), "Glass", alpha=0.25)
rail = []
for z in (-2.9, 2.9):
    rail.append(T([(-20.0, 4.0, z), (20.0, 4.0, z)], 0.07, segs=5))
    for i in range(9):
        x = -18.0 + i * 4.5
        rail.append(C(0.06, 1.1, x, 3.45, z, segs=5))
add(G, "CraneBeam", "CraneRail", rail, (236, 236, 230), "Metal")
add(G, "CraneBeam", "CraneLamp", [S(0.35, 19.6, 3.4, 0, segs=8, rings=5), S(0.35, -16.7, 7.6, 0, segs=8, rings=5)], (255, 70, 50), "Neon")

# ---------------------------------------------------------------- the boom (frame 4 x 4 x 70: a lattice along z over the
# water; its trolley rides out on it with the cable and the hook block hanging 22 under)
look("CraneBoom", (4.0, 4.0, 70.0))
G = Grp("CraneBoom", 1024)
L2 = 35.0
bc = [(-1.6, -1.6), (1.6, -1.6), (1.6, 1.6), (-1.6, 1.6)]
boom = [P(C(0.26, 70.0, x, y, 0, segs=6, axis="z"), R_CRANE) for (x, y) in bc]
NB = 14
for i in range(NB + 1):
    z = -L2 + i * 70.0 / NB
    for k in range(4):
        (xa, ya), (xb, yb) = bc[k], bc[(k + 1) % 4]
        boom.append(P(T([(xa, ya, z), (xb, yb, z)], 0.12, segs=4), R_CRANE))
        if i < NB:
            z2 = z + 70.0 / NB
            a, b = ((xa, ya, z), (xb, yb, z2)) if (i + k) % 2 == 0 else ((xb, yb, z), (xa, ya, z2))
            boom.append(P(T([a, b], 0.09, segs=4), R_CRANE))
boom.append(P(rbox(4.4, 4.4, 1.2, 0, 0, L2 - 0.6, bev=0.1), R_CRANED))  # the boom's nose
add(G, "CraneBoom", "CraneBoomTruss", boom)
trolley = [P(rbox(3.4, 1.2, 3.0, 0, -2.6, 8.0, bev=0.1), R_CRANED), P(rbox(2.0, 1.4, 1.4, 0, -25.5, 8.0, bev=0.15), R_HAZ)]
add(G, "CraneBoom", "CraneTrolley", trolley)
cable = [C(0.06, 22.0, x, -14.4, 8.0, segs=5) for x in (-0.45, 0.45)]
hook = [TOR(0.55, 0.16, 0, -27.0, 8.0, axis="z", segs=14, csegs=5, arc=math.pi * 1.5), C(0.18, 0.7, 0, -26.4, 8.0, segs=6)]
add(G, "CraneBoom", "CraneCable", cable + hook, (46, 48, 54), "Metal")

# ================================================================ the Foundry's chimney (frame 16 x 170 x 16: a cylinder
# box; its glow ring stays on top)
look("FoundryChimney", (16.0, 170.0, 16.0))
G = Grp("FoundryChimney", 1024)
stack = [P(C(7.9, 166.0, 0, -2.0, 0, segs=28, r2=6.6), R_BRICK)]
add(G, "FoundryChimney", "ChimneyStack", stack)
bands = []
for k in range(7):
    y = -78.0 + k * 24.0
    rr = 7.9 - (y + 85.0) / 166.0 * 1.3
    bands.append(P(TOR(rr + 0.12, 0.35, 0, y, 0, segs=28, csegs=5), R_BAND))
bands.append(P(C(7.2, 3.0, 0, 82.5, 0, segs=28, r2=7.0), R_BAND))  # the cap
bands.append(P(C(8.6, 1.4, 0, -84.3, 0, segs=28), R_CONC))  # the plinth
add(G, "FoundryChimney", "ChimneyBands", bands)
lad = []
for sx in (-0.5, 0.5):
    lad.append(T([(sx, -82.0, -7.95), (sx, 80.0, -6.75)], 0.07, segs=4))
for k in range(0, 54):
    y = -80.0 + k * 3.0
    zz = -7.95 + (y + 82.0) / 162.0 * 1.2
    lad.append(T([(-0.5, y, zz), (0.5, y, zz)], 0.05, segs=4))
add(G, "FoundryChimney", "ChimneyLadder", lad, (60, 62, 66), "Metal")

# ================================================================ an Uptown roof garden (frame 28 x 1.2 x 29: the bed
# box stays; the planter rim runs round it, shrubs, flowers, a tree and a bench stand in it)
look("RoofGarden", (28.0, 1.2, 29.0))
G = Grp("RoofGarden", 1024)
rim = [P(rbox(28.6, 1.6, 0.7, 0, 0.2, 14.65, bev=0.08), R_CONC), P(rbox(28.6, 1.6, 0.7, 0, 0.2, -14.65, bev=0.08), R_CONC),
       P(rbox(0.7, 1.6, 29.0, 14.15, 0.2, 0, bev=0.08), R_CONC), P(rbox(0.7, 1.6, 29.0, -14.15, 0.2, 0, bev=0.08), R_CONC),
       P(rbox(1.6, 0.25, 12.0, 0, 0.62, 0), R_CONC)]  # a stepping-stone path down the middle
for k in range(6):
    rim.append(P(rbox(1.8, 0.2, 1.4, 0, 0.66, -12.0 + k * 4.8, bev=0.05), R_CONC))
add(G, "RoofGarden", "GardenRim", rim)


def bush(r, x, z, seed, sq=0.75):
    s = kit.sphere("bu", r, at=rb(x, 0.6 + r * sq * 0.8, z), scale=(1, 1, sq), segs=10, rings=7)
    kit.apply_all(s)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in s.data.vertices:
        n = noise.noise(v.co * (0.9 / r) + off)
        v.co = v.co * (1 + n * 0.22)
    s.data.update()
    return s


shrubs = [bush(2.2, -10.5, -11.0, 1), bush(1.8, -8.0, -12.0, 2), bush(2.0, 10.5, 11.0, 3), bush(1.6, 8.2, 12.2, 4),
          bush(1.7, 11.0, -10.5, 5), bush(1.5, -11.2, 10.0, 6), bush(1.4, -5.5, 4.0, 7), bush(1.3, 5.0, -4.5, 8)]
add(G, "RoofGarden", "GardenShrubs", shrubs, (74, 136, 62), "Grass")
flowersA, flowersB = [], []
for k in range(26):
    x = -12.0 + (k * 7.3) % 9.0
    z = -6.0 + (k * 4.1) % 12.0
    flowersA.append(S(0.32, x, 0.9, z, segs=6, rings=4))
for k in range(26):
    x = 3.5 + (k * 5.7) % 8.5
    z = -2.0 + (k * 3.3) % 12.0
    flowersB.append(S(0.32, x, 0.9, z, segs=6, rings=4))
add(G, "RoofGarden", "GardenFlowersA", flowersA, (240, 110, 160), "SmoothPlastic")
add(G, "RoofGarden", "GardenFlowersB", flowersB, (250, 210, 70), "SmoothPlastic")
add(G, "RoofGarden", "GardenLeaves", [bush(3.6, 7.0, -10.0, 11, sq=0.85)], (88, 150, 64), "Grass")
trunk = [C(0.4, 6.2, 7.0, 3.7, -10.0, segs=8, r2=0.28)]
bench = [B(4.0, 0.25, 1.2, -6.0, 2.1, 8.5), B(4.0, 1.0, 0.18, -6.0, 2.85, 9.05)]
for sx in (-1.7, 1.7):
    bench.append(B(0.2, 1.4, 1.0, -6.0 + sx, 1.3, 8.6))
add(G, "RoofGarden", "GardenWood", trunk + bench, (120, 84, 56), "Wood")

# ================================================================ bake, the fit table and the export
MAPS = {}
if "--no-bake" not in sys.argv:
    for gname, g in GROUPS.items():
        if not g.tex:
            continue
        print("baking", gname, flush=True)
        vkit.RES = 512 if FAST else g.res
        MAPS[gname] = vkit.bake_look(g, ao_samples=6 if FAST else 16)


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


TRIS = {}
total = 0
rows = []
for lk in sorted(LOOKS):
    fx, fy, fz = FRAMES[lk]
    rows.append("\t%s = {" % lk)
    rows.append("\t\tframe = { %.3f, %.3f, %.3f }," % (fx, fy, fz))
    rows.append("\t\tmeshes = {")
    for name in sorted(LOOKS[lk]):
        g = GROUPS[INFO[name]["group"]]
        ob = g.meshes[name]
        lo, hi = bounds(ob)
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        t = kit.tris(ob)
        TRIS[name] = t
        total += t
        inf = INFO[name]
        extra = (", alpha = %g" % inf["alpha"]) if inf["alpha"] else ""
        extra += ", maps = true" if inf["maps"] else ""
        extra += ", tint = true" if inf["tint"] else ""
        rgb = inf["rgb"]
        rows.append("\t\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (name, max(size[0], 0.05), max(size[2], 0.05), max(size[1], 0.05), c[0], c[2], -c[1], rgb[0], rgb[1], rgb[2],
                       inf["mat"], extra, t))
    rows.append("\t\t},")
    rows.append("\t},")
print("alive: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for lk in sorted(LOOKS):
    print("  %-14s %6d tris  (%s)" % (lk, sum(TRIS[n] for n in LOOKS[lk]), ", ".join(sorted(LOOKS[lk]))))
text = "\n".join([
    "-- GENERATED by art/blender/alive.py: do not edit by hand.",
    "-- Round 3 of the living world (alive-world; ReplicatedStorage.Art.Alive; Shared.LifeKit): look -> its frame (the",
    "-- box it is drawn over, studs x, up, z) and its meshes: each mesh's size and centre from the frame's middle,",
    "-- colour, material, transparency, maps (a baked texture set in its SurfaceAppearance), tint (the box's palette",
    "-- colour paints it) and triangles. Visual only: the box stays (Config.Life.alive). %d meshes in %d looks, %d"
    % (len(TRIS), len(LOOKS), total),
    "-- triangles.",
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "AliveArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)

if "--no-export" not in sys.argv and (MAPS or "--no-bake" in sys.argv):
    export = []
    for gname, g in GROUPS.items():
        pm = vkit.export_material(g, MAPS[gname]) if gname in MAPS else None
        for name, ob in g.meshes.items():
            cp = copy(ob)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            cp.data.materials.clear()
            if name in g.tex and pm:
                cp.data.materials.append(pm)
            else:
                rgb = INFO[name]["rgb"]
                cp.data.materials.append(kit.material(name + "Mat", rgb))
            export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(kit.ROOT, "export", "Alive.fbx"), use_selection=True,
        apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        path_mode="COPY", embed_textures=True)
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    import alive_preview  # noqa: E402

    alive_preview.run(GROUPS, LOOKS, FRAMES, INFO, MAPS, fast=FAST)
