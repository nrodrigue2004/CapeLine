# hats.py: the hero creator's headwear as meshes (creator art round 3, 2026-11-18), in place of the boxes, balls,
# wedges and cylinders PieceKits welds to the head for the Headwear slot. Each kit is a few one-colour meshes round
# the classic rounded head (radius 0.6, z 4.02 to 5.2, centre 4.61; kit.py axes: +y is the face): caps, a beanie,
# brims, hoods and helmets that clear the hair (or cover it, like the part-built ones: PieceKits.hatHidesHair),
# bands, glasses and goggles at the eyes, headphones, horns, antlers, crowns, a halo and a laurel. Bright, chunky
# comic shapes that read on a phone at a distance; all original (no famous character's hat or helmet).
# Output: art/export/Hats.fbx (nate imports it as ReplicatedStorage.Art.Hats), src/config/HatArt.luau (each kit's
# meshes with role, glow, material and box against the Head, LookKit's fit) and art/preview/hats.png.
# Run: python art/blender/hats.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, ring, dome_rows, rbox, ball, rod, joined, outline, strip  # noqa: E402
import bpy  # noqa: E402, F401
from mathutils import Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2400  # triangles a hat
HZ = 4.61  # the head's centre
FACE = 0.6  # the face's front (y)
HP = 2.25  # the head's outline power

kit.reset()

STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


def H(ob, role, glow=False, mat=None, alpha=0.0):
    wear.bake(ob)
    return Piece(ob, "head", role, glow, mat, alpha)


def hw(name, rows, na=32, thick=0.04, hole=None, wave=None, power=HP, cy=0.0, a0=-PI, a1=PI):
    """A surface round the head: rows [(z, r)] (round) or [(z, rx, ry)]."""
    rr = [(r[0], r[1], r[1] if len(r) == 2 else r[2]) for r in rows]
    return ring(name, rr, power=power, na=na, cy=cy, thick=thick, hole=hole, wave=wave, a0=a0, a1=a1)


def crown_rows(z0, z1, r, top, n=6):
    return [(z, rx) for z, rx, _ in dome_rows(z0, z1, r, r, top=top, n=n)]


def disc(name, r, z, thick=0.05, na=40, curl=0.0, cy=0.0, rx=None, ry=None, power=2.0, inner=0.35):
    """A flat ring (a brim) from radius inner*r out to r at height z, its edge curled up by `curl`."""
    rows = []
    for k in range(5):
        t = inner + (1 - inner) * k / 4
        rows.append((z + curl * t ** 3, (rx or r) * t, (ry or r) * t))
    return ring(name, rows, power=power, na=na, cy=cy, thick=thick)


def eye_band(name, z0, z1, r=0.64, a=1.9, thick=0.04, bulge=0.05):
    return hw(name, [(z0, r), (z1, r)], a0=-a, a1=a, na=24, thick=thick,
              wave=lambda aa, z: bulge * math.cos(aa) ** 2)


def tails(z, length=0.6, w=0.12, spread=0.12, drop=0.55):
    out = []
    for sx in (-1, 1):
        pts = [(sx * 0.04, -0.64, z), (sx * spread, -0.75, z - 0.2 * drop), (sx * spread * 1.6, -0.8, z - drop * 0.6),
               (sx * spread * 2.0, -0.82, z - drop)]
        out.append(strip("t", pts, [w, w * 0.95, w * 0.9, w * 1.1], up=(1, 0, 0), thick=0.03))
    return out


