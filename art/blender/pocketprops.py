# pocketprops.py: the mission and side quest pockets' most-seen props as Blender meshes (gap-props2, 2026-11-19).
# The pockets (Shared.PocketLayout) build their props from plain boxes and wear the pocket kit (Shared.PocketDress);
# Shared.PocketPropKit finds each prop's boxes (Config.PocketProps rules) and lays a look over them, and each device
# draws the look near its camera within its preset's budget (PocketDecor), hiding the boxes it stands in for (kept,
# so every collision, query and height is as before). Each look is built over the exact boxes it covers
# (art/export/pockets/layout.json from `lune run art/pockets/layout.luau`), in the pocket kit's style: chunky
# bevelled cartoon shapes in the pocket's own tints, one baked texture set a look (hbake.py), low poly for phones.
# Looks (each in its placement's frame: x, up, z from its middle; front at -z):
# * PkKennel, PkCell: the Spark Pound's cages (corner posts, barred sides and door, a grate lid, a padlock, a tag)
# * PkDesk, PkChairSchool, PkLockerSchool (tinted doors): the Halo Academy's classrooms and hall
# * PkLockerHall: Iron Hall's lockers; PkCabinet: Ashgrove's filing cabinets; PkChairLab: its waiting chairs
# * PkTank: a holding tank (steel plinth and cap, see-through glass, the glowing fluid); PkPad: a pod or Kindler pad
# * PkDummy (tinted head with a target ring, never a face), PkPunchBag: the training floors
# * PkPostKindler, PkPostScan, PkPostIron: the Kindler's light posts, the collar scanners, the chain posts
# * PkBrazier: an iron bowl on three legs with a flame; PkDeskOffice, PkDeskLab, PkDeskFront: desks with screens
# * PkCamera: Live's camera rigs; PkBarrier: its crowd barriers; PkChimney, PkWaterTank: The Copy's roofs
# The second set (gap-props3, 2026-11-19; --set 2, the default): PkStatue (Halo's statue: a stylised stone hero on
# the blocky R15 proportions with a plain sculpted head, no face or hair, under its gold halo), PkBlackboard, PkHoop,
# PkBookcase, PkConveyor, PkHalfBot, PkTrophyShelf, PkBench, PkWoodDummy, PkIronDoor, PkSealDoor, PkHoshiCage,
# PkChain, PkRollDoor, PkScanArch, PkDockCrate, PkStation, PkMast, PkStage, into art/export/PocketProps2.fbx and
# src/config/PocketPropArt2.luau (previews art/preview/pocket_props2.png, pocket_props2_rooms.png), so the first
# set's upload stays as it is; --set 1 rebuilds the first set (only to change it: it must then be uploaded again).
# Output (--set 1): art/export/PocketProps.fbx (textures embedded), art/export/pockets/<Look>_{Color,Normal,Roughness,
# Metalness}.png, src/config/PocketPropArt.luau; with --preview art/preview/pocket_props.png (the looks in a row)
# and art/preview/pocket_props_rooms.png (the pockets' rooms with their props, as a high preset sees them).
# Run: lune run art/pockets/layout.luau && $HOME/tools/bpyenv/bin/python art/blender/pocketprops.py [--set 1|2] [--preview] [--fast]
import json
import math
import os
import random
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401

kit.reset()

import numpy as np  # noqa: E402
import hbake  # noqa: E402
import ruinkit as rk  # noqa: E402
from studs import mesh, LOOKS, INFO, B, C, S, T, TOR, turn, shift, rb, star, prism, rings_mesh  # noqa: E402
from vkit import rbox  # noqa: E402

FAST = "--fast" in sys.argv
LAY = json.load(open(os.path.join(kit.ROOT, "export", "pockets", "layout.json")))
OUT = os.path.join(kit.ROOT, "export", "pockets")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- the pocket kit's comic colours
INK = (34, 32, 40)
STEEL = (150, 158, 170)
DSTEEL = (78, 82, 94)
IRON = (62, 60, 66)
CREAM = (246, 236, 210)
WOOD = (196, 140, 84)
DWOOD = (124, 82, 50)
RED = (214, 52, 48)
BLUE = (60, 112, 214)
YELLOW = (250, 204, 52)
GOLD = (240, 190, 60)
NAVY = (40, 52, 110)
GLASS = (196, 236, 255)
WHITE = (240, 242, 246)
BRICK = (178, 82, 62)
CANVAS = (226, 206, 160)
LEATHER = (176, 58, 46)

# ---------------------------------------------------------------- a brick pattern on hbake's bake
_base = hbake.pattern


def _pattern(kind, rgb, P, N):
    if kind == "brick":  # running bond: courses 0.5 up, bricks 1 along, mortar lines, each brick its own shade
        u, v, ax = hbake.planar(P, N)
        n = len(P)
        col = np.tile(np.array(rgb, np.float32) / 255, (n, 1))
        row = np.floor(v / 0.5)
        uu = u + (row % 2) * 0.5
        mortar = hbake._line(v, 0.5, 0.05) | hbake._line(uu, 1.0, 0.04)
        shade = hbake.vnoise(np.stack([np.floor(uu), row, ax * 1.0], axis=1) * 0.999, 1.0)
        mult = (0.82 + 0.22 * shade) * (0.94 + 0.08 * hbake.fbm(P, 2.0))
        col = col * mult[:, None]
        col = np.where(mortar[:, None], np.array([0.78, 0.74, 0.68], np.float32), col)
        h = -mortar.astype(np.float32) * 0.8
        return np.clip(col, 0, 1), mult, h.astype(np.float32), np.full(n, 0.85, np.float32), np.zeros(n, np.float32)
    return _base(kind, rgb, P, N)


hbake.pattern = _pattern
hbake.ROUGH.setdefault("brick", 0.85)

TINTED = set()  # meshes the game tints by the placement's colour (Config.PocketPropArt tint = true)
FRAMES = {}


def look_of(name):
    return LAY["looks"][name]


def frame(name):
    f = look_of(name)["frame"]
    FRAMES[name] = f
    return f


def rgb_of(name, i=0):
    return tuple(look_of(name)["boxes"][i]["rgb"])


def bright(c, k=1.12):
    return tuple(min(255, int(v * k)) for v in c)


def P(ob, rgb, mat="SmoothPlastic", pat=None, tint=False):
    return hbake.paint(ob, rgb, mat, pat, tint)


def box(sx, sy, sz, x, y, z, rgb, mat="SmoothPlastic", bev=0.08, pat=None, tint=False):
    return P(rbox(sx, sy, sz, x, y, z, bev=bev), rgb, mat, pat, tint)


def cyl(r, h, x, y, z, rgb, mat="SmoothPlastic", segs=12, axis="up", r2=None, pat=None):
    return P(C(r, h, x, y, z, segs=segs, axis=axis, r2=r2), rgb, mat, pat)


def bar(x0, y0, z0, x1, y1, z1, r, rgb, mat="Metal", segs=6):
    return P(T([(x0, y0, z0), (x1, y1, z1)], r, segs=segs), rgb, mat)


def body(name, parts, extra=()):
    mesh(name, name + "Body", parts, WHITE, "SmoothPlastic")
    for (suffix, prts, rgb, mat, alpha, tint) in extra:
        if prts:
            mesh(name, name + suffix, prts, rgb, mat, alpha)
            if tint:
                TINTED.add(name + suffix)


# ================================================================ cages (the Pound's kennels and Lark's cell)
def cage(name, bars_side, bar_r, post, trim):
    sx, sy, sz = frame(name)
    hx, hz = sx / 2, sz / 2
    bot, top = -sy / 2, sy / 2
    lid = 0.4
    steel = rgb_of(name)
    dark = tuple(int(c * 0.55) for c in steel)
    parts = []
    # corner posts (square tubes) and the base rail and top beam round all four sides
    pp = post / 2
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(box(post, sy - lid, post, cx * (hx - pp - 0.5), bot + (sy - lid) / 2, cz * (hz - pp - 0.5), dark, "Metal", 0.06))
    for cz in (-1, 1):
        parts.append(box(sx - 1.0, 0.5, 0.5, 0, bot + 0.25, cz * (hz - 0.75), trim, "Metal", 0.06))
        parts.append(box(sx - 1.0, 0.5, 0.5, 0, top - lid - 0.25, cz * (hz - 0.75), dark, "Metal", 0.06))
    for cx in (-1, 1):
        parts.append(box(0.5, 0.5, sz - 1.0, cx * (hx - 0.75), bot + 0.25, 0, trim, "Metal", 0.06))
        parts.append(box(0.5, 0.5, sz - 1.0, cx * (hx - 0.75), top - lid - 0.25, 0, dark, "Metal", 0.06))
    # the lid: a steel grate in a frame
    parts.append(box(sx, lid, sz, 0, top - lid / 2, 0, steel, "Metal", 0.05, pat="grate"))
    # the bars: back and both sides all the way; the front with a door in its middle
    yb, yt = bot + 0.5, top - lid - 0.5
    span_x, span_z = sx - 2.4, sz - 2.4
    for i in range(bars_side):
        t = (i + 0.5) / bars_side - 0.5
        parts.append(bar(t * span_x, yb, -(hz - 0.75), t * span_x, yt, -(hz - 0.75), bar_r, steel))
        for cx in (-1, 1):
            parts.append(bar(cx * (hx - 0.75), yb, t * span_z, cx * (hx - 0.75), yt, t * span_z, bar_r, steel))
    door = min(6.0, sx * 0.24)
    for i in range(bars_side):
        t = (i + 0.5) / bars_side - 0.5
        x = t * span_x
        parts.append(bar(x, yb, hz - 0.75, x, yt, hz - 0.75, bar_r, steel))
    # the door's frame, cross bars, hinges and a fat padlock; a yellow tag plate on the front
    zf = hz - 0.75
    for cx in (-1, 1):
        parts.append(box(0.35, yt - yb, 0.35, cx * door / 2, (yb + yt) / 2, zf + 0.25, trim, "Metal", 0.05))
    for y in (yb + 1.2, (yb + yt) / 2, yt - 1.2):
        parts.append(box(door, 0.3, 0.3, 0, y, zf + 0.28, trim, "Metal", 0.05))
    py = (yb + yt) / 2 - 0.9
    parts.append(box(1.1, 1.0, 0.45, door / 2 - 0.2, py, zf + 0.62, GOLD, "Metal", 0.12))
    parts.append(P(TOR(0.32, 0.08, door / 2 - 0.2, py + 0.65, zf + 0.62, axis="z", segs=12, csegs=4), DSTEEL, "Metal"))
    parts.append(box(3.0, 1.1, 0.12, -door / 2 - 2.6, yt - 1.4, zf + 0.5, YELLOW, "SmoothPlastic", 0.06))
    parts.append(box(2.2, 0.18, 0.06, -door / 2 - 2.6, yt - 1.3, zf + 0.58, INK, "SmoothPlastic", 0.02))
    parts.append(box(1.6, 0.18, 0.06, -door / 2 - 2.6, yt - 1.62, zf + 0.58, INK, "SmoothPlastic", 0.02))
    # a straw-and-blanket floor mat inside (it sits on the floor, never above the base rail)
    parts.append(box(sx * 0.42, 0.14, sz * 0.32, -sx * 0.18, bot + 0.07, -sz * 0.18, CANVAS, "Fabric", 0.05))
    body(name, parts)


# ================================================================ the Academy's desks, chairs and lockers
def desk_school():
    name = "PkDesk"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    wood = bright(rgb_of(name), 1.18)
    parts = [box(sx, 0.32, sz, 0, top - 0.16, 0, wood, "Wood", 0.1)]
    # the book box under the top, open at the pupil's side (+z), and the steel tube frame
    parts.append(box(sx - 0.8, 0.7, sz - 1.2, 0, top - 0.32 - 0.38, -0.3, bright(STEEL, 0.9), "Metal", 0.05))
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(bar(cx * (sx / 2 - 0.4), bot, cz * (sz / 2 - 0.4), cx * (sx / 2 - 0.4), top - 0.32, cz * (sz / 2 - 0.4), 0.12, DSTEEL))
        parts.append(bar(cx * (sx / 2 - 0.4), bot + 0.5, -(sz / 2 - 0.4), cx * (sx / 2 - 0.4), bot + 0.5, sz / 2 - 0.4, 0.08, DSTEEL))
    # a pencil groove, a red and a blue book and a pencil on top
    parts.append(box(sx - 1.4, 0.04, 0.2, 0, top + 0.01, -sz / 2 + 0.45, DWOOD, "Wood", 0.01))
    parts.append(box(1.4, 0.24, 1.0, 1.4, top + 0.12, 0.4, RED, "SmoothPlastic", 0.05))
    parts.append(box(1.2, 0.2, 0.9, 1.5, top + 0.34, 0.35, BLUE, "SmoothPlastic", 0.05))
    p = bar(-1.8, top + 0.08, 0.2, -0.6, top + 0.08, 0.5, 0.07, YELLOW, "SmoothPlastic")
    parts.append(p)
    body(name, parts)


