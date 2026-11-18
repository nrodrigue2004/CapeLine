# heads.py: the hero creator's head pieces as meshes (creator art round 2, 2026-11-18), in place of the boxes, balls
# and wedges LookKit and PieceKits weld to the head: the visor, the helmets and the 3D masks (the 8 flat masks are
# head decals, art/clothes/masks.py). Each kit is a few one-colour meshes round the classic rounded head (radius 0.6,
# z 4.02 to 5.2, centre 4.61; kit.py axes: +y is the face): shells that hug the head with a face opening or a
# visor, bands, plates with eye holes so the hero's own eyes show through, horns, fins, rays and lenses. Bright,
# chunky comic shapes that read on a phone at a distance; all original (no famous hero's helmet or mask).
# Output: art/export/Heads.fbx (nate imports it as ReplicatedStorage.Art.Heads), src/config/HeadArt.luau (each
# kit's meshes with role, glow, material and box against the Head, LookKit's fit) and art/preview/heads.png
# (every kit from the front three-quarter and from behind).
# Run: python art/blender/heads.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2400  # triangles a head kit (a helmet shell is two-sided: solidified so its rim has depth)
HZ = 4.61  # the head's centre
TOPZ = 5.2
PI = math.pi

kit.reset()


def sp(a, r, power=2.25):
    """A point on the head's rounded-square outline at angle a (0 = the face, +y; positive a turns toward +x, the
    hero's right) and radius r."""
    s, c = math.sin(a), math.cos(a)
    return (r * math.copysign(abs(s) ** (2 / power), s), r * math.copysign(abs(c) ** (2 / power), c))


def wrap(name, a0, a1, rows, na=28, bulge=None, hole=None, power=2.25, cy=0.0, thick=0.04):
    """A surface round the head: columns from angle a0 to a1 (a full turn closes the seam), rows [(z, r)] bottom
    to top. bulge(a, z) -> extra radius; hole(a, z) -> True leaves that face out (eye holes, the face opening).
    Solidified by `thick` (0: a single sheet)."""
    full = a1 - a0 >= 2 * PI - 1e-6
    ncol = na if full else na + 1
    bm = bmesh.new()
    grid = []
    for z, r in rows:
        row = []
        for i in range(ncol):
            a = a0 + (a1 - a0) * i / na
            rr = r + (bulge(a, z) if bulge and r > 1e-4 else 0.0)
            x, y = sp(a, rr, power)
            row.append(bm.verts.new((x, y + cy, z)))
        grid.append(row)
    for j in range(len(rows) - 1):
        for i in range(na if full else na):
            i2 = (i + 1) % ncol
            am = a0 + (a1 - a0) * (i + 0.5) / na
            zm = (rows[j][0] + rows[j + 1][0]) / 2
            if hole and hole(am, zm):
                continue
            q = [grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]]
            if len(set(q)) == 4:
                bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    ob = kit._obj(name, bm)
    if thick > 0:
        wear.solid(ob, thick, 0.0)
    kit.shade_auto(ob, 50)
    return ob


def dome(z0, z1, r, top=None, n=7, flat=0.0):
    """Rows for a shell: straight from z0 up to z1 at radius r, then a rounded dome closing at `top`."""
    top = top or (z1 + r * 0.62)
    out = [(z0, r), ((z0 + z1) / 2, r), (z1, r)]
    for k in range(1, n + 1):
        t = k / n * PI / 2
        out.append((z1 + (top - z1) * math.sin(t), r * math.cos(t) * (1 - flat) + flat * r * (1 - k / n)))
    return out


def band(z0, z1, r):
    return [(z0, r), (z1, r)]


def eyes_hole(w=0.17, h=0.11, x=0.22, z=4.7, r=0.6):
    """Eye holes at the face decal's eyes (x +-0.22, z 4.7)."""
    ax = math.asin(min(0.99, x / r))
    aw = w / r

    def f(a, zz):
        return (abs(abs(a) - ax) < aw and abs(zz - z) < h)
    return f


def either(*fs):
    return lambda a, z: any(f(a, z) for f in fs)


def flat_shape(name, pts, depth, at, axis="Y", bevel=0.0):
    """A flat 2D outline extruded `depth` thick: pts [(u, v)] in the plane across `axis` (Y: u = x, v = z;
    X: u = y, v = z), centred at `at`."""
    bm = bmesh.new()
    vs = []
    for u, v in pts:
        if axis == "Y":
            vs.append(bm.verts.new((at[0] + u, at[1], at[2] + v)))
        elif axis == "X":
            vs.append(bm.verts.new((at[0], at[1] + u, at[2] + v)))
        else:
            vs.append(bm.verts.new((at[0] + u, at[1] + v, at[2])))
    bm.faces.new(vs)
    ob = kit._obj(name, bm)
    wear.solid(ob, depth, 0.0)
    if bevel:
        kit.bevel(ob, bevel, 1)
        kit.apply_all(ob)
    return ob


