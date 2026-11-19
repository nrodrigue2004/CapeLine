# panels.py: the comic art pass (2026-11-19, nate: "a more cinematic game"): the guides' and mentors' portraits
# and every comic page panel, staged in Blender from the game's own looks, for art/panels/post.py to ink and
# pack. The people are Roblox's blocky R15 body (art/blender/clothed.py's body, posed with art/store/common.py's
# rig) in their game outfits: the uploaded classic clothes (art/export/clothes/people), else their creator look's
# colours, else a picked hero shirt and pants; the creator pieces that show (hats, masks, capes, pads, emblems:
# art/blender/rogues.py's shapes); and, by nate's hard rule, a Roblox catalog face and catalog hair only (no
# drawn or modelled faces, eyes, hair or facial hair): the face image and the hair accessory's own mesh and
# texture, fetched by art/panels/catalog.py into build/catalog and fitted on the head by its HairAttachment.
# Cast and pages come from art/export/panels/cast.json (lune run art/panels/cast.luau).
# Output: build/panels/raw/portrait_<key>.png (RGBA, the figure on a clear background) and
#         build/panels/raw/panel_<page>.<n>.png (RGB, the whole scene). build/ is not in git.
# Run: $HOME/tools/bpyenv/bin/python art/blender/panels.py [portraits|panels|all] [--only key,key] [--samples N]
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(HERE)
REPO = os.path.dirname(ART)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ART, "store"))
ARGV = list(sys.argv)
sys.argv = [sys.argv[0]]  # the helper scripts read sys.argv at import
import common as C  # noqa: E402
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

sys.argv = ARGV
WHAT = ([a for a in ARGV[1:] if not a.startswith("-") and a not in ("--only", "--samples")] or ["all"])[0]
ONLY = set(ARGV[ARGV.index("--only") + 1].split(",")) if "--only" in ARGV else None
SAMPLES = int(ARGV[ARGV.index("--samples") + 1]) if "--samples" in ARGV else 20
CAST = json.load(open(os.path.join(ART, "export", "panels", "cast.json"), encoding="utf-8"))
CAT = os.path.join(REPO, "build", "catalog")
RAW = os.path.join(REPO, "build", "panels", "raw")
HAIR_INDEX = json.load(open(os.path.join(CAT, "hair", "index.json")))
BODY = C.BODY
PEOPLE = {r["key"]: r for r in CAST["portraits"]}


def _rogues():
    """art/blender/rogues.py's shape helpers (pieces, cape, robot gear) without running its renders."""
    path = os.path.join(HERE, "rogues.py")
    src = open(path, encoding="utf-8").read().rsplit("\nmain()", 1)[0]
    ns = {"__file__": path, "__name__": "rogues_defs"}
    argv = sys.argv
    sys.argv = [path]
    try:
        exec(compile(src, path, "exec"), ns)
    finally:
        sys.argv = argv
    return ns


R = _rogues()


# ------------------------------------------------------------------ catalog faces and hair
def face_path(row):
    return os.path.join(CAT, "faces", "%d.png" % row["face"]["image"])


