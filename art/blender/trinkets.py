# trinkets.py: the hero creator's small worn pieces as meshes (creator art round 3, 2026-11-18), in place of the
# boxes, balls and cylinders PieceKits welds on for four slots: Ears (earrings, an earpiece, fins, on the head's sides
# at x +-0.6), Neck (chains, pendants, collars, a scarf and a ruff round the neck and over the chest, on the upper
# torso), Rings and bracelets (on the hands and wrists) and Arms (bracers, sleeves, wraps, plates and bands on the
# upper and lower arms). kit.py axes: +y the front; the hero's left is -x, and a left piece is mirrored onto the
# right (a MeshPart cannot be mirrored, so each side is its own mesh). Bright, chunky comic shapes; all original.
# Output: art/export/Ears.fbx, Necks.fbx, Wrists.fbx and Arms.fbx (nate imports them as ReplicatedStorage.Art.Ears,
# .Necks, .Wrists and .Arms), src/config/EarArt.luau, NeckArt, WristArt and ArmArt (LookKit's fits) and the previews
# art/preview/ears.png, necks.png, wrists.png and arms.png.
# Run: python art/blender/trinkets.py [--quick] [--only set]   (sets: ears, neck, wrist, arms; bpy, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, ring, rbox, ball, rod, joined, outline, strip  # noqa: E402
import bpy  # noqa: E402, F401
from mathutils import Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2000

kit.reset()

SETS = {"ears": {}, "neck": {}, "wrist": {}, "arms": {}}


def style(group, name):
    def reg(fn):
        SETS[group][name] = fn
        return fn
    return reg


def P(ob, at, role, glow=False, mat=None, alpha=0.0):
    wear.bake(ob)
    return Piece(ob, at, role, glow, mat, alpha)


def LR(ob, at, role, glow=False, mat=None, alpha=0.0):
    """A left piece (built on the left side) and its mirror on the right, both on `at` (the head or torso) or on
    the left body part and its right twin."""
    if at in wear.MIRROR:
        return wear.pair(ob, at, role, glow, mat, alpha)
    short = ob.name.split(".")[0]
    ob.name = short + "L"
    kit.apply_all(ob)
    r = kit.mirror_x(ob, short + "R")
    return [Piece(ob, at, role, glow, mat, alpha), Piece(r, at, role, glow, mat, alpha)]


# ================================================================ ears (the head: centre z 4.61, sides x +-0.6)
EX = -0.625  # the left side of the head
EZ = 4.55  # the lobe's height


def hoop(name, r, at, tube=0.025):
    t = kit.torus(name, r, tube, at=at, segs=16, csegs=5, axis="X")
    kit.shade_auto(t, 60)
    return t


@style("ears", "studs")
def ear_studs():
    return LR(ball("Stud", 0.075, (EX, 0.02, EZ), segs=10, rings=6), "head", "gold", mat="Metal")


@style("ears", "hoops")
def ear_hoops():
    return LR(hoop("Hoop", 0.13, (EX - 0.02, 0.02, EZ - 0.12), 0.024), "head", "gold", mat="Metal")


@style("ears", "comms")
def ear_comms():
    x = -EX
    pod = rbox("Pod", 0.1, 0.24, 0.3, at=(x + 0.02, 0.0, 4.62), bev=0.04)
    boom = rod("Boom", [(x + 0.04, 0.08, 4.52), (x - 0.02, 0.38, 4.38), (0.3, 0.62, 4.32)], 0.022, segs=5)
    mic = ball("Mic", 0.05, (0.28, 0.63, 4.32), segs=8, rings=5)
    light = ball("Light", 0.04, (x + 0.08, 0.06, 4.7), segs=8, rings=4)
    return [P(joined("Pod", [pod, boom, mic]), "head", "dark"), P(light, "head", "a", True)]


@style("ears", "dangles")
def ear_dangles():
    chain = rod("Chain", [(EX - 0.01, 0.02, EZ), (EX - 0.02, 0.02, EZ - 0.22)], 0.016, segs=5)
    stud = ball("s", 0.04, (EX, 0.02, EZ), segs=8, rings=4)
    gem = ball("Gem", 0.07, (EX - 0.02, 0.02, EZ - 0.3), scale=(0.8, 0.8, 1.3), segs=8, rings=5)
    return LR(joined("Chain", [chain, stud]), "head", "gold", mat="Metal") + LR(gem, "head", "a", True)


@style("ears", "cuffs")
def ear_cuffs():
    cuff = kit.torus("Cuff", 0.12, 0.03, at=(EX, 0.04, 4.72), segs=14, csegs=5, arc=PI * 1.3, axis="X")
    wear.turn(cuff, (0.6, 0, 0), (EX, 0.04, 4.72))
    kit.shade_auto(cuff, 60)
    return LR(cuff, "head", "s", mat="Metal")


