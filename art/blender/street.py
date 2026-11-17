# street.py: the city kit's street props (overhaul plan step 3, "one Downtown block"): what lines a sidewalk.
# One mesh per colour region (the game colours each MeshPart; Config.City.kit.props lists each prop's pieces,
# colours and materials): StreetLamp (Pole + LampHead + Bulb), Bench (BenchSeat + BenchFrame), Hydrant, Bin,
# Planter (PlanterBox + Trunk + Crown), TrafficLight (SignalPole + SignalBox + SignalLights).
# Each piece is centred on its own box like the other sets; src/config/StreetArt.luau (generated) gives each
# piece's size and its offset from the prop's foot point, in studs, so the game places them without guessing.
# Output: art/export/Street.fbx, src/config/StreetArt.luau. The block preview is art/blender/block.py.
# Run: python art/blender/street.py   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()

# props: name -> {piece: object}; studs, Blender axes (x across, +y front = toward the street, z up), foot at 0
props = {}


def add(prop, name, ob, bev=None):
    if bev:
        kit.bevel(ob, bev, 2)
    kit.apply_all(ob)
    ob.name = name
    ob.data.name = name
    props.setdefault(prop, {})[name] = ob
    return ob


def joined(prop, name, parts, bev=None):
    for p in parts:
        if bev:
            kit.bevel(p, bev, 1)
    ob = kit.join(name, parts)
    props.setdefault(prop, {})[name] = ob
    return ob


# ---------------------------------------------------------------- street lamp (14 studs tall, arm over the road)
pole = [kit.cyl("p0", 0.42, 0.42, 0.8, at=(0, 0, 0.4), segs=16),
        kit.cyl("p1", 0.3, 0.22, 12.4, at=(0, 0, 7.0), segs=12),
        kit.torus("p2", 0.3, 0.07, at=(0, 0, 1.2), segs=16, csegs=6),
        kit.tube_along("arm", [Vector((0, 0, 12.8)), Vector((0, 0.8, 13.6)), Vector((0, 2.4, 13.9)), Vector((0, 3.2, 13.8))],
                       [0.13, 0.12, 0.11, 0.1], segs=8)]
joined("StreetLamp", "Pole", pole)
head = kit.loft("LampHead", [(13.2, 0.25, 0.5, 0, 3.4), (13.45, 0.42, 0.75, 0, 3.4), (13.75, 0.38, 0.7, 0, 3.4),
                             (13.95, 0.18, 0.3, 0, 3.4)], segs=16, power=2.2)
add("StreetLamp", "LampHead", head)
add("StreetLamp", "Bulb", kit.loft("Bulb", [(13.12, 0.22, 0.45, 0, 3.4), (13.22, 0.24, 0.5, 0, 3.4)], segs=16, power=2.2))

# ---------------------------------------------------------------- bench (wooden slats on a cast frame)
slats = []
for k in range(4):
    slats.append(kit.box("s%d" % k, 5.2, 0.42, 0.14, at=(0, 0.25 - k * 0.5, 1.5)))
for k in range(3):
    b = kit.box("b%d" % k, 5.2, 0.12, 0.38, at=(0, -1.15, 2.05 + k * 0.48))
    slats.append(b)
joined("Bench", "BenchSeat", slats, bev=0.03)
frame = []
for x in (-2.2, 2.2):
    frame.append(kit.box("leg", 0.18, 0.18, 1.45, at=(x, 0.3, 0.72)))
    frame.append(kit.box("leg2", 0.18, 0.18, 2.9, at=(x, -1.25, 1.45)))
    frame.append(kit.box("rail", 0.18, 1.8, 0.16, at=(x, -0.4, 1.38)))
    frame.append(kit.box("arm", 0.2, 1.4, 0.14, at=(x + (0.12 if x > 0 else -0.12), -0.35, 2.2)))
joined("Bench", "BenchFrame", frame, bev=0.03)

# ---------------------------------------------------------------- fire hydrant
hy = kit.loft("Hydrant", [(0.0, 0.62, 0.62, 0, 0), (0.25, 0.62, 0.62, 0, 0), (0.3, 0.42, 0.42, 0, 0), (2.1, 0.4, 0.4, 0, 0),
                          (2.2, 0.5, 0.5, 0, 0), (2.35, 0.5, 0.5, 0, 0), (2.7, 0.38, 0.38, 0, 0), (2.95, 0.12, 0.12, 0, 0)],
              segs=16, power=2.0)
