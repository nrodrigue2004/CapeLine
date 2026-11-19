"""fitshow.py (fix-models, 2026-11-19): renders the game's own placements of our meshes, before and after the fix.

    $HOME/tools/bpyenv/bin/python art/blender/fitshow.py build/fit/before.json build/fit/after.json GROUP [GROUP ...]

Each JSON is art/fit/placements.luau's output for one build (every MeshPart's mesh name, set, CFrame and Size, as the
game's code places it). Each mesh is drawn from our FBX the way Roblox's import stores it: centred on its box,
turned 180 degrees about y when art/models/meshturns.json says the set's meshes were (Open Cloud did that to every
set), scaled to the part's Size and put at its CFrame. So a render is what Studio shows, not what Blender drew.
Writes art/preview/modelfit_<GROUP>.png: Blender's layout (left), the build without the fix (middle), with it (right).
"""

import glob
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "art", "blender"))
import kit  # noqa: E402

FINALES = {"Bramblebeast", "Voidhound", "WindupGiant"}
TURNS = json.load(open(os.path.join(ROOT, "art", "models", "meshturns.json")))


def fbx_path(s):
    if s in FINALES:
        return os.path.join(ROOT, "art", "export", "finales", s + ".fbx")
    return os.path.join(ROOT, "art", "export", s + ".fbx")


LIB = {}


def library(s):
    """{mesh name: (Roblox-frame verts about the box centre, box size, faces, materials)} of one set's FBX."""
    if s in LIB:
        return LIB[s]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx_path(s))
    out = {}
    for ob in set(bpy.data.objects) - before:
        if ob.type != "MESH":
            continue
        M = ob.matrix_world
        vs = [M @ v.co for v in ob.data.vertices]
        r = [Vector((v.x, v.z, -v.y)) for v in vs]
        lo = Vector((min(v.x for v in r), min(v.y for v in r), min(v.z for v in r)))
        hi = Vector((max(v.x for v in r), max(v.y for v in r), max(v.z for v in r)))
        c = (lo + hi) / 2
        faces = [tuple(p.vertices) for p in ob.data.polygons]
        mats = [p.material_index for p in ob.data.polygons]
        uvl = ob.data.uv_layers.active
        uv = [tuple(d.uv) for d in uvl.data] if uvl else None
        out[ob.name.split(".")[0]] = ([v - c for v in r], hi - lo, faces, mats, list(ob.data.materials), uv)
        ob.hide_render = True
        ob.hide_set(True)
    LIB[s] = out
    return out


MATS = {}


def colour_map(name, s):
    """The baked colour map a textured mesh carries (art/export/**/<Look>_Color.png), by the mesh name's first word."""
    for cand in (name.split("_")[0], s):
        hits = glob.glob(os.path.join(ROOT, "art", "export", "**", cand + "_Color.png"), recursive=True)
        if hits:
            return hits[0]
    return None


def paint(row, s):
    """The part's look as Studio shows it: its baked colour map (SurfaceAppearance) or its Color, Neon glowing."""
    tex = colour_map(row["name"], s) if row.get("maps") else None
    key = (tex, tuple(round(c, 2) for c in row.get("color", (0.7, 0.7, 0.7))), row.get("neon"))
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("Fit")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    col = tuple(row.get("color", (0.7, 0.7, 0.7))) + (1,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.55
    if tex:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(tex, check_existing=True)
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    if row.get("neon"):
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 3
    MATS[key] = m
    return m


def place(row, shift, coll, drawn=False):
    s = row.get("set")
    if not s:
        return None
    lib = library(s)
    src = lib.get(row["name"])
    if not src:
        return None
    verts, box, faces, mats, materials, _ = src
    turned = not drawn and TURNS.get(s, {}).get("verdict") == "rotY180"
    size = row["size"]
    k = [size[i] / box[i] if box[i] > 1e-6 else 1 for i in range(3)]
    c = row["cf"]
    R = Matrix(((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11])))
    P = Vector((c[0], c[1], c[2]))
    pts = []
    for v in verts:
        m = Vector((-v.x, v.y, -v.z)) if turned else v  # what Roblox's copy of the mesh holds
        m = Vector((m.x * k[0], m.y * k[1], m.z * k[2]))
        w = R @ m + P
        pts.append((w.x + shift, -w.z, w.y))
    me = bpy.data.meshes.new(row["name"])
    me.from_pydata(pts, [], faces)
    uv = src[5]
    if uv:
        layer = me.uv_layers.new(name="UV")
        for i, loop in enumerate(layer.data):
            loop.uv = uv[i]
    me.materials.append(paint(row, s))
    me.update()
    ob = bpy.data.objects.new(row["name"], me)
    coll.objects.link(ob)
    return ob


def label(text, at, size):
    cu = bpy.data.curves.new("L", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("L", cu)
    ob.location = at
    ob.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new("Lbl")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 1, 1, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2
    cu.materials.append(m)


def caption(path, g):
    """The three panels' names along the top (system python3 with PIL: Blender's python has none)."""
    code = (
        "import sys\nfrom PIL import Image, ImageDraw, ImageFont\n"
        "im = Image.open(sys.argv[1]).convert('RGB'); d = ImageDraw.Draw(im)\n"
        "try:\n    f = ImageFont.truetype('DejaVuSans-Bold.ttf', 28)\nexcept OSError:\n    f = ImageFont.load_default()\n"
        "w = im.width / 3\n"
        "for i, t in enumerate(('Blender layout', 'in game before', 'in game after (MeshFix)')):\n"
        "    d.text((w * i + 24, 16), sys.argv[2] + ': ' + t, fill=(255, 255, 255), font=f)\n"
        "im.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-I", "-c", code, path, g], check=False)


def main():
    before_path, after_path, groups = sys.argv[1], sys.argv[2], sys.argv[3:]
    data = (json.load(open(before_path)), json.load(open(after_path)))
    for g in groups:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        LIB.clear()
        MATS.clear()
        kit.studio(res=(2100, 700), samples=24)
        coll = bpy.context.scene.collection
        rows = data[1][g]
        xs = [r["cf"][0] for r in rows]
        width = (max(xs) - min(xs)) + max(max(r["size"]) for r in rows) + 4
        cx = (max(xs) + min(xs)) / 2
        obs = []
        # left: Blender's own layout (the unfixed build's frames are the drawn ones, drawn as the FBX has them);
        # middle: what the unfixed build shows in Roblox; right: what the fixed build shows
        for side, (d, drawn) in enumerate(((data[0], True), (data[0], False), (data[1], False))):
            shift = (1 - side) * width * 1.1 - cx  # (the camera looks down -y: +x is on the left)
            for r in d[g]:
                ob = place(r, shift, coll, drawn)
                if ob:
                    obs.append(ob)
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for ob in obs:
            for v in ob.data.vertices:
                lo = Vector(map(min, lo, v.co))
                hi = Vector(map(max, hi, v.co))
        mid = (lo + hi) / 2
        span = max(hi.x - lo.x, (hi.z - lo.z) * 2)

        # the front (Roblox's -z, Blender's +y), from a little above and to the side
        d = Vector((0.3, 1.0, 0.45)).normalized()
        cam = kit.camera(mid + d * (span + (hi - lo).length) * 1.5, mid, lens=42)
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = max(hi.x - lo.x, (hi.z - lo.z) * 2, hi.y - lo.y) * 1.08
        cam.data.clip_end = 10000
        out = os.path.join(ROOT, "art", "preview", "modelfit_" + g + ".png")
        kit.render(out)
        caption(out, g)
        print("wrote", out)


main()
