# juice.py: the juice table's world pieces as Blender meshes (list-combat 2026-11-20, Everything Left 386: "Juice
# effects (coin burst, stamps, level badge, tier beams, fireworks, confetti, shield ring, dazed stars) are plain parts
# and frames"). Each drawn in a box the game stretches (Fx.JuiceFx), Roblox frame (x, up, z; front -z):
#   JuiceCoin   a Credit coin: a thick disc with a raised rim and a four-point sparkle struck on both faces,
#               0.25 x 1 x 1 (its faces along x, like the old cylinder coin)
#   JuiceStar   a puffy five-point cartoon star (dazed stars round a stunned head), 1 x 1 x 0.38
#   JuiceRing   a flat glow ring: a band with 12 outward ticks and an inner dashed line (rescue, revive, level up,
#               fireworks), 1 x 0.12 x 1
#   JuiceBeam   the gear drop's tier beam: a six-sided light column with three strands twisting up it, 1 x 10 x 1
#   JuiceBurst  a firework's burst: a core with 18 spikes all round, 1 x 1 x 1
# (the 5 s respawn shield wears Art.Guard's geodesic bubble; the stamps, level badge and confetti are drawn by
# art/ui/juice_ui.py)
# Output: art/export/Juice.fbx and src/config/JuiceArt.luau (generated); --preview renders art/preview/juice.png.
# Run: ~/tools/bpyenv/bin/python art/blender/juice.py [--preview] [--no-export]
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

GOLD = (255, 200, 60)


def ring_x(x, r, segs=32):
    return [(x, math.cos(2 * math.pi * k / segs) * r, math.sin(2 * math.pi * k / segs) * r) for k in range(segs)]


# ---------------------------------------------------------------- the coin
def coin():
    # a lathe along x: rim, face inset, rim
    prof = [(-0.125, 0.47), (-0.125, 0.5), (0.125, 0.5), (0.125, 0.47), (0.09, 0.42), (0.09, 0.0)]
    body = rings_mesh([ring_x(x, r) for (x, r) in prof[:5]], cap=(True, False))
    back = rings_mesh([ring_x(0.09, 0.42), ring_x(-0.09, 0.42), ring_x(-0.125, 0.47)], cap=(False, False))
    face = rings_mesh([ring_x(0.09, 0.42), ring_x(-0.09, 0.42)])
    parts = [body, back, face]
    # a four-point sparkle struck on each face
    for sx in (-1, 1):
        poly = []
        for i in range(8):
            a = math.pi / 2 + i * math.pi / 4
            r = 0.3 if i % 2 == 0 else 0.08
            poly.append((math.sin(a) * r, math.cos(a) * r))
        parts.append(prism(poly, sx * 0.09, sx * 0.125))
    mesh("Juice", "JuiceCoin", parts, GOLD, "Foil", shade=False)


# ---------------------------------------------------------------- the dazed star
def dazed_star():
    def poly(scale):
        pts = []
        for i in range(10):
            a = math.pi / 2 + i * math.pi / 5
            r = (0.5 if i % 2 == 0 else 0.23) * scale
            pts.append((math.cos(a) * r, math.sin(a) * r - 0.03))
        return pts

    rs = []
    for (z, s) in ((-0.19, 0.55), (-0.13, 0.85), (0.0, 1.0), (0.13, 0.85), (0.19, 0.55)):
        rs.append([(x, y, z) for (x, y) in poly(s)])
    mesh("Juice", "JuiceStar", rings_mesh(rs), GOLD, "Neon", shade=False)


# ---------------------------------------------------------------- the glow ring (flat, up is y)
T_ = 0.12


def flat(poly):
    return extrude_up(poly, -T_ / 2, T_ / 2)


def arc(r_out, r_in, a0, a1, segs=8):
    quads = []
    for k in range(segs):
        u, v = a0 + (a1 - a0) * k / segs, a0 + (a1 - a0) * (k + 1) / segs
        quads.append(flat([(math.cos(u) * r_in, math.sin(u) * r_in), (math.cos(u) * r_out, math.sin(u) * r_out),
                           (math.cos(v) * r_out, math.sin(v) * r_out), (math.cos(v) * r_in, math.sin(v) * r_in)]))
    return kit.join("arc", quads, shade=False)


def glow_ring():
    parts = [arc(0.43, 0.37, 2 * math.pi * k / 4, 2 * math.pi * (k + 1) / 4, 12) for k in range(4)]
    parts += [arc(0.32, 0.3, 2 * math.pi * k / 20, 2 * math.pi * (k + 0.55) / 20, 2) for k in range(20)]
    for k in range(12):
        a = 2 * math.pi * k / 12
        c, s_ = math.cos(a), math.sin(a)
        tx, tz = -s_, c
        w = 0.035
        parts.append(flat([(c * 0.42 + tx * w, s_ * 0.42 + tz * w), (c * 0.5, s_ * 0.5),
                           (c * 0.42 - tx * w, s_ * 0.42 - tz * w)]))
    mesh("Juice", "JuiceRing", parts, GOLD, "Neon")