def ball(name, r, at, scale=(1, 1, 1), segs=14, rings=8):
    ob = kit.sphere(name, r, at=at, scale=scale, segs=segs, rings=rings)
    kit.shade_auto(ob, 80)
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


def H(ob, role, glow=False, mat=None, alpha=0.0):
    return Piece(ob, "head", role, glow, mat, alpha)


# ---------------------------------------------------------------- the 19 kits
STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


@style("visor")
def s_visor():
    # a wraparound glowing band across the eyes, rimmed top and bottom, a strap round the back, ear pods
    lens = wrap("Lens", -1.75, 1.75, band(4.5, 4.8, 0.655), bulge=lambda a, z: 0.05 * math.cos(a) ** 2, thick=0.05)
    rim = join("Rim", [wrap("r1", -1.85, 1.85, band(4.8, 4.86, 0.67), bulge=lambda a, z: 0.05 * math.cos(a) ** 2,
                            thick=0.05),
                       wrap("r2", -1.85, 1.85, band(4.44, 4.5, 0.67), bulge=lambda a, z: 0.05 * math.cos(a) ** 2,
                            thick=0.05)])
    strap = wrap("Strap", 1.7, 2 * PI - 1.7, band(4.55, 4.75, 0.625), thick=0.03)
    pods = join("Pods", [kit.cyl("pl", 0.17, 0.15, 0.12, at=(-0.66, 0, 4.65), segs=16, axis="X"),
                         kit.cyl("pr", 0.17, 0.15, 0.12, at=(0.66, 0, 4.65), segs=16, axis="X")])
    return [H(lens, "a", True), H(rim, "s", mat="Metal"), H(strap, "dark"), H(pods, "s", mat="Metal")]


@style("helm")
def s_helm():
    # a rounded full helmet with a big smoked visor, a stripe over the crown and cheek vents
    win = lambda a, z: abs(a) < 1.0 and 4.28 < z < 4.92  # noqa: E731
    shell = wrap("Shell", -PI, PI, [(4.0, 0.7)] + dome(4.1, 4.95, 0.72, top=5.48), hole=win, thick=0.05)
    visor = wrap("Visor", -1.08, 1.08, [(4.24, 0.66), (4.4, 0.7), (4.6, 0.71), (4.8, 0.7), (4.96, 0.67)],
                 bulge=lambda a, z: 0.04 * math.cos(a), thick=0.03)
    stripe = wrap("Stripe", -0.16, 0.16, [(4.96, 0.745)] + [(z, r * 1.035) for z, r in dome(4.96, 4.96, 0.72,
                                                                                            top=5.48)[3:]],
                  na=4, thick=0.03)
    # the stripe runs back over the crown too
    stripe2 = wrap("Stripe2", PI - 0.16, PI + 0.16, [(4.2, 0.745), (4.95, 0.745)] +
                   [(z, r * 1.035) for z, r in dome(4.95, 4.95, 0.72, top=5.48)[3:]], na=4, thick=0.03)
    vents = []
    for s in (-1, 1):
        for k in range(3):
            vents.append(kit.box("v", 0.05, 0.22, 0.05, at=(s * 0.745, 0.08, 4.25 + k * 0.1)))
    return [H(shell, "p"), H(visor, "dark", mat="Glass"), H(join("Stripe", [stripe, stripe2]), "s"),
            H(join("Vents", vents), "a")]


@style("crest")
def s_crest():
    # an open-faced helmet with a tall swept crest fin, cheek guards and a brow chevron
    win = lambda a, z: abs(a) < 0.95 and z < 4.86  # noqa: E731
    shell = wrap("Shell", -PI, PI, [(4.05, 0.69)] + dome(4.2, 4.95, 0.7, top=5.44), hole=win, thick=0.05)
    fin = flat_shape("Fin", [(0.75, -0.05), (0.55, 0.42), (0.1, 0.78), (-0.5, 0.95), (-0.95, 0.7), (-0.75, 0.42),
                             (-0.3, 0.42), (0.2, 0.25)], 0.12, (0, 0, 5.12), axis="X")
    chev = wrap("Chevron", -1.0, 1.0, [(4.82, 0.72), (4.96, 0.73)], bulge=lambda a, z: 0.02 - 0.12 * abs(a) *
                (0.0 if z < 4.9 else 1.0), thick=0.05)
    # the chevron's point: lift the middle (a V pointing down over the nose)
    for v in chev.data.vertices:
        if v.co.y > 0:
            v.co.z -= 0.14 * max(0.0, 1 - abs(v.co.x) / 0.5)
    guards = []
    for s in (-1, 1):
        g = flat_shape("g", [(0.25, 0.25), (0.35, -0.25), (0.05, -0.52), (-0.25, -0.2), (-0.2, 0.25)], 0.06,
                       (s * 0.735, 0.15, 4.55), axis="X")
        guards.append(g)
    return [H(shell, "p"), H(fin, "a"), H(chev, "s", mat="Metal"), H(join("Guards", guards), "s", mat="Metal")]


