# trooper.py: the remade Spark Trooper (overhaul plan step 3, "one remade robot"), the first robot made to the
# new look standard: a superhero on the blocky R15 body (nate, 2026-11-17: robots must read as people first:
# face, hair, a fitted suit with an emblem, gloves, boots and a belt; the metal shows only as it breaks), with
# one baked texture set instead of flat colours.
# * 15 shell meshes named exactly as the R15 parts (Head, UpperTorso, ... RightFoot), each filling its part's
#   box exactly (the game sizes a mesh to its part, so the joints stay where they are for every build), plus
#   the hair as an extra (Hair), placed by
#   src/config/TrooperArt.luau (generated here) against their R15 part.
# * One 512 px texture set for all of them (art/export/trooper/): a colour map, a normal map, roughness and
#   metalness. The colour map's alpha is 0 on the suit, so the game's part colour shows through there
#   (SurfaceAppearance AlphaMode Overlay): skin, hair, suit, gloves and boots take the robot's colours. The
#   emblem, the stripes, the belt, brows and mouth are painted in, with baked ambient occlusion and edge wear.
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


# ---------------------------------------------------------------- the head: a person's face (nate, 2026-11-17:
# "not humanoid enough ... make it look like a superhero"). The skin is the game's colour (see-through), the
# brows, the mouth and a thin android seam at the temples are painted; the glowing eyes are the game's parts.
def head():
    rings = []
    for z, r in ((4.02, 0.36), (4.04, 0.46), (4.08, 0.53), (4.15, 0.58), (4.25, 0.6), (4.97, 0.6), (5.07, 0.58),
                 (5.14, 0.53), (5.18, 0.46), (5.2, 0.36)):
        rings.append((z, r, r, 0, 0))
    skin = piece("Suit", kit.loft("skin", rings, segs=28, power=2.25))
    subs = [skin]
    for s in (-1, 1):
        # brows (a heroic, slightly angled line), the temple seam
        brow = bx("Visor", s * 0.36 - 0.13, s * 0.36 + 0.13, 0.55, 0.62, 4.74, 4.8, 0.012)
        kit.deform(brow, lambda v, s=s: Vector((v.x, v.y, v.z + (0.03 if v.x * s < 0.36 else -0.01))))
        subs.append(brow)
        subs.append(bx("Metal", s * 0.6 - 0.012, s * 0.6 + 0.012, -0.12, 0.2, 4.5, 4.9, 0.0))
    subs.append(bx("Suit", -0.07, 0.07, 0.55, 0.64, 4.45, 4.66, 0.03))  # the nose
    subs.append(bx("Visor", -0.16, 0.16, 0.57, 0.61, 4.3, 4.335, 0.01))  # the mouth
    subs.append(bx("Suit", -0.2, 0.2, 0.5, 0.6, 4.08, 4.22, 0.05))  # the chin
    finish("Head", subs, BLOCKS["Head"])


def hair():
    # swept-back hero hair (an extra on the head; its colour is the game's, picked per robot)
    rings = []
    for z, r, cy in ((4.66, 0.63, 0.0), (4.85, 0.65, -0.02), (5.05, 0.64, -0.04), (5.2, 0.58, -0.06),
                     (5.3, 0.46, -0.08), (5.36, 0.3, -0.1)):
        rings.append((z, r, r, 0, cy))
    cap = kit.loft("cap", rings, segs=24, power=2.4)
    # open the face: push the front ring up above the brow
    for v in cap.data.vertices:
        if v.co.y > 0.25 and v.co.z < 5.0:
            v.co.z = 5.0 + (v.co.z - 4.66) * 0.3
    subs = [piece("Suit", cap)]
    # a front quiff and three swept spikes over the back
    q = bx("Suit", -0.34, 0.2, 0.2, 0.62, 5.1, 5.42, 0.06)
    kit.deform(q, lambda v: Vector((v.x, v.y, v.z + 0.12 * max(0.0, v.y - 0.3))))
    subs.append(q)
    for k, (x, rot) in enumerate(((-0.32, -0.2), (0.0, 0.0), (0.32, 0.2))):
        sp = kit.cyl("sp%d" % k, 0.17, 0.02, 0.5, at=(x, -0.52, 5.12), segs=8, axis="Y")
        kit.deform(sp, lambda v, x=x: Vector((v.x + (v.x - x) * 0.3, v.y, v.z + 0.15 * (-0.52 - v.y))))
        subs.append(piece("Suit", sp))
    for s in (-1, 1):  # sideburn blocks
        subs.append(bx("Suit", s * 0.63 - 0.05, s * 0.63 + 0.05, -0.2, 0.15, 4.5, 4.9, 0.03))
    finish("Hair", subs)


