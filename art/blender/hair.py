# hair.py: the hero creator's 40 hair styles as meshes (creator art round 3, 2026-11-18), in place of the boxes,
# balls and wedges LookKit and PieceKits weld to the head for the Hair slot (nate's 2026-11-17 call: heroes wear our
# own hair, nothing from their avatar). Each style is a cap that hugs the classic rounded head (radius 0.6, z 4.02 to
# 5.2; kit.py axes: +y the face) with its own hairline, plus the style's spikes, locks, bangs, tails, buns, braids,
# curls or flames, joined into one mesh in the hero's hair colour (role "hair"); a tie or band is a second mesh in
# the accent colour. Chunky anime and cartoon shapes that read on a phone at a distance; all original.
# Output: art/export/Hair.fbx (nate imports it as ReplicatedStorage.Art.Hair), src/config/HairArt.luau (LookKit's
# fit) and art/preview/hair.png (each style from the front three-quarter and from behind).
# Run: python art/blender/hair.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, ring, ball, rod, joined, strip  # noqa: E402
import bpy  # noqa: E402, F401
from mathutils import Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 2400  # triangles a style
HP = 2.25  # the head's outline power
R = 0.645  # the hair cap's radius (the head is 0.6)
Z1 = 4.98  # where the cap's dome starts
TOPZ = 5.36  # the cap's crown

kit.reset()

STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def hairline(front=4.98, side=4.42, back=4.25):
    """The cap's lower edge at angle a: the forehead in front, sideburns over the ears, the nape behind."""
    def f(a):
        a = abs(a)
        if a < 1.0:
            return front
        if a < 1.45:
            return lerp(front, side, smooth((a - 1.0) / 0.45))
        if a < 2.2:
            return lerp(side, back, smooth((a - 1.45) / 0.75))
        return back
    return f


def cap(name="Cap", r=R, top=TOPZ, line=None, thick=0.05, wave=None, na=24, ry=None):
    """A shell over the head from its hairline up: each column starts on the line (the forehead, the sideburns, the
    nape), so the edge runs smooth round the face, then the rows close in a dome at `top`."""
    import bmesh
    line = line or hairline()
    ry = ry or r
    nside, ndome = 4, 5
    bm = bmesh.new()
    grid = []
    for j in range(nside + ndome + 1):
        row = []
        for i in range(na):
            a = -PI + 2 * PI * i / na
            if j <= nside:
                z = lerp(line(a), Z1, j / nside)
                f = 1.0
            else:
                t = (j - nside) / ndome * PI / 2
                z = Z1 + (top - Z1) * math.sin(t)
                f = math.cos(t) if j < nside + ndome else 0.0
            w = wave(a, z) if (wave and f > 1e-4) else 0.0
            x, y = wear.spt(a, (r + w) * f, (ry + w) * f, HP)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(len(grid) - 1):
        for i in range(na):
            q = [grid[j][i], grid[j][(i + 1) % na], grid[j + 1][(i + 1) % na], grid[j + 1][i]]
            if len(set(q)) == 4:
                bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = kit._obj(name, bm)
    if thick > 0:
        wear.solid(ob, thick, 0.0)
    kit.shade_auto(ob, 45)
    return ob


def surf(a, t, r=R, top=TOPZ, lift=0.0, z=None):
    """A point on the cap and its outward normal: angle a (0 the face), t 0 at the dome's foot to 1 at the crown;
    or z (below the dome) for a point on the sides."""
    if z is not None and z <= Z1:
        x, y = wear.spt(a, r, r, HP)
        n = Vector((math.sin(a), math.cos(a), 0.0))
        return Vector((x, y, z)) + n * lift, n
    th = t * PI / 2
    x, y = wear.spt(a, r * math.cos(th), r * math.cos(th), HP)
    zz = Z1 + (top - Z1) * math.sin(th)
    n = Vector((math.sin(a) * math.cos(th), math.cos(a) * math.cos(th), math.sin(th) * 1.3)).normalized()
    return Vector((x, y, zz)) + n * lift, n


