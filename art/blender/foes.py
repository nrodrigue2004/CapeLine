# foes.py: the robots' gear and the side quest foes' props as Blender meshes (list-combat 2026-11-20, Everything Left
# 223 and 229: "the newer robots' gear is plain blocks", "enemy props are plain blocks"). Each mesh is drawn to fill
# the box of the EnemyRenderer part with the same name, in that part's own frame (x, up, z; front -z), so
# EnemyRenderer swaps the part for it in place (its colour and material kept, the import turn from MeshFix):
#   riot shield (Riot), officer's cap (Cap, CapPeak), the rifle and its scope (Rifle, Scope), the bandolier (Strap,
#   Grenade, Satchel), the medic's backpack (Medpack), the jet wings (WingL, WingR), the hook launcher (Launcher,
#   Claw, ClawFinger), Skylance's spear (Spear, SpearTip), the toys' wind-up key (KeyShaft, KeyBow), the Salt Dogs'
#   hook (HookShaft, HookCurve, HookTip), Captain Brine's anchor (AnchorShank, AnchorStock, AnchorFluke, AnchorRing)
#   and the Tidewright's trident (TridentShaft, TridentBar, TridentProng). Cartoon sci-fi: the rifle is a chunky
#   blaster, never a real firearm.
# Output: art/export/Foes.fbx and src/config/FoeArt.luau (generated); --preview renders art/preview/foes.png.
# Run: ~/tools/bpyenv/bin/python art/blender/foes.py [--preview] [--no-export]
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

STEEL = (190, 195, 205)
DARK = (60, 62, 72)
BRASS = (215, 170, 70)
IRON = (70, 75, 85)
FABRIC = (110, 85, 50)


def ring_pts(r, y, n=12, sx=1.0, sz=1.0, z0=0.0):
    return [(math.cos(2 * math.pi * k / n) * r * sx, y, z0 + math.sin(2 * math.pi * k / n) * r * sz) for k in range(n)]


# ---------------------------------------------------------------- the riot shield: a curved plate, a raised rim,
# a ridge down the middle; its face toward -z, 2.5 x 3 x 0.25
def riot():
    W, Hh, cur = 1.25, 1.5, 0.12
    rings = []
    for k in range(9):
        y = -Hh + 2 * Hh * k / 8
        ring = []
        for i in range(13):
            x = -W + 2 * W * i / 12
            ring.append((x, y, -cur * (1 - (x / W) ** 2)))
        rings.append(ring)
    # a thin curved plate: the front sheet and the back sheet as one closed loop per row
    loops = []
    for ring in rings:
        front = ring
        back = [(x, y, z + 0.09) for (x, y, z) in reversed(ring)]
        loops.append(front + back)
    plate = rings_mesh(loops)
    rim = []
    for (a, b) in (((-W, -Hh), (W, -Hh)), ((W, -Hh), (W, Hh)), ((W, Hh), (-W, Hh)), ((-W, Hh), (-W, -Hh))):
        za = -cur * (1 - (a[0] / W) ** 2) - 0.02
        zb = -cur * (1 - (b[0] / W) ** 2) - 0.02
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        zm = -cur * (1 - (mid[0] / W) ** 2) - 0.02
        rim.append(T([(a[0], a[1], za), (mid[0], mid[1], zm), (b[0], b[1], zb)], 0.07, segs=6))
    ridge = T([(0, -Hh * 0.9, -cur - 0.03), (0, Hh * 0.9, -cur - 0.03)], 0.06, segs=6)
    grip = B(0.5, 0.18, 0.12, 0, 0, 0.12)
    mesh("Riot", "Riot", [plate] + rim + [ridge, grip], DARK, "Metal")


