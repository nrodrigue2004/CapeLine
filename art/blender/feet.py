# feet.py: the hero creator's boots and shoes as meshes (creator art round 2, 2026-11-18), in place of the boxes
# LookKit and PieceKits weld to the feet and shins. The blocky foot is the 1 x 0.3 x 1 foot of the leg column
# (z 0 to 0.3, toe +y), the shin above it (z 0.3 to 1.15), so a shoe is a rounded shell over the foot reaching a
# little past the toe on its own sole, and a boot adds a shaft up the shin: each kit adds its own shape (wings,
# a jet nozzle, plates, wheels, a fin, a hover disc, spikes, fur, a pom-pom, a gold bit, crystals). Built on the
# left leg (x = -0.5) and mirrored to the right. Bright, chunky comic shapes; all original (no brand marks).
# Output: art/export/Boots.fbx (nate imports it as ReplicatedStorage.Art.Boots), src/config/BootArt.luau
# (LookKit's fit) and art/preview/boots.png (each kit on the left leg, from the front and from behind).
# Run: python art/blender/feet.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
import bpy  # noqa: E402, F401
from mathutils import Matrix, Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 1800  # triangles a pair
X = -0.5  # the left leg's centre
PI = math.pi

kit.reset()


def loft(name, rows, power=6.0, cap=(False, False), segs=16):
    """A rounded-box shell round the leg: rows [(z, rx, ry, cy)] bottom to top (cy moves the ring toward the toe)."""
    rings = [(z, rx, ry, X, cy) for z, rx, ry, cy in rows]
    ob = kit.loft(name, rings, segs=segs, power=power, cap=cap)  # one-sided: the leg fills it
    kit.shade_auto(ob, 45)
    return ob


def shoe(name="Shoe", top=0.36, toe=0.66, rx=0.56, power=5.0, puff=0.0):
    """The shoe over the foot: from the sole up past the ankle, longer toward the toe, the toe rounded over."""
    back = 0.54
    ry, cy = (toe + back) / 2, (toe - back) / 2
    rows = [(0.03, rx + puff, ry + puff, cy), (0.16, rx + puff * 1.2, ry + puff * 1.2, cy),
            (0.26, rx + puff, ry - 0.02 + puff, cy - 0.02), (top - 0.03, rx - 0.0, 0.56, 0.0), (top, rx, 0.555, 0.0)]
    ob = loft(name, rows, power=power, cap=(False, False))
    # the toe's top rounds down to the sole (a shoe, not a box)
    for v in ob.data.vertices:
        f = max(0.0, v.co.y - 0.4) / max(0.01, toe - 0.4)
        if v.co.z > 0.12:
            v.co.z -= (v.co.z - 0.12) * 0.55 * f
    return ob


def sole(name="Sole", toe=0.7, rx=0.6, h=0.07, z=0.0, power=5.0):
    back = 0.58
    ry, cy = (toe + back) / 2, (toe - back) / 2
    rows = [(z - h / 2, rx, ry, cy), (z + h / 2, rx, ry, cy)]
    ob = loft(name, rows, power=power, cap=(True, True))
    kit.shade_auto(ob, 30)
    return ob


def shaft(name, z0, z1, r0=0.56, r1=0.6, power=6.0):
    return loft(name, [(z0, r0, r0, 0.0), (z1, r1, r1, 0.0)], power=power)


def band(name, z, r, h=0.06, power=6.0):
    rows = [(z - h, r, r, 0.0), (z - h * 0.4, r + h * 0.4, r + h * 0.4, 0.0), (z + h * 0.4, r + h * 0.4, r + h * 0.4, 0.0),
            (z + h, r, r, 0.0)]
    ob = loft(name, rows, power=power)
    kit.shade_auto(ob, 60)
    return ob


def flat(name, pts, depth, at, axis="X"):
    import bmesh
    bm = bmesh.new()
    vs = []
    for u, v in pts:
        if axis == "X":  # in the y-z plane (a side wing or fin)
            vs.append(bm.verts.new((at[0], at[1] + u, at[2] + v)))
        elif axis == "Z":  # in the x-y plane (a flipper's fin)
            vs.append(bm.verts.new((at[0] + u, at[1] + v, at[2])))
        else:
            vs.append(bm.verts.new((at[0] + u, at[1], at[2] + v)))
    bm.faces.new(vs)
    ob = kit._obj(name, bm)
    wear.solid(ob, depth, 0.0)
    kit.shade_auto(ob, 30)
    return ob


