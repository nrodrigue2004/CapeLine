# trooper.py: the remade Spark Trooper (overhaul plan step 3, "one remade robot"), the first robot made to the
# new look standard: the blocky R15 body in armour, with one baked texture set instead of flat colours.
# * 15 shell meshes named exactly as the R15 parts (Head, UpperTorso, ... RightFoot), each filling its part's
#   box exactly (the game sizes a mesh to its part, so the joints stay where they are for every build), plus
#   three extras that stick out (PadL, PadR: shoulder pads; Pack: the back thruster), placed by
#   src/config/TrooperArt.luau (generated here) against their R15 part.
# * One 512 px texture set for all of them (art/export/trooper/): a colour map, a normal map, roughness and
#   metalness. The colour map's alpha is 0 on the suit, so the game's part colour shows through there
#   (SurfaceAppearance AlphaMode Overlay): one mesh set can be any robot's colours. Armour plates, the orange
#   trim, the metal and the visor are painted in, with baked ambient occlusion and edge wear.
# * Under ~8,000 triangles for the whole robot (the plan's robot budget).
# Output: art/export/Trooper.fbx (textures embedded; import with Studio's 3D Importer), the four PNGs,
# src/config/TrooperArt.luau and art/preview/trooper.png.
# Run: python art/blender/trooper.py [--preview]   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

RES = 512
OUT = os.path.join(kit.ROOT, "export", "trooper")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- materials (one per paint region)
# id colour (for the bake), albedo, roughness, metalness. "Suit" is the see-through part (the game's colour).
REGIONS = {
    "Suit": ((1, 0, 0), None, 0.62, 0.0),
    "Armor": ((0, 1, 0), (226, 229, 234), 0.42, 0.0),
    "Trim": ((0, 0, 1), (255, 168, 52), 0.38, 0.0),
    "Metal": ((1, 1, 0), (66, 70, 80), 0.32, 1.0),
    "Visor": ((0, 1, 1), (16, 18, 26), 0.1, 0.2),
}
ORDER = list(REGIONS)


