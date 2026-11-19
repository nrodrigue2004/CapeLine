# The destruction previews (fix-destroy, 2026-11-19): renders art/export/destroy/frames.json (from
# `lune run art/destroy/frames.luau`, the game's own Structure, Chunker and CraterRules) into
#   art/preview/destroy_silo.png    a silo whole, holed by a super, its pancake fall, its rubble heap
#   art/preview/destroy_crater.png  a part crater on a road (the ink decal, pit and rim chunks GroundFx draws) and a
#                                   terrain crater dug into a sand seabed (CraterRules.carve's voxels, cut in half)
# Workbench render, object colours, the game's palette. Run: $HOME/tools/bpyenv/bin/python art/blender/destroy_preview.py
import json
import math
import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = json.load(open(os.path.join(ROOT, "art/export/destroy/frames.json")))
STEEL = (0.62, 0.64, 0.68, 1)
WHITE = (0.93, 0.93, 0.9, 1)
PILLAR = (0.46, 0.48, 0.52, 1)
GRASS = (0.42, 0.62, 0.32, 1)
ROAD = (0.24, 0.24, 0.27, 1)
PIT = (0.15, 0.13, 0.14, 1)
SAND = (0.86, 0.76, 0.52, 1)
SAND_DARK = (0.70, 0.60, 0.40, 1)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.78, 0.95, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = w
    L = bpy.data.lights.new("Sun", "SUN")
    L.energy = 3.2
    L.angle = math.radians(3)
    ob = bpy.data.objects.new("Sun", L)
    ob.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    sc.collection.objects.link(ob)
    MATS.clear()
    return sc


MATS = {}


def mat(color):
    key = tuple(round(c, 3) for c in color)
    m = MATS.get(key)
    if not m:
        m = bpy.data.materials.new("m%d" % len(MATS))
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = color
        b.inputs["Roughness"].default_value = 0.8
        MATS[key] = m
    return m


def obj(kind, size, loc, rot=(0, 0, 0), color=STEEL):
    # Roblox (x, up, z) studs -> Blender (x, -z, up)
    x, y, z = loc
    if kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.5, depth=1, location=(x, -z, y))
    elif kind == "ball":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.5, location=(x, -z, y))
    else:
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -z, y))
    o = bpy.context.active_object
    sx, sy, sz = size
    o.scale = (sx, sz, sy)
    rx, ry, rz = rot
    o.rotation_euler = (math.radians(rx), math.radians(-rz), math.radians(ry))
    o.data.materials.append(mat(color))
    return o


def silo_rows(rows, ox, color_wall=STEEL):
    for p in rows:
        loc = (p["x"] + ox, p["y"], p["z"])
        if p.get("disc"):
            obj("cyl", (p["w"], p["h"], p["d"]), loc, color=WHITE)
        else:
            col = PILLAR if p["kind"] == "pillar" else color_wall
            obj("box", (p["w"], p["h"], p["d"]), loc, (p.get("tilt", 0), p["ry"], p.get("tilt", 0) * 0.5), col)


def camera(loc, target, lens=40):
    from mathutils import Vector

    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam


def save(name):
    path = os.path.join(ROOT, "art/preview", name)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


# ---------------------------------------------------------------- the silo sheet
reset()
S = DATA["silo"]
gap = 34
obj("box", (gap * 4 + 30, 0.4, 60), (gap * 1.5, -0.2, 0), color=GRASS)
# 1 whole: the real body (a cylinder and its white cap)
obj("cyl", (S["r"] * 2, S["h"], S["r"] * 2), (0, S["h"] / 2, 0), color=STEEL)
obj("ball", (S["cap"], 8, S["cap"]), (0, S["h"], 0), color=WHITE)
# 2 holed by a super: the Structure stand-in with its holes
silo_rows(DATA["holed"], gap)
# 3 the pancake fall, mid-way
silo_rows(DATA["falling"], gap * 2)
# 4 the rubble heap
for r in DATA["rubble"]:
    obj("box", (r["w"], r["h"], r["d"]), (r["x"] + gap * 3, r["y"], r["z"]), (r["rx"], r["ry"], r["rz"]), (0.55, 0.56, 0.58, 1))
camera((gap * 1.5, 105, 34), (gap * 1.5, 0, 14), lens=34)  # Blender coords: (x, -z, up)
save("destroy_silo.png")

# ---------------------------------------------------------------- the crater sheet
reset()
C = DATA["crater"]
# left: a part crater on a road (what GroundFx draws): the pit disc, the ink decal's dark star, the rim chunks
ox = -26
obj("box", (44, 0.4, 44), (ox, -0.2, 0), color=ROAD)
obj("box", (44, 0.42, 1.0), (ox, -0.19, 9), color=(0.95, 0.85, 0.3, 1))
obj("cyl", (C["r"] * 1.5, 0.12, C["r"] * 1.5), (ox, 0.06, 0), color=PIT)
for k in range(10):  # the comic ink crater decal's cracks, drawn as dark spokes
    a = k / 10 * math.pi * 2
    rr = C["r"] * 1.05
    obj("box", (C["r"] * 0.9, 0.14, 0.5), (ox + math.cos(a) * rr * 0.75, 0.07, math.sin(a) * rr * 0.75), (0, -math.degrees(a), 0), PIT)
for r in C["rim"]:
    obj("box", (r["sx"], r["sy"], r["sz"]), (r["x"] + ox, r["y"], r["z"]), (0, r["ry"], r["tilt"]), (0.34, 0.33, 0.36, 1))
# right: a terrain crater, the voxels CraterRules.carve leaves in a sand seabed, cut through its middle
T = DATA["terrain"]
v = T["voxel"]
tx = 30
for vx in T["voxels"]:
    if vx["z"] > 0.1:
        continue  # the near half cut away so the bowl shows
    h = v * max(vx["o"], 0.15)
    col = SAND if vx["y"] > -v else SAND_DARK
    obj("box", (v, h, v), (vx["x"] + tx, vx["y"] - v / 2 + h / 2, vx["z"]), color=col)
camera((2, 62, 44), (2, 0, -4), lens=30)
save("destroy_crater.png")
