# robots.py: the android robot pieces (Config.Enemies; EnemyRenderer). One mesh per piece shape, shared by all
# 9 robots: the game scales each piece to the robot's build (slim, normal, heavy) and colours it per kind.
# Output: art/export/Robots.fbx (import with Studio's 3D Importer, save as art/models/Robots.rbxm) and
# art/preview/robots.png (a whole robot, a damaged one and a heavy one, for review).
# Run: python art/blender/robots.py   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()

# the normal build at height 6 (EnemyRenderer BUILDS.normal); pieces are authored at these sizes
H = 6
TH, TW, TD = H * 0.3, H * 0.32, H * 0.2
HEAD, LIMB, ARM, LEG = H * 0.15, H * 0.115, H * 0.19, H * 0.235


def B(sx, sy, sz):
    """A Roblox size (x, up, depth) as Blender (x, depth, up)."""
    return sx, sz, sy


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


pieces = {}


HAIR_AT = [0.42, 0.02]


# pieces every robot draws (two of each limb) get thinned to keep a crowd of robots cheap on phones
# (ShLowerR is a mirror of the already thinned ShLowerL)
THIN = {"ShUpper": 0.6, "ShLowerL": 0.55, "ShThigh": 0.6, "ShShin": 0.5, "Spine": 0.5, "Ribs": 0.6, "Pelvis": 0.6,
        "Upper": 0.5, "Lower": 0.5, "Thigh": 0.5, "Shin": 0.5, "Elbow": 0.5, "Knee": 0.5, "Skull": 0.6, "Core": 0.6}


def done(ob):
    if ob.name in THIN:
        kit.decimate(ob, THIN[ob.name])
    kit.centre(ob)
    pieces[ob.name] = ob
    return ob


# ---------------------------------------------------------------- endoskeleton (metal)
def spine():
    bx, by, bz = B(LIMB * 0.5, TH * 0.9, LIMB * 0.5)
    parts = [kit.cyl("rod", bx * 0.22, bx * 0.22, bz, segs=10)]
    n = 6
    for i in range(n):
        z = -bz / 2 + bz * (i + 0.5) / n
        v = kit.bevel(kit.cyl("v%d" % i, bx / 2, bx / 2.2, bz / n * 0.62, at=(0, 0, z), segs=14), 0.02, 2)
        parts.append(v)
        parts.append(kit.bevel(kit.box("s%d" % i, bx * 0.25, by * 0.5, bz / n * 0.35, at=(0, -by * 0.45, z)), 0.01))
    return done(kit.join("Spine", parts))


def ribs():
    bx, by, bz = B(TW * 0.78, TH * 0.72, TD * 0.6)
    parts = [kit.bevel(kit.box("sternum", bx * 0.12, by * 0.12, bz * 0.85, at=(0, by * 0.44, 0)), 0.02)]
    n = 4
    for i in range(n):
        z = bz / 2 - bz * (i + 0.6) / n
        s = 1 - i * 0.08
        r = kit.torus("r%d" % i, 0.5, 0.045, at=(0, 0, 0), segs=28, csegs=6)
        kit.deform(r, lambda v, s=s, z=z: Vector((v.x * bx * s, v.y * by * s, v.z * bz * 0.9 + z)))
        parts.append(r)
    return done(kit.join("Ribs", parts))


def core():
    bx, by, bz = B(TW * 0.3, TW * 0.3, 0.12)
    lens = kit.bevel(kit.cyl("lens", bx / 2, bx / 2, by, axis="Y", segs=24), by * 0.3, 2)
    ring = kit.torus("ring", bx * 0.36, by * 0.35, at=(0, by * 0.2, 0), axis="Y", segs=24, csegs=6)
    return done(kit.join("Core", [lens, ring]))


def pelvis():
    # briefs-shaped hips under the belt: wide at the top, rounding into the leg sockets
    bx, by, bz = B(TW * 0.8, TH * 0.28, TD * 0.9)
    prof = [(-0.5, 0.26, 0.30), (-0.35, 0.36, 0.40), (-0.1, 0.40, 0.44), (0.2, 0.38, 0.44), (0.45, 0.36, 0.42), (0.5, 0.33, 0.38)]
    ob = kit.loft("Pelvis", [(t * bz, rx * TW, ry * TD, 0, 0) for t, rx, ry in prof], segs=24, power=2.5)
    kit.smooth(ob, 1)
    kit.shade_auto(ob, 60)
    return done(ob)


def skull():
    bx, by, bz = B(HEAD * 0.78, HEAD * 0.78, HEAD * 0.78)
    cran = kit.sphere("cran", 0.5, segs=20, rings=14)

    def shape(v):
        x, y, z = v.x, v.y, v.z
        if z < 0:
            x *= 1 - 0.35 * (-z / 0.5)  # narrower toward the jaw
            y *= 1 - 0.15 * (-z / 0.5)
        if y > 0.2 and abs(x) < 0.32 and -0.05 < z < 0.2:
            y -= 0.08  # eye sockets
        return Vector((x * bx, y * by, z * bz))

    kit.deform(cran, shape)
    brow = kit.bevel(kit.box("brow", bx * 0.9, by * 0.18, bz * 0.1, at=(0, by * 0.4, bz * 0.2)), 0.02)
    parts = [cran, brow]
    for s in (-1, 1):
        parts.append(kit.cyl("hinge%d" % s, bz * 0.12, bz * 0.12, bx * 0.1, at=(s * bx * 0.44, 0, -bz * 0.2), axis="X"))
        parts.append(kit.bevel(kit.box("cheek%d" % s, bx * 0.18, by * 0.3, bz * 0.12, at=(s * bx * 0.3, by * 0.25, -bz * 0.08)), 0.02))
    return done(kit.join("Skull", parts))


