# shoulders.py: the hero creator's shoulder pieces as meshes (creator art round 3, 2026-11-18), in place of the
# boxes, balls and wedges PieceKits welds on for the Shoulders slot. Most kits are a left piece on the left upper arm
# (x -2 to -1, z 3.15 to 4.0; kit.py axes: +y the front) mirrored onto the right: a domed pad tipped down over the
# outside of the arm, with its rim, studs, plates, spikes, feathers, gears or flames. The fur trim and the mantle
# drape over both shoulders from the upper torso; the single pauldron and the plume sit on the left only.
# Bright, chunky comic shapes that read on a phone at a distance; all original.
# Output: art/export/Shoulders.fbx (nate imports it as ReplicatedStorage.Art.Shoulders), src/config/ShoulderArt.luau
# (LookKit's fit) and art/preview/shoulders.png (each kit from the front three-quarter and from behind).
# Run: python art/blender/shoulders.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, ring, dome_rows, rbox, ball, rod, joined, outline, strip  # noqa: E402
import bpy  # noqa: E402, F401
from mathutils import Euler, Matrix, Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 3000  # triangles a kit (both shoulders)
AX = -1.5  # the left upper arm's centre
TOP = 4.0  # the shoulder line
PIVOT = (AX, 0.0, TOP)
TILT = -0.32  # a pad tips down over the outside of the arm (radians about y)

kit.reset()

STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


def tip(ob, tilt=TILT):
    return wear.turn(ob, (0, tilt, 0), PIVOT)


def pad(name="Pad", r=0.6, ry=None, top=4.3, z0=3.7, z1=3.92, power=3.0, thick=0.06, cx=AX - 0.04, tilt=TILT,
        wave=None, na=22, n=5):
    ry = ry or r * 0.96
    ob = ring(name, dome_rows(z0, z1, r, ry, top=top, n=n), power=power, na=na, cx=cx, thick=thick, wave=wave)
    return tip(ob, tilt)


def rim(name="Rim", r=0.62, ry=None, z=3.7, h=0.07, power=3.0, cx=AX - 0.04, tilt=TILT, thick=0.05, na=22):
    ry = ry or r * 0.96
    ob = ring(name, [(z - h / 2, r, ry), (z + h / 2, r, ry)], power=power, na=na, cx=cx, thick=thick)
    return tip(ob, tilt)


def on_pad(u, v, r=0.6, top=4.3, z1=3.92, lift=0.0, tilt=TILT, cx=AX - 0.04):
    """A point on the pad's dome: u across it (-1 outside .. 1 inside, x), v front to back (-1 back .. 1 front),
    raised `lift` along the surface normal; returns (point, normal)."""
    x, y = u * r * 0.85, v * r * 0.85
    d = math.sqrt(max(0.0, 1 - (x * x + y * y) / (r * r)))
    p = Vector((cx + x, y, z1 + (top - z1) * d))
    n = Vector((x / r, y / r, max(d, 0.2))).normalized()
    p = p + n * lift
    R = Euler((0, tilt, 0)).to_matrix()
    P = Vector(PIVOT)
    return P + R @ (p - P), (R @ n).normalized()


def L(ob, role, glow=False, mat=None, alpha=0.0):
    """A left piece and its mirror on the right upper arm."""
    return wear.pair(ob, "luarm", role, glow, mat, alpha)


def T(ob, role, glow=False, mat=None, alpha=0.0):
    wear.bake(ob)
    return Piece(ob, "torso", role, glow, mat, alpha)


def leaf(name, length, width, at, d, up=(0, 0, 1), thick=0.03):
    """A pointed leaf or feather blade from `at` along direction d."""
    d = Vector(d).normalized()
    n = 7
    pts, ws = [], []
    for k in range(n):
        t = k / (n - 1)
        pts.append(Vector(at) + d * length * t)
        ws.append(max(0.01, width * math.sin(PI * min(1.0, t * 1.15)) ** 0.8))
    return strip(name, pts, ws, up=up, thick=thick)


# ---------------------------------------------------------------- the 20 kits
@style("pads")
def s_pads():
    return L(pad(), "p") + L(rim(), "s")


@style("studded")
def s_studded():
    studs = []
    for u, v in ((0.0, 0.0), (0.0, 0.55), (0.0, -0.55), (-0.55, 0.0), (-0.45, 0.45), (-0.45, -0.45)):
        p, n = on_pad(u, v, lift=0.01)
        studs.append(wear.cone("c", 0.075, 0.02, 0.09, tuple(p), segs=8, axis=tuple(n)))
    return L(pad(), "p") + L(rim(), "dark") + L(joined("Studs", studs), "gold", mat="Metal")


