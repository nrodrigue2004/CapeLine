# weapons.py: the 36 playable weapons as Blender meshes (2026-11-18), in place of the blocks, balls and cylinders
# Shared.WeaponKit welds to the hands today. Until nate imports them the game keeps those parts; once
# ReplicatedStorage.Art.Weapons holds every mesh of a weapon (all or nothing, as Shared.SetPieceKit), WeaponKit
# welds the meshes instead (Shared.WeaponMesh picks them per style).
# Designs: original, bright and chunky so they read from far off in both the Comic and the Anime styles: bold
# silhouettes, one colour region a mesh (the game colours each MeshPart: p the weapon's main colour or finish, s its
# trim, a its glow, white a string), every glowing part its own mesh so the game tints it and shows it by the glow
# strength. Guns are cartoon sci-fi blasters (never a real firearm); no blade copies a weapon from a show.
# Frames: each weapon is drawn in its body part's own studs (x right, y up, z back; the part's centre at the
# origin) the way WeaponKit's parts are written (a hand weapon points along -z from a grip line under the hand,
# y = -0.2), then turned by its hold (HOLD: about the grip for a hand, about the forearm's centre for a shield) so
# it sits right in HeroAnim's stances and swings: blades tilted 45 degrees down from forward (up and forward in
# the ready stance, leading the slash), blasters, spears and staffs along the arm (they aim where the arm points),
# shields on the back of the forearm (facing forward with the forearm raised), the bow upright with the arm out,
# hanging weapons (whip, yo-yo, rope dart) hanging straight down in their stance. WeaponKit turns today's parts
# by the same hold, so the fallback matches.
# Styles: 1 Classic as drawn, 2 Broad and 3 Jagged get their own meshes where the shape changes (blades, axe and
# scythe heads, claws: `broad` and `jag` rows), 4 Energy is the Classic mesh in glowing light (WeaponKit).
# Output: art/export/Weapons.fbx (nate imports it as ReplicatedStorage.Art.Weapons), src/config/WeaponArt.luau (the
# fit: each weapon's hold, grip and aim, and per mesh its body part, colour role, flags, box and triangles) and,
# with --preview, art/preview/weapons.png (each weapon alone), weapons_held.png (each in its hero's ready stance)
# and weapons_action.png (each in the swing, shot or guard its moves play), posed from
# art/export/weapons/poses.json (`lune run art/weapons/poses.luau` writes it from HeroAnim).
# Run: nice -n 15 $HOME/tools/bpyenv/bin/python art/blender/weapons.py [--preview] [--only 5,11] [--fast]
import json
import math
import os
import shutil
import subprocess
import sys

if "--sheet" in sys.argv:  # plain python3 with PIL: label a preview grid (called by the preview below)
    from PIL import Image, ImageDraw, ImageFont

    a = sys.argv[sys.argv.index("--sheet") + 1:]
    src, out, cols, px, names = a[0], a[1], int(a[2]), int(a[3]), a[4].split("|")
    im = Image.open(src).convert("RGB")
    rows = (len(names) + cols - 1) // cols
    lab = 30
    sheet = Image.new("RGB", (cols * px, rows * (px + lab)), (38, 40, 48))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
    except OSError:
        font = ImageFont.load_default()
    for i, n in enumerate(names):
        r, c = i // cols, i % cols
        sheet.paste(im.crop((c * px, r * px, (c + 1) * px, (r + 1) * px)), (c * px, r * (px + lab)))
        tw = d.textlength(n, font=font)
        d.text((c * px + (px - tw) / 2, r * (px + lab) + px + 3), n, fill=(240, 240, 245), font=font)
    sheet.save(out)
    print("wrote", out)
    sys.exit(0)

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

from studs import B, C, S, T, TOR, rings_mesh, prism, star, turn, shift, mirror, rb  # noqa: E402

PREVIEW = "--preview" in sys.argv
THUMBS = "--thumbs" in sys.argv  # the creator thumbnails only (no fit, no FBX): art/thumbs/cells/weapons/<id>.png
PREVIEW = PREVIEW or THUMBS or "--styles" in sys.argv
FAST = "--fast" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = {int(x) for x in sys.argv[sys.argv.index("--only") + 1].split(",")}
# the grip line: the handle's axis, on Roblox's own Right/LeftGripAttachment (the hand's bottom face, y -0.15 from
# its centre), where a Roblox tool's handle sits, so the handle is half in the fist (pt-fit 2026-11-19: it was
# -0.2, so every handle hung under the hand; Config.RobloxRig, tests/fit_test.luau)
G = -0.15
PI = math.pi
BUDGET = 2000  # triangles a weapon (both hands, Classic)
ATS = ("rhand", "lhand", "rlarm", "llarm", "rfoot", "lfoot", "rshin", "lshin")
LEFT = {"rhand": "lhand", "rlarm": "llarm", "rfoot": "lfoot", "rshin": "lshin"}
ROLES = ("p", "s", "a", "white", "dark")
MATS = ("Metal", "Fabric", "Wood", "Leather", "Glass")


class Piece:
    """One mesh of a weapon: its object, the body part it is welded to, its colour role and flags."""

    def __init__(self, name, ob, role, at="rhand", blade=False, glow=False, neon=False, emblem=False, mat=None,
                 alpha=0.0):
        assert at in ATS, at
        assert role in ROLES, role
        assert mat is None or mat in MATS, mat
        self.name, self.ob, self.role, self.at = name, ob, role, at
        self.blade, self.glow, self.neon, self.emblem, self.mat, self.alpha = blade, glow, neon, emblem, mat, alpha


def flat(parts):
    out = []
    for p in parts:
        if isinstance(p, (list, tuple)):
            out += flat(p)
        elif p is not None:
            out.append(p)
    return out


def join(parts):
    parts = flat(parts)
    if len(parts) == 1:
        return kit.apply_all(parts[0])
    return kit.join("j", parts, shade=False)


def P(name, parts, role, **kw):
    if not isinstance(parts, (list, tuple)):
        parts = [parts]
    return Piece(name, join(parts), role, **kw)


def both(pieces):
    """The pieces on the right hand (or forearm, foot) and their mirror on the left."""
    out = []
    for p in pieces:
        p.name = p.name + "R"
        out.append(p)
        m = Piece(p.name[:-1] + "L", mirror(p.ob), p.role, LEFT.get(p.at, p.at), p.blade, p.glow, p.neon, p.emblem,
                  p.mat, p.alpha)
        out.append(m)
    return out


# ---------------------------------------------------------------- shape helpers (Roblox studs: x, up, z = back)
def resample(pts, n):
    """Stations (z, top, bot) resampled to n along the list (piecewise linear)."""
    out = []
    m = len(pts) - 1
    for i in range(n):
        f = i / (n - 1) * m
        k = min(int(f), m - 1)
        u = f - k
        a, b = pts[k], pts[k + 1]
        out.append(tuple(a[j] + (b[j] - a[j]) * u for j in range(3)))
    return out


def blade_rings(pts, st, t=0.06, n=14, x=0.0, tooth=0.16, spine=False, teeth_on="top"):
    """A blade's cross-sections along z: pts [(z, top, bot)] from the base to the tip; diamond sections with sharp
    edges (a thick flat spine on top with spine=True). st: c Classic, b Broad (wider and thicker), j Jagged (saw teeth
    along the top edge, or the bottom with teeth_on="bot")."""
    S_ = resample(pts, n)
    if st == "b":
        S_ = [(z, (tp + bt) / 2 + (tp - bt) / 2 * 1.35, (tp + bt) / 2 - (tp - bt) / 2 * 1.35) for (z, tp, bt) in S_]
        t *= 1.25
    if st == "j":
        out = []
        for i, (z, tp, bt) in enumerate(S_):
            f = i / (n - 1)
            if 0.12 < f < 0.8 and i % 2 == 1:
                if teeth_on == "top":
                    tp += tooth
                else:
                    bt -= tooth
            out.append((z, tp, bt))
        S_ = out
    rings = []
    for (z, tp, bt) in S_:
        h = max(tp - bt, 0.02)
        e = min(0.42 * h, 0.13)
        tt = t * min(1.0, h / 0.12)
        if spine:
            sp = tt * 0.75
            ring = [(x - sp, tp, z), (x + sp, tp, z), (x + tt, tp - e * 0.4, z), (x + tt * 0.5, bt + e, z),
                    (x, bt, z), (x - tt * 0.5, bt + e, z), (x - tt, tp - e * 0.4, z)]
        else:
            ring = [(x, tp, z), (x + tt, tp - e, z), (x + tt, bt + e, z), (x, bt, z), (x - tt, bt + e, z),
                    (x - tt, tp - e, z)]
        rings.append(ring)
    return S_, rings


def blade(pts, st, **kw):
    """A blade mesh and its cutting edge's glow line (the bottom edge; both=True also the top)."""
    both_edges = kw.pop("both_edges", False)
    r_edge = kw.pop("edge_r", 0.032)
    S_, rings = blade_rings(pts, st, **kw)
    ob = rings_mesh(rings)
    kit.shade_auto(ob, 35)
    x = kw.get("x", 0.0)
    lines = []
    edges = [1] + ([0] if both_edges else [])
    for which in edges:
        pts_e = []
        for (z, tp, bt) in S_[1:-1]:
            pts_e.append((x, (bt - 0.012) if which == 1 else (tp + 0.012), z))
        lines.append(T(pts_e, [r_edge] * len(pts_e), segs=5))
    return ob, join(lines)


def grip(z0, z1, r=0.1, y=G, ridges=3, x=0.0):
    """A wrapped handle along z from z0 to z1 with raised wrap ridges."""
    parts = [C(r, abs(z1 - z0), x, y, (z0 + z1) / 2, segs=10, axis="z")]
    for k in range(ridges):
        z = z0 + (z1 - z0) * (k + 0.5) / ridges
        parts.append(TOR(r * 1.02, 0.035, x, y, z, axis="z", segs=12, csegs=4))
    return join(parts)


def box(sx, sy, sz, x=0.0, y=0.0, z=0.0, bev=0.04):
    return B(sx, sy, sz, x, y, z, bev=bev)


def ball(r, x=0.0, y=0.0, z=0.0, sc=(1, 1, 1), segs=12, rings=8):
    return S(r, x, y, z, sc=sc, segs=segs, rings=rings)


def zx_poly_prism(poly, y0, y1):
    """A polygon in the (x, z) plane pushed up from y0 to y1 (flat stars, boomerangs, fans)."""
    return rings_mesh([[(x, y0, z) for (x, z) in poly], [(x, y1, z) for (x, z) in poly]])


def plate(poly_zy, x, thick):
    """A flat shape in the (z, up) plane, thick along x, centred on x (axe heads, scythe blades)."""
    return prism(poly_zy, x - thick / 2, x + thick / 2)


def edge_line(points, r=0.035, segs=5):
    return T(points, [r] * len(points), segs=segs)


def arc_pts(cz, cy, r, a0, a1, n):
    """Points on a circle in the (z, up) plane: angle 0 is -z (forward), 90 is up."""
    out = []
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / (n - 1))
        out.append((cz - r * math.cos(a), cy + r * math.sin(a)))
    return out


def crescent(outer, inner):
    """A closed outline from an outer curve and an inner curve (both base to tip) in the (z, up) plane."""
    return list(outer) + list(reversed(inner))


def jag_curve(curve, st, tooth=0.14, every=2, lo=0.15, hi=0.85, normal=None):
    """Saw teeth along a curve of (z, y) points for the Jagged style (pushed along each point's outward normal)."""
    if st != "j":
        return curve
    n = len(curve)
    out = []
    for i, (z, y) in enumerate(curve):
        f = i / (n - 1)
        if lo < f < hi and i % every == 1:
            a = curve[max(i - 1, 0)]
            b = curve[min(i + 1, n - 1)]
            dz, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dz, dy) or 1
            nz, ny = (dy / ln, -dz / ln) if normal is None else normal
            out.append((z + nz * tooth, y + ny * tooth))
        else:
            out.append((z, y))
    return out


def widen(curve, st, cz, cy, f=1.25):
    """Broad style: push a curve away from a centre point (an axe or scythe head grows outward)."""
    if st != "b":
        return curve
    return [(cz + (z - cz) * f, cy + (y - cy) * f) for (z, y) in curve]


def crescent_blade(cz, cy, rz, ry, st, side=-1, t0=0.14, n=13, a0=16, tooth=0.15, neck=0.12):
    """An axe bit: a crescent hanging off the haft's end at (z cz, y cy) toward side (-1 down, 1 up), its cutting
    edge a wide convex arc rz along the haft and ry out, its back hugging the haft at the neck and sweeping out to
    two horns. Thick at the back, thin at the edge. Broad: a bigger bit; Jagged: teeth along the edge."""
    if st == "b":
        rz, ry = rz * 1.15, ry * 1.2
    rings = []
    edge = []
    for i in range(n):
        f = i / (n - 1)
        a = math.radians(a0 + (180 - 2 * a0) * f)
        c, s = math.cos(a), math.sin(a)
        oz, oy = cz + rz * c, cy + side * (0.22 + ry * s)
        if st == "j" and 0.12 < f < 0.88 and i % 2 == 1:
            oy += side * tooth
        iz, iy = cz + rz * 0.86 * c, cy + side * (neck + 0.5 * (1 - s) * (0.22 + ry * 0.36))
        mz, my = iz + (oz - iz) * 0.55, iy + (oy - iy) * 0.55
        rings.append([(t0, iy, iz), (t0 * 0.55, my, mz), (0.015, oy, oz), (-0.015, oy, oz), (-t0 * 0.55, my, mz),
                      (-t0, iy, iz)])
        if 0 < i < n - 1:
            edge.append((0, oy + side * 0.012, oz))
    ob = rings_mesh(rings)
    kit.shade_auto(ob, 35)
    return ob, edge_line(edge, 0.04)


