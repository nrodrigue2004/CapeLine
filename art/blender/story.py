# story.py: the story's props and the Echo Drone as Blender meshes (gap-story, 2026-11-19; Tasks.md "Story (M7)").
# The old opening's tram car, shard, trapped citizen and escape beam went with lore step 3; today's story has the
# same four things in its missions, and this script gives each a kit look (chunky bevelled shapes, bright comic
# colours, one baked texture set a look via art/blender/hbake.py, low poly for phones), plus the Echo Drone buddy:
# * StoryTrain: the runaway tram car of mission 3 (Framed, the train branch), over MissionService's two plain boxes
#   (10 x 9 x 26 body, 10.4 x 2 x 26.4 roof; Shared.StoryArtKit.BOXES): yellow car, red stripe, cream window band,
#   glass windows, roof and pantograph, bogies and wheels, hazard bumpers, lit headlights.
# * StoryCrate, StoryRelay, StoryScreen, StoryVan: the four looks of a mission's break target, over the plain shard
#   crate (a 5 x 4 x 5 box and a 1.5 x 3 x 1.5 crystal): the Crane shard crate with Spark shards bursting from its
#   lid, Crane's scanner relay (cabinet, lattice mast, dish, red scanner eye), the stage screen on its truss, and
#   the armoured cash van (riveted green plates, gold stripe, vault-wheel doors, amber light bar).
# * StoryTrap: the fallen girder and rubble that pin a person on the bridge (mission 3, "Get the people off the
#   bridge"); the girder is its own mesh so the device can lift it as the ring is held. The person is Roblox's own
#   body with a catalog face and hair (NpcRig.person): never drawn here.
# * StoryBeacon: the goal beam over a reach step's point (the old escape beam): a gold star plate, a see-through
#   gold column and chevron rings the device slides up it.
# * EchoDrone: the villain's buddy (lore: the reprogrammed twin core): a small friendly comic drone, a round white
#   shell with a purple cap and band, ear fins, a dark face plate with one big round cyan eye (its own mesh, so the
#   device blinks it), a stubby antenna and a little thruster glowing purple underneath.
# Each look is built about its foot (the ground middle; front at -z) and its fit row's offsets are from its frame's
# middle. Neon pieces stay flat glowing colours (never baked).
# Output: art/export/Story.fbx (textures embedded), art/export/story/<Look>_{Color,Normal,Roughness,Metalness}.png,
# src/config/StoryArt.luau; with --preview art/preview/story.png (every look beside a hero for scale) and
# art/preview/story_drone.png (the drone close up, eye open and mid-blink) and art/preview/story_trap.png.
# Run: $HOME/tools/bpyenv/bin/python art/blender/story.py [--preview] [--fast]
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401

kit.reset()

import ruinkit as rk  # noqa: E402
from ruinkit import paint, lump, nut, bars  # noqa: E402
from studs import mesh, LOOKS, C, S, T, TOR, turn, shift, rb, star  # noqa: E402
from vkit import rbox  # noqa: E402

FAST = "--fast" in sys.argv
OUT = os.path.join(kit.ROOT, "export", "story")
os.makedirs(OUT, exist_ok=True)

FRAMES, ORIGINS = {}, {}
YELLOW = (250, 204, 64)
RED = (214, 52, 46)
CREAM = (248, 238, 214)
ROOF = (60, 60, 70)
DARK = (44, 46, 54)
STEEL = (146, 152, 164)
NAVY = (40, 52, 104)
WHITE = (240, 242, 248)
VIOLET = (118, 86, 196)
SPARK = (160, 230, 255)
PURPLE = (150, 60, 200)
GOLD = (240, 190, 60)
GREEN = (62, 96, 72)
CONCRETE = (170, 166, 158)
GIRDER = (204, 84, 52)


def frame(look, size):
    """The box a look stands in for (studs x, up, z) about its foot; offsets are from its middle."""
    FRAMES[look] = size
    ORIGINS[look] = (0.0, size[1] / 2, 0.0)


class Parts:
    def __init__(self):
        self.parts = []

    def __call__(self, ob, rgb, mat="SmoothPlastic", pat=None):
        self.parts.append(paint(ob, rgb, mat, pat))
        return ob


