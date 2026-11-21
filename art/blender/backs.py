# backs.py: the hero creator's back bling as meshes (creator art round 3, 2026-11-18), in place of the boxes, balls,
# wedges and cylinders PieceKits welds to the upper torso's back for the Back bling slot. Every piece is welded to
# the upper torso (2 x 1.6 x 1, z 2.4 to 4.0; kit.py axes: +y the front, so the back is y = -0.5): packs, tanks
# and a jetpack with their straps over the shoulders, a sword in its sheath, a quiver, a shield, wings (feathers,
# bat, energy, butterfly), rings and orbs that float off the back, a banner, a scroll, cogs, fins, a radio pack and
# an umbrella. Bright, chunky comic shapes that read on a phone at a distance; all original.
# Output: art/export/Backs.fbx (nate imports it as ReplicatedStorage.Art.Backs), src/config/BackArt.luau (LookKit's
# fit) and art/preview/backs.png (each kit from behind three-quarter and from the front).
# Run: python art/blender/backs.py [--quick] [--only kit,kit]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, ring, rbox, ball, rod, joined, outline, strip  # noqa: E402
import bpy  # noqa: E402, F401
from mathutils import Vector  # noqa: E402

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 3000  # triangles a back piece
BY = -0.5  # the torso's back
CZ = 3.2  # the torso's centre

kit.reset()

STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


def T(ob, role, glow=False, mat=None, alpha=0.0):
    wear.bake(ob)
    return Piece(ob, "torso", role, glow, mat, alpha)


def straps(width=0.16, x=0.5, front_to=2.6, thick=0.035):
    """Two straps from the pack over the shoulders and down the chest."""
    out = []
    for sx in (-1, 1):
        pts = [(sx * x, BY - 0.12, 3.45), (sx * x, BY - 0.06, 3.95), (sx * x, -0.25, 4.04), (sx * x, 0.25, 4.04),
               (sx * x, 0.53, 3.9), (sx * x * 1.05, 0.535, 3.2), (sx * x * 1.1, 0.53, front_to)]
        out.append(strip("st", pts, width, up=(1, 0, 0), thick=thick))
    return out


def cylinder_z(name, r, h, at, segs=16, round_ends=True):
    c = kit.cyl(name, r, r, h, at=at, segs=segs)
    parts = [c]
    if round_ends:
        for s in (-1, 1):
            parts.append(ball("e", r, (at[0], at[1], at[2] + s * h / 2), scale=(1, 1, 0.45), segs=segs, rings=4))
    return joined(name, parts, 50)


def tilt(ob, ang, pivot, axis=1):
    e = [0, 0, 0]
    e[axis] = ang
    return wear.turn(ob, tuple(e), pivot)


def feather_wing(sx, n=7, span=2.0, w=0.5, at=(0.3, BY - 0.12, 3.7), coverts=True):
    """One wing of broad feather blades fanning out and up from the shoulder blade (sx: -1 left, 1 right), with a
    shorter row of covert feathers over their roots."""
    blades = []
    base = Vector((sx * at[0], at[1], at[2]))
    rows = [(n, span, w, 0.0)] + ([(n - 2, span * 0.55, w * 0.9, -0.06)] if coverts else [])
    for count, length0, width, dy in rows:
        for k in range(count):
            t = k / (count - 1)
            ang = 1.05 - 1.55 * t  # from up-and-out down to out-and-down
            d = Vector((sx * math.cos(ang), -0.22, math.sin(ang)))
            length = length0 * (1.0 - 0.4 * t)
            pts, ws = [], []
            for j in range(7):
                u = j / 6
                pts.append(base + d * length * u + Vector((0, dy - 0.1 * u * u, 0)))
                ws.append(max(0.03, width * (0.45 + 0.55 * math.sin(PI * min(1.0, 0.25 + u * 0.8)))
                              * (1 - 0.85 * u ** 4)))
            # (2026-11-21: the blades lay edge-on to the back, so the wings read as sticks; now flat to it)
            blades.append(strip("f", pts, ws, up=tuple(d.cross(Vector((0, 1, 0)))), thick=0.04))
    return blades


# ---------------------------------------------------------------- the 22 kits
@style("backpack")
def p_backpack():
    body = rbox("Body", 1.5, 0.55, 1.4, at=(0, BY - 0.29, 3.15), bev=0.18, segs=3)
    pocket = rbox("Pocket", 1.0, 0.22, 0.55, at=(0, BY - 0.6, 2.85), bev=0.08)
    flap = rbox("Flap", 1.54, 0.61, 0.32, at=(0, BY - 0.3, 3.78), bev=0.1)
    pflap = rbox("PFlap", 1.04, 0.25, 0.15, at=(0, BY - 0.61, 3.08), bev=0.05)
    buckles = [rbox("b", 0.12, 0.06, 0.12, at=(x, BY - 0.74, 3.08), bev=0.02) for x in (-0.28, 0.28)]
    buckles += [rbox("b", 0.12, 0.06, 0.12, at=(x, BY - 0.62, 3.68), bev=0.02) for x in (-0.4, 0.4)]
    return [T(joined("Body", [body, pocket], 40), "s", mat="Fabric"), T(joined("Flaps", [flap, pflap]), "p",
                                                                         mat="Fabric"),
            T(joined("Straps", straps()), "dark", mat="Fabric"), T(joined("Buckles", buckles), "gold", mat="Metal")]