def spike(p, d, length, r0, segs=5, bend=None):
    """A tapered spike from p along d (bend: a vector the tip curls toward)."""
    d = Vector(d).normalized()
    pts, rs = [], []
    n = 5
    for k in range(n):
        t = k / (n - 1)
        q = Vector(p) + d * length * t
        if bend is not None:
            q += Vector(bend) * length * t * t
        pts.append(tuple(q))
        rs.append(r0 * (1 - t) ** 1.1 + 0.004)
    return rod("s", pts, rs, segs=segs)


def lock(pts, r0, r1=0.01, segs=7):
    n = len(pts)
    return rod("l", pts, [lerp(r0, r1, k / (n - 1)) for k in range(n)], segs=segs)


def braid(pts, r, segs=8, rings=5):
    """A braid: lumps along a path, alternating a little side to side."""
    out = []
    P = [Vector(p) for p in pts]
    for k, p in enumerate(P):
        d = (P[min(k + 1, len(P) - 1)] - P[max(k - 1, 0)]).normalized()
        side = d.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
        rr = r * (1 - 0.35 * k / max(1, len(P) - 1))
        out.append(ball("b", rr, tuple(p + side * rr * 0.25 * (1 if k % 2 else -1)), scale=(1, 1, 1.25), segs=segs,
                        rings=rings))
    return out


def path(p0, p1, p2, n=6):
    """A quadratic curve p0 -> p2 bending toward p1."""
    out = []
    for k in range(n):
        t = k / (n - 1)
        a = Vector(p0).lerp(Vector(p1), t)
        b = Vector(p1).lerp(Vector(p2), t)
        out.append(tuple(a.lerp(b, t)))
    return out


def tie(at, r=0.12, axis="Z"):
    t = kit.torus("Tie", r, 0.04, at=at, segs=12, csegs=5, axis=axis)
    kit.shade_auto(t, 60)
    return t


def fringe(n=7, a0=-0.95, a1=0.95, length=0.28, r0=0.1, droop=0.9, z=None, curl=0.0):
    """Bangs: short tapered locks over the forehead."""
    out = []
    for k in range(n):
        a = lerp(a0, a1, k / (n - 1)) if n > 1 else 0.0
        p, nrm = surf(a, 0.15, lift=-0.01)
        if z is not None:
            p.z = z
        d = Vector((math.sin(a) * 0.25, math.cos(a) * 0.5, -droop))
        out.append(spike(p, d, length, r0, bend=(curl * math.sin(a), 0.2, 0)))
    return out


def Hm(ob, role="hair", glow=False, mat=None, alpha=0.0):
    wear.bake(ob)
    return Piece(ob, "head", role, glow, mat, alpha)


def one(name, parts, extra=None):
    """The style's hair as one mesh, plus its accent pieces."""
    out = [Hm(joined(name, parts, 55))]
    for ob, role in extra or []:
        out.append(Hm(ob, role))
    return out


def spray(count, t0, t1, length, r0, seed, up=0.6, back=0.5, a0=-PI, a1=PI, jitter=0.25):
    rnd = random.Random(seed)
    out = []
    for k in range(count):
        a = lerp(a0, a1, (k + 0.5) / count) + rnd.uniform(-jitter, jitter) * (a1 - a0) / count
        t = rnd.uniform(t0, t1)
        p, n = surf(a, t, lift=-0.02)
        d = n + Vector((0, -back, up))
        out.append(spike(p, d, length * rnd.uniform(0.8, 1.15), r0 * rnd.uniform(0.85, 1.1)))
    return out


# ---------------------------------------------------------------- the 10 launch styles
@style("spiky")
def h_spiky():
    sp = spray(9, 0.35, 0.95, 0.5, 0.17, 1, up=0.8, back=0.7)
    return one("Hair", [cap()] + sp + fringe(5, -0.7, 0.7, 0.25, 0.1))


