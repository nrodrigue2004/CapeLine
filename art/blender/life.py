# life.py: the living-world set (2026-11-19, nate's playtest: "you still use way too many simple shapes ... World
# needs to feel way more alive"). Two kinds of looks, one mesh per colour region like street.py:
#   * cover looks stand over one of the city's own boxes (Shared.LifeKit: the box keeps its record, collisions and
#     breaking; the server builds the mesh in its place): trees (a trunk and three canopies), crop rows, corn rows,
#     round hay bales, house doors, silos and silo domes. Each is drawn round a NOMINAL box centred on the origin
#     (Blender x, y, z = Roblox x, -z, up); the game scales each piece by the real box over the nominal one.
#   * foot looks stand on a foot point like the street props (faces -z, toward the street): shop fronts with a sign
#     board, the vending machine, its cans, a manhole, the pigeon (body and two wings), the news drone (body, arms,
#     one rotor the game spins four of, its eye) and the roof flag pole.
# Output: art/export/Life.fbx, src/config/LifeArt.luau (generated); --preview renders art/preview/life.png.
# Run: ~/tools/bpyenv/bin/python art/blender/life.py [--preview]
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

kit.reset()
rng = random.Random(20261119)

cover = {}  # look -> {"nominal": (x, y, z) Blender, "pieces": {name: ob}}
foot = {}  # look -> {name: ob}


def jitter(ob, amp, seed, scale=0.8):
    """A cartoon lumpy surface: every vertex pushed along its offset from the centre by a little noise."""
    kit.apply_all(ob)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in ob.data.vertices:
        n = noise.noise(v.co * scale + off)
        v.co = v.co + v.co.normalized() * n * amp if v.co.length > 1e-4 else v.co
    return ob


def done(ob, name):
    kit.apply_all(ob)
    ob.name = name
    ob.data.name = name
    return ob


def put_cover(look, nominal, name, parts, bev=None, shade=True):
    for p in parts:
        if bev:
            kit.bevel(p, bev, 1)
    ob = kit.join(name, parts, shade=shade) if len(parts) > 1 else done(parts[0], name)
    if len(parts) == 1 and shade:
        kit.shade_auto(ob)
    cover.setdefault(look, {"nominal": nominal, "pieces": {}})["pieces"][name] = ob
    return ob


def put_foot(look, name, parts, bev=None, shade=True):
    for p in parts:
        if bev:
            kit.bevel(p, bev, 1)
    ob = kit.join(name, parts, shade=shade) if len(parts) > 1 else done(parts[0], name)
    if len(parts) == 1 and shade:
        kit.shade_auto(ob)
    foot.setdefault(look, {})[name] = ob
    return ob


def flat(ob):
    """Faceted shading (the cartoon low-poly canopies)."""
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


# ================================================================ trees (BoxKit.tree: trunk 0.18s x 0.8s, ball 0.9s)
# nominal size 10: the trunk box is 1.8 x 1.8 x 8 centred at 4 over the ground, the ball 9 x 9 x 9 centred at 10
TRUNK_NOM = (1.8, 1.8, 8.0)
tr = [kit.tube_along("trunk", [Vector((0, 0, -4.0)), Vector((0.05, 0, -3.3)), Vector((-0.05, 0.05, -0.5)),
                               Vector((0.1, -0.05, 2.5)), Vector((0, 0, 4.4))], [0.95, 0.66, 0.52, 0.42, 0.3], segs=9)]
for k in range(4):  # root flares
    a = k * math.pi / 2 + 0.4
    d = Vector((math.cos(a), math.sin(a), 0))
    tr.append(kit.tube_along("root", [Vector((0, 0, -3.2)), d * 0.9 + Vector((0, 0, -3.8)), d * 1.45 + Vector((0, 0, -4.0))],
                             [0.32, 0.22, 0.08], segs=6))
for k, (a, z0, z1, out) in enumerate(((0.3, 1.4, 4.2, 1.5), (2.4, 2.2, 4.4, 1.3), (4.3, 1.8, 4.0, 1.4))):
    d = Vector((math.cos(a), math.sin(a), 0))
    tr.append(kit.tube_along("br", [Vector((0, 0, z0)), d * out * 0.55 + Vector((0, 0, (z0 + z1) / 2 + 0.3)), d * out + Vector((0, 0, z1))],
                             [0.24, 0.17, 0.1], segs=6))
trunk = put_cover("TreeTrunk", TRUNK_NOM, "TreeTrunk", tr)
jitter(trunk, 0.06, 3, 1.6)