def sword_back(at, ang, length=2.3):
    """A sheathed sword across the back: (sheath, fittings, grip) meshes, tilted `ang` about y."""
    x, y, z = at
    sheath = rbox("Sheath", 0.22, 0.14, length, at=(x, y, z), bev=0.06)
    throat = rbox("Throat", 0.28, 0.18, 0.12, at=(x, y, z + length / 2), bev=0.03)
    chape = wear.cone("Chape", 0.12, 0.04, 0.16, (x, y, z - length / 2 - 0.12), segs=8)
    guard = rbox("Guard", 0.6, 0.16, 0.08, at=(x, y, z + length / 2 + 0.1), bev=0.03)
    pommel = ball("Pommel", 0.09, (x, y, z + length / 2 + 0.72), segs=10, rings=6)
    grip = kit.cyl("Grip", 0.06, 0.06, 0.55, at=(x, y, z + length / 2 + 0.42), segs=8)
    wraps = [kit.torus("w", 0.065, 0.018, at=(x, y, z + length / 2 + 0.2 + 0.09 * k), segs=8, csegs=4)
             for k in range(5)]
    obs = [sheath, throat, chape, guard, pommel, grip] + wraps
    for o in obs:
        tilt(o, ang, at)
    return sheath, joined("Fittings", [throat, chape, guard, pommel], 40), joined("Grip", [grip] + wraps, 50)


@style("sheath")
def p_sheath():
    sheath, fit, grip = sword_back((0.0, BY - 0.12, 3.2), 0.6)
    band_f = strip("bf", [(-0.95, 0.53, 4.0), (0.0, 0.54, 3.2), (0.95, 0.53, 2.45)], 0.14, up=(0, 1, 0), thick=0.03)
    band_b = strip("bb", [(-0.95, BY - 0.03, 4.0), (0.0, BY - 0.04, 3.2), (0.95, BY - 0.03, 2.45)], 0.14,
                   up=(0, 1, 0), thick=0.03)
    return [T(sheath, "dark", mat="Leather"), T(fit, "gold", mat="Metal"), T(grip, "s", mat="Fabric"),
            T(joined("Strap", [band_f, band_b]), "s", mat="Leather")]


@style("quiver")
def p_quiver():
    q = cylinder_z("Quiver", 0.24, 1.5, (0.45, BY - 0.25, 3.25), segs=14, round_ends=False)
    bottom = ball("Bot", 0.24, (0.45, BY - 0.25, 2.5), scale=(1, 1, 0.4), segs=14, rings=4)
    rimq = kit.torus("Rim", 0.25, 0.04, at=(0.45, BY - 0.25, 4.0), segs=16, csegs=5)
    band = kit.torus("Band", 0.25, 0.035, at=(0.45, BY - 0.25, 3.0), segs=16, csegs=5)
    shafts, fletch = [], []
    for k, (dx, dy) in enumerate(((-0.1, 0.05), (0.08, -0.06), (0.0, 0.1), (0.12, 0.08), (-0.08, -0.1))):
        x, y = 0.45 + dx, BY - 0.25 + dy
        shafts.append(kit.cyl("s", 0.025, 0.025, 0.55, at=(x, y, 4.15), segs=6))
        for a in (0.0, 2 * PI / 3, 4 * PI / 3):
            f = outline("f", [(0, 0), (0.09, 0.05), (0.09, 0.26), (0, 0.3)], 0.015,
                        at=(x, y, 4.2), axis="Y")
            wear.turn(f, (0, 0, a), (x, y, 4.2))
            fletch.append(f)
    obs = [q, bottom, rimq, band] + shafts + fletch
    for o in obs:
        tilt(o, -0.35, (0.45, BY - 0.25, 3.25))
    strap = strip("Strap", [(-0.8, 0.53, 4.0), (0.0, 0.54, 3.2), (0.85, 0.53, 2.5)], 0.12, up=(0, 1, 0), thick=0.03)
    return [T(joined("Quiver", [q, bottom]), "s", mat="Leather"), T(joined("Trim", [rimq, band, strap]), "dark",
                                                                    mat="Leather"),
            T(joined("Shafts", shafts), "dark", mat="Wood"), T(joined("Fletch", fletch, 20), "white", mat="Fabric")]