@style("horns")
def s_horns():
    # an open-faced villain's helm: a V brow plate with a glowing gem, and two big curved horns
    win = lambda a, z: abs(a) < 0.95 and z < 4.8  # noqa: E731
    shell = wrap("Shell", -PI, PI, [(4.05, 0.69)] + dome(4.2, 4.9, 0.7, top=5.38), hole=win, thick=0.05)
    brow = wrap("Brow", -1.1, 1.1, [(4.74, 0.73), (4.94, 0.74)], thick=0.06)
    for v in brow.data.vertices:
        if v.co.y > 0:
            v.co.z -= 0.16 * max(0.0, 1 - abs(v.co.x) / 0.45)
    horns = []
    for s in (-1, 1):
        pts, radii = [], []
        for k in range(9):
            t = k / 8
            pts.append((s * (0.62 + 0.55 * t - 0.18 * t * t), 0.05 - 0.25 * t, 5.0 + 0.15 * t + 0.75 * t * t))
            radii.append(0.17 * (1 - t) + 0.012)
        horns.append(rod("h", pts, radii, segs=10))
    gem = ball("Gem", 0.09, (0, 0.76, 4.7), scale=(1, 0.5, 1.3), segs=10, rings=6)
    return [H(shell, "p"), H(brow, "dark", mat="Metal"), H(join("Horns", horns), "a"), H(gem, "glowRed", True)]


@style("antenna")
def s_antenna():
    # a retro space dome: a clear bubble over the head on a metal collar, with two antennae and glowing tips
    bubble = wrap("Bubble", -PI, PI, [(4.08, 0.74), (4.25, 0.8), (4.55, 0.84), (4.85, 0.83), (5.1, 0.76),
                                      (5.3, 0.62), (5.45, 0.4), (5.52, 0.0)], power=2.0, thick=0.0)
    collar = wrap("Collar", -PI, PI, band(3.96, 4.12, 0.8), power=2.0, thick=0.08)
    ring = wrap("Ring", -PI, PI, band(4.12, 4.17, 0.79), power=2.0, thick=0.05)
    rods, tips = [], []
    for s in (-1, 1):
        rods.append(rod("r", [(s * 0.45, 0, 5.34), (s * 0.62, 0.0, 5.7), (s * 0.7, 0, 5.92)], [0.035, 0.03, 0.025],
                        segs=6))
        tips.append(ball("t", 0.09, (s * 0.7, 0, 5.98)))
    return [H(bubble, "white", mat="Glass", alpha=0.6), H(collar, "p", mat="Metal"), H(ring, "a", True),
            H(join("Rods", rods), "dark"), H(join("Tips", tips), "a", True)]


@style("hood")
def s_hood():
    # a cloth hood with a pointed tip falling behind, its face opening rimmed in the trim
    def bulge(a, z):
        back = max(0.0, -math.cos(a))
        return 0.1 * back * max(0.0, (z - 4.3)) * 2

    win = lambda a, z: abs(a) < 0.85 and z < 5.0  # noqa: E731
    rows = [(3.95, 0.78), (4.1, 0.74), (4.4, 0.71), (4.7, 0.71), (5.0, 0.7), (5.18, 0.64), (5.32, 0.52),
            (5.42, 0.34), (5.46, 0.0)]
    hood = wrap("Hood", -PI, PI, rows, hole=win, bulge=bulge, thick=0.05, na=32)
    # the tip: pull the back of the crown out and down into a point
    for v in hood.data.vertices:
        if v.co.y < -0.2 and v.co.z > 4.7:
            t = (v.co.z - 4.7) / 0.76
            v.co.y -= 0.45 * t * t * (1 - abs(v.co.x) / 0.8)
            v.co.z -= 0.2 * t * t
    # the rim round the face opening
    pts = []
    n = 16
    for k in range(n + 1):
        u = -1 + 2 * k / n
        a = 0.85 * u
        z = 5.0 - 0.12 * (1 - u * u) if abs(u) < 0.999 else 4.1
        x, y = sp(a, 0.75)
        pts.append((x, y, 5.0 - 0.05 * (1 - u * u)))
    left = [(sp(-0.85, 0.75)[0], sp(-0.85, 0.75)[1], z) for z in (4.95, 4.6, 4.2, 3.98)]
    right = [(sp(0.85, 0.75)[0], sp(0.85, 0.75)[1], z) for z in (3.98, 4.2, 4.6, 4.95)]
    path = left[::-1] + pts + right
    rim = rod("Rim", path, [0.05] * len(path), segs=6)
    drawn = rod("Drawstring", [(0.3, 0.68, 4.0), (0.32, 0.72, 3.75)], [0.025, 0.02], segs=6)
    drawn2 = rod("d2", [(-0.3, 0.68, 4.0), (-0.32, 0.72, 3.72)], [0.025, 0.02], segs=6)
    return [H(hood, "s", mat="Fabric"), H(rim, "p", mat="Fabric"), H(join("Strings", [drawn, drawn2]), "white")]


