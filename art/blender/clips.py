# clips.py: the animation contact sheet (pt-anims, 2026-11-19): the game's own clips (Shared.HeroAnim,
# Shared.NpcAnim) posed on the plain blocky R15 body at their key beats, ground and mid-air, a weapon line drawn
# from the right hand for the two-handed moves (so the off hand can be seen on it). No faces or hair (those come
# only from the Roblox catalog). Robots are drawn in steel, people in a plain shirt.
# Run: lune run art/anims/frames.luau && $HOME/tools/bpyenv/bin/python art/blender/clips.py
#      -> art/preview/anim_clips_<page>.png (1 two-handed, 2 ground vs mid-air, 3 robots, 4 people and landings, 5 climb, crawl, flip and sprint)
import json
import math
import os
import sys

PAGES = [int(a) for a in sys.argv[1:] if a.isdigit()]
sys.argv = [sys.argv[0], "clips"]  # clothed.py reads its own args at import (imported: it draws nothing)
sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import clothed  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
import subprocess  # noqa: E402

ROOT = kit.ROOT
FRAMES = json.load(open(os.path.join(ROOT, "anims", "frames.json")))
RIG = json.load(open(os.path.join(ROOT, "thumbs", "pieces.json")))["rig"]
P = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox (x right, y up, z back) to Blender
# the weapon line from the right grip (Blender rest frame) by class: aim in the hand's frame, back and front reach
GRIP = Vector((1.5, 0.0, 2.15 - 0.045))
LINES = {"hilt": ((0, -0.707, -0.707), 1.3, 3.6), "pole": ((0, -1, 0), 1.6, 3.4), "long": ((0, -1, 0), 0.7, 2.6)}
COLS, DX, DZ = 8, 5.0, 7.2
YAW = -32


def matrices(joints):
    """Each part's world matrix for one pose, as HeroAnimator writes it (C0 * CFrame.new(0, py, 0) *
    CFrame.Angles(x, y, z) * C1:Inverse()); the Root's turn is left out so every cell faces the camera."""
    g = RIG["ground"]
    W = {"HumanoidRootPart": Matrix.Identity(4)}
    for j in RIG["joints"]:
        a = joints.get(j["name"])
        R = Matrix.Identity(4)
        if a:
            x, y, z = (math.radians(v) for v in a[:3])
            if j["name"] == "Root":
                y = 0.0
            Rr = Matrix.Rotation(x, 3, "X") @ Matrix.Rotation(y, 3, "Y") @ Matrix.Rotation(z, 3, "Z")
            R = (P @ Rr @ P.transposed()).to_4x4()
            if len(a) > 3 and a[3]:
                R = Matrix.Translation(Vector((0, 0, a[3]))) @ R
        px, py, pz = j["pivot"]
        pv = Vector((px, -pz, py + g))
        W[j["part1"]] = W[j["part0"]] @ Matrix.Translation(pv) @ R @ Matrix.Translation(-pv)
    return W


def stick(a, b, r, mat):
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=10, location=(a + b) / 2)
    ob = bpy.context.active_object
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    ob.data.materials.append(mat)
    return ob


def page(n, cells):
    kit.reset()
    rows = (len(cells) + COLS - 1) // COLS
    res = (2400, int(2400 * (rows * DZ + 1.6) / (COLS * DX)))
    kit.studio(res=res, samples=24)
    steel = {k: (150, 158, 172) for k in clothed.BLOCKS}
    for k in steel:
        if "Torso" in k:
            steel[k] = (90, 100, 120)
    shirt = {k: ((60, 110, 200) if ("Torso" in k or "Arm" in k) else (50, 54, 66)) for k in clothed.BLOCKS}
    for k in shirt:
        if "Hand" in k:
            shirt[k] = (224, 172, 130)
    blade = kit.material("blade", (235, 210, 90), metal=0.6, rough=0.3)
    ground = kit.material("ground", (70, 74, 84), rough=0.8)
    sky = kit.material("sky", (120, 190, 255), emit=0.4)
    for i, c in enumerate(cells):
        col, row = i % COLS, i // COLS
        x = ((COLS - 1) / 2 - col) * DX  # the camera looks back along -y: world -x is the image's right
        z = ((rows - 1) / 2 - row) * DZ - 3.0
        lift = 1.6 if c.get("air") else 0.0
        at = Vector((x, 0, z + lift))
        paint = steel if c.get("robot") else shirt
        obs = clothed.figure((0.0, 0.0, 0.0), 0, (224, 172, 130), (0, 0, 0), face=None, outfit=(None, None),
                             paint=paint, hair_on=False)
        W = matrices(c["joints"])
        Y = Matrix.Translation(at) @ Matrix.Rotation(math.radians(YAW), 4, "Z")
        for ob in obs:
            part = ob.name.split(".")[0]
            ob.matrix_world = Y @ W.get(part, Matrix.Identity(4)) @ ob.matrix_world
        if c.get("weapon"):
            aim, back, front = LINES[c["weapon"]]
            M = Y @ W["RightHand"]
            d = (P @ Vector(aim)).normalized()
            a = M @ (GRIP - d * back)
            b = M @ (GRIP + d * front)
            stick(a, b, 0.12, blade)
        if c.get("air"):
            ring = kit.cyl("air%d" % i, 1.3, 1.3, 0.08, at=(x, 0, z - 0.2), segs=24)
            ring.data.materials.append(sky)
        else:
            disc = kit.cyl("g%d" % i, 1.8, 1.8, 0.1, at=(x, 0, z - 0.05), segs=24)
            disc.data.materials.append(ground)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = COLS * DX
    bpy.context.scene.collection.objects.link(cam)
    cam.location = (0, 60, 0)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    bpy.context.scene.camera = cam
    out = os.path.join(ROOT, "preview", "anim_clips_%d.png" % n)
    kit.render(out)
    # the labels under each cell (plain python3 with PIL: art/anims/label.py)
    ppu = res[0] / (COLS * DX)
    marks = []
    for i, c in enumerate(cells):
        col, row = i % COLS, i // COLS
        z = ((rows - 1) / 2 - row) * DZ - 3.0
        marks.append([res[0] / 2 + (col - (COLS - 1) / 2) * DX * ppu, res[1] / 2 - (z - 0.9) * ppu, c["label"]])
    spec = out + ".labels.json"
    json.dump(marks, open(spec, "w"))
    subprocess.run(["python3", "-I", os.path.join(ROOT, "anims", "label.py"), out, spec], check=True)
    os.remove(spec)
    print("wrote", out)


only = PAGES or None
for n, cells in enumerate(FRAMES["pages"], 1):
    if only is None or n in only:
        page(n, cells)
