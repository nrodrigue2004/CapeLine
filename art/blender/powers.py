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


# ================================================================ Flame Jets (Everything Left 382, 2026-11-20): two boot thrusters under the
# hero's feet, flared nozzles with cooling rings and a glowing throat (anchor: the rider's root; the soles at 3.4 below)
jet = []
throat = []
for sx in (-0.6, 0.6):
    jet.append(C(0.42, 0.55, sx, Y0 - 0.35, 0, segs=14, r2=0.4))  # the collar under the sole
    jet.append(C(0.38, 0.9, sx, Y0 - 1.05, 0, segs=14, r2=0.5))  # the flared bell
    for k, y in enumerate((Y0 - 0.75, Y0 - 1.15)):
        jet.append(TOR(0.42 + k * 0.05, 0.05, sx, y, 0, segs=16, csegs=4))
    jet.append(B(0.14, 0.5, 0.5, sx + (0.42 if sx > 0 else -0.42), Y0 - 0.55, 0, bev=0.04))  # a fin out the side
    throat.append(C(0.3, 0.08, sx, Y0 - 1.48, 0, segs=12))
mesh("FlameJets", "JetNozzles", jet, STEEL, "Metal")
mesh("FlameJets", tint("JetThroats"), throat, PATH, "Neon")

# ================================================================ Light Rail (Everything Left 382): a glowing rail of light 14 long under the
# feet, a bright spine on hard-light ties that fade out ahead and behind (anchor: the rider's root; the spine at
# 3.4 below, running from 4 behind to 10 ahead)
spine = [B(0.42, 0.22, 14, 0, Y0 - 0.05, -3)]
spine += [B(0.12, 0.12, 14, sx * 0.45, Y0 - 0.05, -3) for sx in (-1, 1)]
mesh("LightRail", tint("RailSpine"), spine, PATH, "Neon")
ties = []
for i in range(8):
    z = 3.4 - i * 1.8
    ties.append(B(1.6 - abs(i - 3.5) * 0.12, 0.12, 0.3, 0, Y0 - 0.25, z, bev=0.04))
ties.append(prism([(-0.5, Y0 - 0.25), (0.5, Y0 - 0.25), (0, Y0 - 0.65)], 3.9, -9.9))
mesh("LightRail", "RailTies", ties, WHITE, "Neon", alpha=0.35)

# ================================================================ Psi Platform (Everything Left 382): a torn-up slab of street held by the
# mind: asphalt over a broken concrete edge with a lane stripe and bent rebar (anchor: the rider's root; the top at
# 3.4 below; the crate and barrel stay the street kit's props riding its corners)
road = S(1.0, 0, 0, 0, sc=(3.1, 0.75, 3.1), segs=12, rings=8)
lumpy(road, 0.12, seed=11)
road = kit.cut(road, (0, 0, 1), keep_positive=False)
shift(road, rb(0, Y0, 0))
mesh("PsiSlab", "SlabRock", [road], (100, 98, 104), "Concrete", shade=False)
mesh("PsiSlab", "SlabAsphalt", [B(5.6, 0.12, 5.6, 0, Y0 + 0.04, 0, bev=0.05)], (52, 54, 60), "Asphalt")
mesh("PsiSlab", "SlabStripe", [B(0.35, 0.03, 1.4, 0, Y0 + 0.11, z) for z in (-2.0, 0.0, 2.0)], (245, 205, 60))
rebar = [T([(x, Y0 - 0.6, 2.5), (x + 0.2, Y0 - 0.9, 3.4), (x + 0.6, Y0 - 1.0, 3.8)], [0.07, 0.06, 0.05], segs=5)
         for x in (-1.2, 0.1, 1.3)]
mesh("PsiSlab", "SlabRebar", rebar, (120, 80, 60), "Metal")
mesh("PsiSlab", tint("SlabAura"), [TOR(3.3, 0.08, 0, Y0 - 1.3, 0, segs=36, csegs=5)], PATH, "Neon", alpha=0.3)

# ================================================================ Gunslinger's bullet (Everything Left 173, 2026-11-20): a copper round-nose
# slug and a tapered tracer streak behind it (anchor: the slug's centre; front -z, the streak along +z). CombatFx's
# tracer head flies both.
slug = [C(0.1, 0.26, 0, 0, 0.02, segs=12, axis="z"), S(0.1, 0, 0, -0.11, sc=(1, 1, 1.6), segs=12, rings=8),
        C(0.105, 0.05, 0, 0, 0.16, segs=12, axis="z")]
mesh("Bullet", "BulletSlug", slug, (205, 120, 60), "Metal")
mesh("Bullet", tint("BulletStreak"), [C(0.16, 4.0, 0, 0, 2.2, segs=10, r2=0.0, axis="z")], PATH, "Neon", alpha=0.2)