caps = [hy, kit.cyl("c1", 0.2, 0.2, 1.3, at=(0, 0, 1.55), segs=10, axis="X"),
        kit.cyl("c2", 0.25, 0.25, 0.45, at=(0, 0.5, 1.4), segs=10, axis="Y"),
        kit.cyl("nut", 0.12, 0.12, 0.3, at=(0, 0, 3.05), segs=6)]
joined("Hydrant", "Hydrant", caps)

# ---------------------------------------------------------------- litter bin (a slatted drum with a lid)
drum = [kit.cyl("drum", 0.95, 0.85, 3.0, at=(0, 0, 1.5), segs=20),
        kit.cyl("lid", 1.05, 0.95, 0.3, at=(0, 0, 3.15), segs=20),
        kit.torus("band", 0.97, 0.06, at=(0, 0, 0.6), segs=20, csegs=5),
        kit.torus("band2", 1.0, 0.06, at=(0, 0, 2.5), segs=20, csegs=5)]
joined("Bin", "Bin", drum)

# ---------------------------------------------------------------- planter with a street tree
add("Planter", "PlanterBox", kit.box("PlanterBox", 3.4, 3.4, 1.4, at=(0, 0, 0.7)), bev=0.1)
trunk = kit.tube_along("Trunk", [Vector((0, 0, 1.4)), Vector((0.1, 0.05, 5)), Vector((-0.1, 0.1, 8)), Vector((0, 0, 10))],
                       [0.4, 0.32, 0.26, 0.2], segs=10)
add("Planter", "Trunk", trunk)
blobs = []
for (x, y, z, r) in ((0, 0, 11.2, 3.2), (1.8, 0.6, 10.2, 2.3), (-1.7, -0.5, 10.4, 2.4), (0.4, -1.8, 10.6, 2.2),
                     (-0.5, 1.8, 10.8, 2.2), (0.2, 0.3, 13.0, 2.1)):
    blobs.append(kit.sphere("leaf", r=r * 0.8, at=(x * 0.8, y * 0.8, 10 + (z - 10) * 0.8), segs=14, rings=9))
crown = kit.join("Crown", blobs, shade=False)
kit.smooth(crown, 1)
kit.apply_all(crown)
kit.decimate(crown, 0.45)
kit.apply_all(crown)
kit.shade_auto(crown, 60)
props["Planter"]["Crown"] = crown

# ---------------------------------------------------------------- traffic light (on the corner)
sp = [kit.cyl("sp", 0.32, 0.26, 16, at=(0, 0, 8), segs=12),
      kit.tube_along("sarm", [Vector((0, 0, 15.6)), Vector((0, 5.0, 15.6)), Vector((0, 9.0, 15.6))], [0.18, 0.16, 0.14], segs=8),
      kit.cyl("base", 0.5, 0.5, 0.6, at=(0, 0, 0.3), segs=14)]
joined("TrafficLight", "SignalPole", sp)
add("TrafficLight", "SignalBox", kit.box("SignalBox", 1.1, 0.9, 3.0, at=(0, 8.6, 14.0)), bev=0.12)
lights = [kit.cyl("l%d" % k, 0.32, 0.32, 0.12, at=(0, 9.08, 14.95 - k * 0.95), segs=14, axis="Y") for k in range(3)]
joined("TrafficLight", "SignalLights", lights)


# ---------------------------------------------------------------- sizes and offsets (Roblox axes: x, up, back)
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


rows = []
total = 0
for prop in sorted(props):
    rows.append("\t%s = {" % prop)
    for name in sorted(props[prop]):
        ob = props[prop][name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f } }, -- %d tris"
                    % (name, size.x, size.z, size.y, c.x, c.z, -c.y, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/street.py: do not edit by hand.",
    "-- The city kit's street props (ReplicatedStorage.Art.Street): each piece's size and its centre from the prop's",
    "-- foot point, in studs (x, up, back; a prop faces -z, toward the street). Colours: Config.City.kit.props.",
    "return {",
] + rows + ["}", ""])
with open(os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "StreetArt.luau")), "w") as f:
    f.write(text)
print("street props:", total, "tris")

if "--no-export" not in sys.argv:
    export = []
    for prop in props:
        for name, ob in props[prop].items():
            cp = ob.copy()
            cp.data = ob.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Street.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

# keep the built props for block.py (it imports this module)
PROPS = props