# ---------------------------------------------------------------- the 25 kits
@style("cap")
def h_cap():
    crown = hw("Crown", crown_rows(4.9, 5.05, 0.69, 5.53), na=32)
    seam = rod("Seam", [(0.0, 0.67, 5.0), (0.0, 0.45, 5.35), (0.0, 0.0, 5.48)], 0.015, segs=4)
    bill_pts = [(0.6 * math.cos(a), 0.42 + 0.58 * math.sin(a)) for a in (PI * k / 16 for k in range(17))]
    bill = outline("Bill", bill_pts, 0.05, at=(0, 0, 4.95), axis="Z", bev=0.015)
    for v in bill.data.vertices:
        v.co.z -= 0.25 * max(0.0, v.co.y - 0.55) ** 2 + 0.05 * (v.co.x ** 2)
    button = ball("Button", 0.06, (0, 0, 5.48), scale=(1, 1, 0.5), segs=8, rings=4)
    logo = outline("Logo", wear.star_pts(0.12, 0.05), 0.02, at=(0, 0.69, 5.18), axis="Y")
    wear.turn(logo, (-0.35, 0, 0), (0, 0.69, 5.18))
    return [H(joined("Crown", [crown, seam]), "p", mat="Fabric"), H(joined("Bill", [bill, button]), "s"),
            H(logo, "a")]


@style("beanie")
def h_beanie():
    ribs = lambda a, z: 0.012 * math.cos(a * 24)  # noqa: E731
    knit = hw("Knit", crown_rows(4.82, 5.08, 0.665, 5.58, n=7), na=48, wave=ribs)
    cuff = hw("Cuff", [(4.66, 0.68), (4.79, 0.69), (4.94, 0.685)], na=48, thick=0.06,
              wave=lambda a, z: 0.018 * math.cos(a * 24))
    pom = ball("Pom", 0.17, (0, -0.05, 5.62), segs=12, rings=8)
    for v in pom.data.vertices:
        v.co += (v.co - Vector((0, -0.05, 5.62))) * 0.12 * math.sin(v.co.x * 40) * math.sin(v.co.z * 40)
    return [H(knit, "p", mat="Fabric"), H(joined("Cuff", [cuff, pom], 70), "s", mat="Fabric")]


@style("headband")
def h_headband():
    band = hw("Band", [(4.88, 0.635), (4.98, 0.645), (5.08, 0.635)], na=40, thick=0.05)
    knot = ball("Knot", 0.1, (0.0, -0.66, 4.98), scale=(1.2, 0.7, 1.0), segs=10, rings=6)
    return [H(joined("Band", [band, knot] + tails(4.97, w=0.1, drop=0.5)), "p", mat="Fabric"),
            H(rbox("Plate", 0.3, 0.04, 0.12, at=(0, 0.66, 4.98), bev=0.015), "s", mat="Metal")]


@style("shades")
def h_shades():
    lens_pts = [(0.17 * math.cos(a) * (1.1 if math.cos(a) > 0 else 1.0), 0.11 * math.sin(a) - 0.02 * math.cos(a))
                for a in (2 * PI * k / 16 for k in range(16))]
    lenses, rims = [], []
    for sx in (-1, 1):
        pts = [(sx * u, v) for u, v in lens_pts]
        if sx < 0:
            pts.reverse()
        lenses.append(outline("l", pts, 0.03, at=(sx * 0.22, FACE + 0.06, 4.7), axis="Y"))
        rp = [(sx * 0.22 + u * 1.12, FACE + 0.07, 4.7 + v * 1.15) for u, v in pts] + []
        rp.append(rp[0])
        rims.append(rod("r", rp, 0.022, segs=5))
    bridge = rod("Bridge", [(-0.06, FACE + 0.07, 4.74), (0.0, FACE + 0.08, 4.76), (0.06, FACE + 0.07, 4.74)], 0.022,
                 segs=5)
    arms = [rod("a", [(sx * 0.41, FACE + 0.05, 4.74), (sx * 0.64, 0.35, 4.74), (sx * 0.66, -0.15, 4.72),
                      (sx * 0.64, -0.25, 4.62)], 0.022, segs=5) for sx in (-1, 1)]
    return [H(joined("Lenses", lenses, 20), "dark", mat="Glass"), H(joined("Frame", rims + [bridge] + arms, 60), "p")]


