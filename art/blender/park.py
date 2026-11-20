# park.py: the city park's set (2026-11-20, nate: "maybe add a large park between uptown and downtown. like central
# park"; Config.Park, Shared.ParkLayout). One mesh per colour region like street.py and life.py; every look is a
# foot look: each piece's size and its centre from the look's foot point (Roblox x, up, back), the look facing -z
# (Blender +y). The server builds the structures over hidden collision boxes (ParkBuilder); the device builds the
# living things (Fx.ParkLife). The benches, lamps, bins, carts and bushes are the street set's (Art.Street).
#   Bandshell, Carousel, Boathouse, Terrace (the big fountain), SmallFountain, BowBridge, StoneBridge, Rink,
#   GatePillar, GateSign, ParkWall, ParkRail, Reeds, LilyPads, and the living: Rowboat, Duck, Dog, Picnic, Guitar,
#   GuitarCase. All original designs (no real monument is copied: the finial is Brightharbor's own spark).
# Output: art/export/Park.fbx, src/config/ParkArt.luau (generated); --preview renders art/preview/park_kit.png.
# Run: ~/tools/bpyenv/bin/python art/blender/park.py [--preview]
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

kit.reset()
rng = random.Random(20261120)
looks = {}  # look -> {piece: object}


def put(look, name, parts, bev=None, shade=True, flat=False):
    for p in parts:
        if bev:
            kit.bevel(p, bev, 1)
    if len(parts) > 1:
        ob = kit.join(name, parts, shade=shade)
    else:
        ob = parts[0]
        kit.apply_all(ob)
        ob.name = name
        ob.data.name = name
        if shade:
            kit.shade_auto(ob)
    if flat:
        for f in ob.data.polygons:
            f.use_smooth = False
    looks.setdefault(look, {})[name] = ob
    return ob