def jaw():
    bx, by, bz = B(HEAD * 0.5, HEAD * 0.18, HEAD * 0.5)
    u = kit.torus("u", 0.5, 0.12, segs=20, csegs=6, arc=math.pi)
    kit.deform(u, lambda v: Vector((v.x * bx, v.y * by + by * 0.05, v.z * bz * 2.2)))
    parts = [u]
    for i in range(6):
        a = math.pi * (i + 0.5) / 6
        parts.append(kit.box("t%d" % i, bx * 0.08, by * 0.06, bz * 0.35, at=(math.cos(a) * bx * 0.42, math.sin(a) * by * 0.42, bz * 0.3)))
    return done(kit.join("Jaw", parts))


def visor():
    bx, by, bz = B(HEAD * 0.6, HEAD * 0.12, 0.08)
    v = kit.bevel(kit.box("Eyes", bx, by, bz), min(by, bz) * 0.4, 3)
    kit.deform(v, lambda p: Vector((p.x, p.y - (p.x / bx) ** 2 * by * 1.5, p.z)))
    return done(v)


def bone(name, sx, sy, sz):
    bx, by, bz = B(sx, sy, sz)
    parts = []
    for s in (-1, 1):
        parts.append(kit.cyl("rod%d" % s, bx * 0.16, bx * 0.16, bz * 0.86, at=(s * bx * 0.22, 0, 0), segs=10))
    parts.append(kit.bevel(kit.cyl("piston", bx * 0.26, bx * 0.26, bz * 0.42, at=(bx * 0.22, 0, bz * 0.08), segs=12), 0.01))
    for z in (-1, 1):
        parts.append(kit.bevel(kit.cyl("cap%d" % z, by * 0.5, by * 0.5, bx, at=(0, 0, z * bz * 0.42), axis="X", segs=14), 0.015))
    return done(kit.join(name, parts))


def joint(name, d):
    parts = [kit.sphere("ball", d * 0.42, segs=16, rings=10), kit.torus("ring", d * 0.36, d * 0.08, axis="X", segs=20, csegs=6)]
    return done(kit.join(name, parts))


# ---------------------------------------------------------------- the shell (synthetic superhuman)
TORSO = [(-0.5, 0.34, 0.40), (-0.4, 0.35, 0.42), (-0.25, 0.37, 0.45), (-0.1, 0.40, 0.47), (0.05, 0.45, 0.50),
         (0.2, 0.49, 0.50), (0.33, 0.50, 0.48), (0.43, 0.47, 0.42), (0.5, 0.36, 0.30)]