@style("goggles")
def h_goggles():
    strap = hw("Strap", [(4.92, 0.64), (5.06, 0.645)], na=40, thick=0.04)
    cups, lenses = [], []
    for sx in (-1, 1):
        c = (sx * 0.24, FACE + 0.06, 5.0)
        cup = kit.cyl("c", 0.17, 0.15, 0.14, at=c, segs=16, axis="Y")
        wear.turn(cup, (-0.4, 0, 0), c)
        rim_ = kit.torus("r", 0.16, 0.035, at=(c[0], c[1] + 0.07, c[2]), segs=16, csegs=5, axis="Y")
        wear.turn(rim_, (-0.4, 0, 0), c)
        lens = kit.cyl("l", 0.135, 0.135, 0.03, at=(c[0], c[1] + 0.075, c[2]), segs=16, axis="Y")
        wear.turn(lens, (-0.4, 0, 0), c)
        cups += [cup, rim_]
        lenses.append(lens)
    bridge = rod("Bridge", [(-0.1, FACE + 0.1, 5.0), (0.1, FACE + 0.1, 5.0)], 0.03, segs=5)
    return [H(strap, "dark", mat="Leather"), H(joined("Cups", cups + [bridge], 50), "s", mat="Metal"),
            H(joined("Lenses", lenses), "a", mat="Glass", alpha=0.2)]


@style("visor")
def h_visor():
    lens = hw("Lens", [(4.55, 0.7), (4.68, 0.73), (4.84, 0.72)], a0=-1.25, a1=1.25, na=20, thick=0.035,
              wave=lambda a, z: 0.06 * math.cos(a) ** 2)
    frame = hw("Frame", [(4.84, 0.71), (4.9, 0.71)], a0=-1.35, a1=1.35, na=20, thick=0.04,
               wave=lambda a, z: 0.06 * math.cos(a) ** 2)
    arch = kit.torus("Arch", 0.67, 0.045, at=(0, 0, 4.72), segs=24, csegs=5, arc=PI, axis="Y")
    wear.turn(arch, (0, 0, 0), (0, 0, 4.72))
    pods = [kit.cyl("p", 0.16, 0.14, 0.1, at=(sx * 0.66, 0.0, 4.72), segs=14, axis="X") for sx in (-1, 1)]
    return [H(lens, "a", True, alpha=0.3), H(joined("Frame", [frame, arch], 50), "dark", mat="Metal"),
            H(joined("Pods", pods), "s", mat="Metal")]


@style("phones")
def h_phones():
    arch = kit.torus("Arch", 0.72, 0.06, at=(0, 0, 4.7), segs=28, csegs=6, arc=PI, axis="Y")
    pad_ = kit.torus("Pad", 0.7, 0.045, at=(0, 0, 4.7), segs=12, csegs=5, arc=PI * 0.5, axis="Y")
    wear.turn(pad_, (0, -PI * 0.25, 0), (0, 0, 4.7))
    cups, cushions = [], []
    for sx in (-1, 1):
        cups.append(kit.cyl("c", 0.27, 0.25, 0.2, at=(sx * 0.76, 0.0, 4.62), segs=20, axis="X"))
        cushions.append(kit.torus("k", 0.2, 0.06, at=(sx * 0.66, 0.0, 4.62), segs=16, csegs=5, axis="X"))
        cups.append(kit.cyl("s", 0.06, 0.06, 0.12, at=(sx * 0.72, 0.0, 4.92), segs=8))
    return [H(joined("Arch", [arch] + cushions + [pad_], 50), "dark"), H(joined("Cups", cups, 40), "p"),
            H(joined("Lights", [kit.cyl("l", 0.12, 0.12, 0.03, at=(sx * 0.87, 0, 4.62), segs=14, axis="X")
                                for sx in (-1, 1)]), "a", True)]


@style("brim")
def h_brim():
    crown = hw("Crown", [(4.98, 0.6), (5.25, 0.57), (5.48, 0.54), (5.58, 0.42), (5.6, 0.0)], na=32,
               wave=lambda a, z: -0.06 * max(0.0, z - 5.45) * 6 * math.cos(a) ** 8)
    brim = disc("Brim", 1.1, 4.98, thick=0.05, na=40, curl=0.12, inner=0.5)
    band = hw("Band", [(4.99, 0.615), (5.1, 0.6)], na=32, thick=0.03)
    return [H(joined("Hat", [crown, brim]), "p", mat="Fabric"), H(band, "s", mat="Fabric")]


