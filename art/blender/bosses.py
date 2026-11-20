# bosses.py: the remade world bosses (overhaul plan step 4, the bosses part), the same pipeline as the remade
# Spark Trooper (trooper.py): meshes plus one baked PBR texture set per boss, exported as FBX, with a generated
# fit table the game places them from.
# The looks (nate's lore, 2026-11-17, build plan step 8): the three world bosses stand apart from the main story and
# keep their names and fights, with new looks: Rustjaw Prime, the Junkyard Titan (a giant a mad scrapper bolted
# together from wrecked cars: car bodies, tyres, a bumper jaw, headlight eyes, exhaust stacks, a crane arm, weld
# seams that spark); Lumen Maw, the Light Eater (a sleek night creature with bioluminescent stripes and a huge maw
# that pulls light in); Leviathan Engine, the Deep Machine (an ancient barnacled brass-and-stone sea machine with
# gears, portholes and a tide-turbine heart). Bright cartoon, comic heroic, never gory: machines shed sparks and
# plates, the Maw bursts into light. Original designs only. Bulwark's battle form (NullWarFrame, a mission fight)
# keeps the neutral mech look (grey and steel, hazard stripes) until its own pass. The ids are Config.Boss's.
# PLACEHOLDER ART until nate imports the FBX (Tasks.md "Lore step 8: world bosses"); until then the game draws each
# world boss from the part-built look written here too (BossArt parts, previews boss_<Boss>_parts.png).
# * Each boss is a few meshes by role (src/config/BossArt.luau, generated here):
#     hull           the textured body, split by rig segment (the boss pass, 2026-11-19: "<Seg>_Hull", the main
#                    body plain "Hull"; every role is split the same way; BossArt rig, Shared.BossPose)
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
# src/config/BossArt.luau and, with --preview, art/preview/bosses.png plus art/preview/boss_<Boss>.png (and the
# part-built looks, boss_<Boss>_parts.png).
# Run: python art/blender/bosses.py [--preview] [--only <Boss>] [--quick]   (with the `bpy` module, Blender 5.0;
# --quick: shapes and previews only, flat colours, no bake, no export)
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
def centre_of(ob):
    """The centre of a sub-shape's box (Blender axes, world)."""
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    if not vs:
        return Vector((0, 0, 0))
    return Vector(((min(v.x for v in vs) + max(v.x for v in vs)) / 2, (min(v.y for v in vs) + max(v.y for v in vs)) / 2,
                   (min(v.z for v in vs) + max(v.z for v in vs)) / 2))


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
        self.look = None  # the look in a few words (nate's lore); None keeps the boss's older look
        self.theme = None  # the look's colour: the entrance effects and the name card's slash
        self.debris = None  # the colour of the bits that fly off (plates, the defeat)
        self.fx = None  # the look's own effect round it: {kind, every, at = [(x, up, z)], ...} in Roblox axes
        self.parts = None  # the part-built look until the meshes are imported (fallback rows, Roblox axes)
        self.segs = {}  # piece -> its rig segment ("Body" for the main one)
        self.seg_of = None  # (piece name, centre in Blender axes) -> rig segment; None keeps one segment
        self.rig = []  # [(segment, parent, pivot in Blender axes)], parents first; "Root" is the boss's feet
        self.objective_parts = None  # and its objective, set at each Config.Boss objective

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
            # the body's pieces split by rig segment (the boss pass, 2026-11-19: each segment moves on its own pivot
            # in game, Shared.BossPose); the objective's pieces stay whole
            groups = {}
            for o in subs:
                seg = "Body"
                if self.seg_of and name in ROLE:
                    kit.apply_all(o)
                    seg = o.get("seg") or self.seg_of(name, centre_of(o))  # (a sub-shape may name its own)
                groups.setdefault(seg, []).append(o)
            for seg, objs in groups.items():
                key = name if seg == "Body" else "%s_%s" % (seg, name)
                full = "%s_%s" % (self.id, key)
                ob = kit.join(full, objs, shade=False)
                kit.shade_auto(ob, 35)
                self.pieces[key] = ob
                self.segs[key] = seg
                if key != name:
                    self.roles[key] = ROLE[name]

    def textured(self):
        return [ob for n, ob in self.pieces.items() if self.roles[n] in ("hull", "shed2", "shed3", "objective", "drone")]

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


# ---------------------------------------------------------------- nate's lore (2026-11-17, build plan step 8): new
# looks for the three world bosses. Shared bits: a tyre, a crushed car slab, a barnacle cluster, a gear wheel, and a
# fallback part row (the part-built look the game shows until the meshes are imported, in Roblox axes)


def tyre(at, axis, major, minor, hub=True, segs=16):
    """A cartoon tyre (Dark) with a chrome hub (Metal) on the given axis."""
    out = [ring("Dark", major, minor, at, axis, segs, 5)]
    if hub:
        out.append(cy("Metal", major * 0.62, major * 0.62, minor * 1.1, at, axis, 10))
    return out


def car(region, x0, x1, y0, y1, z0, z1, windows=True, lean=0.0, front=True):
    """A crushed car body: a bevelled slab with dark window strips down both long sides (and a grille band on the
    front when front), leaned lean degrees about y."""
    out = [bx(region, x0, x1, y0, y1, z0, z1, 1.0, 2)]
    if windows:
        h = z1 - z0
        for s in (-1, 1):
            x = x1 if s > 0 else x0
            out.append(bx("Dark", x - 0.4, x + 0.4, y0 + (y1 - y0) * 0.2, y1 - (y1 - y0) * 0.2, z0 + h * 0.55,
                          z0 + h * 0.85, 0.2))
    if front:
        out.append(bx("Metal", x0 + 1.2, x1 - 1.2, y1 - 0.2, y1 + 0.8, z0 + 0.8, z0 + (z1 - z0) * 0.35, 0.3))
    if lean:
        c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        for o in out:
            turn(o, lean, "Y", c)
    return out


def barnacles(pts, r=1.1):
    """Little barnacle cones (pale) clustered on stone."""
    out = []
    for k, p in enumerate(pts):
        rr = r * (0.7 + 0.3 * ((k * 37) % 5) / 4)
        out.append(cy("Hazard", rr, rr * 0.45, rr * 1.1, (p[0], p[1], p[2] + rr * 0.4), "Z", 6))
    return out


def gear(at, r, depth, axis="X", teeth=10, region="Paint"):
    """A gear wheel: a disc with square teeth round the rim and a dark axle (built round z, then turned)."""
    out = [cy(region, r, r, depth, (0, 0, 0), "Z", max(teeth, 10))]
    for k in range(teeth):
        t = bx(region, r - 0.2, r + 1.4, -0.9, 0.9, -depth / 2, depth / 2, 0)
        turn(t, 360 * k / teeth, "Z")
        out.append(t)
    out.append(cy("Dark", r * 0.3, r * 0.3, depth + 0.6, (0, 0, 0), "Z", 8))
    for o in out:
        if axis == "X":
            turn(o, 90, "Y")
        elif axis == "Y":
            turn(o, 90, "X")
        move(o, at)
    return out


def P(role, shape, size, at, rot=(0, 0, 0), color=(200, 200, 200), mat="SmoothPlastic"):
    """One fallback part (Roblox axes: x, up, z with -z the front; rot is CFrame.Angles in degrees)."""
    return {"role": role, "shape": shape, "size": size, "at": at, "rot": rot, "color": color, "mat": mat}


# ================================================================ RustjawPrime: the Junkyard Titan (110 studs)
# A titan a mad scrapper bolted together from wrecked cars: crushed car bodies for legs, chest and arms, tyres for
# knees, shoulders and neck, a chrome bumper jaw, headlight eyes, exhaust-pipe smokestacks, a scrapyard crane arm
# with a claw, glowing weld seams that spit sparks. Bright patchwork car paints over rust.
RUST = (196, 98, 48)
TEAL = (62, 168, 178)
CREAM = (238, 218, 168)
CHERRY = (214, 64, 52)
CHROME = (196, 202, 212)
TYRE = (40, 38, 44)
CRANE = (250, 196, 40)


