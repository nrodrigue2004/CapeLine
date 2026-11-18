# belts.py: the hero creator's belts as meshes (creator art round 3, 2026-11-18), in place of the boxes, balls and
# wedges PieceKits welds to the waist for the Belt slot. A belt is a strap that hugs the blocky lower torso (2 x 1,
# z 2.0 to 2.4; kit.py axes: +y the front) with its buckle, pouches, tools or knots; the thigh holsters also strap
# round each upper leg. Each piece is welded to its own body part (the waist, or each thigh), one colour a mesh.
# Bright, chunky comic shapes that read on a phone at a distance; all original.
# Output: art/export/Belts.fbx (nate imports it as ReplicatedStorage.Art.Belts), src/config/BeltArt.luau
# (LookKit's fit) and art/preview/belts.png (each kit from the front three-quarter and from behind).
# Run: python art/blender/belts.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, ring, rbox, ball, rod, joined, outline, strip  # noqa: E402
import bpy  # noqa: E402, F401

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2400  # triangles a belt
FY = 0.545  # the belt's front (the lower torso's front is y = 0.5)
BZ = 2.24  # the belt line

kit.reset()

STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


def W(ob, role, glow=False, mat=None, alpha=0.0, at="waist"):
    wear.bake(ob)
    return Piece(ob, at, role, glow, mat, alpha)


def strap(name="Strap", z0=BZ - 0.09, z1=BZ + 0.09, rx=1.05, ry=0.55, thick=0.05, wave=None, na=48):
    return ring(name, [(z0, rx, ry), ((z0 + z1) / 2, rx + 0.006, ry + 0.006), (z1, rx, ry)], power=12, na=na,
                thick=thick, wave=wave)


def frame_buckle(name, w, h, bar, depth, at, prong=True):
    """A square buckle frame (a hole in the middle) with its prong, facing +y."""
    x, y, z = at
    parts = [rbox("t", w, depth, bar, at=(x, y, z + h / 2 - bar / 2), bev=0.012),
             rbox("b", w, depth, bar, at=(x, y, z - h / 2 + bar / 2), bev=0.012),
             rbox("l", bar, depth, h, at=(x - w / 2 + bar / 2, y, z), bev=0.012),
             rbox("r", bar, depth, h, at=(x + w / 2 - bar / 2, y, z), bev=0.012)]
    if prong:
        parts.append(rbox("p", w * 0.55, depth * 0.7, bar * 0.45, at=(x + w * 0.1, y + depth * 0.2, z), bev=0.006))
    return joined(name, parts, 30)


def pouch(name, w, d, h, at, flap=True):
    """A rounded pouch on the belt's front (its back against the strap) and its flap."""
    x, y, z = at
    body = rbox(name, w, d, h, at=(x, y + d / 2, z), bev=0.05, segs=2)
    if not flap:
        return body, None
    f = rbox(name + "Flap", w * 1.06, d * 1.12, h * 0.36, at=(x, y + d / 2 + 0.01, z + h / 2 - h * 0.14), bev=0.04)
    return body, f


def tassel(name, at, length=0.18, r=0.07):
    x, y, z = at
    knot = ball("k", r * 0.8, (x, y, z), segs=10, rings=6)
    skirt = wear.cone("c", r * 0.35, r * 1.1, length, (x, y, z - length), segs=10, axis=(0, 0, 1))
    return joined(name, [knot, skirt], 60)


# ---------------------------------------------------------------- the 15 kits
@style("plain")
def b_plain():
    s = strap(thick=0.05)
    loop = rbox("Loop", 0.12, 0.05, 0.22, at=(-0.42, FY + 0.03, BZ), bev=0.015)
    tipb = rbox("Tip", 0.4, 0.05, 0.15, at=(-0.24, FY + 0.03, BZ), bev=0.03)
    buckle = frame_buckle("Buckle", 0.36, 0.28, 0.07, 0.06, (0.0, FY + 0.05, BZ))
    return [W(joined("Strap", [s, loop, tipb]), "dark", mat="Leather"), W(buckle, "gold", mat="Metal")]


