# powers.py: the power summons, rides and forms as Blender meshes (list-combat 2026-11-20, Everything Left 168-182
# and 290: "a few blocks each"). Each look is built in Roblox studs about the point the game anchors it on (the
# summon's spot, the rider's root, the column's foot), so Fx.PowerMeshes puts every mesh at its offset from there.
#   Turret (Turret Drop), Drone (Fix-It Drone; the repair drones too), Totem (Ward Totem), Mine (Shock Mines),
#   Guardian (Guardian Jab, the Ascended Guardian), SpiritBeast (Spirit Ride), Hoverboard, RockSlab (Rock Ride),
#   StonePillar (Stone Pillar), ThornVine (Overgrowth), Wave (Tsunami, Wave Surf), Mech (the Mech Suit's shell on
#   the hero's torso, lower arms and lower legs: each piece drawn round a unit body part, the game scales it to the
#   part).
# Meshes marked tint take the caster's path colour in the game (the colour here is the preview's).
# Output: art/export/Powers.fbx and src/config/PowerArt.luau (generated); --preview renders art/preview/powers.png.
# Run: ~/tools/bpyenv/bin/python art/blender/powers.py [--preview] [--no-export]
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

TINT = set()
PATH = (150, 90, 235)  # the preview's stand-in path colour
SPIRIT = (120, 220, 255)
random.seed(7)


def tint(name):
    TINT.add(name)
    return name


def lumpy(ob, amount, seed=0):
    """Rough a rock up: push each vertex in or out along its direction from the centre by a seeded noise."""
    rnd = random.Random(seed)
    cache = {}

    def fn(v):
        key = (round(v.x, 2), round(v.y, 2), round(v.z, 2))
        if key not in cache:
            cache[key] = 1 + (rnd.random() * 2 - 1) * amount
        c = Vector((0, 0, v.z * 0.0))
        return c + (v - c) * cache[key]

    return kit.deform(ob, fn)


# ================================================================ Turret Drop: a tripod gun turret (anchor: 3 above ground)
legs = [C(0.75, 0.7, 0, -1.55, 0, segs=12)]
for i in range(3):
    a = math.radians(90 + i * 120)
    x, z = math.cos(a) * 2.1, math.sin(a) * 2.1
    legs.append(T([(0, -1.6, 0), (x * 0.6, -2.2, z * 0.6), (x, -2.9, z)], [0.2, 0.17, 0.14], segs=8))
    legs.append(C(0.32, 0.18, x, -2.92, z, segs=10))
mesh("Turret", "TurretLegs", legs, CHARCOAL, "Metal")
head = [
    C(0.9, 0.35, 0, -1.05, 0, segs=16),
    B(2.2, 1.3, 2.4, 0, -0.2, 0.1, bev=0.18),
    B(2.5, 0.35, 1.6, 0, 0.55, 0.3, bev=0.1),
    B(0.35, 1.0, 1.8, -1.2, -0.2, 0.2, bev=0.08),
    B(0.35, 1.0, 1.8, 1.2, -0.2, 0.2, bev=0.08),
]
mesh("Turret", "TurretHead", head, STEEL, "Metal")
barrels = []
for x in (-0.45, 0.45):
    barrels.append(C(0.22, 2.4, x, -0.3, -2.1, segs=10, axis="z"))
    barrels.append(C(0.3, 0.35, x, -0.3, -3.3, segs=10, axis="z"))
    barrels.append(C(0.3, 0.5, x, -0.3, -1.1, segs=10, axis="z"))
mesh("Turret", "TurretBarrels", barrels, BLACK, "Metal")
mesh("Turret", tint("TurretLight"), [B(1.4, 0.22, 0.12, 0, 0.12, -1.12, bev=0.04)], PATH, "Neon")

# ================================================================ Fix-It Drone (and the repair drones): anchor its centre
body = S(0.95, 0, 0, 0, sc=(1, 0.72, 1), segs=18, rings=10)
belly = C(0.6, 0.35, 0, -0.62, 0, segs=14)
mesh("Drone", "DroneBody", [body, belly, TOR(0.82, 0.09, 0, 0.05, 0, segs=24, csegs=6)], WHITE)
rot = []
for sx, sz in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
    x, z = sx * 1.45, sz * 1.45
    rot.append(T([(sx * 0.6, 0.15, sz * 0.6), (x, 0.4, z)], [0.12, 0.1], segs=6))
    rot.append(TOR(0.75, 0.07, x, 0.45, z, segs=20, csegs=5))
    rot.append(C(0.12, 0.3, x, 0.45, z, segs=8))
    rot.append(B(1.3, 0.04, 0.22, x, 0.62, z))
