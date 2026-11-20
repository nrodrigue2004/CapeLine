# throw_meshes.py: the street throwables that were part builds, as Blender meshes (list-combat 2026-11-20, Everything
# Left 390: "Throwable props are single blocks"; the bench, bin, lamp post and vending machine already wear the street
# kit's meshes). Each kind is drawn standing on its foot at y = 0, centred in x and z, inside its Config.Throw.kinds
# box (x, up, z; front -z), in a few pieces of one colour each; Fx.ThrowFx welds them over the server's box (scaled
# to the box's height) and hides the box on this device:
#   mailbox   1.8 x 3.6 x 1.6: a blue street mailbox with a rounded top, a white band, a pull-down slot, a handle
#             and four short feet
#   sign      2.4 x 5 x 0.4: a steel post with clamp bands and a bolted yellow diamond warning sign (a black border
#             and a bold "!" in front)
#   dumpster  6 x 4 x 3.5: a green bin that flares to the top, ribbed sides, lifting pockets, a split dark lid and
#             four caster wheels
#   slab      8 x 2.4 x 6: a broken slab of road concrete, chipped edges, a crack and bent rebar out of its broken end
#   rubble    2.4 x 1.6 x 2: a heap of concrete and brick chunks with a bent bar
# Output: art/export/Throwables.fbx and src/config/ThrowArt.luau (generated: kind -> piece -> size, centre from the
# foot, colour, material, triangles); --preview renders art/preview/throwables_mesh.png.
# Run: ~/tools/bpyenv/bin/python art/blender/throw_meshes.py [--preview] [--no-export]
import math
import os
import random
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

kit.reset()
from studs import *  # noqa: E402,F401,F403
from studs import LOOKS, INFO  # noqa: E402

random.seed(17)
BLUE = (44, 82, 160)
NAVY = (24, 32, 52)
WHITE = (235, 235, 240)
GREEN = (46, 110, 70)
DGREEN = (30, 62, 42)
RUBBER = (25, 25, 28)
CONCRETE = (140, 136, 128)
RUST = (150, 80, 50)


def chunk(cx, cy, cz, sx, sy, sz, jit=0.18, sides=6):
    """An uneven concrete chunk: a jittered prism, narrower at the top."""
    bot, top = [], []
    for k in range(sides):
        a = 2 * math.pi * (k + random.uniform(-0.2, 0.2)) / sides
        rx = sx / 2 * (1 - random.uniform(0, jit))
        rz = sz / 2 * (1 - random.uniform(0, jit))
        bot.append((cx + math.cos(a) * rx, cy - sy / 2, cz + math.sin(a) * rz))
        f = random.uniform(0.7, 0.9)
        top.append((cx + math.cos(a) * rx * f, cy + sy / 2 - random.uniform(0, jit) * sy, cz + math.sin(a) * rz * f))
    return rings_mesh([bot, top])


def bar(points, r=0.07):
    return T(points, r, segs=6)


# ---------------------------------------------------------------- the mailbox
def mailbox():
    body = [B(1.76, 1.8, 1.56, 0, 1.8, 0, bev=0.06)]
    body.append(C(0.88, 1.56, 0, 2.7, 0, segs=20, axis="z"))  # the rounded top along the depth
    mesh("mailbox", "ThrowMailBody", body, BLUE, "Metal")
    trim = [B(1.8, 0.18, 1.6, 0, 1.25, 0)]
    trim.append(T([(-0.35, 2.42, -0.84), (-0.3, 2.5, -0.9), (0.3, 2.5, -0.9), (0.35, 2.42, -0.84)], 0.04, segs=6))
    mesh("mailbox", "ThrowMailTrim", trim, WHITE, "SmoothPlastic")
    dark = [B(1.0, 0.16, 0.08, 0, 2.2, -0.8)]  # the slot's lip
    for sx in (-1, 1):
        for sz in (-1, 1):
            dark.append(B(0.22, 0.9, 0.22, sx * 0.7, 0.45, sz * 0.6))
    dark.append(B(1.7, 0.12, 1.5, 0, 0.86, 0))
    mesh("mailbox", "ThrowMailDark", dark, NAVY, "Metal")