# ---------------------------------------------------------------- the officer's cap: its crown is drawn along x
# (the game stands the part's x up): a band at -x widening to a flat top at +x with piping
def cap():
    rings = []
    for (x, r) in ((-0.19, 0.6), (-0.06, 0.6), (0.05, 0.64), (0.15, 0.69), (0.19, 0.69)):
        rings.append([(x, math.cos(2 * math.pi * k / 20) * r, math.sin(2 * math.pi * k / 20) * r) for k in range(20)])
    crown = rings_mesh(rings)
    pipe = TOR(0.69, 0.03, 0.17, 0, 0, axis="x", segs=24, csegs=5)
    band = TOR(0.605, 0.035, -0.12, 0, 0, axis="x", segs=24, csegs=5)
    mesh("Cap", "Cap", [crown, pipe, band], DARK, "Fabric")
    # the peak: a curved brim (a flattened half disc) reaching forward (-z), 1 x 0.08 x 0.55
    rings = []
    for k in range(7):
        t = k / 6
        z = -0.55 * t
        w = 0.5 * math.sqrt(max(0.0, 1 - (t * 0.92) ** 2))
        dip = -0.03 * t * t
        rings.append([(-w, dip, z), (0, dip + 0.02, z), (w, dip, z), (0, dip - 0.025, z)])
    mesh("Cap", "CapPeak", rings_mesh(rings), (25, 25, 30), "SmoothPlastic")


# ---------------------------------------------------------------- the rifle: a chunky cartoon blaster along z, the
# muzzle at +z (where the aim laser starts), the stock at -z; 0.17 x 0.22 x 3.3
def rifle():
    L = 3.3
    st = []
    for (z, w, yb, yt) in ((-1.65, 0.06, -0.11, 0.06), (-1.2, 0.08, -0.1, 0.07), (-0.9, 0.06, -0.03, 0.06),
                           (-0.55, 0.08, -0.06, 0.09), (0.3, 0.085, -0.07, 0.1), (0.6, 0.06, -0.04, 0.06),
                           (1.65, 0.05, -0.035, 0.045)):
        st.append((z, w, yb, yt))
    body = loft_z(st, segs=10)
    grip = B(0.09, 0.3, 0.12, 0, -0.18, -0.4)
    turn(grip, "x", -15, (0, -0.05, -0.4))
    mag = B(0.1, 0.22, 0.18, 0, -0.16, 0.05)
    rings = [C(0.06, 0.04, 0, 0, z, segs=10, axis="z") for z in (0.9, 1.15, 1.4)]
    mesh("Rifle", "Rifle", [body, grip, mag] + rings, DARK, "Metal")
    tube = C(0.065, 1.0, 0, 0, 0, segs=12, axis="z")
    lens1 = C(0.075, 0.08, 0, 0, -0.5, segs=12, axis="z")
    lens2 = C(0.08, 0.08, 0, 0, 0.42, segs=12, axis="z")
    mesh("Rifle", "Scope", [tube, lens1, lens2], STEEL, "Metal")


# ---------------------------------------------------------------- the bandolier: a stitched strap with a buckle,
# a cartoon grenade (round body, cap and pull ring) and a satchel with a flap
def bandolier():
    strap = B(0.4, 2.6, 0.06)
    stitch = [B(0.02, 2.5, 0.08, x, 0, 0) for x in (-0.16, 0.16)]
    buckle = B(0.5, 0.3, 0.1, 0, 0.6, -0.01)
    hole = B(0.3, 0.14, 0.12, 0, 0.6, -0.02)
    loops = [B(0.44, 0.1, 0.1, 0, y, -0.01) for y in (-0.7, 0.0)]
    mesh("Bandolier", "Strap", [strap, buckle] + stitch + loops + [hole], (70, 55, 35), "Fabric")
    body = S(0.3, 0, -0.03, 0, sc=(1, 1.05, 1), segs=14, rings=9)
    bands = [TOR(0.29, 0.025, 0, y, 0, segs=16, csegs=4) for y in (-0.12, 0.06)]
    capp = C(0.11, 0.12, 0, 0.24, 0, segs=10)
    lever = B(0.06, 0.24, 0.05, 0.12, 0.22, 0)
    ring = TOR(0.07, 0.015, -0.1, 0.32, 0, axis="z", segs=12, csegs=4)
    mesh("Bandolier", "Grenade", [body, capp, lever, ring] + bands, (70, 85, 45), "Metal")
    bag = B(0.5, 0.32, 0.66, 0, -0.02, 0, bev=0.06)
    flap = B(0.52, 0.06, 0.68, 0, 0.15, 0, bev=0.02)
    lip = B(0.52, 0.16, 0.06, 0, 0.08, -0.33)
    clasp = B(0.12, 0.1, 0.05, 0, 0.06, -0.36)
    mesh("Bandolier", "Satchel", [bag, flap, lip, clasp], FABRIC, "Fabric")


