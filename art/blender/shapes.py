# shapes.py: round 2 of the living world (shapes-2, 2026-11-19, nate: "you still use way too many simple shapes and
# textures"). Blender looks over the city boxes the living-world pass left plain (art/preview/city_audit.txt):
# * the outskirts' props: pond rocks (three shapes, a baked stone texture set), the lighthouse's rocky plinth, its red
#   bands and lantern room, driftwood, park benches, beach umbrellas and towels, the small windmills' towers and
#   blades, tractors and their cabs, parked cars on the lots, pier pilings and the courts' basketball hoops
# * the roofs: Downtown's and Uptown's parapets, the moulded cornice round every flat roof's cap and the coping lip
#   round the low roofs' caps (Old Town, the apartment lots, the Docks)
# Every look is drawn in Roblox studs about the middle of its own frame (x, up, z back; a look faces -z): the box the
# city stands it over. Shared.LifeKit scales each mesh by the real box over the frame and CityBuilder builds it where
# the box was (props: the meshes collide like the box did and break like it; roof rings: the box stays, the moulding
# runs round its edges as visual-only meshes). Low poly for phones; same MeshId copies instance.
# Output: art/export/Shapes.fbx (textures embedded), art/export/shapes/ShapesStone_*.png, src/config/ShapeArt.luau
# (generated); --preview renders art/preview/shapes.png (shapes_preview.py).
# Run: ~/tools/bpyenv/bin/python art/blender/shapes.py [--preview] [--fast] [--no-bake]
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
from studs import rb, B, C, S, T, TOR, turn, shift, copy, prism, loft_z  # noqa: E402

FAST = "--fast" in sys.argv
vkit.OUT = os.path.join(kit.ROOT, "export", "shapes")


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
RING = {}  # look -> True: a moulding run round a box's four edges
INFO = {}


def look(name, frame, ring=False):
    FRAMES[name] = frame
    LOOKS.setdefault(name, [])
    if ring:
        RING[name] = True


def add(g, lk, name, parts, rgb=None, mat="SmoothPlastic", alpha=0.0, tint=False):
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
    else:
        g.extra[name] = (tuple(int(c) for c in rgb), mat, alpha)
    LOOKS[lk].append(name)
    INFO[name] = dict(group=g.name, rgb=tuple(int(c) for c in (rgb or (255, 255, 255))), mat=mat, alpha=alpha,
                      maps=rgb is None, tint=tint)
    return ob


def lumpy(ob, amp, f, seed, flat_below=None):
    """A rock's surface: every vertex pushed out from the centre by noise; flattened under flat_below (Roblox y)."""
    kit.apply_all(ob)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in ob.data.vertices:
        d = v.co.length
        if d > 1e-4:
            n = noise.noise(v.co * f + off) + 0.5 * noise.noise(v.co * f * 2.3 + off * 1.7)
            v.co = v.co * (1 + n * amp)
        if flat_below is not None and v.co.z < flat_below:
            v.co.z = flat_below + (v.co.z - flat_below) * 0.08
    ob.data.update()
    return ob


def solid(ob, t):
    m = ob.modifiers.new("solid", "SOLIDIFY")
    m.thickness = t
    m.offset = -1
    kit.apply_all(ob)
    return ob


# ================================================================ the stone pattern (texture space: each texel's baked
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


def shapes_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise_):
    if not (isinstance(pat, tuple) and pat and pat[0] in ("stone", "bleached", "slab")):
        return _orig(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise_)
    p, n = Pp[m], Nn[m]
    c, r, h = col[m], rough[m], height[m]
    kind = pat[0]
    if kind == "stone":  # cartoon boulder: soft strata, speckle, cracks, moss on top
        k = fbm(p, 0.9)
        strata = 0.5 + 0.5 * np.sin(p[:, 1] * 5.0 + k * 4.0)
        c = c * (0.82 + 0.16 * k + 0.08 * strata)[:, None]
        sp = _hash(np.floor(p[:, 0] * 9), np.floor(p[:, 1] * 9), np.floor(p[:, 2] * 9)) > 0.93
        c[sp] *= 0.78
        crack = np.abs(vnoise(p, 1.4, 5.0) - 0.5) < 0.018
        c[crack] *= 0.55
        h = h + k * 0.6 - crack * 0.6
        moss = (n[:, 1] > 0.7) & (fbm(p, 1.2, 9.0) > 0.6)
        c[moss] = rgbf((104, 150, 70)) * (0.85 + 0.25 * fbm(p[moss], 3.0, 2.0))[:, None]
        r = np.where(moss, 0.95, r)
    elif kind == "bleached":  # sea-bleached wood: grain along x, cracks, darker ends
        g = vnoise(p * np.array([0.25, 3.0, 3.0], np.float32), 1.0, 3.0)
        c = c * (0.84 + 0.22 * g)[:, None]
        line = np.abs(np.sin(p[:, 1] * 14 + p[:, 2] * 11 + g * 6)) < 0.08
        c[line] *= 0.7
        h = h - line * 0.4
    elif kind == "slab":  # the plinth's poured top: board marks and stains
        k = fbm(p, 0.4)
        c = c * (0.88 + 0.14 * k)[:, None]
        board = (np.abs(((p[:, 0] + 13) % 2.0) - 1.0) < 0.03)
        c[board] *= 0.85
        h = h - board * 0.3
    col[m], rough[m], height[m] = c, r, h