def chain(points, link=0.16, r=0.05):
    """Oval chain links along a path of Roblox points, each turned a quarter from the last."""
    parts = []
    pts = [Vector(p) for p in points]
    total = [0.0]
    for i in range(1, len(pts)):
        total.append(total[-1] + (pts[i] - pts[i - 1]).length)
    L = total[-1]
    k = 0
    s = 0.0
    while s < L - 1e-4:
        j = 1
        while j < len(total) - 1 and total[j] < s:
            j += 1
        u = (s - total[j - 1]) / max(total[j] - total[j - 1], 1e-6)
        p = pts[j - 1].lerp(pts[j], u)
        d = (pts[j] - pts[j - 1]).normalized()
        ob = TOR(link * 0.5, r * 0.5, 0, 0, 0, axis="x" if k % 2 == 0 else "z", segs=8, csegs=4)
        # stretch along up, then turn up onto the path's direction
        kit.apply_all(ob)
        for v in ob.data.vertices:
            v.co.z *= 1.5
        up = Vector((0, 0, 1))
        dd = Vector(rb(d.x, d.y, d.z))
        q = up.rotation_difference(dd)
        ob.data.transform(q.to_matrix().to_4x4())
        shift(ob, rb(p.x, p.y, p.z))
        parts.append(ob)
        s += link * 1.15
        k += 1
    return join(parts)


# ---------------------------------------------------------------- the weapons
WEAPONS = {}  # id -> (name, fn(st) -> [Piece])
HOLD = {}  # id -> {at: {"rx": deg, "ry": deg}}  (turned about PIVOT[at])
AIM = {}  # id -> {"at": part, "dir": (x, y, z) legacy, "face": (x, y, z) legacy or None}
PIVOT = {"rhand": (0, G, 0), "lhand": (0, G, 0), "rlarm": (0, 0, 0), "llarm": (0, 0, 0), "rfoot": (0, 0, 0),
         "lfoot": (0, 0, 0), "rshin": (0, 0, 0), "lshin": (0, 0, 0)}
GRIP = {}  # id -> (at, (x, y, z) legacy): where the hand holds it
# the two-handed weapons' second hand (pt-fit 2026-11-19): where the left hand should close on the handle, in the
# right hand's frame before the hold (pommel side +z, blade side -z), for HeroAnim's two-handed stances to reach
GRIP2 = {11: 0.55, 12: 0.85, 13: 0.7, 14: -1.85, 15: 0.85, 16: -1.7}


def weapon(wid, name, hold=None, aim=("rhand", (0, 0, -1)), face=None, grip_at=None):
    def deco(fn):
        WEAPONS[wid] = (name, fn)
        HOLD[wid] = hold or {}
        AIM[wid] = {"at": aim[0], "dir": aim[1], "face": face}
        GRIP[wid] = grip_at or (aim[0], (0, G, 0))
        return fn
    return deco


BLADE45 = {"rhand": {"rx": -45}}
ALONG = {"rhand": {"rx": -90}}
HANG = {"rhand": {"rx": -56}}


# 1 Bare Fists: taped hands with a glowing knuckle line
@weapon(1, "Bare Fists", aim=("rhand", (0, -1, 0)))
def w_fists(st):
    tape = join([box(1.06, 0.34, 1.06, 0, 0, 0, bev=0.08)] +
                [box(1.1, 0.08, 1.1, 0, y, 0, bev=0.03) for y in (-0.1, 0.1)])
    knuck = box(0.96, 0.06, 0.08, 0, -0.17, -0.5, bev=0.02)
    if st == "b":  # Plated: a riveted plate over the knuckles and the back of the hand
        tape = join([tape, box(1.14, 0.14, 0.72, 0, -0.14, -0.2, bev=0.05), box(1.0, 0.1, 0.5, 0, 0.17, -0.1, bev=0.04)])
    elif st == "j":  # Spiked: a stud on each knuckle
        tape = join([tape] + [T([(x, -0.16, -0.42), (x, -0.42, -0.5)], [0.08, 0.0], segs=6) for x in (-0.36, -0.12, 0.12, 0.36)])
    return both([P("Tape", tape, "s", mat="Fabric"), P("Knuckle", knuck, "a", glow=True)])


# 2 Martial Arts: wrapped hands and forearms, a ribbon tail
@weapon(2, "Martial Arts", aim=("rhand", (0, -1, 0)))
def w_martial(st):
    wrap = join([box(1.05, 0.33, 1.05, 0, 0, 0, bev=0.07)] +
                [box(1.09, 0.07, 1.09, 0, y, 0, bev=0.025) for y in (-0.1, 0.02, 0.12)])
    arm = []
    for k in range(4):
        b = box(1.07, 0.1, 1.07, 0, -0.38 + k * 0.13, 0, bev=0.03)
        turn(b, "z", 8 if k % 2 else -8, (0, -0.38 + k * 0.13, 0))
        arm.append(b)
    tail = T([(0.36, -0.2, 0.52), (0.42, -0.42, 0.66), (0.4, -0.66, 0.74), (0.46, -0.86, 0.7)],
             [0.07, 0.07, 0.06, 0.03], segs=6)
    bead = ball(0.08, 0.36, -0.2, 0.55, segs=8, rings=6)
    if st == "b":  # Plated: a lacquered bracer over the forearm wraps
        arm.append(box(1.14, 0.42, 0.5, 0, -0.2, -0.32, bev=0.08))
    elif st == "j":  # Spiked: studs along the knuckle wrap
        wrap = join([wrap] + [T([(x, -0.16, -0.42), (x, -0.36, -0.48)], [0.065, 0.0], segs=6) for x in (-0.3, 0.0, 0.3)])
    return both([P("Wrap", wrap, "white", mat="Fabric"), P("ArmWrap", arm, "white", at="rlarm", mat="Fabric"),
                 P("Tail", tail, "p", at="rlarm", mat="Fabric"), P("Bead", bead, "a", at="rlarm", glow=True)])


# 3 Power Gauntlets: big armoured fists with knuckle plates and glowing vents
@weapon(3, "Power Gauntlets", aim=("rhand", (0, -1, 0)))
def w_gauntlets(st):
    fist = [box(1.3, 0.62, 1.3, 0, -0.05, 0, bev=0.12)]
    for k in range(4):
        fist.append(box(0.26, 0.22, 0.34, -0.45 + k * 0.3, -0.34, -0.3, bev=0.06))
    fist.append(box(0.5, 0.3, 0.2, 0.0, 0.05, -0.68, bev=0.06))
    if st == "b":  # Plated: a thick armour plate over the back of the fist
        fist.append(box(1.38, 0.24, 1.1, 0, 0.32, 0.02, bev=0.1))
    elif st == "j":  # Spiked: a spike on each knuckle plate
        fist += [T([(-0.45 + k * 0.3, -0.42, -0.36), (-0.45 + k * 0.3, -0.74, -0.44)], [0.1, 0.0], segs=6) for k in range(4)]
    cuff = [kit.cyl("c", 0.66, 0.6, 0.62, at=rb(0, -0.12, 0), segs=12)]
    cuff.append(box(0.3, 0.5, 0.2, 0.0, -0.1, 0.64, bev=0.05))
    glow = [box(1.12, 0.07, 0.07, 0, -0.33, -0.66, bev=0.02)]
    for k in range(3):
        glow.append(box(0.07, 0.36, 0.05, -0.3 + k * 0.3, -0.12, -0.665, bev=0.015))
    return both([P("Fist", fist, "p", blade=True, mat="Metal"), P("Cuff", cuff, "s", at="rlarm", mat="Metal"),
                 P("Glow", glow, "a", glow=True, neon=True)])


# 4 Strikers: armoured boots with a toe cap, heel fin and glowing soles
@weapon(4, "Strikers", aim=("rfoot", (0, 0, -1)), grip_at=("rfoot", (0, 0, 0)))
def w_strikers(st):
    shell = [box(1.16, 0.46, 1.2, 0, 0.06, -0.04, bev=0.12)]
    toe = rings_mesh([[(-0.5, 0.3, -0.55), (0.5, 0.3, -0.55), (0.5, -0.16, -0.55), (-0.5, -0.16, -0.55)],
                      [(-0.36, 0.18, -0.82), (0.36, 0.18, -0.82), (0.4, -0.16, -0.8), (-0.4, -0.16, -0.8)]])
    shell.append(toe)
    fin = plate([(0.4, 0.2), (0.78, 0.36), (0.66, 0.12), (0.42, -0.05)], 0, 0.12)
    shin = [box(0.4, 0.62, 0.16, 0, -0.1, -0.56, bev=0.05), box(1.12, 0.16, 1.12, 0, -0.38, 0, bev=0.05)]
    if st == "b":  # Plated: a broad shin guard
        shin.append(box(0.9, 0.9, 0.2, 0, 0.05, -0.6, bev=0.08))
    elif st == "j":  # Spiked: a spike at the heel and two on the toe cap
        shell += [T([(0, 0.0, 0.58), (0, 0.05, 0.9)], [0.1, 0.0], segs=6)]
        shell += [T([(x, 0.12, -0.78), (x, 0.18, -1.0)], [0.07, 0.0], segs=6) for x in (-0.2, 0.2)]
    glow = [box(0.05, 0.06, 1.0, 0.6, -0.12, -0.04, bev=0.01), box(0.05, 0.06, 1.0, -0.6, -0.12, -0.04, bev=0.01),
            box(0.7, 0.06, 0.05, 0, -0.12, -0.84, bev=0.01)]
    return both([P("Boot", shell, "p", at="rfoot", blade=True, mat="Metal"),
                 P("Fin", fin, "s", at="rfoot", mat="Metal"), P("Shin", shin, "s", at="rshin", mat="Metal"),
                 P("Glow", glow, "a", at="rfoot", glow=True)])


def guard_bar(w, z, y=G, depth=0.22, h=0.2, flare=0.12):
    """A cross guard along x with flared tips."""
    parts = [box(w, h, depth, 0, y, z, bev=0.05)]
    for sx in (-1, 1):
        parts.append(ball(0.12 + flare * 0.5, sx * w / 2, y, z, sc=(1.0, 1.25, 1.0), segs=8, rings=6))
    return join(parts)


# 5 Sword: a broad straight blade, cross guard with a gem, wrapped grip
@weapon(5, "Sword", hold=BLADE45)
def w_sword(st):
    pts = [(-0.6, G + 0.29, G - 0.29), (-2.6, G + 0.26, G - 0.26), (-3.25, G + 0.2, G - 0.2), (-3.8, G, G)]
    bl, edge = blade(pts, st, t=0.085)
    hilt = [grip(0.42, -0.42, 0.1), ball(0.15, 0, G, 0.52, segs=10, rings=6)]
    guard = guard_bar(0.95, -0.5)
    gem = ball(0.1, 0, G, -0.5, sc=(1.6, 1.2, 1.2), segs=8, rings=6)
    return [P("Blade", bl, "p", blade=True), P("Hilt", hilt, "s"), P("Guard", guard, "s", mat="Metal"),
            P("Gem", gem, "a", neon=True), P("Edge", edge, "a", glow=True)]


# 6 Katana: a long single-edged blade with a gentle upward curve and a round guard
@weapon(6, "Katana", hold=BLADE45)
def w_katana(st):
    pts = []
    for k in range(9):
        f = k / 8
        z = -0.62 - 3.4 * f
        lift = 0.28 * f * f
        w = 0.15 - 0.03 * f
        if f > 0.86:
            w *= max(0.05, (1 - f) / 0.14)
        pts.append((z, G + lift + w, G + lift - w))
    bl, edge = blade(pts, st, t=0.055, spine=True, n=16, teeth_on="top")
    hilt = [grip(0.5, -0.5, 0.095, ridges=5), C(0.11, 0.06, 0, G, 0.55, segs=10, axis="z")]
    tsuba = C(0.3, 0.07, 0, G, -0.56, segs=16, axis="z")
    collar = C(0.12, 0.1, 0, G, -0.62, segs=8, axis="z")
    return [P("Blade", bl, "p", blade=True), P("Hilt", hilt, "s"), P("Guard", [tsuba, collar], "s", mat="Metal"),
            P("Edge", edge, "a", glow=True)]


# 7 Hand Axe: a bearded axe head with a back spike on a short haft
@weapon(7, "Hand Axe", hold=BLADE45)
def w_axe(st):
    haft = T([(0, G, 0.5), (0, G - 0.02, -0.6), (0, G + 0.02, -1.95)], [0.11, 0.105, 0.1], segs=10)
    wrap = grip(0.35, -0.35, 0.125, ridges=3)
    # a bearded blade hanging below the haft's end, its crescent edge forward and down, the beard swept back
    head, edge = crescent_blade(-1.62, G, 0.52, 0.8, st, t0=0.13, tooth=0.12)
    spike = T([(0, G + 0.12, -1.62), (0, G + 0.5, -1.55)], [0.1, 0.0], segs=6)
    socket = box(0.26, 0.46, 0.38, 0, G, -1.62, bev=0.05)
    return [P("Head", [head, spike], "p", blade=True), P("Haft", haft, "s", mat="Wood"),
            P("Wrap", [wrap, socket], "s", mat="Metal"), P("Edge", edge, "a", glow=True)]


# 8 Mace: a flanged head on a banded haft, a glowing core between the flanges
@weapon(8, "Mace", hold=BLADE45)
def w_mace(st):
    haft = [C(0.1, 2.3, 0, G, -0.55, segs=10, axis="z"), ball(0.14, 0, G, 0.62, segs=8, rings=6)]
    wrap = grip(0.4, -0.4, 0.115, ridges=3)
    head = [ball(0.3, 0, G, -1.85, segs=12, rings=8), C(0.12, 0.5, 0, G, -2.25, segs=8, axis="z")]
    head.append(ball(0.1, 0, G, -2.52, sc=(1, 1, 1.6), segs=8, rings=6))
    fl = []
    for k in range(6):
        a = k * 60
        f = plate([(-1.55, 0.0), (-1.55, 0.18), (-1.75, 0.52), (-2.05, 0.5), (-2.2, 0.16), (-2.2, 0.0)], 0, 0.1)
        shift(f, rb(0, G, 0))
        turn(f, "z", a, (0, G, -1.85))
        fl.append(f)
    if st == "j":
        for k in range(6):
            sp = T([(0, G + 0.55, -1.88), (0, G + 0.78, -1.88)], [0.06, 0.0], segs=6)
            turn(sp, "z", k * 60, (0, G, -1.85))
            fl.append(sp)
    if st == "b":
        for f in fl:
            for v in f.data.vertices:
                c = Vector(rb(0, G, -1.85))
                v.co = c + (v.co - c) * 1.2
    ring = TOR(0.2, 0.05, 0, G, -1.42, axis="z", segs=14, csegs=5)
    core = TOR(0.31, 0.04, 0, G, -1.85, axis="z", segs=16, csegs=4)
    return [P("Head", head, "p", blade=True), P("Flanges", fl, "s", mat="Metal"), P("Haft", [haft, wrap], "s"),
            P("Glow", [ring, core], "a", glow=True)]


