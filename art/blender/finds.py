# finds.py: the collection finds you pick up in the world as Blender meshes (list-combat 2026-11-20, Everything Left
# 335: "collection finds are glowing balls with default sparkles"). One small figure per world set (Config.Collect),
# drawn about its own centre in Roblox axes (x, up, z; front -z), about 2 studs tall:
#   ComicCovers  a comic book standing half open, a red cover with a yellow star burst (Find_Comic*)
#   LostToys     a tin wind-up rocket on three fins, a round window and its key (Find_Toy*)
#   ShipBells    a brass ship's bell under its yoke, the clapper showing (Find_Bell*)
#   DeepRelics   an old barnacled brass diving helmet with three glass ports (Find_Relic*)
#   RoofPigeons  a round cartoon pigeon figurine on a little plinth (Find_Pigeon*)
#   CometShards  the Star Charm: a chunky five-point star on a silver loop (Find_Charm*)
# Each find is a few meshes (one colour and material each) placed from Config.FindArt (size and centre offset from the
# find's centre). Client.CollectClient draws them bobbing and turning, with the set's sparkles and light.
# Output: art/export/Finds.fbx and src/config/FindArt.luau (generated); --preview renders art/preview/finds.png.
# Run: ~/tools/bpyenv/bin/python art/blender/finds.py [--preview] [--no-export]
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

BRASS = (222, 176, 72)
SILVER = (205, 210, 220)
PAPER = (246, 240, 222)


# ---------------------------------------------------------------- a comic book standing open like a tent
def comic():
    # the spine toward you, both covers swinging back from it (a V seen from above), the star bursts outside
    covers, pages, marks = [], [], []
    for s in (-1, 1):
        parts = [
            (covers, B(1.1, 1.6, 0.06, s * 0.55, 0, 0, bev=0.02)),
            (pages, B(1.0, 1.48, 0.1, s * 0.52, 0, 0.08)),
            (marks, star(0.34, 0.16, 0.04, s * 0.58, -0.12, -0.05, points=8)),
            (marks, B(0.86, 0.22, 0.04, s * 0.55, 0.56, -0.05)),
        ]
        for into, o in parts:
            turn(o, "up", -s * 55)
            into.append(o)
    covers.append(C(0.07, 1.6, 0, 0, 0, segs=8))
    mesh("ComicCovers", "Find_ComicCover", covers, (230, 60, 60), "SmoothPlastic")
    mesh("ComicCovers", "Find_ComicPages", pages, PAPER, "SmoothPlastic")
    mesh("ComicCovers", "Find_ComicStar", marks, (255, 220, 60), "SmoothPlastic")


# ---------------------------------------------------------------- a tin wind-up rocket
def toy():
    body = rings_mesh([[(math.cos(2 * math.pi * k / 16) * r, y, math.sin(2 * math.pi * k / 16) * r) for k in range(16)]
                       for (y, r) in ((-0.75, 0.3), (-0.6, 0.42), (-0.1, 0.46), (0.35, 0.4), (0.7, 0.22),
                                      (0.9, 0.05))])
    mesh("LostToys", "Find_ToyBody", body, (250, 150, 40), "SmoothPlastic")
    fins = []
    for k in range(3):
        poly = ((0.3, -0.98), (0.74, -1.0), (0.66, -0.7), (0.3, -0.1))  # a swept fin, root on the body
        f = rings_mesh([[(x, y, -0.04) for (x, y) in poly], [(x, y, 0.04) for (x, y) in poly]])
        turn(f, "up", k * 120 + 90)
        fins.append(f)
    fins.append(TOR(0.44, 0.04, 0, 0.3, 0, segs=20, csegs=5))
    mesh("LostToys", "Find_ToyFins", fins, (225, 55, 55), "SmoothPlastic")
    win = C(0.16, 0.08, 0, 0.12, -0.46, segs=14, axis="z")
    mesh("LostToys", "Find_ToyWindow", win, (140, 210, 255), "Glass")
    key = [C(0.04, 0.3, 0.55, -0.15, 0, segs=6, axis="x")]
    for s in (-1, 1):
        key.append(S(0.15, 0.74, -0.15 + s * 0.16, 0, sc=(0.35, 1, 1), segs=10, rings=6))
    mesh("LostToys", "Find_ToyKey", key, SILVER, "Metal")


# ---------------------------------------------------------------- a brass ship's bell under its yoke
def bell():
    prof = ((-0.7, 0.62), (-0.62, 0.66), (-0.5, 0.6), (-0.1, 0.48), (0.3, 0.42), (0.52, 0.38), (0.6, 0.3), (0.64, 0.1))
    shell = rings_mesh([[(math.cos(2 * math.pi * k / 20) * r, y, math.sin(2 * math.pi * k / 20) * r)
                         for k in range(20)] for (y, r) in prof])
    lip = TOR(0.64, 0.05, 0, -0.66, 0, segs=24, csegs=5)
    band = TOR(0.47, 0.035, 0, -0.1, 0, segs=24, csegs=4)
    mesh("ShipBells", "Find_Bell", [shell, lip, band], BRASS, "Metal")
    yoke = [B(1.9, 0.14, 0.24, 0, 0.82, 0, bev=0.04)]
    for s in (-1, 1):
        yoke.append(B(0.14, 0.95, 0.2, s * 0.88, 0.4, 0, bev=0.03))
    yoke.append(C(0.07, 0.25, 0, 0.62, 0, segs=8))
    yoke.append(B(0.3, 0.08, 0.3, 0, 0.72, 0))
    mesh("ShipBells", "Find_BellYoke", yoke, (110, 72, 44), "Wood")
    clap = [C(0.03, 0.75, 0, -0.38, 0, segs=6), S(0.12, 0, -0.78, 0, segs=10, rings=6)]
    mesh("ShipBells", "Find_BellClapper", clap, (80, 80, 88), "Metal")


