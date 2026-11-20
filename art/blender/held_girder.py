# Preview of Girder Swing's held girder (CombatFx.heldGirder, item 178) next to a blocky hero's arm, the same
# pieces as the game. Writes art/preview/held_girder.png.
import math, os, bpy
from mathutils import Matrix, Vector
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 24
sc.render.resolution_x, sc.render.resolution_y = 1000, 700
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.28, 0.33, 1)
def mat(rgb, metal=0.0):
    m = bpy.data.materials.new(str(rgb)); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[c / 255 for c in rgb], 1); b.inputs["Metallic"].default_value = metal
    return m
def box(size, loc, m, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.object
    o.scale = size; o.data.materials.append(m)
    if rot: o.rotation_euler = rot
    return o
# the hero (blocky body), right arm held out forward, the girder along the hand's -Y (here: out in front)
body = mat((70, 80, 110))
box((2, 1, 2), (0, 0, 3), body); box((1.2, 1.2, 1.2), (0, 0, 4.7), body)
box((1, 1, 2), (-0.5, 0, 1), body); box((1, 1, 2), (0.5, 0, 1), body)
box((1, 1, 2), (-1.5, 0, 3), body)
box((1, 2.2, 1), (1.5, -1.1, 3.4), body)  # the right arm, forward
L = 11
steel, dark = mat((204, 84, 52), 0.6), mat((120, 48, 30), 0.6)
c = Vector((1.5, -2.3 - (L / 2 - 0.6), 3.4))
box((0.22, L, 0.9), c, steel)  # web: the hand's x by the line by z (z up here)
box((0.9, L, 0.16), c + Vector((0, 0, 0.45)), steel)
box((0.9, L, 0.16), c + Vector((0, 0, -0.45)), steel)
box((0.95, 0.12, 1.06), c + Vector((0, -L / 2, 0)), dark)
bpy.ops.mesh.primitive_plane_add(size=80); bpy.context.object.data.materials.append(mat((90, 92, 96)))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.location = (14, -10, 9); cam.rotation_euler = (math.radians(68), 0, math.radians(58)); sc.camera = cam
cam.data.lens = 30
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (0.7, 0.3, 0.9); sun.data.energy = 4
sc.render.filepath = os.path.join(ROOT, "art/preview/held_girder.png")
bpy.ops.render.render(write_still=True)