def chair(name, back_tall, arms):
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    seat_c = bright(rgb_of(name), 1.1)
    sy0 = bot + sy * 0.48
    parts = [box(sx - 0.3, 0.32, sz - 0.4, 0, sy0, -0.1, seat_c, "SmoothPlastic", 0.12)]
    parts.append(box(sx - 0.3, top - sy0 - 0.1, 0.3, 0, (sy0 + top) / 2 + 0.05, sz / 2 - 0.2, seat_c, "SmoothPlastic", 0.12))
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(bar(cx * (sx / 2 - 0.35), bot, cz * (sz / 2 - 0.35), cx * (sx / 2 - 0.35), sy0 - 0.15, cz * (sz / 2 - 0.35), 0.1, DSTEEL))
        if arms:
            parts.append(box(0.3, 0.2, sz - 1.0, cx * (sx / 2 - 0.25), sy0 + 0.75, 0.0, DSTEEL, "Metal", 0.06))
            parts.append(bar(cx * (sx / 2 - 0.25), sy0, -sz / 2 + 0.7, cx * (sx / 2 - 0.25), sy0 + 0.7, -sz / 2 + 0.7, 0.08, DSTEEL))
    if back_tall:  # a cushion on the waiting chair
        parts.append(box(sx - 1.2, 0.18, sz - 1.4, 0, sy0 + 0.24, -0.2, bright(seat_c, 1.15), "Fabric", 0.08))
    body(name, parts)


def locker(name, doors, door_rgb=None, tinted=False):
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    shell = bright(rgb_of(name), 1.0) if not tinted else bright(STEEL, 0.95)
    parts = [box(sx, sy - 0.6, sz - 0.1, 0, bot + 0.3 + (sy - 0.6) / 2, 0.05, shell, "Metal", 0.08)]
    parts.append(box(sx, 0.3, sz, 0, top - 0.15, 0, DSTEEL, "Metal", 0.06))
    parts.append(box(sx - 0.2, 0.3, sz - 0.3, 0, bot + 0.15, 0.1, IRON, "Metal", 0.05))
    dw = (sx - 0.4) / doors
    door_parts, trim = [], []
    zf = -sz / 2
    for i in range(doors):
        x = -sx / 2 + 0.2 + dw * (i + 0.5)
        door_parts.append(box(dw - 0.18, sy - 1.3, 0.14, x, (bot + top) / 2, zf + 0.02, door_rgb or WHITE, "Metal", 0.04, tint=tinted))
        for k in range(3):
            trim.append(box(dw * 0.5, 0.12, 0.06, x, top - 1.2 - k * 0.35, zf - 0.06, INK, "Metal", 0.01))
        trim.append(box(0.18, 0.7, 0.14, x + dw * 0.32, (bot + top) / 2, zf - 0.08, bright(STEEL, 1.2), "Metal", 0.05))
        trim.append(box(dw * 0.36, 0.34, 0.05, x, top - 2.4, zf - 0.06, CREAM, "SmoothPlastic", 0.02))
        trim.append(box(0.1, 0.18, 0.04, x - 0.05, top - 2.4, zf - 0.09, INK, "SmoothPlastic", 0.0))
    if tinted:
        body(name, parts + trim, [("Doors", door_parts, WHITE, "Metal", 0.0, True)])
    else:
        body(name, parts + trim + door_parts)


# ================================================================ Ashgrove: cabinets, the tanks, desks
def cabinet():
    name = "PkCabinet"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    steel = bright(rgb_of(name), 1.05)
    parts = [box(sx, sy, sz, 0, 0, 0, steel, "Metal", 0.1)]
    zf = -sz / 2
    cols, rows = 2, 3
    dw, dh = (sx - 0.6) / cols, (sy - 0.8) / rows
    for c in range(cols):
        for r in range(rows):
            x = -sx / 2 + 0.3 + dw * (c + 0.5)
            y = bot + 0.5 + dh * (r + 0.5)
            parts.append(box(dw - 0.2, dh - 0.2, 0.14, x, y, zf - 0.04, bright(steel, 1.1), "Metal", 0.06))
            parts.append(box(1.2, 0.22, 0.2, x, y + dh * 0.18, zf - 0.16, DSTEEL, "Metal", 0.06))
            parts.append(box(1.1, 0.5, 0.04, x, y - dh * 0.12, zf - 0.13, CREAM, "SmoothPlastic", 0.01))
    # a tray of papers and a folder on top
    parts.append(box(2.4, 0.3, 1.8, -1.6, top + 0.15, 0.3, DSTEEL, "Metal", 0.05))
    parts.append(box(2.2, 0.16, 1.6, -1.6, top + 0.33, 0.3, WHITE, "SmoothPlastic", 0.02))
    parts.append(box(1.8, 0.14, 1.4, 1.6, top + 0.07, 0.0, YELLOW, "SmoothPlastic", 0.03))
    body(name, parts)


def tank():
    name = "PkTank"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    glow = tuple(look_of(name)["boxes"][1]["rgb"])
    parts = []
    parts.append(box(sx, 1.4, sz, 0, bot + 0.7, 0, DSTEEL, "Metal", 0.14, pat="plates"))
    parts.append(box(sx - 0.6, 0.2, sz - 0.6, 0, bot + 1.5, 0, YELLOW, "SmoothPlastic", 0.04, pat="hazard"))
    parts.append(box(sx, 1.2, sz, 0, top - 0.6, 0, DSTEEL, "Metal", 0.14))
    parts.append(box(sx - 1.2, 0.5, sz - 1.2, 0, top - 1.45, 0, STEEL, "Metal", 0.06))
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(cyl(0.32, sy - 2.6, cx * (sx / 2 - 0.5), 0, cz * (sz / 2 - 0.5), STEEL, "Metal", segs=8))
    # pipes and a valve wheel on the cap, a gauge on the front of the plinth
    for x in (-2.4, 2.4):
        parts.append(bar(x, top - 0.6, sz / 2 - 0.3, x, top - 0.6, sz / 2 + 0.25, 0.32, STEEL))
        parts.append(cyl(0.42, 0.16, x, top - 0.6, sz / 2 + 0.1, DSTEEL, "Metal", segs=10, axis="z"))
    parts.append(P(TOR(0.6, 0.12, 0, top + 0.25, 0, axis="up", segs=14, csegs=4), RED, "Metal"))
    parts.append(cyl(0.6, 0.2, 2.6, bot + 0.8, -sz / 2 - 0.05, WHITE, "SmoothPlastic", segs=14, axis="z"))
    parts.append(box(0.08, 0.5, 0.05, 2.6, bot + 0.9, -sz / 2 - 0.18, RED, "SmoothPlastic", 0.0))
    for x in (-3.4, -2.4):
        parts.append(cyl(0.22, 0.18, x, bot + 0.8, -sz / 2 - 0.04, (90, 230, 120) if x < -3 else RED, "SmoothPlastic", segs=8, axis="z"))
    # the glass shell and the glowing fluid (with a few bubbles) inside it
    gl = rbox(sx - 0.9, sy - 2.6, sz - 0.9, 0, bot + 1.4 + (sy - 2.6) / 2, 0, bev=0.6, segs=3)
    fluid = [rbox(sx - 1.4, 2.0, sz - 1.4, 0, bot + 2.6, 0, bev=0.3)]
    rnd = random.Random(7)
    for _ in range(7):
        fluid.append(S(rnd.uniform(0.18, 0.4), rnd.uniform(-3.5, 3.5), rnd.uniform(bot + 4.0, top - 3.0), rnd.uniform(-1.8, 1.8), segs=8, rings=5))
    body(name, parts, [("Glass", [gl], GLASS, "Glass", 0.55, False), ("Fluid", fluid, glow, "Neon", 0.0, False)])


def desk_screen(name, screen_box, front=False):
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    base = bright(rgb_of(name), 1.12)
    b0 = look_of(name)["boxes"][0]
    dtop = b0["at"][1] + b0["size"][1] / 2
    mat = "Wood" if b0["color"] == "wood" else "Metal"
    parts = [box(sx, 0.36, sz, 0, dtop - 0.18, 0, base, mat, 0.1)]
    glow = tuple(look_of(name)["boxes"][1]["rgb"])
    gx, gy, gz = look_of(name)["boxes"][1]["at"]
    gw, gh, gd = look_of(name)["boxes"][1]["size"]
    neon = []
    if front:
        # a reception counter: a tall panel on the visitors' side (-z) with a navy band, a glowing strip on top
        parts.append(box(sx, dtop - bot - 0.36, 0.5, 0, (bot + dtop - 0.36) / 2, -sz / 2 + 0.25, CREAM, "SmoothPlastic", 0.08))
        parts.append(box(sx - 0.4, 0.8, 0.1, 0, bot + (dtop - bot) * 0.55, -sz / 2 - 0.03, NAVY, "SmoothPlastic", 0.04))
        parts.append(box(sx - 0.4, 0.4, 0.1, 0, bot + 0.2, -sz / 2 - 0.03, DSTEEL, "Metal", 0.04))
        for cx in (-1, 1):
            parts.append(box(0.5, dtop - bot - 0.36, sz - 0.6, cx * (sx / 2 - 0.25), (bot + dtop - 0.36) / 2, 0.2, base, mat, 0.06))
        parts.append(box(3.0, 0.9, 2.0, -sx / 2 + 4.0, dtop + 0.45, 0.6, DSTEEL, "Metal", 0.08))
        parts.append(box(2.6, 0.06, 1.6, -sx / 2 + 4.0, dtop + 0.93, 0.6, (80, 200, 255), "SmoothPlastic", 0.02))
        neon.append(rbox(gw, gh, gd, gx, gy, gz, bev=0.05))
        neon.append(rbox(1.2, 0.3, 0.2, sx / 2 - 3.0, dtop + 0.15, 1.6, bev=0.05))
    else:
        # drawer pedestals at both ends, a modesty panel at the back (-z), the monitor facing +z and a keyboard
        pw = min(3.6, sx * 0.22)
        for cx in (-1, 1):
            x = cx * (sx / 2 - pw / 2 - 0.2)
            parts.append(box(pw, dtop - bot - 0.36, sz - 0.6, x, (bot + dtop - 0.36) / 2, 0.0, bright(base, 0.92), mat, 0.08))
            for k in range(3):
                hgt = (dtop - bot - 0.36) / 3
                y = bot + hgt * (k + 0.5)
                parts.append(box(pw - 0.4, hgt - 0.2, 0.1, x, y, sz / 2 - 0.28, bright(base, 1.06), mat, 0.04))
                parts.append(box(1.0, 0.16, 0.14, x, y + hgt * 0.15, sz / 2 - 0.18, DSTEEL, "Metal", 0.04))
        parts.append(box(sx - 2 * pw - 0.6, dtop - bot - 1.2, 0.2, 0, (bot + dtop - 0.6) / 2 + 0.2, -sz / 2 + 0.4, bright(base, 0.85), mat, 0.04))
        parts.append(box(gw + 0.6, gh + 0.6, 0.4, gx, gy, gz - 0.12, INK, "SmoothPlastic", 0.12))
        parts.append(box(0.6, gy - gh / 2 - dtop, 0.4, gx, (dtop + gy - gh / 2) / 2, gz - 0.12, DSTEEL, "Metal", 0.05))
        parts.append(box(2.4, 0.12, 1.4, gx, dtop + 0.06, gz - 0.12, DSTEEL, "Metal", 0.04))
        neon.append(rbox(gw, gh, 0.12, gx, gy, gz + 0.12, bev=0.03))
        parts.append(box(min(5.0, gw), 0.18, 1.3, gx, dtop + 0.09, gz + 2.0 if sz > 6 else gz + 1.8, DSTEEL, "Metal", 0.05))
        parts.append(cyl(0.38, 0.8, sx / 2 - pw - 1.2, dtop + 0.4, 1.0, RED, "SmoothPlastic", segs=10))
        parts.append(box(1.6, 0.4, 2.2, -sx / 2 + pw + 1.4, dtop + 0.2, 0.6, CREAM, "SmoothPlastic", 0.03))
    body(name, parts, [("Screen", neon, glow, "Neon", 0.0, False)])


# ================================================================ the training floors
def dummy():
    name = "PkDummy"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    head = look_of(name)["boxes"][1]
    hy = head["at"][1]
    hr = head["size"][1] / 2
    parts = [cyl(1.4, 0.3, 0, bot + 0.15, 0, DSTEEL, "Metal", segs=14)]
    parts.append(cyl(0.45, hy - hr - bot, 0, bot + (hy - hr - bot) / 2, 0, STEEL, "Metal", segs=10))
    parts.append(P(S(1.15, 0, hy - hr - 1.0, 0, sc=(1.0, 1.25, 0.85), segs=14, rings=9), CANVAS, "Fabric"))
    for cx in (-1, 1):
        parts.append(bar(cx * 0.8, hy - hr - 0.8, 0, cx * 1.75, hy - hr - 0.4, -0.2, 0.28, bright(DWOOD, 1.2), "Wood"))
    parts.append(P(TOR(0.75, 0.1, 0, hy, -hr + 0.08, axis="z", segs=16, csegs=4), INK))
    parts.append(P(C(0.32, 0.12, 0, hy, -hr + 0.06, segs=12, axis="z"), RED))
    headm = [P(S(hr * 0.96, 0, hy, 0, segs=16, rings=10), WHITE, "SmoothPlastic", tint=True)]
    body(name, parts, [("Head", headm, WHITE, "SmoothPlastic", 0.0, True)])