@style("swept")
def h_swept():
    locks = []
    for k in range(6):
        a = -0.9 + 0.36 * k
        p0, _ = surf(a, 0.1, lift=0.02)
        p2, _ = surf(a + 1.2, 0.5, lift=0.03)
        mid, _ = surf(a + 0.5, 0.75, lift=0.12)
        locks.append(lock(path(p0, mid, p2), 0.12, 0.03))
    front, _ = surf(0.2, 0.25, lift=0.05)
    locks.append(spike(front, (0.4, 0.5, 0.4), 0.42, 0.15, bend=(0.6, -0.3, -0.2)))
    return one("Hair", [cap(top=5.42)] + locks)


@style("crop")
def h_crop():
    tex = lambda a, z: 0.012 * math.sin(a * 11) * math.sin(z * 30)  # noqa: E731
    return one("Hair", [cap(top=5.32, line=hairline(5.0, 4.5, 4.32), wave=tex)] + fringe(7, -0.8, 0.8, 0.14, 0.07,
                                                                                       droop=0.5))


@style("tail")
def h_tail():
    base = Vector((0, -0.62, 4.85))
    pts = path(tuple(base), (0, -0.95, 4.6), (0, -0.9, 3.75), n=7)
    tl = lock(pts, 0.2, 0.05, segs=8)
    return one("Hair", [cap(top=5.38), tl] + fringe(5, -0.6, 0.6, 0.2, 0.09),
               [(tie(tuple(base + Vector((0, -0.06, -0.02))), 0.13, "Y"), "a")])


@style("twin")
def h_twin():
    tails, ties = [], []
    for sx in (-1, 1):
        base = Vector((sx * 0.55, -0.25, 5.05))
        pts = path(tuple(base), (sx * 0.95, -0.4, 4.9), (sx * 0.85, -0.35, 3.85), n=7)
        tails.append(lock(pts, 0.17, 0.04, segs=8))
        ties.append(kit.torus("t", 0.11, 0.04, at=tuple(base + Vector((sx * 0.06, 0, 0))), segs=12, csegs=5, axis="X"))
    return one("Hair", [cap()] + tails + fringe(6, -0.7, 0.7, 0.22, 0.09), [(joined("Ties", ties), "a")])


@style("mane")
def h_mane():
    rnd = random.Random(6)
    sp = []
    for k in range(16):
        a = PI + lerp(-2.2, 2.2, k / 15)
        p, n = surf(a, rnd.uniform(0.1, 0.7), lift=-0.03)
        d = n + Vector((0, -0.6, -0.5))
        sp.append(spike(p, d, rnd.uniform(0.55, 0.85), 0.2))
    sp += spray(6, 0.6, 0.95, 0.4, 0.15, 7, up=0.7, back=0.3)
    return one("Hair", [cap(r=0.67, top=5.45, line=hairline(4.95, 4.3, 4.1))] + sp + fringe(5, -0.7, 0.7, 0.3, 0.11))


@style("topknot")
def h_topknot():
    knot = ball("Knot", 0.24, (0, -0.1, 5.5), scale=(1, 1, 0.85), segs=14, rings=8)
    tail = spike((0, -0.12, 5.6), (0, -0.4, 1), 0.3, 0.12, bend=(0, -0.6, -0.4))
    return one("Hair", [cap(top=5.36, line=hairline(5.0, 4.6, 4.35)), knot, tail],
               [(tie((0, -0.1, 5.3), 0.15), "a")])


@style("flare")
def h_flare():
    sp = []
    for k in range(5):
        a = lerp(-0.5, 0.5, k / 4)
        p, n = surf(a, 0.3, lift=-0.02)
        sp.append(spike(p, (math.sin(a) * 0.3, 0.6, 1.0), 0.6 - 0.12 * abs(k - 2), 0.18, bend=(0, -1.2, 0.3)))
    sp += spray(5, 0.5, 0.9, 0.38, 0.14, 8, up=0.4, back=0.9, a0=PI - 1.5, a1=PI + 1.5)
    return one("Hair", [cap(top=5.4)] + sp)


