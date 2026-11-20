# Preview of the throwables' part builds (Config.Throw.dress, item 154; ThrowFx.dressPart lays them out the same
# way): each kind's plain box on the left, its build on the right. Reads art/export/throw_dress.json (run
# `lune run art/throw/dress.luau` first). Writes art/preview/throwables.png.
import json, math, os, bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
data = json.load(open(os.path.join(ROOT, "art/export/throw_dress.json")))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 24
sc.render.resolution_x, sc.render.resolution_y = 1800, 520
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.28, 0.33, 1)
mats = {}
def mat(rgb):
    k = tuple(rgb)
    if k not in mats:
        m = bpy.data.materials.new(str(k)); m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*[c / 255 for c in rgb], 1)
        mats[k] = m
    return mats[k]

# Roblox frame (x right, y up, z back) -> Blender (x, -z, y)
def rb(v): return Vector((v[0], -v[2], v[1]))
def place(obj, at_cf, size, cyl):
    obj.matrix_world = at_cf
    obj.scale = (size[0], size[2], size[1]) if not cyl else (size[0], size[1], size[2])

def add_part(origin, p):
    r = p.get("rot", [0, 0, 0])
    # Roblox CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz in Roblox axes; map each axis to Blender
    R = (Matrix.Rotation(math.radians(r[0]), 4, Vector((1, 0, 0)))
         @ Matrix.Rotation(math.radians(r[1]), 4, Vector((0, 0, 1)))
         @ Matrix.Rotation(math.radians(r[2]), 4, Vector((0, -1, 0))))
    s = p["size"]
    if p.get("shape") == "Cylinder":
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.5, depth=1)
        o = bpy.context.object
        # Roblox cylinder axis = local x
        o.data.transform(Matrix.Rotation(math.radians(90), 4, "Y"))
        S = Matrix.Diagonal((s[0], s[2], s[1], 1))
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.object
        S = Matrix.Diagonal((s[0], s[2], s[1], 1))
    o.matrix_world = Matrix.Translation(origin + rb(p["at"])) @ R @ S
    o.data.materials.append(mat(p["color"]))

x = 0
for kind in sorted(data):
    d = data[kind]
    b = d["box"]
    base = Vector((x, 0, b[1] / 2))
    bpy.ops.mesh.primitive_cube_add(size=1, location=base); o = bpy.context.object
    o.scale = (b[0], b[2], b[1]); o.data.materials.append(mat(d["color"]))
    base2 = Vector((x + b[0] + 1.5, 0, b[1] / 2))
    for p in d["parts"]:
        add_part(base2, p)
    x += 2 * b[0] + 5
bpy.ops.mesh.primitive_plane_add(size=200, location=(x / 2, 0, 0)); bpy.context.object.data.materials.append(mat([90, 92, 96]))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = x * 0.92
cam.location = (x / 2 + 2, 40, 18); cam.rotation_euler = (math.radians(68), 0, math.radians(174))
sc.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (0.7, 0.3, -0.5); sun.data.energy = 4
sc.render.filepath = os.path.join(ROOT, "art/preview/throwables.png")
bpy.ops.render.render(write_still=True)
