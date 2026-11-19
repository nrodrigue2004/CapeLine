# capes.py: the hero creator's capes as meshes (overnight queue item 12, 2026-11-18), in place of the flat boxes
# LookKit welds to the back (Config.Creator tabs.back "cape:<style>"). Each cape is cloth that hangs from the
# shoulders, flares as it falls and drifts off the legs, with soft folds; a thin yoke over each shoulder ends in
# a clasp at the front. Two-tone like the old box capes' slots: the outside in the slot's main colour, the
# lining in its trim, clasps and trims in its accent. All original shapes (no famous hero's cape cut or logo).
# Conventions (kit.py): Blender +Y is the hero's front (Roblox -Z), Z up; the blocky R15 UpperTorso is the box
# x -1..1, y -0.5..0.5, z 2.4..4.0. Every piece is its own mesh, named Cape_<style>_<piece>, one colour each (the
# game sets MeshPart.Color from the piece's role); the lining faces the body (Roblox draws one side of a face).
# Output: art/export/Capes.fbx (nate imports it as ReplicatedStorage.Art.Capes), src/config/CapeArt.luau (each
# style's pieces: role, glow and box against the UpperTorso in Roblox axes, studs on the standard rig) and
# art/preview/capes.png (every style from behind, and three from the side).
# Run: python art/blender/capes.py [--quick]   (with the `bpy` module, Blender 5.0; --quick: no export)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

QUICK = "--quick" in sys.argv
BUDGET = 1200  # triangles a cape (up to 30 heroes on a server wear one)
TORSO_C = Vector((0, 0, 3.2))  # the UpperTorso's centre
TOP = 4.03  # the cape's top edge, just over the shoulders
BACK = -0.53  # the torso's back face, plus a hair

kit.reset()


def sheet(name, length, w_top=0.95, w_bot=1.3, drift=0.38, folds=0.05, nfold=3, cols=12, rows=10, u0=-1.0,
          u1=1.0, hem=None, inner=False):
    """The cape's cloth: a grid from the shoulders (v 0) to the hem (v 1); u across, -1 (left) to 1 (right).
    hem(u) -> 0..1 shortens a column (a jagged or scalloped hem). inner: the lining (faces the body, 0.012 in)."""
    bm = bmesh.new()
    grid = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            u = u0 + (u1 - u0) * i / cols
            v = j / rows
            if hem:
                v *= hem(u)
            half = w_top + (w_bot - w_top) * v ** 0.8
            x = half * u
            back = drift * v ** 1.5
            fold = folds * (0.3 + v) * math.sin((u + 1) * math.pi * nfold)
            y = BACK - back - fold - 0.06 * (1 - u * u) * v  # a slight round to the back
            z = TOP - length * v
            if inner:
                y += 0.012
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            q = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            bm.faces.new(q if inner else list(reversed(q)))
    ob = kit._obj(name, bm)
    return ob


def outward(ob, want_back=True):
    """Make sure a sheet's faces point away from the body (outside) or toward it (lining)."""
    me = ob.data
    me.calc_loop_triangles()
    s = 0.0
    for p in me.polygons:
        s += p.normal.y
    if (s > 0) == want_back:
        me.flip_normals()
    return ob


def soft(ob):
    """Smooth shading across the folds (cloth, not pleated card)."""
    kit.shade_auto(ob, 70)
    return ob


def two_tone(style, length, **kw):
    out = soft(outward(sheet("Cape_%s_Outer" % style, length, **kw), True))
    lin = soft(outward(sheet("Cape_%s_Lining" % style, length, inner=True, **kw), False))
    return [(out, "p"), (lin, "s")]


def yoke(style, role="p"):
    """The strip over each shoulder from the cape's top edge, over the shoulder top, to the clasp at the front."""
    prof = [(BACK - 0.01, TOP - 0.02, 0.36, 0.96), (-0.3, TOP + 0.03, 0.4, 0.95), (0.3, TOP + 0.03, 0.46, 0.92),
            (0.545, TOP - 0.06, 0.5, 0.9), (0.55, TOP - 0.24, 0.56, 0.86)]
    pieces = []
    for s in (-1, 1):
        bm = bmesh.new()
        rows = [[bm.verts.new((s * x, y, z)) for x in (xa, xb)] for y, z, xa, xb in prof]
        for k in range(len(rows) - 1):
            bm.faces.new([rows[k][0], rows[k][1], rows[k + 1][1], rows[k + 1][0]])
        ob = kit._obj("y", bm)
        m = ob.modifiers.new("S", "SOLIDIFY")
        m.thickness = 0.04
        m.offset = 1.0
        kit.apply_all(ob)
        pieces.append(ob)
    me = kit.join("Cape_%s_Yoke" % style, pieces)
    outward_any(me)
    return (me, role)