@style("ears", "wings")
def ear_wings():
    pts = [(0.0, 0.0), (-0.08, 0.1), (-0.22, 0.24), (-0.14, 0.24), (-0.2, 0.32), (-0.06, 0.26), (0.02, 0.12)]
    w = outline("Wing", [(-u * 1.35, v * 1.35) for u, v in pts], 0.03, at=(EX - 0.02, 0.05, 4.58), axis="X", bev=0.01)
    return LR(w, "head", "gold", mat="Metal")


@style("ears", "gauges")
def ear_gauges():
    g = kit.cyl("Gauge", 0.09, 0.09, 0.06, at=(EX - 0.01, 0.02, EZ - 0.02), segs=14, axis="X")
    rim = kit.torus("Rim", 0.09, 0.02, at=(EX - 0.04, 0.02, EZ - 0.02), segs=14, csegs=4, axis="X")
    return LR(g, "head", "dark") + LR(rim, "head", "s", mat="Metal")


@style("ears", "chain")
def ear_chain():
    links = []
    for k in range(7):
        t = k / 6
        a = PI * 0.15 + PI * 0.7 * t
        c = (EX - 0.03, 0.12 * math.cos(a) - 0.02, 4.78 - 0.28 * t - 0.06 * math.sin(a * 2))
        lk = kit.torus("l", 0.03, 0.01, at=c, segs=6, csegs=4, axis="Y" if k % 2 else "X")
        links.append(lk)
    studs = [ball("s", 0.035, (EX, 0.06, 4.78), segs=6, rings=4), ball("s", 0.035, (EX, 0.02, EZ - 0.0), segs=6,
                                                                      rings=4)]
    return LR(joined("Chain", links + studs, 60), "head", "white", mat="Metal")


@style("ears", "gems")
def ear_gems():
    gem = ball("Gem", 0.08, (EX - 0.01, 0.02, EZ), scale=(0.6, 1, 1), segs=6, rings=4)
    set_ = kit.torus("Set", 0.06, 0.015, at=(EX + 0.01, 0.02, EZ), segs=12, csegs=4, axis="X")
    return LR(gem, "head", "a", mat="Glass") + LR(set_, "head", "gold", mat="Metal")


@style("ears", "fins")
def ear_fins():
    pts = [(0.15, -0.12), (-0.1, -0.15), (-0.3, 0.05), (-0.42, 0.3), (-0.18, 0.18), (0.1, 0.12)]
    f = outline("Fin", pts, 0.05, at=(EX - 0.02, 0.0, 4.62), axis="X", bev=0.015)
    wear.turn(f, (0, 0, -0.25), (EX - 0.02, 0.0, 4.62))
    ribs = [rod("r", [(EX - 0.05, 0.0 + 0.04 * k, 4.55 + 0.02 * k), (EX - 0.08, -0.25 + 0.05 * k, 4.8 + 0.03 * k)],
                0.014, segs=4) for k in range(3)]
    return LR(f, "head", "p") + LR(joined("Ribs", ribs), "head", "s")


# ================================================================ neck (the upper torso: z 2.4 to 4.0, front y 0.5)
NZ = 4.0  # the shoulder line
NY = 0.53  # in front of the chest


def vchain(name="Chain", depth=0.55, r=0.022, x0=0.32):
    """A chain from both sides of the neck down to a point on the chest."""
    pts = []
    for k in range(13):
        t = k / 12
        x = -x0 + 2 * x0 * t
        z = NZ + 0.02 - depth * math.sin(PI * t) ** 0.9
        y = NY - 0.03 + 0.03 * math.sin(PI * t) if abs(x) < x0 * 0.85 else 0.2 + (NY - 0.2) * (x0 - abs(x)) / (
            x0 * 0.15)
        pts.append((x, min(y, NY), z))
    back = [(-x0, 0.2, NZ + 0.02), (-x0 * 0.8, -0.3, NZ + 0.03), (x0 * 0.8, -0.3, NZ + 0.03), (x0, 0.2, NZ + 0.02)]
    return joined(name, [rod("f", pts, r, segs=5), rod("b", back, r, segs=5)], 60)


@style("neck", "chain")
def n_chain():
    return [P(vchain(r=0.028), "torso", "gold", mat="Metal")]