def punchbag():
    name = "PkPunchBag"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    bag = look_of(name)["boxes"][0]
    by0 = bag["at"][1] - bag["size"][1] / 2
    by1 = bag["at"][1] + bag["size"][1] / 2
    leather = bright(rgb_of(name), 1.15)
    parts = [P(C(1.4, by1 - by0 - 0.8, 0, (by0 + by1) / 2 + 0.1, 0, segs=16), leather, "Fabric")]
    parts.append(P(S(1.4, 0, by0 + 0.5, 0, sc=(1, 0.5, 1), segs=16, rings=6), leather, "Fabric"))
    parts.append(cyl(1.42, 0.3, 0, by1 - 0.2, 0, DSTEEL, "Metal", segs=16))
    for y in (by0 + 1.6, by1 - 1.4):
        parts.append(cyl(1.43, 0.35, 0, y, 0, INK, "Fabric", segs=16))
    parts.append(box(1.2, 0.8, 0.1, 0, (by0 + by1) / 2, -1.4, CREAM, "SmoothPlastic", 0.05))
    parts.append(box(0.7, 0.4, 0.06, 0, (by0 + by1) / 2, -1.47, RED, "SmoothPlastic", 0.02))
    for cx, cz in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        parts.append(bar(cx * 1.1, by1 - 0.05, cz * 1.1, 0, by1 + 1.0, 0, 0.06, DSTEEL))
    y = by1 + 1.0
    k = 0
    while y < top - 0.3:
        parts.append(P(TOR(0.3, 0.07, 0, y + 0.3, 0, axis="z" if k % 2 == 0 else "x", segs=10, csegs=4), STEEL, "Metal"))
        y += 0.5
        k += 1
    parts.append(P(TOR(0.4, 0.1, 0, top - 0.4, 0, axis="z", segs=12, csegs=4), DSTEEL, "Metal"))
    body(name, parts)


# ================================================================ pads, posts and braziers
def pad():
    name = "PkPad"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    r = min(sx, sz) / 2
    parts = [P(C(r / math.cos(math.pi / 8) * 0.98, sy - 0.2, 0, bot + (sy - 0.2) / 2, 0, segs=8), DSTEEL, "Metal")]
    turn(parts[0], "up", 22.5)
    top_ = P(C(r * 0.86, 0.2, 0, top - 0.1, 0, segs=8), bright(STEEL, 1.1), "DiamondPlate")
    turn(top_, "up", 22.5)
    parts.append(top_)
    ring = P(TOR(r * 0.9, 0.12, 0, top - 0.05, 0, segs=24, csegs=4), YELLOW, "SmoothPlastic", "hazard")
    parts.append(ring)
    for i in range(8):
        a = math.radians(22.5 + i * 45)
        parts.append(P(C(0.18, 0.12, math.cos(a) * r * 0.72, top + 0.02, math.sin(a) * r * 0.72, segs=6), IRON, "Metal"))
    parts.append(cyl(1.1, 0.14, 0, top + 0.02, 0, NAVY, "Metal", segs=16))
    body(name, parts)


def post(name, kind):
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    r = min(sx, sz) / 2
    base = bright(rgb_of(name), 1.05)
    parts = []
    if kind == "kindler":
        parts.append(cyl(r * 0.62, sy - 0.2, 0, 0, 0, WHITE, "SmoothPlastic", segs=12))
        parts.append(cyl(r, 0.5, 0, bot + 0.25, 0, DSTEEL, "Metal", segs=12))
        for k in range(1, 4):
            parts.append(cyl(r * 0.68, 0.3, 0, bot + k * sy / 4, 0, (70, 150, 230), "Metal", segs=12))
        parts.append(cyl(r * 0.9, 0.35, 0, top - 0.18, 0, DSTEEL, "Metal", segs=12))
        parts.append(bar(0, bot + 0.3, r * 0.6, 0, bot + 2.0, r * 0.6, 0.12, INK, "Rubber"))
    elif kind == "scan":
        parts.append(box(r * 1.3, sy - 0.4, r * 1.3, 0, bot + (sy - 0.4) / 2, 0, base, "Metal", 0.1))
        parts.append(box(sx, 0.4, sz, 0, bot + 0.2, 0, DSTEEL, "Metal", 0.08))
        parts.append(box(r * 1.36, 2.0, r * 1.36, 0, bot + 1.4, 0, YELLOW, "SmoothPlastic", 0.06, pat="hazard"))
        parts.append(box(1.0, 1.4, 0.4, 0, bot + 4.8, -r * 0.65 - 0.2, NAVY, "Metal", 0.08))
        parts.append(box(0.6, 0.3, 0.06, 0, bot + 5.1, -r * 0.65 - 0.42, (110, 230, 140), "SmoothPlastic", 0.02))
        parts.append(box(0.2, 0.2, 0.06, -0.2, bot + 4.6, -r * 0.65 - 0.42, RED, "SmoothPlastic", 0.02))
        parts.append(box(0.2, 0.2, 0.06, 0.2, bot + 4.6, -r * 0.65 - 0.42, YELLOW, "SmoothPlastic", 0.02))
        parts.append(box(r * 1.5, 0.3, r * 1.5, 0, top - 0.15, 0, DSTEEL, "Metal", 0.06))
    else:  # iron
        parts.append(box(r * 1.4, sy - 0.8, r * 1.4, 0, bot + 0.4 + (sy - 0.8) / 2, 0, IRON, "Metal", 0.12, pat="plates"))
        parts.append(box(sx, 0.8, sz, 0, bot + 0.4, 0, DSTEEL, "Metal", 0.14))
        parts.append(box(r * 1.6, 0.4, r * 1.6, 0, top - 0.9, 0, DSTEEL, "Metal", 0.08))
        for cx in (-1, 1):
            for cz in (-1, 1):
                for y in (bot + 2.0, top - 2.0):
                    parts.append(P(S(0.12, cx * r * 0.5, y, -r * 0.71 if cz < 0 else r * 0.71, segs=6, rings=4), STEEL, "Metal"))
        parts.append(P(TOR(0.42, 0.14, 0, top - 0.3, 0, axis="z", segs=12, csegs=5), DSTEEL, "Metal"))
    body(name, parts)


def brazier():
    name = "PkBrazier"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    fire = tuple(look_of(name)["boxes"][1]["rgb"])
    b0 = look_of(name)["boxes"][0]
    btop = b0["at"][1] + b0["size"][1] / 2
    parts = []
    bowl = rings = None  # noqa: F841
    parts.append(P(C(1.0, 1.2, 0, btop - 0.9, 0, r2=1.95, segs=16), IRON, "Metal"))
    parts.append(P(TOR(1.95, 0.14, 0, btop - 0.3, 0, segs=18, csegs=4), GOLD, "Metal"))
    for i in range(3):
        a = math.radians(90 + i * 120)
        parts.append(bar(math.cos(a) * 0.8, btop - 1.4, math.sin(a) * 0.8, math.cos(a) * 1.75, bot, math.sin(a) * 1.75, 0.16, IRON))
        parts.append(P(S(0.28, math.cos(a) * 1.75, bot + 0.12, math.sin(a) * 1.75, sc=(1, 0.5, 1), segs=8, rings=4), IRON, "Metal"))
    parts.append(P(TOR(1.1, 0.1, 0, btop - 2.0, 0, segs=14, csegs=4), IRON, "Metal"))
    rnd = random.Random(3)
    for i in range(7):
        a = rnd.uniform(0, math.pi * 2)
        d = rnd.uniform(0.2, 1.3)
        parts.append(P(S(rnd.uniform(0.3, 0.5), math.cos(a) * d, btop - 0.3, math.sin(a) * d, sc=(1, 0.6, 1), segs=7, rings=4), (40, 34, 32), "Slate"))
    flame = []
    for (x, z, r, h) in ((0, 0, 1.1, 1.9), (0.6, 0.3, 0.6, 1.3), (-0.6, -0.2, 0.6, 1.2), (0.1, -0.6, 0.5, 1.1), (-0.3, 0.6, 0.5, 1.0)):
        flame.append(C(r, h, x, btop - 0.2 + h / 2, z, segs=8, r2=0.05))
    body(name, parts, [("Flame", flame, fire, "Neon", 0.0, False)])


# ================================================================ Live: camera rigs and crowd barriers
def camera():
    name = "PkCamera"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    head = look_of(name)["boxes"][1]
    hy0 = head["at"][1] - head["size"][1] / 2
    parts = []
    for i in range(3):
        a = math.radians(90 + i * 120)
        parts.append(bar(0, hy0 - 0.5, 0, math.cos(a) * 1.8, bot, math.sin(a) * 2.2, 0.14, DSTEEL))
        parts.append(P(S(0.22, math.cos(a) * 1.8, bot + 0.1, math.sin(a) * 2.2, sc=(1, 0.5, 1), segs=8, rings=4), INK, "Rubber"))
    parts.append(cyl(0.3, hy0 - bot - 1.0, 0, bot + 1.0 + (hy0 - bot - 1.0) / 2 - 0.5, 0, STEEL, "Metal", segs=10))
    parts.append(cyl(0.7, 0.4, 0, hy0 - 0.3, 0, DSTEEL, "Metal", segs=12))
    # the camera: a chunky body with a yellow stripe, the lens forward (-z), viewfinder back, handle on top
    cy = hy0 + 1.3
    parts.append(box(3.0, 2.4, 3.6, 0, cy, 0.5, (52, 56, 66), "Metal", 0.3))
    parts.append(box(3.04, 0.4, 3.0, 0, cy - 0.3, 0.6, YELLOW, "SmoothPlastic", 0.06))
    parts.append(cyl(0.95, 1.2, 0, cy, -1.6, INK, "Metal", segs=16, axis="z"))
    parts.append(cyl(1.1, 0.25, 0, cy, -2.25, DSTEEL, "Metal", segs=16, axis="z"))
    parts.append(cyl(0.75, 0.06, 0, cy, -2.36, (70, 120, 200), "Glass", segs=16, axis="z"))
    parts.append(box(1.4, 1.0, 0.8, 0, cy + 0.5, 2.5, INK, "Metal", 0.15))
    parts.append(bar(-0.9, cy + 1.2, -0.6, 0.9, cy + 1.2, -0.6, 0.12, INK))
    parts.append(box(2.0, 0.24, 0.24, 0, top - 0.25, 0.4, INK, "Rubber", 0.08))
    for x in (-0.9, 0.9):
        parts.append(box(0.24, 0.5, 0.24, x, top - 0.6, 0.4, INK, "Rubber", 0.06))
    tally = [rbox(0.5, 0.35, 0.35, 1.0, top - 1.0, -0.9, bev=0.08)]
    body(name, parts, [("Tally", tally, RED, "Neon", 0.0, False)])


def barrier():
    name = "PkBarrier"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    steel = bright(rgb_of(name), 1.2)
    parts = []
    for y in (bot + 0.3, top - 0.15):
        parts.append(bar(-sx / 2 + 0.2, y, 0, sx / 2 - 0.2, y, 0, 0.14, steel, segs=8))
    for cx in (-1, 1):
        parts.append(bar(cx * (sx / 2 - 0.2), bot - 0.2, 0, cx * (sx / 2 - 0.2), top - 0.15, 0, 0.16, steel, segs=8))
        parts.append(box(0.5, 0.18, 1.7, cx * (sx / 2 - 0.6), bot - 0.41, 0, DSTEEL, "Metal", 0.05))
        parts.append(bar(cx * (sx / 2 - 0.2), bot - 0.32, -0.8, cx * (sx / 2 - 0.2), bot + 0.3, 0, 0.08, steel))
        parts.append(bar(cx * (sx / 2 - 0.2), bot - 0.32, 0.8, cx * (sx / 2 - 0.2), bot + 0.3, 0, 0.08, steel))
    n = 16
    for i in range(1, n):
        x = -sx / 2 + 0.2 + (sx - 0.4) * i / n
        parts.append(bar(x, bot + 0.3, 0, x, top - 0.15, 0, 0.06, steel, segs=5))
    parts.append(box(2.6, 1.0, 0.08, 0, (bot + top) / 2 + 0.1, -0.18, YELLOW, "SmoothPlastic", 0.05))
    parts.append(box(2.0, 0.5, 0.04, 0, (bot + top) / 2 + 0.1, -0.24, RED, "SmoothPlastic", 0.02))
    body(name, parts)


