# contest.py: the costume contest's stage as Blender meshes (list-combat 2026-11-20, Everything Left 337: "the contest
# stage, pads, podium and spotlight are plain parts"). Drawn in the stage's own frame (Roblox x, up, z; the deck's top
# centre at the origin, the podium and the arch at the back, +z), at Config.Contest.stage's size (26 x 2 x 26):
#   StageDeck    the deck: a rounded platform with a stepped skirt (its colour: the old stage's purple)
#   StageLip     the neon gold lip round its top edge
#   StageStars   gold stars along the skirt
#   StageArch    a silver truss arch over the podium: two lattice towers and a crossbeam
#   StageBoard   the marquee board hung from the crossbeam (ServerContest letters COSTUME CONTEST on it)
#   StageBulbs   the marquee's bulbs round the board (Neon)
#   StageCans    two spotlight cans on the crossbeam's ends, aimed at the deck
#   StagePad     one entry pad: a star on a ring (the game sets one on each pad, Neon gold)
#   PodiumStep   one podium block, 1 stud tall (the game stretches it to each step's height), with a gold rim
#   PodiumStar   the star plate on a step's front
#   SpotCone     the spotlight's beam: a soft cone, 1 x 1 x 1 (the client stretches it from a can to the contestant)
# Output: art/export/Stage.fbx and src/config/StageArt.luau (generated); --preview renders art/preview/contest_stage.png.
# Run: ~/tools/bpyenv/bin/python art/blender/contest.py [--preview] [--no-export]
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

PURPLE = (70, 60, 110)
NAVY = (40, 34, 74)
GOLD = (255, 205, 70)
SILVER = (200, 205, 216)
RED = (200, 40, 60)
S_ = 26.0  # the deck's size
H_ = 2.0  # its height