# ---------------------------------------------------------------- the tier beam
def beam():
    rs = []
    for k in range(11):
        y = -5 + k
        r = 0.32 - 0.1 * (k / 10)
        rs.append([(math.cos(math.pi / 6 + 2 * math.pi * i / 6) * r, y, math.sin(math.pi / 6 + 2 * math.pi * i / 6) * r)
                   for i in range(6)])
    parts = [rings_mesh(rs)]
    for s in range(3):
        pts = []
        for k in range(41):
            t = k / 40
            a = 2 * math.pi * s / 3 + t * 2 * math.pi * 2.5
            r = 0.46 - 0.12 * t
            pts.append((math.cos(a) * r, -5 + 10 * t, math.sin(a) * r))
        parts.append(T(pts, 0.04, segs=5))
    # a flared foot ring
    parts.append(TOR(0.4, 0.06, 0, -4.9, 0, segs=24, csegs=6))
    mesh("Juice", "JuiceBeam", parts, (255, 255, 255), "Neon")


# ---------------------------------------------------------------- the firework burst
def burst():
    parts = [S(0.14, segs=12, rings=8)]
    n = 18
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        rr = math.sqrt(1 - y * y)
        a = golden * i
        d = Vector((math.cos(a) * rr, y, math.sin(a) * rr))
        # a cone from the core out to the tip along d
        up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        v = d.cross(u).normalized()
        base, tip = d * 0.1, d * 0.5
        ringb = [tuple(base + (u * math.cos(2 * math.pi * k / 5) + v * math.sin(2 * math.pi * k / 5)) * 0.06)
                 for k in range(5)]
        ringt = [tuple(tip + (u * math.cos(2 * math.pi * k / 5) + v * math.sin(2 * math.pi * k / 5)) * 0.004)
                 for k in range(5)]
        parts.append(rings_mesh([ringb, ringt]))
    mesh("Juice", "JuiceBurst", parts, (255, 255, 255), "Neon", shade=False)


for fn in (coin, dazed_star, glow_ring, beam, burst):
    fn()


# ================================================================ the fit table and the export
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
    "-- GENERATED by art/blender/juice.py: do not edit by hand.",
    "-- The juice table's world pieces as meshes (ReplicatedStorage.Art.Juice, Fx.JuiceFx): the Credit coin, the dazed",
    "-- star, the glow ring, the tier beam and the firework burst, each drawn in its box (x, up, z) and its triangles.",
    "-- %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "JuiceArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("juice: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Juice.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1600, 700), samples=32)
    G = LOOKS["Juice"]
    G["JuiceCoin"].data.materials.append(kit.material("coin", GOLD, metal=0.9, rough=0.3))
    G["JuiceStar"].data.materials.append(kit.material("star", GOLD, emit=0.6))
    G["JuiceRing"].data.materials.append(kit.material("ring", (120, 255, 170), emit=0.8))
    G["JuiceBeam"].data.materials.append(kit.material("beam", (190, 90, 255), emit=0.8))
    G["JuiceBurst"].data.materials.append(kit.material("burst", (255, 110, 160), emit=0.8))
    # coins in a little spray, faces to the camera (Roblox +x to Blender -y: turn -90 about up)
    for k in range(4):
        c = G["JuiceCoin"] if k == 0 else copy(G["JuiceCoin"])
        c.scale = (2.2, 2.2, 2.2)
        c.rotation_euler = (0.3 * k, 0, math.radians(-90 + 30 * k))
        c.location = (-11 + k * 1.6, 0, 2 + (k % 2) * 1.5)
    for k in range(3):
        s_ = G["JuiceStar"] if k == 0 else copy(G["JuiceStar"])
        s_.scale = (1.6, 1.6, 1.6)
        s_.rotation_euler = (0, math.radians(20 * (k - 1)), math.radians(15 * (k - 1)))
        a = 2 * math.pi * k / 3
        s_.location = (-3.5 + math.cos(a) * 1.4, math.sin(a) * 1.4, 4.5)
    G["JuiceRing"].scale = (8, 8, 1)
    G["JuiceRing"].location = (-3.5, 0, 0.1)
    G["JuiceBeam"].scale = (1.5, 1.5, 0.9)
    G["JuiceBeam"].location = (3.5, 0, 4.5)
    G["JuiceBurst"].scale = (5, 5, 5)
    G["JuiceBurst"].location = (10, 0, 4)
    ground = kit.box("ground", 60, 30, 0.2, at=(0, 0, -0.1))
    ground.data.materials.append(kit.material("g", (70, 74, 84)))
    kit.camera((0, -24, 7), (0, 0, 3.5), lens=32)
    kit.render(os.path.join(kit.ROOT, "preview", "juice.png"))
