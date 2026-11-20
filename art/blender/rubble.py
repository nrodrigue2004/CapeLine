# rubble.py: a collapsed building's rubble heaps as Blender meshes (list-combat 2026-11-20, Everything Left 291:
# "building chunks and rubble are plain boxes"). Four heaps of broken floor slabs and concrete lumps, each with its
# own bent rebar, drawn in a 4 x 2 x 4 box: the game stretches each to the box Shared.Chunker gives the heap (so a heap
# stays exactly where it stood, the same size), in the building's colour and kit material; the rebar stays rusty steel.
# Output: art/export/Rubble.fbx, src/config/RubbleArt.luau (generated); --preview renders art/preview/rubble.png.
# Run: ~/tools/bpyenv/bin/python art/blender/rubble.py [--preview] [--no-export]
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

CONCRETE = (170, 166, 158)
REBAR = (120, 70, 48)


def chip(ob, rnd, cuts=3):
    """Knock corners off a block: a few random plane cuts through it near its surface."""
    kit.apply_all(ob)
    vs = ob.data.vertices
    c = Vector((sum(v.co.x for v in vs), sum(v.co.y for v in vs), sum(v.co.z for v in vs))) / len(vs)
    span = max((v.co - c).length for v in vs)
    for _ in range(cuts):
        n = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.2, 1))).normalized()
        shift(ob, tuple(-(c + n * span * rnd.uniform(0.45, 0.7))))
        kit.cut(ob, n, keep_positive=False)
        shift(ob, tuple(c + n * span * rnd.uniform(0.45, 0.7)))
    return ob


def slab(rnd, w, d, t, at, tilt):
    ob = B(w, t, d, 0, 0, 0)
    chip(ob, rnd, 3)
    turn(ob, "x", tilt[0])
    turn(ob, "z", tilt[1])
    turn(ob, "up", tilt[2])
    shift(ob, rb(*at))
    return ob


def lump(rnd, s, at):
    ob = B(s, s * rnd.uniform(0.6, 0.9), s * rnd.uniform(0.7, 1.1), 0, 0, 0)
    chip(ob, rnd, 4)
    turn(ob, "up", rnd.uniform(0, 90))
    turn(ob, "x", rnd.uniform(-20, 20))
    shift(ob, rb(*at))
    return ob


for k in range(4):
    rnd = random.Random(100 + k)
    parts = []
    # broken floor slabs leaning on each other, a pile of lumps between them
    for i in range(3):
        a = i * 2.1 + k
        parts.append(slab(rnd, rnd.uniform(1.6, 2.6), rnd.uniform(1.2, 2.0), 0.28,
                          (math.cos(a) * 0.8, rnd.uniform(0.25, 0.9), math.sin(a) * 0.8),
                          (rnd.uniform(-35, 35), rnd.uniform(-35, 35), rnd.uniform(0, 180))))
    for i in range(7):
        a = rnd.uniform(0, math.pi * 2)
        r = rnd.uniform(0.0, 1.5)
        s = rnd.uniform(0.45, 0.9) * (1.2 - r * 0.3)
        parts.append(lump(rnd, s, (math.cos(a) * r, s * 0.35 + (1.5 - r) * 0.35, math.sin(a) * r)))
    base = S(1.0, 0, 0, 0, sc=(1.9, 0.55, 1.9), segs=10, rings=6)
    parts.append(base)
    ob = kit.join("Rubble%d" % (k + 1), parts, shade=False)
    # the heap sits on its box's floor: cut what is under it
    kit.cut(ob, (0, 0, 1), keep_positive=True)
    mesh("Rubble%d" % (k + 1), "Rubble%d" % (k + 1), [ob], CONCRETE, "Concrete", shade=False)
    bars = []
    for i in range(3 + k % 2):
        a = rnd.uniform(0, math.pi * 2)
        x, z = math.cos(a) * rnd.uniform(0.2, 1.2), math.sin(a) * rnd.uniform(0.2, 1.2)
        top = (x + math.cos(a) * 0.5, rnd.uniform(1.4, 2.0), z + math.sin(a) * 0.5)
        bend = (top[0] + rnd.uniform(-0.6, 0.6), top[1] + rnd.uniform(-0.2, 0.25), top[2] + rnd.uniform(-0.6, 0.6))
        bars.append(T([(x, 0.4, z), top, bend], [0.05, 0.05, 0.04], segs=5))
    mesh("Rubble%d" % (k + 1), "Rubble%dRebar" % (k + 1), bars, REBAR, "Metal")