def make_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    alb = REGIONS[name][1] or (40, 70, 140)
    p.inputs["Base Color"].default_value = (alb[0] / 255, alb[1] / 255, alb[2] / 255, 1)
    p.inputs["Roughness"].default_value = REGIONS[name][2]
    p.inputs["Metallic"].default_value = REGIONS[name][3]
    # surface detail for the normal bake: soft rounded edges (Bevel) plus a fine grain per region
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.inputs["Radius"].default_value = 0.025
    bev.samples = 8
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = {"Suit": 140.0, "Armor": 18.0, "Trim": 18.0, "Metal": 60.0, "Visor": 4.0}[name]
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = {"Suit": 0.18, "Armor": 0.05, "Trim": 0.05, "Metal": 0.12, "Visor": 0.0}[name]
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bev.outputs["Normal"], bump.inputs["Normal"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return m


MATS = {n: make_mat(n) for n in ORDER}

# ---------------------------------------------------------------- building blocks (Blender: x across, +y front,
# z up; the hero's block layout from hero.py, feet on z = 0)


def piece(region, ob):
    ob.data.materials.clear()
    ob.data.materials.append(MATS[region])
    return ob


def bx(region, x0, x1, y0, y1, z0, z1, bev=0.05, segs=1, taper=None):
    """A bevelled box between bounds. taper=(top_x, top_y): scale the top face (1 = straight)."""
    ob = kit.box("b", x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    if taper:
        cx, cy, zc = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
        for v in ob.data.vertices:
            if v.co.z > zc:
                v.co.x = cx + (v.co.x - cx) * taper[0]
                v.co.y = cy + (v.co.y - cy) * taper[1]
    if bev > 0:
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = bev
        m.segments = segs
        m.limit_method = "ANGLE"
        kit.apply_all(ob)
    return piece(region, ob)


def cy(region, r1, r2, depth, at, axis="Z", segs=14):
    return piece(region, kit.cyl("c", r1, r2, depth, at=at, segs=segs, axis=axis))


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

pieces = {}


def finish(name, subs, block=None):
    """Join the sub-shapes into one piece; with a block, scale it to fill that box exactly."""
    ob = kit.join(name, subs, shade=False)
    if block:
        x0, x1, y0, y1, z0, z1 = block
        vs = ob.data.vertices
        lo = Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
        hi = Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
        for v in vs:
            v.co.x = x0 + (v.co.x - lo.x) / (hi.x - lo.x) * (x1 - x0)
            v.co.y = y0 + (v.co.y - lo.y) / (hi.y - lo.y) * (y1 - y0)
            v.co.z = z0 + (v.co.z - lo.z) / (hi.z - lo.z) * (z1 - z0)
    kit.shade_auto(ob, 32)
    pieces[name] = ob
    return ob


def core(block, inset=0.04, bev=0.07):
    """The suit underneath: the part's block a little inset."""
    x0, x1, y0, y1, z0, z1 = block
    return bx("Suit", x0 + inset, x1 - inset, y0 + inset, y1 - inset, z0 + inset * 0.5, z1 - inset * 0.5, bev, 2)


# ---------------------------------------------------------------- the helmet
def head():
    rings = []
    for z, r in ((4.02, 0.34), (4.05, 0.46), (4.1, 0.53), (4.18, 0.56), (4.3, 0.57), (4.95, 0.57), (5.06, 0.55),
                 (5.13, 0.5), (5.18, 0.42), (5.2, 0.3)):
        rings.append((z, r, r, 0, 0))
    shell = piece("Armor", kit.loft("helm", rings, segs=24, power=2.7))
    subs = [shell]
    # the visor band and its brow, the jaw guard, ear pucks (one with an antenna) and a crest
    subs.append(bx("Visor", -0.47, 0.47, 0.42, 0.6, 4.47, 4.76, 0.04))
    subs.append(bx("Trim", -0.52, 0.52, 0.4, 0.6, 4.76, 4.84, 0.025))
    subs.append(bx("Metal", -0.4, 0.4, 0.38, 0.6, 4.08, 4.38, 0.06, taper=(1.15, 1.0)))
    for x in (-0.25, -0.12, 0.0, 0.12, 0.25):
        subs.append(bx("Visor", x - 0.035, x + 0.035, 0.57, 0.61, 4.14, 4.3, 0.01, 1))
    for s in (-1, 1):
        subs.append(cy("Metal", 0.17, 0.17, 0.08, (s * 0.58, 0, 4.58), "X", 16))
        subs.append(cy("Trim", 0.1, 0.1, 0.05, (s * 0.62, 0, 4.58), "X", 12))
    subs.append(cy("Metal", 0.025, 0.018, 0.5, (-0.6, -0.05, 4.9), "Z", 6))
    subs.append(bx("Trim", -0.07, 0.07, -0.42, 0.46, 5.12, 5.22, 0.025))
    finish("Head", subs, BLOCKS["Head"])


# ---------------------------------------------------------------- torso
def upper_torso():
    b = BLOCKS["UpperTorso"]
    subs = [core(b)]
    # the chest plate (narrower at the bottom), its glowing core's metal ring, a collar
    subs.append(bx("Armor", -0.9, 0.9, 0.28, 0.5, 3.08, 3.94, 0.06, taper=(1.0, 1.0)))
    subs.append(bx("Armor", -0.62, 0.62, 0.28, 0.48, 2.9, 3.1, 0.05))
    subs.append(cy("Metal", 0.2, 0.2, 0.06, (0, 0.47, 3.45), "Y", 20))
    subs.append(cy("Visor", 0.13, 0.13, 0.04, (0, 0.49, 3.45), "Y", 20))
    for s in (-1, 1):
        subs.append(bx("Trim", s * 0.7 - 0.04, s * 0.7 + 0.04, 0.46, 0.5, 3.2, 3.82, 0.015))
    subs.append(bx("Metal", -0.62, 0.62, -0.32, 0.32, 3.9, 4.0, 0.03))
    # ab plates, two rows of two
    for z0, z1 in ((2.48, 2.66), (2.7, 2.86)):
        for s in (-1, 1):
            x0, x1 = (0.05, 0.5) if s > 0 else (-0.5, -0.05)
            subs.append(bx("Armor", x0, x1, 0.38, 0.48, z0, z1, 0.03))
    # the back plate with vent slats, side panels
    subs.append(bx("Armor", -0.82, 0.82, -0.47, -0.3, 2.95, 3.9, 0.05))
    for k in range(3):
        z = 3.2 + k * 0.16
        subs.append(bx("Metal", -0.42, 0.42, -0.5, -0.44, z, z + 0.08, 0.015))
    for s in (-1, 1):
        subs.append(bx("Metal", s * 1.0 - 0.06, s * 1.0 + 0.06, -0.26, 0.26, 2.62, 3.75, 0.03))
    finish("UpperTorso", subs, b)


def lower_torso():
    b = BLOCKS["LowerTorso"]
    subs = [core(b, 0.04, 0.05)]
    subs.append(bx("Metal", -1.0, 1.0, -0.5, 0.5, 2.22, 2.38, 0.03))
    subs.append(bx("Trim", -0.22, 0.22, 0.44, 0.52, 2.18, 2.4, 0.03))
    subs.append(bx("Armor", -0.3, 0.3, 0.36, 0.5, 2.0, 2.2, 0.04, taper=(1.25, 1.0)))
    for s in (-1, 1):
        x0, x1 = (0.52, 0.88) if s > 0 else (-0.88, -0.52)
        subs.append(bx("Armor", x0, x1, 0.32, 0.5, 2.04, 2.3, 0.035))
        subs.append(bx("Armor", x0, x1, -0.5, -0.32, 2.04, 2.3, 0.035))
    finish("LowerTorso", subs, b)


# ---------------------------------------------------------------- arms (left; the right is a mirror)
def upper_arm():
    b = BLOCKS["LeftUpperArm"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b)]
    subs.append(bx("Armor", x0, x1, y0, y1, 3.5, 3.86, 0.06))
    subs.append(bx("Trim", x0 + 0.02, x1 - 0.02, y0 + 0.02, y1 - 0.02, 3.42, 3.5, 0.02))
    subs.append(bx("Metal", x0 + 0.08, x1 - 0.08, y0 + 0.08, y1 - 0.08, 3.86, 4.0, 0.03))
    finish("LeftUpperArm", subs, b)


def lower_arm():
    b = BLOCKS["LeftLowerArm"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b)]
    # the gauntlet: a plate a little wider at the elbow, an outer trim stripe, vents and a metal elbow cap
    subs.append(bx("Armor", x0, x1, y0, y1, 2.38, 3.02, 0.06, taper=(1.0, 1.0)))
    subs.append(bx("Trim", x0 - 0.01, x0 + 0.04, -0.18, 0.18, 2.48, 2.92, 0.012))
    for k in range(3):
        z = 2.55 + k * 0.12
        subs.append(bx("Metal", x0 + 0.25, x1 - 0.25, 0.46, 0.51, z, z + 0.06, 0.012))
    subs.append(bx("Metal", x0 + 0.06, x1 - 0.06, y0 + 0.06, y1 - 0.06, 3.02, 3.15, 0.03))
    subs.append(bx("Trim", x0 + 0.02, x1 - 0.02, y0 + 0.02, y1 - 0.02, 2.3, 2.38, 0.02))
    finish("LeftLowerArm", subs, b)


