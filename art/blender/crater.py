# crater.py: the Crater's blasted Crane Industries lab as Blender meshes (gap-wrecks, 2026-11-19; lore step 9, nate's
# lore: the lab blew up in the battle where the old heroes fell). WorldGen.craterRuins builds the ruins from plain
# boxes (Config.World.crater); each look here is built over the exact boxes it stands in for (art/export/crater/
# layout.json from `lune run art/crater/layout.luau`), and once ReplicatedStorage.Art.Crater holds a look's meshes
# the game hides those boxes (kept, so every collision is as before; Shared.CraterArtKit, CityBuilder) and draws the
# meshes. Cartoon kit style: chunky bevelled shapes, bright comic colours under the soot, one baked texture set a
# look (art/blender/hbake.py), low poly for phones. Original designs only (the Crane C, the old heroes' relics).
# Looks (each in its placement's own frame: x, up, z from its middle; front at -z):
# * CraterWall1..7: a broken white lab wall (panel seams, a navy band, a burnt foot) with a ragged top and broken
#   ends that only ever stick out past the box (never into it), rebar poking out, cracks and soot; walls 3 and 5
#   carry the Crane C (a navy plate and a white C) on their outer face
# * CraterChunk: a fallen chunk of wall at each wall's foot (ghost)
# * CraterTank1..3: a cracked containment tank: steel plinth and bolts, a see-through glass shell with a shattered
#   rim, the faint Spark glow still swirling inside, a big glass shard on the floor, cables
# * CraterTower1..2: a toppled lab tower: the white shaft lying on its side (window bands, navy corner posts,
#   floor lines, a broken end with rebar), its navy crown broken off with a dish and a dead beacon, the lattice mast
# * CraterHusk: an old Crane robot husk from the battle (the blocky humanoid frame, shell burnt away to the metal,
#   ribs, spine and a dead core; its metal head rolled off: a skull with a dark visor slit, never a face)
# * CraterCape, CraterShield, CraterHelmet: the old heroes' relics: a torn red cape tied to a bent rebar, a cracked
#   blue shield emblem with a gold chevron half sunk in the dirt, a dented gold helmet half buried
# * CraterBit*: loose debris each device scatters by its preset (Config.World.crater.art.bits): rubble, pipes, a
#   toppled console, panel shards (ghosts, under 2 studs tall)
# Output: art/export/Crater.fbx (textures embedded), art/export/crater/<Look>_{Color,Normal,Roughness,Metalness}.png,
# src/config/CraterArt.luau; with --preview art/preview/crater.png (the bowl from the rim, the lab walls, tanks and
# towers, the relics close up, the husks and bits) and art/preview/crater_relics.png.
# Run: lune run art/crater/layout.luau && $HOME/tools/bpyenv/bin/python art/blender/crater.py [--preview] [--fast]
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401

kit.reset()

import ruinkit as rk  # noqa: E402
from ruinkit import paint, lump, teeth, bars, nut, arc, jag_tube, sheet, shard, ragged  # noqa: E402
from studs import mesh, LOOKS, C, S, T, TOR, turn, shift  # noqa: E402
from vkit import rbox  # noqa: E402
import studs  # noqa: E402

FAST = "--fast" in sys.argv
LAY = json.load(open(os.path.join(kit.ROOT, "export", "crater", "layout.json")))
OUT = os.path.join(kit.ROOT, "export", "crater")

# ---------------------------------------------------------------- colours (the game palette's, comic-bright)
WALL = (236, 238, 242)
NAVY = (36, 48, 110)
BAND = (60, 120, 210)
CONC = (128, 124, 120)
DARKC = (78, 74, 72)
STEEL = (130, 138, 150)
DSTEEL = (70, 74, 84)
RUST = (160, 82, 52)
GLASSC = (190, 236, 255)
SPARK = (110, 210, 255)
GOLD = (240, 190, 60)
RED = (200, 36, 44)
BLUE = (40, 90, 200)
CABLE = (40, 40, 46)
YELLOW = (240, 200, 50)
DIRT = (92, 80, 70)
HUSK = (96, 104, 112)
SCREEN = (24, 30, 40)


def places(look):
    return [p for p in LAY["places"] if p["look"] == look]


FRAMES = {}
SLACK = 1.5  # meshes may reach this far past their placement (CraterArtKit.check)


def frame_of(look):
    p = places(look)[0]
    FRAMES[look] = p["size"]
    return p


def floor_of(p):
    return LAY["floorY"] - p["at"][1]


def B(b):
    """A layout box (in its placement's frame) as its exact block."""
    sx, sy, sz = b["size"]
    x, y, z = b["at"]
    if b.get("shape") == "cylinder":
        ob = C(min(sx, sz) / 2, sy, x, y, z, segs=20)
    elif b.get("shape") == "ball":
        s = max(sx, sy, sz)
        ob = S(s / 2, x, y, z, segs=20, rings=12)
    else:
        ob = rbox(sx, sy, sz, 0, 0, 0, bev=0)
        if b.get("ry"):
            turn(ob, "up", b["ry"])
        ob = shift(ob, studs.rb(x, y, z))
    return ob


def body(look, parts, extra=()):
    mesh(look, look + "Body", parts, WALL, "SmoothPlastic")
    for (suffix, prts, rgb, mat, alpha) in extra:
        if prts:
            mesh(look, look + suffix, prts, rgb, mat, alpha)


