# guard.py: the block's looks as Blender meshes (list-combat 2026-11-20, Everything Left 384: "Block shield, robot
# block ball, shatter and perfect-block flashes are glowing discs and balls"). Each mesh is drawn in a unit box the
# game stretches (Fx.GuardFx), in Roblox's frame (x, up, z):
#   GuardFace   the held shield's face: a domed energy lens bulging to +x (the shield's own forward; GuardFx holds it
#               with +x out from the chest), with a raised hexagon and six spokes, 0.5 x 1 x 1
#   GuardRim    its eight-sided rim: a bevelled octagon frame with a diamond stud at each corner and an inner dashed
#               line, 0.3 x 1 x 1 (the colour runs from rim to low as your Guard drains)
#   GuardCore   the glowing core behind the face: a six-point hex emblem, 0.1 x 1 x 1
#   GuardBubble a robot's timed block (and the War-Frame's): a faceted geodesic shell with raised struts, 1 x 1 x 1
#   GuardShard  one shard of a shattered guard (eight fly out, spinning): a crystal splinter, 0.4 x 0.34 x 1
#   GuardFlash  the perfect block's (and the cut's) flash: a flat eight-point comic starburst, 1 x 1 x 0.06,
#               turned to face the camera
# Output: art/export/Guard.fbx and src/config/GuardArt.luau (generated); --preview renders art/preview/guard.png.
# Run: ~/tools/bpyenv/bin/python art/blender/guard.py [--preview] [--no-export]
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()
from studs import *  # noqa: E402,F401,F403
from studs import LOOKS, INFO  # noqa: E402

BLUE = (110, 180, 255)
RIM = (205, 235, 255)


def disc_ring(x, r, segs, phase=0.0):
    return [(x, math.cos(phase + 2 * math.pi * k / segs) * r, math.sin(phase + 2 * math.pi * k / segs) * r)
            for k in range(segs)]


# ---------------------------------------------------------------- the face: a dome bulging to +x
DOME = [(-0.25, 0.5), (-0.13, 0.5), (-0.05, 0.47), (0.04, 0.41), (0.12, 0.32), (0.18, 0.22), (0.22, 0.12),
        (0.25, 0.02)]


def dome_x(r):
    """The dome's front x at radius r (the profile above, linear between stations)."""
    pts = sorted([(rr, x) for (x, rr) in DOME[1:]])
    for (r0, x0), (r1, x1) in zip(pts, pts[1:]):
        if r0 <= r <= r1:
            return x0 + (x1 - x0) * (r - r0) / (r1 - r0)
    return DOME[1][0]


def face():
    lens = rings_mesh([disc_ring(x, r, 36) for (x, r) in DOME])
    parts = [lens]
    hexr = 0.27
    corners = []
    for k in range(6):
        a = 2 * math.pi * k / 6
        corners.append((math.cos(a) * hexr, math.sin(a) * hexr))
    for k in range(6):
        (y0, z0), (y1, z1) = corners[k], corners[(k + 1) % 6]
        pts = []
        for t in (0.0, 0.5, 1.0):
            y, z = y0 + (y1 - y0) * t, z0 + (z1 - z0) * t
            pts.append((dome_x(math.hypot(y, z)) + 0.01, y, z))
        parts.append(T(pts, 0.022, segs=6))
        # a spoke from the corner out to the rim
        y, z = corners[k]
        sp = []
        for f in (1.0, 1.35, 1.7):
            yy, zz = y * f, z * f
            sp.append((dome_x(math.hypot(yy, zz)) + 0.01, yy, zz))
        parts.append(T(sp, 0.018, segs=6))
    mesh("Guard", "GuardFace", parts, BLUE, "ForceField")


# ---------------------------------------------------------------- the rim: an octagon frame
def rim():
    parts = []
    n = 8
    ro, ri = 0.47, 0.4
    half = 0.15

    def pt(a, r):
        return (math.sin(a) * r, math.cos(a) * r)  # (z, up) for prism

    for k in range(n):
        a0 = 2 * math.pi * (k - 0.5) / n
        a1 = 2 * math.pi * (k + 0.5) / n
        # the band as a convex quad, bevelled: a thin back plate and a taller front lip
        parts.append(prism([pt(a0, ri), pt(a0, ro), pt(a1, ro), pt(a1, ri)], -half, half * 0.4))
        parts.append(prism([pt(a0, ri + 0.02), pt(a0, ro - 0.015), pt(a1, ro - 0.015), pt(a1, ri + 0.02)],
                           half * 0.4, half))
        # a diamond stud on the corner, standing proud of the front
        c = a1
        cz, cy = pt(c, (ro + ri) / 2)
        d = 0.05
        parts.append(rings_mesh([
            [(half * 0.6, cy + d, cz), (half * 0.6, cy, cz + d), (half * 0.6, cy - d, cz), (half * 0.6, cy, cz - d)],
            [(half * 1.0, cy + d * 0.4, cz), (half * 1.0, cy, cz + d * 0.4), (half * 1.0, cy - d * 0.4, cz),
             (half * 1.0, cy, cz - d * 0.4)],
        ]))
        # the outer corner tip, a little wedge that makes the silhouette read as eight-sided
        tz, ty = pt(c, 0.5)
        lz, ly = pt(c - 0.12, ro)
        rz, ry = pt(c + 0.12, ro)
        parts.append(prism([(lz, ly), (tz, ty), (rz, ry)], -half * 0.8, half * 0.4))
        # the inner dashed line
        b0 = 2 * math.pi * (k - 0.25) / n
        b1 = 2 * math.pi * (k + 0.25) / n
        parts.append(prism([pt(b0, 0.36), pt(b0, 0.38), pt(b1, 0.38), pt(b1, 0.36)], -half * 0.5, half * 0.2))
    mesh("Guard", "GuardRim", parts, RIM, "Neon", shade=False)