@style("tanks")
def p_tanks():
    tanks, valves = [], []
    for sx in (-1, 1):
        tanks.append(cylinder_z("t", 0.27, 1.25, (sx * 0.33, BY - 0.3, 3.15), segs=16))
        valves.append(kit.cyl("v", 0.07, 0.07, 0.16, at=(sx * 0.33, BY - 0.3, 3.95), segs=8))
        valves.append(kit.cyl("k", 0.11, 0.11, 0.05, at=(sx * 0.33, BY - 0.3, 4.05), segs=10))
    hose = rod("Hose", [(-0.33, BY - 0.3, 4.05), (-0.2, BY - 0.3, 4.35), (0.2, BY - 0.3, 4.35),
                        (0.33, BY - 0.3, 4.05)], 0.04, segs=6)
    harness = [kit.torus("h", 0.3, 0.04, at=(sx * 0.33, BY - 0.3, z), segs=16, csegs=4)
               for sx in (-1, 1) for z in (2.8, 3.45)]
    stripes = [kit.torus("s", 0.28, 0.025, at=(sx * 0.33, BY - 0.3, 3.15), segs=16, csegs=4) for sx in (-1, 1)]
    return [T(joined("Tanks", tanks, 50), "white", mat="Metal"),
            T(joined("Valves", valves + [hose] + harness, 50), "dark", mat="Metal"),
            T(joined("Stripes", stripes), "a"), T(joined("Straps", straps()), "dark", mat="Fabric")]


@style("jetpack")
def p_jetpack():
    body = rbox("Body", 1.05, 0.45, 1.2, at=(0, BY - 0.25, 3.25), bev=0.14, segs=3)
    fins = [outline("fin", [(0, 0), (0.28, -0.15), (0.28, 0.35), (0, 0.5)], 0.05, at=(sx * 0.52, BY - 0.3, 3.3),
                    axis="Y") for sx in (-1, 1)]
    for sx, f in zip((-1, 1), fins):
        if sx < 0:
            for v in f.data.vertices:
                v.co.x = -0.52 - (v.co.x + 0.52)
            f.data.flip_normals()
    nozzles, flames = [], []
    for sx in (-1, 1):
        nozzles.append(kit.cyl("n", 0.18, 0.22, 0.4, at=(sx * 0.33, BY - 0.32, 2.5), segs=14))
        nozzles.append(kit.torus("nr", 0.21, 0.035, at=(sx * 0.33, BY - 0.32, 2.3), segs=14, csegs=4))
        flames.append(wear.cone("f", 0.17, 0.0, 0.55, (sx * 0.33, BY - 0.32, 2.28), segs=10, axis=(0, 0, -1)))
    light = rbox("Light", 0.5, 0.05, 0.1, at=(0, BY - 0.49, 3.55), bev=0.02)
    return [T(joined("Body", [body] + fins, 40), "dark", mat="Metal"), T(joined("Nozzles", nozzles, 50), "s",
                                                                          mat="Metal"),
            T(joined("Flames", flames, 60), "a", True, alpha=0.2), T(light, "a", True),
            T(joined("Straps", straps(0.14)), "dark", mat="Fabric")]


@style("shield")
def p_shield():
    r = 0.98
    face = kit.cyl("Face", r, r, 0.1, at=(0, BY - 0.12, 3.25), segs=32, axis="Y")
    for v in face.data.vertices:
        d = math.hypot(v.co.x, v.co.z - 3.25) / r
        v.co.y -= 0.12 * (1 - d * d)
    kit.shade_auto(face, 50)
    rim_ = kit.torus("Rim", r, 0.07, at=(0, BY - 0.12, 3.25), segs=32, csegs=6, axis="Y")
    chev = outline("Chevron", [(-0.5, 0.15), (0.0, -0.3), (0.5, 0.15), (0.5, 0.42), (0.0, -0.03), (-0.5, 0.42)],
                   0.05, at=(0, BY - 0.27, 3.2), axis="Y", bev=0.01)
    boss = ball("Boss", 0.16, (0, BY - 0.3, 3.3), scale=(1, 0.5, 1), segs=12, rings=6)
    return [T(face, "p", mat="Metal"), T(rim_, "s", mat="Metal"), T(chev, "a"), T(boss, "gold", mat="Metal")]


@style("drone")
def p_drone():
    c = (0.95, BY - 0.4, 4.45)
    body = ball("Body", 0.32, c, scale=(1, 1, 0.8), segs=16, rings=8)
    eye = ball("Eye", 0.1, (c[0] - 0.08, c[1] + 0.3, c[2]), scale=(1, 0.5, 1), segs=10, rings=5)
    rotors = []
    for sx in (-1, 1):
        arm = rod("a", [(c[0], c[1], c[2] + 0.1), (c[0] + sx * 0.45, c[1], c[2] + 0.25)], 0.03, segs=5)
        disc = kit.cyl("d", 0.18, 0.18, 0.02, at=(c[0] + sx * 0.45, c[1], c[2] + 0.28), segs=14)
        rotors += [arm, disc]
    tether = rod("Tether", [(0.6, BY - 0.02, 3.6), (0.8, BY - 0.25, 4.0), (c[0], c[1], c[2] - 0.2)], 0.025, segs=5)
    dock = rbox("Dock", 0.45, 0.14, 0.45, at=(0.55, BY - 0.07, 3.55), bev=0.05)
    ring_ = kit.torus("Band", 0.3, 0.03, at=c, segs=16, csegs=4)
    return [T(body, "dark", mat="Metal"), T(eye, "a", True), T(joined("Rotors", rotors + [ring_]), "s", mat="Metal"),
            T(joined("Dock", [dock, tether]), "dark", mat="Metal")]