def _obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def lathe(name, profile, segs=24, at=(0, 0, 0), phase=0.0):
    """A solid of revolution about z: profile is [(r, z)] from the axis round the outline (first and last r may
    be 0 to close on the axis)."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs + phase
            ring.append(bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(segs):
            q = (a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i])
            try:
                bm.faces.new(q)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm)


def prism(name, pts, z0, z1):
    """A flat outline (Blender x, y) extruded from z0 to z1 (concave outlines are ear-clipped)."""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    n = len(pts)
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    for i in range(n):
        bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm)


def side_prism(name, pts, x0, x1):
    """An outline in the side plane (Blender y, z) extruded across x from x0 to x1."""
    ob = prism(name, [(y, z) for y, z in pts], x0, x1)
    for v in ob.data.vertices:
        y, z, x = v.co.x, v.co.y, v.co.z
        v.co = Vector((x, y, z))
    ob.data.flip_normals()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def rounded_rect(w, d, r, n=6):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180), (w / 2 - r, -d / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def solidify(ob, t):
    m = ob.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = t
    m.offset = 0
    kit.apply_all(ob)
    return ob


def jitter(ob, amp, scale=0.6, seed=1.0):
    kit.apply_all(ob)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in ob.data.vertices:
        v.co += Vector((noise.noise(v.co * scale + off), noise.noise(v.co * scale + off * 2), noise.noise(v.co * scale + off * 3))) * amp
    return ob


def rot_z(ob, deg):
    kit.apply_all(ob)
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    for v in ob.data.vertices:
        x, y = v.co.x, v.co.y
        v.co.x, v.co.y = x * c - y * s, x * s + y * c
    return ob


def arc_tube(name, radius, minor, y, zscale=1.0, segs=28, csegs=6, z0=0.0):
    """A half arch in the x-z plane at depth y (an upside-down U), its feet at z0."""
    pts = [Vector((radius * math.cos(math.pi * i / segs), y, z0 + zscale * radius * math.sin(math.pi * i / segs))) for i in range(segs + 1)]
    return kit.tube_along(name, pts, [minor] * len(pts), segs=csegs)


# ================================================================ the bandshell (44 wide, 30 deep, opens to +y)
stage_pts = [(-21, -10)] + [(21 * math.cos(math.radians(a)), 2 + 10 * math.sin(math.radians(a))) for a in range(0, 181, 12)][::-1]
stage_pts = [(-21, -10), (21, -10)] + [(21 * math.cos(math.radians(a)), 2 + 10 * math.sin(math.radians(a))) for a in range(0, 181, 12)]
put("Bandshell", "BandStage", [prism("stage", stage_pts, 0, 4)], bev=0.25)
shell = kit.sphere("shell", 1.0, segs=36, rings=20)
kit.cut(shell, (0, 1, 0), keep_positive=False, fill=False)  # keep y < 0
kit.cut(shell, (0, 0, 1), keep_positive=True, fill=False)  # keep z > 0
for v in shell.data.vertices:
    v.co = Vector((v.co.x * 19, v.co.y * 13 - 2, 4 + v.co.z * 21))
solidify(shell, 0.6)
put("Bandshell", "BandShell", [shell])
ribs = []
for k in range(6):
    ribs.append(arc_tube("rib%d" % k, 19.6 + k * 0.85, 0.45, -2 + k * 1.4, zscale=21.6 / 19.6 + k * 0.004, z0=4))
put("Bandshell", "BandRibs", ribs)
put("Bandshell", "BandLights", [arc_tube("lights", 24.2, 0.18, 6.6, zscale=1.07, csegs=5, z0=4)], shade=False)
steps = [kit.box("st%d" % k, 14 - k * 1.5, 1.6, 1.33, at=(0, 12.4 + (2 - k) * 1.5, 0.67 + k * 1.33)) for k in range(3)]
put("Bandshell", "BandSteps", steps, bev=0.1)

# ================================================================ the carousel (r 16, 21 tall)
put("Carousel", "CarouselBase", [lathe("base", [(0, 0), (16.2, 0), (16.2, 0.9), (15.6, 1.0), (15.6, 1.5), (0, 1.5)], segs=40)], bev=0.12)
core = lathe("core", [(0, 1.5), (3.6, 1.5), (3.6, 2.4), (3.0, 2.6), (3.0, 7), (3.4, 7.3), (3.4, 8.4), (3.0, 8.7), (3.0, 14.2), (3.8, 14.6), (3.8, 15.3), (0, 15.3)], segs=16)
fin = [lathe("fin", [(0, 20.4), (0.35, 20.5), (0.25, 22.4), (0.5, 22.8), (0, 23.4)], segs=10), kit.sphere("ball", 0.55, at=(0, 0, 21.2), segs=10, rings=6)]
put("Carousel", "CarouselCore", [core] + fin)


def tent(name, sectors, parity, r0, r1, z0, z1, valance=1.2):
    bm = bmesh.new()
    for i in range(sectors):
        if i % 2 != parity:
            continue
        a0, a1 = 2 * math.pi * i / sectors, 2 * math.pi * (i + 1) / sectors
        steps = 3
        prev = None
        for k in range(steps + 1):
            a = a0 + (a1 - a0) * k / steps
            c, s = math.cos(a), math.sin(a)
            col = [bm.verts.new((c * r0, s * r0, z0)), bm.verts.new((c * (r0 * 0.55 + r1 * 0.45), s * (r0 * 0.55 + r1 * 0.45), z0 + (z1 - z0) * 0.62)),
                   bm.verts.new((c * r1, s * r1, z1))]
            if prev:
                for j in range(2):
                    bm.faces.new((prev[j], col[j], col[j + 1], prev[j + 1]))
            prev = col
        # a scalloped valance tab under the sector
        am = (a0 + a1) / 2
        tab = [bm.verts.new((math.cos(a0) * r0, math.sin(a0) * r0, z0)), bm.verts.new((math.cos(a1) * r0, math.sin(a1) * r0, z0))]
        tip = bm.verts.new((math.cos(am) * r0, math.sin(am) * r0, z0 - valance))
        bm.faces.new((tab[0], tip, tab[1]))
    me_ob = _obj(name, bm)
    return solidify(me_ob, 0.25)


put("Carousel", "CarouselRoof", [tent("roof", 24, 0, 17.4, 0.6, 15.3, 20.6)])
put("Carousel", "CarouselStripes", [tent("stripe", 24, 1, 17.4, 0.6, 15.3, 20.6)])
poles, horses, saddles, bulbs = [], [], [], []


def horse(i, x, y, z, yaw):
    body = kit.loft("hb", [(-1.3, 0.25, 0.3, 0, 0), (-1.0, 0.45, 0.5, 0, 0), (0, 0.52, 0.6, 0, 0), (0.9, 0.48, 0.55, 0, 0), (1.25, 0.3, 0.35, 0, 0)], segs=10, power=2.2)
    for v in body.data.vertices:  # the loft runs up z: lie it along y (nose to +y)
        v.co = Vector((v.co.x, v.co.z, v.co.y))
    neck = kit.tube_along("hn", [Vector((0, 1.0, 0.2)), Vector((0, 1.45, 0.9)), Vector((0, 1.6, 1.4))], [0.32, 0.26, 0.22], segs=8)
    head = kit.loft("hh", [(0, 0.22, 0.2, 0, 0), (0.45, 0.24, 0.26, 0, 0), (0.85, 0.16, 0.2, 0, 0)], segs=8)
    for v in head.data.vertices:
        v.co = Vector((v.co.x, 1.55 + v.co.z, 1.45 + v.co.y * 0.4 - v.co.z * 0.25))
    mane = kit.box("hm", 0.12, 0.7, 0.35, at=(0, 1.35, 1.25))
    tail = kit.tube_along("ht", [Vector((0, -1.3, 0.2)), Vector((0, -1.7, -0.1)), Vector((0, -1.85, -0.6))], [0.14, 0.12, 0.05], segs=6)
    legs = []
    for lx, ly, swing in ((-0.28, 0.75, 0.6), (0.28, 0.75, 0.9), (-0.28, -0.85, -0.5), (0.28, -0.85, -0.8)):
        legs.append(kit.tube_along("hl", [Vector((lx, ly, -0.2)), Vector((lx, ly + swing * 0.4, -0.75)), Vector((lx, ly + swing * 0.9, -1.15))], [0.14, 0.11, 0.09], segs=6))
    parts = [body, neck, head, mane, tail] + legs
    for p in parts:
        rot_z(p, yaw)
        kit.shift(p, (x, y, z))
    sad = kit.box("sad", 0.95, 0.8, 0.2, at=(0, 0, 0.55))
    rot_z(sad, yaw)
    kit.shift(sad, (x, y, z))
    return parts, sad


for k in range(16):
    ring = 12.2 if k % 2 == 0 else 8.6
    a = 2 * math.pi * (k + (0.5 if k % 2 else 0)) / 16
    x, y = ring * math.cos(a), ring * math.sin(a)
    poles.append(kit.cyl("pole%d" % k, 0.14, 0.14, 13.8, at=(x, y, 8.4), segs=6))
    poles.append(kit.torus("cuff%d" % k, 0.2, 0.06, at=(x, y, 14.6), segs=8, csegs=4))
    hz = 5.2 + (0.9 if k % 4 < 2 else 0)
    parts, sad = horse(k, x, y, hz, math.degrees(a) + 180)  # nose along the turn
    horses += parts
    saddles.append(sad)
for k in range(36):
    a = 2 * math.pi * k / 36
    bulbs.append(kit.sphere("bulb%d" % k, 0.22, at=(17.3 * math.cos(a), 17.3 * math.sin(a), 15.0), segs=6, rings=4))
put("Carousel", "CarouselPoles", poles)
put("Carousel", "CarouselHorses", horses)
put("Carousel", "CarouselSaddles", saddles, bev=0.06)
put("Carousel", "CarouselLights", bulbs, shade=False)

# ================================================================ the boathouse (34 wide, a deck out front over the water)
W, D, H = 34.0, 20.0, 10.0
walls = [kit.box("w", W, D, H, at=(0, -D / 2, H / 2)), kit.box("plinth", W + 0.8, D + 0.8, 1.2, at=(0, -D / 2, 0.6))]
put("Boathouse", "BoatWalls", walls, bev=0.2)
glass, trim = [], []
for k in range(7):
    x = -W / 2 + 3 + k * (W - 6) / 6
    if k != 3:
        glass.append(kit.box("g%d" % k, 3.4, 0.25, 5.4, at=(x, 0.06, 5.6)))
    trim.append(kit.box("post%d" % k, 0.7, 0.6, H, at=(x + 2.4 if k < 6 else x - 3 + 0.35, 0.15, H / 2)))
for side in (-1, 1):
    for k in range(4):
        y = -3 - k * 4.6
        glass.append(kit.box("gs%d%d" % (side, k), 0.25, 3, 5.0, at=(side * (W / 2 + 0.06), y, 5.6)))
door = kit.box("door", 5.0, 0.4, 7.2, at=(0, 0.1, 3.6))
glass.append(kit.box("dg", 4.0, 0.3, 6.2, at=(0, 0.2, 3.6)))
trim += [door, kit.box("cornice", W + 1.2, D + 1.2, 0.7, at=(0, -D / 2, H + 0.1)), kit.box("sill", W + 0.4, 0.8, 0.4, at=(0, 0.3, 2.7))]
put("Boathouse", "BoatGlass", glass)
roof = kit.loft("roof", [(H + 0.4, W / 2 + 1.6, D / 2 + 1.6, 0, -D / 2), (H + 3.2, W / 2 - 2.0, D / 2 - 2.2, 0, -D / 2), (H + 5.4, W / 2 - 7.0, 1.8, 0, -D / 2)], segs=24, power=6, cap=(True, True))
cupola = [kit.box("cup", 3.6, 3.6, 2.6, at=(0, -D / 2, H + 6.4)), kit.cyl("cupr", 2.8, 0.2, 2.4, at=(0, -D / 2, H + 8.9), segs=4)]
rot_z(cupola[1], 45)
kit.shift(cupola[1], (0, 0, 0))
put("Boathouse", "BoatRoof", [roof] + cupola, flat=True)
DD = 18.0  # the deck
rail = []
for k in range(13):
    x = -W / 2 + 0.5 + k * (W - 1) / 12
    rail.append(kit.box("rp%d" % k, 0.35, 0.35, 3.2, at=(x, DD - 0.3, 2.2)))
for side in (-1, 1):
    for k in range(6):
        rail.append(kit.box("rs%d%d" % (side, k), 0.35, 0.35, 3.2, at=(side * (W / 2 - 0.3), 2 + k * (DD - 2.3) / 5, 2.2)))
    rail.append(kit.box("rtop%d" % side, 0.45, DD - 1.6, 0.35, at=(side * (W / 2 - 0.3), DD / 2 + 0.4, 3.7)))
rail.append(kit.box("rtopf", W, 0.45, 0.35, at=(0, DD - 0.3, 3.7)))
trim += rail
put("Boathouse", "BoatTrim", trim, bev=0.05)
put("Boathouse", "BoatDeck", [kit.box("deck", W + 0.6, DD, 0.6, at=(0, DD / 2, 0.3))], bev=0.08)
pil = [kit.cyl("pl%d" % k, 0.45, 0.45, 7.4, at=(-W / 2 + 1 + (k % 6) * (W - 2) / 5, 4 + (k // 6) * (DD - 5) / 2, -3.4), segs=8) for k in range(18)]
put("Boathouse", "BoatPilings", pil)

# ================================================================ the terrace fountain (r 19, 17 tall)
put("Terrace", "TerraceBasin", [lathe("basin", [(0, 0.3), (16.2, 0.3), (16.2, 2.7), (16.6, 3.1), (18.4, 3.1), (18.9, 2.8), (18.7, 2.4), (18.9, 0.6), (19.4, 0), (0, 0)], segs=48)], bev=0.08)
pool = kit.cyl("pool", 16.25, 16.25, 0.2, at=(0, 0, 2.4), segs=48)
put("Terrace", "TerracePool", [pool])
put("Terrace", "TerracePedestal", [lathe("ped", [(0, 0.3), (4.2, 0.3), (4.2, 1.2), (3.2, 1.6), (2.0, 2.4), (1.6, 5.0), (2.2, 6.2), (2.2, 7.0), (1.1, 7.4), (0.9, 10.6), (1.3, 11.2), (0, 11.4)], segs=20)], bev=0.05)
bowls = [lathe("b1", [(0, 6.6), (2.0, 6.6), (5.6, 7.4), (7.6, 8.4), (7.8, 9.0), (7.2, 9.0), (5.4, 8.1), (2.4, 7.6), (0, 7.6)], segs=32),
         lathe("b2", [(0, 11.0), (1.0, 11.0), (2.8, 11.6), (3.7, 12.3), (3.8, 12.7), (3.4, 12.7), (2.6, 12.0), (1.2, 11.7), (0, 11.7)], segs=24)]
put("Terrace", "TerraceBowls", bowls)
put("Terrace", "TerraceBowlWater", [kit.cyl("bw1", 7.2, 7.2, 0.15, at=(0, 0, 8.75), segs=32), kit.cyl("bw2", 3.35, 3.35, 0.12, at=(0, 0, 12.55), segs=20)])
star = []
for k in range(4):  # Brightharbor's four-point spark, turned to face every way
    pts = []
    for j in range(8):
        a = math.pi * j / 4
        r = 2.4 if j % 2 == 0 else 0.6
        pts.append((r * math.cos(a), r * math.sin(a)))
    s = prism("spark%d" % k, pts, -0.25, 0.25)
    for v in s.data.vertices:
        v.co = Vector((v.co.x, v.co.z, v.co.y))
    rot_z(s, 45 * k)
    kit.shift(s, (0, 0, 15.8))
    star.append(s)
star.append(kit.sphere("orb", 0.8, at=(0, 0, 13.4), segs=12, rings=8))
star.append(kit.cyl("stem", 0.35, 0.3, 1.6, at=(0, 0, 12.4), segs=8))
put("Terrace", "TerraceFinial", star)

# ================================================================ the small fountain (octagonal, r 8)
put("SmallFountain", "SmallBasin", [lathe("sb", [(0, 0.3), (6.9, 0.3), (6.9, 2.0), (7.3, 2.4), (8.3, 2.4), (8.6, 2.1), (8.4, 0.5), (8.8, 0), (0, 0)], segs=8, phase=math.pi / 8)], bev=0.06, flat=True)
put("SmallFountain", "SmallPool", [kit.cyl("sp", 7.0, 7.0, 0.18, at=(0, 0, 1.75), segs=8)])
put("SmallFountain", "SmallSpout", [lathe("ss", [(0, 0.3), (1.6, 0.3), (1.4, 1.0), (0.8, 1.4), (0.6, 4.6), (2.4, 5.2), (2.6, 5.6), (0.6, 5.5), (0.5, 6.6), (0.8, 7.0), (0, 7.4)], segs=12)])


# ================================================================ the Bow Bridge (72 long along y, 12 wide, rise 4.5)
def arch_z(y, L, rise):
    t = 2 * y / L
    return rise * (1 - t * t)


def deck_strip(name, L, w, rise, thick, z_add=0.0, n=36):
    bm = bmesh.new()
    rows = []
    for i in range(n + 1):
        y = -L / 2 + L * i / n
        z = arch_z(y, L, rise) + z_add
        rows.append([bm.verts.new((-w / 2, y, z)), bm.verts.new((w / 2, y, z)), bm.verts.new((w / 2, y, z - thick)), bm.verts.new((-w / 2, y, z - thick))])
    for i in range(n):
        a, b = rows[i], rows[i + 1]
        for j in range(4):
            bm.faces.new((a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]))
    bm.faces.new(rows[0])
    bm.faces.new(list(reversed(rows[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm)


BL, BW, BR = 72.0, 12.0, 4.5
put("BowBridge", "BowDeck", [deck_strip("bd", BL, BW - 1, BR, 0.7, z_add=0.7)])
girders = []
for side in (-1, 1):
    x = side * (BW / 2 - 0.4)
    top = [Vector((x, -BL / 2 + BL * i / 30, arch_z(-BL / 2 + BL * i / 30, BL, BR) - 0.2)) for i in range(31)]
    girders.append(kit.tube_along("gt%d" % side, top, [0.35] * 31, segs=6))
    under = [Vector((x, -BL / 2 * 0.9 + BL * 0.9 * i / 30, arch_z(-BL / 2 * 0.9 + BL * 0.9 * i / 30, BL * 0.9, BR + 1.2) - 3.2)) for i in range(31)]
    girders.append(kit.tube_along("gu%d" % side, under, [0.3] * 31, segs=6))
    for k in range(11):  # rings between the two girders, the bridge's lace
        y = -BL * 0.38 + k * BL * 0.76 / 10
        z0 = arch_z(y, BL * 0.9, BR + 1.2) - 3.2
        z1 = arch_z(y, BL, BR) - 0.2
        girders.append(kit.torus("lace%d%d" % (side, k), max(0.3, (z1 - z0) / 2 - 0.25), 0.1, at=(x, y, (z0 + z1) / 2), segs=12, csegs=4, axis="X"))
put("BowBridge", "BowGirders", girders)
rails = []
for side in (-1, 1):
    x = side * (BW / 2 - 0.5)
    pts = [Vector((x, -BL / 2 + BL * i / 30, arch_z(-BL / 2 + BL * i / 30, BL, BR) + 3.8)) for i in range(31)]
    rails.append(kit.tube_along("rt%d" % side, pts, [0.16] * 31, segs=6))
    pts2 = [Vector((x, p.y, p.z - 2.6)) for p in pts]
    rails.append(kit.tube_along("rb%d" % side, pts2, [0.1] * 31, segs=5))
    for k in range(37):
        y = -BL / 2 + 0.6 + k * (BL - 1.2) / 36
        z = arch_z(y, BL, BR) + 0.7
        rails.append(kit.cyl("bal%d%d" % (side, k), 0.07, 0.07, 3.1, at=(x, y, z + 1.55), segs=4))
        if k % 3 == 1:
            rails.append(kit.torus("q%d%d" % (side, k), 0.55, 0.06, at=(x, y + 0.9, z + 1.75), segs=10, csegs=3, axis="X"))
put("BowBridge", "BowRails", rails)
urns = []
for sx in (-1, 1):
    for sy in (-1, 1):
        urns.append(lathe("urn", [(0, 0), (0.9, 0), (0.9, 2.2), (0.5, 2.6), (0.9, 3.0), (1.3, 3.9), (1.4, 4.4), (0, 4.4)], segs=14, at=(sx * (BW / 2 - 0.6), sy * (BL / 2 - 0.3), 0)))
put("BowBridge", "BowUrns", urns)

# ================================================================ the stone bridge (62 long along y, 10 wide, an arch over the water)
SL, SW, SR, SPAN = 62.0, 10.0, 5.2, 30.0
top = [(-SL / 2 + SL * i / 24, arch_z(-SL / 2 + SL * i / 24, SL, SR)) for i in range(25)]
under = [(SPAN / 2 * math.cos(math.pi * i / 16), -7 + 10.2 * math.sin(math.pi * i / 16)) for i in range(17)]
outline = top + [(SL / 2, -7.0)] + under + [(-SL / 2, -7.0)]
arch = side_prism("sarch", outline, -SW / 2, SW / 2)
for v in arch.data.vertices:  # stone blocks: a little lumpy so the faces catch the light
    v.co += Vector((0, 0, 0))
put("StoneBridge", "StoneArch", [arch], bev=0.15)
par = []
for side in (-1, 1):
    pp = [(-SL / 2 + SL * i / 24, arch_z(-SL / 2 + SL * i / 24, SL, SR) + 2.4) for i in range(25)]
    pl = [(-SL / 2 + SL * i / 24, arch_z(-SL / 2 + SL * i / 24, SL, SR) - 0.1) for i in range(25)]
    par.append(side_prism("par%d" % side, pp + pl[::-1], side * SW / 2 - 0.7, side * SW / 2 + 0.25))
    cap = [(-SL / 2 - 0.3 + (SL + 0.6) * i / 24, arch_z(-SL / 2 + SL * i / 24, SL, SR) + 2.75) for i in range(25)]
    capb = [(y, z - 0.45) for y, z in cap]
    par.append(side_prism("cap%d" % side, cap + capb[::-1], side * SW / 2 - 0.95, side * SW / 2 + 0.45))
put("StoneBridge", "StoneParapet", par, bev=0.08)
put("StoneBridge", "StoneDeck", [deck_strip("sd", SL, SW - 1.6, SR, 0.2, z_add=0.12, n=24)])

# ================================================================ the rink (70 x 40, rounded corners)
RW, RD, RC = 70.0, 40.0, 10.0
put("Rink", "RinkIce", [prism("ice", rounded_rect(RW - 1.2, RD - 1.2, RC - 0.6), 0, 0.3)])
outer, inner = rounded_rect(RW + 0.6, RD + 0.6, RC + 0.3), rounded_rect(RW - 0.6, RD - 0.6, RC - 0.3)
bm = bmesh.new()


def ring_wall(name, outer, inner, z0, z1):
    bm = bmesh.new()
    n = len(outer)
    o0 = [bm.verts.new((x, y, z0)) for x, y in outer]
    o1 = [bm.verts.new((x, y, z1)) for x, y in outer]
    i0 = [bm.verts.new((x, y, z0)) for x, y in inner]
    i1 = [bm.verts.new((x, y, z1)) for x, y in inner]
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((o0[k], o0[j], o1[j], o1[k]))
        bm.faces.new((i0[j], i0[k], i1[k], i1[j]))
        bm.faces.new((o1[k], o1[j], i1[j], i1[k]))
        bm.faces.new((o0[j], o0[k], i0[k], i0[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm)


put("Rink", "RinkBoards", [ring_wall("boards", outer, inner, 0, 3.4)])
put("Rink", "RinkTrim", [ring_wall("cap", rounded_rect(RW + 0.9, RD + 0.9, RC + 0.45), rounded_rect(RW - 0.9, RD - 0.9, RC - 0.45), 3.4, 3.8),
                         ring_wall("kick", rounded_rect(RW + 0.7, RD + 0.7, RC + 0.35), rounded_rect(RW - 0.7, RD - 0.7, RC - 0.35), 0, 0.6)])

# ================================================================ the gate pillars and the sign over a gate
blocks = []
for k in range(6):
    w = 3.0 if k % 2 == 0 else 2.7
    blocks.append(kit.box("pb%d" % k, w, w, 1.32, at=(0, 0, 0.66 + k * 1.36)))
blocks.append(kit.box("pbase", 3.5, 3.5, 0.8, at=(0, 0, 0.4)))
put("GatePillar", "PillarStone", [jitter(b, 0.04, 1.2, i) for i, b in enumerate(blocks)], bev=0.12)
put("GatePillar", "PillarCap", [kit.box("cap", 3.6, 3.6, 0.6, at=(0, 0, 8.55)), kit.box("cap2", 2.6, 2.6, 0.4, at=(0, 0, 9.05)),
                                kit.cyl("lb", 0.6, 0.4, 0.8, at=(0, 0, 9.6), segs=8)], bev=0.08)
lamp = kit.loft("lamp", [(10.0, 0.5, 0.5, 0, 0), (10.6, 0.75, 0.75, 0, 0), (11.6, 0.7, 0.7, 0, 0), (12.0, 0.25, 0.25, 0, 0)], segs=6, power=2)
put("GatePillar", "PillarLamp", [lamp], flat=True)
SPAN_G = 19.5  # pillar centres for a 16 gate
frame = [arc_tube("arch", SPAN_G / 2, 0.18, 0, zscale=0.32, z0=9.4, segs=20, csegs=6),
         kit.box("hang1", 0.12, 0.12, 0.9, at=(-5.5, 0, 11.4)), kit.box("hang2", 0.12, 0.12, 0.9, at=(5.5, 0, 11.4))]
put("GateSign", "SignFrame", frame)
put("GateSign", "SignBoard", [kit.box("board", 13.0, 0.3, 2.2, at=(0, 0, 10.1))], bev=0.08)

# ================================================================ the park wall (24 long) and the reservoir rail (12 long)
stones = []
for row_ in range(4):
    x = -12.0
    z = 0.42 + row_ * 0.78
    while x < 12.0 - 0.3:
        L = min(rng.uniform(1.3, 2.6), 12.0 - x)
        s = kit.box("s", L - 0.08, 2.0 - rng.uniform(0, 0.1), 0.74, at=(x + L / 2, rng.uniform(-0.04, 0.04), z))
        kit.bevel(s, 0.1, 1)
        stones.append(s)
        x += L
put("ParkWall", "WallStone", stones, shade=False)
caps = []
x = -12.0
while x < 11.9:
    L = min(rng.uniform(2.8, 4.0), 12.0 - x)
    caps.append(kit.box("c", L - 0.06, 2.5, 0.45, at=(x + L / 2, 0, 3.35)))
    x += L
put("ParkWall", "WallCap", caps, bev=0.08)
iron = [kit.box("r1", 12, 0.18, 0.18, at=(0, 0, 3.1)), kit.box("r2", 12, 0.16, 0.16, at=(0, 0, 0.6))]
for k in range(20):
    xx = -5.7 + k * 0.6
    iron.append(kit.cyl("bar%d" % k, 0.05, 0.05, 3.0, at=(xx, 0, 1.9), segs=4))
    iron.append(kit.cyl("tip%d" % k, 0.12, 0.0, 0.4, at=(xx, 0, 3.55), segs=4))
for xx in (-5.85, 5.85):
    iron.append(kit.box("post", 0.35, 0.35, 3.5, at=(xx, 0, 1.75)))
    iron.append(kit.sphere("knob", 0.26, at=(xx, 0, 3.7), segs=8, rings=5))
put("ParkRail", "RailIron", iron, shade=False)

# ================================================================ reeds and lily pads by the water
blades, heads = [], []
for k in range(26):
    a, r = rng.uniform(0, 2 * math.pi), rng.uniform(0, 1.4)
    x, y = r * math.cos(a), r * math.sin(a)
    h = rng.uniform(2.4, 4.0)
    lean = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0))
    blades.append(kit.tube_along("rd", [Vector((x, y, 0)), Vector((x, y, h * 0.6)) + lean * 0.5, Vector((x, y, h)) + lean], [0.06, 0.04, 0.01], segs=4))
    if k % 3 == 0:
        p = Vector((x, y, h * 0.8)) + lean * 0.8
        heads.append(kit.cyl("hd", 0.13, 0.13, 0.6, at=tuple(p), segs=6))
put("Reeds", "Reeds", blades, shade=False)
put("Reeds", "ReedHeads", heads)
pads, flowers = [], []
for k in range(7):
    a, r = rng.uniform(0, 2 * math.pi), rng.uniform(0, 1.6)
    s = rng.uniform(0.5, 0.85)
    pts = [(s * math.cos(t), s * math.sin(t)) for t in [math.radians(20 + 340 * j / 14) for j in range(15)]] + [(0, 0)]
    pd = prism("pad", pts, 0, 0.05)
    rot_z(pd, rng.uniform(0, 360))
    kit.shift(pd, (r * math.cos(a), r * math.sin(a), 0))
    pads.append(pd)
    if k % 3 == 0:
        fl = kit.loft("fl", [(0.05, 0.12, 0.12, 0, 0), (0.25, 0.28, 0.28, 0, 0), (0.4, 0.18, 0.18, 0, 0)], segs=8, power=2)
        kit.shift(fl, (r * math.cos(a), r * math.sin(a), 0))
        flowers.append(fl)
put("LilyPads", "LilyPads", pads, shade=False)
put("LilyPads", "LilyFlowers", flowers, flat=True)

# ================================================================ the rowboat (4 wide, 11 long)
hull = kit.loft("hull", [(0.0, 0.4, 2.6, 0, 0), (0.4, 1.3, 4.6, 0, 0), (1.0, 1.85, 5.4, 0, 0), (1.5, 2.0, 5.6, 0, 0)], segs=28, power=2.0, cap=(True, False))
solidify(hull, 0.16)
gun = kit.loft("gun", [(1.42, 2.05, 5.65, 0, 0), (1.6, 2.08, 5.68, 0, 0)], segs=28, power=2.0, cap=(False, False))
solidify(gun, 0.12)
put("Rowboat", "RowHull", [hull, gun])
put("Rowboat", "RowSeats", [kit.box("t%d" % k, 3.2 - abs(k) * 0.7, 0.8, 0.14, at=(0, k * 2.8, 1.05)) for k in (-1, 0, 1)], bev=0.04)
oars = []
for side in (-1, 1):
    o = kit.tube_along("oar", [Vector((side * 0.6, 0.6, 1.3)), Vector((side * 3.6, -0.6, 0.6))], [0.07, 0.07], segs=5)
    bl = kit.box("blade", 0.12, 0.9, 0.5, at=(side * 3.8, -0.75, 0.5))
    oars += [o, bl]
put("Rowboat", "RowOars", oars)

# ================================================================ the duck (1.4 long), the dog (3.2 long)
db = kit.loft("db", [(0.0, 0.18, 0.3, 0, -0.05), (0.18, 0.36, 0.6, 0, 0), (0.42, 0.34, 0.55, 0, -0.02), (0.6, 0.16, 0.3, 0, -0.15), (0.68, 0.04, 0.08, 0, -0.55)], segs=12, power=2)
put("Duck", "DuckBody", [db])
put("Duck", "DuckHead", [kit.sphere("dh", 0.22, at=(0, 0.42, 0.82), segs=10, rings=7), kit.tube_along("dn", [Vector((0, 0.35, 0.45)), Vector((0, 0.42, 0.75))], [0.13, 0.12], segs=8)])
put("Duck", "DuckBill", [kit.loft("bill", [(0, 0.1, 0.06, 0, 0), (0.25, 0.08, 0.04, 0, 0)], segs=8, power=2)])
for v in looks["Duck"]["DuckBill"].data.vertices:
    v.co = Vector((v.co.x, 0.6 + v.co.z, 0.78 + v.co.y))
dbody = kit.loft("dgb", [(-1.2, 0.35, 0.4, 0, 0.05), (-0.8, 0.5, 0.55, 0, 0), (0.3, 0.52, 0.6, 0, 0.05), (1.0, 0.45, 0.55, 0, 0), (1.25, 0.25, 0.3, 0, -0.05)], segs=12, power=2.2)
for v in dbody.data.vertices:
    v.co = Vector((v.co.x, v.co.z, 1.5 + v.co.y))
put("Dog", "DogBody", [dbody])
dh = [kit.sphere("skull", 0.42, at=(0, 1.45, 2.05), segs=12, rings=8), kit.loft("snout", [(0, 0.24, 0.22, 0, 0), (0.45, 0.2, 0.17, 0, -0.04)], segs=8, power=2)]
for v in dh[1].data.vertices:
    v.co = Vector((v.co.x, 1.75 + v.co.z, 1.95 + v.co.y))
for side in (-1, 1):
    ear = kit.loft("ear", [(0, 0.16, 0.06, 0, 0), (0.45, 0.13, 0.05, 0, 0), (0.6, 0.04, 0.02, 0, 0)], segs=6, power=2)
    for v in ear.data.vertices:
        v.co = Vector((side * (0.34 + v.co.z * 0.25) + v.co.x, 1.4 + v.co.y, 2.35 - v.co.z * 0.9))
    dh.append(ear)
dh.append(kit.sphere("nose", 0.08, at=(0, 2.22, 1.95), segs=6, rings=4))
put("Dog", "DogHead", dh)
put("Dog", "DogLeg", [kit.tube_along("leg", [Vector((0.3, 0.8, 1.25)), Vector((0.3, 0.83, 0.6)), Vector((0.3, 0.8, 0.12))], [0.15, 0.12, 0.13], segs=8),
                      kit.sphere("paw", 0.15, at=(0.3, 0.87, 0.1), scale=(1, 1.3, 0.6), segs=8, rings=5)])
put("Dog", "DogTail", [kit.tube_along("tail", [Vector((0, -1.15, 1.7)), Vector((0, -1.45, 2.1)), Vector((0, -1.5, 2.55))], [0.11, 0.09, 0.04], segs=6)])

# ================================================================ a picnic: blanket, its checks, a basket
bl = kit.box("blanket", 6.0, 5.0, 0.06, at=(0, 0, 0.05))
m = bl.modifiers.new("Sub", "SUBSURF")
m.levels = 3
m.subdivision_type = "SIMPLE"
jitter(bl, 0.05, 0.8, 4)
put("Picnic", "Blanket", [bl], shade=False)
checks = []
for i in range(6):
    for j in range(5):
        if (i + j) % 2 == 0:
            checks.append(kit.box("ck", 0.98, 0.98, 0.02, at=(-2.5 + i, -2.0 + j, 0.1)))
put("Picnic", "BlanketCheck", checks, shade=False)
basket = [kit.box("bk", 1.6, 1.1, 0.9, at=(1.8, 1.4, 0.55)), kit.box("lid", 1.7, 1.2, 0.12, at=(1.8, 1.4, 1.05))]
basket.append(arc_tube("handle", 0.6, 0.06, 1.4, zscale=1.0, z0=1.1, segs=10, csegs=4))
kit.shift(basket[-1], (1.8, 0, 0))
put("Picnic", "Basket", basket, bev=0.05)

# ================================================================ a busker's guitar and its open case
gb = kit.loft("gb", [(0, 0.45, 0.16, 0, 0), (0.45, 0.62, 0.17, 0, 0), (0.95, 0.38, 0.16, 0, 0), (1.35, 0.5, 0.16, 0, 0), (1.75, 0.36, 0.15, 0, 0), (1.95, 0.08, 0.1, 0, 0)], segs=16, power=2)
put("Guitar", "GuitarBody", [gb])
put("Guitar", "GuitarNeck", [kit.box("neck", 0.18, 0.12, 1.6, at=(0, 0, 2.7)), kit.box("head", 0.3, 0.12, 0.45, at=(0, 0, 3.7))])
put("GuitarCase", "CaseShell", [ring_wall("case", rounded_rect(1.4, 4.0, 0.5), rounded_rect(1.2, 3.8, 0.4), 0, 0.5), kit.box("cb", 1.4, 4.0, 0.06, at=(0, 0, 0.03))])
put("GuitarCase", "CaseLining", [kit.box("lin", 1.15, 3.75, 0.04, at=(0, 0, 0.1))], shade=False)


# ================================================================ sizes and offsets (Roblox axes: x, up, back)
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


rows = []
total = 0
for look in sorted(looks):
    rows.append("\t%s = {" % look)
    for name in sorted(looks[look]):
        ob = looks[look][name]
        lo, hi = bounds(ob)
        c, size = (lo + hi) / 2, hi - lo
        t = kit.tris(ob)
        total += t
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f } }, -- %d tris" % (
            name, size.x, size.z, size.y, c.x, c.z, -c.y, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/park.py: do not edit by hand.",
    "-- The city park's set (ReplicatedStorage.Art.Park): every look's pieces, each piece's size and its centre from",
    "-- the look's foot point in studs (x, up, back; a look faces -z). Shared.ParkLayout and Fx.ParkLife place them.",
    "return {",
] + rows + ["}", ""])
with open(os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "ParkArt.luau")), "w") as f:
    f.write(text)
print("park set:", total, "tris,", sum(len(v) for v in looks.values()), "meshes")
for look in sorted(looks):
    for name, ob in looks[look].items():
        if kit.tris(ob) > 19000:
            raise SystemExit("too many triangles in " + name)

if "--no-export" not in sys.argv:
    export = []
    for look in looks:
        for name, ob in looks[look].items():
            cp = ob.copy()
            cp.data = ob.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Park.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    import park_preview  # noqa: E402

    park_preview.kit_sheet(looks)
