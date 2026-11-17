# bosses.py: the remade world bosses (overhaul plan step 4, the bosses part), the same pipeline as the remade
# Spark Trooper (trooper.py): meshes plus one baked PBR texture set per boss, exported as FBX, with a generated
# fit table the game places them from.
# PLACEHOLDER LOOK: boss lore pending (nate, 2026-11-17: world and event bosses stand apart from the main story
# and their lore is not decided). So these are generic, big, readable cartoon comic-book machines (original
# designs, machines only) in a neutral grey and steel scheme with industrial hazard stripes: no faction emblems,
# no text, no story looks. The shapes only follow each fight: a tall walker with shoulder cannons
# (RustjawPrime), a four-legged beast in a pit with three crystals and generators (LumenMaw), a serpent-shaped
# sea machine with two bays on its back (LeviathanEngine), and a mech with a back reactor and shoulder cannons
# (NullWarFrame, the mission 6 fight). The ids are Config.Boss's, not names for the looks.
# * Each boss is a few meshes by role (src/config/BossArt.luau, generated here):
#     hull           the textured body (never moves; the game pivots the whole model)
#     shed2 / shed3  textured armour plates that break off at phase 2 (66%) and phase 3 (33%)
#     glow           emissive accents (eyes, vents, lights): Neon in game, coloured by phase
#     weak           the weak points (Config.Boss targets with weak = true): Neon, one shared pulsing gold on every
#                    boss so "hit the gold" reads the same everywhere; each lamp sits inside its hit sphere
#     objective      the objective's body (a shoulder cannon, a torpedo bay, a shard generator), placed by the game
#                    at each Config.Boss objective; objectiveGlow its lamp (red; it goes dark when broken)
# * Hit boxes are Config.Boss's target spheres and do not change; only the look does.
# * One 1024 px texture set per boss (art/export/bosses/<Boss>_{Color,Normal,Roughness,Metalness}.png): flat bold
#   comic colours, dark ink in the creases, light edge wear, soft baked occlusion with a faint halftone in the
#   shadows. Lamps have no texture.
# * Budget (phone-friendly): at most 16,000 triangles a boss and 10,000 a mesh (Roblox allows 20,000); only one
#   boss is ever on screen.
# Output: art/export/Bosses.fbx (every boss, meshes named "<Boss>_<Piece>"; textures embedded), the PNGs,
# src/config/BossArt.luau and, with --preview, art/preview/bosses.png plus art/preview/boss_<Boss>.png.
# Run: python art/blender/bosses.py [--preview] [--only <Boss>]   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

RES = 1024
OUT = os.path.join(kit.ROOT, "export", "bosses")
os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
BUDGET, MESH_BUDGET = 16000, 10000

# ---------------------------------------------------------------- shared paint regions (the bake's id colours);
# each boss gives them its own colours, roughness and metalness below
REGION_IDS = {
    "Paint": (1, 0, 0),
    "Paint2": (0, 1, 0),
    "Metal": (0, 0, 1),
    "Dark": (1, 1, 0),
    "Hazard": (0, 1, 1),
    "Accent": (1, 0, 1),
}
ORDER = list(REGION_IDS)
GRAIN = {"Paint": (0.6, 0.05), "Paint2": (0.6, 0.05), "Metal": (1.4, 0.12), "Dark": (2.0, 0.1), "Hazard": (0.6, 0.04),
         "Accent": (0.6, 0.05)}


