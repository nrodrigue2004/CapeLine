# boss_cards.py: the boss name cards' portraits (gap-news, 2026-11-19). Poses the game's own boss meshes
# (art/export/Bosses.fbx placed from Config.BossArt like the game, as art/blender/boss_poses.py does) in one key pose
# of Shared.BossPose each (build/boss_poses.json from `lune run art/bosses/poses.luau`) and renders a low, heroic
# three-quarter view on a clear background into build/news/raw/boss_<Boss>.png; art/news/post.py then inks them
# (the comic pass) onto the cards' sheet. The bosses are machines and creatures: no person is drawn.
# Run: lune run art/bosses/poses.luau && python art/blender/boss_cards.py [--only <Boss>] [--fast]
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
OUT = os.path.join(ROOT, "build", "news", "raw")
os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
FAST = "--fast" in sys.argv
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, up, z) -> Blender (x, -z, up)
CI = C.inverted()

# each boss's card shot: the pose (a BossPose key pose by name), the camera's turn from the boss's front (degrees,
# + toward its right), how far it looks up from below (degrees), and how much of the boss's height the frame holds
# from the top (1 = all of it), or the segments to frame (focus) with some room round them (pad); the camera stands
# back until that part fits
SHOTS = {
    "RustjawPrime": dict(pose="idle", yaw=10, elev=-4, keep=0.6),
    "LumenMaw": dict(pose="idle", yaw=25, elev=-3, keep=1.0, focus=("Head", "Jaw", "Body"), pad=1.1),
    "LeviathanEngine": dict(pose="idle", yaw=-35, elev=0, keep=1.0, focus=("Head", "Jaw", "Neck"), pad=1.25),
    "NullWarFrame": dict(pose="idle", yaw=10, elev=-4, keep=0.6),
    # bosses-3 (2026-11-20, DRAFT looks)
    "StormColossus": dict(pose="idle", yaw=20, elev=-4, keep=0.85, focus=("Body", "Head", "ArmL", "ArmR"), pad=1.05),
    "SwarmQueen": dict(pose="idle", yaw=25, elev=-3, keep=1.0),
    "QuarryTitan": dict(pose="idle", yaw=15, elev=-4, keep=0.62),
}
if os.environ.get("CARD_TRY"):  # trying shots: CARD_TRY="pose,yaw,elev,keep"
    p_, y_, e_, k_ = os.environ["CARD_TRY"].split(",")
    for v in SHOTS.values():
        v.update(pose=p_, yaw=float(y_), elev=float(e_), keep=float(k_))
LENS = 40
SENSOR = 36.0


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
    p.inputs["Roughness"].default_value = 0.5
    return m


def roblox_cf(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=os.path.join(kit.ROOT, "export", "Bosses.fbx"))
# bosses-3: the second set's meshes (their names are "<Boss>_<Piece>" too)
bpy.ops.import_scene.fbx(filepath=os.path.join(kit.ROOT, "export", "Bosses2.fbx"))
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

kit.studio(res=(640, 640) if FAST else (1024, 1024), samples=12 if FAST else 48)
scene = bpy.context.scene
scene.render.film_transparent = True
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
WEAK = (255, 214, 90)
for bid, b in DATA.items():
    if (ONLY and bid != ONLY) or bid not in SHOTS:
        continue
    sh = SHOTS[bid]
    frame = next(f for f in b["frames"] if f["name"] == sh["pose"])
    hull = hull_mat(bid)
    mats = {"glow": emit(bid + "_glow", b["glow"][0]), "weak": emit("weak", WEAK, 3.0),
            "objectiveGlow": emit("obj", (255, 70, 60))}
    segs = {s: C @ roblox_cf(c) @ CI for s, c in frame["segs"].items()}
    shown = []
    for name, row in b["pieces"].items():
        src = SRC.get(bid + "_" + name)
        if not src:
            continue
        o = row["offset"]
        M = segs.get(row.get("seg", "Body"), segs["Root"])
        cp = src.copy()
        cp.data = src.data.copy()
        scene.collection.objects.link(cp)
        cp.matrix_world = M @ Matrix.Translation(Vector((o[0], -o[2], o[1]))) @ src.matrix_world.to_3x3().to_4x4()
        cp.hide_render = False
        cp.data.materials.clear()
        cp.data.materials.append(mats.get(row["role"], hull))
        cp["seg"] = row.get("seg", "Body")
        shown.append(cp)
    # a rim light in the boss's own glow colour from behind
    rim = bpy.data.lights.new("BossRim", "SUN")
    rim.energy = 4.0
    rim.color = tuple(lin(c) for c in b["glow"][0])
    rim_ob = bpy.data.objects.new("BossRim", rim)
    rim_ob.rotation_euler = (math.radians(-60), 0, math.radians(180 + sh["yaw"]))
    scene.collection.objects.link(rim_ob)
    focus = sh.get("focus")
    vs = [o.matrix_world @ v.co for o in shown if not focus or o["seg"] in focus for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    top, bot = hi.z, hi.z - (hi.z - lo.z) * sh["keep"]
    ctr = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (top + bot) / 2))
    span = max(top - bot, (hi.x - lo.x) * 0.8, (hi.y - lo.y) * 0.8) * 1.08 * sh.get("pad", 1.0)
    d = span / 2 / math.tan(math.atan(SENSOR / 2 / LENS)) + max(hi.x - lo.x, hi.y - lo.y) * 0.3
    a = math.radians(sh["yaw"])
    e = math.radians(sh["elev"])
    # the boss faces Roblox -z (Blender +y); the camera stands in front, turned yaw toward the boss's right
    eye = ctr + Vector((d * math.cos(e) * math.sin(a), d * math.cos(e) * math.cos(a), d * math.sin(e)))
    cam = kit.camera(tuple(eye), tuple(ctr), LENS)
    kit.render(os.path.join(OUT, "boss_%s.png" % bid))
    for o in shown + [rim_ob, cam]:
        bpy.data.objects.remove(o, do_unlink=True)
print("rendered", OUT)