@style("sky")
def h_sky():
    rnd = random.Random(9)
    sp = []
    for k in range(9):
        a = lerp(-PI, PI, (k + 0.5) / 9)
        p, n = surf(a, rnd.uniform(0.45, 0.9), lift=-0.03)
        sp.append(spike(p, n * 0.3 + Vector((0, -0.1, 1)), rnd.uniform(0.75, 1.0), 0.18))
    return one("Hair", [cap(top=5.42)] + sp + fringe(5, -0.7, 0.7, 0.3, 0.1))


@style("flow")
def h_flow():
    locks = []
    for k in range(8):
        a = PI + lerp(-1.7, 1.7, k / 7)
        p0, n = surf(a, 0.55, lift=0.0)
        sx = math.sin(a)
        p1 = p0 + Vector((sx * 0.35, -0.45, -0.4))
        p2 = p0 + Vector((sx * 0.5 + 0.15 * math.sin(k), -0.75, -1.35))
        locks.append(lock(path(tuple(p0), tuple(p1), tuple(p2), n=7), 0.17, 0.04))
    return one("Hair", [cap(r=0.66, top=5.42)] + locks + fringe(6, -0.8, 0.8, 0.32, 0.1, curl=0.4))


# ---------------------------------------------------------------- the 30 extra styles
@style("afro")
def h_afro():
    rnd = random.Random(10)
    puff = ball("Puff", 0.92, (0, -0.06, 5.12), scale=(1.0, 0.96, 0.78), segs=24, rings=14)
    for v in puff.data.vertices:
        c = v.co - Vector((0, -0.06, 5.12))
        v.co += c.normalized() * 0.04 * math.sin(c.x * 18) * math.sin(c.z * 18 + c.y * 9)
    # trim the inside under the face so the forehead shows
    for v in puff.data.vertices:
        if v.co.y > 0.3 and v.co.z < 5.02:
            v.co.y = 0.3 + (v.co.y - 0.3) * 0.25
    _ = rnd
    return one("Hair", [cap(line=hairline(4.98, 4.4, 4.2)), puff])


@style("buns")
def h_buns():
    buns = [ball("b", 0.27, (sx * 0.42, -0.08, 5.45), segs=14, rings=8) for sx in (-1, 1)]
    ties = [kit.torus("t", 0.2, 0.04, at=(sx * 0.37, -0.08, 5.27), segs=12, csegs=5) for sx in (-1, 1)]
    return one("Hair", [cap()] + buns + fringe(5, -0.6, 0.6, 0.2, 0.09), [(joined("Ties", ties), "a")])


@style("mohawk")
def h_mohawk():
    fins = []
    for k in range(7):
        t = k / 6
        y = lerp(0.45, -0.6, t)
        z = 5.2 + 0.22 * math.sin(PI * min(1.0, t * 1.1))
        fins.append(spike((0, y, z - 0.18), (0, -0.25, 1), 0.5 - 0.1 * abs(t - 0.4), 0.15))
    shaved = cap(r=0.62, top=5.33, line=hairline(5.0, 4.6, 4.4), thick=0.02)
    return one("Hair", [shaved] + fins)


@style("undercut")
def h_undercut():
    top = cap("Top", r=0.665, top=5.45, line=hairline(5.05, 5.05, 5.05))
    sides = cap("Sides", r=0.615, top=5.15, line=hairline(5.0, 4.5, 4.3), thick=0.02)
    sweep, _ = surf(-0.3, 0.3, lift=0.04)
    s1 = spike(sweep, (0.6, 0.5, 0.5), 0.55, 0.17, bend=(0.8, -0.2, -0.3))
    return one("Hair", [top, sides, s1])


