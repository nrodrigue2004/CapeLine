"""The second icon set's symbols (gap-icons2, 2026-11-19): the open world and the books.

Same rules as symbols.py: ink.Sym primitives in a 0..100 box, cartoon shapes only, no text, no faces, no real
brands. Every incident (25), event (16) and contract type (12), the world markers (bosses, side quest givers,
sites, safehouses, beacons, the HQs, squadmates, the three pings), the Badge Book's groups, the collections,
the accolades, the Journal's tabs, the Rogues File's groups, the daily rewards, the weekly boards and the
movement buttons. Palette keys as in symbols.py (w cream, y gold, o orange, r red, s steel, k dark steel,
b blue, g green, v violet, c cyan, n brown, a light accent, d dark accent).
"""

import math

from ink import arcpts, arrow, bolt, flame, ngon, rot, star
from symbols import SYM, sparks, speedlines


def sym(name):
    def deco(f):
        assert name not in SYM, "symbol drawn twice: " + name
        SYM[name] = f
        return f

    return deco


# ---------------------------------------------------------------- small shared pieces
def robot_head(S, p, x=50, y=50, s=1.0, c=None, eye=None):
    """A boxy robot head: antenna, visor (no face), bolts at the sides."""
    S.group().line([(x, y - 30 * s), (x, y - 20 * s)], 4 * s, p["s"])
    S.circle(x, y - 31 * s, 5 * s, p["r"])
    S.group().rect(x - 24 * s, y - 20 * s, x + 24 * s, y + 20 * s, c or p["s"], 8 * s)
    S.rect(x - 30 * s, y - 6 * s, x - 24 * s, y + 8 * s, p["k"], 2)
    S.rect(x + 24 * s, y - 6 * s, x + 30 * s, y + 8 * s, p["k"], 2)
    S.group().rect(x - 17 * s, y - 9 * s, x + 17 * s, y + 5 * s, p["k"], 5 * s)
    S.rect(x - 12 * s, y - 5 * s, x + 12 * s, y + 1 * s, eye or p["c"], 3 * s)


def crate(S, p, x0, y0, x1, y1, c=None):
    S.group().rect(x0, y0, x1, y1, c or p["n"], 3)
    S.line([(x0 + 4, y0 + 4), (x1 - 4, y1 - 4)], 4, p["d"] if c else (120, 80, 45, 255))
    S.rect(x0, y0, x1, y0 + 5, p["y"], 2)


def drone(S, p, x, y, s=1.0, c=None):
    S.group().line([(x - 20 * s, y - 8 * s), (x + 20 * s, y - 8 * s)], 4 * s, p["k"])
    S.ell(x - 28 * s, y - 12 * s, x - 12 * s, y - 6 * s, p["w"])
    S.ell(x + 12 * s, y - 12 * s, x + 28 * s, y - 6 * s, p["w"])
    S.group().ell(x - 13 * s, y - 8 * s, x + 13 * s, y + 10 * s, c or p["s"])
    S.circle(x, y + 1 * s, 5 * s, p["r"])


def person(S, p, x, y, s=1.0, c=None):
    """A plain figure: round head and a rounded body (no face)."""
    S.group().rect(x - 11 * s, y, x + 11 * s, y + 24 * s, c or p["b"], 9 * s)
    S.group().circle(x, y - 8 * s, 8 * s, p["w"])


def hook(S, p, x, y, s=1.0):
    S.line([(x, y - 12 * s), (x, y + 4 * s)], 4 * s, p["s"])
    S.line(arcpts(x - 6 * s, y + 6 * s, 7 * s, 0, 200, 12), 5 * s, p["s"])


def cloud(S, p, x, y, s=1.0, c=None):
    for dx, dy, r in ((-14, 4, 11), (0, -4, 14), (14, 4, 11)):
        S.circle(x + dx * s, y + dy * s, r * s, c or p["w"])
    S.rect(x - 22 * s, y + 2 * s, x + 22 * s, y + 14 * s, c or p["w"], 6 * s)


def coin(S, p, x, y, r, c=None):
    S.group().circle(x, y, r, c or p["y"])
    S.circle(x, y, r * 0.62, p["o"])
    S.poly(star(x, y, r * 0.5, r * 0.22, 5), c or p["y"])


def vault_door(S, p, x, y, r, open_=False):
    S.group().rect(x - r - 6, y - r - 6, x + r + 6, y + r + 6, p["k"], 6)
    S.group().circle(x, y, r, p["s"])
    S.circle(x, y, r * 0.42, p["k"])
    for a in range(0, 360, 60):
        S.line(rot([(x, y - r * 0.35), (x, y - r * 0.85)], a, x, y), 4, p["w"])
    if open_:
        S.group().poly([(x + r + 2, y - r - 4), (x + r + 16, y - r + 4), (x + r + 16, y + r - 4), (x + r + 2, y + r + 4)],
                       p["s"])


# ================================================================= incidents (25)
@sym("i_heist")
def _i_heist(S, p):
    # a robot's loot sack: a tied bag with a coin spilling and the robot's claw on it
    S.poly([(30, 40), (70, 40), (84, 66), (76, 84), (24, 84), (16, 66)], p["n"])
    S.group().rect(38, 30, 62, 40, p["n"], 4)
    S.rect(34, 36, 66, 42, p["y"], 3)
    S.group().poly(star(50, 64, 11, 5, 5), p["y"])
    coin(S, p, 82, 30, 9)
    S.group().line([(12, 22), (28, 36)], 6, p["s"])
    S.line([(28, 36), (34, 30)], 5, p["s"])
    S.line([(28, 36), (30, 46)], 5, p["s"])


@sym("i_fire")
def _i_fire(S, p):
    S.rect(26, 30, 62, 88, p["s"], 3)
    for y in (40, 54, 68):
        for x in (32, 46):
            S.rect(x, y, x + 9, y + 8, p["c"], 1)
    S.group().poly(flame(66, 50, 50, 0.2), p["o"])
    S.group().poly(flame(68, 58, 30, 0.2), p["y"])
    S.poly(flame(34, 30, 26), p["o"])


@sym("i_tram")
def _i_tram(S, p):
    S.line([(50, 8), (50, 22)], 4, p["k"])
    S.line([(40, 8), (60, 8)], 4, p["k"])
    S.group().rect(26, 20, 74, 80, p["r"], 10)
    S.rect(32, 28, 68, 50, p["c"], 4)
    S.circle(36, 64, 5, p["y"])
    S.circle(64, 64, 5, p["y"])
    S.group().rect(20, 82, 80, 88, p["k"], 2)
    speedlines(S, p, 4, 46, 18, n=3, gap=10)