def torso_ring(t):
    for (t0, x0, y0), (t1, x1, y1) in zip(TORSO, TORSO[1:]):
        if t0 <= t <= t1:
            k = (t - t0) / (t1 - t0)
            return (t, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
    return TORSO[0] if t < 0 else TORSO[-1]


def torso_shape(name, t0, t1, shrink=1.0):
    """One band of the torso surface between heights t0 and t1 (fractions of the torso height). The chest
    and belly are separate bands that overlap, the belly a touch smaller, so the chest plate sits over it."""
    W, D, T = TW, TD, TH
    prof = [torso_ring(t0)] + [r for r in TORSO if t0 < r[0] < t1] + [torso_ring(t1)]
    rings = [(t * T, rx * W * shrink, ry * D * shrink, 0, (0.02 * D if 0.0 < t < 0.35 else 0)) for t, rx, ry in prof]
    ob = kit.loft(name, rings, segs=28, power=2.6)
    kit.smooth(ob, 2)

    def detail(v):
        x, y, z = v.x, v.y, v.z
        t = z / T
        if y > 0:
            # pecs: a rounded bulge each side with a crease under it
            px = abs(x) / W
            k = smoothstep(-0.02, 0.1, t) * (1 - smoothstep(0.22, 0.38, t)) * smoothstep(0.03, 0.12, px) * (1 - smoothstep(0.36, 0.47, px))
            y += D * 0.09 * k
            # abs: a centre line and two cross lines
            if t < -0.08:
                g = math.exp(-(x / (W * 0.03)) ** 2) + sum(math.exp(-((t - c) / 0.025) ** 2) for c in (-0.2, -0.33)) * (abs(x) < W * 0.2)
                y -= D * 0.025 * min(1.0, g)
        return Vector((x, y, z))

    kit.deform(ob, detail)
    kit.decimate(ob, 0.4)
    return ob


def chest():
    # the chest plate: from just under the pecs to the shoulders, split down the middle
    left = torso_shape("ChestL", -0.16, 0.5)
    right = left.copy()
    right.data = left.data.copy()
    bpy.context.scene.collection.objects.link(right)
    kit.cut(left, (1, 0, 0), keep_positive=False)
    kit.cut(right, (1, 0, 0), keep_positive=True)
    left.name, right.name = "ChestL", "ChestR"
    for ob in (left, right):
        kit.shift(ob, (0, 0, -0.17 * TH))  # centred on its own box
        kit.shade_auto(ob, 50)
        done(ob)


def belly():
    lo = torso_shape("Belly", -0.5, -0.06, shrink=0.97)
    kit.shift(lo, (0, 0, 0.28 * TH))
    kit.shade_auto(lo, 50)
    return done(lo)


def belt():
    bx, by, bz = B(TW * 0.94, TH * 0.1, TD * 1.02)
    rx, ry = TW * 0.36, TD * 0.43  # the waist (the torso's bottom rings) plus the belt's thickness
    band = kit.loft("band", [(-bz / 2, rx, ry, 0, 0), (-bz * 0.3, rx * 1.02, ry * 1.02, 0, 0), (bz * 0.3, rx * 1.02, ry * 1.02, 0, 0), (bz / 2, rx, ry, 0, 0)], segs=28, power=2.6, cap=(False, False))
    m = band.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = bz * 0.4
    buckle = kit.bevel(kit.box("buckle", TW * 0.2, by * 0.12, bz * 1.15, at=(0, ry * 1.04, 0)), bz * 0.2, 2)
    return done(kit.join("Belt", [band, buckle]))


def emblem():
    bx, by, bz = B(TW * 0.26, TW * 0.26, 0.08)
    plate = kit.bevel(kit.box("plate", bx, by * 0.6, bz), bx * 0.1, 2)
    inner = kit.bevel(kit.box("inner", bx * 0.55, by, bz * 0.55), bx * 0.06, 2)
    return done(kit.join("Emblem", [plate, inner]))


def head_shape():
    hd = HEAD
    prof = [(-0.55, 0.10, 0.10, 0.30), (-0.47, 0.22, 0.24, 0.20), (-0.33, 0.35, 0.38, 0.09), (-0.17, 0.42, 0.45, 0.05),
            (0.0, 0.46, 0.48, 0.02), (0.15, 0.48, 0.5, 0.0), (0.3, 0.46, 0.49, -0.02), (0.42, 0.38, 0.43, -0.03),
            (0.5, 0.25, 0.3, -0.03), (0.55, 0.08, 0.1, -0.03)]
    rings = [(t * hd, rx * hd, ry * hd, 0, cy * hd) for t, rx, ry, cy in prof]
    ob = kit.loft("head", rings, segs=28, power=2.2)
    kit.smooth(ob, 2)

    def detail(v):
        x, y, z = v.x, v.y, v.z
        t = z / hd
        if y > 0:
            # eye hollows and a brow over them, cheekbones
            ex = abs(abs(x) / hd - 0.2)
            y -= hd * 0.04 * math.exp(-(ex / 0.1) ** 2) * math.exp(-((t - 0.04) / 0.07) ** 2)
            y += hd * 0.03 * math.exp(-(ex / 0.14) ** 2) * math.exp(-((t - 0.15) / 0.04) ** 2)
            y += hd * 0.02 * math.exp(-((abs(x) / hd - 0.3) / 0.08) ** 2) * math.exp(-((t + 0.12) / 0.06) ** 2)
            # the nose ridge
            y += hd * 0.09 * math.exp(-(x / (hd * 0.05)) ** 2) * smoothstep(0.08, -0.04, t) * smoothstep(-0.2, -0.1, t)
        return Vector((x, y, z))

    kit.deform(ob, detail)
    kit.decimate(ob, 0.45)
    for s in (-1, 1):
        ear = kit.loft("ear%d" % s, [(-0.12 * hd, 0.02 * hd, 0.06 * hd, 0, 0), (0.0, 0.04 * hd, 0.09 * hd, 0, 0), (0.1 * hd, 0.03 * hd, 0.07 * hd, 0, 0)], segs=10)
        kit.shift(ear, (s * 0.47 * hd, -0.04 * hd, 0.02 * hd))
        ob = kit.join("head", [ob, ear], shade=False)
    return ob


def face():
    f = head_shape()
    kit.cut(f, (1, 0, 0), keep_positive=False)
    f.name = "FaceL"
    kit.shade_auto(f, 60)
    done(f)
    done(kit.mirror_x(f, "FaceR"))


def hair():
    # authored taller than the old flat cap; the game sizes it with Art.fit (Hair: 1.15 x 0.75 x 1.2 heads)
    hd = HEAD
    head = head_shape()
    cap = kit.cut(head, (0, 0, 1), keep_positive=True, fill=True)
    kit.deform(cap, lambda v: Vector((v.x * 1.08, v.y * 1.08 - hd * 0.02, v.z * 1.06 + hd * 0.02)))
    kit.cut(cap, (0, 0, 1), keep_positive=True)
    parts = [cap]
    spikes = [
        # (start x, start z, direction (x, y, z), length, width) in heads; y is front (+) and back (-)
        (0.0, 0.5, (0.0, -0.5, 0.6), 0.55, 0.16), (-0.18, 0.48, (-0.3, -0.5, 0.5), 0.5, 0.15), (0.18, 0.48, (0.3, -0.5, 0.5), 0.5, 0.15),
        (-0.32, 0.36, (-0.7, -0.4, 0.15), 0.45, 0.14), (0.32, 0.36, (0.7, -0.4, 0.15), 0.45, 0.14),
        (-0.12, 0.38, (-0.2, -0.9, -0.1), 0.5, 0.15), (0.12, 0.38, (0.2, -0.9, -0.1), 0.5, 0.15),
        (-0.2, 0.42, (-0.2, 0.5, -0.4), 0.38, 0.12), (0.05, 0.45, (0.1, 0.6, -0.45), 0.4, 0.13), (0.25, 0.4, (0.35, 0.45, -0.35), 0.34, 0.11),
    ]
    for i, (sx, sz, d, length, width) in enumerate(spikes):
        dv = Vector(d).normalized()
        start = Vector((sx * hd, (0.12 if dv.y > 0 else -0.05) * hd, sz * hd))
        pts, radii = [], []
        for k in range(6):
            t = k / 5
            bend = Vector((0, 0, -0.12 * t * t)) if dv.z > 0 else Vector((0, 0, -0.05 * t * t))
            pts.append(start + (dv * t * length + bend) * hd)
            radii.append(width * hd * (1 - t) ** 1.2 + 0.002)
        parts.append(kit.tube_along("sp%d" % i, pts, radii, segs=8))
    h = kit.join("Hair", parts)
    kit.decimate(h, 0.5)
    kit.shade_auto(h, 35)
    kit.apply_all(h)
    lo = [min(v.co[i] for v in h.data.vertices) for i in range(3)]
    hi = [max(v.co[i] for v in h.data.vertices) for i in range(3)]
    HAIR_AT[:] = [(lo[2] + hi[2]) / 2 / hd, -(lo[1] + hi[1]) / 2 / hd]  # (up, back) from the head centre, in heads
    return done(h)


def eye():
    bx, by, bz = B(HEAD * 0.26, HEAD * 0.1, 0.06)
    e = kit.sphere("EyeL", 0.5, segs=16, rings=8)

    def almond(v):
        x, y, z = v.x, v.y, v.z
        z *= 1 - 0.5 * smoothstep(0.0, 0.5, -x)  # the outer corner (-x) narrows to a point
        return Vector((x * bx, y * by, z * bz * (1.2 if x > 0 else 1.0)))

    kit.deform(e, almond)
    done(e)
    done(kit.mirror_x(e, "EyeR"))


def limb(name, sx, sy, sz, prof, front=0.0, power=2.2):
    bx, by, bz = B(sx, sy, sz)
    rings = [(t * bz, r * bx, r * by * 1.0, 0, (front * by if abs(t) < 0.3 else 0)) for t, r in prof]
    ob = kit.loft(name, rings, segs=20, power=power)
    kit.smooth(ob, 1)
    kit.shade_auto(ob, 60)
    return ob


def sleeves():
    done(limb("ShUpper", LIMB, ARM, LIMB, [(-0.5, 0.40), (-0.35, 0.42), (-0.05, 0.5), (0.2, 0.49), (0.38, 0.47), (0.47, 0.38), (0.5, 0.18)], front=0.04))
    done(limb("ShThigh", LIMB * 1.1, LEG, LIMB * 1.1, [(-0.5, 0.36), (-0.3, 0.40), (0.0, 0.46), (0.3, 0.5), (0.47, 0.47), (0.5, 0.35)]))


def glove():
    bx, by, bz = B(LIMB * 0.92, ARM, LIMB * 0.92)
    arm = limb("arm", LIMB * 0.92, ARM, LIMB * 0.92, [(-0.12, 0.4), (0.05, 0.44), (0.25, 0.47), (0.4, 0.46), (0.45, 0.52), (0.5, 0.5)])
    fist = kit.loft("fist", [(-0.5 * bz, 0.30 * bx, 0.30 * by, 0, 0.04 * by), (-0.45 * bz, 0.44 * bx, 0.44 * by, 0, 0.04 * by), (-0.28 * bz, 0.48 * bx, 0.47 * by, 0, 0.03 * by), (-0.12 * bz, 0.42 * bx, 0.42 * by, 0, 0)], segs=20, power=3.2)
    kit.smooth(fist, 1)
    thumb = kit.tube_along("thumb", [Vector((bx * 0.35, by * 0.25, -bz * 0.18)), Vector((bx * 0.42, by * 0.38, -bz * 0.28)), Vector((bx * 0.3, by * 0.46, -bz * 0.36))], [bx * 0.14, bx * 0.12, bx * 0.09], segs=10)
    # finger grooves across the front of the fist
    def grooves(v):
        if v.y > by * 0.2 and -0.48 * bz < v.z < -0.14 * bz:
            g = sum(math.exp(-((v.x - c * bx) / (bx * 0.03)) ** 2) for c in (-0.2, 0.0, 0.2))
            v.y -= by * 0.04 * min(1.0, g)
        return v

    kit.deform(fist, grooves)
    parts = [arm, fist, thumb]
    g = kit.join("ShLowerL", parts)  # the thumb on +x: the inside of the left hand
    kit.shade_auto(g, 60)
    done(g)
    return done(kit.mirror_x(g, "ShLowerR"))


def boot():
    bx, by, bz = B(LIMB, LEG, LIMB * 1.15)
    shaft = kit.loft("shaft", [(-0.3 * bz, 0.40 * bx, 0.36 * by, 0, -0.08 * by), (0.0, 0.44 * bx, 0.4 * by, 0, -0.08 * by), (0.3 * bz, 0.45 * bx, 0.41 * by, 0, -0.08 * by), (0.44 * bz, 0.5 * bx, 0.45 * by, 0, -0.08 * by), (0.5 * bz, 0.48 * bx, 0.43 * by, 0, -0.08 * by)], segs=20, power=2.3)
    kit.smooth(shaft, 1)
    # the foot runs front-to-back: loft along z, then turn it so it runs along y
    foot = kit.loft("foot", [(-0.5, 0.42 * bx, 0.11 * bz, 0, 0), (-0.2, 0.47 * bx, 0.12 * bz, 0, 0.01 * bz), (0.25, 0.46 * bx, 0.1 * bz, 0, 0), (0.45, 0.36 * bx, 0.07 * bz, 0, -0.01 * bz), (0.5, 0.2 * bx, 0.04 * bz, 0, -0.02 * bz)], segs=20, power=3.0)
    kit.deform(foot, lambda v: Vector((v.x, v.z * by, v.y - 0.38 * bz)))
    kit.smooth(foot, 1)
    sole = kit.bevel(kit.box("sole", bx * 0.96, by, bz * 0.04, at=(0, 0, -0.49 * bz)), 0.01)
    b = kit.join("ShShin", [shaft, foot, sole])
    kit.shade_auto(b, 50)
    return done(b)


def cape():
    bx, by, bz = B(TW * 0.95, TH * 1.7, 0.12)
    import bmesh

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=12, y_segments=16, size=0.5)
    ob = kit._obj("Cape", bm)

    def drape(v):
        x, zz = v.x, v.y  # grid is in x, y; y becomes up
        up = zz + 0.5  # 0 at the bottom, 1 at the shoulders
        w = 0.75 + 0.25 * (1 - up)  # wider toward the hem
        y = -0.35 * (x * 2) ** 2 * (1 - up) - 0.15 * math.sin(x * 9 + up * 2) * (1 - up) ** 2
        z = zz * bz
        if up < 0.06:
            z += math.sin(x * 25) * bz * 0.02
        return Vector((x * bx * w, y * 1.2, z))

    kit.deform(ob, drape)
    m = ob.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = 0.05
    return done(ob)


