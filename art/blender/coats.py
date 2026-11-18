# coats.py: the hero creator's coats and scarves as meshes (creator art round 2, 2026-11-18), in place of the
# boxes LookKit welds to the torso for the Capes tab's anime pieces ("coat:<style>", "scarf:<style>"). A coat is
# a shell over the blocky torso, open down the front in a V, with sleeves on the upper and lower arms and a skirt
# from the waist that flares as it falls (a long coat to the shins, split behind); a scarf is a lumpy wrap round
# the neck with ribbon tails that stream behind. Each piece is welded to its own body part (the torso, the waist,
# each arm part), so the sleeves follow the arms. Bright comic shapes; all original.
# Output: art/export/Coats.fbx (nate imports it as ReplicatedStorage.Art.Coats), src/config/CoatArt.luau
# (LookKit's fit) and art/preview/coats.png (each kit from the front three-quarter and from behind).
# Run: python art/blender/coats.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece  # noqa: E402
import bpy  # noqa: E402, F401
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2600  # triangles a coat (sleeves included)
PI = math.pi

kit.reset()


def sp(a, rx, ry, power):
    s, c = math.sin(a), math.cos(a)
    return (rx * math.copysign(abs(s) ** (2 / power), s), ry * math.copysign(abs(c) ** (2 / power), c))


def shell(name, rows, power=6.0, na=32, hole=None, cx=0.0, thick=0.0, wave=None):
    """A surface round the body: rows [(z, rx, ry, cy)] bottom to top, angle 0 the front (+y). hole(a, z) leaves
    a face out (the coat's open front); wave(a, z) -> extra radius (folds)."""
    bm = bmesh.new()
    grid = []
    for z, rx, ry, cy in rows:
        row = []
        for i in range(na):
            a = -PI + 2 * PI * i / na
            w = wave(a, z) if wave else 0.0
            x, y = sp(a, rx + w, ry + w, power)
            row.append(bm.verts.new((cx + x, cy + y, z)))
        grid.append(row)
    for j in range(len(rows) - 1):
        for i in range(na):
            i2 = (i + 1) % na
            am = -PI + 2 * PI * (i + 0.5) / na
            zm = (rows[j][0] + rows[j + 1][0]) / 2
            if hole and hole(am, zm):
                continue
            q = [grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]]
            if len(set(q)) == 4:
                bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = kit._obj(name, bm)
    if thick:
        wear.solid(ob, thick, 0.0)
    else:
        outward(ob, cx)
    kit.shade_auto(ob, 50)
    return ob


def outward(ob, cx=0.0):
    """Point a one-sided shell's faces away from the body's axis (Roblox draws one side)."""
    me = ob.data
    s = 0.0
    for p in me.polygons:
        c = p.center
        s += p.normal.dot(Vector((c.x - cx, c.y, 0)))
    if s < 0:
        me.flip_normals()
    return ob


def ribbon(name, pts, widths, up=(0, 0, 1), thick=0.035):
    """A flat strip through pts (a scarf tail), widths across it, lying across `up` x the direction."""
    bm = bmesh.new()
    rows = []
    for k, p in enumerate(pts):
        p = Vector(p)
        d = (Vector(pts[min(k + 1, len(pts) - 1)]) - Vector(pts[max(k - 1, 0)])).normalized()
        side = Vector(up) - d * d.dot(Vector(up))  # across the strip: `up` with the run taken out
        side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        w = widths[k] / 2
        rows.append((bm.verts.new(p - side * w), bm.verts.new(p + side * w)))
    for k in range(len(rows) - 1):
        a, b = rows[k], rows[k + 1]
        bm.faces.new([a[0], a[1], b[1], b[0]])
    ob = kit._obj(name, bm)
    wear.solid(ob, thick, 0.0)
    kit.shade_auto(ob, 60)
    return ob


def T(ob, role, glow=False, mat=None, alpha=0.0, at="torso"):
    wear.bake(ob)
    return Piece(ob, at, role, glow, mat, alpha)


