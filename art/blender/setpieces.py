# setpieces.py: the side quest chains' set pieces as Blender meshes (overnight queue item 10). Until nate imports
# them the game builds each set piece from plain parts (Shared.SideQuestSets, Shared.PocketLayout's side quest
# pockets, SideQuestService's escort truck); once ReplicatedStorage.Art.SetPieces holds a look's meshes, the
# game draws them over those parts and hides the parts (kept for collisions and the breakable pieces).
# Looks (each a few meshes, one colour region each; the game colours every MeshPart, and a copy may take its own
# tint, Shared.SetPieceKit): the Museum Gala (arch, stage, curtains, marquee poles and canopy, chandelier,
# exhibit cases, velvet benches, spotlights), the Racers' Meet (gantry, start lights, racers, tyre stacks, fuel
# drums, DJ booth, floodlights, kicker ramp), Tick-Tock Toys (clock sign, toy shelves, toy train, toy blocks,
# music box, counter and till, wind-up keys, the Tantrum Tap, toy soldier benches), the farm folk's truck, Brine's
# sea cave (rocks, coral, mooring posts, rowboat, Finn's cage, the Drowned Gull, projectors, treasure chests),
# Velmara (the drowned gate, market stalls, broken columns, the fountain and the Tidewright's statue, tide
# engines, the sea valve) and the Pit (mine lift, timbers, mine cart, cash crates, bookies' counter, odds
# machines, ring posts and ropes, floodlights, the gold throne, the crowd). Original designs, bright cartoon
# colours, chunky silhouettes, low poly for phones.
# Every mesh is built in Roblox studs about its look's foot point (x, up, z; the look's placement in the game is
# that point, turned about up), then centred on its own box for export. src/config/SetPieceArt.luau (generated)
# gives each mesh's size, its centre from the foot, its colour, material and transparency.
# Output: art/export/SetPieces.fbx, src/config/SetPieceArt.luau; with --preview, art/preview/setpieces.png (the
# looks where the game puts them, from art/export/setpieces/layout.json, which `lune run
# art/setpieces/layout.luau` writes from the game's own data; --only <shot> renders one shot alone to
# art/preview/setpieces_<shot>.png, --fast at low quality).
# Run: python art/blender/setpieces.py [--preview] [--only <group>] [--fast]   (with the `bpy` module, Blender 5.0)
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

from studs import *  # noqa: E402,F401,F403  (the colours and shape helpers)
from studs import LOOKS, INFO  # noqa: E402

# ================================================================ the Museum Gala (OpenNorth)
# ---------------------------------------------------------------- the entrance arch (foot: the sign's middle)
parts = []
for x in (-8, 8):
    parts += [B(1.9, 0.6, 1.9, x, 0.3, 0, bev=0.08), C(0.55, 11.0, x, 6.1, 0, segs=10),
              B(1.6, 0.5, 1.6, x, 11.85, 0, bev=0.06), S(0.75, x, 13.4, 0, segs=10, rings=6),
              TOR(0.62, 0.12, x, 2.0, 0, segs=12, csegs=4)]
parts += [B(16.4, 0.3, 0.8, 0, 12.85, 0), B(16.4, 0.3, 0.8, 0, 9.15, 0), star(1.5, 0.65, 0.45, 0, 14.4, 0)]
mesh("GalaArch", "GalaArchGold", parts, GOLD)

# ---------------------------------------------------------------- the opera stage (foot: the deck's middle)
deck = [B(40, 3.4, 12, 0, 1.7, 0, bev=0.12), B(40.6, 0.6, 12.4, 0, 3.7, 0, bev=0.1), B(10, 2, 3, 0, 1, 7.5, bev=0.1),
        B(10, 0.3, 1.2, 0, 2.05, 8.1)]
mesh("GalaStage", "StageDeck", deck, WOOD, "Wood")
gold = [B(40.8, 0.45, 0.5, 0, 3.75, 6.15), B(43, 2.4, 2.8, 0, 19.5, -5, bev=0.15), B(44, 0.5, 3.2, 0, 20.9, -5),
        B(44, 0.5, 3.2, 0, 18.1, -5), star(2.4, 1.0, 0.8, 0, 22.4, -3.8)]
for x in (-20, 20):
    gold += [B(3.8, 0.7, 3.8, x, 17.55, -5, bev=0.1), TOR(1.45, 0.18, x, 5.0, -5, segs=12, csegs=4)]
for i in range(15):  # the scalloped trim along the deck's front
    gold.append(C(0.55, 0.3, -19.0 + i * 2.7, 3.35, 6.25, segs=8, axis="z"))
mesh("GalaStage", "StageGold", gold, GOLD)
pil = []
for x in (-20, 20):
    pil += [B(3.6, 0.8, 3.6, x, 4.4, -5, bev=0.08), C(1.3, 12.4, x, 11.0, -5, segs=12), B(3.2, 0.6, 3.2, x, 17.0, -5)]
mesh("GalaStage", "StagePillars", pil, CREAM)
back = B(37, 16, 0.6, 0, 12, -6.6)
kit.apply_all(back)
mesh("GalaStage", "StageBackdrop", back, NAVY, "Fabric")
stars = []
for (x, y, r) in ((-12, 15, 1.1), (-5, 17, 0.8), (3, 15.5, 1.2), (11, 17.2, 0.9), (-15, 9, 0.7), (14, 10.5, 0.8), (0, 19, 0.6)):
    stars.append(star(r, r * 0.45, 0.2, x, y, -6.25))
mesh("GalaStage", "StageStars", stars, (255, 236, 150), "Neon")

# ---------------------------------------------------------------- a stage curtain (foot: its bottom middle; the
# folds gather toward -x, the outer side: the right-hand copy is turned round)
wave = []
N = 14
for i in range(N + 1):
    u = i / N
    wave.append((-5 + 10 * u, 0.34 * math.sin(u * math.pi * 7) - 0.15))
for i in range(N, -1, -1):
    u = i / N
    wave.append((-5 + 10 * u, 0.34 * math.sin(u * math.pi * 7) + 0.15))


def gather(t, x, z):
    # pinched to 45% width toward -x at a third of the way up, full at the hem and the top
    y = t * 12
    k = 1.0 - 0.55 * math.exp(-((y - 4.2) / 2.6) ** 2)
    return (-5 + (x + 5) * k, z * (1.0 + 0.8 * (1 - k)))


cur = extrude_up(wave, 0, 12, gather, steps=8)
mesh("GalaCurtain", "Curtain", cur, CRIMSON, "Fabric")
tie = [TOR(0.9, 0.22, -3.6, 4.2, 0, axis="up", segs=12, csegs=5), C(0.3, 1.4, -3.6, 3.0, 0, segs=8, r2=0.12),
       S(0.35, -3.6, 3.9, 0.6, segs=8, rings=5)]
mesh("GalaCurtain", "CurtainTie", tie, GOLD)

# ---------------------------------------------------------------- a marquee pole (foot on the paving)
mesh("MarqueePole", "PoleShaft", [C(0.9, 0.5, 0, 0.25, 0, segs=12), C(0.42, 15.3, 0, 8.15, 0, segs=10, r2=0.36)], WHITE)
mesh("MarqueePole", "PoleGold", [S(0.6, 0, 16.0, 0, segs=10, rings=6), TOR(0.46, 0.12, 0, 2.0, 0, segs=10, csegs=4),
                                  TOR(0.4, 0.12, 0, 14.2, 0, segs=10, csegs=4)], GOLD)


# ---------------------------------------------------------------- the marquee canopy (foot: under its middle, at the
# poles' tops less 1; red and cream stripes on a low peaked roof, a gold ridge and a scalloped valance)
def roof_y(z):
    return 1.0 + 1.2 * (1 - min(abs(z), 20.5) / 20.5)


poly = [(-20.6, roof_y(-20.6) - 0.3), (-20.6, roof_y(-20.6)), (0, roof_y(0)), (20.6, roof_y(20.6)), (20.6, roof_y(20.6) - 0.3),
        (0, roof_y(0) - 0.3)]
stripes = {0: [], 1: []}
for i, x in enumerate((-18, -6, 6, 18)):
    stripes[i % 2].append(prism(poly, x - 6.0, x + 6.0))
mesh("GalaCanopy", "CanopyRed", stripes[0], CRIMSON, "Fabric")
mesh("GalaCanopy", "CanopyCream", stripes[1], CREAM, "Fabric")
cg = [C(0.38, 49, 0, roof_y(0) + 0.15, 0, segs=8, axis="x"), B(48.4, 0.5, 0.3, 0, 0.85, 20.7)]
for side in (20.75, -20.75):
    for i in range(14):
        cg.append(C(1.6, 0.22, -22.1 + i * 3.4, 0.5, side, segs=6, axis="z"))
mesh("GalaCanopy", "CanopyGold", cg, GOLD, "Fabric")

# ---------------------------------------------------------------- the chandelier (foot: under its lowest gem)
fr = [C(0.16, 2.6, 0, 4.0, 0, segs=6), TOR(3.6, 0.24, 0, 2.8, 0, segs=24, csegs=5), S(0.5, 0, 2.6, 0, segs=10, rings=6)]
for k in range(6):
    a = k * math.pi / 3
    fr.append(T([(0, 2.6, 0), (math.cos(a) * 1.8, 2.3, math.sin(a) * 1.8), (math.cos(a) * 3.5, 2.8, math.sin(a) * 3.5)],
                [0.12, 0.12, 0.12], segs=5))
    fr.append(C(0.32, 0.45, math.cos(a) * 3.6, 3.2, math.sin(a) * 3.6, segs=8))
mesh("GalaChandelier", "ChandelierFrame", fr, GOLD)
gems = [kit.cyl("g", 0.05, 1.15, 1.5, at=rb(0, 1.0, 0), segs=6), kit.cyl("g", 1.15, 0.5, 0.5, at=rb(0, 2.0, 0), segs=6),
        S(0.55, 0, 0.55, 0, segs=6, rings=4)]
for k in range(6):
    a = k * math.pi / 3 + math.pi / 6
    gems.append(S(0.32, math.cos(a) * 3.6, 2.15, math.sin(a) * 3.6, sc=(1, 1.5, 1), segs=6, rings=4))
mesh("GalaChandelier", "ChandelierGems", gems, GEM, "Neon")

# ---------------------------------------------------------------- an exhibit case (foot on the paving)
mesh("ExhibitCase", "CasePlinth", [B(4.2, 0.5, 4.2, 0, 0.25, 0, bev=0.08), B(3.5, 2.1, 3.5, 0, 1.55, 0),
                                   B(4.1, 0.4, 4.1, 0, 2.8, 0, bev=0.08)], MARBLE, "Marble")
mesh("ExhibitCase", "CaseGlass", B(3.4, 3.0, 3.4, 0, 4.5, 0), GLASS, "Glass", 0.6)
cf = [B(3.7, 0.25, 3.7, 0, 6.1, 0), S(0.3, 0, 6.5, 0, segs=8, rings=5), B(3.6, 0.2, 3.6, 0, 3.08, 0)]
for sx in (-1, 1):
    for sz in (-1, 1):
        cf.append(B(0.2, 3.0, 0.2, sx * 1.7, 4.5, sz * 1.7))
mesh("ExhibitCase", "CaseFrame", cf, GOLD)
mesh("ExhibitCase", "CaseCushion", B(2.0, 0.5, 2.0, 0, 3.4, 0, bev=0.18), CRIMSON, "Fabric")
mesh("ExhibitCase", "CaseJewel", [kit.cyl("j", 0.05, 0.75, 0.75, at=rb(0, 4.0, 0), segs=8),
                                  kit.cyl("j", 0.75, 0.45, 0.35, at=rb(0, 4.55, 0), segs=8)], GEM, "Neon")

# ---------------------------------------------------------------- a velvet bench (foot on the paving; the
# audience faces the stage at -z)
mesh("VelvetBench", "BenchVelvet", [B(18, 0.7, 1.8, 0, 1.45, -0.1, bev=0.22), B(18, 1.7, 0.5, 0, 2.55, 0.75, bev=0.2)],
     CRIMSON, "Fabric")