# ================================================================ the broken lab walls
def wall(i):
    look = "CraterWall%d" % i
    p = frame_of(look)
    bx = p["boxes"]
    main = [b for b in bx if b["kind"] == "building"]
    w0 = max(main, key=lambda b: b["size"][0] * b["size"][1])
    jag = [b for b in main if b is not w0][0]
    L, H, TH = w0["size"]
    x0, y0, z0 = w0["at"]
    bot, top = y0 - H / 2, y0 + H / 2
    seed = 100 * i
    parts = []
    # the wall itself, exactly its box, in white panels; a navy band near the top and a burnt plinth
    core = rbox(L, H, TH, x0, y0, z0, bev=0.06)
    parts.append(paint(core, WALL, pat="labpanel+soot"))
    for s_ in (-1, 1):
        parts.append(paint(rbox(L - 0.2, 0.7, 0.08, x0, top - 1.6, z0 + s_ * (TH / 2 + 0.03), bev=0.02), BAND, "Metal"))
        parts.append(paint(rbox(L - 0.1, 1.1, 0.14, x0, bot + 0.55, z0 + s_ * (TH / 2 + 0.06), bev=0.03), DARKC, "Concrete", "concrete+soot"))
    # the stub on top (the jag box) and the ragged edge along both
    jx, jy, jz = jag["at"]
    jw, jh, _ = jag["size"]
    parts.append(paint(rbox(jw, jh, TH, jx, jy, z0, bev=0.06), WALL, pat="labpanel+soot"))
    for t in teeth(x0 - L / 2, x0 + L / 2, top, z0, TH, seed + 1, 1.3):
        parts.append(paint(t, CONC, "Concrete", "concrete+soot"))
    for t in teeth(jx - jw / 2, jx + jw / 2, jy + jh / 2, z0, TH, seed + 2, 1.0):
        parts.append(paint(t, CONC, "Concrete", "concrete+soot"))
    # broken ends: chunks hanging off each end (outside the box) and rebar out of them
    rnd = random.Random(seed + 3)
    rods = []
    for s_ in (-1, 1):
        ex = x0 + s_ * L / 2
        y = bot + 0.6
        while y < top - 0.3:
            h = rnd.uniform(0.8, 2.2)
            w = rnd.uniform(0.25, 0.8)
            parts.append(paint(lump(w * 2, min(h, top - y), TH * 0.9, ex + s_ * (w - 0.05) * 0.6, y + min(h, top - y) / 2, z0,
                                    rnd.randint(0, 9999), 0.1), CONC, "Concrete", "concrete+soot"))
            y += h
        rods += bars(4, [(ex, bot + H * f, z0 + rnd.uniform(-0.4, 0.4)) for f in (0.3, 0.5, 0.7, 0.9)],
                     (s_, 0.25, 0), 1.6, seed + 10 + s_)
    rods += bars(5, [(x0 + rnd.uniform(-L / 2 + 1, L / 2 - 1), top + 0.2, z0) for _ in range(5)], (0, 1, 0), 1.4, seed + 20)
    for r_ in rods:
        parts.append(paint(r_, RUST, "Metal", "rust"))
    # chips knocked out of both faces (they sit proud of the face, never into it)
    for k in range(6):
        s_ = 1 if k % 2 else -1
        cx = x0 + rnd.uniform(-L / 2 + 1.5, L / 2 - 1.5)
        cy = rnd.uniform(bot + 2, top - 1.5)
        parts.append(paint(lump(rnd.uniform(0.6, 1.4), rnd.uniform(0.4, 1.0), 0.18, cx, cy, z0 + s_ * (TH / 2 + 0.08),
                                rnd.randint(0, 9999), 0.06), DARKC, "Concrete", "concrete+soot"))
    # the Crane C (original): a navy plate and a white C opening to the outside viewer's right
    plate = [b for b in bx if b["kind"] == "prop" and abs(b["size"][2] - 0.3) < 1e-3]
    if plate:
        pb = plate[0]
        px, py, pz = pb["at"]
        sz2 = pb["size"][0]
        side = 1 if pz > z0 else -1
        parts.append(paint(rbox(sz2 + 0.4, sz2 + 0.4, 0.4, px, py, pz + side * 0.05, bev=0.18), NAVY, "Metal"))
        parts.append(paint(rbox(sz2 + 0.8, sz2 + 0.8, 0.2, px, py, pz - side * 0.05, bev=0.08), GOLD, "Foil"))
        gap = 0 if side == 1 else 180
        rad = sz2 / 2 - 1.6
        cc = arc(px, py, pz + side * 0.32, rad, gap + 42, gap + 318, 0.62, n=22)
        parts.append(paint(cc, (250, 250, 250), "SmoothPlastic"))
        for k_ in range(4):  # bolts in the plate's corners
            parts.append(paint(nut(px + (sz2 / 2 - 0.3) * (1 if k_ % 2 else -1), py + (sz2 / 2 - 0.3) * (1 if k_ // 2 else -1),
                                   pz + side * 0.27, 0.16, axis="z"), STEEL, "Metal"))
    body(look, parts)


# ================================================================ a fallen chunk of wall (ghost, at each wall's foot)
def chunk():
    look = "CraterChunk"
    p = frame_of(look)
    sx, sy, sz = p["size"]
    parts = [paint(lump(sx * 0.92, sy * 0.85, sz * 0.88, 0, -sy * 0.07, 0, 7, 0.2, 0.1, (0, 0, 6)), WALL, pat="labpanel+soot")]
    parts.append(paint(lump(sx * 0.4, sy * 0.5, sz * 0.5, sx * 0.25, sy * 0.15, -sz * 0.15, 8, 0.12), CONC, "Concrete", "concrete+soot"))
    parts += [paint(r_, RUST, "Metal", "rust") for r_ in bars(3, [(sx * 0.4, 0, 0), (-sx * 0.3, 0.2, 0.3)], (0.6, 0.7, 0), 1.0, 9)]
    parts.append(paint(rbox(sx * 0.9, 0.3, 0.06, 0, sy * 0.15, -sz * 0.45, bev=0.02), BAND, "Metal"))
    body(look, parts)


# ================================================================ the cracked containment tanks
def tank(i):
    look = "CraterTank%d" % i
    p = frame_of(look)
    bx = p["boxes"]
    shellb = [b for b in bx if b.get("shape") == "cylinder" and b["kind"] == "prop"][0]
    glowb = [b for b in bx if b["kind"] == "glow"][0]
    shardb = [b for b in bx if b.get("shape") != "cylinder"][0]
    r = shellb["size"][0] / 2
    h = shellb["size"][1]
    sx_, sy_, sz_ = shellb["at"]
    bot, top = sy_ - h / 2, sy_ + h / 2
    rnd = random.Random(30 + i)
    parts, glass, glow = [], [], []
    # the steel plinth and a lid ring knocked off onto the floor
    parts.append(paint(C(r + 0.45, 0.9, sx_, bot + 0.45, sz_, segs=28), DSTEEL, "DiamondPlate"))
    parts.append(paint(TOR(r + 0.25, 0.18, sx_, bot + 0.95, sz_, segs=28, csegs=6), YELLOW, "Metal", "hazard"))
    for k in range(10):
        a = 2 * math.pi * k / 10
        parts.append(paint(nut(sx_ + math.cos(a) * (r + 0.3), bot + 0.92, sz_ + math.sin(a) * (r + 0.3), 0.14), STEEL, "Metal"))
    # four ribs up the glass (steel), each snapped at a different height (all above the shell's top)
    for k in range(4):
        a = 2 * math.pi * (k + 0.5) / 4
        hh = top + rnd.uniform(0.1, 0.9)
        parts.append(paint(rbox(0.32, hh - bot - 0.9, 0.32, sx_ + math.cos(a) * (r + 0.05), (bot + 0.9 + hh) / 2,
                                sz_ + math.sin(a) * (r + 0.05), bev=0.05), STEEL, "Metal", "metal+soot"))
    # cables from the plinth out over the floor
    for k in range(3):
        a = rnd.uniform(0, 2 * math.pi)
        x1, z1 = sx_ + math.cos(a) * (r + 3.0), sz_ + math.sin(a) * (r + 3.0)
        pts = [(sx_ + math.cos(a) * (r + 0.4), bot + 0.5, sz_ + math.sin(a) * (r + 0.4)),
               (sx_ + math.cos(a) * (r + 1.5), bot + 0.25, sz_ + math.sin(a) * (r + 1.5)), (x1, bot + 0.12, z1)]
        parts.append(paint(T(pts, 0.13, segs=6), CABLE, "SmoothPlastic", "rubber"))
    # the shell: glass from the plinth up to a shattered rim (never below the box's top, so its collider never
    # shows), plus shards that stuck in the rim
    tops = [top + max(0.0, rnd.uniform(-0.2, 1.6)) for _ in range(28)]
    glass.append(jag_tube(r, 0.16, bot + 0.9, lambda k: tops[k]))
    # the big shard on the floor (its box) and a few small ones
    hx, hy, hz = shardb["at"]
    glass.append(shard(ragged(7, 1.5, 1.4, 40 + i), 0.25, hx, hy - 0.4, hz, ry=shardb["ry"], tilt=(62, 8)))
    for k in range(4):
        a = rnd.uniform(0, 2 * math.pi)
        d = r + rnd.uniform(0.8, 2.2)
        glass.append(shard(ragged(5, 0.5, 0.35, 50 + i * 7 + k), 0.12, sx_ + math.cos(a) * d, bot + 0.1, sz_ + math.sin(a) * d,
                           ry=rnd.uniform(0, 360), tilt=(88, 0)))
    # the faint Spark glow left inside: a soft column (the glow box) and a swirl up through it
    gr = glowb["size"][0] / 2
    gy, gh = glowb["at"][1], glowb["size"][1]
    glow.append(C(gr * 0.85, gh * 0.9, sx_, gy - gh * 0.05, sz_, segs=16, r2=gr * 0.3))
    pts = []
    for k in range(25):
        t = k / 24
        a = t * 4 * math.pi + i
        pts.append((sx_ + math.cos(a) * gr * 0.9, gy - gh / 2 + 0.6 + t * gh * 0.95, sz_ + math.sin(a) * gr * 0.9))
    glow.append(T(pts, [0.12 + 0.08 * math.sin(k / 24 * math.pi) for k in range(25)], segs=6))
    for k in range(5):  # crystals of spent Spark round the plinth floor
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0.3, r - 0.6)
        cr = C(0.28, rnd.uniform(0.6, 1.3), 0, 0, 0, segs=5, r2=0.0)
        turn(cr, "x", rnd.uniform(-25, 25))
        glow.append(shift(cr, studs.rb(sx_ + math.cos(a) * d, bot + 1.3, sz_ + math.sin(a) * d)))
    body(look, parts, [("Glass", glass, GLASSC, "Glass", 0.55), ("Glow", glow, SPARK, "Neon", 0.45)])