def jet():
    bx, by, bz = B(LIMB * 0.8, LIMB * 1.6, LIMB * 0.8)
    parts = [kit.bevel(kit.cyl("body", bx * 0.38, bx * 0.42, bz * 0.6, at=(0, 0, bz * 0.15), segs=14), 0.02)]
    parts.append(kit.cyl("flare", bx * 0.36, bx * 0.5, bz * 0.3, at=(0, 0, -bz * 0.32), segs=14))
    for i in range(3):
        a = i * 2 * math.pi / 3
        parts.append(kit.box("fin%d" % i, bx * 0.06, bx * 0.3, bz * 0.4, at=(math.cos(a) * bx * 0.42, math.sin(a) * bx * 0.42, bz * 0.1)))
    return done(kit.join("Jet", parts))


def cannon():
    bx, by, bz = B(LIMB * 1.6, LIMB * 1.6, ARM * 1.8)  # the barrel runs along depth (Blender y)
    parts = [kit.bevel(kit.cyl("barrel", bx * 0.36, bx * 0.3, by, axis="Y", segs=18), 0.03)]
    for i in range(4):
        parts.append(kit.torus("fin%d" % i, bx * 0.4, bx * 0.06, at=(0, -by * 0.3 + i * by * 0.14, 0), axis="Y", segs=18, csegs=6))
    parts.append(kit.bevel(kit.box("grip", bx * 0.9, by * 0.35, bz * 0.9, at=(0, -by * 0.32, 0)), 0.05, 2))
    return done(kit.join("Cannon", parts))


