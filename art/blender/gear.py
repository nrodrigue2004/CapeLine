# gear.py: the gear styles' looks as meshes (2026-11-19, in place of LookService's blocks, balls, wedges and
# cylinders): every gear shape of the 7 worn slots (head 6, chest 4, hands 4, legs 3, feet 3, back 4, belt 3), the
# 5 Epic set looks on their 4 set slots (head, chest, hands, feet) and the gilded Legendary look of each slot. 54
# looks. Nothing here is a face, hair, facial hair or eyes (those always come from the Roblox catalog): visors and
# masks sit over the face with eye holes, and a full helm hides the catalog hair instead of clipping through it.
# Fitted to Roblox's own blocky R15 body (Config.Creator.robloxBody): the classic rounded head (1.2 studs, centre
# 4.61), the 2 x 1.6 x 1 upper torso, the 2 x 0.4 x 1 lower torso, 1 x 0.3 x 1 hands and feet; a shin piece fits
# the lower leg's knee-to-ankle span (0.85 here), which LookService reads from the leg's own rig attachments, since
# Roblox's lower leg box (1.19 tall) overlaps the knee and ankle. kit.py axes: +y the front, the hero's left is -x.
# Colour roles (LookService colours each MeshPart): trim (the style's own colour: its tint, the set's power colour,
# or gold when gilded), dark (the dark base), glow (Neon in the trim colour), steel and gold (fixed metals).
# Every textured mesh of a slot shares one baked texture set (an atlas: colour with alpha where the part colour
# shows through, AlphaMode Overlay, so one mesh takes any style's tint; normal, roughness and metalness) from region
# ids, ambient occlusion and position (fine grain, brushed metal, cloth weave). Glow meshes are plain Neon.
# Output: art/export/Gear.fbx (textures embedded; uploaded as a Model and pulled into art/models/Gear.rbxm,
# ReplicatedStorage.Art.Gear), art/export/gear/*.png (the 7 texture sets), src/config/GearArt.luau (LookService's
# fit) and the previews art/preview/gear.png (whole outfits, front and back) and gear_<slot>.png (every look).
# Run: python art/blender/gear.py [--quick] [--only key,key] [--nopreview]   (the `bpy` module, Blender 5.0, nice)
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import PI, ring, rbox, ball, rod, joined, outline, strip, cone  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
import vkit  # noqa: E402

QUICK = "--quick" in sys.argv
NOPREVIEW = "--nopreview" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2100  # triangles a look (both sides of a pair together)
RES = 1024  # a slot's atlas (colour and normal; roughness and metalness at half)
OUT = os.path.join(kit.ROOT, "export", "gear")
HZ = 4.61  # the head's centre
TZ = 3.2  # the upper torso's centre
WZ = 2.2  # the lower torso's centre
SLOTS = ("head", "chest", "hands", "legs", "feet", "back", "belt")
SETS = ("Stormcaller", "Rimeguard", "Ironclad", "Orbitwear", "Edgewalker")
SET_SLOTS = ("head", "chest", "hands", "feet")
ROLES = ("trim", "dark", "glow", "steel", "gold")
PATS = ("plate", "cloth", "metal", "gold")
FIXED = {"dark": (34, 38, 52), "steel": (175, 180, 192), "gold": (255, 200, 60)}
SET_COLOR = {"Stormcaller": (120, 210, 255), "Rimeguard": (190, 235, 255), "Ironclad": (255, 150, 60),
             "Orbitwear": (190, 120, 255), "Edgewalker": (255, 70, 90)}
GILD = (255, 200, 60)
# each shape's preview colour: its first loot style's own colour in Config.Gear
SHAPE_COLOR = {"visor": (60, 70, 90), "cap": (40, 90, 160), "mask": (30, 30, 36), "fin": (200, 60, 60),
               "horns": (240, 200, 70), "halo": (255, 240, 160), "vest": (80, 90, 110), "plate": (50, 110, 200),
               "harness": (255, 200, 60), "core": (120, 220, 255), "wraps": (200, 200, 210),
               "gauntlet": (70, 70, 80), "spikes": (180, 60, 60), "coil": (120, 210, 255),
               "shins": (70, 80, 100), "stripes": (230, 70, 70), "greaves": (120, 130, 150),
               "boots": (40, 40, 48), "jets": (255, 140, 40), "wings": (240, 240, 250), "cape": (200, 40, 50),
               "longcape": (40, 60, 160), "jetpack": (90, 90, 100), "lightwings": (255, 230, 140),
               "belt": (210, 170, 60), "buckle": (230, 230, 240), "sash": (170, 90, 240)}
# the reference boxes the fit is written against (LookService scales a piece with its body part's own box; a shin
# piece with the knee-to-ankle span)
REF = {"head": (1.2, 1.2, 1.2), "torso": (2.0, 1.6, 1.0), "waist": (2.0, 0.4, 1.0), "lhand": (1.0, 0.3, 1.0),
       "rhand": (1.0, 0.3, 1.0), "lshin": (1.0, 0.85, 1.0), "rshin": (1.0, 0.85, 1.0), "lfoot": (1.0, 0.3, 1.0),
       "rfoot": (1.0, 0.3, 1.0)}

kit.reset()


class GP:
    """One mesh of a look: the object, the body part role it is welded to, its colour role and texture pattern."""

    def __init__(self, ob, at, role, pat="plate", alpha=0.0):
        assert at in REF, at
        assert role in ROLES, role
        assert pat in PATS, pat
        self.ob, self.at, self.role, self.pat, self.alpha = ob, at, role, pat, alpha
        self.glow = role == "glow"
        self.mat = None


LOOKS = {}  # key -> (slot, fn, hides hair, preview trim colour)


def look(key, hair=True, color=None):
    slot = key.split(":")[0]
    shape = key.split(":")[1]
    if color is None:
        if shape == "set":
            color = SET_COLOR[key.split(":")[2]]
        elif shape == "gilded":
            color = GILD
        else:
            color = SHAPE_COLOR[shape]

    def reg(fn):
        LOOKS[key] = (slot, fn, hair, color)
        return fn
    return reg


def P(ob, role, at, pat="plate", alpha=0.0):
    wear.bake(ob)
    return GP(ob, at, role, pat, alpha)


MIRROR = {"lhand": "rhand", "lshin": "rshin", "lfoot": "rfoot"}


def LR(ob, role, at, pat="plate", alpha=0.0):
    """A piece built on the left body part and its mirror on the right."""
    wear.bake(ob)
    kit.apply_all(ob)
    short = ob.name.split(".")[0]
    ob.name = short + "L"
    r = kit.mirror_x(ob, short + "R")
    return [GP(ob, at, role, pat, alpha), GP(r, MIRROR[at], role, pat, alpha)]


def hring(name, rows, **kw):
    """A surface round the head (the classic head's rounded square, power 2.25): rows [(z, r)]."""
    return ring(name, [(z, r, r) for z, r in rows], power=2.25, **kw)


def hdome(name, z0, z1, r, top, hole=None, thick=0.05, na=32):
    return ring(name, wear.dome_rows(z0, z1, r, r, top=top, n=5), power=2.25, na=na, hole=hole, thick=thick)


def face_open(a_max, z_top):
    return lambda a, z: abs(a) < a_max and z < z_top


def eye_holes(z=4.7, x=0.22, w=0.16, h=0.085, r=0.62):
    ax = math.asin(min(0.99, x / r))
    aw = w / r
    return lambda a, zz: abs(abs(a) - ax) < aw and abs(zz - z) < h


def twrap(name, z0, z1, rx=1.04, ry=0.545, power=14, a0=-PI, a1=PI, thick=0.05, hole=None, na=40):
    """A band round the upper or lower torso (the body's 2 x 1 box) from z0 to z1."""
    return ring(name, [(z0, rx, ry), ((z0 + z1) / 2, rx + 0.006, ry + 0.006), (z1, rx, ry)], power=power, na=na,
                a0=a0, a1=a1, thick=thick, hole=hole)


def lwrap(name, cx, rows, power=14, a0=-PI, a1=PI, thick=0.045, na=24, hole=None):
    """A band round a limb (the 1 x 1 box) centred on x = cx: rows [(z, r)]."""
    return ring(name, [(z, r, r) for z, r in rows], power=power, cx=cx, na=na, a0=a0, a1=a1, thick=thick,
                hole=hole)


def bolt_pts(s=1.0):
    """A lightning bolt outline (u across, v up), about 0.5 x 1.0 at s = 1."""
    pts = [(0.12, 0.5), (-0.2, 0.02), (0.02, 0.02), (-0.14, -0.5), (0.22, 0.08), (0.0, 0.08), (0.18, 0.5)]
    return [(u * s, v * s) for u, v in pts]


def blade_pts(length, width, back=0.25):
    """A swept blade outline pointing +u: a long edge, a hooked tip and a notched back."""
    return [(0.0, -width * 0.5), (length * 0.7, -width * 0.45), (length, 0.0), (length * 0.8, width * 0.35),
            (length * back, width * 0.5), (0.0, width * 0.3)]


def feather_pts(length, width, n=3):
    """A wing of n stepped feathers along +u (v up)."""
    pts = [(0.0, 0.0)]
    for k in range(n):
        t0 = k / n
        t1 = (k + 1) / n
        pts.append((length * (t0 + (t1 - t0) * 0.55), width * (0.35 + 0.65 * (1 - t0))))
        pts.append((length * t1, width * (0.2 + 0.6 * (1 - t1))))
    pts.append((length * 0.9, -width * 0.12))
    pts.append((length * 0.2, -width * 0.18))
    return pts


def spike_ring(name, n, r, z, h, base, cx=0.0, cy=0.0, tilt=0.35, a0=0.0, a1=2 * PI, power=2.25):
    """n cones standing round a ring (a crown's points, ice crystals), leaning out by `tilt`."""
    obs = []
    for k in range(n):
        a = a0 + (a1 - a0) * (k + (0.5 if a1 - a0 < 2 * PI - 1e-6 else 0.0)) / (n if a1 - a0 >= 2 * PI - 1e-6
                                                                               else n)
        x, y = wear.spt(a, r, r, power)
        d = Vector((x, y, 0)).normalized() * tilt + Vector((0, 0, 1))
        obs.append(cone("c", base, 0.0, h, (cx + x, cy + y, z), segs=6, axis=d))
    return joined(name, obs, 30)