@style("utility")
def b_utility():
    s = strap(z0=BZ - 0.11, z1=BZ + 0.11, thick=0.06)
    bodies, flaps = [], []
    for x in (-0.78, -0.4, 0.4, 0.78):
        b, f = pouch("P", 0.3, 0.17, 0.32, (x, FY, BZ - 0.03))
        bodies.append(b)
        flaps.append(f)
    disc = kit.cyl("Disc", 0.17, 0.17, 0.06, at=(0, FY + 0.05, BZ), segs=24, axis="Y")
    kit.shade_auto(disc, 40)
    rim = kit.torus("Rim", 0.17, 0.03, at=(0, FY + 0.08, BZ), segs=24, csegs=6, axis="Y")
    kit.shade_auto(rim, 60)
    return [W(s, "s", mat="Leather"), W(joined("Pouches", bodies), "s", mat="Leather"),
            W(joined("Flaps", flaps), "dark", mat="Leather"), W(disc, "a", True), W(rim, "gold", mat="Metal")]


@style("sash")
def b_sash():
    folds = lambda a, z: 0.018 * math.sin(a * 9 + z * 30)  # noqa: E731
    s = ring("Sash", [(BZ - 0.17, 1.05, 0.55), (BZ, 1.075, 0.575), (BZ + 0.17, 1.05, 0.55)], power=12, na=56,
             thick=0.04, wave=folds)
    knot = ball("Knot", 0.15, (0.72, FY + 0.08, BZ), scale=(1.0, 0.6, 1.0))
    t1 = strip("t1", [(0.7, FY + 0.12, BZ - 0.05), (0.74, FY + 0.14, BZ - 0.35), (0.8, FY + 0.12, BZ - 0.65),
                      (0.86, FY + 0.1, BZ - 0.85)], [0.26, 0.24, 0.22, 0.26], up=(1, 0, 0), thick=0.035)
    t2 = strip("t2", [(0.78, FY + 0.1, BZ - 0.05), (0.92, FY + 0.06, BZ - 0.3), (1.0, FY + 0.02, BZ - 0.55)],
               [0.22, 0.2, 0.22], up=(1, 0, 0.3), thick=0.035)
    return [W(s, "p", mat="Fabric"), W(joined("Knot", [knot, t1, t2]), "p", mat="Fabric")]


@style("rope")
def b_rope():
    # a twisted two-strand rope round the waist, a knot on the left hip, a hanging cord with frayed ends
    strands = []
    n = 88
    path = wear.loop_path(1.07, 0.57, BZ, n, power=12)
    for k in range(2):
        pts = []
        for i in range(n + 1):
            x, y, _ = path[i % n]
            nx, ny = x / 1.07, y / 0.57
            ln = math.hypot(nx, ny) or 1.0
            tw = 2 * PI * 13 * i / n + k * PI
            pts.append((x + nx / ln * 0.03 * math.cos(tw), y + ny / ln * 0.03 * math.cos(tw),
                        BZ + 0.035 * math.sin(tw)))
        strands.append(rod("s%d" % k, pts, 0.04, segs=5))
    knot = ball("Knot", 0.11, (-0.5, FY + 0.06, BZ), scale=(1.1, 0.8, 1.0), segs=10, rings=6)
    cord = rod("Cord", [(-0.5, FY + 0.08, BZ - 0.05), (-0.48, FY + 0.1, BZ - 0.3), (-0.44, FY + 0.08, BZ - 0.55)],
               0.035, segs=6)
    cord2 = rod("Cord2", [(-0.54, FY + 0.07, BZ - 0.05), (-0.62, FY + 0.07, BZ - 0.25),
                          (-0.66, FY + 0.05, BZ - 0.42)], 0.035, segs=6)
    ends = [tassel("e1", (-0.44, FY + 0.08, BZ - 0.55), 0.14, 0.06), tassel("e2", (-0.66, FY + 0.05, BZ - 0.42),
                                                                         0.14, 0.06)]
    return [W(joined("Rope", strands + [knot, cord, cord2] + ends, 60), "s", mat="Fabric")]