# ---------------------------------------------------------------- the medic's backpack: a rounded pack, a top
# handle, side pockets and straps over the front edge; 1.5 x 1.7 x 0.55
def medpack():
    pack = B(1.3, 1.6, 0.5, 0, -0.03, 0.02, bev=0.14)
    lid = B(1.34, 0.22, 0.54, 0, 0.66, 0.02, bev=0.08)
    pockets = [B(0.1, 0.8, 0.36, x, -0.3, 0.04, bev=0.04) for x in (-0.7, 0.7)]
    handle = T([(-0.25, 0.77, 0.02), (-0.2, 0.85, 0.02), (0.2, 0.85, 0.02), (0.25, 0.77, 0.02)], 0.035, segs=6)
    straps = [B(0.16, 1.5, 0.05, x, 0, -0.25) for x in (-0.38, 0.38)]
    mesh("Medpack", "Medpack", [pack, lid, handle] + pockets + straps, (230, 232, 236), "SmoothPlastic")


# ---------------------------------------------------------------- the jet wings: a swept, tapered wing with a
# leading edge and two panel ribs; the root at the body, the tip out (+x for the right, -x for the left)
def wings():
    for name, s in (("WingR", 1), ("WingL", -1)):
        rings = []
        for k in range(6):
            t = k / 5
            x = s * (-1.0 + 2.0 * t)
            chord = 1.0 - 0.55 * t
            z0 = -0.5 + 0.35 * t
            th = 0.06 * (1 - 0.5 * t)
            rings.append([(x, 0, z0), (x, th, z0 + chord * 0.3), (x, 0, z0 + chord), (x, -th, z0 + chord * 0.3)])
        wing = rings_mesh(rings)
        ribs = [T([(s * x, 0.05, -0.45 + 0.35 * (x + 1) / 2), (s * x, 0.05, 0.4 - 0.2 * (x + 1) / 2)], 0.02, segs=4)
                for x in (-0.4, 0.3)]
        mesh("Wings", name, [wing] + ribs, STEEL, "Metal")


# ---------------------------------------------------------------- the hook launcher: a fat drum along z, its muzzle
# at -z (toward the claw), cooling rings and a top rail; the claw's hub and a hooked finger
def launcher():
    drum = C(0.45, 1.2, 0, 0, 0, segs=16, axis="z")
    muzzle = C(0.36, 0.16, 0, 0, -0.68, segs=16, axis="z")
    bore = C(0.24, 0.2, 0, 0, -0.75, segs=12, axis="z")
    rings = [TOR(0.47, 0.035, 0, 0, z, axis="z", segs=18, csegs=4) for z in (-0.35, -0.05, 0.25)]
    rail = B(0.16, 0.12, 1.0, 0, 0.5, -0.05)
    mesh("Launcher", "Launcher", [drum, muzzle, bore, rail] + rings, DARK, "Metal")
    hub = C(0.3, 0.3, 0, -0.15, 0, segs=14)
    bolts = [C(0.05, 0.06, math.cos(a) * 0.2, 0.0, math.sin(a) * 0.2, segs=6) for a in (0, 2.1, 4.2)]
    mesh("Launcher", "Claw", [hub] + bolts, (200, 160, 60), "Metal")
    finger = T([(0, 0.22, 0), (0.02, 0.0, 0.03), (0.04, -0.16, 0.0), (0.0, -0.24, -0.08)], [0.06, 0.06, 0.045, 0.01],
               segs=6)
    mesh("Launcher", "ClawFinger", finger, STEEL, "Metal")