def rustjaw():
    b = Boss("RustjawPrime", {
        "Paint": (TEAL, 0.45, 0.1),       # teal car paint
        "Paint2": (CREAM, 0.45, 0.05),    # cream car paint
        "Metal": (CHROME, 0.28, 1.0),     # chrome bumpers, hubs, pipes
        "Dark": (TYRE, 0.75, 0.0),        # tyres, windows, joints
        "Hazard": (CRANE, 0.5, 0.0),      # crane yellow and hazard stripes
        "Accent": (CHERRY, 0.45, 0.05),   # cherry-red car paint
    }, [(200, 236, 255), (255, 140, 40), (255, 52, 48)], ("Cannon", "CannonGlow"))
    b.look = "the Junkyard Titan: a giant bolted together from wrecked cars"
    b.theme = (255, 170, 60)  # welding orange: the entrance and name card
    b.debris = RUST
    H = "Hull"
    for s in (-1, 1):
        x = s * 14
        paint = "Paint" if s < 0 else "Accent"
        # feet: a crushed car each, its nose forward, two tyres on the outside and a chrome bumper toe
        b.add(H, car(paint, x - 9, x + 9, -11, 15, 0.6, 9.6, windows=True))
        b.add(H, bx("Metal", x - 9.6, x + 9.6, 15, 17.6, 0.4, 4.0, 0.8, 2))
        for y in (-5, 8):
            b.add(H, tyre((x + s * 9.4, y, 4.6), "X", 3.4, 1.5))
        # shins: a car stood on its nose, a door each side (Plates2), and a back piston
        b.add(H, car("Paint2" if s < 0 else "Paint", x - 6.4, x + 6.4, -6.2, 6.2, 9, 27, windows=True, front=False))
        b.add(H, cy("Metal", 1.3, 1.3, 16, (x + s * 2, -8, 18), "Z", 8))
        b.add(H, cy("Dark", 2.0, 2.0, 3, (x + s * 2, -8, 9.5), "Z", 8))
        # the knee: a big tyre facing forward on a dark axle; the hub glows gold (a weak point)
        b.add(H, cy("Dark", 5.4, 5.4, 14.5, (x, 0, 30), "X", 14))
        b.add(H, ring("Dark", 5.4, 2.1, (x, 5.6, 30), "Y", 16, 5))
        b.add(H, ring("Metal", 3.6, 0.6, (x, 7.2, 30), "Y", 14, 4))
        b.lamp("knee" + ("L" if s < 0 else "R"), (x, 8.0, 30), 3.2)
        # thighs: crushed car slabs, slightly askew, a tyre for the hip
        b.add(H, car("Accent" if s < 0 else "Paint2", x - 7, x + 7, -7, 7, 33, 46, windows=True, lean=s * 4, front=False))
        b.add(H, ring("Dark", 5.4, 2.4, (x * 0.95, 0, 48), "X", 14, 5))
        b.add(H, cy("Metal", 3.4, 3.4, 5, (x * 0.95, 0, 48), "X", 10))
        # Plates2: car doors bolted over the shins (they come off at 66%)
        b.add("Plates2", bx("Accent" if s < 0 else "Paint2", x - 5.8, x + 5.8, 6.0, 8.0, 11, 25, 0.6, 2))
        b.add("Plates2", bx("Dark", x - 4.6, x + 4.6, 7.9, 8.5, 19.5, 24, 0.2))  # the door's window
        b.add("Plates2", bx("Metal", x + s * 2.4, x + s * 4.6, 8.0, 8.8, 17, 18, 0.2))  # the handle
    # the pelvis: an engine block on an axle, a chrome bumper belt with hazard stripes
    b.add(H, bx("Metal", -17, 17, -10, 10, 44, 54, 1.4, 2))
    b.add(H, cy("Dark", 2.6, 2.6, 38, (0, 0, 48), "X", 10))
    b.add(H, hazard(-14, 14, 46, 50.6, 10.2, 7, facing=1))
    # the chest: three crushed cars stacked into a heroic wedge (teal, cherry, cream), leaning a little each way
    b.add(H, bx("Paint", -21, 21, -12, 13, 52, 64, 1.6, 2, taper=(1.08, 1.0)))
    b.add(H, car("Accent", -23.5, 23.5, -13.5, 14, 63, 76, windows=True, lean=-3))
    b.add(H, car("Paint2", -25.5, 25.5, -14, 14.5, 75.5, 89, windows=True, lean=2.5))
    # glowing weld seams between the cars (phase glow; the sparks fly from them)
    for z, lean in ((63.4, -3), (75.6, 2.5)):
        seam = tube("Lamp", [(-23, 14.6, z), (-8, 15.4, z + 0.3), (8, 15.4, z - 0.3), (23, 14.6, z)], [0.55] * 4, 6)
        turn(seam, lean, "Y", (0, 0, z))
        b.add("Glow", seam)
    # the core: an engine heart behind a chrome radiator grille in the middle car (a weak point)
    b.add(H, bx("Metal", -10, 10, 13.5, 16.2, 62.5, 81.5, 0.8, 2))
    b.add(H, bx("Dark", -8.4, 8.4, 15.8, 16.8, 64, 80, 0.2))
    for k in range(6):
        xk = -7 + k * 2.8
        if abs(xk) > 4.5:
            b.add(H, bx("Metal", xk - 0.45, xk + 0.45, 16.4, 17.4, 64.4, 79.6, 0.15))
    b.add(H, ring("Metal", 6.6, 1.2, (0, 17.4, 72), "Y", 20, 5))
    b.lamp("core", (0, 18.6, 72), 5.0, (1, 0.62, 1))
    # tail lights on the chest's flanks (phase glow)
    for s in (-1, 1):
        for k in range(2):
            b.add("Glow", bx("Lamp", s * 25.8 - 0.4, s * 25.8 + 0.4, 6 + k * 4, 9 + k * 4, 81, 83.5, 0))
    # Plates2: hood panels over the belly; Plates3: car doors over the chest (rising to the shoulders)
    for row in range(2):
        z0 = 53.5 + row * 4.8
        b.add("Plates2", bx("Paint", -12, 12, 13.2 - row * 0.3, 15.8 - row * 0.3, z0, z0 + 4.2, 0.7, 2))
    for s in (-1, 1):
        pec = bx("Paint" if s < 0 else "Accent", min(s * 11, s * 24), max(s * 11, s * 24), 14.2, 17.0, 77, 88, 0.8, 2)
        shear(pec, lambda v: Vector((v.x, v.y, v.z + (abs(v.x) - 11) * 0.12)))
        b.add("Plates3", pec)
        b.add("Plates3", bx("Dark", min(s * 13, s * 22), max(s * 13, s * 22), 16.8, 17.5, 83.6, 87.4, 0.2))
        b.add("Plates3", rivets("Metal", [(s * 12.5, 17.4, 79), (s * 23, 17.4, 80.5)], 0.6))
    # the back: an engine block pack with four exhaust pipes curling up into smokestacks (glowing rims)
    b.add(H, bx("Metal", -15, 15, -22, -12, 58, 84, 1.6, 2))
    b.add(H, hazard(-10, 10, 62, 66.5, -22.2, 5, facing=-1))
    for s in (-1, 1):
        for k, (dx, top) in enumerate(((5.5, 106), (11.5, 100))):
            xp = s * dx
            b.add(H, tube("Metal", [(xp, -16, 74), (xp, -21, 80), (xp * 1.05, -21.5, 90), (xp * 1.1, -20, top)],
                          [1.9, 1.9, 2.0, 2.3], 10))
            b.add(H, ring("Dark", 2.2, 0.55, (xp * 1.08, -20.6, 92), "Z", 10, 4))
            b.add("Glow", ring("Lamp", 2.2, 0.5, (xp * 1.1, -20, top + 0.2), "Z", 10, 4))
    # the neck: two tyres stacked flat
    for z in (89.5, 92.5):
        b.add(H, ring("Dark", 7.6, 2.0, (0, 1, z), "Z", 16, 5))
    # the head: a car's front end: the hood with a windscreen, angry hood edges, two round headlight eyes in chrome
    # rings, side mirrors for ears and a radio aerial with a blinker
    b.add(H, bx("Paint", -12, 12, -7, 12.5, 93, 106, 1.6, 2, taper=(0.9, 0.82)))
    b.add(H, bx("Dark", -9.5, 9.5, -6, 2, 104.6, 108.8, 0.8, 2, taper=(0.84, 0.7)))  # the windscreen cab
    brow = bx("Paint2", -12.8, 12.8, 9.0, 14.2, 102.8, 105.8, 0.8, 2)
    shear(brow, lambda v: Vector((v.x, v.y, v.z + (abs(v.x) / 12.8) * 2.6 - 1.6)))  # an angry V of hood edge
    b.add(H, brow)
    for s in (-1, 1):
        b.add(H, ring("Metal", 3.4, 0.8, (s * 6.2, 12.9, 99.6), "Y", 16, 5))
        b.add("Glow", cy("Lamp", 2.8, 2.8, 0.8, (s * 6.2, 13.2, 99.6), "Y", 14))
        b.add(H, beam("Metal", (s * 11.6, 2, 101), (s * 15.4, 3, 103.5), 0.8, 0.8, 0.2, 1))  # mirror stalks
        b.add(H, bx("Paint2", min(s * 14.4, s * 17.6), max(s * 14.4, s * 17.6), 1.4, 4.4, 102.2, 105.4, 0.6, 1))
    # the bumper jaw: a big chrome underbite with grille-bar teeth and a blank plate (no text), two exhaust tusks
    b.add(H, bx("Metal", -15, 15, -2, 20.5, 84.5, 93.6, 1.8, 2, taper=(1.0, 0.95)))
    b.add(H, bx("Paint2", -4.4, 4.4, 20.4, 21.2, 86.2, 89.6, 0.3))
    b.add(H, hazard(-13, -6, 86, 90.4, 20.6, 3, facing=1))
    b.add(H, hazard(6, 13, 86, 90.4, 20.6, 3, facing=1))
    for k in range(5):
        xk = -8 + k * 4
        b.add(H, spike("Paint2", (xk, 17.2, 93.2), (xk, 17.5, 97.4), 1.4, 4))
    for s in (-1, 1):
        b.add(H, spike("Metal", (s * 12.4, 16.4, 93.2), (s * 13.6, 17.2, 100.4), 1.9, 6))
        b.add(H, cy("Dark", 2.6, 2.6, 2.0, (s * 15.2, 2, 90), "X", 12))  # jaw hinges
    b.add(H, tube("Metal", [(7, -4, 106), (8.2, -6, 114), (9, -7.6, 119)], [0.6, 0.5, 0.4], 6))
    b.add("Glow", ball("Lamp", 1.3, (9.1, -7.8, 119.6)))
    # shoulders: a tyre pauldron each (tilted out) on a dark joint; the cannons sit on top
    for s in (-1, 1):
        xs = s * 27
        b.add(H, ball("Dark", 7.6, (xs, 0, 82), segs=14, rings=8))
        t = tyre((0, 0, 0), "Z", 9.0, 3.4)
        for o in t:
            turn(o, s * -18, "Y")
            move(o, (xs, 0, 85.5))
        b.add(H, t)
    # the left arm: a car-slab upper arm, a tyre elbow, a crushed-car forearm and a wrecking fist of a car block
    # with exhaust-tip knuckles
    b.add(H, beam("Accent", (-29, 0, 80), (-32, -1, 59), 10, 10, 1.2, 2, 0.9))
    b.add(H, tyre((-32, -1, 58), "X", 5.0, 2.2, hub=False))
    b.add(H, ball("Dark", 4.6, (-32, -1, 58)))
    b.add(H, beam("Paint", (-32, -1, 58), (-33, 1, 41), 11, 11, 1.4, 2, 1.2))
    b.add(H, hazard(-39.6, -26.4, 42, 45.4, 7.4, 4, facing=1))
    b.add("Plates3", beam("Paint2", (-37.6, -1, 56), (-39.2, 1, 44), 2, 9, 0.5, 1))
    b.add(H, car("Paint2", -42, -24, -8, 10, 24, 40, windows=True, front=False))
    for k in range(4):
        z = 26.5 + k * 3.8
        b.add(H, cy("Metal", 1.3, 1.5, 5, (-33, 12, z + 0.8), "Y", 8))
    # the right arm: a scrapyard crane arm: a yellow lattice boom with a hydraulic ram, a cab plate (Plates3) and a
    # three-fingered grab claw on a chrome hub
    sh_, el, wr = Vector((29, 0, 80)), Vector((33, -2, 60)), Vector((34, 2, 41))
    for dx in (-3.2, 3.2):
        b.add(H, beam("Hazard", sh_ + Vector((dx, 0, 0)), el + Vector((dx, 0, 0)), 1.6, 3.4, 0.3, 1))
        b.add(H, beam("Hazard", el + Vector((dx, 0, 0)), wr + Vector((dx * 0.8, 0, 0)), 1.6, 3.4, 0.3, 1))
    for k in range(4):
        f0, f1 = k / 4, (k + 1) / 4
        a = sh_.lerp(el, f0) + Vector((-3.2, 0, 0))
        c = sh_.lerp(el, f1) + Vector((3.2, 0, 0))
        b.add(H, beam("Hazard", a, c, 0.8, 1.2, 0.0, 1))
        a2 = el.lerp(wr, f0) + Vector((2.6, 0, 0))
        c2 = el.lerp(wr, f1) + Vector((-2.6, 0, 0))
        b.add(H, beam("Hazard", a2, c2, 0.8, 1.2, 0.0, 1))
    b.add(H, cy("Dark", 4.2, 4.2, 9, (33, -2, 60), "X", 14))  # the elbow pivot
    b.add(H, beam("Metal", (31, 5, 74), (34, 6, 49), 1.6, 1.6, 0.3, 1))  # the hydraulic ram
    b.add(H, beam("Dark", (31, 5, 76), (32.5, 5.5, 62), 2.6, 2.6, 0.4, 1))
    b.add("Plates3", bx("Hazard", 26.5, 37.5, -5.5, 5.5, 64, 72, 0.6, 2))  # the crane cab plate
    b.add("Plates3", bx("Dark", 27.5, 36.5, 5.3, 5.9, 66.5, 70.5, 0.2))
    b.add(H, cy("Metal", 5.0, 5.0, 4.6, (34, 1.5, 38.6), "Z", 14))
    for k, (dx, dy) in enumerate(((-5, 3.5), (0, 6), (5, 3.5))):
        x0 = 34 + dx * 0.7
        b.add(H, tube("Dark", [(x0, 1.5 + dy * 0.5, 36.6), (x0 + dx * 0.4, 1.5 + dy, 32), (x0 + dx * 0.45, 2 + dy, 26.5),
                               (x0 + dx * 0.2, 1.5 + dy * 0.6, 22.5)], [1.8, 1.6, 1.2, 0.2], 8))
    # the shoulder cannon (one, set by the game on each shoulder; anchor at the origin): a junk launcher of an
    # engine block on a tyre, twin exhaust-pipe barrels aimed forward and up, a hazard band
    c = []
    c += tyre((0, 0, -2.6), "Z", 5.6, 2.0, hub=False)
    c.append(bx("Metal", -5, 5, -4.4, 5.6, -1.2, 5.4, 1.0, 2, taper=(0.9, 0.9)))
    for k in (-1, 1):
        barrel = cy("Metal", 1.9, 2.2, 17, (0, 0, 8.5), "Z", 10)
        muzzle = ring("Dark", 2.3, 0.6, (0, 0, 16.6), "Z", 10, 4)
        for o in (barrel, muzzle):
            turn(o, -66, "X")
            move(o, (k * 2.4, 2.5, 2.6))
            c.append(o)
    c.append(hazard(-4.4, 4.4, 0.4, 2.6, 5.7, 4, 0.4, facing=1))
    b.add("Cannon", c)
    b.add("CannonGlow", ball("Lamp", 2.4, (0, -2.4, 4.0)))
    b.objective_lamp = Vector((0, -2.4, 4.0))
    # the welding sparks fly from the seams, the crane claw and the exhaust tips (Roblox axes from the feet)
    b.fx = {"kind": "sparks", "every": 0.6, "at": [(-18, 63.4, -14.6), (18, 63.4, -14.6), (-16, 75.6, -15.0),
                                                   (16, 75.6, -15.0), (34, 30, -4), (-12, 106, 20), (12, 100, 21)]}
    # the part-built look until the meshes are imported (23 parts, as before)
    b.parts = []
    for s in (-1, 1):
        b.parts += [
            P("body", "Block", (16, 9, 26), (s * 14, 4.6, -2), color=TEAL if s < 0 else CHERRY),
            P("body", "Block", (11, 38, 11), (s * 14, 27, 0), color=CREAM if s < 0 else TEAL),
            P("weak", "Ball", (5, 5, 5), (s * 14, 30, -7.6)),
        ]
    b.parts += [
        P("body", "Block", (48, 42, 28), (0, 68, 0), color=CHERRY),
        P("weak", "Ball", (7, 7, 7), (0, 72, -17.6)),
        P("body", "Block", (24, 13, 20), (0, 99.5, -2.6), color=TEAL),
        P("body", "Block", (30, 9, 23), (0, 89, -9), color=CHROME, mat="Metal"),
        P("glow", "Cylinder", (1, 5.6, 5.6), (-6.2, 99.6, -13), rot=(0, 90, 0)),
        P("glow", "Cylinder", (1, 5.6, 5.6), (6.2, 99.6, -13), rot=(0, 90, 0)),
        P("body", "Block", (10, 34, 10), (-31, 62, -1), rot=(0, 0, -6), color=CREAM),
        P("body", "Block", (18, 16, 18), (-33, 32, -1), color=TEAL),
        P("body", "Block", (6, 44, 6), (32, 61, 1), rot=(0, 0, 5), color=CRANE),
        P("body", "Block", (10, 12, 10), (34, 34, -1.5), color=TYRE),
        P("body", "Cylinder", (30, 5, 5), (0, 92, 20), rot=(0, 0, 90), color=CHROME, mat="Metal"),
    ]
    b.objective_parts = [
        P("objective", "Cylinder", (4, 11, 11), (0, -2.6, 0), rot=(0, 0, 90), color=TYRE),
        P("objective", "Cylinder", (16, 4.2, 4.2), (0, 4.6, -5.2), rot=(0, 90, 66), color=CHROME, mat="Metal"),
        P("objectiveGlow", "Ball", (3.4, 3.4, 3.4), (0, 4, 2.4)),
    ]
    return b


