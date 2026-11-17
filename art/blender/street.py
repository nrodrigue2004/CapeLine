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

# ================================================================ step 5: the whole city. Piece names are unique
# across the set (the game finds each by name). Sizes in studs; a hero is about 5 studs tall.

def placed(ob, loc, rot):
    """A piece built at the origin, then turned and moved (join bakes the transform)."""
    ob.rotation_euler = rot
    ob.location = loc
    return ob


# ---------------------------------------------------------------- Downtown: bus shelter (open to the street)
sf = []
for x in (-3.4, 3.4):
    for y in (-1.0, 0.9):
        sf.append(kit.box("post", 0.22, 0.22, 7.2, at=(x, y, 3.6)))
sf.append(kit.box("rail", 7.0, 0.16, 0.2, at=(0, -1.0, 0.5)))
sf.append(kit.box("top", 7.2, 0.18, 0.2, at=(0, -1.0, 7.1)))
joined("BusStop", "ShelterFrame", sf, bev=0.04)
add("BusStop", "ShelterRoof", kit.box("ShelterRoof", 7.8, 2.9, 0.35, at=(0, -0.05, 7.4)), bev=0.1)
glass = [kit.box("g", 6.6, 0.08, 6.2, at=(0, -1.0, 3.9)), kit.box("g2", 0.08, 1.6, 5.4, at=(-3.4, -0.1, 4.3))]
joined("BusStop", "ShelterGlass", glass)
seat = [kit.box("st", 4.4, 0.9, 0.18, at=(0, -0.45, 1.6))]
for x in (-1.9, 1.9):
    seat.append(kit.box("sl", 0.16, 0.16, 1.5, at=(x, -0.7, 0.8)))
joined("BusStop", "ShelterSeat", seat, bev=0.03)

# ---------------------------------------------------------------- Downtown: bike rack (three hoops on a rail)
hoops = [kit.box("base", 5.2, 0.24, 0.12, at=(0, 0, 0.06))]
for x in (-2.0, 0.0, 2.0):
    arc = [Vector((x, 1.1, 0.0))] + [Vector((x, 1.1 * math.cos(a * math.pi / 8), 1.4 + 1.1 * math.sin(a * math.pi / 8)))
                                     for a in range(9)] + [Vector((x, -1.1, 0.0))]
    hoops.append(kit.tube_along("h", arc, [0.1] * len(arc), segs=6))
joined("BikeRack", "BikeRack", hoops)

# ---------------------------------------------------------------- Downtown: a short street bollard
add("Bollard", "Bollard", kit.loft("Bollard", [(0, 0.38, 0.38, 0, 0), (2.4, 0.34, 0.34, 0, 0), (2.7, 0.36, 0.36, 0, 0),
                                                (2.95, 0.22, 0.22, 0, 0)], segs=14, power=2.0))

# ---------------------------------------------------------------- Docks: wooden crate (3 studs)
cr = [kit.box("crate", 3.0, 3.0, 3.0, at=(0, 0, 1.5))]
for s in (-1, 1):
    cr.append(kit.box("bx", 3.1, 0.35, 0.4, at=(0, s * 1.38, 0.3)))
    cr.append(kit.box("bx", 3.1, 0.35, 0.4, at=(0, s * 1.38, 2.7)))
    cr.append(kit.box("by", 0.35, 3.1, 0.4, at=(s * 1.38, 0, 0.3)))
    cr.append(kit.box("by", 0.35, 3.1, 0.4, at=(s * 1.38, 0, 2.7)))
    cr.append(placed(kit.box("diag", 0.3, 0.2, 3.3), (0, s * 1.52, 1.5), (0, math.radians(42 * s), 0)))
joined("Crate", "Crate", cr, bev=0.05)