bl = [B(18.2, 0.25, 0.3, 0, 1.0, -0.9), B(18.2, 0.25, 0.3, 0, 3.45, 0.75)]
for x in (-8.5, 0, 8.5):
    for z in (-0.75, 0.75):
        bl.append(C(0.14, 1.1, x, 0.55, z, segs=6))
mesh("VelvetBench", "BenchGold", bl, GOLD)

# ---------------------------------------------------------------- a spotlight on a stand (foot on the paving; it
# shines along +x, toward the stage's middle: the right-hand one is turned round)
st = [C(0.2, 5.6, 0, 6.8, 0, segs=6)]
for k in range(3):
    a = k * 2 * math.pi / 3 + 0.4
    st.append(T([(0, 4.2, 0), (math.cos(a) * 1.7, 0.1, math.sin(a) * 1.7)], [0.13, 0.11], segs=5))
st += [T([(0, 9.4, 0), (0, 9.6, -1.25), (0, 10.5, -1.25)], [0.12] * 3, segs=5),
       T([(0, 9.4, 0), (0, 9.6, 1.25), (0, 10.5, 1.25)], [0.12] * 3, segs=5),
       C(0.95, 2.1, -0.15, 10.5, 0, segs=14, r2=1.15, axis="x"), C(0.6, 0.5, -1.4, 10.5, 0, segs=10, axis="x")]
mesh("GalaSpot", "SpotStand", st, CHARCOAL)
mesh("GalaSpot", "SpotLens", C(1.0, 0.16, 0.95, 10.5, 0, segs=14, axis="x"), (255, 246, 214), "Neon")

# ================================================================ the Racers' Meet (OpenWest)
# ---------------------------------------------------------------- the start gantry (foot: the start line's middle)
tw = []
for x0 in (-18, 18):
    tw.append(B(3.4, 0.4, 3.4, x0, 0.2, 0, bev=0.05))
    for sx in (-1, 1):
        for sz in (-1, 1):
            tw.append(B(0.4, 18, 0.4, x0 + sx * 1.2, 9, sz * 1.2))
    for k in range(4):
        y0, y1 = 0.6 + k * 4.3, 0.6 + (k + 1) * 4.3
        for sz in (-1.2, 1.2):  # the faces along x
            tw.append(T([(x0 - 1.2, y0, sz), (x0 + 1.2, y1, sz)], 0.12, segs=4))
        for sx in (-1.2, 1.2):  # the faces along z
            tw.append(T([(x0 + sx, y0, -1.2), (x0 + sx, y1, 1.2)], 0.12, segs=4))
mesh("StartGantry", "GantryTowers", tw, CHARCOAL)
tr = [C(0.32, 39, 0, 20.8, 0, segs=6, axis="x"), C(0.32, 39, 0, 18.4, -1.15, segs=6, axis="x"),
      C(0.32, 39, 0, 18.4, 1.15, segs=6, axis="x"), B(1.0, 3.0, 3.0, -19.3, 19.5, 0), B(1.0, 3.0, 3.0, 19.3, 19.5, 0)]
for k in range(13):
    x0, x1 = -18 + k * 3, -18 + (k + 1) * 3
    for sz in (-1.15, 1.15):
        tr.append(T([(x0, 18.4, sz), (x1, 20.8, 0)] if k % 2 == 0 else [(x0, 20.8, 0), (x1, 18.4, sz)], 0.14, segs=4))
mesh("StartGantry", "GantryTruss", tr, RED)

# ---------------------------------------------------------------- the start lights (foot: the middle lamp)
hs = [B(17, 2.6, 1.4, 0, 0, -0.5, bev=0.2), B(0.5, 1.2, 0.5, -7, 1.6, -0.5), B(0.5, 1.2, 0.5, 7, 1.6, -0.5)]
for x in (-6, 0, 6):
    hs.append(B(2.6, 0.3, 1.2, x, 1.2, 0.5))
mesh("StartLights", "LightHousing", hs, BLACK)
for name, x, rgb in (("LampRed", -6, (255, 50, 50)), ("LampAmber", 0, (255, 176, 40)), ("LampGreen", 6, (60, 230, 90))):
    mesh("StartLights", name, S(0.95, x, 0, 0.25, sc=(1, 1, 0.75), segs=14, rings=8), rgb, "Neon")

# ---------------------------------------------------------------- a racer (foot on the paving, nose at -z)
body = loft_z([(-5.6, 2.2, 0.7, 1.4), (-4.6, 2.8, 0.5, 1.9), (-2.6, 3.0, 0.5, 2.25), (1.0, 3.0, 0.5, 2.4), (4.0, 3.0, 0.5, 2.4),
               (5.6, 2.7, 0.6, 2.2)], segs=16, power=3.0)
mesh("Racer", "RacerBody", body, RED)
gl = S(1.0, 0, 0, 0, sc=(1.75, 1.4, 2.3), segs=14, rings=8)
kit.cut(gl, (0, 0, -1), keep_positive=False)  # the bubble's bottom half goes
shift(gl, rb(0, 2.3, -0.5))
mesh("Racer", "RacerGlass", gl, (50, 64, 90), "Glass", 0.25)
wg = [B(6.4, 0.3, 1.7, 0, 4.3, 5.0, bev=0.08), B(0.2, 1.0, 1.9, -3.15, 4.1, 5.0), B(0.2, 1.0, 1.9, 3.15, 4.1, 5.0),
      T([(-1.6, 2.3, 4.6), (-1.6, 4.2, 5.0)], 0.14, segs=5), T([(1.6, 2.3, 4.6), (1.6, 4.2, 5.0)], 0.14, segs=5)]
mesh("Racer", "RacerWing", wg, BLACK)
wh = []
for z in (-3.6, 3.5):
    for x in (-3.05, 3.05):
        wh.append(C(1.0, 1.0, x, 1.0, z, segs=14, axis="x"))
mesh("Racer", "RacerWheels", wh, TYRE)
trim = [loft_z([(-5.4, 0.35, 1.35, 1.48), (-4.6, 0.35, 1.8, 1.96), (-2.6, 0.35, 2.2, 2.32), (4.0, 0.35, 2.35, 2.46),
                (5.5, 0.35, 2.15, 2.27)], segs=8, power=3.0)]
for x in (-3.6, 3.6):
    for z in (-3.6, 3.5):
        trim.append(C(0.45, 0.12, x, 1.0, z, segs=10, axis="x"))
for x in (-3.03, 3.03):
    trim.append(C(0.85, 0.08, x, 1.45, 0.6, segs=14, axis="x"))
mesh("Racer", "RacerTrim", trim, WHITE)

# ---------------------------------------------------------------- a tyre stack (foot on the paving)
ty, tp = [], []
for k in range(2):
    t = TOR(1.6, 0.66, 0, 0, 0, segs=18, csegs=8)
    kit.apply_all(t)
    for v in t.data.vertices:
        v.co.z *= 1.2
    t.data.update()
    ty.append(shift(t, rb(0, 0.8 + k * 1.6, 0)))
    tp.append(TOR(1.6, 0.13, 0, 1.5 + k * 1.6, 0, segs=18, csegs=4))
mesh("TyreStack", "TyreStack", ty, TYRE)
mesh("TyreStack", "TyrePaint", tp, WHITE)

# ---------------------------------------------------------------- a fuel drum (foot on the paving)
dr = kit.loft("d", [(0, 1.5, 1.5, 0, 0), (0.15, 1.56, 1.56, 0, 0), (0.3, 1.5, 1.5, 0, 0), (1.45, 1.5, 1.5, 0, 0), (1.5, 1.56, 1.56, 0, 0),
                    (1.55, 1.5, 1.5, 0, 0), (2.7, 1.5, 1.5, 0, 0), (2.85, 1.56, 1.56, 0, 0), (3.0, 1.46, 1.46, 0, 0)], segs=16, power=2.0)
mesh("FuelDrum", "DrumBody", dr, FUEL)
mesh("FuelDrum", "DrumBands", [B(1.6, 1.1, 0.12, 0, 2.1, -1.47), star(0.45, 0.2, 0.1, 0, 2.1, -1.56, points=4),
                                C(0.3, 0.15, 0.6, 3.05, 0.4, segs=8)], YELLOW)

# ---------------------------------------------------------------- the DJ booth (foot: the desk's middle; the
# crowd's side is +z)
bd = [B(10, 3.6, 3.6, 0, 1.8, 0, bev=0.12), B(10.4, 0.45, 4.0, 0, 3.8, -0.1, bev=0.08)]
turn(bd[1], "x", -8, (0, 3.8, 0))
mesh("DJBooth", "BoothDesk", bd, CHARCOAL)
mesh("DJBooth", "BoothSpeakers", [B(3, 6, 3, -8, 3, 0, bev=0.15), B(3, 6, 3, 8, 3, 0, bev=0.15)], BLACK)
cones = []
for x in (-8, 8):
    cones += [C(1.15, 0.35, x, 2.2, 1.6, segs=14, r2=0.5, axis="z"), C(0.55, 0.3, x, 4.7, 1.6, segs=10, r2=0.25, axis="z")]
for x in (-2.6, 2.6):
    cones.append(C(1.2, 0.16, x, 4.15, -0.2, segs=14))
cones.append(B(1.6, 0.3, 1.4, 0, 4.15, -0.2))
mesh("DJBooth", "BoothCones", cones, (176, 182, 194))
neon = [B(10.2, 0.4, 0.2, 0, 2.95, 1.9)]
for i in range(9):
    h = 0.5 + 1.1 * abs(math.sin(i * 1.7 + 0.5))
    neon.append(B(0.6, h, 0.16, -4 + i * 1.0, 0.6 + h / 2, 1.88))
mesh("DJBooth", "BoothNeon", neon, PINK, "Neon")

# ---------------------------------------------------------------- a floodlight (foot on the paving; it faces -z)
mesh("Floodlight", "FloodMast", [C(1.0, 0.4, 0, 0.2, 0, segs=12), C(0.45, 19.8, 0, 10.3, 0, segs=10, r2=0.3),
                                 B(4.8, 0.3, 0.3, 0, 20.5, -0.35), T([(0, 19.6, 0), (0, 20.5, -0.35)], 0.18, segs=5)], STEEL)
fh, fl = [], []
for x in (-1.1, 1.1):
    h = B(1.9, 1.9, 1.2, x, 20.5, -1.0, bev=0.12)
    turn(h, "x", -15, (x, 20.5, -1.0))
    fh.append(h)
    lm = B(1.6, 1.6, 0.16, x, 20.5, -1.62)
    turn(lm, "x", -15, (x, 20.5, -1.0))
    fl.append(lm)
mesh("Floodlight", "FloodHead", fh, CHARCOAL)
mesh("Floodlight", "FloodLamps", fl, (255, 252, 236), "Neon")

# ---------------------------------------------------------------- the kicker ramp (foot under the deck's low
# end; the deck is tilted 18 degrees about x, high at -z, just like its box)
dk = B(10, 1, 12, 0, 0, 0, bev=0.08)
lip = B(10.2, 0.5, 0.5, 0, 0.6, -5.8)
chev = []
for k in range(3):
    for s in (-1, 1):
        c = B(2.8, 0.06, 0.45, s * 1.2, 0.53, -2.8 + k * 3.0)
        turn(c, "up", s * 32, (s * 1.2, 0.53, -2.8 + k * 3.0))
        chev.append(c)
for ob in [dk, lip] + chev:
    turn(ob, "x", 18)
    shift(ob, rb(0, 2.6, -6))
mesh("KickerRamp", "RampDeck", [dk, lip], YELLOW, "DiamondPlate")
mesh("KickerRamp", "RampChevrons", chev, BLACK)
hz = -6 - 6 * math.cos(math.radians(18))
hy = 2.6 + 6 * math.sin(math.radians(18)) - 0.5
sp = [(hz, 0.0), (hz, hy), (-1.0, 1.0), (-1.0, 0.0)]
fr = [B(10, 2, 6, 0, 1, 2, bev=0.1), prism(sp, -4.9, -4.4), prism(sp, 4.4, 4.9), B(10, 0.4, 0.4, 0, 0.2, hz + 0.3)]
mesh("KickerRamp", "RampFrame", fr, STEEL, "DiamondPlate")

