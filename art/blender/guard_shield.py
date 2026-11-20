# Preview of the held guard (GuardFx, Config.Guard.shield, item 149): the same layout as the game's parts, in three
# states side by side: raised, the hit kick and flash, and a low guard. Writes art/preview/guard_shield.png.
# Run: $HOME/tools/bpyenv/bin/python art/blender/guard_shield.py
import math, os, bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.device = "CPU"
sc.render.resolution_x, sc.render.resolution_y = 1500, 560
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.06, 0.09, 1)

def mat(name, rgb, alpha, emit):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    c = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1)
    b.inputs["Base Color"].default_value = c
    b.inputs["Emission Color"].default_value = c
    b.inputs["Emission Strength"].default_value = emit
    b.inputs["Alpha"].default_value = alpha
    m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    return m

def box(sx, sy, sz, loc, rot, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.scale = (sx, sy, sz); o.data.materials.append(m)

def disc(d, t, loc, m):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=d / 2, depth=t, location=loc, rotation=(math.pi / 2, 0, 0))
    bpy.context.object.data.materials.append(m)

SIZE, SIDES = 6, 8
def shield(x, scale, core_a, rim):
    face = mat("face", (110, 180, 255), 0.35, 0.25)
    core = mat("core", (150, 205, 255), core_a, 2)
    rm = mat("rim", rim, 0.9, 6)
    d = SIZE * scale
    disc(d, 0.25, (x, 0, 3), face)
    disc(d * 0.55, 0.12, (x, -0.12 * scale, 3), core)
    r = d / 2
    side = 2 * r * math.tan(math.pi / SIDES) + 0.05
    ap = SIZE / 2 * math.cos(math.pi / SIDES) * scale
    for i in range(SIDES):
        a = (i + 0.5) / SIDES * 2 * math.pi
        box(side, 0.3, 0.24, (x + math.sin(a) * ap, 0, 3 + math.cos(a) * ap), (0, a, 0), rm)
    # the hero's chest behind it, for scale (a block torso and head)
    body = mat("body", (60, 70, 90), 1, 0)
    box(2, 1, 2, (x, 2.2, 2.5), (0, 0, 0), body)
    box(1.2, 1.2, 1.2, (x, 2.2, 4.2), (0, 0, 0), body)

lerp = lambda a, b, g: tuple(a[i] + (b[i] - a[i]) * g for i in range(3))
shield(-9, 1.0, 0.22, (205, 235, 255))
shield(0, 1.14, 0.7, (205, 235, 255))
shield(9, 1.0, 0.22, lerp((255, 110, 80), (205, 235, 255), 0.2))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.location = (3, -24, 6.5); cam.rotation_euler = (math.radians(82), 0, math.radians(8))
cam.data.type = "ORTHO"; cam.data.ortho_scale = 27
sc.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (0.8, 0.2, 0.3)
sc.render.filepath = os.path.join(ROOT, "art/preview/guard_shield.png")
bpy.ops.render.render(write_still=True)