@style("tophat")
def h_tophat():
    crown = hw("Crown", [(5.02, 0.5), (5.4, 0.48), (5.8, 0.52), (5.86, 0.0)], na=32, power=2.0)
    brim = disc("Brim", 0.82, 5.02, thick=0.05, na=40, curl=0.1, inner=0.55, rx=0.86, ry=0.76)
    band = hw("Band", [(5.06, 0.51), (5.2, 0.505)], na=32, thick=0.03, power=2.0)
    return [H(joined("Hat", [crown, brim]), "dark", mat="Fabric"), H(band, "p", mat="Fabric")]


@style("streethood")
def h_streethood():
    face = lambda a, z: abs(a) < 0.95 and 4.05 < z < 5.12  # noqa: E731
    rows = [(3.95, 0.74, 0.7), (4.2, 0.72, 0.72), (4.6, 0.73, 0.74), (5.0, 0.72, 0.73), (5.25, 0.64, 0.66),
            (5.42, 0.46, 0.5), (5.52, 0.2, 0.26), (5.54, 0.0, 0.0)]
    hood = ring("Hood", rows, power=HP, na=36, cy=-0.04, thick=0.05, hole=face,
                wave=lambda a, z: 0.02 * math.sin(a * 5 + z * 6))
    edge = []
    pts = []
    for k in range(19):
        t = k / 18
        a = -0.95 + 1.9 * t
        z = 4.05 + 1.07 * math.sin(PI * t) ** 0.6
        x, y = wear.spt(a, 0.74, 0.75, HP)
        pts.append((x, y - 0.04, z))
    edge.append(rod("Edge", pts, 0.05, segs=6))
    strings = [rod("s", [(sx * 0.25, 0.66, 4.15), (sx * 0.27, 0.7, 3.85), (sx * 0.26, 0.69, 3.6)], 0.025, segs=5)
               for sx in (-1, 1)]
    tips = [kit.cyl("t", 0.035, 0.035, 0.1, at=(sx * 0.26, 0.69, 3.55), segs=6) for sx in (-1, 1)]
    return [H(joined("Hood", [hood] + edge), "p", mat="Fabric"), H(joined("Strings", strings + tips), "white")]


@style("crown")
def h_crown():
    band = hw("Band", [(4.98, 0.645), (5.18, 0.65)], na=40, thick=0.05)
    pts = []
    n = 10
    for k in range(n):
        a = -PI + 2 * PI * (k + 0.5) / n
        x, y = wear.spt(a, 0.65, 0.65, HP)
        h = 0.32 if k % 2 == 0 else 0.2
        c = wear.cone("p", 0.11, 0.0, h, (x, y, 5.15), segs=4, axis=(x * 0.15, y * 0.15, 1))
        pts.append(c)
    gems = []
    for k in range(n):
        if k % 2:
            continue
        a = -PI + 2 * PI * (k + 0.5) / n
        x, y = wear.spt(a, 0.69, 0.69, HP)
        gems.append(ball("g", 0.055, (x, y, 5.08), scale=(1, 1, 1.2), segs=8, rings=4))
    return [H(joined("Crown", [band] + pts, 30), "gold", mat="Metal"), H(joined("Gems", gems), "a", True)]


@style("horns")
def h_horns():
    # ram horns: thick ridged curls from the temples, round behind the ears and forward again
    horns = []
    for sx in (-1, 1):
        pts, rs = [], []
        n = 20
        for k in range(n):
            t = k / (n - 1)
            ang = 4.4 * t
            r = 0.36 * (1 - 0.45 * t)
            pts.append((sx * (0.42 + r * (1 - math.cos(ang)) * 1.1), -0.05 - 0.2 * t, 5.02 + r * math.sin(ang)))
            rs.append(0.15 * (1 - 0.8 * t) + 0.018 * abs(math.cos(k * 1.6)))
        horns.append(rod("h", pts, rs, segs=9))
    return [H(joined("Horns", horns, 60), "white")]


HALO_Z = 5.82