@style("neck", "pendant")
def n_pendant():
    gem = ball("Gem", 0.12, (0, NY + 0.04, NZ - 0.66), scale=(1, 0.5, 1.2), segs=12, rings=6)
    bail = kit.torus("Bail", 0.06, 0.02, at=(0, NY + 0.02, NZ - 0.53), segs=10, csegs=4, axis="X")
    setting = kit.torus("Set", 0.12, 0.025, at=(0, NY + 0.05, NZ - 0.66), segs=16, csegs=4, axis="Y")
    return [P(joined("Chain", [vchain(), bail, setting]), "torso", "gold", mat="Metal"), P(gem, "torso", "a")]


@style("neck", "choker")
def n_choker():
    band = ring("Band", [(4.0, 0.52, 0.48), (4.12, 0.52, 0.48)], power=2.2, na=28, thick=0.04)
    charm = ball("Charm", 0.07, (0, 0.5, 4.04), segs=8, rings=5)
    return [P(band, "torso", "dark", mat="Leather"), P(charm, "torso", "a", True)]


@style("neck", "tags")
def n_tags():
    tags = []
    for k, (dx, rot) in enumerate(((-0.05, 0.12), (0.05, -0.1))):
        t = outline("t", wear.rrect_pts(0.16, 0.26, 0.05), 0.02, at=(dx, NY + 0.03 + 0.012 * k, NZ - 0.62), axis="Y")
        wear.turn(t, (0, rot, 0), (dx, NY, NZ - 0.62))
        tags.append(t)
    return [P(vchain(depth=0.48, r=0.016), "torso", "white", mat="Metal"), P(joined("Tags", tags), "torso", "white",
                                                                               mat="Metal")]


@style("neck", "beads")
def n_beads():
    a, b = [], []
    for k in range(13):
        t = k / 12
        x = -0.36 + 0.72 * t
        z = NZ + 0.01 - 0.5 * math.sin(PI * t)
        (a if k % 2 == 0 else b).append(ball("b", 0.07 if k != 6 else 0.1, (x, NY + 0.02, z), segs=10, rings=6))
    return [P(joined("Beads", a), "torso", "a"), P(joined("Beads2", b), "torso", "s")]


@style("neck", "collar")
def n_collar():
    open_ = lambda aa, z: abs(aa) < 1.25  # noqa: E731
    c = ring("Collar", [(3.98, 0.62, 0.52), (4.2, 0.68, 0.57), (4.42, 0.8, 0.68)], power=2.6, na=28, thick=0.05,
             hole=open_)
    trim = ring("Trim", [(4.4, 0.8, 0.68), (4.46, 0.82, 0.7)], power=2.6, na=28, thick=0.04, hole=open_)
    return [P(c, "torso", "p"), P(trim, "torso", "s")]


@style("neck", "amulet")
def n_amulet():
    stone = outline("Stone", [(0.0, 0.16), (0.12, 0.0), (0.0, -0.16), (-0.12, 0.0)], 0.06,
                    at=(0, NY + 0.05, NZ - 0.66), axis="Y", bev=0.02)
    frame = joined("Frame", [rod("f", [(0.0, NY + 0.03, NZ - 0.48), (0.16, NY + 0.03, NZ - 0.66),
                                       (0.0, NY + 0.03, NZ - 0.84), (-0.16, NY + 0.03, NZ - 0.66),
                                       (0.0, NY + 0.03, NZ - 0.48)], 0.025, segs=5), vchain(depth=0.48)])
    return [P(frame, "torso", "gold", mat="Metal"), P(stone, "torso", "a", True)]


@style("neck", "torc")
def n_torc():
    pts = [(x, y, NZ + 0.02) for x, y in (wear.spt(-2.6 + 5.2 * k / 18, 0.56, 0.52, 2.2) for k in range(19))]
    torc = rod("Torc", pts, [0.05 + 0.03 * math.sin(PI * k / 18) for k in range(19)], segs=7)
    knobs = [ball("k", 0.075, pts[0], segs=10, rings=6), ball("k", 0.075, pts[-1], segs=10, rings=6)]
    return [P(joined("Torc", [torc] + knobs), "torso", "gold", mat="Metal")]


@style("neck", "scarf")
def n_scarf():
    wrap = kit.torus("Wrap", 0.46, 0.13, at=(0, -0.02, 4.06), segs=24, csegs=8)
    for v in wrap.data.vertices:
        a = math.atan2(v.co.x, v.co.y + 0.02)
        v.co.z += 0.03 * math.sin(a * 3)
    kit.shade_auto(wrap, 70)
    tail = strip("Tail", [(0.25, 0.5, 4.0), (0.3, 0.6, 3.7), (0.32, 0.58, 3.4), (0.36, 0.56, 3.15)],
                 [0.28, 0.27, 0.26, 0.28], up=(1, 0, 0), thick=0.04)
    fringe = [rod("f", [(0.25 + 0.06 * k, 0.56, 3.15), (0.25 + 0.06 * k, 0.56, 3.05)], 0.015, segs=4)
              for k in range(4)]
    return [P(joined("Scarf", [wrap, tail]), "torso", "p", mat="Fabric"), P(joined("Fringe", fringe), "torso", "s",
                                                                             mat="Fabric")]