# 9 Baton: a hex shock baton with metal bands and a glowing tip
@weapon(9, "Baton", hold=BLADE45)
def w_baton(st):
    shaft = T([(0, G, -0.36), (0, G, -1.4), (0, G, -2.25)], [0.14, 0.12, 0.11] if st != "b" else [0.15, 0.19, 0.21], segs=6)
    if st == "j":  # Jagged: rows of studs down the shaft
        shaft = join([shaft] + [T([(0.11 * math.cos(a), G + 0.11 * math.sin(a), z), (0.24 * math.cos(a), G + 0.24 * math.sin(a), z)],
                                  [0.05, 0.0], segs=5) for z in (-1.15, -1.7, -2.1) for a in (0.5, 2.6, 4.7)])
    hilt = [grip(0.32, -0.32, 0.13, ridges=4), C(0.2, 0.08, 0, G, -0.36, segs=12, axis="z"),
            ball(0.15, 0, G, 0.38, segs=8, rings=6)]
    bands = [TOR(0.13, 0.04, 0, G, z, axis="z", segs=10, csegs=4) for z in (-0.9, -1.45, -1.95)]
    tip = [ball(0.16, 0, G, -2.32, sc=(1, 1, 1.3), segs=10, rings=6)]
    stripes = [T([(0.12 * math.cos(a), G + 0.12 * math.sin(a), -0.5), (0.11 * math.cos(a), G + 0.11 * math.sin(a), -2.15)],
                 [0.025, 0.025], segs=4) for a in (0.0, 2.1, 4.2)]
    return [P("Shaft", shaft, "p", blade=True), P("Hilt", hilt, "s"), P("Bands", bands, "s", mat="Metal"),
            P("Tip", tip, "a", neon=True), P("Glow", stripes, "a", glow=True)]


# 10 Dagger: a leaf-shaped blade, a swept guard and a ring pommel
@weapon(10, "Dagger", hold=BLADE45)
def w_dagger(st):
    pts = [(-0.44, G + 0.13, G - 0.13), (-0.85, G + 0.17, G - 0.17), (-1.3, G + 0.1, G - 0.1), (-1.62, G, G)]
    bl, edge = blade(pts, st, t=0.055, n=10, tooth=0.1)
    hilt = [grip(0.28, -0.32, 0.09, ridges=2)]
    ring = TOR(0.13, 0.04, 0, G, 0.42, axis="x", segs=12, csegs=4)
    guard = T([(-0.34, G - 0.12, -0.28), (0, G, -0.38), (0.34, G - 0.12, -0.28)], [0.05, 0.08, 0.05], segs=6)
    return [P("Blade", bl, "p", blade=True), P("Hilt", [hilt, ring], "s"), P("Guard", guard, "s", mat="Metal"),
            P("Edge", edge, "a", glow=True)]


# 11 Greatsword: a huge blade with a raised ridge, winged guard and a glowing socket
@weapon(11, "Greatsword", hold=BLADE45)
def w_greatsword(st):
    pts = [(-0.85, G + 0.42, G - 0.42), (-1.3, G + 0.38, G - 0.38), (-4.3, G + 0.34, G - 0.34),
           (-5.0, G + 0.22, G - 0.22), (-5.55, G, G)]
    bl, edge = blade(pts, st, t=0.09, n=16, tooth=0.2)
    ridge = T([(0, G, -1.0), (0, G, -4.8)], [0.07, 0.05], segs=4)
    for v in ridge.data.vertices:
        v.co.x *= 1.4  # pushed out of both faces
    hilt = [grip(0.72, -0.72, 0.12, ridges=5), ball(0.2, 0, G, 0.85, sc=(1, 1, 1.2), segs=10, rings=6)]
    guard = [box(0.32, 0.36, 0.3, 0, G, -0.82, bev=0.06)]
    for sx in (-1, 1):
        guard.append(T([(0, G, -0.82), (sx * 0.5, G + 0.1, -0.86), (sx * 0.78, G + 0.3, -0.98)],
                       [0.12, 0.1, 0.05], segs=6))
    gem = ball(0.12, 0, G, -1.05, sc=(1.9, 1.3, 1.3), segs=8, rings=6)
    return [P("Blade", [bl, ridge], "p", blade=True), P("Hilt", hilt, "s"), P("Guard", guard, "s", mat="Metal"),
            P("Gem", gem, "a", neon=True), P("Edge", edge, "a", glow=True)]


# 12 Great Axe: a double-bitted head (big lower crescent, small upper) on a long haft
@weapon(12, "Great Axe", hold=BLADE45)
def w_greataxe(st):
    haft = [T([(0, G, 1.2), (0, G, -1.0), (0, G, -3.5)], [0.12, 0.11, 0.1], segs=10),
            ball(0.15, 0, G, 1.25, segs=8, rings=6)]
    wraps = [grip(0.4, -0.4, 0.135, ridges=3), grip(-1.4, -1.9, 0.13, ridges=2)]
    # two bits on opposite sides of the haft's end: a big crescent below, a smaller one above
    low, e1 = crescent_blade(-2.95, G, 0.85, 1.4, st, side=-1, t0=0.17, n=15, tooth=0.16)
    up, e2 = crescent_blade(-2.95, G, 0.55, 0.75, st, side=1, t0=0.15, n=11, tooth=0.12)
    spike = T([(0, G, -3.2), (0, G, -3.8)], [0.11, 0.0], segs=6)
    socket = box(0.3, 0.62, 0.55, 0, G, -2.95, bev=0.06)
    return [P("Head", [low, up, spike], "p", blade=True), P("Haft", haft, "s", mat="Wood"),
            P("Wrap", [wraps, socket], "s", mat="Metal"), P("Edge", [e1, e2], "a", glow=True)]


# 13 Warhammer: a big two-faced hammer head with rim bands and a glowing core band
@weapon(13, "Warhammer", hold=BLADE45)
def w_hammer(st):
    haft = [T([(0, G, 1.0), (0, G, -3.0)], [0.12, 0.11], segs=10), ball(0.16, 0, G, 1.05, segs=8, rings=6)]
    wraps = [grip(0.45, -0.45, 0.135, ridges=3)]
    sx = 1.12 if st == "b" else 0.92
    head = [box(sx, 1.25, sx, 0, G, -3.4, bev=0.12)]
    for s_ in (-1, 1):
        head.append(rings_mesh([[(-sx / 2, G + s_ * 0.62, -3.4 - sx / 2), (sx / 2, G + s_ * 0.62, -3.4 - sx / 2),
                                 (sx / 2, G + s_ * 0.62, -3.4 + sx / 2), (-sx / 2, G + s_ * 0.62, -3.4 + sx / 2)],
                                [(-sx * 0.36, G + s_ * 0.86, -3.4 - sx * 0.36), (sx * 0.36, G + s_ * 0.86, -3.4 - sx * 0.36),
                                 (sx * 0.36, G + s_ * 0.86, -3.4 + sx * 0.36), (-sx * 0.36, G + s_ * 0.86, -3.4 + sx * 0.36)]]))
        if st == "j":
            for dz in (-0.25, 0.25):
                for dx in (-0.25, 0.25):
                    head.append(T([(dx, G + s_ * 0.86, -3.4 + dz), (dx, G + s_ * 1.06, -3.4 + dz)], [0.08, 0.0], segs=5))
    bands = [box(sx + 0.1, 0.12, sx + 0.1, 0, G + y, -3.4, bev=0.03) for y in (-0.5, 0.5)]
    collar = C(0.17, 0.4, 0, G, -2.85, segs=10, axis="z")
    core = box(sx + 0.06, 0.1, sx + 0.06, 0, G, -3.4, bev=0.02)
    return [P("Head", head, "p", blade=True, emblem=True), P("Haft", [haft, wraps], "s"),
            P("Bands", [bands, collar], "s", mat="Metal"), P("Glow", core, "a", glow=True)]


# 14 Spear: a leaf blade with side wings on a long shaft, a glowing collar
@weapon(14, "Spear", hold=ALONG)
def w_spear(st):
    shaft = T([(0, G, 1.2), (0, G, -4.75)], [0.115, 0.1], segs=8)
    cap = [C(0.12, 0.2, 0, G, 1.2, segs=8, axis="z"), C(0.12, 0.3, 0, G, -4.7, segs=8, axis="z")]
    wraps = [grip(0.35, -0.35, 0.11, ridges=3), grip(-1.6, -2.1, 0.105, ridges=2)]
    pts = [(-4.85, G + 0.12, G - 0.12), (-5.15, G + 0.22, G - 0.22), (-5.6, G + 0.13, G - 0.13), (-6.05, G, G)]
    bl, edge = blade(pts, st, t=0.07, n=10, both_edges=True, tooth=0.1)
    wings = []
    for s_ in (-1, 1):
        wings.append(T([(0, G, -4.88), (0, G + s_ * 0.3, -4.82), (0, G + s_ * 0.42, -4.66)], [0.06, 0.045, 0.0], segs=5))
    ring = TOR(0.13, 0.045, 0, G, -4.55, axis="z", segs=12, csegs=4)
    return [P("Blade", [bl, wings], "p", blade=True), P("Shaft", shaft, "s", mat="Wood"),
            P("Fittings", [cap, wraps], "s", mat="Metal"), P("Glow", [ring, edge], "a", glow=True)]


# 15 Scythe: a long crescent blade from the top of a curved shaft, edge toward the wielder
@weapon(15, "Scythe", hold=BLADE45)
def w_scythe(st):
    shaft = T([(0, G, 1.2), (0, G + 0.08, -1.0), (0, G - 0.05, -3.0), (0, G + 0.05, -4.3)],
              [0.12, 0.115, 0.11, 0.12], segs=8)
    peg = T([(0, G, -1.5), (0, G - 0.45, -1.42)], [0.07, 0.06], segs=6)
    wraps = [grip(0.35, -0.35, 0.115, ridges=3), C(0.14, 0.3, 0, G + 0.05, -4.2, segs=10, axis="z")]
    outer = [(-4.35, G + 0.2), (-4.25, G - 0.4), (-3.95, G - 1.1), (-3.45, G - 1.7), (-2.85, G - 2.05),
             (-2.25, G - 2.15)]
    inner = [(-4.05, G - 0.05), (-3.95, G - 0.5), (-3.65, G - 1.05), (-3.2, G - 1.45), (-2.25, G - 2.15)]
    outer = widen(outer, st, -3.7, G - 0.6, 1.12)
    inner = jag_curve(inner, st, tooth=0.14, every=2, lo=0.1, hi=0.85, normal=(0.7, 0.7))
    bl = plate(crescent(outer, inner), 0, 0.15)
    back = T([(0, G + 0.1, -4.3), (0, G + 0.35, -4.55), (0, G + 0.25, -4.75)], [0.08, 0.06, 0.0], segs=6)
    edge = edge_line([(0, y + 0.02, z + 0.03) for (z, y, _) in resample([(z, y, 0) for (z, y) in inner], 9)], 0.04)
    return [P("Blade", [bl, back], "p", blade=True), P("Shaft", [shaft, peg], "s", mat="Wood"),
            P("Fittings", wraps, "s", mat="Metal"), P("Edge", edge, "a", glow=True)]


# 16 Bo Staff: a long staff with metal caps, grip wraps and glowing rings
@weapon(16, "Bo Staff", hold=ALONG)
def w_staff(st):
    staff = T([(0, G, 1.45), (0, G, -1.6), (0, G, -5.05)], [0.13, 0.12, 0.13] if st != "b" else [0.15, 0.14, 0.15], segs=10)
    caps = [C(0.155, 0.34, 0, G, 1.35, segs=10, axis="z"), C(0.155, 0.34, 0, G, -4.95, segs=10, axis="z")]
    if st == "b":  # Heavy: big iron end caps with rings
        caps = [C(0.24, 0.6, 0, G, 1.2, segs=10, axis="z"), C(0.24, 0.6, 0, G, -4.8, segs=10, axis="z")]
        caps += [TOR(0.24, 0.05, 0, G, z, axis="z", segs=12, csegs=4) for z in (0.88, 1.52, -4.48, -5.12)]
    elif st == "j":  # Jagged: a crown of short blades at each end
        for zc, d in ((1.5, 1), (-5.1, -1)):
            caps += [T([(0.12 * math.cos(a), G + 0.12 * math.sin(a), zc), (0.2 * math.cos(a), G + 0.2 * math.sin(a), zc + d * 0.4)],
                       [0.06, 0.0], segs=5) for a in (0.0, 1.57, 3.14, 4.71)]
    wraps = [grip(0.35, -0.35, 0.14, ridges=3), grip(-1.45, -1.95, 0.135, ridges=2)]
    glow = [TOR(0.145, 0.045, 0, G, z, axis="z", segs=12, csegs=4) for z in (1.05, -4.65)]
    return [P("Staff", staff, "p", blade=True), P("Caps", caps, "s", mat="Metal"), P("Wraps", wraps, "s"),
            P("Glow", glow, "a", glow=True)]


