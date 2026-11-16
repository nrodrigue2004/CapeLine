# kit.py: shared helpers for Capeline's Blender art scripts (run with Blender's Python, e.g. the `bpy` module).
# Every asset is built from code so it can be rebuilt, tweaked and reviewed in git like the rest of the game.
# Conventions (Roblox import):
#   * Blender Z is Roblox up (Y). A model's FRONT faces Blender +Y, which the FBX export turns into Roblox -Z
#     (Roblox's forward). Config.Art.yaw in the game fixes a whole set if the import comes in turned.
#   * Each piece is its own object named exactly as the game looks it up; the game sizes every MeshPart to
#     its own box, so only the shape inside the box matters, not the units.
#   * One colour per piece (the game sets MeshPart.Color), so colour regions are separate pieces.
#   * Keep pieces light: a few hundred to ~2,000 triangles (Roblox's limit is 20,000 per mesh).
import math
import os

import bpy  # first: the bpy module makes bmesh and mathutils importable
import bmesh  # noqa: E402
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def box(name, sx, sy, sz, at=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.translate(bm, vec=at, verts=bm.verts)
    return _obj(name, bm)


def sphere(name, r=0.5, at=(0, 0, 0), scale=(1, 1, 1), segs=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=at, verts=bm.verts)
    return _obj(name, bm)


def cyl(name, r1, r2, depth, at=(0, 0, 0), segs=16, axis="Z"):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
    elif axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=at, verts=bm.verts)
    return _obj(name, bm)


def torus(name, major, minor, at=(0, 0, 0), segs=24, csegs=8, arc=2 * math.pi, axis="Z"):
    bm = bmesh.new()
    verts = []
    n = segs if arc >= 2 * math.pi - 1e-6 else segs + 1
    for i in range(n):
        a = arc * i / segs
        ring = []
        for j in range(csegs):
            b = 2 * math.pi * j / csegs
            x = (major + minor * math.cos(b)) * math.cos(a)
            y = (major + minor * math.cos(b)) * math.sin(a)
            z = minor * math.sin(b)
            ring.append(bm.verts.new((x, y, z)))
        verts.append(ring)
    for i in range(len(verts) - (0 if n == segs else 1)):
        a, b2 = verts[i], verts[(i + 1) % len(verts)]
        for j in range(csegs):
            bm.faces.new((a[j], a[(j + 1) % csegs], b2[(j + 1) % csegs], b2[j]))
    if n != segs:
        bm.faces.new(list(reversed(verts[0])))
        bm.faces.new(verts[-1])
    if axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
    elif axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=at, verts=bm.verts)
    return _obj(name, bm)


def bevel(ob, width, segs=2):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segs
    m.limit_method = "ANGLE"
    return ob


def smooth(ob, levels=1):
    m = ob.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return ob


def apply_all(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


def join(name, parts, shade=True):
    for p in parts:
        apply_all(p)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    if shade:
        shade_auto(ob)
    return ob


def shade_auto(ob, angle=40):
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        bpy.ops.object.shade_smooth()


def deform(ob, fn):
    """Move every vertex with fn(Vector) -> Vector (bulges, tapers, curls)."""
    apply_all(ob)
    for v in ob.data.vertices:
        v.co = fn(v.co.copy())
    return ob


def mirror_x(src, name):
    me = src.data.copy()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for v in me.vertices:
        v.co.x = -v.co.x
    me.flip_normals()
    return ob


def centre(ob):
    """Move the mesh so its bounding box is centred on the origin (the game sizes it to its own box)."""
    apply_all(ob)
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    c = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
    for v in ob.data.vertices:
        v.co -= c
    ob.location = (0, 0, 0)
    return ob


def tris(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def material(name, rgb, metal=0.0, rough=0.5, emit=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    col = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1)
    p.inputs["Base Color"].default_value = col
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    if emit > 0:
        p.inputs["Emission Color"].default_value = col
        p.inputs["Emission Strength"].default_value = emit
    return m


def export_fbx(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )


def studio(res=(900, 900), samples=32):
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = samples
    s.cycles.use_denoising = True
    s.render.resolution_x, s.render.resolution_y = res
    s.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.17, 0.2, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    s.world = world
    for name, rot, energy in (("Key", (0.9, 0.2, 0.7), 3.5), ("Rim", (1.2, 0, 3.6), 2.0)):
        L = bpy.data.lights.new(name, "SUN")
        L.energy = energy
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        s.collection.objects.link(ob)


def camera(loc, target, lens=50):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = lens
    bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def loft(name, rings, segs=20, power=2.4, cap=(True, True)):
    """A smooth shape from cross-sections. rings: [(z, rx, ry, cx, cy)], bottom to top. Each ring is a
    superellipse (power 2 = ellipse, higher = boxier). Ends close on a centre point."""
    bm = bmesh.new()
    loops = []
    for z, rx, ry, cx, cy in rings:
        loop = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            c, s = math.cos(a), math.sin(a)
            x = rx * math.copysign(abs(c) ** (2 / power), c)
            y = ry * math.copysign(abs(s) ** (2 / power), s)
            loop.append(bm.verts.new((cx + x, cy + y, z)))
        loops.append(loop)
    for k in range(len(loops) - 1):
        a, b = loops[k], loops[k + 1]
        for i in range(segs):
            bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    if cap[0]:
        z, rx, ry, cx, cy = rings[0]
        c = bm.verts.new((cx, cy, z - min(rx, ry) * 0.15))
        lp = loops[0]
        for i in range(segs):
            bm.faces.new((lp[(i + 1) % segs], lp[i], c))
    if cap[1]:
        z, rx, ry, cx, cy = rings[-1]
        c = bm.verts.new((cx, cy, z + min(rx, ry) * 0.15))
        lp = loops[-1]
        for i in range(segs):
            bm.faces.new((lp[i], lp[(i + 1) % segs], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm)


def tube_along(name, points, radii, segs=10):
    """A tapered tube through points (Vector list) with a radius at each point, closed at both ends."""
    bm = bmesh.new()
    loops = []
    for k, p in enumerate(points):
        d = (points[min(k + 1, len(points) - 1)] - points[max(k - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        v = d.cross(u).normalized()
        r = radii[k]
        loops.append([bm.verts.new(p + (u * math.cos(2 * math.pi * i / segs) + v * math.sin(2 * math.pi * i / segs)) * r) for i in range(segs)])
    for k in range(len(loops) - 1):
        a, b = loops[k], loops[k + 1]
        for i in range(segs):
            bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    for idx, lp in ((0, loops[0]), (-1, loops[-1])):
        if radii[idx] > 1e-4:
            c = bm.verts.new(points[idx])
            for i in range(segs):
                bm.faces.new((lp[i], lp[(i + 1) % segs], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm)


def cut(ob, normal, keep_positive=False, fill=True):
    """Cut the mesh by the plane through the origin with this normal; keep one side and close the hole."""
    apply_all(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=normal, clear_outer=keep_positive is False, clear_inner=keep_positive is True)
    if fill:
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            try:
                bmesh.ops.edgeloop_fill(bm, edges=edges)
            except Exception:
                bmesh.ops.contextual_create(bm, geom=edges)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def shift(ob, offset):
    apply_all(ob)
    for v in ob.data.vertices:
        v.co += Vector(offset)
    return ob


def decimate(ob, ratio):
    """Fewer triangles with the same silhouette (collapse), for meshes many robots draw at once."""
    m = ob.modifiers.new("Decimate", "DECIMATE")
    m.ratio = ratio
    m.use_collapse_triangulate = True
    return ob