# ================================================================ The Copy's roofs: chimneys and water tanks
def chimney():
    name = "PkChimney"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    brick = bright(rgb_of(name), 1.05)
    parts = [box(sx - 0.3, sy - 0.7, sz - 0.3, 0, bot + (sy - 0.7) / 2, 0, brick, "Brick", 0.04, pat="brick")]
    parts.append(box(sx, 0.5, sz, 0, top - 0.45, 0, (196, 188, 176), "Concrete", 0.08))
    parts.append(box(sx - 1.4, 0.3, sz - 1.4, 0, top - 0.1, 0, (28, 24, 24), "Slate", 0.04))
    for cx in (-1, 1):
        parts.append(cyl(0.45, 0.6, cx * 0.7, top - 0.2, 0, (130, 70, 56), "Concrete", segs=10, r2=0.4))
    parts.append(box(sx - 0.1, 0.25, sz - 0.1, 0, bot + 1.2, 0, (196, 188, 176), "Concrete", 0.04))
    body(name, parts)


def watertank():
    name = "PkWaterTank"
    sx, sy, sz = frame(name)
    bot, top = -sy / 2, sy / 2
    r = min(sx, sz) / 2
    wood = bright(rgb_of(name), 1.1)
    parts = []
    y0, y1 = bot + 1.3, top - 1.8
    stave = P(C(r - 0.35, y1 - y0, 0, (y0 + y1) / 2, 0, segs=20), wood, "Wood")
    parts.append(stave)
    for y in (y0 + 0.5, (y0 + y1) / 2, y1 - 0.5):
        parts.append(P(TOR(r - 0.3, 0.1, 0, y, 0, segs=24, csegs=4), IRON, "Metal"))
    parts.append(P(C(r - 0.05, top - y1, 0, (y1 + top) / 2, 0, r2=0.25, segs=20), (172, 60, 52), "Metal"))
    parts.append(cyl(0.3, 0.4, 0, top - 0.1, 0, IRON, "Metal", segs=8))
    parts.append(cyl(r - 0.2, 0.3, 0, y0 - 0.15, 0, DSTEEL, "Metal", segs=16))
    for i in range(4):
        a = math.radians(45 + i * 90)
        parts.append(bar(math.cos(a) * (r - 0.9), y0 - 0.3, math.sin(a) * (r - 0.9), math.cos(a) * (r - 0.6), bot, math.sin(a) * (r - 0.6), 0.2, IRON))
    parts.append(bar(r - 0.9, y0 + 0.4, 0, r - 0.4, y0 + 0.4, 0, 0.22, DSTEEL))
    parts.append(bar(r - 0.4, y0 + 0.4, 0, r - 0.4, bot, 0, 0.22, DSTEEL))
    for k in range(6):  # a ladder up the side
        y = y0 + k * 0.8
        parts.append(bar(-0.5, y, -r + 0.05, 0.5, y, -r + 0.05, 0.05, IRON))
    for x in (-0.5, 0.5):
        parts.append(bar(x, y0, -r + 0.05, x, y1, -r + 0.05, 0.06, IRON))
    body(name, parts)


# ================================================================ build, bake, fit, export
cage("PkKennel", 7, 0.16, 0.8, (210, 170, 50))
cage("PkCell", 9, 0.2, 1.0, RED)
desk_school()
chair("PkChairSchool", False, False)
chair("PkChairLab", True, True)
locker("PkLockerSchool", 2, tinted=True)
locker("PkLockerHall", 4, door_rgb=(186, 56, 50))
cabinet()
tank()
desk_screen("PkDeskOffice", 1)
desk_screen("PkDeskLab", 1)
desk_screen("PkDeskFront", 1, front=True)
dummy()
punchbag()
pad()
post("PkPostKindler", "kindler")
post("PkPostScan", "scan")
post("PkPostIron", "iron")
brazier()
camera()
barrier()
chimney()
watertank()
SET1 = sorted(LOOKS)

# ================================================================ the second set (gap-props3, 2026-11-19)
# Built into art/export/PocketProps2.fbx and src/config/PocketPropArt2.luau with --set 2, so the first upload
# (PocketProps.fbx, PocketPropArt.luau) stays exactly as it is.
STONE = (226, 220, 206)
DSTONE = (176, 170, 160)
CHALK = (238, 240, 236)
BOARD = (46, 78, 64)
LACQUER = (176, 40, 36)
SILVER = (206, 212, 222)
BRONZE = (190, 120, 64)
RUBBER = (40, 40, 46)


def limb(x0, y0, x1, y1, z, w, d, rgb, mat="SmoothPlastic", bev=0.12, pat=None):
    """A square-ended box from (x0, y0) to (x1, y1) at depth z (a blocky arm or leg)."""
    L = math.hypot(x1 - x0, y1 - y0)
    ob = rbox(w, L, d, 0, 0, 0, bev=bev)
    turn(ob, "z", math.degrees(math.atan2(-(x1 - x0), (y1 - y0))))
    shift(ob, rb((x0 + x1) / 2, (y0 + y1) / 2, z))
    return P(ob, rgb, mat, pat)


def sbar(x0, y0, z0, x1, y1, z1, w, rgb, mat="Metal"):
    """A square bar (a plain box, 12 triangles) from one Roblox point to another: the light truss members."""
    from mathutils import Vector as V
    a, b_ = V(rb(x0, y0, z0)), V(rb(x1, y1, z1))
    d = b_ - a
    ob = kit.box("sb", w, w, d.length, at=(0, 0, 0))
    kit.apply_all(ob)
    q = V((0, 0, 1)).rotation_difference(d.normalized())
    mid = (a + b_) / 2
    for v in ob.data.vertices:
        v.co = q @ v.co + mid
    ob.data.update()
    return P(ob, rgb, mat)


def flat_box(sx, sy, sz, x, y, z, rgb, mat="SmoothPlastic", pat=None):
    return P(B(sx, sy, sz, x, y, z), rgb, mat, pat)


def statue():
    """Halo's statue: a stylised stone hero on the blocky R15 proportions (scale 1.5: legs 3, torso 3, head 1.8),
    hands on hips, cape behind, on a stepped plinth with a gold star plaque; the head is plain sculpted stone (no
    face or hair is ever modelled); the gold halo floats over it (the halo glow's disc)."""
    name = "PkStatue"
    sx, sy, sz = frame(name)
    b = look_of(name)["boxes"]
    fig, plinth, halo = b[0], b[1], b[2]
    f0 = fig["at"][1] - fig["size"][1] / 2  # the plinth's top: the figure's feet
    p0 = plinth["at"][1] - plinth["size"][1] / 2
    parts = []
    # the plinth: a base step, the block, a moulded cap whose top is the plinth box's top
    parts.append(box(12.0, 1.0, 12.0, 0, p0 + 0.5, 0, DSTONE, "Concrete", 0.08))
    parts.append(box(10.4, f0 - p0 - 1.7, 10.4, 0, (p0 + 1.0 + f0 - 0.7) / 2, 0, DSTONE, "Concrete", 0.06))
    parts.append(box(11.2, 0.7, 11.2, 0, f0 - 0.35, 0, STONE, "Marble", 0.1))
    parts.append(box(5.0, 1.4, 0.12, 0, (p0 + f0) / 2 + 0.2, -5.24, GOLD, "Foil", 0.04))
    parts.append(P(star(0.5, 0.22, 0.1, 0, (p0 + f0) / 2 + 0.2, -5.34), WHITE, "SmoothPlastic"))
    k = 1.5
    hip = f0 + 2 * k
    sh = hip + 2 * k
    # legs in a wide heroic stance and boots
    for s in (-1, 1):
        parts.append(limb(s * 0.75 * k, hip - 0.1, s * 1.0 * k, f0 + 0.35, 0, 0.96 * k, 0.96 * k, STONE, "Marble"))
        parts.append(box(1.05 * k, 0.5, 1.2 * k, s * 1.0 * k, f0 + 0.25, -0.1, STONE, "Marble", 0.12))
    # the torso (UpperTorso and LowerTorso), a belt, a raised star on the chest
    parts.append(box(2 * k, 2 * k, 1 * k, 0, hip + k, 0, STONE, "Marble", 0.16))
    parts.append(box(2 * k + 0.1, 0.36, 1 * k + 0.1, 0, hip + 0.3, 0, DSTONE, "Marble", 0.06))
    parts.append(P(star(0.62, 0.28, 0.16, 0, hip + 2.1, -0.78), STONE, "Marble"))
    # arms bent with fists on the hips
    for s in (-1, 1):
        ex, ey = s * 3.45, hip + 1.35
        parts.append(limb(s * 1.5 * k, sh - 0.45, ex, ey, 0, 0.92 * k, 0.92 * k, STONE, "Marble"))
        parts.append(limb(ex, ey, s * 1.95, hip + 0.45, 0, 0.88 * k, 0.88 * k, STONE, "Marble"))
        parts.append(box(1.35, 1.35, 1.35, s * 1.85, hip + 0.4, 0, STONE, "Marble", 0.2))
        parts.append(box(1.08 * k, 0.5, 1.08 * k, s * 1.5 * k, sh - 0.3, 0, STONE, "Marble", 0.2))  # shoulder pads
    # the head: plain sculpted stone, the blocky head's soft cube on a neck (no face, no hair)
    parts.append(cyl(0.45 * k, 0.35, 0, sh + 0.15, 0, STONE, "Marble", segs=12))
    parts.append(box(1.2 * k, 1.2 * k, 1.2 * k, 0, sh + 0.3 + 0.6 * k, 0, STONE, "Marble", 0.32))
    # the cape from the shoulders down the back, flaring and swept back to the plinth's top
    top, bot = sh - 0.1, f0 + 0.9
    rings = []
    for i in range(7):
        t = i / 6
        y = top + (bot - top) * t
        w = 1.55 * k + 1.3 * t
        zb = 0.8 + 1.6 * t * t
        ring = [(-w, y, zb), (w, y, zb), (w, y, zb + 0.32), (-w, y, zb + 0.32)]
        rings.append(ring)
    parts.append(P(rings_mesh(rings), STONE, "Marble"))
    parts.append(box(3.4, 0.4, 0.5, 0, sh - 0.05, 0.62, DSTONE, "Marble", 0.1))  # the collar
    gold = [TOR(3.08, 0.26, 0, halo["at"][1], 0, segs=28, csegs=5)]
    body(name, parts, [("Halo", gold, tuple(halo["rgb"]), "Neon", 0.0, False)])


def blackboard():
    name = "PkBlackboard"
    sx, sy, sz = frame(name)
    hz = sz / 2
    parts = [box(sx, sy, 0.5, 0, 0, hz - 0.25, DWOOD, "Wood", 0.1)]
    parts.append(box(sx - 1.2, sy - 1.2, 0.3, 0, 0.1, -hz + 0.35, BOARD, "Slate", 0.02))
    for y in (sy / 2 - 0.3, -sy / 2 + 0.3):
        parts.append(box(sx, 0.6, sz, 0, y, 0, WOOD, "Wood", 0.08))
    for x in (sx / 2 - 0.3, -sx / 2 + 0.3):
        parts.append(box(0.6, sy, sz, x, 0, 0, WOOD, "Wood", 0.08))
    # the chalk tray, two sticks and an eraser
    ty = -sy / 2 + 0.75
    parts.append(box(sx - 1.4, 0.18, 0.55, 0, ty, -hz - 0.25, WOOD, "Wood", 0.04))
    parts.append(bar(-6, ty + 0.14, -hz - 0.25, -5.0, ty + 0.14, -hz - 0.25, 0.06, CHALK, "SmoothPlastic"))
    parts.append(bar(-4.4, ty + 0.14, -hz - 0.3, -3.8, ty + 0.14, -hz - 0.2, 0.06, YELLOW, "SmoothPlastic"))
    parts.append(box(1.6, 0.36, 0.5, 5.0, ty + 0.27, -hz - 0.25, NAVY, "Fabric", 0.06))
    # chalk drawings: a flight arc of dashes, a star, a ring with an arrow through it, tally lines
    zf = -hz + 0.18
    for i in range(9):
        t = i / 8
        x = -14 + t * 12
        y = -1.5 + math.sin(t * math.pi) * 5.0
        parts.append(flat_box(0.8, 0.14, 0.04, x, y, zf, CHALK))
    parts.append(P(star(1.0, 0.45, 0.04, -1.2, 3.2, zf), CHALK))
    parts.append(P(TOR(1.6, 0.08, 6.0, 1.6, zf, axis="z", segs=20, csegs=3), CHALK))
    parts.append(flat_box(5.6, 0.14, 0.04, 6.0, 1.6, zf, CHALK))
    parts.append(P(turn(B(1.0, 0.14, 0.04, 8.5, 1.95, zf), "z", -35, (8.5, 1.95, zf)), CHALK))
    parts.append(P(turn(B(1.0, 0.14, 0.04, 8.5, 1.25, zf), "z", 35, (8.5, 1.25, zf)), CHALK))
    for i in range(5):
        parts.append(flat_box(0.12, 1.2, 0.04, 11.0 + i * 0.5, -2.2, zf, CHALK))
    parts.append(P(turn(B(2.8, 0.12, 0.04, 12.0, -2.2, zf), "z", 25, (12.0, -2.2, zf)), CHALK))
    for i, w in enumerate((7.0, 5.0, 6.0)):
        parts.append(flat_box(w, 0.12, 0.04, -9.0 + w / 2 - 3.0, -2.8 - i * 0.7, zf, CHALK))
    body(name, parts)