# ================================================================ the toppled lab towers
def tower(i):
    look = "CraterTower%d" % i
    p = frame_of(look)
    bx = p["boxes"]
    shaftb = [b for b in bx if b["kind"] == "building" and b["color"] == bx[0]["color"]][0]
    others = [b for b in bx if b is not shaftb]
    crownb = max(others, key=lambda b: b["size"][0])
    mastb = [b for b in others if b is not crownb][0]
    w, h, L = shaftb["size"]
    x0, y0, z0 = shaftb["at"]
    bot, top = y0 - h / 2, y0 + h / 2
    rnd = random.Random(60 + i)
    parts, glass = [], []
    # the shaft lying on its side: exactly its box in white panels
    parts.append(paint(rbox(w, h, L, x0, y0, z0, bev=0.1), WALL, pat="labpanel+soot"))
    # the navy corner posts along its length (proud of the box) and the floor lines (every 6)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            parts.append(paint(rbox(0.9, 0.9, L - 0.6, x0 + sx_ * (w / 2 - 0.25), y0 + sy_ * (h / 2 - 0.25), z0, bev=0.12), NAVY, "Metal", "metal+soot"))
    n = int(L / 6)
    for k in range(1, n):
        zz = z0 - L / 2 + k * L / n
        for sx_ in (-1, 1):
            parts.append(paint(rbox(0.12, h - 0.4, 0.5, x0 + sx_ * (w / 2 + 0.04), y0, zz, bev=0.03), NAVY, "Metal"))
        parts.append(paint(rbox(w - 0.4, 0.12, 0.5, x0, top + 0.04, zz, bev=0.03), NAVY, "Metal"))
        # window bands on the top and the two long sides (dark glass), a few smashed
        for (gx, gy_, gw, gh_) in ((0, top + 0.05, w - 2.4, 0.06), (-(w / 2 + 0.05), y0, 0.06, h - 2.4), (w / 2 + 0.05, y0, 0.06, h - 2.4)):
            if rnd.random() < 0.82:
                glass.append(rbox(gw if gw > 0.1 else 0.08, gh_ if gh_ > 0.1 else 0.08, L / n - 1.6,
                                  x0 + gx, gy_, zz - L / n / 2, bev=0))
    # the broken top end (+z, where the crown snapped off): jagged chunks and rebar outside the box
    ez = z0 + L / 2
    for k in range(9):
        cx = x0 + rnd.uniform(-w / 2 + 1, w / 2 - 1)
        cy = rnd.uniform(bot + 1, top - 1)
        parts.append(paint(lump(rnd.uniform(1.2, 2.6), rnd.uniform(1.2, 2.6), rnd.uniform(0.5, 1.2), cx, cy, ez + 0.4,
                                rnd.randint(0, 99999), 0.2), CONC, "Concrete", "concrete+soot"))
    for r_ in bars(10, [(x0 + rnd.uniform(-w / 2, w / 2), rnd.uniform(bot + 1, top - 1), ez) for _ in range(10)], (0, 0, 1), 2.4, 70 + i):
        parts.append(paint(r_, RUST, "Metal", "rust"))
    # the base end (-z): its torn footing
    parts.append(paint(lump(w + 1.2, h * 0.55, 2.2, x0, bot + h * 0.27, z0 - L / 2 - 0.6, 80 + i, 0.3), DARKC, "Concrete", "concrete+soot"))
    # the crown broken off past the top (its box): a navy plate cap with a dish and a dead beacon
    cx, cy, cz = crownb["at"]
    cw, ch, cl = crownb["size"]
    cr = crownb["ry"]
    cap = rbox(cw, ch, cl, 0, 0, 0, bev=0.25)
    turn(cap, "up", cr)
    parts.append(paint(shift(cap, studs.rb(cx, cy, cz)), NAVY, "Metal", "plates"))
    dish = S(2.6, 0, 0, 0, sc=(1, 0.38, 1), segs=18, rings=8)
    kit.cut(dish, (0, 0, 1), keep_positive=True)
    turn(dish, "z", 70)
    turn(dish, "up", cr)
    parts.append(paint(shift(dish, studs.rb(cx + 1.2, cy + ch / 2 + 0.6, cz)), (220, 224, 232), "Metal"))
    parts.append(paint(C(0.5, 1.4, cx - 2, cy + ch / 2 + 0.7, cz + 2, segs=10), DSTEEL, "Metal"))
    beacon = [S(0.55, cx - 2, cy + ch / 2 + 1.6, cz + 2, segs=10, rings=6)]
    # the lattice mast lying beside it (its box): three rails and zigzag braces
    mx, my, mz = mastb["at"]
    ml = mastb["size"][2]
    mry = math.radians(mastb["ry"])
    ux, uz = math.sin(mry), math.cos(mry)  # its local z in the placement frame (Roblox turn)
    rails = [(0.45, 0.0), (-0.45, 0.0), (0.0, 0.62)]
    def mp(t, ox, oy):
        d = (t - 0.5) * ml
        return (mx + ux * d + uz * ox, my - 0.3 + oy, mz + uz * d - ux * ox)
    for (ox, oy) in rails:
        parts.append(paint(T([mp(0, ox, oy), mp(1, ox, oy)], 0.09, segs=5), (220, 60, 50), "Metal", "metal+soot"))
    for k in range(18):
        a, b2 = rails[k % 3], rails[(k + 1) % 3]
        parts.append(paint(T([mp(k / 18, *a), mp((k + 1) / 18, *b2)], 0.05, segs=4), (220, 60, 50), "Metal"))
    body(look, parts, [("Glass", glass, (40, 60, 90), "Glass", 0.25), ("Lamp", beacon, (120, 30, 30), "SmoothPlastic", 0.0)])