def rod(name, pts, radii, segs=8):
    ob = kit.tube_along(name, [Vector(p) for p in pts], radii, segs=segs)
    kit.shade_auto(ob, 60)
    return ob


def cone(name, r, h, base, direction, segs=8):
    d = Vector(direction).normalized()
    ob = kit.cyl(name, r, 0.0, h, at=(0, 0, h / 2), segs=segs)
    ob.data.transform(d.to_track_quat("Z", "Y").to_matrix().to_4x4())
    ob.data.transform(Matrix.Translation(Vector(base)))
    kit.shade_auto(ob, 30)
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


def laces(name, n=3, z0=0.2, y=0.5, w=0.36):
    bars = []
    for k in range(n):
        z = z0 + k * 0.1
        b = kit.box("l", w, 0.04, 0.045, at=(X, y + 0.03 - k * 0.04, z))
        kit.bevel(b, 0.015, 1)
        bars.append(b)
    return join(name, bars, 30)


STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


# ---------------------------------------------------------------- the 21 kits
@style("boot")
def s_boot():
    return pair(shoe(), "lfoot", "s") + pair(sole(), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.68), "lshin", "s") + pair(band("Trim", 0.68, 0.6, 0.04), "lshin", "a")


@style("tall")
def s_tall():
    cuff = loft("Cuff", [(0.92, 0.62, 0.62, 0.0), (1.0, 0.68, 0.68, 0.0), (1.12, 0.7, 0.7, 0.0)])
    return pair(shoe(), "lfoot", "s") + pair(sole(), "lfoot", "dark") + \
        pair(join("Shaft", [shaft("Shaft", 0.3, 0.95, 0.56, 0.61), cuff]), "lshin", "s") + \
        pair(band("Trim", 1.12, 0.7, 0.035), "lshin", "a")


@style("sneaker")
def s_sneaker():
    toe = kit.sphere("Toe", 0.34, at=(X, 0.44, 0.1), scale=(1.6, 1.0, 0.55), segs=16, rings=8)
    stripe = flat("Stripe", [(-0.35, 0.18), (-0.1, 0.06), (0.15, 0.2), (0.35, 0.08), (0.35, 0.14), (0.15, 0.27),
                             (-0.1, 0.13), (-0.35, 0.25)], 0.03, (X - 0.575, 0.05, 0.0), axis="X")
    stripe2 = flat("s2", [(-0.35, 0.18), (-0.1, 0.06), (0.15, 0.2), (0.35, 0.08), (0.35, 0.14), (0.15, 0.27),
                          (-0.1, 0.13), (-0.35, 0.25)], 0.03, (X + 0.575, 0.05, 0.0), axis="X")
    return pair(shoe(top=0.38), "lfoot", "white") + pair(sole(h=0.1, z=0.01), "lfoot", "a") + \
        pair(join("Trim", [toe, stripe, stripe2], 40), "lfoot", "a") + pair(laces("Laces"), "lfoot", "dark")


@style("winged")
def s_winged():
    wings = []
    for s in (-1, 1):
        w = flat("w", [(0.05, 0.0), (-0.3, 0.12), (-0.5, 0.36), (-0.36, 0.33), (-0.42, 0.5), (-0.24, 0.42),
                       (-0.26, 0.58), (-0.08, 0.38)], 0.05, (X + s * 0.6, 0.05, 0.48), axis="X")
        wings.append(w)
    return pair(shoe(), "lfoot", "s") + pair(sole(), "lfoot", "dark") + pair(shaft("Shaft", 0.3, 0.72), "lshin", "s") + \
        pair(join("Wings", wings, 30), "lshin", "a")


@style("jet")
def s_jet():
    noz = kit.cyl("Nozzle", 0.2, 0.26, 0.32, at=(X, -0.66, 0.42), segs=14, axis="Y")
    noz2 = kit.cyl("n2", 0.27, 0.27, 0.06, at=(X, -0.83, 0.42), segs=14, axis="Y")
    glow = kit.cyl("Glow", 0.18, 0.18, 0.03, at=(X, -0.87, 0.42), segs=14, axis="Y")
    fins = [flat("f", [(0.0, 0.0), (-0.3, 0.0), (-0.1, 0.3)], 0.05, (X + s * 0.25, -0.6, 0.55), axis="X")
            for s in (-1, 1)]
    return pair(shoe(), "lfoot", "s") + pair(sole(), "lfoot", "dark") + pair(shaft("Shaft", 0.3, 0.7), "lshin", "s") + \
        pair(join("Nozzle", [noz, noz2] + fins, 30), "lshin", "dark", mat="Metal") + pair(glow, "lshin", "a", True)