@style("halo")
def h_halo():
    # pt-fit 2026-11-19: 0.2 higher (was 5.62) so it floats over a Roblox catalog hair, not inside it
    halo = kit.torus("Halo", 0.5, 0.06, at=(0, -0.05, HALO_Z), segs=32, csegs=6)
    wear.turn(halo, (-0.2, 0, 0), (0, -0.05, HALO_Z))
    kit.shade_auto(halo, 60)
    glints = [ball("g", 0.05, (0.5 * math.cos(a), -0.05 + 0.5 * math.sin(a), HALO_Z), segs=8, rings=4)
              for a in (0.5, 2.6, 4.4)]
    for g in glints:
        wear.turn(g, (-0.2, 0, 0), (0, -0.05, HALO_Z))
    return [H(halo, "a", True, alpha=0.2), H(joined("Glints", glints), "white", True)]


@style("kabuto")
def h_kabuto():
    bowl = hw("Bowl", crown_rows(4.82, 5.0, 0.7, 5.56, n=7), na=36, thick=0.05,
              wave=lambda a, z: 0.015 * abs(math.cos(a * 8)))
    guard = []
    for k in range(3):
        z = 4.78 - 0.14 * k
        r = 0.74 + 0.1 * k
        guard.append(hw("g", [(z - 0.13, r + 0.08, r + 0.08), (z, r, r)], a0=PI - 2.2, a1=PI + 2.2, na=24,
                        thick=0.04, cy=-0.04))
    brow = hw("Brow", [(4.8, 0.72), (4.86, 0.73)], a0=-1.3, a1=1.3, na=16, thick=0.05)
    fan = []
    for k in range(7):
        a = -0.9 + 1.8 * k / 6
        fan.append(outline("f", [(-0.04, 0.0), (0.04, 0.0), (0.07, 0.55), (-0.07, 0.55)], 0.03,
                           at=(0, 0.76, 4.92), axis="Y"))
        wear.turn(fan[-1], (0, a * 0.8, 0), (0, 0.76, 4.92))
    disc_ = kit.cyl("Disc", 0.13, 0.13, 0.05, at=(0, 0.78, 4.95), segs=16, axis="Y")
    plume = rod("Plume", [(0, -0.1, 5.55), (0, -0.35, 5.75), (0, -0.65, 5.7), (0, -0.85, 5.45)],
                [0.06, 0.12, 0.1, 0.03], segs=8)
    return [H(joined("Helm", [bowl, brow] + guard, 40), "dark", mat="Metal"),
            H(joined("Crest", fan + [disc_], 30), "gold", mat="Metal"), H(plume, "a", mat="Fabric")]


@style("knight")
def h_knight():
    slit = lambda a, z: abs(a) < 0.62 and 4.64 < z < 4.74  # noqa: E731
    rows = [(3.98, 0.7), (4.3, 0.71), (4.7, 0.72), (5.0, 0.71)] + crown_rows(5.0, 5.05, 0.71, 5.5)[2:]
    shell = hw("Shell", rows, na=36, thick=0.05, hole=slit,
               wave=lambda a, z: 0.05 * max(0.0, math.cos(a)) ** 6 * (1 if z < 4.95 else 0))
    inner = hw("Slit", [(4.62, 0.66), (4.76, 0.66)], a0=-0.7, a1=0.7, na=10, thick=0.02)
    ridge = rod("Ridge", [(0, 0.76, 4.2), (0, 0.79, 4.6), (0, 0.76, 5.0), (0, 0.5, 5.4), (0, 0.0, 5.52),
                          (0, -0.5, 5.4), (0, -0.74, 5.0)], 0.04, segs=6)
    holes = [kit.cyl("h", 0.03, 0.03, 0.1, at=(sx * x, 0.7, z), segs=6, axis="Y")
             for sx in (-1, 1) for x, z in ((0.2, 4.35), (0.32, 4.4), (0.2, 4.47))]
    plume = []
    for k in range(5):
        plume.append(rod("p", [(0.0, 0.2 - 0.08 * k, 5.5), (0.0, -0.1 - 0.15 * k, 5.85 - 0.05 * k),
                               (0.0, -0.45 - 0.15 * k, 5.75 - 0.15 * k)], [0.05, 0.09, 0.03], segs=6))
    return [H(joined("Shell", [shell, ridge], 40), "s", mat="Metal"), H(joined("Slit", [inner] + holes), "dark"),
            H(joined("Plume", plume, 60), "p", mat="Fabric")]