def rivets(name, pts, r=0.045, axis=(0, 1, 0)):
    obs = []
    for p in pts:
        obs.append(ball("r", r, p, scale=(1 if axis[0] == 0 else 0.5, 1 if axis[1] == 0 else 0.5,
                                         1 if axis[2] == 0 else 0.5), segs=8, rings=4))
    return joined(name, obs, 70)


def sheet(name, rows, nx=10, thick=0.04, wave=0.0, waves=3.0):
    """A cloth sheet (a cape): rows [(z, half width, y)] top to bottom; folds `wave` deep across it."""
    bm = bmesh.new()
    grid = []
    for j, (z, hw, y) in enumerate(rows):
        t = j / max(len(rows) - 1, 1)
        row = []
        for i in range(nx + 1):
            u = -1 + 2 * i / nx
            fold = -wave * t * (0.5 + 0.5 * math.cos(u * PI * waves))
            row.append(bm.verts.new((u * hw, y + fold - 0.04 * u * u, z)))
        grid.append(row)
    for j in range(len(rows) - 1):
        for i in range(nx):
            bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
    ob = kit._obj(name, bm)
    wear.solid(ob, thick, 0.0)
    kit.shade_auto(ob, 50)
    return ob


# ================================================================ head (the classic head: radius 0.6, z 4.02-5.2)
@look("head:visor")
def h_visor():
    lens = hring("Lens", [(4.6, 0.645), (4.71, 0.655), (4.82, 0.645)], a0=-1.2, a1=1.2, na=24, thick=0.03)
    top = hring("t", [(4.82, 0.655), (4.87, 0.655)], a0=-1.3, a1=1.3, na=26, thick=0.05)
    bot = hring("b", [(4.55, 0.65), (4.6, 0.65)], a0=-1.3, a1=1.3, na=26, thick=0.05)
    band = hring("k", [(4.66, 0.625), (4.76, 0.625)], a0=1.25, a1=2 * PI - 1.25, na=24, thick=0.04)
    pods = [ball("p", 0.13, (sx * 0.64, 0.05, 4.71), scale=(0.55, 1, 1), segs=10, rings=6) for sx in (-1, 1)]
    return [P(lens, "glow", "head"), P(joined("Frame", [top, bot, band], 40), "dark", "head"),
            P(joined("Pods", pods, 60), "trim", "head")]


@look("head:cap", hair=False)
def h_cap():
    crown = hdome("Crown", 4.86, 5.0, 0.665, 5.36, thick=0.05)
    band = hring("Band", [(4.84, 0.68), (4.97, 0.68)], na=32, thick=0.04)
    brim = outline("Brim", [(-0.55, 0.0), (-0.45, 0.28), (-0.2, 0.42), (0.2, 0.42), (0.45, 0.28), (0.55, 0.0)],
                   0.05, at=(0, 0.6, 4.88), axis="Z", bev=0.015)
    wear.turn(brim, (math.radians(-10), 0, 0), (0, 0.6, 4.88))
    badge = outline("Badge", wear.star_pts(0.13, 0.06), 0.04, at=(0, 0.66, 5.08), axis="Y")
    return [P(crown, "trim", "head"), P(joined("Peak", [band, brim], 40), "dark", "head"),
            P(badge, "steel", "head", "metal")]


@look("head:mask")
def h_mask():
    band = hring("Band", [(4.58, 0.62), (4.7, 0.628), (4.82, 0.62)], na=44, hole=eye_holes(), thick=0.035)
    knot = ball("Knot", 0.09, (0, -0.64, 4.7), scale=(1.2, 0.7, 1), segs=10, rings=6)
    tails = [strip("t", [(sx * 0.04, -0.64, 4.68), (sx * 0.14, -0.7, 4.5), (sx * 0.2, -0.74, 4.3)],
                   [0.1, 0.09, 0.06], up=(1, 0, 0), thick=0.025) for sx in (-1, 1)]
    return [P(band, "trim", "head", "cloth"), P(joined("Ties", [knot] + tails, 50), "dark", "head", "cloth")]


@look("head:fin", hair=False)
def h_fin():
    shell = hdome("Shell", 4.28, 4.95, 0.665, 5.42, hole=face_open(0.78, 4.9))
    brow = hring("Brow", [(4.86, 0.7), (4.97, 0.7)], a0=-1.0, a1=1.0, na=20, thick=0.05)
    crest = outline("Crest", [(0.35, 5.28), (0.05, 5.62), (-0.35, 5.78), (-0.72, 5.5), (-0.66, 5.05),
                              (-0.2, 5.36)], 0.12, at=(0, 0, 0), axis="X", bev=0.02)
    cheeks = [rbox("c", 0.08, 0.3, 0.42, at=(sx * 0.68, 0.32, 4.42), bev=0.03) for sx in (-1, 1)]
    return [P(shell, "trim", "head"), P(joined("Crest", [crest], 30), "dark", "head"),
            P(joined("Guards", [brow] + cheeks, 40), "steel", "head", "metal")]


@look("head:horns", hair=False)
def h_horns():
    helm = hdome("Helm", 4.4, 4.95, 0.66, 5.38, hole=face_open(0.82, 4.93))
    horns = []
    for sx in (-1, 1):
        horns.append(rod("h", [(sx * 0.5, 0.12, 5.05), (sx * 0.82, 0.18, 5.22), (sx * 1.02, 0.12, 5.55),
                               (sx * 0.98, 0.02, 5.9)], [0.15, 0.12, 0.07, 0.0], segs=8))
    brow = hring("Ridge", [(4.9, 0.69), (4.96, 0.71), (5.02, 0.69)], a0=-1.1, a1=1.1, na=22, thick=0.05)
    return [P(helm, "dark", "head"), P(joined("Horns", horns + [brow], 50), "trim", "head", "metal")]


@look("head:halo")
def h_halo():
    halo = kit.torus("Ring", 0.5, 0.055, at=(0, 0, 5.62), segs=36, csegs=8)
    kit.shade_auto(halo, 80)
    pts = spike_ring("Points", 8, 0.5, 5.62, 0.16, 0.045, tilt=0.15, power=2.0)
    return [P(halo, "glow", "head"), P(pts, "trim", "head", "metal")]


def set_helm(name, z0=4.28, a_max=0.78, z_top=4.9, r=0.665, top=5.4):
    return hdome(name, z0, 4.95, r, top, hole=face_open(a_max, z_top))


@look("head:set:Stormcaller", hair=False)
def hs_storm():
    shell = set_helm("Shell")
    visor = hring("Visor", [(4.64, 0.66), (4.8, 0.66)], a0=-0.95, a1=0.95, na=20, thick=0.03)
    bolts = [outline("b", bolt_pts(0.62), 0.07, at=(sx * 0.7, -0.05, 5.0), axis="X") for sx in (-1, 1)]
    for b, sx in zip(bolts, (-1, 1)):
        wear.turn(b, (math.radians(-25), 0, 0), (sx * 0.7, -0.05, 5.0))
    plates = hring("p", [(4.88, 0.705), (5.0, 0.705)], a0=-0.9, a1=0.9, na=18, thick=0.05)
    chin = hring("c", [(4.16, 0.64), (4.36, 0.66)], a0=-0.85, a1=0.85, na=18, thick=0.05)
    return [P(shell, "dark", "head"), P(joined("Plates", [plates, chin], 40), "trim", "head", "metal"),
            P(joined("Bolts", bolts + [visor], 40), "glow", "head")]


@look("head:set:Rimeguard", hair=False)
def hs_rime():
    shell = set_helm("Shell")
    crystals = spike_ring("Crystals", 7, 0.52, 5.2, 0.4, 0.09, tilt=0.55, a0=-1.6, a1=1.6)
    face = hring("Face", [(4.62, 0.655), (4.78, 0.66), (4.86, 0.655)], a0=-0.9, a1=0.9, na=20,
                 hole=eye_holes(z=4.72, w=0.13, h=0.05, r=0.66), thick=0.04)
    return [P(shell, "trim", "head", "metal"), P(crystals, "glow", "head"), P(face, "dark", "head")]


@look("head:set:Ironclad", hair=False)
def hs_iron():
    def slit(a, z):
        return abs(a) < 0.5 and 4.66 < z < 4.76 or (abs(a) < 0.07 and 4.3 < z < 4.76)
    bucket = ring("Bucket", [(4.02, 0.69, 0.69), (4.5, 0.7, 0.7), (5.05, 0.7, 0.7), (5.25, 0.62, 0.62),
                             (5.32, 0.4, 0.4), (5.34, 0.0, 0.0)], power=3.2, na=44, hole=slit, thick=0.06)
    glow = ring("Slit", [(4.3, 0.66, 0.66), (4.78, 0.66, 0.66)], power=3.2, na=12, a0=-0.55, a1=0.55, thick=0.02)
    pts = []
    for k in range(10):
        a = -PI + 2 * PI * (k + 0.5) / 10
        x, y = wear.spt(a, 0.745, 0.745, 3.2)
        pts.append((x, y, 4.95))
    riv = rivets("Rivets", pts, r=0.05)
    band = ring("b", [(4.88, 0.725, 0.725), (5.02, 0.725, 0.725)], power=3.2, na=44, thick=0.04)
    return [P(bucket, "trim", "head", "metal"), P(glow, "glow", "head"),
            P(joined("Studs", [riv, band], 50), "steel", "head", "metal")]