# ================================================================ Sunfall's sun (Everything Left 169, 2026-11-20): a lumpy glowing core and a
# corona of flame spikes all round it (anchor: the sun's centre). CombatFx sizes the core and the corona apart.
core = S(1.0, 0, 0, 0, segs=24, rings=16)
lumpy(core, 0.05, seed=3)
mesh("Sun", "SunCore", [core], (255, 236, 160), "Neon")
spikes = []
N = 26
for i in range(N):  # a fibonacci sphere of directions, long and short spikes in turn
    yv = 1 - 2 * (i + 0.5) / N
    rr = math.sqrt(1 - yv * yv)
    a = i * math.pi * (3 - math.sqrt(5))
    d = Vector((math.cos(a) * rr, yv, math.sin(a) * rr))
    ln = 1.0 if i % 2 == 0 else 0.6
    side = d.cross(Vector((0, 1, 0)) if abs(yv) < 0.9 else Vector((1, 0, 0))).normalized() * 0.12
    pts = [d * 0.85, d * (1.0 + ln * 0.5) + side, d * (1.0 + ln)]
    spikes.append(T([tuple(v) for v in pts], [0.3, 0.16, 0.01], segs=8))
spikes.append(S(1.05, 0, 0, 0, segs=20, rings=12))
mesh("Sun", tint("SunCorona"), spikes, (255, 140, 40), "Neon", alpha=0.3)

# ================================================================ Singularity's black hole (Everything Left 180): a flat accretion disc with three
# spiral arms and a bright photon ring round the dark centre (anchor: the hole's centre; the disc in the x-z plane,
# 2 across). CombatFx spins it and keeps its dark ball in the middle.
disc = TOR(0.66, 0.3, 0, 0, 0, segs=48, csegs=10)
kit.apply_all(disc)
for v in disc.data.vertices:
    v.co.z *= 0.12  # Blender z is Roblox up: flatten to a disc
disc.data.update()
arms = []
for k in range(3):
    pts, radii = [], []
    for j in range(13):
        t = j / 12
        a = k * 2 * math.pi / 3 + t * 2.6
        r = 0.32 + 0.72 * t
        pts.append((math.cos(a) * r, 0.05 * (1 - t), math.sin(a) * r))
        radii.append(0.1 * (1 - t) + 0.015)
    arms.append(T(pts, radii, segs=6))
mesh("BlackHole", tint("HoleDisc"), [disc] + arms, PATH, "Neon", alpha=0.35)
mesh("BlackHole", "HoleRing", [TOR(0.34, 0.04, 0, 0, 0, segs=36, csegs=6),
                               TOR(0.3, 0.025, 0, 0, 0, axis="x", segs=32, csegs=5)], WHITE, "Neon")

# ================================================================ Heavenfall's ki rings and the Ki Blast's halo (Everything Left 177): a ring of
# ki with flame tongues trailing back along +z (anchor: the ring's centre; the ring faces z, 2 across)
tongues = [TOR(1.0, 0.09, 0, 0, 0, axis="z", segs=40, csegs=6)]
for i in range(14):
    a = 2 * math.pi * i / 14
    c, sn = math.cos(a), math.sin(a)
    ln = 0.9 if i % 2 == 0 else 0.55
    tongues.append(T([(c * 1.0, sn * 1.0, 0.0), (c * 1.14, sn * 1.14, ln * 0.45), (c * 1.06 + sn * 0.08,
                      sn * 1.06 - c * 0.08, ln)], [0.16, 0.09, 0.01], segs=6))
mesh("KiRing", tint("KiRingBand"), tongues, (255, 210, 90), "Neon", alpha=0.2)

# ================================================================ the fields' rims (Everything Left 169, 183): Ember Ring's ring of flame tongues
# and Halo Blades' circle of light blades (anchor: the field's centre on the ground; radius 1, CombatFx scales it
# to the field's radius)
flames = [TOR(1.0, 0.035, 0, 0.02, 0, segs=48, csegs=5)]
for i in range(20):
    a = 2 * math.pi * i / 20
    c, sn = math.cos(a), math.sin(a)
    h = 0.32 if i % 2 == 0 else 0.2
    flames.append(T([(c, 0.0, sn), (c * 1.02 - sn * 0.03, h * 0.5, sn * 1.02 + c * 0.03), (c * 0.98 + sn * 0.04, h, sn * 0.98 - c * 0.04)],
                    [0.07, 0.045, 0.004], segs=6))
mesh("EmberRim", tint("EmberFlames"), flames, (255, 120, 40), "Neon", alpha=0.15)
blades = [TOR(1.0, 0.02, 0, 0.02, 0, segs=48, csegs=4)]
for i in range(8):
    a = 2 * math.pi * i / 8
    c, sn = math.cos(a), math.sin(a)
    # a curved blade standing on the ring, leaning along it like a turning sawtooth
    pts = []
    for j in range(7):
        t = j / 6
        b = a + t * 0.32
        pts.append((math.cos(b) * (1.0 + 0.04 * t), 0.06 + 0.36 * math.sin(t * math.pi * 0.5), math.sin(b) * (1.0 + 0.04 * t)))
    tube = T(pts, [0.055, 0.06, 0.055, 0.045, 0.03, 0.015, 0.002], segs=6)
    kit.apply_all(tube)
    for v in tube.data.vertices:  # flatten each blade across the ring (thin, like a blade's edge)
        r = math.hypot(v.co.x, v.co.y)
        if r > 1e-6:
            k = 1.0 + (r - 1.02) * -0.65
            v.co.x *= k
            v.co.y *= k
    tube.data.update()
    blades.append(tube)