@style("dorag")
def h_dorag():
    cap = hw("Cap", [(4.78, 0.645), (4.95, 0.66)] + crown_rows(4.95, 5.0, 0.66, 5.44)[2:], na=36, thick=0.04,
             wave=lambda a, z: 0.012 * math.sin(a * 6 + z * 10))
    knot = ball("Knot", 0.1, (0, -0.67, 4.85), scale=(1.3, 0.7, 1.0), segs=10, rings=6)
    return [H(joined("Cap", [cap, knot] + tails(4.84, w=0.13, drop=0.7, spread=0.06)), "p", mat="Fabric")]


@style("beret")
def h_beret():
    c = (0.12, 0.02, 5.2)
    top = ball("Beret", 0.72, c, scale=(1.0, 0.95, 0.28), segs=28, rings=10)
    for v in top.data.vertices:
        if v.co.z < c[2] - 0.08:
            v.co.z = c[2] - 0.08
    wear.turn(top, (0, 0.22, 0), (0, 0, 5.1))
    band = hw("Band", [(4.95, 0.64), (5.05, 0.645)], na=32, thick=0.04)
    stalk = kit.cyl("Stalk", 0.03, 0.02, 0.1, at=(0.17, 0.02, 5.42), segs=6)
    wear.turn(stalk, (0, 0.22, 0), (0, 0, 5.1))
    return [H(top, "p", mat="Fabric"), H(joined("Band", [band, stalk]), "s", mat="Leather")]


@style("bucket")
def h_bucket():
    crown = hw("Crown", [(4.86, 0.68), (5.2, 0.62), (5.42, 0.56), (5.5, 0.0)], na=32)
    brim = hw("Brim", [(4.62, 0.98), (4.74, 0.83), (4.86, 0.68)], na=36, thick=0.05)
    band = hw("Band", [(4.86, 0.69), (4.96, 0.67)], na=32, thick=0.03)
    stitch = [hw("s%d" % k, [(4.67 + 0.05 * k, 0.94 - 0.13 * k), (4.68 + 0.05 * k, 0.93 - 0.13 * k)], na=36,
                 thick=0.015) for k in range(2)]
    return [H(joined("Hat", [crown, brim]), "p", mat="Fabric"), H(joined("Band", [band] + stitch), "s",
                                                                  mat="Fabric")]


@style("catears")
def h_catears():
    band = kit.torus("Band", 0.66, 0.035, at=(0, 0.05, 4.78), segs=24, csegs=5, arc=PI, axis="Y")
    ears, inners = [], []
    for sx in (-1, 1):
        c = (sx * 0.36, 0.05, 5.15)
        e = outline("e", [(-0.26, 0.0), (0.26, 0.0), (0.07 * sx, 0.56)], 0.12, at=c, axis="Y", bev=0.04)
        wear.turn(e, (0, sx * 0.25, 0), c)
        i = outline("i", [(-0.15, 0.05), (0.15, 0.05), (0.04 * sx, 0.4)], 0.04, at=(c[0], c[1] + 0.07, c[2]),
                    axis="Y")
        wear.turn(i, (0, sx * 0.25, 0), c)
        ears.append(e)
        inners.append(i)
    return [H(joined("Ears", [band] + ears, 30), "p"), H(joined("Inner", inners), "s")]