@look("head:set:Orbitwear", hair=False)
def hs_orbit():
    shell = set_helm("Shell", top=5.48)
    orbit = kit.torus("Orbit", 0.86, 0.035, at=(0, 0, 0), segs=28, csegs=5)
    orbit.data.transform(Matrix.Translation((0, 0, 4.95)) @ Matrix.Rotation(math.radians(18), 4, "X")
                         @ Matrix.Rotation(math.radians(-10), 4, "Y"))
    kit.shade_auto(orbit, 80)
    visor = hring("v", [(4.64, 0.665), (4.8, 0.665)], a0=-0.9, a1=0.9, na=18, thick=0.03)
    moon = ball("m", 0.09, (0.82, 0.2, 5.12), segs=10, rings=6)
    ant = rod("a", [(0.45, -0.3, 5.3), (0.55, -0.4, 5.62)], [0.03, 0.025], segs=6)
    tip = ball("t", 0.06, (0.55, -0.4, 5.66), segs=8, rings=4)
    ears = [kit.cyl("e", 0.16, 0.16, 0.08, at=(sx * 0.69, 0, 4.7), segs=14, axis="X") for sx in (-1, 1)]
    return [P(shell, "trim", "head"), P(joined("Orbit", [orbit, visor, moon, tip], 60), "glow", "head"),
            P(joined("Gear", [ant] + ears, 40), "steel", "head", "metal")]


@look("head:set:Edgewalker", hair=False)
def hs_edge():
    shell = set_helm("Shell", a_max=0.72, z_top=4.86)
    blades = []
    for sx in (-1, 1):
        b = outline("b", blade_pts(0.95, 0.26), 0.05, at=(sx * 0.2, 0, 0), axis="X")
        # swept back over the crown from the brow
        b.data.transform(Matrix.Translation((sx * 0.2, 0.5, 5.12)) @ Matrix.Rotation(math.radians(200), 4, "X")
                         @ Matrix.Translation((-sx * 0.2, 0, 0)))
        blades.append(b)
    guard = hring("Guard", [(4.1, 0.63), (4.3, 0.665), (4.44, 0.66)], a0=-0.85, a1=0.85, na=18, thick=0.05)
    band = hring("Band", [(4.86, 0.69), (4.94, 0.69)], a0=-1.0, a1=1.0, na=20, thick=0.03)
    return [P(shell, "dark", "head"), P(joined("Blades", blades + [guard], 30), "trim", "head", "metal"),
            P(band, "glow", "head")]


@look("head:gilded", hair=False)
def h_gilded():
    shell = hdome("Shell", 4.3, 4.92, 0.66, 5.36, hole=face_open(0.8, 4.88))
    band = hring("b", [(4.84, 0.7), (5.0, 0.7)], na=32, thick=0.05)
    points = spike_ring("p", 9, 0.69, 4.98, 0.3, 0.075, tilt=0.12, power=2.25)
    wings = [outline("w", feather_pts(0.45, 0.22, 3), 0.04, at=(sx * 0.7, -0.05, 4.82), axis="X")
             for sx in (-1, 1)]
    for w in wings:
        for v in w.data.vertices:
            v.co.y = -0.05 - (v.co.y + 0.05)  # sweep the feathers back
    gem = ball("Gem", 0.1, (0, 0.71, 4.94), scale=(1, 0.5, 1.2), segs=10, rings=6)
    return [P(shell, "dark", "head"), P(joined("Crown", [band, points] + wings, 40), "trim", "head", "gold"),
            P(gem, "glow", "head")]


# ================================================================ chest (the upper torso: x +-1, y +-0.5, z 2.4-4.0)
def straps_over(x, w=0.26, t=0.06, z=4.02):
    return rbox("s", w, 1.12, t, at=(x, 0, z), bev=0.02)


@look("chest:vest")
def c_vest():
    front = rbox("f", 1.7, 0.1, 1.32, at=(0, 0.55, 3.18), bev=0.05)
    back = rbox("b", 1.7, 0.1, 1.32, at=(0, -0.55, 3.18), bev=0.05)
    side = twrap("w", 2.5, 2.72, rx=1.035, ry=0.56, thick=0.04)
    sh = [straps_over(sx * 0.6, w=0.4, t=0.08) for sx in (-1, 1)]
    pouches = [rbox("p", 0.4, 0.14, 0.32, at=(x, 0.66, 2.72), bev=0.04) for x in (-0.52, 0.0, 0.52)]
    pouches += [rbox("q", 0.34, 0.1, 0.18, at=(sx * 0.5, 0.63, 3.62), bev=0.03) for sx in (-1, 1)]
    clips = [rbox("c", 0.16, 0.06, 0.1, at=(x, 0.74, 2.84), bev=0.015) for x in (-0.52, 0.0, 0.52)]
    return [P(joined("Panels", [front, back, side] + sh, 35), "trim", "torso", "cloth"),
            P(joined("Pouches", pouches, 35), "dark", "torso", "cloth"),
            P(joined("Clips", clips, 35), "steel", "torso", "metal")]


@look("chest:plate")
def c_plate():
    plate = ring("Plate", [(2.7, 0.88, 0.62), (3.1, 0.94, 0.66), (3.6, 0.95, 0.66), (3.92, 0.88, 0.6)],
                 power=5, na=30, a0=-1.25, a1=1.25, thick=0.06)
    keel = rbox("k", 0.1, 0.1, 1.0, at=(0, 0.68, 3.3), bev=0.04)
    straps = [rbox("s", 0.12, 1.12, 0.22, at=(sx * 0.96, 0, 3.3), bev=0.02) for sx in (-1, 1)]
    sh = [straps_over(sx * 0.62) for sx in (-1, 1)]
    gem = ball("Gem", 0.2, (0, 0.72, 3.5), scale=(1, 0.45, 1), segs=14, rings=8)
    star = outline("St", wear.star_pts(0.3, 0.13), 0.03, at=(0, 0.69, 3.5), axis="Y")
    return [P(joined("Plate", [plate, keel], 35), "trim", "torso", "metal"),
            P(joined("Straps", straps + sh + [star], 35), "dark", "torso"), P(gem, "glow", "torso")]


@look("chest:harness")
def c_harness():
    st = []
    for sx in (-1, 1):
        st.append(rbox("f", 0.26, 0.07, 1.58, at=(sx * 0.5, 0.54, 3.2), bev=0.02))
        st.append(rbox("b", 0.26, 0.07, 1.58, at=(sx * 0.5, -0.54, 3.2), bev=0.02))
        st.append(straps_over(sx * 0.5))
    st.append(twrap("w", 3.36, 3.56, rx=1.035, ry=0.55, thick=0.05))
    ring_ = kit.torus("r", 0.15, 0.045, at=(0, 0.6, 3.46), segs=16, csegs=6, axis="Y")
    bk = [rbox("k", 0.32, 0.06, 0.16, at=(sx * 0.5, 0.6, 2.62), bev=0.02) for sx in (-1, 1)]
    bolt = outline("Bolt", bolt_pts(0.42), 0.04, at=(0, 0.6, 3.0), axis="Y")
    return [P(joined("Straps", st, 35), "trim", "torso", "cloth"),
            P(joined("Rings", [ring_] + bk, 50), "steel", "torso", "metal"), P(bolt, "glow", "torso")]


@look("chest:core")
def c_core():
    plate = rbox("p", 1.5, 0.12, 1.1, at=(0, 0.56, 3.32), bev=0.06)
    collar = twrap("c", 3.82, 3.98, rx=1.03, ry=0.545, thick=0.05)
    rim = kit.torus("Rim", 0.27, 0.065, at=(0, 0.64, 3.42), segs=24, csegs=8, axis="Y")
    kit.shade_auto(rim, 60)
    core = kit.cyl("Core", 0.21, 0.21, 0.06, at=(0, 0.65, 3.42), segs=20, axis="Y")
    lines = [rod("l", [(sx * 0.3, 0.63, 3.52), (sx * 0.55, 0.63, 3.72), (sx * 0.7, 0.63, 3.72)], 0.025, segs=5)
             for sx in (-1, 1)]
    return [P(joined("Plate", [plate, collar], 35), "dark", "torso", "metal"), P(rim, "trim", "torso", "metal"),
            P(joined("Core", [core] + lines, 50), "glow", "torso")]


@look("chest:set:Stormcaller")
def cs_storm():
    plate = rbox("p", 1.6, 0.12, 1.3, at=(0, 0.56, 3.22), bev=0.06)
    pads = [rbox("s", 0.6, 1.14, 0.16, at=(sx * 0.7, 0, 4.03), bev=0.05) for sx in (-1, 1)]
    bolt = outline("Bolt", bolt_pts(1.0), 0.05, at=(0, 0.63, 3.25), axis="Y")
    stripes = [rbox("t", 0.08, 0.04, 1.2, at=(sx * 0.68, 0.63, 3.22), bev=0.01) for sx in (-1, 1)]
    return [P(plate, "dark", "torso", "metal"), P(joined("Pads", pads + stripes, 35), "trim", "torso", "metal"),
            P(bolt, "glow", "torso")]


@look("chest:set:Rimeguard")
def cs_rime():
    plate = ring("Plate", [(2.62, 0.9, 0.62), (3.2, 0.96, 0.66), (3.92, 0.9, 0.6)], power=5, na=28, a0=-1.25,
                 a1=1.25, thick=0.06)
    facets = outline("f", [(-0.5, 0.0), (0.0, 0.5), (0.5, 0.0), (0.0, -0.6)], 0.05, at=(0, 0.69, 3.3), axis="Y")
    crys = []
    for sx in (-1, 1):
        for dx, h, tilt in ((0.0, 0.42, 0.25), (0.22, 0.3, 0.6), (-0.2, 0.28, 0.5)):
            d = Vector((sx * tilt, 0.1, 1.0))
            crys.append(cone("c", 0.1, 0.0, h, (sx * (0.65 + dx), 0.05, 3.98), segs=5, axis=d))
    collar = twrap("Collar", 3.8, 3.98, rx=1.03, ry=0.545, thick=0.05)
    return [P(joined("Plate", [plate, facets], 30), "trim", "torso", "metal"),
            P(joined("Crystals", crys, 25), "glow", "torso"), P(collar, "dark", "torso")]