CAN_NOM = (9.0, 9.0, 9.0)


def lobes(name, spots, seed, amp=0.35):
    parts = []
    for i, (x, y, z, r) in enumerate(spots):
        s = kit.sphere("lb%d" % i, r, at=(x, y, z), segs=9, rings=6)
        parts.append(s)
    for p in parts:
        kit.apply_all(p)
    ob = kit.join(name, parts, shade=False)
    jitter(ob, amp, seed, 0.7)
    flat(ob)
    return ob


# a round broadleaf crown: a ring of lobes, a crown of lobes and one on top, sitting low over the trunk's branches
spots = [(0, 0, 0.6, 3.0)]
for k in range(6):
    a = k * math.pi / 3 + 0.3
    spots.append((math.cos(a) * 2.6, math.sin(a) * 2.6, -0.6 + (k % 2) * 0.5, 2.0 + (k % 3) * 0.25))
for k in range(3):
    a = k * 2 * math.pi / 3 + 1.0
    spots.append((math.cos(a) * 1.4, math.sin(a) * 1.4, 2.2, 1.9))
cr = lobes("CanopyRound", spots, 5)
cover["CanopyRound"] = {"nominal": CAN_NOM, "pieces": {"CanopyRound": done(cr, "CanopyRound")}}

# a tall oval crown (a poplar or a street lime): lobes stacked up a column
spots = []
for k in range(5):
    z = -3.6 + k * 1.9
    r = 1.9 + math.sin((k + 0.5) / 5 * math.pi) * 0.9
    for j in range(3):
        a = j * 2 * math.pi / 3 + k * 0.9
        spots.append((math.cos(a) * r * 0.55, math.sin(a) * r * 0.55, z, r * 0.78))
ct = lobes("CanopyTall", spots, 9, 0.3)
cover["CanopyTall"] = {"nominal": CAN_NOM, "pieces": {"CanopyTall": done(ct, "CanopyTall")}}

# a pine: four jagged tiers down over the trunk
tiers = []
for k, (z, r, h) in enumerate(((-4.4, 4.5, 4.4), (-1.9, 3.7, 4.0), (0.6, 2.8, 3.6), (3.0, 1.8, 3.2))):
    c = kit.cyl("tier%d" % k, r, 0.15, h, at=(0, 0, z + h / 2), segs=12)
    kit.apply_all(c)
    for v in c.data.vertices:  # a sawtooth hem: every other bottom vertex dips and pokes out
        if v.co.z < z + 0.05:
            a = math.atan2(v.co.y, v.co.x)
            i = round(a / (2 * math.pi / 12))
            if i % 2 == 0:
                v.co.z -= 0.55
                v.co.x *= 1.08
                v.co.y *= 1.08
    tiers.append(c)
cp = kit.join("CanopyPine", tiers, shade=False)
jitter(cp, 0.12, 13, 0.9)
flat(cp)
cover["CanopyPine"] = {"nominal": CAN_NOM, "pieces": {"CanopyPine": done(cp, "CanopyPine")}}

# ================================================================ crops (WorldGen field: rows 2 tall, along x here)
ROW_NOM = (30.0, 5.0, 2.0)
heads = []
for line in (-1, 1):
    for k in range(12):
        x = -14.0 + k * (28.0 / 11) + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.95, 1.2)
        s = kit.sphere("h", r, at=(x, line * 1.25 + rng.uniform(-0.2, 0.2), -0.45), scale=(1, 1, 0.62), segs=8, rings=5)
        heads.append(s)
crop = kit.join("CropRow", heads, shade=False)
jitter(crop, 0.22, 21, 1.4)
flat(crop)
cover["CropRow"] = {"nominal": ROW_NOM, "pieces": {"CropRow": done(crop, "CropRow")}}

stalks, cobs = [], []
for line in (-1, 1):
    for k in range(10):
        x = -14.0 + k * (28.0 / 9) + rng.uniform(-0.4, 0.4)
        y = line * 1.3 + rng.uniform(-0.25, 0.25)
        h = rng.uniform(5.0, 6.0)
        stalks.append(kit.cyl("st", 0.16, 0.08, h, at=(x, y, -1.0 + h / 2), segs=5))
        for j in range(3):
            a = rng.uniform(0, 2 * math.pi)
            d = Vector((math.cos(a), math.sin(a), 0))
            z0 = -0.4 + j * 1.4
            p0 = Vector((x, y, z0))
            stalks.append(kit.tube_along("lf", [p0, p0 + d * 0.9 + Vector((0, 0, 0.7)), p0 + d * 1.7 + Vector((0, 0, 0.3))],
                                         [0.14, 0.12, 0.02], segs=4))
        cobs.append(kit.loft("cob", [(-1.0 + h * 0.55, 0.22, 0.22, x + 0.22, y), (-1.0 + h * 0.55 + 0.9, 0.2, 0.2, x + 0.24, y),
                                     (-1.0 + h * 0.55 + 1.3, 0.05, 0.05, x + 0.26, y)], segs=6, power=2.0))