def make_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*REGION_IDS[name], 1)
    # surface detail for the normal bake: rounded edges (Bevel) and a fine grain (object space, in studs)
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.inputs["Radius"].default_value = 0.22
    bev.samples = 8
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = GRAIN[name][0]
    nt.links.new(tc.outputs["Object"], tex.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = GRAIN[name][1]
    bump.inputs["Distance"].default_value = 0.2
    nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bev.outputs["Normal"], bump.inputs["Normal"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return m


MATS = {n: make_mat(n) for n in ORDER}
LAMP = kit.material("Lamp", (255, 255, 255), rough=0.3)  # glow and weak pieces: Neon in game, no texture

# ---------------------------------------------------------------- building blocks (Blender: x across, +y the boss's
# front, z up; studs, feet at z = 0. The FBX export turns +y into Roblox -z, the way the boss faces)


def piece(region, ob):
    ob.data.materials.clear()
    ob.data.materials.append(LAMP if region == "Lamp" else MATS[region])
    return ob


def bx(region, x0, x1, y0, y1, z0, z1, bev=0.6, segs=1, taper=None):
    """A bevelled box between bounds. taper=(top_x, top_y): scale the top face about its centre."""
    ob = kit.box("b", x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    if taper:
        cx, cy_, zc = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
        for v in ob.data.vertices:
            if v.co.z > zc:
                v.co.x = cx + (v.co.x - cx) * taper[0]
                v.co.y = cy_ + (v.co.y - cy_) * taper[1]
    if bev > 0:
        kit.bevel(ob, bev, segs)
        kit.apply_all(ob)
    return piece(region, ob)


def cy(region, r1, r2, depth, at, axis="Z", segs=12):
    return piece(region, kit.cyl("c", r1, r2, depth, at=at, segs=segs, axis=axis))


def ball(region, r, at, scale=(1, 1, 1), segs=14, rings=8):
    return piece(region, kit.sphere("s", r, at=at, scale=scale, segs=segs, rings=rings))


def ring(region, major, minor, at, axis="Z", segs=18, csegs=6):
    return piece(region, kit.torus("t", major, minor, at=at, segs=segs, csegs=csegs, axis=axis))


def loft(region, rings, segs=20, power=2.6):
    """rings: (z, rx, ry, cx, cy) bottom to top."""
    return piece(region, kit.loft("l", rings, segs=segs, power=power))


def loft_y(region, rings, segs=20, power=2.6):
    """A loft along +y (back to front). rings: (y, rx, rz, cx, cz)."""
    ob = kit.loft("ly", [(-y, rx, rz, cx, cz) for y, rx, rz, cx, cz in rings], segs=segs, power=power)
    ob.data.transform(Matrix.Rotation(math.radians(90), 4, "X"))
    return piece(region, ob)


def tube(region, pts, radii, segs=10):
    return piece(region, kit.tube_along("tb", [Vector(p) for p in pts], radii, segs=segs))


def beam(region, a, b, w, d, bev=0.5, segs=1, taper=1.0):
    """A box from point a to point b (w across, d deep), its far end scaled by taper."""
    a, b = Vector(a), Vector(b)
    L = (b - a).length
    ob = kit.box("bm", w, d, L, at=(0, 0, L / 2))
    if taper != 1.0:
        for v in ob.data.vertices:
            if v.co.z > L / 2:
                v.co.x *= taper
                v.co.y *= taper
    if bev > 0:
        kit.bevel(ob, bev, segs)
        kit.apply_all(ob)
    q = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    ob.data.transform(Matrix.Translation(a) @ q.to_matrix().to_4x4())
    return piece(region, ob)


def spike(region, base, tip, r, segs=6):
    return tube(region, [base, tip], [r, 0.0], segs=segs)


def turn(ob, deg, axis="Z", pivot=(0, 0, 0)):
    p = Vector(pivot)
    ob.data.transform(Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-p))
    return ob


def move(ob, by):
    ob.data.transform(Matrix.Translation(Vector(by)))
    return ob


def shear(ob, fn):
    return kit.deform(ob, fn)


def rivets(region, pts, r=0.7, axis="Y", depth=0.6):
    return [cy(region, r, r * 0.8, depth, p, axis, 6) for p in pts]


def hazard(x0, x1, z0, z1, y, n, depth=0.5, facing=1):
    """Yellow and black stripes on a front face (y, facing +y, or -y with facing -1): a yellow plate with dark
    slanted bars on it."""
    out = [bx("Hazard", x0, x1, y - depth / 2, y + depth / 2, z0, z1, 0.15)]
    w = (x1 - x0) / (n * 2)
    h = z1 - z0
    for k in range(n):
        xa = x0 + w * (2 * k + 0.5)
        bar = bx("Dark", xa, xa + w, y + facing * depth / 2 - 0.12, y + facing * depth / 2 + 0.12, z0 + 0.05, z1 - 0.05, 0)
        shear(bar, lambda v, xa=xa: Vector((v.x + ((v.z - z0) / h - 0.5) * w * 0.9, v.y, v.z)))
        out.append(bar)
    return out


def mirror(objs):
    """Mirror copies (x -> -x) of these sub-shapes."""
    out = []
    for o in objs:
        kit.apply_all(o)
        cp = kit.mirror_x(o, o.name + "_m")
        cp.data.materials.clear()
        for m in o.data.materials:
            cp.data.materials.append(m)
        out.append(cp)
    return out


# ---------------------------------------------------------------- one boss: its pieces, roles, lamps and colours
ROLE = {"Hull": "hull", "Plates2": "shed2", "Plates3": "shed3", "Glow": "glow", "Weak": "weak"}


class Boss:
    def __init__(self, bid, palette, glow, objective):
        self.id = bid
        self.palette = palette  # region -> (rgb, roughness, metalness)
        self.glow = glow  # the glow colour in phases 1, 2, 3
        self.objective = objective  # (body piece name, lamp piece name)
        self.subs = {}  # piece -> sub-shapes
        self.weak = {}  # weak target id -> lamp centre (Blender)
        self.objective_lamp = None  # the objective lamp's centre from its anchor (Blender)
        self.pieces = {}  # piece -> joined object
        self.roles = dict(ROLE)
        self.roles[objective[0]] = "objective"
        self.roles[objective[1]] = "objectiveGlow"

    def add(self, name, *objs):
        for o in objs:
            if isinstance(o, (list, tuple)):
                self.add(name, *o)
            else:
                self.subs.setdefault(name, []).append(o)

    def lamp(self, target, at, r, scale=(1, 1, 1)):
        self.weak[target] = Vector(at)
        self.add("Weak", ball("Lamp", r, at, scale, 16, 10))

    def finish(self):
        for name, subs in self.subs.items():
            full = "%s_%s" % (self.id, name)
            ob = kit.join(full, subs, shade=False)
            kit.shade_auto(ob, 35)
            self.pieces[name] = ob

    def textured(self):
        return [ob for n, ob in self.pieces.items() if self.roles[n] in ("hull", "shed2", "shed3", "objective")]

    def tris(self):
        return {n: kit.tris(ob) for n, ob in self.pieces.items()}


PHASES = [(110, 210, 255), (255, 136, 40), (255, 52, 48)]  # accents in phases 1, 2, 3 (every boss)
BOSSES = {}
ANCHORS = {  # where the objectives sit (Config.Boss objectives `at`, Roblox x, up, z), for previews and the test
    "RustjawPrime": [(-26, 92, 0), (26, 92, 0)],
    "NullWarFrame": [(-16, 50, 2), (16, 50, 2)],
    "LeviathanEngine": [(-14, 16, 12), (14, 16, 12)],
    "LumenMaw": None,  # generators stand around the pit, not on the body
}


def rb(v):
    """Roblox (x, up, z with -z the front) to Blender (x, front, up)."""
    return Vector((v[0], -v[2], v[1]))


# ================================================================ RustjawPrime: a tall walker (110 studs)
def rustjaw():
    b = Boss("RustjawPrime", {
        "Paint": ((158, 152, 142), 0.6, 0.0),    # warm grey plate
        "Paint2": ((88, 94, 102), 0.56, 0.0),    # slate panels
        "Metal": ((150, 154, 160), 0.38, 1.0),
        "Dark": ((44, 40, 44), 0.7, 0.2),
        "Hazard": ((250, 200, 40), 0.5, 0.0),
        "Accent": ((118, 126, 136), 0.6, 0.0),   # a mismatched patch plate
    }, PHASES, ("Cannon", "CannonGlow"))
    H = "Hull"
    for s in (-1, 1):
        x = s * 14
        side = []
        # boots: a heavy tapered boot, a steel toe cap with three claws, a dark sole
        side.append(bx("Paint2", x - 9, x + 9, -10, 14, 1.2, 10, 1.4, 2, taper=(0.82, 0.78)))
        side.append(bx("Dark", x - 9.4, x + 9.4, -10.4, 15, 0, 1.6, 0.4))
        side.append(bx("Metal", x - 8, x + 8, 9, 19, 0.8, 6.5, 1.4, 2, taper=(0.9, 0.7)))
        for k in (-1, 0, 1):
            side.append(spike("Dark", (x + k * 5, 18, 2.5), (x + k * 5.6, 23, 1.4), 1.6, 6))
        side.append(hazard(x - 7.5, x + 7.5, 3.0, 8.0, 14.2, 4, facing=1))
        # shins (wider at the top), a back piston, the knee hinge
        side.append(bx("Paint", x - 6.2, x + 6.2, -6, 6, 9, 27, 1.2, 2, taper=(1.22, 1.15)))
        side.append(cy("Metal", 1.3, 1.3, 16, (x + s * 2, -8, 18), "Z", 8))
        side.append(cy("Dark", 2.0, 2.0, 3, (x + s * 2, -8, 9.5), "Z", 8))
        side.append(cy("Dark", 6.2, 6.2, 14.5, (x, 0, 30), "X", 16))
        side.append(ring("Metal", 4.6, 1.0, (x, 7.0, 30), "Y", 18, 6))
        # thighs and the hip ball
        side.append(bx("Paint", x - 7, x + 7, -7, 7, 32, 47, 1.4, 2, taper=(1.15, 1.08)))
        side.append(bx("Dark", x - 7.4, x + 7.4, -3, 3, 36, 43, 0.4))  # a thigh seam band
        side.append(ball("Dark", 6.5, (x * 0.93, 0, 48), segs=14, rings=8))
        b.add(H, side)
        b.lamp("knee" + ("L" if s < 0 else "R"), (x, 8.2, 30), 3.6)
        # Plates2: shin guards (they come off at 66%)
        b.add("Plates2", bx("Paint2", x - 5.6, x + 5.6, 5.4, 8.4, 11, 25, 0.8, 2, taper=(1.15, 1.0)))
        b.add("Plates2", rivets("Metal", [(x + k * 3.6, 8.6, 23) for k in (-1, 1)] + [(x + k * 3.6, 8.6, 13) for k in (-1, 1)], 0.6))
    # a mismatched patch plate on the left thigh
    b.add(H, bx("Accent", -19.5, -9, 6.6, 7.8, 38, 45, 0.3))
    b.add(H, rivets("Metal", [(-18.5, 8.0, 44), (-10, 8.0, 44), (-18.5, 8.0, 39), (-10, 8.0, 39)], 0.5))
    # pelvis, belt and the hazard band across the hips
    b.add(H, bx("Metal", -18, 18, -11, 11, 44, 54, 1.6, 2))
    b.add(H, hazard(-14, 14, 46, 51, 11.2, 7, facing=1))
    # the barrel chest
    b.add(H, loft("Paint", [(52, 19, 13.5, 0, 0), (58, 22, 15, 0, 0), (70, 24, 16, 0, 0), (82, 25.5, 16.5, 0, 0),
                            (88, 23.5, 15.5, 0, 0), (91, 19, 13, 0, 0)], segs=28, power=3.4))
    # the chest core (a weak point) in a riveted hatch
    b.add(H, cy("Dark", 8.6, 8.6, 3.2, (0, 15.6, 72), "Y", 20))
    b.add(H, ring("Metal", 7.4, 1.4, (0, 17.4, 72), "Y", 22, 6))
    b.add(H, rivets("Metal", [(math.cos(a) * 7.4, 18.6, 72 + math.sin(a) * 7.4) for a in
                              [k * math.pi / 4 + math.pi / 8 for k in range(8)]], 0.55))
    b.lamp("core", (0, 18.6, 72), 5.2, (1, 0.62, 1))
    # side vents (glow) on the ribs
    for s in (-1, 1):
        for k in range(3):
            b.add("Glow", bx("Lamp", s * 24.4 - 0.5, s * 24.4 + 0.5, -6 + k * 5, -3 + k * 5, 64, 66, 0))
            b.add(H, bx("Dark", s * 24.0 - 0.6, s * 24.0 + 0.6, -6.6 + k * 5, -2.4 + k * 5, 63.2, 66.8, 0.2))
    # belly plates (Plates2) and chest plates (Plates3): dark slate armour over the grey
    for row in range(2):
        z0 = 54.5 + row * 5.4
        b.add("Plates2", bx("Paint2", -13, 13, 12.6 - row * 0.3, 16.6 - row * 0.3, z0, z0 + 4.8, 0.8, 2, taper=(0.94, 1)))
        b.add("Plates2", rivets("Metal", [(-11, 16.9, z0 + 2.4), (11, 16.9, z0 + 2.4)], 0.55))
    for s in (-1, 1):
        pec = bx("Paint2", min(s * 2.2, s * 20.2), max(s * 2.2, s * 20.2), 12.5, 17.5, 77, 89, 1.0, 2)
        shear(pec, lambda v: Vector((v.x, v.y, v.z + (abs(v.x) - 2.2) * 0.14)))  # rising to the shoulders
        b.add("Plates3", pec)
        b.add("Plates3", rivets("Metal", [(s * 5, 17.8, 80), (s * 16, 17.8, 81.5), (s * 10.5, 17.8, 87.5)], 0.55))
    # the back: a boiler pack and two smokestacks with glowing rims
    b.add(H, bx("Paint2", -15, 15, -21, -12, 58, 86, 1.6, 2))
    b.add(H, hazard(-10, 10, 62, 67, -21.2, 5, facing=-1))
    for s in (-1, 1):
        b.add(H, cy("Metal", 2.9, 2.4, 34, (s * 9, -17.5, 92), "Z", 12))
        b.add(H, ring("Dark", 2.9, 0.7, (s * 9, -17.5, 84), "Z", 12, 5))
        b.add(H, ring("Dark", 2.7, 0.7, (s * 9, -17.5, 100), "Z", 12, 5))
        b.add("Glow", ring("Lamp", 2.6, 0.55, (s * 9, -17.5, 109.2), "Z", 12, 5))
    # neck collar and the head
    b.add(H, bx("Dark", -13, 13, -8, 9, 87, 94, 1.0))
    # the skull: a dome with a dark visor recess, an angry brow and glowing eyes
    b.add(H, loft("Paint", [(93, 11, 9.5, 0, 2), (100, 12.2, 10.4, 0, 2.2), (106, 11.4, 9.8, 0, 1.8), (110, 8.4, 7.4, 0, 1.2),
                            (111.6, 4.4, 4, 0, 1)], segs=24, power=3.0))
    b.add(H, bx("Dark", -9.6, 9.6, 9.6, 12.8, 96.6, 103.2, 0.6))
    brow = bx("Paint2", -12.6, 12.6, 7.5, 14.6, 102.6, 106.8, 1.0, 2)
    shear(brow, lambda v: Vector((v.x, v.y, v.z + (abs(v.x) / 12.6) * 2.8 - 1.6)))  # an angry V brow
    b.add(H, brow)
    for s in (-1, 1):
        eye = bx("Lamp", min(s * 2.4, s * 8.6), max(s * 2.4, s * 8.6), 12.4, 13.4, 98.2, 100.8, 0)
        shear(eye, lambda v: Vector((v.x, v.y, v.z + (abs(v.x) - 2.4) * 0.3)))
        b.add("Glow", eye)
        b.add(H, cy("Metal", 2.8, 2.8, 3.2, (s * 12.4, 2, 101), "X", 12))  # ear pistons
        b.add(H, cy("Dark", 1.4, 1.4, 1.0, (s * 14.4, 2, 101), "X", 8))
    # an underbite jaw: wide and jutting, hazard stripes, steel teeth and two tusks
    b.add(H, bx("Paint", -14, 14, -3, 19.5, 84, 95.4, 1.8, 2, taper=(1.0, 0.96)))
    b.add(H, hazard(-11.5, 11.5, 85.6, 91.4, 19.6, 6, facing=1))
    for k in range(5):
        x = -8 + k * 4
        b.add(H, spike("Metal", (x, 16.6, 94.6), (x, 16.9, 98.6), 1.5, 4))
    for s in (-1, 1):
        b.add(H, spike("Metal", (s * 12, 16.2, 94.6), (s * 13, 16.8, 101.6), 2.1, 5))
        b.add(H, cy("Dark", 2.8, 2.8, 2.0, (s * 14.2, 2, 90.5), "X", 12))  # jaw hinges
    # an antenna with a blinker on the back of the skull
    b.add(H, tube("Metal", [(6, -4, 108), (7.5, -6, 115), (8.4, -7.4, 119)], [0.7, 0.55, 0.45], 6))
    b.add("Glow", ball("Lamp", 1.3, (8.5, -7.6, 119.6)))
    # shoulders: dark joints under big riveted dome pauldrons with a hazard rim (the cannons sit on top)
    for s in (-1, 1):
        x = s * 27
        b.add(H, ball("Dark", 8, (x, 0, 82), segs=14, rings=8))
        b.add(H, loft("Paint", [(77, 12.6, 11.6, x, 0), (83, 13.2, 12.2, x, 0), (87.4, 11.2, 10.2, x, 0),
                                (89.6, 7.4, 7, x, 0)], segs=22, power=2.6))
        b.add(H, loft("Hazard", [(76.4, 12.9, 11.9, x, 0), (78.4, 12.9, 11.9, x, 0)], segs=22, power=2.6))
        b.add(H, rivets("Metal", [(x + s * 8, 9.2, 84.5), (x, 12.3, 84.5), (x - s * 8, 9.2, 84.5)], 0.7))
    # arms: hanging heavy (a gorilla stance): upper arm, elbow, a thick forearm with a hazard cuff
    for s in (-1, 1):
        x = s * 29
        b.add(H, beam("Paint", (x, 0, 80), (x + s * 3, -1, 58), 10, 10, 1.2, 2, 0.9))
        b.add(H, ball("Dark", 6.2, (x + s * 3, -1, 58)))
        b.add(H, beam("Paint", (x + s * 3, -1, 58), (x + s * 4, 1, 40), 11, 11, 1.4, 2, 1.25))
        b.add(H, hazard(x + s * 4 - 6.6, x + s * 4 + 6.6, 41.5, 45, 7.6, 4, facing=1))
        b.add("Plates3", beam("Paint2", (x + s * 3.2 + s * 5.4, -1, 56), (x + s * 4.2 + s * 6.4, 1, 44), 2, 9, 0.5, 1))
    # the left fist: a wrecking-ball fist with knuckle spikes
    b.add(H, bx("Metal", -42, -24, -8, 10, 24, 40, 2.2, 2))
    for k in range(4):
        z = 26.5 + k * 3.8
        b.add(H, spike("Dark", (-33, 9.6, z + 0.8), (-33, 14.4, z + 0.8), 1.4, 6))
    b.add(H, bx("Paint2", -42.6, -23.4, -2, 4, 30, 34, 0.5))  # a strap
    # the right hand: a three-fingered claw
    b.add(H, bx("Metal", 25, 41, -6, 8, 32, 40, 1.8, 2))
    for k, (dx, dy) in enumerate(((-5, 5), (0, 6), (5, 5))):
        x0 = 33 + dx
        b.add(H, tube("Dark", [(x0, dy - 1, 33), (x0 + dx * 0.15, dy + 3, 28), (x0 + dx * 0.25, dy + 3.5, 23),
                               (x0 + dx * 0.3, dy + 1, 19.5)], [1.9, 1.6, 1.2, 0.2], 8))
    b.add(H, tube("Dark", [(25.5, 2, 34), (23, 5, 29), (23.5, 6, 25)], [1.8, 1.4, 0.2], 8))  # the thumb
    # the shoulder cannon (one, placed by the game on each shoulder; anchor at the origin)
    c = []
    c.append(cy("Metal", 6.2, 6.8, 5, (0, 0, -2.5), "Z", 18))
    c.append(ring("Dark", 6.5, 0.9, (0, 0, -0.2), "Z", 18, 5))
    c.append(bx("Paint2", -5, 5, -4.4, 5.6, -0.5, 5.4, 1.0, 2, taper=(0.9, 0.9)))
    for k in (-1, 1):  # twin barrels with muzzle brakes, aimed forward and up
        barrel = cy("Dark", 1.8, 1.6, 17, (0, 0, 8.5), "Z", 10)
        muzzle = cy("Metal", 2.5, 2.5, 3.2, (0, 0, 16.4), "Z", 10)
        for o in (barrel, muzzle):
            turn(o, -66, "X")
            move(o, (k * 2.4, 2.5, 2.6))
            c.append(o)
    c.append(hazard(-4.4, 4.4, 0.4, 2.6, 5.7, 4, 0.4, facing=1))
    b.add("Cannon", c)
    b.add("CannonGlow", ball("Lamp", 2.4, (0, -2.4, 4.0)))
    b.objective_lamp = Vector((0, -2.4, 4.0))
    return b


# ================================================================ LumenMaw: a four-legged beast with crystals
def maw():
    b = Boss("LumenMaw", {
        "Paint": ((112, 118, 128), 0.55, 0.0),   # cool grey shell
        "Paint2": ((186, 180, 166), 0.5, 0.1),   # pale sand-grey bands
        "Metal": ((150, 150, 166), 0.36, 1.0),
        "Dark": ((36, 32, 48), 0.65, 0.2),
        "Hazard": ((250, 200, 40), 0.5, 0.0),
        "Accent": ((90, 96, 108), 0.5, 0.0),
    }, PHASES, ("Generator", "GeneratorCore"))
    H = "Hull"
    # the carapace: a long armoured body along y (tail at the back, shoulders at the front)
    body = [(-42, 9, 8, 0, 20), (-34, 19, 15, 0, 25), (-20, 24, 20, 0, 29), (-4, 25.5, 21, 0, 31),
            (10, 23.5, 19, 0, 31), (20, 18, 15, 0, 32), (24, 12, 10, 0, 32)]
    b.add(H, loft_y("Dark", [(y, rx * 0.96, rz * 0.96, cx, cz) for y, rx, rz, cx, cz in body], segs=26, power=2.7))

    def prof(y):
        for (y0, rx0, rz0, _, z0), (y1, rx1, rz1, _, z1) in zip(body, body[1:]):
            if y0 <= y <= y1:
                f = (y - y0) / (y1 - y0)
                return rx0 + (rx1 - rx0) * f, rz0 + (rz1 - rz0) * f, z0 + (z1 - z0) * f
        return body[-1][1], body[-1][2], body[-1][4]

    # overlapping armour shells, back to front like a pangolin's, each with a pale front lip
    for y0, y1 in ((-41, -29), (-31, -17), (-19, -5), (-7, 7), (5, 17), (15, 24)):
        rings = []
        for y, k in ((y0, 0.9), (y0 + (y1 - y0) * 0.5, 1.0), (y1 - 0.8, 1.05)):
            rx, rz, cz = prof(y)
            rings.append((y, rx * k, rz * k, 0, cz))
        b.add(H, loft_y("Paint", rings, segs=26, power=2.7))
        rx, rz, cz = prof(y1)
        b.add(H, loft_y("Paint2", [(y1 - 1.0, rx * 1.07, rz * 1.07, 0, cz), (y1 + 0.4, rx * 1.03, rz * 1.03, 0, cz)],
                        segs=26, power=2.7))
    b.add(H, bx("Dark", -10, 10, -30, 16, 8, 13, 1.4, 2))  # the belly keel
    # vents along the flanks (phase glow)
    for s in (-1, 1):
        for y in (-24, -10, 4):
            rx, rz, cz = prof(y)
            b.add("Glow", bx("Lamp", min(s * (rx * 1.04 - 0.6), s * (rx * 1.04 + 0.4)), max(s * (rx * 1.04 - 0.6), s * (rx * 1.04 + 0.4)),
                             y - 3, y + 3, cz + 6.5, cz + 8, 0))
    # glowing spines along the back (phase glow) between the three crystals
    for k, y in enumerate((-36, 2, 12)):
        z = 46 if y > -30 else 37
        b.add("Glow", spike("Lamp", (0, y, z - 2), (0, y - 3, z + 7 - k), 2.2, 6))
    for y in (-28, -2):
        for s in (-1, 1):
            b.add("Glow", spike("Lamp", (s * 7, y, 47), (s * 9.5, y - 2.5, 53), 1.5, 6))
    # crystal sockets and the three big crystals (the weak points; Config.Boss crystalA..C)
    for tid, at in (("crystalA", (-12, -8, 58)), ("crystalB", (0, -16, 62)), ("crystalC", (12, -8, 58))):
        x, y, z = at
        lean = Vector((x * 0.04, y * 0.0 - 0.12, 1)).normalized()
        base = Vector((x, y, z)) - lean * 7.5
        b.add(H, ring("Metal", 3.8, 1.1, tuple(base + lean * 0.8), "Z", 14, 5))
        b.add(H, cy("Dark", 4.4, 3.6, 3, tuple(base - lean * 0.6), "Z", 10))
        tip = Vector((x, y, z)) + lean * 7.5
        mid = Vector((x, y, z))
        b.add("Weak", tube("Lamp", [base, base + lean * 4, mid + lean * 3, tip], [2.8, 3.2, 2.6, 0.0], 6))
        b.weak[tid] = mid
    # flank armour (Plates2) and the back plates round the crystals (Plates3)
    for s in (-1, 1):
        for y0 in (-24, -8, 8):
            pl = loft_y("Paint", [(y0, 3, 7, 0, 0), (y0 + 13, 3, 7, 0, 0)], segs=12, power=4)
            move(pl, (s * 25.4, 0, 28))
            turn(pl, s * -8, "Y", (s * 25.4, 0, 28))
            b.add("Plates2", pl)
            b.add("Plates2", rivets("Paint2", [(s * 28.6, y0 + 3, 31), (s * 28.6, y0 + 10, 31)], 0.7, "X", 0.6))
    # Plates3: shoulder guards over the front legs (studded pads)
    for s in (-1, 1):
        pad = loft("Paint", [(0, 7, 8, 0, 0), (2.4, 7.6, 8.6, 0, 0), (4.0, 5.6, 6.4, 0, 0)], segs=16, power=2.6)
        turn(pad, s * 62, "Y")
        move(pad, (s * 24, 12, 31))
        b.add("Plates3", pad)
        b.add("Plates3", rivets("Paint2", [(s * 27.6, 12 + k * 4, 34.4 - abs(k) * 0.8) for k in (-1, 0, 1)], 0.8, "X", 0.8))
    # the head: a wedge skull with angry eyes and a ridge of horns, an open lower jaw, steel fangs, a throat glow
    b.add(H, loft_y("Paint", [(18, 14, 11, 0, 41), (28, 16, 11.5, 0, 43), (40, 14.5, 9.5, 0, 43.5), (49, 10, 6.5, 0, 42),
                              (52, 6, 3.5, 0, 41)], segs=24, power=2.4))
    for k, (y, h) in enumerate(((44, 4.5), (37, 6), (29, 7.5))):
        top = 43.5 + 10.5 - k * 0.3
        b.add(H, spike("Paint2", (0, y, top - 2.5), (0, y - 5, top + h), 2.4, 6))
    b.add(H, loft_y("Paint", [(16, 12.5, 5, 0, 27), (30, 13, 5.5, 0, 25), (44, 10.5, 4, 0, 21), (50, 6, 2.5, 0, 20)],
                    segs=22, power=2.4))
    b.add(H, loft_y("Dark", [(18, 12, 9, 0, 33.5), (30, 11, 7, 0, 32), (33, 10, 6, 0, 31.6)], segs=18, power=2.2))
    b.add("Glow", loft_y("Lamp", [(32.6, 9.6, 5.8, 0, 31.8), (34, 9.0, 5.2, 0, 31.8)], segs=18, power=2.2))
    for k in range(7):  # upper fangs round the skull's rim, lower fangs on the jaw
        a = (k - 3) / 3.0
        x = a * 11.5
        y = 47 - abs(a) ** 2 * 10
        b.add(H, spike("Metal", (x, y, 37.6), (x, y + 0.6, 32.4 - (1 - abs(a)) * 1.4), 1.5, 5))
        b.add(H, spike("Metal", (x * 0.85, y - 3, 22.4), (x * 0.85, y - 2.4, 26.6), 1.2, 5))
    for s in (-1, 1):
        eye = bx("Lamp", min(s * 4.5, s * 11), max(s * 4.5, s * 11), 42.4, 44.2, 46.2, 48.4, 0)
        shear(eye, lambda v: Vector((v.x, v.y - (abs(v.x) - 4.5) * 0.45, v.z + (abs(v.x) - 4.5) * 0.3)))
        b.add("Glow", eye)
        b.add(H, cy("Dark", 2.6, 2.6, 3, (s * 15.8, 22, 31), "X", 12))  # jaw hinges
    # an angler lure: a stalk from the brow with a lamp at its tip (phase glow)
    stalk = [(0, 22 + 34 * t, 52 + 15 * math.sin(t * math.pi * 0.85)) for t in [k / 8 for k in range(9)]]
    b.add(H, tube("Paint2", stalk, [2.0 - 1.0 * k / 8 for k in range(9)], 10))
    tip = stalk[-1]
    b.add("Glow", ball("Lamp", 3.2, (0, tip[1] + 1.5, tip[2] - 2.8)))
    # four digger legs (shoulder ball, a bent leg, a three-talon foot) and a drill tail
    for s in (-1, 1):
        for y in (12, -22):
            sh = (s * 22, y, 25)
            kn = (s * 33, y + 2, 22)
            ft = (s * 31, y + 5, 3)
            b.add(H, ball("Dark", 6.0, sh))
            b.add(H, beam("Paint", sh, kn, 8, 8, 1.2, 2, 0.85))
            b.add(H, ball("Metal", 4.2, kn))
            b.add(H, beam("Paint", kn, ft, 7, 7, 1.0, 2, 0.8))
            b.add(H, bx("Dark", ft[0] - 5, ft[0] + 5, ft[1] - 5, ft[1] + 4, 0, 4, 1.0))
            for k in (-1, 0, 1):
                b.add(H, spike("Metal", (ft[0] + k * 3.2, ft[1] + 3.5, 2), (ft[0] + k * 3.8, ft[1] + 9, 0.6), 1.4, 5))
            b.add(H, ring("Paint2", 4.0, 0.9, kn, "X", 14, 5))
    b.add(H, loft_y("Paint", [(-62, 2, 2, 0, 9), (-54, 6, 6, 0, 12), (-44, 9, 8, 0, 18)], segs=16, power=2.2))
    b.add(H, cy("Metal", 5.0, 0.4, 12, (0, -68, 8.5), "Y", 10))
    for k in range(3):
        b.add(H, ring("Paint2", 4.0 - k * 1.2, 0.6, (0, -64.5 - k * 3, 8.5), "Y", 12, 5))
    # the generator (one; the game stands one at each point round the pit; its foot at the origin). Its core
    # sits inside the generator's hit sphere (8 studs up, BossSim)
    g = []
    g.append(bx("Metal", -6.5, 6.5, -6.5, 6.5, 0, 3, 0.8, 2))
    g.append(cy("Paint", 5.0, 4.0, 6.5, (0, 0, 6.2), "Z", 6))
    g.append(ring("Paint2", 4.7, 0.7, (0, 0, 5.0), "Z", 6, 4))
    g.append(hazard(-4.4, 4.4, 1.0, 2.6, 6.6, 3, 0.3, facing=1))
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 6
        g.append(tube("Metal", [(math.cos(a) * 3.2, math.sin(a) * 3.2, 9), (math.cos(a) * 5.2, math.sin(a) * 5.2, 12),
                                (math.cos(a) * 3.0, math.sin(a) * 3.0, 16)], [1.1, 0.9, 0.2], 6))
    b.add("Generator", g)
    b.add("GeneratorCore", ball("Lamp", 3.2, (0, 0, 12)))
    b.objective_lamp = Vector((0, 0, 12))
    return b


# ================================================================ LeviathanEngine: a serpent-shaped sea machine
def leviathan():
    b = Boss("LeviathanEngine", {
        "Paint": ((96, 110, 120), 0.5, 0.1),     # blue-grey hull
        "Paint2": ((158, 164, 170), 0.5, 0.05),  # light grey stripe and fins
        "Metal": ((140, 148, 156), 0.35, 1.0),
        "Dark": ((26, 32, 40), 0.6, 0.2),
        "Hazard": ((250, 200, 40), 0.5, 0.0),
        "Accent": ((214, 218, 222), 0.45, 0.0),  # a pale band (no markings)
    }, PHASES, ("Bay", "BayGlow"))
    H = "Hull"
    # the hull: a long body running back and down under the water (the surface is z = 0)
    hull_rings = [(22, 9, 8, 0, -1), (10, 15, 12, 0, 2), (-8, 16.5, 13, 0, 2.5), (-28, 15.5, 12, 0, 0),
                  (-52, 13, 10, 0, -6), (-78, 10.5, 8, 0, -13), (-102, 8, 6, 0, -21), (-124, 5, 4, 0, -28),
                  (-140, 2.6, 2.2, 0, -33)]
    b.add(H, loft_y("Paint", hull_rings, segs=26, power=2.4))
    # dark segment bands and a light stripe along the waterline
    for (y0, rx0, rz0, _, z0), (y1, rx1, rz1, _, z1) in zip(hull_rings[1:7], hull_rings[2:8]):
        y = (y0 + y1) / 2
        rx, rz, z = (rx0 + rx1) / 2 + 0.4, (rz0 + rz1) / 2 + 0.4, (z0 + z1) / 2
        b.add(H, loft_y("Dark", [(y - 1, rx, rz, 0, z), (y + 1, rx, rz, 0, z)], segs=26, power=2.4))
    for s in (-1, 1):
        stripe = tube("Paint2", [(s * 15.6, 14, 0.5), (s * 16.6, -8, 0.6), (s * 15.6, -28, -1.6), (s * 13, -52, -7),
                                 (s * 10.4, -78, -13.8)], [1.6, 1.6, 1.5, 1.3, 1.0], 8)
        b.add(H, stripe)
        b.add(H, bx("Accent", s * 15.2, s * 17.2, -20, -10, 4, 7.4, 0.3) if s > 0 else bx("Accent", -17.2, -15.2, -20, -10, 4, 7.4, 0.3))
    # a dorsal tower with portholes, its fin planes, and dorsal fins down the back
    b.add(H, loft("Paint", [(10, 4.5, 11, 0, -34), (20, 4.0, 10, 0, -35), (24, 3.4, 8.5, 0, -36)], segs=20, power=2.6))
    b.add(H, bx("Paint2", -3.8, 3.8, -45, -26, 23.2, 24.6, 0.4))
    for s in (-1, 1):
        b.add(H, bx("Paint2", min(s * 4, s * 11), max(s * 4, s * 11), -31, -27, 17, 18.2, 0.4))
        for k in range(3):
            b.add("Glow", cy("Lamp", 0.9, 0.9, 0.6, (s * 4.0, -28 - k * 4, 18.8 - k * 0.3), "X", 8))
    def hull_top(y):
        for (y0, _, rz0, _, z0), (y1, _, rz1, _, z1) in zip(hull_rings, hull_rings[1:]):
            if y1 <= y <= y0:
                f = (y0 - y) / (y0 - y1)
                return (z0 + rz0) * (1 - f) + (z1 + rz1) * f
        return 0

    for k, y in enumerate((-54, -74, -94)):
        fin = bx("Paint2", -0.9, 0.9, y - 9, y + 3, 0, 9 - k * 1.5, 0.3)
        shear(fin, lambda v: Vector((v.x, v.y - v.z * 0.7, v.z)))
        move(fin, (0, 0, hull_top(y) - 1.5))
        b.add(H, fin)
    # side diving fins and the tail propeller in its shroud
    fin = bx("Paint2", 0, 16, -6, 6, -0.8, 0.8, 0.4, 1)
    shear(fin, lambda v: Vector((v.x, v.y - v.x * 0.45, v.z - v.x * 0.12)))
    move(fin, (14, 6, 2))
    b.add(H, fin, mirror([fin]))
    b.add(H, ring("Metal", 5.2, 1.0, (0, -142, -33.5), "Y", 18, 6))
    for k in range(4):
        blade = bx("Metal", -0.5, 0.5, -0.4, 0.4, 0, 4.2, 0.2)
        turn(blade, 20, "Z")
        turn(blade, k * 90, "Y")
        move(blade, (0, -142, -33.5))
        b.add(H, blade)
    # the reactor dome at the base of the neck (a weak point) in a steel collar
    b.add(H, ring("Metal", 5.0, 1.2, (0, -2, 13.2), "Z", 20, 6))
    b.add(H, cy("Dark", 5.6, 5.0, 2.4, (0, -2, 12.4), "Z", 18))
    b.lamp("reactor", (0, -2, 14.4), 4.2, (1, 1, 0.75))
    # the neck: armoured rings rising in an S to the head
    neck = [(0, 6, 4), (0, 13, 13), (0, 19, 24), (0, 23, 33), (0, 28, 40)]
    b.add(H, tube("Paint", neck, [10.5, 9.8, 9.2, 8.6, 8.2], 18))
    for k in range(1, 5):
        p0, p1 = Vector(neck[k - 1]), Vector(neck[k])
        c = (p0 + p1) / 2
        r = [10.5, 9.8, 9.2, 8.6, 8.2][k] + 0.7
        rg = ring("Dark", r, 1.0, (0, 0, 0), "Z", 18, 5)
        q = Vector((0, 0, 1)).rotation_difference((p1 - p0).normalized())
        rg.data.transform(Matrix.Translation(c) @ q.to_matrix().to_4x4())
        b.add(H, rg)
    # the head: an armoured eel skull with a snout, an open jaw, steel teeth, a throat glow, a crest and a periscope
    b.add(H, loft_y("Paint", [(22, 10.5, 8.5, 0, 44.5), (32, 13, 10, 0, 47), (44, 12.5, 9, 0, 48.5), (54, 9.5, 6, 0, 47.5),
                              (62, 5, 3.2, 0, 46)], segs=24, power=2.5))
    b.add(H, loft_y("Paint", [(26, 10, 4.5, 0, 35.5), (40, 9.6, 3.8, 0, 32.5), (50, 7.4, 2.8, 0, 31.2), (57, 4.4, 2, 0, 32)],
                    segs=20, power=2.4))
    b.add(H, loft_y("Dark", [(28, 9.2, 5.6, 0, 38.6), (44, 8.4, 4.4, 0, 37.6), (50, 7, 3.6, 0, 37.4)], segs=18, power=2.2))
    b.add("Glow", loft_y("Lamp", [(49.4, 7.2, 3.8, 0, 37.6), (50.6, 6.6, 3.4, 0, 37.6)], segs=16, power=2.2))
    for k in range(6):
        a = (k - 2.5) / 2.5
        x = a * 8.4
        y = 58 - abs(a) ** 2 * 9
        b.add(H, spike("Metal", (x, y, 42.2), (x, y + 0.4, 37.6), 1.35, 5))
        b.add(H, spike("Metal", (x * 0.85, y - 3, 33.6), (x * 0.85, y - 2.6, 37.2), 1.15, 5))
    for s in (-1, 1):  # swept gill fins behind the jaw (they come off at 66%)
        for k, z in enumerate((41, 46.5)):
            b.add("Plates2", beam("Paint2", (s * 10.6, 34 - k * 2, z), (s * 17.5, 22 - k * 3, z + 4), 1.0, 7 - k, 0.3, 1, 0.35))
    for s in (-1, 1):
        b.add(H, cy("Dark", 4.2, 4.2, 2.4, (s * 9.4, 46, 50), "X", 14))  # eye sockets
        brow = bx("Paint2", min(s * 4, s * 12.4), max(s * 4, s * 12.4), 42, 50, 53.4, 55.4, 0.6)
        shear(brow, lambda v: Vector((v.x, v.y, v.z - (12.4 - abs(v.x)) * 0.28)))
        b.add(H, brow)
        b.lamp("eye" + ("L" if s < 0 else "R"), (s * 8.8, 46.6, 50), 3.0)
    crest = bx("Paint2", -0.9, 0.9, 22, 44, 55, 59, 0.3)
    shear(crest, lambda v: Vector((v.x, v.y, v.z - (v.y - 22) * 0.12 + (2 if v.z > 57 else 0) * (44 - v.y) / 22)))
    b.add(H, crest)
    b.add(H, tube("Metal", [(0, 26, 52), (0, 25, 62), (0, 27.5, 64.5)], [0.9, 0.9, 0.9], 8))  # the periscope
    b.add(H, bx("Metal", -1.4, 1.4, 26.4, 30, 63, 66, 0.3))
    b.add("Glow", cy("Lamp", 1.0, 1.0, 0.4, (0, 30.2, 64.5), "Y", 10))
    # armour sleeves on the neck (Plates3: they come off at 33%, leaving the dark ribbed neck)
    radii = [10.5, 9.8, 9.2, 8.6, 8.2]
    for k in (1, 3):
        p0, p1 = Vector(neck[k - 1]), Vector(neck[k])
        r = (radii[k - 1] + radii[k]) / 2 + 0.9
        b.add("Plates3", tube("Paint2", [p0.lerp(p1, 0.18), p0.lerp(p1, 0.5), p0.lerp(p1, 0.82)], [r, r + 0.3, r], 18))
    # the torpedo bay (one; the game sets one at each objective on the back; anchor at the origin)
    t = []
    t.append(bx("Metal", -4.6, 4.6, -6.2, 6.2, -7, 0.6, 1.0, 2))
    t.append(hazard(-4, 4, -2.6, -0.2, 6.3, 4, 0.4, facing=1))
    for s in (-1, 1):
        t.append(cy("Dark", 1.6, 1.6, 2, (s * 2.0, 2.4, 0.9), "Z", 10))
        t.append(ring("Paint2", 1.7, 0.4, (s * 2.0, 2.4, 1.8), "Z", 10, 4))
    t.append(bx("Paint2", -4.0, 4.0, -5.2, -1.4, 0.4, 1.2, 0.3))
    b.add("Bay", t)
    b.add("BayGlow", ball("Lamp", 1.5, (0, -3.3, 2.2)))
    b.objective_lamp = Vector((0, -3.3, 2.2))
    return b


# ================================================================ NullWarFrame: an angular mech (mission 6)
def warframe():
    b = Boss("NullWarFrame", {
        "Paint": ((126, 130, 138), 0.5, 0.1),    # steel grey
        "Paint2": ((64, 66, 74), 0.55, 0.1),     # graphite armour
        "Metal": ((150, 156, 170), 0.32, 1.0),
        "Dark": ((22, 22, 28), 0.6, 0.2),
        "Hazard": ((250, 200, 40), 0.5, 0.0),
        "Accent": ((184, 188, 194), 0.45, 0.0),  # light trim
    }, PHASES, ("Cannon", "CannonGlow"))
    H = "Hull"
    for s in (-1, 1):
        # feet: split clawed sabatons with a heel spur
        fx = s * 11
        b.add(H, bx("Paint2", fx - 4.6, fx + 4.6, -5, 5, 0, 4, 0.8, 2, taper=(0.86, 0.8)))
        for k in (-1, 1):
            b.add(H, beam("Metal", (fx + k * 2.2, 4, 1.2), (fx + k * 2.6, 11, 0.8), 3.2, 2.2, 0.5, 1, 0.5))
        b.add(H, spike("Dark", (fx, -4.6, 2), (fx, -9, 0.6), 1.6, 5))
        # shins (angled out to the wide feet) and the knee drives meeting at the centre
        b.add(H, beam("Paint", (fx * 0.98, 0.6, 3.5), (s * 5.6, 4.2, 14), 6.6, 6.6, 0.9, 2, 1.12))
        b.add(H, beam("Accent", (fx * 0.98 + s * 0.2, 3.4, 4.5), (s * 5.8, 7.3, 13.4), 1.4, 1.2, 0.3, 1))
        b.add(H, cy("Dark", 3.8, 3.8, 5.6, (s * 4.4, 5, 14), "X", 14))
        b.add(H, ring("Metal", 2.9, 0.6, (s * 3.9, 7.4, 14), "Y", 14, 5))
        b.add("Weak", ball("Lamp", 2.5, (s * 3.9, 8.3, 14), segs=16, rings=10))
        # thighs up to the hip joints
        b.add(H, beam("Paint", (s * 5.6, 4.2, 14.5), (s * 6.4, 0.5, 27), 7, 7, 1.0, 2, 1.1))
        b.add(H, beam("Accent", (s * 9.2, 3.6, 16), (s * 10.0, 0.6, 26), 1.2, 1.4, 0.3, 1))  # a light trim stripe
        b.add(H, ball("Dark", 4.0, (s * 6.6, 0, 27.5)))
    b.weak["knee"] = Vector((0, 8.3, 14))  # one target between both knee lamps (Config.Boss knee)
    # hips and an armour skirt (Plates2)
    b.add(H, bx("Dark", -10, 10, -6, 6, 25, 31.5, 1.0))
    for s in (-1, 1):
        flap = bx("Paint2", min(s * 1.4, s * 9.6), max(s * 1.4, s * 9.6), 5.4, 7.0, 21, 30, 0.6, 1, taper=None)
        shear(flap, lambda v, s=s: Vector((v.x + s * (30 - v.z) * 0.12, v.y + (30 - v.z) * 0.14, v.z)))
        b.add("Plates2", flap)
        side = bx("Paint2", s * 9.6 - 1, s * 9.6 + 1, -5, 5, 21, 30.5, 0.5)
        shear(side, lambda v, s=s: Vector((v.x + s * (30 - v.z) * 0.18, v.y, v.z)))
        b.add("Plates2", side)
    # the V chest with a round chest lamp (phase colour; no emblem)
    b.add(H, loft("Paint", [(31, 9, 7, 0, 0), (35, 12, 8, 0, 0), (43, 16, 9.5, 0, 0.4), (50, 17.5, 9.6, 0, 0.4),
                            (53.5, 14, 8, 0, 0)], segs=24, power=4.2))
    for s in (-1, 1):
        pec = bx("Paint2", min(s * 1.2, s * 14.5), max(s * 1.2, s * 14.5), 8.4, 10.4, 41, 48.5, 0.8, 2)
        shear(pec, lambda v, s=s: Vector((v.x, v.y, v.z - (14.5 - abs(v.x)) * 0.16 + 1.2)))
        b.add(H, pec)
        b.add("Plates2", beam("Paint2", (s * 15.5, -4, 35), (s * 17.6, 4, 47), 2.4, 5, 0.5, 1))  # rib plates
    b.add("Glow", cy("Lamp", 2.6, 2.6, 0.8, (0, 10.4, 39.2), "Y", 20))
    b.add(H, ring("Metal", 3.4, 0.6, (0, 10.4, 39.2), "Y", 20, 5))
    b.add(H, cy("Dark", 4.2, 4.2, 1.2, (0, 9.8, 39.2), "Y", 20))
    # the back reactor (the shield's weak point) in a vented pack with two thrusters
    b.add(H, bx("Paint2", -9, 9, -12.2, -6, 33, 48, 1.2, 2))
    b.add(H, cy("Metal", 5.4, 5.0, 2.2, (0, -12.6, 40), "Y", 20))
    b.add(H, ring("Accent", 5.0, 0.8, (0, -13.6, 40), "Y", 20, 5))
    b.lamp("back", (0, -13.7, 40), 3.8, (1, 0.6, 1))
    for s in (-1, 1):
        b.add(H, cy("Dark", 2.0, 2.8, 6, (s * 6.6, -10, 30.5), "Z", 12))
        b.add("Glow", cy("Lamp", 2.5, 2.5, 0.4, (s * 6.6, -10, 27.4), "Z", 12))
    # the head: an angular helm with a visor, a mouth grille and swept horns
    b.add(H, loft("Paint2", [(51, 5.5, 5.5, 0, 0.4), (54, 6.4, 6.6, 0, 1.2), (58, 6, 6.2, 0, 1.4), (60.5, 4, 4.4, 0, 1)],
                  segs=20, power=3.6))
    visor = bx("Lamp", -5, 5, 7.4, 8.8, 55.6, 57.4, 0)
    shear(visor, lambda v: Vector((v.x, v.y - abs(v.x) * 0.22, v.z + abs(v.x) * 0.2)))
    b.add("Glow", visor)
    b.add(H, bx("Dark", -2.8, 2.8, 6.2, 7.4, 51.6, 54.4, 0.3))
    for k in range(3):
        b.add(H, bx("Metal", -2.4, 2.4, 7.3, 7.6, 52.0 + k * 0.9, 52.4 + k * 0.9, 0))
    b.add(H, beam("Accent", (0, 5.8, 59.4), (0, -4, 63.6), 1.2, 3.2, 0.4, 1, 0.4))  # the crest fin
    for s in (-1, 1):
        b.add(H, tube("Accent", [(s * 5.2, 2, 58), (s * 8.4, 0, 61), (s * 9.8, -3.6, 64.5)], [1.4, 0.9, 0.0], 6))
        b.add("Plates3", bx("Paint", min(s * 5.8, s * 7.2), max(s * 5.8, s * 7.2), -1, 6, 51.6, 56, 0.4))  # cheek guards
    # shoulders: big angular pauldrons (the cannons sit on top)
    for s in (-1, 1):
        x = s * 19
        b.add(H, ball("Dark", 4.6, (x * 0.94, 0, 46)))
        pd = bx("Paint", x - 6.5, x + 6.5, -6.5, 6.5, 44, 48.5, 1.0, 2, taper=(0.78, 0.8))
        shear(pd, lambda v, x=x: Vector((v.x, v.y, v.z - abs(v.x - x) * 0.18 + (1.2 if (v.x - x) * s < 0 else 0))))
        b.add(H, pd)
        b.add(H, bx("Accent", x - 6.6, x + 6.6, 5.6, 6.8, 43.6, 44.8, 0.2))
        # arms: upper arm, elbow, forearm, a fist (left) or a forearm blade (right)
        el = (s * 22.5, -0.5, 34)
        fi = (s * 23.5, 1, 23.5)
        b.add(H, beam("Paint", (x * 1.05, 0, 44), el, 5.6, 5.6, 0.8, 2, 0.95))
        b.add(H, ball("Dark", 3.4, el))
        b.add(H, beam("Paint2", el, fi, 6.6, 6.6, 0.9, 2, 1.15))
        b.add("Plates3", beam("Paint", (s * 26.4, -0.4, 32.5), (s * 27.4, 1.0, 25.5), 1.6, 5.4, 0.4, 1))
        b.add(H, bx("Metal", fi[0] - 3.6, fi[0] + 3.6, fi[1] - 3.4, fi[1] + 3.6, 18.4, 23.6, 1.0, 2))
    blade = beam("Accent", (25.4, 3.5, 30.5), (26.4, 9, 13), 0.8, 3.4, 0.2, 1, 0.3)
    b.add(H, blade)
    # the shoulder cannon (one; the game sets one on each shoulder; anchor at the origin)
    c = []
    c.append(bx("Paint2", -3.6, 3.6, -3.6, 3.6, -4.2, -0.2, 0.7, 2))
    c.append(bx("Paint", -3.0, 3.0, -3.4, 3.8, -0.4, 2.8, 0.7, 2, taper=(0.8, 0.85)))
    for k in (-1, 1):
        bar = cy("Dark", 0.9, 0.8, 10, (0, 0, 5), "Z", 8)
        turn(bar, -72, "X")
        move(bar, (k * 1.3, 1.6, 1.4))
        c.append(bar)
    c.append(bx("Accent", -3.1, 3.1, 3.7, 4.2, 0.2, 1.4, 0.15))
    b.add("Cannon", c)
    b.add("CannonGlow", ball("Lamp", 1.4, (0, -2.6, 3.0)))
    b.objective_lamp = Vector((0, -2.6, 3.0))
    return b


BUILDERS = {"RustjawPrime": rustjaw, "LumenMaw": maw, "LeviathanEngine": leviathan, "NullWarFrame": warframe}
for bid, fn in BUILDERS.items():
    if ONLY and bid != ONLY:
        continue
    bb = fn()
    bb.finish()
    BOSSES[bid] = bb
    counts = bb.tris()
    total = sum(counts.values())
    print(bid, total, "tris", counts)
    assert total <= BUDGET, "%s is over the boss budget" % bid
    for n, t in counts.items():
        assert t <= MESH_BUDGET, "%s_%s is over the mesh budget" % (bid, n)

# ---------------------------------------------------------------- bakes and the texture set, one boss at a time
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.render.bake.margin = 8
scene.render.bake.use_clear = True
scene.world = scene.world or bpy.data.worlds.new("W")
rng = np.random.default_rng(11)


def image(name, data=True):
    img = bpy.data.images.new(name, RES, RES, alpha=False, float_buffer=False)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


def set_target(img):
    for m in MATS.values():
        nt = m.node_tree
        node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
        node.name = "BakeTarget"
        node.image = img
        nt.nodes.active = node


def with_emission(fn):
    saved = {}
    for name, m in MATS.items():
        nt = m.node_tree
        out = nt.nodes["Material Output"]
        saved[name] = out.inputs["Surface"].links[0].from_socket
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "TmpEmit"
        fn(name, nt, em)
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return saved


def restore(saved):
    for name, m in MATS.items():
        nt = m.node_tree
        nt.links.new(saved[name], nt.nodes["Material Output"].inputs["Surface"])
        em = nt.nodes.get("TmpEmit")
        if em:
            nt.nodes.remove(em)


def bake(kind, img, samples):
    scene.cycles.samples = samples
    set_target(img)
    bpy.ops.object.bake(type=kind)


def pixels(img):
    return np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)


def blur_noise(scale):
    n = rng.random((RES // scale + 2, RES // scale + 2)).astype(np.float32)
    n = np.kron(n, np.ones((scale, scale), dtype=np.float32))[:RES, :RES]
    k = np.ones(scale) / scale
    n = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 0, n)
    n = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, n)
    return n


def save(name, arr, data):
    img = bpy.data.images.new(name, RES, RES, alpha=arr.ndim == 3 and arr.shape[2] == 4)
    if data:
        img.colorspace_settings.name = "Non-Color"
    if arr.ndim == 2:
        arr = np.dstack([arr, arr, arr, np.ones_like(arr)])
    img.pixels[:] = arr.reshape(-1)
    path = os.path.join(OUT, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


EXPORT_MATS = {}
yy, xx = np.mgrid[0:RES, 0:RES].astype(np.float32)
DOT = 5.0  # halftone cell, pixels
cell = np.hypot((xx % DOT) - DOT / 2, (yy % DOT) - DOT / 2)

for bid, bb in BOSSES.items():
    objs = bb.textured()
    # UVs: one atlas for this boss's textured pieces
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.003, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    # only this boss is in the bake's world
    for other in BOSSES.values():
        for o in other.pieces.values():
            o.hide_render = other is not bb
    ids = image(bid + "_ids")
    saved = with_emission(lambda n, nt, em: em.inputs["Color"].__setattr__("default_value", (*REGION_IDS[n], 1)))
    bake("EMIT", ids, 1)
    restore(saved)
    edges = image(bid + "_edges")

    def edge_emit(n, nt, em):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        nt.links.new(geo.outputs["Pointiness"], em.inputs["Color"])

    saved = with_emission(edge_emit)
    bake("EMIT", edges, 1)
    restore(saved)
    ao = image(bid + "_ao")
    scene.world.light_settings.distance = 6.0
    bake("AO", ao, 32)
    cavity = image(bid + "_cavity")  # a short-range occlusion: the creases between panels, for the ink
    scene.world.light_settings.distance = 0.9
    bake("AO", cavity, 24)
    normal = image(bid + "_normal")
    bake("NORMAL", normal, 6)

    I = pixels(ids)
    A = np.clip(pixels(ao)[..., 0], 0, 1)
    E = pixels(edges)[..., 0]
    N = pixels(normal)
    mottle = blur_noise(24) * 0.6 + blur_noise(6) * 0.4
    region = np.full((RES, RES), -1, dtype=np.int32)
    for k, n in enumerate(ORDER):
        c = np.array(REGION_IDS[n], dtype=np.float32)
        region[np.abs(I[..., :3] - c).sum(axis=2) < 0.3] = k
    wear = np.clip((E - 0.52) * 7.0, 0, 1)  # convex edges: worn, lighter paint
    C = np.clip(pixels(cavity)[..., 0], 0, 1)
    ink = np.clip(np.maximum((0.47 - E) * 9.0, (0.8 - C) * 3.4), 0, 1)  # creases: comic ink lines
    shadow = np.clip((0.8 - A) * 2.2, 0, 1)
    dots = (cell < shadow * DOT * 0.42).astype(np.float32)  # halftone dots in the shadows
    col = np.zeros((RES, RES, 4), dtype=np.float32)
    rough = np.full((RES, RES), 0.6, dtype=np.float32)
    metal = np.zeros((RES, RES), dtype=np.float32)
    for k, n in enumerate(ORDER):
        m = region == k
        rgb, r, mt = bb.palette[n]
        base = np.array(rgb, dtype=np.float32) / 255
        px = np.repeat(base[None, :], m.sum(), axis=0)
        shade = (0.62 + 0.38 * A[m])[:, None]
        grime = (1 - 0.08 * mottle[m])[:, None]
        px = px * shade * grime
        px = px + wear[m][:, None] * (0.22 if n not in ("Dark",) else 0.12) * (1 - px * 0.6)
        px = px * (1 - 0.72 * ink[m])[:, None] * (1 - 0.14 * dots[m])[:, None]
        col[m, :3] = np.clip(px, 0, 1)
        rough[m] = np.clip(r + (mottle[m] - 0.5) * 0.14 - wear[m] * 0.1 + ink[m] * 0.2, 0.05, 1)
        metal[m] = mt * (1 - ink[m] * 0.5)
    col[..., 3] = 1
    col[region < 0, :3] = 0.08
    color_img = save(bid + "_Color", col, False)
    normal_img = save(bid + "_Normal", N, True)
    rough_img = save(bid + "_Roughness", rough, True)
    metal_img = save(bid + "_Metalness", metal, True)

    # the export material: one PBR material on this boss's textured pieces (one SurfaceAppearance)
    mat = bpy.data.materials.new(bid)
    mat.use_nodes = True
    nt = mat.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex_node(img, data):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        if data:
            img.colorspace_settings.name = "Non-Color"
        return n

    nt.links.new(tex_node(color_img, False).outputs["Color"], p.inputs["Base Color"])
    nt.links.new(tex_node(rough_img, True).outputs["Color"], p.inputs["Roughness"])
    nt.links.new(tex_node(metal_img, True).outputs["Color"], p.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex_node(normal_img, True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    EXPORT_MATS[bid] = mat
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
for bb in BOSSES.values():
    for o in bb.pieces.values():
        o.hide_render = False


# ---------------------------------------------------------------- the fit table (Roblox axes: x, up, back)
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def v3(v):
    return "{ %.3f, %.3f, %.3f }" % (v[0], v[2], -v[1])


def size3(lo, hi):
    return "{ %.3f, %.3f, %.3f }" % (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)


if ONLY is None:
    rows = []
    for bid, bb in BOSSES.items():
        counts = bb.tris()
        rows.append("\t%s = {" % bid)
        rows.append("\t\ttriangles = %d," % sum(counts.values()))
        rows.append("\t\tglow = { %s }, -- phases 1, 2, 3" % ", ".join("{ %d, %d, %d }" % c for c in bb.glow))
        rows.append("\t\tpieces = {")
        for name in sorted(bb.pieces):
            role = bb.roles[name]
            if role in ("objective", "objectiveGlow"):
                continue
            lo, hi = bounds(bb.pieces[name])
            rows.append("\t\t\t%s = { role = \"%s\", size = %s, offset = %s }, -- %d tris"
                        % (name, role, size3(lo, hi), v3((lo + hi) / 2), counts[name]))
        rows.append("\t\t},")
        rows.append("\t\t-- the objective, set at each Config.Boss objective (offsets from its point; the Maw's from the")
        rows.append("\t\t-- generator's foot)")
        rows.append("\t\tobjective = {")
        for name in sorted(bb.pieces):
            role = bb.roles[name]
            if role not in ("objective", "objectiveGlow"):
                continue
            lo, hi = bounds(bb.pieces[name])
            rows.append("\t\t\t%s = { role = \"%s\", size = %s, offset = %s }, -- %d tris"
                        % (name, role, size3(lo, hi), v3((lo + hi) / 2), counts[name]))
        rows.append("\t\t},")
        rows.append("\t\t-- where each weak point's lamp sits (from the feet): inside its Config.Boss hit sphere")
        rows.append("\t\tweak = {")
        for tid in sorted(bb.weak):
            rows.append("\t\t\t%s = %s," % (tid, v3(bb.weak[tid])))
        rows.append("\t\t},")
        rows.append("\t},")
    text = "\n".join([
        "-- GENERATED by art/blender/bosses.py: do not edit by hand.",
        "-- PLACEHOLDER LOOK: boss lore pending (generic neutral machines: no emblems, no text, no story looks).",
        "-- The remade bosses (ReplicatedStorage.Art.Bosses, meshes named \"<Boss>_<Piece>\"): each piece's size and its",
        "-- centre from the boss's feet, in studs (x, up, back; a boss faces -z). Roles: hull (textured body), shed2 and",
        "-- shed3 (textured plates that break off at phases 2 and 3), glow (Neon, the phase colour), weak (Neon, the",
        "-- pulsing weak-point gold), objective and objectiveGlow (one set per Config.Boss objective; the lamp goes dark",
        "-- when broken). One %d px texture set per boss (art/export/bosses). Hit boxes stay Config.Boss's." % RES,
        "return {",
        "\ttexture = %d," % RES,
        "\tweakColor = { { 255, 196, 40 }, { 255, 246, 190 } }, -- the weak points pulse between these",
        "\tpulse = 2.2, -- pulses a second",
        "\tobjectiveColor = { 255, 70, 60 },",
    ] + rows + ["}", ""])
    cfg = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "BossArt.luau"))
    with open(cfg, "w") as f:
        f.write(text)
    print("wrote", cfg)

if ONLY is None and "--no-export" not in sys.argv:
    export = []
    for bid, bb in BOSSES.items():
        for name, ob in bb.pieces.items():
            cp = ob.copy()
            cp.data = ob.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            full = "%s_%s" % (bid, name)
            cp.name = full + "_x"
            kit.centre(cp)
            cp.name = full
            cp.data.name = full
            export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(kit.ROOT, "export", "Bosses.fbx"),
        use_selection=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="COPY",
        embed_textures=True,
    )
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

# ---------------------------------------------------------------- previews: the game's look (lamps lit in the phase
# colour, weak points gold, objective lamps red), phase 1 from the front and phase 3 (plates gone, red-hot) from
# behind, with a 5-stud hero for scale
if "--preview" in sys.argv:
    WEAK = (255, 214, 90)
    SHOWN = []  # this render's objects

    def keep(o):
        SHOWN.append(o)
        return o

    def emit(name, rgb, strength=4.0):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.type == "BSDF_PRINCIPLED":
                nt.nodes.remove(n)
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
        em.inputs["Strength"].default_value = strength
        nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
        return m

    def copy(ob, matrix, mat=None):
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.matrix_world = matrix
        cp.hide_render = False
        if mat:
            cp.data.materials.clear()
            cp.data.materials.append(mat)
        return keep(cp)

    def place(bb, at, yaw, phase, mats):
        """Copies of a boss's pieces at `at` (Blender), turned by yaw degrees, dressed for a phase."""
        Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        for name, ob in bb.pieces.items():
            role = bb.roles[name]
            if role == "shed2" and phase >= 2 or role == "shed3" and phase >= 3:
                continue
            anchors = [Vector((0, 0, 0))]
            if role in ("objective", "objectiveGlow"):
                if bb.id == "LumenMaw":
                    continue
                anchors = [rb(a) for a in ANCHORS[bb.id]]
            for a in anchors:
                copy(ob, Y @ Matrix.Translation(a), mats.get(role))

    def generators(bb, centre, yaw, mats, radius=46):
        for k in range(3):
            a = math.radians(yaw + 90 + (k - 1) * 55)
            p = Vector(centre) + Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
            copy(bb.pieces["Generator"], Matrix.Translation(p))
            copy(bb.pieces["GeneratorCore"], Matrix.Translation(p), mats["objectiveGlow"])

    def hero(at):
        m = kit.material("hero", (60, 120, 220), rough=0.5)
        sk = kit.material("skin", (240, 190, 150), rough=0.5)
        for size, c, mat in (((2, 1, 2.0), (0, 0, 3.0), m), ((1.2, 1.2, 1.2), (0, 0, 4.6), sk), ((0.95, 1, 2.0), (-0.5, 0, 1.0), m),
                             ((0.95, 1, 2.0), (0.5, 0, 1.0), m), ((1, 1, 2), (-1.5, 0, 3.0), sk), ((1, 1, 2), (1.5, 0, 3.0), sk)):
            o = keep(kit.box("hero", *size, at=tuple(Vector(at) + Vector(c))))
            o.data.materials.append(mat)

    def phase_mats(bb, phase):
        return {
            "glow": emit("glow%d" % phase, bb.glow[phase - 1], 5.0),
            "weak": emit("weak", WEAK, 2.6),
            "objectiveGlow": emit("obj", (255, 70, 60), 5.0),
        }

    def ground(size=400, sea=False):
        if sea:
            w = keep(kit.cyl("water", size, size, 0.3, at=(0, 0, -0.15), segs=64))
            wm = bpy.data.materials.new("water")
            wm.use_nodes = True
            pr = wm.node_tree.nodes["Principled BSDF"]
            pr.inputs["Base Color"].default_value = (0.05, 0.25, 0.35, 1)
            pr.inputs["Roughness"].default_value = 0.15
            pr.inputs["Alpha"].default_value = 0.5
            w.data.materials.append(wm)
            bed = keep(kit.cyl("seabed", size, size, 0.4, at=(0, 0, -60), segs=64))
            bed.data.materials.append(kit.material("seabed", (24, 40, 52), rough=0.9))
        else:
            f = keep(kit.cyl("floor", size, size, 0.4, at=(0, 0, -0.2), segs=64))
            f.data.materials.append(kit.material("floor", (70, 74, 82), rough=0.85))

    def clear():
        for o in SHOWN:
            bpy.data.objects.remove(o, do_unlink=True)
        SHOWN.clear()

    def camera(loc, target, lens):
        keep(kit.camera(loc, target, lens))

    for bb in BOSSES.values():
        for o in bb.pieces.values():
            o.hide_render = True
    kit.studio(res=(1800, 1000), samples=48)
    VIEW = {  # boss spacing, camera distance, camera height, look-at height
        "RustjawPrime": (72, 250, 70, 52),
        "LumenMaw": (88, 290, 95, 26),
        "LeviathanEngine": (100, 330, 120, 16),
        "NullWarFrame": (36, 125, 36, 28),
    }
    for bid, bb in BOSSES.items():
        sep, d, ch, h = VIEW[bid]
        ground(sea=bid == "LeviathanEngine")
        # (the camera looks from the boss's front, so +x is on the left of the picture)
        place(bb, (sep, 0, 0), -30, 1, phase_mats(bb, 1))
        place(bb, (-sep, 0, 0), 150, 3, phase_mats(bb, 3))
        if bid == "LumenMaw":
            generators(bb, (sep, 0, 0), -30, phase_mats(bb, 1))
        hero((0, 30, 0))
        camera((0, d, ch), (0, 0, h), 32)
        kit.render(os.path.join(kit.ROOT, "preview", "boss_%s.png" % bid))
        clear()
    if ONLY is None:
        # the lineup: all four in scale, phase 1, three-quarter view, with a hero for scale
        ground(600)
        xs = {"RustjawPrime": -150, "LumenMaw": -30, "NullWarFrame": 65, "LeviathanEngine": 160}
        for bid, bb in BOSSES.items():
            place(bb, (xs[bid], 0, 0), -20, 1, phase_mats(bb, 1))
        hero((10, 60, 0))
        camera((0, 360, 90), (0, 0, 45), 30)
        kit.render(os.path.join(kit.ROOT, "preview", "bosses.png"))