@style("neck", "kerchief")
def n_kerchief():
    band = ring("Band", [(4.02, 0.5, 0.46), (4.1, 0.5, 0.46)], power=2.6, na=24, thick=0.04)
    tri = outline("Tri", [(-0.36, 0.0), (0.36, 0.0), (0.0, -0.42)], 0.035, at=(0, NY + 0.02, 4.02), axis="Y",
                  bev=0.01)
    knot = ball("Knot", 0.07, (0, -0.5, 4.06), segs=8, rings=5)
    return [P(joined("Kerchief", [band, tri, knot]), "torso", "s", mat="Fabric")]


@style("neck", "medal")
def n_medal():
    ribbon = []
    for sx in (-1, 1):
        ribbon.append(strip("r", [(sx * 0.3, 0.3, NZ + 0.02), (sx * 0.12, NY, NZ - 0.25), (sx * 0.03, NY + 0.01,
                                                                                         NZ - 0.5)],
                            0.12, up=(1, 0, 0), thick=0.02))
    back = strip("rb", [(-0.3, 0.3, NZ + 0.02), (0.0, -0.4, NZ + 0.04), (0.3, 0.3, NZ + 0.02)], 0.12, up=(0, 0, 1),
                 thick=0.02)
    disc = kit.cyl("Disc", 0.17, 0.17, 0.05, at=(0, NY + 0.04, NZ - 0.66), segs=20, axis="Y")
    star = outline("Star", wear.star_pts(0.11, 0.05), 0.02, at=(0, NY + 0.075, NZ - 0.66), axis="Y")
    return [P(joined("Ribbon", ribbon + [back]), "torso", "a", mat="Fabric"), P(disc, "torso", "gold", mat="Metal"),
            P(star, "torso", "s")]


@style("neck", "whistle")
def n_whistle():
    body = kit.cyl("Body", 0.07, 0.07, 0.26, at=(0.02, NY + 0.06, NZ - 0.58), segs=12, axis="X")
    mouth = rbox("Mouth", 0.14, 0.09, 0.06, at=(-0.16, NY + 0.06, NZ - 0.56), bev=0.015)
    cord = vchain(depth=0.5, r=0.02)
    return [P(joined("Whistle", [body, mouth]), "torso", "white", mat="Metal"), P(cord, "torso", "a", mat="Fabric")]


@style("neck", "fang")
def n_fang():
    cord = ring("Cord", [(4.01, 0.52, 0.48), (4.05, 0.52, 0.48)], power=2.6, na=24, thick=0.03)
    drop = rod("Drop", [(0, NY - 0.02, 4.02), (0, NY + 0.02, 3.8)], 0.02, segs=4)
    fang = wear.cone("Fang", 0.1, 0.0, 0.4, (0, NY + 0.03, 3.8), segs=8, axis=(0.15, 0.1, -1))
    return [P(joined("Cord", [cord, drop]), "torso", "dark", mat="Leather"), P(fang, "torso", "white")]


@style("neck", "neckphones")
def n_neckphones():
    band = kit.torus("Band", 0.5, 0.05, at=(0, -0.05, 4.04), segs=24, csegs=5, arc=PI, axis="Z")
    wear.turn(band, (0, 0, PI), (0, -0.05, 4.04))
    cups = [kit.cyl("c", 0.2, 0.2, 0.14, at=(sx * 0.6, 0.12, 4.08), segs=18, axis="X") for sx in (-1, 1)]
    pads = [kit.torus("p", 0.15, 0.05, at=(sx * 0.52, 0.12, 4.08), segs=14, csegs=5, axis="X") for sx in (-1, 1)]
    return [P(joined("Band", [band] + pads), "torso", "dark"), P(joined("Cups", cups), "torso", "s")]


@style("neck", "ruff")
def n_ruff():
    rr = [(4.0, 0.42, 0.4), (4.08, 0.66, 0.6), (4.18, 0.78, 0.72), (4.26, 0.72, 0.66)]
    ruff = ring("Ruff", rr, power=2.0, na=48, thick=0.03, wave=lambda a, z: 0.1 * math.sin(a * 20) *
                (z - 3.98) * 4)
    return [P(ruff, "torso", "white", mat="Fabric")]


# ================================================================ wrist (hands z 2.0 to 2.3, the wrist z 2.34)
WX = -1.5
WZ = 2.34