@style("long")
def h_long():
    curtain = ring("Curtain", [(3.55, 0.7, 0.62), (4.0, 0.68, 0.64), (4.5, 0.66, 0.66), (Z1, R + 0.005, R + 0.005)],
                   power=HP, na=28, thick=0.05, a0=1.15, a1=2 * PI - 1.15, angle=45)
    ends = fringe(9, PI - 1.9, PI + 1.9, 0.18, 0.08, droop=1.0, z=3.62)
    return one("Hair", [cap(top=5.38), curtain] + ends + fringe(5, -0.5, 0.5, 0.22, 0.09))


@style("bob")
def h_bob():
    bowl = ring("Bob", [(4.18, 0.74, 0.72), (4.3, 0.73, 0.73), (4.6, 0.7, 0.7), (Z1, 0.67, 0.67)], power=HP, na=32,
                thick=0.05, a0=0.95, a1=2 * PI - 0.95, angle=45)
    return one("Hair", [cap(r=0.67, top=5.42), bowl] + fringe(9, -0.85, 0.85, 0.26, 0.09, droop=1.2))


@style("locs")
def h_locs():
    locks = []
    for k in range(12):
        a = PI + lerp(-2.3, 2.3, k / 11)
        p0, n = surf(a, 0.25, lift=-0.02)
        sx = math.sin(a)
        locks.append(lock([tuple(p0), tuple(p0 + Vector((sx * 0.18, -0.12, -0.35))),
                           tuple(p0 + Vector((sx * 0.22, -0.18, -0.85 - 0.1 * (k % 3))))], 0.075, 0.06, segs=6))
    return one("Hair", [cap(top=5.38)] + locks)


@style("pony")
def h_pony():
    base = Vector((0, -0.45, 5.32))
    pts = path(tuple(base), (0, -1.0, 5.4), (0, -1.0, 4.35), n=7)
    tl = lock(pts, 0.19, 0.05, segs=8)
    return one("Hair", [cap(top=5.38), tl] + fringe(4, -0.5, 0.5, 0.2, 0.09),
               [(tie(tuple(base + Vector((0, -0.08, 0.02))), 0.13, "Y"), "a")])


@style("curly")
def h_curly():
    curls = []
    rnd = random.Random(12)
    for k in range(26):
        a = rnd.uniform(-PI, PI)
        t = rnd.uniform(0.0, 0.95)
        if abs(a) < 0.9 and t < 0.2:
            t = 0.25
        p, n = surf(a, t, lift=0.06)
        curls.append(ball("c", rnd.uniform(0.13, 0.18), tuple(p), segs=7, rings=5))
    return one("Hair", [cap(r=0.66, top=5.45)] + curls)


@style("sideshave")
def h_sideshave():
    shaved = cap("Shaved", r=0.615, top=5.2, line=hairline(5.0, 4.5, 4.3), thick=0.02)
    side = ring("Side", [(4.05, 0.69, 0.69), (4.5, 0.69, 0.69), (Z1, 0.67, 0.67)], power=HP, na=28, thick=0.05,
                a0=-PI + 0.3, a1=-0.6, angle=45)
    top = cap("Top", r=0.67, top=5.44, line=hairline(5.1, 4.9, 4.7))
    sweep, _ = surf(0.4, 0.3, lift=0.03)
    s = spike(sweep, (-0.6, 0.4, 0.2), 0.6, 0.16, bend=(-0.8, -0.2, -0.6))
    return one("Hair", [shaved, side, top, s])


@style("spikes")
def h_spikes():
    sp = spray(14, 0.2, 0.95, 0.42, 0.15, 14, up=0.3, back=0.2)
    return one("Hair", [cap(top=5.4)] + sp + fringe(5, -0.7, 0.7, 0.3, 0.11))


