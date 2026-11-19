# activity.py: the open-world activities' props as Blender meshes (2026-11-19, the props gap): what the 24 incidents,
# 12 events and 12 contract types put in the street. Until ReplicatedStorage.Art.Activity holds a look's meshes the
# game draws each prop from today's plain parts (SiteKit, IncidentService, EventService, ContractService); once
# imported, the device (Fx.ActivityProps) draws the look over them and hides them on that device only. The server's
# parts stay exactly as they are: they never collide (SiteKit.part), and every combat target, ring radius, drop circle,
# pickup range and prompt is a number in the services, untouched. Same kit style as the street props and the set
# pieces: chunky cartoon silhouettes, bright comic colours, one baked texture set a look (art/blender/vkit.py: region
# colours with patterns such as hazard stripes, plates and planks, baked occlusion, normal, roughness and metalness),
# plus untextured Neon glows (tinted per copy from the part they stand in for: a generator's core, a ring's colour) and
# see-through glass or water.
# Looks (ActivityArt key = Shared.ActivityKit kind's look; every look is built about its prop's own foot point, in the
# same studs as the parts the service builds for it, so it sits exactly over them):
#   incidents: ActRelay (the relay dish), ActVault (the bank vault wall), ActShardCrate, ActValve (a burst main and its
#     valve), ActScaffold, ActCraneLoad, ActCrateStack, ActBalcony (the tower fire ledge), ActBillboard (the falling
#     sign; foot at the board's middle); the tram reuses vehicles.py's Tram and the towed car its CarSedan
#   events: ActTrain (the runaway train), ActAirship, ActFloat (the parade float), ActClamp (the power clamps),
#     ActDataTruck (the Crane data truck), ActGate (the stadium gates), ActGenerator (also the contract generator),
#     ActCityVault, ActBarricade (the bridge barricade), ActFog (a Harbour fog bank, drawn by Fx.ActivityFx)
#   contracts: ActCharge (the defusal charge), ActPylon (the demolition pylons), ActOutpost (the outpost mast),
#     ActParcel and ActDropPad (the rooftop courier's parcel and drops); the escort truck reuses vehicles.py's DockTruck
#   everywhere: ActRescuePad (a drop circle's post, sign and rim), ActRing (a hold ring's rim, scaled to its radius),
#     ActShard (a shard pickup's crystal cluster)
# Original designs: no real brands, logos or lettering (the Crane C on the data truck is the game's own lore mark).
# Output: art/export/Activity.fbx (textures embedded), art/export/activity/<Look>_{Color,Normal,Roughness,Metalness}.png,
# src/config/ActivityArt.luau; with --preview, art/preview/activity_<Look>.png and the sheet art/preview/activity.png.
# --only <Look,...> builds and bakes only those (a check: no export, no fit table), --fast bakes and renders at low
# quality.
# Run: $HOME/tools/bpyenv/bin/python art/blender/activity.py [--preview] [--only <Look>] [--fast]
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402

kit.reset()

import vkit  # noqa: E402
from vkit import R, P, Look, LOOKS, rbox  # noqa: E402
from studs import B, C, S, T, TOR, turn, shift, copy, star, loft_z, prism, rings_mesh, rb  # noqa: E402,F401

ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
FAST = "--fast" in sys.argv
vkit.OUT = os.path.join(kit.ROOT, "export", "activity")
BIG = {}  # look -> texture size (default 512; the big ones 1024)


def want(name):
    return ONLY is None or name in ONLY


# ================================================================ patterns of our own (added to vkit's)
_base_pattern = vkit._pattern


def _pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise):
    kind = pat[0] if isinstance(pat, tuple) else pat
    p = Pp[m]
    n = Nn[m]
    c = col[m]
    h = height[m]
    if kind == "hazard":  # diagonal stripes: ("hazard", rgb2, width, axis) across the face's long way
        rgb2 = np.array(pat[1], dtype=np.float32) / 255
        w = pat[2]
        u = np.where(np.abs(n[:, 0]) > 0.6, p[:, 2], p[:, 0]) if pat[3] == "auto" else p[:, 0 if pat[3] == "x" else 2]
        s = (((u + p[:, 1]) / w) % 2) < 1
        c[s] = rgb2
        edge = np.abs(((u + p[:, 1]) / w) % 1 - 0.5) > 0.46
        c[edge] *= 0.55
        h[edge] -= 0.3
    elif kind == "plates":  # riveted steel plates: seams every `step` studs, a rivet at each corner
        step = pat[1]
        a = np.where(np.abs(n[:, 0]) > 0.6, p[:, 2], p[:, 0])
        b = np.where(np.abs(n[:, 1]) > 0.6, p[:, 2], p[:, 1])
        fa, fb = (a / step) % 1, (b / step) % 1
        seam = (np.abs(fa - 0.5) > 0.47) | (np.abs(fb - 0.5) > 0.47)
        c[seam] *= 0.5
        h[seam] -= 0.6
        rv = ((np.abs(fa - 0.5) > 0.36) & (np.abs(fa - 0.5) < 0.44)) & ((np.abs(fb - 0.5) > 0.36) & (np.abs(fb - 0.5) < 0.44))
        c[rv] = c[rv] * 0.5 + 0.45
        h[rv] += 0.5
        c *= (0.94 + 0.06 * noise[m])[:, None]
    elif kind == "sunburst":  # a poster: rays round its middle in two colours, a star in the third, ink edges
        rgb2 = np.array(pat[1], dtype=np.float32) / 255
        rgb3 = np.array(pat[2], dtype=np.float32) / 255
        x, y = p[:, 0], p[:, 1]
        ang = np.arctan2(y, x)
        ray = (np.floor((ang + math.pi) / (math.pi / 8)) % 2) == 0
        c[ray] = rgb2
        r = np.sqrt(x * x + y * y)
        sa = (ang + math.pi / 2) % (2 * math.pi / 5) - math.pi / 5
        st = 1.9 * (0.55 + 0.45 * np.abs(np.cos(sa * 2.5)) ** 6)
        inner = r < st
        c[inner] = rgb3
        ink = np.abs(r - st) < 0.12
        c[ink] = (0.06, 0.06, 0.08)
        h[ink] -= 0.3
    elif kind == "tape":  # cardboard with a tape band across the top and down the sides at x = 0
        c *= (0.92 + 0.08 * noise[m])[:, None]
        band = np.abs(p[:, 0]) < 0.32
        c[band] = (0.86, 0.80, 0.62)
        h[band] += 0.3
    elif kind == "chevron":  # a ring rim: ("chevron", rgb2, n) alternating blocks round the up axis
        rgb2 = np.array(pat[1], dtype=np.float32) / 255
        ang = np.arctan2(p[:, 2], p[:, 0])
        s = (np.floor((ang + math.pi) / (2 * math.pi / pat[2])) % 2) == 0
        c[s] = rgb2
    elif kind == "dial":  # a vault door: rings and a sunray grain
        r = np.sqrt(p[:, 0] ** 2 + (p[:, 1] - pat[1]) ** 2)
        ring = np.abs((r / pat[2]) % 1 - 0.5) > 0.44
        c[ring] *= 0.6
        h[ring] -= 0.4
        ang = np.arctan2(p[:, 1] - pat[1], p[:, 0])
        c *= (0.93 + 0.07 * np.sin(ang * 60))[:, None]
    else:
        return _base_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise)
    col[m] = c
    height[m] = h


vkit._pattern = _pattern