def band_on(name, z, r=0.56, h=0.1, cx=WX, thick=0.04, power=10.0, wave=None):
    return ring(name, [(z - h / 2, r, r), (z + h / 2, r, r)], power=power, na=28, cx=cx, thick=thick, wave=wave)


def finger_ring(name, x, y=0.44, z=2.15, r=0.17):
    """A band round the hand's front edge (the blocky hand has no fingers: it wraps the slab where they are)."""
    t = kit.torus(name, r, 0.035, at=(x, y, z), segs=16, csegs=5, axis="X")
    kit.shade_auto(t, 60)
    return t


@style("wrist", "ring")
def w_ring():
    r = finger_ring("RingR", 1.7)
    gem = ball("GemR", 0.06, (1.7, 0.47, 2.33), segs=8, rings=5)
    return [P(r, "rhand", "gold", mat="Metal"), P(gem, "rhand", "a", True)]


@style("wrist", "bracelet")
def w_bracelet():
    return [P(band_on("BraceletL", WZ, h=0.1), "llarm", "gold", mat="Metal")]


@style("wrist", "rings")
def w_rings():
    r = finger_ring("Ring", WX - 0.2)
    return LR(r, "lhand", "gold", mat="Metal")


@style("wrist", "cuffs")
def w_cuffs():
    c = band_on("Cuff", WZ + 0.08, r=0.57, h=0.26, power=7.0)
    rivets = [ball("r", 0.035, (WX + 0.57 * math.sin(a), 0.57 * math.cos(a), WZ + 0.08), segs=6, rings=4)
              for a in (-2.4, -1.2, 0.0, 1.2, 2.4)]
    return LR(c, "llarm", "s", mat="Metal") + LR(joined("Rivets", rivets), "llarm", "white", mat="Metal")


@style("wrist", "beads")
def w_beads():
    bs = []
    for k, (x, y, z) in enumerate(wear.loop_path(0.56, 0.56, WZ, 14, power=10, cx=WX)):
        bs.append(ball("b", 0.06, (x, y, z), segs=8, rings=5))
    charm = ball("Charm", 0.08, (WX, 0.62, WZ - 0.04), segs=10, rings=6)
    return [P(joined("BeadsL", bs, 60), "llarm", "a"), P(joined("CharmL", [charm]), "llarm", "s")]


@style("wrist", "power")
def w_power():
    b = band_on("Band", WZ, r=0.56, h=0.12)
    return LR(b, "llarm", "a", True)


@style("wrist", "watch")
def w_watch():
    strap = band_on("StrapL", WZ + 0.04, r=0.555, h=0.1)
    face = kit.cyl("FaceL", 0.13, 0.13, 0.06, at=(WX - 0.55, 0.0, WZ + 0.04), segs=18, axis="X")
    glass = kit.cyl("GlassL", 0.1, 0.1, 0.02, at=(WX - 0.59, 0.0, WZ + 0.04), segs=18, axis="X")
    return [P(strap, "llarm", "dark", mat="Leather"), P(face, "llarm", "s", mat="Metal"),
            P(glass, "llarm", "a", True)]


@style("wrist", "bangles")
def w_bangles():
    bs = [band_on("b", WZ + 0.12 * k, r=0.57 + 0.01 * k, h=0.05, thick=0.035) for k in range(3)]
    return [P(joined("BanglesL", bs[::2]), "llarm", "gold", mat="Metal"), P(joined("BangleL", [bs[1]]), "llarm", "a"),
            P(joined("BanglesR", [band_on("c", WZ + 0.06, r=0.575, h=0.05, thick=0.035, cx=-WX)]), "rlarm", "gold",
              mat="Metal")]


@style("wrist", "sweatband")
def w_sweatband():
    ribs = lambda a, z: 0.008 * math.cos(a * 20)  # noqa: E731
    return LR(band_on("Band", WZ + 0.08, r=0.575, h=0.24, thick=0.06, wave=ribs), "llarm", "white", mat="Fabric")


@style("wrist", "links")
def w_links():
    links = []
    for k, (x, y, z) in enumerate(wear.loop_path(0.57, 0.57, WZ, 12, power=10, cx=WX)):
        a = math.atan2(x - WX, y)
        lk = kit.torus("l", 0.08, 0.022, at=(0, 0, 0), segs=6, csegs=4)
        if k % 2:
            wear.turn(lk, (PI / 2, 0, 0), (0, 0, 0))
        wear.turn(lk, (0, 0, -a), (0, 0, 0))
        for v in lk.data.vertices:
            v.co += Vector((x, y, z))
        links.append(lk)
    return LR(joined("Links", links, 70), "llarm", "white", mat="Metal")