mesh("HaloRim", tint("HaloBlades"), blades, (255, 240, 170), "Neon", alpha=0.1)
# Static Field's rim (Everything Left 167, 2026-11-20): a crackling ring with jagged lightning arcs leaping up off it,
# each a zigzag that forks near its top (radius 1 like the others)
arcs = [TOR(1.0, 0.025, 0, 0.02, 0, segs=48, csegs=4)]
rnd = __import__("random").Random(167)
for i in range(12):
    a = 2 * math.pi * (i + rnd.uniform(-0.2, 0.2)) / 12
    c, sn = math.cos(a), math.sin(a)
    tx, tz = -sn, c  # along the ring
    h = rnd.uniform(0.26, 0.42)
    pts = []
    for j in range(6):
        t = j / 5
        off = 0.0 if j in (0, 5) else (0.05 if j % 2 else -0.05) + rnd.uniform(-0.02, 0.02)
        r = 1.0 + rnd.uniform(-0.015, 0.015) * (j > 0)
        pts.append((c * r + tx * off, h * t, sn * r + tz * off))
    arcs.append(T(pts, [0.03, 0.026, 0.022, 0.018, 0.012, 0.002], segs=5))
    # a fork off the upper half, out to the side
    f0 = pts[3]
    side = 1 if i % 2 else -1
    arcs.append(T([f0, (f0[0] + tx * 0.07 * side, f0[1] + h * 0.15, f0[2] + tz * 0.07 * side),
                   (f0[0] + tx * 0.05 * side + c * 0.03, f0[1] + h * 0.28, f0[2] + tz * 0.05 * side + sn * 0.03)],
                  [0.016, 0.01, 0.001], segs=4))
mesh("VoltRim", tint("StaticArcs"), arcs, (150, 220, 255), "Neon", alpha=0.1)

# ================================================================ the flying heads (Everything Left 381, 2026-11-20): what a bolt throws, in place of
# boxes and balls (CombatFx PIECE): an ice crystal, a chipped stone, a kunai, a fireball and a water glob. Each flies
# nose first along -z (anchor: its centre); CombatFx stretches each to the piece's old box so sizes stay the same
# a long hexagonal ice crystal, faceted, with two smaller crystals growing off its flank
def crystal(r, nose, tail, x=0.0, y=0.0, z=0.0, tilt=0.0, yaw=0.0):
    def hexr(k, zz):
        return [(x + r * k * math.cos(math.pi / 3 * i + 0.3), y + r * k * math.sin(math.pi / 3 * i + 0.3), zz) for i in range(6)]
    ob = rings_mesh([hexr(0.02, z - nose), hexr(1.0, z - nose * 0.55), hexr(0.92, z + tail * 0.6), hexr(0.02, z + tail)])
    return ob
spike = [crystal(0.22, 0.7, 0.55)]
mesh("Heads", tint("HeadSpike"), spike, (170, 230, 255), "Glass", alpha=0.15)
rock = B(1.0, 0.8, 0.9, 0, 0, 0)
kit.bevel(rock, 0.12, 1)
kit.apply_all(rock)
rr = random.Random(381)
for _ in range(5):  # knock its corners off
    n = Vector((rr.uniform(-1, 1), rr.uniform(-1, 1), rr.uniform(-1, 1))).normalized()
    shift(rock, tuple(-n * 0.42))
    kit.cut(rock, n, keep_positive=False)
    shift(rock, tuple(n * 0.42))
mesh("Heads", tint("HeadRock"), [rock], (150, 120, 90), "Slate")
# a kunai: a diamond blade, a wrapped grip and a ring at the back
blade = rings_mesh([[(0.002, 0, -0.8), (0, 0.001, -0.8), (-0.002, 0, -0.8), (0, -0.001, -0.8)],
                    [(0.11, 0, -0.25), (0, 0.025, -0.25), (-0.11, 0, -0.25), (0, -0.025, -0.25)],
                    [(0.04, 0, 0.0), (0, 0.02, 0.0), (-0.04, 0, 0.0), (0, -0.02, 0.0)]])
grip = C(0.035, 0.42, 0, 0, 0.21, segs=8, axis="z")
ring = TOR(0.07, 0.018, 0, 0, 0.5, axis="x", segs=14, csegs=5)
mesh("Heads", tint("HeadKunai"), [blade, grip, ring], (60, 60, 72), "Metal")
# a fireball: a round head that trails off into flame tongues behind it
fire = [S(0.5, 0, 0, -0.05, sc=(1, 1, 1), segs=14, rings=10)]
for i in range(6):
    a = 2 * math.pi * i / 6
    c, sn = math.cos(a), math.sin(a)
    fire.append(T([(c * 0.32, sn * 0.32, 0.0), (c * 0.46 + sn * 0.1, sn * 0.46 - c * 0.1, 0.45), (c * 0.34 + sn * 0.16, sn * 0.34 - c * 0.16, 0.95)],
                  [0.22, 0.14, 0.01], segs=7))
