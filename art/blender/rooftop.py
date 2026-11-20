# rooftop.py: the rooftop row's dressing as Blender meshes (list-combat 2026-11-20, Everything Left 268: "The
# rooftop row's dressing is plain boxes (AC units, water tanks, a blank billboard, a washing line)"; the AC units
# and the billboard were done before). Shared.CityLayout's ROW_DRESS names a prop for each box; CityBuilder draws
# it in the box's place (Config.City.kit.props pieces and colours), all-or-nothing, the box until then. Drawn in
# Roblox's frame from the prop's foot point (x, up, z; front -z), each the size of the box it stands for:
#   RoofTankStand   the water tank's steel stand: four legs, cross braces and a slatted deck, 8 x 2 x 8
#   RoofTank        the wooden water tank: staves, three steel hoops, a cone roof with a finial and a ladder, 7 x 10 x 7
#   RoofHatch       the stair hatch: a low housing with a sloped lid, a door and a handle, 4 x 2.5 x 4
#   RoofSkylight    a pitched glass skylight: a steel frame with mullions over two glass panes, 6 x 1.2 x 8
#   LaundryPole     a washing line pole with a cap and a hook ring, 0.6 x 7 x 0.6
#   LaundryShirt / LaundrySheet / LaundryTowel   the washing on the line, pegged, 2.4 x 3 x 0.2 (the line stays a
#                   thin part: its length is the roof's)
# Output: art/export/Roof.fbx and src/config/RoofArt.luau (generated); --preview renders art/preview/rooftop.png.
# Run: ~/tools/bpyenv/bin/python art/blender/rooftop.py [--preview] [--no-export]
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

STEEL = (150, 156, 162)
DARK = (60, 64, 72)


def flat(poly, z0, z1):
    """A polygon in the (x, up) plane pushed from z0 to z1 (cloths and plates facing -z)."""
    return rings_mesh([[(x, y, z0) for (x, y) in poly], [(x, y, z1) for (x, y) in poly]])


# ================================================================ the water tank's stand (foot: the roof)
stand = []
for sx in (-1, 1):
    for sz in (-1, 1):
        stand.append(B(0.5, 1.6, 0.5, sx * 3.6, 0.8, sz * 3.6))
for s in (-1, 1):
    stand.append(T([(s * 3.6, 0.2, -3.6), (s * 3.6, 1.4, 3.6)], 0.09, segs=6))
    stand.append(T([(-3.6, 0.2, s * 3.6), (3.6, 1.4, s * 3.6)], 0.09, segs=6))
for k in range(9):
    stand.append(B(8.0, 0.25, 0.7, 0, 1.85, -3.6 + k * 0.9))
mesh("RoofTankStand", "TankStand", stand, STEEL, "Metal")

# ================================================================ the wooden tank (foot: the deck, 2 above the roof)
staves = [C(3.4, 8.4, 0, 4.2, 0, segs=28)]
for k in range(14):  # stave grooves: thin dark ribs round the barrel
    a = k * math.tau / 14
    staves.append(B(0.12, 8.2, 0.12, math.cos(a) * 3.41, 4.2, math.sin(a) * 3.41))
mesh("RoofTank", "TankStaves", staves, (150, 104, 62), "Wood")
hoops = [TOR(3.46, 0.09, 0, y, 0, segs=36, csegs=5) for y in (1.2, 4.2, 7.2)]
ladder = [T([(sx * 0.45, 0, -3.55), (sx * 0.45, 8.6, -3.55)], 0.06, segs=5) for sx in (-1, 1)]
ladder += [T([(-0.45, y, -3.55), (0.45, y, -3.55)], 0.05, segs=5) for y in (0.8, 1.8, 2.8, 3.8, 4.8, 5.8, 6.8, 7.8)]
mesh("RoofTank", "TankHoops", hoops + ladder, DARK, "Metal")
mesh("RoofTank", "TankRoof", [C(3.6, 1.4, 0, 8.4, 0, segs=28, r2=0.25), C(0.12, 0.3, 0, 9.8, 0, segs=8),
                              S(0.14, 0, 10.0 - 0.14, 0, segs=8, rings=5)], (90, 80, 72), "Slate")