def crane_c(x, y, z, r, face=-1):
    """Crane Industries' C: a white open ring on a navy square, facing -z (face=-1) or +z."""
    plate = rbox(r * 2.4, r * 2.4, 0.12, x, y, z, bev=0.04)
    ring = TOR(r, r * 0.26, x, y, z + face * 0.08, axis="z", segs=18, csegs=4, arc=math.radians(290))
    turn(ring, "z", 35, pivot=(x, y, z))
    return plate, ring


# ================================================================ StoryTrain: the runaway tram car
def train():
    look = "StoryTrain"
    frame(look, (10.4, 9.0, 26.4))
    P = Parts()
    glass, lamps = [], []
    # the car body: chunky and round-cornered, a red stripe low and a cream window band
    P(rbox(9.6, 5.4, 24.0, 0, 4.9, 0, bev=0.9, segs=3), YELLOW, "SmoothPlastic", "plastic+soot")
    P(rbox(9.76, 0.55, 23.6, 0, 3.2, 0, bev=0.2), RED)
    P(rbox(9.72, 2.7, 22.6, 0, 5.8, 0, bev=0.3), CREAM)
    # the windows: five a side, the windscreens at both ends
    for s in (-1, 1):
        for k in range(5):
            glass.append(rbox(0.14, 2.0, 3.0, s * 4.88, 5.85, -8.0 + k * 4.0, bev=0.05))
    for e in (-1, 1):
        glass.append(rbox(7.0, 2.4, 0.14, 0, 5.85, e * 11.98, bev=0.05))
        # the destination board over the windscreen and the dark frame round it
        P(rbox(4.2, 0.9, 0.2, 0, 7.55, e * 11.9, bev=0.08), DARK)
        P(rbox(3.6, 0.5, 0.06, 0, 7.55, e * 12.02), CREAM)
        # the hazard bumper and its buffers
        P(rbox(8.6, 0.9, 0.9, 0, 2.3, e * 12.4, bev=0.2), GOLD, "SmoothPlastic", "hazard")
        for bx in (-3.0, 3.0):
            P(C(0.42, 0.5, bx, 2.3, e * 12.95, segs=10, axis="z"), DARK, "Metal")
    # headlights at the front (lit) and red tail lamps at the back
    for x in (-3.0, 3.0):
        lamps.append(C(0.55, 0.16, x, 3.9, -12.1, segs=14, axis="z"))
        P(TOR(0.6, 0.12, x, 3.9, -12.06, axis="z", segs=14, csegs=4), STEEL, "Metal")
        P(C(0.4, 0.16, x, 3.9, 12.1, segs=12, axis="z"), RED)
    # the roof: a dark cap with vents and the pantograph's frame
    P(rbox(8.8, 0.8, 22.4, 0, 7.95, 0, bev=0.3), ROOF, "Metal", "plates")
    for z in (-6.0, 0.0, 6.0):
        P(rbox(2.4, 0.4, 1.6, 0, 8.5, z, bev=0.1), DARK, "Metal", "grate")
    P(rbox(3.0, 0.3, 0.3, 0, 8.55, -1.5, bev=0.05), DARK, "Metal")
    P(T([(-1.4, 8.6, -1.5), (0, 8.85, 0.6), (1.4, 8.6, -1.5)], 0.08, segs=5), STEEL, "Metal")
    P(T([(0, 8.85, 0.6), (0, 8.95, 1.8)], 0.08, segs=5), STEEL, "Metal")
    P(rbox(3.6, 0.12, 0.3, 0, 8.95, 1.8, bev=0.03), DARK, "Metal")
    # the underframe, two bogies and their wheels (the box's foot)
    P(rbox(8.6, 0.8, 21.0, 0, 1.75, 0, bev=0.15), DARK, "Metal")
    for z in (-7.6, 7.6):
        P(rbox(7.4, 1.0, 5.2, 0, 1.0, z, bev=0.2), ROOF, "Metal", "plates")
        for dz in (-1.5, 1.5):
            for x in (-3.55, 3.55):
                P(C(0.78, 0.5, x, 0.8, z + dz, segs=14, axis="x"), DARK, "Metal")
                P(C(0.3, 0.56, x, 0.8, z + dz, segs=8, axis="x"), STEEL, "Metal")
    # the side doors (darker panels with a stripe of glass)
    for s in (-1, 1):
        for z in (-10.2, 10.2):
            P(rbox(0.1, 4.4, 2.0, s * 4.86, 4.4, z * 0.0 + (z / abs(z)) * 9.9, bev=0.05), (220, 172, 48))
    mesh(look, look + "Body", P.parts, YELLOW)
    mesh(look, look + "Glass", glass, (200, 230, 255), "Glass", 0.4)
    mesh(look, look + "Lamps", lamps, (255, 240, 190), "Neon")