# ================================================================ Tick-Tock Toys (the "toyshop" pocket)
# ---------------------------------------------------------------- the clock sign over the door (foot: its middle;
# it faces -z, into the shop)
mesh("ToyClock", "ClockFace", C(7.2, 0.6, 0, 0, -0.2, segs=28, axis="z"), (252, 246, 226))
rim = [TOR(7.55, 0.7, 0, 0, -0.1, axis="z", segs=28, csegs=6), S(0.7, 0, 8.4, 0, segs=10, rings=6),
       B(0.5, 1.2, 0.5, 0, 7.9, 0)]
mesh("ToyClock", "ClockRim", rim, TOYRED)
bells = []
for s in (-1, 1):
    bl_ = S(2.3, 0, 0, 0, sc=(1, 0.8, 1), segs=14, rings=8)
    kit.cut(bl_, (0, 0, -1), keep_positive=False)
    shift(bl_, rb(0, -0.3, 0))
    turn(bl_, "z", -s * 30)
    shift(bl_, rb(s * 4.8, 6.6, 0))
    bells += [bl_, C(0.6, 0.7, s * 4.0, -7.8, 0, segs=8, r2=0.35)]
bells.append(C(0.75, 0.3, 0, 0, -0.7, segs=12, axis="z"))
mesh("ToyClock", "ClockBells", bells, GOLD)
hands = [B(0.75, 5.6, 0.25, 0, 2.6, -0.65), B(4.6, 0.9, 0.25, 2.1, 0, -0.65)]
for k in range(12):
    a = k * math.pi / 6
    h = B(0.5, 1.1 if k % 3 == 0 else 0.6, 0.15, 0, 0, 0)
    turn(h, "z", -math.degrees(a))
    shift(h, rb(math.sin(a) * 6.0, math.cos(a) * 6.0, -0.55))
    hands.append(h)
mesh("ToyClock", "ClockHands", hands, NAVY)

# ---------------------------------------------------------------- a toy shelf (foot: its middle on the floor;
# five toys on top, coloured per copy)
sh = [B(70, 11.2, 0.25, 0, 6.0, 0)]
for x in (-35, -17.5, 0, 17.5, 35):
    sh.append(B(0.7, 12, 4, x, 6, 0, bev=0.06))
for y in (0.35, 4.2, 8.1, 11.85):
    sh.append(B(70.4, 0.4, 4.2, 0, y, 0, bev=0.05))
mesh("ToyShelf", "ToyShelfFrame", sh, WOOD, "Wood")
stuff = {0: [], 1: []}
k = 0
for y in (0.55, 4.4, 8.3):
    for side in (-1, 1):
        x = -33.0
        while x < 32:
            w = 1.8 + (k * 7 % 5) * 0.45
            h = 1.6 + (k * 3 % 4) * 0.5
            if k % 3 == 2:
                stuff[k % 2].append(S(h * 0.45, x + w / 2, y + h * 0.45, side * 1.0, segs=6, rings=4))
            else:
                stuff[k % 2].append(B(w, h, 1.4, x + w / 2, y + h / 2, side * 1.0))
            x += w + 1.6 + (k % 3) * 0.9
            if abs(x) < 1.0 or abs(abs(x) - 17.5) < 1.2:
                x += 1.4
            k += 1
mesh("ToyShelf", "ShelfStuffA", stuff[0], (255, 196, 60))
mesh("ToyShelf", "ShelfStuffB", stuff[1], (90, 200, 180))
X5 = (-30, -16, -2, 12, 26)
Y0 = 12.05
# 1 a rocket
r1 = [kit.loft("r", [(0, 0.9, 0.9, 0, 0), (2.2, 1.0, 1.0, 0, 0), (3.2, 0.6, 0.6, 0, 0), (3.9, 0.05, 0.05, 0, 0)], segs=12, power=2.0)]
for k in range(3):
    f = B(0.2, 1.3, 1.1, 0, 0.6, 0)
    shift(f, rb(0, 0, -1.0))
    turn(f, "up", k * 120)
    r1.append(f)
r1 = [move(o, X5[0], Y0) for o in r1]
mesh("ToyShelf", "ShelfToy1", r1, TOYRED)
# 2 a tin robot
r2 = [B(2.4, 1.9, 1.8, 0, 1.1, 0, bev=0.12), B(1.7, 1.2, 1.4, 0, 2.7, 0, bev=0.12), C(0.08, 0.6, 0, 3.6, 0, segs=5),
      S(0.2, 0, 3.95, 0, segs=6, rings=4), B(0.5, 1.4, 0.5, -1.5, 1.4, 0), B(0.5, 1.4, 0.5, 1.5, 1.4, 0),
      B(0.7, 0.4, 0.9, -0.6, 0.0, 0), B(0.7, 0.4, 0.9, 0.6, 0.0, 0)]
r2 = [move(o, X5[1], Y0 + 0.2) for o in r2]
mesh("ToyShelf", "ShelfToy2", r2, TOYBLUE)
# 3 a plush bear
r3 = [S(1.15, 0, 1.15, 0, sc=(1, 1.05, 0.9), segs=10, rings=6), S(0.85, 0, 2.75, 0, segs=10, rings=6),
      S(0.33, -0.65, 3.5, 0, segs=6, rings=4), S(0.33, 0.65, 3.5, 0, segs=6, rings=4), S(0.3, 0, 2.6, -0.8, segs=6, rings=4),
      S(0.38, -1.1, 1.4, -0.2, segs=6, rings=4), S(0.38, 1.1, 1.4, -0.2, segs=6, rings=4)]
r3 = [move(o, X5[2], Y0) for o in r3]
mesh("ToyShelf", "ShelfToy3", r3, TOYWHITE, "Fabric")
# 4 a drum with sticks
r4 = [C(1.3, 1.6, 0, 0.8, 0, segs=14), TOR(1.32, 0.12, 0, 0.1, 0, segs=14, csegs=4), TOR(1.32, 0.12, 0, 1.55, 0, segs=14, csegs=4),
      T([(-0.4, 1.7, 0.2), (0.8, 2.5, -0.4)], 0.07, segs=4), T([(0.4, 1.7, 0.4), (-0.7, 2.6, -0.2)], 0.07, segs=4)]
r4 = [move(o, X5[3], Y0) for o in r4]
mesh("ToyShelf", "ShelfToy4", r4, TOYRED)
# 5 a toy car
r5 = [loft_z([(-1.6, 0.8, 0.35, 0.9), (-0.8, 0.9, 0.3, 1.2), (0.2, 0.85, 0.3, 1.9), (1.0, 0.85, 0.3, 1.8), (1.6, 0.8, 0.35, 1.0)],
             segs=10, power=3.0)]
for z in (-1.0, 1.0):
    for x in (-0.85, 0.85):
        r5.append(C(0.42, 0.32, x, 0.42, z, segs=10, axis="x"))
r5 = [move(o, X5[4], Y0, 0, 90) for o in r5]
mesh("ToyShelf", "ShelfToy5", r5, TOYBLUE)

# ---------------------------------------------------------------- the toy train round the rug (foot: the ring's middle)
rails = [TOR(25.2, 0.2, 0, 0.32, 0, segs=32, csegs=4), TOR(26.8, 0.2, 0, 0.32, 0, segs=32, csegs=4)]
mesh("ToyTrain", "TrainRails", rails, (180, 186, 196))
sl = []
for k in range(30):
    a = k * 2 * math.pi / 30
    s_ = B(0.6, 0.2, 2.8, 0, 0.1, 0)
    move(s_, math.cos(a) * 26, 0, math.sin(a) * 26, -math.degrees(a) + 90)
    sl.append(s_)
mesh("ToyTrain", "TrainSleepers", sl, DARKWOOD, "Wood")
cars, roofs, wheels = [], [], []
for i in range(8):
    a = i * math.pi / 4
    yaw = -math.degrees(a)
    px, pz = math.cos(a) * 26, math.sin(a) * 26
    if i == 0:  # the engine: boiler, cab and chimney
        parts_c = [C(0.95, 3.0, 0, 1.45, -0.6, segs=12, axis="z"), B(2.4, 1.9, 1.6, 0, 1.55, 1.4, bev=0.12),
                   B(2.6, 0.4, 4.6, 0, 0.55, 0)]
        parts_r = [B(2.8, 0.3, 2.0, 0, 2.65, 1.4, bev=0.08), C(0.4, 1.1, 0, 2.7, -1.5, segs=8, r2=0.6)]
    else:
        parts_c = [B(2.4, 1.5, 4.2, 0, 1.25, 0, bev=0.15)]
        parts_r = [B(2.7, 0.3, 4.5, 0, 2.1, 0, bev=0.08)] if i % 2 == 1 else [S(0.6, -0.5, 2.2, -0.8, segs=8, rings=5),
                                                                              S(0.6, 0.4, 2.2, 0.7, segs=8, rings=5)]
    parts_w = [C(0.5, 2.7, 0, 0.5, z, segs=8, axis="x") for z in (-1.4, 1.4)]
    for o in parts_c:
        cars.append(move(o, px, 0, pz, yaw))
    for o in parts_r:
        roofs.append(move(o, px, 0, pz, yaw))
    for o in parts_w:
        wheels.append(move(o, px, 0, pz, yaw))
mesh("ToyTrain", "TrainCars", cars, TOYRED)
mesh("ToyTrain", "TrainRoofs", roofs, TOYBLUE)
mesh("ToyTrain", "TrainWheels", wheels, BLACK)

# ---------------------------------------------------------------- a giant toy block (foot on the floor)
blk = B(5, 5, 5, 0, 2.5, 0)
kit.bevel(blk, 0.4, 2)
mesh("ToyBlock", "ToyBlockBody", blk, TOYWHITE)
mk = [star(1.5, 0.65, 0.2, 0, 2.5, -2.55), C(1.3, 0.2, 2.55, 2.5, 0, segs=16, axis="x"), C(1.2, 0.2, 0, 5.05, 0, segs=4),
      kit.cyl("tri", 1.5, 1.5, 0.2, at=(0, 0, 0), segs=3, axis="Y")]
shift(mk[-1], rb(0, 2.4, 2.55))
mk.append(B(0.2, 2.2, 2.2, -2.55, 2.5, 0))
mesh("ToyBlock", "ToyBlockMarks", mk, TOYRED)

# ---------------------------------------------------------------- the music box (foot on the floor)
mb = [B(9.6, 6.4, 7.6, 0, 3.9, 0, bev=0.25)]
lid = B(9.6, 0.6, 7.6, 0, 0, 3.8, bev=0.15)
turn(lid, "x", -105)
shift(lid, rb(0, 7.1, -3.8))
mb.append(lid)
mesh("MusicBox", "MusicBoxBody", mb, (240, 132, 172))
mg = [B(9.9, 0.4, 7.9, 0, 1.0, 0), B(9.9, 0.4, 7.9, 0, 7.0, 0)]
for sx in (-1, 1):
    for sz in (-1, 1):
        mg.append(S(0.45, sx * 4.2, 0.45, sz * 3.2, segs=8, rings=5))
mg += [C(0.25, 1.6, 5.6, 4.2, 0, segs=8, axis="x"), TOR(0.7, 0.18, 6.6, 4.9, 0, axis="x", segs=12, csegs=4),
       TOR(0.7, 0.18, 6.6, 3.5, 0, axis="x", segs=12, csegs=4)]