@style("wings")
def p_wings():
    out = []
    for sx, nm in ((-1, "WingL"), (1, "WingR")):
        out.append(T(joined(nm, feather_wing(sx), 60), "white", mat="Fabric"))
    out.append(T(rbox("Mount", 0.5, 0.12, 0.5, at=(0, BY - 0.06, 3.6), bev=0.08), "gold", mat="Metal"))
    return out


def membrane_wing(name, sx, span=2.2):
    """A bat wing: bone spars from the shoulder blade and a scalloped skin between them."""
    root = Vector((sx * 0.3, BY - 0.12, 3.7))
    tips = [Vector((sx * span * 0.45, BY - 0.35, 4.75)), Vector((sx * span, BY - 0.45, 4.2)),
            Vector((sx * span * 1.05, BY - 0.45, 3.4)), Vector((sx * span * 0.7, BY - 0.35, 2.7))]
    spars = [rod("s", [tuple(root), tuple((root + t) / 2 + Vector((0, 0, 0.08))), tuple(t)], [0.06, 0.045, 0.02],
                 segs=6) for t in tips]
    import bmesh
    bm = bmesh.new()
    rv = bm.verts.new(root)
    prev = None
    for k, t in enumerate(tips):
        tv = bm.verts.new(t)
        if prev is not None:
            mid = (tips[k - 1] + t) / 2
            mid = root + (mid - root) * 0.72
            mv = bm.verts.new(mid)
            bm.faces.new([rv, prev, mv])
            bm.faces.new([rv, mv, tv])
        prev = tv
    ob = kit._obj(name, bm)
    wear.solid(ob, 0.03, 0.0)
    kit.shade_auto(ob, 30)
    return ob, spars


@style("bat")
def p_bat():
    out = []
    bones = []
    for sx, nm in ((-1, "WingL"), (1, "WingR")):
        skin, spars = membrane_wing(nm, sx)
        out.append(T(skin, "dark", mat="Leather"))
        bones += spars
    out.append(T(joined("Bones", bones, 50), "s"))
    return out


@style("ring")
def p_ring():
    halo = kit.torus("Ring", 1.1, 0.07, at=(0, BY - 0.45, 3.75), segs=40, csegs=6, axis="Y")
    inner = kit.torus("Inner", 0.92, 0.025, at=(0, BY - 0.45, 3.75), segs=40, csegs=4, axis="Y")
    sparks = [ball("s", 0.07, (1.1 * math.cos(a), BY - 0.45, 3.75 + 1.1 * math.sin(a)), segs=8, rings=4)
              for a in (0.3, 1.9, 3.5, 5.0)]
    for o in (halo, inner):
        kit.shade_auto(o, 60)
    return [T(halo, "a", True, alpha=0.15), T(joined("Glints", [inner] + sparks), "white", True, alpha=0.3)]


@style("energy")
def p_energy():
    out = []
    for sx, nm in ((-1, "WingL"), (1, "WingR")):
        out.append(T(joined(nm, feather_wing(sx, n=6, span=2.2, w=0.5, coverts=False), 60), "a", True, alpha=0.35))
    core = ball("Core", 0.16, (0, BY - 0.12, 3.62), segs=12, rings=6)
    return out + [T(core, "white", True)]


@style("rack")
def p_rack():
    frame = [rbox("f", 0.1, 0.1, 1.6, at=(sx * 0.5, BY - 0.12, 3.2), bev=0.02) for sx in (-1, 1)]
    frame += [rbox("c", 1.1, 0.1, 0.1, at=(0, BY - 0.12, z), bev=0.02) for z in (2.5, 3.2, 3.9)]
    gear_ = wear.gear("Gear", 0.3, 9, 0.08, (-0.25, BY - 0.25, 3.55), axis="Y", tooth=0.07)
    pipe = rod("Pipe", [(0.3, BY - 0.25, 2.55), (0.3, BY - 0.3, 3.4), (0.15, BY - 0.35, 3.75), (0.15, BY - 0.35, 4.1)],
               0.07, segs=8)
    canister = cylinder_z("Can", 0.16, 0.5, (-0.25, BY - 0.3, 2.85), segs=12)
    gauge = kit.cyl("Gauge", 0.13, 0.13, 0.05, at=(0.3, BY - 0.37, 3.1), segs=14, axis="Y")
    exhaust = [kit.cyl("e", 0.07, 0.07, 0.4, at=(x, BY - 0.25, 4.2), segs=8) for x in (-0.35, 0.35)]
    return [T(joined("Frame", frame + exhaust, 30), "dark", mat="Metal"), T(joined("Gear", [gear_, pipe]), "s",
                                                                            mat="Metal"),
            T(joined("Parts", [canister, gauge]), "a"), T(joined("Straps", straps(0.12)), "dark", mat="Leather")]