@style("armored")
def s_armored():
    toe = kit.box("Toe", 1.12, 0.36, 0.3, at=(X, 0.5, 0.16))
    kit.bevel(toe, 0.06, 2)
    knee = flat("Knee", [(-0.25, 0.0), (0.25, 0.0), (0.3, 0.3), (0.0, 0.45), (-0.3, 0.3)], 0.08,
                (X, 0.64, 0.75), axis="Y")
    return pair(shoe(power=9.0, rx=0.58), "lfoot", "s", mat="Metal") + pair(sole(rx=0.62, h=0.09), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.95, 0.58, 0.63, power=9.0), "lshin", "s", mat="Metal") + \
        pair(join("Plates", [knee], 30), "lshin", "a", mat="Metal") + pair(toe, "lfoot", "a", mat="Metal")


@style("sandals")
def s_sandals():
    straps = []
    for y, z in ((0.32, 0.16), (0.0, 0.24)):
        straps.append(loft("s", [(z - 0.04, 0.53, 0.08, y), (z + 0.04, 0.53, 0.08, y)], power=8.0))
    ankle = band("Ankle", 0.36, 0.55, 0.04)
    return pair(sole(h=0.08, toe=0.62, rx=0.57), "lfoot", "s", mat="Leather") + \
        pair(join("Straps", straps, 30), "lfoot", "s", mat="Leather") + pair(ankle, "lshin", "s", mat="Leather")


@style("hightops")
def s_hightops():
    toe = kit.sphere("Toe", 0.34, at=(X, 0.44, 0.1), scale=(1.6, 1.0, 0.55), segs=16, rings=8)
    patch = [kit.cyl("p", 0.13, 0.13, 0.03, at=(X + s * 0.575, -0.05, 0.6), segs=14, axis="X") for s in (-1, 1)]
    return pair(shoe(top=0.38), "lfoot", "white") + pair(sole(h=0.1, z=0.01), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.82, 0.56, 0.58), "lshin", "white") + pair(toe, "lfoot", "dark") + \
        pair(join("Patch", patch + [band("t", 0.82, 0.58, 0.035)]), "lshin", "a") + pair(laces("Laces", 4), "lfoot", "a")


@style("geta")
def s_geta():
    base = kit.box("Base", 1.0, 1.12, 0.1, at=(X, 0.03, -0.02))
    kit.bevel(base, 0.03, 1)
    teeth = [kit.box("t", 0.9, 0.12, 0.2, at=(X, y, -0.17)) for y in (-0.3, 0.32)]
    for t in teeth:
        kit.bevel(t, 0.02, 1)
    thong = rod("Thong", [(X - 0.52, -0.1, 0.05), (X - 0.4, 0.15, 0.3), (X, 0.42, 0.32), (X + 0.4, 0.15, 0.3),
                          (X + 0.52, -0.1, 0.05)], [0.04] * 5, segs=6)
    return pair(join("Base", [base] + teeth, 30), "lfoot", "s", mat="Wood") + pair(thong, "lfoot", "p", mat="Fabric")


@style("tabi")
def s_tabi():
    groove = kit.box("Split", 0.04, 0.3, 0.26, at=(X + 0.16, 0.56, 0.14))
    return pair(shoe(toe=0.6), "lfoot", "dark", mat="Fabric") + pair(sole(toe=0.62), "lfoot", "s") + \
        pair(shaft("Shaft", 0.3, 0.66), "lshin", "dark", mat="Fabric") + \
        pair(join("Trim", [groove, band("t", 0.66, 0.6, 0.03)]), "lshin", "s")


@style("combat")
def s_combat():
    lugs = [kit.box("g", 1.1, 0.12, 0.06, at=(X, -0.45 + k * 0.24, -0.06)) for k in range(5)]
    strap = band("Strap", 0.55, 0.6, 0.05)
    buckle = kit.box("b", 0.16, 0.06, 0.14, at=(X - 0.62, 0.0, 0.55))
    return pair(shoe(rx=0.58, top=0.38), "lfoot", "dark", mat="Leather") + \
        pair(join("Sole", [sole(h=0.1, z=0.0, rx=0.61)] + lugs, 30), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.8, 0.57, 0.6), "lshin", "dark", mat="Leather") + \
        pair(join("Straps", [strap, buckle], 30), "lshin", "s") + pair(laces("Laces", 4), "lfoot", "s")


