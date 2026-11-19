"""The icon set's symbols (gap-icons, 2026-11-19): one drawing per ability verb, weapon, mobility, gadget,
action and gear slot, as ink.Sym primitives in a 0..100 box (the symbol fills about 18..82).

Each function takes (S, p): S the Sym to draw into, p the palette (w cream white, a the path's light
accent, d the path's dark tone, y gold, o orange, r red, s steel, k dark steel, b blue, g green, v violet,
c cyan, n brown). Cartoon shapes only: no text, no faces, no real brands or weapons (blasters are sci-fi).
"""

import math

from ink import arcpts, arrow, bolt, crescent, flame, ngon, rot, star

SYM = {}


def sym(name):
    def deco(f):
        SYM[name] = f
        return f

    return deco


def speedlines(S, p, x0, y0, x1, n=3, gap=7, w=3.2):
    for i in range(n):
        y = y0 + (i - (n - 1) / 2) * gap
        S.line([(x0, y), (x1 - i * 4, y)], w, p["w"])


def sparks(S, p, pts, r=5, c=None):
    for x, y in pts:
        S.poly(star(x, y, r, r * 0.38, 4, -90), c or p["y"])


def ground(S, p, y=76, x0=22, x1=78, c=None):
    S.rect(x0, y, x1, y + 6, c or p["n"], 3)


# ---------------------------------------------------------------- projectiles and beams
@sym("zap")
def _zap(S, p):
    S.poly(bolt(52, 50, 66, 18), p["y"])


@sym("orb")
def _orb(S, p):
    S.poly([(20, 44), (52, 36), (52, 64), (20, 56)], p["a"])
    S.group().circle(58, 50, 17, p["w"])
    S.circle(53, 45, 6, p["a"])


@sym("shard")
def _shard(S, p):
    S.poly(rot([(18, 50), (42, 40), (84, 50), (42, 60)], -20), p["w"])
    S.group().poly(rot([(42, 40), (84, 50), (42, 50)], -20), p["c"])
    speedlines(S, p, 14, 66, 34, n=2, gap=8)


@sym("beam")
def _beam(S, p):
    S.rect(30, 40, 86, 60, p["w"], 10)
    S.group().rect(36, 46, 86, 54, p["c"], 4)
    S.group().poly(star(28, 50, 18, 8, 6, 0), p["w"])


@sym("beamdown")
def _beamdown(S, p):
    S.rect(38, 14, 62, 72, p["w"], 10)
    S.group().rect(45, 14, 55, 72, p["y"], 4)
    S.group().poly(star(50, 74, 20, 8, 8, 0), p["y"])


@sym("lance")
def _lance(S, p):
    S.poly(rot([(14, 46), (64, 46), (64, 40), (88, 50), (64, 60), (64, 54), (14, 54)], -35), p["w"])
    S.group().poly(rot([(64, 40), (88, 50), (64, 50)], -35), p["y"])


@sym("fireball")
def _fireball(S, p):
    S.poly([(14, 30), (40, 40), (24, 50), (40, 60), (14, 70), (58, 76), (58, 24)], p["o"])
    S.group().circle(60, 50, 22, p["o"])
    S.group().circle(62, 50, 14, p["y"])
    S.circle(64, 47, 6, p["w"])


@sym("jet")
def _jet(S, p):
    S.poly([(16, 42), (60, 40), (60, 60), (16, 58)], p["c"])
    S.group().circle(66, 50, 14, p["w"])
    for x, y in ((80, 36), (84, 56), (74, 70)):
        S.circle(x, y, 5, p["c"])


@sym("kunai")
def _kunai(S, p):
    k = rot([(16, 47), (40, 47), (44, 42), (80, 50), (44, 58), (40, 53), (16, 53)], -30)
    S.poly(k, p["s"])
    S.group().circle(*rot([(14, 50)], -30)[0], 6, p["a"])
    S.group().poly(rot([(44, 42), (80, 50), (44, 50)], -30), p["w"])


@sym("pebbles")
def _pebbles(S, p):
    for x, y, r in ((30, 62, 12), (56, 40, 14), (70, 68, 10)):
        S.group().poly(ngon(x, y, r, 6, 10), p["n"])
        S.circle(x - r * 0.3, y - r * 0.3, r * 0.3, p["w"])
    speedlines(S, p, 14, 34, 34, n=2, gap=8)


@sym("blaster")
def _blaster(S, p):
    S.poly([(20, 40), (70, 40), (78, 46), (78, 54), (70, 56), (44, 56), (40, 74), (26, 74), (30, 56), (20, 56)],
           p["s"])
    S.group().rect(46, 34, 66, 40, p["k"], 2)
    S.group().circle(83, 48, 7, p["c"])
    S.rect(26, 45, 40, 51, p["c"], 2)


@sym("wristblaster")
def _wristblaster(S, p):
    S.rect(18, 46, 56, 68, p["w"], 8)
    S.group().rect(36, 36, 70, 56, p["s"], 5)
    S.group().rect(70, 40, 80, 52, p["k"], 2)
    S.group().poly(star(86, 46, 9, 4, 5, 0), p["y"])
    S.circle(46, 46, 4, p["c"])


@sym("twinblaster")
def _twinblaster(S, p):
    for dy, ang in ((-12, -14), (14, 10)):
        g = [(22, 44), (64, 44), (70, 50), (64, 54), (42, 54), (38, 66), (28, 66), (30, 54), (22, 54)]
        S.group().poly(rot([(x, y + dy) for x, y in g], ang), p["s"])
        S.circle(*rot([(74, 49 + dy)], ang)[0], 5, p["c"])


@sym("psibolt")
def _psibolt(S, p):
    for r in (30, 22):
        S.arc(40, 50, r, -40, 40, 4, p["w"])
    S.group().circle(64, 50, 14, p["v"])
    S.circle(60, 46, 5, p["w"])


# ---------------------------------------------------------------- lightning, chains, links
@sym("chain")
def _chain(S, p):
    pts = [(18, 30), (40, 54), (58, 34), (82, 62)]
    S.line(pts, 6, p["y"])
    for x, y in pts[1:]:
        S.group().circle(x, y, 8, p["w"])


@sym("chainlinks")
def _chainlinks(S, p):
    for i, (x, y) in enumerate(((28, 66), (50, 50), (72, 34))):
        S.group()
        S.arc(x, y, 12, 0, 360, 6, p["w"] if i % 2 == 0 else p["a"], steps=40)


@sym("ricochet")
def _ricochet(S, p):
    S.line([(14, 30), (40, 72), (62, 30)], 5, p["w"])
    S.group().poly(arrow(62, 30, 84, 66, 5, 12), p["w"])
    for x, y in ((40, 74), (62, 28)):
        S.group().poly(star(x, y, 9, 4, 6), p["y"])


@sym("link")
def _link(S, p):
    S.arc(38, 50, 16, 0, 360, 7, p["w"], steps=40)
    S.group().arc(62, 50, 16, 0, 360, 7, p["a"], steps=40)
    S.group().arc(38, 50, 16, -40, 40, 7, p["w"])


@sym("thunder")
def _thunder(S, p):
    S.group().poly(bolt(52, 64, 40, 10), p["y"])
    S.group()
    for x, y, r in ((34, 36, 13), (52, 28, 16), (68, 38, 12)):
        S.circle(x, y, r, p["w"])
    S.rect(26, 34, 76, 48, p["w"], 6)


@sym("boltride")
def _boltride(S, p):
    speedlines(S, p, 14, 50, 40, n=3, gap=9)
    S.group().poly(bolt(60, 50, 56, 70), p["y"])


@sym("battery")
def _battery(S, p):
    S.rect(30, 24, 70, 80, p["w"], 7)
    S.rect(42, 16, 58, 24, p["s"], 2)
    S.group().rect(36, 46, 64, 74, p["g"], 3)
    S.group().poly(bolt(50, 48, 30, 15), p["y"])