@sym("i_sign")
def _i_sign(S, p):
    S.line([(30, 86), (36, 52)], 5, p["k"])
    S.line([(70, 86), (64, 66)], 5, p["k"])
    S.group().poly(rot([(14, 22), (86, 22), (86, 56), (14, 56)], 14), p["y"])
    S.poly(rot([(22, 30), (78, 30), (78, 48), (22, 48)], 14), p["o"])
    S.group().poly(arrow(84, 70, 84, 94, 7, 10), p["r"])
    sparks(S, p, [(16, 70), (8, 56)], 5, p["w"])


@sym("i_chase")
def _i_chase(S, p):
    # a cat-burglar bot's paw print fleeing over a roof edge
    S.rect(14, 76, 86, 84, p["k"], 2)
    S.group().ell(40, 40, 72, 68, p["v"])
    for x, y in ((38, 30), (50, 22), (64, 22), (76, 30)):
        S.circle(x, y, 7, p["v"])
    speedlines(S, p, 6, 50, 32, n=3, gap=10)


@sym("i_cat")
def _i_cat(S, p):
    S.line([(50, 4), (50, 26)], 4, p["k"])
    S.line(arcpts(44, 28, 8, 0, 200, 12), 5, p["s"])
    # a cat's head (ears, no face) hanging from the hook, a tail curling
    S.group().poly([(28, 44), (32, 24), (44, 38), (56, 38), (68, 24), (72, 44)], p["o"])
    S.ell(26, 34, 74, 74, p["o"])
    S.line([(64, 72), (80, 84), (86, 72)], 6, p["o"])
    S.group().poly(star(50, 58, 8, 3.5, 5), p["y"])


@sym("i_raid")
def _i_raid(S, p):
    drone(S, p, 50, 46, 1.25, p["v"])
    S.group().arc(50, 50, 40, 0, 360, 4, p["r"], steps=48)
    for a in (0, 90, 180, 270):
        S.line(rot([(50, 4), (50, 18)], a), 4, p["r"])


@sym("i_vault")
def _i_vault(S, p):
    vault_door(S, p, 46, 50, 28, open_=True)
    S.group().poly(bolt(80, 30, 26, 20), p["y"])


@sym("i_crate")
def _i_crate(S, p):
    S.rect(16, 36, 84, 86, p["c"], 6)
    S.rect(16, 52, 84, 60, p["k"], 2)
    S.group().poly(ngon(50, 56, 12, 6, 0), p["y"])
    S.circle(50, 56, 5, p["w"])
    S.group().poly([(14, 34), (86, 34), (78, 18), (22, 18)], p["c"])
    sparks(S, p, [(84, 14), (16, 12)], 6)


@sym("i_comm")
def _i_comm(S, p):
    S.poly([(50, 18), (32, 88), (40, 88), (50, 48), (60, 88), (68, 88)], p["s"])
    S.line([(38, 64), (62, 64)], 4, p["s"])
    S.group().circle(50, 18, 7, p["r"])
    for r in (16, 26):
        S.arc(50, 18, r, -150, -30, 4, p["w"])
    S.group().poly(rot([(64, 52), (88, 52), (88, 59), (64, 59)], 45, 76, 55), p["r"])
    S.poly(rot([(64, 52), (88, 52), (88, 59), (64, 59)], -45, 76, 55), p["r"])


@sym("i_sniper")
def _i_sniper(S, p):
    S.rect(10, 70, 90, 90, p["k"], 3)
    S.rect(16, 60, 44, 70, p["s"], 2)
    S.group().circle(54, 40, 26, p["w"])
    S.circle(54, 40, 18, p["c"])
    S.group().line([(54, 14), (54, 66)], 4, p["r"])
    S.line([(28, 40), (80, 40)], 4, p["r"])
    S.circle(54, 40, 4, p["r"])


@sym("i_medic")
def _i_medic(S, p):
    S.rect(10, 34, 70, 74, p["w"], 6)
    S.poly([(70, 44), (84, 44), (92, 58), (92, 74), (70, 74)], p["w"])
    S.rect(76, 48, 86, 58, p["c"], 2)
    S.group().rect(32, 42, 44, 66, p["r"], 2)
    S.rect(26, 48, 50, 60, p["r"], 2)
    S.group().circle(26, 78, 8, p["k"])
    S.circle(76, 78, 8, p["k"])
    S.group().poly([(38, 24), (52, 16), (52, 32)], p["r"])


@sym("i_warband")
def _i_warband(S, p):
    robot_head(S, p, 50, 58, 1.1, p["r"], p["y"])
    S.group().poly([(30, 30), (36, 14), (44, 26), (50, 8), (56, 26), (64, 14), (70, 30)], p["y"])


@sym("i_mimic")
def _i_mimic(S, p):
    person(S, p, 24, 56, 0.85, p["s"])
    person(S, p, 50, 50, 0.95, p["v"])
    person(S, p, 76, 56, 0.85, p["s"])
    S.group().circle(62, 34, 14, p["c"])
    S.arc(62, 34, 14, 0, 360, 5, p["k"], steps=40)
    S.line([(72, 44), (86, 60)], 7, p["n"])


@sym("i_bomber")
def _i_bomber(S, p):
    for x, y, a in ((28, 34, -20), (56, 48, 0), (78, 28, 15)):
        S.group().circle(x, y + 10, 11, p["k"])
        S.poly(rot([(x - 6, y - 4), (x + 6, y - 4), (x, y + 2)], a, x, y + 10), p["s"])
        S.line([(x + 6, y + 2), (x + 12, y - 4)], 3, p["s"])
    S.group().poly(star(30, 82, 14, 6, 8), p["o"])
    S.poly(star(70, 84, 10, 4, 8), p["y"])


@sym("i_tow")
def _i_tow(S, p):
    S.line([(20, 6), (52, 34)], 4, p["s"])
    S.line(arcpts(48, 38, 7, 0, 200, 12), 5, p["s"])
    S.group().poly([(14, 70), (20, 54), (34, 46), (62, 46), (74, 56), (88, 60), (88, 72), (14, 72)], p["b"])
    S.rect(38, 50, 56, 58, p["c"], 2)
    S.group().circle(30, 74, 8, p["k"])
    S.circle(72, 74, 8, p["k"])
    S.group().poly(arrow(30, 24, 8, 24, 6, 10), p["y"])


@sym("i_scaffold")
def _i_scaffold(S, p):
    S.group()
    pts = rot([(22, 86), (22, 20)], 10, 22, 86) + rot([(78, 86), (78, 20)], 10, 78, 86)
    S.line(pts[:2], 6, p["s"])
    S.line(pts[2:], 6, p["s"])
    for y in (30, 52, 74):
        a = rot([(22, y), (78, y)], 10, 50, 86)
        S.line(a, 6, p["o"])
    S.line(rot([(22, 74), (78, 30)], 10, 50, 86), 4, p["s"])
    S.group().rect(10, 86, 90, 92, p["k"], 2)
    sparks(S, p, [(88, 22), (82, 10)], 6, p["w"])