@style("antlers")
def h_antlers():
    parts = []
    for sx in (-1, 1):
        b = (sx * 0.38, 0.0, 5.12)
        main = [b, (sx * 0.55, -0.05, 5.5), (sx * 0.7, -0.12, 5.85), (sx * 0.78, -0.18, 6.1)]
        parts.append(rod("m", main, [0.07, 0.06, 0.045, 0.02], segs=7))
        for p0, p1 in (((sx * 0.55, -0.05, 5.5), (sx * 0.42, 0.12, 5.82)),
                       ((sx * 0.68, -0.1, 5.8), (sx * 0.95, -0.05, 5.98)),
                       ((sx * 0.48, -0.02, 5.35), (sx * 0.8, 0.02, 5.42))):
            parts.append(rod("t", [p0, p1], [0.045, 0.018], segs=6))
        parts.append(kit.torus("base", 0.08, 0.03, at=(b[0], b[1], b[2] + 0.02), segs=10, csegs=4))
    return [H(joined("Antlers", parts, 50), "s", mat="Wood")]


@style("hachimaki")
def h_hachimaki():
    band = hw("Band", [(4.86, 0.64), (4.95, 0.65), (5.04, 0.64)], na=40, thick=0.05)
    knot = ball("Knot", 0.09, (0, -0.66, 4.95), scale=(1.2, 0.7, 1.0), segs=10, rings=6)
    mark = outline("Mark", wear.rrect_pts(0.28, 0.12, 0.04), 0.03, at=(0, 0.675, 4.95), axis="Y")
    return [H(joined("Band", [band, knot] + tails(4.94, w=0.09, drop=0.65, spread=0.1)), "white", mat="Fabric"),
            H(mark, "glowRed")]


@style("tiara")
def h_tiara():
    band = rod("Band", [(x, y, 5.0) for x, y in (wear.spt(-1.9 + 3.8 * k / 20, 0.655, 0.655, HP)
                                                for k in range(21))], 0.03, segs=5)
    peak = outline("Peak", [(-0.18, 0.0), (0.0, 0.0), (0.18, 0.0), (0.06, 0.12), (0.0, 0.32), (-0.06, 0.12)], 0.04,
                   at=(0, 0.66, 5.0), axis="Y", bev=0.01)
    sides = []
    for sx in (-1, 1):
        a = sx * 0.6
        x, y = wear.spt(a, 0.66, 0.66, HP)
        sides.append(wear.cone("s", 0.05, 0.0, 0.16, (x, y, 5.01), segs=4))
    gem = ball("Gem", 0.07, (0, 0.71, 5.11), scale=(1, 0.5, 1.3), segs=8, rings=5)
    return [H(joined("Tiara", [band, peak] + sides, 40), "gold", mat="Metal"), H(gem, "a", mat="Glass")]


@style("laurel")
def h_laurel():
    leaves = []
    for sx in (-1, 1):
        n = 9
        for k in range(n):
            t = k / (n - 1)
            a = sx * (0.35 + 2.35 * t)
            x, y = wear.spt(a, 0.68, 0.68, HP)
            z = 5.0 - 0.06 * t
            for side in (-1, 1):
                d = Vector((math.cos(a) * sx * 0.3, -math.sin(a) * sx * 0.3, 0.6 * side + 0.2)).normalized()
                pts, ws = [], []
                for j in range(4):
                    u = j / 3
                    pts.append(Vector((x, y, z)) + d * 0.2 * u)
                    ws.append(0.11 * math.sin(PI * min(1.0, u * 1.0 + 0.15)) + 0.01)
                nrm = Vector((x, y, 0)).normalized()
                leaves.append(strip("l", pts, ws, up=tuple(nrm.cross(d)), thick=0.02))
        stem = [wear.spt(sx * (0.35 + 2.35 * k / 12), 0.67, 0.67, HP) for k in range(13)]
        leaves.append(rod("s", [(p[0], p[1], 5.0 - 0.06 * k / 12) for k, p in enumerate(stem)], 0.018, segs=4))
    return [H(joined("Laurel", leaves, 50), "gold", mat="Metal")]