# ================================================================ the break targets (over the shard crate's boxes)
CRATE = (5.0, 6.5, 5.0)


def crate():
    look = "StoryCrate"
    frame(look, CRATE)
    P = Parts()
    shards = []
    P(rbox(4.6, 3.7, 4.6, 0, 1.9, 0, bev=0.2), VIOLET, "Metal", "plates")
    # steel corner caps and two bands
    for x in (-2.25, 2.25):
        for z in (-2.25, 2.25):
            for y in (0.35, 3.45):
                P(rbox(0.7, 0.7, 0.7, x, y, z, bev=0.12), STEEL, "Metal")
    for y in (1.2, 2.6):
        P(rbox(4.75, 0.3, 4.75, 0, y, 0, bev=0.06), STEEL, "Metal")
    plate, ring = crane_c(0, 1.9, -2.34, 0.6)
    P(plate, NAVY)
    P(ring, WHITE)
    # the lid knocked open on its back hinge, the packing straw inside
    lid = rbox(4.6, 0.35, 4.6, 0, 0, 0, bev=0.1)
    shift(lid, rb(0, 0, -2.3))
    turn(lid, "x", -24)
    P(shift(lid, rb(0, 3.95, 2.3)), VIOLET, "Metal", "plates")
    P(lump(4.0, 0.6, 4.0, 0, 3.7, 0, 3, 0.12, 0.2), (226, 196, 120), "Fabric")
    # the Spark shards bursting out of the top (one big, four small), lit
    rnd = random.Random(7)
    for (x, z, h, r, tx, tz) in ((0, 0, 3.0, 0.75, 0, 0), (-1.1, 0.6, 1.9, 0.48, 14, -18),
                                 (1.0, -0.7, 1.8, 0.42, -16, 12), (0.9, 1.0, 1.3, 0.34, 10, 20),
                                 (-0.8, -1.0, 1.2, 0.32, -12, -14)):
        sh = C(r, h, 0, h / 2, 0, segs=6, r2=r * 0.15)
        tip = C(r * 0.15, 0.3, 0, h + 0.15, 0, segs=6, r2=0.0)
        for ob in (sh, tip):
            turn(ob, "x", tx)
            turn(ob, "z", tz)
            turn(ob, "up", rnd.uniform(0, 60))
            shift(ob, rb(x, 3.5, z))
        shards += [sh, tip]
    mesh(look, look + "Body", P.parts, VIOLET)
    mesh(look, look + "Shard", shards, SPARK, "Neon")


def relay():
    look = "StoryRelay"
    frame(look, CRATE)
    P = Parts()
    lamp = []
    P(rbox(4.2, 3.2, 3.8, 0, 1.6, 0, bev=0.25), STEEL, "Metal")
    P(rbox(4.3, 0.5, 3.9, 0, 0.25, 0, bev=0.1), DARK, "Metal")
    P(rbox(4.26, 0.5, 3.86, 0, 2.6, 0, bev=0.1), NAVY)
    for s in (-1, 1):
        P(rbox(0.1, 1.2, 2.6, s * 2.12, 1.3, 0, bev=0.04), DARK, "Metal", "grate")
    P(rbox(2.6, 1.3, 0.1, -0.2, 1.4, -1.92, bev=0.04), DARK, "Metal", "grate")
    plate, ring = crane_c(1.35, 1.45, -1.94, 0.38)
    P(plate, NAVY)
    P(ring, WHITE)
    lamp.append(S(0.28, 1.35, 2.62, -1.95, segs=10, rings=6))
    # the lattice mast up to the dish
    top = 6.1
    legs = [(-1.0, 3.2, -0.9), (1.0, 3.2, -0.9), (1.0, 3.2, 0.9), (-1.0, 3.2, 0.9)]
    for (x, y, z) in legs:
        P(T([(x, y, z), (x * 0.3, top, z * 0.3)], 0.09, segs=5), (200, 70, 60), "Metal")
    for k in range(3):
        y = 3.6 + k * 0.8
        f = 1 - (y - 3.2) / (top - 3.2) * 0.7
        for i in range(4):
            a, b = legs[i], legs[(i + 1) % 4]
            P(T([(a[0] * f, y, a[2] * f), (b[0] * f, y + 0.4, b[2] * f)], 0.05, segs=4), (200, 70, 60), "Metal")
    # the scanner dish facing front, its feed arm and the red scanner eye
    dish = C(1.5, 0.5, 0, 0, 0, segs=18, r2=0.5, axis="z")
    turn(dish, "x", -12)
    P(shift(dish, rb(0, top + 0.6, -0.3)), WHITE)
    P(T([(0, top + 0.6, -0.5), (0, top + 0.75, -1.4)], 0.06, segs=4), STEEL, "Metal")
    lamp.append(S(0.22, 0, top + 0.78, -1.5, segs=10, rings=6))
    P(C(0.35, 0.4, 0, top + 0.25, -0.1, segs=10), DARK, "Metal")
    mesh(look, look + "Body", P.parts, STEEL)
    mesh(look, look + "Lamp", lamp, (255, 70, 60), "Neon")