# ================================================================ an old Crane robot husk (shared by the five)
def husk():
    look = "CraterHusk"
    p = frame_of(look)
    bx = p["boxes"]
    tb = max(bx, key=lambda b: b["size"][2])
    hb = [b for b in bx if b is not tb][0]
    tx, ty, tz = tb["at"]
    tw, th, tl = tb["size"]
    fl = floor_of(p)
    rnd = random.Random(90)
    parts, glow = [], []
    # lying on its back along z (head end +z): the chest plate box (exactly the torso box's footprint, its top a
    # broken shell over the ribs), hips at -z, shoulders and arm stubs either side, leg stubs off the hips
    chest = rbox(tw, th * 0.62, tl * 0.62, tx, fl + th * 0.31, tz + tl * 0.19, bev=0.2)
    parts.append(paint(chest, HUSK, "Metal", "plates+soot"))
    hips = rbox(tw * 0.86, th * 0.7, tl * 0.36, tx, fl + th * 0.35, tz - tl * 0.31, bev=0.2)
    parts.append(paint(hips, HUSK, "Metal", "rust"))
    # the open chest: ribs, spine and a dead core in it, shell plates peeled back
    for k in range(5):
        zz = tz + tl * 0.02 + k * tl * 0.085
        parts.append(paint(arc(tx, fl + th * 0.62, zz, tw * 0.36, 0, 180, 0.13, n=10), STEEL, "Metal", "metal+soot"))
    parts.append(paint(rbox(0.6, 0.5, tl * 0.62, tx, fl + th * 0.66, tz + tl * 0.19, bev=0.1), DSTEEL, "Metal"))
    parts.append(paint(C(0.75, 0.25, tx, fl + th * 0.9, tz + tl * 0.22, segs=14), (60, 64, 72), "Metal"))
    for s_ in (-1, 1):
        flap = rbox(tw * 0.45, 0.2, tl * 0.42, 0, 0, 0, bev=0.05)
        turn(flap, "z", s_ * 48)
        parts.append(paint(shift(flap, studs.rb(tx + s_ * tw * 0.62, fl + th * 0.75, tz + tl * 0.22)), HUSK, "Metal", "plates+soot"))
        # shoulder ball and an arm stub lying beside the body
        parts.append(paint(S(0.75, tx + s_ * (tw / 2 + 0.2), fl + th * 0.5, tz + tl * 0.38, segs=12, rings=8), DSTEEL, "Metal"))
        arm = [(tx + s_ * (tw / 2 + 0.5), fl + th * 0.42, tz + tl * 0.32), (tx + s_ * (tw / 2 + 1.0), fl + 0.5, tz - tl * 0.05),
               (tx + s_ * (tw / 2 + 1.1), fl + 0.4, tz - tl * 0.32)]
        parts.append(paint(T(arm, [0.42, 0.38, 0.34], segs=8), STEEL, "Metal", "metal+soot"))
        parts.append(paint(lump(0.9, 0.6, 1.1, arm[-1][0], fl + 0.35, arm[-1][2] - 0.5, 91 + s_, 0.08), DSTEEL, "Metal"))
        # a leg stub off the hips, snapped at the thigh
        leg = [(tx + s_ * tw * 0.24, fl + th * 0.35, tz - tl * 0.45), (tx + s_ * tw * 0.3, fl + 0.55, tz - tl / 2 - 0.9)]
        parts.append(paint(T(leg, [0.55, 0.5], segs=8), STEEL, "Metal", "metal+soot"))
        parts.append(paint(lump(1.0, 0.9, 0.5, leg[-1][0], fl + 0.5, leg[-1][2] - 0.2, 95 + s_, 0.14), HUSK, "Metal", "rust"))
        parts += [paint(r_, (200, 140, 40), "SmoothPlastic", "rubber") for r_ in bars(2, [leg[-1]], (s_ * 0.3, 0.1, -1), 0.9, 97 + s_, r=0.05)]
    # cables out of the neck toward the head
    hx, hy, hz = hb["at"]
    for k, col in enumerate(((200, 50, 40), (240, 200, 50), (60, 110, 220))):
        pts = [(tx + (k - 1) * 0.35, fl + th * 0.55, tz + tl * 0.5), (tx + (k - 1) * 0.5 + (hx - tx) * 0.4, fl + 0.4, (tz + tl * 0.5 + hz) / 2),
               (hx - 0.6 + k * 0.3, hy - 0.5, hz - 0.9)]
        parts.append(paint(T(pts, 0.1, segs=5), col, "SmoothPlastic", "rubber"))
    # the head rolled off (its box): a metal skull, a dark visor slit, a dented jaw plate; never a face
    hs = hb["size"][0]
    sk = rbox(hs * 0.92, hs * 0.88, hs * 0.92, 0, 0, 0, bev=0.45)
    turn(sk, "up", hb["ry"])
    turn(sk, "x", 22)
    parts.append(paint(shift(sk, studs.rb(hx, hy, hz)), (150, 90, 60), "Metal", "rust"))
    jaw = rbox(hs * 0.7, hs * 0.22, hs * 0.5, 0, -hs * 0.38, -hs * 0.2, bev=0.08)
    turn(jaw, "up", hb["ry"])
    turn(jaw, "x", 22)
    parts.append(paint(shift(jaw, studs.rb(hx, hy, hz)), DSTEEL, "Metal"))
    visor = rbox(hs * 0.7, hs * 0.14, 0.12, 0, hs * 0.08, -hs * 0.47, bev=0.03)
    turn(visor, "up", hb["ry"])
    turn(visor, "x", 22)
    glow.append(shift(visor, studs.rb(hx, hy, hz)))
    body(look, parts, [("Visor", glow, (24, 26, 34), "SmoothPlastic", 0.0)])