@style("satchel")
def p_satchel():
    bag = rbox("Bag", 0.95, 0.34, 0.7, at=(0.42, BY - 0.2, 2.6), bev=0.12, segs=3)
    flap = rbox("Flap", 0.98, 0.37, 0.36, at=(0.42, BY - 0.21, 2.82), bev=0.1)
    clasp = rbox("Clasp", 0.14, 0.05, 0.16, at=(0.42, BY - 0.4, 2.7), bev=0.02)
    band_f = strip("bf", [(-0.85, 0.53, 4.02), (0.0, 0.54, 3.3), (0.85, 0.53, 2.6)], 0.14, up=(0, 1, 0), thick=0.03)
    band_b = strip("bb", [(-0.85, BY - 0.03, 4.02), (0.0, BY - 0.04, 3.3), (0.7, BY - 0.05, 2.75)], 0.14,
                   up=(0, 1, 0), thick=0.03)
    return [T(joined("Bag", [bag, band_f, band_b]), "s", mat="Leather"), T(flap, "p", mat="Leather"),
            T(clasp, "gold", mat="Metal")]


@style("case")
def p_case():
    c = (0.0, BY - 0.22, 3.1)
    rows = []
    for k in range(13):
        t = k / 12
        z = c[2] - 1.1 + 2.2 * t
        w = 0.22 + 0.25 * math.exp(-((t - 0.18) / 0.16) ** 2) + 0.18 * math.exp(-((t - 0.52) / 0.13) ** 2)
        rows.append((z, w, 0.16))
    body = ring("Body", rows, power=2.4, na=24, cx=0.0, cy=c[1], thick=0.0)
    caps = [ball("c", 0.22, (0, c[1], c[2] - 1.1), scale=(1, 0.72, 0.3), segs=12, rings=4),
            ball("c", 0.22, (0, c[1], c[2] + 1.1), scale=(1, 0.72, 0.3), segs=12, rings=4)]
    obs = [body] + caps
    latches = [rbox("l", 0.08, 0.06, 0.12, at=(sx * 0.42, c[1] - 0.1, c[2] - 0.75), bev=0.02) for sx in (-1, 1)]
    handle = kit.torus("h", 0.12, 0.03, at=(0.5, c[1], c[2] - 0.2), segs=12, csegs=4, arc=PI, axis="Y")
    wear.turn(handle, (0, -PI / 2, 0), (0.5, c[1], c[2] - 0.2))
    trim = [kit.torus("t", 0.25, 0.025, at=(0, c[1], c[2] + 0.75), segs=16, csegs=4)]
    for v in trim[0].data.vertices:
        v.co.y = c[1] + (v.co.y - c[1]) * 0.7
    allp = obs + latches + [handle] + trim
    for o in allp:
        tilt(o, -0.3, c)
    strap = strip("Strap", [(-0.85, 0.53, 4.0), (0.0, 0.54, 3.25), (0.9, 0.53, 2.5)], 0.12, up=(0, 1, 0), thick=0.03)
    return [T(joined("Case", obs, 50), "dark", mat="Leather"),
            T(joined("Latches", latches + [handle] + trim), "gold", mat="Metal"), T(strap, "s", mat="Leather")]


@style("banner")
def p_banner():
    pole = kit.cyl("Pole", 0.045, 0.045, 2.6, at=(0.45, BY - 0.2, 3.7), segs=8)
    cross = kit.cyl("Cross", 0.035, 0.035, 1.15, at=(-0.07, BY - 0.2, 4.87), segs=8, axis="X")
    finial = ball("Finial", 0.09, (0.45, BY - 0.2, 5.05), scale=(1, 1, 1.4), segs=10, rings=6)
    clip = rbox("Clip", 0.16, 0.14, 0.3, at=(0.45, BY - 0.12, 3.3), bev=0.04)
    for o in (pole, cross, finial, clip):
        tilt(o, -0.12, (0.45, BY - 0.2, 3.3))
    import bmesh
    bm = bmesh.new()
    cols, rows_ = 7, 6
    grid = []
    for j in range(rows_ + 1):
        row = []
        for i in range(cols + 1):
            u, v = i / cols, j / rows_
            x = -0.62 + 1.1 * u
            z = 4.85 - 1.1 * v - (0.25 * (1 - abs(2 * u - 1)) if j == rows_ else 0)
            y = BY - 0.22 + 0.06 * math.sin(u * 5 + v * 2) * u
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(rows_):
        for i in range(cols):
            bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
    flag = kit._obj("Flag", bm)
    wear.solid(flag, 0.03, 0.0)
    tilt(flag, -0.12, (0.45, BY - 0.2, 3.3))
    mark = outline("Mark", wear.star_pts(0.26, 0.11), 0.02, at=(-0.07, BY - 0.27, 4.32), axis="Y")
    tilt(mark, -0.12, (0.45, BY - 0.2, 3.3))
    return [T(joined("Pole", [pole, cross, clip]), "dark", mat="Metal"), T(finial, "gold", mat="Metal"),
            T(flag, "p", mat="Fabric"), T(mark, "s")]