@look("chest:set:Ironclad")
def cs_iron():
    plate = ring("Plate", [(2.55, 0.9, 0.64), (3.0, 1.0, 0.7), (3.7, 1.0, 0.7), (3.98, 0.9, 0.62)], power=4,
                 na=30, a0=-1.3, a1=1.3, thick=0.1)
    backp = rbox("b", 1.7, 0.12, 1.3, at=(0, -0.57, 3.2), bev=0.05)
    pts = [(x, 0.75, z) for x in (-0.7, 0.7) for z in (2.75, 3.2, 3.65)] + [(0, 0.76, 3.82)]
    riv = rivets("Rivets", pts, r=0.055)
    collar = ring("Collar", [(3.92, 0.78, 0.5), (4.12, 0.72, 0.46)], power=4, na=28, thick=0.07)
    return [P(joined("Plate", [plate, backp], 35), "trim", "torso", "metal"), P(riv, "steel", "torso", "metal"),
            P(collar, "dark", "torso", "metal")]


@look("chest:set:Orbitwear")
def cs_orbit():
    plate = rbox("p", 1.55, 0.12, 1.2, at=(0, 0.56, 3.26), bev=0.08)
    sides = [rbox("s", 0.22, 1.1, 1.3, at=(sx * 0.9, 0, 3.22), bev=0.06) for sx in (-1, 1)]
    orbit = kit.torus("o", 0.42, 0.03, at=(0, 0, 0), segs=36, csegs=6)
    orbit.data.transform(Matrix.Translation((0, 0.66, 3.36)) @ Matrix.Rotation(math.radians(90), 4, "X")
                         @ Matrix.Scale(1.0, 4, (1, 0, 0)) @ Matrix.Rotation(math.radians(25), 4, "Y"))
    orbit2 = kit.torus("o2", 0.42, 0.03, at=(0, 0, 0), segs=36, csegs=6)
    orbit2.data.transform(Matrix.Translation((0, 0.66, 3.36)) @ Matrix.Rotation(math.radians(90), 4, "X")
                          @ Matrix.Rotation(math.radians(-25), 4, "Y"))
    core = ball("c", 0.14, (0, 0.68, 3.36), scale=(1, 0.6, 1), segs=12, rings=6)
    return [P(plate, "dark", "torso"), P(joined("Sides", sides, 35), "trim", "torso"),
            P(joined("Orbit", [orbit, orbit2, core], 60), "glow", "torso")]


@look("chest:set:Edgewalker")
def cs_edge():
    # a sash wrapping the torso from the right shoulder to the left hip
    pts = []
    for k in range(41):
        a = -PI + 2 * PI * k / 40
        x, y = wear.spt(a, 1.045, 0.555, 14)
        pts.append((x, y, TZ + 0.0 - 0.42 * x))
    sash = strip("Sash", pts, 0.34, thick=0.04)
    blades = []
    for sx in (-1, 1):
        b = outline("b", blade_pts(1.5, 0.22), 0.05, at=(0, 0, 0), axis="Y")
        b.data.transform(Matrix.Translation((0, -0.6, 3.25)) @ Matrix.Rotation(math.radians(sx * 50 - 90), 4, "Y")
                         @ Matrix.Translation((-0.75, 0, 0)))
        blades.append(b)
    guard = rbox("g", 0.6, 0.1, 0.5, at=(-0.45, 0.57, 3.55), bev=0.04)
    clasp = ball("Clasp", 0.11, (0.12, 0.62, 3.16), scale=(1, 0.5, 1), segs=10, rings=6)
    return [P(sash, "dark", "torso", "cloth"), P(joined("Blades", blades + [guard], 30), "trim", "torso", "metal"),
            P(clasp, "glow", "torso")]


@look("chest:gilded")
def c_gilded():
    under = ring("Under", [(2.62, 0.9, 0.6), (3.2, 0.95, 0.63), (3.94, 0.9, 0.58)], power=5, na=28, a0=-1.25,
                 a1=1.25, thick=0.05)
    plate = ring("p", [(2.95, 0.84, 0.66), (3.4, 0.88, 0.69), (3.92, 0.8, 0.63)], power=5, na=26, a0=-1.1,
                 a1=1.1, thick=0.04)
    scroll = []
    for sx in (-1, 1):
        scroll.append(rod("s", [(sx * 0.15, 0.71, 3.05), (sx * 0.45, 0.71, 3.15), (sx * 0.6, 0.7, 3.45),
                                (sx * 0.45, 0.7, 3.7)], 0.03, segs=6))
    sh = [rbox("e", 0.62, 1.14, 0.12, at=(sx * 0.68, 0, 4.03), bev=0.05) for sx in (-1, 1)]
    gem = ball("Gem", 0.16, (0, 0.74, 3.42), scale=(0.9, 0.45, 1.2), segs=12, rings=6)
    return [P(under, "dark", "torso"), P(joined("Gold", [plate] + scroll + sh, 35), "trim", "torso", "gold"),
            P(gem, "glow", "torso")]


# ================================================================ hands (the left hand: x -2..-1, z 2.0-2.3)
HX = -1.5


def glove(name, z0=1.97, z1=2.33, r=0.56):
    return ring(name, [(z0 - 0.03, 0.0, 0.0), (z0 - 0.03, r - 0.06, r - 0.06), (z0, r, r), (z1, r, r)],
                power=14, cx=HX, na=24, thick=0.04)


def cuff(name, z0=2.3, z1=2.6, r0=0.575, r1=0.62):
    return lwrap(name, HX, [(z0, r0), (z1, r1)], thick=0.05)


@look("hands:wraps")
def g_wraps():
    bands = [lwrap("b", HX, [(z, 0.535), (z + 0.075, 0.535)], thick=0.035) for z in (2.0, 2.11, 2.22)]
    bands.append(lwrap("w", HX, [(2.36, 0.54), (2.48, 0.54)], thick=0.035))
    tape = rbox("t", 0.12, 0.06, 0.34, at=(HX - 0.3, 0.54, 2.15), bev=0.01)
    return LR(joined("Wraps", bands, 40), "trim", "lhand", "cloth") + LR(tape, "dark", "lhand", "cloth")


@look("hands:gauntlet")
def g_gauntlet():
    knuck = rbox("k", 0.86, 0.1, 0.18, at=(HX, 0.58, 2.1), bev=0.04)
    return (LR(glove("Glove"), "dark", "lhand") + LR(joined("Cuff", [cuff("c"), knuck], 40), "trim", "lhand",
                                                    "metal"))


@look("hands:spikes")
def g_spikes():
    spikes = [cone("s", 0.07, 0.0, 0.24, (HX + dx, 0.58, 2.12), segs=6, axis=(0, 1, 0)) for dx in (-0.25, 0, 0.25)]
    plate = rbox("k", 0.86, 0.08, 0.2, at=(HX, 0.57, 2.12), bev=0.03)
    return (LR(glove("Glove"), "dark", "lhand") + LR(joined("Cuff", [cuff("c"), plate], 40), "trim", "lhand",
                                                    "metal") + LR(joined("Spikes", spikes, 30), "steel", "lhand",
                                                                  "metal"))


@look("hands:coil")
def g_coil():
    base = cuff("Cuff", 2.28, 2.7, 0.56, 0.58)
    coils = [kit.torus("c", 0.6, 0.04, at=(HX, 0, z), segs=18, csegs=5) for z in (2.38, 2.5, 2.62)]
    return (LR(glove("Glove"), "trim", "lhand") + LR(base, "dark", "lhand", "metal")
            + LR(joined("Coils", coils, 70), "glow", "lhand"))


@look("hands:set:Stormcaller")
def gs_storm():
    fins = []
    for dz in (0.0, 0.2):
        b = outline("f", bolt_pts(0.32), 0.05, at=(HX - 0.6, 0.0, 2.3 + dz), axis="X")
        fins.append(b)
    return (LR(glove("Glove"), "dark", "lhand") + LR(cuff("Cuff", 2.3, 2.66), "trim", "lhand", "metal")
            + LR(joined("Bolts", fins, 30), "glow", "lhand"))


@look("hands:set:Rimeguard")
def gs_rime():
    shards = []
    for k, (dy, h) in enumerate(((-0.25, 0.3), (0.0, 0.42), (0.25, 0.3))):
        shards.append(cone("s", 0.08, 0.0, h, (HX - 0.6, dy, 2.42), segs=5, axis=(-0.8, 0, 0.6)))
    return (LR(glove("Glove"), "trim", "lhand", "metal") + LR(cuff("Cuff", 2.3, 2.62), "dark", "lhand")
            + LR(joined("Shards", shards, 25), "glow", "lhand"))


@look("hands:set:Ironclad")
def gs_iron():
    big = ring("Glove", [(1.92, 0.0, 0.0), (1.92, 0.56, 0.56), (1.96, 0.62, 0.62), (2.34, 0.62, 0.62)],
               power=10, cx=HX, na=32, thick=0.06)
    plate = rbox("k", 0.96, 0.12, 0.24, at=(HX, 0.66, 2.12), bev=0.04)
    riv = rivets("r", [(HX + dx, 0.73, 2.12) for dx in (-0.3, 0, 0.3)], r=0.045)
    return (LR(big, "trim", "lhand", "metal") + LR(joined("Knuckles", [plate, riv], 50), "steel", "lhand", "metal")
            + LR(cuff("Cuff", 2.32, 2.66, 0.6, 0.66), "dark", "lhand", "metal"))


@look("hands:set:Orbitwear")
def gs_orbit():
    orbit = kit.torus("o", 0.68, 0.03, at=(0, 0, 0), segs=20, csegs=5)
    orbit.data.transform(Matrix.Translation((HX, 0, 2.46)) @ Matrix.Rotation(math.radians(20), 4, "X"))
    bead = ball("b", 0.07, (HX + 0.68, 0, 2.46), segs=8, rings=4)
    return (LR(glove("Glove"), "dark", "lhand") + LR(cuff("Cuff", 2.3, 2.58), "trim", "lhand")
            + LR(joined("Orbit", [orbit, bead], 70), "glow", "lhand"))


@look("hands:set:Edgewalker")
def gs_edge():
    blade = outline("b", blade_pts(0.9, 0.2), 0.05, at=(0, 0, 0), axis="X")
    blade.data.transform(Matrix.Translation((HX - 0.62, 0.0, 2.2)) @ Matrix.Rotation(math.radians(90), 4, "X"))
    band = lwrap("w", HX, [(2.42, 0.6), (2.48, 0.6)], thick=0.03)
    return (LR(glove("Glove"), "dark", "lhand") + LR(joined("Blade", [blade, cuff("c", 2.3, 2.38, 0.6, 0.6)], 30),
                                                    "trim", "lhand", "metal") + LR(band, "glow", "lhand"))