def hand():
    b = BLOCKS["LeftHand"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b, 0.03, 0.05)]
    subs.append(bx("Armor", x0 + 0.08, x1 - 0.08, 0.3, 0.5, 2.12, 2.3, 0.04))
    for k in range(4):
        x = x0 + 0.2 + k * 0.2
        subs.append(bx("Metal", x - 0.07, x + 0.07, 0.42, 0.52, 2.0, 2.1, 0.02))
    finish("LeftHand", subs, b)


def pad():
    # the shoulder pad: a domed plate over the shoulder with a trim edge (an extra piece)
    ob = bx("Armor", -2.14, -0.92, -0.6, 0.6, 3.82, 4.22, 0.12, 2)

    def dome(v):
        t = (v.x + 1.53) / 0.61  # -1 inner .. 1 outer
        v.z += 0.1 * (1 - min(1.0, abs(t) ** 2)) if v.z > 4.0 else 0
        if v.z < 3.95 and v.x < -1.9:
            v.z -= 0.08
        return v

    kit.deform(ob, dome)
    edge = bx("Trim", -2.2, -2.08, -0.55, 0.55, 3.7, 4.0, 0.02)
    rivet = cy("Metal", 0.06, 0.06, 0.05, (-1.6, 0.0, 4.33), "Z", 10)
    finish("PadL", [ob, edge, rivet])