# 17 Twin Blades: a curved short blade with a hooked guard in each hand
@weapon(17, "Twin Blades", hold={"rhand": {"rx": -45}, "lhand": {"rx": -45}})
def w_twin(st):
    pts = []
    for k in range(7):
        f = k / 6
        z = -0.45 - 2.2 * f
        lift = -0.18 * f * f
        w = 0.2 - 0.04 * f
        if f > 0.8:
            w *= max(0.05, (1 - f) / 0.2)
        pts.append((z, G + lift + w, G + lift - w))
    bl, edge = blade(pts, st, t=0.06, n=12, tooth=0.12)
    hilt = [grip(0.3, -0.3, 0.09, ridges=2), ball(0.12, 0, G, 0.38, segs=8, rings=6)]
    guard = T([(0, G - 0.32, -0.12), (0, G - 0.18, -0.36), (0, G + 0.28, -0.4), (0, G + 0.38, -0.2)],
              [0.04, 0.07, 0.07, 0.03], segs=6)
    return both([P("Blade", bl, "p", blade=True), P("Hilt", hilt, "s"), P("Guard", guard, "s", mat="Metal"),
                 P("Edge", edge, "a", glow=True)])


# 18 Claws: three curved blades from a knuckle bar, a strap round the wrist
@weapon(18, "Claws", hold={"rhand": {"rx": -75}, "lhand": {"rx": -75}})
def w_claws(st):
    blades = []
    edges = []
    for x in (-0.3, 0.0, 0.3):
        pts = []
        L = 1.15 if x == 0 else 1.0
        for k in range(6):
            f = k / 5
            z = -0.55 - L * f
            dip = -0.2 * f * f
            w = 0.09 * (1 - f) + 0.01
            pts.append((z, -0.1 + dip + w, -0.1 + dip - w))
        b, e = blade(pts, st, t=0.05, n=8, x=x, tooth=0.08, edge_r=0.022)
        blades.append(b)
        edges.append(e)
    bar = [box(1.02, 0.24, 0.3, 0, -0.1, -0.46, bev=0.06), box(1.06, 0.14, 0.9, 0, 0.0, 0.05, bev=0.04)]
    return both([P("Blades", blades, "p", blade=True), P("Bar", bar, "s", mat="Metal"),
                 P("Glow", edges, "a", glow=True)])


# 19 Sai: a long centre prong with two forward-curling side prongs
@weapon(19, "Sai", hold={"rhand": {"rx": -45}, "lhand": {"rx": -45}})
def w_sai(st):
    prong = T([(0, G, -0.32), (0, G, -1.4), (0, G, -1.95)], [0.07, 0.055, 0.0], segs=8)
    wings = []
    for s_ in (-1, 1):
        wings.append(T([(0, G, -0.34), (0, G + s_ * 0.3, -0.36), (0, G + s_ * 0.38, -0.55), (0, G + s_ * 0.3, -0.85)],
                       [0.06, 0.055, 0.045, 0.0], segs=6))
        if st == "j":
            wings.append(T([(0, G + s_ * 0.06, -1.0), (0, G + s_ * 0.2, -1.12)], [0.04, 0.0], segs=5))
        if st == "b":  # Hooked: each side prong curls back into a catching hook
            wings.append(T([(0, G + s_ * 0.3, -0.85), (0, G + s_ * 0.18, -1.0), (0, G + s_ * 0.08, -0.9)],
                           [0.045, 0.035, 0.0], segs=5))
    hilt = [grip(0.3, -0.28, 0.08, ridges=3)]
    knob = ball(0.11, 0, G, 0.36, segs=8, rings=6)
    return both([P("Prong", [prong, wings], "p", blade=True), P("Hilt", hilt, "s"), P("Knob", knob, "a", glow=True)])


# 20 Tonfa: a grip peg in the hand and the long arm along the forearm's back
@weapon(20, "Tonfa", aim=("rhand", (0, 1, 0)))
def w_tonfa(st):
    arm = [box(0.32, 2.3, 0.34, 0, 0.55, 0.62, bev=0.1)]
    arm.append(ball(0.18, 0, -0.62, 0.62, sc=(0.9, 1, 1), segs=8, rings=6))
    if st == "b":  # Hooked: the long end hooks forward
        arm.append(T([(0, 1.6, 0.62), (0, 1.85, 0.4), (0, 1.8, 0.12)], [0.15, 0.12, 0.06], segs=8))
    elif st == "j":  # Jagged: studs down the outer face
        arm += [T([(0, y, 0.78), (0, y, 1.0)], [0.07, 0.0], segs=5) for y in (0.0, 0.5, 1.0, 1.5)]
    peg = [C(0.11, 0.95, 0, G + 0.05, 0.2, segs=8, axis="z"), ball(0.15, 0, G + 0.05, -0.3, segs=8, rings=6)]
    glow = box(0.06, 1.8, 0.06, 0.17, 0.62, 0.62, bev=0.015)
    glow2 = box(0.06, 1.8, 0.06, -0.17, 0.62, 0.62, bev=0.015)
    return both([P("Arm", arm, "p", blade=True), P("Peg", peg, "s"), P("Glow", [glow, glow2], "a", glow=True)])


# 21 Nunchucks: two ridged sticks on a short chain, folded together
@weapon(21, "Nunchucks", hold=BLADE45)
def w_nunchucks(st):
    r1, r2 = (0.1, 0.09) if st != "b" else (0.13, 0.12)  # Hooked: chunkier sticks with hooked ends
    s1 = T([(0, G, 0.42), (0, G, -0.62)], [r1, r2], segs=8)
    s2 = T([(0, G - 0.5, -0.72), (0, G - 0.52, 0.32)], [r2, r1], segs=8)
    if st == "b":
        s1 = join([s1, T([(0, G, 0.42), (0, G + 0.14, 0.5), (0, G + 0.2, 0.38)], [0.08, 0.06, 0.0], segs=6)])
        s2 = join([s2, T([(0, G - 0.52, 0.32), (0, G - 0.66, 0.4), (0, G - 0.72, 0.28)], [0.08, 0.06, 0.0], segs=6)])
    elif st == "j":
        s1 = join([s1] + [T([(0, G, z), (0.2 * math.cos(a), G + 0.2 * math.sin(a), z)], [0.04, 0.0], segs=4)
                          for z in (0.32,) for a in (0.0, 2.1, 4.2)])
    rid = [TOR(0.1, 0.03, 0, G, z, axis="z", segs=10, csegs=4) for z in (0.2, -0.05, -0.3)]
    rid += [TOR(0.1, 0.03, 0, G - 0.51, z, axis="z", segs=10, csegs=4) for z in (0.1, -0.15, -0.4)]
    links = chain([(0, G, -0.66), (0, G - 0.08, -0.86), (0, G - 0.3, -0.92), (0, G - 0.47, -0.78)], link=0.13,
                  r=0.04)
    caps = [ball(0.1, 0, G, -0.63, segs=8, rings=6), ball(0.1, 0, G - 0.5, -0.74, segs=8, rings=6)]
    return [P("Sticks", [s1, s2], "p", blade=True), P("Rings", rid, "s"), P("Chain", links, "s", mat="Metal"),
            P("Caps", caps, "a", glow=True)]


def round_shield(st, d, x=-0.62, y=0.0, emb=True):
    r = d / 2
    face = kit.loft("f", [(0.0, r, r, 0, 0), (0.06, r * 0.98, r * 0.98, 0, 0), (0.12, r * 0.7, r * 0.7, 0, 0),
                          (0.16, r * 0.2, r * 0.2, 0, 0)], segs=24, power=2.0, cap=(True, True))
    # the loft runs along Blender z: lay it along Roblox -x (outward) and move it onto the arm
    kit.apply_all(face)
    face.data.transform(Matrix.Rotation(-PI / 2, 4, "Y"))
    shift(face, rb(x + 0.06, y, 0))
    rim = TOR(r, 0.07 if st != "b" else 0.1, x + 0.05, y, 0, axis="x", segs=28, csegs=6)
    if st == "j":
        teeth = []
        for k in range(10):
            a = 2 * PI * k / 10
            t_ = T([(x + 0.05, y + (r + 0.02) * math.sin(a), (r + 0.02) * math.cos(a)),
                    (x + 0.05, y + (r + 0.22) * math.sin(a), (r + 0.22) * math.cos(a))], [0.07, 0.0], segs=5)
            teeth.append(t_)
        rim = join([rim] + teeth)
    boss = ball(r * 0.2, x - 0.13, y, 0, sc=(0.7, 1, 1), segs=12, rings=8)
    ring = TOR(r * 0.3, 0.04, x - 0.16, y, 0, axis="x", segs=18, csegs=4)
    straps = [box(0.5, 0.12, 1.08, x + 0.34, y + s_ * 0.25, 0, bev=0.03) for s_ in (-1, 1)]
    return face, rim, boss, ring, straps


# 22 Round Shield: a domed round shield with a rim, a boss and a glowing ring
@weapon(22, "Round Shield", hold={"llarm": {"ry": 90}}, aim=("llarm", (0, -1, 0)), face=(-1, 0, 0),
        grip_at=("llarm", (0, 0, 0)))
def w_round(st):
    face, rim, boss, ring, straps = round_shield(st, 2.2)
    return [P("Face", face, "p", at="llarm", blade=True, emblem=True), P("Rim", [rim, straps], "s", at="llarm",
                                                                         mat="Metal"),
            P("Boss", boss, "s", at="llarm", mat="Metal"), P("Glow", ring, "a", at="llarm", glow=True)]


# 23 Tower Shield: a tall curved slab with rails, a glowing band and a crest plate
@weapon(23, "Tower Shield", hold={"llarm": {"ry": 90}}, aim=("llarm", (0, -1, 0)), face=(-1, 0, 0),
        grip_at=("llarm", (0, 0, 0)))
def w_tower(st):
    H, W = 3.4, 2.0
    yc = 0.35
    rings = []
    for k in range(9):
        y = yc - H / 2 + H * k / 8
        ring = []
        # a rounded top and bottom: narrower at the ends
        e = abs(k - 4) / 4
        w = W / 2 * (1 - 0.12 * e ** 4)
        for j in range(9):
            z = -w + 2 * w * j / 8
            bend = 0.18 * (1 - (z / (W / 2)) ** 2)
            ring.append((-0.62 - bend, y, z))
        for j in range(9):
            z = w - 2 * w * j / 8
            bend = 0.18 * (1 - (z / (W / 2)) ** 2)
            ring.append((-0.62 - bend + 0.16, y, z))
        rings.append(ring)
    slab = rings_mesh(rings)
    kit.shade_auto(slab, 30)
    rails = []
    for s_ in (-1, 1):
        rails.append(box(0.24, H + 0.04, 0.16, -0.6, yc, s_ * W / 2, bev=0.06))
    for s_ in (-1, 1):
        rails.append(box(0.24, 0.14, W, -0.6, yc + s_ * H / 2, 0, bev=0.05))
    if st == "j":
        for s_ in (-1, 1):
            for k in range(4):
                rails.append(T([(-0.6, yc - 1.2 + k * 0.8, s_ * (W / 2 + 0.05)), (-0.6, yc - 1.2 + k * 0.8, s_ * (W / 2 + 0.3))],
                               [0.08, 0.0], segs=5))
    crest = box(0.12, 0.9, 0.9, -0.84, yc - 0.1, 0, bev=0.08)
    if st == "b":  # Spiked: a heavy spiked boss on the crest plate
        crest = join([crest, T([(-0.88, yc - 0.1, 0), (-1.35, yc - 0.1, 0)], [0.26, 0.0], segs=8)])
    band = box(0.1, 0.12, W * 0.92, -0.82, yc + 0.6, 0, bev=0.02)
    band2 = box(0.1, 0.12, W * 0.92, -0.82, yc - 0.8, 0, bev=0.02)
    straps = [box(0.5, 0.12, 1.08, -0.28, y, 0, bev=0.03) for y in (-0.25, 0.25)]
    return [P("Slab", slab, "p", at="llarm", blade=True, emblem=True),
            P("Rails", [rails, straps], "s", at="llarm", mat="Metal"),
            P("Crest", crest, "s", at="llarm", mat="Metal"), P("Glow", [band, band2], "a", at="llarm", glow=True)]


# 24 Sword and Shield: a pointed heater shield on the arm and an arming sword with a ring guard
@weapon(24, "Sword and Shield", hold={"llarm": {"ry": 90}, "rhand": {"rx": -45}}, aim=("rhand", (0, 0, -1)),
        face=(-1, 0, 0))
def w_swordshield(st):
    # the heater: the point toward +y (down in the stance, where the forearm's +y points at the ground)
    out = []
    for k in range(13):
        a = PI * k / 12
        out.append((0.85 * math.cos(a), -0.15 - 0.55 * math.sin(a)))  # the round top (toward -y)
    pts = [(0.85, 0.4), (0.55, 0.95), (0.0, 1.25), (-0.55, 0.95), (-0.85, 0.4)]
    poly = list(reversed(out)) + pts  # (z, y)
    poly = [(z * (1.1 if st == "b" else 1.0), y) for (z, y) in poly]
    face = prism([(z, y) for (z, y) in poly], -0.76, -0.62)
    bev = kit.bevel(face, 0.04, 1)
    kit.apply_all(bev)
    rim = T([(-0.79, y, z) for (z, y) in poly + [poly[0]]], [0.06] * (len(poly) + 1), segs=5)
    if st == "j":
        rim = join([rim] + [T([(-0.79, 0.4 + 0.25 * k, 0.86 - 0.3 * k), (-0.79, 0.5 + 0.25 * k, 1.05 - 0.3 * k)],
                              [0.06, 0.0], segs=5) for k in range(2)])
    chev = T([(-0.8, 0.2, -0.75), (-0.8, 0.55, 0.0), (-0.8, 0.2, 0.75)], [0.08, 0.1, 0.08], segs=5)
    boss = ball(0.2, -0.82, -0.15, 0, sc=(0.6, 1, 1), segs=10, rings=6)
    straps = [box(0.5, 0.12, 1.08, -0.3, y, 0, bev=0.03) for y in (-0.25, 0.25)]
    pts_b = [(-0.55, G + 0.2, G - 0.2), (-2.4, G + 0.18, G - 0.18), (-2.95, G + 0.12, G - 0.12), (-3.25, G, G)]
    bl, edge = blade(pts_b, st, t=0.065, n=12)
    hilt = [grip(0.38, -0.36, 0.095, ridges=3), ball(0.13, 0, G, 0.46, segs=8, rings=6)]
    guard = [box(0.8, 0.14, 0.18, 0, G, -0.45, bev=0.05), TOR(0.17, 0.04, 0, G + 0.02, -0.6, axis="x", segs=12, csegs=4)]
    return [P("ShieldFace", face, "p", at="llarm", blade=True, emblem=True),
            P("ShieldRim", [rim, straps], "s", at="llarm", mat="Metal"), P("Chevron", chev, "s", at="llarm"),
            P("Boss", boss, "a", at="llarm", glow=True), P("Blade", bl, "p", blade=True), P("Hilt", hilt, "s"),
            P("Guard", guard, "s", mat="Metal"), P("Edge", edge, "a", glow=True)]