@style("moon")
def s_moon():
    body = loft("Boot", [(0.0, 0.6, 0.66, 0.06), (0.15, 0.68, 0.74, 0.06), (0.4, 0.66, 0.66, 0.0),
                         (0.7, 0.66, 0.66, 0.0), (0.85, 0.62, 0.62, 0.0)], power=3.0, cap=(True, False))
    bands = [band("b", z, 0.67, 0.04, power=3.0) for z in (0.42, 0.62)]
    s = sole(h=0.1, z=-0.02, rx=0.66, toe=0.78, power=3.0)
    return pair(body, "lshin", "white") + pair(join("Bands", bands), "lshin", "a") + pair(s, "lfoot", "s")


@style("skates")
def s_skates():
    plate = kit.box("Plate", 0.5, 1.1, 0.08, at=(X, 0.04, -0.06))
    kit.bevel(plate, 0.02, 1)
    wheels = []
    for y in (-0.38, 0.46):
        for s in (-1, 1):
            wheels.append(kit.cyl("w", 0.12, 0.12, 0.1, at=(X + s * 0.2, y, -0.14), segs=14, axis="X"))
    stop = kit.sphere("Stopper", 0.12, at=(X, 0.62, -0.08), segs=10, rings=6)
    return pair(shoe(top=0.38), "lfoot", "p") + pair(shaft("Shaft", 0.3, 0.72), "lshin", "p") + \
        pair(join("Plate", [plate, stop], 30), "lfoot", "dark") + pair(join("Wheels", wheels, 30), "lfoot", "a") + \
        pair(laces("Laces", 4), "lfoot", "white")


@style("flippers")
def s_flippers():
    fin = flat("Fin", [(-0.5, 0.4), (0.5, 0.4), (0.7, 1.55), (0.3, 1.45), (0.0, 1.6), (-0.3, 1.45), (-0.7, 1.55)],
               0.05, (X, 0.0, 0.02), axis="Z")
    ribs = [kit.box("r", 0.06, 1.0, 0.04, at=(X + x, 1.0, 0.06)) for x in (-0.3, 0.0, 0.3)]
    return pair(shoe(), "lfoot", "dark", mat="Rubber") + pair(fin, "lfoot", "a", mat="Rubber") + \
        pair(join("Ribs", ribs, 30), "lfoot", "s")


@style("hover")
def s_hover():
    disc = kit.cyl("Disc", 0.62, 0.48, 0.06, at=(X, 0.04, -0.12), segs=20)
    ring = kit.torus("Ring", 0.6, 0.035, at=(X, 0.04, -0.1), segs=24, csegs=6)
    vents = [kit.box("v", 0.04, 0.3, 0.06, at=(X + s * 0.6, -0.1, 0.18 + k * 0.1)) for s in (-1, 1) for k in range(2)]
    return pair(shoe(power=8.0), "lfoot", "s", mat="Metal") + pair(sole(h=0.06), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.7, power=8.0), "lshin", "s", mat="Metal") + \
        pair(disc, "lfoot", "a", True, alpha=0.35) + pair(join("Glow", [ring] + vents, 30), "lfoot", "a", True)


@style("spikes")
def s_spikes():
    spikes = [cone("s", 0.08, 0.3, (X, 0.6, 0.5 + k * 0.2), (0, 1, 0.3)) for k in range(3)]
    spikes += [cone("s", 0.07, 0.24, (X - 0.6, 0.0, 0.55 + k * 0.2), (-1, 0, 0.3)) for k in range(2)]
    spikes += [cone("s", 0.07, 0.24, (X + 0.6, 0.0, 0.55 + k * 0.2), (1, 0, 0.3)) for k in range(2)]
    return pair(shoe(), "lfoot", "dark") + pair(sole(), "lfoot", "s") + \
        pair(shaft("Shaft", 0.3, 0.95, 0.56, 0.6), "lshin", "dark") + pair(join("Spikes", spikes, 20), "lshin", "white",
                                                                          mat="Metal")


@style("fur")
def s_fur():
    fur = kit.torus("Fur", 0.62, 0.15, at=(X, 0, 0.62), segs=20, csegs=6)
    for v in fur.data.vertices:
        a = math.atan2(v.co.y, v.co.x - X)
        v.co.z += 0.04 * math.sin(a * 7) * (1 if v.co.z < 0.62 else 0.6)
    kit.shade_auto(fur, 80)
    return pair(shoe(rx=0.58, puff=0.02), "lfoot", "s", mat="Leather") + pair(sole(), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.55, 0.57, 0.58), "lshin", "s", mat="Leather") + pair(fur, "lshin", "white",
                                                                                    mat="Fabric")


