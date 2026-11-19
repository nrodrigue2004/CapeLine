# carry.py: the carry preview (fix-carry, 2026-11-19; nate after gaps7: "when i pickup cars or items or whatever i
# should actually hold them. Unless i have powers like telekinesis then i could make them float"). The plain
# blocky R15 body posed in the game's hold clips with each carried thing where Shared.CarryPose puts it (the
# frames come from the game's own sums: art/carry/frames.luau). The car is the game's CarSedan mesh
# (art/export/Vehicles.fbx), the robot the blocky body in steel; telekinesis glows in the path's colour.
# No faces or hair (those come only from the Roblox catalog).
# Run: lune run art/carry/frames.luau && $HOME/tools/bpyenv/bin/python art/blender/carry.py
#      -> art/preview/carry.png (and art/preview/carry_<n>.png per cell)
import json
import math
import os
import sys

ONLY = [a for a in sys.argv[1:] if a.isdigit()]
sys.argv = [sys.argv[0], "carry"]  # clothed.py reads its own args at import (imported: it draws nothing)
sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import clothed  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = kit.ROOT
DATA = json.load(open(os.path.join(ROOT, "carry", "frames.json")))
G = DATA["ground"]
P4 = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, up, back) to Blender
PREV = os.path.join(ROOT, "preview")


def cf(c):
    x, y, z, a, b, cc, d, e, f, g, h, i = c
    return Matrix(((a, b, cc, x), (d, e, f, y), (g, h, i, z), (0, 0, 0, 1)))


def to_blender(m):
    """a Roblox root-frame transform as a Blender world transform (feet on z = 0, the root G up)"""
    return Matrix.Translation((0, 0, G)) @ P4 @ m @ P4.transposed() @ Matrix.Translation((0, 0, -G))


def box_world(c):
    return Matrix.Translation((0, 0, G)) @ P4 @ cf(c) @ P4.transposed()


SHIRT = {k: ((210, 60, 60) if ("Torso" in k or "Arm" in k) else (40, 46, 90)) for k in clothed.BLOCKS}
for k in SHIRT:
    if "Hand" in k:
        SHIRT[k] = (240, 196, 150)
STEEL = {k: ((90, 100, 120) if "Torso" in k else (150, 158, 172)) for k in clothed.BLOCKS}


def figure(paint):
    obs = clothed.figure((0.0, 0.0, 0.0), 0, (240, 196, 150), (0, 0, 0), face=None, outfit=(None, None),
                         paint=paint, hair_on=False)
    return obs


def pose(obs, deltas, extra=Matrix.Identity(4)):
    for ob in obs:
        part = ob.name.split(".")[0]
        d = deltas.get(part)
        if part.startswith("Head") or part == "Head":
            d = deltas.get("Head")
        m = to_blender(cf(d)) if d else Matrix.Identity(4)
        ob.matrix_world = extra @ m @ ob.matrix_world


CAR = None


def car_meshes():
    global CAR
    if CAR is None:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, "export", "Vehicles.fbx"))
        new = [o for o in bpy.data.objects if o not in before]
        CAR = [o for o in new if o.name.startswith("CarSedan")]
        for o in new:
            if o not in CAR:
                bpy.data.objects.remove(o, do_unlink=True)
        for o in CAR:
            # each mesh centred on its own box, then put at its offset from the car's middle (Config.VehicleArt)
            lo = Vector((1e9, 1e9, 1e9))
            hi = Vector((-1e9, -1e9, -1e9))
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
            o.data.transform(Matrix.Translation(-(lo + hi) / 2) @ o.matrix_world)
            off = DATA["car"].get(o.name.split(".")[0], (0, 0, 0))
            o.matrix_world = Matrix.Translation(P4.to_3x3() @ Vector(off))
            o.hide_render = True
            o.data.materials.clear()
            name = o.name.split(".")[0]
            rgb = (220, 50, 46)
            if "Glass" in name:
                rgb = (120, 170, 210)
            elif "Wheel" in name or "Detail" in name:
                rgb = (40, 40, 46)
            elif "Lamp" in name or "Tail" in name:
                rgb = (250, 236, 180)
            o.data.materials.append(kit.material("car_" + name, clothed.srgb(rgb), metal=0.2, rough=0.4))
    out = []
    for o in CAR:
        cp = o.copy()
        cp.data = o.data.copy()
        cp["rest"] = list(o.matrix_world.translation)
        cp.hide_render = False
        bpy.context.scene.collection.objects.link(cp)
        out.append(cp)
    return out


def held(c, shift):
    k = c["kind"]
    B = shift @ box_world(c["box"])
    sx, sy, sz = c["size"]
    obs = []
    if k == "car":
        for o in car_meshes():
            o.matrix_world = B @ Matrix.Translation(Vector(o["rest"]))
            obs.append(o)
    elif k == "robot":
        # the blocky body in steel, its middle (half its 5.25-stud height) on the box's middle
        fig = figure(STEEL)
        for o in fig:
            o.matrix_world = B @ Matrix.Translation((0, 0, -2.625)) @ o.matrix_world
        obs += fig
    else:
        rgb = {"crate": (46, 110, 70), "bench": (150, 102, 64), "pole": (48, 60, 56)}[k]
        ob = kit.box("held", sx, sz, sy)
        ob.data.materials.append(kit.material("held_" + k, clothed.srgb(rgb), metal=0.3, rough=0.5))
        ob.matrix_world = B
        obs.append(ob)
        if k == "bench":
            for dz in (-0.6, 0.6):
                slat = kit.box("slat", sx + 0.1, 0.12, 0.2, at=(0, 0, dz))
                slat.data.materials.append(kit.material("slat", clothed.srgb((110, 72, 44))))
                slat.matrix_world = B @ slat.matrix_world
    if c["glow"]:
        # the telekinesis glow: a soft shell in the Mind colour and a light
        g = kit.box("glow", sx + 0.6, sz + 0.6, sy + 0.6)
        m = kit.material("glow", (255, 70, 220), emit=1.5)
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Alpha"].default_value = 0.18
        g.data.materials.append(m)
        g.matrix_world = B
        light = bpy.data.objects.new("tk", bpy.data.lights.new("tk", "POINT"))
        light.data.energy = 900
        light.data.color = (1.0, 0.45, 0.9)
        light.location = B.translation
        bpy.context.scene.collection.objects.link(light)
    return obs


def render(n, c):
    kit.reset()
    global CAR
    CAR = None
    kit.studio(res=(800, 800), samples=24)
    ground = kit.material("ground", (0.35, 0.36, 0.4), rough=0.85)
    lift = 3.0 if c["air"] else 0.0
    shift = Matrix.Translation((0, 0, lift))
    pose(figure(SHIRT), c["deltas"], shift)
    held(c, shift)
    disc = kit.cyl("g", 7, 7, 0.1, at=(0, 0, -0.05), segs=48)
    disc.data.materials.append(ground)
    kit.camera((-15.5, 17.0, 9.5 + lift * 0.6), (0, 0, 4.4 + lift * 0.7), lens=40)
    out = os.path.join(PREV, "carry_%d.png" % n)
    kit.render(out)
    return out


shots = []
for n, c in enumerate(DATA["cells"], 1):
    if ONLY and str(n) not in ONLY:
        continue
    shots.append((render(n, c), c["label"]))
json.dump(shots, open(os.path.join(PREV, "carry.shots.json"), "w"))
print("rendered", len(shots))