def muzzle():
    bx, by, bz = B(LIMB, LIMB, 0.3)
    return done(kit.join("Muzzle", [kit.torus("m", bx * 0.38, bx * 0.12, axis="Y", segs=20, csegs=8)]))


def base():
    bx, by, bz = B(TW * 1.6, 0.6, TW * 1.6)
    plate = kit.bevel(kit.cyl("hex", bx / 2, bx / 2 * 0.96, bz, segs=6), bz * 0.2, 2)
    ring = kit.torus("ring", bx * 0.3, bz * 0.2, at=(0, 0, bz * 0.45), segs=24, csegs=6)
    return done(kit.join("Base", [plate, ring]))


def guard():
    bx, by, bz = B(TW * 1.1, TH * 1.5, 0.35)
    import bmesh

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=10, y_segments=14, size=0.5)
    ob = kit._obj("Guard", bm)
    kit.deform(ob, lambda v: Vector((v.x * bx * (1 - 0.25 * max(0.0, -v.y * 2) ** 2), -(v.x * 2) ** 2 * by * 0.5 - (v.y * 2) ** 2 * by * 0.2, v.y * bz)))
    m = ob.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = 0.1
    kit.bevel(ob, 0.03, 2)
    return done(ob)


def tank():
    bx, by, bz = B(TW * 0.32, TH * 0.85, TW * 0.32)
    parts = [kit.cyl("body", bx / 2, bx / 2, bz * 0.7, segs=16)]
    for s in (-1, 1):
        parts.append(kit.sphere("cap%d" % s, bx / 2, at=(0, 0, s * bz * 0.35), scale=(1, 1, 0.6), segs=16, rings=8))
    parts.append(kit.cyl("valve", bx * 0.12, bx * 0.12, bz * 0.1, at=(0, 0, bz * 0.49), segs=8))
    parts.append(kit.torus("band", bx * 0.5, bx * 0.05, at=(0, 0, 0), segs=18, csegs=6))
    return done(kit.join("Tank", parts))