# ---------------------------------------------------------------- legs (left; the right is a mirror)
def upper_leg():
    b = BLOCKS["LeftUpperLeg"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b)]
    subs.append(bx("Armor", x0 + 0.08, x1 - 0.08, 0.28, 0.5, 1.28, 1.94, 0.06, taper=(1.1, 1.0)))
    subs.append(bx("Metal", x0 - 0.0, x0 + 0.1, -0.3, 0.2, 1.35, 1.75, 0.03))
    subs.append(bx("Trim", x0 + 0.1, x1 - 0.1, 0.46, 0.51, 1.52, 1.6, 0.015))
    finish("LeftUpperLeg", subs, b)


def lower_leg():
    b = BLOCKS["LeftLowerLeg"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b)]
    subs.append(bx("Armor", x0, x1, -0.32, 0.5, 0.34, 0.98, 0.06, taper=(1.0, 1.0)))
    subs.append(bx("Trim", x0 + 0.2, x1 - 0.2, 0.32, 0.52, 0.96, 1.15, 0.07, 2))
    subs.append(bx("Metal", x0 + 0.3, x1 - 0.3, y0, -0.36, 0.5, 0.78, 0.03))
    finish("LeftLowerLeg", subs, b)


def foot():
    b = BLOCKS["LeftFoot"]
    x0, x1, y0, y1, z0, z1 = b
    subs = []
    subs.append(bx("Metal", x0, x1, y0, y1, 0.0, 0.09, 0.03))
    subs.append(bx("Armor", x0 + 0.02, x1 - 0.02, y0 + 0.02, y1 - 0.02, 0.08, 0.3, 0.05))
    subs.append(bx("Trim", x0 + 0.08, x1 - 0.08, 0.3, 0.5, 0.06, 0.24, 0.04))
    # the jet nozzle ring under the heel (the game's neon jet sits below it)
    subs.append(cy("Metal", 0.2, 0.24, 0.05, ((x0 + x1) / 2, -0.15, 0.025), "Z", 14))
    finish("LeftFoot", subs, b)


def pack():
    # the back thruster (an extra on the upper torso): a box with a cover plate, a trim stripe and two nozzles
    subs = [bx("Metal", -0.62, 0.62, -0.88, -0.5, 2.95, 3.82, 0.07)]
    subs.append(bx("Armor", -0.5, 0.5, -0.94, -0.82, 3.05, 3.72, 0.05))
    subs.append(bx("Trim", -0.5, 0.5, -0.95, -0.9, 3.48, 3.56, 0.012))
    for s in (-1, 1):
        subs.append(cy("Metal", 0.13, 0.19, 0.22, (s * 0.34, -0.69, 2.84), "Z", 14))
        subs.append(cy("Visor", 0.1, 0.1, 0.03, (s * 0.34, -0.69, 2.73), "Z", 12))
    finish("Pack", subs)


head()
upper_torso()
lower_torso()
upper_arm()
lower_arm()
hand()
pad()
upper_leg()
lower_leg()
foot()
pack()

# the right side: mirrors of the left
for name in list(pieces):
    if name.startswith("Left") or name == "PadL":
        right = "Right" + name[4:] if name.startswith("Left") else "PadR"
        ob = kit.mirror_x(pieces[name], right)
        ob.data.name = right
        pieces[right] = ob
BLOCKS_ALL = dict(BLOCKS)
for name in list(BLOCKS):
    if name.startswith("Left"):
        x0, x1, y0, y1, z0, z1 = BLOCKS[name]
        BLOCKS_ALL["Right" + name[4:]] = (-x1, -x0, y0, y1, z0, z1)

PARTS = ["Head", "UpperTorso", "LowerTorso"] + [s + p for s in ("Left", "Right") for p in
                                                  ("UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot")]
EXTRAS = {"PadL": "LeftUpperArm", "PadR": "RightUpperArm", "Pack": "UpperTorso"}
for name in PARTS + list(EXTRAS):
    assert name in pieces, name

total = 0
for name in PARTS + list(EXTRAS):
    t = kit.tris(pieces[name])
    total += t
    print("%-14s %5d tris" % (name, t))