def cframe(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


HEAD_HAIR = Matrix.Translation((0, 0.6, 0))  # the blocky R15 head's HairAttachment (from the head's centre)


def catalog_hair(asset):
    """The catalog hair accessory's own mesh and texture, fitted as Roblox fits it: the handle placed so its
    HairAttachment meets the head's, the SpecialMesh's scale and offset applied. In rest coordinates (the head's
    centre at z 4.6, Blender axes)."""
    asset = int(asset)
    e = HAIR_INDEX.get(str(asset))
    if not e:
        return None
    fit = e["fit"]
    mesh = json.load(open(os.path.join(CAT, "hair", e["mesh"])))
    att = fit.get("attachment")
    handle = HEAD_HAIR @ cframe(att["cframe"]).inverted() if att else Matrix.Translation((0, 0.6, 0))
    sc = Vector(fit.get("scale") or (1, 1, 1))
    off = Vector(fit.get("offset") or (0, 0, 0))
    verts = []
    for p in mesh["pos"]:
        q = off + Vector((p[0] * sc.x, p[1] * sc.y, p[2] * sc.z))
        w = handle @ q
        verts.append((w.x, -w.z, w.y + 4.6))
    me = bpy.data.meshes.new("CatHair%d" % asset)
    me.from_pydata(verts, [], [tuple(f) for f in mesh["faces"]])
    me.update()
    uv = me.uv_layers.new(name="UV")
    for poly in me.polygons:
        for li in poly.loop_indices:
            t = mesh["uv"][me.loops[li].vertex_index]
            uv.data[li].uv = (t[0], 1 - t[1])
    for poly in me.polygons:
        poly.use_smooth = True
    ob = bpy.data.objects.new("CatHair%d" % asset, me)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new("cathair%d" % asset)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.6
    if e.get("texture"):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(CAT, "hair", e["texture"]), check_existing=True)
        nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    else:
        p.inputs["Base Color"].default_value = (0.1, 0.08, 0.06, 1)
    ob.data.materials.append(m)
    return ob


# ------------------------------------------------------------------ people
# where a hat's band sits: catalog hair is cut off above it so the hat sits on the hair (as a Roblox hat does)
HAT_CUT = {"Ball Cap": 4.98, "Top Hat": 5.3, "Wide Brim": 5.24, "Iron Crown": 5.22, "cap": 4.98, "tophat": 5.3,
           "strawhat": 5.26, "crown": 5.22}


def cut_above(ob, z):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_outer=True)
    bm.to_mesh(ob.data)
    bm.free()


def _clothes(row):
    """Per-part material maker from the person's outfit."""
    skin = tuple(row["skin"])
    o = row.get("outfit") or {}
    if row.get("clothes"):
        # a robot's uniform (art/export/clothes/uniforms) or a hero's outfit, as <base>_Shirt and <base>_Pants
        shirt = (BODY["image"](row["clothes"] + "_Shirt"), (255, 255, 255))
        pants = (BODY["image"](row["clothes"] + "_Pants"), (255, 255, 255))
    elif row.get("people"):
        shirt = (BODY["image"]("people/%s_Shirt" % row["people"]), (255, 255, 255))
        pants = (BODY["image"]("people/%s_Pants" % row["people"]), (255, 255, 255))
    elif o.get("shirt"):
        shirt = (BODY["image"]("heroes/Shirt_" + o["shirt"]), tuple(o["shirtTint"]))
        pants = (BODY["image"]("heroes/Pants_" + o["pants"]), tuple(o["pantsTint"]))
    else:
        suit = o.get("suit")
        if not suit and row.get("rgb"):
            prim, sec, acc = [tuple(c) if c else (128, 128, 128) for c in row["rgb"]]
            suit = (prim, prim, sec)
        suit = [tuple(c) for c in (suit or ((90, 90, 100), (90, 90, 100), (60, 60, 70)))]

        def painted(n, short):
            col = suit[0] if "Torso" in short else (suit[1] if short in ("UpperArm", "LowerArm", "Hand") else suit[2])
            return C.flat("suit", col, rough=0.45, coat=0.2)
        return painted

    def clothed(n, short):
        if "Torso" in short:
            layers = [pants, shirt]
        elif short in ("UpperArm", "LowerArm", "Hand"):
            layers = [shirt]
        else:
            layers = [pants]
        return C.clothes_mat(n, skin, layers)
    return clothed


def _look_page(row):
    """The person's creator look as rogues.pieces reads it, without the pieces nate's rule leaves to the
    catalog (hair, facial hair, face details, makeup)."""
    look = row.get("look")
    if not look:
        return None
    pc = {k: v for k, v in look["pieces"].items() if k not in ("hair", "beard", "makeup", "eyes", "face")}
    return {"look": dict(look, pieces=pc), "rgb": row.get("rgb"), "tints": row.get("tints") or {}}


