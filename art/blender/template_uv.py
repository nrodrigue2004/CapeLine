# template_uv.py: UV-maps a blocky R15 body part onto Roblox's classic clothing template (585 x 559), the way Roblox
# maps a Shirt and Pants onto the classic R15 body. Classic clothing on a MeshPart samples the mesh's own UVs, so
# a body mesh with no UVs (or a plain cube unwrap) shows no Shirt or Pants at all (nate's playtest-art3, 2026-11-18).
# hero.py and bodies.py call apply() on each limb and torso block after its bevel and before any reshaping, so the
# template lands on the box faces exactly as art/blender/clothed.py previews it. The same rectangles as
# Shared.ClothesMap and art/clothes/trooper.py.
from mathutils import Vector

W, H = 585, 559
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
# each face (Blender: x across, +y front, z up): the axis it faces, then the viewer's right and the image's up on it
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


def apply(ob, part):
    """Give ob (a box-like block in world space, transforms applied) the classic template UVs for R15 part `part`."""
    me = ob.data
    vs = [ob.matrix_world @ v.co for v in me.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c, half = (lo + hi) / 2, (hi - lo) / 2
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UV")
    for poly in me.polygons:
        n = (ob.matrix_world.to_3x3() @ poly.normal).normalized()
        key = max(FACES, key=lambda k: n.dot(FACES[k][0]))
        _, right, up = FACES[key]
        x, y, w, h = rect(part, key)
        er = abs(right.x) * half.x + abs(right.y) * half.y + abs(right.z) * half.z
        eu = abs(up.x) * half.x + abs(up.y) * half.y + abs(up.z) * half.z
        for li in poly.loop_indices:
            p = vs[me.loops[li].vertex_index] - c
            u = max(0.0, min(1.0, p.dot(right) / (2 * er) + 0.5))
            v = max(0.0, min(1.0, p.dot(up) / (2 * eu) + 0.5))
            px, py = x + u * w, y + (1 - v) * h
            uv.data[li].uv = (px / W, 1 - py / H)