print("total", total)
assert total <= 8000, "over the robot budget"

# ---------------------------------------------------------------- one UV atlas for every piece
objs = [pieces[n] for n in PARTS + list(EXTRAS)]
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, scale_to_bounds=False)
bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
bpy.ops.object.mode_set(mode="OBJECT")

# ---------------------------------------------------------------- bakes: region ids, ambient occlusion, edges,
# normals
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.render.bake.margin = 6
scene.render.bake.use_clear = True


def image(name, alpha=False, data=False):
    img = bpy.data.images.new(name, RES, RES, alpha=alpha, float_buffer=False)
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
    """Point each material's output at an emission shader made by fn(material name, node tree) for one bake."""
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


def bake(kind, img, samples=16):
    scene.cycles.samples = samples
    set_target(img)
    bpy.ops.object.bake(type=kind)


def pixels(img):
    a = np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)
    return a


ids = image("ids", data=True)
saved = with_emission(lambda n, nt, em: em.inputs["Color"].__setattr__("default_value", (*REGIONS[n][0], 1)))
bake("EMIT", ids, 1)
restore(saved)

edges = image("edges", data=True)


def edge_emit(n, nt, em):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nt.links.new(geo.outputs["Pointiness"], em.inputs["Color"])


saved = with_emission(edge_emit)
bake("EMIT", edges, 1)
restore(saved)

ao = image("ao", data=True)
scene.world = scene.world or bpy.data.worlds.new("W")
bake("AO", ao, 48)

normal = image("normal", data=True)
bake("NORMAL", normal, 8)

# ---------------------------------------------------------------- compose the four maps
I = pixels(ids)
A = pixels(ao)[..., 0]
E = pixels(edges)[..., 0]
N = pixels(normal)
rng = np.random.default_rng(7)


def blur_noise(scale):
    n = rng.random((RES // scale + 2, RES // scale + 2)).astype(np.float32)
    n = np.kron(n, np.ones((scale, scale), dtype=np.float32))[:RES, :RES]
    k = np.ones(scale) / scale
    n = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 0, n)
    n = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, n)
    return n


mottle = blur_noise(16) * 0.6 + blur_noise(4) * 0.4  # 0..1, soft dirt and paint variation
region = np.full((RES, RES), -1, dtype=np.int32)
for k, n in enumerate(ORDER):
    c = np.array(REGIONS[n][0], dtype=np.float32)
    d = np.abs(I[..., :3] - c).sum(axis=2)
    region[d < 0.3] = k
edge = np.clip((E - 0.5) * 6.0, 0, 1)  # convex edges light up (worn paint), creases stay dark
occl = np.clip(A, 0, 1)

col = np.zeros((RES, RES, 4), dtype=np.float32)
rough = np.zeros((RES, RES), dtype=np.float32)
metal = np.zeros((RES, RES), dtype=np.float32)
for k, n in enumerate(ORDER):
    m = region == k
    _, alb, r, mt = REGIONS[n]
    if n == "Suit":
        # see-through: only shading over the game's colour (darker in creases, a little grime)
        col[m, :3] = (0.02, 0.02, 0.03)
        col[m, 3] = np.clip((1 - occl[m]) * 0.7 + (mottle[m] - 0.5) * 0.12, 0, 0.75)
    else:
        base = np.array(alb, dtype=np.float32) / 255
        shade = (0.5 + 0.5 * occl[m])[:, None]
        grime = (1 - 0.1 * mottle[m])[:, None]
        wear = edge[m][:, None] * (0.25 if n != "Visor" else 0.05)
        col[m, :3] = np.clip(base * shade * grime + wear * (1 - base * 0.5), 0, 1)
        col[m, 3] = 1
    rough[m] = np.clip(r + (mottle[m] - 0.5) * 0.12 - edge[m] * 0.1, 0.04, 1)
    metal[m] = mt
# texels outside any island: suit-like (see-through), so a seam bleeds harmlessly
col[region < 0] = (0.02, 0.02, 0.03, 0.2)
rough[region < 0] = 0.6