fire.append(T([(0, 0, 0.1), (0, 0.05, 0.6), (0, 0, 1.15)], [0.3, 0.18, 0.01], segs=8))
mesh("Heads", tint("HeadFlame"), fire, (255, 140, 40), "Neon", alpha=0.15)
# a water glob: a teardrop, round in front, pulled out behind
mesh("Heads", tint("HeadDrop"), [loft_z([(-0.5, 0.01, -0.01, 0.01), (-0.42, 0.28, -0.28, 0.28), (-0.2, 0.42, -0.42, 0.42),
                                        (0.05, 0.4, -0.4, 0.4), (0.3, 0.26, -0.26, 0.26), (0.6, 0.09, -0.09, 0.09),
                                        (0.8, 0.01, -0.01, 0.01)], segs=14, power=2.0)],
     (80, 170, 255), "Glass", alpha=0.2)

# Light's lance: a long fluted spear of light with a diamond tip and two flanges (nose at -z)
def hexring(r, z, n=6, rot=0.0):
    return [(r * math.cos(2 * math.pi * i / n + rot), r * math.sin(2 * math.pi * i / n + rot), z) for i in range(n)]
lance = [rings_mesh([hexring(0.01, -3.0), hexring(0.22, -2.3), hexring(0.09, -2.0), hexring(0.08, 2.6), hexring(0.01, 3.0)])]
for zf in (-1.7, 1.9):
    lance.append(TOR(0.16, 0.035, 0, 0, zf, axis="z", segs=16, csegs=5))
mesh("Heads", tint("HeadLance"), lance, (255, 240, 170), "Neon", alpha=0.05)
# Mind's psi ring: a ring face-on to its flight (in the x-y plane) with three teeth pointing in, like a sigil
psi = [TOR(1.0, 0.09, 0, 0, 0, axis="z", segs=40, csegs=6)]
for i in range(3):
    a = 2 * math.pi * i / 3 + math.pi / 2
    c, sn = math.cos(a), math.sin(a)
    psi.append(T([(c * 0.98, sn * 0.98, 0), (c * 0.55, sn * 0.55, 0)], [0.22, 0.01], segs=4))
mesh("Heads", tint("HeadPsiRing"), psi, (200, 140, 255), "Neon", alpha=0.1)

# ================================================================ the Swordsman's slash (Everything Left 172, 2026-11-20): an anime sword crescent
# with a white-hot cutting edge (anchor: the swing's centre; the arc lies flat in the x-z plane, radius 1, 140 degrees
# round the front -z). CombatFx tilts it per combo step and stands it up for Heaven Splitter.
def crescent(r, half, w0, h0, n=25, edge=False):
    pts, radii = [], []
    for j in range(n):
        t = j / (n - 1)
        a = math.radians(-half + 2 * half * t)
        bulge = math.sin(t * math.pi)
        rr = r - (0.0 if edge else w0 * 0.5 * bulge)
        pts.append((math.sin(a) * rr, 0, -math.cos(a) * rr))
        radii.append(max(0.004, (w0 if not edge else h0) * (0.08 + 0.92 * bulge ** 0.7)))
    ob = T(pts, radii, segs=10)
    kit.apply_all(ob)
    for v in ob.data.vertices:
        v.co.z *= h0 / max(radii)  # Blender z is Roblox up: flatten the tube to a blade
    ob.data.update()
    return ob


mesh("Slash", tint("SlashCrescent"), [crescent(1.0, 70, 0.16, 0.05)], (120, 200, 255), "Neon", alpha=0.15)
mesh("Slash", "SlashEdge", [crescent(1.04, 66, 0.03, 0.03, edge=True)], WHITE, "Neon")

# ================================================================ the shock pieces (Everything Left 381, 2026-11-20): a hollow shockwave ring
# (anchor: its centre on the ground; radius 1, a raised rounded crest at the outer edge thinning to a sharp inner
# lip) for every burst's ring, and a blast fan for the cone powers (anchor: the hand; an open flared horn 1 long
# down -z, 1 across at its mouth, with streak ridges along it)
prof = []
for j in range(9):  # the ring's cross-section, inner lip to outer crest and back down
    t = j / 8
    prof.append((0.78 + 0.22 * t, 0.02 + 0.1 * math.sin(t * math.pi * 0.85)))
rings_ = []
for i in range(49):
    a = 2 * math.pi * i / 48
    rings_.append([(math.cos(a) * r, y, math.sin(a) * r) for r, y in prof]
                  + [(math.cos(a) * r, 0.0, math.sin(a) * r) for r, y in reversed(prof)])