@style("scroll")
def p_scroll():
    c = (0.0, BY - 0.28, 3.3)
    roll = kit.cyl("Roll", 0.22, 0.22, 1.7, at=c, segs=16, axis="X")
    lip = strip("Lip", [(-0.8, c[1] - 0.2, c[2] - 0.12), (0.8, c[1] - 0.2, c[2] - 0.12)], 0.25, up=(0, 0, 1),
                thick=0.02)
    caps = []
    for sx in (-1, 1):
        caps.append(kit.cyl("c", 0.26, 0.26, 0.1, at=(sx * 0.9, c[1], c[2]), segs=16, axis="X"))
        caps.append(ball("k", 0.1, (sx * 1.0, c[1], c[2]), segs=10, rings=5))
    tie = kit.torus("Tie", 0.235, 0.035, at=(0.0, c[1], c[2]), segs=16, csegs=5, axis="X")
    tails = [strip("t", [(0.0, c[1] - 0.2, c[2] - 0.15), (sx * 0.08, c[1] - 0.25, c[2] - 0.45)], 0.08,
                   up=(1, 0, 0), thick=0.02) for sx in (-1, 1)]
    allp = [roll, lip] + caps + [tie] + tails
    for o in allp:
        tilt(o, 0.5, c)
    strap = strip("Strap", [(-0.85, 0.53, 4.0), (0.0, 0.54, 3.25), (0.85, 0.53, 2.5)], 0.12, up=(0, 1, 0), thick=0.03)
    return [T(joined("Roll", [roll, lip]), "white", mat="Fabric"), T(joined("Caps", caps), "s", mat="Wood"),
            T(joined("Tie", [tie] + tails + [strap]), "a", mat="Fabric")]


@style("cogs")
def p_cogs():
    big = wear.gear("Big", 0.5, 12, 0.12, (-0.28, BY - 0.12, 3.45), axis="Y", tooth=0.1)
    small = wear.gear("Small", 0.32, 9, 0.12, (0.5, BY - 0.12, 2.9), axis="Y", tooth=0.08)
    top = wear.gear("Top", 0.22, 8, 0.1, (0.45, BY - 0.14, 3.85), axis="Y", tooth=0.06)
    hubs = [kit.cyl("h", r, r, 0.2, at=(x, BY - 0.15, z), segs=12, axis="Y")
            for x, z, r in ((-0.28, 3.45, 0.14), (0.5, 2.9, 0.1), (0.45, 3.85, 0.07))]
    return [T(big, "gold", mat="Metal"), T(joined("Gears", [small, top], 30), "s", mat="Metal"),
            T(joined("Hubs", hubs), "dark", mat="Metal")]


@style("butterfly")
def p_butterfly():
    def wing(sx, top):
        pts = []
        n = 14
        for k in range(n):
            a = PI * k / (n - 1)
            if top:
                r = 1.5 * (0.65 + 0.35 * math.sin(a)) * (0.7 + 0.3 * math.sin(2 * a))
                pts.append((sx * r * math.sin(a), 0.15 + r * math.cos(a) * 0.9 * 0.5 + r * 0.45 * math.sin(a)))
            else:
                r = 1.0 * (0.6 + 0.4 * math.sin(a))
                pts.append((sx * r * math.sin(a), -0.1 - r * 0.8 * math.sin(a) * 0.9 + r * 0.2 * math.cos(a)))
        if sx < 0:
            pts.reverse()
        return [(0.0, 0.0)] + pts
    out = []
    for sx, nm in ((-1, "L"), (1, "R")):
        up_ = outline("Up" + nm, wing(sx, True), 0.03, at=(sx * 0.1, BY - 0.25, 3.55), axis="Y")
        lo = outline("Lo" + nm, wing(sx, False), 0.03, at=(sx * 0.1, BY - 0.25, 3.5), axis="Y")
        out.append(T(up_, "a", True, alpha=0.3))
        out.append(T(lo, "s", True, alpha=0.3))
    body = cylinder_z("Body", 0.06, 0.55, (0, BY - 0.25, 3.5), segs=8)
    return out + [T(body, "dark")]


@style("fins")
def p_fins():
    big = outline("Dorsal", [(0.0, -0.6), (0.55, -0.63), (0.15, 0.38), (-0.4, 1.15), (-0.3, 0.45), (-0.22, -0.52)],
                  0.08, at=(0.0, BY - 0.45, 3.45), axis="X", bev=0.02)
    side = []
    for sx in (-1, 1):
        f = outline("s", [(0.0, 0.0), (0.8, -0.1), (0.25, 0.55)], 0.06, at=(sx * 0.45, BY - 0.15, 2.9), axis="Y",
                    bev=0.015)
        if sx < 0:
            for v in f.data.vertices:
                v.co.x = -0.45 - (v.co.x + 0.45)
            f.data.flip_normals()
        wear.turn(f, (0.5, 0, 0), (sx * 0.45, BY - 0.15, 2.9))
        side.append(f)
    base = rbox("Base", 0.3, 0.12, 0.9, at=(0, BY - 0.06, 3.3), bev=0.05)
    return [T(big, "a"), T(joined("Side", side, 30), "a"), T(base, "s")]