@style("frame")
def s_frame():
    # a faceted robot helmet: a boxy shell, a wide glowing slit and side fins
    rows = [(4.0, 0.72), (4.3, 0.74), (4.9, 0.74), (5.2, 0.66), (5.38, 0.4), (5.42, 0.0)]
    shell = wrap("Shell", -PI, PI, rows, na=8, power=4.0, thick=0.06)
    kit.shade_auto(shell, 20)
    slit = wrap("Slit", -0.75, 0.75, band(4.62, 4.74, 0.765), na=6, power=4.0, thick=0.03)
    fins = []
    for s in (-1, 1):
        fins.append(flat_shape("f", [(0.3, -0.3), (0.3, 0.35), (-0.45, 0.62), (-0.3, -0.1)], 0.08,
                               (s * 0.8, -0.05, 4.65), axis="X"))
    vent = kit.box("Vent", 0.5, 0.06, 0.12, at=(0, 0.775, 4.32))
    kit.bevel(vent, 0.02, 1)
    return [H(shell, "s", mat="Metal"), H(slit, "a", True), H(join("Fins", fins, 20), "p"), H(vent, "dark")]


@style("crown")
def s_crown():
    # a sun crown: a band with rays fanning up and out, a glowing gem, and a dark eye mask
    bandm = wrap("Band", -PI, PI, band(4.98, 5.12, 0.655), thick=0.05)
    rays = []
    for k in range(11):
        a = -PI * 0.75 + 1.5 * PI * k / 10
        tall = 0.55 if k == 5 else (0.42 if k in (4, 6) else 0.32)
        x, y = sp(a, 0.67)
        d = Vector((x, y, 0)).normalized()
        base = Vector((x, y, 5.08))
        tip = base + d * 0.16 * tall + Vector((0, 0, tall))
        side = Vector((-d.y, d.x, 0)) * 0.11
        bm = bmesh.new()
        v = [bm.verts.new(base - side), bm.verts.new(base + side), bm.verts.new(tip)]
        bm.faces.new(v)
        ob = kit._obj("ray", bm)
        wear.solid(ob, 0.05, 0.0)
        rays.append(ob)
    gem = ball("Gem", 0.1, (0, 0.71, 5.08), scale=(1, 0.5, 1.25), segs=10, rings=6)
    mask = wrap("Mask", -1.15, 1.15, [(4.6, 0.625), (4.83, 0.625)], hole=eyes_hole(0.13, 0.07, z=4.71), thick=0.03)
    for v in mask.data.vertices:  # tapered wing tips
        if abs(v.co.x) > 0.45:
            v.co.z += (abs(v.co.x) - 0.45) * 0.3
    return [H(bandm, "a", mat="Metal"), H(join("Rays", rays, 20), "a", mat="Metal"), H(gem, "p", True),
            H(mask, "dark")]


@style("fullface")
def s_fullface():
    # a smooth face plate over the whole front: a glowing eye line under a V brow, cheek lines, a strap
    def bulge(a, z):
        return 0.04 * math.cos(a) ** 3 + 0.03 * math.exp(-((a / 0.2) ** 2)) * max(0.0, 1 - abs(z - 4.45) / 0.3)

    plate = wrap("Plate", -1.35, 1.35, [(4.06, 0.6), (4.15, 0.645), (4.5, 0.66), (4.9, 0.66), (5.12, 0.64),
                                        (5.2, 0.58)], bulge=bulge, thick=0.05, na=32)
    line = wrap("Eyes", -0.62, 0.62, band(4.66, 4.75, 0.71), bulge=lambda a, z: 0.04 * math.cos(a) ** 3, thick=0.02)
    for v in line.data.vertices:  # the eye line sweeps up at its ends
        v.co.z += 0.1 * max(0.0, abs(v.co.x) - 0.15)
    brow = wrap("Brow", -0.75, 0.75, band(4.82, 4.92, 0.712), bulge=lambda a, z: 0.04 * math.cos(a) ** 3,
                thick=0.03)
    for v in brow.data.vertices:
        if v.co.y > 0:
            v.co.z += 0.14 * min(1.0, abs(v.co.x) / 0.45) - 0.05
    cheeks = [wrap("c", a - 0.05, a + 0.05, [(4.25, 0.705), (4.52, 0.705)], na=1,
                   bulge=lambda a2, z: 0.04 * math.cos(a2) ** 3, thick=0.02) for a in (-0.62, 0.62)]
    strap = wrap("Strap", 1.3, 2 * PI - 1.3, band(4.6, 4.78, 0.62), thick=0.03)
    return [H(plate, "p"), H(line, "a", True), H(join("Trim", [brow] + cheeks), "s"), H(strap, "dark")]