# ================================================================ LumenMaw: the Light Eater (a night creature)
# A sleek dark creature that eats light: a long panther-low body, bioluminescent stripes down its back and flanks,
# three glowing light sacs on stalks over its shoulders (the weak points; ids crystalA..C), and a huge maw that
# swallows light: a glowing throat vortex with light streams curving into it. Its pit's three stolen lights (the
# generators) feed it. A creature, but cartoon: no blood ever; it bursts into light motes.
NIGHT = (38, 32, 78)
DEEP = (20, 18, 42)
BONE = (232, 236, 250)
VIOLET = (110, 80, 186)
BIO = (90, 240, 230)


def maw():
    b = Boss("LumenMaw", {
        "Paint": (NIGHT, 0.35, 0.0),     # sleek indigo hide
        "Paint2": (DEEP, 0.4, 0.0),      # the deep night belly and shell
        "Metal": (BONE, 0.38, 0.0),      # pale fangs and claws
        "Dark": ((14, 12, 26), 0.6, 0.0),
        "Hazard": (VIOLET, 0.4, 0.0),    # violet ridges
        "Accent": ((150, 120, 230), 0.35, 0.0),
    }, [BIO, (186, 110, 255), (255, 70, 150)], ("Generator", "GeneratorCore"))
    b.look = "the Light Eater: a sleek night creature that swallows light"
    b.theme = BIO
    b.debris = (150, 120, 230)
    H = "Hull"
    # the body: a long sleek loft along y, low at the hips, the shoulders high (tail at the back)
    body = [(-44, 6, 6, 0, 26), (-34, 11, 10, 0, 28), (-20, 14.5, 12, 0, 31), (-6, 16, 13.5, 0, 35),
            (8, 16, 13.5, 0, 37), (18, 13.5, 11.5, 0, 37), (24, 10, 9, 0, 38)]
    b.add(H, loft_y("Paint", body, segs=28, power=2.2))

    def prof(y):
        for (y0, rx0, rz0, _, z0), (y1, rx1, rz1, _, z1) in zip(body, body[1:]):
            if y0 <= y <= y1:
                f = (y - y0) / (y1 - y0)
                return rx0 + (rx1 - rx0) * f, rz0 + (rz1 - rz0) * f, z0 + (z1 - z0) * f
        return body[-1][1], body[-1][2], body[-1][4]

    def on(y, a, out=1.02):
        """A point on the body's surface at y and angle a (0 = the side, 90 = the top)."""
        rx, rz, cz = prof(y)
        return (rx * math.cos(math.radians(a)) * out, y, cz + rz * math.sin(math.radians(a)) * out)

    b.add(H, loft_y("Paint2", [(y, rx * 0.8, rz * 0.6, 0, cz - rz * 0.42) for y, rx, rz, _, cz in body[1:-1]], segs=20,
                    power=2.2))  # the dark belly
    # bioluminescent stripes: a dorsal line and three sweeping stripes down each flank (phase glow)
    b.add("Glow", tube("Lamp", [on(y, 90, 1.0) for y in (-40, -30, -18, -6, 6, 16, 22)], [0.8, 1.2, 1.3, 1.3, 1.3, 1.2, 0.7], 6))
    for s in (-1, 1):
        for y0 in (-30, -14, 2):
            pts = [on(y0 + 7 * t, s * 0 + (70 - 70 * t) if s > 0 else 180 - (70 - 70 * t), 1.0) for t in (0, 0.33, 0.66, 1.0)]
            b.add("Glow", tube("Lamp", pts, [1.2, 1.0, 0.8, 0.25], 6))
    # ridges of violet along the spine
    for k, y in enumerate((-34, -24, 14, 20)):
        p = on(y, 90, 0.98)
        b.add(H, spike("Hazard", p, (0, y - 4, p[2] + 4.5 - k * 0.4), 1.8, 5))
    # the three light sacs over the shoulders (weak points; Config.Boss crystalA..C) on dark stalks with collars
    for tid, at in (("crystalA", (-12, -8, 58)), ("crystalB", (0, -16, 62)), ("crystalC", (12, -8, 58))):
        x, y, z = at
        root = Vector(on(y, 90, 0.92)) + Vector((x * 0.7, 0, 0))
        mid = Vector((x, y, z))
        b.add(H, tube("Paint2", [root, root.lerp(mid, 0.5) + Vector((0, 1.5, 0)), mid - Vector((0, 0, 4.2))], [2.6, 1.6, 1.4], 8))
        b.add(H, ring("Hazard", 2.6, 0.7, tuple(mid - Vector((0, 0, 3.8))), "Z", 12, 4))
        b.add("Weak", ball("Lamp", 3.4, tuple(mid), (1, 1, 1.25), 14, 9))
        b.weak[tid] = mid
    # Plates2: dark shell plates over the flanks (66%); Plates3: the brow and shoulder plates (33%)
    for s in (-1, 1):
        for y0 in (-26, -10, 6):
            pl = loft_y("Paint2", [(y0, 1.8, 6.0, 0, 0), (y0 + 12, 1.8, 6.0, 0, 0)], segs=12, power=2.2)
            rx, rz, cz = prof(y0 + 6)
            move(pl, (s * (rx + 1.4), 0, cz + 2))
            turn(pl, s * -10, "Y", (s * (rx + 1.4), 0, cz + 2))
            b.add("Plates2", pl)
            b.add("Plates2", bx("Hazard", s * (rx + 3.6) - 0.4, s * (rx + 3.6) + 0.4, y0 + 1, y0 + 11, cz + 5.6, cz + 6.4, 0))
    for s in (-1, 1):
        pad = loft("Paint2", [(0, 7, 8, 0, 0), (2.4, 7.6, 8.6, 0, 0), (4.2, 5.4, 6.2, 0, 0)], segs=16, power=2.4)
        turn(pad, s * 60, "Y")
        move(pad, (s * 17, 14, 40))
        b.add("Plates3", pad)
        brow = bx("Paint2", min(s * 3, s * 15), max(s * 3, s * 15), 34, 44, 51, 53.6, 0.8, 2)
        shear(brow, lambda v, s=s: Vector((v.x, v.y, v.z - (abs(v.x) - 3) * 0.22)))
        b.add("Plates3", brow)
    # the head: almost all maw: a sleek upper skull, a wide jaw dropped open, rows of pale fangs, four slit eyes
    b.add(H, loft_y("Paint", [(18, 13, 10, 0, 42), (28, 16.5, 10, 0, 44.5), (40, 17, 8.5, 0, 45), (50, 14, 6, 0, 43.5),
                              (55, 9, 3.6, 0, 42)], segs=26, power=2.3))
    b.add(H, loft_y("Paint", [(16, 12, 5, 0, 26), (30, 15.5, 5.6, 0, 22.5), (44, 15, 4.4, 0, 18.5), (52, 10, 3, 0, 18)],
                    segs=24, power=2.3))
    b.add(H, loft_y("Dark", [(20, 13, 9, 0, 32.5), (34, 14, 9.6, 0, 31.5), (46, 12.4, 8.4, 0, 30.5), (49, 11, 7.6, 0, 30.4)],
                    segs=22, power=2.2))  # the mouth's dark inside
    # the throat vortex: glowing rings sinking into the throat (phase glow) and a bright core
    for k in range(4):
        b.add("Glow", ring("Lamp", 7.6 - k * 1.7, 0.55, (0, 44 - k * 4.5, 31), "Y", 22, 4))
    b.add("Glow", ball("Lamp", 2.8, (0, 28, 31), (1, 0.5, 1)))
    # light streams curving in from around the jaws to the throat (phase glow)
    for k in range(8):  # a spiral funnel: each stream winds in as it nears the mouth
        a0 = math.radians(k * 45)
        r0 = 13 + (k % 2) * 3
        pts = []
        for t in (0, 0.25, 0.5, 0.75, 1.0):
            ang = a0 + t * 2.4
            r = r0 * (1 - t) + 1.5
            pts.append((math.cos(ang) * r, 44 + 18 * (1 - t), 31 + math.sin(ang) * r * 0.75))
        b.add("Glow", tube("Lamp", pts, [0.08, 0.35, 0.55, 0.65, 0.45], 5))
    for k in range(9):  # upper fangs round the skull's rim, lower fangs on the jaw
        a = (k - 4) / 4.0
        xk = a * 14
        yk = 51 - abs(a) ** 2 * 11
        ln = 6.4 - abs(a) * 2.4
        b.add(H, spike("Metal", (xk, yk, 38.6), (xk, yk + 0.8, 38.6 - ln), 1.5, 5))
        b.add(H, spike("Metal", (xk * 0.92, yk - 2.4, 21.6), (xk * 0.92, yk - 1.8, 21.6 + ln * 0.8), 1.3, 5))
    for s in (-1, 1):
        for k, (dx, dy, w) in enumerate(((6, 40, 5.4), (11, 33, 3.6))):
            eye = bx("Lamp", min(s * dx, s * (dx + w)), max(s * dx, s * (dx + w)), dy, dy + 1.6, 49.4 - k, 50.8 - k, 0)
            shear(eye, lambda v, dx=dx, dy=dy: Vector((v.x, v.y - (abs(v.x) - dx) * 0.5, v.z + (abs(v.x) - dx) * 0.35)))
            b.add("Glow", eye)
        b.add(H, cy("Dark", 2.4, 2.4, 3, (s * 15.6, 20, 32), "X", 12))  # jaw hinges
        # swept ear fins
        b.add(H, beam("Hazard", (s * 12, 22, 48), (s * 20, 12, 57), 1.2, 6, 0.3, 1, 0.3))
    # four long legs (shoulders high, paws with pale claws) and a long curling tail with a glowing tip
    for s in (-1, 1):
        for y, dy in ((12, 5), (-26, -6)):  # the front knees forward, the back hocks back, like a big cat
            sh = (s * 13, y, 32)
            kn = (s * 18, y + dy, 17)
            ft = (s * 16, y + 2, 3)
            b.add(H, ball("Paint", 7.0, sh))
            b.add(H, beam("Paint", sh, kn, 8, 8, 1.4, 2, 0.8))
            b.add(H, ball("Paint2", 4.0, kn))
            b.add(H, beam("Paint", kn, ft, 6.4, 6.4, 1.2, 2, 0.75))
            b.add(H, bx("Paint2", ft[0] - 4.6, ft[0] + 4.6, ft[1] - 4.6, ft[1] + 4.6, 0, 3.4, 1.4, 2))
            for k in (-1, 0, 1):
                b.add(H, spike("Metal", (ft[0] + k * 2.8, ft[1] + 4, 1.6), (ft[0] + k * 3.4, ft[1] + 8.4, 0.4), 1.2, 5))
            b.add("Glow", tube("Lamp", [(kn[0] * 1.04, kn[1] + 1, kn[2] + 4), (ft[0] * 1.08, ft[1] + 2, 8)], [0.5, 0.3], 5))
    tail = [(0, -42, 27), (0, -54, 25), (0, -64, 27), (0, -73, 32), (0, -79, 39), (-2, -81, 46)]
    b.add(H, tube("Paint", tail, [5.4, 4.4, 3.4, 2.6, 1.8, 1.0], 12))
    b.add("Glow", tube("Lamp", [(0, -56, 29.6), (0, -66, 31), (0, -74, 35.4), (-1, -79.6, 41.4)], [0.6, 0.7, 0.6, 0.3], 6))
    b.add("Glow", ball("Lamp", 2.4, (-2.4, -81.4, 47.6)))
    # the generator (one; the game stands one at each point round the pit; its foot at the origin): a stolen light,
    # a dark standing stone with violet bands and a glowing orb held in pale prongs. Its core sits inside the
    # generator's hit sphere (8 studs up, BossSim)
    g = []
    g.append(bx("Paint2", -6.5, 6.5, -6.5, 6.5, 0, 2.6, 0.8, 2))
    g.append(cy("Paint", 4.4, 3.0, 7.4, (0, 0, 6.2), "Z", 6))
    g.append(ring("Hazard", 4.1, 0.6, (0, 0, 4.4), "Z", 6, 4))
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 6
        g.append(tube("Metal", [(math.cos(a) * 2.6, math.sin(a) * 2.6, 9.4), (math.cos(a) * 4.6, math.sin(a) * 4.6, 12),
                                (math.cos(a) * 2.2, math.sin(a) * 2.2, 16)], [1.0, 0.8, 0.15], 6))
    b.add("Generator", g)
    b.add("GeneratorCore", ball("Lamp", 3.2, (0, 0, 12)))
    b.objective_lamp = Vector((0, 0, 12))
    # light streams pulled into the maw (from a ring round the mouth) and the area dims round it
    b.fx = {"kind": "light", "every": 0.12, "at": [(0, 31, -44)], "reach": 34, "dim": 0.22}
    # the part-built look until the meshes are imported (13 parts and 2 a generator, as before)
    b.parts = [
        P("body", "Block", (32, 32, 60), (0, 34, 10), color=NIGHT),
        P("body", "Block", (32, 13, 28), (0, 45, -32), color=NIGHT),
        P("body", "Block", (28, 4, 24), (0, 22.5, -34), rot=(-14, 0, 0), color=DEEP),
        P("glow", "Cylinder", (1, 12, 12), (0, 31, -44), rot=(0, 90, 0)),
        P("glow", "Block", (16, 2, 1), (0, 48.6, -46), rot=(0, 0, 0)),
        P("glow", "Block", (2, 1, 60), (0, 48.4, 10)),
    ]
    for s in (-1, 1):
        for y in (-12, 24):
            b.parts.append(P("body", "Block", (7, 24, 7), (s * 16, 11, y), color=NIGHT))
    # the light sacs as glowing stalks standing on the back (each centre inside its hit sphere)
    for at, length in (((-12, 55, 8), 12), ((0, 58, 16), 16), ((12, 55, 8), 12)):
        b.parts.append(P("weak", "Cylinder", (length, 5, 5), at, rot=(0, 0, 90)))
    b.objective_parts = [
        P("objective", "Block", (7, 10, 7), (0, 5, 0), rot=(0, 45, 0), color=DEEP),
        P("objectiveGlow", "Ball", (5, 5, 5), (0, 12, 0)),
    ]
    return b