@style("epaulettes")
def s_epaulettes():
    board = outline("Board", wear.rrect_pts(0.95, 0.8, 0.3), 0.12, at=(AX - 0.08, 0.0, TOP + 0.08), axis="Z",
                    bev=0.03)
    tip(board, -0.12)
    fringe = []
    for k in range(11):
        y = -0.36 + 0.72 * k / 10
        fringe.append(rod("f", [(AX - 0.54, y, TOP + 0.08), (AX - 0.63, y, TOP - 0.05), (AX - 0.65, y, TOP - 0.42)],
                          0.035, segs=5))
    band = rod("Band", [(AX - 0.55, -0.4, TOP + 0.08), (AX - 0.55, 0.4, TOP + 0.08)], 0.045, segs=6)
    button = ball("Button", 0.09, (AX + 0.3, 0.0, TOP + 0.17), scale=(1, 1, 0.5), segs=10, rings=5)
    cloth = outline("Cloth", wear.rrect_pts(0.8, 0.66, 0.24), 0.04, at=(AX - 0.06, 0.0, TOP + 0.14), axis="Z")
    tip(cloth, -0.12)
    return (L(joined("Board", [board, band] + fringe), "gold", mat="Metal") + L(cloth, "p", mat="Fabric")
            + L(button, "a"))


@style("fur")
def s_fur():
    lumps = lambda a, z: 0.05 * math.sin(a * 13) + 0.035 * math.sin(a * 7 + z * 9)  # noqa: E731
    fur = ring("Fur", [(3.72, 1.5, 0.66), (3.86, 1.68, 0.78), (4.04, 1.66, 0.8), (4.2, 1.28, 0.7), (4.28, 0.74, 0.5)],
               power=3.2, na=48, thick=0.06, wave=lumps)
    tufts = []
    for k in range(14):
        a = -PI + 2 * PI * (k + 0.5) / 14
        x, y = wear.spt(a, 1.6, 0.76, 3.2)
        tufts.append(wear.cone("t", 0.1, 0.0, 0.18, (x, y, 3.76), segs=5, axis=(math.sin(a) * 0.4, math.cos(a) * 0.4,
                                                                                -1)))
    clasp = ball("Clasp", 0.1, (0, 0.62, 4.0), scale=(1, 0.5, 1), segs=10, rings=5)
    return [T(joined("Fur", [fur] + tufts, 70), "s", mat="Fabric"), T(clasp, "gold", mat="Metal")]


@style("spikes")
def s_spikes():
    sp = []
    for u, v, h in ((-0.1, 0.0, 0.42), (0.25, 0.45, 0.3), (0.25, -0.45, 0.3), (-0.6, 0.0, 0.28)):
        p, n = on_pad(u, v)
        sp.append(wear.cone("s", 0.11, 0.0, h, tuple(p - n * 0.02), segs=8, axis=tuple(n + Vector((-0.2, 0, 0.3)))))
    return L(pad(), "p") + L(rim(), "dark") + L(joined("Spikes", sp), "white")


@style("single")
def s_single():
    big = pad("Pauldron", r=0.72, top=4.45, z0=3.55, z1=3.86, tilt=-0.38)
    lames = [rim("l1", r=0.74, z=3.62, h=0.09, tilt=-0.38), rim("l2", r=0.78, z=3.5, h=0.09, tilt=-0.38)]
    rimr = rim("RimL", r=0.75, z=3.9, h=0.05, tilt=-0.38)
    strap_f = strip("sf", [(-1.0, 0.53, 3.95), (0.0, 0.54, 3.25), (0.95, 0.53, 2.55)], 0.16, up=(0, 1, 0), thick=0.03)
    strap_b = strip("sb", [(-1.0, -0.53, 3.95), (0.0, -0.54, 3.25), (0.95, -0.53, 2.55)], 0.16, up=(0, 1, 0),
                    thick=0.03)
    return [Piece(joined("PauldronL", [big] + lames), "luarm", "s", False, "Metal"),
            Piece(rimr, "luarm", "a", False, None), T(joined("Strap", [strap_f, strap_b]), "dark", mat="Leather")]