def _extras(row, has_hat):
    """The portrait's own props (Config.Story.guides.speakers portrait extras) that are clothing or gear: a cap,
    a top hat, a straw hat, a crown, a headset, goggles, glasses, a headband, a mask, a visor, a tie, pearls, a
    mic, the Censor's black bar; and the hood or helmet shapes. Facial hair, scars and stars are left out (the
    face is the catalog's). In rest coordinates; returns (objects, covers the hair)."""
    before = set(bpy.data.objects)
    col = tuple(row.get("color") or (200, 200, 200))
    dark = (28, 28, 34)
    ex = set(row.get("extras") or [])
    covers = False
    shape = row.get("shape")
    if shape == "hood":
        hood = kit.sphere("Hood", 0.82, at=(0, -0.08, 4.72), scale=(1, 1, 1.05), segs=28, rings=16)
        kit.cut(hood, Vector((0, 1, 0)), keep_positive=False)
        R["put"](hood, tuple(int(c * 0.8) for c in (row.get("outfit") or {}).get("shirtTint", (70, 60, 90))),
                 rough=0.9)
        R["put"](kit.cyl("HoodRim", 0.8, 0.8, 0.12, at=(0, 0.08, 4.7), segs=28, axis="Y"),
                 (40, 34, 50), rough=0.9)
        covers = True
    if shape == "helmet" and not has_hat:
        h = kit.sphere("Helmet", 0.74, at=(0, -0.02, 4.78), scale=(1, 1.02, 0.95), segs=32, rings=18)
        kit.cut(h, Vector((0, 1, -0.9)).normalized(), keep_positive=False)
        R["put"](h, col, metal=0.5, rough=0.3)
        covers = True
    if not has_hat:
        if "cap" in ex:
            dome = kit.sphere("CapDome", 0.72, at=(0, 0, 4.98), scale=(1, 1, 0.66), segs=28, rings=14)
            cut_above(dome, 99)
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(dome.data)
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 4.98),
                                   plane_no=(0, 0, -1), clear_outer=True)
            bm.to_mesh(dome.data)
            bm.free()
            R["put"](dome, tuple(int(c * 0.7) for c in col), rough=0.8)
            pk = R["bx"]("CapPeak", (1.05, 0.7, 0.07), (0, 0.86, 4.98), tuple(int(c * 0.55) for c in col), bev=0.03)
            R["rot"](pk, -8, "X", (0, 0.5, 5.0))
        if "tophat" in ex:
            R["put"](kit.cyl("HatBrim", 0.85, 0.85, 0.07, at=(0, 0, 5.28), segs=32), (24, 24, 28), rough=0.7)
            R["put"](kit.cyl("HatCrown", 0.55, 0.58, 0.95, at=(0, 0, 5.78), segs=32), (24, 24, 28), rough=0.7)
            R["put"](kit.cyl("HatBand", 0.585, 0.585, 0.2, at=(0, 0, 5.42), segs=32), (190, 40, 40), rough=0.7)
        if "strawhat" in ex:
            straw = (230, 200, 120)
            R["put"](kit.cyl("Brim", 1.15, 1.15, 0.07, at=(0, 0, 5.24), segs=36), straw, rough=0.9)
            R["put"](kit.sphere("Crown", 0.62, at=(0, 0, 5.3), scale=(1, 1, 0.7), segs=28, rings=14), straw,
                     rough=0.9)
            R["put"](kit.cyl("Band", 0.63, 0.63, 0.12, at=(0, 0, 5.32), segs=28), (170, 50, 40), rough=0.8)
        if "crown" in ex:
            gold = (230, 190, 60)
            R["put"](kit.cyl("Crown", 0.66, 0.68, 0.28, at=(0, 0, 5.28), segs=32), gold, metal=0.8, rough=0.3)
            for k in range(5):
                a = 2 * math.pi * k / 5 + math.pi / 2
                R["put"](kit.cyl("Spike", 0.13, 0.0, 0.4, at=(0.64 * math.cos(a), 0.64 * math.sin(a), 5.6), segs=8),
                         gold, metal=0.8, rough=0.3)
    if "headset" in ex:
        R["put"](kit.torus("Band", 0.68, 0.05, at=(0, 0, 4.7), segs=28, csegs=8, axis="Y"), dark)
        for s in (-1, 1):
            R["put"](kit.cyl("Ear", 0.22, 0.22, 0.14, at=(s * 0.66, 0, 4.6), segs=16, axis="X"), dark)
        mic = R["bx"]("Boom", (0.05, 0.6, 0.05), (0.62, 0.35, 4.35), dark, bev=0.0)
        R["rot"](mic, -25, "Z", (0.62, 0.05, 4.35))
    if "goggles" in ex:
        R["put"](kit.cyl("Strap", 0.635, 0.635, 0.14, at=(0, 0, 4.72), segs=28), dark, rough=0.8)
        for s in (-1, 1):
            R["put"](kit.cyl("Lens", 0.2, 0.2, 0.14, at=(s * 0.25, 0.64, 4.72), segs=18, axis="Y"),
                     (150, 220, 255), metal=0.5, rough=0.1, emit=0.4)
    if "spectacles" in ex:
        rim = (60, 50, 44)
        for s in (-1, 1):
            R["put"](kit.torus("Rim", 0.16, 0.025, at=(s * 0.24, 0.66, 4.7), segs=20, csegs=6, axis="Y"), rim,
                     metal=0.6, rough=0.3)
        R["bx"]("Bridge", (0.16, 0.03, 0.03), (0, 0.66, 4.72), rim, bev=0.0)
    if "headband" in ex:
        R["put"](kit.cyl("Band", 0.64, 0.64, 0.16, at=(0, 0, 4.96), segs=28), col, rough=0.8)
        for s in (-1, 1):
            t = R["bx"]("Tail", (0.1, 0.07, 0.6), (s * 0.12, -0.7, 4.7), col, bev=0.02)
            R["rot"](t, s * 20, "Y", (s * 0.12, -0.68, 4.96))
    if "mask" in ex and not (row.get("look") or {}).get("pieces", {}).get("head"):
        R["bx"]("Mask", (1.28, 0.1, 0.32), (0, 0.63, 4.74), (230, 180, 40) if "tophat" not in ex else (240, 240, 245),
                bev=0.04, metal=0.4, rough=0.3)
    if "visor" in ex:
        R["bx"]("Visor", (1.28, 0.1, 0.22), (0, 0.65, 4.72), (255, 70, 70), bev=0.03, emit=2.5)
    if "blackbar" in ex:
        R["bx"]("Bar", (1.4, 0.06, 0.26), (0, 0.66, 4.74), (12, 12, 14), bev=0.0)
    if "tie" in ex:
        R["bx"]("Tie", (0.22, 0.06, 0.8), (0, 0.53, 3.5), (170, 30, 40), bev=0.02)
        R["bx"]("Knot", (0.26, 0.08, 0.18), (0, 0.54, 3.92), (150, 24, 34), bev=0.03)
    if "pearls" in ex:
        R["put"](kit.torus("Pearls", 0.6, 0.07, at=(0, 0.06, 3.98), segs=24, csegs=8), (245, 240, 230), rough=0.2)
    if "mic" in ex:
        R["put"](kit.cyl("Mic", 0.07, 0.07, 0.8, at=(1.5, 0.75, 2.35), segs=12), (40, 40, 46), metal=0.5)
        R["put"](kit.sphere("MicHead", 0.17, at=(1.5, 0.75, 2.85), segs=14, rings=10), (70, 70, 80), metal=0.6)
    return [o for o in bpy.data.objects if o not in before], covers