def outward_any(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def clasps(style, role="a", shape="disc"):
    subs = []
    for s in (-1, 1):
        if shape == "star":
            bm = bmesh.new()
            c = Vector((s * 0.72, 0.56, TOP - 0.2))
            ring = []
            for k in range(10):
                r = 0.16 if k % 2 == 0 else 0.07
                a = math.radians(90 + k * 36)
                ring.append(bm.verts.new((c.x + r * math.cos(a), c.y, c.z + r * math.sin(a))))
            back = [bm.verts.new((v.co.x, v.co.y - 0.04, v.co.z)) for v in ring]
            bm.faces.new(ring)
            bm.faces.new(list(reversed(back)))
            for k in range(10):
                bm.faces.new([ring[k], back[k], back[(k + 1) % 10], ring[(k + 1) % 10]])
            ob = kit._obj("c", bm)
        else:
            ob = kit.cyl("c", 0.13, 0.11, 0.06, at=(s * 0.72, 0.56, TOP - 0.2), segs=14, axis="Y")
        subs.append(ob)
    j = kit.join("Cape_%s_Clasps" % style, subs)
    outward_any(j)
    return (j, role)


def collar(style, role="s"):
    """A tall stiff collar standing up behind the head, flaring out."""
    bm = bmesh.new()
    cols, rows = 10, 3
    grid = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            a = math.radians(200 + 140 * i / cols)
            v = j / rows
            r = 0.62 + 0.34 * v
            row.append(bm.verts.new((r * math.cos(a) * 1.05, r * math.sin(a) * 0.9 - 0.05, TOP - 0.02 + 0.95 * v)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
    ob = kit._obj("Cape_%s_Collar" % style, bm)
    m = ob.modifiers.new("S", "SOLIDIFY")
    m.thickness = 0.05
    kit.apply_all(ob)
    outward_any(ob)
    return (ob, role)


def hem_band(style, length, role, glow=False, at=0.9, width=0.08, **kw):
    """A band across the cape near its hem (a glow line or a gold trim), just outside the cloth."""
    kw = dict(kw)
    w_top, w_bot, drift = kw.get("w_top", 0.95), kw.get("w_bot", 1.3), kw.get("drift", 0.38)
    folds, nfold = kw.get("folds", 0.05), kw.get("nfold", 3)
    bm = bmesh.new()
    cols = 16
    rows = [at - width / length / 2, at + width / length / 2]
    grid = []
    for v in rows:
        row = []
        for i in range(cols + 1):
            u = -1 + 2 * i / cols
            half = w_top + (w_bot - w_top) * v ** 0.8
            back = drift * v ** 1.5
            fold = folds * (0.3 + v) * math.sin((u + 1) * math.pi * nfold)
            y = BACK - back - fold - 0.06 * (1 - u * u) * v - 0.015
            row.append(bm.verts.new((half * u * 1.002, y, TOP - length * v)))
        grid.append(row)
    for i in range(cols):
        bm.faces.new([grid[1][i], grid[1][i + 1], grid[0][i + 1], grid[0][i]])
    ob = outward(kit._obj("Cape_%s_Band" % style, bm), True)
    return (ob, role, glow)


def sparkles(style, pts, role, size=0.11, name="Stars"):
    """Little four-point stars on the cape's outside (glow pieces)."""
    bm = bmesh.new()
    for x, y, z, k in pts:
        c = Vector((x, y - 0.02, z))
        r = size * k
        ring = []
        for i in range(8):
            rr = r if i % 2 == 0 else r * 0.35
            a = math.radians(90 + i * 45)
            ring.append(bm.verts.new((c.x + rr * math.cos(a), c.y, c.z + rr * math.sin(a))))
        f = bm.faces.new(ring)
        f.normal_update()
    ob = kit._obj("Cape_%s_%s" % (style, name), bm)
    return outward(ob, True)


def on_sheet(u, v, length, **kw):
    """A point on the outside of a sheet at (u, v) (to place trims and stars on it)."""
    w_top, w_bot, drift = kw.get("w_top", 0.95), kw.get("w_bot", 1.3), kw.get("drift", 0.38)
    folds, nfold = kw.get("folds", 0.05), kw.get("nfold", 3)
    half = w_top + (w_bot - w_top) * v ** 0.8
    y = BACK - drift * v ** 1.5 - folds * (0.3 + v) * math.sin((u + 1) * math.pi * nfold) - 0.06 * (1 - u * u) * v
    return half * u, y - 0.02, TOP - length * v


def feathers(style, length, role, **kw):
    """Feather tips along the hem (wedges in the trim colour), overlapping like a bird's tail."""
    subs = []
    rows = [(-0.84 + k * 0.28, 0.74, 0.0) for k in range(7)] + [(-0.98 + k * 0.28, 0.95, 0.012) for k in range(8)]
    for u, v, lift in rows:
        x, y, z = on_sheet(u, v, length, **kw)
        y -= lift  # the lower row lies over the upper one
        bm = bmesh.new()
        w, h = 0.2, 0.78
        pts = [(x - w, y, z + 0.1), (x + w, y, z + 0.1), (x + w * 0.5, y - 0.02, z - h * 0.55), (x, y - 0.03, z - h),
               (x - w * 0.5, y - 0.02, z - h * 0.55)]
        f = [bm.verts.new(p) for p in pts]
        bm.faces.new(f)
        b = [bm.verts.new((p[0], p[1] + 0.012, p[2])) for p in pts]
        bm.faces.new(list(reversed(b)))
        ob = kit._obj("f", bm)
        subs.append(ob)
    j = kit.join("Cape_%s_Feathers" % style, subs)
    outward_any(j)
    return (j, role)


def hood(style):
    """A lowered hood lying behind the neck, over the cape's top (outside main colour)."""
    rings = []
    for z, rx, ry, cy in ((TOP - 0.05, 0.55, 0.3, -0.72), (TOP + 0.12, 0.62, 0.36, -0.8), (TOP + 0.32, 0.58, 0.34, -0.84),
                          (TOP + 0.5, 0.46, 0.28, -0.84), (TOP + 0.62, 0.28, 0.16, -0.82)):
        rings.append((z, rx, ry, 0, cy))
    ob = kit.loft("Cape_%s_Hood" % style, rings, segs=16, power=2.2)
    return (ob, "p")


def mantle(style):
    """A fur-trimmed mantle round the shoulders (a lumpy ring in the accent)."""
    ob = kit.torus("Cape_%s_Mantle" % style, 1.02, 0.2, at=(0, 0.0, TOP + 0.02), segs=28, csegs=8)
    for v in ob.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        v.co.z += 0.04 * math.sin(a * 9)
        v.co.y *= 0.62
        v.co.x *= 1.0
    return (ob, "a")


# ---------------------------------------------------------------- the 12 styles
def tattered_hem(u):
    k = (u + 1) * 4.5
    t = abs(k - round(k))  # sharp notches
    return 1.0 - 0.28 * (1 - 2 * t) ** 2 * (0.6 + 0.4 * math.sin(u * 7.3))


STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


@style("short")
def s_short():
    kw = dict(w_top=0.95, w_bot=1.15, drift=0.16, folds=0.03, rows=6)
    return two_tone("short", 1.55, **kw) + [yoke("short"), clasps("short")]


@style("classic")
def s_classic():
    kw = dict(w_top=0.95, w_bot=1.32, drift=0.36)
    return two_tone("classic", 2.75, **kw) + [yoke("classic"), clasps("classic")]


@style("collar")
def s_collar():
    kw = dict(w_top=0.95, w_bot=1.36, drift=0.38)
    return two_tone("collar", 2.8, **kw) + [yoke("collar"), clasps("collar"), collar("collar")]


@style("long")
def s_long():
    kw = dict(w_top=0.95, w_bot=1.55, drift=0.6, folds=0.06, nfold=4, rows=12)
    return two_tone("long", 3.85, **kw) + [yoke("long"), clasps("long")]


@style("tattered")
def s_tattered():
    kw = dict(w_top=0.95, w_bot=1.3, drift=0.4, folds=0.06, cols=18, hem=tattered_hem)
    return two_tone("tattered", 2.7, **kw) + [yoke("tattered"), clasps("tattered")]


@style("split")
def s_split():
    kw = dict(w_top=0.95, w_bot=1.38, drift=0.4, cols=6)
    left = sheet("Cape_split_Left", 2.8, u0=-1.0, u1=-0.05, **kw)
    right = sheet("Cape_split_Right", 2.8, u0=0.05, u1=1.0, **kw)
    lin_l = sheet("Cape_split_LiningL", 2.8, u0=-1.0, u1=-0.05, inner=True, **kw)
    lin_r = sheet("Cape_split_LiningR", 2.8, u0=0.05, u1=1.0, inner=True, **kw)
    lining = kit.join("Cape_split_Lining", [outward(lin_l, False), outward(lin_r, False)], shade=False)
    return [(soft(outward(left, True)), "p"), (soft(outward(right, True)), "s"), (soft(lining), "dark"), yoke("split"),
            clasps("split")]


@style("comet")
def s_comet():
    kw = dict(w_top=0.95, w_bot=1.4, drift=0.42)
    band = hem_band("comet", 2.95, "a", True, at=0.86, width=0.12, **kw)
    band2 = hem_band("comet", 2.95, "a", True, at=0.72, width=0.05, **kw)
    band2[0].name = band2[0].data.name = "Cape_comet_Band2"
    return two_tone("comet", 2.95, **kw) + [yoke("comet"), clasps("comet", shape="star"), band, band2]


@style("mantle")
def s_mantle():
    kw = dict(w_top=1.05, w_bot=1.7, drift=0.7, folds=0.07, nfold=4, rows=12)
    return two_tone("mantle", 3.7, **kw) + [mantle("mantle"), clasps("mantle")]


@style("hood")
def s_hood():
    kw = dict(w_top=0.95, w_bot=1.3, drift=0.36)
    return two_tone("hood", 2.75, **kw) + [yoke("hood"), hood("hood")]


@style("feather")
def s_feather():
    kw = dict(w_top=0.95, w_bot=1.3, drift=0.36)
    return two_tone("feather", 2.35, **kw) + [yoke("feather"), clasps("feather"), feathers("feather", 2.35, "s", **kw)]


@style("star")
def s_star():
    kw = dict(w_top=0.95, w_bot=1.38, drift=0.4)
    parts = two_tone("star", 2.95, **kw)
    parts[0] = (parts[0][0], "dark")
    parts[1] = (parts[1][0], "a")
    pts = []
    import random
    rnd = random.Random(5)
    for _ in range(16):
        u, v = rnd.uniform(-0.85, 0.85), rnd.uniform(0.12, 0.92)
        x, y, z = on_sheet(u, v, 2.95, **kw)
        pts.append((x, y, z, rnd.choice((0.6, 0.8, 1.0, 1.4))))
    stars = sparkles("star", pts, "white")
    big = []
    for u, v in ((-0.4, 0.35), (0.45, 0.62)):
        x, y, z = on_sheet(u, v, 2.95, **kw)
        big.append((x, y - 0.005, z, 2.2))
    accent = sparkles("star", big, "a", name="BigStars")
    return parts + [yoke("star", "dark"), clasps("star", shape="star"), (stars, "white", True), (accent, "a", True)]


@style("night")
def s_night():
    kw = dict(w_top=0.95, w_bot=1.36, drift=0.4)
    band = hem_band("night", 2.9, "gold", False, at=0.93, width=0.14, **kw)
    pts = []
    for u, v, k in ((-0.45, 0.25, 1.2), (0.45, 0.5, 1.4), (-0.2, 0.68, 0.9), (0.6, 0.18, 0.8)):
        x, y, z = on_sheet(u, v, 2.9, **kw)
        pts.append((x, y, z, k))
    spark = sparkles("night", pts, "gold")
    return two_tone("night", 2.9, **kw) + [yoke("night"), clasps("night", "gold", shape="star"), band,
                                          (spark, "gold", True)]


# ---------------------------------------------------------------- build, fit, export, preview
def bounds(ob):
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def rbx(v):
    """Blender (x, y front, z up) to Roblox (X right, Y up, Z back)."""
    return (v.x, v.z, -v.y)


def build():
    rows = {}
    pieces = {}
    for name, fn in STYLES.items():
        items = []
        for it in fn():
            ob, role = it[0], it[1]
            glow = it[2] if len(it) > 2 else False
            kit.apply_all(ob)
            items.append((ob, role, glow))
        total = sum(kit.tris(ob) for ob, _, _ in items)
        assert total <= BUDGET, "%s: %d triangles" % (name, total)
        row = []
        for ob, role, glow in items:
            lo, hi = bounds(ob)
            c = (lo + hi) / 2 - TORSO_C
            size = hi - lo
            row.append({"mesh": ob.name, "role": role, "glow": glow,
                        "offset": [round(x, 3) for x in rbx(c)],
                        "size": [round(max(size.x, 0.02), 3), round(max(size.z, 0.02), 3), round(max(size.y, 0.02), 3)]})
        rows[name] = {"triangles": total, "pieces": row}
        pieces[name] = items
        print(name, total, "triangles")
    return rows, pieces


def write_config(rows):
    def v(t):
        return "{ %s }" % ", ".join("%.3f" % x for x in t)
    lines = ["-- GENERATED by art/blender/capes.py: do not edit by hand.",
             "-- The creator's cape meshes (ReplicatedStorage.Art.Capes once nate imports art/export/Capes.fbx; LookKit",
             "-- wears them then, the part-built capes until then). Keyed by the Capes kit's style (\"cape:<style>\"): each",
             "-- piece's mesh name, its colour role (the slot's p main, s trim, a accent, or dark, white, gold), glow",
             "-- (Neon) and its box against the UpperTorso's centre in Roblox axes (x right, y up, z back), in studs on",
             "-- the standard blocky rig (scaled with the torso).",
             "return {"]
    for name in rows:
        r = rows[name]
        lines.append("\t%s = {" % name)
        lines.append("\t\ttriangles = %d," % r["triangles"])
        lines.append("\t\tpieces = {")
        for p in r["pieces"]:
            lines.append("\t\t\t{ mesh = \"%s\", role = \"%s\", glow = %s, offset = %s, size = %s }," % (
                p["mesh"], p["role"], "true" if p["glow"] else "false", v(p["offset"]), v(p["size"])))
        lines.append("\t\t},")
        lines.append("\t},")
    lines += ["}", ""]
    path = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "CapeArt.luau"))
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote", path)


# the blocky R15 body for the preview (as clothed.py)
BLOCKS = {
    "UpperTorso": (-1.0, 1.0, -0.5, 0.5, 2.4, 4.0), "LowerTorso": (-1.0, 1.0, -0.5, 0.5, 2.0, 2.4),
    "LeftUpperArm": (-2.0, -1.0, -0.5, 0.5, 3.15, 4.0), "LeftLowerArm": (-2.0, -1.0, -0.5, 0.5, 2.3, 3.15),
    "LeftHand": (-2.0, -1.0, -0.5, 0.5, 2.0, 2.3), "LeftUpperLeg": (-1.0, 0.0, -0.5, 0.5, 1.15, 2.0),
    "LeftLowerLeg": (-1.0, 0.0, -0.5, 0.5, 0.3, 1.15), "LeftFoot": (-1.0, 0.0, -0.5, 0.5, 0.0, 0.3),
}
for k in list(BLOCKS):
    if k.startswith("Left"):
        x0, x1, y0, y1, z0, z1 = BLOCKS[k]
        BLOCKS["Right" + k[4:]] = (-x1, -x0, y0, y1, z0, z1)

SAMPLES = [((40, 110, 220), (235, 60, 60), (255, 210, 60)), ((235, 60, 60), (255, 210, 60), (245, 245, 245)),
           ((120, 80, 220), (24, 24, 28), (80, 255, 255)), ((40, 150, 80), (250, 240, 150), (255, 210, 60)),
           ((30, 45, 120), (175, 180, 190), (110, 210, 255)), ((150, 40, 110), (24, 24, 28), (255, 60, 140))]
FIXED = {"dark": (34, 38, 52), "white": (240, 240, 245), "gold": (255, 210, 70)}


def body(at, yaw, suit, skin=(224, 172, 130)):
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    obs = []
    for name, (x0, x1, y0, y1, z0, z1) in BLOCKS.items():
        ob = kit.box(name, x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        kit.bevel(ob, 0.03, 1)
        ob.data.materials.append(kit.material("suit%d" % len(bpy.data.materials), suit, rough=0.6))
        obs.append(ob)
    h = kit.sphere("Head", 0.62, at=(0, 0, 4.6), scale=(1, 1, 0.97), segs=24, rings=14)
    h.data.materials.append(kit.material("skin%d" % len(bpy.data.materials), skin, rough=0.55))
    obs.append(h)
    hair = kit.sphere("Hair", 0.66, at=(0, -0.04, 4.78), scale=(1, 1, 0.75), segs=20, rings=10)
    hair.data.materials.append(kit.material("hair%d" % len(bpy.data.materials), (40, 30, 26), rough=0.6))
    obs.append(hair)
    for ob in obs:
        ob.matrix_world = Y @ ob.matrix_world


def place(items, at, yaw, pal):
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for ob, role, glow in items:
        c = ob.copy()
        c.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(c)
        rgb = pal["psa".index(role)] if role in ("p", "s", "a") else FIXED[role]
        rgb = tuple(255 * (x / 255) ** 2.2 for x in rgb)  # the sRGB colour as Blender's linear value
        c.data.materials.clear()
        c.data.materials.append(kit.material("m%d" % len(bpy.data.materials), rgb, rough=0.55,
                                             emit=2.0 if glow else 0.0))
        c.matrix_world = Y @ c.matrix_world
        c.hide_render = False


def preview(pieces):
    for o in list(bpy.context.scene.objects):
        o.hide_render = True
    kit.studio(res=(2400, 1700), samples=40)
    bpy.context.scene.view_settings.view_transform = "Standard"
    names = list(STYLES)
    for i, name in enumerate(names):
        col, row = i % 6, i // 6
        at = ((2.5 - col) * 4.3, row * 9.0, 0)
        pal = SAMPLES[i % len(SAMPLES)]
        suit = (60, 64, 76)
        yaw = (col % 3 - 1) * 28  # backs to the camera, turned a little to show the drape
        body(at, yaw, suit)
        place(pieces[name], at, yaw, pal)
    # a third row from the side (the drift off the legs, the collar, hood and mantle)
    for k, name in enumerate(("classic", "long", "collar", "hood", "mantle", "feather")):
        at = ((2.5 - k) * 4.3, 18.0, 0)
        pal = SAMPLES[list(STYLES).index(name) % len(SAMPLES)]
        body(at, 90, (60, 64, 76))
        place(pieces[name], at, 90, pal)
    floor = kit.cyl("floor", 50, 50, 0.2, at=(0, 9.0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, -21.0, 15.0), (0, 8.0, 1.6), lens=31)
    kit.render(os.path.join(kit.ROOT, "preview", "capes.png"))


def thumbs(pieces):
    """The creator thumbnails (THUMBS=1, art/thumbs/thumbs.py packs them): each cape from behind on the plain
    blocky body (wear.body: no face, no hair), framed on the cape."""
    import wear
    for o in list(bpy.context.scene.objects):
        o.hide_render = True

    def dress(name, at, yaw, pal):
        wear.body(at, yaw, suit=(150, 156, 170))
        before = set(bpy.context.scene.objects)
        place(pieces[name[5:]], at, yaw, pal)
        for o in set(bpy.context.scene.objects) - before:
            o["thumb_piece"] = True
    wear.thumb_cells(["cape:" + n for n in STYLES], "capes", dress, 25, 0.12)


if __name__ == "__main__":
    rows, pieces = build()
    if os.environ.get("THUMBS"):
        thumbs(pieces)
        sys.exit(0)
    if not QUICK:
        objs = [ob for items in pieces.values() for ob, _, _ in items]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Capes.fbx"))
        write_config(rows)
    preview(pieces)