def blaster_body(z0, z1, y, h, w, nose=0.12):
    """A chunky rounded blaster body along z from z0 (back) to z1 (front)."""
    rings = []
    L = z0 - z1
    for k in range(7):
        f = k / 6
        z = z0 - L * f
        sc = 1.0 - 0.18 * max(0, f - 0.7) / 0.3
        hh, ww = h * sc, w * sc
        top = y + hh / 2
        bot = y - hh / 2
        ring = [(-ww / 2, top - 0.05, z), (-ww / 2 + 0.05, top, z), (ww / 2 - 0.05, top, z), (ww / 2, top - 0.05, z),
                (ww / 2, bot + 0.05, z), (ww / 2 - 0.05, bot, z), (-ww / 2 + 0.05, bot, z), (-ww / 2, bot + 0.05, z)]
        rings.append(ring)
    ob = rings_mesh(rings)
    kit.shade_auto(ob, 40)
    return ob


def pistol(st, scale=1.0, twin=False):
    """A cartoon sci-fi blaster: body over the hand, grip down behind it, barrel coils and a glowing muzzle."""
    yb = 0.14
    body = [blaster_body(0.38, -0.82, yb, 0.4, 0.3)]
    body.append(plate([(0.2, yb + 0.2), (-0.35, yb + 0.2), (-0.5, yb + 0.34), (0.05, yb + 0.38)], 0, 0.08))  # fin
    grip_ = T([(0, yb - 0.1, 0.22), (0, yb - 0.45, 0.32), (0, yb - 0.78, 0.4)], [0.12, 0.12, 0.11], segs=8)
    for v in grip_.data.vertices:
        v.co.x *= 1.25 / 1.0
    guard = T([(0, yb - 0.2, -0.05), (0, yb - 0.42, -0.04), (0, yb - 0.4, 0.2)], [0.03, 0.03, 0.03], segs=4)
    barrels = []
    coils = []
    ys = [yb + 0.02] if not twin else [yb + 0.1, yb - 0.08]
    for by in ys:
        if st == "j":  # Heavy: a boxy shroud round a thicker barrel
            barrels.append(box(0.3 if not twin else 0.24, 0.26 if not twin else 0.18, 0.5, 0, by, -0.95, bev=0.05))
        if st == "b":  # Compact: a stub barrel
            barrels.append(C(0.1 if not twin else 0.08, 0.22, 0, by, -0.9, segs=10, axis="z"))
            continue
        barrels.append(C(0.09 if not twin else 0.07, 0.5, 0, by, -1.02, segs=10, axis="z"))
        for z in (-0.88, -1.02, -1.16):
            coils.append(TOR(0.1 if not twin else 0.08, 0.03, 0, by, z, axis="z", segs=10, csegs=4))
    mz = -1.0 if st == "b" else -1.28
    muzzle = [C(0.07 if not twin else 0.055, 0.06, 0, by, mz, segs=10, axis="z") for by in ys]
    side = box(0.04, 0.12, 0.62, 0.16, yb + 0.02, -0.3, bev=0.015)
    side2 = box(0.04, 0.12, 0.62, -0.16, yb + 0.02, -0.3, bev=0.015)
    parts = [P("Body", body, "p", blade=True), P("Grip", [grip_, guard], "s"),
             P("Barrel", [barrels, coils], "s", mat="Metal"), P("Muzzle", muzzle, "a", neon=True, glow=True),
             P("Glow", [side, side2], "a", glow=True, emblem=True)]
    if scale != 1.0:
        for p in parts:
            kit.apply_all(p.ob)
            for v in p.ob.data.vertices:
                v.co *= scale
    return parts


# 25 Blaster Pistol
@weapon(25, "Blaster Pistol", hold=ALONG)
def w_pistol(st):
    return pistol(st)


# 26 Twin Blasters: a smaller twin-barrelled blaster in each hand
@weapon(26, "Twin Blasters", hold={"rhand": {"rx": -90}, "lhand": {"rx": -90}})
def w_twins(st):
    return both(pistol(st, 0.92, twin=True))


# 27 Blaster Rifle: a long body with a stock along the forearm, a scope and glowing cells
@weapon(27, "Blaster Rifle", hold=ALONG)
def w_rifle(st):
    yb = 0.22
    body = [blaster_body(0.42, -1.75, yb, 0.46, 0.32)]
    stock = rings_mesh([[(-0.12, yb + 0.2, 0.38), (0.12, yb + 0.2, 0.38), (0.12, yb - 0.2, 0.38), (-0.12, yb - 0.2, 0.38)],
                        [(-0.13, yb + 0.26, 1.35), (0.13, yb + 0.26, 1.35), (0.13, yb - 0.32, 1.35), (-0.13, yb - 0.32, 1.35)]])
    grip_ = T([(0, yb - 0.15, 0.22), (0, yb - 0.5, 0.32), (0, yb - 0.8, 0.4)], [0.12, 0.12, 0.11], segs=8)
    fore = box(0.22, 0.3, 0.5, 0, yb - 0.32, -1.0, bev=0.06)
    barrel = [C(0.1, 0.6, 0, yb, -2.0, segs=10, axis="z"), C(0.15, 0.22, 0, yb, -2.3, segs=10, axis="z")]
    scope = [C(0.09, 0.62, 0, yb + 0.36, -0.5, segs=10, axis="z"), box(0.1, 0.16, 0.12, 0, yb + 0.27, -0.5, bev=0.02)]
    muzzle = C(0.1, 0.05, 0, yb, -2.42, segs=10, axis="z")
    if st == "b":  # Compact: a short barrel and a red-dot instead of the scope
        barrel = [C(0.11, 0.3, 0, yb, -1.88, segs=10, axis="z")]
        scope = [box(0.14, 0.14, 0.2, 0, yb + 0.3, -0.6, bev=0.03)]
        muzzle = C(0.1, 0.05, 0, yb, -2.06, segs=10, axis="z")
    elif st == "j":  # Heavy: a big muzzle brake and a power drum under the body
        barrel.append(box(0.36, 0.3, 0.32, 0, yb, -2.3, bev=0.05))
        barrel.append(C(0.22, 0.3, 0.0, yb - 0.38, -0.7, segs=12, axis="x"))
    cells = [box(0.05, 0.16, 0.18, s_ * 0.17, yb, -0.35 - k * 0.28, bev=0.02) for s_ in (-1, 1) for k in range(4)]
    lens = C(0.07, 0.03, 0, yb + 0.36, -0.82, segs=10, axis="z")
    return [P("Body", body, "p", blade=True), P("Stock", [stock, grip_, fore], "s"),
            P("Barrel", [barrel, scope], "s", mat="Metal"), P("Muzzle", [muzzle, lens], "a", neon=True, glow=True),
            P("Cells", cells, "a", glow=True, emblem=True)]


# 28 Bow: a recurve bow with glowing tips, the string toward the archer
@weapon(28, "Bow", hold={"lhand": {"rx": -90}}, aim=("lhand", (0, 1, 0)), face=(0, 0, 1),
        grip_at=("lhand", (0, G, 0)))
def w_bow(st):
    z0 = 0.0  # the riser through the palm (pt-fit: it was 0.15 past the knuckles, so the bow hung under the fist)
    riser = [box(0.18, 0.95, 0.22, 0, G, z0, bev=0.06)]
    limbs = []
    tips = []
    th = 1.2 if st == "b" else 1.0
    for s_ in (-1, 1):
        pts = [(0, G + s_ * 0.45, z0), (0, G + s_ * 1.0, z0 - 0.35), (0, G + s_ * 1.55, z0 - 0.42),
               (0, G + s_ * 1.92, z0 - 0.2), (0, G + s_ * 2.02, z0 + 0.06)]
        limbs.append(T(pts, [0.1 * th, 0.085 * th, 0.07 * th, 0.055 * th, 0.04], segs=6))
        if st == "j":
            limbs.append(T([(0, G + s_ * 1.2, z0 - 0.42), (0, G + s_ * 1.3, z0 - 0.7)], [0.05, 0.0], segs=5))
        tips.append(ball(0.09, 0, G + s_ * 2.02, z0 + 0.06, segs=8, rings=6))
    string = T([(0, G + 2.0, z0 + 0.08), (0, G, z0 + 0.5), (0, G - 2.0, z0 + 0.08)], [0.015, 0.015, 0.015], segs=4)
    rest = box(0.06, 0.2, 0.08, 0.12, G + 0.3, z0 - 0.12, bev=0.02)
    wraps = [TOR(0.14, 0.035, 0, G + y, z0, axis="up", segs=10, csegs=4) for y in (-0.25, 0.0, 0.25)]
    return [P("Limbs", limbs, "p", at="lhand", blade=True), P("Riser", [riser, wraps], "s", at="lhand"),
            P("String", string, "white", at="lhand"), P("Tips", [tips, rest], "a", at="lhand", glow=True)]


# 29 Crossbow: a stock with a swept prod, a string to the latch and a glowing bolt
@weapon(29, "Crossbow", hold=ALONG)
def w_crossbow(st):
    yb = 0.18
    stock = [blaster_body(0.9, -1.55, yb, 0.3, 0.24)]
    grip_ = T([(0, yb - 0.1, 0.22), (0, yb - 0.45, 0.32), (0, yb - 0.75, 0.38)], [0.11, 0.11, 0.1], segs=8)
    prod = []
    wide = 1.12 if st == "b" else 1.0
    for s_ in (-1, 1):
        prod.append(T([(0, yb, -1.4), (s_ * 0.5 * wide, yb + 0.04, -1.5), (s_ * 1.0 * wide, yb + 0.02, -1.38),
                       (s_ * 1.2 * wide, yb, -1.12)], [0.09, 0.085, 0.065, 0.04], segs=6))
        if st == "j":
            prod.append(T([(s_ * 0.75, yb + 0.02, -1.48), (s_ * 0.78, yb + 0.02, -1.72)], [0.05, 0.0], segs=5))
    string = T([(-1.18 * wide, yb, -1.1), (0, yb + 0.02, -0.25), (1.18 * wide, yb, -1.1)], [0.015] * 3, segs=4)
    latch = box(0.2, 0.14, 0.2, 0, yb + 0.18, -0.25, bev=0.03)
    bolt = [T([(0, yb + 0.2, -0.2), (0, yb + 0.2, -1.6)], [0.035, 0.035], segs=5),
            T([(0, yb + 0.2, -1.6), (0, yb + 0.2, -1.8)], [0.08, 0.0], segs=6)]
    return [P("Prod", prod, "p", blade=True), P("Stock", [stock, grip_], "s", mat="Wood"),
            P("String", string, "white"), P("Latch", latch, "s", mat="Metal"),
            P("Bolt", bolt, "a", glow=True)]


# 30 Arm Cannon: a cylinder round the forearm and fist, cooling fins and a glowing muzzle
@weapon(30, "Arm Cannon", hold={}, aim=("rlarm", (0, -1, 0)), grip_at=("rlarm", (0, 0, 0)))
def w_cannon(st):
    sleeve = kit.loft("s", [(-1.3, 0.56, 0.56, 0, 0), (-1.15, 0.66, 0.66, 0, 0), (0.15, 0.68, 0.68, 0, 0),
                            (0.32, 0.62, 0.62, 0, 0)], segs=16, power=2.2, cap=(False, False))
    clamp = TOR(0.64, 0.07, 0, 0.3, 0, axis="up", segs=18, csegs=5)
    muzzle = [TOR(0.5, 0.1, 0, -1.32, 0, axis="up", segs=18, csegs=5), C(0.5, 0.08, 0, -1.4, 0, segs=16)]
    fins = []
    for k in range(4):
        a = PI / 4 + k * PI / 2
        f = box(0.12, 0.9, 0.18, 0, 0, 0, bev=0.03)
        shift(f, rb(0.74, -0.45, 0))
        turn(f, "up", math.degrees(a), (0, 0, 0))
        fins.append(f)
    if st == "b":  # Compact: a slimmer sleeve with half the fins
        kit.apply_all(sleeve)
        for v in sleeve.data.vertices:
            v.co.x *= 0.86
            v.co.y *= 0.86
        fins = fins[::2]
    elif st == "j":  # Heavy: a flared muzzle and four more fins
        muzzle.append(C(0.62, 0.3, 0, -1.25, 0, segs=18, r2=0.5))
        for k in range(4):
            f = box(0.1, 0.6, 0.14, 0, 0, 0, bev=0.03)
            shift(f, rb(0.72, 0.05, 0))
            turn(f, "up", k * 90, (0, 0, 0))
            fins.append(f)
    core = [C(0.36, 0.04, 0, -1.45, 0, segs=16), TOR(0.36, 0.04, 0, -1.43, 0, axis="up", segs=16, csegs=4)]
    vents = [box(0.06, 0.5, 0.12, 0.69 * math.cos(a), -0.3, 0.69 * math.sin(a), bev=0.015)
             for a in (0.0, PI)]
    return [P("Sleeve", sleeve, "p", at="rlarm", blade=True, emblem=True),
            P("Fittings", [clamp, muzzle, fins], "s", at="rlarm", mat="Metal"),
            P("Core", core, "a", at="rlarm", neon=True, glow=True),
            P("Vents", vents, "a", at="rlarm", glow=True)]


