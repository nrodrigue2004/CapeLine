# hands.py: the hero creator's gloves and wraps as meshes (creator art round 2, 2026-11-18), in place of the boxes
# LookKit and PieceKits weld to the hands and forearms. The blocky hand is the 1 x 0.3 x 1 foot of the arm column
# (z 2.0 to 2.3), the forearm above it (z 2.3 to 3.15), so a glove is a rounded sleeve over the hand with a cuff
# over the wrist: each kit adds its own shape (a flared gauntlet, spikes, claws, a boxing glove, a puffy mitten,
# bandage wraps that spiral up the forearm, glowing circuit lines, crystals, talons, flames). Built on the left
# arm (x = -1.5) and mirrored to the right. Bright, chunky comic shapes; all original.
# Output: art/export/Gloves.fbx (nate imports it as ReplicatedStorage.Art.Gloves), src/config/GloveArt.luau
# (LookKit's fit) and art/preview/gloves.png (each kit on the left arm, from the front and from behind).
# Run: python art/blender/hands.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
import bpy  # noqa: E402, F401
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 1600  # triangles a pair
X = -1.5  # the left arm's centre
WRIST = 2.3
PI = math.pi

kit.reset()


def sleeve(name, rows, power=7.0, cap=(True, False), segs=16, cy=0.0):
    """A rounded-box sleeve round the arm column: rows [(z, r)] or [(z, rx, ry)] bottom to top."""
    rings = []
    for r in rows:
        if len(r) == 2:
            rings.append((r[0], r[1], r[1], X, cy))
        else:
            rings.append((r[0], r[1], r[2], X, cy))
    ob = kit.loft(name, rings, segs=segs, power=power, cap=cap)  # one-sided: the arm fills it
    kit.shade_auto(ob, 45)
    return ob


def ring(name, z, r, thick=0.06, tube=None, power=7.0, segs=16):
    """A rounded band round the arm at height z (a cuff trim or a wrap)."""
    t = tube or thick
    rings = [(z - t, r, r, X, 0), (z - t * 0.4, r + t * 0.5, r + t * 0.5, X, 0),
             (z + t * 0.4, r + t * 0.5, r + t * 0.5, X, 0), (z + t, r, r, X, 0)]
    ob = kit.loft(name, rings, segs=segs, power=power, cap=(False, False))
    kit.shade_auto(ob, 60)
    return ob


def tilt(ob, deg, axis="Y", pivot=(X, 0, 2.15)):
    e = {"X": (math.radians(deg), 0, 0), "Y": (0, math.radians(deg), 0), "Z": (0, 0, math.radians(deg))}[axis]
    return wear.turn(ob, e, pivot)


def cone(name, r, h, base, direction, segs=8):
    d = Vector(direction).normalized()
    ob = kit.cyl(name, r, 0.0, h, at=(0, 0, h / 2), segs=segs)
    q = d.to_track_quat("Z", "Y")
    ob.data.transform(q.to_matrix().to_4x4())
    ob.data.transform(__import__("mathutils").Matrix.Translation(Vector(base)))
    kit.shade_auto(ob, 30)
    return ob


def rod(name, pts, radii, segs=8):
    ob = kit.tube_along(name, [Vector(p) for p in pts], radii, segs=segs)
    kit.shade_auto(ob, 60)
    return ob


def join(name, obs, angle=50):
    for o in obs:
        kit.apply_all(o)
        wear.bake(o)
    ob = kit.join(name, obs, shade=False)
    kit.shade_auto(ob, angle)
    return ob


def pair(ob, at, role, glow=False, mat=None, alpha=0.0):
    wear.bake(ob)
    return wear.pair(ob, at, role, glow, mat, alpha)


GLOVE = [(1.97, 0.5), (1.99, 0.55), (2.06, 0.565), (2.22, 0.565), (2.33, 0.555)]  # round the hand


def glove(name="Glove", rows=None, power=7.0):
    return sleeve(name, rows or GLOVE, power=power)


def wraps_on(name, zs, r, tilt_deg=6, width=0.075):
    bands = []
    for k, z in enumerate(zs):
        b = ring("w", z, r, tube=width)
        tilt(b, tilt_deg if k % 2 == 0 else -tilt_deg, "Y", (X, 0, z))
        bands.append(b)
    return join(name, bands)


STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


# ---------------------------------------------------------------- the 19 kits
@style("glove")
def s_glove():
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.36, 0.6), (2.44, 0.62)], cap=(False, False))
    trim = ring("Trim", 2.45, 0.6, tube=0.03)
    return pair(glove(), "lhand", "s") + pair(cuff, "llarm", "s") + pair(trim, "llarm", "a")