def screen():
    look = "StoryScreen"
    frame(look, CRATE)
    P = Parts()
    face = []
    # the truss legs on their feet, the black bezel, a speaker on each foot
    for s in (-1, 1):
        P(rbox(1.6, 0.4, 2.4, s * 3.0, 0.2, 0, bev=0.1), DARK, "Metal")
        for dx in (-0.25, 0.25):
            for dz in (-0.25, 0.25):
                P(T([(s * 3.0 + dx, 0.4, dz), (s * 3.0 + dx, 6.8, dz)], 0.06, segs=4), STEEL, "Metal")
        for k in range(8):
            y = 0.6 + k * 0.8
            P(T([(s * 3.0 - 0.25, y, -0.25), (s * 3.0 + 0.25, y + 0.8, 0.25)], 0.04, segs=4), STEEL, "Metal")
        P(rbox(1.2, 1.5, 1.1, s * 3.0, 1.15, -0.9, bev=0.12), DARK)
        P(C(0.38, 0.08, s * 3.0, 1.3, -1.47, segs=12, axis="z"), (90, 94, 104), "Metal")
    P(rbox(7.0, 4.6, 0.5, 0, 4.6, 0.1, bev=0.18), DARK, "SmoothPlastic")
    P(rbox(7.0, 0.3, 0.6, 0, 6.95, 0.1, bev=0.08), (230, 60, 140))
    face.append(rbox(6.4, 4.0, 0.08, 0, 4.6, -0.17, bev=0.04))
    mesh(look, look + "Body", P.parts, DARK)
    mesh(look, look + "Face", face, (90, 170, 255), "Neon")


def van():
    look = "StoryVan"
    frame(look, CRATE)
    P = Parts()
    glass, lamps = [], []
    # the boxy armoured back and the lower cab, riveted green plates and a gold stripe
    P(rbox(5.4, 3.6, 5.6, 0, 2.95, 1.25, bev=0.35), GREEN, "Metal", "plates")
    P(rbox(5.2, 2.6, 2.8, 0, 2.3, -2.75, bev=0.45), GREEN, "Metal", "plates")
    P(rbox(5.5, 0.4, 8.2, 0, 2.2, -0.1, bev=0.1), GOLD, "Foil")
    P(rbox(5.0, 0.8, 8.0, 0, 0.95, -0.1, bev=0.2), DARK, "Metal")
    glass.append(rbox(4.4, 1.0, 0.1, 0, 3.0, -3.95, bev=0.05))
    for s in (-1, 1):
        glass.append(rbox(0.1, 0.9, 1.6, s * 2.6, 3.0, -2.7, bev=0.04))
        P(rbox(0.1, 0.5, 3.2, s * 2.72, 3.9, 1.0, bev=0.04), DARK)  # gun-slit windows on the box, shut
    # the gold coin emblem on each side
    for s in (-1, 1):
        P(C(0.75, 0.12, s * 2.74, 3.0, 1.3, segs=18, axis="x"), GOLD, "Foil")
        P(rbox(0.1, 0.6, 0.18, s * 2.82, 3.0, 1.3, bev=0.02), (180, 130, 30))
    # the rear doors with a vault wheel
    P(rbox(5.0, 3.2, 0.15, 0, 2.95, 4.08, bev=0.06), (52, 82, 62), "Metal", "plates")
    P(TOR(0.7, 0.1, 0, 3.0, 4.25, axis="z", segs=16, csegs=4), STEEL, "Metal")
    for a in range(0, 180, 60):
        sp = rbox(1.4, 0.1, 0.1, 0, 3.0, 4.25)
        turn(sp, "z", a, pivot=(0, 3.0, 4.25))
        P(sp, STEEL, "Metal")
    P(C(0.2, 0.2, 0, 3.0, 4.3, segs=8, axis="z"), GOLD, "Foil")
    # the bull bar, bumpers, wheels and the amber light bar, the headlights
    P(rbox(4.8, 0.6, 0.5, 0, 1.2, -4.15, bev=0.12), STEEL, "Metal")
    for x in (-1.6, 1.6):
        P(T([(x, 1.2, -4.25), (x, 2.4, -4.2)], 0.1, segs=5), STEEL, "Metal")
        lamps.append(C(0.34, 0.12, x * 1.25, 2.05, -4.15, segs=12, axis="z"))
    P(rbox(4.6, 0.5, 0.4, 0, 1.2, 4.3, bev=0.12), STEEL, "Metal")
    for x in (-2.45, 2.45):
        for z in (-2.6, 2.6):
            P(C(0.95, 0.7, x, 0.95, z, segs=14, axis="x"), (38, 38, 44), "SmoothPlastic", "rubber")
            P(C(0.45, 0.76, x, 0.95, z, segs=8, axis="x"), STEEL, "Metal")
    P(rbox(2.6, 0.3, 0.7, 0, 4.9, -1.2, bev=0.08), DARK, "Metal")
    lamps.append(rbox(2.2, 0.35, 0.5, 0, 5.15, -1.2, bev=0.1))
    mesh(look, look + "Body", P.parts, GREEN)
    mesh(look, look + "Glass", glass, (200, 230, 255), "Glass", 0.4)
    mesh(look, look + "Lamps", lamps, (255, 176, 50), "Neon")


