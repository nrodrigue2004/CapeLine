# simrender.py: the weapons as they show in game: Roblox's own downloaded geometry for every piece, at the CFrame and
# size the game's code gives it, on Roblox's blocky body (build/weaponsim/<mode>_geo.json from simcheck.py
# --render). One cell a weapon (Classic), seen from the hero's front right. Pieces get alternating colours so a piece
# that has come off its weapon is easy to see.
#   $HOME/tools/bpyenv/bin/python art/weapons/simrender.py after|before   (each in its HeroAnim ready stance, from
# art/export/weapons/poses.json; --rest leaves the body at rest)
import json
import math
import os
import subprocess
import sys

import bpy  # first: the bpy module makes mathutils importable
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "blender"))
import kit  # noqa: E402

mode = sys.argv[-1]
pose_on = "--rest" not in sys.argv
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
data = json.load(open(os.path.join(ROOT, "build", "weaponsim", mode + "_geo.json")))
kit.reset()
POSES = json.load(open(os.path.join(ROOT, "art", "export", "weapons", "poses.json")))
HOLD = {w["id"]: w["hold"] for w in POSES["weapons"]}
# the arm joints as art/blender/weapons.py poses them (Roblox frame, at rest)
JOINTS = [("Waist", "LowerTorso", "UpperTorso", (0, 2.4, 0)), ("Neck", "UpperTorso", "Head", (0, 4.0, 0)),
          ("RightShoulder", "UpperTorso", "RightUpperArm", (1.0, 3.76, 0)),
          ("RightElbow", "RightUpperArm", "RightLowerArm", (1.5, 3.15, 0)),
          ("RightWrist", "RightLowerArm", "RightHand", (1.5, 2.3, 0)),
          ("LeftShoulder", "UpperTorso", "LeftUpperArm", (-1.0, 3.76, 0)),
          ("LeftElbow", "LeftUpperArm", "LeftLowerArm", (-1.5, 3.15, 0)),
          ("LeftWrist", "LeftLowerArm", "LeftHand", (-1.5, 2.3, 0))]


def angles(a):
    """Roblox CFrame.Angles(rx, ry, rz) as a 4x4 (Roblox frame)"""
    rx, ry, rz = (math.radians(x) for x in a)
    return Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rz, 4, "Z")


def posed(clip):
    """each body part's rest-to-posed matrix (Roblox frame) for a HeroAnim clip, as HeroAnimator writes it"""
    pose = POSES["poses"].get(clip, {}) if pose_on else {}
    W = {"LowerTorso": Matrix.Identity(4)}
    for j, parent, child, at in JOINTS:
        a = pose.get(j)
        R = angles(a) if a else Matrix.Identity(4)
        p = Vector(at)
        W[child] = W[parent] @ Matrix.Translation(p) @ R @ Matrix.Translation(-p)
    return W


MATS = {}


def mat(rgb, emit=0.0):
    k = (rgb, emit)
    if k not in MATS:
        MATS[k] = kit.material("m%d" % len(MATS), rgb, rough=0.5, emit=emit)
    return MATS[k]


COLS = [(235, 70, 60), (60, 160, 235), (250, 200, 60), (90, 200, 110), (200, 90, 220), (240, 140, 50)]
cols, cell = 6, 6.4
rows = (len(data["weapons"]) + cols - 1) // cols
d = Vector((0.8, 0.55, 0.3)).normalized()  # the camera's way: from the hero's front right, a little above
fwd = -d
right = fwd.cross(Vector((0, 0, 1))).normalized()
up = right.cross(fwd).normalized()

for i, w in enumerate(data["weapons"]):
    r, c = i // cols, i % cols
    at = right * ((c - (cols - 1) / 2) * cell) + up * (-(r - (rows - 1) / 2) * cell) - Vector((0, 0, 2.6))
    T = Matrix.Translation(at)
    Wp = posed(HOLD.get(w["id"]))
    C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox frame to Blender
    Ci = C.inverted()
    for name, p in w["parts"].items():
        s = p["size"]
        ob = kit.box(name, s[0], s[2], s[1])
        R = p["rot"]
        M = Matrix(((R[0][0], R[0][1], R[0][2], p["pos"][0]), (R[1][0], R[1][1], R[1][2], p["pos"][1]),
                    (R[2][0], R[2][1], R[2][2], p["pos"][2]), (0, 0, 0, 1)))
        ob.matrix_world = T @ C @ Wp.get(name, Matrix.Identity(4)) @ M @ Ci
        skin = "Hand" in name or name == "Head"
        ob.data.materials.append(mat((224, 172, 130) if skin else (70, 74, 88)))
    for k, p in enumerate(w["pieces"]):
        me = bpy.data.meshes.new(p["mesh"])
        me.from_pydata([tuple(v) for v in p["verts"]], [], [tuple(f) for f in p["faces"]])
        me.update()
        ob = bpy.data.objects.new(p["mesh"], me)
        bpy.context.scene.collection.objects.link(ob)
        # (the piece's verts are world Roblox studs at rest; welded, it moves with its body part)
        ob.matrix_world = T @ C @ Wp.get(p["part"], Matrix.Identity(4))
        ob.data.materials.append(mat(COLS[k % len(COLS)]))

kit.studio((cols * 260, rows * 260), 16)
cam = kit.camera(tuple(d * 80), (0, 0, 0))
cam.data.type = "ORTHO"
cam.data.ortho_scale = cols * cell
out = os.path.join(ROOT, "art", "preview", "weapons_ingame_%s.png" % mode)
raw = out[:-4] + "_raw.png"
kit.render(raw)
names = ["%d %s" % (w["id"], w["name"]) for w in data["weapons"]]
subprocess.run(["python3", os.path.join(ROOT, "art", "blender", "weapons.py"), "--sheet", raw, out, str(cols), "260",
                "|".join(names)], check=True)
os.remove(raw)
print("wrote", out)