@sym("sparkfield")
def _sparkfield(S, p):
    S.ell(16, 52, 84, 80, p["a"])
    S.group().ell(26, 58, 74, 74, p["d"])
    S.group().poly(bolt(36, 44, 30, 10), p["y"])
    S.poly(bolt(62, 38, 34, -10), p["y"])


@sym("groundline")
def _groundline(S, p):
    ground(S, p, 70, 14, 86)
    S.group()
    for x in (30, 50, 70):
        S.poly(bolt(x, 50, 30, 10), p["y"])


# ---------------------------------------------------------------- melee

def rrect(x0, y0, x1, y1, r):
    """A rounded box as a polygon (so it can turn)."""
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        pts += arcpts(cx, cy, r, a0, a0 + 90, 6)
    return pts


def fistshape(S, p, cx, cy, s, ang=0, c=None, band=None):
    """A cartoon fist facing right (knuckles at +x), centred on (cx, cy), s across; each finger outlined."""
    c = c or p["w"]

    def R(x0, y0, x1, y1, r):
        pts = [(cx + x * s, cy + y * s) for x, y in rrect(x0, y0, x1, y1, r)]
        return rot(pts, ang, cx, cy) if ang else pts

    if band:
        S.group().poly(R(-0.66, -0.3, -0.36, 0.3, 0.06), band)
    S.group().poly(R(-0.46, -0.42, 0.16, 0.44, 0.16), c)
    for i in range(4):
        y = -0.44 + i * 0.205
        S.group().poly(R(-0.04, y, 0.5, y + 0.215, 0.1), c)
    S.group().poly(R(-0.36, 0.14, 0.26, 0.38, 0.12), c)


@sym("fist")
def _fist(S, p):
    speedlines(S, p, 10, 50, 26, n=3, gap=10)
    fistshape(S, p, 54, 50, 58, band=p["a"])

@sym("gauntlet")
def _gauntlet(S, p):
    fistshape(S, p, 54, 50, 62, c=p["s"], band=p["k"])
    for y in (36, 64):
        S.circle(36, y, 3, p["y"])

@sym("palm")
def _palm(S, p):
    S.rect(32, 42, 66, 80, p["w"], 12)
    S.group()
    for i, h in enumerate((30, 22, 24, 32)):
        S.rect(32 + i * 9, h, 40 + i * 9, 50, p["w"], 4)
    S.group().rect(20, 50, 36, 62, p["w"], 5)
    S.group()
    for r in (36, 44):
        S.arc(50, 50, r, -150, -30, 3, p["y"])


@sym("fists")
def _fists(S, p):
    for i, (x, y) in enumerate(((40, 28), (60, 50), (40, 72))):
        fistshape(S, p, x, y, 30, c=p["w"] if i != 1 else p["a"])
    S.group()
    for y in (28, 72):
        S.line([(64, y), (84, y)], 3, p["y"])

@sym("haymaker")
def _haymaker(S, p):
    S.arc(46, 60, 32, 150, 300, 7, p["y"])
    fistshape(S, p, 62, 36, 46, ang=-20, band=p["a"])

@sym("slam")
def _slam(S, p):
    S.poly(star(50, 76, 36, 14, 9, 0), p["y"])
    S.group().ell(14, 74, 86, 88, p["n"])
    fistshape(S, p, 50, 42, 52, ang=90, band=p["a"])

def blade(S, p, ang, cx=50, cy=50, length=1.0, c=None):
    L = length
    pts = [(cx - 4, cy - 36 * L), (cx + 4, cy - 40 * L), (cx + 5, cy + 10), (cx - 5, cy + 10)]
    S.group().poly(rot(pts, ang, cx, cy), c or p["s"])
    S.group().poly(rot([(cx - 12, cy + 10), (cx + 12, cy + 10), (cx + 12, cy + 16), (cx - 12, cy + 16)], ang, cx, cy),
                   p["y"])
    S.poly(rot([(cx - 3, cy + 16), (cx + 3, cy + 16), (cx + 3, cy + 30), (cx - 3, cy + 30)], ang, cx, cy), p["n"])


@sym("swordslash")
def _swordslash(S, p):
    S.arc(50, 50, 32, 200, 330, 7, p["w"])
    blade(S, p, 40, 52, 54)


@sym("swordup")
def _swordup(S, p):
    S.poly(arrow(24, 80, 24, 26, 8, 12), p["y"])
    blade(S, p, 0, 56, 52)


@sym("crossed")
def _crossed(S, p):
    blade(S, p, -38, 50, 52)
    blade(S, p, 38, 50, 52)


@sym("parry")
def _parry(S, p):
    blade(S, p, 30, 44, 54)
    S.group().poly(star(62, 34, 18, 7, 8), p["y"])
    S.circle(62, 34, 5, p["w"])


@sym("splitter")
def _splitter(S, p):
    S.poly([(44, 8), (56, 8), (60, 70), (50, 92), (40, 70)], p["w"])
    S.group().poly([(50, 8), (56, 8), (60, 70), (50, 92)], p["c"])
    S.group().line([(20, 70), (80, 70)], 4, p["y"])


@sym("crescent")
def _crescent(S, p):
    S.poly(crescent(46, 50, 32, 30, 12, 0), p["w"])
    speedlines(S, p, 10, 50, 26, n=3, gap=10, w=3)


@sym("swipe")
def _swipe(S, p):
    for i in range(3):
        S.group().poly(crescent(40 + i * 12, 50, 30 - i * 2, 28 - i * 2, 6, -30), p["w"] if i != 1 else p["a"])


@sym("sickle")
def _sickle(S, p):
    S.line([(18, 80), (30, 66), (42, 74), (54, 60)], 4, p["s"])
    S.group().rect(52, 40, 60, 66, p["n"], 3)
    S.group().poly(crescent(64, 36, 22, 20, 8, -60)[:26] + [(58, 42)], p["w"])


@sym("whip")
def _whip(S, p):
    S.line(arcpts(52, 56, 26, 160, 400, 30), 5, p["o"])
    S.group().rect(14, 60, 30, 70, p["n"], 3)
    S.group().poly(star(80, 44, 10, 4, 5), p["y"])


@sym("girder")
def _girder(S, p):
    g = [(14, 30), (86, 30), (86, 38), (56, 38), (56, 62), (86, 62), (86, 70), (14, 70), (14, 62), (44, 62),
         (44, 38), (14, 38)]
    S.poly(rot(g, -25), p["r"])
    for x in (24, 76):
        S.circle(*rot([(x, 34)], -25)[0], 2.5, p["s"])


# ---------------------------------------------------------------- movement and travel
@sym("dash")
def _dash(S, p):
    speedlines(S, p, 12, 50, 36, n=3, gap=10)
    S.group().poly(arrow(32, 50, 86, 50, 16, 22), p["w"])


@sym("charge")
def _charge(S, p):
    speedlines(S, p, 10, 50, 30, n=3, gap=10)
    S.group().poly([(30, 30), (64, 30), (82, 50), (64, 70), (30, 70), (40, 50)], p["w"])
    S.group().poly(star(82, 50, 14, 6, 6, 0), p["y"])


@sym("step")
def _step(S, p):
    for i, (x, y) in enumerate(((28, 66), (50, 44), (72, 26))):
        S.group().ell(x - 7, y - 10, x + 7, y + 10, p["w"] if i == 2 else p["a"])
    S.group().line([(20, 40), (40, 24)], 3, p["w"])


@sym("steps")
def _steps(S, p):
    for i in range(3):
        x, y = 26 + i * 18, 72 - i * 18
        S.group().rect(x - 10, y, x + 10, y + 6, p["w"], 3)
        S.group().ell(x - 5, y - 12, x + 5, y - 2, p["a"])


