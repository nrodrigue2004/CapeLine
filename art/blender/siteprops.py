# siteprops.py: small site props as Blender meshes (list-combat 2026-11-20, Everything Left 399, 401, 402: "the cat
# on the crane is plain parts", "giver ! markers are plain dots", "the Patch relay giver is a post, a box and a
# screen"). Each mesh is drawn to fill the box of the SiteKit part with the same name, in that part's own frame
# (x, up, z; front -z), so Services.SiteKit.skin swaps the part for it in place (its colour and material kept):
#   QuestMark    the side quest giver's marker: a chunky comic "!" (round, so it reads from every side), 0.8 x 1.6 x 0.8
#   RelayPost    the relay's post: a steel pole on a bolted foot plate with a clamp ring, 0.5 x 4 x 0.5
#   RelayBox     the relay box: a rugged radio case with a carry handle, side grilles, two dials and corner guards,
#                2.2 x 1.6 x 1.4 (the screen stays its own glowing part in front)
#   RelayAerial  the aerial: a whip with two coils, 0.12 x 2.6 x 0.12
#   CatBody      the stranded cat (CatOnCrane): a round loaf body with four paws, 1.4 x 1 x 2.2
#   CatHead      its head with cheeks and a muzzle, 1.1 x 1 x 1 (the eyes and nose are carved in the bake: none here,
#                the colour is the part's ginger)
#   CatEar       one ear, 0.3 x 0.5 x 0.2
#   CatTail      the tail (its part is tipped up 40 degrees), 0.25 x 0.25 x 1.6
# Output: art/export/SiteProps.fbx and src/config/SitePropArt.luau (generated); --preview renders
# art/preview/siteprops.png.
# Run: ~/tools/bpyenv/bin/python art/blender/siteprops.py [--preview] [--no-export]
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

GOLD = (255, 210, 60)
STEEL = (70, 74, 86)
CASE = (40, 44, 54)
GINGER = (240, 150, 60)


def lathe(prof, segs=16):
    """A round solid through (y, r) stations bottom to top."""
    return rings_mesh([[(math.cos(2 * math.pi * k / segs) * r, y, math.sin(2 * math.pi * k / segs) * r)
                        for k in range(segs)] for (y, r) in prof])


# ---------------------------------------------------------------- the "!": a bar swelling to the top, and its dot
def mark():
    bar = lathe([(-0.28, 0.14), (-0.2, 0.22), (0.1, 0.3), (0.5, 0.38), (0.72, 0.38), (0.8, 0.3)], 16)
    dot = S(0.2, 0, -0.6, 0, segs=14, rings=8)
    mesh("Giver", "QuestMark", [bar, dot], GOLD, "Neon")


# ---------------------------------------------------------------- the relay: post, box and aerial
def relay():
    post = [C(0.13, 3.7, 0, 0.1, 0, segs=10), B(0.5, 0.12, 0.5, 0, -1.94, 0, bev=0.03),
            TOR(0.15, 0.04, 0, 1.4, 0, segs=12, csegs=4)]
    for sx, sz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        post.append(C(0.03, 0.06, sx * 0.18, -1.86, sz * 0.18, segs=6))
    mesh("Relay", "RelayPost", post, STEEL, "Metal")
    box = [B(2.0, 1.2, 1.3, 0, -0.05, 0, bev=0.1)]
    # the handle over the top
    box.append(T([(-0.6, 0.55, 0), (-0.55, 0.78, 0), (0.55, 0.78, 0), (0.6, 0.55, 0)], 0.06, segs=6))
    # corner guards
    for sx in (-1, 1):
        for sy in (-1, 1):
            box.append(B(0.24, 0.24, 1.36, sx * 0.94, -0.05 + sy * 0.54, 0, bev=0.05))
    # side grilles: ribs on both ends
    for sx in (-1, 1):
        for k in range(4):
            box.append(B(0.06, 0.08, 0.9, sx * 1.02, -0.35 + k * 0.2, 0))
    # two dials on the front's lower edge (the screen sits above them)
    for x in (-0.55, 0.55):
        box.append(C(0.1, 0.1, x, -0.48, -0.66, segs=10, axis="z"))
    mesh("Relay", "RelayBox", box, CASE, "Metal")
    aer = [C(0.04, 2.5, 0, 0.0, 0, segs=6)]
    for y in (-0.6, 0.3):
        aer.append(TOR(0.05, 0.015, 0, y, 0, segs=8, csegs=4))
        aer.append(TOR(0.05, 0.015, 0, y + 0.08, 0, segs=8, csegs=4))
    aer.append(S(0.05, 0, -1.26, 0, segs=6, rings=4))
    mesh("Relay", "RelayAerial", aer, STEEL, "Metal")