vkit._pattern = shapes_pattern

STONE = R("Stone", (150, 142, 132), 0.9, pat=("stone",))
STONE_W = R("StoneWarm", (170, 150, 124), 0.9, pat=("stone",))
STONE_D = R("StoneDark", (118, 118, 122), 0.9, pat=("stone",))
DRIFT = R("Drift", (190, 176, 156), 0.85, pat=("bleached",))
SLAB = R("PlinthTop", (176, 172, 164), 0.85, pat=("slab",))

G_STONE = Grp("ShapesStone", 1024)
G = Grp("ShapesFlat")  # flat-coloured meshes (no bake)

WOODC = (166, 112, 66)
IRON = (46, 64, 56)
WHITE = (244, 244, 240)
DARK = (40, 42, 48)
METAL = (150, 156, 164)
RED = (204, 52, 44)
YELLOW = (246, 196, 40)
GLASS = (170, 210, 230)
ROPE = (214, 184, 124)
CONCRETE = (214, 210, 200)


def boulder(r, at, seed, sc=(1, 1, 1), flat=None):
    s = kit.sphere("rk", r, at=rb(*at), scale=(sc[0], sc[2], sc[1]), segs=14, rings=9)
    return lumpy(s, 0.22, 0.55 / r, seed, flat)


# ================================================================ rocks (BoxKit ball boxes 5 x 4 x 5 and 4 x 3 x 4; the
# ball is round in the game, the rock fills the box's real size, its foot a little in the ground)
look("RockA", (5, 4, 5))
add(G_STONE, "RockA", "RockA", [P(boulder(2.4, (0, 0, 0), 1, (1.04, 0.86, 0.96), -1.75), STONE)])
look("RockB", (5, 4, 5))
rb_ = [P(boulder(1.9, (-0.7, -0.3, 0.2), 2, (1.15, 0.8, 1.0), -1.75), STONE_W),
       P(boulder(1.4, (1.2, -0.7, -0.6), 3, (1.0, 0.75, 1.0), -1.75), STONE_W),
       P(boulder(0.8, (0.6, -1.2, 1.5), 4, (1.1, 0.7, 1.0), -1.75), STONE_W)]
add(G_STONE, "RockB", "RockB", rb_)
look("RockC", (5, 4, 5))
rc = boulder(1.9, (0, -0.2, 0), 5, (0.9, 1.15, 0.85), -1.75)
kit.deform(rc, lambda v: Vector((v.x + v.z * 0.12, v.y, v.z)))
add(G_STONE, "RockC", "RockC", [P(rc, STONE_D), P(boulder(0.9, (1.6, -1.2, 0.8), 6, (1.2, 0.7, 1.0), -1.75), STONE_D)])

# ---------------------------------------------------------------- the lighthouse's plinth (frame 26 x 6 x 26: a
# cylinder box; the tower's foot is 12 across in its middle)
look("RockBase", (26, 6, 26))
pl = [P(C(11.6, 1.2, 0, 2.4, 0, segs=28), SLAB), P(C(12.2, 4.6, 0, -0.6, 0, segs=28, r2=11.6), STONE)]
for k in range(12):
    a = k * math.pi * 2 / 12 + 0.2
    rr = 1.9 + 0.5 * ((k * 7) % 3)
    pl.append(P(boulder(rr, (math.cos(a) * 11.6, -2.0 + rr * 0.4, math.sin(a) * 11.6), 10 + k, (1.2, 0.8, 1.0), -2.9), STONE))
add(G_STONE, "RockBase", "RockBase", pl)

# ---------------------------------------------------------------- driftwood (frame 10 x 1.2 x 1.2, lying along x)
look("Driftwood", (10, 1.2, 1.2))
dw = [P(T([(-5.0, 0.0, 0.1), (-2.5, 0.1, -0.15), (0.5, 0.0, 0.12), (3.0, 0.08, -0.1), (5.0, -0.05, 0.05)],
          [0.62, 0.55, 0.5, 0.42, 0.28], segs=9), DRIFT),
      P(T([(1.0, 0.1, 0.1), (2.2, 0.35, 0.9), (3.0, 0.4, 1.5)], [0.22, 0.15, 0.08], segs=6), DRIFT),
      P(T([(-4.6, 0.0, 0.0), (-5.2, 0.35, 0.55)], [0.3, 0.12], segs=6), DRIFT),
      P(T([(-4.6, 0.0, 0.0), (-5.3, -0.2, -0.6)], [0.28, 0.1], segs=6), DRIFT)]
add(G_STONE, "Driftwood", "Driftwood", dw)

