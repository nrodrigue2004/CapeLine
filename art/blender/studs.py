# studs.py: shared helpers for the set piece style Blender scripts (setpieces.py, vehicles.py): the bright comic
# colours, shapes built in Roblox studs (x, up, z; z = back) about a look's foot point, and the look registry the
# fit tables are written from (one colour region a mesh; the game colours every MeshPart).
# Imported after kit (which imports bpy first).
import math

import kit
import bpy  # noqa: F401
import bmesh
from mathutils import Matrix, Vector

LOOKS = {}  # look -> {mesh name: object}
INFO = {}  # mesh name -> (rgb, material, transparency)

# ---------------------------------------------------------------- colours (bright comic versions of the city's)
GOLD = (236, 190, 58)
CRIMSON = (176, 28, 50)
CREAM = (248, 238, 214)
NAVY = (34, 44, 100)
WOOD = (158, 104, 62)
DARKWOOD = (112, 72, 44)
MARBLE = (238, 234, 226)
GLASS = (200, 235, 255)
GEM = (120, 230, 255)
WHITE = (246, 246, 246)
BLACK = (30, 30, 36)
CHARCOAL = (58, 62, 72)
RED = (226, 44, 44)
STEEL = (128, 136, 148)
TYRE = (38, 38, 44)
FUEL = (210, 62, 40)
YELLOW = (252, 212, 40)
PINK = (255, 64, 150)
BRASS = (226, 168, 58)
BRONZE = (182, 112, 58)
VERDIGRIS = (72, 186, 160)
SPARK = (110, 226, 245)
ROCK = (132, 122, 112)
SLATE = (96, 104, 118)
RUST = (184, 76, 50)
SKIN = (242, 196, 152)
TOYRED = (228, 62, 56)
TOYBLUE = (60, 124, 226)
TOYWHITE = (246, 242, 232)
TEAL = (64, 178, 196)
ROPE = (218, 186, 120)
HAY = (226, 190, 96)
ORANGE = (248, 140, 30)
GREEN = (96, 178, 82)
PURPLE = (128, 44, 150)


# ---------------------------------------------------------------- helpers in Roblox studs: x, up, z (z = back)
def rb(x, y, z):
    """Roblox (x, up, z) to Blender (x, front, up)."""
    return (x, -z, y)


def B(sx, sy, sz, x=0.0, y=0.0, z=0.0, bev=None):
    ob = kit.box("b", sx, sz, sy, at=rb(x, y, z))
    if bev:
        kit.bevel(ob, bev, 1)
        kit.apply_all(ob)
    return ob


AX = {"up": "Z", "x": "X", "z": "Y"}


def C(r, h, x=0.0, y=0.0, z=0.0, segs=12, r2=None, axis="up"):
    """A cylinder (or cone with r2) along up, x or z; for up, r is the bottom radius."""
    # (kit's cone puts r at its bottom: Roblox -x for "x", -z for "z")
    ob = kit.cyl("c", r, r if r2 is None else r2, h, at=(0, 0, 0), segs=segs, axis=AX[axis])
    shift(ob, rb(x, y, z))
    return ob


def S(r, x=0.0, y=0.0, z=0.0, sc=(1, 1, 1), segs=12, rings=8):
    return kit.sphere("s", r=r, at=rb(x, y, z), scale=(sc[0], sc[2], sc[1]), segs=segs, rings=rings)


def T(points, radii, segs=8):
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * len(points)
    return kit.tube_along("t", [Vector(rb(*p)) for p in points], list(radii), segs=segs)


def TOR(major, minor, x=0.0, y=0.0, z=0.0, axis="up", segs=20, csegs=6, arc=2 * math.pi):
    return kit.torus("tor", major, minor, at=rb(x, y, z), segs=segs, csegs=csegs, arc=arc, axis=AX[axis])


def shift(ob, off):
    kit.apply_all(ob)
    for v in ob.data.vertices:
        v.co += Vector(off)
    ob.data.update()
    return ob


def turn(ob, axis, deg, pivot=(0, 0, 0)):
    """Turn a mesh by deg about a Roblox axis ("x", "up", "z") through pivot (Roblox studs), the way Roblox's
    CFrame.Angles turns a part (x and up keep the angle in Blender, z flips it)."""
    kit.apply_all(ob)
    a = math.radians(deg)
    if axis == "x":
        M = Matrix.Rotation(a, 4, "X")
    elif axis == "up":
        M = Matrix.Rotation(a, 4, "Z")
    else:
        M = Matrix.Rotation(-a, 4, "Y")
    p = Vector(rb(*pivot))
    for v in ob.data.vertices:
        v.co = (M @ (v.co - p)) + p
    ob.data.update()
    return ob