# ================================================================ LeviathanEngine: the Deep Machine
# An ancient sea machine of brass and stone, older than the city: a barnacled stone hull ringed with brass bands
# and portholes running back under the water, brass gear wheels on its flanks, a neck of stacked gear rings rising
# to a brass diving-bell head with porthole eyes (weak points), stone jaws, and a tide-turbine heart on its back
# (the reactor weak point) between two bronze vent hatches (the objectives).
BRASS = (204, 152, 64)
STONE = (92, 108, 100)
VERDI = (86, 168, 148)
BARN = (232, 226, 206)
AQUA = (80, 230, 255)


def leviathan():
    b = Boss("LeviathanEngine", {
        "Paint": (BRASS, 0.34, 0.85),    # old brass
        "Paint2": (STONE, 0.85, 0.0),    # sea-worn stone
        "Metal": (VERDI, 0.45, 0.55),    # verdigris bronze
        "Dark": ((28, 34, 40), 0.6, 0.2),
        "Hazard": (BARN, 0.9, 0.0),      # barnacles
        "Accent": ((96, 140, 84), 0.7, 0.0),  # sea moss
    }, [AQUA, (255, 172, 60), (255, 60, 48)], ("Bay", "BayGlow"))
    b.look = "the Deep Machine: an ancient brass-and-stone sea machine"
    b.theme = AQUA
    b.debris = BRASS
    H = "Hull"
    # the hull: a long stone body running back and down under the water (the surface is z = 0)
    hull_rings = [(22, 9, 8, 0, -1), (10, 15, 12, 0, 2), (-8, 16.5, 13, 0, 2.5), (-28, 15.5, 12, 0, 0),
                  (-52, 13, 10, 0, -6), (-78, 10.5, 8, 0, -13), (-102, 8, 6, 0, -21), (-124, 5, 4, 0, -28),
                  (-140, 2.6, 2.2, 0, -33)]
    b.add(H, loft_y("Paint2", hull_rings, segs=26, power=2.4))

    def ring_at(y):
        for (y0, rx0, rz0, _, z0), (y1, rx1, rz1, _, z1) in zip(hull_rings, hull_rings[1:]):
            if y1 <= y <= y0:
                f = (y0 - y) / (y0 - y1)
                return rx0 + (rx1 - rx0) * f, rz0 + (rz1 - rz0) * f, z0 + (z1 - z0) * f
        return hull_rings[-1][1], hull_rings[-1][2], hull_rings[-1][4]

    # brass bands ringing the hull, with portholes between them along the waterline (phase glow)
    for y in (4, -18, -40, -64, -90, -114):
        rx, rz, z = ring_at(y)
        b.add(H, loft_y("Paint", [(y - 1.4, rx + 0.5, rz + 0.5, 0, z), (y + 1.4, rx + 0.5, rz + 0.5, 0, z)], segs=26, power=2.4))
    for s in (-1, 1):
        for y in (-7, -29, -52, -77):
            rx, rz, z = ring_at(y)
            p = (s * (rx * 0.97), y, z + rz * 0.28)
            b.add(H, ring("Paint", 2.0, 0.55, p, "X", 12, 4))
            b.add("Glow", cy("Lamp", 1.6, 1.6, 0.6, (p[0] + s * 0.2, p[1], p[2]), "X", 10))
    # barnacle clusters and moss on the stone
    pts = []
    for s in (-1, 1):
        for y, a in ((-14, 50), (-22, 30), (-36, 62), (-46, 40), (-60, 55), (-70, 25), (-86, 48)):
            rx, rz, z = ring_at(y)
            for k in range(3):
                pts.append((s * rx * math.cos(math.radians(a + k * 7)) * 0.98, y + k * 1.6,
                            z + rz * math.sin(math.radians(a + k * 7)) * 0.98))
    b.add(H, barnacles(pts))
    for s in (-1, 1):
        b.add(H, bx("Accent", s * 12 - 2, s * 12 + 2, -34, -22, 9.5, 11.6, 0.6, 1))
    # brass gear wheels turning on the flanks (one big, one small a side)
    for s in (-1, 1):
        b.add(H, gear((s * 16.4, -16, 3), 7.5, 2.4, "X", 12))
        b.add(H, gear((s * 14.6, -34, 6.5), 4.6, 2.0, "X", 9, "Metal"))
    # stone dorsal fins down the back, barnacled
    def hull_top(y):
        rx, rz, z = ring_at(y)
        return z + rz

    for k, y in enumerate((-54, -74, -94)):
        fin = bx("Paint2", -1.0, 1.0, y - 9, y + 3, 0, 9 - k * 1.5, 0.4)
        shear(fin, lambda v: Vector((v.x, v.y - v.z * 0.7, v.z)))
        move(fin, (0, 0, hull_top(y) - 1.5))
        b.add(H, fin)
    b.add(H, barnacles([(0.8, -58, hull_top(-56) + 3), (-0.8, -78, hull_top(-76) + 2.5)], 0.9))
    # side flippers of stone with brass edges, and the tail: a tide wheel in a brass shroud
    fin = bx("Paint2", 0, 16, -6, 6, -0.9, 0.9, 0.5, 1)
    shear(fin, lambda v: Vector((v.x, v.y - v.x * 0.45, v.z - v.x * 0.12)))
    move(fin, (14, 6, 2))
    b.add(H, fin, mirror([fin]))
    b.add(H, ring("Paint", 5.4, 1.1, (0, -142, -33.5), "Y", 18, 6))
    for k in range(6):
        blade = bx("Metal", -0.5, 0.5, -0.4, 0.4, 0, 4.4, 0.2)
        turn(blade, 20, "Z")
        turn(blade, k * 60, "Y")
        move(blade, (0, -142, -33.5))
        b.add(H, blade)
    # the tide-turbine heart on the back (the reactor weak point): a brass housing with turbine blades round a gold
    # hub, in a glowing ring (phase glow)
    b.add(H, cy("Paint", 7.4, 7.4, 2.4, (0, -2, 12.4), "Z", 20))
    b.add(H, ring("Metal", 7.4, 1.1, (0, -2, 13.6), "Z", 20, 6))
    b.add("Glow", ring("Lamp", 5.6, 0.45, (0, -2, 13.8), "Z", 20, 4))
    for k in range(8):
        blade = bx("Paint", 0, 5.0, -0.9, 0.9, -0.25, 0.25, 0.1)
        turn(blade, 25, "X")
        turn(blade, k * 45, "Z")
        move(blade, (0, -2, 13.9))
        b.add(H, blade)
    b.lamp("reactor", (0, -2, 14.6), 3.4, (1, 1, 0.7))
    # the neck: stacked brass gear rings rising in an S to the head, verdigris collars between
    neck = [(0, 6, 4), (0, 13, 13), (0, 19, 24), (0, 23, 33), (0, 28, 40)]
    radii = [10.5, 9.8, 9.2, 8.6, 8.2]
    b.add(H, tube("Paint", neck, radii, 18))
    for k in range(1, 5):
        p0, p1 = Vector(neck[k - 1]), Vector(neck[k])
        c = (p0 + p1) / 2
        r = radii[k] + 0.7
        q = Vector((0, 0, 1)).rotation_difference((p1 - p0).normalized())
        collar = ring("Metal", r, 1.0, (0, 0, 0), "Z", 18, 5)
        collar.data.transform(Matrix.Translation(c) @ q.to_matrix().to_4x4())
        b.add(H, collar)
        for t in range(8):  # gear teeth round each collar
            tooth = bx("Metal", -0.8, 0.8, r + 0.4, r + 1.8, -0.8, 0.8, 0)
            turn(tooth, t * 45 + k * 22, "Z")
            tooth.data.transform(Matrix.Translation(c) @ q.to_matrix().to_4x4())
            b.add(H, tooth)
    # the head: a brass diving-bell skull with a stone brow and snout, stone jaws with bronze teeth, a throat glow,
    # porthole eyes (weak points) in heavy bronze rings, a barnacled stone crest and an old brass horn
    b.add(H, loft_y("Paint", [(22, 10.5, 8.5, 0, 44.5), (32, 13, 10.5, 0, 47.5), (44, 12.5, 9.5, 0, 48.5), (54, 9.5, 6.4, 0, 47.5),
                              (62, 5, 3.4, 0, 46)], segs=24, power=2.3))
    b.add(H, loft_y("Paint2", [(26, 10, 4.5, 0, 35.5), (40, 9.6, 3.8, 0, 32.5), (50, 7.4, 2.8, 0, 31.2), (57, 4.4, 2, 0, 32)],
                    segs=20, power=2.4))
    b.add(H, loft_y("Dark", [(28, 9.2, 5.6, 0, 38.6), (44, 8.4, 4.4, 0, 37.6), (50, 7, 3.6, 0, 37.4)], segs=18, power=2.2))
    b.add("Glow", loft_y("Lamp", [(49.4, 7.2, 3.8, 0, 37.6), (50.6, 6.6, 3.4, 0, 37.6)], segs=16, power=2.2))
    for k in range(6):
        a = (k - 2.5) / 2.5
        xk = a * 8.4
        yk = 58 - abs(a) ** 2 * 9
        b.add(H, spike("Metal", (xk, yk, 42.2), (xk, yk + 0.4, 37.8), 1.3, 5))
        b.add(H, spike("Metal", (xk * 0.85, yk - 3, 33.6), (xk * 0.85, yk - 2.6, 37.0), 1.1, 5))
    for s in (-1, 1):  # stone cheek fins with barnacles (they come off at 66%)
        for k, z in enumerate((41, 46.5)):
            b.add("Plates2", beam("Paint2", (s * 10.6, 34 - k * 2, z), (s * 17.5, 22 - k * 3, z + 4), 1.2, 7 - k, 0.4, 1, 0.4))
        b.add("Plates2", barnacles([(s * 12.6, 30, 44), (s * 14.6, 27.4, 50)], 0.8))
    for s in (-1, 1):
        b.add(H, ring("Metal", 3.9, 1.1, (s * 8.8, 46.0, 50), "Y", 16, 5))  # the porthole rings
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            b.add(H, cy("Paint", 0.6, 0.6, 0.8, (s * 8.8 + math.cos(a) * 3.9, 47.0, 50 + math.sin(a) * 3.9), "Y", 6))
        brow = bx("Paint2", min(s * 4, s * 12.8), max(s * 4, s * 12.8), 42, 50, 54.2, 56.4, 0.6)
        shear(brow, lambda v: Vector((v.x, v.y, v.z - (12.8 - abs(v.x)) * 0.26)))
        b.add(H, brow)
        b.lamp("eye" + ("L" if s < 0 else "R"), (s * 8.8, 46.6, 50), 3.0)
    crest = bx("Paint2", -1.0, 1.0, 22, 44, 55, 59, 0.4)
    shear(crest, lambda v: Vector((v.x, v.y, v.z - (v.y - 22) * 0.12 + (2 if v.z > 57 else 0) * (44 - v.y) / 22)))
    b.add(H, crest)
    b.add(H, barnacles([(0.6, 30, 58.4), (-0.6, 36, 57.8), (0.5, 26, 59)], 0.8))
    b.add(H, tube("Paint", [(0, 26, 52), (0, 25, 60), (0, 27, 63.5), (0, 30.4, 64.5)], [0.9, 0.9, 1.1, 1.8], 10))  # the horn
    b.add("Glow", cy("Lamp", 1.5, 1.5, 0.4, (0, 30.8, 64.5), "Y", 10))
    # Plates3: stone sleeves on the neck (33%: they come off, leaving the brass gear rings)
    for k in (1, 3):
        p0, p1 = Vector(neck[k - 1]), Vector(neck[k])
        r = (radii[k - 1] + radii[k]) / 2 + 1.0
        b.add("Plates3", tube("Paint2", [p0.lerp(p1, 0.18), p0.lerp(p1, 0.5), p0.lerp(p1, 0.82)], [r, r + 0.4, r], 18))
        c = p0.lerp(p1, 0.5)
        b.add("Plates3", barnacles([(r * 0.7, c.y + 1, c.z + r * 0.6), (-r * 0.6, c.y - 1, c.z + r * 0.7)], 0.9))
    # the vent hatch (one; the game sets one at each objective on the back; anchor at the origin): a stone block, a
    # brass porthole hatch and two bronze vent pipes
    t = []
    t.append(bx("Paint2", -4.6, 4.6, -6.2, 6.2, -7, 0.6, 1.0, 2))
    t.append(ring("Paint", 3.2, 0.7, (0, -1.2, 0.9), "Z", 14, 4))
    for s in (-1, 1):
        t.append(cy("Metal", 1.6, 1.8, 2.6, (s * 2.4, 3.4, 1.2), "Z", 10))
        t.append(ring("Paint", 1.8, 0.4, (s * 2.4, 3.4, 2.5), "Z", 10, 4))
    t += barnacles([(-3.6, -5, 0.6), (3.4, 4.8, 0.6)], 0.7)
    b.add("Bay", t)
    b.add("BayGlow", ball("Lamp", 1.6, (0, -1.2, 2.2)))
    b.objective_lamp = Vector((0, -1.2, 2.2))
    # sea mist and bubbles from the vents and the turbine
    b.fx = {"kind": "tide", "every": 0.5, "at": [(0, 15, -2), (-14, 18, 12), (14, 18, 12), (0, 64.5, -30)]}
    # the part-built look until the meshes are imported (at most 29 parts, as before)
    b.parts = []
    for k in range(6):
        size = 30 - k * 3.6
        b.parts.append(P("body", "Block", (size, size * 0.72, 24), (0, 2 - k * 5, 8 + k * 22), rot=(-10, 0, 0),
                         color=STONE if k % 2 == 0 else BRASS, mat="Slate" if k % 2 == 0 else "Metal"))
    b.parts += [
        P("body", "Cylinder", (2.4, 15, 15), (-16.4, 3, 16), color=BRASS, mat="Metal"),
        P("body", "Cylinder", (2.4, 15, 15), (16.4, 3, 16), color=BRASS, mat="Metal"),
        P("body", "Cylinder", (2.4, 15, 15), (0, 12.4, 2), rot=(0, 0, 90), color=BRASS, mat="Metal"),
        P("weak", "Ball", (6, 6, 6), (0, 14.6, 2)),
        P("body", "Block", (16, 14, 16), (0, 12, -6), rot=(-35, 0, 0), color=BRASS, mat="Metal"),
        P("body", "Block", (15, 14, 15), (0, 23, -15), rot=(-35, 0, 0), color=VERDI, mat="Metal"),
        P("body", "Block", (14, 14, 14), (0, 34, -24), rot=(-35, 0, 0), color=BRASS, mat="Metal"),
        P("body", "Block", (24, 18, 30), (0, 47.5, -38), color=BRASS, mat="Metal"),
        P("body", "Block", (20, 5, 26), (0, 34.5, -41), color=STONE, mat="Slate"),
        P("glow", "Block", (14, 4, 1), (0, 38, -54)),
        P("weak", "Ball", (6, 6, 6), (-8.8, 50, -46.6)),
        P("weak", "Ball", (6, 6, 6), (8.8, 50, -46.6)),
        P("glow", "Block", (1, 2, 26), (-15.4, 3.5, 12), rot=(-10, 0, 0)),
        P("glow", "Block", (1, 2, 26), (15.4, 3.5, 12), rot=(-10, 0, 0)),
        P("body", "Block", (2, 7, 26), (0, 58, -33), color=STONE, mat="Slate"),
        P("body", "Block", (30, 2, 12), (0, 2, -6), rot=(0, 0, 0), color=STONE, mat="Slate"),
        P("body", "Block", (2, 14, 10), (0, -30, 142), color=BRASS, mat="Metal"),
    ]
    b.objective_parts = [
        P("objective", "Block", (9, 7, 12), (0, -3, 0), color=STONE, mat="Slate"),
        P("objectiveGlow", "Ball", (3.2, 3.2, 3.2), (0, 2.2, 1.2)),
    ]
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