def hoop():
    name = "PkHoop"
    sx, sy, sz = frame(name)
    b = look_of(name)["boxes"]
    pz = b[0]["at"][2]
    bot = -sy / 2
    ry_ = b[1]["at"][1]
    parts = [box(2.8, 0.5, 2.8, 0, bot + 0.25, pz, DSTEEL, "Metal", 0.1)]
    parts.append(cyl(0.9, 0.4, 0, bot + 0.7, pz, IRON, "Metal", segs=12))
    top = ry_ - 0.5
    parts.append(cyl(0.38, top - bot - 0.9, 0, bot + 0.9 + (top - bot - 0.9) / 2, pz, STEEL, "Metal", segs=10))
    for k in range(4):
        y = bot + 3.0 + k * 3.6
        parts.append(cyl(0.41, 1.2, 0, y, pz, YELLOW if k % 2 == 0 else BLUE, "SmoothPlastic", segs=10))
    parts.append(bar(0, top, pz, 0, ry_, -2.75, 0.16, DSTEEL))
    parts.append(box(1.4, 0.3, 0.8, 0, ry_ - 0.1, -2.75, DSTEEL, "Metal", 0.06))
    ring = [TOR(2.72, 0.2, 0, ry_, 0, segs=28, csegs=5)]
    body(name, parts, [("Ring", ring, tuple(b[1]["rgb"]), "Neon", 0.0, False)])


def bookcase():
    name = "PkBookcase"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    parts = []
    wood = bright(rgb_of(name), 0.95)
    for s in (-1, 1):
        parts.append(box(0.6, sy, sz, s * (hx - 0.3), 0, 0, wood, "Wood", 0.06))
    parts.append(box(sx, 0.7, sz, 0, hy - 0.35, 0, DWOOD, "Wood", 0.1))
    parts.append(box(sx - 1.2, 0.8, sz - 0.2, 0, -hy + 0.4, 0.1, DWOOD, "Wood", 0.06))
    parts.append(box(sx - 1.2, sy - 1.5, 0.3, 0, 0.05, hz - 0.15, bright(DWOOD, 0.8), "Wood", 0.02))
    rows = 5
    y0, y1 = -hy + 0.8, hy - 0.7
    step = (y1 - y0) / rows
    rnd = random.Random(11)
    cols = [RED, BLUE, (60, 150, 90), YELLOW, NAVY, (150, 70, 150), CREAM, (200, 110, 50)]
    for r in range(rows):
        sy0 = y0 + r * step
        if r > 0:
            parts.append(box(sx - 1.2, 0.3, sz - 0.4, 0, sy0, 0.0, wood, "Wood", 0.04))
        x = -hx + 0.75
        while x < hx - 1.4:
            w = rnd.uniform(0.35, 0.7)
            h = rnd.uniform(step * 0.6, step * 0.85)
            if rnd.random() < 0.12 and x < hx - 3:  # a lying stack
                for k in range(3):
                    parts.append(flat_box(1.8, 0.3, sz - 1.0, x + 0.9, sy0 + 0.3 + k * 0.32, -0.2, rnd.choice(cols)))
                x += 2.0
                continue
            c = rnd.choice(cols)
            parts.append(flat_box(w, h, sz - 0.9 - rnd.uniform(0, 0.3), x + w / 2, sy0 + 0.15 + h / 2, -0.2, c))
            parts.append(flat_box(w + 0.02, 0.1, 0.05, x + w / 2, sy0 + 0.15 + h * 0.75, -hz + 0.42, GOLD))
            x += w + 0.04
    body(name, parts)