@style("cuff")
def s_cuff():
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.45, 0.6), (2.65, 0.64), (2.82, 0.68)], cap=(False, False))
    trim = ring("Trim", 2.82, 0.68, tube=0.035)
    return pair(glove(), "lhand", "s") + pair(cuff, "llarm", "s") + pair(trim, "llarm", "a")


@style("fingerless")
def s_fingerless():
    g = sleeve("Glove", [(2.08, 0.555), (2.12, 0.565), (2.33, 0.56)], cap=(False, False))
    strap = ring("Strap", 2.26, 0.575, tube=0.04)
    dot = kit.cyl("Snap", 0.06, 0.06, 0.04, at=(X - 0.6, 0, 2.26), segs=10, axis="X")
    return pair(g, "lhand", "s") + pair(join("Strap", [strap, dot]), "lhand", "dark")


@style("spiked")
def s_spiked():
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.4, 0.61), (2.55, 0.63)], cap=(False, False))
    spikes = []
    for k in range(3):  # a row down the outside of the hand and round the cuff
        spikes.append(cone("s", 0.07, 0.24, (X - 0.56, -0.25 + k * 0.25, 2.15), (-1, 0, 0.15)))
    for a in (0.0, 1.2, 2.4, 3.6, 4.8):
        d = (math.sin(a), math.cos(a), 0.0)
        spikes.append(cone("c", 0.06, 0.2, (X + d[0] * 0.62, d[1] * 0.62, 2.45), (d[0], d[1], 0.25)))
    return pair(glove(), "lhand", "dark", mat="Leather") + pair(cuff, "llarm", "dark", mat="Leather") + \
        pair(join("Spikes", spikes, 20), "llarm", "a", mat="Metal")


@style("gauntlet")
def s_gauntlet():
    g = glove(rows=[(1.96, 0.52), (1.98, 0.58), (2.06, 0.6), (2.24, 0.6), (2.33, 0.58)], power=9.0)
    arm = sleeve("Guard", [(2.28, 0.6), (2.5, 0.62), (2.78, 0.68), (2.98, 0.72)], power=9.0, cap=(False, False))
    ridge = sleeve("Ridge", [(2.95, 0.73), (3.03, 0.75)], power=9.0, cap=(False, False))
    plate = kit.box("Knuckles", 0.8, 0.1, 0.16, at=(X, 0.64, 2.12))
    kit.bevel(plate, 0.03, 1)
    fin = kit.box("Fin", 0.08, 0.5, 0.55, at=(X - 0.73, 0, 2.62))
    kit.bevel(fin, 0.02, 1)
    return pair(g, "lhand", "s", mat="Metal") + pair(arm, "llarm", "s", mat="Metal") + \
        pair(join("Trim", [ridge, fin], 30), "llarm", "a", mat="Metal") + pair(plate, "lhand", "a", mat="Metal")


@style("spark")
def s_spark():
    g = glove()
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.4, 0.6), (2.5, 0.61)], cap=(False, False))
    bolts = []
    for a in (0.6, 2.2, 3.8, 5.4):
        d = Vector((math.sin(a), math.cos(a), 0))
        base = Vector((X, 0, 2.5)) + d * 0.6
        pts = [base, base + d * 0.12 + Vector((0, 0, 0.14)), base + d * 0.03 + Vector((0, 0, 0.2)),
               base + d * 0.16 + Vector((0, 0, 0.36))]
        bolts.append(rod("b", pts, [0.05, 0.04, 0.04, 0.0], segs=5))
    return pair(g, "lhand", "a", True) + pair(cuff, "llarm", "dark") + pair(join("Bolts", bolts, 20), "llarm", "a", True)


@style("claws")
def s_claws():
    blades = []
    for k in range(3):
        y = 0.3 - k * 0.3
        pts = [(X - 0.1, y, 2.02), (X - 0.12, y + 0.08, 1.75), (X - 0.08, y + 0.22, 1.5), (X - 0.02, y + 0.38, 1.36)]
        blades.append(rod("c", pts, [0.07, 0.06, 0.04, 0.0], segs=4))
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.38, 0.6), (2.48, 0.6)], cap=(False, False))
    return pair(glove(), "lhand", "dark") + pair(cuff, "llarm", "dark") + pair(join("Claws", blades, 20), "lhand", "a", True)


@style("wraps")
def s_wraps():
    w = wraps_on("Wraps", (2.05, 2.15, 2.25), 0.55)
    return pair(w, "lhand", "white", mat="Fabric")


@style("wraps:long")
def s_wraps_long():
    hand = wraps_on("Wraps", (2.05, 2.15, 2.25), 0.55)
    arm = wraps_on("ArmWraps", (2.4, 2.53, 2.66, 2.79), 0.55, tilt_deg=12)
    tape = kit.box("Tape", 0.18, 0.04, 0.3, at=(X + 0.1, 0.56, 2.86))
    return pair(hand, "lhand", "white", mat="Fabric") + pair(join("ArmWraps", [arm, tape]), "llarm", "white", mat="Fabric")