# 31 Throwing Stars: a four-point star with a glowing hub, held flat in front of the hand
@weapon(31, "Throwing Stars", hold={})
def w_stars(st):
    pts = 5 if st == "j" else 4
    ro = 0.68 if st == "b" else 0.58
    s_ = star(ro, 0.17, 0.08, 0, G, -0.62, points=pts, axis="up")
    hub = TOR(0.15, 0.05, 0, G, -0.62, axis="up", segs=12, csegs=4)
    ring = C(0.1, 0.12, 0, G, -0.62, segs=10)
    # two spares in a holster strapped round the forearm (its outer side)
    band = box(1.08, 0.24, 1.08, 0, -0.18, 0, bev=0.05)
    spares = []
    for k, y in enumerate((-0.05, -0.3)):
        sp = star(0.3, 0.09, 0.05, 0.56, y, 0.0, points=4, axis="z")
        turn(sp, "up", 90, (0.56, y, 0.0))
        turn(sp, "x", 45 * k, (0.56, y, 0.0))
        spares.append(sp)
    return [P("Star", s_, "p", blade=True), P("Hub", hub, "s", mat="Metal"), P("Glow", ring, "a", glow=True),
            P("Holster", band, "s", at="rlarm", mat="Leather"), P("Spares", spares, "p", at="rlarm", blade=True)]


# 32 Chain Whip: a short handle and a hanging S of chain links with a glowing barb
@weapon(32, "Chain Whip", hold=HANG)
def w_whip(st):
    handle = [grip(0.4, -0.35, 0.1, ridges=3), ball(0.14, 0, G, 0.47, segs=8, rings=6),
              C(0.15, 0.1, 0, G, -0.42, segs=10, axis="z")]
    path = [(0, G, -0.48), (0, G - 0.25, -0.62), (0, G - 0.6, -0.55), (0, G - 0.9, -0.3), (0, G - 1.15, -0.2),
            (0, G - 1.4, -0.32), (0, G - 1.62, -0.5)]
    links = chain(path, link=0.18 if st != "b" else 0.22, r=0.06 if st != "b" else 0.075)
    barb = T([(0, G - 1.62, -0.5), (0, G - 1.85, -0.62)], [0.1, 0.0], segs=6)
    if st == "j":
        barb = join([barb, T([(0, G - 1.7, -0.55), (0, G - 1.6, -0.75)], [0.05, 0.0], segs=5)])
    return [P("Chain", links, "p", blade=True), P("Handle", handle, "s"), P("Barb", barb, "a", glow=True)]


# 33 War Fan: an open folding fan with metal guard ribs and a glowing rim
@weapon(33, "War Fan", hold=BLADE45)
def w_fan(st):
    cz = -0.25
    n = 11
    R = 1.5 if st == "b" else 1.35
    leaf_rings = []
    lo = []
    hi = []
    rim = []
    for k in range(n * 2 + 1):
        a = math.radians(-70 + 140 * k / (n * 2))
        rr = R * (0.94 if k % 2 else 1.0) if st != "j" else R * (0.82 if k % 2 else 1.04)
        lo.append((0.45 * math.sin(a), cz - 0.45 * math.cos(a)))
        hi.append((rr * math.sin(a), cz - rr * math.cos(a)))
        rim.append((rr * math.sin(a) * 1.0, G + 0.035, cz - rr * math.cos(a)))
    poly = hi + list(reversed(lo))
    leaf = zx_poly_prism(poly, G - 0.025, G + 0.025)
    ribs = []
    for k in range(n + 1):
        a = math.radians(-70 + 140 * k / n)
        ribs.append(T([(0, G, cz), (R * 0.98 * math.sin(a), G, cz - R * 0.98 * math.cos(a))], [0.04, 0.03], segs=4))
    guards = []
    for a in (-70, 70):
        aa = math.radians(a)
        guards.append(T([(0, G, cz + 0.05), (R * 1.04 * math.sin(aa), G, cz - R * 1.04 * math.cos(aa))],
                        [0.07, 0.05], segs=5))
    pin = C(0.12, 0.14, 0, G, cz, segs=10)
    tassel = T([(0, G, cz + 0.05), (0, G - 0.1, cz + 0.4), (0, G - 0.35, cz + 0.55)], [0.05, 0.04, 0.07], segs=5)
    edge = T(rim, [0.035] * len(rim), segs=4)
    return roll([P("Leaf", leaf, "p", blade=True, emblem=True), P("Ribs", [ribs, pin], "s"),
                 P("Guards", guards, "s", mat="Metal"), P("Tassel", tassel, "s", mat="Fabric"),
                 P("Edge", edge, "a", glow=True)], 50)


# 34 Yo-yo: a chunky yo-yo hanging on its string with a glowing gap ring
@weapon(34, "Yo-yo", hold=HANG)
def w_yoyo(st):
    yc, zc = G - 1.15, -0.2
    rr = 0.42 if st == "b" else 0.36
    halves = [C(rr, 0.13, s_ * 0.11, yc, zc, segs=18, axis="x") for s_ in (-1, 1)]
    for h in halves:
        kit.bevel(h, 0.04, 2)
        kit.apply_all(h)
    caps = [C(rr * 0.4, 0.04, s_ * 0.19, yc, zc, segs=12, axis="x") for s_ in (-1, 1)]
    if st == "j":
        for s_ in (-1, 1):
            for k in range(6):
                a = 2 * PI * k / 6
                caps.append(T([(s_ * 0.1, yc + rr * math.sin(a), zc + rr * math.cos(a)),
                               (s_ * 0.1, yc + (rr + 0.14) * math.sin(a), zc + (rr + 0.14) * math.cos(a))],
                              [0.05, 0.0], segs=4))
    gap = C(rr * 0.82, 0.08, 0, yc, zc, segs=18, axis="x")
    string = T([(0, G, zc), (0, yc + 0.05, zc)], [0.015, 0.015], segs=4)
    loop = TOR(0.12, 0.03, 0, G + 0.02, zc, axis="z", segs=10, csegs=4)
    return [P("Halves", halves, "p", blade=True, emblem=True), P("Caps", caps, "s", mat="Metal"),
            P("String", [string, loop], "white"), P("Glow", gap, "a", glow=True)]


# 35 Rope Dart: a rope coil at the hand, the rope hanging to a diamond dart with a glowing ribbon
@weapon(35, "Rope Dart", hold=HANG)
def w_dart(st):
    coil = [TOR(0.3, 0.06, 0, G - 0.05 - k * 0.09, -0.15, axis="up", segs=14, csegs=4) for k in range(3)]
    rope = T([(0, G - 0.25, -0.42), (0, G - 0.65, -0.48), (0, G - 1.0, -0.4), (0, G - 1.2, -0.3)],
             [0.04] * 4, segs=5)
    pts = [(G - 1.42, 0.12, -0.12), (G - 1.65, 0.16, -0.16), (G - 1.9, 0.06, -0.06), (G - 2.05, 0.0, 0.0)]
    # the dart: a diamond blade pointing down (a blade along -y)
    rings = []
    W = 1.3 if st == "b" else 1.0
    for (y, a, b) in resample(pts, 8):
        w = a * W
        rings.append([(0, y, -0.3 - w), (0.05, y, -0.3), (0, y, -0.3 + w), (-0.05, y, -0.3)])
    dart = rings_mesh(rings)
    if st == "j":
        dart = join([dart] + [T([(0, G - 1.55, -0.3 + s_ * 0.18), (0, G - 1.48, -0.3 + s_ * 0.34)], [0.04, 0.0],
                                segs=4) for s_ in (-1, 1)])
    ring = TOR(0.09, 0.03, 0, G - 1.3, -0.3, axis="z", segs=10, csegs=4)
    ribbon = [T([(0.0, G - 1.32, -0.25), (0.12, G - 1.45, -0.05), (0.08, G - 1.7, 0.05)], [0.05, 0.05, 0.02], segs=4),
              T([(0.0, G - 1.32, -0.35), (-0.1, G - 1.5, -0.5), (-0.04, G - 1.72, -0.55)], [0.05, 0.05, 0.02],
                segs=4)]
    return [P("Dart", dart, "p", blade=True), P("Rope", [coil, rope], "s", mat="Fabric"),
            P("Ring", ring, "s", mat="Metal"), P("Ribbon", ribbon, "a", glow=True)]


# 36 Boomerang: a chunky V of two curved arms with glowing stripes and a hub disc
@weapon(36, "Boomerang", hold=BLADE45)
def w_rang(st):
    def arm(sx):
        pts = [(0.0, -1.3), (sx * 0.34, -0.95), (sx * 0.62, -0.5), (sx * 0.78, 0.02), (sx * 0.8, 0.22)]
        out = []
        w = 0.22 if st != "b" else 0.29
        for i, (x, z) in enumerate(pts):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            dx, dz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dz)
            nx, nz = -dz / ln, dx / ln
            ww = w * (1.0 if i < 3 else (0.8 if i == 3 else 0.45))
            out.append([(x + nx * ww, G, z + nz * ww), (x + nx * ww * 0.3, G + 0.1, z + nz * ww * 0.3),
                        (x - nx * ww * 0.5, G + 0.07, z - nz * ww * 0.5), (x - nx * ww, G, z - nz * ww),
                        (x, G - 0.07, z)])
        return rings_mesh(out)
    arms = [arm(1), arm(-1)]
    if st == "j":
        for sx in (-1, 1):
            arms.append(T([(sx * 0.48, G, -0.74), (sx * 0.72, G, -0.9)], [0.06, 0.0], segs=4))
    hub = C(0.26, 0.2, 0, G, -1.2, segs=12)
    stripes = [T([(sx * 0.2, G + 0.095, -1.05), (sx * 0.56, G + 0.09, -0.55), (sx * 0.72, G + 0.08, -0.02)],
                 [0.035] * 3, segs=4) for sx in (-1, 1)]
    out = [P("Arms", arms, "p", blade=True), P("Hub", hub, "s", emblem=True), P("Glow", stripes, "a", glow=True)]
    return roll(out, 55)


def roll(pieces, deg):
    """Turn a flat weapon about its own pointing line (the grip line, z) so it reads from the side and the front."""
    for p in pieces:
        turn(p.ob, "z", deg, (0, G, 0))
    return pieces


# ---------------------------------------------------------------- build: styles, holds, fit
def apply_hold(piece, hold):
    h = hold.get(piece.at)
    if not h:
        return
    pv = PIVOT[piece.at]
    if h.get("ry"):
        turn(piece.ob, "up", h["ry"], pv)
    if h.get("rx"):
        turn(piece.ob, "x", h["rx"], pv)


def turn_vec(v, hold, at):
    """A legacy-frame direction turned by the hold (Roblox CFrame.Angles(rx, ry, 0) about the pivot)."""
    h = hold.get(at) or {}
    x, y, z = v
    a = math.radians(h.get("ry", 0))
    x, z = x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)
    a = math.radians(h.get("rx", 0))
    y, z = y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a)
    return (x, y, z)


def turn_point(p, hold, at):
    pv = PIVOT[at]
    d = turn_vec((p[0] - pv[0], p[1] - pv[1], p[2] - pv[2]), hold, at)
    return (pv[0] + d[0], pv[1] + d[1], pv[2] + d[2])


def verts(ob):
    return [tuple(round(c, 4) for c in v.co) for v in ob.data.vertices]


def bounds(ob):
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def box_of(ob):
    lo, hi = bounds(ob)
    c = (lo + hi) / 2
    s = hi - lo
    return [round(c.x, 3), round(c.z, 3), round(-c.y, 3)], [round(max(s.x, 0.02), 3), round(max(s.z, 0.02), 3),
                                                             round(max(s.y, 0.02), 3)]


ids = sorted(i for i in WEAPONS if ONLY is None or i in ONLY)
BUILT = {}  # id -> {"pieces": [Piece], "variants": {name: {"b": Piece, "j": Piece}}, "legacy": [Piece]}
for wid in ids:
    name, fn = WEAPONS[wid]
    sets = {}
    for st in ("c", "b", "j"):
        ps = fn(st)
        for p in ps:
            kit.apply_all(p.ob)
            p.ob.name = "W%02d_%s%s" % (wid, p.name, "" if st == "c" else "_" + st.upper())
            p.ob.data.name = p.ob.name
        sets[st] = ps
    names = [p.name for p in sets["c"]]
    assert len(set(names)) == len(names), (wid, names)
    legacy = []
    for p in sets["c"]:
        cp = p.ob.copy()
        cp.data = p.ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        legacy.append(Piece(p.name, cp, p.role, p.at, p.blade, p.glow, p.neon, p.emblem, p.mat, p.alpha))
    for st in ("c", "b", "j"):
        for p in sets[st]:
            apply_hold(p, HOLD[wid])
    variants = {}
    base = {p.name: p for p in sets["c"]}
    for st in ("b", "j"):
        for p in sets[st]:
            c = base[p.name]
            if verts(p.ob) == verts(c.ob):
                bpy.data.objects.remove(p.ob, do_unlink=True)
            else:
                variants.setdefault(p.name, {})[st] = p
    BUILT[wid] = {"pieces": sets["c"], "variants": variants, "legacy": legacy}