mesh("MusicBox", "MusicBoxGold", mg, GOLD)
mesh("MusicBox", "MusicBoxStage", C(2.9, 0.45, 0, 7.4, 0, segs=18), (140, 214, 255), "Neon")
dn = [kit.loft("sk", [(7.7, 0.15, 0.15, 0, 0), (8.0, 1.1, 1.1, 0, 0), (8.25, 0.4, 0.4, 0, 0), (9.6, 0.32, 0.32, 0, 0)], segs=12, power=2.0),
      S(0.45, 0, 10.1, 0, segs=10, rings=6), T([(-0.25, 9.4, 0), (-0.8, 10.3, 0), (-0.3, 11.0, 0)], 0.1, segs=4),
      T([(0.25, 9.4, 0), (0.8, 10.3, 0), (0.3, 11.0, 0)], 0.1, segs=4)]
dn[0] = shift(dn[0], (0, 0, 0))
mesh("MusicBox", "MusicBoxDancer", dn, TOYWHITE)

# ---------------------------------------------------------------- the counter and till (foot: the counter's middle;
# the shop floor is at +z)
cb = [B(49, 3.4, 5.6, 0, 1.7, 0, bev=0.12)]
for i in range(8):
    cb.append(B(5.0, 2.2, 0.2, -21 + i * 6, 1.8, 2.85, bev=0.04))
mesh("ShopCounter", "CounterBody", cb, WOOD, "Wood")
mesh("ShopCounter", "CounterTop", [B(50.4, 0.5, 6.4, 0, 3.65, 0, bev=0.1), B(50, 0.4, 0.4, 0, 0.2, 2.9)], TOYRED)
tl = [B(3.6, 1.4, 2.8, -16, 4.6, 0, bev=0.12), B(3.4, 1.0, 1.4, -16, 5.4, -0.6, bev=0.1), B(2.2, 1.0, 0.25, -16, 6.4, -0.9),
      C(0.15, 1.0, -14.0, 5.0, 0, segs=6, axis="x"), S(0.3, -13.4, 5.0, 0, segs=8, rings=5)]
key = B(3.0, 0.3, 1.2, -16, 5.4, 0.5)
turn(key, "x", 20, (-16, 5.4, 0.5))
tl.append(key)
mesh("ShopCounter", "ShopTill", tl, BRASS)

# ---------------------------------------------------------------- a wind-up key on its plinth (foot on the basement
# floor; its pipe runs along +x to the hall's middle, 120 studs)
pl = [C(4.1, 1.0, 0, 0.5, 0, segs=20)]
for k in range(12):
    t_ = B(1.0, 0.9, 0.9, 0, 0.45, 0)
    shift(t_, rb(0, 0, -4.3))
    turn(t_, "up", k * 30)
    pl.append(t_)
mesh("WindKey", "WinderPlinth", pl, STEEL)
wk = [C(0.75, 6.8, 0, 4.2, 0, segs=10), TOR(0.95, 0.25, 0, 1.4, 0, segs=12, csegs=4), C(0.5, 1.2, 0, 7.9, 0, segs=8),
      TOR(1.75, 0.5, -2.1, 9.3, 0, axis="z", segs=16, csegs=6), TOR(1.75, 0.5, 2.1, 9.3, 0, axis="z", segs=16, csegs=6),
      B(1.4, 1.6, 0.9, 0, 9.0, 0, bev=0.15)]
mesh("WindKey", "WinderKey", wk, BRASS)
wp = [T([(4.6, 1.0, 0), (4.6, 13.0, 0), (5.4, 13.9, 0), (6.4, 14.0, 0)], [0.7, 0.7, 0.72, 0.72], segs=10),
      C(0.75, 114, 63.0, 14.0, 0, segs=10, axis="x"), B(2.0, 2.0, 2.0, 4.6, 1.0, 0, bev=0.15)]
for x in range(20, 120, 25):
    wp.append(C(1.0, 0.5, x, 14.0, 0, segs=10, axis="x"))
mesh("WindKey", "WinderPipe", wp, (104, 112, 126))

# ---------------------------------------------------------------- the Tantrum Tap (foot: the tank's middle on the
# floor; the main pipe comes in along +z at 14 up, the gauge faces +z)
tank = kit.loft("tank", [(0, 13.0, 13.0, 0, 0), (0.6, 13.2, 13.2, 0, 0), (15.0, 13.0, 13.0, 0, 0), (16.6, 11.6, 11.6, 0, 0),
                         (18.0, 8.0, 8.0, 0, 0), (18.8, 3.2, 3.2, 0, 0), (19.0, 0.2, 0.2, 0, 0)], segs=24, power=2.0)
mesh("TantrumTap", "TapTank", tank, BRASS)
tb = [TOR(13.1, 0.4, 0, 3.0, 0, segs=24, csegs=4), TOR(13.1, 0.4, 0, 9.0, 0, segs=24, csegs=4),
      TOR(13.1, 0.4, 0, 14.4, 0, segs=24, csegs=4), C(0.5, 1.4, 0, 19.4, 0, segs=8),
      TOR(2.4, 0.35, 0, 20.2, 0, segs=16, csegs=5), B(0.3, 0.3, 4.6, 0, 20.2, 0), B(4.6, 0.3, 0.3, 0, 20.2, 0),
      B(0.3, 2.2, 0.2, 0.6, 12.4, 13.6)]
turn(tb[-1], "z", -35, (0, 12, 13.6))
mesh("TantrumTap", "TapBands", tb, (214, 52, 64))
tp_ = [C(0.75, 86, 0, 14.0, 55.0, segs=10, axis="z"), T([(9.0, 4.5, 9.6), (11.2, 4.5, 12.0), (11.8, 3.2, 12.6), (11.8, 2.0, 12.6)],
                                                      [0.9, 0.9, 0.9, 0.7], segs=10),
       TOR(1.2, 0.25, 11.8, 6.0, 12.6, segs=12, csegs=4), C(0.15, 1.6, 11.8, 5.2, 12.6, segs=5)]
for z in range(25, 100, 18):
    tp_ += [C(1.0, 0.5, 0, 14.0, z, segs=10, axis="z"), C(0.25, 13.3, 0, 6.65, z, segs=6)]
mesh("TantrumTap", "TapPipes", tp_, STEEL)
mesh("TantrumTap", "TapGauge", [B(7.6, 3.6, 0.3, 0, 12, 13.25, bev=0.12)], (156, 110, 255), "Neon")

# ---------------------------------------------------------------- a toy soldier bench (foot: the bench's middle on
# the floor; four soldiers on it at x -20, -8, 4, 16)
bp = [B(60, 0.7, 8, 0, 2.65, 0, bev=0.1)]
for x in (-27, -9, 9, 27):
    for z in (-3, 3):
        bp.append(B(1.0, 2.4, 1.0, x, 1.2, z))
mesh("SoldierBench", "BenchPlanks", bp, WOOD, "Wood")
js, tr_, fc = [], [], []
for x in (-20, -8, 4, 16):
    js += [B(2.1, 2.0, 1.7, x, 4.9, 0, bev=0.15), B(0.6, 1.8, 0.6, x - 1.4, 4.9, 0, bev=0.1), B(0.6, 1.8, 0.6, x + 1.4, 4.9, 0, bev=0.1)]
    tr_ += [B(0.8, 1.4, 0.9, x - 0.5, 3.55, 0, bev=0.08), B(0.8, 1.4, 0.9, x + 0.5, 3.55, 0, bev=0.08),
            C(0.85, 1.9, x, 7.5, 0, segs=10, r2=0.75), B(2.2, 0.3, 1.8, x, 4.0, 0), C(0.25, 0.25, x, 7.0, -0.85, segs=6, axis="z")]
    fc.append(S(0.72, x, 6.3, 0, segs=10, rings=6))
mesh("SoldierBench", "ToySoldiers", js, TOYRED)
mesh("SoldierBench", "SoldierTrim", tr_, NAVY)
mesh("SoldierBench", "SoldierFaces", fc, SKIN)

# ================================================================ the farm folk's truck (The Harvest King)
# ---------------------------------------------------------------- foot on the road, nose at -z
tk = [B(6.8, 2.6, 4.0, 0, 2.5, -5.0, bev=0.35), B(6.6, 4.4, 4.6, 0, 3.6, -1.3, bev=0.35), B(7.0, 0.5, 6.4, 0, 1.55, 4.0, bev=0.08),
      B(0.35, 1.8, 6.4, -3.35, 2.5, 4.0, bev=0.06), B(0.35, 1.8, 6.4, 3.35, 2.5, 4.0, bev=0.06), B(6.6, 1.8, 0.35, 0, 2.5, 7.0, bev=0.06)]
for z in (-4.6, 4.4):
    for x in (-3.0, 3.0):
        f = TOR(1.45, 0.35, 0, 0, 0, axis="x", segs=14, csegs=4, arc=math.pi)
        turn(f, "x", 90)  # the half ring over the wheel
        shift(f, rb(x, 1.25, z))
        tk.append(f)
mesh("FarmTruck", "FarmTruckBody", tk, (214, 52, 46))
gw = [B(6.0, 1.7, 0.2, 0, 4.7, -3.6), B(0.2, 1.6, 2.6, -3.32, 4.7, -1.2), B(0.2, 1.6, 2.6, 3.32, 4.7, -1.2)]
turn(gw[0], "x", -14, (0, 4.7, -3.6))
mesh("FarmTruck", "FarmTruckGlass", gw, (150, 200, 232), "Glass", 0.3)
fw = []
for z in (-4.6, 4.4):
    for x in (-3.0, 3.0):
        fw.append(C(1.2, 1.0, x, 1.2, z, segs=14, axis="x"))
mesh("FarmTruck", "FarmTruckWheels", fw, TYRE)
ft = [B(7.2, 0.7, 0.6, 0, 1.4, -7.1, bev=0.15), B(7.2, 0.6, 0.5, 0, 1.4, 7.25, bev=0.15), B(4.0, 1.4, 0.2, 0, 2.7, -7.05),
      C(0.45, 0.2, -2.6, 3.0, -7.05, segs=10, axis="z"), C(0.45, 0.2, 2.6, 3.0, -7.05, segs=10, axis="z")]
for z in (-4.6, 4.4):
    for x in (-3.55, 3.55):
        ft.append(C(0.5, 0.12, x, 1.2, z, segs=10, axis="x"))
mesh("FarmTruck", "FarmTruckTrim", ft, (244, 242, 232))
mesh("FarmTruck", "FarmTruckHay", [B(2.8, 1.6, 2.6, -1.5, 2.6, 3.0, bev=0.2), B(2.8, 1.6, 2.6, 1.5, 2.6, 5.4, bev=0.2),
                                   B(2.8, 1.5, 2.4, -1.4, 4.15, 3.2, bev=0.2)], HAY, "Fabric")
pk = []
for (x, y, z, r) in ((1.6, 2.7, 2.6, 1.0), (-1.4, 5.5, 3.1, 0.85), (1.5, 4.0, 5.5, 0.75)):
    p = S(r, 0, 0, 0, sc=(1.15, 0.85, 1.15), segs=12, rings=7)
    kit.apply_all(p)
    for v in p.data.vertices:  # the ribs
        a = math.atan2(v.co.y, v.co.x)
        v.co.x *= 1 + 0.07 * math.cos(a * 6)
        v.co.y *= 1 + 0.07 * math.cos(a * 6)
    p.data.update()
    pk.append(shift(p, rb(x, y, z)))
mesh("FarmTruck", "FarmTruckPumpkins", pk, ORANGE)
mesh("FarmTruck", "FarmTruckStems", [C(0.14, 0.5, 1.6, 3.6, 2.6, segs=5), C(0.12, 0.45, -1.4, 6.3, 3.1, segs=5),
                                     C(0.12, 0.4, 1.5, 4.7, 5.5, segs=5)], GREEN)


# ================================================================ Brine's sea cave (the "seacave" pocket)
# ---------------------------------------------------------------- a tide pool rock (foot on the shelf)
def lump(r, sc, at, segs=10, rings=6, seed=0.0):
    o = S(r, 0, 0, 0, sc=sc, segs=segs, rings=rings)
    kit.apply_all(o)
    for v in o.data.vertices:
        n = 1 + 0.12 * math.sin(v.co.x * 2.1 + seed) * math.cos(v.co.y * 1.7 - seed) + 0.08 * math.sin(v.co.z * 2.6 + seed * 2)
        v.co *= n
    o.data.update()
    return shift(o, rb(*at))