# ================================================================ regions (one material each, for the bake)
STEEL = R("Steel", (150, 158, 170), 0.4, 0.8)
DARKSTEEL = R("DarkSteel", (70, 76, 90), 0.5, 0.7)
PLATE = R("Plate", (128, 136, 150), 0.45, 0.7, pat=("plates", 2.0))
DARKPLATE = R("DarkPlate", (64, 70, 86), 0.5, 0.6, pat=("plates", 2.5))
NAVYPLATE = R("NavyPlate", (40, 54, 110), 0.45, 0.5, pat=("plates", 2.5))
CHROME = R("Chrome", (226, 230, 236), 0.12, 1.0)
WHITE = R("White", (244, 244, 240), 0.5)
CREAM = R("Cream", (250, 240, 214), 0.55)
BLACK = R("Black", (36, 37, 42), 0.6)
RUBBER = R("Rubber", (34, 34, 38), 0.85)
RED = R("Red", (226, 52, 48), 0.45)
REDMETAL = R("RedMetal", (214, 50, 44), 0.35, 0.5)
YELLOW = R("Yellow", (252, 206, 42), 0.45)
ORANGE = R("Orange", (248, 140, 30), 0.45)
BLUE = R("Blue", (52, 116, 220), 0.45)
NAVY = R("Navy", (36, 48, 104), 0.45)
GREEN = R("Green", (80, 184, 96), 0.5)
PURPLE = R("Purple", (96, 70, 150), 0.45, 0.4, pat=("plates", 1.5))
PINK = R("Pink", (255, 96, 168), 0.4)
GOLD = R("Gold", (240, 190, 60), 0.25, 1.0)
BRASS = R("Brass", (226, 168, 58), 0.3, 1.0)
COPPER = R("Copper", (214, 120, 70), 0.3, 1.0)
WOOD = R("Wood", (174, 118, 70), 0.75, pat="planks")
DARKWOOD = R("DarkWood", (124, 82, 50), 0.8, pat="planks")
CONCRETE = R("Concrete", (178, 176, 170), 0.9)
ROCK = R("Rock", (128, 120, 112), 0.9)
CARDBOARD = R("Cardboard", (196, 150, 96), 0.9, pat="tape")
HAZARD = R("Hazard", (252, 206, 42), 0.5, pat=("hazard", (36, 37, 42), 0.9, "auto"))
HAZARDX = R("HazardX", (252, 206, 42), 0.5, pat=("hazard", (36, 37, 42), 0.7, "x"))
HAZARDRED = R("HazardRed", (244, 244, 240), 0.5, pat=("hazard", (226, 52, 48), 0.8, "auto"))
GRILLE = R("Grille", (50, 54, 62), 0.5, 0.4, pat="grille")
SLATS = R("Slats", (90, 96, 110), 0.5, 0.5, pat=("slats", 3.0))
CHECKS = R("Checks", (244, 244, 240), 0.5, pat="checks")
TYRE = R("Tyre", (44, 44, 48), 0.88)
HUB = R("Hub", (150, 156, 166), 0.3, 1.0)
CANVAS = R("Canvas", (72, 138, 84), 0.85, pat=("stripes", (92, 160, 100), 0.8))
SKIRT = R("Skirt", (255, 96, 168), 0.8, pat=("stripes", (252, 206, 42), 2.0))
ENVELOPE = R("Envelope", (92, 98, 112), 0.55, 0.2, pat=("plates", 6.0))
POSTER = R("Poster", (64, 150, 230), 0.6, pat=("sunburst", (110, 200, 255), (252, 206, 42)))

NEON = "Neon"
GLASS = ((150, 210, 240), "Glass", 0.45)


def glow(lk, parts, rgb, role="Glow"):
    lk.add(role, parts, rgb, NEON)


def glass(lk, parts, rgb=GLASS[0], alpha=GLASS[2], role="Glass"):
    lk.add(role, parts, rgb, "Glass", alpha)


def ring_of(n, r, fn):
    out = []
    for k in range(n):
        a = k * 2 * math.pi / n
        out += fn(math.cos(a) * r, math.sin(a) * r, a)
    return out


def tilt(parts, axis, deg, pivot):
    for p in parts:
        turn(p, axis, deg, pivot)
    return parts


def bolts(n, r, x, y, z, rr=0.18, axis="z", reg=None):
    out = []
    for k in range(n):
        a = k * 2 * math.pi / n
        if axis == "z":
            out.append(P(C(rr, 0.25, x + math.cos(a) * r, y + math.sin(a) * r, z, segs=6, axis="z"), reg or CHROME))
        else:
            out.append(P(C(rr, 0.25, x + math.cos(a) * r, y, z + math.sin(a) * r, segs=6), reg or CHROME))
    return out


def wheel(x, y, z, r, w, segs=14):
    """A chunky tyre along x with a hub cap."""
    return [P(C(r, w, x, y, z, segs=segs, axis="x"), TYRE), P(C(r * 0.55, w + 0.12, x, y, z, segs=segs, axis="x"), HUB),
            P(C(r * 0.2, w + 0.3, x, y, z, segs=8, axis="x"), CHROME)]


# ================================================================ incidents
# ---------------------------------------------------------------- the relay dish (relayModel: base 4 x 2 x 4, mast to
# 19, the dish at 17 facing up and +x, a blue light at 19.5)
if want("ActRelay"):
    lk = Look("ActRelay", "ActRelay", False)
    det = [P(rbox(4, 1.8, 4, 0, 0.9, 0, bev=0.25), DARKPLATE), P(rbox(4.3, 0.3, 4.3, 0, 0.15, 0, bev=0.08), BLACK),
           P(rbox(2.2, 1.1, 0.3, 0, 1.0, -2.05, bev=0.06), GRILLE)]
    det += bolts(8, 1.6, 0, 1.85, 0, axis="up")
    det += [P(C(0.5, 15.5, 0, 9.5, 0, segs=10, r2=0.34), STEEL)]
    for y in (4.5, 9.0, 13.5):
        det.append(P(TOR(0.48, 0.12, 0, y, 0, segs=12, csegs=4), CHROME))
    for k in range(3):  # guy struts to the base's corners
        a = k * 2 * math.pi / 3 + 0.5
        det.append(P(T([(0, 8.0, 0), (math.cos(a) * 1.8, 1.9, math.sin(a) * 1.8)], 0.09, segs=5), DARKSTEEL))
    dish = [P(C(0.35, 0.9, 0, 17.0, 0, segs=18, r2=3.5), WHITE), P(TOR(3.45, 0.2, 0, 17.45, 0, segs=24, csegs=5), CHROME),
            P(C(0.55, 1.0, 0, 16.4, 0, segs=10), DARKSTEEL)]
    for k in range(3):  # the feed's struts and its horn
        a = k * 2 * math.pi / 3
        dish.append(P(T([(math.cos(a) * 3.0, 17.4, math.sin(a) * 3.0), (0, 19.3, 0)], 0.07, segs=4), STEEL))
    dish.append(P(C(0.32, 0.7, 0, 19.45, 0, segs=10), DARKSTEEL))
    tilt(dish, "z", -30, (0, 16.6, 0))
    lk.add("Detail", det + dish)
    glow(lk, [S(0.7, 0, 19.5, 0, segs=12, rings=8)], (80, 160, 255))
    glow(lk, [S(0.22, 1.6, 1.9, -1.6, segs=8, rings=5), S(0.22, -1.6, 1.9, -1.6, segs=8, rings=5)], (255, 70, 60), "Lamp")


# ---------------------------------------------------------------- the bank vault wall (propAt / ContractService:
# a 14 x 12 x 4 wall at z 6..10 and its round door, 9 across, at z 5..6.2, facing -z)
def vault(name, w, h, d, zc, dr, dz, dt):
    lk = Look(name, name, False)
    y = h / 2
    det = [P(rbox(w, h, d, 0, y, zc, bev=0.3), PLATE)]
    for x in (-w / 2 + 0.9, w / 2 - 0.9):  # pilasters
        det.append(P(rbox(1.6, h - 0.4, 0.8, x, y, zc - d / 2 - 0.2, bev=0.15), DARKPLATE))
    det.append(P(rbox(w + 0.4, 0.8, d + 0.4, 0, h - 0.3, zc, bev=0.12), DARKSTEEL))
    det.append(P(rbox(w + 0.4, 0.6, d + 0.4, 0, 0.3, zc, bev=0.1), DARKSTEEL))
    det.append(P(TOR(dr + 0.25, 0.42, 0, y, dz + 0.1, axis="z", segs=32, csegs=6), CHROME))
    det.append(P(C(dr, dt * 0.85, 0, y, dz, segs=32, axis="z"), R("Door" + name, (214, 172, 80), 0.3, 1.0, pat=("dial", y, dr / 4))))
    det += bolts(16, dr - 0.5, 0, y, dz - dt * 0.45, rr=0.22)
    wz = dz - dt / 2 - 0.35
    det.append(P(TOR(dr * 0.42, 0.16, 0, y, wz, axis="z", segs=20, csegs=5), CHROME))
    for k in range(3):  # the spoked wheel
        a = k * math.pi / 3
        det.append(P(T([(math.cos(a) * dr * 0.5, y + math.sin(a) * dr * 0.5, wz), (-math.cos(a) * dr * 0.5, y - math.sin(a) * dr * 0.5, wz)],
                       0.12, segs=5), CHROME))
    det.append(P(C(dr * 0.12, 0.6, 0, y, wz, segs=10, axis="z"), BRASS))
    for yy in (y - dr * 0.5, y + dr * 0.5):  # hinges on the right
        det.append(P(C(0.35, 1.4, dr + 0.2, yy, dz + 0.1, segs=8), DARKSTEEL))
    lk.add("Detail", det)
    glow(lk, [rbox(1.1, 0.5, 0.3, 0, h - 1.4, zc - d / 2 - 0.05, bev=0.1)], (90, 255, 140), "Lamp")
    return lk


if want("ActVault"):
    vault("ActVault", 14, 12, 4, 8, 4.5, 5.6, 1.2)