@style("chain")
def b_chain():
    links = []
    pts = wear.loop_path(1.08, 0.58, BZ, 30, power=12)
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        d = math.atan2(q[1] - p[1], q[0] - p[0])
        lk = kit.torus("l", 0.11, 0.034, at=(0, 0, 0), segs=6, csegs=4)
        for v in lk.data.vertices:
            v.co.y *= 0.62
        if i % 2:
            wear.turn(lk, (PI / 2, 0, 0), (0, 0, 0))
        wear.turn(lk, (0, 0, d), (0, 0, 0))
        for v in lk.data.vertices:
            v.co.x += p[0]
            v.co.y += p[1]
            v.co.z += p[2]
        links.append(lk)
    drop = []
    for k in range(4):
        lk = kit.torus("d", 0.07, 0.02, at=(0, 0, 0), segs=6, csegs=4)
        for v in lk.data.vertices:
            v.co.y *= 0.6
        wear.turn(lk, (0, PI / 2 if k % 2 else 0, PI / 2), (0, 0, 0))
        for v in lk.data.vertices:
            v.co.x += 0.55 + 0.03 * k
            v.co.y += FY + 0.05
            v.co.z += BZ - 0.12 - k * 0.12
        drop.append(lk)
    padlock = rbox("Lock", 0.16, 0.07, 0.14, at=(0.67, FY + 0.06, BZ - 0.62), bev=0.025)
    shackle = kit.torus("Sh", 0.05, 0.016, at=(0.67, FY + 0.06, BZ - 0.54), segs=10, csegs=4, arc=PI, axis="Y")
    return [W(joined("Chain", links + drop, 70), "white", mat="Metal"),
            W(joined("Lock", [padlock, shackle]), "gold", mat="Metal")]


@style("holsters")
def b_holsters():
    s = strap(thick=0.05)
    buckle = frame_buckle("Buckle", 0.3, 0.24, 0.06, 0.05, (0.0, FY + 0.04, BZ))
    out = [W(s, "dark", mat="Leather"), W(buckle, "gold", mat="Metal")]
    # each thigh (left built at x -0.5, z 1.15 to 2.0; mirrored for the right): a strap round it, a drop strap from
    # the belt, and the holster on the outside of the leg
    cx = -0.5
    band = ring("Band", [(1.66, 0.545, 0.545), (1.76, 0.55, 0.55)], power=8, na=32, cx=cx, thick=0.04)
    drop = strip("Drop", [(-1.03, 0.0, 2.02), (-1.05, 0.0, 1.85), (-1.06, 0.0, 1.72)], 0.12, up=(0, 1, 0),
                 thick=0.03)
    out += wear.pair(joined("Band", [band, drop]), "lthigh", "dark", mat="Leather")
    shape = [(-0.16, 0.16), (0.16, 0.16), (0.15, -0.12), (0.06, -0.3), (-0.08, -0.3), (-0.15, -0.12)]
    hol = outline("Holster", shape, 0.16, at=(-1.12, 0.0, 1.72), axis="X", bev=0.03)
    out += wear.pair(hol, "lthigh", "s", mat="Leather")
    flap = rbox("Flap", 0.12, 0.34, 0.12, at=(-1.15, 0.0, 1.87), bev=0.03)
    snap = ball("snap", 0.035, (-1.22, 0.0, 1.84), segs=8, rings=5)
    out += wear.pair(joined("Flap", [flap, snap]), "lthigh", "dark", mat="Leather")
    return out


@style("tech")
def b_tech():
    s = strap(z0=BZ - 0.1, z1=BZ + 0.1, thick=0.06)
    panels = []
    for x in (-0.82, -0.56, -0.3, 0.3, 0.56, 0.82):
        panels.append(rbox("p", 0.22, 0.06, 0.16, at=(x, FY + 0.035, BZ), bev=0.02))
    for a in (PI / 2 + 0.6, -PI / 2 - 0.6, PI):
        x, y = wear.spt(a, 1.08, 0.58, 12)
        panels.append(rbox("p", 0.22 if abs(y) > 0.4 else 0.06, 0.22 if abs(y) < 0.4 else 0.06, 0.16,
                           at=(x, y, BZ), bev=0.02))
    hexa = [(0.2 * math.cos(PI / 6 + k * PI / 3), 0.2 * math.sin(PI / 6 + k * PI / 3)) for k in range(6)]
    plate = outline("Plate", [(1.25 * u, 1.25 * v) for u, v in hexa], 0.06, at=(0, FY + 0.05, BZ), bev=0.015)
    core = outline("Core", hexa, 0.05, at=(0, FY + 0.09, BZ))
    lights = [core] + [rbox("l", 0.12, 0.03, 0.04, at=(x, FY + 0.075, BZ), bev=0.01) for x in (-0.82, -0.56, -0.3,
                                                                                                 0.3, 0.56, 0.82)]
    return [W(s, "dark"), W(joined("Panels", panels + [plate], 30), "s", mat="Metal"),
            W(joined("Lights", lights, 30), "a", True)]