corn = kit.join("CornRow", stalks, shade=False)
flat(corn)
cover["CornRow"] = {"nominal": ROW_NOM, "pieces": {"CornRow": done(corn, "CornRow")}}
cobj = kit.join("CornCobs", cobs, shade=True)
cover["CornRow"]["pieces"]["CornCobs"] = done(cobj, "CornCobs")

# ================================================================ a round hay bale on its side (the 5 x 5 x 5 cylinder)
BALE_NOM = (5.0, 5.0, 5.0)
bale = kit.loft("HayBale", [(-2.3, 2.1, 2.1, 0, 0), (-2.2, 2.35, 2.35, 0, 0), (-1.2, 2.42, 2.42, 0, 0), (0, 2.46, 2.46, 0, 0),
                            (1.2, 2.42, 2.42, 0, 0), (2.2, 2.35, 2.35, 0, 0), (2.3, 2.1, 2.1, 0, 0)], segs=22, power=2.0)
kit.apply_all(bale)
for v in bale.data.vertices:  # straw ridges round the roll and a little sag at the bottom
    a = math.atan2(v.co.y, v.co.x)
    v.co.x *= 1 + 0.025 * math.sin(a * 11)
    v.co.y *= 1 + 0.025 * math.sin(a * 11)
for v in bale.data.vertices:  # lie it along x
    v.co = Vector((v.co.z, v.co.y, v.co.x))
bale.data.update()
bale_ob = kit.join("HayBale", [bale] + [kit.torus("b2", 2.47, 0.07, at=(0, 0, 0), segs=24, csegs=4, axis="X")], shade=True)
kit.shift(bale_ob, (0, 0, 2.46 - 2.5))
cover["HayBale"] = {"nominal": BALE_NOM, "pieces": {"HayBale": done(bale_ob, "HayBale")}}

# ================================================================ a house door (BoxKit.house: 4 x 7 x 0.4 on the +z face)
# the house's street side is Roblox +z = Blender -y: the panels and the knob are on -y
DOOR_NOM = (4.0, 0.4, 7.0)
dp = [kit.box("slab", 3.2, 0.25, 6.4, at=(0, 0, -0.25))]
for side in (-1, 1):
    dp.append(kit.box("jamb", 0.4, 0.5, 7.0, at=(side * 1.8, 0, 0)))
dp.append(kit.box("head", 4.0, 0.5, 0.45, at=(0, 0, 3.27)))
dp.append(kit.box("sill", 3.6, 0.6, 0.2, at=(0, -0.05, -3.4)))
for row, (z, h) in enumerate(((1.45, 2.2), (-1.65, 2.6))):  # raised panels
    for side in (-1, 1):
        dp.append(kit.box("pn", 1.15, 0.12, h, at=(side * 0.72, -0.15, z)))
put_cover("HouseDoor", DOOR_NOM, "DoorPanel", dp, bev=0.04)
knob = [kit.sphere("kn", 0.17, at=(1.15, -0.28, -0.4), segs=8, rings=6),
        kit.cyl("ro", 0.12, 0.12, 0.12, at=(1.15, -0.18, -0.4), segs=8, axis="Y")]
put_cover("HouseDoor", DOOR_NOM, "DoorKnob", knob)

# ================================================================ silos (WorldGen silo: an 11 x h x 11 cylinder and an 11 ball)
SILO_NOM = (11.0, 11.0, 30.0)
sb = [kit.cyl("body", 5.5, 5.5, 30.0, at=(0, 0, 0), segs=24)]
for k in range(9):
    sb.append(kit.torus("rib", 5.55, 0.12, at=(0, 0, -13.5 + k * 3.4), segs=24, csegs=4))
for x in (-0.45, 0.45):  # a ladder up the side
    sb.append(kit.box("rail", 0.12, 0.12, 29.0, at=(x, -5.75, 0.3)))