@sym("stride")
def _stride(S, p):
    S.ell(30, 26, 70, 86, p["w"])
    S.group()
    for i, x in enumerate((30, 40, 50, 60, 70)):
        S.circle(x, 18 + abs(2 - i) * 4, 5, p["w"])


@sym("ramp")
def _ramp(S, p):
    S.poly([(14, 78), (86, 78), (86, 34)], p["c"])
    S.group().poly([(30, 78), (86, 78), (86, 48)], p["w"])
    speedlines(S, p, 20, 36, 46, n=2, gap=8)


@sym("board")
def _board(S, p):
    S.poly(rot([(14, 52), (24, 44), (76, 44), (86, 52), (76, 60), (24, 60)], -10), p["w"])
    S.group().line(rot([(30, 52), (70, 52)], -10), 3, p["c"])
    S.group()
    for x in (32, 68):
        S.ell(x - 8, 66, x + 8, 76, p["c"])
    speedlines(S, p, 12, 30, 36, n=2, gap=8)


@sym("surf")
def _surf(S, p):
    S.poly([(10, 80)] + arcpts(50, 92, 40, 200, 340, 16) + [(90, 80), (90, 92), (10, 92)], p["c"])
    S.group().poly(rot([(18, 54), (28, 46), (76, 46), (86, 54), (76, 62), (28, 62)], -14), p["w"])
    S.group().line(rot([(30, 54), (72, 54)], -14), 3, p["o"])


@sym("rockride")
def _rockride(S, p):
    S.poly([(16, 58), (30, 46), (74, 44), (86, 58), (70, 70), (28, 70)], p["n"])
    S.group().poly([(30, 46), (74, 44), (68, 52), (34, 54)], p["a"])
    speedlines(S, p, 16, 30, 46, n=2, gap=8)


@sym("rocket")
def _rocket(S, p):
    for x in (36, 64):
        S.group().poly(flame(x, 70, 26), p["o"])
        S.group().rect(x - 8, 30, x + 8, 58, p["s"], 5)
        S.poly([(x - 8, 34), (x, 20), (x + 8, 34)], p["r"])


@sym("rail")
def _rail(S, p):
    S.line(arcpts(50, 110, 70, 230, 310, 20), 8, p["y"])
    S.group().line(arcpts(50, 110, 56, 232, 308, 20), 4, p["w"])
    S.group().poly(star(76, 48, 10, 4, 4), p["w"])


@sym("platform")
def _platform(S, p):
    S.ell(18, 50, 82, 70, p["v"])
    S.group().ell(26, 50, 74, 62, p["w"])
    S.group()
    for x in (32, 50, 68):
        S.line([(x, 76), (x, 86)], 3, p["v"])


@sym("wisp")
def _wisp(S, p):
    S.poly([(14, 62), (30, 40), (60, 34), (82, 46), (80, 62), (58, 70), (40, 60), (30, 72)], p["w"])
    S.group().circle(66, 50, 8, p["a"])
    speedlines(S, p, 10, 32, 26, n=2, gap=10)


@sym("launch")
def _launch(S, p):
    S.poly(star(50, 74, 22, 9, 8, 0), p["y"])
    S.group().poly(arrow(50, 70, 50, 14, 16, 22), p["w"])


@sym("wallrun")
def _wallrun(S, p):
    S.rect(62, 14, 84, 86, p["n"], 3)
    S.group()
    for y in (26, 46, 66):
        S.line([(62, y), (84, y)], 2, p["d"])
    S.group().poly(arrow(22, 80, 48, 20, 12, 16), p["w"])


@sym("swap")
def _swap(S, p):
    S.arc(50, 50, 26, 200, 340, 7, p["w"])
    S.poly(arrow(70, 40, 78, 56, 2, 12), p["w"])
    S.group().arc(50, 50, 26, 20, 160, 7, p["a"])
    S.poly(arrow(30, 60, 22, 44, 2, 12), p["a"])


# ---------------------------------------------------------------- areas and bursts
@sym("cone")
def _cone(S, p):
    S.poly([(18, 50)] + arcpts(18, 50, 68, -28, 28, 12), p["w"])
    S.group().poly([(18, 50)] + arcpts(18, 50, 50, -18, 18, 8), p["y"])
    S.circle(18, 50, 8, p["w"])


@sym("push")
def _push(S, p):
    S.circle(20, 50, 8, p["w"])
    S.group()
    for r in (22, 36, 50):
        S.arc(20, 50, r, -35, 35, 6, p["w"])


@sym("repulse")
def _repulse(S, p):
    S.circle(50, 50, 12, p["w"])
    S.group()
    for a in range(0, 360, 60):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        S.poly(arrow(50 + c * 18, 50 + s * 18, 50 + c * 38, 50 + s * 38, 7, 10), p["w"])


@sym("snowburst")
def _snowburst(S, p):
    for a in range(0, 180, 60):
        S.line(rot([(50, 16), (50, 84)], a), 7, p["w"])
        for t in (24, 76):
            S.line(rot([(42, t + (8 if t < 50 else -8)), (50, t), (58, t + (8 if t < 50 else -8))], a), 4, p["w"])
    S.group().poly(ngon(50, 50, 10, 6), p["c"])


@sym("explosion")
def _explosion(S, p):
    S.poly(star(50, 50, 38, 18, 11), p["o"])
    S.group().poly(star(50, 50, 24, 12, 9, -70), p["y"])
    S.circle(50, 50, 8, p["w"])


@sym("flash")
def _flash(S, p):
    S.poly(star(50, 50, 40, 9, 4), p["w"])
    S.group().poly(star(50, 50, 22, 7, 4, -45), p["y"])


@sym("stomp")
def _stomp(S, p):
    S.ell(14, 66, 86, 86, p["a"])
    S.group().ell(26, 70, 74, 82, p["d"])
    S.group().poly([(34, 20), (54, 20), (56, 52), (72, 56), (74, 72), (32, 72)], p["s"])
    S.rect(30, 64, 76, 74, p["k"], 3)


@sym("clap")
def _clap(S, p):
    S.poly(star(50, 50, 40, 14, 10), p["y"])
    S.group().rect(18, 28, 44, 72, p["w"], 10)
    S.group().rect(56, 28, 82, 72, p["w"], 10)


@sym("smoke")
def _smoke(S, p):
    for x, y, r in ((32, 58, 16), (52, 46, 20), (70, 60, 15), (50, 66, 16)):
        S.circle(x, y, r, p["a"])
    S.group().circle(44, 40, 7, p["w"])


@sym("roar")
def _roar(S, p):
    S.poly([(18, 40), (34, 40), (52, 24), (52, 76), (34, 60), (18, 60)], p["w"])
    S.group()
    for r in (12, 22, 32):
        S.arc(54, 50, r + 6, -40, 40, 5, p["y"])


@sym("eclipse")
def _eclipse(S, p):
    S.poly(star(50, 50, 40, 30, 16), p["y"])
    S.group().circle(50, 50, 26, p["k"])
    S.group().poly(crescent(50, 50, 26, 24, 8, 135), p["w"])


@sym("sun")
def _sun(S, p):
    S.poly(star(50, 42, 34, 22, 12), p["y"])
    S.group().circle(50, 42, 18, p["o"])
    S.group()
    for x in (30, 50, 70):
        S.poly(arrow(x, 64, x - 6, 88, 5, 8), p["o"])


@sym("dawn")
def _dawn(S, p):
    S.poly(star(50, 50, 40, 20, 14), p["y"])
    S.group().circle(50, 50, 20, p["w"])
    S.group().circle(50, 50, 10, p["y"])


@sym("field")
def _field(S, p):
    S.ell(14, 50, 86, 82, p["a"])
    S.group().ell(26, 56, 74, 76, p["d"])