def conveyor():
    name = "PkConveyor"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    parts = [box(sx - 3.0, 0.3, sz - 2.4, 0, hy - 0.15, 0, RUBBER, "Rubber", 0.04)]
    for s in (-1, 1):
        parts.append(box(sx, 0.8, 0.8, 0, hy - 0.3, s * (hz - 0.6), YELLOW, "Metal", 0.08))
        parts.append(box(sx - 1.0, 1.7, 0.3, 0, hy - 1.4, s * (hz - 0.85), DSTEEL, "Metal", 0.04, pat="plates"))
        parts.append(cyl(0.95, sz - 1.8, s * (hx - 1.5), hy - 1.0, 0, STEEL, "Metal", segs=14, axis="z"))
        parts.append(box(1.8, 2.4, sz - 0.2, s * (hx - 0.9), -0.3, 0, DSTEEL, "Metal", 0.1))
        parts.append(box(0.2, 1.2, sz - 0.6, s * (hx - 0.05), -0.2, 0, YELLOW, "SmoothPlastic", 0.04, pat="hazard"))
    n = int(sx // 20)
    for i in range(n + 1):
        x = -hx + 6 + i * (sx - 12) / n
        for s in (-1, 1):
            parts.append(box(0.8, sy - 1.6, 0.8, x, -hy + (sy - 1.6) / 2, s * (hz - 1.2), IRON, "Metal", 0))
        parts.append(box(0.6, 0.4, sz - 2.4, x, -hy + 0.6, 0, IRON, "Metal", 0))
    body(name, parts)


def halfbot():
    """A half-built copy robot on the line: its carrier plate and stand, no legs yet, the chest open on its wires, one
    arm on and the other socket empty, the head's visor glowing (the eye glow box)."""
    name = "PkHalfBot"
    sx, sy, sz = frame(name)
    b = look_of(name)["boxes"]
    metal = bright(rgb_of(name), 1.05)
    dark = tuple(int(c * 0.55) for c in metal)
    eye = b[1]
    ez, ey = eye["at"][2], eye["at"][1]
    belt = -sy / 2 + 0.5
    parts = [box(3.6, 0.5, 3.0, 0, belt + 0.25, 0.15, DSTEEL, "Metal", 0.08, pat="plates")]
    parts.append(cyl(0.35, 1.8, 0, belt + 1.4, 0.15, STEEL, "Metal", segs=10))
    pel = belt + 2.4
    parts.append(box(2.4, 0.9, 1.8, 0, pel, 0.15, dark, "Metal", 0.14))
    for s in (-1, 1):  # empty hip sockets with dangling cables
        parts.append(cyl(0.35, 0.3, s * 0.75, pel - 0.55, 0.15, INK, "Metal", segs=8))
        parts.append(bar(s * 0.75, pel - 0.6, 0.15, s * 0.9, pel - 1.6, -0.2, 0.06, RED if s < 0 else BLUE, "Rubber"))
    t0, t1 = pel + 0.45, ey - 0.95
    parts.append(box(3.2, t1 - t0, 2.2, 0, (t0 + t1) / 2, 0.25, metal, "Metal", 0.2))
    zf = 0.25 - 1.1
    parts.append(box(1.9, 1.5, 0.1, 0, (t0 + t1) / 2 + 0.1, zf - 0.02, INK, "SmoothPlastic", 0.02))
    for i, c in enumerate((RED, YELLOW, BLUE, (90, 220, 120))):
        parts.append(bar(-0.7 + i * 0.45, (t0 + t1) / 2 + 0.7, zf - 0.08, -0.5 + i * 0.35, (t0 + t1) / 2 - 0.6, zf - 0.08, 0.06, c, "Rubber"))
    door = box(1.0, 1.6, 0.12, 1.55, (t0 + t1) / 2 + 0.1, zf - 0.35, metal, "Metal", 0.04)
    parts.append(door)
    parts.append(box(0.15, 0.4, 0.2, 1.05, (t0 + t1) / 2 + 0.1, zf - 0.14, DSTEEL, "Metal", 0.02))
    # one arm on (left), the right shoulder an empty socket with wires
    parts.append(box(1.0, 0.8, 1.2, -1.75, t1 - 0.4, 0.25, dark, "Metal", 0.14))
    parts.append(box(0.8, t1 - t0 - 0.4, 0.9, -1.75, (t0 + t1) / 2 - 0.4, 0.25, metal, "Metal", 0.14))
    parts.append(cyl(0.42, 0.3, 1.6, t1 - 0.45, 0.25, INK, "Metal", segs=8, axis="x"))
    parts.append(bar(1.65, t1 - 0.45, 0.25, 1.85, t1 - 1.6, 0.0, 0.06, YELLOW, "Rubber"))
    # the head, the visor's slot round the glowing eye
    parts.append(box(0.9, 0.4, 0.9, 0, t1 + 0.15, 0.25, dark, "Metal", 0.06))
    h0 = t1 + 0.3
    h1 = sy / 2
    parts.append(box(2.3, h1 - h0, 2.0, 0, (h0 + h1) / 2, 0.25, metal, "Metal", 0.22))
    parts.append(box(2.3, 0.8, 0.2, 0, ey, ez + 0.32, INK, "SmoothPlastic", 0.06))
    visor = [rbox(eye["size"][0], eye["size"][1] - 0.1, 0.16, 0, ey, ez + 0.1, bev=0.05)]
    body(name, parts, [("Eye", visor, tuple(eye["rgb"]), "Neon", 0.0, False)])


def trophy_shelf():
    name = "PkTrophyShelf"
    sx, sy, sz = frame(name)
    b = look_of(name)["boxes"]
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    shelves = [r for r in b if r["kind"] == "prop" and r["size"][0] > 50]
    cups = [r for r in b if r["color"] == "bank"]
    parts = [box(sx, sy, 0.25, 0, 0, hz - 0.125, bright(DWOOD, 0.8), "Wood", 0.02)]
    parts.append(box(sx, 0.5, 0.6, 0, hy - 0.25, hz - 0.5, DWOOD, "Wood", 0.06))
    shelf_ys = sorted(r["at"][1] for r in shelves)
    for y in shelf_ys:
        parts.append(box(sx, 0.6, 3.0, 0, y, 0.25, WOOD, "Wood", 0.08))
        parts.append(box(sx, 0.25, 0.12, 0, y - 0.12, -1.27, GOLD, "Foil", 0.02))
        for i in range(5):
            x = -hx + 4 + i * (sx - 8) / 4
            parts.append(P(prism([(1.75, y - 0.3), (1.75, y - 0.85), (0.6, y - 0.3)], x - 0.2, x + 0.2), DSTEEL, "Metal"))
    metals = {0: GOLD, 1: SILVER, 2: BRONZE}
    tops = [y + 0.3 for y in shelf_ys]
    for c in cups:
        x, y, z = c["at"]
        bottom = y - c["size"][1] / 2
        idx = max(i for i, t in enumerate(tops) if t <= bottom + 0.2)
        shelf_top = tops[idx]
        m = metals[len(tops) - 1 - idx]
        h = c["size"][1] + 0.1
        kind = int(round(x / 10.0)) % 3
        parts.append(box(1.5, 0.45, 1.5, x, shelf_top + 0.225, z, IRON, "Wood", 0))
        parts.append(box(1.0, 0.08, 0.05, x, shelf_top + 0.225, z - 0.77, GOLD, "Foil", 0.0))
        if kind == 0:  # a two-handled cup
            parts.append(cyl(0.18, 0.6, x, shelf_top + 0.75, z, m, "Foil", segs=8))
            parts.append(cyl(0.38, h - 1.15, x, shelf_top + 1.05 + (h - 1.15) / 2, z, m, "Foil", segs=8, r2=0.95))
            for s in (-1, 1):
                parts.append(P(TOR(0.3, 0.07, x + s * 0.85, shelf_top + h - 0.55, z, axis="z", segs=8, csegs=3), m, "Foil"))
        elif kind == 1:  # a star on a column
            parts.append(cyl(0.3, h - 1.6, x, shelf_top + 0.45 + (h - 1.6) / 2, z, m, "Foil", segs=8))
            parts.append(P(star(0.62, 0.27, 0.3, x, shelf_top + h - 0.65, z), m, "Foil"))
        else:  # a fist trophy: a blocky fist raised on a column
            parts.append(cyl(0.28, h - 1.7, x, shelf_top + 0.45 + (h - 1.7) / 2, z, m, "Foil", segs=8))
            parts.append(box(0.9, 0.9, 0.8, x, shelf_top + h - 0.75, z, m, "Foil", 0))
    body(name, parts)


def bench():
    name = "PkBench"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    parts = []
    for k in (-1, 0, 1):
        parts.append(box(sx, 0.32, 1.22, 0, hy - 0.16, k * 1.3, bright(WOOD, 1.08), "Wood", 0.06))
    n = 6
    for i in range(n):
        x = -hx + 2 + i * (sx - 4) / (n - 1)
        for s in (-1, 1):
            parts.append(box(0.4, sy - 0.32, 0.4, x, -hy + (sy - 0.32) / 2, s * (hz - 0.45), DSTEEL, "Metal", 0.05))
        parts.append(box(0.4, 0.3, sz - 0.4, x, hy - 0.47, 0, DSTEEL, "Metal", 0.04))
        parts.append(box(0.3, 0.25, sz - 0.6, x, -hy + 0.4, 0, DSTEEL, "Metal", 0.04))
    parts.append(box(sx - 4, 0.25, 0.25, 0, -hy + 0.4, 0, DSTEEL, "Metal", 0.04))
    # a folded towel, a water bottle and a gym bag's strap on top
    parts.append(box(2.4, 0.3, 1.8, -18, hy + 0.15, 0.3, (240, 240, 236), "Fabric", 0.1))
    parts.append(box(2.4, 0.06, 0.4, -18, hy + 0.31, 0.3, RED, "Fabric", 0.02))
    parts.append(cyl(0.22, 0.5, 9.0, hy + 0.25, -0.8, BLUE, "SmoothPlastic", segs=10))
    parts.append(box(3.0, 0.5, 1.6, 21.0, hy + 0.25, 0.4, RED, "Fabric", 0.18))
    body(name, parts)


def wood_dummy():
    name = "PkWoodDummy"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    arm = look_of(name)["boxes"][1]
    ay = arm["at"][1]
    wood = bright(rgb_of(name), 1.05)
    parts = [box(3.4, 0.3, 1.9, 0, -hy + 0.15, 0, DWOOD, "Wood", 0.06)]
    parts.append(box(0.5, 0.3, 1.9, -1.4, -hy + 0.45, 0, DWOOD, "Wood", 0.04))
    parts.append(box(0.5, 0.3, 1.9, 1.4, -hy + 0.45, 0, DWOOD, "Wood", 0.04))
    parts.append(cyl(0.72, sy - 0.4, 0, 0.2, 0, wood, "Wood", segs=12))
    parts.append(cyl(0.76, 0.2, 0, hy - 0.1, 0, DWOOD, "Wood", segs=12))
    for y in (ay - 1.3, ay + 0.9):
        parts.append(cyl(0.75, 0.16, 0, y, 0, IRON, "Metal", segs=12))
    for s in (-1, 1):  # the two upper arms, out and up a little, and the middle arm's stub below
        parts.append(bar(s * 0.5, ay, 0, s * 2.4, ay + 0.35, -0.3, 0.2, wood, "Wood", segs=8))
    parts.append(bar(0.3, ay - 0.9, -0.3, 1.9, ay - 1.0, -0.6, 0.2, wood, "Wood", segs=8))
    parts.append(bar(-0.4, -0.9, -0.3, -1.6, -1.6, -0.55, 0.22, wood, "Wood", segs=8))
    parts.append(bar(-1.6, -1.6, -0.55, -1.7, -2.4, -0.55, 0.2, wood, "Wood", segs=8))
    body(name, parts)


def slab_door(name, iron):
    """The sealed door (Ashgrove: hazard-striped steel, a locking wheel) or Iron Hall's iron door (studded plates, two
    ring pulls), each slid aside on its top track."""
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    parts = []
    zf = -hz
    if iron:
        parts.append(box(sx - 0.2, sy - 0.8, sz - 0.6, 0, -0.4, 0.1, IRON, "Metal", 0.14, pat="plates"))
        for y in (-hy + 2.2, 0.0, hy - 3.0):
            parts.append(box(sx, 1.1, sz - 0.2, 0, y, 0.0, DSTEEL, "Metal", 0.1))
            for i in range(7):
                parts.append(P(S(0.22, -hx + 1.2 + i * (sx - 2.4) / 6, y, zf + 0.05, segs=8, rings=5), GOLD, "Metal"))
        for s in (-1, 1):
            parts.append(P(TOR(0.75, 0.16, s * 2.0, -1.0, zf - 0.1, axis="z", segs=14, csegs=4), GOLD, "Metal"))
            parts.append(cyl(0.4, 0.3, s * 2.0, -0.3, zf + 0.05, DSTEEL, "Metal", segs=10, axis="z"))
    else:
        parts.append(box(sx - 0.2, sy - 0.8, sz - 0.6, 0, -0.4, 0.1, bright(STEEL, 1.05), "Metal", 0.14))
        parts.append(box(sx - 2.2, sy - 3.0, 0.3, 0, -0.6, zf + 0.2, STEEL, "Metal", 0.06, pat="plates"))
        for y in (-hy + 0.9, hy - 1.7):
            parts.append(box(sx - 0.2, 0.9, 0.14, 0, y, zf + 0.26, YELLOW, "SmoothPlastic", 0.04, pat="hazard"))
        parts.append(P(TOR(1.8, 0.2, 0, -0.4, zf - 0.15, axis="z", segs=20, csegs=4), RED, "Metal"))
        for a in range(4):
            r = math.radians(45 + a * 90)
            parts.append(bar(0, -0.4, zf - 0.15, math.cos(r) * 1.8, -0.4 + math.sin(r) * 1.8, zf - 0.15, 0.12, RED))
        parts.append(cyl(0.45, 0.4, 0, -0.4, zf - 0.1, DSTEEL, "Metal", segs=12, axis="z"))
        for s in (-1, 1):
            for y in (-3.5, 2.5):
                parts.append(box(1.4, 0.6, 0.6, s * (hx - 1.0), y, zf + 0.05, DSTEEL, "Metal", 0.08))
        parts.append(box(3.0, 1.0, 0.08, 0, hy - 3.1, zf + 0.22, WHITE, "SmoothPlastic", 0.03))
        parts.append(box(0.9, 0.7, 0.06, 0, hy - 3.1, zf + 0.16, RED, "SmoothPlastic", 0.02))
    # the track it slid along, its rollers
    parts.append(box(sx, 0.6, 0.8, 0, hy - 0.3, 0.0, DSTEEL, "Metal", 0.06))
    for s in (-1, 1):
        parts.append(cyl(0.38, 0.5, s * (hx - 2.0), hy - 0.75, 0.0, INK, "Metal", segs=10, axis="z"))
    body(name, parts)


def hoshi_cage():
    """Master Hoshi's cage: red-lacquered corner posts with gold caps, iron bars on every side, a door with a padlock
    on the front, a grated lid with a gold edge and a ring on each post where its chain is fixed."""
    name = "PkHoshiCage"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    b = look_of(name)["boxes"]
    lid = b[0]
    ly = lid["at"][1]
    bot = -hy
    parts = []
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(box(1.0, ly - 0.5 - bot, 1.0, cx * 12, bot + (ly - 0.5 - bot) / 2, cz * 12, LACQUER, "SmoothPlastic", 0.08))
            parts.append(box(1.3, 0.6, 1.3, cx * 12, bot + 0.3, cz * 12, GOLD, "Metal", 0.08))
            parts.append(P(TOR(0.42, 0.12, cx * 12.45, -2.5, cz * 12.45, axis="up", segs=10, csegs=4), DSTEEL, "Metal"))
    for s in (-1, 1):
        for y in (bot + 0.4, ly - 0.9):
            parts.append(box(23.0, 0.45, 0.45, 0, y, s * 12, IRON, "Metal", 0))
            parts.append(box(0.45, 0.45, 23.0, s * 12, y, 0, IRON, "Metal", 0))
    n = 13
    for i in range(1, n):
        t = -11.5 + 23.0 * i / n
        for s in (-1, 1):
            parts.append(bar(s * 12, bot + 0.6, t, s * 12, ly - 1.1, t, 0.13, IRON, "Metal", 4))
            parts.append(bar(t, bot + 0.6, 12, t, ly - 1.1, 12, 0.13, IRON, "Metal", 4))
            if abs(t) > 3.0:
                parts.append(bar(t, bot + 0.6, -12, t, ly - 1.1, -12, 0.13, IRON, "Metal", 4))
    # the door (front, -z): a frame of flat bars, its bars, hinges and a fat padlock
    for x in (-3.0, 3.0):
        parts.append(box(0.4, ly - 1.5 - bot, 0.4, x, (bot + ly - 1.5) / 2 + 0.3, -12.25, DSTEEL, "Metal", 0))
    for y in (bot + 1.2, 0.0, ly - 1.6):
        parts.append(box(6.4, 0.35, 0.35, 0, y, -12.3, DSTEEL, "Metal", 0))
    for x in (-1.5, 0.0, 1.5):
        parts.append(bar(x, bot + 1.2, -12.3, x, ly - 1.6, -12.3, 0.13, IRON, "Metal", 4))
    parts.append(box(1.1, 1.1, 0.5, 2.6, -1.2, -12.7, GOLD, "Metal", 0.12))
    parts.append(P(TOR(0.34, 0.09, 2.6, -0.45, -12.7, axis="z", segs=10, csegs=4), DSTEEL, "Metal"))
    # the lid: a gold-edged grate, the finials
    parts.append(box(24.4, 0.6, 24.4, 0, ly + 0.2, 0, IRON, "Metal", 0.05, pat="grate"))
    for s in (-1, 1):
        parts.append(box(24.8, 0.4, 0.5, 0, ly - 0.25, s * 12.2, GOLD, "Metal", 0))
        parts.append(box(0.5, 0.4, 24.8, s * 12.2, ly - 0.25, 0, GOLD, "Metal", 0))
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(P(S(0.4, cx * 12, ly + 0.55, cz * 12, segs=8, rings=5), GOLD, "Metal"))
    parts.append(box(6.0, 0.08, 6.0, -4.0, bot + 0.04, 3.0, (196, 170, 110), "Fabric", 0.02))  # a straw mat inside
    body(name, parts)


def chain():
    name = "PkChain"
    sx, sy, sz = frame(name)
    hz = sz / 2
    parts = []
    n = int(sz / 0.52)
    for i in range(n + 1):
        z = -hz + 0.3 + i * (sz - 0.6) / n
        t = z / hz
        y = -0.45 * (1 - t * t)
        parts.append(TOR(0.3, 0.09, 0, y, z, axis="x" if i % 2 == 0 else "up", segs=8, csegs=4))
    link = [P(p, DSTEEL, "Metal") for p in parts]
    body(name, link)


def roll_door():
    """The dock's roll door: guide rails, the roller drum's housing, the ribbed curtain part raised, a bottom bar with
    hazard stripes and its handle, and the daylight under it (the glowing window box's light)."""
    name = "PkRollDoor"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    b = look_of(name)["boxes"]
    win = b[0]
    parts = []
    for s in (-1, 1):
        parts.append(box(1.2, sy, sz, s * (hx - 0.6), 0, 0, DSTEEL, "Metal", 0.06))
    parts.append(box(sx, 1.8, sz, 0, hy - 0.9, 0, STEEL, "Metal", 0.14, pat="plates"))
    gap = -hy + 6.5
    top = hy - 1.8
    n = int((top - gap) / 0.5)
    for i in range(n):
        y = gap + 0.6 + i * (top - gap - 0.6) / n + 0.25
        parts.append(box(sx - 2.4, 0.44, 0.3, 0, y, -0.1 if i % 2 == 0 else 0.0, bright(STEEL, 1.08 if i % 2 == 0 else 0.92), "Metal", 0.06))
    parts.append(box(sx - 2.4, 0.6, 0.6, 0, gap + 0.3, -0.1, YELLOW, "SmoothPlastic", 0.06, pat="hazard"))
    parts.append(bar(-1.2, gap + 0.1, -0.55, 1.2, gap + 0.1, -0.55, 0.1, INK))
    for x in (-1.2, 1.2):
        parts.append(bar(x, gap + 0.1, -0.55, x, gap + 0.1, -0.35, 0.1, INK))
    parts.append(box(sx - 2.4, 0.3, sz, 0, -hy + 0.15, 0, IRON, "Metal", 0.04))
    light = [rbox(sx - 2.4, gap - (-hy + 0.3), 0.2, 0, (gap - hy + 0.3) / 2, win["at"][2] + 0.25, bev=0.02)]
    body(name, parts, [("Light", light, tuple(win["rgb"]), "Neon", 0.0, False)])


def scan_arch():
    name = "PkScanArch"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    b = look_of(name)["boxes"]
    glow = b[2]
    gy = glow["at"][1]
    parts = []
    for s in (-1, 1):
        x = s * 6
        parts.append(box(1.5, gy - 0.5 + hy, 1.5, x, (-hy + gy - 0.5) / 2, 0, WHITE, "SmoothPlastic", 0.18))
        parts.append(box(2.2, 0.5, 2.6, x, -hy + 0.25, 0, DSTEEL, "Metal", 0.08))
        parts.append(box(0.3, gy - 2.5 + hy, 1.0, x - s * 0.72, (-hy + 1.0 + gy - 1.5) / 2, 0, NAVY, "Metal", 0.04))
        for y in range(4):
            parts.append(box(0.1, 0.3, 0.7, x - s * 0.88, -hy + 2.5 + y * 2.6, 0, YELLOW, "SmoothPlastic", 0.02))
    parts.append(box(1.0, 1.4, 0.24, -6, -hy + 6.0, -0.84, INK, "SmoothPlastic", 0.06))
    parts.append(box(0.7, 0.5, 0.06, -6, -hy + 6.3, -0.97, (110, 230, 140), "SmoothPlastic", 0.02))
    parts.append(box(sx, 0.4, sz, 0, gy + 0.5 - 0.2, 0, DSTEEL, "Metal", 0.06))
    parts.append(box(sx, 0.3, sz, 0, gy - 0.5 + 0.15, 0, DSTEEL, "Metal", 0.06))
    band = [rbox(sx - 1.6, 0.4, sz + 0.1, 0, gy, 0, bev=0.04)]
    body(name, parts, [("Glow", band, tuple(glow["rgb"]), "Neon", 0.0, False)])


def dock_crate():
    name = "PkDockCrate"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    paint = bright(rgb_of(name), 1.05)
    parts = []
    for k in (-1, 0, 1):
        parts.append(box(sx, 0.3, 1.6, 0, -hy + 0.45, k * (hz - 0.8), DWOOD, "Wood", 0.04))
        parts.append(box(1.4, 0.3, sz, k * (hx - 0.7), -hy + 0.15, 0, DWOOD, "Wood", 0.04))
    c0, c1 = -hy + 0.6, -hy + 4.0
    parts.append(box(sx - 0.2, c1 - c0, sz - 0.2, 0, (c0 + c1) / 2, 0, bright(WOOD, 1.02), "Wood", 0.06))
    parts.append(box(sx, 0.9, sz, 0, (c0 + c1) / 2, 0, paint, "Metal", 0.04))
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(box(0.6, c1 - c0, 0.6, cx * (hx - 0.3), (c0 + c1) / 2, cz * (hz - 0.3), DWOOD, "Wood", 0.04))
    for s in (-1, 1):
        parts.append(P(turn(B(0.4, c1 - c0 - 0.2, 0.15, 0, (c0 + c1) / 2, s * (hz - 0.02)), "z", 50, (0, (c0 + c1) / 2, s * (hz - 0.02))), DWOOD, "Wood"))
    top = box(6.0, hy - c1, 6.0, 0, (c1 + hy) / 2, 0, bright(WOOD, 0.95), "Wood", 0.06)
    stripe = box(6.1, 0.5, 6.1, 0, (c1 + hy) / 2, 0, YELLOW, "Metal", 0.03)
    for o in (top, stripe):
        turn(o, "up", 18)
        shift(o, rb(-0.8, 0, 0.6))
        parts.append(o)
    body(name, parts)


def station():
    name = "PkStation"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    b = look_of(name)["boxes"]
    core, scr = b[0], b[1]
    cz0 = core["at"][2]
    parts = [box(8.0, 7.2, 4.0, 0, -hy + 0.4 + 3.6, cz0, bright(STEEL, 0.98), "Metal", 0.16, pat="plates")]
    parts.append(box(8.0, 0.8, 4.0, 0, -hy + 0.4, cz0, YELLOW, "SmoothPlastic", 0.06, pat="hazard"))
    for s in (-1, 1):
        parts.append(box(0.12, 4.0, 2.6, s * 4.0, 0.6, cz0, DSTEEL, "Metal", 0.03, pat="grate"))
    parts.append(box(7.0, 0.4, 3.4, 0, hy - 0.2, cz0, DSTEEL, "Metal", 0.06))
    for i in range(5):
        parts.append(cyl(0.22, 0.55, -2.4 + i * 1.2, hy + 0.25, cz0 + 0.3, STEEL, "Metal", segs=8))
    sx_, sy_, _ = scr["size"]
    _, gy, gz = scr["at"]
    parts.append(box(sx_ + 0.6, sy_ + 0.6, 0.3, 0, gy, gz + 0.25, INK, "SmoothPlastic", 0.08))
    parts.append(box(1.0, 1.8, 0.4, 3.3, -1.8, gz + 0.2, RED, "SmoothPlastic", 0.12))
    parts.append(bar(3.3, -1.8, gz + 0.1, 3.3, -0.6, gz - 0.1, 0.12, INK))
    parts.append(P(S(0.28, 3.3, -0.55, gz - 0.12, segs=8, rings=5), RED, "SmoothPlastic"))
    for i, c in enumerate(((90, 220, 120), YELLOW, RED)):
        parts.append(cyl(0.2, 0.12, -2.4 + i * 0.7, -1.9, gz + 0.06, c, "SmoothPlastic", segs=8, axis="z"))
    screen = [rbox(sx_, sy_, 0.12, 0, gy, gz + 0.12, bev=0.03)]
    body(name, parts, [("Screen", screen, tuple(scr["rgb"]), "Neon", 0.0, False)])


def mast():
    """Crane Tower's broadcast mast: a red and white lattice of four legs and cross braces on a foot plate, a deck and
    railing near the top, two dishes, and the beacon lamp (the glow box) in a cage."""
    name = "PkMast"
    sx, sy, sz = frame(name)
    hy = sy / 2
    b = look_of(name)["boxes"]
    pole, lamp = b[0], b[1]
    bot = -hy
    top = pole["at"][1] + pole["size"][1] / 2
    ly = lamp["at"][1]
    parts = [box(3.8, 0.4, 3.8, 0, bot + 0.2, 0, DSTEEL, "Metal", 0.06)]
    def w(y):
        t = (y - bot) / (top - bot)
        return 1.35 - 0.55 * t
    legs = []
    n = 10
    ys = [bot + 0.4 + (top - 1.0 - bot - 0.4) * i / n for i in range(n + 1)]
    for i in range(n):
        y0, y1 = ys[i], ys[i + 1]
        c = RED if i % 2 == 0 else WHITE
        a0, a1 = w(y0), w(y1)
        for cx, cz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            legs.append(bar(cx * a0, y0, cz * a0, cx * a1, y1, cz * a1, 0.14, c, "Metal", 6))
        for (p0, p1) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
            legs.append(bar(p0[0] * a0, y0, p0[1] * a0, p1[0] * a1, y1, p1[1] * a1, 0.07, c, "Metal", 4))
            legs.append(bar(p0[0] * a1, y1, p0[1] * a1, p1[0] * a1, y1, p1[1] * a1, 0.07, c, "Metal", 4))
    parts += legs
    dy = top - 0.6
    parts.append(box(2.8, 0.25, 2.8, 0, dy, 0, DSTEEL, "Metal", 0.04, pat="grate"))
    for s in (-1, 1):
        parts.append(bar(s * 1.35, dy + 0.9, -1.35, s * 1.35, dy + 0.9, 1.35, 0.06, YELLOW, "Metal", 4))
        parts.append(bar(-1.35, dy + 0.9, s * 1.35, 1.35, dy + 0.9, s * 1.35, 0.06, YELLOW, "Metal", 4))
    for cx, cz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        parts.append(bar(cx * 1.35, dy, cz * 1.35, cx * 1.35, dy + 0.9, cz * 1.35, 0.06, YELLOW, "Metal", 4))
    for (y, s) in ((bot + 20.0, -1), (bot + 24.0, 1)):
        d = P(C(1.1, 0.4, s * 1.6, y, 0, segs=14, r2=0.35, axis="x"), WHITE, "SmoothPlastic")
        parts.append(d)
        parts.append(bar(s * 0.9, y, 0, s * 1.4, y, 0, 0.1, DSTEEL))
    parts.append(cyl(1.2, 0.5, 0, top + 0.25, 0, DSTEEL, "Metal", segs=12))
    for i in range(6):
        a = math.radians(i * 60)
        parts.append(bar(math.cos(a) * 1.75, top + 0.5, math.sin(a) * 1.75, math.cos(a) * 1.75, ly + 1.4, math.sin(a) * 1.75, 0.08, INK, "Metal", 4))
    parts.append(cyl(1.9, 0.3, 0, ly + 1.55, 0, DSTEEL, "Metal", segs=12, r2=1.2))
    beacon = [S(1.5, 0, ly, 0, segs=14, rings=8)]
    body(name, parts, [("Beacon", beacon, tuple(lamp["rgb"]), "Neon", 0.0, False)])


def stage():
    """Live's stage: the deck in black boards with a star-skirted front, footlights along its edge; a truss round the
    giant screen (kept: never covered past its edge) on two towers, with par cans along the top."""
    name = "PkStage"
    sx, sy, sz = frame(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    b = look_of(name)["boxes"]
    deck, scr = b[0], b[1]
    dx_, dy_, dz_ = deck["size"]
    _, dcy, dcz = deck["at"]
    dtop = dcy + dy_ / 2
    dbot = dcy - dy_ / 2
    zf = dcz + dz_ / 2  # the audience's side (+z)
    zb = dcz - dz_ / 2
    parts = [box(dx_, 0.4, dz_, 0, dtop - 0.2, dcz, (46, 44, 52), "Wood", 0.06)]
    parts.append(box(dx_ - 0.4, dy_ - 0.4, dz_ - 0.4, 0, dcy - 0.2, dcz, (30, 30, 36), "Fabric", 0.02))
    parts.append(box(dx_, 0.5, 0.5, 0, dtop - 0.25, zf - 0.25, GOLD, "Metal", 0.08))
    parts.append(box(dx_, 0.5, 0.5, 0, dtop - 0.25, zb + 0.25, IRON, "Metal", 0.08))
    for s in (-1, 1):
        parts.append(box(0.5, 0.5, dz_, s * (dx_ / 2 - 0.25), dtop - 0.25, dcz, GOLD, "Metal", 0.08))
    for i in range(7):
        x = -dx_ / 2 + 8 + i * (dx_ - 16) / 6
        parts.append(P(star(0.7, 0.3, 0.1, x, dcy - 0.4, zf + 0.02), GOLD, "Foil"))
    lights = []
    for i in range(20):
        x = -dx_ / 2 + 3 + i * (dx_ - 6) / 19
        parts.append(box(1.1, 0.4, 0.5, x, dtop + 0.15, zf - 0.6, INK, "Metal", 0))
        lights.append(B(0.8, 0.2, 0.12, x, dtop + 0.2, zf - 0.88))
    # the truss: two towers from the ground beside the screen, a beam over it, a rail under it
    sw, sh_, _ = scr["size"]
    _, scy, scz = scr["at"]
    s_top, s_bot = scy + sh_ / 2, scy - sh_ / 2
    zt = scz + 1.0 + 1.0  # in front of the screen's face
    tw = 2.0

    def truss(x0, y0, x1, y1, z, along):
        bars = []
        L = math.hypot(x1 - x0, y1 - y0)
        n = max(1, int(L / 6.0))
        for cy_, cz_ in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            if along == "x":
                bars.append(sbar(x0, y0 + cy_ * tw / 2, z + cz_ * tw / 2, x1, y1 + cy_ * tw / 2, z + cz_ * tw / 2, 0.22, SILVER))
            else:
                bars.append(sbar(x0 + cy_ * tw / 2, y0, z + cz_ * tw / 2, x1 + cy_ * tw / 2, y1, z + cz_ * tw / 2, 0.22, SILVER))
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            p0 = (x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0)
            p1 = (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
            if along == "x":
                for cz_ in (-1, 1):
                    bars.append(sbar(p0[0], p0[1] - tw / 2, z + cz_ * tw / 2, p1[0], p1[1] + tw / 2, z + cz_ * tw / 2, 0.12, SILVER))
                bars.append(sbar(p0[0], p0[1] + tw / 2, z - tw / 2, p1[0], p1[1] + tw / 2, z + tw / 2, 0.12, SILVER))
            else:
                for cx_ in (-1, 1):
                    bars.append(sbar(p0[0] + cx_ * tw / 2, p0[1], z - tw / 2, p1[0] + cx_ * tw / 2, p1[1], z + tw / 2, 0.12, SILVER))
                bars.append(sbar(p0[0] - tw / 2, p0[1], z + tw / 2, p1[0] + tw / 2, p1[1], z + tw / 2, 0.12, SILVER))
        return bars

    tx = sw / 2 - tw / 2 - 0.1
    for s in (-1, 1):
        parts += truss(s * tx, -hy + 0.6, s * tx, s_top - tw / 2, zt, "up")
        parts.append(box(3.2, 0.6, 3.2, s * tx, -hy + 0.3, zt, IRON, "Metal", 0.06))
    parts += truss(-tx + tw / 2, s_top - tw / 2 + 0.25, tx - tw / 2, s_top - tw / 2 + 0.25, zt, "x")
    for i in range(10):
        x = -sw / 2 + 12 + i * (sw - 24) / 9
        y = s_top - tw - 0.6
        parts.append(sbar(x, s_top - tw + 0.2, zt, x, y + 0.3, zt, 0.14, INK))
        parts.append(cyl(0.6, 1.4, x, y, zt + 0.3, INK, "Metal", segs=8, axis="z", r2=0.5))
        lights.append(C(0.5, 0.1, x, y, zt + 1.0, segs=8, axis="z"))
    body(name, parts, [("Lights", lights, (255, 240, 200), "Neon", 0.0, False)])


SET2 = ["PkStatue", "PkBlackboard", "PkHoop", "PkBookcase", "PkConveyor", "PkHalfBot", "PkTrophyShelf", "PkBench",
        "PkWoodDummy", "PkIronDoor", "PkSealDoor", "PkHoshiCage", "PkChain", "PkRollDoor", "PkScanArch", "PkDockCrate",
        "PkStation", "PkMast", "PkStage"]
statue()
blackboard()
hoop()
bookcase()
conveyor()
halfbot()
trophy_shelf()
bench()
wood_dummy()
slab_door("PkIronDoor", True)
slab_door("PkSealDoor", False)
hoshi_cage()
chain()
roll_door()
scan_arch()
dock_crate()
station()
mast()
stage()



SETN = int(sys.argv[sys.argv.index("--set") + 1]) if "--set" in sys.argv else 2
ALL = sorted(SET2) if SETN == 2 else SET1
OTHER = SET1 if SETN == 2 else sorted(SET2)
SUFFIX = "2" if SETN == 2 else ""
missing = sorted(set(LAY["looks"]) - set(SET1) - set(SET2))
assert not missing, "looks in the layout with no builder: %s" % missing


def res_of(look, objs):
    span = max(FRAMES[look])
    return 256 if span <= 5 else (512 if span <= 20 else 1024)


REUSE = "--reuse" in sys.argv  # previews only: the texture sets already on disk, no fit or FBX written


def reuse_all(looks):
    mapped = {}
    for look in looks:
        objs = [ob for name, ob in sorted(LOOKS[look].items())
                if INFO[name][1] not in ("Neon", "Glass", "ForceField") and not INFO[name][2]]
        m = hbake.reuse(look, objs, OUT) if objs else None
        for ob in objs if m else ():
            mapped[ob.name] = m
    for img in bpy.data.images:  # (named as the bake names them, so hbake.preview_material finds the colour map)
        if img.name.endswith(".png"):
            img.name = img.name[:-4]
    return mapped


MAPPED = reuse_all(ALL) if REUSE else rk.bake_all(ALL, OUT, res_of, fast=FAST)
if "--preview" in sys.argv:  # the other set's looks from their texture sets on disk, for the room views
    MAPPED.update(reuse_all(OTHER))


def write_fit(path):
    rows = []
    total = count = 0
    for look in ALL:
        f = FRAMES[look]
        rows.append("\t%s = {" % look)
        rows.append("\t\tframe = { %.3f, %.3f, %.3f }," % tuple(f))
        rows.append("\t\tmeshes = {")
        for name in sorted(LOOKS[look]):
            ob = LOOKS[look][name]
            lo, hi = rk.bounds(ob)
            c = (lo + hi) / 2
            size = hi - lo
            t = kit.tris(ob)
            total += t
            count += 1
            rgb, mat, alpha = INFO[name]
            extra = (", alpha = %g" % alpha) if alpha else ""
            if name in MAPPED:
                extra += ", maps = true"
            if name in TINTED:
                extra += ", tint = true"
            rows.append("\t\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                        % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x, c.z, -c.y,
                           rgb[0], rgb[1], rgb[2], mat, extra, t))
        rows.append("\t\t},")
        rows.append("\t},")
    head = [
        "-- GENERATED by art/blender/pocketprops.py%s: do not edit by hand." % (" --set 2" if SETN == 2 else " --set 1"),
        "-- The pockets' %s props in Blender meshes (ReplicatedStorage.Art.PocketProps%s; Shared.PocketPropKit, the"
        % ("second set of" if SETN == 2 else "most-seen", SUFFIX),
        "-- Config.PocketProps rules, PocketDecor): look -> its frame (the box of its placement, studs x, up, z) and its meshes:",
        "-- each mesh's size and its centre from the frame's middle, its colour, material, transparency, maps (a baked texture",
        "-- set in its SurfaceAppearance), tint (takes its placement's palette colour) and triangles.",
        "-- %d meshes in %d looks, %d triangles." % (count, len(ALL), total),
    ]
    with open(path, "w") as fh:
        fh.write("\n".join(head + ["return {"] + rows + ["}", ""]))
    st = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
    if os.path.exists(st):
        subprocess.run([st, "--config-path", os.path.join(kit.ROOT, "..", "stylua.toml"), path], check=False)
    return total, count


if not REUSE:
    FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "PocketPropArt%s.luau" % SUFFIX))
    total, count = write_fit(FIT)
    print("pocket props: %d looks, %d meshes, %d tris" % (len(ALL), count, total))
    for look in ALL:
        print("  %-16s %5d tris  %d meshes" % (look, sum(kit.tris(o) for o in LOOKS[look].values()), len(LOOKS[look])))
    rk.export_fbx(os.path.join(kit.ROOT, "export", "PocketProps%s.fbx" % SUFFIX), ALL, MAPPED)