# loose chunks (list-combat 2026-11-20, Tasks "Destruction (M5)": "building chunks are plain boxes"): three broken
# blocks, a 2 x 2 x 2 box with its corners and edges knocked off and one face torn, that BuildingFx stretches to a
# knocked-out pillar's or slab's box (and throws small ones off a wall panel), in the building's colour and material
for k in range(3):
    rnd = random.Random(300 + k)
    ob = B(2.0, 2.0, 2.0, 0, 0, 0)
    chip(ob, rnd, 5 + k)
    # a torn face: a few shallow cuts across one side
    for _ in range(3):
        n = Vector((rnd.uniform(0.7, 1.0), rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5))).normalized()
        d = rnd.uniform(0.62, 0.85)
        shift(ob, tuple(-n * d))
        kit.cut(ob, n, keep_positive=False)
        shift(ob, tuple(n * d))
    mesh("Chunk%d" % (k + 1), "Chunk%d" % (k + 1), [ob], CONCRETE, "Concrete", shade=False)


# the knocked-over crowd barrier (list-combat 2026-11-20, the Ceremony prologue's run: PrologueFx "barrier", was a
# yellow box with three dark bars): a sawhorse barricade, two yellow planks with black diagonal stripes on both faces,
# on splayed steel A-frame legs with a warning lamp on top. Drawn upright with its top plank filling a 9 x 2.4 x 0.6
# box (the part it dresses); the legs and lamp hang off that box at their own offsets.
YELLOW, INK, STEEL, LAMP = (250, 200, 40), (30, 30, 34), (140, 144, 150), (255, 140, 30)
planks, stripes = [], []
for y in (0.6, -0.6):  # two planks, a gap between
    planks.append(B(9.0, 1.0, 0.3, 0, y, 0, bev=0.05))
    for i in range(-4, 5):
        x = i * 1.1
        for side in (-1, 1):
            poly = [(x - 0.25, y - 0.5), (x + 0.15, y - 0.5), (x + 0.45, y + 0.5), (x + 0.05, y + 0.5)]
            if max(px for px, _ in poly) > 4.45 or min(px for px, _ in poly) < -4.45:
                continue
            z0 = side * 0.15
            z1 = side * 0.17
            stripes.append(rings_mesh([[(px, py, z0) for px, py in poly], [(px, py, z1) for px, py in poly]]))
mesh("Barrier", "Barrier", [kit.join("Barrier", planks, shade=False)], YELLOW, "SmoothPlastic", shade=False)
mesh("Barrier", "BarrierStripes", stripes, INK, "SmoothPlastic", shade=False)
legs = []
for x in (-3.6, 3.6):
    for side in (-1, 1):
        legs.append(T([(x, 1.1, 0), (x, -0.4, side * 0.6), (x, -2.4, side * 1.3)], [0.09, 0.09, 0.09], segs=6))
    legs.append(T([(x, -1.7, -1.0), (x, -1.7, 1.0)], [0.06, 0.06], segs=6))
    legs.append(B(0.5, 0.12, 0.5, x, 1.15, 0))
mesh("Barrier", "BarrierLegs", legs, STEEL, "Metal")
mesh("Barrier", "BarrierLamp", [C(0.28, 0.4, -3.6, 1.25, 0, segs=10), S(0.26, -3.6, 1.7, 0, segs=10, rings=6)], LAMP, "Neon")


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


# the box every heap is drawn for: its main mesh's bounds (the rebar's offset is kept from the same frame)
rows = []
total = 0
for look in sorted(LOOKS):
    main = LOOKS[look][look]
    blo, bhi = bounds(main)
    bc = (blo + bhi) / 2
    rows.append("\t%s = {" % look)
    rows.append("\t\tbox = { %.3f, %.3f, %.3f }," % (bhi.x - blo.x, bhi.z - blo.z, bhi.y - blo.y))
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rgb, mat, _ = INFO[name]
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\", tris = %d },"
                    % (name, size.x, size.z, size.y, c.x - bc.x, c.z - bc.z, -(c.y - bc.y), rgb[0], rgb[1], rgb[2], mat, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/rubble.py: do not edit by hand.",
    "-- A collapsed building's rubble heaps (ReplicatedStorage.Art.Rubble, Fx.BuildingFx): heap -> its drawn box (studs,",
    "-- x, up, z) and each mesh's size, centre from the box's centre, colour, material and triangles. %d meshes, %d triangles."
    % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "RubbleArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)
print("rubble: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Rubble.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1400, 600), samples=24)
    for k, look in enumerate(sorted(LOOKS)):
        for name, ob in LOOKS[look].items():
            rgb, mat, _ = INFO[name]
            ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.5 if mat == "Metal" else 0, rough=0.8))
            if look == "Barrier":  # the barrier at the back, standing
                ob.location = (0, 8, 2.4)
            elif look.startswith("Chunk"):  # the loose chunks in a row in front
                ob.location = (int(look[5:]) * 4 - 8, -5, 1.2)
            else:
                ob.location = (int(look[6:]) * 5 - 12.5, 0, 0)
            ob.scale = (1, 1, 1)
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (90, 94, 100)))
    kit.camera((0, -22, 10), (0, 1, 0.6), lens=34)
    kit.render(os.path.join(kit.ROOT, "preview", "rubble.png"))