@style("champion")
def b_champion():
    s = strap(z0=BZ - 0.14, z1=BZ + 0.14, thick=0.05)
    oct_ = [(0.42 * math.cos(PI / 8 + k * PI / 4) * 1.1, 0.42 * math.sin(PI / 8 + k * PI / 4) * 0.78)
            for k in range(8)]
    plate = outline("Plate", oct_, 0.07, at=(0, FY + 0.05, BZ), bev=0.025)
    inner = outline("In", [(u * 0.78, v * 0.78) for u, v in oct_], 0.04, at=(0, FY + 0.1, BZ), bev=0.01)
    sides = []
    for sx in (-1, 1):
        sides.append(outline("s", wear.rrect_pts(0.32, 0.3, 0.07), 0.05, at=(sx * 0.62, FY + 0.04, BZ), bev=0.015))
    sides_back = []
    for a in (PI / 2 + 0.25, -PI / 2 - 0.25):
        x, y = wear.spt(a, 1.09, 0.58, 12)
        sides_back.append(rbox("sb", 0.06, 0.3, 0.28, at=(x, y, BZ), bev=0.02))
    gem = ball("Gem", 0.12, (0, FY + 0.15, BZ), scale=(1.0, 0.5, 1.0), segs=12, rings=6)
    studs = [ball("st", 0.028, (0.31 * math.cos(k * PI / 4), FY + 0.14, BZ + 0.22 * math.sin(k * PI / 4)), segs=6,
                  rings=4) for k in range(8)]
    star = outline("Star", wear.star_pts(0.1, 0.045), 0.03, at=(0.62, FY + 0.075, BZ))
    star2 = outline("Star2", wear.star_pts(0.1, 0.045), 0.03, at=(-0.62, FY + 0.075, BZ))
    return [W(s, "p", mat="Leather"), W(joined("Plate", [plate] + sides + sides_back, 30), "gold", mat="Metal"),
            W(joined("Inner", [inner, star, star2], 30), "s", mat="Metal"), W(gem, "a", True),
            W(joined("Studs", studs), "white", mat="Metal")]


@style("studded")
def b_studded():
    s = strap(z0=BZ - 0.1, z1=BZ + 0.1, thick=0.05)
    studs = []
    for i, (x, y, z) in enumerate(wear.loop_path(1.08, 0.58, BZ, 26, power=12)):
        if abs(x) < 0.25 and y > 0:
            continue
        a = math.atan2(x, y)
        n = (math.sin(a), math.cos(a), 0)
        studs.append(wear.cone("c", 0.075, 0.0, 0.1, (x, y, z), segs=4, axis=n))
    buckle = frame_buckle("Buckle", 0.3, 0.26, 0.06, 0.05, (0.0, FY + 0.04, BZ))
    return [W(s, "dark", mat="Leather"), W(joined("Studs", studs, 20), "white", mat="Metal"),
            W(buckle, "white", mat="Metal")]


@style("bigbuckle")
def b_bigbuckle():
    s = strap(thick=0.05)
    shape = [(0.32 * math.cos(PI / 8 + k * PI / 4) * 1.15, 0.32 * math.sin(PI / 8 + k * PI / 4) * 0.82)
             for k in range(8)]
    plate = outline("Plate", shape, 0.08, at=(0, FY + 0.06, BZ - 0.02), bev=0.03)
    rim = []
    for k in range(8):
        a, b = shape[k], shape[(k + 1) % 8]
        rim.append(rod("r", [(a[0] * 0.86, FY + 0.115, BZ - 0.02 + a[1] * 0.86),
                             (b[0] * 0.86, FY + 0.115, BZ - 0.02 + b[1] * 0.86)], 0.018, segs=5))
    star = outline("Star", wear.star_pts(0.15, 0.065), 0.05, at=(0, FY + 0.12, BZ - 0.02), bev=0.01)
    return [W(s, "s", mat="Leather"), W(joined("Buckle", [plate] + rim, 30), "gold", mat="Metal"),
            W(star, "a")]