def vneck(depth=1.0, gap=0.12, top=4.02, bottom=2.0):
    """The coat's open front: a V from the collar down to `depth` of the way, then a gap."""
    def f(a, z):
        t = (top - z) / (top - bottom)
        w = gap + 0.5 * max(0.0, 1 - t / depth) if t < depth else gap
        return abs(a) < w
    return f


def torso_shell(name="Body", hole=None, power=8.0, lift=0.0):
    rows = [(2.0, 1.07, 0.57, 0.0), (2.4, 1.07, 0.57, 0.0), (3.2, 1.08, 0.58, 0.0), (3.85, 1.08, 0.58, 0.0),
            (4.02 + lift, 1.0, 0.55, 0.0), (4.1 + lift, 0.62, 0.42, 0.0)]
    return shell(name, rows, power=power, hole=hole, na=36)


def sleeves(name, z0=3.12, z1=4.02, r=0.57, lower=True, cuff=None):
    """Upper (and lower) sleeves on both arms: [Piece]."""
    out = []
    up = shell(name + "Up", [(z0, r, r, 0.0), (z1 - 0.06, r, r, 0.0), (z1, r - 0.04, r - 0.04, 0.0),
                             (z1 + 0.04, r - 0.2, r - 0.2, 0.0)], power=7.0, na=16, cx=-1.5)
    out += wear.pair(up, "luarm", "p", short=name + "Up")
    if lower:
        lo = shell(name + "Lo", [(2.4, r + 0.02, r + 0.02, 0.0), (3.16, r, r, 0.0)], power=7.0, na=16, cx=-1.5)
        out += wear.pair(lo, "llarm", "p", short=name + "Lo")
        if cuff:
            c = shell(name + "Cuff", [(2.38, r + 0.05, r + 0.05, 0.0), (2.56, r + 0.05, r + 0.05, 0.0)], power=7.0,
                      na=16, cx=-1.5)
            out += wear.pair(c, "llarm", cuff, short=name + "Cuff")
    return out


def collar(name, h=0.4, flare=0.18, open_front=0.5, z=4.02):
    rows = [(z, 0.66, 0.48, -0.02), (z + h * 0.5, 0.7 + flare * 0.5, 0.52 + flare * 0.5, -0.04),
            (z + h, 0.74 + flare, 0.56 + flare, -0.06)]
    return shell(name, rows, power=3.0, na=24, hole=lambda a, zz: abs(a) < open_front, thick=0.05)


def lapels(name, z0=3.1, z1=4.0):
    out = []
    for s in (-1, 1):
        bm = bmesh.new()
        pts = [(s * 0.14, 0.6, z0), (s * 0.5, 0.6, z1 - 0.1), (s * 0.62, 0.6, z1), (s * 0.4, 0.62, z1 - 0.25)]
        vs = [bm.verts.new(p) for p in pts]
        bm.faces.new(vs)
        ob = kit._obj("l", bm)
        wear.solid(ob, 0.04, 0.0)
        out.append(ob)
    return join(name, out, 30)


def join(name, obs, angle=50):
    for o in obs:
        kit.apply_all(o)
        wear.bake(o)
    ob = kit.join(name, obs, shade=False)
    kit.shade_auto(ob, angle)
    return ob


def skirt(name, hem, flare=0.2, back_slit=False, front=0.28, power=6.0, jag=False):
    """From the waist down to z = hem, open at the front (and split behind)."""
    zs = [2.0 - (2.0 - hem) * k / 6 for k in range(7)]
    rows = [(2.42, 1.08, 0.58, 0.0)] + [(z, 1.08 + flare * (2.0 - z) / (2.0 - hem), 0.58 + flare * 1.3 *
                                         (2.0 - z) / (2.0 - hem), 0.0) for z in zs]

    def hole(a, z):
        if abs(a) < front * (1 + 0.6 * (2.0 - z)):
            return z < 2.3
        if back_slit and abs(abs(a) - PI) < 0.1 and z < (2.0 + hem) / 2:
            return True
        return False

    ob = shell(name, rows, power=power, na=36, hole=hole,
               wave=lambda a, z: 0.04 * max(0.0, 2.0 - z) * math.sin(a * 5))
    if jag:
        for v in ob.data.vertices:
            if v.co.z < hem + 0.01:
                a = math.atan2(v.co.x, v.co.y)
                v.co.z += 0.25 * abs(math.sin(a * 4.5))
    return ob


STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


# ---------------------------------------------------------------- the 4 coats
@style("coat:short")
def s_short():
    body = torso_shell(hole=vneck(0.45))
    sk = skirt("Skirt", 1.55, flare=0.1, front=0.16)
    pockets = [kit.box("pk", 0.42, 0.05, 0.3, at=(s * 0.55, 0.62, 2.3)) for s in (-1, 1)]
    return [T(body, "p"), T(sk, "p", at="waist"), T(lapels("Lapels", 3.4), "s"),
            T(collar("Collar", h=0.22, flare=0.06, open_front=0.6), "s"), T(join("Pockets", pockets, 30), "s",
                                                                            at="waist")] + \
        sleeves("Sleeve", cuff="s")


@style("coat:long")
def s_long():
    body = torso_shell(hole=vneck(0.55))
    sk = skirt("Skirt", 0.45, flare=0.3, back_slit=True, front=0.2)
    belt = shell("Belt", [(2.32, 1.1, 0.6, 0.0), (2.5, 1.1, 0.6, 0.0)], power=8.0, na=36,
                 hole=lambda a, z: abs(a) < 0.12)
    return [T(body, "p"), T(sk, "p", at="waist"), T(lapels("Lapels", 3.2), "s"),
            T(collar("Collar", h=0.34, flare=0.12, open_front=0.55), "s"), T(belt, "s", at="waist")] + \
        sleeves("Sleeve", cuff="s")


@style("coat:shoulder")
def s_shoulder():
    # a captain's coat worn over the shoulders: empty sleeves hang behind, gold epaulettes, a high collar
    cape = shell("Coat", [(1.05, 2.2, 0.98, -0.2), (1.6, 2.18, 0.9, -0.14), (2.4, 2.15, 0.78, -0.08),
                          (3.4, 2.13, 0.7, 0.0), (3.98, 2.12, 0.66, 0.0), (4.1, 2.0, 0.6, 0.0),
                          (4.16, 1.3, 0.5, 0.0), (4.2, 0.64, 0.44, 0.0)], power=9.0, na=40,
                 hole=lambda a, z: abs(a) < (0.3 if z < 3.98 else 0.25))
    eps = []
    for s in (-1, 1):
        e = kit.box("e", 0.8, 0.72, 0.1, at=(s * 1.5, 0.0, 4.17))
        kit.bevel(e, 0.04, 2)
        eps.append(e)
        for k in range(5):
            eps.append(kit.cyl("f", 0.03, 0.03, 0.24, at=(s * 1.92, -0.26 + k * 0.13, 4.02), segs=6))
    buttons = [kit.sphere("b", 0.07, at=(s * 0.62, 0.69, z), segs=8, rings=5) for s in (-1, 1)
               for z in (2.4, 2.9, 3.4)]
    return [T(cape, "p"), T(join("Epaulettes", eps, 30), "a", mat="Metal"),
            T(collar("Collar", h=0.42, flare=0.2, open_front=0.65, z=4.08), "s"),
            T(join("Buttons", buttons, 60), "gold", mat="Metal")]


@style("coat:shadow")
def s_shadow():
    body = torso_shell(hole=vneck(0.7, gap=0.1))
    sk = skirt("Skirt", 0.3, flare=0.38, back_slit=True, front=0.22, jag=True)
    seams = []
    for s in (-1, 1):
        seams.append(kit.box("s", 0.05, 0.04, 1.4, at=(s * 0.82, 0.6, 2.9)))
        seams.append(kit.box("s2", 0.05, 0.04, 1.2, at=(s * 0.82, -0.6, 3.0)))
    return [T(body, "dark"), T(sk, "dark", at="waist"), T(collar("Collar", h=0.55, flare=0.24, open_front=0.5), "a"),
            T(join("Seams", seams, 30), "a", True)] + \
        [Piece(p.ob, p.at, "dark") for p in sleeves("Sleeve")]