@style("respirator")
def s_respirator():
    # a metal mouth guard with a forward snout, grille slats and twin side filters
    def bulge(a, z):
        return 0.16 * math.cos(a) ** 4 * max(0.0, 1 - abs(z - 4.3) / 0.3)

    guard = wrap("Guard", -1.2, 1.2, [(4.08, 0.6), (4.16, 0.64), (4.3, 0.65), (4.45, 0.64), (4.55, 0.61)],
                 bulge=bulge, thick=0.05)
    slats = [kit.box("sl", 0.36, 0.05, 0.035, at=(0, 0.815, 4.22 + k * 0.08)) for k in range(3)]
    cans = []
    for s in (-1, 1):
        c = kit.cyl("c", 0.13, 0.13, 0.26, at=(s * 0.52, 0.5, 4.27), segs=14, axis="Y")
        wear.turn(c, (0, 0, -s * 0.7), (s * 0.52, 0.5, 4.27))
        cans.append(c)
    caps = []
    for s in (-1, 1):
        c = kit.cyl("cap", 0.14, 0.14, 0.04, at=(s * 0.61, 0.62, 4.27), segs=14, axis="Y")
        wear.turn(c, (0, 0, -s * 0.7), (s * 0.61, 0.62, 4.27))
        caps.append(c)
    strap = wrap("Strap", 1.15, 2 * PI - 1.15, band(4.38, 4.5, 0.62), thick=0.03)
    return [H(guard, "s", mat="Metal"), H(join("Slats", slats, 20), "dark"),
            H(join("Filters", cans), "dark"), H(join("Caps", caps), "a"), H(strap, "dark")]


@style("gasmask")
def s_gasmask():
    # a rubber face mask with two big round lenses in rings and a front filter
    def bulge(a, z):
        return 0.1 * math.cos(a) ** 4 * max(0.0, 1 - abs(z - 4.3) / 0.35)

    face = wrap("Face", -1.4, 1.4, [(4.04, 0.58), (4.12, 0.64), (4.4, 0.66), (4.75, 0.66), (5.0, 0.64),
                                    (5.08, 0.6)], bulge=bulge, thick=0.05)
    lenses, rings = [], []
    for s in (-1, 1):
        x, y = sp(s * 0.38, 0.69)
        lenses.append(kit.cyl("l", 0.17, 0.17, 0.05, at=(x, y + 0.02, 4.72), segs=18, axis="Y"))
        rr = kit.torus("ring", 0.18, 0.04, at=(x, y + 0.04, 4.72), segs=20, csegs=6, axis="Y")
        rings.append(rr)
    filt = kit.cyl("Filter", 0.2, 0.17, 0.26, at=(0, 0.86, 4.26), segs=18, axis="Y")
    fcap = kit.cyl("fc", 0.21, 0.21, 0.04, at=(0, 1.0, 4.26), segs=18, axis="Y")
    straps = wrap("Straps", 1.35, 2 * PI - 1.35, band(4.55, 4.72, 0.62), thick=0.03)
    return [H(face, "dark", mat="Rubber"), H(join("Lenses", lenses), "a", mat="Glass"),
            H(join("Rings", rings), "s", mat="Metal"), H(join("Filter", [filt, fcap]), "s"), H(straps, "dark")]