@style("wraps:glow")
def s_wraps_glow():
    hand = wraps_on("Wraps", (2.07, 2.22), 0.55, width=0.05)
    arm = wraps_on("ArmWraps", (2.42, 2.6, 2.78), 0.55, tilt_deg=14, width=0.045)
    return pair(hand, "lhand", "a", True) + pair(arm, "llarm", "a", True)


@style("wraps:dark")
def s_wraps_dark():
    hand = wraps_on("Wraps", (2.05, 2.15, 2.25), 0.55)
    arm = wraps_on("ArmWraps", (2.4, 2.55, 2.7), 0.55, tilt_deg=12)
    tail = rod("Tail", [(X - 0.55, 0.1, 2.72), (X - 0.7, 0.05, 2.55), (X - 0.78, 0.1, 2.32), (X - 0.85, 0.02, 2.12)],
               [0.05, 0.045, 0.04, 0.03], segs=6)
    for v in tail.data.vertices:  # a flat ribbon end
        v.co.y = 0.05 + (v.co.y - 0.05) * 2.2
        v.co.x = X - 0.55 + (v.co.x - (X - 0.55)) * 1.0
    return pair(hand, "lhand", "dark", mat="Fabric") + pair(join("ArmWraps", [arm, tail]), "llarm", "dark", mat="Fabric")


@style("boxing")
def s_boxing():
    mitt = kit.sphere("Glove", 0.62, at=(X, 0.12, 1.86), scale=(1.0, 1.08, 0.82), segs=16, rings=10)
    thumb = kit.sphere("t", 0.22, at=(X + 0.48, 0.38, 2.0), scale=(0.9, 1.1, 1.3), segs=12, rings=8)
    kit.shade_auto(mitt, 80)
    g = join("Glove", [mitt, thumb], 80)
    cuff = sleeve("Cuff", [(2.22, 0.57), (2.3, 0.6), (2.6, 0.62), (2.68, 0.6)], power=5.0, cap=(False, False))
    lace = kit.box("Lace", 0.06, 0.05, 0.4, at=(X, 0.64, 2.45))
    return pair(g, "lhand", "p") + pair(join("Cuff", [cuff, lace]), "llarm", "white")


@style("knuckle")
def s_knuckle():
    bar = []
    for k in range(4):
        b = kit.sphere("k", 0.13, at=(X - 0.33 + k * 0.22, 0.6, 2.13), scale=(1, 0.7, 0.9), segs=10, rings=6)
        bar.append(b)
    plate = kit.box("p", 0.92, 0.08, 0.2, at=(X, 0.58, 2.13))
    kit.bevel(plate, 0.03, 1)
    return pair(glove(), "lhand", "dark", mat="Leather") + pair(join("Guard", bar + [plate], 40), "lhand", "s",
                                                                mat="Metal")


@style("mittens")
def s_mittens():
    mitt = kit.loft("Mitten", [(1.82, 0.32, 0.4, X, 0.05), (1.88, 0.48, 0.55, X, 0.05), (2.0, 0.62, 0.64, X, 0.03),
                               (2.2, 0.62, 0.62, X, 0), (2.36, 0.6, 0.6, X, 0)], segs=16, power=4.0, cap=(True, False))
    thumb = kit.sphere("t", 0.18, at=(X + 0.5, 0.3, 2.0), scale=(1, 1, 1.4), segs=12, rings=8)
    m = join("Mitten", [mitt, thumb], 80)
    fluff = kit.torus("Fluff", 0.6, 0.1, at=(X, 0, 2.4), segs=18, csegs=6)
    for v in fluff.data.vertices:
        v.co.z += 0.025 * math.sin(math.atan2(v.co.y, v.co.x - X) * 9)
    kit.shade_auto(fluff, 80)
    return pair(m, "lhand", "p", mat="Fabric") + pair(fluff, "llarm", "white", mat="Fabric")


@style("work")
def s_work():
    cuff = sleeve("Cuff", [(2.26, 0.58), (2.4, 0.63), (2.62, 0.68), (2.7, 0.69)], power=6.0, cap=(False, False))
    strap = ring("Strap", 2.2, 0.575, tube=0.045)
    stitch = ring("Stitch", 2.64, 0.7, tube=0.02, power=6.0)
    return pair(glove(), "lhand", "s", mat="Leather") + pair(cuff, "llarm", "s", mat="Leather") + \
        pair(join("Straps", [strap, stitch]), "llarm", "dark")