@look("hands:gilded")
def g_gilded():
    ridge = lwrap("r", HX, [(2.5, 0.64), (2.56, 0.66), (2.62, 0.64)], thick=0.03)
    gem = ball("Gem", 0.1, (HX, 0.6, 2.15), scale=(1, 0.5, 1), segs=10, rings=6)
    return (LR(glove("Glove"), "dark", "lhand") + LR(joined("Cuff", [cuff("c", 2.3, 2.6), ridge], 40), "trim",
                                                    "lhand", "gold") + LR(gem, "glow", "lhand"))


# ================================================================ legs (the left lower leg: x -1..0, z 0.3-1.15)
LX = -0.5


@look("legs:shins")
def l_shins():
    guard = ring("Guard", [(0.42, 0.565, 0.565), (0.78, 0.6, 0.6), (1.08, 0.57, 0.57)], power=8, cx=LX, na=24,
                 a0=-1.0, a1=1.0, thick=0.05)
    knee = ball("k", 0.22, (LX, 0.56, 1.1), scale=(1.1, 0.55, 0.9), segs=12, rings=6)
    straps = [lwrap("s", LX, [(z, 0.535), (z + 0.07, 0.535)], thick=0.03) for z in (0.52, 0.92)]
    return LR(joined("Guard", [guard, knee], 40), "trim", "lshin", "metal") + LR(joined("Straps", straps, 40),
                                                                                "dark", "lshin", "cloth")


@look("legs:stripes")
def l_stripes():
    # two racing stripes down the outer side and one down the front, a band under the knee
    st = [rbox("s", 0.04, 0.1, 0.78, at=(LX - 0.515, dy, 0.73), bev=0.012) for dy in (-0.14, 0.14)]
    st.append(rbox("f", 0.12, 0.04, 0.78, at=(LX, 0.515, 0.73), bev=0.012))
    band = lwrap("b", LX, [(1.0, 0.54), (1.1, 0.54)], thick=0.03)
    return LR(joined("Stripes", st, 40), "trim", "lshin", "cloth") + LR(band, "dark", "lshin", "cloth")


@look("legs:greaves")
def l_greaves():
    greave = lwrap("Greave", LX, [(0.36, 0.56), (0.75, 0.58), (1.12, 0.565)], thick=0.05, na=24)
    ridge = rbox("r", 0.12, 0.08, 0.7, at=(LX, 0.6, 0.74), bev=0.03)
    knee = ball("k", 0.24, (LX, 0.57, 1.12), scale=(1.1, 0.55, 0.85), segs=12, rings=6)
    return LR(greave, "dark", "lshin", "metal") + LR(joined("Plates", [ridge, knee], 40), "trim", "lshin", "metal")


@look("legs:gilded")
def l_gilded():
    greave = lwrap("Greave", LX, [(0.36, 0.56), (0.75, 0.58), (1.12, 0.565)], thick=0.05, na=24)
    plate = ring("p", [(0.42, 0.6, 0.6), (1.0, 0.615, 0.615)], power=8, cx=LX, na=20, a0=-0.85, a1=0.85, thick=0.04)
    wing = outline("w", feather_pts(0.35, 0.2, 2), 0.035, at=(LX - 0.58, 0.0, 1.0), axis="X")
    for v in wing.data.vertices:
        v.co.y = -v.co.y
    gem = ball("Gem", 0.09, (LX, 0.66, 1.08), scale=(1, 0.5, 1), segs=10, rings=6)
    return (LR(greave, "dark", "lshin", "metal") + LR(joined("Gold", [plate, wing], 40), "trim", "lshin", "gold")
            + LR(gem, "glow", "lshin"))


# ================================================================ feet (the left foot: x -1..0, z 0-0.3)
FX = -0.5


def boot(name, top=0.56):
    return ring(name, [(-0.03, 0.0, 0.0), (-0.03, 0.5, 0.52), (0.0, 0.555, 0.575), (0.3, 0.555, 0.575),
                       (0.36, 0.55, 0.55), (top, 0.565, 0.565)], power=14, cx=FX, na=24, thick=0.045)


def sole(name):
    return rbox(name, 1.14, 1.18, 0.08, at=(FX, 0.01, -0.02), bev=0.03)


@look("feet:boots")
def f_boots():
    toe = rbox("t", 1.08, 0.12, 0.2, at=(FX, 0.56, 0.12), bev=0.04)
    return LR(boot("Boot"), "trim", "lfoot", "cloth") + LR(joined("Sole", [sole("s"), toe], 40), "dark", "lfoot")


@look("feet:jets")
def f_jets():
    jets = [kit.cyl("j", 0.15, 0.18, 0.4, at=(FX + dx, -0.66, 0.3), segs=12) for dx in (-0.22, 0.22)]
    noz = [kit.cyl("n", 0.13, 0.13, 0.04, at=(FX + dx, -0.66, 0.09), segs=12) for dx in (-0.22, 0.22)]
    return (LR(joined("Boot", [boot("b"), sole("s")], 40), "dark", "lfoot") + LR(joined("Jets", jets, 40), "trim",
                                                                                 "lfoot", "metal")
            + LR(joined("Glow", noz, 40), "glow", "lfoot"))


@look("feet:wings")
def f_wings():
    wing = outline("w", feather_pts(0.55, 0.32, 3), 0.04, at=(FX - 0.6, 0.0, 0.42), axis="X")
    for v in wing.data.vertices:
        v.co.y = -v.co.y  # the feathers point back
    return (LR(boot("Boot"), "trim", "lfoot") + LR(sole("Sole"), "dark", "lfoot")
            + LR(wing, "steel", "lfoot", "metal"))


@look("feet:set:Stormcaller")
def fs_storm():
    bolt = outline("b", bolt_pts(0.42), 0.05, at=(FX - 0.6, 0.0, 0.3), axis="X")
    wear.turn(bolt, (0, 0, 0), (0, 0, 0))
    return (LR(boot("Boot"), "dark", "lfoot") + LR(sole("Sole"), "trim", "lfoot", "metal")
            + LR(bolt, "glow", "lfoot"))


@look("feet:set:Rimeguard")
def fs_rime():
    shards = [cone("s", 0.08, 0.0, h, (FX - 0.58, dy, 0.42), segs=5, axis=(-0.6, -0.2, 0.8))
              for dy, h in ((-0.2, 0.26), (0.05, 0.36), (0.28, 0.24))]
    return (LR(boot("Boot"), "trim", "lfoot", "metal") + LR(sole("Sole"), "dark", "lfoot")
            + LR(joined("Shards", shards, 25), "glow", "lfoot"))


@look("feet:set:Ironclad")
def fs_iron():
    big = ring("Boot", [(-0.05, 0.0, 0.0), (-0.05, 0.56, 0.6), (0.0, 0.6, 0.64), (0.32, 0.6, 0.64),
                        (0.4, 0.58, 0.58), (0.6, 0.6, 0.6)], power=10, cx=FX, na=32, thick=0.06)
    toe = rbox("t", 1.14, 0.14, 0.24, at=(FX, 0.63, 0.12), bev=0.05)
    riv = rivets("r", [(FX + dx, 0.71, 0.12) for dx in (-0.3, 0.0, 0.3)], r=0.04)
    return (LR(big, "trim", "lfoot", "metal") + LR(joined("Toe", [toe, riv], 50), "steel", "lfoot", "metal")
            + LR(sole("Sole"), "dark", "lfoot"))


@look("feet:set:Orbitwear")
def fs_orbit():
    orbit = kit.torus("o", 0.68, 0.03, at=(FX, 0, 0.45), segs=20, csegs=5)
    pads = [kit.cyl("p", 0.14, 0.14, 0.06, at=(FX + dx, 0.0, -0.06), segs=12) for dx in (-0.25, 0.25)]
    return (LR(boot("Boot"), "dark", "lfoot") + LR(sole("Sole"), "trim", "lfoot")
            + LR(joined("Orbit", [orbit] + pads, 70), "glow", "lfoot"))


@look("feet:set:Edgewalker")
def fs_edge():
    blade = outline("b", blade_pts(0.55, 0.16), 0.04, at=(0, 0, 0), axis="X")
    blade.data.transform(Matrix.Translation((FX - 0.6, -0.1, 0.38)) @ Matrix.Rotation(PI, 4, "X"))
    band = lwrap("w", FX, [(0.44, 0.58), (0.49, 0.58)], thick=0.03)
    return (LR(boot("Boot"), "dark", "lfoot", "cloth") + LR(joined("Blade", [blade, sole("s")], 30), "trim",
                                                            "lfoot", "metal") + LR(band, "glow", "lfoot"))


@look("feet:gilded")
def f_gilded():
    wing = outline("w", feather_pts(0.42, 0.26, 3), 0.035, at=(FX - 0.6, 0.0, 0.4), axis="X")
    for v in wing.data.vertices:
        v.co.y = -v.co.y
    cuffb = lwrap("c", FX, [(0.44, 0.585), (0.56, 0.59)], thick=0.035)
    gem = ball("Gem", 0.08, (FX, 0.6, 0.46), scale=(1, 0.5, 1), segs=10, rings=6)
    return (LR(boot("Boot"), "dark", "lfoot") + LR(joined("Gold", [wing, cuffb, sole("s")], 40), "trim", "lfoot",
                                                   "gold") + LR(gem, "glow", "lfoot"))


# ================================================================ back (welded to the upper torso; its back y = -0.5)
def cape_rows(z_bot, w_top=0.95, w_bot=1.2, y_top=-0.56, y_bot=-0.86, n=12):
    rows = []
    for j in range(n + 1):
        t = j / n
        z = 3.96 + (z_bot - 3.96) * t
        rows.append((z, w_top + (w_bot - w_top) * t ** 0.8, y_top + (y_bot - y_top) * t ** 1.4))
    return rows


def clasps():
    return [ball("c", 0.13, (sx * 0.78, 0.25, 3.98), scale=(1, 1, 0.6), segs=12, rings=6) for sx in (-1, 1)]