def collar():
    bx, by, bz = B(HEAD * 1.3, HEAD * 0.2, HEAD * 1.3)
    c = kit.torus("Collar", 0.4, 0.1, segs=28, csegs=8)
    kit.deform(c, lambda v: Vector((v.x * bx, v.y * by, v.z * bz * 4)))
    return done(c)


def mask():
    bx, by, bz = B(HEAD * 1.05, HEAD * 0.35, HEAD * 1.05)
    m = kit.torus("Mask", 0.45, 0.06, segs=28, csegs=8)
    kit.deform(m, lambda v: Vector((v.x * bx, v.y * by, v.z * bz * 6)))
    return done(m)


def bag():
    bx, by, bz = B(TW * 0.7, TH * 0.7, TD * 0.8)
    s = kit.sphere("sack", 0.5, segs=18, rings=12)
    kit.deform(s, lambda v: Vector((v.x * bx * (1 - 0.5 * max(0.0, v.z) ** 2), v.y * by * (1 - 0.5 * max(0.0, v.z) ** 2), v.z * bz * 0.9)))
    knot = kit.sphere("knot", bx * 0.1, at=(0, 0, bz * 0.45), segs=10, rings=6)
    return done(kit.join("Bag", [s, knot]))


spine(); ribs(); core(); pelvis(); skull(); jaw(); visor()
bone("Upper", LIMB * 0.5, ARM * 0.94, LIMB * 0.5)
bone("Lower", LIMB * 0.45, ARM * 0.94, LIMB * 0.45)
bone("Thigh", LIMB * 0.55, LEG * 0.94, LIMB * 0.55)
bone("Shin", LIMB * 0.5, LEG * 0.94, LIMB * 0.5)
joint("Elbow", LIMB * 0.7); joint("Knee", LIMB * 0.75)
chest(); belly(); belt(); emblem(); face(); hair(); eye()
sleeves(); glove(); boot(); cape(); jet(); cannon(); muzzle(); base(); guard(); tank(); collar(); mask(); bag()

total = 0
for name, ob in sorted(pieces.items()):
    t = kit.tris(ob)
    total += t
    print("%-8s %5d tris" % (name, t))
print("total", total, "tris in", len(pieces), "pieces")
TWICE = ("Upper", "Lower", "Thigh", "Shin", "Elbow", "Knee", "ShUpper", "ShThigh", "ShShin")
ONE = ("Spine", "Ribs", "Core", "Pelvis", "Skull", "Jaw", "Eyes", "ChestL", "ChestR", "Belly", "Belt", "Emblem",
       "FaceL", "FaceR", "Hair", "EyeL", "EyeR", "ShLowerL", "ShLowerR")
print("one plain robot", sum(kit.tris(pieces[n]) for n in ONE) + 2 * sum(kit.tris(pieces[n]) for n in TWICE), "tris")
if "--flip" in sys.argv:
    # if Studio's importer ever turns the robots round, export them turned 180 degrees instead
    for ob in pieces.values():
        for v in ob.data.vertices:
            v.co.x, v.co.y = -v.co.x, -v.co.y
kit.export_fbx(list(pieces.values()), os.path.join(kit.ROOT, "export", "Robots.fbx"))

# The game sizes each mesh to its piece's box. Where a mesh is authored at a different size than the box
# (the belt hugs the waist, the hair stands up), write_fit (below) writes the ratio so the game fits it the
# way it was made.



# ---------------------------------------------------------------- preview: whole robots posed like the game
def dims(h, build):
    b = {"slim": (0.28, 0.17, 0.1, 0.15), "normal": (0.32, 0.2, 0.115, 0.15), "heavy": (0.42, 0.27, 0.155, 0.13)}[build]
    return dict(h=h, TH=h * 0.3, TW=h * b[0], TD=h * b[1], HEAD=h * b[3], LIMB=h * b[2], ARM=h * 0.19, LEG=h * 0.235)