def person(key, root=None, bends=None, coll=None, arm_up=None):
    """One person from the cast on the blocky R15 body, posed. Returns (part matrices, objects)."""
    row = PEOPLE[key] if isinstance(key, str) else key
    root = root if root is not None else C.root_matrix((0, 0, C.CENTRE.z))
    M = C.rig(root, bends or {})
    coll = coll or C.collection("People")
    mat_for = _clothes(row)
    skin = tuple(row["skin"])
    obs = []
    for n in C.PARTS:
        if n == "Head":
            continue
        ob = BODY["part_box"](n)
        short = n.replace("Left", "").replace("Right", "")
        ob.data.materials.append(mat_for(n, short))
        obs.append(C._apply(ob, M[n]))
    h = BODY["head"]()
    kit.shade_auto(h, 60)
    h.data.materials.append(BODY["projected_head_mat"](skin, [(face_path(row), (255, 255, 255), "front")]))
    obs.append(C._apply(h, M["Head"]))
    # the look's pieces, then the portrait's props; each follows the head or the chest
    page = _look_page(row)
    rest = []
    has_hat = False
    if page:
        pc = page["look"]["pieces"]
        has_hat = bool(pc.get("hat")) or pc.get("head") in ("Mono Visor",)
        before = set(bpy.data.objects)
        R["pieces"](page, skin, (40, 30, 26))
        rest += [o for o in bpy.data.objects if o not in before]
    ex, covers = _extras(row, has_hat)
    rest += ex
    bpy.context.view_layer.update()
    for o in rest:
        zs = [(o.matrix_world @ v.co).z for v in o.data.vertices] if o.type == "MESH" else [0]
        mid = (min(zs) + max(zs)) / 2
        part = "Head" if mid >= 4.05 and o.name.split(".")[0] not in ("Cape", "Collar") else "UpperTorso"
        if o.name.startswith("Mic"):
            part = "RightHand"
            o.matrix_world = Matrix.Translation((0, 0, 0)) @ o.matrix_world
        obs.append(C._apply(o, M[part]))
    if row.get("hair") and not covers:
        hr = catalog_hair(row["hair"]["asset"])
        hat = (page and page["look"]["pieces"].get("hat")) or next((e for e in row.get("extras") or [] if e in HAT_CUT),
                                                                   None)
        if hr and hat in HAT_CUT:
            cut_above(hr, HAT_CUT[hat])
        if hr:
            obs.append(C._apply(hr, M["Head"]))
    for ob in obs:
        C.put(ob, coll)
    return M, obs