if want("ActCityVault"):
    vault("ActCityVault", 22, 16, 5, 12, 6.0, 9.0, 1.4)

# ---------------------------------------------------------------- the shard crate (6 x 5 x 6, a band of light at 4)
if want("ActShardCrate"):
    lk = Look("ActShardCrate", "ActShardCrate", False)
    det = [P(rbox(5.6, 3.4, 5.6, 0, 1.75, 0, bev=0.3), PURPLE), P(rbox(6.0, 0.6, 6.0, 0, 0.3, 0, bev=0.12), BLACK),
           P(rbox(6.0, 0.5, 6.0, 0, 4.75, 0, bev=0.12), BLACK)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            det.append(P(rbox(0.8, 5.0, 0.8, sx * 2.7, 2.5, sz * 2.7, bev=0.15), HAZARD))
    for s_ in (-1, 1):  # handles
        det.append(P(T([(s_ * 3.0, 2.0, -1.0), (s_ * 3.3, 2.0, -1.0), (s_ * 3.3, 2.0, 1.0), (s_ * 3.0, 2.0, 1.0)], 0.12, segs=5), CHROME))
    lk.add("Detail", det)
    cr = [rbox(6.15, 0.8, 6.15, 0, 4.0, 0, bev=0.1)]
    for (x, z, hgt, a) in ((-1.2, -0.8, 2.2, 14), (0.9, 0.6, 2.8, -10), (0.2, -1.6, 1.6, 22)):
        k = C(0.42, hgt, x, 5.0 + hgt / 2, z, segs=6)
        cap = C(0.42, 0.7, x, 5.0 + hgt + 0.35, z, segs=6, r2=0.02)
        tilt([k, cap], "z", a, (x, 5.0, z))
        cr += [k, cap]
    glow(lk, cr, (150, 120, 255))


# ---------------------------------------------------------------- the burst water main (valveModel: a 3 x 3 x 3 base,
# the valve wheel flat on top at 4, the spray column at x 1.5 up to 17)
if want("ActValve"):
    lk = Look("ActValve", "ActValve", False)
    det = [P(rbox(3.0, 0.6, 3.0, 0, 0.3, 0, bev=0.12), CONCRETE), P(C(0.95, 2.6, 0, 1.6, 0, segs=14), BLUE),
           P(C(1.25, 0.35, 0, 0.75, 0, segs=14), DARKSTEEL), P(C(1.25, 0.35, 0, 2.75, 0, segs=14), DARKSTEEL),
           P(C(0.25, 1.0, 0, 3.4, 0, segs=8), STEEL)]
    det += bolts(8, 1.05, 0, 2.95, 0, rr=0.12, axis="up")
    det += [P(T([(0.6, 1.6, 0), (1.2, 1.6, 0), (1.5, 1.9, 0), (1.5, 2.6, 0)], 0.5, segs=10), BLUE)]
    for k in range(6):  # the burst pipe's torn lip
        a = k * math.pi / 3
        det.append(P(C(0.16, 0.7, 1.5 + math.cos(a) * 0.45, 2.9, math.sin(a) * 0.45, segs=4, r2=0.02), BLUE))
    det.append(P(TOR(1.7, 0.2, 0, 4.0, 0, segs=24, csegs=6), REDMETAL))
    for k in range(4):
        a = k * math.pi / 4
        det.append(P(T([(math.cos(a) * 1.7, 4.0, math.sin(a) * 1.7), (-math.cos(a) * 1.7, 4.0, -math.sin(a) * 1.7)], 0.13, segs=5), REDMETAL))
    det.append(P(C(0.4, 0.5, 0, 4.0, 0, segs=10), CHROME))
    lk.add("Detail", det)
    water = [C(0.45, 14.0, 1.5, 9.4, 0, segs=12, r2=1.15)]
    for (dx, dy, dz, r) in ((0.0, 16.6, 0.0, 1.2), (0.7, 16.0, 0.6, 0.7), (-0.6, 15.6, -0.5, 0.75), (0.5, 15.2, -0.8, 0.5)):
        water.append(S(r, 1.5 + dx, dy, dz, segs=10, rings=6))
    glass(lk, water, (120, 190, 255), 0.45, "Water")


# ---------------------------------------------------------------- the leaning scaffold (holdProp Scaffold: 4 poles at
# x, z = +-5, 22 tall, leaning 4 degrees; decks at 7, 14, 21 tipping 6, 12 and 18 degrees)
if want("ActScaffold"):
    lk = Look("ActScaffold", "ActScaffold", False)
    det = []
    for (ox, oz) in ((-5, -5), (5, -5), (-5, 5), (5, 5)):
        pole = [P(C(0.3, 22, ox, 11, oz, segs=8), YELLOW), P(rbox(1.2, 0.3, 1.2, ox, 0.15, oz, bev=0.05), DARKSTEEL)]
        for y in (3.5, 10.5, 17.5):
            pole.append(P(C(0.42, 0.5, ox, y, oz, segs=8), DARKSTEEL))
        tilt(pole, "x", ox * 0.8, (ox, 11, oz))
        det += pole
    for hh in (1, 2, 3):
        y = hh * 7
        deck = [P(rbox(11, 0.5, 11, 0, y, 0, bev=0.06), WOOD)]
        for sz in (-5.4, 5.4):
            deck.append(P(rbox(11, 0.7, 0.2, 0, y + 0.55, sz, bev=0.04), HAZARDX))
        for sx in (-5.6, 5.6):
            deck.append(P(T([(sx, y + 0.3, -5.2), (sx, y + 1.4, -5.2), (sx, y + 1.4, 5.2), (sx, y + 0.3, 5.2)], 0.12, segs=5), YELLOW))
        tilt(deck, "x", 6 * hh, (0, y, 0))
        det += deck
    for sx in (-5, 5):  # cross braces on the sides
        for (y0, y1) in ((0.5, 7), (7, 14), (14, 21)):
            det.append(P(T([(sx * 1.02, y0, -5 + y0 * 0.07), (sx * 1.02, y1, 5 + y1 * 0.07)], 0.1, segs=5), YELLOW))
    lk.add("Detail", det)
    glow(lk, [S(0.3, -5.2, 22.2, -5.2, segs=8, rings=5), S(0.3, 5.2, 22.2, 5.8, segs=8, rings=5)], (255, 150, 40), "Lamp")


# ---------------------------------------------------------------- the crane's swinging load (holdProp Load: the cable
# from 19 to 49, a 7 x 5 x 7 load at 16 tipped 12 degrees about x and 8 about z)
if want("ActCraneLoad"):
    lk = Look("ActCraneLoad", "ActCraneLoad", False)
    load = [P(rbox(7, 1.0, 7, 0, 14.0, 0, bev=0.1), DARKWOOD)]
    for (x, z) in ((-2.2, -1.8), (0.0, -1.8), (2.2, -1.8), (-2.2, 0.6), (0.0, 0.6), (2.2, 0.6), (-1.1, 2.4), (1.1, 2.4)):
        load.append(P(rbox(2.0, 2.2, 2.0, x, 15.6, z, bev=0.15), RED if (x + z) % 2 else ORANGE))
    load.append(P(rbox(6.2, 1.4, 1.8, 0, 17.4, 0, bev=0.2), BLUE))
    for (x, z) in ((-3.2, -3.2), (3.2, -3.2), (-3.2, 3.2), (3.2, 3.2)):
        load.append(P(T([(x, 14.5, z), (0, 20.2, 0)], 0.08, segs=4), CHROME))
    load += [P(rbox(1.6, 1.4, 1.0, 0, 20.6, 0, bev=0.2), YELLOW), P(TOR(0.5, 0.15, 0, 19.9, 0, axis="z", segs=12, csegs=4), DARKSTEEL)]
    tilt(load, "z", 8, (0, 16, 0))
    tilt(load, "x", 12, (0, 16, 0))
    cable = [P(C(0.14, 28.0, 0, 35.0, 0, segs=6), BLACK), P(rbox(1.4, 2.0, 1.4, 0, 48.0, 0, bev=0.2), YELLOW),
             P(C(0.5, 1.2, 0, 47.9, 0, segs=10, axis="x"), DARKSTEEL)]
    lk.add("Detail", load + cable)
    glow(lk, [S(0.25, 0, 49.1, 0, segs=8, rings=5)], (255, 70, 60), "Lamp")


# ---------------------------------------------------------------- the crate stack (holdProp Crates: four 4-stud crates
# at x -6, -1.8, 2.4, 6.6, z 6)
if want("ActCrateStack"):
    lk = Look("ActCrateStack", "ActCrateStack", False)
    det = []
    for i in range(4):
        x = -6 + i * 4.2
        det.append(P(rbox(3.8, 3.8, 3.8, x, 1.9, 6, bev=0.12), WOOD if i % 2 == 0 else DARKWOOD))
        for (sy, sz) in ((0.25, 4.05), (3.55, 4.05), (0.25, 7.95), (3.55, 7.95)):
            det.append(P(rbox(4.0, 0.45, 0.25, x, sy, sz, bev=0.04), DARKWOOD))
        for sx in (-1.9, 1.9):
            det.append(P(rbox(0.3, 3.9, 0.3, x + sx, 1.95, 4.05, bev=0.04), DARKWOOD))
        det.append(P(T([(x - 1.5, 0.5, 4.02), (x + 1.5, 3.3, 4.02)], 0.14, segs=4), DARKWOOD))
        det.append(P(star(0.7, 0.3, 0.06, x, 2.0, 3.98), BLACK if i != 1 else RED))
    det.append(P(rbox(7.6, 0.2, 3.9, -3.9, 3.95, 6, bev=0.05), CANVAS))
    det.append(P(T([(-7.6, 3.9, 4.3), (-7.6, 4.15, 6), (-7.6, 3.9, 7.7)], 0.08, segs=4), BLACK))
    lk.add("Detail", det)
    glow(lk, [rbox(0.8, 0.12, 0.2, x, 3.0, 3.95, bev=0.04) for x in (-6, 6.6)], (255, 210, 80), "Lamp")


# ---------------------------------------------------------------- the tower ledge (Balcony: 6 x 0.6 x 6, its top at
# the foot)
if want("ActBalcony"):
    lk = Look("ActBalcony", "ActBalcony", False)
    det = [P(rbox(6.0, 0.6, 6.0, 0, -0.3, 0, bev=0.12), CONCRETE), P(rbox(6.3, 0.25, 6.3, 0, -0.65, 0, bev=0.05), WHITE)]
    for (x, z) in ((-2.6, -2.6), (2.6, -2.6), (-2.6, 2.6), (2.6, 2.6)):
        det.append(P(C(0.2, 2.6, x, 1.3, z, segs=8), BLACK))
    for (a, b) in (((-2.8, -2.8), (2.8, -2.8)), ((2.8, -2.8), (2.8, 2.8)), ((2.8, 2.8), (-2.8, 2.8)), ((-2.8, 2.8), (-2.8, -2.8))):
        det.append(P(T([(a[0], 2.6, a[1]), (b[0], 2.6, b[1])], 0.12, segs=5), BLACK))
        det.append(P(T([(a[0], 1.3, a[1]), (b[0], 1.3, b[1])], 0.07, segs=4), BLACK))
    for x in (-1.5, 1.5):  # corbels under it
        det.append(P(rbox(0.8, 1.6, 4.5, x, -1.6, 0, bev=0.12), CONCRETE))
    det += [P(C(0.55, 0.8, 1.8, 0.4, 1.8, segs=10, r2=0.75), RED), P(S(0.7, 1.8, 1.15, 1.8, sc=(1, 0.6, 1), segs=10, rings=6), GREEN)]
    lk.add("Detail", det)
    glow(lk, [S(0.18, x, 2.75, -2.6, segs=6, rings=4) for x in (-2.6, 2.6)], (255, 220, 120), "Lamp")


# ---------------------------------------------------------------- the falling billboard (FallingSign: a 16 x 8 board,
# foot at its middle, the poster facing -z; struts behind)
if want("ActBillboard"):
    lk = Look("ActBillboard", "ActBillboard", False)
    BIG["ActBillboard"] = 1024
    det = [P(rbox(16, 8, 0.5, 0, 0, 0.05, bev=0.12), REDMETAL), P(rbox(14.4, 6.4, 0.3, 0, 0, -0.18, bev=0.04), POSTER),
           P(rbox(16.4, 0.4, 0.8, 0, -4.1, 0, bev=0.08), BLACK), P(rbox(16.4, 0.4, 0.8, 0, 4.1, 0, bev=0.08), BLACK)]
    for x in (-5.0, 0.0, 5.0):  # the struts and the catwalk behind
        det.append(P(T([(x, 3.5, 0.4), (x, -3.5, 2.4)], 0.16, segs=5), DARKSTEEL))
        det.append(P(T([(x, -3.8, 0.4), (x, -3.8, 2.4)], 0.16, segs=5), DARKSTEEL))
    det.append(P(rbox(15, 0.25, 1.6, 0, -4.4, -0.9, bev=0.04), GRILLE))
    det.append(P(T([(-7.4, -4.3, -1.6), (-7.4, -3.3, -1.6), (7.4, -3.3, -1.6), (7.4, -4.3, -1.6)], 0.07, segs=4), DARKSTEEL))
    lk.add("Detail", det)
    bulbs = []
    for i in range(13):
        x = -7.2 + i * 1.2
        bulbs += [S(0.22, x, 3.65, -0.32, segs=8, rings=5), S(0.22, x, -3.65, -0.32, segs=8, rings=5)]
    for j in range(5):
        y = -2.4 + j * 1.2
        bulbs += [S(0.22, -7.65, y, -0.32, segs=8, rings=5), S(0.22, 7.65, y, -0.32, segs=8, rings=5)]
    glow(lk, bulbs, (255, 230, 120))

# ================================================================ events
# ---------------------------------------------------------------- the runaway train (trainModel: a 10 x 8 x 40 car at
# y 1..9, its cab hump at -16, the headlight at -20; nose at -z)
if want("ActTrain"):
    lk = Look("ActTrain", "ActTrain", False)
    BIG["ActTrain"] = 1024
    low = [(-20.0, 3.6, 1.4, 4.0), (-19.4, 4.6, 1.2, 5.4), (-18.0, 5.0, 1.1, 5.6), (18.0, 5.0, 1.1, 5.6), (19.5, 4.8, 1.2, 5.4),
           (20.0, 4.2, 1.4, 4.8)]
    up = [(-19.0, 3.6, 5.5, 8.4), (-17.0, 4.8, 5.5, 9.2), (-15.0, 5.0, 5.5, 9.4), (18.0, 5.0, 5.5, 9.4), (19.4, 4.6, 5.5, 9.0),
          (19.9, 3.8, 5.5, 8.0)]
    det = [P(loft_z(low, segs=16, power=3.2), R("TrainLow", (52, 92, 180), 0.4, 0.3)),
           P(loft_z(up, segs=16, power=3.2), CREAM)]
    det.append(P(rbox(10.1, 0.35, 37.0, 0, 5.5, 0.5, bev=0.1), RED))
    det.append(P(rbox(7.6, 2.6, 5.6, 0, 10.3, -16.0, bev=0.6), R("TrainCab", (226, 52, 48), 0.4, 0.3)))
    det.append(P(rbox(6.6, 0.4, 30, 0, 9.6, 4.0, bev=0.15), DARKSTEEL))
    for z in (-13.0, 13.0):  # bogies and wheels
        det.append(P(rbox(8.0, 1.0, 6.0, 0, 1.0, z, bev=0.2), BLACK))
        for x in (-4.1, 4.1):
            for dz in (-1.8, 1.8):
                det += wheel(x, 1.1, z + dz, 1.0, 0.6)
    det.append(P(rbox(9.6, 1.0, 1.0, 0, 1.6, -20.0, bev=0.3), HAZARDX))  # cow-catcher bumper
    det.append(P(rbox(4.0, 0.5, 0.3, 0, 3.2, -20.15, bev=0.1), GRILLE))
    for z in [-10.5 + k * 6.6 for k in range(5)]:  # door outlines between the windows
        det.append(P(rbox(10.15, 3.6, 0.25, 0, 3.4, z, bev=0.05), BLACK))
    lk.add("Detail", det)
    win = [rbox(10.25, 2.4, 29.0, 0, 7.0, 4.0, bev=0.3), rbox(6.0, 1.4, 0.3, 0, 10.6, -18.9, bev=0.2)]
    glass(lk, win, (130, 190, 235), 0.35)
    glow(lk, [C(0.9, 0.3, 0, 6.0, -20.15, segs=14, axis="z"), C(0.45, 0.3, -3.0, 2.8, -20.05, segs=10, axis="z"),
              C(0.45, 0.3, 3.0, 2.8, -20.05, segs=10, axis="z")], (255, 236, 150), "Lamp")


# ---------------------------------------------------------------- the airship (airshipModel: the envelope 60 long and 16
# across about the foot, the gondola under it at -10, its red engines at the tail, z 30)
if want("ActAirship"):
    lk = Look("ActAirship", "ActAirship", False)
    BIG["ActAirship"] = 1024
    st = []
    for k in range(13):
        t = k / 12
        z = -30 + 60 * t
        rr = 8.0 * math.sin(math.pi * (0.08 + 0.86 * t)) ** 0.62
        st.append((z, max(rr, 1.2), -max(rr, 1.2), max(rr, 1.2)))
    det = [P(loft_z(st, segs=20, power=2.0), ENVELOPE)]
    det.append(P(TOR(7.2, 0.45, 0, 0, -6, axis="z", segs=28, csegs=6), R("AirBand", (214, 44, 50), 0.4)))
    det.append(P(TOR(6.9, 0.45, 0, 0, 10, axis="z", segs=28, csegs=6), R("AirBand", (214, 44, 50), 0.4)))
    fin = [(20, 0), (29, 0), (29.5, 7.5), (24, 7.5)]
    for (ax, deg) in (("z", 0), ("z", 90), ("z", 180), ("z", 270)):
        f = prism([(z_, y_ + 2.5) for (z_, y_) in fin], -0.25, 0.25)
        turn(f, "z", deg, (0, 0, 0))
        det.append(P(f, R("AirFin", (60, 64, 76), 0.5, 0.4, pat=("hazard", (214, 44, 50), 1.5, "z"))))
    gon = [P(rbox(9.0, 4.4, 15.0, 0, -10.0, 4.0, bev=1.0), DARKPLATE), P(rbox(9.4, 0.6, 15.4, 0, -12.3, 4.0, bev=0.25), BLACK)]
    for x in (-3.0, 3.0):
        gon.append(P(T([(x, -7.8, -1.0), (x * 1.1, -4.0, -2.0)], 0.2, segs=5), DARKSTEEL))
        gon.append(P(T([(x, -7.8, 9.0), (x * 1.1, -4.5, 10.0)], 0.2, segs=5), DARKSTEEL))
    for s_ in (-1, 1):  # side engines with propellers
        gon.append(P(T([(s_ * 4.4, -9.5, 6.0), (s_ * 7.0, -9.5, 6.0)], 0.3, segs=6), DARKSTEEL))
        gon.append(P(C(1.0, 3.2, s_ * 7.5, -9.5, 6.4, segs=12, axis="z"), STEEL))
        for k in range(3):
            a = k * 2 * math.pi / 3
            gon.append(P(T([(s_ * 7.5, -9.5, 4.6), (s_ * 7.5 + math.cos(a) * 2.2, -9.5 + math.sin(a) * 2.2, 4.5)], 0.18, segs=4), BLACK))
    det += gon
    lk.add("Detail", det)
    glass(lk, [rbox(9.2, 1.6, 13.0, 0, -9.4, 4.0, bev=0.5), rbox(6.0, 1.6, 0.4, 0, -9.4, -3.4, bev=0.3)], (120, 40, 50), 0.35)
    glow(lk, [C(4.0, 1.2, -6, 0, 30.0, segs=14, axis="x"), C(4.0, 1.2, 6, 0, 30.0, segs=14, axis="x")], (255, 90, 60))
    glow(lk, [S(0.5, 0, -12.6, -2.5, segs=10, rings=6), S(0.45, 0, 8.0, -14.0, segs=8, rings=5)], (255, 60, 50), "Lamp")


# ---------------------------------------------------------------- the parade float (floatModel: a 12 x 4 x 22 deck at
# 0.5..4.5, a 10-stud pink ball at (0, 9.5, 2), a pole at (4, ., -8) and a banner at (7, 16, -8))
if want("ActFloat"):
    lk = Look("ActFloat", "ActFloat", False)
    BIG["ActFloat"] = 1024
    det = [P(rbox(12, 2.6, 22, 0, 3.0, 0, bev=0.5), R("FloatDeck", (252, 206, 42), 0.45)),
           P(rbox(12.4, 0.5, 22.4, 0, 4.45, 0, bev=0.2), WHITE), P(rbox(12.2, 1.4, 22.2, 0, 1.3, 0, bev=0.3), SKIRT)]
    for i in range(16):  # scalloped trim along the sides
        z = -10.0 + i * 1.33
        for x in (-6.15, 6.15):
            det.append(P(C(0.55, 0.25, x, 3.0, z, segs=8, axis="x"), PINK))
    for (x, z) in ((-4.6, -9.0), (4.6, -9.0), (-4.6, 9.0), (4.6, 9.0)):
        det += wheel(x * 1.0, 0.75, z, 0.75, 0.5)
    det.append(P(C(1.6, 0.8, 0, 4.9, 2, segs=16), GOLD))
    # the giant gift ball: ribbons round it both ways and a bow on top
    det.append(P(S(4.4, 0, 9.5, 2.0, segs=20, rings=14), PINK))
    det.append(P(TOR(4.45, 0.45, 0, 9.5, 2.0, axis="z", segs=28, csegs=6), GOLD))
    det.append(P(TOR(4.45, 0.45, 0, 9.5, 2.0, axis="x", segs=28, csegs=6), GOLD))
    for s_ in (-1, 1):
        lp = TOR(1.1, 0.35, s_ * 1.0, 14.4, 2.0, axis="z", segs=14, csegs=5)
        turn(lp, "z", s_ * 25, (s_ * 1.0, 14.4, 2.0))
        det.append(P(lp, GOLD))
    det.append(P(S(0.55, 0, 14.2, 2.0, segs=10, rings=6), GOLD))
    for (x, y, z, c_) in ((-2.6, 11.6, -1.4, YELLOW), (2.4, 7.4, -1.6, BLUE), (-1.6, 6.8, -1.9, GREEN), (2.8, 12.0, 0.2, YELLOW)):
        det.append(P(S(0.45, x, y, z, segs=8, rings=5), c_))  # polka dots
    det.append(P(C(0.3, 14.0, 4, 11.0, -8, segs=8), WHITE))
    det.append(P(S(0.5, 4, 18.2, -8, segs=10, rings=6), GOLD))
    for x0 in (-5.5, 5.5):  # bunting posts and flags
        det.append(P(C(0.15, 4.0, x0, 6.5, 10.5, segs=6), WHITE))
    for i in range(7):
        x = -5.0 + i * 1.65
        f = prism([(-0.02, 8.3 - 0.25 * math.sin(i / 6 * math.pi)), (0.02, 8.3 - 0.25 * math.sin(i / 6 * math.pi)),
                   (0.0, 7.3 - 0.25 * math.sin(i / 6 * math.pi))], x - 0.6, x + 0.6)
        det.append(P(f, [RED, BLUE, YELLOW, GREEN][i % 4]))
    for (x, z, c_) in ((-3.8, -7.0, BLUE), (3.0, 6.5, GREEN), (-3.5, 7.5, ORANGE)):  # gift boxes
        det.append(P(rbox(1.8, 1.8, 1.8, x, 5.6, z, bev=0.15), c_))
        det.append(P(rbox(1.9, 1.9, 0.35, x, 5.6, z, bev=0.05), GOLD))
    lk.add("Detail", det)
    glow(lk, [rbox(6, 4, 0.3, 7, 16, -8, bev=0.15)], (90, 200, 255), "Banner")
    glow(lk, [star(1.3, 0.55, 0.4, 7, 16, -8.3)], (255, 240, 160))


# ---------------------------------------------------------------- the power clamp (clampModel: a 6 x 10 x 6 column,
# an orange band at 6..8)
if want("ActClamp"):
    lk = Look("ActClamp", "ActClamp", False)
    det = [P(C(3.0, 1.2, 0, 0.6, 0, segs=6), DARKPLATE), P(C(2.1, 9.0, 0, 5.6, 0, segs=8, r2=1.7), DARKPLATE),
           P(C(2.4, 0.8, 0, 9.7, 0, segs=8), BLACK)]
    for y in (2.2, 3.0, 3.8, 4.6):
        det.append(P(TOR(2.15, 0.2, 0, y, 0, segs=16, csegs=4), COPPER))
    for k in range(4):  # prongs and spark tips on top
        a = k * math.pi / 2 + math.pi / 4
        det.append(P(T([(math.cos(a) * 1.4, 9.8, math.sin(a) * 1.4), (math.cos(a) * 2.4, 10.8, math.sin(a) * 2.4)], 0.18, segs=5), STEEL))
    for k in range(3):  # cables into the ground
        a = k * 2 * math.pi / 3 + 0.3
        det.append(P(T([(math.cos(a) * 1.9, 4.0, math.sin(a) * 1.9), (math.cos(a) * 2.9, 1.5, math.sin(a) * 2.9),
                        (math.cos(a) * 3.0, 0.2, math.sin(a) * 3.0)], 0.22, segs=6), BLACK))
    det.append(P(rbox(1.6, 1.0, 0.4, 0, 5.0, -2.0, bev=0.1), HAZARD))
    lk.add("Detail", det)
    glow(lk, [C(2.6, 1.8, 0, 7.0, 0, segs=8), S(0.35, 0, 10.6, 0, segs=8, rings=5)] +
         [S(0.25, math.cos(k * math.pi / 2 + math.pi / 4) * 2.45, 10.85, math.sin(k * math.pi / 2 + math.pi / 4) * 2.45, segs=6, rings=4)
          for k in range(4)], (255, 140, 40))


# ---------------------------------------------------------------- the Crane data truck (truckModel: a 9 x 22 chassis,
# the armoured box at (0, 7.5, 3), the cab at -7.5; nose at -z; the Crane C on each side, its red light on top)
if want("ActDataTruck"):
    lk = Look("ActDataTruck", "ActDataTruck", False)
    BIG["ActDataTruck"] = 1024
    det = [P(rbox(8.6, 1.6, 21.6, 0, 2.0, 0, bev=0.3), BLACK), P(rbox(9.0, 8.0, 14.0, 0, 7.5, 3.0, bev=0.5), NAVYPLATE),
           P(rbox(8.6, 5.0, 6.0, 0, 6.0, -7.5, bev=0.8), NAVYPLATE), P(rbox(8.0, 1.2, 1.4, 0, 2.6, -10.6, bev=0.3), CHROME),
           P(rbox(5.0, 1.4, 0.3, 0, 4.4, -10.55, bev=0.1), GRILLE), P(rbox(9.2, 0.4, 14.2, 0, 11.6, 3.0, bev=0.15), DARKSTEEL)]
    for s_ in (-1, 1):
        for z in (-7.0, 7.0):
            det += wheel(s_ * 4.2, 1.6, z, 1.6, 1.3)
            det.append(P(rbox(1.0, 0.6, 4.0, s_ * 4.4, 3.4, z, bev=0.2), BLACK))
        # the Crane C: three white bars on each side, as the parts
        x = s_ * 4.55
        det += [P(rbox(0.12, 0.8, 4.0, x, 10.0, 3.0, bev=0.05), WHITE), P(rbox(0.12, 4.0, 0.8, x, 8.0, 4.6, bev=0.05), WHITE),
                P(rbox(0.12, 0.8, 4.0, x, 6.0, 3.0, bev=0.05), WHITE)]
        det.append(P(rbox(0.3, 1.0, 0.5, s_ * 4.6, 7.2, -9.6, bev=0.1), BLACK))  # mirrors
        for z in (-3.0, 9.0):
            det.append(P(rbox(0.25, 6.0, 0.4, s_ * 4.5, 7.5, z, bev=0.08), DARKSTEEL))
    det.append(P(rbox(3.0, 7.0, 0.3, 0, 7.4, 10.05, bev=0.1), DARKSTEEL))
    lk.add("Detail", det)
    glass(lk, [rbox(7.8, 2.2, 0.3, 0, 7.0, -10.55, bev=0.3), rbox(0.3, 1.8, 3.0, -4.32, 7.0, -7.5, bev=0.2),
               rbox(0.3, 1.8, 3.0, 4.32, 7.0, -7.5, bev=0.2)], (110, 160, 210), 0.3)
    glow(lk, [rbox(4.0, 0.5, 1.0, 0, 12.0, 3.0, bev=0.2)], (255, 80, 60))
    glow(lk, [C(0.5, 0.3, -3.2, 4.5, -10.6, segs=10, axis="z"), C(0.5, 0.3, 3.2, 4.5, -10.6, segs=10, axis="z")], (255, 236, 150), "Lamp")


# ---------------------------------------------------------------- the stadium gates (siteModel Gate: posts 2 x 14 x 2 at
# x +-7, z 6; the barrier (Core) stays as it is between them)
if want("ActGate"):
    lk = Look("ActGate", "ActGate", False)
    det = []
    for x in (-7, 7):
        det += [P(rbox(2.4, 1.0, 2.4, x, 0.5, 6, bev=0.15), DARKSTEEL), P(rbox(2.0, 12.0, 2.0, x, 7.0, 6, bev=0.25), CHECKS),
                P(rbox(2.6, 1.0, 2.6, x, 13.5, 6, bev=0.2), DARKSTEEL)]
        for y in (3.0, 7.0, 11.0):
            det.append(P(rbox(2.2, 0.4, 2.2, x, y, 6, bev=0.05), BLACK))
        det.append(P(C(0.12, 2.6, x, 15.3, 6, segs=6), WHITE))
        det.append(P(prism([(6.0, 16.4), (6.0, 15.2), (7.8, 15.8)], x - 0.04, x + 0.04), RED))
    det.append(P(rbox(16.4, 0.8, 1.0, 0, 13.6, 6, bev=0.2), DARKSTEEL))
    lk.add("Detail", det)
    glow(lk, [rbox(0.5, 11.0, 0.5, x * 0.86, 6.0, 6, bev=0.15) for x in (-7, 7)] +
         [S(0.45, x, 14.4, 6, segs=10, rings=6) for x in (-7, 7)], (255, 90, 60))


# ---------------------------------------------------------------- the generator (siteModel / ContractService: a
# 6 x 6 x 6 housing, the core ball at 7; the glow takes the core's colour)
if want("ActGenerator"):
    lk = Look("ActGenerator", "ActGenerator", False)
    det = [P(rbox(5.8, 5.2, 5.8, 0, 2.9, 0, bev=0.5), R("GenBody", (232, 196, 52), 0.45, 0.3)),
           P(rbox(6.1, 0.6, 6.1, 0, 0.3, 0, bev=0.15), BLACK), P(rbox(6.0, 0.5, 6.0, 0, 5.6, 0, bev=0.15), DARKSTEEL)]
    for s_ in (-1, 1):
        det.append(P(rbox(0.3, 3.0, 4.0, s_ * 2.95, 2.9, 0, bev=0.1), GRILLE))
        det.append(P(rbox(4.0, 3.0, 0.3, 0, 2.9, s_ * 2.95, bev=0.1), SLATS))
    det += [P(C(1.4, 0.6, 0, 6.1, 0, segs=14), DARKSTEEL), P(TOR(1.3, 0.15, 0, 6.5, 0, segs=16, csegs=4), CHROME)]
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        det.append(P(T([(math.cos(a) * 1.3, 6.3, math.sin(a) * 1.3), (math.cos(a) * 1.25, 8.2, math.sin(a) * 1.25),
                        (0, 8.6, 0)], 0.1, segs=4), CHROME))
    det.append(P(T([(2.6, 1.0, 2.6), (3.6, 0.4, 3.4), (4.4, 0.2, 2.0)], 0.25, segs=6), BLACK))
    det.append(P(rbox(1.2, 0.8, 0.3, -1.6, 4.3, -3.0, bev=0.1), HAZARD))
    lk.add("Detail", det)
    glow(lk, [S(1.0, 0, 7.0, 0, segs=14, rings=10)], (120, 200, 255))
    glass(lk, [S(1.3, 0, 7.1, 0, sc=(1, 1.1, 1), segs=14, rings=10)], (200, 235, 255), 0.7, "Dome")


# ---------------------------------------------------------------- the city vault (holdProp Vault, events: a 22 x 16 x 5
# wall at z 9.5..14.5 and its 12-stud door at z 8.3..9.7): vault() above

# ---------------------------------------------------------------- the bridge barricade (holdProp Barricade: five 5 x 3
# boards at x = 5.5 i, z -18, each turned 4 i degrees)
if want("ActBarricade"):
    lk = Look("ActBarricade", "ActBarricade", False)
    det, lamps = [], []
    for i in range(-2, 3):
        x = i * 5.5
        one = [P(rbox(5.0, 1.0, 0.35, x, 2.2, -18, bev=0.1), HAZARDX), P(rbox(5.0, 0.7, 0.3, x, 1.0, -18, bev=0.08), HAZARDRED)]
        for sx in (-2.0, 2.0):
            one.append(P(T([(x + sx, 2.7, -18), (x + sx, 0.05, -18.9)], 0.12, segs=4), WHITE))
            one.append(P(T([(x + sx, 2.7, -18), (x + sx, 0.05, -17.1)], 0.12, segs=4), WHITE))
            one.append(P(rbox(0.5, 0.2, 2.0, x + sx, 0.1, -18, bev=0.05), BLACK))
        turn_ = [o for o in one]
        tilt(turn_, "up", i * 4, (x, 0, -18))
        det += one
        if i % 2 == 0:
            lp = C(0.3, 0.45, x - 2.0, 3.05, -18, segs=10)
            turn(lp, "up", i * 4, (x, 0, -18))
            lamps.append(lp)
    lk.add("Detail", det)
    glow(lk, lamps, (255, 150, 40), "Lamp")


# ---------------------------------------------------------------- a Harbour fog bank (ActivityFx: 90 x 16 x 90 about its
# middle): soft puffs, one see-through mesh (no texture)
if want("ActFog"):
    lk = Look("ActFog", "ActFog", False)
    puffs = []
    for (x, y, z, r, sy) in ((0, 1.0, 0, 30, 0.22), (-22, 0, 14, 22, 0.26), (24, -0.5, -10, 22, 0.26), (8, 0.5, 26, 18, 0.3),
                             (-12, 0.0, -26, 18, 0.3), (-32, -1.5, -12, 12, 0.34), (32, -1.5, 18, 12, 0.34)):
        puffs.append(S(r, x, y, z, sc=(1, sy * 2.6, 1), segs=14, rings=8))
    lk.add("Puffs", puffs, (215, 222, 230), "SmoothPlastic", 0.55)

# ================================================================ contracts
# ---------------------------------------------------------------- the defusal charge (chargeModel: a 3 x 2 x 3 case,
# its light (Core) at 2.5; the glow takes the light's colour)
if want("ActCharge"):
    lk = Look("ActCharge", "ActCharge", False)
    det = [P(rbox(3.0, 1.6, 2.4, 0, 0.8, 0, bev=0.25), DARKPLATE), P(rbox(3.1, 0.3, 2.5, 0, 0.15, 0, bev=0.05), BLACK)]
    for (z, reg) in ((-0.5, RED), (0.0, BLUE), (0.5, YELLOW)):
        det.append(P(T([(-1.4, 1.6, z), (-0.6, 2.2, z * 1.3), (0.6, 2.0, -z), (1.3, 1.6, z)], 0.09, segs=5), reg))
    for x in (-1.0, 1.0):  # the canisters
        det.append(P(C(0.42, 1.0, x, 1.85, 0.75, segs=10, axis="x"), HAZARDRED))
    det += [P(rbox(1.4, 0.8, 0.2, 0, 0.9, -1.25, bev=0.06), BLACK), P(C(0.4, 0.4, 0, 1.75, 0, segs=12), CHROME)]
    lk.add("Detail", det)
    glow(lk, [S(0.5, 0, 2.3, 0, segs=12, rings=8)], (255, 70, 60))
    glow(lk, [rbox(1.1, 0.5, 0.1, 0, 0.9, -1.36, bev=0.04)], (255, 90, 60), "Timer")


# ---------------------------------------------------------------- a demolition pylon (pylonModel: a 3 x 14 x 3 column,
# a red cap at 14)
if want("ActPylon"):
    lk = Look("ActPylon", "ActPylon", False)
    det = [P(C(1.9, 0.8, 0, 0.4, 0, segs=8), DARKSTEEL), P(C(1.4, 12.4, 0, 7.0, 0, segs=8, r2=0.9), HAZARD)]
    for y in (3.0, 6.5, 10.0):
        det.append(P(C(1.55 - y * 0.04, 0.6, 0, y, 0, segs=8), BLACK))
    for k in range(4):  # fins
        a = k * math.pi / 2
        f = prism([(0, 0.8), (0, 5.0), (1.2, 0.8)], -0.12, 0.12)
        turn(f, "up", math.degrees(a) + 90, (0, 0, 0))
        det.append(P(f, DARKSTEEL))
    det.append(P(C(1.0, 0.5, 0, 13.25, 0, segs=10), BLACK))
    lk.add("Detail", det)
    glow(lk, [C(1.8, 1.0, 0, 14.0, 0, segs=10, r2=1.4), S(0.5, 0, 14.8, 0, segs=8, rings=5)], (255, 90, 60))


# ---------------------------------------------------------------- the outpost mast (Demolition: a 2 x 26 x 2 mast, its
# red lamp at 27)
if want("ActOutpost"):
    lk = Look("ActOutpost", "ActOutpost", False)
    det = [P(rbox(3.6, 1.4, 3.6, 0, 0.7, 0, bev=0.2), DARKPLATE)]
    pts = [(math.cos(a) * 0.85, math.sin(a) * 0.85) for a in (math.pi / 2, math.pi / 2 + 2.094, math.pi / 2 + 4.189)]
    for (x, z) in pts:
        det.append(P(C(0.12, 24.6, x, 13.7, z, segs=6), REDMETAL))
    for k in range(12):  # the zigzag lacing
        y0, y1 = 1.4 + k * 2.0, 1.4 + (k + 1) * 2.0
        a, b = pts[k % 3], pts[(k + 1) % 3]
        det.append(P(T([(a[0], y0, a[1]), (b[0], y1, b[1])], 0.06, segs=4), WHITE))
    for (y, a) in ((18.0, 0.0), (21.0, 2.2)):  # dishes
        d = [P(C(0.25, 0.5, 0, y, 0, segs=12, r2=1.3), WHITE)]
        tilt(d, "z", -80, (0, y, 0))
        tilt(d, "up", math.degrees(a), (0, y, 0))
        for o in d:
            shift(o, rb(math.cos(a) * 0.9, 0, -math.sin(a) * 0.9))
        det += d
    det.append(P(rbox(1.6, 1.6, 0.8, 0, 3.0, -1.6, bev=0.15), BLACK))
    det.append(P(C(0.35, 1.0, 0, 26.0, 0, segs=8), DARKSTEEL))
    lk.add("Detail", det)
    glow(lk, [S(1.4, 0, 27.0, 0, segs=14, rings=10)], (255, 70, 60))
    glow(lk, [S(0.3, 0, 13.0, -0.95, segs=6, rings=4), S(0.3, 0, 7.0, -0.95, segs=6, rings=4)], (255, 70, 60), "Lamp")


# ---------------------------------------------------------------- the courier's parcel and drops (ContractService
# courierNext: a pickup, its crystal 2 x 4 x 2 at 2.5; the glow takes the pickup's colour)
if want("ActParcel"):
    lk = Look("ActParcel", "ActParcel", False)
    det = [P(rbox(2.6, 2.0, 2.0, 0, 1.6, 0, bev=0.12), CARDBOARD), P(rbox(2.7, 0.2, 2.1, 0, 2.62, 0, bev=0.04), CARDBOARD)]
    det.append(P(rbox(1.0, 0.7, 0.05, 0.6, 1.6, -1.02, bev=0.02), WHITE))
    det.append(P(rbox(3.2, 0.3, 2.6, 0, 0.45, 0, bev=0.08), DARKWOOD))
    for z in (-0.9, 0.9):
        det.append(P(rbox(3.2, 0.3, 0.4, 0, 0.15, z, bev=0.04), DARKWOOD))
    lk.add("Detail", det)
    glow(lk, [TOR(2.0, 0.14, 0, 0.12, 0, segs=24, csegs=4), C(0.5, 0.6, 0, 3.9, 0, segs=4, r2=0.02)] +
         [C(0.3, 0.8, 0, 4.6, 0, segs=6)], (120, 255, 170))

if want("ActDropPad"):
    lk = Look("ActDropPad", "ActDropPad", False)
    det = [P(C(2.4, 0.3, 0, 0.15, 0, segs=20), DARKSTEEL), P(C(1.7, 0.36, 0, 0.18, 0, segs=20), R("PadTop", (60, 66, 80), 0.6))]
    det += [P(C(0.12, 4.6, 2.2, 2.3, 2.2, segs=6), WHITE)]
    det.append(P(prism([(2.2, 4.6), (2.2, 3.6), (3.6, 4.1)], 2.16, 2.24), RED))
    lk.add("Detail", det)
    arrow = [rbox(0.6, 1.4, 0.6, 0, 3.7, 0, bev=0.1), C(1.0, 1.0, 0, 2.6, 0, segs=4, r2=0.02)]
    turn(arrow[1], "x", 180, (0, 2.6, 0))
    glow(lk, arrow + [TOR(2.0, 0.12, 0, 0.36, 0, segs=24, csegs=4)], (255, 210, 70))

# ================================================================ everywhere (SiteKit)
# ---------------------------------------------------------------- a drop circle (SiteKit.pad: the 28-stud disc stays;
# a post 10 tall with its green sign at 9.5, a rim round the circle)
if want("ActRescuePad"):
    lk = Look("ActRescuePad", "ActRescuePad", False)
    det = [P(TOR(13.7, 0.35, 0, 0.3, 0, segs=48, csegs=5), R("PadRim", (244, 244, 240), 0.5, pat=("chevron", (80, 184, 96), 24))),
           P(C(0.9, 0.5, 0, 0.25, 0, segs=12), CONCRETE), P(C(0.32, 9.0, 0, 4.9, 0, segs=10), WHITE),
           P(rbox(4.4, 2.8, 0.35, 0, 9.5, 0.05, bev=0.15), WHITE)]
    for y in (2.0, 3.0):
        det.append(P(TOR(0.4, 0.1, 0, y, 0, segs=10, csegs=4), GREEN))
    lk.add("Detail", det)
    cross = [rbox(2.0, 0.6, 0.2, 0, 9.5, -0.2, bev=0.08), rbox(0.6, 2.0, 0.2, 0, 9.5, -0.2, bev=0.08),
             rbox(2.0, 0.6, 0.2, 0, 9.5, 0.3, bev=0.08), rbox(0.6, 2.0, 0.2, 0, 9.5, 0.3, bev=0.08)]
    glow(lk, cross + [S(0.35, 0, 11.3, 0, segs=8, rings=5)], (80, 220, 140))

# ---------------------------------------------------------------- a hold ring (SiteKit.ring: the disc stays; a rim and
# arrows round it, built for radius 10, scaled to the ring; the glow takes the ring's colour)
if want("ActRing"):
    lk = Look("ActRing", "ActRing", False)
    det = [P(TOR(10.0, 0.22, 0, 0.3, 0, segs=56, csegs=4), BLACK)]
    for k in range(12):
        a = k * math.pi / 6
        det.append(P(C(0.25, 0.4, math.cos(a) * 10.0, 0.3, math.sin(a) * 10.0, segs=6), CHROME))
    lk.add("Detail", det)
    arrows = []
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        ch = prism([(-0.4, 0.05), (0.4, 0.05), (0.4, 0.32), (-0.4, 0.32)], -0.6, 0.6)
        ar = rings_mesh([[(-0.9, 0.06, 0.6), (0.0, 0.06, -0.5), (0.9, 0.06, 0.6), (0.0, 0.06, 0.1)],
                         [(-0.9, 0.3, 0.6), (0.0, 0.3, -0.5), (0.9, 0.3, 0.6), (0.0, 0.3, 0.1)]])
        bpy.data.objects.remove(ch, do_unlink=True)
        turn(ar, "up", -math.degrees(a) - 90, (0, 0, 0))
        shift(ar, rb(math.cos(a) * 8.8, 0, -math.sin(a) * 8.8))
        arrows.append(ar)
    glow(lk, arrows + [TOR(10.0, 0.12, 0, 0.55, 0, segs=56, csegs=4)], (255, 210, 70))

# ---------------------------------------------------------------- a shard (SiteKit.pickup: the 2 x 4 x 2 crystal at
# 2.5; the glow takes its colour)
if want("ActShard"):
    lk = Look("ActShard", "ActShard", False)
    det = [P(S(1.4, 0, 0.3, 0, sc=(1.2, 0.45, 1.0), segs=8, rings=5), ROCK), P(S(0.7, 0.9, 0.3, 0.6, sc=(1, 0.6, 1), segs=6, rings=4), ROCK)]
    lk.add("Detail", det)
    cr = []
    for (x, z, hgt, r, ax, az) in ((0.0, 0.0, 3.0, 0.55, 0, 14), (0.7, 0.4, 1.8, 0.35, 20, -24), (-0.6, -0.3, 1.5, 0.3, -18, 30),
                                   (-0.2, 0.7, 1.2, 0.25, 26, 10)):
        k = C(r, hgt, x, 0.6 + hgt / 2, z, segs=6)
        cap = C(r, r * 1.6, x, 0.6 + hgt + r * 0.8, z, segs=6, r2=0.02)
        tilt([k, cap], "z", az, (x, 0.6, z))
        tilt([k, cap], "x", ax, (x, 0.6, z))
        cr += [k, cap]
    glow(lk, cr, (150, 120, 255))


# ================================================================ the bake, the fit table and the export
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


MAPS = {}
for name, lk in LOOKS.items():
    if not lk.textured():
        continue
    vkit.RES = BIG.get(name, 512)
    print("baking", name, vkit.RES, flush=True)
    MAPS[name] = vkit.bake_look(lk, ao_samples=8 if FAST else 24)

TRIS = {}
total = 0
rows = []
for look in sorted(LOOKS):
    lk = LOOKS[look]
    rows.append("\t%s = {" % look)
    for mname in sorted(lk.meshes):
        ob = lk.meshes[mname]
        lo, hi = bounds(ob)
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        t = kit.tris(ob)
        TRIS[mname] = t
        total += t
        textured = ob in lk.textured()
        if textured:
            rgb, mat, alpha = (248, 248, 248), "SmoothPlastic", 0.0
        else:
            rgb, mat, alpha = lk.extra[mname]
        extra = (", alpha = %g" % alpha) if alpha else ""
        extra += ", maps = true" if textured else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (mname, max(size[0], 0.05), max(size[2], 0.05), max(size[1], 0.05), c[0], c[2], -c[1], rgb[0], rgb[1],
                       rgb[2], mat, extra, t))
    rows.append("\t},")