shock = rings_mesh(rings_, cap=(False, False))  # the 49th section is the first again: a closed ring
mesh("Shock", tint("ShockRing"), [shock], (255, 220, 120), "Neon", alpha=0.15)
horn = []
for k in range(8):  # the outer skin from the hand to the mouth, then the inner skin back (a thin closed shell)
    t = k / 7
    r = 0.04 + 0.46 * t ** 0.8
    horn.append([(math.cos(2 * math.pi * i / 24) * r * (1.06 if i % 3 == 0 and t > 0.2 else 1.0),
                  math.sin(2 * math.pi * i / 24) * r * (1.06 if i % 3 == 0 and t > 0.2 else 1.0), -t) for i in range(24)])
for k in range(7, -1, -1):
    t = k / 7
    r = (0.04 + 0.46 * t ** 0.8) * 0.9
    horn.append([(math.cos(2 * math.pi * i / 24) * r, math.sin(2 * math.pi * i / 24) * r, -t + 0.03) for i in range(24)])
fan = rings_mesh(horn)
streaks = []
for i in range(8):
    a = 2 * math.pi * (i + 0.5) / 8
    streaks.append(T([(math.cos(a) * 0.05, math.sin(a) * 0.05, -0.02), (math.cos(a) * 0.3, math.sin(a) * 0.3, -0.55),
                      (math.cos(a) * 0.52, math.sin(a) * 0.52, -1.0)], [0.012, 0.022, 0.004], segs=5))
mesh("Shock", tint("ConeFan"), [fan], (255, 220, 120), "Neon", alpha=0.45)
mesh("Shock", "ConeStreaks", streaks, WHITE, "Neon")

# ================================================================ the nemesis's armour (NemesisFx, Everything Left 218): each piece drawn to fill
# the box of the part it replaces on the Brute Bot (centred on it), so NemesisFx sizes it to that same box.
# shoulders: 5 x 1 x 3 (times the build's width)
pads = []
for sx in (-1, 1):
    pad = S(1.0, sx * 1.6, 0, 0, sc=(0.95, 0.55, 1.45), segs=14, rings=8)
    pads.append(kit.cut(pad, (0, 0, 1), keep_positive=True))
    pads.append(B(1.7, 0.18, 2.6, sx * 1.55, -0.02, 0, bev=0.05))
    for k in range(3):
        pads.append(TOR(0.75 - k * 0.18, 0.06, sx * 1.6, 0.06 + k * 0.12, 0, segs=16, csegs=4))
pads.append(B(1.6, 0.6, 2.2, 0, 0.05, 0, bev=0.12))
mesh("Nemesis", "NemShoulders", pads, (90, 30, 40), "Metal")
# a horn: 0.6 x 2.2 x 0.6, curling back at the tip
mesh("Nemesis", "NemHorn", [T([(0, -1.1, 0), (0, -0.2, 0.05), (0, 0.6, 0.2), (0, 1.1, 0.5)], [0.3, 0.24, 0.14, 0.01], segs=10)],
     (90, 30, 40), "SmoothPlastic")
# the cape: 4.5 x 6 x 0.3, folds that open toward the hem
rings = []
for k in range(9):
    y = 3 - 6 * k / 8
    w = 1.8 + 0.45 * k / 8
    ring = []
    for j in range(13):
        x = -w + 2 * w * j / 12
        fold = 0.12 * math.sin(j * math.pi / 2) * (0.3 + k / 8)
        ring.append((x, y, fold))
    for j in range(13):
        x = w - 2 * w * j / 12
        fold = 0.12 * math.sin((12 - j) * math.pi / 2) * (0.3 + k / 8)
        ring.append((x, y, fold + 0.08))
    rings.append(ring)
cape = rings_mesh(rings)
for v in cape.data.vertices:  # a ragged hem: every other fold a little longer
    if v.co.z < -2.9:
        v.co.z -= 0.25 * (1 + math.sin(v.co.x * 4))
mesh("Nemesis", "NemCape", [cape], (150, 30, 50), "Fabric")
# chest plates: 5.5 x 3 x 0.6, a ridged breastplate with rivets
plate = [B(5.0, 2.6, 0.4, 0, 0, 0, bev=0.15), B(0.5, 2.6, 0.5, 0, 0, -0.08, bev=0.12)]
for sx in (-1, 1):
    plate.append(B(2.0, 0.3, 0.45, sx * 1.4, 0.7, -0.04, bev=0.08))
    plate += [S(0.12, sx * 2.25, y, -0.22, segs=6, rings=4) for y in (-0.9, 0.0, 0.9)]
mesh("Nemesis", "NemPlates", plate, (90, 30, 40), "DiamondPlate")
# the second arm cannon: 4 long (along x) by 1.2, barrel rings and a glowing muzzle
can = [C(0.55, 2.8, 0.4, 0, 0, segs=14, axis="x"), C(0.4, 1.3, -1.6, 0, 0, segs=12, axis="x")]
can += [TOR(0.5, 0.08, x, 0, 0, axis="x", segs=14, csegs=4) for x in (-1.2, -0.7, 0.9, 1.5)]
mesh("Nemesis", "NemCannon", can, (70, 72, 80), "Metal")
# the summoner's antenna: 0.3 x 3 x 0.3
ant = [C(0.12, 2.6, 0, -0.2, 0, segs=8, r2=0.06), TOR(0.14, 0.03, 0, 0.2, 0, segs=10, csegs=4), TOR(0.12, 0.03, 0, 0.7, 0, segs=10, csegs=4)]
mesh("Nemesis", "NemAntenna", ant, (70, 72, 80), "Metal")
mesh("Nemesis", tint("NemAntennaTip"), [S(0.2, 0, 1.3, 0, segs=10, rings=6)], (255, 60, 60), "Neon")