@sym("i_craneload")
def _i_craneload(S, p):
    S.line([(8, 12), (92, 12)], 6, p["y"])
    S.line([(64, 12), (64, 28)], 3, p["k"])
    S.line([(64, 28), (68, 34)], 3, p["k"])
    S.group().poly(arrow(30, 24, 30, 92, 6, 10), p["r"])
    crate(S, p, 46, 38, 84, 72)
    S.group().line([(52, 28), (60, 20)], 3, p["w"])


@sym("i_water")
def _i_water(S, p):
    S.rect(8, 64, 92, 80, p["s"], 4)
    S.rect(42, 58, 58, 86, p["k"], 3)
    S.group()
    for x, a in ((50, 0), (36, -22), (64, 22)):
        S.poly([(50, 60), (x - 6, 20), (x + 6, 20)] if a == 0 else rot([(50, 60), (44, 22), (56, 22)], a, 50, 60),
               p["c"])
    for x, y in ((28, 18), (50, 10), (72, 18)):
        S.circle(x, y, 6, p["b"])


@sym("i_swarm")
def _i_swarm(S, p):
    drone(S, p, 28, 34, 0.8, p["v"])
    drone(S, p, 72, 30, 0.8, p["v"])
    drone(S, p, 50, 66, 0.9, p["r"])


@sym("i_shieldwall")
def _i_shieldwall(S, p):
    for x in (22, 50, 78):
        S.group().poly([(x - 14, 26), (x + 14, 26), (x + 14, 56), (x, 80), (x - 14, 56)], p["s"])
        S.poly([(x - 7, 34), (x + 7, 34), (x + 7, 54), (x, 66), (x - 7, 54)], p["b"])
    S.group().poly(arrow(50, 8, 50, 22, 4, 8), p["r"])


@sym("i_skyambush")
def _i_skyambush(S, p):
    S.poly([(14, 60), (62, 44), (86, 50), (62, 56)], p["s"])
    S.poly([(40, 52), (54, 24), (62, 26), (56, 50)], p["k"])
    S.poly([(40, 56), (54, 80), (62, 78), (56, 54)], p["k"])
    S.group().circle(78, 50, 4, p["r"])
    speedlines(S, p, 4, 32, 30, n=2, gap=8)
    S.group().arc(26, 22, 14, 0, 360, 4, p["r"], steps=36)
    S.line([(26, 4), (26, 40)], 3, p["r"])
    S.line([(8, 22), (44, 22)], 3, p["r"])


@sym("i_depot")
def _i_depot(S, p):
    crate(S, p, 12, 54, 46, 86)
    crate(S, p, 50, 54, 86, 86)
    crate(S, p, 30, 22, 66, 52)
    S.group().poly(arrow(84, 40, 84, 12, 6, 10), p["g"])


@sym("i_jam")
def _i_jam(S, p):
    S.poly([(40, 88), (48, 30), (52, 30), (60, 88)], p["s"])
    S.group().circle(50, 26, 8, p["c"])
    S.group().line([(10, 34), (18, 22), (26, 34), (34, 22)], 5, p["r"])
    S.line([(66, 22), (74, 34), (82, 22), (90, 34)], 5, p["r"])
    S.group().poly(star(50, 60, 12, 5, 8), p["y"])


@sym("i_suspect")
def _i_suspect(S, p):
    # a hero's domino mask under a magnifying glass, a crack across it
    S.poly([(10, 46), (30, 36), (50, 44), (70, 36), (90, 46), (80, 62), (60, 60), (50, 52), (40, 60), (20, 62)],
           p["r"])
    S.ell(22, 44, 36, 54, p["k"])
    S.ell(64, 44, 78, 54, p["k"])
    S.line([(46, 36), (52, 46), (48, 54)], 3, p["w"])
    S.group().arc(62, 50, 22, 0, 360, 6, p["k"], steps=48)
    S.line([(78, 66), (92, 82)], 9, p["n"])


# ================================================================= events (16)
@sym("e_meteors")
def _e_meteors(S, p):
    for x, y, s in ((30, 30, 13), (70, 46, 16), (40, 72, 11)):
        S.group().poly([(x - s * 2.2, y - s * 2.2), (x - s * 0.4, y - s), (x - s, y - s * 0.4)], p["o"])
        S.poly(ngon(x, y, s, 5, x), p["c"])
        S.poly(ngon(x + 1, y - 1, s * 0.45, 5, x), p["w"])


@sym("e_rampage")
def _e_rampage(S, p):
    robot_head(S, p, 46, 54, 1.15, p["s"], p["r"])
    S.group().poly(star(82, 26, 12, 5, 8), p["y"])
    S.poly(star(16, 80, 9, 4, 8), p["o"])


@sym("e_surge")
def _e_surge(S, p):
    S.poly([(8, 90), (8, 54), (24, 30), (50, 16), (78, 22), (88, 40), (72, 40), (62, 54), (72, 66), (92, 66), (92, 90)],
           p["b"])
    S.group().line(arcpts(60, 40, 16, 200, 380, 14), 5, p["w"])
    S.group().poly([(30, 70), (56, 70), (50, 80), (36, 80)], p["r"])
    S.line([(43, 70), (43, 56)], 3, p["k"])
    S.poly([(43, 56), (54, 64), (43, 64)], p["w"])


@sym("e_vault")
def _e_vault(S, p):
    for i, (x, y) in enumerate(((32, 72), (68, 72), (50, 50))):
        S.group().poly([(x - 18, y + 10), (x - 12, y - 8), (x + 12, y - 8), (x + 18, y + 10)], p["y"])
        S.line([(x - 8, y - 2), (x + 8, y - 2)], 3, p["w"])
    sparks(S, p, [(20, 30), (80, 26), (50, 16)], 7, p["w"])


@sym("e_train")
def _e_train(S, p):
    S.group().rect(14, 30, 62, 78, p["g"], 6)
    S.rect(20, 38, 40, 54, p["c"], 3)
    S.group().poly([(62, 42), (84, 50), (90, 78), (62, 78)], p["g"])
    S.rect(70, 22, 80, 46, p["k"], 2)
    for x in (26, 50, 76):
        S.group().circle(x, 80, 8, p["k"])
    S.group().poly(arrow(70, 12, 94, 12, 4, 8), p["r"])
    cloud(S, p, 34, 16, 0.6)


@sym("e_blackout")
def _e_blackout(S, p):
    S.ell(28, 12, 72, 62, p["k"])
    S.rect(38, 58, 62, 80, p["s"], 3)
    S.line([(38, 66), (62, 66)], 3, p["k"])
    S.line([(38, 73), (62, 73)], 3, p["k"])
    S.group().line([(46, 24), (54, 36), (44, 44), (52, 54)], 4, p["w"])
    S.group().poly(star(80, 22, 10, 4, 4), p["y"])