mesh("Drone", "DroneRotors", rot, CHARCOAL, "Metal")
mesh("Drone", tint("DroneEye"), [S(0.32, 0, -0.05, -0.82, sc=(1, 1, 0.6), segs=12, rings=8)], SPARK, "Neon")
claw = [C(0.18, 0.5, 0, -0.95, 0, segs=8)]
for sx in (-1, 1):
    claw.append(T([(0, -1.15, 0), (sx * 0.35, -1.5, -0.05), (sx * 0.2, -1.85, -0.1)], [0.1, 0.09, 0.06], segs=6))
mesh("Drone", "DroneClaw", claw, STEEL, "Metal")

# ================================================================ Ward Totem: a carved post with a glowing crest (anchor: 3 above ground)
pole = [C(0.75, 0.5, 0, -2.75, 0, segs=10)]
for i, y in enumerate((-2.0, -0.6, 0.8, 2.1)):
    pole.append(C(0.62 - i * 0.04, 1.25, 0, y, 0, segs=8))
    pole.append(C(0.74 - i * 0.04, 0.2, 0, y + 0.62, 0, segs=8))
for sx in (-1, 1):
    pole.append(prism([(-0.25, 1.4), (0.25, 1.4), (0.1, 2.2), (-0.1, 1.9)], 0.5 * sx, 1.6 * sx))
mesh("Totem", "TotemPole", pole, WOOD, "Wood")
mesh("Totem", tint("TotemCrest"), [star(0.95, 0.42, 0.35, 0, 3.6, 0, points=6), S(0.42, 0, 3.6, 0, segs=10, rings=6)], PATH, "Neon")

# ================================================================ Shock Mine: a squat disc with a light (anchor: its centre)
shell = [C(0.75, 0.32, 0, 0, 0, segs=16, r2=0.62)]
for i in range(6):
    a = i * math.pi / 3
    shell.append(B(0.2, 0.18, 0.4, math.cos(a) * 0.72, -0.05, math.sin(a) * 0.72))
mesh("Mine", "MineShell", shell, CHARCOAL, "Metal")
mesh("Mine", tint("MineLight"), [S(0.3, 0, 0.2, 0, sc=(1, 0.6, 1), segs=10, rings=6)], PATH, "Neon")

# ================================================================ the spirit guardian: a broad-shouldered spirit that trails off in a wisp
# (anchor: the bottom of its wisp; about 11 studs tall)
torso = S(1.0, 0, 7.4, 0, sc=(2.5, 1.7, 1.45), segs=16, rings=10)
belly = C(1.7, 2.6, 0, 5.0, 0.1, segs=14, r2=0.0)
turn(belly, "x", 180, pivot=(0, 5.0, 0.1))
tail = T([(0, 4.2, 0), (0.3, 2.5, 0.6), (-0.2, 1.0, 1.2), (0.1, 0.0, 1.8)], [1.5, 1.0, 0.5, 0.06], segs=10)
headp = S(1.3, 0, 10.0, -0.1, sc=(1, 1.05, 0.95), segs=14, rings=10)
horn = T([(0, 10.9, 0.3), (0, 11.9, 0.9), (0, 12.4, 2.0)], [0.45, 0.3, 0.05], segs=8)
arms = []
for sx in (-1, 1):
    arms.append(S(1.0, sx * 2.6, 8.3, 0, segs=12, rings=8))
    arms.append(T([(sx * 2.8, 8.0, 0), (sx * 3.6, 6.4, -0.4), (sx * 3.8, 4.8, -1.0)], [0.75, 0.65, 0.6], segs=10))
    arms.append(S(1.05, sx * 3.85, 4.3, -1.2, sc=(1, 1.1, 1), segs=12, rings=8))
mesh("Guardian", tint("GuardianForm"), [torso, belly, tail, headp, horn] + arms, SPIRIT, "Neon", alpha=0.45)
core = [B(0.75, 0.16, 0.12, -0.45, 10.15, -1.2), B(0.75, 0.16, 0.12, 0.45, 10.15, -1.2), S(0.55, 0, 7.2, -1.55, segs=10, rings=6)]
mesh("Guardian", "GuardianCore", core, WHITE, "Neon")