rk = kit.join("CaveRock", [lump(1, (4.0, 2.8, 3.4), (0, 2.0, 0)), lump(1, (2.4, 1.8, 2.2), (2.2, 1.0, 1.2), seed=1.3),
                           lump(1, (1.8, 1.4, 1.6), (-2.6, 0.8, -1.0), seed=2.1)], shade=False)
kit.cut(rk, (0, 0, -1), keep_positive=False)
mesh("CaveRock", "CaveRock", rk, ROCK, "Slate")

# ---------------------------------------------------------------- a coral (foot on the floor; tinted per copy)
co = [T([(0, 0, 0), (0.1, 1.0, 0), (0, 1.6, 0.1)], [0.42, 0.32, 0.26], segs=7)]
for k, (dx, dy, dz) in enumerate(((1.2, 2.3, 0.3), (-1.1, 2.6, -0.4), (0.3, 3.0, -1.0), (-0.4, 2.2, 1.1), (0.6, 2.9, 0.8))):
    mid = (dx * 0.45, 1.3 + dy * 0.3, dz * 0.45)
    co.append(T([(0, 1.1, 0), mid, (dx, dy, dz)], [0.28, 0.22, 0.16], segs=6))
    co.append(S(0.3, dx, dy, dz, segs=7, rings=5))
mesh("Coral", "CoralBranch", co, (255, 120, 120))

# ---------------------------------------------------------------- a mooring post (foot on the wharf)
mesh("MooringPost", "PostWood", [C(0.85, 4.8, 0, 2.4, 0, segs=10, r2=0.8), C(1.0, 0.45, 0, 5.0, 0, segs=10, r2=0.75)],
     DARKWOOD, "Wood")
mesh("MooringPost", "PostRope", [TOR(0.95, 0.2, 0, 3.0, 0, segs=12, csegs=5), TOR(0.95, 0.2, 0, 3.45, 0, segs=12, csegs=5),
                                 T([(0.9, 3.0, 0.2), (1.3, 2.0, 0.6), (1.1, 0.4, 1.4)], 0.16, segs=5)], ROPE, "Fabric")

# ---------------------------------------------------------------- the rowboat (foot on the wharf, bow at -z)
STN = [(-7.0, 0.2, 1.1, 2.1), (-5.6, 1.9, 0.4, 1.9), (-2.5, 2.9, 0.1, 1.8), (2.5, 2.9, 0.1, 1.8), (5.6, 2.3, 0.35, 1.85), (6.9, 1.6, 0.7, 1.9)]
# the hull's deck sits low (the floor boards); a fat rail round the top edge makes the sides, so it reads open
mesh("Rowboat", "RowboatHull", hull_z([(z, w, yb, yt - 0.8) for (z, w, yb, yt) in STN], segs=10), TEAL)
gun = [(w - 0.2, yt - 0.4, z) for (z, w, yb, yt) in STN[1:]] + [(-w + 0.2, yt - 0.4, z) for (z, w, yb, yt) in reversed(STN[1:])]
rim_out = T(gun + [gun[0]], 0.42, segs=6)
floor_ = hull_z([(z, max(0.1, w - 0.35), yt - 0.8, yt - 0.76) for (z, w, yb, yt) in STN[1:-1]], segs=6)
rw = [rim_out, floor_, B(5.4, 0.3, 1.1, 0, 1.75, -1.5), B(4.8, 0.3, 1.0, 0, 1.75, 3.0),
      T([(-3.6, 2.1, -3.4), (3.2, 2.0, 1.6)], 0.12, segs=5), B(0.25, 0.9, 2.0, 3.6, 2.0, 1.9)]
mesh("Rowboat", "RowboatWood", rw, WOOD, "Wood")

# ---------------------------------------------------------------- Finn's cage (foot: its middle on the wharf)
cb_ = [B(11, 0.4, 0.5, 0, 0.2, -5.25), B(11, 0.4, 0.5, 0, 0.2, 5.25), B(0.5, 0.4, 11, -5.25, 0.2, 0), B(0.5, 0.4, 11, 5.25, 0.2, 0),
       B(11.2, 0.45, 11.2, 0, 8.2, 0, bev=0.08), TOR(0.8, 0.15, 0, 9.2, 0, axis="x", segs=12, csegs=4)]
for i in range(9):
    t_ = -5.0 + i * 1.25
    for (x, z) in ((t_, -5.0), (t_, 5.0), (-5.0, t_), (5.0, t_)):
        cb_.append(C(0.13 if abs(t_) < 4.9 else 0.3, 8.0, x, 4.1, z, segs=5))
mesh("FinnCage", "CageBars", cb_, STEEL)
mesh("FinnCage", "CageLock", [B(1.0, 1.1, 0.4, 0, 3.6, 5.25, bev=0.1), TOR(0.32, 0.1, 0, 4.25, 5.25, axis="z", segs=10, csegs=4,
                                                                         arc=math.pi)], GOLD)

# ---------------------------------------------------------------- the Drowned Gull (foot: its middle on the grotto
# floor; bow at -z, hologram sails fore and aft of the mast)
HS = [(-30.0, 0.6, 2.2, 5.6), (-26.0, 6.2, 0.8, 5.4), (-18.0, 10.0, 0.0, 5.2), (10.0, 11.0, 0.0, 5.2), (24.0, 10.0, 0.4, 5.8),
      (29.6, 8.0, 1.2, 6.6)]
mesh("DrownedGull", "ShipHull", hull_z(HS, segs=12), (40, 104, 96))
dk_ = hull_z([(z, w - 0.5, yt - 0.4, yt) for (z, w, yb, yt) in HS[1:]], segs=8)
mesh("DrownedGull", "ShipDeck", [dk_, B(8, 3, 6, 0, 7.0, 23.5, bev=0.2)], WOOD, "Wood")
ms = [C(0.75, 13.0, 0, 11.5, 0, segs=10, r2=0.5), C(0.28, 42, 0, 8.2, 0, segs=6, axis="z"), C(0.25, 40, 0, 16.0, 0, segs=6, axis="z"),
      C(1.1, 0.8, 0, 15.4, 0, segs=10)]
mesh("DrownedGull", "ShipMast", ms, DARKWOOD, "Wood")