@style("goalie")
def s_goalie():
    # a white sports face guard with eye holes, bold accent stripes, a brow bar and chin vents
    holes = eyes_hole(0.16, 0.1, z=4.71)
    mask = wrap("Mask", -1.3, 1.3, [(4.04, 0.58), (4.12, 0.645), (4.45, 0.665), (4.85, 0.665), (5.1, 0.64),
                                    (5.2, 0.58)], hole=holes, bulge=lambda a, z: 0.05 * math.cos(a) ** 2,
                na=34, thick=0.05)
    stripes = []
    for s in (-1, 1):
        stripes.append(wrap("st", s * 0.55 - 0.08, s * 0.55 + 0.08, [(4.2, 0.715), (4.55, 0.715)], na=2,
                            bulge=lambda a, z: 0.05 * math.cos(a) ** 2, thick=0.02))
    mid = wrap("mid", -0.07, 0.07, [(4.88, 0.72), (5.16, 0.69)], na=2, thick=0.02)
    brow = wrap("Brow", -0.75, 0.75, band(4.83, 4.9, 0.715), bulge=lambda a, z: 0.05 * math.cos(a) ** 2, thick=0.03)
    vents = []
    for k, (x, z) in enumerate(((-0.14, 4.25), (0.0, 4.2), (0.14, 4.25), (-0.07, 4.37), (0.07, 4.37))):
        vents.append(kit.cyl("v", 0.035, 0.035, 0.03, at=(x, 0.712, z), segs=8, axis="Y"))
    return [H(mask, "white"), H(join("Stripes", stripes + [mid]), "a"), H(brow, "p"), H(join("Vents", vents), "dark")]


@style("monovisor")
def s_monovisor():
    # a metal half helmet with one wide glowing visor across the eyes in a dark housing
    cap = wrap("Cap", -PI, PI, dome(4.78, 4.98, 0.68, top=5.4), thick=0.05)
    house = wrap("Housing", -PI, PI, band(4.52, 4.84, 0.665), bulge=lambda a, z: 0.06 * max(0.0, math.cos(a)) ** 2,
                 thick=0.05)
    vis = wrap("Visor", -1.0, 1.0, band(4.61, 4.75, 0.735), bulge=lambda a, z: 0.06 * max(0.0, math.cos(a)) ** 2,
               thick=0.02)
    discs = join("Discs", [kit.cyl("d", 0.16, 0.16, 0.08, at=(s * 0.7, 0, 4.68), segs=16, axis="X")
                           for s in (-1, 1)])
    return [H(cap, "p", mat="Metal"), H(house, "dark"), H(vis, "a", True), H(discs, "s")]


@style("welder")
def s_welder():
    # a tall flip-down shield with a dark window, a headband and pivot knobs
    shield = wrap("Shield", -1.15, 1.15, [(4.0, 0.74), (4.3, 0.77), (4.9, 0.77), (5.15, 0.74), (5.25, 0.66)],
                  power=3.2, thick=0.06)
    win = wrap("Window", -0.62, 0.62, band(4.62, 4.8, 0.805), power=3.2, thick=0.02)
    frame = wrap("Frame", -0.7, 0.7, band(4.57, 4.85, 0.795), power=3.2, thick=0.02)
    head = wrap("Band", -PI, PI, band(4.85, 4.97, 0.625), thick=0.04)
    crown = wrap("Crown", PI - 0.12, PI + 0.12, [(4.97, 0.625)] + [(z, r) for z, r in dome(4.97, 4.97, 0.625,
                                                                                         top=5.34)[3:]], na=2,
                 thick=0.04)
    knobs = join("Knobs", [kit.cyl("k", 0.11, 0.09, 0.12, at=(s * 0.82, 0.05, 4.9), segs=12, axis="X")
                           for s in (-1, 1)])
    return [H(shield, "s", mat="Metal"), H(win, "dark", mat="Glass"), H(frame, "a"),
            H(join("Band", [head, crown]), "dark"), H(knobs, "a", mat="Metal")]


@style("techmask")
def s_techmask():
    # an angular lower-face mask with glowing vent lines and ear pieces
    guard = wrap("Guard", -1.25, 1.25, [(4.06, 0.58), (4.14, 0.64), (4.4, 0.665), (4.55, 0.655)], power=3.0,
                 na=12, bulge=lambda a, z: 0.08 * max(0.0, math.cos(a)) ** 6, thick=0.05)
    kit.shade_auto(guard, 25)
    lines = [wrap("ln", a - 0.05, a + 0.05, [(4.18, 0.71), (4.46, 0.71)], na=1, power=3.0,
                  bulge=lambda a2, z: 0.08 * max(0.0, math.cos(a2)) ** 6, thick=0.02) for a in (-0.42, 0.0, 0.42)]
    ears = join("Ears", [kit.cyl("e", 0.2, 0.18, 0.1, at=(s * 0.66, 0, 4.62), segs=6, axis="X") for s in (-1, 1)],
                20)
    rings = join("Rings", [kit.torus("r", 0.12, 0.025, at=(s * 0.72, 0, 4.62), segs=12, csegs=4, axis="X")
                           for s in (-1, 1)])
    return [H(guard, "dark", mat="Metal"), H(join("Lines", lines), "a", True), H(ears, "s", mat="Metal"),
            H(rings, "a", True)]