# ---------------------------------------------------------------- a barnacled diving helmet
def relic():
    dome = S(0.62, 0, 0.12, 0, sc=(1, 1.05, 1), segs=18, rings=10)
    collar = C(0.6, 0.22, 0, -0.55, 0, segs=18, r2=0.5)
    base = C(0.7, 0.12, 0, -0.69, 0, segs=18)
    rims = [TOR(0.24, 0.06, 0, 0.12, -0.6, axis="z", segs=16, csegs=5)]
    for s in (-1, 1):
        rims.append(TOR(0.15, 0.05, s * 0.6, 0.12, 0, axis="x", segs=14, csegs=5))
    bolts = [S(0.05, math.cos(a) * 0.56, -0.48, math.sin(a) * 0.56, segs=6, rings=4)
             for a in [i * math.pi / 4 for i in range(8)]]
    mesh("DeepRelics", "Find_RelicHelmet", [dome, collar, base] + rims + bolts, (176, 140, 70), "Metal")
    glass = [C(0.2, 0.06, 0, 0.12, -0.6, segs=14, axis="z")]
    for s in (-1, 1):
        g = C(0.12, 0.06, s * 0.6, 0.12, 0, segs=12, axis="x")
        glass.append(g)
    mesh("DeepRelics", "Find_RelicGlass", glass, (110, 230, 215), "Glass")
    barn = []
    for i, (x, y, z) in enumerate(((0.38, 0.45, 0.28), (-0.45, 0.3, 0.3), (0.2, -0.3, 0.5), (-0.3, 0.55, -0.15),
                                   (0.5, -0.1, 0.25), (-0.15, 0.62, 0.3))):
        r = 0.09 + (i % 3) * 0.025
        barn.append(C(r, r * 1.1, x, y, z, segs=8, r2=r * 0.45))
    mesh("DeepRelics", "Find_RelicBarnacles", barn, (234, 226, 200), "Slate")


# ---------------------------------------------------------------- a round pigeon figurine on a plinth
def pigeon():
    body = S(0.5, 0, -0.05, 0.08, sc=(0.85, 0.82, 1.15), segs=16, rings=10)
    tail = rings_mesh([[(-0.16, 0.0, 0.55), (0.16, 0.0, 0.55), (0.12, 0.08, 0.55), (-0.12, 0.08, 0.55)],
                       [(-0.24, -0.12, 0.95), (0.24, -0.12, 0.95), (0.2, -0.06, 0.95), (-0.2, -0.06, 0.95)]])
    wings = []
    for s in (-1, 1):
        wings.append(S(0.36, s * 0.38, 0.0, 0.18, sc=(0.25, 0.6, 1.0), segs=12, rings=8))
    mesh("RoofPigeons", "Find_PigeonBody", [body, tail] + wings, (150, 156, 180), "SmoothPlastic")
    head = S(0.27, 0, 0.55, -0.32, segs=14, rings=8)
    neck = S(0.3, 0, 0.3, -0.22, sc=(0.95, 0.9, 0.85), segs=14, rings=8)
    mesh("RoofPigeons", "Find_PigeonNeck", [head, neck], (96, 150, 140), "SmoothPlastic")
    beak = C(0.07, 0.2, 0, 0.53, -0.58, segs=8, r2=0.0, axis="z")
    feet = [C(0.06, 0.22, s * 0.16, -0.62, 0.0, segs=6) for s in (-1, 1)]
    mesh("RoofPigeons", "Find_PigeonBeak", [beak] + feet, (250, 170, 60), "SmoothPlastic")
    eyes = [S(0.06, s * 0.2, 0.62, -0.47, segs=8, rings=6) for s in (-1, 1)]
    plinth = C(0.55, 0.16, 0, -0.78, 0.05, segs=18, r2=0.5)
    mesh("RoofPigeons", "Find_PigeonPlinth", [plinth] + eyes, (40, 40, 48), "SmoothPlastic")


# ---------------------------------------------------------------- the Star Charm
def charm():
    st = star(0.78, 0.36, 0.3, 0, -0.12, 0, points=5)
    kit.bevel(st, 0.06, 1)
    kit.apply_all(st)
    mesh("CometShards", "Find_CharmStar", st, (160, 140, 255), "Neon")
    loop = [TOR(0.17, 0.045, 0, 0.82, 0, axis="z", segs=16, csegs=5), C(0.08, 0.14, 0, 0.62, 0, segs=10)]
    mesh("CometShards", "Find_CharmLoop", loop, SILVER, "Metal")


for fn in (comic, toy, bell, relic, pigeon, charm):
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
    rows.append("\t%s = {" % look)
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rgb, mat, _ = INFO[name]
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d },"
                    " mat = \"%s\", tris = %d }," % (name, max(size.x, 0.02), max(size.z, 0.02), max(size.y, 0.02),
                                                    c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/finds.py: do not edit by hand.",
    "-- The collection finds as meshes (ReplicatedStorage.Art.Finds, Client.CollectClient): world set -> each mesh's",
    "-- size and centre from the find's centre (studs, x, up, z), colour, material and triangles. %d meshes, %d"
    " triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "FindArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("finds: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Finds.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1600, 520), samples=32)
    for k, look in enumerate(sorted(LOOKS)):
        for name, ob in LOOKS[look].items():
            rgb, mat, _ = INFO[name]
            ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.6 if mat == "Metal" else 0,
                                                  emit=2.0 if mat == "Neon" else 0.0))
            ob.location = (5.5 - k * 2.2, 0, 1.1)  # seen from the front (-z is Blender +y)
    kit.camera((0, 16, 3.0), (0, 0, 1.0), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "finds.png"))