def save(name, arr, data):
    img = bpy.data.images.new(name, RES, RES, alpha=arr.shape[2] == 4 if arr.ndim == 3 else False)
    if data:
        img.colorspace_settings.name = "Non-Color"
    if arr.ndim == 2:
        arr = np.dstack([arr, arr, arr, np.ones_like(arr)])
    img.pixels[:] = arr.reshape(-1)
    path = os.path.join(OUT, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img, path


color_img, color_path = save("Trooper_Color", col, False)
normal_img, normal_path = save("Trooper_Normal", N, True)
rough_img, rough_path = save("Trooper_Roughness", rough, True)
metal_img, metal_path = save("Trooper_Metalness", metal, True)

# ---------------------------------------------------------------- the export material: one PBR material on every
# piece, so the importer makes one SurfaceAppearance with all four maps
out_mat = bpy.data.materials.new("Trooper")
out_mat.use_nodes = True
nt = out_mat.node_tree
p = nt.nodes["Principled BSDF"]


def tex_node(img, data):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = img
    if data:
        img.colorspace_settings.name = "Non-Color"
    return n


tc = tex_node(color_img, False)
nt.links.new(tc.outputs["Color"], p.inputs["Base Color"])
nt.links.new(tc.outputs["Alpha"], p.inputs["Alpha"])
tr = tex_node(rough_img, True)
nt.links.new(tr.outputs["Color"], p.inputs["Roughness"])
tm = tex_node(metal_img, True)
nt.links.new(tm.outputs["Color"], p.inputs["Metallic"])
tn = tex_node(normal_img, True)
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])


def rbx(v):
    """Blender (x, front, up) to Roblox (x, up, back)."""
    return (v[0], v[2], -v[1])


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


# the extras against their R15 part's box: offset of centres and size, as fractions of that part (Roblox axes)
rows = []
for name, parent in EXTRAS.items():
    lo, hi = bounds(pieces[name])
    x0, x1, y0, y1, z0, z1 = BLOCKS_ALL[parent]
    bsize = Vector((x1 - x0, y1 - y0, z1 - z0))
    bc = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    c = (lo + hi) / 2
    off = Vector(((c.x - bc.x) / bsize.x, (c.y - bc.y) / bsize.y, (c.z - bc.z) / bsize.z))
    size = Vector(((hi.x - lo.x) / bsize.x, (hi.y - lo.y) / bsize.y, (hi.z - lo.z) / bsize.z))
    o, s = rbx(off), (size.x, size.z, size.y)
    rows.append("\t\t%s = { parent = \"%s\", offset = { %.3f, %.3f, %.3f }, size = { %.3f, %.3f, %.3f } },"
                % (name, parent, o[0], o[1], o[2], s[0], s[1], s[2]))
text = "\n".join([
    "-- GENERATED by art/blender/trooper.py: do not edit by hand.",
    "-- The remade Spark Trooper (ReplicatedStorage.Art.Trooper): its 15 R15 shell meshes fill their parts' boxes;",
    "-- the extras sit against an R15 part, as fractions of that part's size (x, up, depth; offset of centres).",
    "return {",
    "\ttriangles = %d," % total,
    "\textras = {",
] + rows + ["\t},", "}", ""])
cfg = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "TrooperArt.luau"))
with open(cfg, "w") as f:
    f.write(text)
print("wrote", cfg)

if "--no-export" not in sys.argv:
    export = []
    for name in PARTS + list(EXTRAS):
        ob = pieces[name]
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.name = name + "_x"
        kit.centre(cp)
        cp.name = name
        cp.data.name = name
        cp.data.materials.clear()
        cp.data.materials.append(out_mat)
        export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(kit.ROOT, "export", "Trooper.fbx"),
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