# ================================================================ the rigs (the boss pass, 2026-11-19)
# Each boss's body is split into rig segments by where each sub-shape's centre sits, so the game can pose them
# (Shared.BossPose, Fx.BossAnim): the titans' arms, forearms, thighs, shins, head and bumper jaw; the Maw's head,
# jaw, four legs and tail; the Leviathan's neck, head, jaw, flank gears, turbine and tide wheel. Each segment turns
# about its pivot (Blender axes here, Roblox x, up, z in BossArt.rig), children after their parents. "Root" is the
# boss's feet (the model's pivot). Textures, roles, hit boxes and the triangle budget are unchanged by the split.
def side(x):
    return "L" if x < 0 else "R"


def rust_seg(name, c):
    x, y, z = c
    ax = abs(x)
    if ax >= 26.5 or (ax >= 24 and z < 78):
        return ("Arm" if z >= 60 else "Fore") + side(x)
    if z < 49 and 3 < ax < 24 and not (44 < z < 54 and y > 9.5):
        return ("Thigh" if z >= 32 else "Shin") + side(x)
    if 84 < z < 98.5 and y > 4 and ax <= 16:
        return "Jaw"
    if z >= 93 and ax < 24 and y > -12:
        return "Head"
    return "Body"


RUST_RIG = [("Body", "Root", (0, 0, 48)), ("ThighL", "Root", (-13.3, 0, 48)), ("ShinL", "ThighL", (-14, 0, 31)),
            ("ThighR", "Root", (13.3, 0, 48)), ("ShinR", "ThighR", (14, 0, 31)), ("Head", "Body", (0, 1, 91)),
            ("Jaw", "Head", (0, 2, 90)), ("ArmL", "Body", (-28, 0, 82)), ("ForeL", "ArmL", (-32, -1, 59)),
            ("ArmR", "Body", (28, 0, 82)), ("ForeR", "ArmR", (33, -2, 60))]