def collar():
    return rod("Collar", [(-0.95, -0.56, 3.98), (-0.5, -0.6, 4.02), (0.5, -0.6, 4.02), (0.95, -0.56, 3.98)], 0.06,
               segs=8)


def shoulder_ties():
    return [strip("t", [(sx * 0.78, 0.25, 3.99), (sx * 0.85, -0.1, 4.03), (sx * 0.9, -0.56, 3.98)], 0.16,
                  thick=0.03) for sx in (-1, 1)]


@look("back:cape")
def b_cape():
    cloth = sheet("Cloth", cape_rows(1.25), wave=0.08, waves=2.5)
    return [P(cloth, "trim", "torso", "cloth"), P(joined("Ties", [collar()] + shoulder_ties(), 40), "dark", "torso"),
            P(joined("Clasps", clasps(), 60), "steel", "torso", "metal")]


@look("back:longcape")
def b_longcape():
    cloth = sheet("Cloth", cape_rows(0.2, w_top=0.98, w_bot=1.4, y_bot=-1.0, n=16), wave=0.1, waves=3.0)
    return [P(cloth, "trim", "torso", "cloth"), P(joined("Ties", [collar()] + shoulder_ties(), 40), "dark", "torso"),
            P(joined("Clasps", clasps(), 60), "gold", "torso", "gold")]


@look("back:jetpack")
def b_jetpack():
    pack = rbox("Pack", 1.25, 0.6, 1.35, at=(0, -0.86, 3.22), bev=0.14, segs=3)
    fins = [rbox("f", 0.08, 0.4, 0.6, at=(sx * 0.66, -0.9, 3.4), bev=0.02) for sx in (-1, 1)]
    straps = [rbox("s", 0.26, 1.15, 0.07, at=(sx * 0.5, -0.02, 4.02), bev=0.02) for sx in (-1, 1)]
    straps += [rbox("d", 0.26, 0.07, 1.3, at=(sx * 0.5, 0.54, 3.3), bev=0.02) for sx in (-1, 1)]
    jets = [kit.cyl("j", 0.2, 0.24, 0.55, at=(sx * 0.36, -0.9, 2.4), segs=14) for sx in (-1, 1)]
    noz = [kit.cyl("n", 0.18, 0.18, 0.04, at=(sx * 0.36, -0.9, 2.1), segs=14) for sx in (-1, 1)]
    return [P(joined("Pack", [pack] + straps, 35), "dark", "torso", "metal"),
            P(joined("Jets", jets + fins, 40), "trim", "torso", "metal"), P(joined("Glow", noz, 40), "glow", "torso")]


@look("back:lightwings")
def b_lightwings():
    mount = rbox("Mount", 0.5, 0.2, 0.8, at=(0, -0.62, 3.45), bev=0.06)
    wings, frames = [], []
    for sx in (-1, 1):
        w = outline("w", feather_pts(1.5, 0.75, 4), 0.03, at=(0, 0, 0), axis="Y")
        w.data.transform(Matrix.Translation((sx * 0.2, -0.75, 3.55)) @ Matrix.Rotation(math.radians(-sx * 28), 4, "Z")
                         @ Matrix.Scale(sx, 4, (1, 0, 0)) @ Matrix.Rotation(math.radians(18), 4, "Y"))
        if sx < 0:
            w.data.flip_normals()
        wings.append(w)
        frames.append(rod("f", [(sx * 0.2, -0.72, 3.55), (sx * 0.9, -1.1, 3.95), (sx * 1.55, -1.45, 4.1)],
                          [0.05, 0.04, 0.02], segs=6))
    return [P(joined("Wings", wings, 30), "glow", "torso", alpha=0.35), P(mount, "dark", "torso", "metal"),
            P(joined("Frames", frames, 50), "trim", "torso", "metal")]


@look("back:gilded")
def b_gilded():
    rows = cape_rows(0.2, w_top=0.98, w_bot=1.4, y_bot=-1.0, n=16)
    cloth = sheet("Cloth", rows, wave=0.1, waves=3.0)
    # a gold hem along the cape's sides and foot
    hem = [rod("hl", [(-hw * 1.01, y - 0.06, z) for z, hw, y in rows], 0.045, segs=6),
           rod("hr", [(hw * 1.01, y - 0.06, z) for z, hw, y in rows], 0.045, segs=6),
           rod("hb", [(u * rows[-1][1], rows[-1][2] - 0.1, rows[-1][0] + 0.02) for u in
                      (-1.0, -0.5, 0.0, 0.5, 1.0)], 0.045, segs=6)]
    gems = [ball("g", 0.12, (sx * 0.78, 0.25, 3.99), scale=(1, 1, 0.65), segs=12, rings=6) for sx in (-1, 1)]
    return [P(cloth, "dark", "torso", "cloth"), P(joined("Gold", hem + [collar()] + shoulder_ties(), 40), "trim",
                                                  "torso", "gold"), P(joined("Gems", gems, 60), "glow", "torso")]


# ================================================================ belt (the lower torso: x +-1, y +-0.5, z 2.0-2.4)
def belt_strap(name, z0=2.12, z1=2.32):
    return twrap(name, z0, z1, rx=1.05, ry=0.555, thick=0.05, na=40)


def frame_buckle(name, w, h, bar, depth, at):
    x, y, z = at
    parts = [rbox("t", w, depth, bar, at=(x, y, z + h / 2 - bar / 2), bev=0.012),
             rbox("b", w, depth, bar, at=(x, y, z - h / 2 + bar / 2), bev=0.012),
             rbox("l", bar, depth, h, at=(x - w / 2 + bar / 2, y, z), bev=0.012),
             rbox("r", bar, depth, h, at=(x + w / 2 - bar / 2, y, z), bev=0.012),
             rbox("p", w * 0.55, depth * 0.7, bar * 0.45, at=(x + w * 0.1, y + depth * 0.2, z), bev=0.006)]
    return joined(name, parts, 30)


@look("belt:belt")
def w_belt():
    pouches = [rbox("p", 0.3, 0.16, 0.26, at=(x, 0.62, 2.2), bev=0.04) for x in (-0.68, -0.36, 0.36, 0.68)]
    pouches += [rbox("q", 0.3, 0.16, 0.26, at=(x, -0.62, 2.2), bev=0.04) for x in (-0.4, 0.4)]
    return [P(belt_strap("Strap"), "trim", "waist", "cloth"),
            P(joined("Pouches", pouches, 35), "dark", "waist", "cloth"),
            P(frame_buckle("Buckle", 0.34, 0.26, 0.06, 0.06, (0, 0.6, 2.22)), "steel", "waist", "metal")]


@look("belt:buckle")
def w_buckle():
    plate = rbox("Plate", 0.62, 0.09, 0.4, at=(0, 0.61, 2.22), bev=0.05)
    star = outline("s", wear.star_pts(0.13, 0.06), 0.03, at=(0, 0.66, 2.22), axis="Y")
    return [P(belt_strap("Strap"), "dark", "waist", "cloth"), P(plate, "trim", "waist", "metal"),
            P(star, "glow", "waist")]


@look("belt:sash")
def w_sash():
    pts = []
    for k in range(41):
        a = -PI + 2 * PI * k / 40
        x, y = wear.spt(a, 1.045, 0.555, 14)
        pts.append((x, y, TZ - 0.05 + 0.42 * x))
    sash = strip("Sash", pts, 0.36, thick=0.04)
    knot = ball("k", 0.15, (-0.78, 0.5, 2.83), scale=(1, 0.6, 1), segs=12, rings=6)
    tails = [strip("t", [(-0.78, 0.54, 2.8), (-0.82 + dx, 0.6, 2.5), (-0.86 + dx * 1.5, 0.62, 2.2)], [0.18, 0.16, 0.1],
                   up=(1, 0, 0), thick=0.03) for dx in (-0.08, 0.08)]
    return [P(sash, "trim", "torso", "cloth"), P(joined("Knot", [knot] + tails, 40), "trim", "torso", "cloth")]


@look("belt:gilded")
def w_gilded():
    plate = rbox("p", 0.9, 0.1, 0.5, at=(0, 0.62, 2.22), bev=0.06)
    sides = [rbox("s", 0.4, 0.08, 0.34, at=(sx * 0.66, 0.6, 2.22), bev=0.04) for sx in (-1, 1)]
    rimr = rod("r", [(-0.42, 0.68, 2.0), (-0.42, 0.68, 2.44), (0.42, 0.68, 2.44), (0.42, 0.68, 2.0),
                     (-0.42, 0.68, 2.0)], 0.025, segs=5)
    gems = [ball("g", r, (x, 0.69, 2.22), scale=(1, 0.5, 1), segs=10, rings=6) for x, r in
            ((0, 0.12), (-0.66, 0.06), (0.66, 0.06))]
    return [P(belt_strap("Strap", 2.1, 2.34), "dark", "waist", "cloth"),
            P(joined("Plate", [plate, rimr] + sides, 35), "trim", "waist", "gold"),
            P(joined("Gems", gems, 60), "glow", "waist")]


# ================================================================ build
def mesh_name(key, short):
    return "Gear_" + key.replace(":", "_") + "_" + short


def build_all():
    built = {}
    for key, (slot, fn, hair, color) in LOOKS.items():
        if ONLY is not None and key not in ONLY:
            continue
        pieces = fn()
        seen = set()
        for p in pieces:
            n = mesh_name(key, p.ob.name.split(".")[0])
            assert n not in seen, n
            seen.add(n)
            p.ob.name = n
            p.ob.data.name = n
        built[key] = pieces
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    for key in rows:
        for row, p in zip(rows[key]["pieces"], built[key]):
            row["pat"] = p.pat
    return rows, built


# ================================================================ bake (one texture set a slot)
def region_of(p):
    return ROLES.index(p.role) * 4 + PATS.index(p.pat)


def body_copy(at, parts):
    obs = wear.body(at, 0, parts=parts, show_hair=False)
    return [o for o in obs if o.type == "MESH" and not o.name.startswith("Plane")]