@style("antenna")
def p_antenna():
    box = rbox("Radio", 0.95, 0.42, 0.95, at=(0, BY - 0.24, 3.15), bev=0.08)
    dial = kit.cyl("Dial", 0.14, 0.14, 0.05, at=(-0.2, BY - 0.47, 3.3), segs=14, axis="Y")
    grill = [rbox("g", 0.36, 0.04, 0.04, at=(0.2, BY - 0.46, 3.0 + 0.09 * k), bev=0.01) for k in range(5)]
    mast = rod("Mast", [(0.33, BY - 0.24, 3.6), (0.36, BY - 0.24, 4.6), (0.38, BY - 0.24, 5.0)], [0.035, 0.025, 0.02],
               segs=6)
    tipb = ball("Tip", 0.08, (0.38, BY - 0.24, 5.05), segs=10, rings=5)
    light = ball("Lamp", 0.06, (-0.3, BY - 0.46, 3.48), scale=(1, 0.5, 1), segs=8, rings=4)
    return [T(box, "s", mat="Metal"), T(joined("Mast", [mast, dial] + grill), "dark", mat="Metal"),
            T(joined("Tip", [tipb, light]), "a", True), T(joined("Straps", straps(0.12)), "dark", mat="Fabric")]


@style("umbrella")
def p_umbrella():
    c = (-0.15, BY - 0.25, 3.2)
    canopy = []
    n = 8
    rows = [(c[2] - 0.95, 0.05, 0.05), (c[2] - 0.6, 0.17, 0.17), (c[2] + 0.1, 0.2, 0.2), (c[2] + 0.75, 0.12, 0.12),
            (c[2] + 0.95, 0.03, 0.03)]
    canopy = ring("Canopy", rows, power=2.0, na=n * 2, cx=c[0], cy=c[1], thick=0.0,
                  wave=lambda a, z: 0.04 * abs(math.sin(a * n / 2)))
    tie = kit.torus("Tie", 0.2, 0.03, at=(c[0], c[1], c[2] + 0.05), segs=14, csegs=4)
    shaft = kit.cyl("Shaft", 0.035, 0.035, 0.45, at=(c[0], c[1], c[2] + 1.15), segs=8)
    hook = kit.torus("Hook", 0.13, 0.04, at=(c[0] + 0.13, c[1], c[2] + 1.38), segs=12, csegs=5, arc=PI, axis="Y")
    ferrule = wear.cone("F", 0.04, 0.0, 0.25, (c[0], c[1], c[2] - 0.95), segs=8, axis=(0, 0, -1))
    for o in (canopy, tie, shaft, hook, ferrule):
        tilt(o, 0.3, c)
    return [T(canopy, "p", mat="Fabric"), T(joined("Handle", [shaft, hook, ferrule]), "dark", mat="Wood"),
            T(tie, "s"), T(joined("Strap", straps(0.1)[:1]), "dark", mat="Fabric")]


@style("orbs")
def p_orbs():
    big = [ball("o", r, at, segs=16, rings=8) for r, at in ((0.24, (-0.85, BY - 0.5, 4.25)),
                                                            (0.2, (0.9, BY - 0.5, 4.05)))]
    top = ball("Top", 0.17, (0.0, BY - 0.55, 4.75), segs=14, rings=7)
    rings_ = [kit.torus("r", r + 0.08, 0.02, at=at, segs=20, csegs=4, axis="Y")
              for r, at in ((0.24, (-0.85, BY - 0.5, 4.25)), (0.2, (0.9, BY - 0.5, 4.05)), (0.17, (0, BY - 0.55, 4.75)))]
    return [T(joined("Orbs", big, 70), "a", True), T(top, "s", True), T(joined("Rings", rings_), "white", True,
                                                                        alpha=0.4)]