# ---------------------------------------------------------------- Docks: oil drum
add("Barrel", "Barrel", kit.loft("Barrel", [(0, 0.95, 0.95, 0, 0), (0.15, 1.0, 1.0, 0, 0), (0.25, 0.96, 0.96, 0, 0),
                                              (1.3, 0.96, 0.96, 0, 0), (1.4, 1.0, 1.0, 0, 0), (1.5, 0.96, 0.96, 0, 0),
                                              (2.75, 0.96, 0.96, 0, 0), (2.85, 1.0, 1.0, 0, 0), (3.0, 0.92, 0.92, 0, 0)],
                                    segs=18, power=2.0))

# ---------------------------------------------------------------- Docks: pallet
pal = []
for k in range(5):
    pal.append(kit.box("top", 4.0, 0.62, 0.14, at=(0, -1.6 + k * 0.8, 0.83)))
for x in (-1.75, 0, 1.75):
    pal.append(kit.box("blk", 0.5, 4.0, 0.62, at=(x, 0, 0.45)))
for k in range(3):
    pal.append(kit.box("bot", 4.0, 0.62, 0.14, at=(0, -1.6 + k * 1.6, 0.07)))
joined("Pallet", "Pallet", pal, bev=0.02)

# ---------------------------------------------------------------- Docks: mooring bollard (cast iron mushroom)
add("MooringBollard", "MooringBollard",
    kit.loft("MooringBollard", [(0, 1.0, 1.0, 0, 0), (0.3, 0.95, 0.95, 0, 0), (0.4, 0.62, 0.62, 0, 0), (1.6, 0.55, 0.55, 0, 0),
                                (1.9, 0.9, 0.9, 0, 0), (2.25, 0.88, 0.88, 0, 0), (2.4, 0.5, 0.5, 0, 0)], segs=18, power=2.0),
    bev=None)

# ---------------------------------------------------------------- Docks: floodlight mast (22 studs)
mast = [kit.cyl("m", 0.55, 0.35, 21, at=(0, 0, 10.5), segs=10),
        kit.box("bar", 4.6, 0.3, 0.3, at=(0, 0.3, 20.6)),
        kit.cyl("foot", 0.9, 0.9, 0.7, at=(0, 0, 0.35), segs=12)]
joined("DockLight", "DockMast", mast)
heads = []
for x in (-1.6, 0.0, 1.6):
    heads.append(placed(kit.box("hd", 1.2, 0.5, 0.9), (x, 0.75, 20.9), (math.radians(-25), 0, 0)))
joined("DockLight", "DockLamps", heads, bev=0.06)

# ---------------------------------------------------------------- Docks: jib crane (a quay crane, 34 studs, the
# jib reaching 22 studs out over the water in front)
ped = [kit.loft("ped", [(0, 3.4, 3.4, 0, 0), (1.2, 3.2, 3.2, 0, 0), (1.4, 2.0, 2.0, 0, 0), (20, 1.6, 1.6, 0, 0),
                        (20.6, 2.2, 2.2, 0, 0), (21.2, 2.2, 2.2, 0, 0)], segs=12, power=2.0)]
for a in range(4):  # the four feet
    ang = math.pi / 4 + a * math.pi / 2
    ped.append(kit.box("foot", 1.2, 1.2, 0.8, at=(math.cos(ang) * 3.0, math.sin(ang) * 3.0, 0.4)))
joined("JibCrane", "CranePedestal", ped)
add("JibCrane", "CraneCab", kit.box("CraneCab", 5.0, 6.0, 5.4, at=(0, -0.8, 24.0)), bev=0.3)
jib = [kit.tube_along("j1", [Vector((-1.1, 1.0, 22.6)), Vector((-0.6, 22.0, 28.2))], [0.35, 0.3], segs=6),
       kit.tube_along("j2", [Vector((1.1, 1.0, 22.6)), Vector((0.6, 22.0, 28.2))], [0.35, 0.3], segs=6),
       kit.tube_along("j3", [Vector((0, 1.0, 26.4)), Vector((0, 22.0, 28.4))], [0.3, 0.25], segs=6),
       kit.tube_along("cw", [Vector((0, -3.6, 27.4)), Vector((0, -0.6, 32.0)), Vector((0, 22.0, 28.6))], [0.16, 0.14, 0.12], segs=6),
       kit.box("ballast", 4.2, 2.4, 2.6, at=(0, -4.6, 23.4))]