@style("wrist", "studs")
def w_studs():
    b = band_on("Band", WZ + 0.06, r=0.565, h=0.2)
    studs = []
    for k, (x, y, z) in enumerate(wear.loop_path(0.58, 0.58, WZ + 0.06, 10, power=10, cx=WX)):
        a = math.atan2(x - WX, y)
        studs.append(wear.cone("s", 0.05, 0.0, 0.08, (x, y, z), segs=4, axis=(math.sin(a), math.cos(a), 0)))
    return LR(b, "llarm", "dark", mat="Leather") + LR(joined("Studs", studs), "llarm", "white", mat="Metal")


@style("wrist", "gemring")
def w_gemring():
    r = finger_ring("RingR", 1.7)
    gem = outline("GemR", [(0.0, 0.1), (0.12, 0.0), (0.0, -0.1), (-0.12, 0.0)], 0.08, at=(1.7, 0.47, 2.36), axis="Z",
                  bev=0.02)
    prongs = [rod("p", [(1.7 + dx, 0.47 + dy, 2.32), (1.7 + dx * 1.2, 0.47 + dy * 1.2, 2.39)], 0.015, segs=4)
              for dx, dy in ((0.1, 0.0), (-0.1, 0.0), (0.0, 0.08), (0.0, -0.08))]
    return [P(joined("RingR", [r] + prongs), "rhand", "gold", mat="Metal"), P(gem, "rhand", "a", mat="Glass")]


# ================================================================ arms (upper arm z 3.15 to 4.0, lower 2.3 to 3.15)
AX = -1.5
UZ = 3.575  # the upper arm's centre
LZ = 2.725  # the lower arm's centre


def sleeve(name, z0, z1, r=0.56, power=10.0, thick=0.04, wave=None, na=20):
    return ring(name, [(z0, r, r), ((z0 + z1) / 2, r + 0.005, r + 0.005), (z1, r, r)], power=power, na=na, cx=AX,
                thick=thick, wave=wave)


@style("arms", "bracers")
def a_bracers():
    guard = ring("Guard", [(2.36, 0.56, 0.56), (2.6, 0.58, 0.58), (2.9, 0.6, 0.6), (3.0, 0.6, 0.6)], power=10,
                 na=28, cx=AX, thick=0.05)
    ridge = rod("Ridge", [(AX - 0.62, 0.0, 2.4), (AX - 0.64, 0.0, 2.95)], 0.04, segs=6)
    trim = sleeve("Trim", 3.0, 3.08, r=0.615)
    return LR(joined("Guard", [guard, ridge]), "llarm", "s", mat="Metal") + LR(trim, "llarm", "a")


@style("arms", "sleeves")
def a_sleeves():
    s = sleeve("Sleeve", 3.16, 3.98, r=0.56, wave=lambda a, z: 0.012 * math.sin(a * 5 + z * 9))
    cuff = sleeve("Cuff", 3.14, 3.26, r=0.58)
    return LR(s, "luarm", "s", mat="Fabric") + LR(cuff, "luarm", "s", mat="Fabric")


@style("arms", "wraps")
def a_wraps():
    turns = []
    for k in range(6):
        z = 2.42 + 0.12 * k
        turns.append(ring("w", [(z - 0.06, 0.56, 0.56), (z + 0.06, 0.565, 0.565)], power=10, na=16, cx=AX, thick=0.03))
        wear.turn(turns[-1], (0.1 * (1 if k % 2 else -1), 0, 0), (AX, 0, z))
    tie = strip("Tie", [(AX - 0.56, 0.1, 3.08), (AX - 0.7, 0.15, 2.95), (AX - 0.75, 0.2, 2.8)], 0.08, up=(0, 1, 0),
                thick=0.02)
    return LR(joined("Wraps", turns + [tie]), "llarm", "white", mat="Fabric")


@style("arms", "bands")
def a_bands():
    b = [sleeve("b", z - 0.05, z + 0.05, r=0.57) for z in (3.7, 3.5)]
    return LR(joined("Bands", b), "luarm", "a")


@style("arms", "tattoo")
def a_tattoo():
    # a tribal sweep of thin dark strokes on the outside of the upper arm
    strokes = []
    for k in range(3):
        pts = []
        for j in range(8):
            t = j / 7
            pts.append((AX - 0.565, -0.3 + 0.6 * t, 3.3 + 0.12 * k + 0.25 * math.sin(PI * t) - 0.1 * t))
        strokes.append(strip("s", pts, [0.03 + 0.05 * math.sin(PI * j / 7) for j in range(8)], up=(0, 0, 1),
                             thick=0.01))
    return LR(joined("Ink", strokes), "luarm", "dark", alpha=0.15)