def maw_seg(name, c):
    x, y, z = c
    ax = abs(x)
    if y < -42:
        return "Tail"
    if ax >= 9 and y < 22 and z < 26:
        return ("LegF" if y > -8 else "LegB") + side(x)
    if y >= 14 and z < 29.5 and ax < 17:
        return "Jaw"
    if y >= 16 and z >= 29.5:
        return "Head"
    return "Body"


MAW_RIG = [("Body", "Root", (0, -4, 30)), ("Head", "Body", (0, 18, 40)), ("Jaw", "Head", (0, 20, 31)),
           ("Tail", "Body", (0, -42, 27)), ("LegFL", "Root", (-13, 12, 32)), ("LegFR", "Root", (13, 12, 32)),
           ("LegBL", "Root", (-13, -26, 32)), ("LegBR", "Root", (13, -26, 32))]

LEV_GEARS = (("GearL", -16.4, -16, 3, 9.0), ("GearR", 16.4, -16, 3, 9.0), ("CogL", -14.6, -34, 6.5, 6.0),
             ("CogR", 14.6, -34, 6.5, 6.0))


def lev_seg(name, c):
    x, y, z = c
    ax = abs(x)
    for gid, gx, gy, gz, r in LEV_GEARS:
        if ax > 12 and x * gx > 0 and math.hypot(y - gy, z - gz) <= r and abs(x - gx) < 3:
            return gid
    if y < -136:
        return "Wheel"
    if name == "Hull" and ax < 6.5 and abs(y + 2) < 6.5 and 13.75 <= z < 14.5:
        return "Turbine"
    if 3 < y < 27.5 and 3 < z < 44 and ax < 14:
        return "Neck"
    if y >= 22 and z >= 30:
        return "Jaw" if z < 36.5 and ax < 12 else "Head"
    return "Body"