# ---------------------------------------------------------------- the fit table (src/config/WeaponArt.luau)
total = 0
lines = []
report = []
for wid in ids:
    name = WEAPONS[wid][0]
    b = BUILT[wid]
    tris = sum(kit.tris(p.ob) for p in b["pieces"])
    vt = sum(kit.tris(v.ob) for vs in b["variants"].values() for v in vs.values())
    assert tris <= BUDGET, "%s: %d triangles" % (name, tris)
    total += tris
    report.append((wid, name, tris, vt, len(b["pieces"]), sum(len(v) for v in b["variants"].values())))
    hold = HOLD[wid]
    aim = AIM[wid]
    ga, gp = GRIP[wid]
    lines.append("\t[%d] = {" % wid)
    lines.append('\t\tname = "%s",' % name)
    lines.append("\t\ttriangles = %d," % tris)
    lines.append("\t\tvariantTriangles = %d," % vt)
    hs = []
    for at in sorted(hold):
        h = hold[at]
        hs.append("%s = { rx = %d, ry = %d, pivot = { %.3f, %.3f, %.3f } }" % (at, h.get("rx", 0), h.get("ry", 0),
                                                                                 *PIVOT[at]))
    lines.append("\t\thold = { %s }," % ", ".join(hs) if hs else "\t\thold = {},")
    d = turn_vec(aim["dir"], hold, aim["at"])
    # a shield's face lives on its forearm (Sword and Shield aims with the sword hand), anything else's on aim.at
    fa = "llarm" if aim["face"] and "llarm" in hold else aim["at"]
    f = turn_vec(aim["face"], hold, fa) if aim["face"] else None
    face_s = (', face = { %.3f, %.3f, %.3f }, faceAt = "%s"' % (*f, fa)) if f else ""
    lines.append('\t\taim = { at = "%s", dir = { %.3f, %.3f, %.3f }%s },' % (aim["at"], *d, face_s))
    g = turn_point(gp, hold, ga)
    lines.append('\t\tgrip = { at = "%s", pos = { %.3f, %.3f, %.3f } },' % (ga, *g))
    if wid in GRIP2:
        g2 = turn_point((0, G, GRIP2[wid]), hold, "rhand")
        lines.append('\t\tgrip2 = { at = "rhand", pos = { %.3f, %.3f, %.3f } },' % g2)
    lines.append("\t\tpieces = {")
    for p in b["pieces"]:
        off, size = box_of(p.ob)
        flags = []
        for k in ("blade", "glow", "neon", "emblem"):
            if getattr(p, k):
                flags.append("%s = true" % k)
        if p.mat:
            flags.append('mat = "%s"' % p.mat)
        extra = (", " + ", ".join(flags)) if flags else ""
        row = '\t\t\t{ mesh = "%s", at = "%s", role = "%s"%s, offset = { %.3f, %.3f, %.3f }, size = { %.3f, %.3f, %.3f }, tris = %d' % (
            p.ob.name, p.at, p.role, extra, *off, *size, kit.tris(p.ob))
        for st, key in (("b", "broad"), ("j", "jag")):
            v = b["variants"].get(p.name, {}).get(st)
            if v:
                vo, vs = box_of(v.ob)
                row += ', %s = { mesh = "%s", offset = { %.3f, %.3f, %.3f }, size = { %.3f, %.3f, %.3f }, tris = %d }' % (
                    key, v.ob.name, *vo, *vs, kit.tris(v.ob))
        lines.append(row + " },")
    lines.append("\t\t},")
    lines.append("\t},")

meshes = sum(len(BUILT[w]["pieces"]) + sum(len(v) for v in BUILT[w]["variants"].values()) for w in ids)
HEADER = [
    "-- GENERATED by art/blender/weapons.py: do not edit by hand.",
    "-- The 36 weapons as Blender meshes (ReplicatedStorage.Art.Weapons once nate imports art/export/Weapons.fbx;",
    "-- Shared.WeaponMesh and WeaponKit weld them then, all of a weapon's meshes or none, else today's parts). By weapon",
    "-- id: hold, how the weapon is turned from WeaponKit's parts frame (degrees about x then y, CFrame.Angles(rx, ry, 0),",
    "-- about the pivot: the grip line for a hand, the forearm's centre for a shield; WeaponKit turns its parts the same",
    "-- way); aim, the weapon's pointing direction (and a shield's or bow's face) in its body part's frame; grip, where",
    "-- the hand holds it (on the hand's grip attachment); grip2, where a two-handed weapon's left hand closes on it;",
    "-- pieces, each mesh with the body part it is welded to (a LookKit ATTACH role), its colour role (p main or",
    "-- finish, s trim, a glow, white), flags (blade: takes the finish and the styles; glow: shown by the glow",
    "-- strength; neon: always lit; emblem: carries the hero's symbol), its box against that part's centre in studs",
    "-- on the classic blocks of Config.HeroRig (x right, y up, z back; Shared.BodyFit puts it on Roblox's own body),",
    "-- triangles, and its Broad and Jagged meshes where",
    "-- those styles change its shape. %d weapons, %d meshes, %d triangles (Classic)." % (len(ids), meshes, total),
    "return {",
]
if ONLY is None and not THUMBS:
    FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "WeaponArt.luau"))
    with open(FIT, "w") as fh:
        fh.write("\n".join(HEADER + lines + ["}", ""]))
    _stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
    if os.path.exists(_stylua):
        subprocess.run([_stylua, "--config-path", os.path.join(kit.ROOT, "..", "stylua.toml"), FIT], check=False)
    print("wrote", FIT)
print("weapons: %d, %d meshes, %d triangles (Classic)" % (len(ids), meshes, total))
for r in report:
    print("  %2d %-18s %5d tris (+%4d in %d style meshes), %d meshes" % (r[0], r[1], r[2], r[3], r[5], r[4]))

# ---------------------------------------------------------------- export: every mesh centred on its own box
def all_obs(wid):
    b = BUILT[wid]
    return [p.ob for p in b["pieces"]] + [v.ob for vs in b["variants"].values() for v in vs.values()]


# ---------------------------------------------------------------- --bake: one texture set a weapon (Everything Left 192)
# Every mesh of a weapon (its Classic, Broad and Jagged meshes) shares one baked texture set (hbake: the same UV
# unwrap, AO, pattern and export material as the HQ and the gear): brushed metal on blades and metal fittings, wood
# grain, fabric and leather wraps on grips, a soft plastic grain elsewhere, with the baked creases and a normal map.
# Every region is tinted (SurfaceAppearance AlphaMode Overlay: the colour map is see-through with only its shading
# and pattern laid over), so the colour WeaponKit gives each MeshPart (the finish, main, trim) still paints it.
# Glow and neon meshes are never baked (they stay the game's flat light). The weapons are baked at 3x their size so
# the patterns (drawn per stud for room-sized pieces) read at a hand weapon's size.
TEX = os.path.join(kit.ROOT, "export", "weapons", "tex")
BAKED = {}  # wid -> export material
if "--bake" in sys.argv and not THUMBS:
    import hbake  # noqa: E402

    WKIND = {"Metal": "metal", "Fabric": "fabric", "Wood": "wood", "Leather": "rubber", "Glass": "plastic"}
    for wid in ids:
        b = BUILT[wid]
        pieces = list(b["pieces"]) + [v for vs in b["variants"].values() for v in vs.values()]
        objs = []
        for p in pieces:
            if p.glow or p.neon:
                continue
            kind = "metal" if p.blade else WKIND.get(p.mat, "plastic")
            hbake.paint(p.ob, (190, 195, 205), pat=kind, tint=True)
            objs.append(p.ob)
        if not objs:
            continue
        for o in objs:
            o.scale = (3, 3, 3)
        bpy.context.view_layer.update()
        BAKED[wid] = hbake.bake("W%02d" % wid, objs, TEX, res=256 if len(objs) <= 3 else 512, ao_samples=12)
        for o in objs:
            o.scale = (1, 1, 1)
        bpy.context.view_layer.update()
        print("baked", wid, WEAPONS[wid][0], len(objs), "meshes")
    glow_mat = bpy.data.materials.new("WeaponGlow")
    glow_mat.use_nodes = True
    for wid in ids:
        b = BUILT[wid]
        for p in list(b["pieces"]) + [v for vs in b["variants"].values() for v in vs.values()]:
            if p.glow or p.neon:
                p.ob.data.materials.clear()
                p.ob.data.materials.append(glow_mat)