# ---------------------------------------------------------------- the 4 scarves
def wrap(name="Wrap", z=4.08, r=0.6, tube=0.16, lumpy=0.03):
    ob = kit.torus(name, r, tube, at=(0, -0.04, z), segs=24, csegs=8)
    for v in ob.data.vertices:
        a = math.atan2(v.co.x, v.co.y + 0.04)
        v.co.y = -0.04 + (v.co.y + 0.04) * 0.78
        v.co.z += lumpy * math.sin(a * 3) + 0.04 * math.cos(a)
    kit.shade_auto(ob, 70)
    return ob


def tail(name, x, length, sway=0.2, lift=0.0, width=0.34, drop=1.0):
    """A ribbon tail from the back of the neck, streaming behind and falling."""
    pts, widths = [], []
    n = 9
    for k in range(n):
        t = k / (n - 1)
        pts.append((x + sway * math.sin(t * 2.0), -0.62 - length * 0.3 * t ** 1.3, 3.98 - drop * length * 0.7 * t +
                    lift * t * t))
        widths.append(width * (1 - 0.35 * t))
    return ribbon(name, pts, widths, up=(1, 0, 0))


@style("scarf:one")
def s_one():
    return [T(wrap(), "a", mat="Fabric"), T(tail("Tail", 0.3, 2.0, 0.15), "a", mat="Fabric")]


@style("scarf:two")
def s_two():
    tails = join("Tails", [tail("t1", 0.32, 2.2, 0.3, width=0.3), tail("t2", -0.28, 1.8, -0.3, width=0.26)], 60)
    return [T(wrap(), "a", mat="Fabric"), T(tails, "a", mat="Fabric")]


@style("scarf:long")
def s_long_scarf():
    t = tail("Tail", 0.25, 3.4, 1.0, lift=0.5, width=0.4, drop=0.55)
    return [T(wrap(tube=0.19, lumpy=0.05), "a", mat="Fabric"), T(t, "a", mat="Fabric")]


@style("scarf:spirit")
def s_spirit():
    t = join("Tails", [tail("t1", 0.25, 3.0, 0.9, lift=0.6, width=0.34, drop=0.55),
                       tail("t2", -0.25, 2.5, -0.8, lift=0.4, width=0.24, drop=0.6)], 60)
    return [T(wrap(tube=0.15), "a", True, alpha=0.2), T(t, "a", True, alpha=0.35)]


# ---------------------------------------------------------------- build, export, preview
HEADER = ["coats.py",
          "The creator's coats and scarves as meshes (ReplicatedStorage.Art.Coats once nate imports art/export/Coats.fbx;",
          "LookKit wears them then, the part-built ones until then). Keyed by the Capes tab's coat and scarf kits: each",
          "piece's mesh name, the body part it is welded to (at: torso, waist, the arm parts), its colour role (the",
          "slot's p main, s trim, a accent, or dark, white, gold, ice, glowRed), glow (Neon), material and",
          "transparency, and its box against that part's centre in Roblox axes (x right, y up, z back), in studs on",
          "the standard blocky rig (scaled with the part)."]


def preview(built):
    def dress(name, at, yaw, pal):
        wear.body(at, yaw, suit=(150, 156, 170))
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", "coats.png" if ONLY is None else "coats_test.png")
    wear.grid_preview(built, out, dress, cols=4, cell=6.2, px=420,
                      focus=2.9, yaw_front=180 - 35, yaw_back=30, samples=40)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Coat_" + name.replace(":", "_"), fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Coats.fbx"))
        wear.write_fit("CoatArt", HEADER, rows)
    preview(built)