# ---------------------------------------------------------------- preview: the game's look (suit colour under the
# colour map's alpha), front, three-quarter flying pose, back, a damaged one, next to the plain hero body
if "--preview" in sys.argv:
    J = {
        "Waist": Vector((0, 0, 2.4)), "Neck": Vector((0, 0, 4.0)),
        "LeftShoulder": Vector((-1.0, 0, 3.76)), "LeftElbow": Vector((-1.5, 0, 3.15)),
        "LeftWrist": Vector((-1.5, 0, 2.3)), "LeftHip": Vector((-0.5, 0, 2.0)),
        "LeftKnee": Vector((-0.5, 0, 1.15)), "LeftAnkle": Vector((-0.5, 0, 0.3)),
    }
    for k in list(J):
        if k.startswith("Left"):
            v = J[k]
            J["Right" + k[4:]] = Vector((-v.x, v.y, v.z))
    PARENT = {"UpperTorso": ("LowerTorso", "Waist"), "Head": ("UpperTorso", "Neck"), "Pack": ("UpperTorso", None)}
    for s in ("Left", "Right"):
        PARENT[s + "UpperArm"] = ("UpperTorso", s + "Shoulder")
        PARENT[s + "LowerArm"] = (s + "UpperArm", s + "Elbow")
        PARENT[s + "Hand"] = (s + "LowerArm", s + "Wrist")
        PARENT[s + "UpperLeg"] = ("LowerTorso", s + "Hip")
        PARENT[s + "LowerLeg"] = (s + "UpperLeg", s + "Knee")
        PARENT[s + "Foot"] = (s + "LowerLeg", s + "Ankle")
    PARENT["PadL"] = ("LeftUpperArm", None)
    PARENT["PadR"] = ("RightUpperArm", None)

    def game_mat(suit_rgb):
        m = out_mat.copy()
        t = m.node_tree
        pr = t.nodes["Principled BSDF"]
        img = [n for n in t.nodes if n.type == "TEX_IMAGE" and n.image == color_img][0]
        mix = t.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = (*(c / 255 for c in suit_rgb), 1)
        t.links.new(img.outputs["Alpha"], mix.inputs["Factor"])
        t.links.new(img.outputs["Color"], mix.inputs["B"])
        t.links.new(mix.outputs["Result"], pr.inputs["Base Color"])
        for l in list(pr.inputs["Alpha"].links):
            t.links.remove(l)
        pr.inputs["Alpha"].default_value = 1
        return m

    def pose_copy(at, bends, mat, yaw=0.0, hide=(), endo=None):
        world = {}

        def matrix(n):
            if n in world:
                return world[n]
            if n not in PARENT:
                world[n] = Matrix.Identity(4)
                return world[n]
            par, jn = PARENT[n]
            m = matrix(par)
            if jn and jn in bends:
                axis, deg = bends[jn]
                pt = J[jn]
                m = m @ Matrix.Translation(pt) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-pt)
            world[n] = m
            return m

        Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        for n in PARTS + list(EXTRAS):
            if n in hide:
                if endo and n in BLOCKS_ALL:
                    x0, x1, y0, y1, z0, z1 = BLOCKS_ALL[n]
                    r, sz = min(x1 - x0, y1 - y0) * 0.2, (z1 - z0) * 0.94
                    e = kit.cyl("endo", r, r * 0.85, sz, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), segs=12)
                    e.data.materials.append(endo)
                    e.matrix_world = Y @ matrix(n)
                continue
            src = pieces[n]
            cp = src.copy()
            cp.data = src.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            cp.matrix_world = Y @ matrix(n)
            cp.data.materials.clear()
            cp.data.materials.append(mat)
            cp.hide_render = False

    for ob in pieces.values():
        ob.hide_render = True
    kit.studio(res=(1800, 1000), samples=64)
    blue = game_mat((40, 70, 140))
    chrome = kit.material("endo", (150, 155, 168), metal=1.0, rough=0.3)
    fly = {"LeftShoulder": ("X", -25), "RightShoulder": ("X", 70), "RightElbow": ("X", 15),
           "LeftHip": ("X", 15), "LeftKnee": ("X", -35), "RightHip": ("X", -10), "RightKnee": ("X", -15)}
    pose_copy((7.6, 0, 0), {}, blue)
    pose_copy((2.6, 0, 0.6), fly, blue, yaw=35)
    pose_copy((-2.6, 0, 0), {}, blue, yaw=180)
    pose_copy((-7.6, 0, 0), {"Neck": ("Z", -12)}, blue, yaw=-20,
              hide=("LeftUpperArm", "LeftLowerArm", "LeftHand", "PadL", "RightLowerLeg", "RightFoot"), endo=chrome)
    floor = kit.cyl("floor", 16, 16, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 25.0, 5.4), (0, 0, 2.6), lens=42)
    kit.render(os.path.join(kit.ROOT, "preview", "trooper.png"))