# ================================================================ previews
def placed(look, at, ry, keep, tint=None):
    import vpreview as vp
    for name, ob in LOOKS[look].items():
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.data.materials.clear()
        rgb, mat, alpha = INFO[name]
        if name in MAPPED:
            m = hbake.preview_material(MAPPED[name], tuple(tint) if (tint and name in TINTED) else rgb) if name in TINTED else MAPPED[name]
        else:
            m = vp._mat_flat(tuple(rgb), mat, alpha)
        cp.data.materials.append(m)
        cp.location = rb(*at)
        cp.rotation_euler = (0, 0, math.radians(ry))
        keep(cp)


if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402

    PREV = os.path.join(kit.ROOT, "preview")
    vp._scene(FAST, (640, 400) if FAST else (1400, 800))
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))  # light the props' fronts (Roblox -z)
    fill.data.energy = 2.6
    fill.rotation_euler = (math.radians(-50), math.radians(-12), math.radians(-25))
    bpy.context.scene.collection.objects.link(fill)
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    if SETN == 1:
        # the looks in two rows, each with its first tint
        vp._ground(400, (120, 118, 112))
        order = ["PkDesk", "PkChairSchool", "PkLockerSchool", "PkDummy", "PkPad", "PkChairLab", "PkCabinet", "PkTank",
                 "PkPostKindler", "PkDeskFront", "PkDeskLab", "PkLockerHall", "PkPunchBag", "PkPostIron", "PkBrazier",
                 "PkDeskOffice", "PkPostScan", "PkKennel", "PkCell", "PkCamera", "PkBarrier", "PkChimney", "PkWaterTank"]
        rows_ = [order[:12], order[12:]]
        for ri, row in enumerate(rows_):
            x = 0.0
            for look in row:
                f = FRAMES[look]
                placed(look, (x + f[0] / 2, f[1] / 2, ri * 36.0), 0, vp._keep, look_of(look).get("tint"))
                x += f[0] + 2.0
        vp._camera((60, 34, -48), (60, 4, 18), lens=30)
        shots = []
        out = os.path.join(PREV, "pocket_props_row.png")
        kit.render(out)
        shots.append(out)
        for (frm, to, n) in (((14, 7, -12), (14, 3, 0), "close1"), ((44, 8, -14), (44, 3, 0), "close2"),
                             ((24, 10, 18), (26, 4, 36), "close3")):
            vp._camera(frm, to, lens=30)
            out = os.path.join(PREV, "pocket_props_%s.png" % n)
            kit.render(out)
            shots.append(out)
        vp._clear()
    else:  # the second set: each look on its own, seen from its front (-z) and a little above
        shots = []
        for look in SET2:
            f = FRAMES[look]
            vp._ground(600, (120, 118, 112))
            placed(look, (0, f[1] / 2, 0), 0, vp._keep, look_of(look).get("tint"))
            d = max(f[0], f[1] * 1.3, 6.0) * 0.95 + 2.0
            vp._camera((d * 0.45, f[1] * 0.55 + d * 0.3, -d), (0, f[1] * 0.45, 0), lens=34)
            out = os.path.join(PREV, "pocket_props2_%s.png" % look)
            kit.render(out)
            shots.append(out)
            vp._clear()

    # the pockets' rooms: every other box plain, the props in their looks
    def room(pk, frm, to, name, lens=30, ybelow=-1e9, yabove=1e9):
        vp._ground(800, (110, 108, 104), at=(0, -2.2, 0))
        for b in pk["boxes"]:
            sx, sy, sz = b["size"]
            x, y, z = b["at"]
            if b.get("big", 0) > 300 and b["kind"] in ("plaza",):
                pass
            if y < ybelow or y > yabove or b.get("tag") == "ceiling":
                continue
            if b.get("shape") == "cylinder":
                o = kit.cyl("c", min(sx, sz) / 2, min(sx, sz) / 2, sy, at=rb(x, y, z), segs=24)
            elif b.get("shape") == "ball":
                o = kit.sphere("s", r=max(sx, sy, sz) / 2, at=rb(x, y, z))
            elif b.get("shape") == "wedge":
                continue
            else:
                o = kit.box("b", sx, sz, sy, at=(0, 0, 0))
                o.rotation_euler = (0, 0, math.radians(b.get("ry", 0)))
                o.location = rb(x, y, z)
            kind = "Neon" if b["kind"] == "glow" else "SmoothPlastic"
            alpha = 0.6 if b["color"] == "glass" else 0.0
            o.data.materials.append(vp._mat_flat(tuple(b["rgb"]), kind, alpha))
            vp._keep(o)
        for p in pk["places"]:
            placed(p["look"], tuple(p["at"]), p["ry"], vp._keep, p.get("tint"))
        vp._camera(frm, to, lens=lens)
        out = os.path.join(PREV, name + ".png")
        kit.render(out)
        vp._clear()
        return out

    P_ = {pk["name"]: pk for pk in LAY["pockets"]}
    A, L, I = P_["academy"], P_["ashlab"], P_["ironhall"]
    if SETN == 1:
        rooms = [
            room(A, (-100, 38, 116), (-150, 25, 55), "pocket_props_class", 30),
            room(A, (0, 36, 120), (0, 27, 40), "pocket_props_hall", 30),
            room(A, (-10, 32, 178), (-86, 27, 152), "pocket_props_lockers", 30),
            room(P_["pound"], (0, 40, 70), (0, 4, -60), "pocket_props_pound", 26, yabove=26),
            room(L, (100, 32, 65), (160, 23, 65), "pocket_props_records", 30),
            room(L, (-96, 30, 112), (-150, 22, 74), "pocket_props_reception", 30),
            room(L, (60, 22, -90), (40, 6, -170), "pocket_props_sublevel", 30, yabove=18),
            room(I, (-100, 32, 65), (-150, 25, 28), "pocket_props_ironhall", 30),
            room(I, (60, 14, -100), (0, 5, -150), "pocket_props_dojo", 30, yabove=18),
            room(P_["arena"], (-110, 10, 30), (-130, 4, 2), "pocket_props_camera", 30, yabove=48),
            room(P_["arena"], (20, 10, -95), (0, 2, -130), "pocket_props_barriers", 30, yabove=48),
            room(P_["rooftops"], (110, 110, 160), (20, 40, 20), "pocket_props_rooftops", 26),
        ]
    else:
        rooms = [
            room(A, (14, 36, 176), (0, 31, 146), "pocket_props2_statue", 30),
            room(A, (-120, 38, 104), (-192, 30, 62), "pocket_props2_class", 30),
            room(A, (10, 40, 62), (10, 32, -24), "pocket_props2_hall", 28),
            room(A, (70, 13, -128), (10, 5, -185), "pocket_props2_workshop", 30, yabove=22),
            room(I, (150, 34, 40), (194, 30, 70), "pocket_props2_trophies", 30),
            room(I, (-112, 30, 92), (-143, 22, 62), "pocket_props2_bench", 30),
            room(I, (0, 30, 84), (8, 24, 10), "pocket_props2_floor", 30),
            room(I, (40, 24, -96), (0, 8, -140), "pocket_props2_cage", 30, yabove=18),
            room(L, (14, 32, 4), (24, 27, -30), "pocket_props2_sealdoor", 30),
            room(P_["pound"], (-10, 16, 140), (0, 8, 192), "pocket_props2_dock", 30, yabove=26),
            room(P_["pound"], (-66, 13, 66), (-90, 8, 90), "pocket_props2_arch", 30, yabove=26),
            room(P_["station"], (-34, 14, -18), (-60, 4, -48), "pocket_props2_station", 30, yabove=40),
            room(P_["tower"], (24, 196, 14), (0, 194, -30), "pocket_props2_mast", 30),
            room(P_["arena"], (40, 26, -70), (0, 18, -172), "pocket_props2_stage", 28, yabove=60),
        ]
    code = (
        "import sys\nfrom PIL import Image\n"
        "ims=[Image.open(p).convert('RGB') for p in sys.argv[2:]]\n"
        "w,h=ims[0].size; cols=int(sys.argv[1].endswith('pocket_props2.png'))*2+2; rows=(len(ims)+cols-1)//cols\n"
        "sheet=Image.new('RGB',(cols*w,rows*h),(24,26,32))\n"
        "for i,im in enumerate(ims): sheet.paste(im.resize((w,h)),((i%cols)*w,(i//cols)*h))\n"
        "sheet.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-c", code, os.path.join(PREV, "pocket_props%s.png" % SUFFIX)] + shots, check=True)
    subprocess.run(["python3", "-c", code, os.path.join(PREV, "pocket_props%s_rooms.png" % SUFFIX)] + rooms + [rooms[0]][:0], check=True)
    for p_ in shots + rooms:
        os.remove(p_)
    print("preview:", os.path.join(PREV, "pocket_props%s.png" % SUFFIX), os.path.join(PREV, "pocket_props%s_rooms.png" % SUFFIX))
