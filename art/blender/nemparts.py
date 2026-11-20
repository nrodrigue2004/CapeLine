# nemparts.py: the rest of a nemesis head's and bust's pieces as Blender meshes (list-combat 2026-11-20, Everything
# Left 397: "the nemesis heads' eyes, domes, antennas and cannons are plain parts"). The WANTED poster's bust and the
# trophy heads (Shared.WantedRules, HqClient) cover each part with its shape's meshes (Shared.HqArtKit.SHAPES, look
# HqNemParts; Fx.HqMeshes.cover stretches them over the part, the first mesh in the part's own colour and material).
# Each drawn in its part's own frame (x, up, z; front -z):
#   NemEye      eye: a bevelled lens, 0.38 x 0.26 x 0.1
#   NemDome     dome: the glass brain dome (Ball) with NemDomeRibs, its metal collar and three ribs over the top
#   NemCyclops  cyclopsEye: the big glowing eye (Ball) in NemCyclopsHood, a metal shutter hood round it
#   NemNeck     neck: a ribbed neck with a collar, 0.9 x 0.8 x 0.9
#   NemPlates   plates: three overlapping chevron plates with rivets on the chest, 3.2 x 1.8 x 0.3
#   NemCannon   cannon: the shoulder cannon along +x (the part is a Cylinder turned to point forward): housing,
#               cooling rings, barrel and a slotted muzzle brake, 2.6 x 0.9 x 0.9
#   NemDrone    healDrone: the heal drone's glowing core with a plus on its face, and NemDroneFrame, its white
#               shell ring and two rotor pods (Ball 1 x 1 x 1)
#   NemAntenna  antenna: a segmented mast with collars and a ball tip, 0.2 x 2 x 0.2
# Output: art/export/NemParts.fbx and src/config/NemPartArt.luau (generated, HqArt's format: look -> mesh -> size,
# offset, colour, material, triangles); --preview renders art/preview/nemparts.png.
# Run: ~/tools/bpyenv/bin/python art/blender/nemparts.py [--preview] [--no-export]
import math
import os
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

L = "HqNemParts"
METAL = (90, 94, 104)
WHITE = (236, 238, 242)


def lathe_y(prof, segs=16, x=0.0, z=0.0):
    return rings_mesh([[(x + math.cos(2 * math.pi * k / segs) * r, y, z + math.sin(2 * math.pi * k / segs) * r)
                        for k in range(segs)] for (y, r) in prof])


def lathe_x(prof, segs=16):
    return rings_mesh([[(x, math.cos(2 * math.pi * k / segs) * r, math.sin(2 * math.pi * k / segs) * r)
                        for k in range(segs)] for (x, r) in prof])


def eye():
    # a rounded lens (a squashed capsule outline), bevelled toward the front
    def outline(w, h, n=20):
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            c, s = math.cos(a), math.sin(a)
            pts.append((w * math.copysign(abs(c) ** 0.6, c), h * math.copysign(abs(s) ** 0.6, s)))
        return pts

    rs = [[(x, y, z) for (x, y) in outline(w, h)] for (z, w, h) in ((0.05, 0.19, 0.13), (-0.02, 0.19, 0.13),
                                                                      (-0.05, 0.15, 0.09))]
    mesh(L, "NemEye", rings_mesh(rs), (255, 220, 90), "Neon", shade=False)


def dome():
    sph = S(0.5, segs=20, rings=12)
    mesh(L, "NemDome", sph, (200, 60, 60), "Glass")
    ribs = [TOR(0.47, 0.035, 0, -0.05, 0, segs=28, csegs=6)]
    for k in range(3):
        a = math.pi * k / 3
        pts = []
        for i in range(13):
            t = i / 12
            b = math.pi * t
            r = 0.505
            pts.append((math.cos(b) * r * math.cos(a), math.sin(b) * r - 0.0, math.cos(b) * r * math.sin(a)))
        ribs.append(T([(p[0], max(p[1], -0.05), p[2]) for p in pts], 0.02, segs=5))
    mesh(L, "NemDomeRibs", ribs, METAL, "Metal")


def cyclops():
    ball = S(0.4, segs=18, rings=12)
    mesh(L, "NemCyclops", ball, (255, 60, 50), "Neon")
    # the hood: a thick ring round the eye's front, a brow plate over it
    hood = [TOR(0.42, 0.07, 0, 0, -0.18, segs=24, csegs=6, axis="z"), B(0.85, 0.16, 0.5, 0, 0.4, -0.12, bev=0.04)]
    mesh(L, "NemCyclopsHood", hood, METAL, "Metal")


def neck():
    parts = [C(0.3, 0.8, 0, 0, 0, segs=14)]
    for y in (-0.15, 0.05, 0.25):
        parts.append(TOR(0.33, 0.06, 0, y, 0, segs=16, csegs=5))
    parts.append(C(0.45, 0.12, 0, -0.34, 0, segs=16, r2=0.38))
    mesh(L, "NemNeck", parts, METAL, "Metal")