# ---------------------------------------------------------------- torso: a fitted hero suit with an emblem
def upper_torso():
    b = BLOCKS["UpperTorso"]
    subs = [core(b)]
    # chest panels (a faint pec line), the emblem: a bold diamond with a spark chevron in it
    for s in (-1, 1):
        x0, x1 = (0.02, 0.92) if s > 0 else (-0.92, -0.02)
        subs.append(bx("Suit", x0, x1, 0.42, 0.5, 3.3, 3.94, 0.07, 2))
    # (a white diamond rim, an orange diamond inside it and a dark spark bolt across, standing proud of the pecs)
    def diamond(region, hw, hh, y0, y1, zc=3.54):
        # a square turned 45 degrees in the chest's plane, then stretched to hw wide, hh tall
        a = hh / math.sqrt(2)
        d = bx(region, -a, a, y0, y1, zc - a, zc + a, 0.02)
        c = math.sqrt(0.5)
        kit.deform(d, lambda v: Vector(((v.x - (v.z - zc)) * c * hw / hh, v.y, (v.x + (v.z - zc)) * c + zc)))
        return d
    subs.append(diamond("Armor", 0.5, 0.42, 0.46, 0.56))
    subs.append(diamond("Trim", 0.38, 0.32, 0.5, 0.59))
    # the spark: a zig-zag bolt of two slanted strokes and a jog between them
    top = bx("Visor", -0.04, 0.04, 0.56, 0.62, 3.53, 3.8, 0.0)
    kit.deform(top, lambda v: Vector((v.x - 0.02 + (v.z - 3.53) * 0.6, v.y, v.z)))
    low = bx("Visor", -0.04, 0.04, 0.56, 0.62, 3.28, 3.57, 0.0)
    kit.deform(low, lambda v: Vector((v.x - 0.1 + (v.z - 3.28) * 0.6, v.y, v.z)))
    subs += [top, low, bx("Visor", -0.06, 0.1, 0.56, 0.62, 3.53, 3.58, 0.0)]
    # side stripes and a collar
    for s in (-1, 1):
        subs.append(bx("Trim", s * 1.0 - 0.04, s * 1.0 + 0.04, -0.3, 0.3, 2.45, 3.95, 0.015))
    subs.append(bx("Trim", -0.52, 0.52, -0.3, 0.3, 3.92, 4.0, 0.03))
    # ab seams (two rows) and the back's shoulder-blade panels
    for z in (2.62, 2.9):
        subs.append(bx("Suit", -0.5, 0.5, 0.44, 0.49, z, z + 0.2, 0.05))
    for s in (-1, 1):
        x0, x1 = (0.08, 0.82) if s > 0 else (-0.82, -0.08)
        subs.append(bx("Suit", x0, x1, -0.5, -0.44, 3.2, 3.85, 0.06))
    finish("UpperTorso", subs, b)


def lower_torso():
    b = BLOCKS["LowerTorso"]
    subs = [core(b, 0.04, 0.05)]
    subs.append(bx("Trim", -1.0, 1.0, -0.5, 0.5, 2.24, 2.38, 0.03))  # the belt
    subs.append(cy("Armor", 0.15, 0.15, 0.06, (0, 0.5, 2.31), "Y", 18))  # the buckle
    for s in (-1, 1):
        subs.append(bx("Metal", s * 0.62 - 0.12, s * 0.62 + 0.12, 0.42, 0.52, 2.22, 2.36, 0.02))  # belt pouches
    finish("LowerTorso", subs, b)