def rounded(w, d, r, n=4):
    """A rounded rectangle in (x, z), corners of radius r, n segments each."""
    pts = []
    for cx, cz, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180),
                       (w / 2 - r, -d / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


# ---------------------------------------------------------------- the deck, its lip and stars
top = rounded(S_, S_, 2.2)
skirt = rounded(S_ - 0.8, S_ - 0.8, 1.9)
deck = extrude_up(top, -0.5, 0.0)
base = extrude_up(skirt, -H_, -0.5)
mesh("Stage", "StageDeck", [deck, base], PURPLE, "SmoothPlastic")
ring = [(x, -0.12, z) for (x, z) in rounded(S_ - 0.05, S_ - 0.05, 2.2, 6)]
lip = T(ring + ring[:2], 0.2, segs=6)
mesh("Stage", "StageLip", lip, GOLD, "Neon")
stars = []
for i in range(5):
    x = -10 + i * 5
    for side in (-1, 1):  # front and back faces
        stars.append(star(0.5, 0.22, 0.12, x, -1.25, side * ((S_ - 0.8) / 2 + 0.04)))
    for side in (-1, 1):  # left and right faces
        st = star(0.5, 0.22, 0.12, 0, -1.25, 0)
        turn(st, "up", 90)
        shift(st, rb(side * ((S_ - 0.8) / 2 + 0.04), 0, x))
        stars.append(st)
mesh("Stage", "StageStars", stars, GOLD, "SmoothPlastic")

# ---------------------------------------------------------------- the truss arch over the podium (back edge, +z)
AZ = S_ / 2 - 1.2
TH = 18.0
arch = []
for s in (-1, 1):
    x = s * 11.5
    for dx in (-0.6, 0.6):
        for dz in (-0.6, 0.6):
            arch.append(C(0.12, TH, x + dx, TH / 2, AZ + dz, segs=6))
    for k in range(9):  # zigzag lattice on the inner and outer faces
        y0, y1 = k * 2.0, (k + 1) * 2.0
        for dz in (-0.6, 0.6):
            a = (x - 0.6 if k % 2 == 0 else x + 0.6, y0, AZ + dz)
            b = (x + 0.6 if k % 2 == 0 else x - 0.6, y1, AZ + dz)
            arch.append(T([a, b], 0.07, segs=5))
    arch.append(B(1.9, 0.3, 1.9, x, 0.15, AZ, bev=0.05))
for dy in (-0.6, 0.6):
    for dz in (-0.6, 0.6):
        arch.append(C(0.12, 24.2, 0, TH + dy, AZ + dz, segs=6, axis="x"))
for k in range(12):
    x0, x1 = -12 + k * 2, -10 + k * 2
    for dz in (-0.6, 0.6):
        a = (x0, TH - 0.6 if k % 2 == 0 else TH + 0.6, AZ + dz)
        b = (x1, TH + 0.6 if k % 2 == 0 else TH - 0.6, AZ + dz)
        arch.append(T([a, b], 0.07, segs=5))
mesh("Stage", "StageArch", arch, SILVER, "Metal")
board = [B(15, 3.6, 0.5, 0, TH - 3.2, AZ - 0.1, bev=0.1)]
for s in (-1, 1):
    board.append(C(0.06, 1.0, s * 6.5, TH - 0.9, AZ, segs=5))
mesh("Stage", "StageBoard", board, RED, "SmoothPlastic")
bulbs = []
for k in range(14):
    x = -7.0 + k * (14.0 / 13)
    for y in (TH - 1.15, TH - 5.25):
        bulbs.append(S(0.2, x, y, AZ - 0.4, segs=8, rings=5))
for y in (TH - 2.5, TH - 3.9):
    for s in (-1, 1):
        bulbs.append(S(0.2, s * 7.6, y, AZ - 0.4, segs=8, rings=5))
mesh("Stage", "StageBulbs", bulbs, GOLD, "Neon")
cans = []
for s in (-1, 1):
    can = C(0.75, 1.8, 0, 0, 0, segs=12, r2=0.95)
    rim = TOR(0.95, 0.12, 0, 0.9, 0, segs=14, csegs=4)
    yoke = T([(-1.0, 0.0, 0), (-1.0, 1.4, 0), (1.0, 1.4, 0), (1.0, 0.0, 0)], 0.1, segs=5)
    for o in (can, rim, yoke):
        turn(o, "x", 180 - 40)  # the lens down and forward over the deck
        shift(o, rb(s * 10.5, TH + 1.8, AZ - 1.0))
        cans.append(o)
mesh("Stage", "StageCans", cans, (40, 40, 48), "Metal")

# ---------------------------------------------------------------- a pad, a podium step and its star, the beam cone
pad = [star(1.9, 0.9, 0.3, 0, 0, 0, points=5, axis="up"), TOR(1.85, 0.1, 0, -0.05, 0, segs=24, csegs=4)]
mesh("Pad", "StagePad", pad, GOLD, "Neon")
step = B(4.5, 1.0, 4.5, 0, 0, 0, bev=0.18)
mesh("Podium", "PodiumStep", step, (255, 205, 60), "SmoothPlastic")
mesh("Podium", "PodiumStar", star(0.9, 0.42, 0.12, 0, 0, 0, points=5), GOLD, "Neon")
cone = rings_mesh([[(math.cos(2 * math.pi * k / 24) * r, y, math.sin(2 * math.pi * k / 24) * r) for k in range(24)]
                   for (y, r) in ((-0.5, 0.5), (0.5, 0.06))])
mesh("Beam", "SpotCone", cone, (255, 244, 210), "Neon", alpha=0.8)


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
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rgb, mat, alpha = INFO[name]
        rows.append("\t%s = { look = \"%s\", size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d,"
                    " %d }, mat = \"%s\", alpha = %.2f, tris = %d }," % (
                        name, look, max(size.x, 0.02), max(size.z, 0.02), max(size.y, 0.02), c.x, c.z, -c.y,
                        rgb[0], rgb[1], rgb[2], mat, alpha, t))
text = "\n".join([
    "-- GENERATED by art/blender/contest.py: do not edit by hand.",
    "-- The costume contest's stage as meshes (ReplicatedStorage.Art.Stage; ContestService, Ui.ContestHud): each mesh's",
    "-- size and centre in the stage's frame (studs, x, up, z; the deck's top centre at 0, the arch at +z), or about its",
    "-- own centre for the pieces placed one by one (Pad, Podium, Beam), colour, material, transparency and triangles.",
    "-- %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "StageArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("stage: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Stage.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1500, 900), samples=32)
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            rgb, mat, alpha = INFO[name]
            ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.6 if mat == "Metal" else 0,
                                                  emit=2.0 if mat == "Neon" else 0.0))
    # the pads, podium steps and stars where the game puts them, a beam from the left can
    pads = LOOKS["Pad"]["StagePad"]
    for i in range(8):
        cp = copy(pads)
        ox = -7.5 + (i % 4) * 5
        oz = -8 + (i // 4) * 6
        cp.location = rb(ox, 0.2, oz)
    steps = LOOKS["Podium"]["PodiumStep"]
    for i, h in enumerate((4, 3, 2)):
        ox = (0, -5, 5)[i]
        cp = copy(steps)
        cp.scale = (1, 1, h)
        cp.location = rb(ox, h / 2, S_ / 2 - 4)
        st = copy(LOOKS["Podium"]["PodiumStar"])
        st.location = rb(ox, h * 0.55, S_ / 2 - 4 - 2.3)
    steps.location = (0, 0, -50)
    LOOKS["Podium"]["PodiumStar"].location = (0, 0, -50)
    pads.location = (0, 0, -50)
    cone = LOOKS["Beam"]["SpotCone"]
    cone.scale = (5, 5, 16)
    cone.rotation_euler = (math.radians(-30), 0, 0)
    cone.location = rb(-7.5, 10, 5)
    ground = kit.box("ground", 120, 120, 0.2, at=(0, 0, -H_ - 0.1))
    ground.data.materials.append(kit.material("g", (150, 150, 158)))
    kit.camera((-26, 44, 20), (0, 0, 6), lens=34)
    kit.render(os.path.join(kit.ROOT, "preview", "contest_stage.png"))