# ================================================================ Girder Swing's girder (Everything Left 178, 2026-11-20): a red steel I-beam
# held in the right hand (anchor: the hand; the beam hangs down -y 11 long from just above it), riveted flanges, a dark
# end plate at the grip and a torn, bent far end where it was ripped out of a building. CombatFx.heldGirder welds it.
GL = 11.0
IPOLY = [(-0.45, 0.53), (0.45, 0.53), (0.45, 0.37), (0.11, 0.37), (0.11, -0.37), (0.45, -0.37), (0.45, -0.53),
         (-0.45, -0.53), (-0.45, -0.37), (-0.11, -0.37), (-0.11, 0.37), (-0.45, 0.37)]


def girder_bend(t, x, z):
    k = max(0.0, 0.16 - t) / 0.16  # the last 1.8 studs curl sideways and twist a little
    a = k * k * 0.5
    return x * math.cos(a) - z * math.sin(a) + k * k * 0.7, x * math.sin(a) + z * math.cos(a) + k * k * 0.25


beam = extrude_up(IPOLY, 0.45 - GL, 0.45, fn=girder_bend, steps=14)
for n, at in (((0.35, 0.25, -1.0), 10.15), ((-0.4, -0.15, -1.0), 10.3)):  # the ripped end: two slanted cuts
    shift(beam, (0, 0, at))
    kit.cut(beam, Vector(n).normalized(), keep_positive=False)
    shift(beam, (0, 0, -at))
mesh("Girder", "GirderBeam", [beam], (204, 84, 52), "Metal", shade=False)
rivets = []
for side in (-1, 1):
    for x in (-0.27, 0.27):
        y = 0.1
        while y > 1.6 - GL:
            rivets.append(C(0.07, 0.06, x, y, side * 0.56, segs=6, axis="z"))
            y -= 1.15
rivets.append(B(0.95, 0.12, 1.08, 0, 0.51, 0))  # the end plate at the grip
mesh("Girder", "GirderRivets", rivets, (120, 48, 30), "Metal")

# ================================================================ the wings flourish (AbilityFx FLAIR.wings, 2026-11-20): a right wing of light
# (anchor: its root at the shoulder blade; it spreads out to +x and up, flat in x-up, thin along z): seven tapered
# feathers fanning from the root under a curved leading edge. The left wing is the same mesh turned about up.
def feather(ang, length, w, z=0.0):
    a = math.radians(ang)
    tip = (math.cos(a) * length, math.sin(a) * length, z)
    mid = (math.cos(a) * length * 0.55 - math.sin(a) * w * 0.4, math.sin(a) * length * 0.55 + math.cos(a) * w * 0.4, z)
    ob = T([(0.05, 0.0, z), mid, tip], [w * 0.35, w, 0.01], segs=8)
    kit.apply_all(ob)
    for v in ob.data.vertices:
        v.co.y = z * -1 + (v.co.y + z) * 0.18  # Blender y is Roblox -z: flatten the tube to a vane
    ob.data.update()
    return ob


feathers = []
for i in range(7):
    t = i / 6
    ang = 58 - t * 110  # the top feather sweeps up and out, the last hangs down
    length = 3.5 - 1.9 * t  # the long primaries on top, short coverts below
    feathers.append(feather(ang, length, 0.3 + 0.08 * (1 - t), z=0.02 * (i % 2)))
mesh("Wing", tint("WingFeathers"), feathers, (255, 230, 150), "Neon", alpha=0.25)
_e = [(math.cos(math.radians(g)) * r, math.sin(math.radians(g)) * r, -0.04)
      for g, r in ((40, 0.1), (52, 1.0), (57, 2.0), (58, 3.4))]  # the leading edge along the top feather
mesh("Wing", "WingEdge", [T(_e, [0.1, 0.08, 0.05, 0.01], segs=6)], WHITE, "Neon")

# ================================================================ the Interceptor's net and the Grappler's claw (CombatFx net and hook, 2026-11-20)
# Net (anchor: its centre; it faces z, 2 across, CombatFx scales it to Config.Fx.robots.net.size as it opens): a woven
# square of glowing cords with a thicker rim and four weights at the corners.
cords = []
for i in range(5):
    u = -1.0 + i * 0.5
    sag = [0.0, -0.06, 0.0]
    w = 0.05 if i in (0, 4) else 0.025
    cords.append(T([(-1.0, u, 0.0), (0.0, u, sag[1] * (1 - abs(u))), (1.0, u, 0.0)], [w, w, w], segs=5))
    cords.append(T([(u, -1.0, 0.0), (u, 0.0, sag[1] * (1 - abs(u))), (u, 1.0, 0.0)], [w, w, w], segs=5))