@sym("ring")
def _ring(S, p):
    S.ell(16, 56, 84, 84, p["d"])
    S.group()
    for x, s in ((24, 22), (38, 30), (52, 34), (66, 30), (78, 22)):
        S.poly(flame(x, 60, s), p["o"])
    S.group()
    for x, s in ((38, 16), (52, 20), (66, 16)):
        S.poly(flame(x, 70, s), p["y"])


@sym("dome")
def _dome(S, p):
    S.ell(14, 68, 86, 84, p["d"])
    S.group().poly(arcpts(50, 76, 34, 180, 360, 24), p["c"])
    S.group().arc(50, 76, 24, 200, 250, 4, p["w"])


@sym("tornado")
def _tornado(S, p):
    for i, (y, w) in enumerate(((22, 32), (36, 26), (50, 20), (64, 13), (76, 7))):
        S.group().ell(50 - w + i * 2, y - 6, 50 + w + i * 2, y + 6, p["w"] if i % 2 == 0 else p["a"])


@sym("haze")
def _haze(S, p):
    for i in range(4):
        x = 26 + i * 16
        pts = [(x + 5 * math.sin(t / 3.0), 82 - t * 4) for t in range(15)]
        S.line(pts, 5, p["o"] if i % 2 else p["y"])


@sym("vortex")
def _vortex(S, p):
    pts = [(50 + (4 + t * 1.3) * math.cos(t * 0.42), 50 + (4 + t * 1.3) * math.sin(t * 0.42)) for t in range(28)]
    S.line(pts, 6, p["w"])
    S.group().circle(50, 50, 5, p["a"])


@sym("blackhole")
def _blackhole(S, p):
    S.ell(12, 40, 88, 60, p["v"])
    S.group().circle(50, 50, 20, p["k"])
    S.group().arc(50, 50, 38, 15, 165, 6, p["v"], steps=24)
    S.circle(43, 43, 4, p["a"])


@sym("quicksand")
def _quicksand(S, p):
    S.ell(12, 50, 88, 84, p["n"])
    S.group()
    pts = [(50 + (3 + t * 1.3) * math.cos(t * 0.5), 67 + (2 + t * 0.6) * math.sin(t * 0.5)) for t in range(24)]
    S.line(pts, 4, p["y"])
    S.group().poly(arrow(50, 22, 50, 50, 8, 12), p["w"])


@sym("storm")
def _storm(S, p):
    for x, y, r in ((32, 44, 15), (52, 34, 18), (70, 46, 13)):
        S.circle(x, y, r, p["v"])
    S.rect(22, 44, 80, 58, p["v"], 6)
    S.group()
    for i in range(2):
        pts = [(36 + i * 24 + 6 * math.cos(t * 0.6), 70 + 5 * math.sin(t * 0.6) - t * 0.4) for t in range(12)]
        S.line(pts, 3, p["w"])


@sym("rain")
def _rain(S, p):
    for x, y, r in ((32, 36, 13), (52, 28, 16), (70, 38, 12)):
        S.circle(x, y, r, p["w"])
    S.rect(24, 36, 78, 48, p["w"], 6)
    S.group()
    for x, y in ((32, 66), (52, 74), (70, 64)):
        S.poly([(x, y - 10), (x + 6, y), (x, y + 6), (x - 6, y)], p["c"])
    S.group().rect(46, 54, 56, 66, p["g"], 1)
    S.rect(43, 57, 59, 63, p["g"], 1)


# ---------------------------------------------------------------- big hitters
@sym("meteor")
def _meteor(S, p):
    S.poly([(28, 20), (76, 66), (60, 78), (14, 34)], p["o"])
    S.group().poly([(22, 24), (70, 66), (62, 72), (18, 30)], p["y"])
    S.group().poly(ngon(68, 70, 16, 7, 5), p["n"])
    S.circle(63, 65, 4, p["a"])


@sym("wingdive")
def _wingdive(S, p):
    S.poly([(50, 82), (40, 56), (14, 30), (36, 34), (30, 18), (50, 40), (70, 18), (64, 34), (86, 30), (60, 56)],
           p["o"])
    S.group().poly([(50, 84), (44, 60), (50, 46), (56, 60)], p["y"])


@sym("boulder")
def _boulder(S, p):
    S.poly(ngon(50, 52, 32, 8, 12), p["n"])
    S.group().poly([(34, 32), (54, 26), (44, 44)], p["a"])
    S.group().line([(46, 52), (56, 62), (52, 74)], 3, p["k"])


@sym("splash")
def _splash(S, p):
    S.poly(star(50, 54, 34, 16, 7), p["c"])


@sym("wave")
def _wave(S, p):
    pts = [(12, 80), (12, 60)] + arcpts(46, 50, 30, 180, 330, 18) + arcpts(56, 40, 10, 0, 160, 10)[::-1][:0]
    pts += [(70, 40), (60, 50), (88, 64), (88, 80)]
    S.poly(pts, p["c"])
    S.group().arc(46, 50, 20, 200, 300, 5, p["w"])
    S.circle(74, 34, 4, p["w"])


@sym("geyser")
def _geyser(S, p):
    S.ell(18, 72, 82, 86, p["d"])
    S.group().poly([(38, 80), (34, 30), (42, 16), (50, 24), (58, 14), (66, 30), (62, 80)], p["c"])
    S.group().rect(46, 30, 54, 76, p["w"], 4)


@sym("mirror")
def _mirror(S, p):
    S.ell(28, 16, 72, 74, p["s"])
    S.group().ell(34, 22, 66, 68, p["c"])
    S.group().line([(40, 34), (56, 28)], 4, p["w"])
    S.rect(46, 72, 54, 86, p["s"], 3)


@sym("bubble")
def _bubble(S, p):
    S.circle(50, 50, 32, p["c"])
    S.group().circle(50, 50, 24, p["a"])
    S.group().arc(50, 50, 24, 200, 250, 5, p["w"])
    S.circle(66, 64, 4, p["w"])


@sym("float")
def _float(S, p):
    S.rect(32, 40, 68, 66, p["w"], 6)
    S.group()
    for x in (24, 76):
        S.poly(arrow(x, 82, x, 34, 6, 10), p["a"])
    S.group().ell(30, 76, 70, 86, p["d"])


@sym("feather")
def _feather(S, p):
    S.poly(rot([(50, 12), (66, 36), (62, 70), (50, 84), (38, 70), (34, 36)], 30), p["w"])
    S.group().line(rot([(50, 20), (50, 90)], 30), 3, p["a"])


@sym("anvil")
def _anvil(S, p):
    S.poly([(20, 34), (80, 34), (80, 44), (64, 50), (64, 64), (74, 74), (26, 74), (36, 64), (36, 50), (20, 42)],
           p["k"])
    S.group().poly(arrow(50, 6, 50, 30, 8, 10), p["w"])


@sym("magnet")
def _magnet(S, p):
    S.arc(50, 46, 22, 0, 180, 14, p["r"], steps=24)
    S.line([(28, 46), (28, 22)], 14, p["r"])
    S.line([(72, 46), (72, 22)], 14, p["r"])
    S.group().rect(21, 14, 35, 24, p["s"], 1)
    S.rect(65, 14, 79, 24, p["s"], 1)
    S.group()
    for x in (40, 60):
        S.line([(x, 82), (x, 74)], 3, p["w"])


@sym("throw")
def _throw(S, p):
    S.arc(50, 62, 28, 180, 330, 5, p["w"])
    S.poly(arrow(68, 42, 78, 50, 2, 10), p["w"])
    S.group().rect(28, 22, 52, 44, p["s"], 3)
    S.group().rect(26, 60, 48, 82, p["w"], 8)