for k in range(1, 7):  # lattice struts
    y = 1.0 + k * 3.0
    z = 22.6 + (y - 1.0) * (5.6 / 21.0)
    jib.append(kit.tube_along("s", [Vector((-1.0, y, z)), Vector((0, y + 1.5, z + 3.6))], [0.12, 0.12], segs=5))
    jib.append(kit.tube_along("s", [Vector((1.0, y, z)), Vector((0, y + 1.5, z + 3.6))], [0.12, 0.12], segs=5))
joined("JibCrane", "CraneJib", jib)
hook = [kit.cyl("rope", 0.07, 0.07, 9.0, at=(0, 21.4, 23.6), segs=5),
        kit.box("block", 1.0, 0.8, 1.2, at=(0, 21.4, 18.8)),
        placed(kit.torus("hk", 0.45, 0.14, segs=12, csegs=5, arc=math.pi * 1.4), (0, 21.4, 17.8), (math.pi / 2, 0, 0))]
joined("JibCrane", "CraneHook", hook)

# ---------------------------------------------------------------- Old Town: cast-iron lantern post (12 studs)
op = [kit.loft("base", [(0, 0.62, 0.62, 0, 0), (0.5, 0.58, 0.58, 0, 0), (0.8, 0.36, 0.36, 0, 0), (1.6, 0.3, 0.3, 0, 0),
                        (1.8, 0.24, 0.24, 0, 0), (9.6, 0.18, 0.18, 0, 0), (9.9, 0.3, 0.3, 0, 0), (10.1, 0.3, 0.3, 0, 0)],
              segs=12, power=2.0),
      kit.box("cross", 1.8, 0.14, 0.14, at=(0, 0, 9.0))]
joined("OldLamp", "OldPost", op)
lan = [kit.loft("cage", [(10.1, 0.42, 0.42, 0, 0), (10.3, 0.62, 0.62, 0, 0), (11.6, 0.72, 0.72, 0, 0),
                         (11.75, 0.85, 0.85, 0, 0), (12.3, 0.3, 0.3, 0, 0), (12.6, 0.08, 0.08, 0, 0)], segs=4, power=2.0)]
for a in range(4):
    ang = math.pi / 4 + a * math.pi / 2
    lan.append(kit.box("bar", 0.1, 0.1, 1.4, at=(math.cos(ang) * 0.66, math.sin(ang) * 0.66, 10.95)))
joined("OldLamp", "OldLantern", lan)
glow = kit.loft("OldGlow", [(10.35, 0.5, 0.5, 0, 0), (11.55, 0.6, 0.6, 0, 0)], segs=4, power=2.0)
add("OldLamp", "OldGlow", glow)

# ---------------------------------------------------------------- Old Town: flower tub
add("FlowerTub", "Tub", kit.loft("Tub", [(0, 0.9, 0.9, 0, 0), (1.2, 1.2, 1.2, 0, 0), (1.35, 1.3, 1.3, 0, 0),
                                       (1.5, 1.25, 1.25, 0, 0)], segs=16, power=2.0, cap=(True, False)))
leaves = []
for (x, y, z, r) in ((0, 0, 1.6, 1.05), (0.6, 0.3, 1.8, 0.65), (-0.6, -0.2, 1.8, 0.7), (0.1, -0.6, 1.9, 0.6),
                     (-0.2, 0.6, 2.0, 0.6)):
    leaves.append(kit.sphere("lf", r=r, at=(x, y, z), scale=(1, 1, 0.7), segs=10, rings=6))
joined("FlowerTub", "TubLeaves", leaves)
blooms = []
for k in range(9):
    ang = k * 2.4
    rr = 0.35 + 0.5 * ((k * 7) % 5) / 5
    blooms.append(kit.sphere("bl", r=0.24, at=(math.cos(ang) * rr, math.sin(ang) * rr, 2.25 + 0.1 * (k % 3)), segs=8, rings=5))
joined("FlowerTub", "TubBlooms", blooms)