# ================================================================ Spirit Ride: a spirit wolf the hero stands on (anchor: the rider's root;
# its back at 3.4 below)
Y0 = -3.4
wolf = loft_z([(3.6, 0.5, Y0 - 1.2, Y0 - 0.4), (2.6, 1.3, Y0 - 2.1, Y0 + 0.1), (0.0, 1.5, Y0 - 2.4, Y0 + 0.2), (-2.4, 1.4, Y0 - 2.3, Y0 + 0.3), (-3.4, 0.9, Y0 - 1.8, Y0 + 0.6)], segs=14)
whead = S(1.0, 0, Y0 + 1.0, -4.3, sc=(0.95, 0.9, 1.2), segs=12, rings=8)
snout = C(0.55, 1.3, 0, Y0 + 0.75, -5.4, segs=10, r2=0.32, axis="z")
ears = [T([(sx * 0.5, Y0 + 1.6, -4.1), (sx * 0.65, Y0 + 2.5, -3.9)], [0.35, 0.02], segs=6) for sx in (-1, 1)]
wtail = T([(0, Y0 - 0.6, 3.4), (0.4, Y0 + 0.3, 5.0), (-0.3, Y0 + 1.4, 6.2), (0.2, Y0 + 2.0, 6.8)], [0.7, 0.8, 0.5, 0.05], segs=10)
wlegs = []
for sx in (-1, 1):
    for z in (-2.2, 2.0):
        wlegs.append(T([(sx * 1.0, Y0 - 1.8, z), (sx * 1.1, Y0 - 3.0, z + 0.4), (sx * 0.9, Y0 - 3.8, z + 1.3)], [0.5, 0.35, 0.05], segs=8))
mesh("SpiritBeast", tint("BeastForm"), [wolf, whead, snout, wtail] + ears + wlegs, SPIRIT, "Neon", alpha=0.45)
mesh("SpiritBeast", "BeastEyes", [S(0.2, sx * 0.45, Y0 + 1.25, -5.05, segs=8, rings=6) for sx in (-1, 1)], WHITE, "Neon")

# ================================================================ Hoverboard (anchor: the rider's root; the deck at 3.4 below)
deck = loft_z([(-3.6, 0.6, Y0 - 0.1, Y0 + 0.35), (-3.0, 1.15, Y0 - 0.25, Y0 + 0.05), (0.0, 1.3, Y0 - 0.3, Y0), (3.0, 1.15, Y0 - 0.25, Y0 + 0.05), (3.6, 0.6, Y0 - 0.1, Y0 + 0.35)], segs=12, power=3.2)
grip = B(2.0, 0.06, 5.2, 0, Y0 + 0.02, 0)
mesh("Hoverboard", "BoardDeck", [deck, grip], CHARCOAL, "Metal")
mesh("Hoverboard", tint("BoardGlow"), [B(0.25, 0.1, 5.6, sx * 0.85, Y0 - 0.34, 0) for sx in (-1, 1)] + [C(0.55, 0.08, 0, Y0 - 0.36, z, segs=14) for z in (-1.6, 1.6)], PATH, "Neon")
jets = []
for sx in (-0.6, 0.6):
    jets.append(C(0.32, 1.1, sx, Y0 - 0.45, 3.1, segs=10, r2=0.38, axis="z"))
    jets.append(TOR(0.33, 0.07, sx, Y0 - 0.45, 3.68, axis="z", segs=12, csegs=5))
mesh("Hoverboard", "BoardJets", jets, STEEL, "Metal")

# ================================================================ Rock Ride: a craggy slab of street rock (anchor: the rider's root)
slab = S(1.0, 0, 0.25, 0, sc=(3.1, 0.9, 4.1), segs=14, rings=8)
lumpy(slab, 0.2, seed=3)
slab = kit.cut(slab, (0, 0, 1), keep_positive=False)  # flat top under the feet
shift(slab, rb(0, Y0, 0))
mesh("RockSlab", "RockBody", [slab], ROCK, "Slate", shade=False)
cracks = []
for i in range(5):
    a = i * 1.25 + 0.3
    pts = [(math.cos(a) * 0.5, Y0 + 0.02, math.sin(a) * 0.7)]
    for k in range(1, 4):
        pts.append((math.cos(a + k * 0.15) * (0.5 + k * 0.8), Y0 + 0.02, math.sin(a - k * 0.12) * (0.7 + k * 1.05)))
    cracks.append(T(pts, [0.14, 0.12, 0.09, 0.04], segs=5))