@sym("e_airship")
def _e_airship(S, p):
    S.ell(10, 16, 82, 50, p["s"])
    S.poly([(76, 30), (94, 16), (94, 50), (76, 38)], p["k"])
    S.line([(18, 33), (74, 33)], 3, p["k"])
    S.group().rect(32, 52, 58, 62, p["k"], 3)
    for x in (34, 54):
        S.group().poly(arrow(x, 66, x, 92, 6, 10), p["r"])


@sym("e_bridge")
def _e_bridge(S, p):
    S.line(arcpts(50, 92, 44, 180, 360, 24), 7, p["r"])
    S.rect(4, 58, 96, 66, p["s"], 2)
    for x in (22, 36, 50, 64, 78):
        y = 92 - math.sqrt(max(0, 44 ** 2 - (x - 50) ** 2))
        S.line([(x, y), (x, 58)], 3, p["r"])
    S.group().rect(14, 66, 22, 92, p["s"], 2)
    S.rect(78, 66, 86, 92, p["s"], 2)
    S.group().poly(star(50, 26, 11, 5, 8), p["y"])


@sym("e_stadium")
def _e_stadium(S, p):
    S.ell(8, 30, 92, 78, p["s"])
    S.ell(20, 38, 80, 64, p["g"])
    S.group().rect(36, 54, 64, 82, p["y"], 4)
    S.line(arcpts(50, 54, 10, 180, 360, 12), 5, p["k"])
    S.circle(50, 66, 4, p["k"])


@sym("e_plant")
def _e_plant(S, p):
    S.poly([(16, 88), (22, 54), (16, 22), (46, 22), (40, 54), (46, 88)], p["s"])
    S.poly([(52, 88), (56, 62), (52, 40), (74, 40), (70, 62), (74, 88)], p["s"])
    cloud(S, p, 32, 14, 0.5)
    S.group().poly(bolt(78, 44, 44, 15), p["y"])


@sym("e_parade")
def _e_parade(S, p):
    S.rect(12, 58, 88, 80, p["v"], 5)
    for x in (24, 40, 56, 72):
        S.poly([(x - 6, 58), (x + 6, 58), (x, 66)], p["y"])
    S.group().circle(26, 82, 7, p["k"])
    S.circle(74, 82, 7, p["k"])
    S.group().ell(36, 10, 64, 44, p["r"])
    S.line([(50, 44), (50, 58)], 3, p["k"])
    S.group().poly(arrow(70, 26, 94, 34, 4, 8), p["w"])


@sym("e_fog")
def _e_fog(S, p):
    S.line([(58, 14), (58, 76)], 7, p["s"])
    S.line([(46, 26), (70, 26)], 6, p["s"])
    S.circle(58, 10, 6, p["s"])
    S.line(arcpts(58, 56, 24, 20, 160, 14), 7, p["s"])
    S.group()
    cloud(S, p, 26, 60, 0.9)
    S.rect(6, 82, 64, 92, p["w"], 5)


@sym("e_double")
def _e_double(S, p):
    # two mirrored hero busts (no faces), one with a crack: the fake wearing your face
    for x, c in ((32, p["b"]), (68, p["r"])):
        S.group().rect(x - 18, 54, x + 18, 88, c, 12)
        S.group().circle(x, 40, 14, p["w"])
    S.line([(68, 26), (64, 38), (72, 44), (68, 54)], 3, p["k"])
    S.group().poly(bolt(50, 20, 22, 10), p["y"])


@sym("e_datatruck")
def _e_datatruck(S, p):
    S.rect(8, 36, 64, 76, p["s"], 5)
    S.poly([(64, 46), (82, 46), (92, 60), (92, 76), (64, 76)], p["s"])
    S.rect(70, 50, 82, 60, p["c"], 2)
    S.group().rect(22, 44, 50, 68, p["k"], 3)
    S.rect(26, 48, 46, 56, p["c"], 2)
    S.group().circle(24, 80, 8, p["k"])
    S.circle(76, 80, 8, p["k"])
    S.group().poly([(36, 14), (50, 8), (64, 14), (64, 26), (50, 34), (36, 26)], p["b"])


@sym("e_upvault")
def _e_upvault(S, p):
    S.rect(12, 14, 40, 90, p["v"], 3)
    for y in (22, 36, 50, 64):
        S.rect(18, y, 34, y + 8, p["y"], 1)
    S.group()
    vault_door(S, p, 66, 60, 20)
    S.group().arc(66, 60, 33, 200, 340, 4, p["y"])


@sym("e_crystals")
def _e_crystals(S, p):
    S.rect(10, 78, 90, 88, p["n"], 3)
    for x, h, w, c in ((30, 46, 11, p["c"]), (52, 62, 14, p["v"]), (72, 40, 10, p["c"])):
        S.group().poly([(x - w, 80), (x - w, 80 - h * 0.6), (x, 80 - h), (x + w, 80 - h * 0.6), (x + w, 80)], c)
        S.poly([(x, 80 - h), (x + w, 80 - h * 0.6), (x + w, 80), (x, 80)], p["w"])
    sparks(S, p, [(16, 30), (86, 22)], 6)


# ================================================================= contracts (12)
@sym("c_sweep")
def _c_sweep(S, p):
    drone(S, p, 34, 34, 0.9, p["v"])
    S.group().line([(54, 34), (80, 76)], 6, p["n"])
    S.poly([(70, 70), (92, 64), (96, 88), (76, 92)], p["y"])
    for x in (78, 84, 90):
        S.line([(x - 6, 74), (x - 2, 90)], 2, p["o"])


@sym("c_rescue")
def _c_rescue(S, p):
    S.arc(50, 50, 30, 0, 360, 16, p["w"], steps=48)
    S.group()
    for a in (45, 135, 225, 315):
        S.line(arcpts(50, 50, 30, a - 14, a + 14, 6), 16, p["r"])
    S.group().poly(star(50, 50, 10, 4, 5), p["y"])


@sym("c_core")
def _c_core(S, p):
    for r in (40, 30):
        S.arc(50, 50, r, -60, 60, 4, p["g"])
    S.group().rect(28, 26, 56, 74, p["s"], 6)
    S.rect(34, 32, 50, 68, p["c"], 4)
    S.circle(42, 50, 6, p["w"])


@sym("c_escort")
def _c_escort(S, p):
    S.rect(8, 44, 60, 76, p["y"], 5)
    S.poly([(60, 52), (78, 52), (88, 64), (88, 76), (60, 76)], p["y"])
    S.rect(66, 56, 78, 64, p["c"], 2)
    S.group().circle(24, 80, 8, p["k"])
    S.circle(72, 80, 8, p["k"])
    S.group().poly([(22, 12), (44, 12), (44, 30), (33, 40), (22, 30)], p["b"])
    S.poly(star(33, 24, 6, 2.6, 5), p["w"])