# ================================================================ the old heroes' relics (original designs)
def cape():
    look = "CraterCape"
    p = frame_of(look)
    bx = p["boxes"]
    rod = [b for b in bx if b.get("shape") == "cylinder"][0]
    cloth = sorted([b for b in bx if b is not rod], key=lambda b: -b["size"][1])
    rx, ry_, rz = rod["at"]
    rh = rod["size"][1]
    bot, top = ry_ - rh / 2, ry_ + rh / 2
    parts = []
    # the rebar: rusty, bent near the top, out of a rubble lump
    rodm = T([(rx, bot - 0.3, rz), (rx, bot + rh * 0.55, rz), (rx + 0.25, top - 1.2, rz - 0.1), (rx + 0.7, top + 0.3, rz - 0.35)],
             [0.42, 0.4, 0.38, 0.34], segs=10)
    parts.append(paint(rodm, RUST, "Metal", "rust"))
    for k in range(5):
        a = 2 * math.pi * k / 5
        parts.append(paint(lump(1.4, 0.9, 1.2, rx + math.cos(a) * 0.9, bot + 0.35, rz + math.sin(a) * 0.9, 200 + k, 0.2), CONC, "Concrete", "concrete+soot"))
    # the cape tied on just under the bend (gold clasp), hanging and lifting in the wind, torn along its hem
    c0 = cloth[0]
    cx, cy, cz = c0["at"]
    ch, cw = c0["size"][1], c0["size"][2]
    rnd = random.Random(210)
    hem = [rnd.uniform(0.0, 0.28) for _ in range(9)]

    def capef(u, v):  # u across (z), v down
        z = cz + (u - 0.5) * cw * (0.55 + 0.45 * v)
        d = v * ch * (1 - hem[min(8, int(u * 8.99))] * (v ** 3))
        y = cy + ch / 2 - d
        x = cx + 0.15 + 0.35 * math.sin(u * math.pi * 3 + v * 2) * v + 0.6 * v * v
        return (x, y, z)
    parts.append(paint(sheet(capef, 10, 10, 0.1), RED, "Fabric", "fabric+soot"))
    parts.append(paint(TOR(0.45, 0.14, cx, cy + ch / 2, cz, axis="x", segs=14, csegs=6), GOLD, "Foil"))
    parts.append(paint(S(0.3, cx + 0.12, cy + ch / 2, cz, segs=10, rings=6), GOLD, "Foil"))
    # the torn scrap caught lower down (its box)
    c1 = cloth[1]
    sx_, sy_, sz_ = c1["at"]
    sh, sw = c1["size"][1], c1["size"][2]
    parts.append(paint(sheet(lambda u, v: (sx_ + 0.2 * math.sin(u * 6), sy_ + sh / 2 - v * sh * (1 - 0.3 * u * v), sz_ + (u - 0.5) * sw), 6, 6, 0.08),
                       RED, "Fabric", "fabric+soot"))
    body(look, parts)