mesh("RockSlab", tint("RockVeins"), cracks, (240, 160, 70), "Neon")

# ================================================================ Stone Pillar: a cluster of basalt columns (anchor: its centre; the game
# stretches it to the pillar's height)
cols = []
for i, (x, z, r, h) in enumerate(((0, 0, 1.25, 10), (1.35, 0.6, 0.8, 8.8), (-1.2, 0.9, 0.85, 9.3), (0.3, -1.4, 0.8, 9.0), (-0.9, -1.0, 0.65, 8.2), (1.2, -0.9, 0.6, 8.5))):
    cols.append(C(r, h, x, h / 2 - 5, z, segs=6))
    cols.append(C(r * 0.98, 0.3, x, h - 5 + 0.1, z, segs=6, r2=r * 0.7))
mesh("StonePillar", "PillarStone", cols, (120, 108, 96), "Slate", shade=False)

# ================================================================ Overgrowth: a curling thorny vine (anchor: its centre; 1 x 10 x 1, the game
# stretches it up)
vpts = [(0, -5, 0), (0.25, -2.5, 0.1), (-0.15, 0, -0.2), (0.3, 2.5, 0.15), (0.0, 4.4, 0.45), (-0.35, 5, 0.9)]
vine = T(vpts, [0.55, 0.48, 0.4, 0.32, 0.2, 0.05], segs=8)
thorns = []
for i in range(10):
    t = i / 10
    y = -4.4 + t * 8.6
    a = i * 2.3
    x, z = math.cos(a), math.sin(a)
    r = 0.5 - t * 0.28
    thorns.append(C(0.16, 0.7, 0, 0, 0, segs=6, r2=0.0, axis="x"))
    ob = thorns[-1]
    turn(ob, "up", math.degrees(-a))
    turn(ob, "z", 25)
    shift(ob, rb(x * (r + 0.25), y, z * (r + 0.25)))
leaves = [S(0.45, 0.55, 1.2, 0, sc=(1, 0.25, 0.55), segs=8, rings=5), S(0.4, -0.5, -1.6, 0.1, sc=(1, 0.25, 0.55), segs=8, rings=5)]
mesh("ThornVine", "VineStem", [vine] + thorns + leaves, (64, 132, 58), "Grass")
petals = []
for i in range(5):
    p = S(0.32, 0, 0, 0, sc=(0.6, 0.2, 1.1), segs=8, rings=5)
    shift(p, rb(0, 0, -0.35))
    turn(p, "x", -35)
    turn(p, "up", i * 72)
    shift(p, rb(-0.35, 5.0, 0.9))
    petals.append(p)
mesh("ThornVine", tint("VineBloom"), petals + [S(0.18, -0.35, 5.05, 0.9, segs=8, rings=5)], (250, 120, 160))

# ================================================================ Tsunami and Wave Surf: a breaking wave (anchor: its centre; 8 wide, the
# game stretches it to the line's width). Its front (the curl) faces -z.
prof = [(2.6, -5), (1.8, -2.0), (0.8, 1.2), (-0.2, 3.6), (-1.4, 4.9), (-2.6, 4.7), (-3.4, 3.7), (-3.0, 2.9), (-2.2, 3.1), (-1.2, 2.9), (-0.4, 1.8), (-0.3, 0), (-0.8, -2.6), (-1.6, -5)]
wave = prism([(z, y) for (z, y) in prof], -4, 4)
mesh("Wave", tint("WaveWater"), [wave], (60, 150, 230), "Glass", alpha=0.3, shade=False)
foam = [T([(x, 4.5, -1.3 + 0.2 * math.sin(x * 2)) for x in (-4, -2.5, -1, 0.5, 2, 3.5, 4)], [0.45, 0.6, 0.5, 0.65, 0.5, 0.6, 0.45], segs=8)]
for x in (-3.2, -1.6, 0.2, 1.8, 3.3):
    foam.append(S(0.45, x, 3.9, -2.6, segs=8, rings=6))