# ================================================================ park benches (frame 8 x 2 x 2: the box stands on the
# ground at y -1; the seat faces -z)
look("ParkBench", (8, 2, 2))
bw = [rbox(7.6, 0.16, 0.42, 0, 0.42, z, bev=0.05, segs=1) for z in (-0.55, -0.05, 0.45)]
for k, (y, z) in enumerate(((1.25, 0.86), (1.85, 1.0))):
    slat = rbox(7.6, 0.4, 0.14, 0, y, z, bev=0.05, segs=1)
    turn(slat, "x", -12, pivot=(0, y, z))
    bw.append(slat)
add(G, "ParkBench", "BenchWood", bw, WOODC, "Wood")
bi = []
for x in (-3.3, 3.3):
    side = prism([(-0.75, -1.0), (-0.6, -1.0), (-0.45, 0.3), (0.7, 0.3), (0.82, -1.0), (0.98, -1.0), (0.86, 0.36),
                  (1.12, 2.15), (0.96, 2.2), (0.74, 0.5), (-0.6, 0.5)], x - 0.09, x + 0.09)
    bi.append(side)
    bi.append(T([(x, 0.95, -0.85), (x, 1.05, -0.2), (x, 0.95, 0.3)], [0.07, 0.07, 0.07], segs=5))  # arm rest
add(G, "ParkBench", "BenchIron", bi, IRON, "Metal")

# ================================================================ beach umbrellas: the pole (frame 0.6 x 8 x 0.6) and
# the canopy (frame 9 x 1 x 9, a cylinder box); the canopy's cloth takes the box's colour
look("UmbrellaPole", (0.6, 8, 0.6))
up = [C(0.11, 8.2, 0, -0.1, 0, segs=8), C(0.17, 0.5, 0, 1.4, 0, segs=8), C(0.02, 0.7, 0, -4.2, 0, segs=6, r2=0.12),
      TOR(0.2, 0.05, 0, -3.2, 0, segs=10, csegs=4)]
add(G, "UmbrellaPole", "UmbrellaPole", up, WHITE, "Metal")
look("UmbrellaTop", (9, 1, 9))
cloth, trim = [], []
N8 = 8
for k in range(N8):
    a0, a1 = k * 2 * math.pi / N8, (k + 1) * 2 * math.pi / N8
    ring = []
    for i in range(5):  # the panel's scalloped edge
        a = a0 + (a1 - a0) * i / 4
        dip = 0.22 * math.sin(math.pi * i / 4)
        ring.append((math.cos(a) * 4.5, -0.5 + dip, math.sin(a) * 4.5))
    import bmesh
    bm = bmesh.new()
    tip = bm.verts.new(rb(0, 0.5, 0))
    vs = [bm.verts.new(rb(*q)) for q in ring]
    mid = [bm.verts.new(rb(q[0] * 0.55, 0.05 + (q[1] + 0.5) * 0.5, q[2] * 0.55)) for q in ring]
    for i in range(4):
        bm.faces.new((tip, mid[i + 1], mid[i]))
        bm.faces.new((mid[i], mid[i + 1], vs[i + 1], vs[i]))
    me = bpy.data.meshes.new("panel")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("panel", me)
    bpy.context.scene.collection.objects.link(ob)
    solid(ob, 0.07)
    (cloth if k % 2 == 0 else trim).append(ob)
add(G, "UmbrellaTop", "UmbrellaCloth", cloth, WHITE, "Fabric", tint=True)
add(G, "UmbrellaTop", "UmbrellaTrim", trim + [S(0.2, 0, 0.55, 0, segs=8, rings=5)], WHITE, "Fabric")

# ================================================================ beach towels (frame 3 x 0.2 x 6, flat on the sand)
look("BeachTowel", (3, 0.2, 6))
tw = [rbox(2.9, 0.08, 5.3, 0, -0.06, 0.3, bev=0.03, segs=1), C(0.36, 2.9, 0, 0.26, -2.55, segs=10, axis="x")]
shift(tw[1], rb(-1.45, 0, 0))
add(G, "BeachTowel", "TowelCloth", tw, WHITE, "Fabric", tint=True)
add(G, "BeachTowel", "TowelStripe", [B(2.92, 0.02, 0.35, 0, -0.01, z) for z in (-1.4, 1.7, 2.3)], WHITE, "Fabric")

# ================================================================ the small windmills: the tower (frame 3 x 28 x 3, a
# cylinder box) with the nacelle on top, the rotor's two blade boxes (1 x 22 x 1 and 22 x 1 x 1 at the top, 2 in front)
look("WindTower", (3, 28, 3))
wt = [C(1.35, 27.4, 0, -0.3, 0, segs=12, r2=0.55)]
for y in (-13.6, -4.0, 6.0):
    wt.append(C(1.45 - (y + 14) * 0.029, 0.35, 0, y, 0, segs=12))
wt.append(rbox(1.4, 1.5, 3.6, 0, 14.2, -0.3, bev=0.3, segs=2))
wt.append(rbox(0.12, 1.0, 1.2, 0, 15.4, 1.0, bev=0.02, segs=1))  # the tail fin
add(G, "WindTower", "WindTower", wt, WHITE)
look("WindBladeV", (1, 22, 1))