@style("arms", "spikes")
def a_spikes():
    sp = [wear.cone("s", 0.08, 0.0, 0.3, (AX - 0.55, 0.0, z), segs=6, axis=(-1, 0, 0.5)) for z in (2.55, 2.8, 3.02)]
    base = sleeve("Base", 2.45, 3.08, r=0.565)
    return LR(base, "llarm", "dark", mat="Leather") + LR(joined("Spikes", sp), "llarm", "white", mat="Metal")


@style("arms", "armor")
def a_armor():
    up = ring("Up", [(3.3, 0.57, 0.57), (3.6, 0.6, 0.6), (3.9, 0.58, 0.58)], power=10, na=18, cx=AX, thick=0.05)
    low = ring("Low", [(2.42, 0.57, 0.57), (2.75, 0.6, 0.6), (3.05, 0.58, 0.58)], power=10, na=18, cx=AX, thick=0.05)
    edge_u = sleeve("eu", 3.28, 3.33, r=0.6)
    edge_l = sleeve("el", 3.03, 3.08, r=0.6)
    return (LR(up, "luarm", "s", mat="Metal") + LR(low, "llarm", "s", mat="Metal") + LR(edge_u, "luarm", "a")
            + LR(edge_l, "llarm", "a"))


@style("arms", "coils")
def a_coils():
    c = [sleeve("c", z - 0.04, z + 0.04, r=0.6, thick=0.06) for z in (2.85, 2.58)]
    return LR(joined("Coils", c), "llarm", "a", True)


@style("arms", "elbowpads")
def a_elbowpads():
    pad = ball("Pad", 0.32, (AX, -0.5, 3.02), scale=(1.0, 0.4, 0.75), segs=14, rings=8)
    strap = sleeve("Strap", 2.98, 3.06, r=0.57)
    return LR(pad, "llarm", "dark", mat="Rubber") + LR(strap, "llarm", "dark", mat="Rubber")


@style("arms", "rolled")
def a_rolled():
    s = sleeve("Sleeve", 3.16, 3.98, r=0.56)
    roll = ring("Roll", [(3.12, 0.58, 0.58), (3.2, 0.62, 0.62), (3.3, 0.6, 0.6)], power=10, na=28, cx=AX, thick=0.04,
                wave=lambda a, z: 0.015 * math.sin(a * 4))
    return LR(joined("Sleeve", [s, roll]), "luarm", "white", mat="Fabric")


@style("arms", "chains")
def a_chains():
    links = []
    for zc, tilt in ((2.85, 0.2), (2.6, -0.2)):
        for k, (x, y, z) in enumerate(wear.loop_path(0.58, 0.58, zc, 12, power=10, cx=AX)):
            a = math.atan2(x - AX, y)
            lk = kit.torus("l", 0.07, 0.02, at=(0, 0, 0), segs=6, csegs=3)
            if k % 2:
                wear.turn(lk, (PI / 2, 0, 0), (0, 0, 0))
            wear.turn(lk, (0, 0, -a), (0, 0, 0))
            for v in lk.data.vertices:
                v.co += Vector((x, y, z + tilt * (x - AX)))
            links.append(lk)
    return LR(joined("Chains", links, 70), "llarm", "white", mat="Metal")


@style("arms", "fins")
def a_fins():
    f = outline("Fin", [(0.3, -0.3), (-0.2, -0.32), (-0.62, 0.28), (-0.42, 0.3), (0.1, 0.02)], 0.05,
                at=(AX - 0.55, 0.0, 2.75), axis="X", bev=0.015)
    for v in f.data.vertices:
        v.co.x -= 0.12 * max(0.0, v.co.z - 2.45)
    return LR(f, "llarm", "a") + LR(sleeve("Base", 2.42, 2.52, r=0.57), "llarm", "s")


@style("arms", "runes")
def a_runes():
    band = sleeve("Band", 3.65, 3.75, r=0.57)
    marks = []
    for k, a in enumerate((-2.0, -1.0, 0.0, 1.0, 2.0)):
        x, y = wear.spt(a - PI / 2, 0.575, 0.575, 10)
        c = Vector((AX + x, y, 3.42))
        pts = [(0.0, 0.1), (0.06, 0.0), (0.0, -0.1), (-0.06, 0.0)] if k % 2 else [(-0.06, 0.08), (0.06, 0.08),
                                                                                  (0.0, -0.1)]
        m = outline("m", pts, 0.02, at=(0, 0, 0), axis="Y")
        n = Vector((x, y, 0)).normalized()
        q = Vector((0, 1, 0)).rotation_difference(n)
        from mathutils import Matrix
        m.data.transform(Matrix.Translation(c) @ q.to_matrix().to_4x4())
        marks.append(m)
    return LR(joined("Runes", [band] + marks, 30), "luarm", "a", True)