@style("layered")
def s_layered():
    plates = []
    for k in range(3):
        t = TILT - 0.22 * k
        plates.append(pad("p%d" % k, r=0.6 + 0.03 * k, top=4.28 - 0.12 * k, z0=3.78 - 0.1 * k, z1=3.92 - 0.06 * k,
                          tilt=t, cx=AX - 0.04 - 0.1 * k, na=16, n=4))
    rivets = []
    for k in range(3):
        for v in (-0.6, 0.6):
            p, n = on_pad(-0.82, v, r=0.6 + 0.03 * k, top=4.28 - 0.12 * k, z1=3.92 - 0.06 * k, lift=0.03,
                          tilt=TILT - 0.22 * k, cx=AX - 0.04 - 0.1 * k)
            rivets.append(ball("r", 0.04, tuple(p), segs=8, rings=4))
    return L(joined("Plates", plates, 35), "s", mat="Metal") + L(joined("Rivets", rivets), "gold", mat="Metal")


@style("pauldrons")
def s_pauldrons():
    shell = pad("Shell", r=0.78, ry=0.74, top=4.55, z0=3.5, z1=3.85, tilt=-0.42, power=2.6,
                wave=lambda a, z: 0.04 * max(0.0, 3.6 - z))
    ridge = []
    pts = []
    for k in range(9):
        v = -0.9 + 1.8 * k / 8
        p, n = on_pad(-0.15, v, r=0.78, top=4.55, z1=3.85, tilt=-0.42, lift=0.02)
        pts.append(tuple(p))
    ridge.append(rod("Ridge", pts, [0.05, 0.08, 0.1, 0.11, 0.11, 0.11, 0.1, 0.08, 0.05], segs=8))
    r = rim("Rim", r=0.8, ry=0.76, z=3.52, h=0.1, tilt=-0.42, power=2.6)
    return L(shell, "s", mat="Metal") + L(ridge[0], "p") + L(r, "a")


@style("coils")
def s_coils():
    mount = pad("Mount", r=0.55, top=4.2, z0=3.86, z1=3.95)
    coils = [kit.torus("c%d" % k, 0.6, 0.06, at=(AX, 0, z), segs=24, csegs=6) for k, z in enumerate((3.82, 3.6))]
    for c in coils:
        kit.shade_auto(c, 60)
    bolts = [ball("b", 0.06, (AX - 0.6 * math.cos(a), 0.6 * math.sin(a), 3.71), segs=8, rings=4)
             for a in (0.0, PI / 2, -PI / 2)]
    return (L(mount, "s", mat="Metal") + L(joined("Coils", coils), "a", True)
            + L(joined("Bolts", bolts), "dark", mat="Metal"))


@style("crystal")
def s_crystal():
    base = pad("Base", r=0.56, top=4.18, z0=3.84, z1=3.94)
    shards = []
    for u, v, h, lean in ((-0.2, 0.0, 0.6, (-0.35, 0, 1)), (0.2, 0.35, 0.42, (0.1, 0.4, 1)),
                          (0.15, -0.38, 0.45, (0.05, -0.45, 1)), (-0.6, 0.3, 0.34, (-0.7, 0.3, 0.6)),
                          (-0.6, -0.3, 0.3, (-0.7, -0.3, 0.6))):
        p, n = on_pad(u, v, r=0.56, top=4.18, z1=3.94)
        d = Vector(lean).normalized()
        body = wear.cone("b", 0.1, 0.1, h * 0.65, tuple(p - n * 0.03), segs=6, axis=tuple(d))
        point = wear.cone("p", 0.1, 0.0, h * 0.35, tuple(p - n * 0.03 + d * h * 0.65), segs=6, axis=tuple(d))
        shards += [body, point]
    return L(base, "s", mat="Metal") + L(joined("Shards", shards, 20), "a", mat="Glass", alpha=0.15)


@style("mantle")
def s_mantle():
    folds = lambda a, z: 0.03 * math.sin(a * 10) * max(0.0, 4.0 - z)  # noqa: E731
    rows = [(3.55, 2.12, 0.86), (3.75, 2.06, 0.84), (3.95, 1.75, 0.8), (4.1, 1.25, 0.7), (4.24, 0.74, 0.5)]
    cape = ring("Mantle", rows, power=3.4, na=48, thick=0.05, wave=folds)
    hem = ring("Hem", [(3.5, 2.14, 0.88), (3.6, 2.16, 0.89)], power=3.4, na=48, thick=0.05, wave=folds)
    collar = ring("Collar", [(4.2, 0.76, 0.52), (4.36, 0.8, 0.56)], power=3.0, na=32, thick=0.05)
    clasp = outline("Clasp", wear.star_pts(0.12, 0.06, n=4), 0.05, at=(0, 0.66, 4.1), axis="Y")
    return [T(cape, "p", mat="Fabric"), T(joined("Trim", [hem, collar]), "s", mat="Fabric"),
            T(clasp, "gold", mat="Metal")]