# ---------------------------------------------------------------- angel and devil wings (2026-11-21, nate's ask)
def arm_curve(sx, span):
    """The wing's leading edge: from the shoulder blade up to the elbow, then out and a little down to the tip."""
    pts = [Vector((sx * 0.28, BY - 0.14, 3.72)), Vector((sx * span * 0.32, BY - 0.32, 4.55)),
           Vector((sx * span * 0.62, BY - 0.46, 4.78)), Vector((sx * span, BY - 0.6, 4.5))]

    def at(u):
        # Catmull-Rom through the 4 points
        n = len(pts) - 1
        f = min(n - 1e-6, u * n)
        i = int(f)
        t = f - i
        p0, p1, p2, p3 = pts[max(0, i - 1)], pts[i], pts[i + 1], pts[min(n, i + 2)]
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                      (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
    return at


def feather(base, d, length, width, back):
    """One broad rounded feather from base along d, flat facing the back (lying across y)."""
    pts, ws = [], []
    for j in range(6):
        u = j / 5
        pts.append(base + d * length * u + Vector((0, back * u, 0)))
        ws.append(max(0.035, width * (0.55 + 0.45 * math.sin(PI * min(1.0, 0.2 + u * 0.75))) * (1 - 0.9 * u ** 5)))
    # broad side facing the back: the width runs across the feather, square to the back (not edge-on)
    return strip("f", pts, ws, up=tuple(d.cross(Vector((0, 1, 0)))), thick=0.035)


def angel_wing(sx, span=2.7):
    arm = arm_curve(sx, span)
    prim, sec, cov = [], [], []
    for k in range(6):  # primaries: long, from the tip, fanning from out to down
        t = k / 5
        u = 1.0 - 0.32 * t
        ang = 0.15 - 0.95 * t
        d = Vector((sx * math.cos(ang), -0.05, math.sin(ang))).normalized()
        prim.append(feather(arm(u), d, 1.5 - 0.35 * t, 0.36, -0.04))
    for k in range(8):  # secondaries: hanging down from the arm, a little out
        t = k / 7
        u = 0.66 - 0.56 * t
        d = Vector((sx * (0.35 - 0.25 * t), -0.04, -1.0)).normalized()
        sec.append(feather(arm(u) + Vector((0, 0.03, 0)), d, 1.35 - 0.45 * t, 0.34, -0.03))
    for k in range(11):  # coverts: short scallops over the roots, just behind the rest
        t = k / 10
        u = 0.97 - 0.9 * t
        d = Vector((sx * 0.25, -0.02, -1.0)).normalized()
        cov.append(feather(arm(u) + Vector((0, -0.05, 0.02)), d, 0.6 - 0.12 * t, 0.3, -0.02))
    bone = rod("arm", [tuple(arm(u / 8)) for u in range(9)], [0.09, 0.085, 0.08, 0.075, 0.07, 0.06, 0.05, 0.04,
                                                              0.03], segs=8)
    return prim + sec, cov, bone


@style("angel")
def p_angel():
    out, trims = [], []
    for sx, nm in ((-1, "WingL"), (1, "WingR")):
        long_, cov, bone = angel_wing(sx)
        out.append(T(joined(nm, long_, 50), "white", mat="Fabric"))
        out.append(T(joined(nm + "Cov", cov, 50), "white", mat="Fabric"))
        trims.append(bone)
    out.append(T(joined("Arms", trims + [rbox("Mount", 0.46, 0.12, 0.46, at=(0, BY - 0.06, 3.65), bev=0.08)]),
                 "gold", mat="Metal"))
    return out


@style("devil")
def p_devil():
    out, bones, claws = [], [], []
    for sx, nm in ((-1, "WingL"), (1, "WingR")):
        skin, spars = membrane_wing(nm, sx, span=2.7)
        # the skin's top edge rises into a point at the elbow, like a devil's
        for v in skin.data.vertices:
            if abs(v.co.x) > 0.6:
                v.co.z += 0.18 * math.exp(-((abs(v.co.x) - 1.2) / 0.5) ** 2)
        out.append(T(skin, "p", mat="Leather"))
        bones += spars
        elbow = Vector((sx * 2.7 * 0.45, BY - 0.35, 4.75))
        c = kit.cyl("claw", 0.08, 0.0, 0.34, at=tuple(elbow + Vector((0, 0, 0.17))), segs=8)
        wear.turn(c, (0, -sx * 0.5, 0), tuple(elbow))
        claws.append(c)
        for t in (Vector((sx * 2.7, BY - 0.45, 4.2)), Vector((sx * 2.7 * 1.05, BY - 0.45, 3.4))):
            k = kit.cyl("tip", 0.05, 0.0, 0.22, at=tuple(t + Vector((sx * 0.1, 0, -0.05))), segs=6, axis="X")
            claws.append(k)
    out.append(T(joined("Bones", bones, 50), "dark"))
    out.append(T(joined("Claws", claws, 30), "white"))
    return out

# ---------------------------------------------------------------- build, export, preview
HEADER = ["backs.py",
          "The creator's back bling as meshes (ReplicatedStorage.Art.Backs once nate imports art/export/Backs.fbx;",
          "LookKit wears them then, the part-built ones until then). Keyed by the Back bling slot's kit: each piece's",
          "mesh name, the body part it is welded to (at: the upper torso), its colour role (the slot's p main, s trim,",
          "a accent, or dark, white, gold, ice, glowRed), glow (Neon), material and transparency, and its box against",
          "the upper torso's centre in Roblox axes (x right, y up, z back), in studs on the standard blocky rig."]


def preview(built):
    def dress(name, at, yaw, pal):
        wear.body(at, yaw, suit=(150, 156, 170))
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", "backs.png" if ONLY is None else "backs_test.png")
    # the back is the side that matters: the first view is from behind three-quarter
    wear.grid_preview(built, out, dress, cols=5, cell=5.4, px=320, focus=3.0, yaw_front=30,
                      yaw_back=150, samples=32, look_down=0.1)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Back_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Backs.fbx"))
        wear.write_fit("BackArt", HEADER, rows)
    preview(built)