def shield():
    look = "CraterShield"
    p = frame_of(look)
    bx = p["boxes"]
    sb = max(bx, key=lambda b: b["size"][0] * b["size"][2])
    sx_, sy_, sz_ = sb["at"]
    w, h, d = sb["size"]
    fl = floor_of(p)
    parts = []
    # a rounded heater shield lying tilted, sunk into the dirt, cracked in two along the scratch (28 degrees)
    out = []
    for k in range(24):
        t = k / 24
        a = math.pi * 2 * t
        x = math.cos(a) * w / 2
        z = math.sin(a) * d / 2
        if z > 0:
            z *= 1 - 0.35 * (abs(x) / (w / 2)) ** 2
        else:
            z = z * 1.05 + (abs(x) / (w / 2)) ** 1.5 * 0.0
        out.append((x, z))
    half = math.radians(28)
    ca, sa = math.cos(half), math.sin(half)
    for side in (1, -1):
        poly = [(x, z) for (x, z) in out if (x * sa - z * ca) * side >= -0.05]
        if len(poly) < 3:
            continue
        gap = 0.18 * side
        plate = vkit_plate(poly, h * 0.6)
        shift(plate, studs.rb(sx_ + sa * gap, sy_ - 0.05 + side * 0.08, sz_ - ca * gap))
        turn(plate, "x", side * 3, pivot=(sx_, sy_, sz_))
        parts.append(paint(plate, BLUE, "Metal", "metal+soot"))
    parts.append(paint(TOR(w * 0.47, 0.18, sx_, sy_ + h * 0.3, sz_, segs=28, csegs=6), GOLD, "Foil"))
    # the gold chevron (original) raised on its face
    chev = []
    cz0 = sz_ + 0.2
    pts = [(sx_ - w * 0.27, sy_ + h * 0.42, cz0 + d * 0.16), (sx_, sy_ + h * 0.42, cz0 - d * 0.14), (sx_ + w * 0.27, sy_ + h * 0.42, cz0 + d * 0.16)]
    for a_, b_ in ((pts[0], pts[1]), (pts[1], pts[2])):
        bar_ = T([a_, b_], 0.36, segs=6)
        rk.bend(bar_, lambda x, y, z: (x, sy_ + h * 0.42 + (y - sy_ - h * 0.42) * 0.45, z))
        chev.append(paint(bar_, GOLD, "Foil"))
    parts += chev
    # dirt piled over its edges
    rnd = random.Random(300)
    for k in range(9):
        a = rnd.uniform(0, 2 * math.pi)
        parts.append(paint(lump(rnd.uniform(0.9, 1.8), rnd.uniform(0.3, 0.6), rnd.uniform(0.8, 1.6), sx_ + math.cos(a) * w * 0.48,
                                fl + 0.15, sz_ + math.sin(a) * d * 0.48, 310 + k, 0.15), DIRT, "Concrete", "concrete"))
    body(look, parts)


def vkit_plate(poly, thick):
    """A flat plate from an (x, z) outline, thick tall (centred on 0)."""
    return studs.rings_mesh([[(x, -thick / 2, z) for (x, z) in poly], [(x, thick / 2, z) for (x, z) in poly]])