@style("oni")
def s_oni():
    # a folk ogre mask: a bold face with eye holes, gold brows, a toothy grin and two white horns
    def bulge(a, z):
        nose = 0.08 * math.exp(-((a / 0.25) ** 2) - ((z - 4.5) / 0.12) ** 2)
        brow = 0.06 * math.exp(-((z - 4.85) / 0.08) ** 2) * math.cos(a) ** 2
        return nose + brow + 0.04 * math.cos(a) ** 2

    face = wrap("Face", -1.3, 1.3, [(4.04, 0.58), (4.12, 0.645), (4.45, 0.665), (4.85, 0.665), (5.1, 0.64),
                                    (5.2, 0.58)], hole=eyes_hole(0.15, 0.08, z=4.71), bulge=bulge, na=34, thick=0.05)
    brows = []
    for s in (-1, 1):
        b = flat_shape("b", [(-0.2, -0.04), (0.18, 0.1), (0.2, 0.16), (-0.2, 0.04)], 0.06,
                       (s * 0.24, 0.72, 4.86), axis="Y")
        if s > 0:
            b.data.transform(Matrix.Translation((0.48, 0, 0)) @ Matrix.Scale(-1, 4, (1, 0, 0)))
            wear.fix_normals(b)
        brows.append(b)
    mouth = wrap("Mouth", -0.5, 0.5, band(4.2, 4.34, 0.705), bulge=lambda a, z: 0.04 * math.cos(a) ** 2, thick=0.02)
    teeth = []
    for k in range(5):
        x = -0.24 + k * 0.12
        teeth.append(flat_shape("t", [(-0.045, 0.0), (0.045, 0.0), (0.0, -0.09)], 0.03, (x, 0.75, 4.34), axis="Y"))
    for s in (-1, 1):
        teeth.append(flat_shape("tusk", [(-0.05, 0.0), (0.05, 0.0), (0.0, 0.16)], 0.04, (s * 0.3, 0.75, 4.2),
                                axis="Y"))
    horns = []
    for s in (-1, 1):
        pts = [(s * (0.36 + 0.16 * t + 0.08 * t * t), 0.22 - 0.1 * t, 5.08 + 0.62 * t) for t in
               (0, 0.2, 0.4, 0.6, 0.8, 1.0)]
        horns.append(rod("h", pts, [0.15, 0.13, 0.105, 0.075, 0.045, 0.01], segs=10))
    return [H(face, "p"), H(join("Brows", brows, 20), "gold"), H(mouth, "dark"),
            H(join("Teeth", teeth, 20), "white"), H(join("Horns", horns), "white")]


@style("fox")
def s_fox():
    # a folk fox mask: a white face with a pointed snout, tall ears and swept accent markings
    def bulge(a, z):
        return 0.3 * math.exp(-((a / 0.32) ** 2) - ((z - 4.42) / 0.2) ** 2) + 0.03 * math.cos(a) ** 2

    face = wrap("Face", -1.3, 1.3, [(4.12, 0.6), (4.2, 0.65), (4.42, 0.665), (4.85, 0.665), (5.1, 0.64),
                                    (5.2, 0.58)], hole=eyes_hole(0.14, 0.07, z=4.71), bulge=bulge, na=34, thick=0.05)
    nose = ball("Nose", 0.07, (0, 0.98, 4.44), scale=(1.2, 0.8, 0.8))
    ears, inner = [], []
    for s in (-1, 1):
        ears.append(flat_shape("e", [(-0.25, 0.0), (0.25, 0.0), (0.06, 0.66)], 0.1, (s * 0.36, 0.1, 5.05),
                               axis="Y"))
        inner.append(flat_shape("i", [(-0.14, 0.05), (0.14, 0.05), (0.045, 0.48)], 0.04, (s * 0.36, 0.17, 5.05),
                                axis="Y"))
    for e in ears + inner:
        x = e.data.vertices[0].co.x
        wear.turn(e, (0, -0.3 if x < 0 else 0.3, 0), (0.36 if x > 0 else -0.36, 0.1, 5.05))
    marks = []
    for s in (-1, 1):
        # a swept flick over each eye and a cheek stripe
        marks.append(wrap("m1", s * 0.18 if s > 0 else -0.62, 0.62 if s > 0 else -0.18,
                          [(4.82, 0.71), (4.86, 0.712)], na=6, bulge=lambda a, z: 0.03 * math.cos(a) ** 2,
                          thick=0.015))
        marks.append(wrap("m2", s * 0.55 - 0.06, s * 0.55 + 0.06, [(4.3, 0.705), (4.55, 0.705)], na=1,
                          bulge=lambda a, z: 0.03 * math.cos(a) ** 2, thick=0.015))
    for m in marks:
        for v in m.data.vertices:
            v.co.z += 0.12 * (abs(v.co.x) - 0.2) if v.co.z > 4.7 else 0.0
    return [H(face, "white"), H(nose, "dark"), H(join("Ears", ears, 20), "white"),
            H(join("Inner", inner, 20), "a"), H(join("Marks", marks, 20), "a")]