# ---------------------------------------------------------------- Skylance's spear: a wrapped shaft with bands and a
# butt cap (0.18 x 6.9 x 0.18) and a leaf blade with a fuller (0.35 x 0.9 x 0.35)
def spear():
    L = 6.9
    shaft = C(0.07, L * 0.98, 0, 0, 0, segs=8)
    bands = [C(0.09, 0.12, 0, y, 0, segs=8) for y in (-L * 0.45, L * 0.05, L * 0.45)]
    wraps = [TOR(0.075, 0.02, 0, -0.6 + k * 0.14, 0, segs=10, csegs=4) for k in range(8)]
    butt = S(0.09, 0, -L * 0.49, 0, segs=8, rings=6)
    mesh("Spear", "Spear", [shaft, butt] + bands + wraps, (215, 220, 230), "Metal")
    rings = []
    for (y, w) in ((-0.45, 0.04), (-0.35, 0.12), (-0.05, 0.17), (0.2, 0.12), (0.45, 0.0)):
        rings.append([(w, y, 0), (0, y, 0.045 + w * 0.15), (-w, y, 0), (0, y, -0.045 - w * 0.15)])
    blade = rings_mesh(rings)
    mesh("Spear", "SpearTip", blade, (255, 210, 90), "Neon")


# ---------------------------------------------------------------- the wind-up key: a shaft along z with a collar
# and a square boss, and a bow: a ring round x with a cross web
def windkey():
    shaft = C(0.07, 1.0, 0, 0, 0, segs=10, axis="z")
    collar = C(0.12, 0.12, 0, 0, -0.42, segs=12, axis="z")
    boss = B(0.2, 0.2, 0.22, 0, 0, 0.45)
    mesh("WindKey", "KeyShaft", [shaft, collar, boss], BRASS, "Metal")
    ring = TOR(0.28, 0.05, 0, 0, 0, axis="x", segs=20, csegs=6)
    web = B(0.06, 0.5, 0.1)
    web2 = B(0.06, 0.1, 0.5)
    mesh("WindKey", "KeyBow", [ring, web, web2], BRASS, "Metal")


# ---------------------------------------------------------------- the Salt Dogs' hook: a cuffed shaft, a bend and
# a barbed point
def hook():
    cuff = C(0.11, 0.14, 0, 0.11, 0, segs=10)
    shaft = C(0.07, 0.36, 0, -0.1, 0, segs=10)
    mesh("Hook", "HookShaft", [cuff, shaft], (190, 195, 205), "Metal")
    bend = T([(0, 0.08, 0.42), (0, -0.04, 0.2), (0, -0.07, -0.05), (0, -0.02, -0.3), (0, 0.08, -0.45)], 0.08, segs=8)
    mesh("Hook", "HookCurve", bend, (190, 195, 205), "Metal")
    tip = rings_mesh([[(0.08, -0.12, 0), (0, -0.12, 0.08), (-0.08, -0.12, 0), (0, -0.12, -0.08)],
                      [(0.05, 0.05, 0.02), (0, 0.05, 0.07), (-0.05, 0.05, 0.02), (0, 0.05, -0.04)],
                      [(0.005, 0.15, 0.06), (0, 0.15, 0.065), (-0.005, 0.15, 0.06), (0, 0.15, 0.055)]])
    mesh("Hook", "HookTip", tip, (190, 195, 205), "Metal")


# ---------------------------------------------------------------- Captain Brine's anchor: a tapered shank with a
# collar, a stock with ball ends, spade flukes and a heavy ring round x
def anchor():
    shank = C(0.2, 3.3, 0, 0, 0, segs=10, r2=0.15)
    collar = C(0.26, 0.2, 0, 1.2, 0, segs=10)
    crown = S(0.26, 0, -1.6, 0, segs=10, rings=6)
    mesh("Anchor", "AnchorShank", [shank, collar, crown], IRON, "Metal")
    bar = C(0.13, 1.2, 0, 0, 0, segs=10, axis="x")
    balls = [S(0.2, x, 0, 0, segs=10, rings=6) for x in (-0.62, 0.62)]
    mesh("Anchor", "AnchorStock", [bar] + balls, IRON, "Metal")
    arm = C(0.14, 0.75, 0, -0.1, 0, segs=8, r2=0.11)
    spade = rings_mesh([[(0, 0.6, 0.07), (0.22, 0.45, 0), (0, 0.6, -0.07), (-0.22, 0.45, 0)],
                        [(0, 0.35, 0.1), (0.25, 0.4, 0), (0, 0.35, -0.1), (-0.25, 0.4, 0)],
                        [(0, 0.05, 0.03), (0.03, 0.1, 0), (0, 0.05, -0.03), (-0.03, 0.1, 0)]])
    turn(spade, "x", 180)
    shift(spade, rb(0, -0.1, 0))
    mesh("Anchor", "AnchorFluke", [arm, spade], IRON, "Metal")
    ring = TOR(0.27, 0.08, 0, 0, 0, axis="x", segs=20, csegs=6)
    mesh("Anchor", "AnchorRing", ring, IRON, "Metal")