for k in range(28):
    sb.append(kit.box("rung", 0.95, 0.1, 0.1, at=(0, -5.75, -13.8 + k * 1.02)))
put_cover("SiloBody", SILO_NOM, "SiloBody", sb)
DOME_NOM = (11.0, 11.0, 11.0)
dm = kit.loft("dome", [(0.0, 5.62, 5.62, 0, 0), (1.6, 5.3, 5.3, 0, 0), (3.0, 4.4, 4.4, 0, 0), (4.1, 3.0, 3.0, 0, 0), (4.8, 1.3, 1.3, 0, 0),
                       (5.0, 0.2, 0.2, 0, 0)], segs=24, power=2.0)
cap = kit.cyl("vent", 0.8, 0.6, 0.9, at=(0, 0, 5.3), segs=10)
hood = kit.cyl("hood", 1.1, 0.2, 0.5, at=(0, 0, 5.95), segs=10)
dome = kit.join("SiloDome", [dm, cap, hood])
kit.shift(dome, (0, 0, -0.4))
cover["SiloDome"] = {"nominal": DOME_NOM, "pieces": {"SiloDome": done(dome, "SiloDome")}}

# ================================================================ foot looks (foot point at 0, the front toward +y)
# ---- a shop front under an awning: 12.4 wide, 10.6 tall, 0.9 out from the wall (its awning sits at 11)
SW, SH, SD = 12.4, 10.6, 0.9
fr = []
for side in (-1, 1):
    fr.append(kit.box("pil", 0.9, SD, SH, at=(side * (SW / 2 - 0.45), SD / 2, SH / 2)))
    fr.append(kit.box("cap", 1.1, SD + 0.15, 0.4, at=(side * (SW / 2 - 0.45), (SD + 0.15) / 2, SH - 0.2)))
    fr.append(kit.box("plinth", 1.1, SD + 0.15, 0.5, at=(side * (SW / 2 - 0.45), (SD + 0.15) / 2, 0.25)))
fr.append(kit.box("fascia", SW, SD, 2.4, at=(0, SD / 2, SH - 1.2)))
fr.append(kit.box("corn", SW + 0.3, SD + 0.25, 0.3, at=(0, (SD + 0.25) / 2, SH - 0.15)))
fr.append(kit.box("kick", 7.6, SD * 0.8, 1.3, at=(-1.5, SD * 0.4, 0.65)))
fr.append(kit.box("sill", 7.8, SD + 0.1, 0.18, at=(-1.5, (SD + 0.1) / 2, 1.36)))
fr.append(kit.box("transom", 10.6, SD * 0.7, 0.25, at=(0, SD * 0.35, 6.9)))
for x in (-3.9, -1.5, 0.9):
    fr.append(kit.box("mull", 0.22, SD * 0.7, 5.4, at=(x, SD * 0.35, 4.1)))
fr.append(kit.box("dj1", 0.3, SD * 0.8, 6.8, at=(2.4, SD * 0.4, 3.4)))
fr.append(kit.box("dj2", 0.3, SD * 0.8, 6.8, at=(5.3, SD * 0.4, 3.4)))
fr.append(kit.box("door", 2.6, 0.15, 6.6, at=(3.85, 0.2, 3.3)))
fr.append(kit.box("push", 0.12, 0.25, 1.6, at=(3.0, 0.42, 3.4)))
put_foot("ShopFront", "ShopFrame", fr, bev=0.04)
gl = [kit.box("g1", 7.6, 0.08, 5.4, at=(-1.5, 0.3, 4.1)), kit.box("g2", 10.6, 0.08, 1.0, at=(0, 0.3, 7.55)),
      kit.box("g3", 2.0, 0.08, 4.2, at=(3.85, 0.3, 4.4))]
put_foot("ShopFront", "ShopGlass", gl, shade=False)
bk = [kit.box("wall", 10.6, 0.1, 6.8, at=(0, 0.05, 4.4))]
for z in (2.6, 4.2, 5.8):  # shelves of goods behind the glass
    bk.append(kit.box("shelf", 6.8, 0.22, 0.14, at=(-1.5, 0.2, z)))
    for k in range(7):
        h = 0.5 + (k * 37 % 5) * 0.12
        bk.append(kit.box("good", 0.62, 0.18, h, at=(-4.6 + k * 1.02, 0.22, z + 0.07 + h / 2)))