mesh("Wave", "WaveFoam", foam, WHITE)

# ================================================================ the Mech Suit's shell, drawn round unit body parts: chest round a torso of
# 2 x 2 x 1, an arm piece round a lower arm of 1 x 1 x 1, a leg piece round a lower leg of 1 x 1 x 1 (each centred)
chest = [B(2.3, 1.4, 1.3, 0, 0.35, 0, bev=0.15), B(1.8, 0.7, 1.2, 0, -0.55, 0, bev=0.12)]
for sx in (-1, 1):
    chest.append(S(0.8, sx * 1.3, 0.9, 0, sc=(1, 0.75, 0.95), segs=12, rings=8))
pack = [B(1.6, 1.6, 0.6, 0, 0.2, 0.85, bev=0.12)] + [C(0.28, 1.0, sx * 0.5, -0.5, 1.05, segs=10, r2=0.34) for sx in (-1, 1)]
mesh("Mech", "MechChest", chest + pack, (210, 216, 226), "Metal")
mesh("Mech", tint("MechCore"), [C(0.35, 0.12, 0, 0.45, -0.68, segs=12, axis="z")] + [C(0.22, 0.08, sx * 0.5, -1.04, 1.05, segs=10) for sx in (-1, 1)], PATH, "Neon")
arm = [C(0.68, 1.1, 0, 0, 0, segs=10, r2=0.6), TOR(0.66, 0.1, 0, 0.5, 0, segs=14, csegs=5), B(0.3, 0.8, 0.5, 0.62, 0.05, 0, bev=0.06)]
mesh("Mech", "MechArm", arm, (210, 216, 226), "Metal")
leg = [C(0.62, 1.05, 0, 0.0, 0, segs=10, r2=0.7), B(0.9, 0.6, 0.35, 0, 0.2, -0.62, bev=0.1), C(0.75, 0.25, 0, -0.55, 0, segs=10)]
mesh("Mech", "MechLeg", leg, (210, 216, 226), "Metal")


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
        rgb, mat, alpha = INFO[name]
        extra = (", alpha = %g" % alpha) if alpha else ""
        extra += ", tint = true" if name in TINT else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat, extra, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/powers.py: do not edit by hand.",
    "-- The power summons, rides and forms in Blender meshes (ReplicatedStorage.Art.Powers, Fx.PowerMeshes): look -> mesh ->",
    "-- its size and its centre from the look's anchor, in studs (x, up, z), its colour, material, transparency, tint (takes",
    "-- the caster's path colour) and triangles. %d meshes in %d looks, %d triangles." % (len(INFO), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "PowerArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)
print("powers: %d looks, %d meshes, %d tris" % (len(LOOKS), len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Powers.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

# ================================================================ preview: every look in a row, lit, in its game colours
if "--preview" in sys.argv:
    kit.studio(res=(1600, 700), samples=24)
    spots = {"Turret": (-14, 6, 3), "Drone": (-8, 6, 4), "Totem": (-2, 6, 3), "Mine": (3, 6, 0.5), "Mech": (8, 6, 1.2),
             "Guardian": (15, 8, 0), "SpiritBeast": (-15, -6, 7.8), "Hoverboard": (-6, -6, 3.7), "RockSlab": (2, -6, 4.6),
             "StonePillar": (9, -6, 5), "ThornVine": (13, -6, 5), "Wave": (19, -6, 5)}
    for look, meshes in LOOKS.items():
        x, yb, y = spots[look]
        for name, ob in meshes.items():
            rgb, mat, alpha = INFO[name]
            m = kit.material("m_" + name, rgb, metal=0.6 if mat == "Metal" else 0.0, rough=0.4, emit=2.0 if mat == "Neon" else 0.0)
            if alpha:
                m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - alpha
            ob.data.materials.append(m)
            ob.location = (x, yb, y)
            ob.rotation_euler = (0, 0, math.radians({"SpiritBeast": 100, "Wave": 235, "Guardian": 215}.get(look, 35)))
    ground = kit.box("ground", 120, 60, 0.2, at=(2, 0, -0.1))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    kit.camera((2, -48, 22), (2, 0, 3), lens=30)
    kit.render(os.path.join(kit.ROOT, "preview", "powers.png"))