def blade(up_):
    pts = [(0.0, 0.0, 0.0)]
    b_ = []
    for s_ in (1, -1):
        sec_ = []
        for i, (y, w) in enumerate(((0.8, 0.5), (4.0, 0.95), (8.0, 0.7), (10.8, 0.3))):
            sec_.append((y * s_, w))
        verts = []
        for (y, w) in sec_:
            verts.append((y, w))
        poly = [(-w * 0.5 + 0.25 * (abs(y) / 11), y) for (y, w) in verts] + [(w * 0.5 + 0.25 * (abs(y) / 11), y) for (y, w) in reversed(verts)]
        bl = prism([(z, y) for (z, y) in [(px, py) for (px, py) in poly]], -0.09, 0.09)
        turn(bl, "up", 90)  # (the blade's width runs along x, its thickness along z)
        turn(bl, "up", 8 * s_)
        b_.append(bl)
    if not up_:
        for bl in b_:
            turn(bl, "z", 90)
    return b_ + [r for r in pts if False]


add(G, "WindBladeV", "BladeV", blade(True) + [C(0.45, 0.9, 0, 0, -0.1, segs=10, axis="z", r2=0.1)], WHITE)
look("WindBladeH", (22, 1, 1))
add(G, "WindBladeH", "BladeH", blade(False), WHITE)

# ================================================================ tractors: the body (frame 6 x 4 x 9, its foot 1 below
# the frame on the field; the hood at -z) and the cab (frame 5 x 3 x 4 over the body's back)
look("Tractor", (6, 4, 9))
tp = [rbox(2.4, 2.0, 5.4, 0, -0.2, -1.6, bev=0.3, segs=2), rbox(3.4, 0.8, 3.4, 0, 0.6, 2.4, bev=0.15, segs=1)]
for s_ in (1, -1):
    fe = TOR(2.45, 0.18, s_ * 2.6, -0.85, 2.4, axis="x", segs=16, csegs=4, arc=math.pi)
    turn(fe, "x", 0, pivot=(s_ * 2.6, -0.85, 2.4))
    tp.append(solid(B(1.3, 0.14, 3.4, s_ * 2.6, 1.6, 2.4), 0.02))
    tp.append(fe)
add(G, "Tractor", "TractorPaint", tp, RED)
ty, rim = [], []
for s_ in (1, -1):
    ty.append(TOR(1.7, 0.55, s_ * 2.6, -0.85, 2.4, axis="x", segs=20, csegs=8))
    ty.append(TOR(0.85, 0.35, s_ * 1.6, -2.0, -3.1, axis="x", segs=16, csegs=6))
    rim.append(C(1.3, 0.7, s_ * 2.6 - 0.35, -0.85, 2.4, segs=14, axis="x"))
    rim.append(C(0.6, 0.5, s_ * 1.6 - 0.25, -2.0, -3.1, segs=12, axis="x"))
add(G, "Tractor", "TractorTyre", ty, DARK, "Rubber" if False else "SmoothPlastic")
add(G, "Tractor", "TractorRim", rim, YELLOW)
tr_ = [C(0.15, 2.6, 0.7, 2.0, -2.6, segs=8), rbox(2.2, 1.4, 0.15, 0, -0.4, -4.35, bev=0.04, segs=1),
       B(1.4, 0.6, 7.2, 0, -1.6, -0.6), C(0.25, 4.4, -1.6, -2.0, -3.1, segs=8, axis="x")]
add(G, "Tractor", "TractorTrim", tr_, METAL, "Metal")
look("TractorCab", (5, 3, 4))
cf = []
for sx_ in (1, -1):
    for sz_ in (1, -1):
        cf.append(B(0.22, 2.9, 0.22, sx_ * 1.85, 0, sz_ * 1.55))
cf.append(rbox(4.4, 0.3, 3.9, 0, 1.55, 0, bev=0.1, segs=1))
cf.append(rbox(1.2, 0.8, 0.9, 0, -1.0, 0.6, bev=0.15, segs=1))  # the seat
cf.append(T([(0, -0.9, -0.6), (0, -0.2, -0.9)], [0.06, 0.06], segs=5))
cf.append(TOR(0.32, 0.05, 0, -0.18, -0.95, axis="up", segs=10, csegs=4))
add(G, "TractorCab", "CabFrame", cf, DARK, "Metal")
cg = [B(3.6, 2.6, 0.06, 0, 0, -1.55), B(3.6, 2.6, 0.06, 0, 0, 1.55), B(0.06, 2.6, 2.9, 1.85, 0, 0), B(0.06, 2.6, 2.9, -1.85, 0, 0)]
add(G, "TractorCab", "CabGlass", cg, GLASS, "Glass", 0.55)