# ---------------------------------------------------------------- the Tidewright's trident: a shaft with scale
# bands and a grip, a crossbar that sweeps up at its ends, and a barbed prong
def trident():
    L = 4.2
    shaft = C(0.15, L, 0, 0, 0, segs=10)
    bands = [C(0.21, 0.14, 0, y, 0, segs=10) for y in (-L * 0.45, -L * 0.1, L * 0.3, L * 0.47)]
    wraps = [TOR(0.16, 0.035, 0, -0.9 + k * 0.16, 0, segs=10, csegs=4) for k in range(7)]
    mesh("Trident", "TridentShaft", [shaft] + bands + wraps, (180, 140, 70), "Metal")
    bar = T([(-0.67, 0.18, 0), (-0.45, -0.05, 0), (0, -0.12, 0), (0.45, -0.05, 0), (0.67, 0.18, 0)],
            [0.12, 0.16, 0.2, 0.16, 0.12], segs=8)
    shell = S(0.2, 0, -0.08, -0.05, sc=(1, 1, 0.6), segs=10, rings=6)
    mesh("Trident", "TridentBar", [bar, shell], (180, 140, 70), "Metal")
    rings = []
    for (y, r) in ((-0.65, 0.13), (-0.2, 0.12), (0.3, 0.1), (0.55, 0.06), (0.65, 0.0)):
        rings.append(ring_pts(r, y, n=8))
    prong = rings_mesh(rings)
    barbs = [T([(s * 0.08, 0.32, 0), (s * 0.17, 0.12, 0), (s * 0.14, 0.04, 0)], [0.05, 0.04, 0.0], segs=4)
             for s in (-1, 1)]
    mesh("Trident", "TridentProng", [prong] + barbs, (180, 140, 70), "Metal")


riot()
cap()
rifle()
bandolier()
medpack()
wings()
launcher()
spear()
windkey()
hook()
anchor()
trident()


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
        rows.append('\t%s = { look = "%s", size = { %.3f, %.3f, %.3f }, tris = %d },'
                    % (name, look, max(size.x, 0.02), max(size.z, 0.02), max(size.y, 0.02), t))
text = "\n".join([
    "-- GENERATED by art/blender/foes.py: do not edit by hand.",
    "-- The robots' gear and the side quest foes' props as meshes (ReplicatedStorage.Art.Foes, EnemyRenderer): each",
    "-- named for the EnemyRenderer part whose box it fills (x, up, z as drawn; the game stretches it to the part), the",
    "-- prop it belongs to and its triangles. %d meshes, %d triangles." % (len(INFO), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "FoeArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("foes: %d meshes, %d tris" % (len(INFO), total))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Foes.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    kit.studio(res=(1600, 1000), samples=24)
    k = 0
    for look in sorted(LOOKS):
        for name in sorted(LOOKS[look]):
            ob = LOOKS[look][name]
            rgb, mat, _ = INFO[name]
            ob.data.materials.append(kit.material("m_" + name, rgb, metal=0.5 if mat == "Metal" else 0,
                                                  emit=2.0 if mat == "Neon" else 0.0))
            lo, hi = bounds(ob)
            c = (lo + hi) / 2
            span = max(hi - lo)
            sc = 1.6 / span if span > 1.6 else 1.0
            ob.scale = (sc, sc, sc)
            ob.location = (-(c.x * sc) + (k % 7) * 2.3 - 6.9, -(c.y * sc), -(c.z * sc) + 4.6 - (k // 7) * 2.1)
            k += 1
    kit.camera((0, -19, 1.5), (0, 0, 1.45), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "foes.png"))
