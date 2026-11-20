# Preview of cape sway (Fx.CapeSway, item 219): the classic box cape (LookKit back "cape:classic") hung from the
# collar hinge and turned the way CapeSway turns it, standing, running (lift 35), sprinting or falling (70) and
# strafing right (side -18). Side view and three-quarter view. Writes art/preview/cape_sway.png.
import math, os, bpy
from mathutils import Matrix, Vector
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 24
sc.render.resolution_x, sc.render.resolution_y = 1600, 520
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.28, 0.33, 1)
def mat(rgb):
    m = bpy.data.materials.new(str(rgb)); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*[c / 255 for c in rgb], 1)
    return m
body, cape = mat((70, 90, 150)), mat((200, 40, 40))
# Roblox frame (x right, y up, z back) -> Blender (x, -z, y): a hero facing Blender -y... we face +y (Roblox -z)
def R(v): return Vector((v[0], -v[2], v[1]))
def box(size, cf, m):
    bpy.ops.mesh.primitive_cube_add(size=1); o = bpy.context.object
    o.matrix_world = cf @ Matrix.Diagonal((size[0], size[2], size[1], 1))
    o.data.materials.append(m)
def roblox_cf(pos, rx=0.0, rz=0.0):
    # CFrame.Angles(rx, 0, rz) in Roblox axes: about Roblox x (Blender x) then Roblox z (Blender -y)
    return (Matrix.Translation(R(pos)) @ Matrix.Rotation(rx, 4, Vector((1, 0, 0)))
            @ Matrix.Rotation(rz, 4, Vector((0, -1, 0))))
poses = [(0, 0, "still"), (35, 0, "run"), (70, 0, "sprint/fall"), (35, -18, "strafe right")]
for i, (lift, side, _) in enumerate(poses):
    x0 = i * 7
    torso = Vector((x0, 0, 3))
    box((2, 2, 1), Matrix.Translation(R((x0, 3, 0))), body)  # torso (Roblox y up)
    box((1.2, 1.2, 1.2), Matrix.Translation(R((x0, 4.6, 0))), body)
    box((1, 2, 1), Matrix.Translation(R((x0 - 0.5, 1, 0))), body); box((1, 2, 1), Matrix.Translation(R((x0 + 0.5, 1, 0))), body)
    box((1, 2, 1), Matrix.Translation(R((x0 - 1.5, 3, 0))), body); box((1, 2, 1), Matrix.Translation(R((x0 + 1.5, 3, 0))), body)
    hinge = (x0, 3 + 2 * 0.42, 0.5 + 0.05)
    # the cape's rest place relative to the hinge (LookKit: centre (0, -0.9, 0.62) from the torso centre)
    rest = Vector((0, -0.9 - 0.84, 0.62 - 0.55))
    turn = roblox_cf(hinge, -math.radians(lift), math.radians(side))
    box((1.9, 2.8, 0.08), turn @ Matrix.Translation(R(rest)), cape)
bpy.ops.mesh.primitive_plane_add(size=80, location=(10, 0, 0)); bpy.context.object.data.materials.append(mat((90, 92, 96)))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = 30
cam.location = (35, -16, 9); cam.rotation_euler = (math.radians(75), 0, math.radians(62)); sc.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (0.7, 0.3, 0.9); sun.data.energy = 4
sc.render.filepath = os.path.join(ROOT, "art/preview/cape_sway.png")
bpy.ops.render.render(write_still=True)