# ================================================================ parked cars on the lots (frame 5 x 4 x 9; the box's
# foot is the lot's tarmac; the paint takes the box's colour)
look("LotCar", (5, 4, 9))
body = loft_z([(-4.4, 2.2, -1.25, 0.1), (-3.8, 2.4, -1.4, 0.35), (-1.5, 2.45, -1.45, 0.45), (2.0, 2.45, -1.45, 0.5),
               (4.1, 2.35, -1.35, 0.45), (4.45, 2.1, -1.1, 0.2)], segs=16, power=3.2)
cab = loft_z([(-1.6, 2.0, 0.3, 0.6), (-0.6, 1.95, 0.4, 1.7), (2.0, 1.95, 0.4, 1.75), (3.0, 1.9, 0.4, 0.8)], segs=12, power=3.0)
add(G, "LotCar", "CarPaint", [body, cab], WHITE, tint=True)
gl = loft_z([(-1.45, 2.03, 0.55, 0.62), (-0.55, 1.99, 0.62, 1.62), (1.95, 1.99, 0.62, 1.67), (2.85, 1.94, 0.6, 0.78)], segs=12, power=3.0)
add(G, "LotCar", "CarGlass", [gl], (60, 80, 100), "Glass", 0.3)
cw = []
for sx_ in (1, -1):
    for z in (-2.7, 2.7):
        cw.append(TOR(0.62, 0.32, sx_ * 2.1, -1.08, z, axis="x", segs=14, csegs=6))
        cw.append(C(0.5, 0.5, sx_ * 2.1 - 0.25, -1.08, z, segs=10, axis="x"))
add(G, "LotCar", "CarWheels", cw, DARK)
lamps = [S(0.32, sx_ * 1.6, -0.35, -4.38, sc=(1.2, 0.8, 0.5), segs=8, rings=5) for sx_ in (1, -1)]
lamps += [B(4.6, 0.3, 0.3, 0, -1.0, -4.45), B(4.4, 0.3, 0.3, 0, -0.95, 4.45)]
add(G, "LotCar", "CarTrim", lamps, (230, 232, 236), "Metal")

# ================================================================ pier pilings (frame 2 x 8 x 2)
look("Piling", (2, 8, 2))
add(G, "Piling", "PilingWood", [C(0.9, 7.6, 0, -0.2, 0, segs=12, r2=0.85), C(0.95, 0.4, 0, 3.8, 0, segs=12, r2=0.8)], (120, 90, 62), "Wood")
add(G, "Piling", "PilingRope", [TOR(0.93, 0.12, 0, y, 0, segs=12, csegs=4) for y in (2.4, 2.7, 3.0)], ROPE, "Fabric")

# ================================================================ basketball hoops (frame 1 x 10 x 1: the court's end
# posts; the board faces -z, the box's turn faces it at the court)
look("HoopPost", (1, 10, 1))
hp = [C(0.22, 7.6, 0, -1.2, 0.6, segs=10), T([(0, 2.6, 0.6), (0, 3.4, 0.2), (0, 3.5, -0.9)], [0.14, 0.14, 0.14], segs=6),
      C(0.5, 0.3, 0, -4.85, 0.6, segs=10)]
add(G, "HoopPost", "HoopPole", hp, (36, 60, 120), "Metal")
add(G, "HoopPost", "HoopBoard", [rbox(3.6, 2.4, 0.14, 0, 3.8, -1.0, bev=0.05, segs=1)], WHITE)
rimp = [TOR(0.45, 0.04, 0, 3.05, -1.55, segs=14, csegs=4), B(1.0, 0.7, 0.03, 0, 3.4, -1.09), B(0.6, 0.08, 0.2, 0, 3.05, -1.15)]
add(G, "HoopPost", "HoopRim", rimp, (244, 112, 36), "Metal")
net = []
for k in range(8):
    a = k * math.pi / 4
    net.append(T([(math.cos(a) * 0.45, 3.05, -1.55 + math.sin(a) * 0.45), (math.cos(a + 0.4) * 0.3, 2.3, -1.55 + math.sin(a + 0.4) * 0.3)],
                 [0.025, 0.025], segs=4))
net.append(TOR(0.32, 0.025, 0, 2.5, -1.55, segs=12, csegs=3))
add(G, "HoopPost", "HoopNet", net, WHITE, "Fabric")

# ================================================================ the lighthouse: its red bands (frame 12.6 x 6 x 12.6,
# cylinder boxes round the 12-wide tower) and the lantern room (frame 8 x 6 x 8 on the tower's top)
look("LightBand", (12.6, 6, 12.6))
band = solid(C(6.25, 5.4, 0, 0, 0, segs=28), 0.0)
add(G, "LightBand", "LightBand", [band], RED, tint=True)
add(G, "LightBand", "LightBead", [TOR(6.25, 0.24, 0, y, 0, segs=28, csegs=5) for y in (-2.75, 2.75)], WHITE)
look("Lantern", (8, 6, 8))
ld = [C(6.6, 0.4, 0, -2.8, 0, segs=28), TOR(6.3, 0.08, 0, -1.5, 0, segs=28, csegs=4), TOR(6.3, 0.06, 0, -2.1, 0, segs=28, csegs=4),
      C(4.0, 0.35, 0, 1.4, 0, segs=24)]