@style("quiff")
def h_quiff():
    puff = ball("Quiff", 0.36, (0, 0.38, 5.4), scale=(1.3, 1.1, 0.75), segs=16, rings=8)
    wear.turn(puff, (0.35, 0, 0), (0, 0.38, 5.4))
    return one("Hair", [cap(top=5.38, line=hairline(5.05, 4.5, 4.3)), puff])


@style("sidepart")
def h_sidepart():
    locks = []
    for k in range(5):
        a = lerp(-0.25, 0.9, k / 4)
        p0, _ = surf(a - 0.3, 0.75, lift=0.0)
        p2, _ = surf(a + 0.25, 0.05, lift=0.04)
        mid, _ = surf(a, 0.45, lift=0.1)
        locks.append(lock(path(tuple(p0), tuple(mid), tuple(p2)), 0.13, 0.04))
    return one("Hair", [cap(top=5.4)] + locks)


@style("bangs")
def h_bangs():
    return one("Hair", [cap(r=0.66, top=5.42)] + fringe(9, -0.95, 0.95, 0.45, 0.11, droop=1.6))


@style("messy")
def h_messy():
    rnd = random.Random(15)
    sp = []
    for k in range(16):
        a = rnd.uniform(-PI, PI)
        p, n = surf(a, rnd.uniform(0.1, 0.9), lift=-0.02)
        d = n + Vector((rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.4), rnd.uniform(-0.2, 0.6)))
        sp.append(spike(p, d, rnd.uniform(0.22, 0.38), 0.12))
    return one("Hair", [cap(top=5.4)] + sp)


@style("buzz")
def h_buzz():
    return one("Hair", [cap(r=0.62, top=5.33, line=hairline(5.02, 4.55, 4.35), thick=0.015)])


@style("slick")
def h_slick():
    grooves = lambda a, z: 0.012 * abs(math.sin(a * 9))  # noqa: E731
    tail = []
    for sx in (-0.25, 0.0, 0.25):
        p, n = surf(PI + sx, 0.15, lift=0.0)
        tail.append(spike(p, (sx * 0.3, -0.6, -0.4), 0.3, 0.1))
    return one("Hair", [cap(top=5.36, line=hairline(5.05, 4.5, 4.28), wave=grooves)] + tail)


@style("braids")
def h_braids():
    out = []
    ties = []
    for sx in (-1, 1):
        pts = path((sx * 0.35, -0.6, 4.6), (sx * 0.45, -0.72, 4.1), (sx * 0.4, -0.66, 3.4), n=8)
        out += braid(pts, 0.12)
        ties.append(tie((sx * 0.4, -0.66, 3.4), 0.08))
    return one("Hair", [cap(top=5.38)] + out + fringe(5, -0.6, 0.6, 0.18, 0.09), [(joined("Ties", ties), "a")])


@style("topbun")
def h_topbun():
    bun = ball("Bun", 0.3, (0, -0.05, 5.55), segs=16, rings=8)
    return one("Hair", [cap(top=5.38), bun] + fringe(3, -0.4, 0.4, 0.2, 0.08), [(tie((0, -0.05, 5.33), 0.18), "a")])


@style("shaggy")
def h_shaggy():
    rnd = random.Random(17)
    layers = []
    for k in range(18):
        a = lerp(-PI, PI, (k + 0.5) / 18)
        p, n = surf(a, rnd.uniform(0.0, 0.2), lift=-0.01)
        d = n * 0.35 + Vector((0, 0, -1)) + (Vector((0, 0.3, 0)) if abs(a) < 1 else Vector())
        layers.append(spike(p, d, rnd.uniform(0.3, 0.45) if abs(a) > 1 else 0.3, 0.13))
    return one("Hair", [cap(r=0.665, top=5.44)] + layers)


