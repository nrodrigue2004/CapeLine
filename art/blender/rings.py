# rings.py: the PvP flag rings and the Downed ring as Blender meshes (list-combat 2026-11-20, Everything Left 385:
# "PvP flag rings and the Downed ring are flat glowing discs"). Flat outlines on the ground, drawn in a 1 x 0.12 x 1
# stud box (the game stretches each to its ring's size; Fx.PvpFx), glowing Neon in the side's colour:
#   RingRound   the Vigil's ring: a round band with 8 inward chevrons (round = the Vigil, colourblind-safe)
#   RingSquare  the Syndicate's ring: a square frame with notched corners and 4 inward chevrons (square = Syndicate)
#   RingDowned  the Downed ring: a dashed round band with 4 small plus marks (help is needed here)
# Output: art/export/Rings.fbx and src/config/RingArt.luau (generated); --preview renders art/preview/rings.png.
# Run: ~/tools/bpyenv/bin/python art/blender/rings.py [--preview] [--no-export]
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

kit.reset()
from studs import *  # noqa: E402,F401,F403
from studs import LOOKS, INFO  # noqa: E402

T_ = 0.12  # thickness


def flat(poly, y0=-T_ / 2, y1=T_ / 2):
    """A flat (x, z) polygon pushed up a little."""
    return extrude_up(poly, y0, y1)


def chevron(at, ang, w=0.06, l=0.07):
    """A small triangle on the ground at radius `at`, pointing to the middle (convex, so its caps stay clean)."""
    c, s_ = math.cos(ang), math.sin(ang)
    bx, bz = at * c, at * s_
    tx, tz = -s_, c
    return flat([(bx + tx * w, bz + tz * w), (bx - c * l, bz - s_ * l), (bx - tx * w, bz - tz * w)])


def band(r_out, r_in, segs=48, a0=0.0, a1=2 * math.pi):
    pts_o = [(math.cos(a0 + (a1 - a0) * k / segs) * r_out, math.sin(a0 + (a1 - a0) * k / segs) * r_out) for k in range(segs + 1)]
    pts_i = [(math.cos(a0 + (a1 - a0) * k / segs) * r_in, math.sin(a0 + (a1 - a0) * k / segs) * r_in) for k in range(segs + 1)]
    return pts_o, pts_i


def ring_mesh(r_out, r_in, segs=48):
    # a closed band as rings: outer and inner loops, extruded (top and bottom caps between them)
    rs = []
    for y in (-T_ / 2, T_ / 2):
        rs.append([(math.cos(2 * math.pi * k / segs) * r_out, y, math.sin(2 * math.pi * k / segs) * r_out) for k in range(segs)])
    outer = rings_mesh(rs, cap=(False, False))
    rs = []
    for y in (-T_ / 2, T_ / 2):
        rs.append([(math.cos(2 * math.pi * k / segs) * r_in, y, math.sin(2 * math.pi * k / segs) * r_in) for k in range(segs)])
    inner = rings_mesh(rs, cap=(False, False))
    # caps: thin quads round the band
    tops = []
    for k in range(segs):
        a, b = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
        q = [(math.cos(a) * r_in, math.sin(a) * r_in), (math.cos(a) * r_out, math.sin(a) * r_out),
             (math.cos(b) * r_out, math.sin(b) * r_out), (math.cos(b) * r_in, math.sin(b) * r_in)]
        tops.append(flat(q))
    return [outer, inner] + tops


def arc(r_out, r_in, a0, a1, segs=8):
    """A band from angle a0 to a1 as one solid of small convex quads (a concave outline would fan across its hole)."""
    quads = []
    for k in range(segs):
        u, v = a0 + (a1 - a0) * k / segs, a0 + (a1 - a0) * (k + 1) / segs
        quads.append(flat([(math.cos(u) * r_in, math.sin(u) * r_in), (math.cos(u) * r_out, math.sin(u) * r_out),
                           (math.cos(v) * r_out, math.sin(v) * r_out), (math.cos(v) * r_in, math.sin(v) * r_in)]))
    return kit.join("arc", quads, shade=False)