@sym("car")
def _car(S, p):
    car = [(14, 60), (22, 46), (36, 44), (44, 32), (66, 32), (76, 46), (86, 50), (86, 62), (14, 62)]
    S.poly(rot(car, -18), p["r"])
    S.group().poly(rot([(46, 36), (64, 36), (70, 46), (46, 46)], -18), p["c"])
    S.group()
    for x in (30, 72):
        S.circle(*rot([(x, 64)], -18)[0], 8, p["k"])


@sym("pillar")
def _pillar(S, p):
    ground(S, p, 76, 14, 86)
    S.group().poly([(34, 78), (36, 26), (50, 16), (64, 26), (66, 78)], p["n"])
    S.group().line([(44, 34), (48, 50), (44, 62)], 3, p["k"])
    S.group().poly(arrow(20, 64, 20, 22, 6, 10), p["w"])
    S.poly(arrow(80, 64, 80, 22, 6, 10), p["w"])


@sym("vine")
def _vine(S, p):
    pts = [(20 + t * 2.4, 50 + 22 * math.sin(t * 0.34)) for t in range(26)]
    S.line(pts, 6, p["g"])
    S.group()
    for x, y, a in ((30, 34, -30), (50, 66, 30), (70, 36, -30)):
        S.poly(rot([(x - 9, y), (x, y - 5), (x + 9, y), (x, y + 5)], a, x, y), p["g"])


@sym("sprout")
def _sprout(S, p):
    S.line([(50, 84), (50, 40)], 7, p["g"])
    S.group().poly([(50, 56), (24, 40), (18, 24), (36, 26)], p["g"])
    S.poly([(50, 46), (76, 28), (84, 12), (64, 16)], p["g"])
    S.group().ell(30, 76, 70, 88, p["n"])


@sym("crack")
def _crack(S, p):
    S.poly([(50, 14), (70, 36), (60, 60), (50, 86), (40, 60), (30, 36)], p["c"])
    S.group().line([(50, 14), (46, 34), (56, 46), (48, 62), (50, 86)], 4, p["k"])
    S.group()
    for x, y in ((22, 70), (80, 66), (24, 20)):
        S.poly(ngon(x, y, 6, 3, x), p["w"])


@sym("wall")
def _wall(S, p):
    S.rect(14, 26, 86, 80, p["w"], 4)
    S.group()
    for row in range(3):
        y = 26 + row * 18
        S.line([(14, y + 18), (86, y + 18)], 3, p["c"])
        off = 12 if row % 2 else 0
        for x in range(26 + off, 86, 24):
            S.line([(x, y), (x, y + 18)], 3, p["c"])


@sym("shield")
def _shield(S, p):
    S.poly([(22, 22), (50, 14), (78, 22), (76, 54), (50, 86), (24, 54)], p["w"])
    S.group().poly([(50, 22), (70, 28), (68, 52), (50, 76)], p["a"])


@sym("armor")
def _armor(S, p):
    S.poly([(22, 24), (38, 18), (50, 26), (62, 18), (78, 24), (74, 56), (66, 80), (34, 80), (26, 56)], p["c"])
    S.group().poly([(38, 34), (50, 40), (62, 34), (60, 60), (50, 70), (40, 60)], p["w"])


@sym("heal")
def _heal(S, p):
    S.poly(star(50, 50, 40, 30, 12), p["y"])
    S.group()
    S.rect(40, 22, 60, 78, p["w"], 4)
    S.rect(22, 40, 78, 60, p["w"], 4)


@sym("sanctuary")
def _sanctuary(S, p):
    S.poly(arcpts(50, 78, 36, 180, 360, 24), p["y"])
    S.group().ell(12, 72, 88, 86, p["d"])
    S.group().rect(45, 36, 55, 70, p["w"], 2)
    S.rect(36, 46, 64, 56, p["w"], 2)


@sym("hourglass")
def _hourglass(S, p):
    S.rect(26, 14, 74, 22, p["n"], 3)
    S.rect(26, 78, 74, 86, p["n"], 3)
    S.group().poly([(32, 22), (68, 22), (54, 50), (68, 78), (32, 78), (46, 50)], p["c"])
    S.group().poly([(40, 78), (60, 78), (50, 62)], p["y"])
    S.poly([(40, 32), (60, 32), (50, 46)], p["y"])


@sym("grenade")
def _grenade(S, p):
    S.circle(46, 56, 24, p["g"])
    S.group().rect(40, 24, 56, 34, p["s"], 2)
    S.group().arc(62, 26, 8, 180, 450, 3, p["s"])
    S.group().line([(30, 56), (62, 56)], 3, p["d"])
    speedlines(S, p, 74, 70, 88, n=2, gap=8)


@sym("crosshair")
def _crosshair(S, p):
    S.arc(50, 50, 26, 0, 360, 7, p["r"], steps=48)
    S.group()
    for a in (0, 90, 180, 270):
        S.line(rot([(50, 14), (50, 34)], a), 6, p["w"])
    S.group().circle(50, 50, 6, p["r"])


@sym("trickshot")
def _trickshot(S, p):
    S.arc(36, 64, 20, 0, 360, 5, p["r"], steps=40)
    S.group().circle(36, 64, 6, p["r"])
    S.group().line(arcpts(52, 46, 30, 120, -60, 20)[:-3], 4, p["w"])
    S.poly(arrow(70, 38, 56, 54, 2, 10), p["w"])


@sym("sheriff")
def _sheriff(S, p):
    S.poly(star(50, 50, 38, 17, 6), p["y"])
    for pt in star(50, 50, 38, 17, 6)[::2]:
        S.circle(pt[0], pt[1], 5, p["y"])
    S.group().circle(50, 50, 10, p["w"])


@sym("turret")
def _turret(S, p):
    S.poly([(22, 80), (34, 58), (66, 58), (78, 80)], p["s"])
    S.group().ell(32, 34, 68, 66, p["k"])
    S.group().rect(56, 40, 86, 50, p["s"], 3)
    S.circle(44, 48, 5, p["c"])


@sym("hook")
def _hook(S, p):
    S.line([(14, 84), (54, 34)], 3, p["w"])
    S.group().arc(62, 40, 14, -30, 200, 6, p["s"])
    S.line([(62, 26), (62, 16)], 6, p["s"])
    S.group().poly([(46, 46), (52, 54), (44, 54)], p["s"])


@sym("mine")
def _mine(S, p):
    S.ell(20, 50, 80, 80, p["k"])
    S.group().ell(30, 50, 70, 68, p["s"])
    S.group().circle(50, 56, 5, p["r"])
    S.poly(bolt(34, 34, 24, 15), p["y"])
    S.poly(bolt(68, 32, 22, -10), p["y"])


@sym("wrench")
def _wrench(S, p):
    S.line([(28, 72), (62, 38)], 10, p["s"])
    S.group().poly(crescent(68, 32, 14, 12, 7, -45), p["s"])
    S.group().poly(star(28, 30, 14, 6, 5), p["y"])
    S.group().rect(20, 66, 34, 80, p["k"], 4)


@sym("decoy")
def _decoy(S, p):
    S.circle(50, 28, 11, p["c"])
    S.poly([(32, 84), (34, 46), (66, 46), (68, 84)], p["c"])
    S.group()
    for y in (54, 66, 78):
        S.line([(30, y), (70, y)], 2, p["w"])


@sym("mech")
def _mech(S, p):
    S.rect(26, 24, 74, 74, p["s"], 14)
    S.group().rect(32, 38, 68, 52, p["c"], 6)
    S.group().rect(40, 60, 60, 66, p["k"], 2)
    S.line([(50, 24), (50, 12)], 4, p["s"])
    S.circle(50, 12, 4, p["r"])


@sym("clones")
def _clones(S, p):
    for x, c in ((30, p["a"]), (70, p["a"]), (50, p["w"])):
        S.group().circle(x, 34, 9, c)
        S.poly([(x - 14, 82), (x - 12, 48), (x + 12, 48), (x + 14, 82)], c)