mesh("Net", "NetCords", cords, (190, 235, 255), "Neon")
mesh("Net", "NetWeights", [S(0.13, x, y, 0, segs=8, rings=6) for x in (-1.05, 1.05) for y in (-1.05, 1.05)],
     (60, 60, 66), "Metal")
# Claw (anchor: the hub's centre; it flies toward -z): a hub with a cable eye at the back, and one curved prong
# rooted 0.25 above the axis that CombatFx sets three times round the hub, opening and closing them about their root.
mesh("Claw", "ClawHub", [C(0.3, 0.55, 0, 0, 0.0, segs=10, axis="z"), TOR(0.14, 0.05, 0, 0, 0.42, axis="z", segs=12)],
     (200, 120, 50), "Metal")
mesh("Claw", "ClawProng", [T([(0, 0.25, 0.1), (0, 0.55, -0.4), (0, 0.5, -0.9), (0, 0.26, -1.15), (0, 0.12, -1.05)],
                            [0.1, 0.09, 0.07, 0.04, 0.015], segs=7)], (200, 120, 50), "Metal")

# ================================================================ the plate piece (CombatFx PIECE.plate, 2026-11-20): Gadgeteer's hex plates and
# Juggernaut's armour plates, the petals hit and the Mech Suit's drop: a flat hexagon 2 across (corner to corner, in
# x-z, 0.15 thick) with a raised inner hexagon, a groove between and a bolt in the middle; regular, so the import's
# half turn leaves it as drawn.
def hexpoly(r, rot=0.0):
    return [(r * math.cos(rot + i * math.pi / 3), r * math.sin(rot + i * math.pi / 3)) for i in range(6)]


plate = [extrude_up(hexpoly(1.0), -0.075, 0.075), extrude_up(hexpoly(0.92), 0.075, 0.095),
         extrude_up(hexpoly(0.62), 0.095, 0.13), C(0.11, 0.06, 0, 0.13, 0, segs=8)]
mesh("Plate", tint("PlateHex"), plate, (220, 255, 240), "SmoothPlastic", shade=False)

# ================================================================ the flake piece (CombatFx PIECE.flake, 2026-11-20): Frost's tumbling snowflake chip,
# a flat six-armed crystal 2 across in x-z (0.1 thick) with two pairs of side branches on each arm and a hex heart;
# six-fold, so the import's half turn leaves it as drawn.
flake = [extrude_up(hexpoly(0.22), -0.05, 0.05)]
for i in range(6):
    a = i * math.pi / 3
    c, sn = math.cos(a), math.sin(a)
    flake.append(T([(c * 0.15, 0, sn * 0.15), (c * 1.0, 0, sn * 1.0)], [0.07, 0.035], segs=5))
    for d, ln in ((0.45, 0.32), (0.72, 0.22)):
        for side in (-1, 1):
            b = a + side * math.radians(55)
            px, pz = c * d, sn * d
            flake.append(T([(px, 0, pz), (px + math.cos(b) * ln, 0, pz + math.sin(b) * ln)], [0.045, 0.02], segs=4))
for ob in flake:
    kit.apply_all(ob)
    for v in ob.data.vertices:
        v.co.z = max(-0.05, min(0.05, v.co.z))  # Blender z is Roblox up: flatten the tubes to the chip's thickness
    ob.data.update()
