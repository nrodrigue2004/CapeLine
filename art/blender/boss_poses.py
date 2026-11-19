# boss_poses.py: the boss pass's render check (2026-11-19). Poses the game's own boss meshes (art/export/Bosses.fbx,
# placed from Config.BossArt like the game) in Shared.BossPose's key poses, using the segment frames that
# art/bosses/poses.luau samples with Fx.BossAnim's maths, and renders one frame a pose into build/boss_poses/;
# art/bosses/sheet.py lays them out as art/preview/boss_poses_<Boss>.png with each pose's name.
# Run: lune run art/bosses/poses.luau && python art/blender/boss_poses.py [--only <Boss>] && python3 art/bosses/sheet.py
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()
ROOT = os.path.dirname(kit.ROOT)
DATA = json.load(open(os.path.join(ROOT, "build", "boss_poses.json")))
OUT = os.path.join(ROOT, "build", "boss_poses")
os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, up, z) -> Blender (x, -z, up)
CI = C.inverted()


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def emit(name, rgb, strength=5.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == "BSDF_PRINCIPLED":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    return m


def hull_mat(boss):
    m = bpy.data.materials.new(boss + "_tex")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(kit.ROOT, "export", "bosses", boss + "_Color.png"), check_existing=True)
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.55
    return m


def roblox_cf(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=os.path.join(kit.ROOT, "export", "Bosses.fbx"))
SRC = {}
for ob in set(bpy.data.objects) - before:
    if ob.type != "MESH":
        bpy.data.objects.remove(ob, do_unlink=True)
        continue
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    ob.data.transform(Matrix.Translation(-(lo + hi) / 2))
    SRC[ob.name.split(".")[0]] = ob
    ob.hide_render = True

kit.studio(res=(480, 480), samples=10)
WEAK = (255, 214, 90)
OBJ = (255, 70, 60)
for bid, b in DATA.items():
    if ONLY and bid != ONLY:
        continue
    hull = hull_mat(bid)
    glow = emit(bid + "_glow", b["glow"][0])
    mats = {"glow": glow, "weak": emit("weak", WEAK, 3.0), "objectiveGlow": emit("obj", OBJ)}
    sea = bid == "LeviathanEngine"
    if sea:
        w = kit.cyl("water", 300, 300, 0.3, at=(0, 0, -0.15), segs=48)
        wm = bpy.data.materials.new("water")
        wm.use_nodes = True
        pr = wm.node_tree.nodes["Principled BSDF"]
        pr.inputs["Base Color"].default_value = (0.05, 0.25, 0.35, 1)
        pr.inputs["Alpha"].default_value = 0.55
        w.data.materials.append(wm)
    else:
        f = kit.cyl("floor", 300, 300, 0.4, at=(0, 0, -0.2), segs=48)
        f.data.materials.append(kit.material("floor", (70, 74, 82), rough=0.85))
    h = b["height"]
    span = {"RustjawPrime": 1.0, "NullWarFrame": 1.0, "LumenMaw": 1.9, "LeviathanEngine": 2.4}[bid]
    d = h * 1.5 * max(1.0, span * 0.8)
    cam = kit.camera((d * 0.55, d * 0.85, h * 0.5), (0, 0, h * (0.45 if span < 1.5 else 0.3)), 32)
    for k, fr in enumerate(b["frames"]):
        shown = []
        segs = {s: C @ roblox_cf(c) @ CI for s, c in fr["segs"].items()}

        def place(name, row, at=Vector((0, 0, 0)), seg=None):
            src = SRC.get(bid + "_" + name)
            if not src:
                return
            o = row["offset"]
            M = segs.get(seg or row.get("seg", "Body"), segs["Root"])
            cp = src.copy()
            cp.data = src.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            R0 = src.matrix_world.to_3x3().to_4x4()
            cp.matrix_world = M @ Matrix.Translation(at + Vector((o[0], -o[2], o[1]))) @ R0
            cp.hide_render = False
            cp.data.materials.clear()
            cp.data.materials.append(mats.get(row["role"], hull))
            shown.append(cp)

        for name, row in b["pieces"].items():
            place(name, row)
        for a in b["anchors"]:
            for name, row in b["objective"].items():
                place(name, row, Vector((a[0], -a[2], a[1])), "Body")
        kit.render(os.path.join(OUT, "%s_%02d.png" % (bid, k)))
        for o in shown:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in list(bpy.data.objects):
        if o.name.startswith(("water", "floor", "Cam")):
            bpy.data.objects.remove(o, do_unlink=True)
print("rendered", OUT)