@sym("eye")
def _eye(S, p):
    S.poly(arcpts(50, 72, 40, 210, 330, 16) + arcpts(50, 28, 40, 30, 150, 16), p["w"])
    S.group().circle(50, 50, 13, p["a"])
    S.circle(50, 50, 6, p["k"])


@sym("counter")
def _counter(S, p):
    S.rect(20, 30, 46, 74, p["w"], 10)
    S.group().arc(56, 50, 24, -120, 120, 6, p["y"])
    S.poly(arrow(46, 74, 38, 72, 2, 10), p["y"])


@sym("rising")
def _rising(S, p):
    pts = [(50 + 20 * math.cos(t * 0.5), 86 - t * 2.6) for t in range(24)]
    S.line(pts, 6, p["o"])
    S.group().poly(arrow(50, 28, 50, 10, 6, 14), p["y"])


@sym("lotus")
def _lotus(S, p):
    for ang in (-56, -28, 28, 56):
        S.group().poly(rot([(50, 72), (40, 46), (50, 24), (60, 46)], ang, 50, 72), p["a"])
    S.group().poly([(50, 72), (40, 44), (50, 18), (60, 44)], p["w"])
    S.group().circle(50, 12, 4, p["y"])


@sym("plow")
def _plow(S, p):
    S.poly([(56, 18), (84, 30), (84, 70), (56, 82), (66, 50)], p["y"])
    S.group().rect(20, 36, 60, 64, p["s"], 5)
    speedlines(S, p, 6, 50, 22, n=3, gap=9)


@sym("challenge")
def _challenge(S, p):
    S.poly(star(50, 50, 18, 8, 5), p["y"])
    S.group()
    for a in (0, 180):
        S.poly(rot([(10, 38), (30, 50), (10, 62), (20, 50)], a), p["w"])


@sym("tower")
def _tower(S, p):
    S.poly([(26, 84), (30, 34), (70, 34), (74, 84)], p["s"])
    S.group()
    for x in (26, 44, 62):
        S.rect(x, 20, x + 12, 34, p["s"], 1)
    S.group().rect(44, 60, 56, 84, p["k"], 5)
    S.rect(46, 42, 54, 50, p["y"], 1)


@sym("grow")
def _grow(S, p):
    S.rect(36, 36, 64, 64, p["w"], 4)
    S.group()
    for a in (225, 315, 45, 135):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        S.poly(arrow(50 + c * 22, 50 + s * 22, 50 + c * 42, 50 + s * 42, 6, 10), p["y"])


@sym("shrink")
def _shrink(S, p):
    S.rect(42, 42, 58, 58, p["w"], 3)
    S.group()
    for a in (225, 315, 45, 135):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        S.poly(arrow(50 + c * 42, 50 + s * 42, 50 + c * 20, 50 + s * 20, 6, 10), p["a"])


@sym("colossus")
def _colossus(S, p):
    S.circle(50, 22, 10, p["n"])
    S.poly([(26, 36), (74, 36), (82, 62), (70, 62), (66, 84), (34, 84), (30, 62), (18, 62)], p["n"])
    S.group().poly([(40, 36), (60, 36), (50, 52)], p["y"])


@sym("levitate")
def _levitate(S, p):
    S.poly(ngon(50, 30, 16, 6, 0), p["n"])
    S.group()
    for r in (12, 20):
        S.arc(50, 74, r, 200, 340, 4, p["v"])
    S.group().rect(36, 70, 64, 86, p["w"], 8)


@sym("spiral")
def _spiral(S, p):
    pts = [(50 + (2 + t * 1.25) * math.cos(t * 0.55), 50 + (2 + t * 1.25) * math.sin(t * 0.55)) for t in range(28)]
    S.circle(50, 50, 36, p["w"])
    S.group().line(pts, 5, p["v"])


@sym("totem")
def _totem(S, p):
    S.rect(36, 18, 64, 84, p["n"], 4)
    S.group()
    for y in (30, 50, 70):
        S.rect(32, y - 6, 68, y + 6, p["a"], 3)
    S.group().poly(star(50, 12, 10, 4, 4), p["y"])


@sym("wings")
def _wings(S, p):
    for side in (-1, 1):
        S.group().poly([(50, 48), (50 + side * 40, 18), (50 + side * 36, 44), (50 + side * 28, 62)], p["w"])
    S.group().circle(50, 30, 9, p["a"])
    S.poly([(40, 84), (42, 44), (58, 44), (60, 84)], p["a"])


@sym("halo")
def _halo(S, p):
    S.arc(50, 50, 28, 0, 360, 7, p["y"], steps=48)
    S.group()
    for a in range(0, 360, 90):
        S.poly(rot([(50, 6), (56, 18), (50, 30), (44, 18)], a + 45), p["w"])


@sym("prism")
def _prism(S, p):
    S.line([(10, 54), (40, 50)], 5, p["w"])
    S.group().poly([(50, 20), (72, 70), (28, 70)], p["c"])
    S.group()
    for i, c in enumerate((p["r"], p["y"], p["g"])):
        S.line([(62, 50 + i * 6), (88, 40 + i * 14)], 4, c)


@sym("guardian")
def _guardian(S, p):
    S.poly([(22, 22), (50, 14), (78, 22), (76, 54), (50, 86), (24, 54)], p["a"])
    S.group().poly(star(50, 46, 16, 7, 5), p["w"])


# ---------------------------------------------------------------- weapons (silhouettes, diagonal)
def handle(S, p, x0, y0, x1, y1, w=7, c=None):
    S.line([(x0, y0), (x1, y1)], w, c or p["n"])


@sym("w_fists")
def _w_fists(S, p):
    _fist(S, p)


@sym("w_martial")
def _w_martial(S, p):
    S.poly([(30, 14), (46, 14), (50, 54), (78, 58), (82, 74), (34, 76)], p["w"])
    S.group().rect(30, 70, 84, 80, p["a"], 3)
    S.group()
    for r in (38, 46):
        S.arc(42, 64, r, -80, -20, 3, p["y"])


@sym("w_gauntlet")
def _w_gauntlet(S, p):
    _gauntlet(S, p)
    S.group().poly(bolt(80, 22, 26, 10), p["y"])


@sym("w_strikers")
def _w_strikers(S, p):
    S.poly([(30, 14), (52, 14), (54, 50), (82, 56), (84, 76), (28, 76)], p["s"])
    S.group().rect(26, 68, 86, 82, p["k"], 4)
    S.group().rect(30, 30, 54, 40, p["y"], 3)


@sym("w_sword")
def _w_sword(S, p):
    blade(S, p, 45)


@sym("w_katana")
def _w_katana(S, p):
    S.line(arcpts(96, 96, 80, 196, 250, 12), 10, p["w"])
    S.group().line([(26, 82), (36, 70)], 7, p["k"])
    S.group().ell(33, 62, 45, 74, p["y"])


@sym("w_axe")
def _w_axe(S, p):
    handle(S, p, 30, 84, 62, 22)
    S.group().poly([(52, 24), (78, 20), (84, 44), (62, 50)], p["s"])
    S.group().line([(76, 20), (84, 44)], 3, p["w"])


@sym("w_mace")
def _w_mace(S, p):
    handle(S, p, 28, 84, 56, 44)
    S.group().poly(star(64, 34, 22, 14, 8), p["s"])
    S.circle(64, 34, 12, p["k"])


@sym("w_baton")
def _w_baton(S, p):
    handle(S, p, 22, 80, 78, 22, 10, p["k"])
    S.group().line([(22, 80), (34, 68)], 12, p["s"])
    S.group().poly(bolt(80, 22, 18, 20), p["y"])


