# clothed.py: preview of a robot as a plain Roblox character in classic clothing (nate, 2026-11-17: "just looks
# like a roblox character with clothes"). The standard blocky R15 body (block proportions as hero.py), each part
# UV-mapped onto Roblox's classic clothing template exactly as Roblox maps a Shirt and Pants, the face decal on the
# head and the hair accessory. Uses the textures art/clothes/<robot>.py draws into art/export/clothes.
# Run: python art/blender/clothed.py [Trooper]   (with the `bpy` module) -> art/preview/clothed_<robot>.png
#      python art/blender/clothed.py uniforms Grunt   -> art/preview/uniforms_grunt.png (every robot kind in that
#      version of its uniform, art/clothes/uniforms.py); python art/blender/clothed.py uniforms Grunt new ->
#      art/preview/uniforms_new_grunt.png (the 9 kinds added with the new enemy types; `chains`: the side quest
#      chains' Wind-Up Toy, Wind-Up Giant and Salt Dog, front and back, into uniforms_chains_<version>.png); then
#      python3 art/clothes/uniforms.py --stack makes art/preview/uniforms.png and uniforms_new.png
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ARGS = [a for a in sys.argv[1:] if not a.startswith("-")]
ROBOT = ARGS[0] if ARGS else "Trooper"
VERSION = ARGS[1] if len(ARGS) > 1 else "Grunt"
CLOTHES = os.path.join(kit.ROOT, "export", "clothes")
W, H = 585, 559

kit.reset()

# the blocky R15 body (Blender: x across, +y front, z up; feet on z = 0), left side (the right mirrors it)
BLOCKS = {
    "UpperTorso": (-1.0, 1.0, -0.5, 0.5, 2.4, 4.0),
    "LowerTorso": (-1.0, 1.0, -0.5, 0.5, 2.0, 2.4),
    "LeftUpperArm": (-2.0, -1.0, -0.5, 0.5, 3.15, 4.0),
    "LeftLowerArm": (-2.0, -1.0, -0.5, 0.5, 2.3, 3.15),
    "LeftHand": (-2.0, -1.0, -0.5, 0.5, 2.0, 2.3),
    "LeftUpperLeg": (-1.0, 0.0, -0.5, 0.5, 1.15, 2.0),
    "LeftLowerLeg": (-1.0, 0.0, -0.5, 0.5, 0.3, 1.15),
    "LeftFoot": (-1.0, 0.0, -0.5, 0.5, 0.0, 0.3),
}
for k in list(BLOCKS):
    if k.startswith("Left"):
        x0, x1, y0, y1, z0, z1 = BLOCKS[k]
        BLOCKS["Right" + k[4:]] = (-x1, -x0, y0, y1, z0, z1)

# Roblox's classic clothing template (see art/clothes/trooper.py)
TORSO = {"F": (231, 74, 128, 128), "B": (427, 74, 128, 128), "R": (165, 74, 64, 128), "L": (361, 74, 64, 128),
         "U": (231, 8, 128, 64), "D": (231, 204, 128, 64)}
RIGHT = {"L": (19, 355, 64, 128), "B": (85, 355, 64, 128), "R": (151, 355, 64, 128), "F": (217, 355, 64, 128),
         "U": (217, 289, 64, 64), "D": (217, 485, 64, 64)}
LEFT = {"F": (308, 355, 64, 128), "L": (374, 355, 64, 128), "B": (440, 355, 64, 128), "R": (506, 355, 64, 128),
        "U": (308, 289, 64, 64), "D": (308, 485, 64, 64)}
# which rows of a 128 px strip each R15 part takes (Roblox's R15 split of classic clothing)
ROWS = {"UpperTorso": (0, 102), "LowerTorso": (102, 128), "UpperArm": (0, 54), "LowerArm": (54, 108),
        "Hand": (108, 128), "UpperLeg": (0, 54), "LowerLeg": (54, 108), "Foot": (108, 128)}