# ================================================================ the stair hatch (foot: the roof)
box = [B(4.0, 1.7, 4.0, 0, 0.85, 0, bev=0.08)]
lid = prism([(-2.1, 1.7), (2.1, 1.7), (2.1, 2.1), (-2.1, 2.5)], -2.1, 2.1)
mesh("RoofHatch", "HatchHousing", box + [lid], (176, 168, 156), "Concrete")
door = [flat([(-0.8, 0.1), (0.8, 0.1), (0.8, 1.55), (-0.8, 1.55)], -2.06, -1.98)]
mesh("RoofHatch", "HatchDoor", door + [B(0.35, 0.1, 0.1, 0.5, 0.85, -2.1)], (70, 110, 90), "Metal")

# ================================================================ a skylight (foot: the roof)
frame = [B(6.0, 0.35, 8.0, 0, 0.175, 0, bev=0.05)]
for x in (-3.0, 3.0):
    frame.append(T([(x * 0.97, 0.35, -3.9), (0, 1.2, -3.9)], 0.07, segs=5))
    frame.append(T([(x * 0.97, 0.35, 3.9), (0, 1.2, 3.9)], 0.07, segs=5))
frame.append(T([(0, 1.2, -3.9), (0, 1.2, 3.9)], 0.09, segs=6))
for z in (-1.3, 1.3):
    for x in (-3.0, 3.0):
        frame.append(T([(x * 0.97, 0.35, z), (0, 1.2, z)], 0.05, segs=5))
mesh("RoofSkylight", "SkylightFrame", frame, DARK, "Metal")
glass = [prism([(-3.9, 0.32), (3.9, 0.32), (3.9, 0.36), (-3.9, 0.36)], -2.9, 0)]
panes = []
for sx in (-1, 1):
    p = flat([(0, 1.18), (sx * 2.9, 0.36), (sx * 2.9, 0.4), (0, 1.22)], -3.9, 3.9)
    panes.append(p)
mesh("RoofSkylight", "SkylightGlass", panes, (170, 215, 235), "Glass", alpha=0.35)
for o in glass:
    bpy.data.objects.remove(o, do_unlink=True)

# ================================================================ the washing line's pole (foot: the roof)
pole = [C(0.22, 6.8, 0, 3.4, 0, segs=10), C(0.3, 0.2, 0, 6.9, 0, segs=10), C(0.3, 0.25, 0, 0.12, 0, segs=10),
        TOR(0.16, 0.04, 0, 6.6, -0.26, axis="x", segs=10, csegs=4)]
mesh("LaundryPole", "LaundryPole", pole, STEEL, "Metal")


# ================================================================ the washing (foot: 3.6 under the line; each 2.4 x 3 x 0.2)
def pegs(xs, y=3.0):
    return [B(0.12, 0.38, 0.16, x, y - 0.05, 0) for x in xs]


# convex pieces (the caps are fans): the body, the shoulders and two sleeves
shirt = [flat([(-0.6, 0.15), (0.6, 0.15), (0.6, 2.7), (-0.6, 2.7)], -0.05, 0.05),
         flat([(-0.6, 2.6), (0.6, 2.6), (0.5, 3.0), (-0.5, 3.0)], -0.05, 0.05)]
for sx in (-1, 1):
    shirt.append(flat([(sx * 0.55, 2.95), (sx * 1.2, 2.55), (sx * 0.95, 2.05), (sx * 0.55, 2.3)][::sx], -0.045, 0.045))