@sym("w_dagger")
def _w_dagger(S, p):
    S.poly(rot([(46, 20), (54, 20), (56, 54), (50, 60), (44, 54)], 45)[::-1], p["w"])
    S.group().poly(rot([(38, 58), (62, 58), (62, 64), (38, 64)], 45), p["v"])
    S.poly(rot([(47, 64), (53, 64), (53, 78), (47, 78)], 45), p["k"])


@sym("w_greatsword")
def _w_greatsword(S, p):
    blade(S, p, 45, 52, 52, 1.25)
    S.group().poly(rot([(44, 22), (56, 22), (58, 58), (42, 58)], 45, 52, 52), p["s"])


@sym("w_greataxe")
def _w_greataxe(S, p):
    handle(S, p, 22, 86, 72, 18)
    S.group().poly([(60, 20), (86, 8), (90, 40), (68, 40)], p["s"])
    S.poly([(58, 30), (36, 26), (32, 50), (52, 44)], p["s"])


@sym("w_hammer")
def _w_hammer(S, p):
    handle(S, p, 24, 86, 60, 36)
    S.group().poly(rot([(34, 22), (82, 22), (82, 46), (34, 46)], -36, 58, 34), p["s"])
    S.poly(rot([(34, 22), (42, 22), (42, 46), (34, 46)], -36, 58, 34), p["k"])


@sym("w_spear")
def _w_spear(S, p):
    handle(S, p, 16, 86, 70, 30, 6)
    S.group().poly(rot([(64, 30), (84, 16), (74, 40)], 0), p["w"])
    S.poly([(64, 30), (84, 16), (70, 36)], p["s"])
    S.group().line([(64, 36), (70, 42)], 5, p["r"])


@sym("w_scythe")
def _w_scythe(S, p):
    handle(S, p, 34, 88, 58, 16)
    S.group().poly([(56, 14), (60, 22)] + arcpts(40, 40, 30, -40, -150, 12)[1:] + arcpts(44, 34, 18, -150, -50, 10), p["s"])


@sym("w_staff")
def _w_staff(S, p):
    handle(S, p, 16, 84, 84, 16, 7)
    S.group()
    for t in (0.12, 0.5, 0.88):
        S.line([(16 + 68 * t - 3, 84 - 68 * t - 3), (16 + 68 * t + 3, 84 - 68 * t + 3)][::1], 11, p["y"])


@sym("w_twin")
def _w_twin(S, p):
    blade(S, p, -30, 44, 52, 0.85)
    blade(S, p, 30, 56, 52, 0.85)


@sym("w_claws")
def _w_claws(S, p):
    S.rect(16, 60, 54, 84, p["k"], 6)
    S.group()
    for i in range(3):
        S.poly([(30 + i * 10, 62), (38 + i * 10, 62), (70 + i * 8, 16 + i * 6), (64 + i * 8, 18 + i * 6)], p["s"])


@sym("w_sai")
def _w_sai(S, p):
    for side in (-1, 1):
        cx = 50 + side * 14
        S.group().line([(cx, 84), (cx, 70)], 7, p["n"])
        S.line([(cx, 66), (cx, 14)], 5, p["s"])
        S.line([(cx - 10, 52), (cx - 12, 64), (cx + 12, 64), (cx + 10, 52)], 4, p["s"])


@sym("w_tonfa")
def _w_tonfa(S, p):
    for side in (-1, 1):
        cx = 50 + side * 16
        S.group().line([(cx, 16), (cx, 84)], 8, p["k"])
        S.line([(cx, 30), (cx - side * 14, 30)], 6, p["n"])


@sym("w_nunchucks")
def _w_nunchucks(S, p):
    S.line([(36, 34), (50, 44), (64, 34)], 2, p["s"])
    for x0, y0, x1, y1 in ((36, 34, 18, 76), (64, 34, 82, 76)):
        S.group().line([(x0, y0), (x1, y1)], 9, p["n"])
        S.line([(x0, y0), (x0 + (x1 - x0) * 0.15, y0 + (y1 - y0) * 0.15)], 9, p["y"])


@sym("w_roundshield")
def _w_roundshield(S, p):
    S.circle(50, 50, 32, p["s"])
    S.group().arc(50, 50, 22, 0, 360, 5, p["y"], steps=48)
    S.group().circle(50, 50, 8, p["w"])


@sym("w_towershield")
def _w_towershield(S, p):
    S.rect(28, 12, 72, 88, p["s"], 8)
    S.group().rect(34, 18, 66, 82, p["a"], 5)
    S.group().rect(46, 26, 54, 74, p["w"], 2)


@sym("w_swordshield")
def _w_swordshield(S, p):
    blade(S, p, 40, 60, 46, 0.9)
    S.group().poly([(16, 34), (36, 28), (56, 34), (54, 60), (36, 82), (18, 60)], p["s"])
    S.group().poly([(36, 34), (48, 38), (46, 58), (36, 72)], p["a"])


@sym("w_pistol")
def _w_pistol(S, p):
    _blaster(S, p)


@sym("w_twinblasters")
def _w_twinblasters(S, p):
    _twinblaster(S, p)


@sym("w_rifle")
def _w_rifle(S, p):
    g = [(8, 46), (24, 40), (78, 40), (90, 46), (90, 52), (40, 52), (36, 66), (24, 66), (22, 54), (8, 56)]
    S.poly(rot(g, -24), p["s"])
    S.group().poly(rot([(40, 32), (64, 32), (64, 38), (40, 38)], -24), p["k"])
    S.circle(*rot([(90, 49)], -24)[0], 5, p["c"])


@sym("w_bow")
def _w_bow(S, p):
    S.line(arcpts(66, 66, 50, 180, 270, 18), 7, p["n"])
    S.group().line([(16, 66), (66, 16)], 2, p["w"])
    S.group().line([(26, 74), (78, 22)], 3, p["w"])
    S.poly(arrow(70, 30, 84, 16, 2, 10), p["s"])


@sym("w_crossbow")
def _w_crossbow(S, p):
    S.line([(22, 80), (72, 30)], 8, p["n"])
    S.group().line(arcpts(52, 52, 30, -150, -30, 12)[::1], 6, p["s"])
    S.line(rot(arcpts(50, 50, 30, -150, -30, 12), 45), 6, p["s"])
    S.group().poly(arrow(46, 56, 84, 18, 3, 10), p["w"])


@sym("w_cannon")
def _w_cannon(S, p):
    S.rect(14, 40, 56, 74, p["w"], 10)
    S.group().rect(36, 30, 78, 64, p["s"], 10)
    S.group().ell(70, 30, 88, 64, p["k"])
    S.ell(74, 38, 84, 56, p["c"])


@sym("w_stars")
def _w_stars(S, p):
    for x, y, r, c in ((34, 62, 20, p["s"]), (66, 36, 16, p["w"])):
        S.group().poly(star(x, y, r, r * 0.35, 4, -70), c)
        S.circle(x, y, r * 0.22, p["k"])


@sym("w_whip")
def _w_whip(S, p):
    S.line([(24, 76)] + arcpts(56, 44, 28, 140, 400, 30), 4, p["s"])
    S.group().line([(16, 86), (28, 72)], 8, p["n"])


@sym("w_fan")
def _w_fan(S, p):
    S.poly([(30, 76)] + arcpts(30, 76, 56, -90, 0, 14), p["r"])
    S.group()
    for a in range(-90, 1, 18):
        S.line([(30, 76), (30 + 54 * math.cos(math.radians(a)), 76 + 54 * math.sin(math.radians(a)))], 2, p["k"])
    S.group().circle(30, 76, 6, p["y"])


@sym("w_yoyo")
def _w_yoyo(S, p):
    S.line([(20, 14), (56, 56)], 2, p["w"])
    S.group().circle(60, 60, 22, p["r"])
    S.group().circle(60, 60, 8, p["w"])
    S.group().circle(20, 14, 5, p["y"])