# ---------------------------------------------------------------- arms (left; the right is a mirror)
def upper_arm():
    b = BLOCKS["LeftUpperArm"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b)]
    subs.append(bx("Trim", x0, x0 + 0.05, -0.3, 0.3, 3.2, 3.98, 0.015))  # the outer stripe runs on
    subs.append(bx("Suit", x0 + 0.06, x1 - 0.06, 0.42, 0.5, 3.28, 3.5, 0.04))  # a shoulder seam panel
    finish("LeftUpperArm", subs, b)


def lower_arm():
    b = BLOCKS["LeftLowerArm"]
    x0, x1, y0, y1, z0, z1 = b
    # a classic hero glove: flared cuff at the top, fitted below (its colour is the game's trim)
    subs = [core(b, 0.08)]
    cuff = bx("Suit", x0, x1, y0, y1, 2.82, 3.06, 0.05, 2, taper=(1.0, 1.0))
    kit.deform(cuff, lambda v: Vector(((v.x + 1.5) * (1.0 if v.z > 2.95 else 0.88) - 1.5, v.y * (1.0 if v.z > 2.95 else 0.88), v.z)))
    subs.append(cuff)
    subs.append(bx("Armor", x0 - 0.0, x0 + 0.04, -0.12, 0.12, 2.86, 3.02, 0.01))  # a cuff badge
    finish("LeftLowerArm", subs, b)


def hand():
    b = BLOCKS["LeftHand"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b, 0.03, 0.06)]
    subs.append(bx("Suit", x0 + 0.1, x1 - 0.1, 0.4, 0.5, 2.0, 2.16, 0.05))  # a padded knuckle band
    finish("LeftHand", subs, b)