def helmet():
    look = "CraterHelmet"
    p = frame_of(look)
    bx = p["boxes"]
    ball = [b for b in bx if b.get("shape") == "ball"][0]
    vb = [b for b in bx if b is not ball][0]
    hx, hy, hz = ball["at"]
    R = ball["size"][0] / 2
    fl = floor_of(p)
    parts, visor = [], []
    dome = S(R * 1.02, 0, 0, 0, segs=24, rings=14)
    rk.bend(dome, lambda x, y, z: (x, y - (0.35 if (x > 0.6 and y > 0.8) else 0.0) * max(0.0, 1 - ((x - 1.4) ** 2 + (y - 1.6) ** 2) / 1.2), z))
    turn(dome, "z", 14)
    parts.append(paint(shift(dome, studs.rb(hx, hy, hz)), GOLD, "Foil", "foil+soot"))
    # the crest along its top and the cheek guards, a dark cracked visor band at the front (its box)
    crest = T([(hx, hy + R * 0.2, hz + R * 0.95), (hx + 0.1, hy + R * 1.05, hz + R * 0.1), (hx + 0.1, hy + R * 0.95, hz - R * 0.7)],
              [0.25, 0.42, 0.3], segs=8)
    parts.append(paint(crest, RED, "Metal"))
    for s_ in (-1, 1):
        parts.append(paint(lump(0.5, R * 0.9, R * 0.8, hx + s_ * R * 0.92, hy - R * 0.2, hz - R * 0.3, 400 + s_, 0.06), GOLD, "Foil"))
    vx, vy, vz = vb["at"]
    vw, vh, _ = vb["size"]
    v_ = rbox(vw * 1.05, vh * 1.1, 0.5, 0, 0, 0, bev=0.2)
    rk.bend(v_, lambda x, y, z: (x, y, z - 0.25 * (x / vw) ** 2 * 4))
    visor.append(shift(v_, studs.rb(vx, vy + 0.1, vz - 0.05)))
    parts.append(paint(rbox(vw * 0.08, vh * 1.1, 0.2, vx + vw * 0.15, vy + 0.1, vz - 0.4, bev=0.02), (230, 230, 240), "SmoothPlastic"))
    # the rubble mound it is half buried in
    rnd = random.Random(410)
    for k in range(10):
        a = 2 * math.pi * k / 10 + rnd.uniform(-0.2, 0.2)
        parts.append(paint(lump(rnd.uniform(1.0, 1.8), rnd.uniform(0.5, 1.0), rnd.uniform(1.0, 1.6), hx + math.cos(a) * R * 0.95,
                                fl + 0.3, hz + math.sin(a) * R * 0.95, 420 + k, 0.2), DIRT, "Concrete", "concrete"))
    body(look, parts, [("Visor", visor, (20, 24, 34), "Glass", 0.15)])


# ================================================================ loose debris (each device by its preset; ghosts)
BITS = {"CraterBitRubble": (3.0, 1.4, 2.6), "CraterBitPipes": (4.0, 1.2, 2.4), "CraterBitConsole": (2.8, 1.8, 2.2),
        "CraterBitPlates": (3.2, 0.8, 3.0)}
ORIGINS = {}


def bit(look):
    sx, sy, sz = BITS[look]
    FRAMES[look] = [sx, sy, sz]
    ORIGINS[look] = (0.0, sy / 2, 0.0)  # built from its foot on the floor; the frame's middle is half up
    rnd = random.Random(hash(look) % 1000)
    parts = []
    if look == "CraterBitRubble":
        for k in range(5):
            parts.append(paint(lump(rnd.uniform(0.8, 1.5), rnd.uniform(0.5, 1.0), rnd.uniform(0.7, 1.3), rnd.uniform(-0.8, 0.8),
                                    0.4, rnd.uniform(-0.6, 0.6), 500 + k, 0.18), CONC if k % 2 else WALL, "Concrete", "concrete+soot"))
        parts += [paint(r_, RUST, "Metal", "rust") for r_ in bars(3, [(0, 0.5, 0)], (0.4, 1, 0.2), 0.8, 510)]
    elif look == "CraterBitPipes":
        parts.append(paint(T([(-1.8, 0.3, -0.6), (-0.4, 0.3, -0.4), (0.6, 0.7, 0.2), (1.8, 0.3, 0.9)], 0.3, segs=10), STEEL, "Metal", "metal+soot"))
        parts.append(paint(TOR(0.32, 0.08, -0.4, 0.3, -0.4, axis="x", segs=12, csegs=5), YELLOW, "Metal"))
        parts.append(paint(TOR(0.7, 0.09, 0.8, 0.12, -0.6, segs=16, csegs=5), CABLE, "SmoothPlastic", "rubber"))
        parts.append(paint(TOR(0.5, 0.09, 0.8, 0.28, -0.6, segs=16, csegs=5), CABLE, "SmoothPlastic", "rubber"))
    elif look == "CraterBitConsole":
        con = rbox(2.4, 1.0, 1.4, 0, 0, 0, bev=0.12)
        turn(con, "z", 18)
        parts.append(paint(shift(con, studs.rb(0, 0.55, 0)), WALL, "SmoothPlastic", "plastic+soot"))
        scr = rbox(2.0, 0.08, 1.0, 0, 0, 0, bev=0.02)
        turn(scr, "z", 18)
        parts.append(paint(shift(scr, studs.rb(-0.05, 1.08, 0)), SCREEN, "SmoothPlastic"))
        for k in range(6):
            parts.append(paint(rbox(0.25, 0.1, 0.25, -0.7 + k * 0.28, 0.12, -0.9, bev=0.02), (200, 60, 60) if k % 3 == 0 else (60, 140, 230), "SmoothPlastic"))
        parts.append(paint(T([(1.1, 0.3, 0.3), (1.6, 0.08, 0.6), (1.3, 0.08, 1.0)], 0.07, segs=5), CABLE, "SmoothPlastic", "rubber"))
    else:
        for k in range(5):
            pl = shard(ragged(6, rnd.uniform(0.5, 0.9), rnd.uniform(0.4, 0.8), 600 + k), 0.12, rnd.uniform(-1.1, 1.1), 0.12 + k * 0.05,
                       rnd.uniform(-1.0, 1.0), ry=rnd.uniform(0, 360), tilt=(86, rnd.uniform(-10, 10)))
            parts.append(paint(pl, WALL if k % 2 else BAND, "SmoothPlastic", "labpanel+soot" if k % 2 else None))
    body(look, parts)


# ================================================================ build, bake, fit, export
for i in range(1, 8):
    wall(i)
chunk()
for i in range(1, 4):
    tank(i)