for k in range(16):
    a = k * math.pi / 8
    ld.append(C(0.07, 1.3, math.cos(a) * 6.3, -2.0, math.sin(a) * 6.3, segs=4))
for k in range(8):
    a = k * math.pi / 4
    ld.append(C(0.12, 4.0, math.cos(a) * 3.65, -0.6, math.sin(a) * 3.65, segs=5))
add(G, "Lantern", "LanternDeck", ld, (52, 56, 64), "Metal")
add(G, "Lantern", "LanternGlass", [C(3.6, 4.0, 0, -0.6, 0, segs=20)], (220, 236, 245), "Glass", 0.55)
add(G, "Lantern", "LanternLamp", [S(1.35, 0, -0.5, 0, sc=(1, 1.25, 1), segs=12, rings=8)], (255, 236, 160), "Neon")
add(G, "Lantern", "LanternCap", [C(4.2, 1.9, 0, 2.5, 0, segs=24, r2=0.45), S(0.55, 0, 3.6, 0, segs=10, rings=6)], RED)

# ================================================================ roofs
# ---------------------------------------------------------------- a parapet (frame 40 x 2 x 1.5: a wall along x on a
# roof's edge, its outside at -z): the wall and its coping
look("Parapet", (40, 2, 1.5))
add(G, "Parapet", "ParapetWall", [B(40, 1.75, 1.3, 0, -0.12, 0.05),
                                  prism([(-0.68, -1.0), (-0.68, -0.75), (-0.78, -0.65), (-0.68, -0.55), (-0.68, -0.4), (-0.6, -0.4), (-0.6, -1.0)], -20, 20)],
    WHITE, tint=True)
cop = prism([(-0.86, 0.72), (-0.86, 0.86), (-0.7, 1.0), (0.78, 1.0), (0.86, 0.86), (0.86, 0.72), (0.76, 0.72), (0.76, 0.78), (-0.76, 0.78), (-0.76, 0.72)], -20, 20)
add(G, "Parapet", "ParapetCap", [cop], CONCRETE)

# ---------------------------------------------------------------- the cornice run (frame 40 x 1.2 x 1.2): one edge's
# moulding, its face out at -z; LifeKit runs one along each edge of a flat roof's cap (the cap is 0.5 proud all round)
look("CorniceRun", (40, 1.2, 1.2), ring=True)
prof = [(0.6, -0.6), (-0.05, -0.6), (-0.05, -0.45), (-0.2, -0.38), (-0.32, -0.2), (-0.42, 0.05), (-0.52, 0.22), (-0.62, 0.3),
        (-0.62, 0.48), (-0.7, 0.52), (-0.7, 0.6), (0.6, 0.6)]
add(G, "CorniceRun", "CorniceRun", [prism(prof, -20, 20)], WHITE, tint=True)
dent = [B(0.32, 0.2, 0.18, x, 0.2, -0.47) for x in [(-19.6 + k * 0.8) for k in range(50)]]
add(G, "CorniceRun", "CorniceDentils", dent, CONCRETE)

# ---------------------------------------------------------------- the roof edge (frame 40 x 2 x 1.2): a coping lip
# round a low roof's cap (Old Town, the apartment lots, the Docks)
look("RoofEdge", (40, 2, 1.2), ring=True)
add(G, "RoofEdge", "RoofEdge", [prism([(0.6, -1.0), (-0.3, -1.0), (-0.3, 0.55), (-0.55, 0.6), (-0.55, 1.0), (0.6, 1.0)], -20, 20)],
    CONCRETE)
add(G, "RoofEdge", "RoofEdgeBand", [B(40, 0.35, 0.1, 0, -0.55, -0.34)], (140, 136, 130))

# ================================================================ dunes (frame 26 x 10 x 16: a sand ball box, its middle
# on the sand; only the top half shows): a wind-swept mound, steep on its lee side, with marram tufts
look("Dune", (26, 10, 16))
du = kit.sphere("dune", 1.0, at=(0, 0, 0), segs=24, rings=12)


def _dune(v):
    x, y, z = v.x * 13.0, -v.y * 8.0, v.z * 5.0
    if y > 0:  # the lee side (+z) falls off steeper
        z *= 1.0 + 0.0 * y
    lean = 2.2 * (1 - (abs(x) / 13.0) ** 2) * max(z, 0) / 5.0
    return Vector((x, -(y + lean * 0.4), z + 0.35 * math.sin(x * 0.9 + y * 0.7)))


kit.deform(du, _dune)
add(G, "Dune", "DuneSand", [du], (232, 210, 156), "Sand")
tufts = []
for k, (x, z) in enumerate(((-6, -2), (3, -3.5), (8, 1), (-2, 2.5), (-9, 0.5))):
    for j in range(5):
        a = j * 1.25 + k
        tufts.append(T([(x, 3.6, z), (x + math.cos(a) * 0.6, 5.4, z + math.sin(a) * 0.6)], [0.1, 0.02], segs=4))