@style("wolf")
def h_wolf():
    rnd = random.Random(18)
    sp = spray(8, 0.45, 0.9, 0.3, 0.14, 18, up=0.5, back=0.4)
    back = []
    for k in range(9):
        a = PI + lerp(-1.3, 1.3, k / 8)
        p, n = surf(a, 0.0, z=4.4, lift=-0.01)
        back.append(spike(p, n * 0.3 + Vector((0, 0, -1)), rnd.uniform(0.45, 0.6), 0.13))
    return one("Hair", [cap(r=0.665, top=5.42, line=hairline(4.98, 4.35, 4.2))] + sp + back +
               fringe(7, -0.8, 0.8, 0.3, 0.1))


@style("pigs")
def h_pigs():
    tails, ties = [], []
    for sx in (-1, 1):
        base = Vector((sx * 0.6, -0.3, 4.45))
        pts = path(tuple(base), (sx * 0.85, -0.35, 4.3), (sx * 0.8, -0.2, 3.95), n=6)
        tails.append(lock(pts, 0.16, 0.06, segs=8))
        ties.append(kit.torus("t", 0.1, 0.035, at=tuple(base + Vector((sx * 0.06, 0, 0))), segs=12, csegs=5,
                              axis="X"))
    return one("Hair", [cap()] + tails + fringe(6, -0.7, 0.7, 0.22, 0.09), [(joined("Ties", ties), "a")])


@style("fauxhawk")
def h_fauxhawk():
    sp = [spike(surf(a, t, lift=-0.03)[0], (0, 0.3 if a == 0 else -0.3, 1), h, 0.15)
          for a, t, h in ((0.0, 0.55, 0.4), (0.0, 0.85, 0.42), (PI, 0.85, 0.38), (PI, 0.55, 0.3))]
    sides = cap(r=0.63, top=5.3, line=hairline(5.0, 4.55, 4.35), thick=0.03)
    return one("Hair", [sides] + sp)


@style("rows")
def h_rows():
    # cornrows: raised rows from the hairline over the crown and down to the nape
    ridges = []
    for k in range(7):
        x0 = lerp(-0.48, 0.48, k / 6)
        f = math.sqrt(max(0.05, 1 - (x0 / 0.66) ** 2))
        pts = []
        for j in range(10):
            ph = PI * j / 9
            pts.append((x0, 0.655 * f * math.cos(ph), Z1 + 0.36 * f * math.sin(ph)))
        pts += [(x0, -0.655 * f, 4.7), (x0 * 0.9, -0.65 * f, 4.4)]
        ridges.append(rod("r", pts, 0.05, segs=5))
    return one("Hair", [cap(r=0.62, top=5.3, thick=0.02)] + ridges)


@style("sidebraid")
def h_sidebraid():
    pts = path((0.45, -0.4, 4.6), (0.75, 0.0, 4.2), (0.7, 0.35, 3.45), n=8)
    return one("Hair", [cap(top=5.38)] + braid(pts, 0.13) + fringe(5, -0.6, 0.6, 0.22, 0.09),
               [(tie((0.7, 0.35, 3.45), 0.08), "a")])


@style("hime")
def h_hime():
    curtain = ring("Back", [(3.5, 0.72, 0.64), (4.0, 0.69, 0.66), (4.5, 0.67, 0.67), (Z1, R + 0.005, R + 0.005)],
                   power=HP, na=24, thick=0.05, a0=1.55, a1=2 * PI - 1.55, angle=45)
    locks = []
    for sx in (-1, 1):
        locks.append(ring("s", [(4.15, 0.69, 0.69), (Z1, R + 0.005, R + 0.005)], power=HP, na=6, thick=0.05,
                          a0=sx * 1.0 - 0.22, a1=sx * 1.0 + 0.22, angle=45))
    bangs = [wear.rbox("b", 1.05, 0.12, 0.2, at=(0, 0.63, 4.97), bev=0.04)]
    return one("Hair", [cap(r=0.66, top=5.42), curtain] + locks + bangs)