@sym("w_ropedart")
def _w_ropedart(S, p):
    pts = [(20 + t * 2.2, 70 - 18 * math.sin(t * 0.3)) for t in range(24)]
    S.line(pts, 3, p["r"])
    S.group().poly(rot([(70, 42), (80, 30), (90, 34), (82, 48)], 0), p["s"])


@sym("w_boomerang")
def _w_boomerang(S, p):
    S.poly([(20, 26), (34, 18), (56, 50), (84, 70), (78, 82), (44, 64)], p["y"])
    S.group().line(arcpts(50, 50, 40, 200, 290, 10), 3, p["w"])


# ---------------------------------------------------------------- mobility, gadgets, actions, move badges
@sym("m_flight")
def _m_flight(S, p):
    S.poly([(50, 70), (14, 30), (30, 34), (26, 20), (50, 42), (74, 20), (70, 34), (86, 30)], p["w"])
    S.group().poly(arrow(50, 86, 50, 40, 10, 14), p["y"])


@sym("m_speed")
def _m_speed(S, p):
    speedlines(S, p, 10, 54, 38, n=3, gap=10)
    S.group().poly([(40, 26), (60, 26), (62, 54), (86, 60), (86, 74), (38, 74)], p["r"])
    S.group().poly(bolt(64, 38, 22, 25), p["y"])


@sym("m_leap")
def _m_leap(S, p):
    S.group()
    for i in range(4):
        S.line([(32, 80 - i * 10), (68, 74 - i * 10)], 5, p["s"])
    S.group().rect(28, 78, 72, 86, p["k"], 3)
    S.group().poly(arrow(50, 40, 50, 8, 10, 14), p["y"])


@sym("m_acrobat")
def _m_acrobat(S, p):
    S.arc(50, 50, 28, 120, 400, 8, p["w"])
    S.poly(arrow(64, 74, 46, 78, 2, 14), p["w"])
    S.group().poly(star(50, 50, 12, 5, 5), p["y"])


@sym("m_swing")
def _m_swing(S, p):
    S.line([(50, 8), (50, 40)], 3, p["w"])
    S.line(arcpts(50, 8, 56, 60, 120, 16), 3, p["w"])
    S.group().poly(star(50, 10, 8, 3, 4), p["y"])
    S.group().circle(50 + 56 * math.cos(math.radians(60)), 8 + 56 * math.sin(math.radians(60)), 9, p["a"])
    S.circle(50 + 56 * math.cos(math.radians(120)), 8 + 56 * math.sin(math.radians(120)), 6, p["w"])


@sym("g_grapple")
def _g_grapple(S, p):
    S.line([(16, 86), (50, 50)], 3, p["w"])
    S.group().line([(50, 50), (66, 34)], 7, p["s"])
    for a in (-60, 30, 120):
        S.line([(66, 34), (66 + 16 * math.cos(math.radians(a - 45)), 34 + 16 * math.sin(math.radians(a - 45)))],
               5, p["s"])


@sym("g_smoke")
def _g_smoke(S, p):
    for x, y, r in ((58, 30, 12), (72, 22, 9), (66, 40, 8)):
        S.circle(x, y, r, p["a"])
    S.group().circle(44, 62, 22, p["k"])
    S.group().line([(56, 44), (62, 36)], 4, p["y"])
    S.circle(38, 56, 5, p["w"])


@sym("g_drone")
def _g_drone(S, p):
    S.line([(20, 30), (80, 30)], 4, p["s"])
    for x in (20, 80):
        S.ell(x - 12, 24, x + 12, 30, p["s"])
    S.group().rect(36, 30, 64, 52, p["s"], 8)
    S.group().poly([(34, 56), (50, 52), (66, 56), (64, 72), (50, 84), (36, 72)], p["c"])


@sym("g_decoy")
def _g_decoy(S, p):
    _decoy(S, p)
    S.group().poly(star(76, 24, 10, 4, 4), p["y"])


@sym("a_awaken")
def _a_awaken(S, p):
    S.poly([(50, 8), (60, 30), (80, 18), (74, 44), (90, 56), (68, 64), (72, 88), (50, 74), (28, 88), (32, 64),
            (10, 56), (26, 44), (20, 18), (40, 30)], p["o"])
    S.group().poly(star(50, 54, 22, 10, 8), p["y"])
    S.circle(50, 54, 9, p["w"])


@sym("a_block")
def _a_block(S, p):
    S.poly([(22, 22), (50, 12), (78, 22), (76, 54), (50, 88), (24, 54)], p["c"])
    S.group().poly([(50, 22), (68, 28), (66, 52), (50, 74)], p["w"])
    S.group().poly([(34, 30), (44, 26), (40, 40)], p["w"])


@sym("a_power")
def _a_power(S, p):
    _fist(S, p)
    S.group().poly(bolt(80, 24, 26, 10), p["y"])


def pips(S, p, n, y=50, r=7, gap=17):
    x0 = 50 - (n - 1) * gap / 2
    for i in range(n):
        S.circle(x0 + i * gap, y, r, p["w"])


@sym("b_combo")
def _b_combo(S, p):
    for i in range(3):
        S.group().poly(arrow(22 + i * 18, 70, 36 + i * 18, 30, 6, 10), p["w"])


for _n in range(1, 5):
    def _mk(n):
        def f(S, p):
            pips(S, p, n, r=8 if n < 4 else 7, gap=19 if n < 4 else 17)
        return f

    SYM["b_move%d" % _n] = _mk(_n)


# ---------------------------------------------------------------- gear slots
@sym("s_head")
def _s_head(S, p):
    S.poly(arcpts(50, 52, 32, 180, 360, 24) + [(82, 72), (62, 72), (60, 60), (40, 60), (38, 72), (18, 72)], p["w"])
    S.group().rect(30, 48, 70, 58, p["c"], 4)


@sym("s_chest")
def _s_chest(S, p):
    S.poly([(20, 24), (38, 16), (50, 24), (62, 16), (80, 24), (76, 52), (70, 84), (30, 84), (24, 52)], p["w"])
    S.group().poly(star(50, 46, 14, 6, 5), p["y"])


@sym("s_hands")
def _s_hands(S, p):
    S.rect(30, 50, 70, 86, p["w"], 10)
    S.group()
    for i, h in enumerate((24, 16, 18, 26)):
        S.rect(30 + i * 10, h, 39 + i * 10, 56, p["w"], 4)
    S.group().rect(16, 54, 32, 66, p["w"], 5)
    S.group().rect(28, 76, 72, 86, p["a"], 3)


@sym("s_legs")
def _s_legs(S, p):
    S.poly([(26, 16), (74, 16), (78, 86), (56, 86), (50, 40), (44, 86), (22, 86)], p["w"])
    S.group().rect(26, 16, 74, 26, p["a"], 3)


@sym("s_feet")
def _s_feet(S, p):
    S.poly([(26, 14), (52, 14), (54, 52), (82, 60), (84, 78), (24, 78)], p["w"])
    S.group().rect(22, 72, 86, 84, p["a"], 4)


@sym("s_back")
def _s_back(S, p):
    S.poly([(36, 14), (64, 14), (78, 82), (64, 76), (50, 86), (36, 76), (22, 82)], p["r"])
    S.group().rect(30, 12, 70, 22, p["y"], 4)


@sym("s_belt")
def _s_belt(S, p):
    S.rect(10, 40, 90, 60, p["n"], 4)
    S.group().rect(36, 32, 64, 68, p["y"], 5)
    S.group().rect(44, 40, 56, 60, p["n"], 2)


@sym("s_gadget")
def _s_gadget(S, p):
    S.poly(star(50, 50, 32, 24, 8, -90 + 22.5), p["s"])
    S.group().circle(50, 50, 13, p["c"])
    S.circle(50, 50, 5, p["k"])