# ---------------------------------------------------------------- Old Town: cafe table, two chairs, a parasol
tb = [kit.cyl("top", 1.3, 1.3, 0.14, at=(0, 0, 2.5), segs=18), kit.cyl("leg", 0.12, 0.12, 2.4, at=(0, 0, 1.25), segs=8),
      kit.cyl("ft", 0.7, 0.7, 0.1, at=(0, 0, 0.05), segs=12), kit.cyl("pole", 0.08, 0.08, 5.2, at=(0, 0, 5.1), segs=6)]
joined("CafeSet", "CafeTable", tb)
ch = []
for s in (-1, 1):
    x = s * 2.1
    ch.append(kit.box("seat", 1.3, 1.3, 0.14, at=(x, 0, 1.6)))
    ch.append(kit.box("back", 0.14, 1.3, 1.6, at=(x + s * 0.62, 0, 2.4)))
    for lx in (-0.55, 0.55):
        for ly in (-0.55, 0.55):
            ch.append(kit.box("leg", 0.1, 0.1, 1.6, at=(x + lx, ly, 0.8)))
joined("CafeSet", "CafeChairs", ch, bev=0.02)
add("CafeSet", "Umbrella", kit.loft("Umbrella", [(6.3, 3.0, 3.0, 0, 0), (6.5, 2.9, 2.9, 0, 0), (7.4, 1.4, 1.4, 0, 0),
                                                 (7.8, 0.15, 0.15, 0, 0)], segs=8, power=2.0))

# ---------------------------------------------------------------- outskirts: mailbox on a post
add("Mailbox", "MailPost", kit.box("MailPost", 0.4, 0.4, 3.4, at=(0, 0, 1.7)))
mb = [kit.box("flat", 1.0, 1.5, 0.5, at=(0, 0, 3.35)),
      placed(kit.loft("mb", [(-0.75, 0.5, 0.5, 0, 0), (0.75, 0.5, 0.5, 0, 0)], segs=14, power=2.0), (0, 0, 3.6), (math.pi / 2, 0, 0)),
      kit.box("flag", 0.06, 0.5, 0.8, at=(0.52, -0.4, 4.0))]
joined("Mailbox", "MailBox", mb)

# ---------------------------------------------------------------- outskirts: a round bush
bb = []
for (x, y, z, r) in ((0, 0, 1.5, 1.8), (1.2, 0.4, 1.2, 1.3), (-1.2, -0.3, 1.2, 1.35), (0.3, -1.1, 1.3, 1.2),
                     (-0.4, 1.1, 1.3, 1.2), (0.1, 0.1, 2.4, 1.2)):
    bb.append(kit.sphere("b", r=r, at=(x, y, z), segs=12, rings=8))
bush = kit.join("Bush", bb, shade=False)
kit.smooth(bush, 1)
kit.apply_all(bush)
kit.decimate(bush, 0.4)
kit.apply_all(bush)
kit.shade_auto(bush, 60)
kit.cut(bush, (0, 0, -1), keep_positive=False)  # a flat bottom at the ground
props["Bush"] = {"Bush": bush}

# ---------------------------------------------------------------- outskirts: wooden power pole (24 studs)
pp = [kit.cyl("pole", 0.5, 0.36, 24, at=(0, 0, 12), segs=10),
      kit.box("arm", 6.4, 0.4, 0.4, at=(0, 0, 22.4)),
      placed(kit.box("brace", 0.2, 0.2, 2.4), (-1.0, 0, 21.4), (0, math.radians(40), 0)),
      placed(kit.box("brace2", 0.2, 0.2, 2.4), (1.0, 0, 21.4), (0, math.radians(-40), 0))]
for x in (-2.8, -1.2, 1.2, 2.8):
    pp.append(kit.cyl("ins", 0.16, 0.12, 0.6, at=(x, 0, 22.9), segs=8))
pp.append(kit.cyl("can", 0.6, 0.6, 1.6, at=(0, 0.75, 19.0), segs=10))
joined("PowerPole", "PowerPole", pp)


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