LEV_RIG = [("Body", "Root", (0, -20, 0)), ("Neck", "Body", (0, 6, 4)), ("Head", "Neck", (0, 26, 40)),
           ("Jaw", "Head", (0, 28, 37))] + [(g[0], "Body", (g[1], g[2], g[3])) for g in LEV_GEARS] + [
           ("Turbine", "Body", (0, -2, 13.9)), ("Wheel", "Body", (0, -142, -33.5))]


def war_seg(name, c):
    x, y, z = c
    ax = abs(x)
    if ax >= 13.5 and 18 <= z <= 50 and name != "Plates2":
        return ("Arm" if z >= 34 else "Fore") + side(x)
    if z >= 50.5 and ax < 10:
        return "Head"
    if z < 28 and ax > 1.5 and y > -8 and name != "Plates2":
        return ("Thigh" if z >= 14.25 else "Shin") + side(x)
    return "Body"


WAR_RIG = [("Body", "Root", (0, 0, 28)), ("ThighL", "Root", (-6.6, 0, 27.5)), ("ShinL", "ThighL", (-5, 4.5, 14)),
           ("ThighR", "Root", (6.6, 0, 27.5)), ("ShinR", "ThighR", (5, 4.5, 14)), ("Head", "Body", (0, 0, 50.5)),
           ("ArmL", "Body", (-18, 0, 46)), ("ForeL", "ArmL", (-22.5, -0.5, 34)), ("ArmR", "Body", (18, 0, 46)),
           ("ForeR", "ArmR", (22.5, -0.5, 34))]
RIGS = {"RustjawPrime": (rust_seg, RUST_RIG), "LumenMaw": (maw_seg, MAW_RIG), "LeviathanEngine": (lev_seg, LEV_RIG),
        "NullWarFrame": (war_seg, WAR_RIG)}
PART_NAME = {"body": "Hull", "glow": "Glow", "weak": "Weak"}

BUILDERS = {"RustjawPrime": rustjaw, "LumenMaw": maw, "LeviathanEngine": leviathan, "NullWarFrame": warframe}
# --set 2 (bosses-3, 2026-11-20): the second world boss set from bosses2.py (the Storm Colossus, the Swarm Queen and the
# Quarry Titan; DRAFT names and looks until nate OKs them) into Bosses2.fbx and src/config/BossArt2.luau
SET2 = "--set" in sys.argv and sys.argv[sys.argv.index("--set") + 1] == "2"
LINEUP = {"RustjawPrime": -150, "LumenMaw": -30, "NullWarFrame": 65, "LeviathanEngine": 160}
if SET2:
    import bosses2  # noqa: E402

    bosses2.bind(sys.modules[__name__])
    BUILDERS = bosses2.BUILDERS
    RIGS = dict(RIGS, **bosses2.RIGS)
    ANCHORS.update(bosses2.ANCHORS)
    LINEUP = bosses2.LINEUP
for bid, fn in BUILDERS.items():
    if ONLY and bid != ONLY:
        continue
    bb = fn()
    bb.seg_of, bb.rig = RIGS[bid]
    for row in bb.parts or []:
        row["seg"] = bb.seg_of(PART_NAME[row["role"]], rb(row["at"]))
    bb.finish()
    used = set(bb.segs.values())
    for seg, parent, _ in bb.rig:
        assert parent == "Root" or parent in [r[0] for r in bb.rig], "%s: %s's parent" % (bid, seg)
    assert used <= {r[0] for r in bb.rig}, "%s: segments %s not in the rig" % (bid, used)
    print(bid, "segments", sorted(used))
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

QUICK = "--quick" in sys.argv  # shapes only: flat palette colours, no bake, no export (for previews while working)
if QUICK:
    for bid, bb in BOSSES.items():
        for o in bb.textured():
            mats = []
            for m in o.data.materials:
                rgb, r, mt = bb.palette[m.name]
                mats.append(kit.material("%s_%s" % (bid, m.name), rgb, metal=mt, rough=r))
            for i, m in enumerate(mats):
                o.data.materials[i] = m
for bid, bb in (() if QUICK else BOSSES.items()):
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


def fmt(c):
    return ("%.3f" % c).rstrip("0").rstrip(".") if c != int(c) else "%d" % c


def part_row(r):
    vec = lambda t: "{ %s }" % ", ".join(fmt(c) for c in t)  # noqa: E731
    out = 'role = "%s", shape = "%s", size = %s, at = %s' % (r["role"], r["shape"], vec(r["size"]), vec(r["at"]))
    if any(r["rot"]):
        out += ", rot = %s" % vec(r["rot"])
    if r["role"] in ("body", "objective"):
        out += ', color = %s, mat = "%s"' % (vec(r["color"]), r["mat"])
    if r.get("seg"):
        out += ', seg = "%s"' % r["seg"]
    return "{ %s }" % out


def size3(lo, hi):
    return "{ %.3f, %.3f, %.3f }" % (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)