@style("crystal")
def s_crystal():
    # a faceted crystal half mask over the eyes and brow, crowned with glowing crystal shards
    mask = wrap("Mask", -1.2, 1.2, [(4.52, 0.64), (4.62, 0.68), (4.84, 0.69), (5.0, 0.66)], na=8, power=2.6,
                hole=eyes_hole(0.14, 0.07, z=4.71), bulge=lambda a, z: 0.05 * math.cos(a) ** 2, thick=0.06)
    kit.shade_auto(mask, 15)
    shards = []
    for x, h, lean, r in ((0.0, 0.62, 0.0, 0.12), (-0.24, 0.44, -0.35, 0.09), (0.24, 0.44, 0.35, 0.09),
                          (-0.44, 0.28, -0.6, 0.07), (0.44, 0.28, 0.6, 0.07)):
        c = kit.cyl("s", r, 0.0, h, at=(x, 0.42, 4.98 + h / 2), segs=5)
        wear.turn(c, (-0.25, lean, 0), (x, 0.42, 4.98))
        shards.append(c)
    sh = join("Shards", shards, 10)
    return [H(mask, "a", mat="Glass", alpha=0.15), H(sh, "a", True)]


@style("nightMask")
def s_night():
    # a gala mask: a dark domino with eye holes, gold edging and gold swirl wings, a glowing brow gem
    mask = wrap("Mask", -1.2, 1.2, [(4.58, 0.625), (4.86, 0.625)], hole=eyes_hole(0.14, 0.08, z=4.71), thick=0.04)
    for v in mask.data.vertices:
        if abs(v.co.x) > 0.4:
            v.co.z += (abs(v.co.x) - 0.4) * 0.45
    edge = []
    for zz in (4.58, 4.86):
        pts = []
        for k in range(17):
            a = -1.2 + 2.4 * k / 16
            x, y = sp(a, 0.65)
            pts.append((x, y, zz + max(0.0, abs(x) - 0.4) * 0.45))
        edge.append(rod("e", pts, [0.025] * len(pts), segs=5))
    wings = []
    for s in (-1, 1):
        # a gold curl sweeping up from the mask's outer corner into a spiral above the temple
        pts = []
        n = 16
        for k in range(n):
            t = k / (n - 1)
            ang = 4.4 * t
            rr = 0.3 * (1 - 0.75 * t)
            pts.append((s * (0.66 + 0.04 * t), 0.3 - 0.22 * t - rr * math.sin(ang) * 0.6,
                        5.02 + 0.22 * t + rr * (1 - math.cos(ang)) * 0.8))
        wings.append(rod("w", pts, [0.055 * (1 - 0.6 * k / (n - 1)) for k in range(n)], segs=6))
    gem = ball("Gem", 0.07, (0, 0.66, 4.9), scale=(1, 0.5, 1.2), segs=10, rings=6)
    return [H(mask, "dark"), H(join("Edge", edge), "gold", mat="Metal"), H(join("Wings", wings), "gold", mat="Metal"),
            H(gem, "a", True)]


# ---------------------------------------------------------------- build, export, preview
HEADER = ["heads.py",
          "The creator's head pieces as meshes (ReplicatedStorage.Art.Heads once nate imports art/export/Heads.fbx;",
          "LookKit wears them then, the part-built pieces until then). Keyed by the Masks tab's kit: each piece's",
          "mesh name, the body part it is welded to (at), its colour role (the slot's p main, s trim, a accent, or",
          "dark, white, gold, ice, glowRed), glow (Neon), material and transparency, and its box against the Head's",
          "centre in Roblox axes (x right, y up, z back), in studs on the standard blocky rig (scaled with the head)."]


# the kits whose meshes cover the hair (LookKit leaves the hair off under them; HeadArt hair = false)
COVERS_HAIR = {"helm", "crest", "horns", "antenna", "hood", "frame", "monovisor"}


def preview(built):
    def dress(name, at, yaw, pal):
        # the head alone (a torso would cover the row above in the grid)
        wear.body(at, yaw, parts={"Head"}, show_hair=name not in COVERS_HAIR)
        wear.place(built[name], at, yaw, pal)
    wear.grid_preview(built, os.path.join(kit.ROOT, "preview", "heads.png"), dress, cols=5, cell=2.9, px=300,
                      focus=4.85, yaw_front=180 - 30, yaw_back=25)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Head_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    for name in rows:
        rows[name]["flags"] = {"hair": name not in COVERS_HAIR}
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Heads.fbx"))
        wear.write_fit("HeadArt", HEADER, rows)
    preview(built)