@sym("c_safe")
def _c_safe(S, p):
    S.rect(16, 16, 84, 80, p["k"], 6)
    S.rect(22, 22, 78, 74, p["s"], 4)
    S.group().circle(50, 48, 16, p["w"])
    for a in range(0, 360, 45):
        S.line(rot([(50, 34), (50, 38)], a, 50, 48), 3, p["k"])
    S.line([(50, 48), (58, 40)], 4, p["r"])
    S.group().rect(22, 80, 32, 88, p["k"], 2)
    S.rect(68, 80, 78, 88, p["k"], 2)


@sym("c_stakeout")
def _c_stakeout(S, p):
    S.rect(36, 30, 64, 44, p["k"], 4)
    for x in (30, 70):
        S.group().rect(x - 16, 30, x + 16, 64, p["k"], 8)
        S.circle(x, 66, 15, p["k"])
        S.circle(x, 66, 9, p["c"])
        S.circle(x - 3, 63, 3, p["w"])


@sym("c_bounty")
def _c_bounty(S, p):
    for r, c in ((40, p["r"]), (30, p["w"]), (20, p["r"]), (10, p["w"])):
        S.circle(50, 50, r, c)
    S.group().poly(star(50, 50, 9, 4, 5), p["y"])
    S.group().line([(74, 26), (92, 8)], 5, p["n"])
    S.poly([(70, 22), (80, 28), (72, 32)], p["s"])


@sym("c_demo")
def _c_demo(S, p):
    S.line([(14, 6), (58, 52)], 4, p["k"])
    S.group().circle(64, 60, 22, p["k"])
    S.circle(58, 54, 6, p["s"])
    S.group().poly([(10, 92), (10, 60), (22, 54), (30, 70), (30, 92)], p["s"])
    sparks(S, p, [(34, 50), (90, 34), (88, 86)], 7)


@sym("c_courier")
def _c_courier(S, p):
    S.poly([(4, 40), (28, 30), (34, 44)], p["w"])
    S.poly([(96, 40), (72, 30), (66, 44)], p["w"])
    S.group().rect(26, 34, 74, 78, p["n"], 4)
    S.rect(46, 34, 54, 78, p["y"], 1)
    S.rect(26, 50, 74, 56, p["y"], 1)
    speedlines(S, p, 4, 70, 22, n=2, gap=8)


@sym("c_defuse")
def _c_defuse(S, p):
    S.circle(40, 56, 26, p["k"])
    S.circle(32, 48, 6, p["s"])
    S.group().rect(32, 22, 48, 32, p["s"], 2)
    S.line([(40, 22), (52, 10), (64, 14)], 4, p["r"])
    S.group().line([(64, 52), (90, 78)], 5, p["s"])
    S.line([(64, 78), (90, 52)], 5, p["s"])
    S.circle(62, 50, 7, p["y"])
    S.circle(62, 80, 7, p["y"])


@sym("c_photo")
def _c_photo(S, p):
    S.rect(30, 22, 52, 32, p["k"], 3)
    S.rect(12, 30, 88, 78, p["k"], 8)
    S.group().circle(50, 54, 20, p["s"])
    S.circle(50, 54, 12, p["c"])
    S.circle(46, 50, 4, p["w"])
    S.group().poly(star(78, 22, 10, 4, 8), p["y"])


@sym("c_generator")
def _c_generator(S, p):
    S.arc(50, 56, 40, 0, 360, 5, p["g"], steps=48)
    S.group().rect(24, 34, 76, 76, p["o"], 6)
    S.rect(30, 40, 70, 54, p["k"], 3)
    S.group().poly(bolt(50, 60, 34, 15), p["y"])


# ================================================================= world markers
@sym("k_boss")
def _k_boss(S, p):
    S.poly([(20, 30), (12, 6), (34, 22)], p["s"])
    S.poly([(80, 30), (88, 6), (66, 22)], p["s"])
    robot_head(S, p, 50, 54, 1.3, p["k"], p["r"])


@sym("k_rustjaw")
def _k_rustjaw(S, p):
    S.rect(20, 14, 80, 52, p["o"], 8)
    S.rect(28, 26, 72, 38, p["k"], 4)
    S.circle(40, 32, 4, p["y"])
    S.circle(60, 32, 4, p["y"])
    S.group().rect(14, 54, 86, 82, p["s"], 6)
    for x in range(22, 84, 12):
        S.poly([(x, 54), (x + 10, 54), (x + 5, 44)], p["w"])


@sym("k_maw")
def _k_maw(S, p):
    S.ell(10, 26, 90, 86, p["v"])
    S.group().ell(22, 44, 78, 76, p["k"])
    for x in range(26, 76, 10):
        S.poly([(x, 46), (x + 8, 46), (x + 4, 56)], p["w"])
        S.poly([(x, 74), (x + 8, 74), (x + 4, 64)], p["w"])
    S.group().line([(50, 26), (56, 10), (68, 8)], 3, p["s"])
    S.circle(70, 8, 7, p["y"])


@sym("k_leviathan")
def _k_leviathan(S, p):
    S.line([(8, 66), (24, 52), (40, 66), (56, 52), (72, 60)], 14, p["c"])
    S.group().ell(62, 40, 94, 70, p["c"])
    S.rect(70, 26, 80, 44, p["s"], 2)
    S.group().circle(84, 54, 5, p["y"])
    S.group().line([(4, 84), (96, 84)], 4, p["b"])


@sym("k_warframe")
def _k_warframe(S, p):
    S.poly([(28, 34), (20, 8), (42, 26)], p["r"])
    S.poly([(72, 34), (80, 8), (58, 26)], p["r"])
    S.group().poly([(24, 30), (76, 30), (84, 60), (66, 88), (34, 88), (16, 60)], p["k"])
    S.poly([(30, 46), (70, 46), (64, 58), (36, 58)], p["r"])
    S.group().poly(ngon(50, 74, 8, 6), p["y"])


@sym("k_giver")
def _k_giver(S, p):
    S.poly([(14, 18), (86, 18), (86, 64), (48, 64), (30, 84), (32, 64), (14, 64)], p["w"])
    S.group().poly(star(50, 41, 18, 8, 5), p["y"])


@sym("k_site")
def _k_site(S, p):
    S.line([(28, 8), (28, 92)], 6, p["s"])
    S.group().poly([(30, 12), (86, 26), (30, 44)], p["y"])
    S.ell(14, 86, 42, 96, p["k"])