# ================================================================ StoryTrap: the fallen girder over a person
TRAP = (11.0, 6.0, 7.0)
GIRDER_LOW = (-4.2, 0.62, 0.0)  # the girder's low end on the ground: the device lifts it about this point
GIRDER_HIGH = (3.4, 4.6, 0.0)  # its high end on the rubble pile


def trap():
    look = "StoryTrap"
    frame(look, TRAP)
    P = Parts()
    G = Parts()
    rnd = random.Random(31)
    # the rubble pile the girder rests on (east) and chunks round the person, a broken slab, rebar, dust
    for k in range(7):
        sx, sy, sz = rnd.uniform(1.2, 2.2), rnd.uniform(0.9, 1.6), rnd.uniform(1.2, 2.2)
        y = sy / 2 - 0.12 if k < 4 else 1.5 + (k - 4) * 0.7
        x = 3.4 + rnd.uniform(-0.9, 0.7)
        z = rnd.uniform(-1.4, 1.4)
        P(lump(sx, sy, sz, x, min(y, 3.6), z, 100 + k, 0.18, 0.1,
               (rnd.uniform(-15, 15), rnd.uniform(0, 90), rnd.uniform(-15, 15))), CONCRETE, "Concrete", "concrete+soot")
    P(lump(2.6, 0.5, 2.0, 3.2, 3.85, 0, 120, 0.12, 0.08, (0, 20, 8)), CONCRETE, "Concrete", "concrete+soot")
    for k in range(6):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(2.2, 3.4)
        P(lump(rnd.uniform(0.5, 1.0), rnd.uniform(0.35, 0.7), rnd.uniform(0.5, 1.0), math.cos(a) * r * 0.9 - 0.6, 0.3,
               math.sin(a) * r * 0.75, 200 + k, 0.2, 0.06, (rnd.uniform(-20, 20), rnd.uniform(0, 90), 0)),
          CONCRETE, "Concrete", "concrete")
    slab = rbox(3.0, 0.4, 2.2, 0, 0, 0, bev=0.08)
    turn(slab, "z", 14)
    turn(slab, "up", -18)
    P(shift(slab, rb(-2.6, 0.5, 1.8)), (150, 148, 142), "Concrete", "slab")
    for ob in bars(3, [(3.0, 2.6, -0.8), (3.8, 3.2, 0.6), (-2.2, 0.8, 1.6)], (0.2, 1.0, -0.3), 1.4, 41):
        P(ob, (120, 80, 60), "Metal", "rust")
    P(lump(5.5, 0.12, 4.0, 0, 0.06, 0, 300, 0.05, 0.02), (130, 124, 116), "Concrete", "concrete")
    # the steel I-beam: top and bottom flanges and the web, bolt plates at the ends, leaning from low to high
    lx, ly, _ = GIRDER_LOW
    hx, hy, _ = GIRDER_HIGH
    ln = math.hypot(hx - lx, hy - ly) + 0.6
    ang = math.degrees(math.atan2(hy - ly, hx - lx))
    parts = [rbox(ln, 0.16, 0.9, ln / 2 - 0.3, 0.42, 0, bev=0.03), rbox(ln, 0.16, 0.9, ln / 2 - 0.3, -0.42, 0, bev=0.03),
             rbox(ln, 0.74, 0.18, ln / 2 - 0.3, 0, 0, bev=0.02)]
    for k in range(4):
        parts.append(C(0.2, 0.22, 0.6 + k * (ln - 1.6) / 3, 0, 0, segs=10, axis="z"))
    for e in (-0.2, ln - 0.45):
        parts.append(rbox(0.12, 0.92, 0.94, e, 0, 0, bev=0.02))
    for ob in parts:
        turn(ob, "z", ang)
        shift(ob, rb(lx, ly, 0))
        G(ob, GIRDER, "Metal", "metal+soot")
    mesh(look, look + "Rubble", P.parts, CONCRETE)
    mesh(look, look + "Girder", G.parts, GIRDER)