mesh("LaundryShirt", "LaundryShirt", shirt, (200, 70, 60), "Fabric")
mesh("LaundryShirt", "LaundryShirtPegs", pegs((-0.45, 0.45)), (230, 210, 150), "Wood")
sheet = [flat([(-1.15, 0.4), (1.15, 0.4), (1.15, 3.0), (-1.15, 3.0)], -0.04, 0.04)]
for k in range(10):  # a wavy hem, one convex strip a step
    x0, x1 = -1.15 + 2.3 * k / 10, -1.15 + 2.3 * (k + 1) / 10
    y0, y1 = 0.12 + 0.16 * math.sin(k * 1.3), 0.12 + 0.16 * math.sin((k + 1) * 1.3)
    sheet.append(flat([(x0, y0), (x1, y1), (x1, 0.42), (x0, 0.42)], -0.04, 0.04))
mesh("LaundrySheet", "LaundrySheet", sheet, (240, 240, 236), "Fabric")
mesh("LaundrySheet", "LaundrySheetPegs", pegs((-1.0, 0.0, 1.0)), (230, 210, 150), "Wood")
towel = flat([(-0.85, 3.0), (0.85, 3.0), (0.85, 0.5), (-0.85, 0.5)], -0.06, 0.06)
stripes = [flat([(-0.86, y), (0.86, y), (0.86, y + 0.18), (-0.86, y + 0.18)], -0.08, 0.08) for y in (0.75, 1.05)]
mesh("LaundryTowel", "LaundryTowel", [towel], (70, 120, 200), "Fabric")
mesh("LaundryTowel", "LaundryTowelBands", stripes + pegs((-0.7, 0.7)), (245, 245, 245), "Fabric")


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


lines = []
total = 0
for look in sorted(LOOKS):
    lines.append("\t%s = {" % look)
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        size = hi - lo
        c = (lo + hi) / 2
        t = kit.tris(ob)
        total += t
        # Blender (x, front, up) -> Roblox (x, up, z back)
        lines.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f } }, -- %d tris"
                     % (name, size.x, size.z, size.y, c.x, c.z, -c.y, t))
    lines.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/rooftop.py: do not edit by hand.",
    "-- The rooftop row's dressing (ReplicatedStorage.Art.Roof; CityBuilder draws them like Art.Street's props): each",
    "-- piece's size and its centre from the prop's foot point, in studs (x, up, back; a prop faces -z). Colours:",
    "-- Config.City.kit.props. %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + lines + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "RoofArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("rooftop: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Roof.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1500, 700), samples=32)
    # a roof as the game lays it: the stand and tank, the hatch, two skylights, two poles and the washing
    place = {"RoofTankStand": (-9, 0, 0), "RoofTank": (-9, 2, 0), "RoofHatch": (-1, 0, 2), "RoofSkylight": (6, 0, -1),
             "LaundryPole": (2, 0, -7), "LaundryShirt": (5, 3.6, -7), "LaundrySheet": (8, 3.6, -7),
             "LaundryTowel": (11, 3.6, -7)}
    for look, meshes in LOOKS.items():
        x, y, z = place[look]
        for name, ob in meshes.items():
            rgb, mat, alpha = INFO[name]
            m = kit.material("m_" + name, rgb, metal=0.6 if mat == "Metal" else 0.0, rough=0.5)
            if alpha:
                m.blend_method = "BLEND"
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - alpha
            ob.data.materials.append(m)
            ob.location = rb(x, y, z)
    pole2 = copy(LOOKS["LaundryPole"]["LaundryPole"])
    pole2.location = rb(14, 0, -7)
    line = kit.box("line", 12, 0.1, 0.1, at=rb(8, 6.6, -7))
    line.data.materials.append(kit.material("line", (240, 240, 240)))
    roof = kit.box("roof", 34, 22, 0.4, at=(1, 0, -0.2))
    roof.data.materials.append(kit.material("roof", (120, 118, 116)))
    kit.camera((6, 30, 16), (1, 0, 3), lens=34)  # from the front (Roblox -z is Blender +y)
    kit.render(os.path.join(kit.ROOT, "preview", "rooftop.png"))