@style("lens")
def h_lens():
    pod = rbox("Pod", 0.12, 0.3, 0.3, at=(0.67, 0.0, 4.68), bev=0.04)
    arm = rod("Arm", [(0.67, 0.12, 4.74), (0.6, 0.45, 4.76), (0.42, 0.66, 4.74)], 0.03, segs=5)
    frame = kit.torus("Frame", 0.15, 0.025, at=(0.24, 0.68, 4.72), segs=16, csegs=4, axis="Y")
    lens = kit.cyl("Lens", 0.14, 0.14, 0.02, at=(0.24, 0.68, 4.72), segs=16, axis="Y")
    light = ball("Light", 0.045, (0.74, 0.08, 4.78), segs=8, rings=4)
    return [H(joined("Pod", [pod, arm, frame], 40), "dark", mat="Metal"), H(lens, "a", True, alpha=0.3),
            H(light, "glowRed", True)]


@style("aviator")
def h_aviator():
    cap = hw("Cap", [(4.82, 0.65), (4.98, 0.665)] + crown_rows(4.98, 5.0, 0.665, 5.46)[2:], na=36, thick=0.05,
             wave=lambda a, z: 0.012 * abs(math.cos(a * 3)))
    flaps = []
    for sx in (-1, 1):
        f = hw("f", [(4.3, 0.645), (4.55, 0.66), (4.85, 0.665)], a0=sx * PI / 2 - 0.55, a1=sx * PI / 2 + 0.55, na=8,
               thick=0.05)
        flaps.append(f)
    strap = rod("Strap", [(-0.6, 0.15, 4.32), (-0.3, 0.5, 3.98), (0.3, 0.5, 3.98), (0.6, 0.15, 4.32)], 0.03, segs=5)
    fur = hw("Fur", [(4.8, 0.68), (4.88, 0.69)], na=36, thick=0.05, wave=lambda a, z: 0.02 * math.sin(a * 17))
    cups, lenses = [], []
    for sx in (-1, 1):
        c = (sx * 0.24, FACE + 0.08, 5.06)
        cups.append(kit.torus("r", 0.15, 0.035, at=c, segs=16, csegs=5, axis="Y"))
        lenses.append(kit.cyl("l", 0.14, 0.14, 0.03, at=c, segs=16, axis="Y"))
        for o in (cups[-1], lenses[-1]):
            wear.turn(o, (-0.45, 0, 0), c)
    return [H(joined("Cap", [cap] + flaps), "s", mat="Leather"), H(fur, "white", mat="Fabric"),
            H(joined("Rims", cups + [strap], 50), "dark", mat="Metal"),
            H(joined("Lenses", lenses), "a", mat="Glass", alpha=0.2)]


# ---------------------------------------------------------------- build, export, preview
HEADER = ["hats.py",
          "The creator's headwear as meshes (ReplicatedStorage.Art.Hats once nate imports art/export/Hats.fbx; LookKit",
          "wears them then, the part-built ones until then). Keyed by the Headwear slot's kit: each piece's mesh name,",
          "the body part it is welded to (at: the head), its colour role (the slot's p main, s trim, a accent, or",
          "dark, white, gold, ice, glowRed), glow (Neon), material and transparency, and its box against the Head's",
          "centre in Roblox axes (x right, y up, z back), in studs on the standard blocky rig (scaled with the head).",
          "hair = false: the hat covers the hair (the same kits as PieceKits.hatHidesHair)."]

# the kits that cover the hair (as PieceKits.hatHidesHair, so a hat hides the same hair with meshes or parts)
# pt-fit 2026-11-19: the crowned hats (cap, brim, tophat, beret) cover it too: Roblox catalog hair rises 0.15 to 0.9
# above the head, so they sank into it
COVERS_HAIR = {"beanie", "streethood", "kabuto", "knight", "dorag", "bucket", "aviator", "cap", "brim", "tophat", "beret"}


def preview(built):
    def dress(name, at, yaw, pal):
        wear.body(at, yaw, parts={"Head"}, show_hair=name not in COVERS_HAIR)
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", "hats.png" if ONLY is None else "hats_test.png")
    wear.grid_preview(built, out, dress, cols=5, cell=3.0, px=300, focus=4.95, yaw_front=180 - 30, yaw_back=25)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Hat_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    for name in rows:
        rows[name]["flags"] = {"hair": name not in COVERS_HAIR}
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Hats.fbx"))
        wear.write_fit("HatArt", HEADER, rows)
    preview(built)