def plates():
    parts = []
    for k, y in enumerate((0.55, 0.0, -0.55)):
        w = 1.6 - 0.15 * k
        # a chevron plate: a wide V pointing down, bevelled, each lower one a little in front
        poly = [(-w, 0.3), (w, 0.3), (w, -0.05), (0, -0.4), (-w, -0.05)]
        z = -0.05 - 0.05 * k
        ob = rings_mesh([[(x, y + yy, z + 0.08) for (x, yy) in poly], [(x, y + yy, z - 0.08) for (x, yy) in poly]])
        parts.append(ob)
        for sx in (-1, 1):
            parts.append(S(0.06, sx * (w - 0.18), y + 0.15, z - 0.09, segs=8, rings=5))
    mesh(L, "NemPlates", parts, (120, 124, 134), "DiamondPlate", shade=False)


def cannon():
    parts = [B(0.7, 0.85, 0.85, -0.95, 0, 0, bev=0.08)]  # the housing at the back
    parts.append(lathe_x([(-0.6, 0.3), (1.2, 0.26)], 16))  # the barrel
    for x in (-0.45, -0.25, -0.05):
        parts.append(lathe_x([(x - 0.06, 0.38), (x + 0.06, 0.38)], 16))
    # the muzzle brake: a block with slots each side
    parts.append(lathe_x([(1.0, 0.36), (1.3, 0.36)], 8))
    for sz in (-1, 1):
        parts.append(B(0.2, 0.5, 0.06, 1.15, 0, sz * 0.38))
    mesh(L, "NemCannon", parts, METAL, "Metal")


def drone():
    core = S(0.3, segs=16, rings=10)
    plus = [B(0.24, 0.07, 0.06, 0, 0, -0.31), B(0.07, 0.24, 0.06, 0, 0, -0.31)]
    mesh(L, "NemDrone", [core] + plus, (120, 255, 140), "Neon")
    frame = [TOR(0.38, 0.05, 0, 0, 0, segs=24, csegs=6)]
    for sx in (-1, 1):
        frame.append(C(0.06, 0.2, sx * 0.42, 0, 0, segs=8, axis="x"))
        frame.append(C(0.1, 0.06, sx * 0.5, 0.06, 0, segs=12))  # a rotor pod
        frame.append(B(0.08, 0.02, 0.22, sx * 0.5, 0.12, 0))  # its blade
    mesh(L, "NemDroneFrame", frame, WHITE, "SmoothPlastic")


def antenna():
    parts = [lathe_y([(-1.0, 0.07), (0.85, 0.04)], 8)]
    for y in (-0.9, -0.3, 0.3):
        parts.append(lathe_y([(y - 0.04, 0.1), (y + 0.04, 0.1)], 8))
    parts.append(S(0.1, 0, 0.9, 0, segs=10, rings=6))
    mesh(L, "NemAntenna", parts, METAL, "Metal")


for fn in (eye, dome, cyclops, neck, plates, cannon, drone, antenna):
    fn()


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


rows = ["\t%s = {" % L]
total = 0
for name in sorted(LOOKS[L]):
    ob = LOOKS[L][name]
    lo, hi = bounds(ob)
    c = (lo + hi) / 2
    size = hi - lo
    t = kit.tris(ob)
    total += t
    rgb, mat, alpha = INFO[name]
    rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, "
                "mat = \"%s\", tris = %d }," % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x,
                                               c.z, -c.y, rgb[0], rgb[1], rgb[2], mat, t))
rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/nemparts.py: do not edit by hand.",
    "-- A nemesis head's and bust's other pieces in Blender meshes (ReplicatedStorage.Art.NemParts; Shared.HqArtKit.SHAPES",
    "-- eye, dome, cyclopsEye, neck, plates, cannon, healDrone, antenna): look -> mesh -> its size and centre in its",
    "-- part's frame, in studs (x, up, z; front at -z), its colour, material and triangles.",
    "-- %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "NemPartArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("nemparts: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for name, ob in LOOKS[L].items():
        cp = copy(ob)
        kit.centre(cp)
        cp.name = name
        cp.data.name = name
        export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "NemParts.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1600, 600), samples=32)
    for name, ob in LOOKS[L].items():
        rgb, mat, _ = INFO[name]
        ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.6 if mat == "Metal" else 0,
                                              emit=0.8 if mat == "Neon" else 0.0))
    spots = {
        "NemEye": ((10.5, 0, 6), 4), "NemDome": ((-8, 0, 3), 2.5), "NemDomeRibs": ((-8, 0, 3), 2.5),
        "NemCyclops": ((-3.5, 0, 3), 2.5), "NemCyclopsHood": ((-3.5, 0, 3), 2.5), "NemNeck": ((0.5, 0, 3), 2.5),
        "NemPlates": ((5, 0, 3), 1.6), "NemCannon": ((10, 0, 3), 1.6), "NemDrone": ((-12, 0, 4.5), 2.2),
        "NemDroneFrame": ((-12, 0, 4.5), 2.2), "NemAntenna": ((-12, 0, 1.4), 1.2),
    }
    for name, ob in LOOKS[L].items():
        at, s = spots[name]
        ob.scale = (s, s, s)
        ob.location = at
        if name in ("NemCannon",):
            ob.rotation_euler = (0, 0, math.radians(-30))
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    kit.camera((-1, 24, 8), (-1, 0, 3.2), lens=34)  # from the front (Roblox -z is Blender +y)
    kit.render(os.path.join(kit.ROOT, "preview", "nemparts.png"))