def value_noise(P_, freq, seed=0):
    """Smooth 3D value noise at points P_ (N x 3), 0..1."""
    q = P_ * freq + seed * 17.0
    i = np.floor(q)
    f = q - i
    f = f * f * (3 - 2 * f)

    def h(ix, iy, iz):
        v = np.sin(ix * 127.1 + iy * 311.7 + iz * 74.7 + seed) * 43758.5453
        return v - np.floor(v)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = ((f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1])
                     * (f[:, 2] if dz else 1 - f[:, 2]))
                out = out + w * h(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out


CACHE = os.path.join(kit.ROOT, "export", "gear", "cache")


def bake_slot(slot, built):
    """Bake and compose one slot's texture set; returns {map: (image, path)}. --reuse keeps the last bake (its
    UVs travel with the cache: the meshes must be unchanged) and only composes again."""
    keys = [k for k in built if LOOKS[k][0] == slot]
    tex = [p for k in keys for p in built[k] if not p.glow]
    if not tex:
        return None
    cache = os.path.join(CACHE, slot + ".npz")
    rebake = sys.argv[sys.argv.index("--rebake") + 1].split(",") if "--rebake" in sys.argv else []
    if "--reuse" in sys.argv and os.path.exists(cache) and slot not in rebake:
        d = np.load(cache, allow_pickle=True)
        uvs = d["uvs"].item()
        for p in tex:
            me = p.ob.data
            if not me.uv_layers:
                me.uv_layers.new(name="UVMap")
            me.uv_layers.active.data.foreach_set("uv", uvs[p.ob.name])
        return compose(slot, d["region"], d["inside"], d["pos"], d["ao"])
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.world = sc.world or bpy.data.worlds.new("W")
    sc.world.light_settings.distance = 0.45
    objs = [p.ob for p in tex]
    vkit.unwrap(objs)
    # spread the looks apart (each on its own body copy for the occlusion), so no look darkens another
    extra = []
    parts = {"head": {"Head"}, "chest": {"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm"},
             "hands": {"LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm"},
             "legs": {"LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperLeg", "RightUpperLeg"},
             "feet": {"LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"},
             "back": {"UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg",
                      "RightLowerLeg"},
             "belt": {"UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg"}}[slot]
    for i, k in enumerate(keys):
        off = Vector((i * 8.0, 0, 0))
        for p in built[k]:
            p.ob.location = off
        extra += body_copy(tuple(off), parts)
    for o in sc.objects:
        o.hide_render = not (o in objs or o in extra)
    for o in extra:
        o.data.materials.clear()
        o.data.materials.append(kit.material("bodyao", (150, 150, 150)))
    mats = {}
    for p in tex:
        rid = region_of(p)
        if rid not in mats:
            mats[rid] = kit.material("rid%d_%s" % (rid, slot), (128, 128, 128))
            mats[rid]["rid"] = rid
        p.ob.data.materials.clear()
        p.ob.data.materials.append(mats[rid])

    def id_emit(m, nt, em):
        i = int(m.get("rid", 255))
        em.inputs["Color"].default_value = ((i % 16 + 0.5) / 16, (i // 16 + 0.5) / 16, 0.5, 1)

    def pos_emit(m, nt, em):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        geo.name = "TmpGeo"
        nt.links.new(geo.outputs["Position"], em.inputs["Color"])

    def clean():
        for m in vkit._mats(objs):
            g = m.node_tree.nodes.get("TmpGeo")
            if g:
                m.node_tree.nodes.remove(g)
    old_res = vkit.RES
    ids = vkit._image("ids_" + slot, RES, float_buf=True)
    sc.render.bake.use_clear = True
    sc.render.bake.margin = 0
    vkit._bake(objs, "EMIT", ids, 1, id_emit)
    raw = vkit._pixels(ids).copy()
    sc.render.bake.margin = 6
    vkit._bake(objs, "EMIT", ids, 1, id_emit)
    I = vkit._pixels(ids).copy()
    pos = vkit._image("pos_" + slot, RES, float_buf=True)
    vkit._bake(objs, "EMIT", pos, 1, pos_emit)
    clean()
    Pb = vkit._pixels(pos)[..., :3].copy()
    ao = vkit._image("ao_" + slot, RES)
    vkit._bake(objs, "AO", ao, 16)
    A = vkit._pixels(ao)[..., 0].copy()
    vkit.RES = old_res
    for img in (ids, pos, ao):
        bpy.data.images.remove(img)
    for o in extra:
        bpy.data.objects.remove(o, do_unlink=True)
    for p in tex:
        p.ob.location = (0, 0, 0)
    for k in keys:
        for p in built[k]:
            p.ob.location = (0, 0, 0)
    for o in sc.objects:
        o.hide_render = False
    region = np.floor(I[..., 0] * 16).astype(np.int32) + 16 * np.floor(I[..., 1] * 16).astype(np.int32)
    region[I[..., 2] < 0.25] = -1
    os.makedirs(CACHE, exist_ok=True)
    uvs = {}
    for p in tex:
        a = np.zeros(len(p.ob.data.loops) * 2, dtype=np.float32)
        p.ob.data.uv_layers.active.data.foreach_get("uv", a)
        uvs[p.ob.name] = a
    np.savez_compressed(cache, region=region, inside=raw[..., 2] > 0.25, pos=Pb, ao=A, uvs=np.array(uvs))
    return compose(slot, region, raw[..., 2] > 0.25, Pb, A)


def compose(slot, region, inside, Pb, A):
    H, W = region.shape
    ao = np.clip(A, 0, 1)
    for _ in range(2):
        ao = (ao + np.roll(ao, 1, 0) + np.roll(ao, -1, 0) + np.roll(ao, 1, 1) + np.roll(ao, -1, 1)) / 5
    flat = Pb.reshape(-1, 3)
    grain = value_noise(flat, 9.0, 1).reshape(H, W)
    fine = value_noise(flat, 14.0, 2).reshape(H, W)
    brushed = value_noise(flat * np.array([1.0, 1.0, 4.0], dtype=np.float32), 6.0, 3).reshape(H, W)
    weave = (np.sin(Pb[..., 0] * 45) * np.sin(Pb[..., 2] * 45) + np.sin(Pb[..., 1] * 45) * np.sin(Pb[..., 2] * 45)) * 0.5
    col = np.zeros((H, W, 3), dtype=np.float32) + 0.03
    alpha = np.zeros((H, W), dtype=np.float32)
    rough = np.full((H, W), 0.55, dtype=np.float32)
    metal = np.zeros((H, W), dtype=np.float32)
    height = np.zeros((H, W), dtype=np.float32)
    for ri, role in enumerate(ROLES):
        for pi, pat in enumerate(PATS):
            m = region == ri * 4 + pi
            if not m.any():
                continue
            base_r = {"trim": 0.42, "dark": 0.58, "glow": 0.3, "steel": 0.3, "gold": 0.24}[role]
            base_m = {"trim": 0.05, "dark": 0.15, "glow": 0.0, "steel": 0.8, "gold": 0.95}[role]
            if pat == "cloth":
                rough[m] = 0.82 + 0.08 * grain[m]
                metal[m] = 0.0
                height[m] = 0.35 * weave[m] + 0.25 * fine[m]
                alpha[m] = 0.05 + 0.05 * (weave[m] > 0.6)
            elif pat == "metal":
                rough[m] = np.clip(base_r - 0.05 + 0.14 * brushed[m], 0.1, 1)
                metal[m] = max(base_m, 0.35)
                height[m] = 0.1 * brushed[m]
                alpha[m] = 0.02 + 0.05 * brushed[m]
            elif pat == "gold":
                rough[m] = np.clip(0.22 + 0.12 * brushed[m], 0.1, 1)
                metal[m] = 0.95
                height[m] = 0.06 * brushed[m]
                alpha[m] = 0.02 * fine[m]
            else:  # plate: a painted shell with a fine grain
                rough[m] = np.clip(base_r + 0.12 * grain[m], 0.1, 1)
                metal[m] = base_m
                height[m] = 0.12 * grain[m]
                alpha[m] = 0.03 * fine[m]
    # baked occlusion shows over the part colour as a dark veil and roughens the creases
    veil = np.clip((1 - ao) * 0.5, 0, 0.5)
    alpha = np.clip(alpha + veil * (1 - alpha), 0, 1)
    rough = np.clip(rough + (1 - ao) * 0.15, 0, 1)
    col[region < 0] = 0.08
    alpha[region < 0] = 1.0
    gy, gx = np.gradient(np.where(region >= 0, height, 0.0))
    gx[~inside] = 0
    gy[~inside] = 0
    k = 1.2
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(gx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], axis=-1)
    return save(slot, col, alpha, normal, rough, metal)


def save(slot, col, alpha, normal, rough, metal):
    os.makedirs(OUT, exist_ok=True)
    H, W = alpha.shape
    name = "Gear" + slot.capitalize()

    def write(suffix, rgba, data, res=None):
        res = res or W
        if res != W:
            f = W // res
            rgba = rgba.reshape(res, f, res, f, 4).mean(axis=(1, 3))
        img = bpy.data.images.new(name + "_" + suffix, res, res, alpha=True)
        if data:
            img.colorspace_settings.name = "Non-Color"
        img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).reshape(-1))
        path = os.path.join(OUT, name + "_" + suffix + ".png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return img, path
    one = np.ones_like(alpha)
    maps = {"Color": write("Color", np.dstack([np.clip(col, 0, 1), alpha]), False),
            "Normal": write("Normal", np.dstack([normal, one]), True),
            "Roughness": write("Roughness", np.dstack([rough, rough, rough, one]), True, W // 2),
            "Metalness": write("Metalness", np.dstack([metal, metal, metal, one]), True, W // 2)}
    return maps


def export_material(slot, maps):
    m = bpy.data.materials.new("Gear" + slot.capitalize() + "Paint")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex(img, data):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        if data:
            img.colorspace_settings.name = "Non-Color"
        return n
    tc = tex(maps["Color"][0], False)
    nt.links.new(tc.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(tc.outputs["Alpha"], p.inputs["Alpha"])
    tr = tex(maps["Roughness"][0], True)
    nt.links.new(tr.outputs["Color"], p.inputs["Roughness"])
    tm = tex(maps["Metalness"][0], True)
    nt.links.new(tm.outputs["Color"], p.inputs["Metallic"])
    tn = tex(maps["Normal"][0], True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return m


# ================================================================ fit table
HEADER = ["gear.py",
          "The gear styles' looks as meshes (ReplicatedStorage.Art.Gear, art/models/Gear.rbxm; LookService wears them",
          "once every piece of a look is there, the part-built shapes until then). Keyed by look: \"<slot>:<shape>\", the",
          "set looks \"<slot>:set:<Set>\" and \"<slot>:gilded\". Each piece: its mesh, the body part it is welded to (a",
          "LookService ATTACH role), its colour role (trim: the style's own colour, the set's power colour or gold;",
          "dark; glow: Neon in the trim colour; steel; gold), its texture pattern, transparency, and its box against",
          "that body part in Roblox axes (x right, y up, z back), in studs on the reference box `ref` (scaled with the",
          "part's own box; a shin piece with the knee-to-ankle span). maps: the slot's baked texture set (a",
          "SurfaceAppearance, AlphaMode Overlay: the part colour shows through). hair = false: hides catalog hair."]


def write_fit(rows):
    def v(t):
        return "{ %s }" % ", ".join("%.3f" % x for x in t)
    lines = ["-- GENERATED by art/blender/%s: do not edit by hand." % HEADER[0]] + ["-- " + h for h in HEADER[1:]]
    total = sum(r["triangles"] for r in rows.values())
    n = sum(len(r["pieces"]) for r in rows.values())
    lines.append("-- %d looks, %d meshes, %d triangles." % (len(rows), n, total))
    lines.append("return {")
    lines.append("\tref = {")
    for at in sorted(REF):
        lines.append("\t\t%s = %s," % (at, v(REF[at])))
    lines.append("\t},")
    lines.append("\tlooks = {")
    for key in sorted(rows):
        r = rows[key]
        lines.append('\t\t["%s"] = {' % key)
        lines.append("\t\t\ttriangles = %d," % r["triangles"])
        if not LOOKS[key][2]:
            lines.append("\t\t\thair = false,")
        lines.append("\t\t\tpieces = {")
        for p in r["pieces"]:
            extra = ""
            if p["alpha"]:
                extra += ", alpha = %.2f" % p["alpha"]
            maps = "false" if p["glow"] else "true"
            lines.append('\t\t\t\t{ mesh = "%s", at = "%s", role = "%s", pat = "%s", maps = %s%s, offset = %s, '
                         "size = %s }," % (p["mesh"], p["at"], p["role"], p["pat"], maps, extra, v(p["offset"]),
                                           v(p["size"])))
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines += ["\t},", "}", ""]
    path = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "GearArt.luau"))
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote", path)


# ================================================================ previews
def preview_mat(color, maps, p):
    """A preview material: the style colour under the baked colour map's overlay, its normal and roughness."""
    if p.glow or maps is None:
        return wear.mat(color, glow=p.glow, alpha=p.alpha, rough=0.4)
    m = bpy.data.materials.new("pv%d" % len(bpy.data.materials))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = maps["Color"][0]
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (*[wear.lin(c) for c in color], 1)
    nt.links.new(tc.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(tc.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    for key, inp in (("Roughness", "Roughness"), ("Metalness", "Metallic")):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = maps[key][0]
        nt.links.new(t.outputs["Color"], b.inputs[inp])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = maps["Normal"][0]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


def role_color(p, trim):
    return trim if p.role in ("trim", "glow") else FIXED[p.role]


def place(pieces, at, yaw, trim, slot_maps):
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for p in pieces:
        c = p.ob.copy()
        c.data = p.ob.data.copy()
        bpy.context.scene.collection.objects.link(c)
        c.data.materials.clear()
        c.data.materials.append(preview_mat(role_color(p, trim), slot_maps, p))
        c.matrix_world = Y @ c.matrix_world
        c.hide_render = False


LEGS = {"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"}
ARMS = {"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand"}
FRAME = {"head": dict(cell=2.6, focus=4.75, parts={"Head", "UpperTorso"}, look_down=0.1),
         "chest": dict(cell=3.6, focus=3.3, parts={"Head", "UpperTorso", "LowerTorso"} | ARMS, look_down=0.1),
         "hands": dict(cell=4.6, focus=2.6, parts={"UpperTorso", "LowerTorso"} | ARMS, look_down=0.05),
         "legs": dict(cell=3.0, focus=1.0, parts={"LowerTorso"} | LEGS, look_down=0.25),
         "feet": dict(cell=2.6, focus=0.5, parts=LEGS, look_down=0.3),
         "back": dict(cell=5.6, focus=2.55, parts=None, look_down=0.0),
         "belt": dict(cell=3.6, focus=2.7, parts={"UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg"} | ARMS,
                      look_down=0.1)}


def preview(built, maps):
    for slot in SLOTS:
        keys = [k for k in built if LOOKS[k][0] == slot]
        if not keys:
            continue
        fr = FRAME[slot]
        sub = {k: built[k] for k in keys}

        def dress(name, at, yaw, pal, fr=fr, slot=slot):
            hair = LOOKS[name][2]
            wear.body(at, yaw, suit=(150, 156, 170), parts=fr["parts"], show_hair=hair)
            place(built[name], at, yaw, LOOKS[name][3], maps.get(slot))
        wear.hide_sources(built)
        name = "gear_%s.png" % slot if ONLY is None else "gear_%s_test.png" % slot
        wear.grid_preview(sub, os.path.join(kit.ROOT, "preview", name), dress, cols=min(6, len(keys)),
                          cell=fr["cell"], px=300, focus=fr["focus"], yaw_front=150, yaw_back=25, samples=24,
                          look_down=fr["look_down"])
        wear.hide_sources(built)


OUTFITS = [  # whole outfits for art/preview/gear.png (each slot's look, trim colour)
    ("Rookie", ["head:visor", "chest:vest", "hands:wraps", "legs:shins", "feet:boots", "back:cape", "belt:belt"]),
    ("Patrol", ["head:cap", "chest:harness", "hands:gauntlet", "legs:stripes", "feet:jets", "back:jetpack",
                "belt:buckle"]),
    ("Brawler", ["head:horns", "chest:core", "hands:spikes", "legs:greaves", "feet:wings", "back:lightwings",
                 "belt:sash"]),
    ("Stormcaller", ["head:set:Stormcaller", "chest:set:Stormcaller", "hands:set:Stormcaller",
                     "feet:set:Stormcaller", "back:longcape", "belt:belt"]),
    ("Rimeguard", ["head:set:Rimeguard", "chest:set:Rimeguard", "hands:set:Rimeguard", "feet:set:Rimeguard",
                   "back:cape"]),
    ("Ironclad", ["head:set:Ironclad", "chest:set:Ironclad", "hands:set:Ironclad", "feet:set:Ironclad",
                  "legs:greaves", "back:jetpack"]),
    ("Orbitwear", ["head:set:Orbitwear", "chest:set:Orbitwear", "hands:set:Orbitwear", "feet:set:Orbitwear",
                   "back:lightwings"]),
    ("Edgewalker", ["head:set:Edgewalker", "chest:set:Edgewalker", "hands:set:Edgewalker",
                    "feet:set:Edgewalker", "back:longcape", "belt:sash"]),
    ("Gilded", ["head:gilded", "chest:gilded", "hands:gilded", "legs:gilded", "feet:gilded", "back:gilded",
                "belt:gilded"]),
    ("Mixed", ["head:fin", "chest:plate", "hands:coil", "legs:shins", "feet:boots", "back:cape", "belt:buckle"]),
    ("Halo", ["head:halo", "chest:vest", "hands:wraps", "feet:wings", "back:lightwings", "belt:sash"]),
    ("Masked", ["head:mask", "chest:harness", "hands:gauntlet", "legs:stripes", "feet:boots", "back:longcape",
                "belt:belt"]),
]


def outfit_preview(built, maps):
    outfits = [(n, ks) for n, ks in OUTFITS if all(k in built for k in ks)]
    if not outfits:
        return
    fake = {n: [p for k in ks for p in built[k]] for n, ks in outfits}
    wear.hide_sources(built)

    def dress(name, at, yaw, pal):
        ks = dict(outfits)[name]
        hair = all(LOOKS[k][2] for k in ks if k.startswith("head:"))
        wear.body(at, yaw, suit=(150, 156, 170), show_hair=hair)
        for k in ks:
            set_name = name if name in SET_COLOR else None
            trim = SET_COLOR[set_name] if set_name else LOOKS[k][3]
            place(built[k], at, yaw, trim, maps.get(LOOKS[k][0]))
    wear.grid_preview(fake, os.path.join(kit.ROOT, "preview", "gear.png" if ONLY is None else "gear_test.png"),
                      dress, cols=6, cell=6.4, px=360, focus=2.85, yaw_front=150, yaw_back=25, samples=24)


def export(built, maps):
    glow = bpy.data.materials.new("GearGlow")
    glow.use_nodes = True
    objs = []
    for key, pieces in built.items():
        slot = LOOKS[key][0]
        for p in pieces:
            p.ob.data.materials.clear()
            p.ob.data.materials.append(glow if p.glow else maps[slot]["_mat"])
            objs.append(p.ob)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_render = False
        o.hide_set(False)
        o.select_set(True)
    path = os.path.join(kit.ROOT, "export", "Gear.fbx")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", object_types={"MESH"}, use_mesh_modifiers=True,
                             mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False, path_mode="COPY",
                             embed_textures=True)
    print("wrote", path, len(objs), "meshes")


if __name__ == "__main__":
    rows, built = build_all()
    total = sum(r["triangles"] for r in rows.values())
    print(len(rows), "looks", sum(len(v) for v in built.values()), "meshes", total, "triangles")
    maps = {}
    if not QUICK:
        for slot in SLOTS:
            mp = bake_slot(slot, built)
            if mp:
                mp["_mat"] = export_material(slot, mp)
                maps[slot] = mp
                print("baked", slot)
        if ONLY is None and "--noexport" not in sys.argv:
            export(built, maps)
            write_fit(rows)
    if not NOPREVIEW:
        preview(built, maps)
        outfit_preview(built, maps)