TOPS = ("UpperTorso", "UpperArm", "UpperLeg")
BOTTOMS = ("LowerTorso", "Hand", "Foot")
# each face: the axis it faces, then the viewer's right and the image's up on it
FACES = {
    "F": (Vector((0, 1, 0)), Vector((-1, 0, 0)), Vector((0, 0, 1))),
    "B": (Vector((0, -1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1))),
    "R": (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))),
    "L": (Vector((-1, 0, 0)), Vector((0, -1, 0)), Vector((0, 0, 1))),
    "U": (Vector((0, 0, 1)), Vector((-1, 0, 0)), Vector((0, -1, 0))),
    "D": (Vector((0, 0, -1)), Vector((-1, 0, 0)), Vector((0, 1, 0))),
}


def rect(part, face):
    """The template rectangle (x, y, w, h) a part's face shows."""
    short = part.replace("Left", "").replace("Right", "")
    slots = TORSO if "Torso" in part else (RIGHT if part.startswith("Right") else LEFT)
    if face == "U":
        if short in TOPS:
            return slots["U"]
        face = "F"  # hidden inside the body
    if face == "D":
        if short in BOTTOMS:
            return slots["D"]
        face = "F"
    x, y, w, h = slots[face]
    r0, r1 = ROWS[short]
    return (x, y + r0, w, r1 - r0)


def image(name):
    path = os.path.join(CLOTHES, name + ".png")
    img = bpy.data.images.load(path, check_existing=True)
    img.alpha_mode = "STRAIGHT"
    return img

FACES_DIR = os.path.join(CLOTHES, "faces")


def face_img(name, turned):
    # a name with a folder ("people/Face_Gus") is that file under art/export/clothes (the side quests' people)
    path = (os.path.join(CLOTHES, name + ".png") if "/" in name
            else os.path.join(FACES_DIR, "Face_%s%s.png" % (name, "_Turned" if turned else "")))
    img = bpy.data.images.load(path)
    img.alpha_mode = "STRAIGHT"
    return img