# ---------------------------------------------------------------- the cat (front -z)
def cat():
    body = S(0.62, 0, 0.05, 0.05, sc=(1.0, 0.72, 1.6), segs=16, rings=10)
    paws = [S(0.18, sx * 0.38, -0.38, sz * 0.72, sc=(1, 0.6, 1.3), segs=8, rings=6) for sx in (-1, 1) for sz in (-1, 1)]
    mesh("Cat", "CatBody", [body] + paws, GINGER, "SmoothPlastic")
    head = S(0.46, 0, 0.02, 0.05, sc=(1.08, 0.95, 0.92), segs=16, rings=10)
    cheeks = [S(0.2, sx * 0.24, -0.22, -0.3, sc=(1, 0.8, 0.8), segs=10, rings=6) for sx in (-1, 1)]
    muzzle = S(0.13, 0, -0.18, -0.42, segs=8, rings=6)
    mesh("Cat", "CatHead", [head, muzzle] + cheeks, GINGER, "SmoothPlastic")
    ear = rings_mesh([[(-0.15, -0.25, -0.1), (0.15, -0.25, -0.1), (0.12, -0.25, 0.1), (-0.12, -0.25, 0.1)],
                      [(-0.02, 0.25, -0.02), (0.02, 0.25, -0.02), (0.02, 0.25, 0.02), (-0.02, 0.25, 0.02)]])
    mesh("Cat", "CatEar", ear, GINGER, "SmoothPlastic")
    tail = T([(0, 0, -0.8), (0, 0.01, -0.2), (0, 0.0, 0.3), (0, 0.01, 0.65), (0, 0.02, 0.8)],
             [0.12, 0.12, 0.11, 0.1, 0.08], segs=8)
    mesh("Cat", "CatTail", tail, (220, 130, 50), "SmoothPlastic")


for fn in (mark, relay, cat):
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
        rows.append('\t%s = { look = "%s", size = { %.3f, %.3f, %.3f }, tris = %d },'
                    % (name, look, max(size.x, 0.02), max(size.z, 0.02), max(size.y, 0.02), t))
text = "\n".join([
    "-- GENERATED by art/blender/siteprops.py: do not edit by hand.",
    "-- Small site props as meshes (ReplicatedStorage.Art.SiteProps, Services.SiteKit.skin): each named for the SiteKit",
    "-- part whose box it fills (x, up, z as drawn; the game stretches it to the part), its prop and its triangles.",
    "-- %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "SitePropArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("siteprops: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "SiteProps.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    # assembled as the game places them: the giver's mark, the relay giver, the cat
    kit.studio(res=(1400, 700), samples=32)
    place = {
        "QuestMark": rb(-4, 3.0, 0),
        "RelayPost": rb(0, 2.0, 0), "RelayBox": rb(0, 4.6, 0), "RelayAerial": rb(0.7, 6.7, 0),
        "CatBody": rb(4, 0.5, 0), "CatHead": rb(4, 1.2, -1.2), "CatTail": rb(4, 1.2, 1.6),
    }
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            rgb, mat, _ = INFO[name]
            ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.5 if mat == "Metal" else 0,
                                                  emit=2.0 if mat == "Neon" else 0.0))
            ob.location = place.get(name, (0, 0, -40))
    ears = LOOKS["Cat"]["CatEar"]
    ears.location = rb(4 - 0.35, 1.9, -1.2)
    e2 = copy(ears)
    e2.location = rb(4 + 0.35, 1.9, -1.2)
    tail = LOOKS["Cat"]["CatTail"]
    tail.rotation_euler = (math.radians(-40), 0, 0)
    screen = kit.box("screen", 1.4, 0.1, 0.5, at=rb(0, 4.7, -0.72))
    screen.data.materials.append(kit.material("scr", (110, 200, 255), emit=2.0))
    lamp = kit.sphere("lamp", 0.2, at=rb(0.7, 8.1, 0))
    lamp.data.materials.append(kit.material("lmp", (110, 200, 255), emit=2.0))
    ground = kit.box("ground", 40, 40, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (150, 150, 158)))
    kit.camera((-3, 14, 6), (0, 0, 3.0), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "siteprops.png"))