# ------------------------------------------------------------------ portraits
def setup(res, transparent=True, samples=None):
    kit.reset()
    C._mats.clear()
    kit.studio(res=res, samples=samples or SAMPLES)
    s = bpy.context.scene
    s.render.film_transparent = transparent
    s.view_settings.view_transform = "Standard"
    s.cycles.max_bounces = 4
    s.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.62, 1)
    s.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0


def ink(colls, thickness=2.2):
    C.outlines(colls, thickness)
    bpy.context.view_layer.use_freestyle = True


def portrait(row):
    setup((512, 512))
    person(row)
    yaw = -28
    R["frame"](yaw, (0, 0, 4.42), 3.75)
    ink(["People"], 2.4)
    path = os.path.join(RAW, "portrait_%s.png" % row["key"])
    kit.render(path)
    print("panels.py: rendered", path, flush=True)


def main():
    os.makedirs(RAW, exist_ok=True)
    if WHAT in ("portraits", "all"):
        for row in CAST["portraits"]:
            if ONLY and row["key"] not in ONLY:
                continue
            portrait(row)
    if WHAT in ("panels", "all"):
        import scenes  # noqa: E402  (art/blender/scenes.py: one staging per panel)
        for p in CAST["panels"]:
            if ONLY and p["key"] not in ONLY and p["page"] not in ONLY:
                continue
            try:
                scenes.render(p, sys.modules[__name__])
            except Exception:  # noqa: BLE001  (one bad staging never stops the batch; the log names it)
                import traceback
                traceback.print_exc()
                print("panels.py: FAILED", p["key"], flush=True)


if __name__ == "__main__":
    main()