add(G, "Dune", "DuneGrass", tufts, (150, 170, 90), "Grass")

# ================================================================ the outskirts shops' awnings (frame 26 x 0.6 x 4 over
# the shop's door, along x, its front edge at +z): a sloped striped canvas with a scalloped valance, on two arms
look("ShopAwning", (26, 0.6, 4))
can, stp = [], []
for k in range(13):
    x0 = -13 + k * 2
    pan = prism([(-2.0, 0.9), (2.0, -0.4), (2.0, -0.32), (-2.0, 0.98)], x0, x0 + 2)
    turn(pan, "up", 90, pivot=(0, 0, 0)) if False else None
    (can if k % 2 == 0 else stp).append(pan)
    val = []
    for i in range(5):
        a = i / 4
        val.append((2.0 + 0.02, -0.4 - 0.45 * math.sin(math.pi * a)))
    vp = rbox(2.0, 0.6, 0.06, x0 + 1, -0.68, 2.02, bev=0.02, segs=1)
    (can if k % 2 == 0 else stp).append(vp)
# (the prisms run along x: the slope rises from the front (+z, low) to the wall (-z, high))
add(G, "ShopAwning", "AwningCloth", can, WHITE, "Fabric", tint=True)
add(G, "ShopAwning", "AwningStripes", stp, WHITE, "Fabric")
arms = [T([(x, 0.9, -2.0), (x, -0.3, 1.9)], [0.07, 0.07], segs=5) for x in (-12.6, 0, 12.6)]
arms += [T([(x, -0.6, -2.0), (x, 0.2, 0.0)], [0.05, 0.05], segs=4) for x in (-12.6, 12.6)]
add(G, "ShopAwning", "AwningArms", arms, DARK, "Metal")

# ================================================================ a pool's coping (ring, frame 20 x 0.6 x 1.2): a
# rounded white stone lip round the water box
look("PoolEdge", (20, 0.6, 1.2), ring=True)
add(G, "PoolEdge", "PoolEdge", [prism([(0.6, -0.3), (-0.45, -0.3), (-0.6, -0.1), (-0.6, 0.2), (-0.45, 0.35), (0.6, 0.35)], -10, 10)],
    (236, 232, 222))

# ================================================================ pools (nate 2026-11-19: "pools need to look better as
# well"): a ladder over the coping (frame 2 x 4 x 1: the rails hook over the edge at z 0 and drop into the water at
# +z) and sun loungers (frame 2.4 x 1.4 x 6, the head at +z; the cushion takes the box's colour)
look("PoolLadder", (2, 4, 1))
lad = []
for x in (-0.8, 0.8):
    lad.append(T([(x, -0.2, -0.9), (x, 1.3, -0.9), (x, 1.75, -0.45), (x, 1.75, 0.15), (x, 1.2, 0.6), (x, -1.9, 0.6)],
                 [0.07] * 6, segs=6))
for y in (0.6, -0.4, -1.4):
    lad.append(B(1.5, 0.08, 0.3, 0, y, 0.62))
add(G, "PoolLadder", "PoolLadder", lad, (214, 220, 228), "Metal")
look("Lounger", (2.4, 1.4, 6))
lf = []
for x in (-1.05, 1.05):
    lf.append(T([(x, -0.7, -2.8), (x, -0.1, -2.6), (x, -0.1, 1.2), (x, 0.9, 2.8)], [0.06] * 4, segs=5))
    lf.append(T([(x, -0.1, 1.0), (x, -0.7, 1.4)], [0.05, 0.05], segs=4))
    lf.append(TOR(0.2, 0.06, x, -0.5, -2.6, axis="x", segs=8, csegs=4))
for z in (-2.4, -1.4, -0.4, 0.6):
    lf.append(B(2.1, 0.06, 0.5, 0, -0.08, z))
add(G, "Lounger", "LoungerFrame", lf, (236, 236, 232))
cu = [rbox(1.9, 0.22, 3.8, 0, 0.08, -0.85, bev=0.08, segs=2)]
bk = rbox(1.9, 0.22, 1.8, 0, 0, 0, bev=0.08, segs=2)
turn(bk, "x", 32)
shift(bk, rb(0, 0.5, 1.95))
cu.append(bk)
cu.append(C(0.28, 1.6, -0.8, 0.95, 2.6, segs=10, axis="x"))
add(G, "Lounger", "LoungerCushion", cu, WHITE, "Fabric", tint=True)

# ---------------------------------------------------------------- a pond's rim (frame 30 x 0.6 x 30: the round water
# box stays; stones and reeds round its edge, lily pads on it)
look("PondRim", (30, 0.6, 30))
st, reeds, pads = [], [], []
NSTONE = 22
for k in range(NSTONE):
    a = k * 2 * math.pi / NSTONE + 0.1 * math.sin(k * 3.1)
    rr = 0.9 + 0.35 * ((k * 5) % 3)
    st.append(P(boulder(rr, (math.cos(a) * 15.2, 0.1, math.sin(a) * 15.2), 40 + k, (1.3, 0.55, 1.0), -0.3), STONE))