for i in range(1, 3):
    tower(i)
husk()
cape()
shield()
helmet()
for b_ in BITS:
    bit(b_)

ALL = sorted(LOOKS)


def res_of(look, objs):
    if look.startswith("CraterTower"):
        return 1024
    if look.startswith("CraterBit") or look == "CraterChunk":
        return 256
    return 512


MAPPED = rk.bake_all(ALL, OUT, res_of, fast=FAST)
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "CraterArt.luau"))
tris, total, count = rk.write_fit(FIT, [
    "-- GENERATED by art/blender/crater.py: do not edit by hand.",
    "-- The Crater's blasted Crane lab in Blender meshes (ReplicatedStorage.Art.Crater; Shared.CraterArtKit, WorldGen's",
    "-- craterRuins placements, CityBuilder; the CraterBit looks are each device's loose debris, CraterDecor): look -> its",
    "-- frame (the box of its placement, studs x, up, z) and its meshes: each mesh's size and its centre from the frame's",
    "-- middle, its colour, material, transparency, maps (a baked texture set in its SurfaceAppearance) and triangles.",
], ALL, FRAMES, MAPPED, ORIGINS)
print("crater: %d looks, %d meshes, %d tris" % (len(ALL), count, total))
for look in ALL:
    print("  %-16s %5d tris  %d meshes" % (look, sum(tris[n] for n in LOOKS[look]), len(LOOKS[look])))
rk.export_fbx(os.path.join(kit.ROOT, "export", "Crater.fbx"), ALL, MAPPED)

# ================================================================ previews
if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402

    PREV = os.path.join(kit.ROOT, "preview")
    vp._scene(FAST, (640, 400) if FAST else (1200, 720))
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    CX, CZ = LAY["centre"]

    def W(x, y, z):  # world studs to the preview's (the Crater's middle at 0)
        return (x - CX, y, z - CZ)

    def scene(meshes=True):
        for b in LAY["boxes"]:
            if meshes and b.get("art") and b["art"] in LOOKS:
                continue
            sx, sy, sz = b["size"]
            x, y, z = W(*b["at"])
            if b.get("shape") == "cylinder":
                o = kit.cyl("c", min(sx, sz) / 2, min(sx, sz) / 2, sy, at=studs.rb(x, y, z), segs=48)
            elif b.get("shape") == "ball":
                o = kit.sphere("s", r=max(sx, sy, sz) / 2, at=studs.rb(x, y, z))
            else:
                o = kit.box("b", sx, sz, sy, at=(0, 0, 0))
                o.rotation_euler = (0, 0, math.radians(b.get("ry", 0)))
                o.location = studs.rb(x, y, z)
            kind = {"rock": "Slate", "field": "Slate", "glow": "Neon"}.get(b["kind"], "SmoothPlastic")
            alpha = 0.5 if b["color"] == [200, 235, 255] or b["kind"] == "glow" else 0.0
            if b["kind"] == "mark":
                rgb = (40, 34, 30)
            elif b["kind"] in ("rock", "field"):
                rgb = (118, 104, 94) if b["kind"] == "rock" else (96, 86, 80)
            else:
                rgb = b["color"]
            o.data.materials.append(vp._mat_flat(tuple(rgb), kind, alpha))
            vp._keep(o)
        if meshes:
            for p in LAY["places"]:
                x, y, z = W(*p["at"])
                rk.placed(p["look"], MAPPED, (x, y, z), p["ry"], vp._keep)
            for b in LAY["bits"]:
                rk.placed(b["look"], MAPPED, W(*b["at"]), b["ry"], vp._keep)

    shots = []
    vp._ground(1400, (104, 112, 96))
    scene()
    for (frm, to, lens, name) in (((-150, 70, -190), (0, 0, 0), 26, "crater_bowl"), ((40, 14, -78), (10, 6, 0), 26, "crater_lab"),
                                  ((-102, 7, 2), (-76, 1.5, 3), 26, "crater_relics"), ((-55, 18, -125), (-80, 4, -50), 30, "crater_tower"),
                                  ((70, 7, 18), (86, 1, 31), 30, "crater_husk")):
        vp._camera(frm, to, lens=lens)
        out = os.path.join(PREV, name + ".png")
        kit.render(out)
        shots.append(out)
    vp._clear()
    # the looks one by one in a row (the small ones)
    vp._ground(300, (110, 104, 98))
    x = -16.0
    for look in ("CraterHusk", "CraterCape", "CraterShield", "CraterHelmet", "CraterChunk") + tuple(BITS):
        f = FRAMES[look]
        rk.placed(look, MAPPED, (x + f[0] / 2, 0.0 if look in BITS else f[1] / 2, 0), 0, vp._keep)
        x += f[0] + 1.5
    vp._camera((x / 2 - 16 + 4, 14, -30), (x / 2 - 16, 2, 0), lens=34)
    out = os.path.join(PREV, "crater_looks.png")
    kit.render(out)
    shots.append(out)
    vp._clear()
    code = (
        "import sys\nfrom PIL import Image\n"
        "ims=[Image.open(p).convert('RGB') for p in sys.argv[2:]]\n"
        "w,h=ims[0].size; cols=2; rows=(len(ims)+1)//2\n"
        "sheet=Image.new('RGB',(cols*w,rows*h),(24,26,32))\n"
        "for i,im in enumerate(ims): sheet.paste(im.resize((w,h)),((i%cols)*w,(i//cols)*h))\n"
        "sheet.save(sys.argv[1])\n"
    )
    import subprocess  # noqa: E402
    subprocess.run(["python3", "-c", code, os.path.join(PREV, "crater.png")] + shots, check=True)
    for p_ in shots:
        if not p_.endswith("crater_relics.png"):
            os.remove(p_)
    print("preview:", os.path.join(PREV, "crater.png"))