@style("slippers")
def s_slippers():
    pom = kit.sphere("Pom", 0.17, at=(X, 0.58, 0.34), segs=14, rings=8)
    kit.shade_auto(pom, 80)
    return pair(shoe(top=0.34, power=3.4, rx=0.6, puff=0.04), "lfoot", "p", mat="Fabric") + \
        pair(sole(power=3.4, rx=0.64, h=0.06), "lfoot", "white") + pair(pom, "lfoot", "white", mat="Fabric")


@style("loafers")
def s_loafers():
    bit = rod("Bit", [(X - 0.18, 0.5, 0.25), (X, 0.56, 0.27), (X + 0.18, 0.5, 0.25)], [0.035] * 3, segs=6)
    saddle = kit.box("Saddle", 0.7, 0.1, 0.06, at=(X, 0.45, 0.22))
    return pair(shoe(top=0.32), "lfoot", "dark", mat="Leather") + pair(sole(h=0.06), "lfoot", "s") + \
        pair(saddle, "lfoot", "s", mat="Leather") + pair(bit, "lfoot", "gold", mat="Metal")


@style("nightBoots")
def s_night():
    heel = kit.box("Heel", 0.4, 0.3, 0.16, at=(X, -0.4, -0.05))
    kit.bevel(heel, 0.03, 1)
    buckle = kit.box("Buckle", 0.22, 0.05, 0.16, at=(X, 0.6, 0.62))
    kit.bevel(buckle, 0.02, 1)
    return pair(shoe(), "lfoot", "dark", mat="Leather") + pair(sole(), "lfoot", "dark") + \
        pair(shaft("Shaft", 0.3, 0.9, 0.56, 0.6), "lshin", "dark", mat="Leather") + \
        pair(join("Gold", [band("b", 0.9, 0.6, 0.05), buckle], 30), "lshin", "gold", mat="Metal") + \
        pair(heel, "lfoot", "a", True)


@style("ice")
def s_ice():
    shards = []
    for (x, y, z, h, d) in ((-0.6, 0.1, 0.4, 0.32, (-1, 0.2, 1.2)), (0.6, -0.1, 0.45, 0.28, (1, -0.2, 1.2)),
                            (0.0, 0.62, 0.45, 0.3, (0, 1, 1.0)), (-0.4, -0.6, 0.5, 0.26, (-0.6, -1, 1.2)),
                            (0.4, 0.6, 0.25, 0.22, (0.6, 1, 0.8))):
        shards.append(cone("s", 0.09, h, (X + x, y, z), d, segs=5))
    return pair(shoe(power=4.0), "lfoot", "ice", mat="Glass", alpha=0.1) + pair(sole(), "lfoot", "white") + \
        pair(shaft("Shaft", 0.3, 0.72, power=4.0), "lshin", "ice", mat="Glass", alpha=0.1) + \
        pair(join("Shards", shards, 10), "lshin", "ice", True)


# ---------------------------------------------------------------- build, export, preview
HEADER = ["feet.py",
          "The creator's boots and shoes as meshes (ReplicatedStorage.Art.Boots once nate imports art/export/Boots.fbx;",
          "LookKit wears them then, the part-built boots until then). Keyed by the Boots tab's kit: each piece's mesh",
          "name, the body part it is welded to (at: lfoot, rfoot, lshin, rshin), its colour role (the slot's p main,",
          "s trim, a accent, or dark, white, gold, ice, glowRed), glow (Neon), material and transparency, and its box",
          "against that part's centre in Roblox axes (x right, y up, z back), in studs on the standard blocky rig."]
LEFT = {"lfoot", "lshin"}


def preview(built):
    def dress(name, at, yaw, pal):
        piv = (X, 0, 0)
        wear.body(at, yaw, parts={"LeftLowerLeg", "LeftFoot"}, pivot=piv, suit=(150, 156, 170))
        wear.place([p for p in built[name] if p.at in LEFT], at, yaw, pal, pivot=piv)
    wear.grid_preview(built, os.path.join(kit.ROOT, "preview", "boots.png"), dress, cols=7, cell=2.3, px=280,
                      focus=0.5, yaw_front=180 + 40, yaw_back=40, look_down=0.12)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Boot_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Boots.fbx"))
        wear.write_fit("BootArt", HEADER, rows)
    preview(built)