@style("feathers")
def s_feathers():
    big, small = [], []
    for k in range(5):
        v = -0.6 + 0.3 * k
        p, n = on_pad(0.1, v * 0.8)
        d = Vector((-1.0, v * 0.5, -0.5))
        big.append(leaf("f", 1.0, 0.3, tuple(p), d, up=(0, 1, 0), thick=0.04))
    for k in range(4):
        v = -0.45 + 0.3 * k
        p, n = on_pad(0.2, v * 0.8, lift=0.03)
        d = Vector((-1.0, v * 0.6, -0.25))
        small.append(leaf("s", 0.7, 0.24, tuple(p), d, up=(0, 1, 0), thick=0.04))
    return (L(pad(r=0.5, top=4.18), "s", mat="Fabric") + L(joined("Feathers", big), "white", mat="Fabric")
            + L(joined("Tips", small), "a", mat="Fabric"))


@style("scales")
def s_scales():
    scales = []
    for row, (u, nv) in enumerate(((-0.75, 5), (-0.35, 5), (0.05, 4), (0.4, 3))):
        for k in range(nv):
            v = -0.8 + 1.6 * k / (nv - 1) + (0.12 if row % 2 else 0.0)
            p, n = on_pad(u, v * 0.9, lift=0.02)
            s = ball("s", 0.17, (0, 0, 0), scale=(1.0, 1.0, 0.35), segs=8, rings=4)
            q = Vector((0, 0, 1)).rotation_difference(n)
            s.data.transform(Matrix.Translation(p) @ q.to_matrix().to_4x4())
            scales.append(s)
    return L(pad(), "p", mat="Metal") + L(joined("Scales", scales, 60), "s", mat="Metal")


@style("riveted")
def s_riveted():
    plate = rbox("Plate", 1.16, 1.12, 0.3, at=(AX - 0.05, 0.0, TOP + 0.08), bev=0.08, segs=2)
    side = rbox("Side", 0.14, 1.12, 0.5, at=(AX - 0.6, 0.0, TOP - 0.18), bev=0.05)
    tip(plate, -0.18)
    tip(side, -0.18)
    rivets = []
    for x, y in ((-0.45, 0.45), (-0.45, -0.45), (0.38, 0.45), (0.38, -0.45), (-0.45, 0.0), (0.38, 0.0)):
        rivets.append(tip(ball("r", 0.05, (AX - 0.05 + x, y, TOP + 0.24), segs=8, rings=4), -0.18))
    for y in (-0.4, 0.0, 0.4):
        rivets.append(tip(ball("r", 0.05, (AX - 0.68, y, TOP - 0.25), segs=8, rings=4), -0.18))
    return L(joined("Plate", [plate, side], 30), "s", mat="Metal") + L(joined("Rivets", rivets), "white",
                                                                        mat="Metal")


@style("plume")
def s_plume():
    p = pad("PadL", r=0.6, top=4.3)
    r = rim("Ring", r=0.62, z=3.72)
    pts = [(AX - 0.05, 0.0, 4.25), (AX - 0.15, -0.08, 4.6), (AX - 0.25, -0.3, 4.9), (AX - 0.3, -0.6, 5.0),
           (AX - 0.32, -0.9, 4.85)]
    plume = strip("Plume", pts, [0.12, 0.34, 0.42, 0.38, 0.12], up=(1, 0, 0), thick=0.05)
    plume2 = strip("P2", [(x - 0.06, y + 0.04, z - 0.05) for x, y, z in pts], [0.1, 0.26, 0.32, 0.28, 0.1],
                   up=(1, 0, 0.3), thick=0.04)
    holder = wear.cone("Hold", 0.08, 0.05, 0.16, (AX - 0.05, 0.0, 4.24), segs=8)
    return [Piece(joined("PadL", [p, r, holder]), "luarm", "gold", False, "Metal"),
            Piece(joined("PlumeL", [plume, plume2], 70), "luarm", "a", False, "Fabric")]


@style("wingtips")
def s_wingtips():
    wing = [(0.0, 0.0), (0.12, 0.25), (0.2, 0.55), (0.12, 0.75), (0.02, 0.6), (-0.04, 0.68), (-0.12, 0.45),
            (-0.18, 0.5), (-0.2, 0.25)]
    w = outline("Wing", [(-u * 1.3, v * 1.2) for u, v in wing], 0.06, at=(AX - 0.35, 0.05, 3.98), axis="X",
                bev=0.015)
    wear.turn(w, (0.35, -0.35, 0), (AX - 0.35, 0.05, 3.98))
    return L(pad(r=0.56, top=4.22), "s") + L(w, "white")