# ---------------------------------------------------------------- the sign
def sign():
    pole = [C(0.12, 4.4, 0, 2.2, 0.08, segs=10)]
    for y in (3.3, 4.2):
        pole.append(B(0.32, 0.12, 0.3, 0, y, 0.08))
    mesh("sign", "ThrowSignPole", pole, (120, 124, 130), "Metal")

    def diamond(r, z0, z1, y=3.8):
        return rings_mesh([[(0, y + r, z), (r, y, z), (0, y - r, z), (-r, y, z)] for z in (z0, z1)])

    back = [diamond(1.2, -0.1, -0.02)]
    # the "!": a tapering bar and a dot, in front of the face
    back.append(rings_mesh([[(-0.13, 4.4, z), (0.13, 4.4, z), (0.07, 3.6, z), (-0.07, 3.6, z)] for z in (-0.2, -0.16)]))
    back.append(C(0.1, 0.04, 0, 3.32, -0.18, segs=12, axis="z"))
    for y in (3.3, 4.2):  # bolts
        back.append(C(0.05, 0.05, 0, y, -0.16, segs=8, axis="z"))
    mesh("sign", "ThrowSignBack", back, (35, 35, 38), "SmoothPlastic")
    mesh("sign", "ThrowSignFace", diamond(1.06, -0.16, -0.1), (230, 190, 40), "SmoothPlastic")


# ---------------------------------------------------------------- the dumpster
def dumpster():
    # the bin flares a little toward the top (front -z, back +z)
    bot = [(-2.8, 0.6, -1.4), (2.8, 0.6, -1.4), (2.8, 0.6, 1.5), (-2.8, 0.6, 1.5)]
    top = [(-2.9, 3.4, -1.68), (2.9, 3.4, -1.68), (2.9, 3.4, 1.62), (-2.9, 3.4, 1.62)]
    body = [rings_mesh([bot, top])]
    for x in (-1.8, -0.6, 0.6, 1.8):  # ribs on the front and back
        body.append(B(0.22, 2.6, 0.12, x, 2.0, -1.62))
        body.append(B(0.22, 2.6, 0.12, x, 2.0, 1.6))
    body.append(B(5.9, 0.22, 3.4, 0, 3.35, -0.03))  # the top rim
    mesh("dumpster", "ThrowDumpBody", body, GREEN, "Metal")
    lid = []
    for sx in (-1, 1):
        q = [(sx * 0.05, 3.5, -1.7), (sx * 2.95, 3.5, -1.7), (sx * 2.95, 3.85, 1.68), (sx * 0.05, 3.85, 1.68)]
        lid.append(rings_mesh([q, [(x, y + 0.14, z) for (x, y, z) in q]]))
    for sx in (-1, 1):  # the lifting pockets on the ends
        lid.append(B(0.3, 0.4, 3.0, sx * 3.0, 2.6, 0))
    lid.append(B(5.7, 0.24, 3.0, 0, 0.62, 0.05))  # the floor frame
    mesh("dumpster", "ThrowDumpLid", lid, DGREEN, "Metal")
    wheels = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            wheels.append(C(0.3, 0.26, sx * 2.3, 0.3, sz * 1.15, segs=14, axis="x"))
            wheels.append(B(0.4, 0.3, 0.5, sx * 2.3, 0.62, sz * 1.15))
    mesh("dumpster", "ThrowDumpWheels", wheels, RUBBER, "Rubber")


