# finales.py: the side quest finales that are not people (2026-11-18 art pass; nate's direction: creature bosses
# are cartoon creatures that burst into light, never blood; machines spark apart): the Bramblebeast (The Harvest
# King's crop creature: a pumpkin head with a glowing grin, bark and vines, a seed of light in its chest), the
# Voidhound (Starblood Calling's hunting machine from the stars: a hound's helm and snout, one ultraviolet eye,
# fins down the back and a tail) and the Wind-Up Giant (Wind-Up Lane's giant clockwork tin soldier: a painted tin
# face, a shako, a red coat with cross belts and a drum, the wind-up key in his back). Original designs only.
# The same pipeline as the remade Spark Trooper (trooper.py) and the bosses' bake (bosses.py):
# * 15 meshes named exactly as the R15 parts, each filling its part's box (the game sizes a mesh to its part, so
#   the joints stay where they are and every fight's animations fit), plus extras (the crown, the snout, the
#   shako, the key...) placed against an R15 part by src/config/FinaleArt.luau (generated here).
# * One 1024 px PBR texture set a finale (art/export/finales/<Name>_{Color,Normal,Roughness,Metalness}.png):
#   flat bold comic colours, baked occlusion in the creases, light edge wear. The colour map's alpha is 0 on the
#   "Tint" region (SurfaceAppearance AlphaMode Overlay), so the part colour shows there: the game paints it
#   FinaleArt.tint, and the hit flash still shows.
# * At most 12,000 triangles a finale (one is on screen at a time).
# The game (EnemyRenderer) uses ReplicatedStorage.Art.<Name> once nate imports art/export/finales/<Name>.fbx, and
# today's look (the creator look on the blocky rig, or the uniform) until then. PLACEHOLDER ART until nate
# approves the looks.
# Output: art/export/finales/<Name>.fbx (textures embedded), the PNGs, src/config/FinaleArt.luau and
# art/preview/finale_<Name>.png (front, a pose, the back; machines also damaged).
# Run: python art/blender/finales.py [--only <Name>] [--quick]   (with the `bpy` module, Blender 5.0; --quick:
# shapes and a flat preview only, no bake or export)
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

RES = 1024
OUT = os.path.join(kit.ROOT, "export", "finales")
os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
QUICK = "--quick" in sys.argv
BUDGET = 12000
ID_COLOURS = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (0, 1, 1), (1, 0, 1), (1, 1, 1), (0.5, 0.5, 0)]

# the blocky R15 body (Blender: x across, +y the front, z up; feet on z = 0), left side; the right mirrors it
BLOCKS = {
    "Head": (-0.6, 0.6, -0.6, 0.6, 4.0, 5.2),
    "UpperTorso": (-1.0, 1.0, -0.5, 0.5, 2.4, 4.0),
    "LowerTorso": (-1.0, 1.0, -0.5, 0.5, 2.0, 2.4),
    "LeftUpperArm": (-2.0, -1.0, -0.5, 0.5, 3.15, 4.0),
    "LeftLowerArm": (-2.0, -1.0, -0.5, 0.5, 2.3, 3.15),
    "LeftHand": (-2.0, -1.0, -0.5, 0.5, 2.0, 2.3),
    "LeftUpperLeg": (-1.0, 0.0, -0.5, 0.5, 1.15, 2.0),
    "LeftLowerLeg": (-1.0, 0.0, -0.5, 0.5, 0.3, 1.15),
    "LeftFoot": (-1.0, 0.0, -0.5, 0.5, 0.0, 0.3),
}
BLOCKS_ALL = dict(BLOCKS)
for _n in list(BLOCKS):
    if _n.startswith("Left"):
        x0, x1, y0, y1, z0, z1 = BLOCKS[_n]
        BLOCKS_ALL["Right" + _n[4:]] = (-x1, -x0, y0, y1, z0, z1)
PARTS = ["Head", "UpperTorso", "LowerTorso"] + [s + p for s in ("Left", "Right") for p in
                                                  ("UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot")]