def move(ob, x=0.0, y=0.0, z=0.0, yaw=0.0):
    """Turn by yaw (Roblox degrees about up) about the origin, then move."""
    if yaw:
        turn(ob, "up", yaw)
    return shift(ob, rb(x, y, z))


def mirror(ob):
    """A copy mirrored across x = 0."""
    kit.apply_all(ob)
    return kit.mirror_x(ob, ob.name + "_m")


def copy(ob):
    cp = ob.copy()
    cp.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(cp)
    return cp


def rings_mesh(rings, cap=(True, True)):
    """A closed mesh through rings of Roblox points (each ring the same count), capped at the ends."""
    bm = bmesh.new()
    loops = [[bm.verts.new(rb(*p)) for p in ring] for ring in rings]
    n = len(rings[0])
    for k in range(len(loops) - 1):
        a, b = loops[k], loops[k + 1]
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    for idx, on in ((0, cap[0]), (-1, cap[1])):
        if on:
            lp = loops[idx]
            c = Vector((0, 0, 0))
            for v in lp:
                c += v.co
            cv = bm.verts.new(c / n)
            for i in range(n):
                bm.faces.new((lp[i], lp[(i + 1) % n], cv))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("rm")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("rm", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def prism(poly, x0, x1):
    """A polygon in the (z, up) plane pushed out along x from x0 to x1 (side frames, roof stripes)."""
    return rings_mesh([[(x0, y, z) for (z, y) in poly], [(x1, y, z) for (z, y) in poly]])


def extrude_up(poly, y0, y1, fn=None, steps=1):
    """A polygon in the (x, z) plane pushed up from y0 to y1; fn(t, x, z) -> (x, z) bends each level (t 0..1)."""
    rs = []
    for k in range(steps + 1):
        t = k / steps
        y = y0 + (y1 - y0) * t
        ring = []
        for (x, z) in poly:
            if fn:
                x, z = fn(t, x, z)
            ring.append((x, y, z))
        rs.append(ring)
    return rings_mesh(rs)


def star(r_out, r_in, depth, x=0.0, y=0.0, z=0.0, points=5, axis="z"):
    """A flat star facing along z (or up)."""
    poly = []
    for i in range(points * 2):
        a = math.pi / 2 + i * math.pi / points
        r = r_out if i % 2 == 0 else r_in
        poly.append((math.cos(a) * r, math.sin(a) * r))
    if axis == "z":
        ob = rings_mesh([[(px, py, -depth / 2) for (px, py) in poly], [(px, py, depth / 2) for (px, py) in poly]])
    else:
        ob = rings_mesh([[(px, -depth / 2, py) for (px, py) in poly], [(px, depth / 2, py) for (px, py) in poly]])
    return shift(ob, rb(x, y, z))


def section(w, yb, yt, segs=12, power=2.6):
    """A rounded cross-section (half width w, from yb to yt) as (x, y) points."""
    cy, ry = (yb + yt) / 2, (yt - yb) / 2
    out = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        out.append((w * math.copysign(abs(c) ** (2 / power), c), cy + ry * math.copysign(abs(s) ** (2 / power), s)))
    return out


def loft_z(stations, segs=12, power=2.6):
    """A body lofted along z through (z, half width, bottom, top) stations (car bodies, hulls)."""
    return rings_mesh([[(x, y, z) for (x, y) in section(w, yb, yt, segs, power)] for (z, w, yb, yt) in stations])


def hull_z(stations, segs=10):
    """A boat hull along z: (z, half width, keel, deck) stations; a U cross-section with a flat deck."""
    rs = []
    for (z, w, yb, yt) in stations:
        ring = []
        for i in range(segs + 1):
            a = math.pi + math.pi * i / segs
            ring.append((w * math.cos(a), yt + (yt - yb) * math.sin(a), z))
        rs.append(ring)
    return rings_mesh(rs)


def mesh(look, name, parts, rgb, mat="SmoothPlastic", alpha=0.0, shade=True):
    """One mesh of a look: its parts joined, with the colour, material and transparency the game gives it."""
    if not isinstance(parts, (list, tuple)):
        parts = [parts]
    if len(parts) == 1:
        ob = kit.apply_all(parts[0])
        ob.name = name
        ob.data.name = name
        if shade:
            kit.shade_auto(ob)
    else:
        ob = kit.join(name, list(parts), shade=shade)
    assert name not in INFO, "mesh names are unique across the set: " + name
    LOOKS.setdefault(look, {})[name] = ob
    INFO[name] = (tuple(int(c) for c in rgb), mat, alpha)
    return ob