def sizes(d):
    W, Hh, D, hd, l, a, g = d["TW"], d["TH"], d["TD"], d["HEAD"], d["LIMB"], d["ARM"], d["LEG"]
    return {
        "Spine": (l * 0.5, Hh * 0.9, l * 0.5), "Ribs": (W * 0.78, Hh * 0.72, D * 0.6), "Core": (W * 0.3, W * 0.3, 0.12),
        "Pelvis": (W * 0.8, Hh * 0.28, D * 0.9), "Skull": (hd * 0.78,) * 3, "Jaw": (hd * 0.5, hd * 0.18, hd * 0.5),
        "Eyes": (hd * 0.6, hd * 0.12, 0.08), "Upper": (l * 0.5, a * 0.94, l * 0.5), "Lower": (l * 0.45, a * 0.94, l * 0.45),
        "Thigh": (l * 0.55, g * 0.94, l * 0.55), "Shin": (l * 0.5, g * 0.94, l * 0.5), "Elbow": (l * 0.7,) * 3,
        "Knee": (l * 0.75,) * 3, "ChestL": (W * 0.5, Hh * 0.6, D), "ChestR": (W * 0.5, Hh * 0.6, D),
        "Belly": (W * 0.9, Hh * 0.4, D * 0.95), "Belt": (W * 0.94, Hh * 0.1, D * 1.02), "Emblem": (W * 0.26, W * 0.26, 0.08),
        "FaceL": (hd * 0.5, hd * 1.1, hd), "FaceR": (hd * 0.5, hd * 1.1, hd), "Hair": (hd * 1.06, hd * 0.3, hd * 1.06),
        "EyeL": (hd * 0.26, hd * 0.1, 0.06), "EyeR": (hd * 0.26, hd * 0.1, 0.06), "ShUpper": (l, a, l),
        "ShLower": (l * 0.92, a, l * 0.92), "ShThigh": (l * 1.1, g, l * 1.1), "ShShin": (l, g, l * 1.15),
        "Cape": (W * 0.95, Hh * 1.7, 0.12),
    }


AUTHORED = sizes(dims(6, "normal"))


def write_fit():
    fit = {}
    rows = []
    for name in sorted(pieces):
        key = name if name in AUTHORED else name[:-1]  # ShLowerL and ShLowerR share the ShLower box
        if key not in AUTHORED:
            continue
        dm, box_ = pieces[name].dimensions, AUTHORED[key]
        fx, fy, fz = dm.x / box_[0], dm.z / box_[1], dm.y / box_[2]
        if name in ("ChestL", "ChestR", "FaceL", "FaceR"):
            fx = 1.0  # the halves fill their box across so they meet in the middle
        if max(abs(fx - 1), abs(fy - 1), abs(fz - 1)) > 0.04:
            fit[name] = (fx, fy, fz)
            rows.append("\t\t%s = { %.3f, %.3f, %.3f }," % (name, fx, fy, fz))
    text = "\n".join([
        "-- GENERATED by art/blender/robots.py: do not edit by hand.",
        "-- How the robot meshes (ReplicatedStorage.Art.Robots) sit on EnemyRenderer's pieces when they are there.",
        "return {",
        "\t-- each mesh's size against its piece's box (x, up, depth); pieces not listed fill their box",
        "\tfit = {",
    ] + rows + [
        "\t},",
        "\t-- where the hair mesh's centre sits from the head centre, in heads (up, back)",
        "\thair = { %.3f, %.3f }," % tuple(HAIR_AT),
        "}",
        "",
    ])
    path = os.path.join(kit.ROOT, "..", "src", "config", "ArtFit.luau")
    with open(path, "w") as f:
        f.write(text)
    print("wrote", os.path.normpath(path))
    return fit


FIT = write_fit()