@style("tech")
def s_tech():
    lines = []
    for y in (-0.3, 0.0, 0.3):  # circuit traces down the outside of the hand, round the wrist
        lines.append(kit.box("l", 0.03, 0.05, 0.28, at=(X - 0.58, y, 2.15)))
    lines.append(kit.box("f", 0.5, 0.03, 0.05, at=(X, 0.58, 2.2)))
    nodes = [kit.cyl("n", 0.05, 0.05, 0.03, at=(X - 0.59, y, 2.3), segs=8, axis="X") for y in (-0.3, 0.0, 0.3)]
    pad = kit.box("Pad", 0.4, 0.06, 0.3, at=(X, 0.6, 2.5))
    kit.bevel(pad, 0.02, 1)
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.4, 0.6), (2.6, 0.6)], power=9.0, cap=(False, False))
    return pair(glove(power=9.0), "lhand", "dark") + pair(join("Lines", lines + nodes, 20), "lhand", "a", True) + \
        pair(cuff, "llarm", "s", mat="Metal") + pair(pad, "llarm", "a", True)


@style("crystal")
def s_crystal():
    shards = []
    for (x, y, z, h, lean) in ((-0.58, 0.0, 2.2, 0.36, -0.5), (-0.5, 0.3, 2.25, 0.26, -0.7),
                               (-0.5, -0.3, 2.25, 0.26, -0.7), (-0.6, 0.15, 2.45, 0.3, -0.4),
                               (-0.6, -0.15, 2.45, 0.3, -0.4)):
        shards.append(cone("s", 0.09, h, (X + x, y, z), (math.sin(lean), 0, math.cos(lean)), segs=5))
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.4, 0.6), (2.52, 0.6)], cap=(False, False))
    return pair(glove(), "lhand", "s") + pair(cuff, "llarm", "s") + pair(join("Crystals", shards, 10), "llarm", "a",
                                                                       mat="Glass", alpha=0.1)


@style("talons")
def s_talons():
    talons = []
    for k in range(4):
        y = 0.36 - k * 0.24
        pts = [(X - 0.3, y, 2.0), (X - 0.3, y + 0.1, 1.8), (X - 0.24, y + 0.26, 1.68), (X - 0.18, y + 0.38, 1.7)]
        talons.append(rod("t", pts, [0.08, 0.065, 0.04, 0.0], segs=6))
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.36, 0.6), (2.46, 0.62)], cap=(False, False))
    return pair(glove(), "lhand", "dark") + pair(cuff, "llarm", "dark") + pair(join("Talons", talons, 30), "lhand",
                                                                              "white")


@style("flame")
def s_flame():
    tongues = []
    for k, a in enumerate((0.3, 1.35, 2.4, 3.45, 4.5, 5.55)):
        d = Vector((math.sin(a), math.cos(a), 0))
        base = Vector((X, 0, 2.3)) + d * 0.6
        h = 0.36 if k % 2 == 0 else 0.26
        pts = [base, base + d * 0.08 + Vector((0, 0, h * 0.45)), base + d * 0.02 + Vector((0, 0, h))]
        tongues.append(rod("f", pts, [0.13, 0.08, 0.0], segs=6))
    cuff = sleeve("Cuff", [(2.26, 0.57), (2.34, 0.6), (2.4, 0.6)], cap=(False, False))
    return pair(glove(), "lhand", "dark") + pair(cuff, "llarm", "dark") + pair(join("Flames", tongues, 60), "llarm",
                                                                              "glowRed", True, alpha=0.15)


# ---------------------------------------------------------------- build, export, preview
HEADER = ["hands.py",
          "The creator's gloves and wraps as meshes (ReplicatedStorage.Art.Gloves once nate imports",
          "art/export/Gloves.fbx; LookKit wears them then, the part-built gloves until then). Keyed by the Gloves",
          "tab's kit: each piece's mesh name, the body part it is welded to (at: lhand, rhand, llarm, rlarm), its",
          "colour role (the slot's p main, s trim, a accent, or dark, white, gold, ice, glowRed), glow (Neon),",
          "material and transparency, and its box against that part's centre in Roblox axes (x right, y up, z back),",
          "in studs on the standard blocky rig (scaled with the part)."]
LEFT = {"lhand", "llarm"}


def preview(built):
    def dress(name, at, yaw, pal):
        piv = (X, 0, 0)
        wear.body(at, yaw, parts={"LeftLowerArm", "LeftHand"}, pivot=piv, suit=(150, 156, 170))
        wear.place([p for p in built[name] if p.at in LEFT], at, yaw, pal, pivot=piv)
    wear.grid_preview(built, os.path.join(kit.ROOT, "preview", "gloves.png"), dress, cols=7, cell=2.3, px=280,
                      focus=2.45, yaw_front=180 + 40, yaw_back=30, look_down=0.25)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Glove_" + name.replace(":", "_"), fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Gloves.fbx"))
        wear.write_fit("GloveArt", HEADER, rows)
    preview(built)