@sym("k_quest")
def _k_quest(S, p):
    S.poly([(50, 94), (26, 52), (26, 36), (38, 14), (62, 14), (74, 36), (74, 52)], p["y"])
    S.group().circle(50, 38, 14, p["w"])
    S.poly(star(50, 38, 9, 4, 5), p["o"])


@sym("k_safehouse")
def _k_safehouse(S, p):
    S.poly([(10, 50), (50, 14), (90, 50), (80, 50), (80, 88), (20, 88), (20, 50)], p["w"])
    S.group().rect(40, 60, 60, 88, p["n"], 3)
    S.group().poly([(38, 28), (62, 28), (62, 42), (50, 52), (38, 42)], p["g"])


@sym("k_beacon")
def _k_beacon(S, p):
    S.poly([(36, 92), (42, 40), (58, 40), (64, 92)], p["s"])
    S.group().rect(36, 26, 64, 42, p["k"], 3)
    S.circle(50, 26, 12, p["y"])
    S.group()
    for a in (-160, -125, -55, -20):
        S.line([(50 + 18 * math.cos(math.radians(a)), 26 + 18 * math.sin(math.radians(a))),
                (50 + 34 * math.cos(math.radians(a)), 26 + 34 * math.sin(math.radians(a)))], 5, p["y"])


@sym("k_hqhero")
def _k_hqhero(S, p):
    S.poly([(14, 22), (50, 8), (86, 22), (84, 56), (50, 92), (16, 56)], p["b"])
    S.group().poly([(26, 34), (50, 26), (74, 34), (72, 54), (50, 78), (28, 54)], p["w"])
    S.poly(star(50, 50, 16, 7, 5), p["y"])


@sym("k_hqvillain")
def _k_hqvillain(S, p):
    S.poly([(10, 82), (14, 30), (32, 52), (50, 12), (68, 52), (86, 30), (90, 82)], p["r"])
    S.group().rect(10, 74, 90, 88, p["k"], 3)
    S.group().poly(ngon(50, 56, 9, 4), p["y"])


@sym("k_squad")
def _k_squad(S, p):
    person(S, p, 28, 54, 0.8, p["g"])
    person(S, p, 72, 54, 0.8, p["v"])
    person(S, p, 50, 48, 1.0, p["b"])


@sym("k_help")
def _k_help(S, p):
    # a raised open hand with a call burst
    S.poly(star(50, 50, 46, 30, 10), p["y"])
    S.group().rect(36, 46, 64, 80, p["w"], 10)
    for x, h in ((38, 26), (46, 20), (54, 22), (62, 28)):
        S.rect(x - 3.5, h, x + 3.5, 54, p["w"], 3.5)
    S.rect(62, 52, 74, 60, p["w"], 4)


@sym("k_here")
def _k_here(S, p):
    S.ell(18, 74, 82, 92, p["k"])
    S.ell(28, 78, 72, 88, p["c"])
    S.group().poly(arrow(50, 8, 50, 78, 16, 22), p["c"])


@sym("k_danger")
def _k_danger(S, p):
    S.poly(star(50, 54, 40, 18, 10), p["o"])
    S.group().poly(bolt(50, 54, 52, 10), p["y"])


# ================================================================= badge groups and accolades
@sym("compass")
def _compass(S, p):
    S.circle(50, 50, 34, p["w"])
    S.group().poly([(50, 18), (58, 50), (50, 50)], p["r"])
    S.poly([(50, 18), (42, 50), (50, 50)], p["r"])
    S.poly([(50, 82), (58, 50), (42, 50)], p["s"])
    S.circle(50, 50, 5, p["k"])


@sym("brokenbot")
def _brokenbot(S, p):
    robot_head(S, p, 50, 56, 1.15, p["s"], p["k"])
    S.group().line([(46, 34), (54, 46), (46, 58), (56, 74)], 4, p["k"])
    S.group().poly(star(80, 24, 10, 4, 8), p["y"])


@sym("lifebuoy")
def _lifebuoy(S, p):
    _c_rescue(S, p)


@sym("book")
def _book(S, p):
    S.poly([(50, 28), (14, 20), (14, 76), (50, 84)], p["w"])
    S.poly([(50, 28), (86, 20), (86, 76), (50, 84)], p["w"])
    S.group()
    for y in (36, 48, 60):
        S.line([(22, y - 4), (42, y)], 3, p["s"])
        S.line([(58, y), (78, y - 4)], 3, p["s"])
    S.group().poly([(66, 22), (76, 20), (76, 44), (71, 38), (66, 44)], p["r"])


@sym("starfist")
def _starfist(S, p):
    S.poly(star(50, 50, 46, 26, 8), p["o"])
    S.group().rect(28, 34, 70, 72, p["w"], 10)
    for y in (40, 50, 60):
        S.line([(38, y), (66, y)], 3, p["s"])
    S.rect(22, 44, 34, 66, p["w"], 5)


@sym("trio")
def _trio(S, p):
    _k_squad(S, p)
    S.group().arc(50, 50, 42, 200, 340, 5, p["y"])


@sym("versus")
def _versus(S, p):
    S.poly(arrow(10, 80, 54, 36, 12, 18), p["b"])
    S.group().poly(arrow(90, 80, 46, 36, 12, 18), p["r"])
    S.group().poly(star(50, 30, 14, 6, 8), p["y"])


@sym("spotlight")
def _spotlight(S, p):
    S.poly([(40, 26), (60, 26), (90, 88), (10, 88)], p["y"])
    S.group().rect(34, 10, 66, 28, p["k"], 4)
    S.group().poly(star(50, 66, 14, 6, 5), p["w"])


@sym("crater")
def _crater(S, p):
    S.ell(8, 56, 92, 90, p["n"])
    S.ell(22, 62, 78, 84, p["k"])
    S.group().line([(50, 64), (50, 14)], 4, p["s"])
    S.poly([(52, 14), (84, 22), (52, 32)], p["r"])


@sym("tv")
def _tv(S, p):
    S.line([(38, 8), (50, 22), (62, 8)], 4, p["k"])
    S.group().rect(10, 22, 90, 80, p["k"], 10)
    S.rect(18, 30, 74, 72, p["c"], 6)
    S.poly(star(46, 51, 12, 5, 5), p["y"])
    S.circle(82, 40, 4, p["r"])
    S.circle(82, 58, 4, p["s"])


@sym("glowcompass")
def _glowcompass(S, p):
    S.poly(star(50, 50, 48, 36, 16), p["c"])
    _compass(S.group(), p)


@sym("rivets")
def _rivets(S, p):
    S.rect(12, 12, 88, 88, p["s"], 10)
    S.rect(26, 26, 74, 74, p["k"], 6)
    S.group()
    for x, y in ((20, 20), (80, 20), (20, 80), (80, 80), (50, 19), (50, 81), (19, 50), (81, 50)):
        S.circle(x, y, 4.5, p["w"])