@style("shell")
def s_shell():
    ribs = lambda a, z: 0.045 * abs(math.cos(a * 4.5)) * max(0.0, 4.3 - z) * 2.2  # noqa: E731
    sh = pad("Shell", r=0.68, top=4.4, z0=3.6, z1=3.86, power=2.4, wave=ribs, na=36, tilt=-0.38)
    hinge = ball("Hinge", 0.16, (AX + 0.38, 0, 4.18), scale=(0.7, 1.4, 0.6), segs=10, rings=5)
    return L(sh, "p") + L(hinge, "s")


@style("gears")
def s_gears():
    big = wear.gear("Gear", 0.36, 10, 0.08, (AX - 0.62, 0.0, 3.78), axis="X", tooth=0.08)
    small = wear.gear("Small", 0.18, 8, 0.07, (AX - 0.1, 0.42, 4.2), axis="Y", tooth=0.06)
    wear.turn(small, (0.0, -0.5, 0.0), (AX - 0.1, 0.42, 4.2))
    hub = kit.cyl("Hub", 0.12, 0.12, 0.14, at=(AX - 0.66, 0.0, 3.78), segs=12, axis="X")
    hub2 = kit.cyl("Hub2", 0.06, 0.06, 0.1, at=(AX - 0.1, 0.45, 4.2), segs=10, axis="Y")
    return (L(pad(), "dark", mat="Metal") + L(joined("Gears", [big, small], 30), "s", mat="Metal")
            + L(joined("Hubs", [hub, hub2]), "gold", mat="Metal"))


@style("flames")
def s_flames():
    outer, inner = [], []
    for u, v, h in ((0.0, 0.0, 0.7), (-0.4, 0.4, 0.5), (-0.4, -0.4, 0.5), (0.3, 0.45, 0.4), (0.3, -0.45, 0.4)):
        p, n = on_pad(u, v)
        pts, rs = [], []
        for k in range(6):
            t = k / 5
            pts.append(tuple(p + Vector((-0.12 * t * t, 0.04 * math.sin(t * 5), h * t))))
            rs.append(0.13 * (1 - t) ** 0.8 + 0.005)
        outer.append(rod("o", pts, rs, segs=7))
        inner.append(rod("i", [tuple(Vector(q) + Vector((0, 0, -0.02))) for q in pts[:4]],
                         [r * 0.55 for r in rs[:4]], segs=6))
    return (L(pad(), "dark") + L(joined("Flames", outer, 70), "glowRed", True, alpha=0.25)
            + L(joined("Core", inner, 70), "a", True, alpha=0.1))


@style("blades")
def s_blades():
    blade = [(0.0, 0.0), (0.07, 0.0), (0.03, 0.62), (-0.04, 0.0)]
    bl = []
    for k, (y, h, lean) in enumerate(((0.0, 1.0, 0.55), (0.32, 0.75, 0.5), (-0.32, 0.75, 0.5))):
        b = outline("b%d" % k, [(u * 2.2, v * h) for u, v in blade], 0.05, at=(AX - 0.3, y, 4.15), axis="X")
        wear.turn(b, (0, -lean, 0), (AX - 0.3, y, 4.15))
        bl.append(b)
    return L(pad(), "dark", mat="Metal") + L(rim(), "a") + L(joined("Blades", bl, 20), "white", mat="Metal")


# ---------------------------------------------------------------- build, export, preview
HEADER = ["shoulders.py",
          "The creator's shoulder pieces as meshes (ReplicatedStorage.Art.Shoulders once nate imports",
          "art/export/Shoulders.fbx; LookKit wears them then, the part-built ones until then). Keyed by the Shoulders",
          "slot's kit: each piece's mesh name, the body part it is welded to (at: an upper arm, or the torso), its",
          "colour role (the slot's p main, s trim, a accent, or dark, white, gold, ice, glowRed), glow (Neon), material",
          "and transparency, and its box against that part's centre in Roblox axes (x right, y up, z back), in studs",
          "on the standard blocky rig (scaled with the part)."]

PARTS = {"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "Head"}


def preview(built):
    def dress(name, at, yaw, pal):
        wear.body(at, yaw, suit=(150, 156, 170), parts=PARTS)
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", "shoulders.png" if ONLY is None else "shoulders_test.png")
    wear.grid_preview(built, out, dress, cols=5, cell=5.0, px=340, focus=3.75, yaw_front=180 - 30, yaw_back=30,
                      samples=32, look_down=0.12)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Shoulder_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Shoulders.fbx"))
        wear.write_fit("ShoulderArt", HEADER, rows)
    preview(built)