def robot(at, h, build, suit, trim, metal, eye, skin, hairc, shell_off=(), cape_col=None):
    d = dims(h, build)
    S = sizes(d)
    W, Hh, D, hd, l, a, g = d["TW"], d["TH"], d["TD"], d["HEAD"], d["LIMB"], d["ARM"], d["LEG"]
    endo = [c / 255 for c in (168, 172, 182)]
    mcol = [endo[i] + (metal[i] / 255 - endo[i]) * 0.35 for i in range(3)]
    dark = [c / 255 * 0.55 for c in metal]
    mats = {
        "metal": kit.material("metal%s" % str(metal), [c * 255 for c in mcol], metal=0.9, rough=0.3),
        "dark": kit.material("dark%s" % str(metal), [c * 255 for c in dark], metal=0.8, rough=0.45),
        "eye": kit.material("eye%s" % str(eye), eye, emit=6),
        "suit": kit.material("suit%s" % str(suit), suit, rough=0.55),
        "trim": kit.material("trim%s" % str(trim), trim, rough=0.4),
        "skin": kit.material("skin%s" % str(skin), skin, rough=0.6),
        "hair": kit.material("hair%s" % str(hairc), hairc, rough=0.5),
    }
    if cape_col:
        mats["cape"] = kit.material("cape%s" % str(cape_col), cape_col, rough=0.7)
    hipY = -h * 0.5 + g * 2
    hips = Vector((0, hipY, 0))
    torso = hips + Vector((0, Hh * 0.64, 0))
    neck = torso + Vector((0, Hh * 0.5 + hd * 0.58, 0))
    place = []

    def put(mesh, pos, mat, size_key=None, rot=None):
        if mesh in shell_off:
            return
        src = pieces[mesh]
        key = size_key or mesh
        ob = src.copy()
        ob.data = src.data.copy()
        ob.hide_render = False
        bpy.context.scene.collection.objects.link(ob)
        f = FIT.get(mesh, (1, 1, 1))
        t, dm = [S[key][i] * f[i] for i in range(3)], src.dimensions  # the game fits each mesh to box x fit, like this
        ob.scale = (t[0] / max(dm.x, 1e-4), t[2] / max(dm.y, 1e-4), t[1] / max(dm.z, 1e-4))
        ob.location = (at[0] + pos.x, at[1] - pos.z, at[2] + pos.y + h * 0.5)
        if rot:
            ob.rotation_euler = rot
        ob.data.materials.clear()
        ob.data.materials.append(mats[mat])
        place.append(ob)

    put("Pelvis", hips, "suit")
    put("Spine", torso + Vector((0, 0, D * 0.12)), "metal")
    put("Ribs", torso + Vector((0, Hh * 0.1, 0)), "dark")
    put("Core", torso + Vector((0, Hh * 0.12, -D * 0.3 - 0.06)), "eye")
    put("Skull", neck + Vector((0, hd * 0.05, 0)), "metal")
    put("Jaw", neck + Vector((0, -hd * 0.36, -hd * 0.1)), "dark")
    put("Eyes", neck + Vector((0, hd * 0.08, -hd * 0.39 - 0.02)), "eye")
    put("ChestL", torso + Vector((-W * 0.25, Hh * 0.2, 0)), "suit")
    put("ChestR", torso + Vector((W * 0.25, Hh * 0.2, 0)), "suit")
    put("Belly", torso + Vector((0, -Hh * 0.3, 0)), "suit")
    put("Belt", torso + Vector((0, -Hh * 0.44, 0)), "trim")
    put("Emblem", torso + Vector((0, Hh * 0.24, -D * 0.58 - 0.04)), "trim", rot=(0, math.radians(45), 0))
    put("FaceL", neck + Vector((-hd * 0.25, 0, 0)), "skin")
    put("FaceR", neck + Vector((hd * 0.25, 0, 0)), "skin")
    put("Hair", neck + Vector((0, hd * HAIR_AT[0], hd * HAIR_AT[1])), "hair")
    put("EyeL", neck + Vector((-hd * 0.2, hd * 0.08, -hd * 0.5 - 0.03)), "eye")
    put("EyeR", neck + Vector((hd * 0.2, hd * 0.08, -hd * 0.5 - 0.03)), "eye")
    if cape_col:
        put("Cape", torso + Vector((0, Hh * 0.48 - Hh * 0.85, D * 0.5 + 0.2)), "cape", rot=(math.radians(-8), 0, 0))
    for sign, side in ((-1, "L"), (1, "R")):
        sh = torso + Vector((sign * (W * 0.5 + l * 0.55), Hh * 0.38, 0))
        up = sh + Vector((0, -a * 0.5, 0))
        el = up + Vector((0, -a * 0.5, 0))
        lo = el + Vector((0, -a * 0.5, 0))
        put("Upper", up, "metal"); put("Elbow", el, "dark"); put("Lower", lo, "metal")
        if "ShUpper" + side not in shell_off:
            put("ShUpper", up, "suit")
        if "ShLower" + side not in shell_off:
            put("ShLower" + side, lo, "trim", "ShLower")
        hp = hips + Vector((sign * W * 0.25, -Hh * 0.1, 0))
        th = hp + Vector((0, -g * 0.5, 0))
        kn = th + Vector((0, -g * 0.5, 0))
        sn = kn + Vector((0, -g * 0.5, 0))
        put("Thigh", th, "metal"); put("Knee", kn, "dark"); put("Shin", sn, "metal")
        if "ShThigh" + side not in shell_off:
            put("ShThigh", th, "suit")
        if "ShShin" + side not in shell_off:
            put("ShShin", sn, "trim")
    return place


if "--preview" in sys.argv:
    import bpy

    for ob in pieces.values():
        ob.hide_render = True
    kit.studio(res=(1400, 900), samples=48)
    robot((-4.2, 0, 0), 6, "slim", (40, 70, 140), (255, 170, 60), (120, 130, 145), (255, 120, 60), (240, 190, 150), (30, 26, 24))
    robot((0, 0, 0), 6, "normal", (62, 62, 72), (30, 30, 36), (70, 70, 85), (255, 220, 80), (198, 140, 96), (160, 120, 60),
          shell_off=("ShUpperL", "ShLowerL", "ShThighR", "ShShinR", "Belly", "ChestL", "FaceL", "EyeL", "Hair"))
    robot((5.2, 0, 0), 7.5, "heavy", (30, 30, 42), (235, 235, 245), (35, 35, 45), (255, 255, 255), (141, 95, 64), (225, 225, 230),
          cape_col=(92, 40, 140))
    floor = kit.cyl("floor", 14, 14, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((1.0, 15.5, 5.2), (0.6, 0, 3.4), lens=45)
    kit.render(os.path.join(kit.ROOT, "preview", "robots.png"))