@style("arms", "scales")
def a_scales():
    sc = []
    for row, z in enumerate((2.95, 2.75, 2.55)):
        for k in range(6):
            a = -PI + 2 * PI * (k + 0.5 * (row % 2)) / 6
            x, y = wear.spt(a, 0.58, 0.58, 10)
            s = ball("s", 0.21, (0, 0, 0), scale=(1.0, 0.35, 0.8), segs=6, rings=4)
            n = Vector((x, y, 0)).normalized()
            from mathutils import Matrix
            q = Vector((0, 1, 0)).rotation_difference(n)
            s.data.transform(Matrix.Translation(Vector((AX + x, y, z))) @ q.to_matrix().to_4x4())
            sc.append(s)
    return LR(sleeve("Base", 2.45, 3.08, r=0.56), "llarm", "s", mat="Metal") + LR(joined("Scales", sc, 60), "llarm",
                                                                                   "p", mat="Metal")


@style("arms", "longsleeve")
def a_longsleeve():
    up = sleeve("Up", 3.16, 3.98, r=0.56)
    low = sleeve("Low", 2.36, 3.16, r=0.56)
    cuff = sleeve("Cuff", 2.33, 2.43, r=0.575)
    return LR(up, "luarm", "s", mat="Fabric") + LR(joined("Low", [low, cuff]), "llarm", "s", mat="Fabric")


# ---------------------------------------------------------------- build, export, preview
INFO = {
    "ears": ("EarArt", "Ears", "Ear", "ears.png", "Ears slot", "the head"),
    "neck": ("NeckArt", "Necks", "Neck", "necks.png", "Neck slot", "the upper torso"),
    "wrist": ("WristArt", "Wrists", "Wrist", "wrists.png", "Rings and bracelets slot", "a hand or lower arm"),
    "arms": ("ArmArt", "Arms", "Arm", "arms.png", "Arms slot", "an upper or lower arm"),
}


def header(group):
    module, fbx, _, _, slot, at = INFO[group]
    return ["trinkets.py",
            "The creator's %s pieces as meshes (ReplicatedStorage.Art.%s once nate imports art/export/%s.fbx;" % (
                slot, fbx, fbx),
            "LookKit wears them then, the part-built ones until then). Keyed by the kit: each piece's mesh name, the",
            "body part it is welded to (%s), its colour role (the slot's p main, s trim, a accent, or dark, white," % at,
            "gold, ice, glowRed), glow (Neon), material and transparency, and its box against that part's centre in",
            "Roblox axes (x right, y up, z back), in studs on the standard blocky rig (scaled with the part)."]


VIEW = {
    "ears": dict(parts={"Head"}, cols=5, cell=2.2, px=300, focus=4.6, yaw_front=180 - 60, yaw_back=180 + 60),
    "neck": dict(parts={"Head", "UpperTorso"}, cols=5, cell=3.0, px=300, focus=3.9, yaw_front=180 - 25,
                 yaw_back=25),
    "wrist": dict(parts={"LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LowerTorso"}, cols=4, cell=4.4,
                  px=440, focus=2.5, yaw_front=180 - 20, yaw_back=20),
    "arms": dict(parts={"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
                        "LeftHand", "RightHand"}, cols=5, cell=4.6, px=320, focus=3.0, yaw_front=180 - 30,
                 yaw_back=30),
}


def preview(group, built):
    v = dict(VIEW[group])
    parts = v.pop("parts")

    def dress(name, at, yaw, pal):
        wear.body(at, yaw, suit=(150, 156, 170), parts=parts, show_hair=group != "ears")
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", INFO[group][3] if not QUICK else INFO[group][3][:-4] + "_test.png")
    wear.grid_preview(built, out, dress, samples=28, **v)


if __name__ == "__main__":
    for group, styles in SETS.items():
        if ONLY is not None and group not in ONLY:
            continue
        module, fbx, prefix, _, _, _ = INFO[group]
        built = {}
        for name, fn in styles.items():
            built[name] = wear.name_all(prefix + "_" + name, fn())
        rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
        if not QUICK:
            objs = [p.ob for ps in built.values() for p in ps]
            kit.export_fbx(objs, os.path.join(kit.ROOT, "export", fbx + ".fbx"))
            wear.write_fit(module, header(group), rows)
        preview(group, built)
        # the next set's preview starts from an empty scene (this set's meshes stay out of it)
        for ps in built.values():
            for p in ps:
                p.ob.hide_render = True
        for o in list(bpy.context.scene.objects):
            if o.get("preview") or o.type in ("LIGHT", "CAMERA"):
                bpy.data.objects.remove(o, do_unlink=True)