put_foot("ShopFront", "ShopBack", bk, shade=False)
sg = [kit.box("board", 10.0, 0.22, 1.9, at=(0, SD + 0.11, SH - 1.25))]
put_foot("ShopFront", "ShopSign", sg, bev=0.05)

# ---- the vending machine (spills its cans when it is smashed): 3.6 wide, 2.4 deep, 6.8 tall, its back at y -1.2
VB = [kit.box("body", 3.6, 2.4, 6.4, at=(0, 0, 3.4))]
put_foot("VendingMachine", "VendBody", VB, bev=0.12)
VT = [kit.box("base", 3.7, 2.5, 0.25, at=(0, 0, 0.12)), kit.box("top", 3.75, 2.55, 0.28, at=(0, 0, 6.7)),
      kit.box("flap", 2.2, 0.12, 0.7, at=(-0.4, 1.24, 0.95)), kit.box("panel", 0.8, 0.12, 2.6, at=(1.25, 1.24, 3.7)),
      kit.box("slot", 0.35, 0.18, 0.12, at=(1.25, 1.3, 4.5)), kit.box("keys", 0.5, 0.16, 0.9, at=(1.25, 1.3, 3.5))]
put_foot("VendingMachine", "VendTrim", VT, bev=0.03)
put_foot("VendingMachine", "VendGlass", [kit.box("glass", 2.3, 0.08, 3.8, at=(-0.45, 1.22, 3.75))], shade=False)
cans = []
for row in range(4):
    for k in range(5):
        cans.append(kit.cyl("c", 0.17, 0.17, 0.6, at=(-1.35 + k * 0.45, 1.0, 2.25 + row * 0.98), segs=8))
put_foot("VendingMachine", "VendCans", cans)
put_foot("VendingMachine", "VendLight", [kit.box("hdr", 3.2, 0.1, 0.55, at=(0, 1.22, 6.15))], shade=False)

# ---- one can (the machine's spill, thrown about by the device)
can = kit.loft("Can", [(0.0, 0.2, 0.2, 0, 0), (0.05, 0.25, 0.25, 0, 0), (0.62, 0.25, 0.25, 0, 0), (0.72, 0.19, 0.19, 0, 0)], segs=12, power=2.0)
put_foot("Can", "Can", [can])

# ---- a manhole cover (the steam vents): 3.2 across, a ring of grip bumps
mh = [kit.cyl("disc", 1.6, 1.6, 0.14, at=(0, 0, 0.07), segs=20), kit.torus("rim", 1.55, 0.07, at=(0, 0, 0.14), segs=20, csegs=4)]
for i in range(-2, 3):
    for j in range(-2, 3):
        if i * i + j * j <= 5:
            mh.append(kit.box("b", 0.36, 0.36, 0.06, at=(i * 0.52, j * 0.52, 0.16)))
put_foot("Manhole", "Manhole", mh)

# ---- the pigeon: body and head one piece, a wing each side (the device flaps them about the shoulder)
body = kit.sphere("body", 0.36, at=(0, 0.0, 0.55), scale=(0.8, 1.25, 0.85), segs=12, rings=8)
head = kit.sphere("head", 0.2, at=(0, 0.42, 0.98), segs=10, rings=7)
beak = kit.cyl("beak", 0.06, 0.01, 0.16, at=(0, 0.63, 0.96), segs=6, axis="Y")
tail = kit.box("tail", 0.3, 0.42, 0.06, at=(0, -0.52, 0.55))
legs = [kit.cyl("leg", 0.035, 0.035, 0.3, at=(x, 0.05, 0.15), segs=4) for x in (-0.1, 0.1)]
put_foot("Pigeon", "PigeonBody", [body, head, beak, tail] + legs)
for side, name in ((-1, "PigeonWingL"), (1, "PigeonWingR")):
    w = kit.loft(name, [(0.0, 0.05, 0.22, 0, 0), (0.25, 0.05, 0.26, 0, -0.05), (0.5, 0.04, 0.2, 0, -0.12), (0.62, 0.02, 0.08, 0, -0.2)],
                 segs=8, power=2.0)
    kit.apply_all(w)
    for v in w.data.vertices:  # the loft runs up z: lay it out sideways from the shoulder
        v.co = Vector((side * v.co.z, v.co.y, v.co.x))
    w.data.update()
    kit.shift(w, (side * 0.22, 0.02, 0.72))
    put_foot("Pigeon", name, [w])