def clothed_mat(name, skin, layers):
    """The part's colour (skin) under the Pants, then the Shirt, as Roblox layers classic clothing."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.62
    col = nt.nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = (*(lin(c) for c in skin), 1)
    last = col.outputs[0]
    for img in layers:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.interpolation = "Closest"  # Roblox shows the template's pixels crisp
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(t.outputs["Alpha"], mix.inputs["Factor"])
        nt.links.new(last, mix.inputs["A"])
        nt.links.new(t.outputs["Color"], mix.inputs["B"])
        last = mix.outputs["Result"]
    nt.links.new(last, p.inputs["Base Color"])
    return m


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def srgb(c):
    """kit.material takes 0-255 linear-ish values: convert a Roblox (sRGB) colour so it renders true."""
    return tuple(lin(v) * 255 for v in c)


def part_box(name):
    x0, x1, y0, y1, z0, z1 = BLOCKS[name]
    ob = kit.box(name, x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = 0.035
    m.segments = 2
    kit.apply_all(ob)
    c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    half = Vector(((x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2))
    me = ob.data
    uv = me.uv_layers.new(name="UV")
    for poly in me.polygons:
        n = poly.normal
        key = max(FACES, key=lambda k: n.dot(FACES[k][0]))
        _, right, up = FACES[key]
        x, y, w, h = rect(name, key)
        er = abs(right.x) * half.x + abs(right.y) * half.y + abs(right.z) * half.z
        eu = abs(up.x) * half.x + abs(up.y) * half.y + abs(up.z) * half.z
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co - c
            u = max(0.0, min(1.0, p.dot(right) / (2 * er) + 0.5))
            v = max(0.0, min(1.0, p.dot(up) / (2 * eu) + 0.5))
            px, py = x + u * w, y + (1 - v) * h
            uv.data[li].uv = (px / W, 1 - py / H)
    kit.shade_auto(ob, 30)
    return ob


def head():
    # the classic rounded Roblox head (1.2 studs), skin coloured
    rings = []
    for z, r in ((4.02, 0.4), (4.05, 0.5), (4.1, 0.56), (4.18, 0.6), (4.3, 0.62), (4.92, 0.62), (5.04, 0.6),
                 (5.12, 0.56), (5.17, 0.5), (5.2, 0.4)):
        rings.append((z, r, r, 0, 0))
    return kit.loft("Head", rings, segs=32, power=2.6)


def hair():
    # swept-back hair: the accessory (the same shape as the Trooper's Hair mesh)
    rings = []
    for z, r, cy in ((4.66, 0.65, 0.0), (4.85, 0.67, -0.02), (5.05, 0.66, -0.04), (5.2, 0.6, -0.06),
                     (5.3, 0.48, -0.08), (5.36, 0.31, -0.1)):
        rings.append((z, r, r, 0, cy))
    cap = kit.loft("cap", rings, segs=24, power=2.4)
    for v in cap.data.vertices:
        if v.co.y > 0.25 and v.co.z < 5.0:
            v.co.z = 5.0 + (v.co.z - 4.66) * 0.3
    q = kit.box("q", 0.56, 0.42, 0.32, at=(-0.07, 0.41, 5.26))
    kit.bevel(q, 0.06, 2)
    kit.deform(q, lambda v: Vector((v.x, v.y, v.z + 0.12 * max(0.0, v.y - 0.3))))
    subs = [cap, q]
    for k, x in enumerate((-0.32, 0.0, 0.32)):
        sp = kit.cyl("sp%d" % k, 0.17, 0.02, 0.5, at=(x, -0.54, 5.12), segs=8, axis="Y")
        kit.deform(sp, lambda v, x=x: Vector((v.x + (v.x - x) * 0.3, v.y, v.z + 0.15 * (-0.54 - v.y))))
        subs.append(sp)
    for s in (-1, 1):
        sb = kit.box("sb", 0.1, 0.35, 0.4, at=(s * 0.64, -0.03, 4.7))
        kit.bevel(sb, 0.03, 1)
        subs.append(sb)
    return kit.join("Hair", subs)


def face_plane(turned, name):
    bpy.ops.mesh.primitive_plane_add(size=1.12, location=(0, 0.635, 4.6), rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.active_object
    m = bpy.data.materials.new("face")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = face_img(name, turned)
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], p.inputs["Alpha"])
    p.inputs["Roughness"].default_value = 0.5
    if turned:
        nt.links.new(t.outputs["Color"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = 1.2
    ob.data.materials.append(m)
    return ob



def projected_head_mat(skin, layers):
    """The head's skin with decals projected onto it face by face, as Roblox draws a head's Decals (each image
    flat across its face of the head's box, shown where the surface faces that way). layers: (path, tint, face),
    bottom first (the face decal, then a mask)."""
    m = bpy.data.materials.new("head_decals")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.55
    col = nt.nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = (*(lin(c) for c in skin), 1)
    last = col.outputs[0]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    pos = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], pos.inputs[0])
    nrm = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Normal"], nrm.inputs[0])
    # face -> (u from axis, u sign, normal axis, normal sign); v is always up (z), the head's centre z 4.6
    axes = {"front": ("X", -1, "Y", 1), "back": ("X", 1, "Y", -1), "left": ("Y", -1, "X", -1),
            "right": ("Y", 1, "X", 1), "top": ("X", -1, "Z", 1)}

    def math_node(op, a, b=None, val=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        nt.links.new(a, n.inputs[0])
        if b is not None:
            nt.links.new(b, n.inputs[1])
        elif val is not None:
            n.inputs[1].default_value = val
        return n.outputs[0]

    for path, tint, face in layers:
        ua, us, na, ns = axes[face]
        u = math_node("ADD", math_node("MULTIPLY", pos.outputs[ua], val=us / 1.24), val=0.5)
        if face == "top":
            v = math_node("ADD", math_node("MULTIPLY", pos.outputs["Y"], val=-1 / 1.24), val=0.5)
        else:
            v = math_node("ADD", math_node("MULTIPLY", math_node("SUBTRACT", pos.outputs["Z"], val=4.6), val=1 / 1.2),
                          val=0.5)
        vec = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(u, vec.inputs[0])
        nt.links.new(v, vec.inputs[1])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(path, check_existing=True)
        t.image.alpha_mode = "STRAIGHT"
        t.extension = "CLIP"
        nt.links.new(vec.outputs[0], t.inputs["Vector"])
        facing = math_node("GREATER_THAN", math_node("MULTIPLY", nrm.outputs[na], val=ns), val=0.35)
        fac = math_node("MULTIPLY", t.outputs["Alpha"], facing)
        tinted_c = nt.nodes.new("ShaderNodeMix")
        tinted_c.data_type = "RGBA"
        tinted_c.blend_type = "MULTIPLY"
        tinted_c.inputs["Factor"].default_value = 1.0
        nt.links.new(t.outputs["Color"], tinted_c.inputs["A"])
        tinted_c.inputs["B"].default_value = (*(lin(c) for c in tint), 1)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(fac, mix.inputs["Factor"])
        nt.links.new(last, mix.inputs["A"])
        nt.links.new(tinted_c.outputs["Result"], mix.inputs["B"])
        last = mix.outputs["Result"]
    nt.links.new(last, p.inputs["Base Color"])
    return m


def figure(at, yaw, skin, hair_rgb, turned=False, arm_up=False, face="Hero", outfit=None, layered=False, paint=None,
           decals=None, hair_on=True):
    """outfit: the clothes image's name (under art/export/clothes), shirt and pants as <outfit>_Shirt/_Pants;
    paint: the body's own part colours under the clothes (torso, arms, legs: a creator suit's paint), else skin"""
    outfit = outfit or ROBOT
    shirt_img, pants_img = image(outfit + "_Shirt"), image(outfit + "_Pants")
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    obs = []
    for name in BLOCKS:
        ob = part_box(name)
        short = name.replace("Left", "").replace("Right", "")
        # as the game's robots wear them (Shared.ClothesMap): the upper torso and arms show the shirt, the lower
        # torso and legs the pants
        layers = [shirt_img] if short in ("UpperTorso", "UpperArm", "LowerArm", "Hand") else [pants_img]
        if layered and "Torso" in short:
            layers = [pants_img, shirt_img]  # a real Shirt and Pants on a Humanoid: the shirt over the pants
        under = skin
        if paint:
            under = paint[0] if "Torso" in short else (paint[1] if short in ("UpperArm", "LowerArm", "Hand") else paint[2])
        ob.data.materials.append(clothed_mat(name, under, layers))
        if arm_up and name in ("RightUpperArm", "RightLowerArm", "RightHand"):
            pivot = Vector((1.0, 0, 3.76))
            ob.data.transform(Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-125), 4, "Y")
                              @ Matrix.Translation(-pivot))
        obs.append(ob)
    h = head()
    kit.shade_auto(h, 60)
    if decals is not None:
        # a creator mask's head decals (art/clothes/masks.py) over the face, projected onto the head
        fpath = os.path.join(FACES_DIR, "Face_%s.png" % face)
        h.data.materials.append(projected_head_mat(skin, [(fpath, (255, 255, 255), "front")] + decals))
        obs.append(h)
    else:
        h.data.materials.append(kit.material("skin%d" % len(bpy.data.materials), srgb(skin), rough=0.55))
        obs.append(h)
        obs.append(face_plane(turned, face))
    if hair_on:
        hr = hair()
        kit.shade_auto(hr, 40)
        hr.data.materials.append(kit.material("hair%d" % len(bpy.data.materials), srgb(hair_rgb), rough=0.6))
        obs.append(hr)
    for ob in obs:
        ob.matrix_world = Y @ ob.matrix_world


if __name__ != "__main__":
    pass  # imported (art/blender/rogues.py uses figure() and the helpers): no preview
elif ROBOT == "heroes":
    # heroes in our own Roblox-style clothes (art/clothes/heroes.py), with our faces
    skins = [(240, 190, 150), (141, 95, 64), (224, 172, 130), (198, 140, 96), (92, 62, 44), (250, 210, 180),
             (170, 120, 84), (232, 180, 140)]
    hairs = [(70, 46, 30), (30, 26, 24), (160, 120, 60), (20, 20, 22), (120, 50, 30), (200, 170, 110),
             (60, 40, 28), (150, 140, 170)]
    faces = ["Hero", "Stern", "Sharp", "Rookie", "Cold", "Scarred", "Hero", "Sharp"]
    kit.studio(res=(2400, 760), samples=48)
    page = int(VERSION) if VERSION.isdigit() else 1  # clothed.py heroes 2: outfits 9 to 16
    for i in range(8):
        figure(((3.5 - i) * 4.4, 0, 0), (i % 3 - 1) * 12, skins[i], hairs[i], face=faces[i],
               outfit="heroes/preview/Hero%d" % ((page - 1) * 8 + i + 1), layered=True)
    floor = kit.cyl("floor", 24, 24, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 40.0, 4.2), (0, 0, 2.3), lens=37)
    kit.render(os.path.join(kit.ROOT, "preview", "hero_clothes.png" if page == 1 else "hero_clothes_%d.png" % page))
elif ROBOT == "people":
    # the side quests' people in their own outfits and faces (art/clothes/people.py writes preview.json): one page
    # of 8 (`people 1` .. `people 5`) into art/preview/people_<page>.png
    import json
    page = int(VERSION) if VERSION.isdigit() else 1
    rows = json.load(open(os.path.join(CLOTHES, "people", "preview.json")))[page - 1]
    kit.studio(res=(2400, 760), samples=48)
    # a short page (the famous fakes, page 6) shows each person from the front and from the back, closer up
    if len(rows) <= 4:
        rows = [dict(r, back=b) for r in rows for b in (False, True)]
    n = len(rows)
    for i, r in enumerate(rows):
        yaw = 180 + 15 if r.get("back") else (i % 3 - 1) * 12
        figure((((n - 1) / 2 - i) * 4.4, 0, 0), yaw, tuple(r["skin"]), tuple(r["hair"]), face=r["face"],
               outfit="people/" + r["name"])
    floor = kit.cyl("floor", 24, 24, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 40.0 * max(n, 6) / 8, 4.2), (0, 0, 2.3), lens=37)
    kit.render(os.path.join(kit.ROOT, "preview", "people_%d.png" % page))
elif ROBOT == "masks":
    # the creator's flat masks as head decals (art/clothes/masks.py writes preview.json), shoulders up: `masks`
    # from the front into art/preview/masks_front.png, `masks back` turned round into masks_back.png
    # (python3 art/clothes/masks.py --stack then makes art/preview/masks.png)
    import json
    rows = json.load(open(os.path.join(CLOTHES, "masks", "preview.json")))
    tints = {"p": (40, 110, 220), "s": (235, 60, 60), "a": (255, 210, 60), "white": (255, 255, 255)}
    skins = [(240, 190, 150), (141, 95, 64), (224, 172, 130), (198, 140, 96), (92, 62, 44), (250, 210, 180),
             (170, 120, 84), (232, 180, 140)]
    back = VERSION == "back"
    kit.studio(res=(2400, 520), samples=40)
    n = len(rows)
    folder = os.path.join(CLOTHES, "masks")
    for i, r in enumerate(rows):
        tint = tints[r["tint"]]
        decals = []
        for side, name in (("front", "Front"), ("left", "Side"), ("right", "Side"), ("back", "Back"), ("top", "Top")):
            f = os.path.join(folder, "Mask%s_%s.png" % (name, r["kit"]))
            if side == "back" and not os.path.isfile(f):
                f = os.path.join(folder, "MaskSide_%s.png" % r["kit"])
            if os.path.isfile(f):
                decals.append((f, tint, side))
        yaw = (150 if back else 0) + (i % 3 - 1) * 22
        figure((((n - 1) / 2 - i) * 2.9, 0, 0), yaw, skins[i], (40, 30, 26), face="Hero",
               outfit="heroes/preview/Hero%d" % (i + 1), layered=True, decals=decals,
               hair_on=r["kit"] not in ("cowl", "ninja"))
    kit.camera((0, 24.0, 5.0), (0, 0, 4.3), lens=36)
    kit.render(os.path.join(kit.ROOT, "preview", "masks_back.png" if back else "masks_front.png"))
elif ROBOT == "suits":
    # the creator's Suits tab as Shirt and Pants overlays over each suit's body paint (art/clothes/suits.py writes
    # preview.json): one page of 8 (`suits 1` .. `suits 6`) into art/preview/suits_<page>.png
    import json
    page = int(VERSION) if VERSION.isdigit() else 1
    rows = json.load(open(os.path.join(CLOTHES, "suits", "preview.json")))[page - 1]
    skins = [(240, 190, 150), (141, 95, 64), (224, 172, 130), (198, 140, 96), (92, 62, 44), (250, 210, 180),
             (170, 120, 84), (232, 180, 140)]
    kit.studio(res=(2400, 760), samples=40)
    n = len(rows)
    for i, r in enumerate(rows):
        paint = [tuple(c) for c in r["paint"]]
        paint = [skins[i] if c == (224, 172, 130) else c for c in paint]
        figure((((n - 1) / 2 - i) * 4.4, 0, 0), (i % 3 - 1) * 12, skins[i], (40, 30, 26), face="Hero",
               outfit=r["name"], layered=True, paint=paint)
    floor = kit.cyl("floor", 24, 24, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 40.0, 4.2), (0, 0, 2.3), lens=37)
    kit.render(os.path.join(kit.ROOT, "preview", "suits_%d.png" % page))
elif ROBOT == "uniforms":
    # every robot kind in one version of its uniform, with mixed skins, faces and hair (art/clothes/uniforms.py)
    # `uniforms <Version> new`: the 9 kinds added with the new enemy types, into uniforms_new_<version>.png
    # (python3 art/clothes/uniforms.py --stack then stacks each page's three versions)
    page = ARGS[2] if len(ARGS) > 2 else ""
    if page == "new":
        kinds = ["ShieldBearer", "Captain", "Sniper", "Bomber", "MedicUnit", "Swarmer", "Mimic", "Interceptor",
                 "Grappler"]
    elif page == "chains":
        # the side quest chains' robot kinds (lore step 11): the Toymaker's toys and giant, Captain Brine's crew,
        # each from the front and the back
        kinds = ["WindupToy", "WindupToy", "WindupGiant", "WindupGiant", "SaltDog", "SaltDog"]
    else:
        kinds = ["SparkDrone", "BurglarBot", "SneakBot", "BruteBot", "Turret", "NullSentinel", "Diver", "Anchor",
                 "TorpedoSentry"]
    skins = [(240, 190, 150), (141, 95, 64), (224, 172, 130), (198, 140, 96), (92, 62, 44), (250, 210, 180),
             (170, 120, 84), (120, 80, 56), (232, 180, 140)]
    hairs = [(70, 46, 30), (30, 26, 24), (160, 120, 60), (20, 20, 22), (120, 50, 30), (200, 170, 110),
             (60, 40, 28), (40, 34, 30), (150, 140, 170)]
    faces = ["Hero", "Stern", "Sharp", "Scarred", "Rookie", "Cold"]
    kit.studio(res=(2600, 760), samples=48)
    n = len(kinds)
    for i, k in enumerate(kinds):
        back = page == "chains" and i % 2 == 1
        yaw = 195 if back else (i % 3 - 1) * 12
        figure((((n - 1) / 2 - i) * 4.4, 0, 0), yaw, skins[i], hairs[i], turned=(i == 3 and not page == "chains"),
               face=faces[i % len(faces)], outfit="uniforms/%s_%s" % (k, VERSION))
    floor = kit.cyl("floor", 24, 24, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 44.0 * max(n, 6) / 9, 4.2), (0, 0, 2.3), lens=37)
    kit.render(os.path.join(kit.ROOT, "preview", "uniforms_%s%s.png" % (page + "_" if page else "", VERSION.lower())))
else:
    kit.studio(res=(1800, 1000), samples=64)
    figure((7.6, 0, 0), 0, (240, 190, 150), (70, 46, 30), face="Hero")
    figure((2.6, 0, 0), 20, (141, 95, 64), (30, 26, 24), arm_up=True, face="Stern")
    figure((-2.6, 0, 0), 0, (224, 172, 130), (160, 120, 60), face="Sharp")
    figure((-7.6, 0, 0), -15, (198, 140, 96), (70, 46, 30), turned=True, face="Scarred")
    floor = kit.cyl("floor", 16, 16, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 25.0, 5.4), (0, 0, 2.6), lens=42)
    kit.render(os.path.join(kit.ROOT, "preview", "clothed_%s.png" % ROBOT.lower()))