# ================================================================ StoryBeacon: the goal beam
BEACON = (6.0, 40.0, 6.0)


def beacon():
    look = "StoryBeacon"
    frame(look, BEACON)
    P = Parts()
    P(C(2.9, 0.3, 0, 0.15, 0, segs=24), (52, 56, 70), "Metal")
    P(TOR(2.75, 0.16, 0, 0.32, 0, segs=24, csegs=4), GOLD, "Foil")
    st = star(2.1, 0.95, 0.14, 0, 0.37, 0, axis="up")
    P(st, GOLD, "Foil")
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        P(nut(math.cos(a) * 2.45, 0.36, math.sin(a) * 2.45, 0.14), STEEL, "Metal")
    beam = C(1.15, 38.6, 0, 0.45 + 19.3, 0, segs=16, r2=0.9)
    rings = [TOR(1.75, 0.17, 0, 1.6 + k * 2.0, 0, segs=20, csegs=4) for k in range(3)]
    mesh(look, look + "Base", P.parts, GOLD)
    mesh(look, look + "Beam", [beam], (255, 222, 110), "Neon", 0.55)
    mesh(look, look + "Rings", rings, (255, 236, 150), "Neon")


# ================================================================ EchoDrone: the villain's buddy
DRONE = (1.8, 1.8, 1.8)
DC = 0.9  # its middle's height over its foot


def drone():
    look = "EchoDrone"
    frame(look, DRONE)
    P = Parts()
    eye, glow = [], []
    P(S(0.72, 0, DC, 0, sc=(1, 0.9, 1), segs=20, rings=12), WHITE, "SmoothPlastic")
    P(S(0.5, 0, DC + 0.5, 0.04, sc=(1, 0.5, 1), segs=18, rings=8), PURPLE)
    P(TOR(0.57, 0.06, 0, DC - 0.42, 0, segs=24, csegs=4), PURPLE)
    # the face plate (dark, round) and its purple bezel; the big round eye sits on it
    P(C(0.36, 0.2, 0, DC + 0.08, -0.69, segs=20, axis="z"), (26, 28, 40), "SmoothPlastic")
    P(TOR(0.37, 0.05, 0, DC + 0.08, -0.78, axis="z", segs=20, csegs=4), PURPLE)
    eye.append(C(0.21, 0.05, 0, DC + 0.1, -0.8, segs=18, axis="z"))
    # ear fins, tilted out and back
    for s in (-1, 1):
        fin = rbox(0.13, 0.4, 0.36, 0, 0, 0, bev=0.05)
        turn(fin, "z", s * -22)
        turn(fin, "up", s * 12)
        P(shift(fin, rb(s * 0.78, DC + 0.12, 0.05)), PURPLE)
        P(C(0.12, 0.12, s * 0.7, DC + 0.05, 0.05, segs=10, axis="x"), (90, 94, 110), "Metal")
    # the stubby antenna and its glowing tip
    P(T([(0.08, DC + 0.7, 0.12), (0.18, DC + 0.88, 0.2)], 0.035, segs=5), (90, 94, 110), "Metal")
    glow.append(S(0.07, 0.19, DC + 0.9, 0.21, segs=8, rings=5))
    # the little thruster underneath and its glow ring
    P(C(0.3, 0.22, 0, DC - 0.72, 0, segs=14, r2=0.22), (90, 94, 110), "Metal")
    glow.append(TOR(0.2, 0.05, 0, DC - 0.84, 0, segs=14, csegs=4))
    mesh(look, look + "Body", P.parts, WHITE)
    mesh(look, look + "Eye", eye, (110, 235, 255), "Neon")
    mesh(look, look + "Glow", glow, (210, 120, 255), "Neon")