@style("drills")
def h_drills():
    curls = []
    for sx in (-1, 1):
        base = Vector((sx * 0.68, -0.15, 4.75))
        pts, rs = [], []
        n = 22
        for k in range(n):
            t = k / (n - 1)
            ang = 7 * PI * t
            rr = 0.15 * (1 - 0.6 * t)
            pts.append(tuple(base + Vector((sx * (0.12 + rr * math.cos(ang)), rr * math.sin(ang), -0.95 * t))))
            rs.append(0.1 * (1 - 0.6 * t) + 0.02)
        curls.append(rod("d", pts, rs, segs=7))
    return one("Hair", [cap(top=5.4)] + curls + fringe(6, -0.7, 0.7, 0.22, 0.09))


@style("flame")
def h_flame():
    rnd = random.Random(20)
    tongues = []
    for k in range(9):
        a = lerp(-PI, PI, (k + 0.5) / 9)
        p, n = surf(a, rnd.uniform(0.35, 0.85), lift=-0.03)
        wig = Vector((math.cos(a) * 0.3, -math.sin(a) * 0.3, 0)) * (1 if k % 2 else -1)
        tongues.append(spike(p, n * 0.4 + Vector((0, -0.2, 1)), rnd.uniform(0.6, 0.85), 0.2, bend=tuple(wig)))
    return one("Hair", [cap(top=5.42)] + tongues + fringe(5, -0.7, 0.7, 0.25, 0.1, droop=0.3))


@style("super")
def h_super():
    sp = []
    for k in range(11):
        a = lerp(-PI, PI, (k + 0.5) / 11)
        p, n = surf(a, 0.55 + 0.3 * (k % 2), lift=-0.03)
        sp.append(spike(p, n * 0.55 + Vector((0, -0.15, 1)), 0.95 + 0.2 * (k % 2), 0.22))
    sp += fringe(3, -0.4, 0.4, 0.32, 0.12, droop=0.8)
    return one("Hair", [cap(r=0.665, top=5.45)] + sp)


@style("crownbraid")
def h_crownbraid():
    pts = []
    for k in range(17):
        a = -PI + 2 * PI * k / 16
        p, n = surf(a, 0.45, lift=0.06)
        pts.append(tuple(p))
    return one("Hair", [cap(top=5.38)] + braid(pts, 0.12, segs=8, rings=5) + fringe(4, -0.5, 0.5, 0.18, 0.08))


# ---------------------------------------------------------------- build, export, preview
HEADER = ["hair.py",
          "The creator's hair styles as meshes (ReplicatedStorage.Art.Hair once nate imports art/export/Hair.fbx;",
          "LookKit wears them then, the part-built ones until then). Keyed by the Hair slot's kit: each piece's mesh",
          "name, the body part it is welded to (at: the head), its colour role (hair: the look's hair colour; a: the",
          "accent for ties), glow, material and transparency, and its box against the Head's centre in Roblox axes",
          "(x right, y up, z back), in studs on the standard blocky rig (scaled with the head)."]

HAIR_SAMPLES = [(60, 40, 30), (240, 200, 90), (30, 30, 36), (200, 70, 40), (245, 245, 245), (80, 120, 230),
                (230, 90, 160), (120, 70, 40)]


def preview(built):
    def dress(name, at, yaw, pal):
        i = list(built).index(name)
        hc = HAIR_SAMPLES[i % len(HAIR_SAMPLES)]
        wear.body(at, yaw, parts={"Head"}, show_hair=False)
        old = wear.FIXED["hair"]
        wear.FIXED["hair"] = hc
        wear.place(built[name], at, yaw, pal)
        wear.FIXED["hair"] = old
    out = os.path.join(kit.ROOT, "preview", "hair.png" if ONLY is None else "hair_test.png")
    # (more columns than rows: the camera's frame is fitted to the picture's width)
    wear.grid_preview(built, out, dress, cols=8, cell=3.2, px=250, focus=4.65, yaw_front=180 - 30, yaw_back=25)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Hair_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Hair.fbx"))
        wear.write_fit("HairArt", HEADER, rows)
    preview(built)