# ---------------------------------------------------------------- the slab
def slab():
    # an uneven outline (front -z) with a broken right end, pushed up 2.4 with a chipped top edge
    out = [(-4.0, -2.8), (-1.0, -3.0), (2.2, -2.9), (3.4, -2.2), (3.0, -1.0), (3.9, 0.2), (3.3, 1.3), (3.8, 2.6),
           (1.0, 3.0), (-2.6, 2.9), (-4.0, 2.4), (-3.8, 0.0)]
    rs = []
    for (y, k) in ((0.0, 1.0), (1.9, 1.0), (2.4, 0.93)):
        rs.append([(x * k, y, z * k) for (x, z) in out])
    parts = [rings_mesh(rs)]
    parts.append(chunk(-3.1, 2.55, 2.1, 1.6, 0.5, 1.2))  # a loose chunk on top
    parts.append(chunk(-0.5, 2.45, -1.6, 1.2, 0.3, 0.9))
    mesh("slab", "ThrowSlabConcrete", parts, (128, 124, 118), "Concrete")
    rebar = []
    for z in (-1.6, -0.4, 0.8, 2.0):
        rebar.append(bar([(2.6, 1.0, z), (3.9, 1.05, z), (4.0, 1.4 + random.uniform(0, 0.6), z + random.uniform(-0.3, 0.3))]))
    # the crack across the top: a dark groove
    rebar.append(T([(-2.0, 2.41, -2.6), (-1.2, 2.41, -0.8), (-1.6, 2.41, 0.6), (-0.8, 2.41, 2.4)], 0.06, segs=4))
    mesh("slab", "ThrowSlabRebar", rebar, RUST, "Metal")


# ---------------------------------------------------------------- the rubble heap
def rubble():
    parts = [chunk(-0.4, 0.4, 0.1, 1.5, 0.8, 1.3), chunk(0.5, 0.35, -0.3, 1.2, 0.7, 1.1),
             chunk(0.1, 0.95, 0.15, 1.1, 0.6, 0.9), chunk(0.6, 0.3, 0.6, 0.9, 0.6, 0.7)]
    mesh("rubble", "ThrowRubbleChunks", parts, CONCRETE, "Concrete")
    bits = [chunk(-0.8, 0.22, -0.6, 0.6, 0.4, 0.4, sides=4), chunk(0.9, 0.2, 0.0, 0.5, 0.35, 0.4, sides=4),
            chunk(-0.2, 1.38, -0.1, 0.5, 0.3, 0.4, sides=4)]
    mesh("rubble", "ThrowRubbleBrick", bits, (170, 80, 60), "Brick")
    mesh("rubble", "ThrowRubbleBar", [bar([(-0.6, 0.6, 0.5), (0.0, 1.1, 0.3), (0.4, 1.5, 0.5)], 0.05)], RUST, "Metal")


for fn in (mailbox, sign, dumpster, slab, rubble):
    fn()


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


rows = []
total = 0
for look in sorted(LOOKS):
    rows.append("\t%s = {" % look)
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rgb, mat, _ = INFO[name]
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, "
                    "mat = \"%s\", tris = %d }," % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05),
                                                   c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/throw_meshes.py: do not edit by hand.",
    "-- The street throwables that were part builds, as meshes (ReplicatedStorage.Art.Throwables, Fx.ThrowFx): kind ->",
    "-- piece -> its size and its centre from the kind's foot, in studs (x, up, z; front at -z), its colour, material",
    "-- and triangles. %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "ThrowArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("throwables: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Throwables.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1600, 640), samples=32)
    xs = {"mailbox": -12, "sign": -8, "dumpster": -1.5, "slab": 7.5, "rubble": 14}
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            rgb, mat, _ = INFO[name]
            ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.5 if mat == "Metal" else 0))
            ob.location = (xs[look], 0, 0)
            ob.rotation_euler = (0, 0, math.radians(180 + 20))  # the front (Blender +y) turned toward the camera
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (150, 150, 158)))
    kit.camera((0, -26, 8), (1, 0, 2.2), lens=34)
    kit.render(os.path.join(kit.ROOT, "preview", "throwables_mesh.png"))