@style("fanny")
def b_fanny():
    s = strap(z0=BZ - 0.04, z1=BZ + 0.04, thick=0.035)
    bag = ball("Bag", 0.3, (0.32, FY + 0.15, BZ - 0.04), scale=(1.45, 0.62, 0.78), segs=20, rings=10)
    for v in bag.data.vertices:
        if v.co.y < FY + 0.06:
            v.co.y = FY + 0.06 + (v.co.y - FY - 0.06) * 0.2
    zip_pts = []
    for k in range(11):
        t = -1 + 2 * k / 10
        zip_pts.append((0.32 + t * 0.4, FY + 0.15 + 0.17 * math.sqrt(max(0.0, 1 - t * t)) + 0.02,
                        BZ + 0.04 + 0.08 * (1 - t * t)))
    zipper = rod("Zip", zip_pts, 0.022, segs=5)
    pull = rbox("Pull", 0.05, 0.03, 0.12, at=(0.7, FY + 0.24, BZ - 0.02), bev=0.01)
    clip = rbox("Clip", 0.18, 0.05, 0.11, at=(-0.62, FY + 0.03, BZ), bev=0.02)
    return [W(s, "dark"), W(bag, "p", mat="Fabric"), W(joined("Zip", [zipper, clip]), "s"),
            W(pull, "gold", mat="Metal")]


@style("toolbelt")
def b_toolbelt():
    s = strap(thick=0.05)
    loop = rbox("Loop", 0.2, 0.08, 0.2, at=(-0.74, FY + 0.05, BZ - 0.02), bev=0.03)
    pocket, flap = pouch("Pocket", 0.4, 0.2, 0.42, (0.7, FY, BZ - 0.12))
    out = [W(joined("Strap", [s, loop, pocket, flap]), "s", mat="Leather")]
    handle = rod("Handle", [(-0.76, FY + 0.12, BZ + 0.12), (-0.78, FY + 0.12, BZ - 0.55)], [0.045, 0.05], segs=8)
    out.append(W(handle, "dark", mat="Wood"))
    head = rbox("Head", 0.42, 0.12, 0.13, at=(-0.76, FY + 0.12, BZ + 0.18), bev=0.03)
    claw = wear.cone("Claw", 0.06, 0.02, 0.16, (-0.55, FY + 0.12, BZ + 0.18), segs=6, axis=(1, 0, 0.25))
    wr = rod("Wr", [(0.52, FY + 0.24, BZ + 0.3), (0.56, FY + 0.24, BZ - 0.1)], 0.035, segs=6)
    jaw = kit.torus("Jaw", 0.075, 0.028, at=(0.515, FY + 0.24, BZ + 0.36), segs=12, csegs=5, arc=PI * 1.4, axis="Y")
    out.append(W(joined("Tools", [head, claw, wr, jaw], 40), "white", mat="Metal"))
    return out


@style("obi")
def b_obi():
    folds = lambda a, z: 0.012 * math.sin(a * 7)  # noqa: E731
    sash = ring("Obi", [(BZ - 0.22, 1.05, 0.55), (BZ, 1.07, 0.57), (BZ + 0.2, 1.05, 0.55)], power=12, na=56,
                thick=0.04, wave=folds)
    cord = ring("Cord", [(BZ - 0.025, 1.09, 0.59), (BZ + 0.025, 1.09, 0.59)], power=12, na=56, thick=0.03)
    by = -0.6  # the bow on the back
    knot = rbox("Knot", 0.26, 0.14, 0.26, at=(0, by - 0.05, BZ), bev=0.06)
    loops = []
    for sx in (-1, 1):
        lp = ball("l", 0.22, (sx * 0.3, by - 0.08, BZ + 0.05), scale=(1.4, 0.35, 0.9), segs=14, rings=8)
        wear.turn(lp, (0, sx * 0.25, 0), (sx * 0.1, by, BZ))
        loops.append(lp)
    tails = [strip("t", [(sx * 0.06, by - 0.1, BZ - 0.05), (sx * 0.16, by - 0.12, BZ - 0.4),
                         (sx * 0.24, by - 0.1, BZ - 0.7)], [0.22, 0.2, 0.24], up=(1, 0, 0), thick=0.03)
             for sx in (-1, 1)]
    return [W(sash, "p", mat="Fabric"), W(cord, "a", mat="Fabric"),
            W(joined("Bow", [knot] + loops + tails), "s", mat="Fabric")]