# ---------------------------------------------------------------- legs (left; the right is a mirror)
def upper_leg():
    b = BLOCKS["LeftUpperLeg"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [core(b)]
    subs.append(bx("Trim", x0, x0 + 0.05, -0.3, 0.3, 1.2, 1.98, 0.015))  # the outer stripe
    subs.append(bx("Suit", x0 + 0.1, x1 - 0.1, 0.42, 0.5, 1.25, 1.62, 0.05))  # the thigh panel
    finish("LeftUpperLeg", subs, b)


def lower_leg():
    b = BLOCKS["LeftLowerLeg"]
    x0, x1, y0, y1, z0, z1 = b
    # the boot: a flared top (a classic hero boot), a knee crease, a seam down the front
    subs = [core(b, 0.07)]
    top = bx("Suit", x0, x1, y0, y1, 0.86, 1.12, 0.05, 2)
    kit.deform(top, lambda v: Vector(((v.x + 0.5) * (1.0 if v.z > 1.0 else 0.9) - 0.5, v.y * (1.0 if v.z > 1.0 else 0.9) + (0.04 if v.y > 0 and v.z > 1.0 else 0), v.z)))
    subs.append(top)
    subs.append(bx("Armor", x0 + 0.3, x1 - 0.3, 0.44, 0.52, 0.9, 1.08, 0.02))  # the boot badge
    finish("LeftLowerLeg", subs, b)


def foot():
    b = BLOCKS["LeftFoot"]
    x0, x1, y0, y1, z0, z1 = b
    subs = [bx("Visor", x0, x1, y0, y1, 0.0, 0.08, 0.03)]  # the sole
    subs.append(bx("Suit", x0 + 0.02, x1 - 0.02, y0 + 0.02, y1 - 0.02, 0.07, 0.3, 0.07, 2))
    subs.append(bx("Suit", x0 + 0.1, x1 - 0.1, 0.25, 0.5, 0.06, 0.2, 0.06))  # the toe cap
    subs.append(cy("Metal", 0.18, 0.22, 0.05, ((x0 + x1) / 2, -0.15, 0.025), "Z", 14))  # the jet ring
    finish("LeftFoot", subs, b)


head()
hair()
upper_torso()
lower_torso()
upper_arm()
lower_arm()
hand()
upper_leg()
lower_leg()
foot()

# the right side: mirrors of the left
for name in list(pieces):
    if name.startswith("Left"):
        right = "Right" + name[4:]
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
EXTRAS = {"Hair": "Head"}
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
    PARENT = {"UpperTorso": ("LowerTorso", "Waist"), "Head": ("UpperTorso", "Neck"), "Hair": ("Head", None)}
    for s in ("Left", "Right"):
        PARENT[s + "UpperArm"] = ("UpperTorso", s + "Shoulder")
        PARENT[s + "LowerArm"] = (s + "UpperArm", s + "Elbow")
        PARENT[s + "Hand"] = (s + "LowerArm", s + "Wrist")
        PARENT[s + "UpperLeg"] = ("LowerTorso", s + "Hip")
        PARENT[s + "LowerLeg"] = (s + "UpperLeg", s + "Knee")
        PARENT[s + "Foot"] = (s + "LowerLeg", s + "Ankle")

    def lin(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def game_mat(suit_rgb):
        m = out_mat.copy()
        t = m.node_tree
        pr = t.nodes["Principled BSDF"]
        img = [n for n in t.nodes if n.type == "TEX_IMAGE" and n.image == color_img][0]
        mix = t.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = (*(lin(c) for c in suit_rgb), 1)  # Part.Color is sRGB
        t.links.new(img.outputs["Alpha"], mix.inputs["Factor"])
        t.links.new(img.outputs["Color"], mix.inputs["B"])
        t.links.new(mix.outputs["Result"], pr.inputs["Base Color"])
        for l in list(pr.inputs["Alpha"].links):
            t.links.remove(l)
        pr.inputs["Alpha"].default_value = 1
        return m

    def colours(suit, trim, skin, hair_rgb):
        """Each part's game colour (EnemyRenderer: suit on the torso, upper arms and thighs; trim for gloves
        and boots; the skin and hair picked per robot)."""
        out = {"Head": skin, "Hair": hair_rgb, "UpperTorso": suit, "LowerTorso": suit}
        for sd in ("Left", "Right"):
            out[sd + "UpperArm"] = suit
            out[sd + "UpperLeg"] = suit
            for pn in ("LowerArm", "Hand", "LowerLeg", "Foot"):
                out[sd + pn] = trim
        return {k: game_mat(v) for k, v in out.items()}

    eye_mat = kit.material("eye", (255, 167, 124), emit=3.0)  # Spark Trooper eye, lerped to white as in game

    def pose_copy(at, bends, mats, yaw=0.0, hide=(), endo=None):
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
            cp.data.materials.append(mats[n])
            cp.hide_render = False
            if n == "Head":
                for sd in (-1, 1):
                    e = kit.box("eye", 0.27, 0.05, 0.1, at=(sd * 0.24, 0.61, 4.66))
                    e.data.materials.append(eye_mat)
                    e.matrix_world = Y @ matrix(n)

    for ob in pieces.values():
        ob.hide_render = True
    kit.studio(res=(1800, 1000), samples=64)
    # the Spark Trooper's colours (Config.Enemies: suit 40,70,140, trim 255,170,60), two of the skins and hairs
    a = colours((40, 70, 140), (255, 170, 60), (240, 190, 150), (70, 46, 30))
    b2 = colours((40, 70, 140), (255, 170, 60), (141, 95, 64), (30, 26, 24))
    c = colours((40, 70, 140), (255, 170, 60), (224, 172, 130), (160, 120, 60))
    chrome = kit.material("endo", (150, 155, 168), metal=1.0, rough=0.3)
    fly = {"LeftShoulder": ("X", -25), "RightShoulder": ("X", 70), "RightElbow": ("X", 15),
           "LeftHip": ("X", 15), "LeftKnee": ("X", -35), "RightHip": ("X", -10), "RightKnee": ("X", -15)}
    pose_copy((7.6, 0, 0), {}, a)
    pose_copy((2.6, 0, 0.6), fly, b2, yaw=35)
    pose_copy((-2.6, 0, 0), {}, c, yaw=180)
    pose_copy((-7.6, 0, 0), {"Neck": ("Z", -12)}, a, yaw=-20,
              hide=("LeftUpperArm", "LeftLowerArm", "LeftHand", "RightLowerLeg", "RightFoot"), endo=chrome)
    floor = kit.cyl("floor", 16, 16, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 25.0, 5.4), (0, 0, 2.6), lens=42)
    kit.render(os.path.join(kit.ROOT, "preview", "trooper.png"))