def sail(z0, z1, y0, y1, bulge, t=0.3, nu=8, nv=5):
    bm = bmesh.new()
    grid = {}
    for side in (-1, 1):
        for i in range(nu + 1):
            for j in range(nv + 1):
                u, v = i / nu, j / nv
                x = bulge * math.sin(math.pi * u) * math.sin(math.pi * v * 0.9 + 0.15) + side * t / 2
                grid[(side, i, j)] = bm.verts.new(rb(x, y0 + (y1 - y0) * v, z0 + (z1 - z0) * u))
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((grid[(1, i, j)], grid[(1, i + 1, j)], grid[(1, i + 1, j + 1)], grid[(1, i, j + 1)]))
            bm.faces.new((grid[(-1, i, j)], grid[(-1, i, j + 1)], grid[(-1, i + 1, j + 1)], grid[(-1, i + 1, j)]))
    edge = [(i, 0) for i in range(nu)] + [(nu, j) for j in range(nv)] + [(i, nv) for i in range(nu, 0, -1)] + [(0, j) for j in range(nv, 0, -1)]
    for k in range(len(edge)):
        a, b = edge[k], edge[(k + 1) % len(edge)]
        bm.faces.new((grid[(1, *a)], grid[(-1, *a)], grid[(-1, *b)], grid[(1, *b)]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("sail")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("sail", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


mesh("DrownedGull", "ShipSails", [sail(-20.5, -1.2, 8.6, 15.6, 1.6), sail(1.2, 20.5, 8.6, 15.6, 1.6)], (130, 226, 255), "Neon", 0.45)
mesh("DrownedGull", "ShipLens", [S(1.05, 0, 17.5, 0, segs=12, rings=8)], SPARK, "Neon")
rail = [T([(sx * (w - 0.1), yt + 0.35, z) for (z, w, yb, yt) in HS[1:]], 0.18, segs=5) for sx in (-1, 1)]
gull = [S(1.0, 0, 5.6, -30.6, sc=(0.8, 0.8, 1.3), segs=10, rings=6), S(0.6, 0, 6.5, -31.6, segs=8, rings=5),
        kit.cyl("beak", 0.25, 0.02, 0.8, at=(0, 0, 0), segs=6, axis="Y")]
shift(gull[-1], rb(0, 6.4, -32.3))
for s_ in (-1, 1):
    wing = B(2.6, 0.25, 1.1, s_ * 1.6, 6.0, -30.2)
    turn(wing, "z", s_ * 25, (s_ * 0.4, 6.0, -30.2))
    gull.append(wing)
mesh("DrownedGull", "ShipTrim", rail + gull, GOLD)

# ---------------------------------------------------------------- a projector rig (foot on the grotto floor; it
# throws its light along +x, toward the ship's pool: the east rigs are turned round)
pb = [B(6.6, 1.0, 6.6, 0, 0.5, 0, bev=0.15), C(0.6, 5.2, 0, 3.6, 0, segs=8), C(1.35, 3.4, -0.4, 7.5, 0, segs=14, axis="x"),
      B(1.6, 2.2, 2.2, -2.6, 7.5, 0, bev=0.12), C(1.6, 0.4, 1.35, 7.5, 0, segs=14, r2=1.6, axis="x")]
for k in range(3):
    pb.append(B(0.2, 3.0, 3.0, -1.6 + k * 0.7, 7.5, 0))
mesh("Projector", "ProjectorBase", pb, STEEL)
mesh("Projector", "ProjectorLens", C(1.25, 0.2, 1.6, 7.5, 0, segs=14, axis="x"), SPARK, "Neon")

# ---------------------------------------------------------------- a treasure chest (foot on the floor; its lid opens
# back toward -z, the wall)
lid = C(2.3, 7.6, 0, 0, 0, segs=12, axis="x")
kit.cut(lid, (0, 0, -1), keep_positive=False)  # a half drum, closed on the chest, then swung open on its back hinge
shift(lid, rb(0, 2.8, 0))
turn(lid, "x", -100, (0, 2.8, -2.3))
mesh("TreasureChest", "ChestBox", [B(7.6, 2.8, 4.6, 0, 1.4, 0, bev=0.12), lid], (164, 98, 54), "Wood")
cbn = [B(0.5, 2.9, 4.7, -2.4, 1.4, 0), B(0.5, 2.9, 4.7, 2.4, 1.4, 0), B(7.7, 0.4, 4.7, 0, 0.2, 0)]
mesh("TreasureChest", "ChestBands", cbn, (64, 64, 74))
hp = S(1.0, 0, 0, 0, sc=(3.1, 1.0, 1.9), segs=12, rings=7)
kit.cut(hp, (0, 0, -1), keep_positive=False)
shift(hp, rb(0, 2.8, 0))
cg_ = [hp, B(0.9, 1.0, 0.25, 0, 2.0, 2.35, bev=0.06)]
for (x, y, z) in ((-2.8, 3.1, 1.2), (2.6, 3.0, -0.8), (0.6, 3.9, 0.4), (-1.2, 3.6, -0.6)):
    c_ = C(0.45, 0.12, x, y, z, segs=10)
    turn(c_, "x", 25, (x, y, z))
    cg_.append(c_)
mesh("TreasureChest", "ChestGold", cg_, (252, 204, 60))

# ================================================================ Velmara (the "velmara" pocket)
# ---------------------------------------------------------------- the drowned gate (foot: between the pillars on the
# terrace; the city's side is -z)
gb = []
for x in (-26, 26):
    gb += [B(11, 3, 11, x, 1.5, 0, bev=0.2), B(8.6, 30, 8.6, x, 18, 0, bev=0.3), B(11, 3, 11, x, 34.5, 0, bev=0.2)]
gb += [B(64, 6, 10, 0, 39, 0, bev=0.3), B(66, 1.0, 11, 0, 42.5, 0, bev=0.1)]
tri = [C(0.4, 7.0, 0, 46.4, 0, segs=6), B(5.0, 0.6, 0.8, 0, 46.0, 0), C(0.3, 3.2, -2.3, 47.6, 0, segs=6), C(0.3, 3.2, 2.3, 47.6, 0, segs=6)]
for x in (-2.3, 0, 2.3):
    tri.append(kit.cyl("tip", 0.55, 0.02, 1.2, at=rb(x, 49.8 if x else 50.4, 0), segs=6))
mesh("DrownedGate", "GateBronze", gb + tri, BRONZE)
gv = []
for x in (-26, 26):
    for y in (9, 18, 27):
        gv.append(B(9.2, 0.9, 9.2, x, y, 0))
    gv.append(C(2.0, 0.5, x, 39, -5.1, segs=12, axis="z"))
mesh("DrownedGate", "GateVerdigris", gv, VERDIGRIS)
ru = []
for i in range(11):
    x = -18 + i * 3.6
    kind = i % 3
    if kind == 0:
        g = B(0.9, 0.9, 0.2, x, 39, -5.25)
        turn(g, "z", 45, (x, 39, -5.25))
        ru.append(g)
    elif kind == 1:
        ru += [B(0.25, 1.3, 0.2, x - 0.35, 39, -5.25), B(0.25, 1.3, 0.2, x + 0.35, 39, -5.25), B(1.0, 0.22, 0.2, x, 39.55, -5.25)]
    else:
        ru.append(TOR(0.45, 0.12, x, 39, -5.25, axis="z", segs=10, csegs=4))
mesh("DrownedGate", "GateRunes", ru, SPARK, "Neon")

# ---------------------------------------------------------------- a market stall (foot: its middle on the terrace;
# the street side is +z: the west stalls are turned round)
mesh("MarketStall", "StallCounter", [B(17.6, 3.6, 5.6, 0, 1.8, 0, bev=0.12), B(18.2, 0.45, 6.2, 0, 3.8, 0, bev=0.08)],
     (214, 200, 170))
aw = B(19.0, 0.3, 7.6, 0, 9.6, 0.6, bev=0.05)
turn(aw, "x", 12, (0, 9.6, 0.6))
sa = [aw]
for x in (-8.6, 8.6):
    sa += [C(0.25, 5.6, x, 6.8, -2.6, segs=6), C(0.25, 4.8, x, 6.4, 3.2, segs=6)]
for i in range(10):
    sa.append(C(0.95, 0.25, -8.55 + i * 1.9, 8.75, 4.35, segs=8, axis="z"))
mesh("MarketStall", "StallAwning", sa, (64, 170, 206), "Fabric")
vases = []
for (x, z, h) in ((-5.5, -0.8, 1.9), (-3.4, 0.9, 1.4), (4.2, -0.4, 2.1)):
    vases.append(kit.loft("v", [(0, 0.3, 0.3, 0, 0), (h * 0.35, 0.7, 0.7, 0, 0), (h * 0.75, 0.42, 0.42, 0, 0), (h * 0.85, 0.22, 0.22, 0, 0),
                                (h, 0.35, 0.35, 0, 0)], segs=10, power=2.0, cap=(True, True)))
    shift(vases[-1], rb(x, 4.0, z))
vases += [S(0.6, 1.2, 4.35, 0.5, sc=(1, 0.6, 1), segs=8, rings=5), S(0.5, 6.8, 4.3, 1.2, sc=(1, 0.6, 1), segs=8, rings=5)]
mesh("MarketStall", "StallGoods", vases, (208, 112, 72))


# ---------------------------------------------------------------- the broken columns (foot on the terrace: one look a
# height, each fluted marble with a jagged top)
def column(h):
    sh_ = C(1.65, h - 1.0, 0, 0.8 + (h - 1.0) / 2, 0, segs=12)
    kit.apply_all(sh_)
    top = max(v.co.z for v in sh_.data.vertices)
    for v in sh_.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        if v.co.z > top - 0.05:
            v.co.z -= 0.9 * (0.5 + 0.5 * math.sin(a * 3 + h)) + 0.4 * abs(math.sin(a * 5))
        r = math.hypot(v.co.x, v.co.y)
        if r > 0.01:  # the flutes
            k_ = 1 + 0.06 * math.cos(a * 12)
            v.co.x *= k_
            v.co.y *= k_
    sh_.data.update()
    return [B(4.4, 0.8, 4.4, 0, 0.4, 0, bev=0.1), sh_, B(3.8, 0.4, 3.8, 0, 1.0, 0)]


for name, h in (("ColumnTall", 14), ("ColumnMid", 10), ("ColumnStub", 6)):
    mesh(name, name, column(h), MARBLE, "Marble")

# ---------------------------------------------------------------- the old fountain and the Tidewright's statue (foot:
# the basin's middle on the terrace; the statue looks along -z)
fr_ = [B(33, 0.9, 33, 0, 0.45, 0)]
for (sx, sz, x, z) in ((34, 1.8, 0, 16.1), (34, 1.8, 0, -16.1), (1.8, 30.4, 16.1, 0), (1.8, 30.4, -16.1, 0)):
    fr_.append(B(sx, 1.7, sz, x, 0.85, z, bev=0.2))
fr_ += [C(3.6, 1.0, 0, 1.3, 0, segs=8), C(3.0, 1.2, 0, 2.4, 0, segs=8, r2=2.6)]
mesh("Fountain", "FountainRim", fr_, MARBLE, "Marble")
robe = kit.loft("robe", [(3.0, 2.3, 2.1, 0, 0), (5.0, 2.0, 1.8, 0, 0), (8.6, 1.6, 1.3, 0, 0), (10.4, 2.1, 1.3, 0, 0), (11.2, 1.2, 1.0, 0, 0)],
                segs=14, power=2.2)
stt = [robe, S(1.55, 0, 13.0, 0, segs=12, rings=8)]
for k, x in enumerate((-0.9, 0, 0.9)):
    stt.append(kit.cyl("cr", 0.32, 0.03, 1.4 if k == 1 else 1.0, at=rb(x, 15.0 if k == 1 else 14.8, 0), segs=6))
stt += [T([(1.8, 10.4, 0), (3.0, 12.0, -0.4), (3.0, 13.6, -0.6)], [0.5, 0.45, 0.4], segs=7), S(0.5, 3.0, 13.7, -0.6, segs=8, rings=5),
        C(0.2, 12.0, 3.0, 12.4, -0.6, segs=6), B(2.2, 0.35, 0.35, 3.0, 17.6, -0.6)]
for x in (2.1, 3.0, 3.9):
    stt.append(kit.cyl("p", 0.22, 0.02, 1.3, at=rb(x, 18.4, -0.6), segs=5))
stt += [T([(-1.8, 10.4, 0), (-2.8, 9.0, -1.0), (-3.2, 8.6, -2.2)], [0.5, 0.45, 0.4], segs=7), S(0.5, -3.2, 8.6, -2.3, segs=8, rings=5)]
mesh("Fountain", "FountainStatue", stt, BRONZE)
mesh("Fountain", "StatueEyes", [B(0.7, 0.35, 0.2, -0.6, 13.4, -1.45), B(0.7, 0.35, 0.2, 0.6, 13.4, -1.45)], SPARK, "Neon")

# ---------------------------------------------------------------- a tide engine (foot on the engine hall's floor)
mesh("TideEngine", "EngineBase", [C(4.6, 0.6, 0, 0.3, 0, segs=8), C(3.8, 0.5, 0, 0.85, 0, segs=8)], SLATE, "Slate")
ed = [kit.loft("drum", [(1.1, 3.0, 3.0, 0, 0), (1.5, 3.2, 3.2, 0, 0), (1.9, 3.0, 3.0, 0, 0), (7.8, 3.0, 3.0, 0, 0), (8.2, 3.2, 3.2, 0, 0),
                        (8.6, 2.6, 2.6, 0, 0), (8.8, 1.4, 1.4, 0, 0)], segs=16, power=2.0)]
for k in range(4):
    f_ = B(0.4, 5.0, 1.2, 0, 4.8, 0)
    shift(f_, rb(0, 0, -3.4))
    turn(f_, "up", 45 + k * 90)
    ed.append(f_)
    a = math.radians(k * 90)
    ed.append(T([(math.cos(a) * 1.6, 8.8, math.sin(a) * 1.6), (math.cos(a) * 1.9, 10.2, math.sin(a) * 1.9), (0, 11.9, 0)],
                [0.18, 0.18, 0.18], segs=5))
mesh("TideEngine", "EngineDrum", ed, BRONZE)
ec = [S(1.4, 0, 10.0, 0, segs=12, rings=8)]
for k in range(4):
    w_ = B(0.5, 3.6, 0.2, 0, 4.8, 0)
    shift(w_, rb(0, 0, -3.02))
    turn(w_, "up", k * 90)
    ec.append(w_)
mesh("TideEngine", "EngineCore", ec, SPARK, "Neon")

# ---------------------------------------------------------------- the great sea valve (foot: the middle pipe on the
# floor; the wheel at +z, the hall's side)
vp = [C(1.4, 110, 0, 16.6, 0, segs=10, axis="x"), C(0.6, 4.2, 0, 10, 2.0, segs=8, axis="z")]
for i in range(-3, 4):
    x = i * 18
    vp += [C(1.85, 15.4, x, 7.7, 0, segs=10), C(2.3, 0.6, x, 2.0, 0, segs=8), C(2.3, 0.6, x, 13.6, 0, segs=8),
           S(1.9, x, 16.2, 0, segs=8, rings=5)]
mesh("SeaValve", "ValvePipes", vp, BRONZE)
vw = [TOR(6.2, 0.55, 0, 10, 4.0, axis="z", segs=20, csegs=5), C(1.1, 1.0, 0, 10, 4.0, segs=10, axis="z")]
for k in range(6):
    sp_ = B(0.45, 12.0, 0.45, 0, 10, 4.0)
    turn(sp_, "z", k * 30, (0, 10, 4.0))
    vw.append(sp_)
for k in range(6):
    a = k * math.pi / 3 + math.pi / 6
    vw.append(S(0.65, math.cos(a) * 6.3, 10 + math.sin(a) * 6.3, 4.0, segs=6, rings=4))
mesh("SeaValve", "ValveWheel", vw, (214, 52, 64))

# ================================================================ the Pit (the "pit" pocket)
# ---------------------------------------------------------------- the mine lift (foot: the cage's middle on the
# gallery; the gate faces -z, toward the spawn)
lc = [B(22, 0.4, 16, 0, 0.2, 0), B(22, 0.8, 16, 0, 18.6, 0, bev=0.1)]
for (x, z) in ((-10, -7), (10, -7), (-10, 7), (10, 7)):
    lc.append(B(0.9, 18, 0.9, x, 9, z))
for y in (3, 6, 9, 12, 15):
    lc += [B(20, 0.3, 0.3, 0, y, 7), B(0.3, 0.3, 14, -10, y, 0), B(0.3, 0.3, 14, 10, y, 0)]
for k in range(4):  # the scissor gate on the front
    x0 = -10 + k * 5
    lc.append(T([(x0, 0.6, -7), (x0 + 5, 17.4, -7)], 0.14, segs=4))
    lc.append(T([(x0 + 5, 0.6, -7), (x0, 17.4, -7)], 0.14, segs=4))
mesh("MineLift", "LiftCage", lc, STEEL)
hf = [B(1.8, 14, 1.8, 0, 26, 7), B(15, 1.8, 1.8, 0, 32, 7), T([(-9.5, 19, 7), (-0.6, 30.5, 7)], 0.4, segs=6),
      T([(9.5, 19, 7), (0.6, 30.5, 7)], 0.4, segs=6), TOR(3.0, 0.35, 0, 35.6, 7, axis="z", segs=18, csegs=5),
      C(0.6, 2.4, 0, 35.6, 7, segs=8, axis="z"), C(0.08, 16.4, -3.0, 27.4, 7, segs=4)]
for k in range(4):
    s_ = B(0.25, 6.0, 0.25, 0, 35.6, 7)
    turn(s_, "z", k * 45, (0, 35.6, 7))
    hf.append(s_)
mesh("MineLift", "LiftHeadframe", hf, RUST)

# ---------------------------------------------------------------- a mine timber set (foot: between its posts)
mt = [B(2.8, 20, 2.8, -32, 10, 0, bev=0.15), B(2.8, 20, 2.8, 32, 10, 0, bev=0.15), B(70, 2, 2.8, 0, 20.5, 0, bev=0.15)]
for s_ in (-1, 1):
    mt.append(T([(s_ * 31.0, 16.0, 0), (s_ * 27.0, 19.6, 0)], 0.45, segs=5))
mesh("MineTimber", "MineTimbers", mt, (150, 104, 62), "Wood")

# ---------------------------------------------------------------- the mine cart (foot between the rails)
cart = rings_mesh([[(x, y, z) for (x, z) in [(-a, -b), (a, -b), (a, b), (-a, b)]] for (y, a, b) in
                   ((1.2, 3.2, 5.2), (4.3, 3.9, 5.9), (4.6, 4.0, 6.0))])
mesh("MineCart", "CartBody", [cart, B(8.2, 0.4, 0.4, 0, 2.6, -5.6), B(8.2, 0.4, 0.4, 0, 2.6, 5.6)], RUST)
cw = []
for z in (-3.8, 3.8):
    cw.append(C(0.25, 8.4, 0, 1.6, z, segs=6, axis="x"))
    for x in (-4, 4):
        cw.append(C(0.9, 0.5, x, 1.6, z, segs=12, axis="x"))
mesh("MineCart", "CartWheels", cw, (62, 64, 72))
mesh("MineCart", "CartLoad", [lump(1, (1.2, 0.8, 1.1), (x, 4.6, z), segs=8, rings=5, seed=x + z) for (x, z) in
                              ((-1.6, -2.5), (1.2, -1.8), (-0.4, 0.4), (1.8, 1.9), (-1.8, 2.6), (0.4, 3.4), (0.2, -3.8))], GOLD)

# ---------------------------------------------------------------- a cash crate (foot on the gallery)
cr_ = [B(9.6, 5.8, 9.6, 0, 2.9, 0)]
for s_ in (-1, 1):
    for (sx, sy, sz, x, y, z) in ((10, 0.7, 0.7, 0, 0.4, s_ * 4.7), (10, 0.7, 0.7, 0, 5.6, s_ * 4.7), (0.7, 0.7, 10, s_ * 4.7, 0.4, 0),
                                  (0.7, 0.7, 10, s_ * 4.7, 5.6, 0), (0.7, 6, 0.7, s_ * 4.7, 3, 4.7), (0.7, 6, 0.7, s_ * 4.7, 3, -4.7)):
        cr_.append(B(sx, sy, sz, x, y, z, bev=0.06))
mesh("CashCrate", "CrateWood", cr_, (174, 122, 70), "Wood")
bags, ties = [], []
for (x, z, s_) in ((-1.6, -1.2, 1.0), (1.7, 0.6, 0.9), (-0.6, 2.2, 0.8)):
    b_ = kit.loft("bag", [(0, 0.5 * s_, 0.5 * s_, 0, 0), (0.6 * s_, 1.3 * s_, 1.2 * s_, 0, 0), (1.4 * s_, 1.1 * s_, 1.0 * s_, 0, 0),
                          (1.9 * s_, 0.3 * s_, 0.3 * s_, 0, 0), (2.4 * s_, 0.55 * s_, 0.5 * s_, 0, 0)], segs=10, power=2.0)
    bags.append(shift(b_, rb(x, 5.9, z)))
    ties.append(TOR(0.32 * s_, 0.1, x, 5.9 + 1.95 * s_, z, segs=10, csegs=4))
    ties.append(C(0.4, 0.1, x + 1.2, 5.95, z - 0.9, segs=10))
mesh("CashCrate", "CashBags", bags, (112, 176, 84), "Fabric")
mesh("CashCrate", "BagTies", ties, GOLD)

# ---------------------------------------------------------------- the bookies' counter (foot: its middle; the hall
# is at -z)
bw = [B(59.6, 3.6, 5.6, 0, 1.8, 0, bev=0.12), B(60.4, 0.45, 6.4, 0, 3.8, 0, bev=0.08)]
for i in range(10):
    bw.append(B(5.0, 2.2, 0.2, -27 + i * 6, 1.9, -2.85, bev=0.04))
mesh("BookieCounter", "BookieWood", bw, DARKWOOD, "Wood")
bb = [C(0.18, 58, 0, 5.2, 2.4, segs=6, axis="x")]
for x in (-28, -14, 0, 14, 28):
    bb.append(C(0.15, 1.2, x, 4.6, 2.4, segs=5))
bb += [C(0.6, 0.3, -8, 4.2, -1.4, segs=10, r2=0.5), S(0.45, -8, 4.5, -1.4, segs=8, rings=5), C(0.5, 0.15, 10, 4.1, -1.6, segs=8),
       C(0.05, 1.2, 10, 4.7, -1.6, segs=4)]
mesh("BookieCounter", "BookieBrass", bb, BRASS)

# ---------------------------------------------------------------- an odds machine (foot on the gallery; it faces -z)
oc = [B(6, 6.4, 4, 0, 3.6, 0, bev=0.2), C(2.0, 6.0, 0, 6.8, 0, segs=12, axis="x"), B(6.4, 0.6, 4.4, 0, 0.3, 0, bev=0.1),
      B(4.2, 0.8, 1.2, 0, 2.6, -2.4, bev=0.1)]
kit.apply_all(oc[1])
for v in oc[1].data.vertices:
    v.co.y *= 1.0
mesh("OddsMachine", "OddsCabinet", oc, (214, 46, 58))
mesh("OddsMachine", "OddsDial", [B(4.0, 2.8, 0.3, 0, 5.9, -2.05, bev=0.1), B(4.6, 0.6, 0.3, 0, 8.3, -1.6, bev=0.08)], (255, 210, 70), "Neon")
mesh("OddsMachine", "OddsLever", [C(0.5, 0.6, 3.25, 4.2, 0, segs=10, axis="x"), T([(3.5, 4.2, 0), (3.6, 6.4, 0.2)], 0.12, segs=6)],
     (204, 210, 222))
mesh("OddsMachine", "OddsKnob", S(0.45, 3.6, 6.7, 0.2, segs=10, rings=6), RED)

# ---------------------------------------------------------------- the ring's posts and ropes (foot: the ring's middle
# on its stage)
H = 19
rp, pads = [], []
for (sx, sz) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
    rp += [C(0.6, 8.6, sx * H, 4.3, sz * H, segs=10), S(0.6, sx * H, 8.6, sz * H, segs=8, rings=5)]
    for y in (3, 5.5, 8):
        pads.append(B(1.3, 1.0, 1.3, sx * H, y, sz * H, bev=0.2))
mesh("RingRopes", "RingPosts", rp, STEEL)
mesh("RingRopes", "RingPads", pads, WHITE)
ropes = []
for y in (3, 5.5, 8):
    for (a, b) in (((-H, -H), (H, -H)), ((H, -H), (H, H)), ((H, H), (-H, H)), ((-H, H), (-H, -H))):
        mid = ((a[0] + b[0]) / 2, y - 0.3, (a[1] + b[1]) / 2)
        ropes.append(T([(a[0], y, a[1]), mid, (b[0], y, b[1])], 0.2, segs=6))
mesh("RingRopes", "RingRopeLines", ropes, (232, 52, 64), "Neon")

# ---------------------------------------------------------------- a Pit floodlight (foot on the Pit's floor; its lamp
# hangs out at -x, -z, turned to each corner)
mesh("PitFlood", "PitFloodPole", [C(1.1, 0.6, 0, 0.3, 0, segs=10), C(0.7, 29.4, 0, 15.3, 0, segs=10, r2=0.5),
                                  T([(0, 29.0, 0), (-1.5, 31.0, -1.5), (-2.4, 31.2, -2.4)], 0.22, segs=6)], STEEL)
mesh("PitFlood", "PitFloodHousing", [B(5.6, 1.4, 5.6, -3, 30.6, -3, bev=0.2), C(1.0, 0.6, -3, 31.6, -3, segs=8)], CHARCOAL)
mesh("PitFlood", "PitFloodLamp", [B(4.9, 0.25, 4.9, -3, 29.8, -3)], (255, 244, 180), "Neon")

# ---------------------------------------------------------------- the Pitboss's gold throne (foot on its box seat;
# it faces +z, the ring)
tg = [B(8, 2.6, 6, 0, 1.3, 0, bev=0.2), B(8, 6.4, 1.0, 0, 5.4, -2.5, bev=0.2), C(4.0, 1.0, 0, 8.6, -2.5, segs=14, axis="z")]
kit.apply_all(tg[2])
for v in tg[2].data.vertices:  # a flattened arch on the back
    v.co.z = 8.6 + (v.co.z - 8.6) * 0.45
tg[2].data.update()
for x in (-3.6, 3.6):
    tg += [B(1.0, 1.4, 5.0, x, 3.2, 0.3, bev=0.2), S(0.6, x, 3.4, 2.8, segs=8, rings=5)]
for x in (-2.4, 0, 2.4):
    tg.append(S(0.45 if x else 0.6, x, 10.6 if x else 10.9, -2.5, segs=8, rings=5))
mesh("GoldThrone", "ThroneGold", tg, (255, 206, 70))
mesh("GoldThrone", "ThroneVelvet", [B(6.6, 0.8, 4.8, 0, 2.95, 0.3, bev=0.3), B(5.6, 4.4, 0.4, 0, 5.6, -1.9, bev=0.15)], PURPLE, "Fabric")

# ---------------------------------------------------------------- a fan in the crowd (foot on the bench; faces -z,
# cheering; the shirt takes each fan's colour)
mesh("CrowdFan", "FanShirt", [B(1.4, 1.4, 0.9, 0, 2.05, 0, bev=0.15), T([(-0.65, 2.55, 0), (-1.0, 3.3, -0.1), (-1.05, 3.95, 0)], 0.2, segs=5),
                              T([(0.65, 2.55, 0), (1.0, 3.3, -0.1), (1.05, 3.95, 0)], 0.2, segs=5)], (228, 62, 56))
mesh("CrowdFan", "FanLegs", [B(0.6, 1.35, 0.7, -0.35, 0.68, 0, bev=0.1), B(0.6, 1.35, 0.7, 0.35, 0.68, 0, bev=0.1)], NAVY)
mesh("CrowdFan", "FanSkin", [S(0.55, 0, 3.25, 0, segs=10, rings=6), S(0.25, -1.05, 4.1, 0, segs=6, rings=4),
                             S(0.25, 1.05, 4.1, 0, segs=6, rings=4)], SKIN)


# ================================================================ the fit table and the export
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


TRIS = {}
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
        TRIS[name] = t
        total += t
        rgb, mat, alpha = INFO[name]
        extra = (", alpha = %g" % alpha) if alpha else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat,
                       extra, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/setpieces.py: do not edit by hand.",
    "-- The side quests' set pieces in Blender meshes (ReplicatedStorage.Art.SetPieces, Shared.SetPieceKit): look -> mesh ->",
    "-- its size and its centre from the look's foot point, in studs (x, up, z), its colour (a copy's tint may replace it),",
    "-- material, transparency and triangles. %d meshes in %d looks, %d triangles." % (len(INFO), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "SetPieceArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
# formatted as the repo's stylua does, so a re-run writes the committed file byte for byte
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)
print("set pieces: %d looks, %d meshes, %d tris" % (len(LOOKS), len(INFO), total))
for look in sorted(LOOKS):
    print("  %-16s %5d tris  (%s)" % (look, sum(TRIS[n] for n in LOOKS[look]), ", ".join(sorted(LOOKS[look]))))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "SetPieces.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

# ================================================================ previews: each group where the game puts it, its
# looks drawn over the boxes they hide and the boxes it keeps (the pockets' basement ceilings and glass walls left
# out so the camera sees in), plus the Gala as it looks today (the plain parts), for comparison
if "--preview" in sys.argv:
    FAST = "--fast" in sys.argv
    ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    with open(os.path.join(kit.ROOT, "export", "setpieces", "layout.json")) as f:
        LAYOUT = {g["name"]: g for g in json.load(f)["groups"]}
    for look in LOOKS.values():
        for ob in look.values():
            ob.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 8 if FAST else 40
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = (560, 350) if FAST else (760, 475)
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.52, 0.7, 0.95, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.6
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(38), math.radians(12), math.radians(30))
    sc.collection.objects.link(sun)

    def lin(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    MATS = {}
    ROUGH = {"Wood": 0.7, "Fabric": 0.9, "Marble": 0.25, "Glass": 0.05, "Slate": 0.85, "Pavement": 0.9, "Sand": 0.95,
             "DiamondPlate": 0.4, "SmoothPlastic": 0.45}

    def mat(rgb, kind="SmoothPlastic", alpha=0.0):
        key = (tuple(int(c) for c in rgb), kind, round(alpha, 2))
        if key in MATS:
            return MATS[key]
        m = bpy.data.materials.new("m%d" % len(MATS))
        m.use_nodes = True
        p = m.node_tree.nodes["Principled BSDF"]
        col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
        p.inputs["Base Color"].default_value = col
        p.inputs["Roughness"].default_value = ROUGH.get(kind, 0.5)
        if kind == "Neon":
            p.inputs["Emission Color"].default_value = col
            p.inputs["Emission Strength"].default_value = 3.0
        if alpha > 0:
            p.inputs["Alpha"].default_value = max(0.05, 1 - alpha)
        MATS[key] = m
        return m

    SHOWN = []

    def keep(o):
        o.hide_render = False
        SHOWN.append(o)
        return o

    def clear():
        for o in SHOWN:
            bpy.data.objects.remove(o, do_unlink=True)
        SHOWN.clear()

    def place_look(pl):
        M = Matrix.Translation(Vector(rb(*pl["at"]))) @ Matrix.Rotation(math.radians(pl.get("ry") or 0), 4, "Z")
        tint = pl.get("tint") or {}
        for name, ob in LOOKS[pl["look"]].items():
            rgb, kind, alpha = INFO[name]
            cp = keep(copy(ob))
            cp.matrix_world = M
            cp.data.materials.clear()
            cp.data.materials.append(mat(tint.get(name, rgb), kind, alpha))

    def sign_text(text, at, size, color):
        for back in (False, True):
            cu = bpy.data.curves.new("sign", "FONT")
            cu.body = text
            cu.align_x = "CENTER"
            cu.align_y = "CENTER"
            cu.size = min(size[1] * 0.6, size[0] * 0.9 / (0.66 * len(text)))
            ob = keep(bpy.data.objects.new("sign", cu))
            sc.collection.objects.link(ob)
            ob.rotation_euler = (math.radians(90), 0, math.radians(180) if back else 0)
            ob.location = Vector(rb(at[0], at[1], at[2] + (-1 if back else 1) * (size[2] / 2 + 0.03)))
            ob.data.materials.append(mat(color, "SmoothPlastic"))

    def draw_box(b):
        sx, sy, sz = b["size"]
        x, y, z = b["at"]
        if b.get("shape") == "cylinder":
            ob = kit.cyl("bx", min(sx, sz) / 2, min(sx, sz) / 2, sy, at=rb(x, y, z), segs=24)
        elif b.get("shape") == "ball":
            ob = kit.sphere("bx", r=max(sx, sy, sz) / 2, at=rb(x, y, z), segs=16, rings=10)
        else:
            ob = kit.box("bx", sx, sz, sy, at=(0, 0, 0))
            if b.get("tilt"):
                turn(ob, "x", b["tilt"])
            shift(ob, rb(x, y, z))
        keep(ob)
        ob.data.materials.append(mat(b["color"], b.get("mat") or "SmoothPlastic", b.get("alpha") or 0))
        if b.get("sign"):
            sign_text(b["sign"], b["at"], b["size"], (150, 30, 50))

    def ground(size, rgb=(150, 150, 146), y=0.0):
        g = keep(kit.box("ground", size, size, 0.4, at=(0, 0, y - 0.2)))
        g.data.materials.append(mat(rgb, "Pavement"))

    def hero(x, y, z, yaw=0):
        """A blocky 5-stud hero for scale."""
        for (s_, c, rgb) in (((2, 2, 1), (0, 3.0, 0), (60, 120, 220)), ((1.2, 1.2, 1.2), (0, 4.6, 0), SKIN),
                             ((0.95, 2, 1), (-0.5, 1.0, 0), (40, 50, 90)), ((0.95, 2, 1), (0.5, 1.0, 0), (40, 50, 90)),
                             ((1, 2, 1), (-1.5, 3.0, 0), SKIN), ((1, 2, 1), (1.5, 3.0, 0), SKIN)):
            o = kit.box("hero", s_[0], s_[2], s_[1], at=rb(*c))
            move(o, x, y, z, yaw)
            keep(o).data.materials.append(mat(rgb))

    def gallery(gname):
        """Every look of a group once, side by side in rows on a floor (the first copy's tint), true scale; returns
        the camera (from, to, lens) in Roblox studs that frames them."""
        order, tints = [], {}
        for pl in LAYOUT[gname]["art"]:
            if pl["look"] not in tints:
                order.append(pl["look"])
                tints[pl["look"]] = pl.get("tint") or {}
        box = {}
        for look in order:
            vs = [ob.matrix_world @ v.co for ob in LOOKS[look].values() for v in ob.data.vertices]
            lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
            hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
            # a long thin run (the winders' pull rods, the tap's pipe) may reach past its neighbours: pack by the body
            lo.x, lo.y, hi.x, hi.y = max(lo.x, -30), max(lo.y, -20), min(hi.x, 30), min(hi.y, 20)
            box[look] = (lo, hi)
        order.sort(key=lambda k: -(box[k][1].x - box[k][0].x))
        wmax = max(60.0, box[order[0]][1].x - box[order[0]][0].x)
        rows, row, w = [], [], 0.0
        for look in order:
            lw = box[look][1].x - box[look][0].x
            if row and w + lw > wmax:
                rows.append(row)
                row, w = [], 0.0
            row.append(look)
            w += lw + 5
        rows.append(row)
        z, top = 0.0, 0.0
        for r in rows:  # the widest row at the back (Roblox -z), nearer rows smaller
            depth = max(box[k][1].y - box[k][0].y for k in r)
            x = -sum(box[k][1].x - box[k][0].x + 5 for k in r) / 2
            for look in r:
                lo, hi = box[look]
                cx = x + (hi.x - lo.x) / 2
                # Blender bounds: x across, y front (Roblox -z), z up
                at = (cx - (lo.x + hi.x) / 2, -lo.z, z + (lo.y + hi.y) / 2)
                place_look({"look": look, "at": [at[0], at[1], at[2]], "ry": 0, "tint": tints[look]})
                top = max(top, hi.z - lo.z)
                x += hi.x - lo.x + 5
            z += depth + 6
        ground(max(wmax, z) * 2.2, (120, 124, 132))
        mid = z / 2 - 3
        d = max(wmax, z * 1.25) * 0.78 + top * 0.4
        return ((d * 0.22, top * 0.3 + d * 0.5, mid + d * 0.84), (0, top * 0.3, mid), 30)

    # name: (group, camera from, to (Roblox studs from the group's origin; "gallery": its looks in rows), lens,
    # the meshes drawn, a hero for scale)
    SHOTS = [
        ("gala", "gala", (34, 13, 58), (-2, 8, -12), 26, True, (6, 0, 20)),
        ("gala_parts", "gala", (34, 13, 58), (-2, 8, -12), 26, False, (6, 0, 20)),
        ("meet", "meet", (-50, 22, 54), (2, 6, -4), 26, True, (-6, 0, 12)),
        ("farm", "farm", (17, 8, -15), (0, 3, 0.5), 34, True, (6.5, 0, 3)),
        ("toyshop", "toyshop", (-150, 70, -40), (40, 15, 90), 18, True, (-100, 20, 40)),
        ("toyshop_gallery", "toyshop", "gallery", None, None, True, None),
        ("seacave", "seacave", (0, 46, -8), (0, 18, 64), 18, True, (6, 20, 56)),
        ("seacave_gallery", "seacave", "gallery", None, None, True, None),
        ("velmara", "velmara", (0, 50, -4), (0, 22, 100), 17, True, (8, 20, 46)),
        ("velmara_gallery", "velmara", "gallery", None, None, True, None),
        ("pit_below", "pit", (0, 52, -60), (0, 4, -150), 16, True, (8, 2, -126)),
        ("pit_gallery", "pit", "gallery", None, None, True, None),
    ]
    CAPTIONS = {
        "gala": "The Museum Gala (OpenNorth square)", "gala_parts": "The Museum Gala today (the plain parts fallback)",
        "meet": "The Racers' Meet (OpenWest square)", "farm": "The farm folk's truck (The Harvest King)",
        "toyshop": "Tick-Tock Toys: the shop floor", "toyshop_below": "Tick-Tock Toys: the workshop, Tantrum Tap",
        "toyshop_gallery": "Tick-Tock Toys: every piece", "seacave": "Brine's sea cave: the wharf and tide pools",
        "seacave_below": "Brine's sea cave: the Drowned Gull's grotto", "seacave_gallery": "Brine's sea cave: every piece",
        "velmara": "Velmara: the gate, market and fountain", "velmara_below": "Velmara: tide engines, the sea valve",
        "velmara_gallery": "Velmara: every piece", "pit": "The Pit: lift, mine tunnel, betting hall",
        "pit_below": "The Pit: the ring, the crowd, the throne", "pit_gallery": "The Pit: every piece",
    }
    made = []
    for (shot, gname, frm, to, lens, dressed, hero_at) in SHOTS:
        if ONLY and ONLY not in shot:
            continue
        g = LAYOUT[gname]
        if frm == "gallery":
            frm, to, lens = gallery(gname)
        else:
            if gname in ("gala", "meet"):
                ground(170)
            elif gname == "farm":
                ground(80, (52, 54, 60))
            for b in g["boxes"]:
                if b.get("tag") in ("ceiling", "pocketWall"):
                    continue
                if dressed and b.get("art"):
                    continue
                draw_box(b)
            if dressed:
                for pl in g["art"]:
                    place_look(pl)
            hero(*hero_at, yaw=200)
        cam = keep(kit.camera(rb(*frm), rb(*to), lens=lens))
        cam.data.clip_end = 3000
        out = os.path.join(kit.ROOT, "preview", "setpieces_%s.png" % shot)
        kit.render(out)
        made.append((shot, out))
        clear()
    if not ONLY:
        # one sheet: every shot with its caption, 3 across (python3 with PIL; Blender's Python has none)
        args = json.dumps([[CAPTIONS[s_], p_] for (s_, p_) in made])
        sheet = os.path.join(kit.ROOT, "preview", "setpieces.png")
        code = (
            "import json,sys\n"
            "from PIL import Image, ImageDraw, ImageFont\n"
            "shots=json.loads(sys.argv[1]); out=sys.argv[2]\n"
            "ims=[Image.open(p).convert('RGB') for _,p in shots]\n"
            "w,h=ims[0].size; cols=4; rows=(len(ims)+cols-1)//cols; bar=44\n"
            "sheet=Image.new('RGB',(cols*w,rows*(h+bar)),(24,26,32)); d=ImageDraw.Draw(sheet)\n"
            "try:\n f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',22)\n"
            "except Exception:\n f=ImageFont.load_default()\n"
            "for i,(im,(cap,_)) in enumerate(zip(ims,shots)):\n"
            " x=(i%cols)*w; y=(i//cols)*(h+bar); sheet.paste(im,(x,y+bar)); d.text((x+14,y+8),cap,fill=(255,236,150),font=f)\n"
            "sheet.save(out)\n"
        )
        subprocess.run(["python3", "-c", code, args, sheet], check=True)
        for (_, p_) in made:
            os.remove(p_)
        print("preview:", sheet)