for k in range(6):
    a = k * 1.13 + 0.4
    cx_, cz_ = math.cos(a) * 14.2, math.sin(a) * 14.2
    for j in range(7):
        b_ = j * 0.9 + k
        h = 2.2 + 0.9 * ((j * 7) % 3) / 2
        reeds.append(T([(cx_ + math.cos(b_) * 0.4, 0.0, cz_ + math.sin(b_) * 0.4), (cx_ + math.cos(b_) * 0.8, h, cz_ + math.sin(b_) * 0.8)],
                       [0.07, 0.02], segs=4))
    reeds.append(C(0.1, 0.7, cx_, 2.6, cz_, segs=6))
for (x, z, r) in ((-5, 3, 1.3), (-3.5, 5.5, 1.0), (4, -6, 1.2), (7, -4, 0.9), (2, 8, 1.1)):
    pad = C(r, 0.05, x, 0.33, z, segs=12)
    pads.append(pad)
add(G_STONE, "PondRim", "PondStones", st)
add(G, "PondRim", "PondReeds", reeds, (96, 140, 70), "Grass")
add(G, "PondRim", "PondPads", pads, (90, 160, 80), "SmoothPlastic")

# ================================================================ Radio Hill's mast (frame 3 x 120 x 3, a cylinder box on
# the hill's top step): a three-legged lattice in red and white sections, two rest platforms, dishes, a red light
look("RadioMast", (3, 120, 3))
reds, whites = [], []
RL = 1.5
legs = [(math.cos(a) * RL, math.sin(a) * RL) for a in (math.pi / 2, math.pi / 2 + 2 * math.pi / 3, math.pi / 2 + 4 * math.pi / 3)]
SEC = 20
for k in range(6):
    y0, y1 = -60 + k * SEC, -60 + (k + 1) * SEC
    out = reds if k % 2 == 1 else whites
    for (x, z) in legs:
        out.append(C(0.16, SEC, x, (y0 + y1) / 2, z, segs=5))
    for j in range(4):
        ya, yb = y0 + j * 5, y0 + (j + 1) * 5
        for i in range(3):
            (xa, za), (xb, zb) = legs[i], legs[(i + 1) % 3]
            out.append(T([(xa, ya, za), (xb, yb, zb)], [0.07, 0.07], segs=4))
            out.append(T([(xa, yb, za), (xb, yb, zb)], [0.06, 0.06], segs=4))
plat = []
for y in (-20.0, 20.0):
    plat.append(C(2.6, 0.2, 0, y, 0, segs=12))
    plat.append(TOR(2.5, 0.06, 0, y + 1.0, 0, segs=12, csegs=3))
    for k in range(6):
        a = k * math.pi / 3
        plat.append(C(0.05, 1.0, math.cos(a) * 2.5, y + 0.5, math.sin(a) * 2.5, segs=4))
for (y, a) in ((8.0, 0.3), (30.0, 2.4)):
    d = C(1.4, 0.4, 0, 0, 0, segs=14, r2=0.6, axis="z")
    turn(d, "up", math.degrees(a))
    shift(d, rb(math.cos(a) * 2.4, y, math.sin(a) * 2.4))
    plat.append(d)
plat.append(C(0.12, 6.0, 0, 63.0, 0, segs=6))
add(G, "RadioMast", "MastRed", reds, RED, "Metal")
add(G, "RadioMast", "MastWhite", whites, WHITE, "Metal")
add(G, "RadioMast", "MastKit", plat, (120, 126, 134), "Metal")
add(G, "RadioMast", "MastLight", [S(0.45, 0, 66.2, 0, segs=8, rings=5)], (255, 60, 50), "Neon")

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
    if RING.get(lk):
        rows.append("\t\tring = true,")
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
print("shapes: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for lk in sorted(LOOKS):
    print("  %-14s %6d tris  (%s)" % (lk, sum(TRIS[n] for n in LOOKS[lk]), ", ".join(sorted(LOOKS[lk]))))
text = "\n".join([
    "-- GENERATED by art/blender/shapes.py: do not edit by hand.",
    "-- Round 2 of the living world (ReplicatedStorage.Art.Shapes; Shared.LifeKit): look -> its frame (the box it is",
    "-- drawn over, studs x, up, z), ring (a moulding run LifeKit lays along each edge of the box) and its meshes: each",
    "-- mesh's size and centre from the frame's middle, colour, material, transparency, maps (a baked texture set in its",
    "-- SurfaceAppearance), tint (the box's palette colour paints it) and triangles. %d meshes in %d looks, %d triangles."
    % (len(TRIS), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "ShapeArt.luau"))
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
        filepath=os.path.join(kit.ROOT, "export", "Shapes.fbx"), use_selection=True,
        apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        path_mode="COPY", embed_textures=True)
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    import shapes_preview  # noqa: E402

    shapes_preview.run(GROUPS, LOOKS, FRAMES, INFO, MAPS, fast=FAST)