if BAKED and "--bakeview" in sys.argv:  # art/preview/weapon_textures.png: the baked weapons in Steel and Gold
    for o in list(bpy.context.scene.objects):
        o.hide_render = True
    kit.studio(res=(1600, 900), samples=32)
    ROLE_RGB = {"p": (190, 195, 205), "s": (70, 60, 52), "white": (240, 240, 240), "dark": (40, 40, 46)}
    shown_ids = [w for w in ids if w in BAKED][:12]
    for k, wid in enumerate(shown_ids):
        for row, gold in enumerate((False, True)):
            for p in BUILT[wid]["pieces"]:
                cp = p.ob.copy()
                cp.data = p.ob.data.copy()
                bpy.context.scene.collection.objects.link(cp)
                cp.hide_render = False
                rgb = ROLE_RGB.get(p.role, (190, 195, 205))
                if p.role == "p" and gold:
                    rgb = (255, 200, 80)
                cp.data.materials.clear()
                if p.glow or p.neon or p.role == "a":
                    cp.data.materials.append(kit.material("g%d" % k, (120, 220, 255), emit=2.0))
                else:
                    cp.data.materials.append(hbake.preview_material(BAKED[wid], rgb))
                cp.location = ((k % 6) * 2.6 - 6.5, 0, 2.6 - (k // 6) * 2.9 + (1.3 if gold else 0) * 0)
                cp.location.x += 0.9 if gold else -0.4
                cp.location.y += 0.0
    ground = kit.box("ground", 80, 40, 0.2, at=(0, 6, -4))
    ground.data.materials.append(kit.material("gr", (60, 64, 74)))
    kit.camera((0, -19, 0.5), (0, 0, 0.2), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "weapon_textures.png"))
    sys.exit(0)

if ONLY is None and "--no-export" not in sys.argv and not THUMBS:
    export = []
    for wid in ids:
        for ob in all_obs(wid):
            nm = ob.name
            ob.name = nm + "_src"  # out of the way, so the exported copy carries the exact name
            ob.data.name = nm + "_src"
            cp = ob.copy()
            cp.data = ob.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            kit.centre(cp)
            cp.name = nm
            cp.data.name = nm
            assert cp.name == nm, nm
            export.append((cp, ob, nm))
    if BAKED:  # the texture sets go inside the FBX: the importer turns them into SurfaceAppearances
        bpy.ops.object.select_all(action="DESELECT")
        for cp, _, _ in export:
            cp.select_set(True)
        bpy.ops.export_scene.fbx(filepath=os.path.join(kit.ROOT, "export", "Weapons.fbx"), use_selection=True,
                                 apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y",
                                 object_types={"MESH"}, use_mesh_modifiers=True, mesh_smooth_type="FACE",
                                 add_leaf_bones=False, bake_anim=False, path_mode="COPY", embed_textures=True)
    else:
        kit.export_fbx([cp for cp, _, _ in export], os.path.join(kit.ROOT, "export", "Weapons.fbx"))
    for cp, ob, nm in export:
        bpy.data.objects.remove(cp, do_unlink=True)
        ob.name = nm
        ob.data.name = nm
    print("wrote", os.path.join(kit.ROOT, "export", "Weapons.fbx"))

if not PREVIEW:
    sys.exit(0)

# ================================================================ previews
import wear  # noqa: E402  (the blocky body's head, face and hair meshes)

with open(os.path.join(kit.ROOT, "export", "weapons", "poses.json")) as fh:
    POSES = json.load(fh)
WINFO = {w["id"]: w for w in POSES["weapons"]}

RIG = {  # part -> (size (x, y, z), rest centre (Roblox))
    "LowerTorso": ((2.0, 0.4, 1.0), (0.0, 2.2, 0.0)), "UpperTorso": ((2.0, 1.6, 1.0), (0.0, 3.2, 0.0)),
    "Head": ((1.194, 1.277, 1.194), (0.0, 4.61, 0.0)),
    "RightUpperArm": ((1.0, 0.85, 1.0), (1.5, 3.575, 0.0)), "RightLowerArm": ((1.0, 0.85, 1.0), (1.5, 2.725, 0.0)),
    "RightHand": ((1.0, 0.3, 1.0), (1.5, 2.15, 0.0)), "LeftUpperArm": ((1.0, 0.85, 1.0), (-1.5, 3.575, 0.0)),
    "LeftLowerArm": ((1.0, 0.85, 1.0), (-1.5, 2.725, 0.0)), "LeftHand": ((1.0, 0.3, 1.0), (-1.5, 2.15, 0.0)),
    "RightUpperLeg": ((1.0, 0.85, 1.0), (0.5, 1.575, 0.0)), "RightLowerLeg": ((1.0, 0.85, 1.0), (0.5, 0.725, 0.0)),
    "RightFoot": ((1.0, 0.3, 1.0), (0.5, 0.15, 0.0)), "LeftUpperLeg": ((1.0, 0.85, 1.0), (-0.5, 1.575, 0.0)),
    "LeftLowerLeg": ((1.0, 0.85, 1.0), (-0.5, 0.725, 0.0)), "LeftFoot": ((1.0, 0.3, 1.0), (-0.5, 0.15, 0.0)),
}
ROLE_PART = {"rhand": "RightHand", "lhand": "LeftHand", "rlarm": "RightLowerArm", "llarm": "LeftLowerArm",
             "rfoot": "RightFoot", "lfoot": "LeftFoot", "rshin": "RightLowerLeg", "lshin": "LeftLowerLeg"}
# joint: (parent, child, joint point (Roblox, at rest))
JOINTS = [("Waist", "LowerTorso", "UpperTorso", (0, 2.4, 0)), ("Neck", "UpperTorso", "Head", (0, 4.0, 0)),
          ("RightShoulder", "UpperTorso", "RightUpperArm", (1.0, 3.76, 0)),
          ("RightElbow", "RightUpperArm", "RightLowerArm", (1.5, 3.15, 0)),
          ("RightWrist", "RightLowerArm", "RightHand", (1.5, 2.3, 0)),
          ("LeftShoulder", "UpperTorso", "LeftUpperArm", (-1.0, 3.76, 0)),
          ("LeftElbow", "LeftUpperArm", "LeftLowerArm", (-1.5, 3.15, 0)),
          ("LeftWrist", "LeftLowerArm", "LeftHand", (-1.5, 2.3, 0))]


def rbx_rot(a):
    """Roblox CFrame.Angles(rx, ry, rz) as a Blender 4x4 rotation (in Blender axes)."""
    rx, ry, rz = (math.radians(x) for x in a)
    Mx = Matrix.Rotation(rx, 4, "X")
    My = Matrix.Rotation(ry, 4, "Z")  # Roblox up is Blender z; the angle keeps its sign
    Mz = Matrix.Rotation(-rz, 4, "Y")  # Roblox z is Blender -y
    return Mx @ My @ Mz


def pose_world(pose):
    """Each part's world matrix (Blender) for a pose {joint: (rx, ry, rz)}: rest to posed."""
    W = {"LowerTorso": Matrix.Identity(4)}
    for j, parent, child, at in JOINTS:
        a = pose.get(j)
        R = rbx_rot(a) if a else Matrix.Identity(4)
        p = Vector(rb(*at))
        W[child] = W[parent] @ Matrix.Translation(p) @ R @ Matrix.Translation(-p)
    for n in RIG:
        W.setdefault(n, Matrix.Identity(4))
    return W


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MATC = {}


def mat(rgb, kind=None, glow=False, alpha=0.0):
    key = (tuple(int(c) for c in rgb), kind, glow, round(alpha, 2))
    if key in MATC:
        return MATC[key]
    m = bpy.data.materials.new("m%d" % len(MATC))
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
    p.inputs["Base Color"].default_value = col
    p.inputs["Roughness"].default_value = {"Metal": 0.32, "Fabric": 0.9, "Wood": 0.7, "Leather": 0.6}.get(kind, 0.45)
    p.inputs["Metallic"].default_value = 0.55 if kind == "Metal" else 0.0
    if glow:
        p.inputs["Emission Color"].default_value = col
        p.inputs["Emission Strength"].default_value = 3.0
    if alpha > 0:
        p.inputs["Alpha"].default_value = max(0.05, 1 - alpha)
    MATC[key] = m
    return m


# sample looks: (main or finish, trim, glow)
STEEL = (190, 195, 205)
LOOKS = [(STEEL, (60, 50, 45), (80, 220, 255)), ((255, 200, 80), (120, 30, 40), (255, 120, 40)),
         ((235, 60, 60), (40, 40, 48), (255, 210, 60)), (STEEL, (30, 45, 120), (120, 255, 140)),
         ((120, 80, 220), (245, 245, 245), (255, 80, 200)), ((40, 150, 80), (250, 240, 150), (255, 230, 90)),
         ((30, 28, 40), (175, 180, 190), (255, 60, 60)), ((40, 110, 220), (255, 210, 60), (110, 230, 255))]
FIXED = {"white": (240, 240, 245), "dark": (34, 38, 52)}


def colour(role, look):
    if role in FIXED:
        return FIXED[role]
    return look["psa".index(role)]


SHOWN = []


def show_copy(ob, M, rgb, kind=None, glow=False, alpha=0.0):
    cp = ob.copy()
    cp.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(cp)
    cp.data.materials.clear()
    cp.data.materials.append(mat(rgb, kind, glow, alpha))
    cp.matrix_world = M
    cp.hide_render = False
    SHOWN.append(cp)
    return cp


def clear_shown():
    for o in SHOWN:
        bpy.data.objects.remove(o, do_unlink=True)
    SHOWN.clear()


def piece_mat(p):
    return ("Metal" if p.blade else p.mat), (p.glow or p.neon)


def draw_body(at, yaw, pose, suit=(70, 74, 88), skin=(224, 172, 130)):
    """The blocky body posed, at `at` (Blender), turned yaw degrees; returns each part's world matrix."""
    Wp = pose_world(pose)
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for n, (size, c) in RIG.items():
        if n == "Head":
            continue
        ob = kit.box(n, size[0], size[2], size[1], at=rb(*c))
        kit.bevel(ob, 0.03, 1)
        kit.apply_all(ob)
        col = skin if "Hand" in n else ((40, 44, 58) if "Leg" in n or "Foot" in n or n == "LowerTorso" else suit)
        show_copy(ob, Y @ Wp[n], col)
        bpy.data.objects.remove(ob, do_unlink=True)
    h = wear.head_mesh()
    f = wear.face_plane()
    hr = wear.hair_mesh()
    for ob, col in ((h, skin), (hr, (50, 36, 30))):
        show_copy(ob, Y @ Wp["Head"], col)
        bpy.data.objects.remove(ob, do_unlink=True)
    f.matrix_world = Y @ Wp["Head"]
    f.hide_render = False
    SHOWN.append(f)
    return {n: Y @ Wp[n] for n in RIG}


def draw_weapon(wid, parts_M, look):
    for p in BUILT[wid]["pieces"]:
        part = ROLE_PART[p.at]
        c = Vector(rb(*RIG[part][1]))
        kind, glow = piece_mat(p)
        show_copy(p.ob, parts_M[part] @ Matrix.Translation(c), colour(p.role, look), kind, glow, p.alpha)


def setup(res, samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.045, 0.05, 0.065, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = world
    for nm, rot, energy in (("Key", (0.9, 0.2, 0.7), 3.2), ("Rim", (1.2, 0, 3.6), 1.8), ("Fill", (1.0, 0, -2.2), 1.0)):
        L = bpy.data.lights.new(nm, "SUN")
        L.energy = energy
        ob = bpy.data.objects.new(nm, L)
        ob.rotation_euler = rot
        sc.collection.objects.link(ob)


def ortho_cam(loc, target, scale):
    cam = kit.camera(loc, target)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    return cam


def label(src, out, cols, px, names):
    subprocess.run(["python3", os.path.abspath(__file__), "--sheet", src, out, str(cols), str(px), "|".join(names)],
                   check=True)
    os.remove(src)


for wid in BUILT:
    for p in BUILT[wid]["pieces"] + BUILT[wid]["legacy"]:
        p.ob.hide_render = True
    for vs in BUILT[wid]["variants"].values():
        for v in vs.values():
            v.ob.hide_render = True

if THUMBS:
    # each weapon alone as in weapons.png (seen from the hero's right and a little above), one render each on a
    # transparent card for art/thumbs/thumbs.py, in the one bright look every creator thumbnail uses
    setup((224, 224), 16)
    bpy.context.scene.render.film_transparent = True
    tlook = ((40, 110, 220), (235, 60, 60), (255, 210, 60))
    view = Matrix.Rotation(math.radians(24), 4, "Y") @ Matrix.Rotation(math.radians(-18), 4, "Z")
    for wid in ids:
        legacy = BUILT[wid]["legacy"]
        rights = {p.name[:-1] for p in legacy if p.name.endswith("R")}
        shown = [p for p in legacy if not (p.name.endswith("L") and p.name[:-1] in rights)]
        placed = []
        for p in shown:
            M = Matrix.Translation(Vector(rb(*RIG[ROLE_PART[p.at]][1])))
            if p.at == "llarm":
                M = Matrix.Translation(Vector(rb(1.5, 2.6, 1.4 if wid == 24 else 0.0))) @ Matrix.Rotation(PI, 4, "Z")
            if p.at == "lhand" and not rights:
                M = Matrix.Translation(Vector(rb(1.5, 2.15, 0)))
            placed.append((p, M))
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for p, M in placed:
            for v in p.ob.data.vertices:
                w = view @ M @ v.co
                lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        ctr = (lo + hi) / 2
        ext = hi - lo
        for p, M in placed:
            kind, glow = piece_mat(p)
            show_copy(p.ob, Matrix.Translation(-ctr) @ view @ M, colour(p.role, tlook), kind, glow, p.alpha)
        cam = ortho_cam((40, 0, 0), (0, 0, 0), max(ext.y, ext.z, 0.8) * 1.12)
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
        kit.render(os.path.join(kit.ROOT, "thumbs", "cells", "weapons", "%d.png" % wid))
        clear_shown()
        bpy.data.objects.remove(cam, do_unlink=True)
    sys.exit(0)

if "--styles" in sys.argv:
    # each weapon's Classic, Broad and Jagged meshes side by side (list-combat 2026-11-20, Everything Left 193: check
    # every style changes the shape): one cell a style, art/export/weapons/styles/<id>_<c|b|j>.png, then
    # `python3 art/weapons/styles_sheet.py` packs them into art/preview/weapon_styles.png
    setup((240, 240), 16)
    tlook = ((40, 110, 220), (235, 60, 60), (255, 210, 60))
    view = Matrix.Rotation(math.radians(24), 4, "Y") @ Matrix.Rotation(math.radians(-18), 4, "Z")
    outdir = os.path.join(kit.ROOT, "export", "weapons", "styles")
    os.makedirs(outdir, exist_ok=True)
    for wid in ids:
        b = BUILT[wid]
        rights = {p.name[:-1] for p in b["pieces"] if p.name.endswith("R")}
        for st in ("c", "b", "j"):
            placed = []
            for p in b["pieces"]:
                if p.name.endswith("L") and p.name[:-1] in rights:
                    continue
                ob = p.ob if st == "c" else b["variants"].get(p.name, {}).get(st, p).ob
                placed.append((p, ob, Matrix.Translation(Vector(rb(*RIG[ROLE_PART[p.at]][1])))))
            lo = Vector((1e9, 1e9, 1e9))
            hi = -lo
            for p, ob, M in placed:
                for v in ob.data.vertices:
                    w = view @ M @ v.co
                    lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                    hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
            ctr = (lo + hi) / 2
            ext = hi - lo
            for p, ob, M in placed:
                kind, glow = piece_mat(p)
                show_copy(ob, Matrix.Translation(-ctr) @ view @ M, colour(p.role, tlook), kind, glow, p.alpha)
            cam = ortho_cam((40, 0, 0), (0, 0, 0), max(ext.y, ext.z, 0.8) * 1.12)
            cam.rotation_euler = (math.radians(90), 0, math.radians(90))
            kit.render(os.path.join(outdir, "%d_%s.png" % (wid, st)))
            clear_shown()
            bpy.data.objects.remove(cam, do_unlink=True)
    sys.exit(0)

PX = int(sys.argv[sys.argv.index("--px") + 1]) if "--px" in sys.argv else (220 if FAST else 300)
SAMPLES = 10 if FAST else 28
cols = 6
rows = (len(ids) + cols - 1) // cols
setup((cols * PX, rows * PX), SAMPLES)
OUT = os.path.join(kit.ROOT, "preview")
names = ["%d %s" % (w, WEAPONS[w][0]) for w in ids]

# 1) each weapon alone, as drawn (before its hold; the right hand's pieces, hand, forearm and foot pieces where they
# sit on the resting body), seen from the hero's right and a little above, framed to its cell
cell = 6.0
for i, wid in enumerate(ids):
    r, c = i // cols, i % cols
    look = LOOKS[i % len(LOOKS)]
    legacy = BUILT[wid]["legacy"]
    rights = {p.name[:-1] for p in legacy if p.name.endswith("R")}
    shown = [p for p in legacy if not (p.name.endswith("L") and p.name[:-1] in rights)]
    placed = []
    for p in shown:
        part = ROLE_PART[p.at]
        M = Matrix.Translation(Vector(rb(*RIG[part][1])))
        if p.at == "llarm":
            # a shield faces out from the left arm: turn it to the camera, beside the right hand's weapon
            M = Matrix.Translation(Vector(rb(1.5, 2.6, 1.4 if wid == 24 else 0.0))) @ Matrix.Rotation(PI, 4, "Z")
        if p.at == "lhand" and not rights:
            M = Matrix.Translation(Vector(rb(1.5, 2.15, 0)))  # the bow: drawn where a right-hand weapon would be
        placed.append((p, M))
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for p, M in placed:
        for v in p.ob.data.vertices:
            w = M @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    ctr = (lo + hi) / 2
    ext = hi - lo
    sc_ = min(cell * 0.8 / max(ext.y, ext.z * 1.15, 0.5), 2.4)
    # the cell's centre on the camera's view plane (it looks along -x from +x)
    Mc = Matrix.Translation(Vector((0, (c - (cols - 1) / 2) * cell, -(r - (rows - 1) / 2) * cell)))
    view = Matrix.Rotation(math.radians(24), 4, "Y") @ Matrix.Rotation(math.radians(-18), 4, "Z")
    for p, M in placed:
        kind, glow = piece_mat(p)
        show_copy(p.ob, Mc @ view @ Matrix.Scale(sc_, 4) @ Matrix.Translation(-ctr) @ M, colour(p.role, look), kind,
                  glow, p.alpha)
cam = ortho_cam((40, 0, 0), (0, 0, 0), cols * cell)
cam.rotation_euler = (math.radians(90), 0, math.radians(90))
kit.render(os.path.join(OUT, "_weapons.png"))
label(os.path.join(OUT, "_weapons.png"), os.path.join(OUT, "weapons.png"), cols, PX, names)
clear_shown()


# 2) and 3) each weapon on the blocky hero: its ready stance, then the swing, shot or guard its moves play, from the
# hero's front right and a little above (orthographic, every hero centred in its cell)
def hero_sheet(kind_, out):
    cellw = 7.4
    d = Vector((0.8, 0.5, 0.26)).normalized()
    fwd = -d
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    for i, wid in enumerate(ids):
        r, c = i // cols, i % cols
        info = WINFO[wid]
        clip = info["hold"] if kind_ == "hold" else info["action"]
        pose = {j: tuple(a) for j, a in POSES["poses"].get(clip, {}).items() if j != "Root"}
        at = right * ((c - (cols - 1) / 2) * cellw) + up * (-(r - (rows - 1) / 2) * cellw) - Vector((0, 0, 3.0))
        M = draw_body(tuple(at), 0, pose)
        draw_weapon(wid, M, LOOKS[i % len(LOOKS)])
    ortho_cam(tuple(d * 80), (0, 0, 0), cols * cellw)
    kit.render(out[:-4] + "_raw.png")
    label(out[:-4] + "_raw.png", out, cols, PX, names)
    clear_shown()


if "--no-heroes" not in sys.argv:
    hero_sheet("hold", os.path.join(OUT, "weapons_held.png"))
    hero_sheet("action", os.path.join(OUT, "weapons_action.png"))