# ---------------------------------------------------------------- the Vigil's round ring
parts = [arc(0.5, 0.43, 2 * math.pi * k / 4, 2 * math.pi * (k + 1) / 4, 12) for k in range(4)]
parts += [arc(0.36, 0.34, 2 * math.pi * k / 16, 2 * math.pi * (k + 0.6) / 16, 3) for k in range(16)]  # inner dashes
parts += [chevron(0.42, 2 * math.pi * k / 8 + math.pi / 8) for k in range(8)]
mesh("Rings", "RingRound", parts, (90, 170, 255), "Neon")

# ---------------------------------------------------------------- the Syndicate's square ring
sq = []
o, i = 0.5, 0.43
for (x0, z0, x1, z1) in ((-o + 0.09, -o, o - 0.09, -i), (-o + 0.09, i, o - 0.09, o), (-o, -o + 0.09, -i, o - 0.09),
                         (i, -o + 0.09, o, o - 0.09)):
    sq.append(flat([(x0, z0), (x1, z0), (x1, z1), (x0, z1)]))
for sx in (-1, 1):  # notched corners: an L of two short bars standing off each corner
    for sz in (-1, 1):
        sq.append(flat([(sx * 0.5, sz * 0.5), (sx * 0.35, sz * 0.5), (sx * 0.35, sz * 0.455), (sx * 0.5, sz * 0.455)]))
        sq.append(flat([(sx * 0.5, sz * 0.5), (sx * 0.455, sz * 0.5), (sx * 0.455, sz * 0.35), (sx * 0.5, sz * 0.35)]))
sq += [chevron(0.42, math.pi / 2 * k) for k in range(4)]
mesh("Rings", "RingSquare", sq, (255, 80, 80), "Neon")

# ---------------------------------------------------------------- the Downed ring: dashes and plus marks
dn = [arc(0.5, 0.44, 2 * math.pi * k / 12, 2 * math.pi * (k + 0.62) / 12, 4) for k in range(12)]
for k in range(4):
    a = 2 * math.pi * k / 4 + math.pi / 4
    cx, cz = math.cos(a) * 0.37, math.sin(a) * 0.37
    dn.append(flat([(cx - 0.05, cz - 0.015), (cx + 0.05, cz - 0.015), (cx + 0.05, cz + 0.015), (cx - 0.05, cz + 0.015)]))
    dn.append(flat([(cx - 0.015, cz - 0.05), (cx + 0.015, cz - 0.05), (cx + 0.015, cz + 0.05), (cx - 0.015, cz + 0.05)]))
mesh("Rings", "RingDowned", dn, (170, 170, 180), "Neon")


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


rows = []
total = 0
for look in sorted(LOOKS):
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        size = hi - lo
        t = kit.tris(ob)
        total += t
        rows.append('\t%s = { size = { %.3f, %.3f, %.3f }, tris = %d },' % (name, size.x, size.z, size.y, t))
text = "\n".join([
    "-- GENERATED by art/blender/rings.py: do not edit by hand.",
    "-- The PvP flag rings and the Downed ring as meshes (ReplicatedStorage.Art.Rings, Fx.PvpFx): each drawn in a",
    "-- 1 x 0.12 x 1 box (x, up, z) the game stretches to its ring, and its triangles. %d meshes, %d triangles."
    % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "RingArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("rings: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Rings.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1500, 560), samples=24)
    for k, name in enumerate(("RingRound", "RingSquare", "RingDowned")):
        ob = LOOKS["Rings"][name]
        rgb, mat, _ = INFO[name]
        ob.data.materials.append(kit.material("m_" + name, rgb, emit=2.5))
        ob.scale = (7, 7, 1)
        ob.location = ((k - 1) * 9, 0, 0.1)
        if name == "RingSquare":
            ob.rotation_euler = (0, 0, math.radians(45))
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    kit.camera((0, -22, 18), (0, 0, 0), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "rings.png"))