@sym("thumbs")
def _thumbs(S, p):
    S.rect(28, 44, 70, 84, p["w"], 10)
    S.rect(32, 18, 46, 52, p["w"], 7)
    S.group()
    for y in (54, 64, 74):
        S.line([(48, y), (66, y)], 3, p["s"])
    S.group().rect(18, 46, 30, 86, p["b"], 3)


@sym("nib")
def _nib(S, p):
    S.poly([(50, 90), (24, 46), (36, 14), (64, 14), (76, 46)], p["k"])
    S.group().line([(50, 88), (50, 52)], 3, p["w"])
    S.circle(50, 48, 6, p["w"])
    S.group().ell(62, 74, 92, 92, p["k"])


@sym("guardspark")
def _guardspark(S, p):
    S.poly([(20, 18), (80, 18), (80, 50), (50, 88), (20, 50)], p["b"])
    S.group().poly(bolt(50, 48, 46, 15), p["y"])
    sparks(S, p, [(88, 14), (12, 70)], 7, p["c"])


@sym("hands")
def _hands(S, p):
    for a, c in ((0, p["b"]), (120, p["r"]), (240, p["g"])):
        S.group().poly(rot([(44, 50), (56, 50), (58, 14), (42, 14)], a), c)
        S.circle(*rot([(50, 12)], a)[0], 8, p["w"])
    S.group().circle(50, 50, 9, p["y"])


# ================================================================= collections (12)
@sym("comicbook")
def _comicbook(S, p):
    S.rect(20, 10, 80, 90, p["y"], 4)
    S.group().rect(26, 18, 74, 36, p["r"], 3)
    S.poly(star(50, 62, 20, 9, 8), p["w"])
    S.poly(bolt(50, 62, 20, 10), p["b"])


@sym("windkey")
def _windkey(S, p):
    S.rect(46, 44, 54, 90, p["s"], 3)
    S.group().circle(34, 30, 16, p["y"])
    S.circle(66, 30, 16, p["y"])
    S.circle(34, 30, 7, p["k"])
    S.circle(66, 30, 7, p["k"])
    S.group().rect(42, 24, 58, 46, p["y"], 4)


@sym("bell")
def _bell(S, p):
    S.poly([(20, 74), (28, 62), (30, 34), (40, 20), (60, 20), (70, 34), (72, 62), (80, 74)], p["y"])
    S.group().rect(16, 72, 84, 80, p["o"], 3)
    S.group().circle(50, 84, 7, p["s"])
    S.circle(50, 14, 6, p["s"])


@sym("amphora")
def _amphora(S, p):
    S.poly([(40, 12), (60, 12), (58, 24), (74, 40), (70, 70), (56, 90), (44, 90), (30, 70), (26, 40), (42, 24)],
           p["o"])
    S.line([(26, 32), (36, 44)], 4, p["n"])
    S.line([(74, 32), (64, 44)], 4, p["n"])
    S.group().line([(32, 56), (68, 56)], 4, p["c"])
    S.line([(34, 64), (66, 64)], 4, p["c"])


@sym("pigeon")
def _pigeon(S, p):
    S.ell(20, 40, 76, 76, p["s"])
    S.poly([(20, 56), (4, 46), (8, 64)], p["s"])
    S.group().circle(70, 38, 13, p["s"])
    S.poly([(82, 36), (94, 40), (82, 44)], p["y"])
    S.circle(73, 35, 3, p["k"])
    S.group().poly([(30, 52), (58, 46), (52, 64)], p["k"])
    S.group().line([(42, 76), (40, 88)], 3, p["o"])
    S.line([(54, 76), (56, 88)], 3, p["o"])


@sym("charm")
def _charm(S, p):
    S.arc(50, 14, 8, 0, 360, 4, p["s"], steps=24)
    S.group().poly(star(50, 56, 34, 15, 5), p["y"])
    S.poly(star(50, 56, 14, 6, 5), p["w"])


@sym("gearnut")
def _gearnut(S, p):
    S.poly(star(42, 46, 30, 22, 10), p["s"])
    S.circle(42, 46, 11, p["k"])
    S.group().poly(ngon(74, 74, 16, 6), p["y"])
    S.circle(74, 74, 6, p["k"])


@sym("plate")
def _plate(S, p):
    S.poly([(16, 20), (84, 20), (84, 60), (50, 88), (16, 60)], p["s"])
    S.group()
    for x, y in ((24, 28), (76, 28), (24, 56), (76, 56)):
        S.circle(x, y, 4, p["k"])
    S.group().line([(40, 30), (56, 48), (44, 62)], 4, p["k"])


@sym("core")
def _core(S, p):
    S.poly(star(50, 50, 44, 34, 12), p["v"])
    S.group().circle(50, 50, 24, p["k"])
    S.circle(50, 50, 16, p["r"])
    S.circle(45, 45, 5, p["w"])


@sym("rosette")
def _rosette(S, p):
    S.poly([(36, 54), (24, 92), (36, 84), (44, 94), (50, 58)], p["b"])
    S.poly([(64, 54), (76, 92), (64, 84), (56, 94), (50, 58)], p["b"])
    S.group().poly(star(50, 40, 32, 24, 14), p["y"])
    S.circle(50, 40, 15, p["w"])


@sym("locket")
def _locket(S, p):
    S.line(arcpts(50, 40, 26, 180, 360, 18), 3, p["s"])
    S.group().poly([(50, 88), (22, 58), (22, 44), (32, 34), (44, 36), (50, 44), (56, 36), (68, 34), (78, 44),
                    (78, 58)], p["r"])
    S.poly(star(50, 56, 9, 4, 5), p["y"])


@sym("crest")
def _crest(S, p):
    S.poly([(20, 14), (80, 14), (80, 54), (50, 88), (20, 54)], p["g"])
    S.group().rect(20, 34, 80, 44, p["w"], 1)
    S.group().poly(star(50, 58, 12, 5, 5), p["y"])
    S.poly([(30, 22), (40, 22), (40, 30), (30, 30)], p["y"])


# ================================================================= Journal tabs, Rogues File groups, daily, boards
@sym("j_quests")
def _j_quests(S, p):
    S.rect(18, 20, 82, 82, p["w"], 4)
    S.group().rect(12, 14, 88, 24, p["n"], 5)
    S.rect(12, 78, 88, 88, p["n"], 5)
    S.group().line([(28, 36), (44, 52), (36, 66), (60, 62)], 3, p["r"])
    S.poly(star(68, 62, 9, 4, 5), p["y"])