# ---------------------------------------------------------------- the core: a hex emblem
def core():
    poly = []
    for i in range(12):
        a = math.pi / 2 + i * math.pi / 6
        r = 0.5 if i % 2 == 0 else 0.3
        poly.append((math.sin(a) * r, math.cos(a) * r))
    parts = [prism(poly, -0.05, 0.05)]
    mesh("Guard", "GuardCore", parts, BLUE, "Neon", shade=False)


# ---------------------------------------------------------------- the bubble: a geodesic shell with struts
def bubble():
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.47)
    shell = kit._obj("shell", bm)
    struts = copy(shell)
    for v in struts.data.vertices:
        v.co *= 1.04
    m = struts.modifiers.new("w", "WIREFRAME")
    m.thickness = 0.022
    m.offset = 0.0
    m.use_even_offset = True
    kit.apply_all(struts)
    mesh("Guard", "GuardBubble", [shell, struts], BLUE, "ForceField", shade=False)


# ---------------------------------------------------------------- a shard
def shard():
    # an uneven five-sided splinter, long along z, its widest point a third of the way back
    def ring(z, r, j):
        out = []
        for k in range(5):
            a = 2 * math.pi * k / 5 + j
            rr = r * (1.0 + 0.25 * math.sin(3 * k + 1.3))
            out.append((math.cos(a) * rr, math.sin(a) * rr * 0.85, z))
        return out

    sp = rings_mesh([ring(-0.5, 0.01, 0), ring(-0.15, 0.17, 0.2), ring(0.12, 0.12, 0.35), ring(0.5, 0.012, 0.5)])
    mesh("Guard", "GuardShard", sp, RIM, "Glass", shade=False)


# ---------------------------------------------------------------- the flash: a comic starburst
def flash():
    poly = []
    n = 8
    for i in range(n * 2):
        a = math.pi / 2 + i * math.pi / n
        r = 0.5 if i % 2 == 0 else (0.24 if i % 4 == 1 else 0.3)
        poly.append((math.cos(a) * r, math.sin(a) * r))
    st = rings_mesh([[(x, y, -0.03) for (x, y) in poly], [(x, y, 0.03) for (x, y) in poly]])
    mesh("Guard", "GuardFlash", st, (255, 240, 140), "Neon", shade=False)


for fn in (face, rim, core, bubble, shard, flash):
    fn()


# ================================================================ the fit table and the export
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


rows = []
total = 0
for look in sorted(LOOKS):
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rows.append('\t%s = { size = { %.3f, %.3f, %.3f }, tris = %d },' % (name, size.x, size.z, size.y, t))
text = "\n".join([
    "-- GENERATED by art/blender/guard.py: do not edit by hand.",
    "-- The block's looks as meshes (ReplicatedStorage.Art.Guard, Fx.GuardFx): the held shield's face, rim and core,",
    "-- the robots' block bubble, the shatter's shard and the perfect block's flash, each drawn in its box (x, up, z)",
    "-- and its triangles. %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "GuardArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("guard: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Guard.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    # the held shield (face, rim, core at 6 studs, seen from its front-left), the robot bubble, shards, the flash
    kit.studio(res=(1600, 640), samples=32)
    G = LOOKS["Guard"]
    mats = {
        "GuardFace": kit.material("face", BLUE, emit=0.2),
        "GuardRim": kit.material("rim", (150, 210, 255), emit=0.8),
        "GuardCore": kit.material("core", (60, 140, 255), emit=0.8),
        "GuardBubble": kit.material("bub", BLUE, emit=0.2),
        "GuardShard": kit.material("shd", (170, 215, 255), emit=0.3),
        "GuardFlash": kit.material("fl", (255, 220, 80), emit=0.8),
    }
    for name, ob in G.items():
        ob.data.materials.append(mats[name])
    # Roblox +x (the shield's forward) faces the camera: Blender +x toward the camera at -y means turn 90 about up
    for name, dx in (("GuardFace", 0.0), ("GuardRim", 0.0), ("GuardCore", -0.7)):
        ob = G[name]
        ob.scale = (6, 6, 6)
        ob.rotation_euler = (0, 0, math.radians(-90 + 25))
        ob.location = (-8 + dx * 0.4, 0, 4)
    G["GuardBubble"].scale = (5, 5, 5)
    G["GuardBubble"].location = (-0.5, 0, 3.5)
    sh = G["GuardShard"]
    sh.scale = (2, 2, 2)
    sh.location = (6, 0, 5.5)
    sh.rotation_euler = (0.5, 0.3, 0.9)
    for k in range(5):
        c = copy(sh)
        a = 2 * math.pi * k / 5
        c.location = (6 + math.cos(a) * 1.8, 0, 4 + math.sin(a) * 1.8)
        c.rotation_euler = (a, 0.4 * k, a * 0.7)
    fl = G["GuardFlash"]
    fl.scale = (5, 5, 5)
    fl.location = (10.5, 0, 4)
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    kit.camera((1.5, -24, 7), (1.5, 0, 4), lens=32)
    kit.render(os.path.join(kit.ROOT, "preview", "guard.png"))