mesh("Flake", tint("FlakeChip"), flake, (200, 235, 255), "Glass", alpha=0.1, shade=False)

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
             "StonePillar": (9, -6, 5), "ThornVine": (13, -6, 5), "Wave": (19, -6, 5), "Nemesis": (-22, 8, 4),
             "FlameJets": (-21, -6, 5.2), "LightRail": (25, 6, 4), "PsiSlab": (24, -8, 5.2),
             "Bullet": (-4, -14, 2), "Sun": (6, -16, 4), "BlackHole": (13, -16, 3), "KiRing": (19, -16, 3),
             "EmberRim": (-12, -16, 0.2), "HaloRim": (-18, -16, 0.2), "VoltRim": (-38, -16, 0.2),
             "Slash": (-26, -16, 2), "Shock": (-32, -16, 1), "Heads": (26, -16, 2), "Girder": (31, 6, 11.5), "Wing": (-28, 6, 3), "Net": (-34, 6, 2),
             "Claw": (-31, -6, 1), "Plate": (-35, -6, 1), "Flake": (-38, -6, 1)}
    close = "--close" in sys.argv  # the 2026-11-20 effect looks only, near the camera (art/preview/powers_fx.png)
    if close:
        spots = {"Sun": (-9, 0, 3), "BlackHole": (-3.5, 0, 2.5), "KiRing": (1, 0, 2.5), "EmberRim": (5.5, 0, 0.2),
                 "HaloRim": (10, 0, 0.2), "Slash": (4, -5, 4.5),
                 "Shock": (-6, -6, 1.2), "VoltRim": (-1, -5.5, 0.2)}
    for look, meshes in LOOKS.items():
        if look not in spots:
            for ob in meshes.values():
                ob.hide_render = True
            continue
        x, yb, y = spots[look]
        for name, ob in meshes.items():
            rgb, mat, alpha = INFO[name]
            m = kit.material("m_" + name, rgb, metal=0.6 if mat == "Metal" else 0.0, rough=0.4, emit=2.0 if mat == "Neon" else 0.0)
            if alpha:
                m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - alpha
            ob.data.materials.append(m)
            ob.location = (x, yb, y)
            if look == "Heads":  # the five heads side by side, flying left to right
                ob.location = (x + sorted(meshes).index(name) * (2.2 if close else 1.4), yb, y)
            ob.rotation_euler = (0, 0, math.radians({"SpiritBeast": 100, "Wave": 235, "Guardian": 215, "Heads": 70}.get(look, 35)))
            if close:
                ob.scale = {"Sun": (1.6,) * 3, "BlackHole": (2.2,) * 3, "KiRing": (1.4,) * 3, "EmberRim": (2,) * 3,
                            "HaloRim": (2,) * 3, "Slash": (3,) * 3,
                            "Shock": (2.4,) * 3, "VoltRim": (2.4,) * 3}[look]
                if look == "BlackHole":
                    ob.rotation_euler = (math.radians(25), 0, 0)
                if look == "Slash":
                    ob.rotation_euler = (math.radians(40), math.radians(20), 0)
    ground = kit.box("ground", 120, 60, 0.2, at=(2, 0, -0.1))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    if close:
        kit.camera((0.5, -20, 9), (0.5, 0, 1.6), lens=36)
        kit.render(os.path.join(kit.ROOT, "preview", "powers_fx.png"))
    else:
        kit.camera((2, -48, 22), (2, 0, 3), lens=30)
        kit.render(os.path.join(kit.ROOT, "preview", "powers.png"))

# ================================================================ --nemesis: the armour on a stand-in Brute Bot body, at NemesisFx's offsets and
# boxes (front: -z), seen from the front and three-quarters
if "--nemesis" in sys.argv:
    for o in list(bpy.context.scene.objects):
        o.hide_render = True
    kit.studio(res=(1200, 700), samples=24)
    PLACE = [  # mesh, box (Roblox x, up, z), centre, turn (degrees about z then x)
        ("NemShoulders", (5, 1, 3), (0, 3.2, 0), 0),
        ("NemHorn", (0.6, 2.2, 0.6), (-1.2, 6.2, 0), 23),
        ("NemHorn", (0.6, 2.2, 0.6), (1.2, 6.2, 0), -23),
        ("NemCape", (4.5, 6, 0.3), (0, 0.5, 1.8), 0),
        ("NemPlates", (5.5, 3, 0.6), (0, 1.4, -1.9), 0),
        ("NemCannon", (4, 1.2, 1.2), (3.4, 2, -1), 0),
        ("NemAntenna", (0.3, 3, 0.3), (1, 7, 0.8), 0),
        ("NemAntennaTip", None, None, 0),
    ]
    import mathutils
    for k, yaw in enumerate((0, 35)):
        base = mathutils.Matrix.Translation((k * 9 - 4.5, 0, 0)) @ mathutils.Matrix.Rotation(math.radians(yaw), 4, "Z")
        body = kit.box("bot", 4.2, 3.2, 5.0, at=(0, 0, 1.6))
        body.data.materials.append(kit.material("bot", (110, 116, 128), metal=0.4))
        head = kit.box("bothead", 2.4, 2.2, 2.0, at=(0, 0, 5.1))
        head.data.materials.append(kit.material("bot", (110, 116, 128), metal=0.4))
        for o in (body, head):
            o.matrix_world = base @ o.matrix_world
        for name, box_, at, tilt in PLACE:
            src = LOOKS["Nemesis"][name]
            ob = copy(src)
            kit.centre(ob)
            if box_ is None:  # the tip rides the antenna's top
                box_, at = (0.4, 0.4, 0.4), (1, 8.6, 0.8)
            vs = ob.data.vertices
            ext = [max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3)]
            want = (box_[0], box_[2], box_[1])
            for v in vs:
                for i in range(3):
                    v.co[i] *= want[i] / max(ext[i], 1e-6)
            rgb, mat, _ = INFO[name]
            ob.data.materials.append(kit.material("n_" + name, rgb, metal=0.5 if mat in ("Metal", "DiamondPlate") else 0.0,
                                                  emit=2.0 if mat == "Neon" else 0.0))
            ob.hide_render = False
            M = mathutils.Matrix.Translation(rb(*at)) @ mathutils.Matrix.Rotation(math.radians(tilt), 4, "Y")
            ob.matrix_world = base @ M
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.9))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    kit.camera((0, 26 if "--front" in sys.argv else -26, 9), (0, 0, 3), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "nemesis_armour.png"))