@sym("j_rep")
def _j_rep(S, p):
    S.rect(46, 18, 54, 86, p["s"], 2)
    S.rect(26, 82, 74, 90, p["s"], 2)
    S.rect(14, 24, 86, 30, p["s"], 3)
    S.group().line([(22, 30), (14, 56)], 2, p["k"])
    S.line([(22, 30), (30, 56)], 2, p["k"])
    S.ell(8, 52, 36, 64, p["b"])
    S.group().line([(78, 30), (70, 50)], 2, p["k"])
    S.line([(78, 30), (86, 50)], 2, p["k"])
    S.ell(64, 46, 92, 58, p["r"])


@sym("j_perks")
def _j_perks(S, p):
    S.poly(ngon(50, 50, 38, 8, 22.5), p["v"])
    S.group().poly(star(50, 50, 24, 10, 5), p["y"])


@sym("j_rogues")
def _j_rogues(S, p):
    S.poly([(10, 26), (36, 26), (42, 34), (90, 34), (90, 84), (10, 84)], p["n"])
    S.group().rect(24, 40, 62, 72, p["w"], 2)
    S.circle(43, 52, 8, p["s"])
    S.rect(33, 60, 53, 72, p["s"], 4)
    S.group().poly(rot([(58, 50), (92, 50), (92, 60), (58, 60)], -25, 75, 55), p["r"])


@sym("j_medal")
def _j_medal(S, p):
    S.poly([(30, 8), (44, 8), (56, 40), (42, 40)], p["b"])
    S.poly([(70, 8), (56, 8), (44, 40), (58, 40)], p["r"])
    S.group().circle(50, 62, 26, p["y"])
    S.poly(star(50, 62, 15, 7, 5), p["w"])


@sym("j_mentor")
def _j_mentor(S, p):
    # a teacher's mortarboard over a shining star
    S.poly([(10, 34), (50, 18), (90, 34), (50, 50)], p["k"])
    S.group().rect(30, 40, 70, 58, p["k"], 3)
    S.line([(86, 34), (86, 56)], 3, p["y"])
    S.circle(86, 58, 4, p["y"])
    S.group().poly(star(50, 74, 14, 6, 5), p["y"])


@sym("j_showdown")
def _j_showdown(S, p):
    S.poly(bolt(32, 50, 70, 10), p["b"])
    S.poly(bolt(68, 50, 70, -10), p["r"])
    S.group().poly(star(50, 50, 12, 5, 8), p["y"])


@sym("r_fake")
def _r_fake(S, p):
    S.poly([(14, 30), (50, 14), (86, 30), (80, 64), (50, 88), (20, 64)], p["y"])
    S.group().poly([(50, 14), (86, 30), (80, 64), (50, 88), (56, 64), (46, 50), (56, 34)], p["s"])
    S.circle(68, 48, 6, p["r"])
    S.group().ell(26, 42, 40, 52, p["k"])


@sym("r_villain")
def _r_villain(S, p):
    S.poly([(10, 44), (22, 14), (36, 36), (64, 36), (78, 14), (90, 44), (78, 70), (22, 70)], p["v"])
    S.group().ell(24, 44, 44, 56, p["k"])
    S.ell(56, 44, 76, 56, p["k"])
    S.group().poly([(30, 76), (70, 76), (50, 92)], p["r"])


@sym("d_credits")
def _d_credits(S, p):
    for y in (78, 68, 58):
        S.group().ell(18, y - 8, 62, y + 8, p["y"])
    coin(S, p, 66, 36, 22)


@sym("d_renown")
def _d_renown(S, p):
    # a laurel of leaves round a gold star
    for side in (-1, 1):
        for i in range(5):
            a = math.radians(100 + i * 28)
            x, y = 50 + side * -32 * math.cos(a), 52 + 32 * math.sin(a) * -1 + 8
            S.ell(x - 7, y - 4.5, x + 7, y + 4.5, p["g"])
    S.group().poly(star(50, 46, 22, 10, 5), p["y"])


@sym("d_dust")
def _d_dust(S, p):
    S.poly([(14, 86), (30, 62), (50, 54), (70, 62), (86, 86)], p["v"])
    sparks(S, p, [(50, 30), (28, 40), (74, 36)], 11, p["c"])
    sparks(S, p, [(40, 14), (64, 16)], 6, p["w"])


@sym("d_title")
def _d_title(S, p):
    S.poly([(4, 40), (20, 40), (20, 66), (4, 66), (12, 53)], p["r"])
    S.poly([(96, 40), (80, 40), (80, 66), (96, 66), (88, 53)], p["r"])
    S.group().rect(16, 32, 84, 60, p["y"], 4)
    S.line([(28, 46), (72, 46)], 4, p["o"])


@sym("d_got")
def _d_got(S, p):
    S.poly([(12, 52), (26, 38), (42, 54), (76, 18), (90, 32), (42, 82)], p["g"])


@sym("b_mvp")
def _b_mvp(S, p):
    S.poly([(14, 74), (10, 30), (30, 48), (50, 18), (70, 48), (90, 30), (86, 74)], p["y"])
    S.group().rect(14, 70, 86, 84, p["o"], 3)
    S.group()
    for x in (30, 50, 70):
        S.circle(x, 77, 4, p["r"])


@sym("b_trophy")
def _b_trophy(S, p):
    S.arc(24, 36, 12, 90, 270, 5, p["y"])
    S.arc(76, 36, 12, -90, 90, 5, p["y"])
    S.group().poly([(24, 18), (76, 18), (70, 50), (56, 60), (44, 60), (30, 50)], p["y"])
    S.group().rect(44, 58, 56, 74, p["o"], 1)
    S.rect(30, 74, 70, 86, p["n"], 3)
    S.group().poly(star(50, 36, 10, 4, 5), p["w"])


# ================================================================= the movement buttons
@sym("v_leap")
def _v_leap(S, p):
    S.rect(16, 80, 84, 88, p["k"], 3)
    S.line(arcpts(50, 84, 30, 180, 270, 10), 5, p["w"])
    S.group().poly(arrow(50, 54, 70, 12, 12, 16), p["y"])
    S.group()
    for x in (26, 36):
        S.line([(x, 70), (x - 6, 78)], 3, p["w"])


@sym("v_boost")
def _v_boost(S, p):
    for i, x in enumerate((24, 46, 68)):
        S.group().poly([(x - 14, 26), (x + 4, 26), (x + 22, 50), (x + 4, 74), (x - 14, 74), (x + 4, 50)],
                       p["o"] if i < 2 else p["y"])


@sym("v_down")
def _v_down(S, p):
    S.poly(arrow(50, 8, 50, 70, 14, 20), p["y"])
    S.group().rect(10, 76, 90, 86, p["k"], 3)
    sparks(S, p, [(20, 66), (80, 66)], 8, p["w"])


@sym("r_robot")
def _r_robot(S, p):
    robot_head(S, p, 50, 54, 1.3, p["s"], p["c"])