# ---- the news drone: a 3.4-wide quad with a camera under its nose (the device spins the rotors and hovers it)
db = [kit.loft("shell", [(-0.35, 0.55, 0.8, 0, 0), (0.0, 0.75, 1.05, 0, 0), (0.3, 0.62, 0.9, 0, 0), (0.42, 0.3, 0.45, 0, 0)], segs=16, power=2.4)]
put_foot("NewsDrone", "DroneBody", db)
da = []
for sx in (-1, 1):
    for sy in (-1, 1):
        da.append(kit.tube_along("arm", [Vector((0, 0, 0.05)), Vector((sx * 1.3, sy * 1.3, 0.12))], [0.09, 0.07], segs=6))
        da.append(kit.cyl("mot", 0.18, 0.18, 0.3, at=(sx * 1.3, sy * 1.3, 0.15), segs=8))
        da.append(kit.cyl("leg", 0.04, 0.04, 0.6, at=(sx * 0.45, sy * 0.45, -0.6), segs=4))
da.append(kit.sphere("gimbal", 0.26, at=(0, 0.8, -0.35), segs=10, rings=6))
put_foot("NewsDrone", "DroneArm", da)
rot = [kit.box("blade", 1.5, 0.16, 0.03, at=(0, 0, 0)), kit.box("blade2", 0.16, 1.5, 0.03, at=(0, 0, 0)),
       kit.cyl("hub", 0.08, 0.08, 0.08, at=(0, 0, 0), segs=6)]
put_foot("NewsDrone", "DroneRotor", rot)
put_foot("NewsDrone", "DroneEye", [kit.sphere("eye", 0.12, at=(0, 1.02, -0.38), segs=8, rings=6)])

# ---- the roof flag pole: 16 tall, a gold ball on top, a weighted foot (the flag itself is the device's cloth)
fp = [kit.cyl("base", 0.55, 0.65, 0.4, at=(0, 0, 0.2), segs=10), kit.cyl("pole", 0.14, 0.1, 15.6, at=(0, 0, 8.2), segs=8),
      kit.torus("cleat", 0.16, 0.04, at=(0, 0, 2.0), segs=8, csegs=4)]
put_foot("FlagPole", "FlagPole", fp)
put_foot("FlagPole", "FlagFinial", [kit.sphere("ball", 0.3, at=(0, 0, 16.2), segs=10, rings=7)])


# ================================================================ sizes and offsets (Roblox axes: x, up, back)
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def row(name, ob):
    lo, hi = bounds(ob)
    c, size = (lo + hi) / 2, hi - lo
    t = kit.tris(ob)
    return t, "\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f } }, -- %d tris" % (
        name, size.x, size.z, size.y, c.x, c.z, -c.y, t)


rows = []
total = 0
rows.append("\tcover = {")
for look in sorted(cover):
    nom = cover[look]["nominal"]
    rows.append("\t\t%s = {" % look)
    rows.append("\t\t\tnominal = { %.3f, %.3f, %.3f }," % (nom[0], nom[2], nom[1]))
    rows.append("\t\t\tpieces = {")
    for name in sorted(cover[look]["pieces"]):
        t, r = row(name, cover[look]["pieces"][name])
        total += t
        rows.append("\t\t" + r)
    rows.append("\t\t\t},")
    rows.append("\t\t},")
rows.append("\t},")
for look in sorted(foot):
    rows.append("\t%s = {" % look)
    for name in sorted(foot[look]):
        t, r = row(name, foot[look][name])
        total += t
        rows.append(r)
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/life.py: do not edit by hand.",
    "-- The living-world set (ReplicatedStorage.Art.Life). cover: looks drawn over one of the city's boxes; each",
    "-- piece's size and centre are in studs round the look's nominal box (x, up, back), and Shared.LifeKit scales",
    "-- them by the real box over the nominal one. The rest are foot looks like Config.StreetArt: each piece's size",
    "-- and its centre from the look's foot point (x, up, back; a look faces -z).",
    "return {",
] + rows + ["}", ""])
with open(os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "LifeArt.luau")), "w") as f:
    f.write(text)
print("life set:", total, "tris")

ALL = {}
for look in cover:
    for name, ob in cover[look]["pieces"].items():
        ALL[name] = ob
for look in foot:
    for name, ob in foot[look].items():
        ALL[name] = ob

if "--no-export" not in sys.argv:
    export = []
    for name, ob in ALL.items():
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.name = name + "_x"
        kit.centre(cp)
        cp.name = name
        cp.data.name = name
        export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Life.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

COVER, FOOT = cover, foot