for build in (train, crate, relay, screen, van, trap, beacon, drone):
    build()
ALL = sorted(LOOKS)

RES = {"StoryTrain": 512, "StoryVan": 512, "StoryTrap": 512}
MAPPED = rk.bake_all(ALL, OUT, lambda look, objs: RES.get(look, 256), fast=FAST)
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "StoryArt.luau"))
tris, total, count = rk.write_fit(FIT, [
    "-- GENERATED by art/blender/story.py: do not edit by hand.",
    "-- The story's props and the Echo Drone in Blender meshes (ReplicatedStorage.Art.Story; Shared.StoryArtKit,",
    "-- Fx.StoryProps, Fx.StoryFx): look -> its frame (the box it stands in for: studs x, up, z) and its meshes: each",
    "-- mesh's size and its centre from the frame's middle, its colour, material, transparency, maps (a baked texture",
    "-- set in its SurfaceAppearance) and triangles. StoryTrapGirder lifts about StoryArtKit.GIRDER_LOW; EchoDroneEye",
    "-- blinks; StoryBeaconRings slide up the beam.",
], ALL, FRAMES, MAPPED, ORIGINS)
print("story: %d looks, %d meshes, %d tris" % (len(ALL), count, total))
for look in ALL:
    print("  %-14s %5d tris" % (look, sum(tris[n] for n in LOOKS[look])))
rk.export_fbx(os.path.join(kit.ROOT, "export", "Story.fbx"), ALL, MAPPED)

# ================================================================ previews
if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402

    PREV = os.path.join(kit.ROOT, "preview")
    vp._scene(FAST, (760, 420) if FAST else (1500, 820))
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    vp._ground(400, (128, 130, 136))
    rk.placed("StoryTrain", MAPPED, (-14, 0, 6), 35, vp._keep)
    for i, look in enumerate(("StoryCrate", "StoryRelay", "StoryScreen", "StoryVan")):
        rk.placed(look, MAPPED, (2 + i * 8.5, 0, -2), -15, vp._keep)
    rk.placed("StoryTrap", MAPPED, (8, 0, 12), 10, vp._keep)
    rk.placed("StoryBeacon", MAPPED, (32, 0, 16), 0, vp._keep)
    rk.placed("EchoDrone", MAPPED, (30.5, 3.6, -1), -20, vp._keep)
    vp._hero(28.5, 0, -1, yaw=-20)
    vp._hero(1, 0, 8, yaw=10)
    vp._camera((12, 24, -34), (12, 3, 4), lens=30)
    out = os.path.join(PREV, "story.png")
    kit.render(out)
    vp._clear()
    # the drone close up: three quarter front, side, and mid-blink (the eye squashed as the device does)
    vp._ground(60, (90, 92, 98))
    for i, ry in enumerate((-35, 0, 35)):
        rk.placed("EchoDrone", MAPPED, ((i - 1) * 3.0, 1.0, 0), ry, vp._keep)
    for o in list(vp.SHOWN):
        if o.name.startswith("EchoDroneEye") and abs(o.location.x - 3.0) < 0.01:
            o.scale = (1, 1, 0.15)
            o.location.z += (DC + 0.1) * (1 - 0.15)
    vp._camera((0, 2.6, -16), (0, 1.9, 0), lens=85)
    kit.render(os.path.join(PREV, "story_drone.png"))
    vp._clear()
    # the trap close up with a person-sized figure crouched under it (the game's person is Roblox's own body)
    vp._ground(80, (110, 112, 118))
    rk.placed("StoryTrap", MAPPED, (0, 0, 0), 0, vp._keep)
    vp._hero(1.6, -1.2, 0.6, yaw=0)
    vp._camera((3, 6, -13), (0, 2, 0), lens=34)
    kit.render(os.path.join(PREV, "story_trap.png"))
    print("preview:", out)