if ONLY is None and not QUICK:
    rows = []
    for bid, bb in BOSSES.items():
        counts = bb.tris()
        rows.append("\t%s = {" % bid)
        rows.append("\t\ttriangles = %d," % sum(counts.values()))
        rows.append("\t\tglow = { %s }, -- phases 1, 2, 3" % ", ".join("{ %d, %d, %d }" % c for c in bb.glow))
        if bb.look:
            rows.append("\t\tlook = \"%s\"," % bb.look)
            rows.append("\t\ttheme = { %d, %d, %d }, -- the entrance effects and the name card's slash" % bb.theme)
            rows.append("\t\tdebris = { %d, %d, %d }, -- the bits that fly off" % bb.debris)
        if bb.fx:
            fx = bb.fx
            extra = "".join(", %s = %s" % (k, fx[k]) for k in ("reach", "dim") if k in fx)
            rows.append("\t\tfx = { kind = \"%s\", every = %s%s, at = { %s } }," % (
                fx["kind"], fx["every"], extra, ", ".join("{ %s, %s, %s }" % tuple(fmt(c) for c in p) for p in fx["at"])))
        rows.append("\t\tpieces = {")
        for name in sorted(bb.pieces):
            role = bb.roles[name]
            if role in ("objective", "objectiveGlow", "drone"):
                continue
            lo, hi = bounds(bb.pieces[name])
            rows.append("\t\t\t%s = { role = \"%s\", size = %s, offset = %s, seg = \"%s\" }, -- %d tris"
                        % (name, role, size3(lo, hi), v3((lo + hi) / 2), bb.segs.get(name, "Body"), counts[name]))
        rows.append("\t\t},")
        rows.append("\t\t-- the rig (Shared.BossPose poses it): each segment turns about its pivot (x, up, z from the feet),")
        rows.append("\t\t-- parents first; Root is the feet. The objectives on the body ride on the Body segment")
        rows.append("\t\trig = {")
        for seg, parent, pv in bb.rig:
            rows.append("\t\t\t{ name = \"%s\", parent = \"%s\", pivot = { %s, %s, %s } }," % (
                seg, parent, fmt(pv[0]), fmt(pv[2]), fmt(-pv[1])))
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
        if bb.parts:
            n = len(bb.parts) + len(bb.objective_parts) * len(ANCHORS[bid] or [0, 0, 0])
            rows.append("\t\t-- the part-built look until the meshes are imported (x, up, z from the feet; rot in degrees,")
            rows.append("\t\t-- CFrame.Angles); objectiveParts are set at each objective. %d parts in all" % n)
            rows.append("\t\tparts = {")
            rows += ["\t\t\t%s," % part_row(r) for r in bb.parts]
            rows.append("\t\t},")
            rows.append("\t\tobjectiveParts = {")
            rows += ["\t\t\t%s," % part_row(r) for r in bb.objective_parts]
            rows.append("\t\t},")
        if "Drone" in bb.pieces:
            lo, hi = bounds(bb.pieces["Drone"])
            rows.append("\t\t-- the one drone mesh the client swarms (Fx.SwarmFx), %d tris" % counts["Drone"])
            rows.append("\t\tdrone = { Drone = { role = \"drone\", size = %s, offset = %s } }," % (size3(lo, hi), v3((lo + hi) / 2)))
        if SET2:
            rows.append("\t\tset = \"Bosses2\", -- imported as ReplicatedStorage.Art.Bosses2")
            rows.append("\t\tdraft = true, -- the name and look are DRAFTS until nate OKs them (Config.Boss draft)")
        rows.append("\t\t-- where each weak point's lamp sits (from the feet): inside its Config.Boss hit sphere")
        rows.append("\t\tweak = {")
        for tid in sorted(bb.weak):
            rows.append("\t\t\t%s = %s," % (tid, v3(bb.weak[tid])))
        rows.append("\t\t},")
        rows.append("\t},")
    head = [
        "-- GENERATED by art/blender/bosses.py --set 2: do not edit by hand. Merged into Config.BossArt at boot (init).",
        "-- The second world boss set (bosses-3, nate 2026-11-20 \"more bosses\"): the Storm Colossus, the Swarm Queen and",
        "-- the Quarry Titan (art/blender/bosses2.py). DRAFT names and looks until nate OKs them. Same rows as BossArt;",
        "-- set: the Art folder they import as; drone: the Swarm Queen's one drone mesh (Fx.SwarmFx draws it by the hundred).",
        "return {",
    ] if SET2 else None
    text = "\n".join(head + rows + ["}", ""]) if SET2 else "\n".join([
        "-- GENERATED by art/blender/bosses.py: do not edit by hand.",
        "-- PLACEHOLDER ART until nate imports art/export/Bosses.fbx. The world bosses wear nate's lore looks (2026-11-17,",
        "-- build plan step 8: Rustjaw Prime the junkyard titan, Lumen Maw the light eater, Leviathan Engine the deep",
        "-- machine); Bulwark's battle form (NullWarFrame) keeps the neutral machine look until its own pass.",
        "-- The remade bosses (ReplicatedStorage.Art.Bosses, meshes named \"<Boss>_<Piece>\"): each piece's size and its",
        "-- centre from the boss's feet, in studs (x, up, back; a boss faces -z). Roles: hull (textured body), shed2 and",
        "-- shed3 (textured plates that break off at phases 2 and 3), glow (Neon, the phase colour), weak (Neon, the",
        "-- pulsing weak-point gold), objective and objectiveGlow (one set per Config.Boss objective; the lamp goes dark",
        "-- when broken). One %d px texture set per boss (art/export/bosses). Hit boxes stay Config.Boss's." % RES,
        "-- seg: the rig segment a piece moves with (the boss pass, 2026-11-19; pieces of a segment other than Body are",
        "-- named \"<Seg>_<Piece>\"); rig: each segment's parent and pivot; Shared.BossPose poses them (Fx.BossAnim).",
        "-- look, theme, debris, fx and parts (the world bosses): the look in words, its colour (entrance and name card),",
        "-- the colour of the bits that fly off, its own effect round it (sparks, light pulled in, sea mist) and the",
        "-- part-built look the game draws until the meshes are imported (at most partBudget parts, the old count).",
        "return {",
        "\ttexture = %d," % RES,
        "\tweakColor = { { 255, 196, 40 }, { 255, 246, 190 } }, -- the weak points pulse between these",
        "\tpulse = 2.2, -- pulses a second",
        "\tobjectiveColor = { 255, 70, 60 },",
        "\tpartBudget = { RustjawPrime = 23, LumenMaw = 19, LeviathanEngine = 29 }, -- the part-built looks' old counts",
    ] + rows + ["}", ""])
    cfg = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "BossArt2.luau" if SET2 else "BossArt.luau"))
    with open(cfg, "w") as f:
        f.write(text)
    print("wrote", cfg)

if ONLY is None and not QUICK and "--no-export" not in sys.argv:
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
        filepath=os.path.join(kit.ROOT, "export", "Bosses2.fbx" if SET2 else "Bosses.fbx"),
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
                if ANCHORS[bb.id] is None:
                    continue
                anchors = [rb(a) for a in ANCHORS[bb.id]]
            if role == "drone":
                # the swarm round the core (Fx.SwarmFx draws hundreds in game): a loose cloud for the preview
                anchors = []
                for j in range(60):
                    a1, a2 = j * 2.399, (j * 0.618) % 1
                    r = 26 + (j * 7) % 13
                    anchors.append(Vector((math.cos(a1) * r * math.sqrt(1 - (a2 * 2 - 1) ** 2),
                                           math.sin(a1) * r * math.sqrt(1 - (a2 * 2 - 1) ** 2), 30 + (a2 * 2 - 1) * r * 0.7)))
            for a in anchors:
                copy(ob, Y @ Matrix.Translation(a), mats.get(role))

    def generators(bb, centre, yaw, mats, radius=46):
        for k in range(3):
            a = math.radians(yaw + 90 + (k - 1) * 55)
            p = Vector(centre) + Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
            copy(bb.pieces[bb.objective[0]], Matrix.Translation(p))
            copy(bb.pieces[bb.objective[1]], Matrix.Translation(p), mats["objectiveGlow"])

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
    if SET2:
        VIEW.update(bosses2.VIEW)
    for bid, bb in BOSSES.items():
        sep, d, ch, h = VIEW[bid]
        ground(sea=bid == "LeviathanEngine")
        # (the camera looks from the boss's front, so +x is on the left of the picture)
        place(bb, (sep, 0, 0), -30, 1, phase_mats(bb, 1))
        place(bb, (-sep, 0, 0), 150, 3, phase_mats(bb, 3))
        if ANCHORS[bid] is None:
            generators(bb, (sep, 0, 0), -30, phase_mats(bb, 1))
        hero((0, 30, 0))
        camera((0, d, ch), (0, 0, h), 32)
        kit.render(os.path.join(kit.ROOT, "preview", "boss_%s.png" % bid))
        clear()
    # the part-built look (what the game draws until the meshes are imported), phase 1, the same view as above
    T = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox (x, up, z) to Blender (x, front, up)

    def roblox_rot(rot):
        rx, ry, rz = (math.radians(a) for a in rot)
        return (Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z"))

    def fallback_part(row, base, mats, color=None):
        sx, sy, sz = row["size"]
        if row["shape"] == "Ball":
            ob = kit.sphere("fp", min(sx, sy, sz) / 2, segs=16, rings=10)
        elif row["shape"] == "Cylinder":
            ob = kit.cyl("fp", min(sy, sz) / 2, min(sy, sz) / 2, sx, segs=20, axis="X")  # along Roblox x
        else:
            ob = kit.box("fp", sx, sy, sz)
        # the shape is built in Roblox's local axes (a cylinder along x); turn it, then map to Blender's axes
        M = roblox_rot(row["rot"])
        for v in ob.data.vertices:
            v.co = T @ (M @ v.co)
        ob.data.update()
        ob.matrix_world = base @ Matrix.Translation(rb(row["at"]))
        role = row["role"]
        if role in mats:
            ob.data.materials.append(mats[role])
        else:
            ob.data.materials.append(kit.material("fp%d_%d_%d" % tuple(color or row["color"]), color or row["color"],
                                                  metal=0.6 if row["mat"] == "Metal" else 0.0, rough=0.5))
        return keep(ob)

    for bid, bb in BOSSES.items():
        if not bb.parts:
            continue
        sep, d, ch, h = VIEW[bid]
        ground(sea=bid == "LeviathanEngine")
        mats = phase_mats(bb, 1)
        for at, yaw in (((sep, 0, 0), -30), ((-sep, 0, 0), 150)):
            base = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
            for row in bb.parts:
                fallback_part(row, base, mats)
            if ANCHORS[bid] is None:
                for k in range(3):
                    a = math.radians(yaw + 90 + (k - 1) * 55)
                    g = Vector(at) + Vector((math.cos(a) * 46, math.sin(a) * 46, 0))
                    for row in bb.objective_parts:
                        fallback_part(row, Matrix.Translation(g), mats)
            else:
                for anchor in ANCHORS[bid]:
                    for row in bb.objective_parts:
                        fallback_part(row, base @ Matrix.Translation(rb(anchor)), mats)
        hero((0, 30, 0))
        camera((0, d, ch), (0, 0, h), 32)
        kit.render(os.path.join(kit.ROOT, "preview", "boss_%s_parts.png" % bid))
        clear()
    if ONLY is None:
        # the lineup: all four in scale, phase 1, three-quarter view, with a hero for scale
        ground(600)
        for bid, bb in BOSSES.items():
            place(bb, (LINEUP[bid], 0, 0), -20, 1, phase_mats(bb, 1))
        hero((10, 60, 0))
        camera((0, 360, 90), (0, 0, 45), 30)
        kit.render(os.path.join(kit.ROOT, "preview", "bosses2.png" if SET2 else "bosses.png"))