# ---------------------------------------------------------------- one finale's paint regions and pieces
class Finale:
    """name, tint (the game's colour for the see-through region, sRGB), regions: {name: (albedo or None for the
    tint, roughness, metalness)}; build(f) makes the pieces; extras: {extra name: parent R15 part}."""

    def __init__(self, name, tint, regions, build, extras, machine):
        self.name, self.tint, self.regions, self.build, self.extras = name, tint, regions, build, extras
        self.machine = machine
        self.ids = {r: ID_COLOURS[i] for i, r in enumerate(regions)}
        self.pieces = {}
        self.mats = {}

    def mat(self, region):
        if region not in self.mats:
            m = bpy.data.materials.new(self.name + region)
            m.use_nodes = True
            nt = m.node_tree
            p = nt.nodes["Principled BSDF"]
            alb = self.regions[region][0] or self.tint
            p.inputs["Base Color"].default_value = (*(lin(c) for c in alb), 1)
            p.inputs["Roughness"].default_value = self.regions[region][1]
            p.inputs["Metallic"].default_value = self.regions[region][2]
            bev = nt.nodes.new("ShaderNodeBevel")
            bev.inputs["Radius"].default_value = 0.03
            bev.samples = 8
            tex = nt.nodes.new("ShaderNodeTexNoise")
            tex.inputs["Scale"].default_value = 40.0
            bump = nt.nodes.new("ShaderNodeBump")
            bump.inputs["Strength"].default_value = 0.08
            bump.inputs["Distance"].default_value = 0.02
            nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
            nt.links.new(bev.outputs["Normal"], bump.inputs["Normal"])
            nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
            self.mats[region] = m
        return self.mats[region]

    def paint(self, region, ob):
        ob.data.materials.clear()
        ob.data.materials.append(self.mat(region))
        return ob

    def finish(self, name, subs, fill=True):
        """Join sub-shapes into one piece; an R15 part is scaled to fill its box exactly."""
        ob = kit.join(name, subs, shade=False)
        if fill:
            x0, x1, y0, y1, z0, z1 = BLOCKS_ALL[name]
            vs = ob.data.vertices
            lo = Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
            hi = Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
            for v in vs:
                v.co.x = x0 + (v.co.x - lo.x) / (hi.x - lo.x) * (x1 - x0)
                v.co.y = y0 + (v.co.y - lo.y) / (hi.y - lo.y) * (y1 - y0)
                v.co.z = z0 + (v.co.z - lo.z) / (hi.z - lo.z) * (z1 - z0)
        kit.shade_auto(ob, 35)
        self.pieces[name] = ob
        return ob


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# ---------------------------------------------------------------- shape helpers (each returns a painted object)
def B(f, region, x0, x1, y0, y1, z0, z1, bev=0.05, segs=2):
    ob = kit.box("b", x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    if bev > 0:
        kit.bevel(ob, min(bev, (x1 - x0) * 0.45, (y1 - y0) * 0.45, (z1 - z0) * 0.45), segs)
        kit.apply_all(ob)
    return f.paint(region, ob)


def C(f, region, r1, r2, depth, at, axis="Z", segs=14):
    return f.paint(region, kit.cyl("c", r1, r2, depth, at=at, segs=segs, axis=axis))


def S(f, region, r, at, scale=(1, 1, 1), segs=14, rings=8):
    return f.paint(region, kit.sphere("s", r, at=at, scale=scale, segs=segs, rings=rings))


def L(f, region, rings, segs=18, power=2.4):
    return f.paint(region, kit.loft("l", rings, segs=segs, power=power))


def Tu(f, region, pts, radii, segs=8):
    return f.paint(region, kit.tube_along("t", [Vector(p) for p in pts], radii, segs=segs))


def spike(f, region, base, tip, r, segs=6):
    a, b = Vector(base), Vector(tip)
    d = b - a
    ob = kit.cyl("sp", r, 0.0, d.length, at=(0, 0, 0), segs=segs)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    ob.location = (a + b) / 2
    kit.apply_all(ob)
    return f.paint(region, ob)


def limb(f, name, region, r_top, r_bot, extra=()):
    """A rounded limb filling its block (a soft square tube), plus extra shapes."""
    x0, x1, y0, y1, z0, z1 = BLOCKS_ALL[name]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rings = [(z0, r_bot * 0.9, r_bot * 0.9, cx, cy), (z0 + 0.02, r_bot, r_bot, cx, cy),
             ((z0 + z1) / 2, (r_top + r_bot) / 2 * 1.04, (r_top + r_bot) / 2 * 1.04, cx, cy),
             (z1 - 0.02, r_top, r_top, cx, cy), (z1, r_top * 0.9, r_top * 0.9, cx, cy)]
    f.finish(name, [L(f, region, rings, 16, 2.8)] + list(extra))


def leaf(f, at, ang, size=0.22, tilt=0.4):
    ob = kit.sphere("lf", 1.0, at=(0, 0, 0), scale=(size * 0.45, size, size * 0.08), segs=8, rings=5)
    ob.rotation_euler = (tilt, 0, ang)
    ob.location = at
    kit.apply_all(ob)
    return f.paint("Leaf", ob)


# ---------------------------------------------------------------- the Bramblebeast
def bramblebeast(f):
    # the head: a ribbed pumpkin with a carved, glowing grin and eyes (friendly-scary, never gory)
    rings = []
    for z, r in ((4.0, 0.3), (4.05, 0.48), (4.18, 0.6), (4.45, 0.66), (4.75, 0.64), (5.0, 0.56), (5.15, 0.4),
                 (5.2, 0.15)):
        rings.append((z, r, r * 0.95, 0, 0))
    head = L(f, "Rind", rings, 32, 2.0)
    kit.deform(head, lambda v: Vector((v.x * (1 + 0.07 * math.cos(8 * math.atan2(v.y, v.x))),
                                       v.y * (1 + 0.07 * math.cos(8 * math.atan2(v.y, v.x))), v.z)))
    subs = [head]
    for s in (-1, 1):  # angry triangle eyes, a brow ridge of bark
        e = B(f, "Glow", s * 0.24 - 0.13, s * 0.24 + 0.13, 0.5, 0.66, 4.62, 4.8, 0.02)
        kit.deform(e, lambda v, s=s: Vector((v.x, v.y, v.z - (0.08 if v.x * s > 0.24 else 0) * (v.z - 4.62) / 0.18 * 2)))
        subs.append(e)
        subs.append(B(f, "Bark", s * 0.24 - 0.17, s * 0.24 + 0.17, 0.5, 0.68, 4.82, 4.9, 0.02))
    for k in range(7):  # the jagged grin
        x = -0.36 + k * 0.12
        up = 0.05 if k % 2 else 0.0
        subs.append(B(f, "Glow", x - 0.055, x + 0.055, 0.52, 0.66, 4.3 + up, 4.42 + up - abs(x) * 0.1, 0.01))
    subs.append(C(f, "Bark", 0.08, 0.06, 0.18, (0, 0, 5.25), segs=8))
    f.finish("Head", subs)
    # the crown: bramble antlers with leaves (an extra on the head)
    crown = []
    for s in (-1, 1):
        pts = [(s * 0.15, 0, 5.15), (s * 0.4, -0.05, 5.5), (s * 0.55, -0.1, 5.85), (s * 0.85, -0.05, 6.05)]
        crown.append(Tu(f, "Bark", pts, [0.09, 0.07, 0.05, 0.02]))
        crown.append(Tu(f, "Bark", [(s * 0.45, -0.07, 5.62), (s * 0.3, -0.05, 5.95), (s * 0.25, 0.0, 6.12)],
                        [0.05, 0.035, 0.015]))
        for k, (x, z) in enumerate(((0.55, 5.86), (0.86, 6.05), (0.27, 6.1), (0.4, 5.5))):
            crown.append(leaf(f, (s * x, -0.05, z), s * (0.6 + k * 0.5), 0.2))
    f.finish("BrambleCrown", crown, fill=False)
    # the torso: a barrel of bark (the tint), wrapped in vines, rind plates over the ribs and a seed of light
    rings = [(2.4, 0.86, 0.46, 0, 0), (2.7, 0.94, 0.5, 0, 0), (3.2, 1.0, 0.52, 0, 0.02), (3.7, 1.0, 0.5, 0, 0),
             (3.95, 0.86, 0.42, 0, 0), (4.0, 0.6, 0.3, 0, 0)]
    subs = [L(f, "Tint", rings, 24, 2.6)]
    for k, x in enumerate((-0.6, -0.3, 0.3, 0.6)):
        p = B(f, "Rind", x - 0.12, x + 0.12, 0.38, 0.58, 2.9, 3.85, 0.1, 3)
        kit.deform(p, lambda v, x=x: Vector((v.x, v.y - 0.25 * (v.x - x) ** 2 * 6, v.z)))
        subs.append(p)
    subs.append(S(f, "Glow", 0.22, (0, 0.5, 3.35), (1, 0.6, 1.2)))
    subs.append(S(f, "Dark", 0.3, (0, 0.44, 3.35), (1, 0.4, 1.25)))
    for k in range(3):  # vines spiralling round
        pts = [(math.cos(a) * 1.02, math.sin(a) * 0.54, 2.45 + (a - k * 2.1) * 0.22)
               for a in [k * 2.1 + t * 0.4 for t in range(9)]]
        subs.append(Tu(f, "Leaf", pts, [0.05] * len(pts), 6))
    f.finish("UpperTorso", subs)
    # the mane: a collar of leaves round the neck; the back: a bramble hump with thorns
    mane = []
    for k in range(14):
        a = k / 14 * math.pi * 2
        mane.append(leaf(f, (math.cos(a) * 0.62, math.sin(a) * 0.45, 4.02), a + math.pi / 2, 0.32, 1.2))
    f.finish("BrambleMane", mane, fill=False)
    back = [S(f, "Bark", 0.6, (0, -0.55, 3.45), (1.2, 0.55, 0.9), 16, 10)]
    for k in range(9):
        a = -0.9 + k * 0.225
        base = (math.sin(a) * 0.55, -0.75 - math.cos(a) * 0.05, 3.4 + math.cos(a * 2) * 0.25)
        back.append(spike(f, "Dark", base, (base[0] * 1.3, base[1] - 0.35, base[2] + 0.2), 0.07))
    for k in range(5):
        back.append(leaf(f, (-0.5 + k * 0.25, -0.85, 3.85), k, 0.22))
    f.finish("BrambleBack", back, fill=False)
    # the waist: bark with a woven vine belt
    lt = [L(f, "Tint", [(2.0, 0.8, 0.42, 0, 0), (2.2, 0.88, 0.46, 0, 0), (2.4, 0.86, 0.46, 0, 0)], 20, 2.6)]
    lt.append(f.paint("Leaf", kit.torus("belt", 0.9, 0.06, at=(0, 0, 2.25), segs=24, csegs=6)))
    kit.deform(lt[-1], lambda v: Vector((v.x, v.y * 0.53, v.z)))
    f.finish("LowerTorso", lt)
    # arms: bark, vines and leaf tufts; root-claw hands
    limb(f, "LeftUpperArm", "Tint", 0.52, 0.46, [leaf(f, (-1.5, 0.0, 3.95), 0.3, 0.3, 1.0),
                                                   leaf(f, (-1.9, -0.1, 3.8), 1.6, 0.26, 0.8)])
    ua = BLOCKS["LeftLowerArm"]
    vines = [Tu(f, "Leaf", [(-1.5 + math.cos(a) * 0.5, math.sin(a) * 0.5, ua[4] + 0.05 + a * 0.12) for a in
                            [t * 0.5 for t in range(13)]], [0.05] * 13, 6)]
    limb(f, "LeftLowerArm", "Bark", 0.46, 0.42, vines)
    h = [S(f, "Bark", 0.42, (-1.5, 0, 2.2), (1, 1, 0.5))]
    for k, (x, y) in enumerate(((-1.75, 0.15), (-1.5, 0.25), (-1.25, 0.15), (-1.5, -0.2))):
        h.append(spike(f, "Dark", (x, y, 2.2), (x * 1.0 + (x + 1.5) * 0.3, y * 1.5, 2.0), 0.08))
    f.finish("LeftHand", h)
    # legs: stumpy bark trunks with vine bands; root feet
    limb(f, "LeftUpperLeg", "Tint", 0.5, 0.46, [leaf(f, (-0.5, 0.45, 1.8), 0, 0.24, 1.4)])
    ll = BLOCKS["LeftLowerLeg"]
    limb(f, "LeftLowerLeg", "Bark", 0.46, 0.52,
         [f.paint("Leaf", kit.torus("band", 0.5, 0.05, at=(-0.5, 0, (ll[4] + ll[5]) / 2), segs=16, csegs=6))])
    ft = [S(f, "Bark", 0.5, (-0.5, 0.05, 0.12), (1.0, 1.0, 0.3))]
    for k, x in enumerate((-0.8, -0.5, -0.2)):
        ft.append(spike(f, "Bark", (x, 0.3, 0.1), (x + (x + 0.5) * 0.4, 0.55, 0.02), 0.1))
    f.finish("LeftFoot", ft)


# ---------------------------------------------------------------- the Voidhound
def voidhound(f):
    # the helm: an angular hound's head, a brow crest, one ultraviolet eye (the snout and ears are extras)
    subs = [B(f, "Tint", -0.56, 0.56, -0.58, 0.5, 4.02, 5.1, 0.14, 3)]
    subs.append(B(f, "Plate", -0.6, 0.6, -0.4, 0.58, 4.82, 5.2, 0.08))  # the brow crest
    kit.deform(subs[-1], lambda v: Vector((v.x, v.y, v.z + (0.1 if v.y > 0.3 else 0) * (1 - abs(v.x)))))
    subs.append(B(f, "Dark", -0.42, 0.42, 0.44, 0.6, 4.5, 4.78, 0.05))  # the visor slot
    subs.append(S(f, "Glow", 0.15, (0, 0.6, 4.64), (2.5, 0.45, 0.6)))  # one wide ultraviolet eye
    for s in (-1, 1):
        subs.append(B(f, "Metal", s * 0.56 - 0.05, s * 0.56 + 0.05, -0.3, 0.3, 4.2, 4.7, 0.02))  # cheek vents
    f.finish("Head", subs)
    snout = [B(f, "Plate", -0.32, 0.32, 0.4, 1.35, 4.12, 4.5, 0.08)]
    kit.deform(snout[0], lambda v: Vector((v.x * (1 - (v.y - 0.4) * 0.35), v.y, v.z - (v.y - 0.4) * 0.08)))
    snout.append(B(f, "Metal", -0.28, 0.28, 0.42, 1.25, 4.0, 4.14, 0.04))  # the jaw
    for k in range(5):
        x = -0.2 + k * 0.1
        snout.append(spike(f, "Metal", (x, 1.18, 4.14), (x, 1.2, 4.04), 0.035, 4))
    snout.append(S(f, "Dark", 0.06, (0, 1.3, 4.42), (1.6, 0.6, 0.8)))  # the nose
    f.finish("HoundSnout", snout, fill=False)
    ears = []
    for s in (-1, 1):
        e = B(f, "Plate", s * 0.42 - 0.1, s * 0.42 + 0.1, -0.3, 0.1, 5.0, 5.7, 0.04)
        kit.deform(e, lambda v: Vector((v.x, v.y - (v.z - 5.0) * 0.55, v.z)))
        ears += [e, spike(f, "Glow", (s * 0.42, -0.36, 5.66), (s * 0.44, -0.55, 5.9), 0.05)]
    f.finish("HoundEars", ears, fill=False)
    # the chest: plates over the shell, ribs and a glowing diamond core
    subs = [L(f, "Tint", [(2.4, 0.8, 0.42, 0, 0), (2.9, 0.9, 0.46, 0, 0), (3.5, 1.0, 0.5, 0, 0.02),
                          (3.95, 0.96, 0.46, 0, 0), (4.0, 0.6, 0.3, 0, 0)], 20, 3.2)]
    for s in (-1, 1):
        p = B(f, "Plate", s * 0.5 - 0.45, s * 0.5 + 0.45, 0.3, 0.56, 3.35, 3.95, 0.06)
        kit.deform(p, lambda v, s=s: Vector((v.x, v.y, v.z - 0.15 * max(0.0, s * v.x - 0.2))))
        subs.append(p)
        for k in range(3):
            subs.append(B(f, "Metal", s * 0.55 - 0.3, s * 0.55 + 0.3, 0.36, 0.52, 2.65 + k * 0.2, 2.75 + k * 0.2, 0.03))
    core = B(f, "Glow", -0.16, 0.16, 0.5, 0.62, 3.0, 3.32, 0.02)
    kit.deform(core, lambda v: Vector((v.x * (1 - abs(v.z - 3.16) * 4), v.y, v.z)))
    subs.append(core)
    f.finish("UpperTorso", subs)
    spines = []
    for k in range(5):
        z = 3.9 - k * 0.32
        fin = B(f, "Plate", -0.05, 0.05, -0.5, -0.1, z - 0.12, z + 0.1, 0.02)
        kit.deform(fin, lambda v, z=z: Vector((v.x, v.y - (z + 0.1 - v.z) * 1.2 * (0.8 - k * 0.1), v.z)))
        spines += [fin, spike(f, "Glow", (0, -0.62 - (0.8 - k * 0.1) * 0.25, z + 0.05), (0, -0.8 - k * 0.02, z + 0.1), 0.03, 4)]
    f.finish("HoundSpines", spines, fill=False)
    f.finish("LowerTorso", [B(f, "Tint", -0.9, 0.9, -0.46, 0.46, 2.0, 2.4, 0.08),
                            B(f, "Metal", -0.95, 0.95, -0.5, 0.5, 2.24, 2.34, 0.03),
                            B(f, "Glow", -0.1, 0.1, 0.48, 0.54, 2.25, 2.33, 0.01)])
    pts = [(0, -0.45, 2.2), (0, -0.85, 2.05), (0, -1.25, 1.75), (0, -1.5, 1.35), (0, -1.62, 0.95)]
    tail = [Tu(f, "Plate", pts, [0.16, 0.14, 0.11, 0.08, 0.04], 8)]
    for k in range(1, 4):
        tail.append(f.paint("Glow", kit.torus("tr", 0.13 - k * 0.025, 0.02, at=pts[k], segs=10, csegs=4)))
    f.finish("HoundTail", tail, fill=False)
    # arms: plated, glowing seams; talon hands
    limb(f, "LeftUpperArm", "Tint", 0.5, 0.42, [B(f, "Plate", -2.06, -0.96, -0.52, 0.52, 3.7, 4.05, 0.08),
                                                  B(f, "Glow", -2.03, -1.97, -0.2, 0.2, 3.3, 3.6, 0.01)])
    limb(f, "LeftLowerArm", "Plate", 0.44, 0.38, [B(f, "Metal", -1.75, -1.25, 0.36, 0.48, 2.5, 3.0, 0.03)])
    h = [B(f, "Metal", -1.85, -1.15, -0.3, 0.3, 2.15, 2.3, 0.05)]
    for x in (-1.75, -1.5, -1.25):
        h.append(spike(f, "Dark", (x, 0.15, 2.18), (x, 0.42, 1.96), 0.07, 5))
    f.finish("LeftHand", h)
    # legs: thigh plates, a backward knee spur, clawed paws
    limb(f, "LeftUpperLeg", "Tint", 0.48, 0.42, [B(f, "Plate", -0.95, -0.05, 0.3, 0.52, 1.3, 1.95, 0.06)])
    limb(f, "LeftLowerLeg", "Plate", 0.42, 0.36, [spike(f, "Metal", (-0.5, -0.4, 1.05), (-0.5, -0.75, 1.2), 0.1),
                                                   B(f, "Glow", -0.53, -0.47, 0.4, 0.46, 0.4, 0.95, 0.01)])
    ft = [B(f, "Metal", -0.9, -0.1, -0.4, 0.45, 0.0, 0.3, 0.08)]
    for x in (-0.75, -0.5, -0.25):
        ft.append(spike(f, "Dark", (x, 0.35, 0.12), (x, 0.62, 0.0), 0.07, 5))
    f.finish("LeftFoot", ft)


# ---------------------------------------------------------------- the Wind-Up Giant
def windup_giant(f):
    # the head: a round tin head, a painted face (dot eyes, rosy cheeks, a black moustache), the chin strap
    rings = [(4.0, 0.42, 0.42, 0, 0), (4.05, 0.52, 0.52, 0, 0), (4.2, 0.58, 0.58, 0, 0), (4.9, 0.58, 0.58, 0, 0),
             (5.1, 0.5, 0.5, 0, 0), (5.2, 0.3, 0.3, 0, 0)]
    subs = [L(f, "Face", rings, 28, 2.2)]
    for s in (-1, 1):
        subs.append(S(f, "Black", 0.075, (s * 0.2, 0.56, 4.68), (1, 0.4, 1.2), 10, 6))
        subs.append(S(f, "Cheek", 0.11, (s * 0.33, 0.52, 4.42), (1, 0.3, 0.8), 10, 6))
        m = S(f, "Black", 0.16, (s * 0.15, 0.58, 4.38), (1.2, 0.35, 0.4), 10, 6)
        kit.deform(m, lambda v, s=s: Vector((v.x, v.y, v.z + 0.12 * (v.x * s - 0.1) ** 2 * 6)))
        subs.append(m)
    subs.append(S(f, "Cheek", 0.07, (0, 0.6, 4.52), (1, 0.6, 1), 10, 6))  # the nose
    subs.append(f.paint("Gold", kit.torus("strap", 0.59, 0.03, at=(0, 0.05, 4.3), segs=24, csegs=4)))
    kit.deform(subs[-1], lambda v: Vector((v.x, v.y, v.z + (0.35 if v.y < 0 else 0) * abs(v.y))))
    f.finish("Head", subs)
    # the shako: a tall black hat, a gold band and plate, a red and white plume
    shako = [C(f, "Black", 0.55, 0.62, 0.95, (0, 0, 5.62), segs=24),
             C(f, "Gold", 0.565, 0.57, 0.1, (0, 0, 5.22), segs=24),
             C(f, "Gold", 0.635, 0.64, 0.06, (0, 0, 6.08), segs=24),
             B(f, "Black", -0.4, 0.4, 0.25, 0.75, 5.1, 5.16, 0.03),  # the peak
             B(f, "Gold", -0.16, 0.16, 0.6, 0.66, 5.45, 5.8, 0.02)]
    shako.append(S(f, "White", 0.16, (0, 0.3, 6.25), (1, 1, 1.6), 12, 8))
    shako.append(S(f, "Tint", 0.12, (0, 0.3, 6.5), (1, 1, 1.6), 12, 8))
    f.finish("GiantShako", shako, fill=False)
    # the coat: a red barrel (the tint) with white cross belts, two columns of gold buttons, epaulettes, the drum
    rings = [(2.4, 0.86, 0.44, 0, 0), (2.8, 0.96, 0.5, 0, 0), (3.6, 1.0, 0.52, 0, 0), (3.9, 0.94, 0.5, 0, 0),
             (4.0, 0.55, 0.32, 0, 0)]
    subs = [L(f, "Tint", rings, 24, 2.4)]
    for s in (-1, 1):
        belt = B(f, "White", -0.08, 0.08, 0.44, 0.58, 2.45, 4.0, 0.02)
        kit.deform(belt, lambda v, s=s: Vector((v.x + s * (v.z - 3.2) * 0.85, v.y, v.z)))
        subs.append(belt)
        for k in range(5):
            subs.append(S(f, "Gold", 0.055, (s * 0.42, 0.52, 2.65 + k * 0.28), (1, 0.5, 1), 8, 5))
        ep = C(f, "Gold", 0.32, 0.36, 0.1, (s * 0.85, 0, 3.98), segs=16)
        subs.append(ep)
        for k in range(6):
            a = k / 6 * math.pi
            subs.append(C(f, "Gold", 0.025, 0.025, 0.14, (s * 0.85 + math.cos(a) * 0.32 * s, -math.sin(a) * 0.2 + 0.05,
                                                            3.88), segs=5))
    subs.append(C(f, "White", 0.2, 0.2, 0.14, (0, 0.55, 2.62), axis="Y", segs=18))  # the drum
    subs.append(f.paint("Tint", kit.torus("rim", 0.2, 0.025, at=(0, 0.62, 2.62), segs=18, csegs=4, axis="Y")))
    f.finish("UpperTorso", subs)
    key = [C(f, "Gold", 0.07, 0.07, 0.5, (0, -0.75, 3.3), axis="Y", segs=10),
           C(f, "Gold", 0.18, 0.18, 0.06, (0, -0.52, 3.3), axis="Y", segs=16)]
    for s in (-1, 1):
        bow = f.paint("Gold", kit.torus("bow", 0.22, 0.06, at=(s * 0.28, -1.0, 3.3), segs=16, csegs=6, axis="Y"))
        key.append(bow)
    key.append(B(f, "Gold", -0.1, 0.1, -1.06, -0.94, 3.22, 3.38, 0.02))
    f.finish("GiantKey", key, fill=False)
    f.finish("LowerTorso", [B(f, "Black", -0.92, 0.92, -0.48, 0.48, 2.0, 2.4, 0.06),
                            B(f, "Gold", -0.16, 0.16, 0.44, 0.52, 2.08, 2.32, 0.03),
                            B(f, "Tint", -0.08, 0.08, 0.5, 0.54, 2.13, 2.27, 0.01)])
    # arms: red sleeves, gold cuffs, white mitten hands
    limb(f, "LeftUpperArm", "Tint", 0.48, 0.44)
    la = BLOCKS["LeftLowerArm"]
    limb(f, "LeftLowerArm", "Tint", 0.44, 0.42, [C(f, "Gold", 0.47, 0.47, 0.18, (-1.5, 0, la[4] + 0.12), segs=18)])
    f.finish("LeftHand", [S(f, "White", 0.42, (-1.5, 0, 2.15), (1, 1, 0.55), 16, 8),
                          S(f, "White", 0.14, (-1.12, 0.15, 2.18), (0.8, 1, 1), 8, 6)])
    # legs: white trousers with a red stripe, tall black boots with a gold band
    limb(f, "LeftUpperLeg", "White", 0.46, 0.44, [B(f, "Tint", -1.02, -0.94, -0.12, 0.12, 1.15, 2.0, 0.01)])
    ll = BLOCKS["LeftLowerLeg"]
    limb(f, "LeftLowerLeg", "Black", 0.48, 0.44, [C(f, "Gold", 0.5, 0.5, 0.08, (-0.5, 0, ll[5] - 0.08), segs=18)])
    f.finish("LeftFoot", [B(f, "Black", -0.92, -0.08, -0.42, 0.5, 0.0, 0.3, 0.1),
                          B(f, "Tin", -0.92, -0.08, -0.42, 0.5, 0.0, 0.05, 0.02)])


FINALES = [
    Finale("Bramblebeast", (60, 130, 60),
           {"Tint": (None, 0.8, 0.0), "Rind": ((240, 140, 40), 0.55, 0.0), "Bark": ((104, 74, 46), 0.85, 0.0),
            "Leaf": ((96, 176, 64), 0.6, 0.0), "Glow": ((255, 232, 120), 0.3, 0.0), "Dark": ((44, 34, 26), 0.8, 0.0)},
           bramblebeast, {"BrambleCrown": "Head", "BrambleMane": "UpperTorso", "BrambleBack": "UpperTorso"}, False),
    Finale("Voidhound", (44, 48, 72),
           {"Tint": (None, 0.45, 0.3), "Plate": ((74, 66, 120), 0.4, 0.4), "Metal": ((150, 156, 172), 0.3, 1.0),
            "Glow": ((200, 110, 255), 0.2, 0.0), "Dark": ((20, 20, 28), 0.5, 0.3)},
           voidhound, {"HoundSnout": "Head", "HoundEars": "Head", "HoundSpines": "UpperTorso",
                       "HoundTail": "LowerTorso"}, True),
    Finale("WindupGiant", (190, 35, 45),
           {"Tint": (None, 0.45, 0.0), "Gold": ((232, 186, 72), 0.3, 0.8), "White": ((238, 238, 240), 0.5, 0.0),
            "Black": ((26, 26, 30), 0.35, 0.0), "Tin": ((176, 182, 194), 0.3, 1.0), "Face": ((246, 214, 186), 0.45, 0.0),
            "Cheek": ((236, 120, 120), 0.45, 0.0)},
           windup_giant, {"GiantShako": "Head", "GiantKey": "UpperTorso"}, True),
]


# ---------------------------------------------------------------- bake, export, config and preview
def rbx(v):
    return (v[0], v[2], -v[1])


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def make(f):
    kit.reset()
    f.build(f)
    # the right side mirrors the left
    for name in list(f.pieces):
        if name.startswith("Left"):
            right = "Right" + name[4:]
            ob = kit.mirror_x(f.pieces[name], right)
            ob.data.name = right
            f.pieces[right] = ob
    names = PARTS + list(f.extras)
    for n in names:
        assert n in f.pieces, (f.name, n)
    total = sum(kit.tris(f.pieces[n]) for n in names)
    print(f.name, "triangles", total)
    assert total <= BUDGET, "%s is over the finale budget" % f.name
    # the extras against their R15 part's box (fractions of that part, Roblox axes)
    extras = {}
    for name, parent in f.extras.items():
        lo, hi = bounds(f.pieces[name])
        x0, x1, y0, y1, z0, z1 = BLOCKS_ALL[parent]
        bs = Vector((x1 - x0, y1 - y0, z1 - z0))
        bc = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        c = (lo + hi) / 2
        off = Vector(((c.x - bc.x) / bs.x, (c.y - bc.y) / bs.y, (c.z - bc.z) / bs.z))
        size = Vector(((hi.x - lo.x) / bs.x, (hi.y - lo.y) / bs.y, (hi.z - lo.z) / bs.z))
        extras[name] = {"parent": parent, "offset": [round(x, 3) for x in rbx(off)],
                        "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)]}
    row = {"tint": list(f.tint), "triangles": total, "machine": f.machine, "extras": extras}
    objs = [f.pieces[n] for n in names]
    color_img = None
    if not QUICK:
        color_img = bake(f, objs)
        export(f, names, color_img)
    preview(f, names, color_img)
    return row


def bake(f, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 6
    scene.render.bake.use_clear = True
    scene.world = scene.world or bpy.data.worlds.new("W")

    def image(name):
        img = bpy.data.images.new(name, RES, RES, alpha=False, float_buffer=False)
        img.colorspace_settings.name = "Non-Color"
        return img

    def set_target(img):
        for m in f.mats.values():
            nt = m.node_tree
            node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
            node.name = "BakeTarget"
            node.image = img
            nt.nodes.active = node

    def emit_bake(img, fn):
        saved = {}
        for region, m in f.mats.items():
            nt = m.node_tree
            out = nt.nodes["Material Output"]
            saved[region] = out.inputs["Surface"].links[0].from_socket
            em = nt.nodes.new("ShaderNodeEmission")
            em.name = "TmpEmit"
            fn(region, nt, em)
            nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        scene.cycles.samples = 1
        set_target(img)
        bpy.ops.object.bake(type="EMIT")
        for region, m in f.mats.items():
            nt = m.node_tree
            nt.links.new(saved[region], nt.nodes["Material Output"].inputs["Surface"])
            nt.nodes.remove(nt.nodes["TmpEmit"])

    ids = image("ids")
    emit_bake(ids, lambda r, nt, em: em.inputs["Color"].__setattr__("default_value", (*f.ids[r], 1)))
    edges = image("edges")

    def edge(r, nt, em):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        nt.links.new(geo.outputs["Pointiness"], em.inputs["Color"])
    emit_bake(edges, edge)
    ao = image("ao")
    scene.cycles.samples = 48
    set_target(ao)
    bpy.ops.object.bake(type="AO")
    normal = image("normal")
    scene.cycles.samples = 8
    set_target(normal)
    bpy.ops.object.bake(type="NORMAL")

    def px(img):
        return np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)
    I, A, E, N = px(ids), px(ao)[..., 0], px(edges)[..., 0], px(normal)
    rng = np.random.default_rng(11)

    def blur_noise(scale):
        n = rng.random((RES // scale + 2, RES // scale + 2)).astype(np.float32)
        n = np.kron(n, np.ones((scale, scale), dtype=np.float32))[:RES, :RES]
        k = np.ones(scale) / scale
        n = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 0, n)
        return np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, n)
    mottle = blur_noise(16) * 0.6 + blur_noise(4) * 0.4
    region = np.full((RES, RES), -1, dtype=np.int32)
    order = list(f.regions)
    for k, r in enumerate(order):
        d = np.abs(I[..., :3] - np.array(f.ids[r], dtype=np.float32)).sum(axis=2)
        region[d < 0.3] = k
    edge_k = np.clip((E - 0.5) * 6.0, 0, 1)
    occl = np.clip(A, 0, 1)
    col = np.zeros((RES, RES, 4), dtype=np.float32)
    rough = np.zeros((RES, RES), dtype=np.float32)
    metal = np.zeros((RES, RES), dtype=np.float32)
    for k, r in enumerate(order):
        m = region == k
        alb, ro, mt = f.regions[r]
        if alb is None:
            col[m, :3] = (0.02, 0.02, 0.03)
            col[m, 3] = np.clip((1 - occl[m]) * 0.7 + (mottle[m] - 0.5) * 0.12, 0, 0.75)
        else:
            base = np.array([lin(c) for c in alb], dtype=np.float32)
            shade_ = (0.45 + 0.55 * occl[m])[:, None]
            grime = (1 - 0.1 * mottle[m])[:, None]
            wear = edge_k[m][:, None] * (0.05 if r == "Glow" else 0.22)
            col[m, :3] = np.clip(base * shade_ * grime + wear * (1 - base * 0.5), 0, 1)
            if r == "Glow":
                col[m, :3] = base  # lamps stay bright: no shading
            col[m, 3] = 1
        rough[m] = np.clip(ro + (mottle[m] - 0.5) * 0.12 - edge_k[m] * 0.1, 0.04, 1)
        metal[m] = mt
    col[region < 0] = (0.02, 0.02, 0.03, 0.2)
    rough[region < 0] = 0.6

    def save(name, arr, data):
        img = bpy.data.images.new(name, RES, RES, alpha=True)
        if data:
            img.colorspace_settings.name = "Non-Color"
        if arr.ndim == 2:
            arr = np.dstack([arr, arr, arr, np.ones_like(arr)])
        img.pixels[:] = arr.reshape(-1)
        img.filepath_raw = os.path.join(OUT, name + ".png")
        img.file_format = "PNG"
        img.save()
        return img
    # (the colour map is in linear values: save it as sRGB so the game's view matches)
    srgb = col.copy()
    srgb[..., :3] = np.where(col[..., :3] <= 0.0031308, col[..., :3] * 12.92,
                             1.055 * np.power(np.clip(col[..., :3], 1e-6, 1), 1 / 2.4) - 0.055)
    color_img = save(f.name + "_Color", srgb, True)
    color_img.colorspace_settings.name = "sRGB"
    f.maps = {"Color": color_img, "Normal": save(f.name + "_Normal", N, True),
              "Roughness": save(f.name + "_Roughness", rough, True), "Metalness": save(f.name + "_Metalness", metal, True)}
    return color_img


def out_material(f):
    m = bpy.data.materials.new(f.name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex(img, data):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        if data:
            img.colorspace_settings.name = "Non-Color"
        return n
    tc = tex(f.maps["Color"], False)
    nt.links.new(tc.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(tc.outputs["Alpha"], p.inputs["Alpha"])
    nt.links.new(tex(f.maps["Roughness"], True).outputs["Color"], p.inputs["Roughness"])
    nt.links.new(tex(f.maps["Metalness"], True).outputs["Color"], p.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex(f.maps["Normal"], True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return m


def export(f, names, color_img):
    m = out_material(f)
    f.out_mat = m
    out = []
    for name in names:
        ob = f.pieces[name]
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        kit.centre(cp)
        cp.name = name
        cp.data.name = name
        cp.data.materials.clear()
        cp.data.materials.append(m)
        out.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in out:
        o.select_set(True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, f.name + ".fbx"), use_selection=True,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
                             use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
                             path_mode="COPY", embed_textures=True)
    for cp in out:
        bpy.data.objects.remove(cp, do_unlink=True)


def preview(f, names, color_img):
    """Front, a fighting pose, the back (and for a machine, a damaged one) under the studio lights."""
    J = {"Waist": Vector((0, 0, 2.4)), "Neck": Vector((0, 0, 4.0)), "LeftShoulder": Vector((-1.0, 0, 3.76)),
         "LeftElbow": Vector((-1.5, 0, 3.15)), "LeftWrist": Vector((-1.5, 0, 2.3)), "LeftHip": Vector((-0.5, 0, 2.0)),
         "LeftKnee": Vector((-0.5, 0, 1.15)), "LeftAnkle": Vector((-0.5, 0, 0.3))}
    for k in list(J):
        if k.startswith("Left"):
            v = J[k]
            J["Right" + k[4:]] = Vector((-v.x, v.y, v.z))
    PARENT = {"UpperTorso": ("LowerTorso", "Waist"), "Head": ("UpperTorso", "Neck")}
    for s in ("Left", "Right"):
        PARENT[s + "UpperArm"] = ("UpperTorso", s + "Shoulder")
        PARENT[s + "LowerArm"] = (s + "UpperArm", s + "Elbow")
        PARENT[s + "Hand"] = (s + "LowerArm", s + "Wrist")
        PARENT[s + "UpperLeg"] = ("LowerTorso", s + "Hip")
        PARENT[s + "LowerLeg"] = (s + "UpperLeg", s + "Knee")
        PARENT[s + "Foot"] = (s + "LowerLeg", s + "Ankle")
    for x, parent in f.extras.items():
        PARENT[x] = (parent, None)
    if color_img is not None:
        mat = out_material(f) if not hasattr(f, "out_mat") else f.out_mat
        m = mat.copy()
        t = m.node_tree
        pr = t.nodes["Principled BSDF"]
        img = [n for n in t.nodes if n.type == "TEX_IMAGE" and n.image == f.maps["Color"]][0]
        mix = t.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        ins = [i for i in mix.inputs if i.type == "RGBA"]
        res = [o for o in mix.outputs if o.type == "RGBA"][0]
        ins[0].default_value = (*(lin(c) for c in f.tint), 1)
        t.links.new(img.outputs["Alpha"], mix.inputs[0])
        t.links.new(img.outputs["Color"], ins[1])
        t.links.new(res, pr.inputs["Base Color"])
        for link in list(pr.inputs["Alpha"].links):
            t.links.remove(link)
        pr.inputs["Alpha"].default_value = 1
        game = m
    else:
        game = None
    endo = kit.material("endo", (150, 155, 168), metal=1.0, rough=0.3)

    def pose_copy(at, bends, yaw=0.0, hide=()):
        world = {}

        def matrix(n):
            if n in world:
                return world[n]
            if n not in PARENT:
                world[n] = Matrix.Identity(4)
                return world[n]
            par, jn = PARENT[n]
            mm = matrix(par)
            if jn and jn in bends:
                axis, deg = bends[jn]
                pt = J[jn]
                mm = mm @ Matrix.Translation(pt) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-pt)
            world[n] = mm
            return mm
        Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        for n in names:
            if n in hide or (n in f.extras and f.extras[n] in hide):
                if n in BLOCKS_ALL:
                    x0, x1, y0, y1, z0, z1 = BLOCKS_ALL[n]
                    r = min(x1 - x0, y1 - y0) * 0.2
                    e = kit.cyl("endo", r, r * 0.85, (z1 - z0) * 0.94, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), segs=12)
                    e.data.materials.append(endo)
                    e.matrix_world = Y @ matrix(n)
                continue
            src = f.pieces[n]
            cp = src.copy()
            cp.data = src.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            cp.matrix_world = Y @ matrix(n)
            if game is not None:
                cp.data.materials.clear()
                cp.data.materials.append(game)
            cp.hide_render = False
    for ob in f.pieces.values():
        ob.hide_render = True
    kit.studio(res=(1800, 1000), samples=48)
    fight = {"LeftShoulder": ("X", 60), "RightShoulder": ("X", -30), "LeftElbow": ("X", 40), "LeftHip": ("X", 20),
             "LeftKnee": ("X", -30), "RightHip": ("X", -15)}
    if f.machine:
        pose_copy((7.6, 0, 0), {})
        pose_copy((2.6, 0, 0), fight, yaw=35)
        pose_copy((-2.6, 0, 0), {}, yaw=180)
        pose_copy((-7.6, 0, 0), {"Neck": ("Z", -12)}, yaw=-20,
                  hide=("LeftUpperArm", "LeftLowerArm", "LeftHand", "RightLowerLeg", "RightFoot"))
        kit.camera((0, 25.0, 5.4), (0, 0, 2.9), lens=40)
    else:
        pose_copy((5.2, 0, 0), {})
        pose_copy((0, 0, 0), fight, yaw=35)
        pose_copy((-5.2, 0, 0), {}, yaw=180)
        kit.camera((0, 21.0, 5.0), (0, 0, 2.9), lens=40)
    floor = kit.cyl("floor", 16, 16, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.render(os.path.join(kit.ROOT, "preview", "finale_%s.png" % f.name))


def write_config(rows):
    def v(t):
        return "{ %s }" % ", ".join("%.3f" % x if isinstance(x, float) else str(x) for x in t)
    lines = ["-- GENERATED by art/blender/finales.py: do not edit by hand.",
             "-- The side quest finales that are not people (ReplicatedStorage.Art.<Name> once nate imports",
             "-- art/export/finales/<Name>.fbx; EnemyRenderer uses the model then, today's look until then; PLACEHOLDER ART",
             "-- until nate approves): its 15 R15 meshes fill their parts' boxes; `tint` is the colour the see-through",
             "-- part of the colour map shows; the extras sit against an R15 part, as fractions of that part's size",
             "-- (x, up, depth; offset of centres). Keyed by the finale's Config.Enemies kind or Config.SideQuests dress.",
             "return {"]
    for name in sorted(rows):
        r = rows[name]
        lines.append("\t%s = {" % name)
        lines.append("\t\ttint = %s," % v(r["tint"]))
        lines.append("\t\ttriangles = %d," % r["triangles"])
        lines.append("\t\tmachine = %s," % ("true" if r["machine"] else "false"))
        lines.append("\t\textras = {")
        for x in sorted(r["extras"]):
            e = r["extras"][x]
            lines.append("\t\t\t%s = { parent = \"%s\", offset = %s, size = %s }," % (
                x, e["parent"], v([float(a) for a in e["offset"]]), v([float(a) for a in e["size"]])))
        lines.append("\t\t},")
        lines.append("\t},")
    lines += ["}", ""]
    path = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "FinaleArt.luau"))
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote", path)


if __name__ == "__main__":
    store = os.path.join(OUT, "finales.json")
    rows = json.load(open(store)) if os.path.exists(store) else {}
    for f in FINALES:
        if ONLY and f.name != ONLY:
            continue
        rows[f.name] = make(f)
    if not QUICK:
        with open(store, "w") as fh:
            json.dump(rows, fh, indent=1)
        write_config(rows)