@style("capsules")
def b_capsules():
    s = strap(z0=BZ - 0.1, z1=BZ + 0.1, thick=0.05)
    vials, clips = [], []
    for x in (-0.72, -0.42, 0.42, 0.72):
        v = kit.cyl("v", 0.075, 0.075, 0.24, at=(x, FY + 0.1, BZ), segs=8)
        cap1 = ball("c", 0.075, (x, FY + 0.1, BZ + 0.12), scale=(1, 1, 0.7), segs=8, rings=4)
        cap2 = ball("c", 0.075, (x, FY + 0.1, BZ - 0.12), scale=(1, 1, 0.7), segs=8, rings=4)
        vials.append(joined("v", [v, cap1, cap2], 60))
        for dz in (-0.08, 0.08):
            clips.append(kit.torus("k", 0.085, 0.018, at=(x, FY + 0.1, BZ + dz), segs=8, csegs=4))
        clips.append(rbox("b", 0.1, 0.05, 0.22, at=(x, FY + 0.03, BZ), bev=0.015))
    hub = rbox("Hub", 0.3, 0.07, 0.22, at=(0, FY + 0.04, BZ), bev=0.03)
    dot = ball("Dot", 0.05, (0, FY + 0.09, BZ), scale=(1, 0.5, 1), segs=10, rings=5)
    return [W(s, "dark"), W(joined("Vials", vials + [dot], 60), "a", True),
            W(joined("Clips", clips + [hub], 40), "s", mat="Metal")]


@style("cord")
def b_cord():
    pts = wear.loop_path(1.075, 0.575, BZ, 56, power=12)
    pts.append(pts[0])
    cord = rod("Cord", pts, 0.045, segs=7)
    knot = ball("Knot", 0.09, (0, FY + 0.05, BZ), scale=(1.3, 0.8, 1.0), segs=12, rings=6)
    hang = []
    for sx in (-1, 1):
        hang.append(rod("h", [(sx * 0.04, FY + 0.07, BZ - 0.03), (sx * 0.16, FY + 0.1, BZ - 0.3),
                              (sx * 0.22, FY + 0.08, BZ - 0.5)], 0.035, segs=6))
        hang.append(tassel("t", (sx * 0.22, FY + 0.08, BZ - 0.52), 0.2, 0.08))
    return [W(joined("Cord", [cord, knot] + hang, 60), "gold", mat="Fabric")]


# ---------------------------------------------------------------- build, export, preview
HEADER = ["belts.py",
          "The creator's belts as meshes (ReplicatedStorage.Art.Belts once nate imports art/export/Belts.fbx; LookKit",
          "wears them then, the part-built ones until then). Keyed by the Belt slot's kit: each piece's mesh name, the",
          "body part it is welded to (at: the waist, or a thigh), its colour role (the slot's p main, s trim, a accent,",
          "or dark, white, gold, ice, glowRed), glow (Neon), material and transparency, and its box against that",
          "part's centre in Roblox axes (x right, y up, z back), in studs on the standard blocky rig (scaled with it)."]

PARTS = {"UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftUpperArm", "RightUpperArm",
         "LeftLowerArm", "RightLowerArm"}


def preview(built):
    def dress(name, at, yaw, pal):
        wear.body(at, yaw, suit=(150, 156, 170), parts=PARTS)
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", "belts.png" if ONLY is None else "belts_test.png")
    wear.grid_preview(built, out, dress, cols=5, cell=2.7, px=300, focus=2.3, yaw_front=180 - 30, yaw_back=30,
                      samples=32, look_down=0.15)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Belt_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Belts.fbx"))
        wear.write_fit("BeltArt", HEADER, rows)
    preview(built)