print("activity: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for look in sorted(LOOKS):
    lk = LOOKS[look]
    print("  %-16s %5d tris  (%s)" % (look, sum(TRIS[n] for n in lk.meshes), ", ".join(
        "%s %d" % (n[len(lk.prefix):], TRIS[n]) for n in sorted(lk.meshes))))

if ONLY is None:
    text = "\n".join([
        "-- GENERATED by art/blender/activity.py: do not edit by hand.",
        "-- The open-world activities' props in Blender meshes (ReplicatedStorage.Art.Activity; Shared.ActivityKit says which",
        "-- prop each look dresses, Fx.ActivityProps draws them): look -> mesh -> its size and its centre from the prop's",
        "-- foot point, in studs (x, up, z; front at -z), its colour (a copy's tint may replace a glow's), material,",
        "-- transparency, maps (a baked texture set in its SurfaceAppearance) and triangles. %d meshes in %d looks, %d triangles."
        % (len(TRIS), len(LOOKS), total),
        "return {",
    ] + rows + ["}", ""])
    FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "ActivityArt.luau"))
    with open(FIT, "w") as f:
        f.write(text)
    _stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
    if os.path.exists(_stylua):
        subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                       check=False)
    export = []
    for look, lk in LOOKS.items():
        pm = vkit.export_material(lk, MAPS[look]) if look in MAPS else None
        for mname, ob in lk.meshes.items():
            cp = copy(ob)
            cp.name = mname + "_x"
            kit.centre(cp)
            cp.name = mname
            cp.data.name = mname
            cp.data.materials.clear()
            if ob in lk.textured():
                cp.data.materials.append(pm)
            else:
                rgb, mat, alpha = lk.extra[mname]
                cp.data.materials.append(kit.material(mname + "Mat", rgb))
            export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(kit.ROOT, "export", "Activity.fbx"), use_selection=True,
        apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        path_mode="COPY", embed_textures=True)
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    import vpreview  # noqa: E402

    vpreview.PREV = os.path.join(kit.ROOT, "preview")
    res = (480, 360) if FAST else (640, 480)
    vpreview._scene(FAST, res)
    bpy.context.scene.cycles.samples = 10 if FAST else 24
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    mats = {name: vpreview._mat_textured(name, MAPS[name]) for name in MAPS}
    shots = []
    for name in sorted(LOOKS):
        lk = LOOKS[name]
        lo, hi = vpreview._size(lk)
        cx, cy, cz = [(lo[i] + hi[i]) / 2 for i in range(3)]
        span = max(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
        vpreview._ground(800, (112, 114, 120), at=(0, min(0.0, lo[1]) if lo[1] > -3 else lo[1] - 0.5, 0))
        vpreview._place(lk, mats)
        if name not in ("ActFog", "ActAirship", "ActBillboard"):
            vpreview._hero(hi[0] + 2.0, 0, lo[2] + (hi[2] - lo[2]) * 0.3, yaw=-20)
        d = span * 1.35 + 6
        vpreview._camera((cx - d * 0.62, cy + d * 0.42, cz - d * 0.72), (cx, cy, cz), lens=45)
        out = os.path.join(vpreview.PREV, "activity_%s.png" % name)
        kit.render(out)
        shots.append((name, out))
        vpreview._clear()
    imgs = []
    for name, path in shots:
        im = bpy.data.images.load(path)
        a = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32)
        im.pixels.foreach_get(a)
        imgs.append(a.reshape(im.size[1], im.size[0], 4))
    h, w = imgs[0].shape[:2]
    cols = 5
    rows_ = (len(imgs) + cols - 1) // cols
    sheet = np.ones((rows_ * h, cols * w, 4), dtype=np.float32) * 0.1
    for i, a in enumerate(imgs):
        r, c = i // cols, i % cols
        sheet[(rows_ - 1 - r) * h:(rows_ - r) * h, c * w:(c + 1) * w] = a
    im = bpy.data.images.new("sheet", cols * w, rows_ * h, alpha=True)
    im.pixels.foreach_set(sheet.reshape(-1))
    im.filepath_raw = os.path.join(vpreview.PREV, "activity.png")
    im.file_format = "PNG"
    im.save()
    print("preview", im.filepath_raw)
