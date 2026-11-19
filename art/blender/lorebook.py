# lorebook.py: the render check for the lore pages' book and the HQ Lore Shelf (side-content, 2026-11-19). The game
# builds both from parts on the device (Shared.LoreBookKit); `lune run art/lore/book.luau` writes that very piece
# list to art/export/lore/book.json and this script renders it, so the preview is what Roblox draws (blocks,
# cylinders along x, balls and wedges; neon glows; three district colours side by side, the shelf behind).
# Output: art/preview/lorebook.png. PLACEHOLDER ART until a sculpted book mesh replaces the parts.
# Run: lune run art/lore/book.luau && $HOME/tools/bpyenv/bin/python art/blender/lorebook.py
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()
DATA = json.load(open(os.path.join(kit.ROOT, "export", "lore", "book.json")))

# Roblox (x, y, z) -> Blender (x, -z, y): Roblox -Z (forward) is Blender +Y, Roblox up is Blender Z
R2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def rbx_rot(rx, ry, rz):
    # CFrame.fromEulerAnglesYXZ(rx, ry, rz) = Ry * Rx * Rz
    ax, ay, az = math.radians(rx), math.radians(ry), math.radians(rz)
    Rx = Matrix(((1, 0, 0), (0, math.cos(ax), -math.sin(ax)), (0, math.sin(ax), math.cos(ax))))
    Ry = Matrix(((math.cos(ay), 0, math.sin(ay)), (0, 1, 0), (-math.sin(ay), 0, math.cos(ay))))
    Rz = Matrix(((math.cos(az), -math.sin(az), 0), (math.sin(az), math.cos(az), 0), (0, 0, 1)))
    return Ry @ Rx @ Rz


MATS = {}


def mat(rgb, material, alpha):
    key = (tuple(rgb), material, alpha)
    if key in MATS:
        return MATS[key]
    name = "M%d" % len(MATS)
    if material == "neon":
        # a see-through neon part (the halo) glows faintly in Roblox: emit by how solid it is
        m = kit.material(name, rgb, rough=0.4, emit=6.0 * (1 - (alpha or 0)) ** 2)
    elif material == "metal":
        m = kit.material(name, rgb, metal=0.9, rough=0.3)
    elif material == "fabric":
        m = kit.material(name, rgb, rough=0.85)
    else:
        m = kit.material(name, rgb, rough=0.55)
    if alpha:
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Alpha"].default_value = 1 - alpha
    MATS[key] = m
    return m


def piece(p, colors, origin, scale=1.0):
    sx, sy, sz = [v * scale for v in p["size"]]
    shape = p["shape"]
    if shape == "cylinder":
        # Roblox cylinders run along x
        ob = kit.cyl(p["name"], 0.5, 0.5, 1.0, axis="X", segs=24)
    elif shape == "ball":
        ob = kit.sphere(p["name"], 0.5)
    elif shape == "wedge":
        bm = bmesh.new()
        # Roblox wedge: the slope runs from the top back edge down to the bottom front edge
        v = [bm.verts.new(c) for c in (
            (-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5),
            (-0.5, 0.5, 0.5), (0.5, 0.5, 0.5))]
        for f in ((0, 1, 2, 3), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2), (0, 4, 5, 1)):
            bm.faces.new([v[i] for i in f])
        me = bpy.data.meshes.new(p["name"])
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(p["name"], me)
        bpy.context.scene.collection.objects.link(ob)
    else:
        ob = kit.box(p["name"], 1, 1, 1)
    # the mesh's coordinates are the piece's own Roblox-local ones: world (Roblox) = T(pos) Rot S, then into Blender
    ob.scale = (1, 1, 1)
    rot = rbx_rot(*p["rot"])
    pos = Vector(p["pos"]) * scale + Vector(origin)
    S = Matrix.Diagonal((sx, sy, sz, 1))
    ob.matrix_world = R2B.to_4x4() @ Matrix.Translation(pos) @ rot.to_4x4() @ S
    col = p["color"]
    rgb = colors.get(col) if not col.startswith("book:") else colors_all[col[5:]]["cover"]
    ob.data.materials.append(mat(rgb or (255, 0, 255), p["material"], p.get("alpha")))
    return ob


colors_all = DATA["colors"]
kit.studio(res=(1400, 900), samples=48)
# three books, floating, in three districts' colours
for i, d in enumerate(DATA["show"]):
    origin = (-3.2 + i * 3.2, 3.6 + (0.25 if i == 1 else 0), 0)  # Roblox x, y (up), z
    for p in DATA["book"]:
        piece(p, colors_all[d], origin)
# the Lore Shelf behind them (spines out), half scale so it fits the frame
shelf_colors = dict(colors_all["Downtown"])
shelf_colors["spine"] = (120, 80, 50)
for p in DATA["shelf"]:
    piece(p, shelf_colors, (0, 0, 4.5), 0.7)
# a ground plane
g = kit.box("Ground", 30, 30, 0.2, at=(0, 0, -0.1))
g.data.materials.append(kit.material("Ground", (90, 95, 110), rough=0.9))
# the book faces Roblox -z, which is Blender +y: the camera stands there, the shelf behind the books
kit.camera((1.5, 12.5, 5.6), (0, -1.0, 3.2), lens=40)
out = os.path.join(kit.ROOT, "preview", "lorebook.png")
kit.render(out)
print("wrote", out)
