"""fit_bodies.py (fix-respawn, 2026-11-19; nate: "Clothes dont fit on certain body sizes"): every gender x build x
height dressed as the game dresses it, drawn the way Roblox draws it.

    flock /tmp/capeline-lune.lock ~/tools/lune run art/fit/bodies.luau build/Capeline.rbxl build/fit/bodies.json
    nice $HOME/tools/bpyenv/bin/python art/blender/fit_bodies.py [--torsos FBX] [--tag NAME] [--outfits 1,2,3]

Bodies come from build/fit/bodies.json (art/fit/bodies.luau: the game's LookKit and LookService on Roblox's body,
shaped and stood up by its joints). Each body part is Roblox's own mesh (build/robloxbody, art/fit/robloxbody.py),
or the body set's torso (Art.BodyTorsos: the FBX given, default art/export/BodyTorsos.fbx, turned 180 degrees about
up as Roblox's import stores it), scaled to the part's size. Classic clothing is drawn as Roblox draws it on R15:
the template is composited into Roblox's own per-limb layout (the UV layout of Roblox's own body meshes), and a part
samples that at its mesh's UVs. So for every face corner its UV is looked up in that layout (which triangle of
Roblox's own mesh holds it) and turned back into the template spot Roblox's mesh shows there; a UV outside the
layout draws magenta (Roblox shows the composite's empty space there). Pieces come from their FBX like
fitshow.py. Writes art/preview/fit_bodies[_TAG]_<outfit>.png: rows Male/Female x Small, Medium, Large, Titan;
columns the five heights.
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
import template_uv  # noqa: E402

ARG = sys.argv
TORSOS = ARG[ARG.index("--torsos") + 1] if "--torsos" in ARG else os.path.join(ROOT, "art", "export", "BodyTorsos.fbx")
TAG = ARG[ARG.index("--tag") + 1] if "--tag" in ARG else ""
ONLY = [int(x) for x in ARG[ARG.index("--outfits") + 1].split(",")] if "--outfits" in ARG else None
DATA = json.load(open(os.path.join(ROOT, "build", "fit", "bodies.json")))
TURNS = json.load(open(os.path.join(ROOT, "art", "models", "meshturns.json")))
CLOTHES = os.path.join(ROOT, "art", "export", "clothes", "heroes")
GROUP = {
    "UpperTorso": "torso", "LowerTorso": "torso",
    "LeftUpperArm": "larm", "LeftLowerArm": "larm", "LeftHand": "larm",
    "RightUpperArm": "rarm", "RightLowerArm": "rarm", "RightHand": "rarm",
    "LeftUpperLeg": "lleg", "LeftLowerLeg": "lleg", "LeftFoot": "lleg",
    "RightUpperLeg": "rleg", "RightLowerLeg": "rleg", "RightFoot": "rleg",
}


def r2b(v):
    """Roblox (x right, y up, z back) to Blender (x right, y front, z up)."""
    return Vector((v[0], -v[2], v[1]))


# ---------------------------------------------------------------- Roblox's own meshes and their layout
RB = {}


def roblox_part(name):
    if name not in RB:
        d = json.load(open(os.path.join(ROOT, "build", "robloxbody", name + ".json")))
        RB[name] = d
    return RB[name]


OWN = {}


def template_of_roblox(name):
    if name not in OWN:
        OWN[name] = template_of_roblox_(name)
    return OWN[name]


def template_of_roblox_(name):
    """Per face corner of Roblox's own mesh: (mesh-file uv, template uv) by template_uv's face mapping."""
    d = roblox_part(name)
    me = bpy.data.meshes.new("tmp_" + name)
    me.from_pydata([r2b(p) for p in d["pos"]], [], [tuple(f[:3]) for f in d["faces"]])
    me.update()
    ob = bpy.data.objects.new("tmp_" + name, me)
    bpy.context.scene.collection.objects.link(ob)
    template_uv.apply(ob, name)
    layer = me.uv_layers.active
    tris = []
    for poly in me.polygons:
        li = list(poly.loop_indices)
        fu = [tuple(d["uv"][me.loops[i].vertex_index]) for i in li]
        tu = [tuple(layer.data[i].uv) for i in li]
        tris.append((fu, tu))
    bpy.data.objects.remove(ob, do_unlink=True)
    return tris


LAYOUT = {}


def layout(group):
    if group not in LAYOUT:
        tris = []
        for part, g in GROUP.items():
            if g == group:
                tris += template_of_roblox(part)
        LAYOUT[group] = tris
    return LAYOUT[group]


def bary(fu, u, v):
    (x1, y1), (x2, y2), (x3, y3) = fu
    den = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    if abs(den) < 1e-12:
        return None
    a = ((y2 - y3) * (u - x3) + (x3 - x2) * (v - y3)) / den
    b = ((y3 - y1) * (u - x3) + (x1 - x3) * (v - y3)) / den
    return a, b, 1 - a - b


def to_template(group, corner):
    """A face's mesh-file UVs in Roblox's layout -> the template UVs Roblox's own mesh shows there (None: empty
    space). The whole face takes the layout triangle under its centre, so a face never straddles two template
    rectangles (a corner on a seam belongs to every triangle that meets there)."""
    cu = sum(c[0] for c in corner) / len(corner)
    cv = sum(c[1] for c in corner) / len(corner)
    for fu, tu in layout(group):
        w = bary(fu, cu, cv)
        if w and min(w) >= -1e-4:
            out = []
            for u, v in corner:
                a, b, c = bary(fu, u, v)
                out.append((tu[0][0] * a + tu[1][0] * b + tu[2][0] * c, tu[0][1] * a + tu[1][1] * b + tu[2][1] * c))
            return out
    return None


# ---------------------------------------------------------------- the body sets' torsos as Roblox stores them
TORSO_LIB = {}


def torso_lib():
    if TORSO_LIB:
        return TORSO_LIB
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=TORSOS)
    for ob in set(bpy.data.objects) - before:
        if ob.type != "MESH":
            continue
        M = ob.matrix_world
        r = [M @ v.co for v in ob.data.vertices]
        r = [Vector((v.x, v.z, -v.y)) for v in r]  # Blender -> Roblox
        r = [Vector((-v.x, v.y, -v.z)) for v in r]  # Roblox's import turns it 180 degrees about up
        lo = Vector([min(v[k] for v in r) for k in range(3)])
        hi = Vector([max(v[k] for v in r) for k in range(3)])
        c = (lo + hi) / 2
        uvl = ob.data.uv_layers.active
        loops = []
        for poly in ob.data.polygons:
            corner = []
            for li in poly.loop_indices:
                uv = uvl.data[li].uv
                corner.append((ob.data.loops[li].vertex_index, (uv[0], 1 - uv[1])))  # mesh-file v is down
            loops.append(corner)
        TORSO_LIB[ob.name.split(".")[0]] = ([v - c for v in r], hi - lo, loops)
        bpy.data.objects.remove(ob, do_unlink=True)
    return TORSO_LIB


# ---------------------------------------------------------------- materials
MATS = {}
COL = 7.0  # studs between columns (a Very tall Titan is about 6 wide)
MAGENTA = (1.0, 0.0, 1.0, 1.0)


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def clothes_image(kind, shirt, pants):
    """The template a group shows (pants under the shirt on the torso), tinted, composited in PIL."""
    out = os.path.join(ROOT, "build", "fit", "tex_%s_%s_%s.png" % (kind, shirt and shirt["kit"], pants and pants["kit"]))
    if not os.path.exists(out):
        layers = []
        if pants and kind in ("torso", "leg"):
            layers.append((os.path.join(CLOTHES, "Pants_%s.png" % pants["kit"]), pants["color"]))
        if shirt and kind in ("torso", "arm"):
            layers.append((os.path.join(CLOTHES, "Shirt_%s.png" % shirt["kit"]), shirt["color"]))
        code = (
            "import sys, json\nfrom PIL import Image, ImageChops\n"
            "layers = json.loads(sys.argv[2])\nbase = Image.new('RGBA', (585, 559), (0, 0, 0, 0))\n"
            "for path, c in layers:\n"
            "    im = Image.open(path).convert('RGBA').resize((585, 559))\n"
            "    tint = Image.new('RGBA', im.size, tuple(int(x * 255) for x in c) + (255,))\n"
            "    rgb = ImageChops.multiply(im, tint); rgb.putalpha(im.getchannel('A'))\n"
            "    base = Image.alpha_composite(base, rgb)\n"
            "base.save(sys.argv[1])\n"
        )
        subprocess.run(["python3", "-I", "-c", code, out, json.dumps(layers)], check=True)
    return out


def body_mat(color, image):
    key = (tuple(round(c, 3) for c in color), image)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("Body")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.6
    col = lin(color) + (1,)
    if image:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image, check_existing=True)
        tex.interpolation = "Closest"
        attr = nt.nodes.new("ShaderNodeVertexColor")  # magenta where the UV falls outside Roblox's layout
        attr.layer_name = "Miss"
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.inputs["Color1"].default_value = col
        nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
        nt.links.new(tex.outputs["Color"], mix.inputs["Color2"])
        miss = nt.nodes.new("ShaderNodeMixRGB")
        miss.inputs["Color2"].default_value = MAGENTA
        nt.links.new(mix.outputs["Color"], miss.inputs["Color1"])
        nt.links.new(attr.outputs["Color"], miss.inputs["Fac"])
        nt.links.new(miss.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = col
    MATS[key] = m
    return m


def piece_mat(row):
    tex = None
    if row.get("maps"):
        for cand in (row["name"].split("_")[0], row.get("set") or ""):
            hits = glob.glob(os.path.join(ROOT, "art", "export", "**", cand + "_Color.png"), recursive=True)
            if hits:
                tex = hits[0]
                break
    key = ("piece", tex, tuple(round(c, 2) for c in row["color"]), row.get("neon"))
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("Piece")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    col = lin(row["color"]) + (1,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.5
    if tex:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(tex, check_existing=True)
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    if row.get("neon"):
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 3
    MATS[key] = m
    return m


# ---------------------------------------------------------------- placing
def world(cf, local, shift):
    R = Matrix(((cf[3], cf[4], cf[5]), (cf[6], cf[7], cf[8]), (cf[9], cf[10], cf[11])))
    w = R @ local + Vector((cf[0], cf[1], cf[2]))
    return Vector((w.x + shift[0], -w.z + shift[1], w.y))


STATS = {"miss": 0, "corners": 0}


def draw_part(row, b, shift, coll):
    name = row["name"]
    size = row["size"]
    group = GROUP.get(name)
    kind = "torso" if group == "torso" else ("arm" if group in ("larm", "rarm") else "leg")
    if row.get("mesh"):
        lib = torso_lib()
        verts, box, loops = lib[row["mesh"]]
        k = [size[i] / box[i] for i in range(3)]
        pts = [world(row["cf"], Vector((v.x * k[0], v.y * k[1], v.z * k[2])), shift) for v in verts]
        faces = [tuple(vi for vi, _ in corner) for corner in loops]
        uvs = [[uv for _, uv in corner] for corner in loops]
    else:
        d = roblox_part(name)
        box = d["size"]
        k = [size[i] / box[i] for i in range(3)]
        pts = [world(row["cf"], Vector((p[0] * k[0], p[1] * k[1], p[2] * k[2])), shift) for p in d["pos"]]
        faces = [tuple(f[:3]) for f in d["faces"]]
        uvs = [[tuple(d["uv"][i]) for i in f[:3]] for f in d["faces"]]
    me = bpy.data.meshes.new(name)
    me.from_pydata(pts, [], faces)
    image = None
    if group and (b.get("shirt") or b.get("pants")):
        image = clothes_image(kind, b.get("shirt"), b.get("pants"))
        me.uv_layers.new(name="UV")
        me.color_attributes.new("Miss", "FLOAT_COLOR", "CORNER")
        # (fetched again after both exist: adding an attribute moves the others, so an older handle writes nowhere)
        layer, miss = me.uv_layers["UV"], me.color_attributes["Miss"]
        n = 0
        own = None if row.get("mesh") else template_of_roblox(name)
        for fi, (poly, corner) in enumerate(zip(me.polygons, uvs)):
            # Roblox's own mesh: its own face's template spot; a body set torso: through Roblox's layout
            ts = own[fi][1] if own else to_template(group, corner)
            STATS["corners"] += len(corner)
            for k, li in enumerate(poly.loop_indices):
                if ts is None:
                    STATS["miss"] += 1
                    miss.data[li].color = (1, 1, 1, 1)
                    layer.data[li].uv = (0, 0)
                else:
                    miss.data[li].color = (0, 0, 0, 1)
                    layer.data[li].uv = ts[k]
                n += 1
    me.materials.append(body_mat(row["color"], image))
    me.update()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


PIECE_LIB = {}


def piece_lib(s):
    if s in PIECE_LIB:
        return PIECE_LIB[s]
    finales = {"Bramblebeast", "Voidhound", "WindupGiant"}
    path = os.path.join(ROOT, "art", "export", "finales", s + ".fbx") if s in finales else os.path.join(
        ROOT, "art", "export", s + ".fbx")
    out = {}
    if os.path.exists(path):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=path)
        for ob in set(bpy.data.objects) - before:
            if ob.type == "MESH":
                M = ob.matrix_world
                r = [M @ v.co for v in ob.data.vertices]
                r = [Vector((v.x, v.z, -v.y)) for v in r]
                lo = Vector([min(v[k] for v in r) for k in range(3)])
                hi = Vector([max(v[k] for v in r) for k in range(3)])
                c = (lo + hi) / 2
                uvl = ob.data.uv_layers.active
                uv = [tuple(d.uv) for d in uvl.data] if uvl else None
                out[ob.name.split(".")[0]] = ([v - c for v in r], hi - lo, [tuple(p.vertices) for p in ob.data.polygons], uv)
            bpy.data.objects.remove(ob, do_unlink=True)
    PIECE_LIB[s] = out
    return out


def draw_piece(row, shift, coll):
    s = row.get("set")
    src = s and piece_lib(s).get(row["name"])
    if not src:
        return None
    verts, box, faces, uv = src
    turned = TURNS.get(s, {}).get("verdict") == "rotY180"
    size = row["size"]
    k = [size[i] / box[i] if box[i] > 1e-6 else 1 for i in range(3)]
    pts = []
    for v in verts:
        m = Vector((-v.x, v.y, -v.z)) if turned else v
        pts.append(world(row["cf"], Vector((m.x * k[0], m.y * k[1], m.z * k[2])), shift))
    me = bpy.data.meshes.new(row["name"])
    me.from_pydata(pts, [], faces)
    if uv:
        layer = me.uv_layers.new(name="UV")
        for i, loop in enumerate(layer.data):
            loop.uv = uv[i]
    me.materials.append(piece_mat(row))
    me.update()
    ob = bpy.data.objects.new(row["name"], me)
    coll.objects.link(ob)
    return ob


def caption(path, title, rows, cols, colx, rowy):
    code = (
        "import sys, json\nfrom PIL import Image, ImageDraw, ImageFont\n"
        "im = Image.open(sys.argv[1]).convert('RGB'); d = ImageDraw.Draw(im)\n"
        "try:\n    f = ImageFont.truetype('DejaVuSans-Bold.ttf', 22)\nexcept OSError:\n    f = ImageFont.load_default()\n"
        "rows, cols = json.loads(sys.argv[3]), json.loads(sys.argv[4])\n"
        "colx, rowy = json.loads(sys.argv[5]), json.loads(sys.argv[6])\n"
        "d.text((16, 10), sys.argv[2], fill=(255, 255, 255), font=f)\n"
        "for t, y in zip(rows, rowy):\n    d.text((10, y), t, fill=(255, 230, 120), font=f)\n"
        "for t, x in zip(cols, colx):\n    d.text((x - d.textlength(t, font=f) / 2, 40), t, fill=(200, 220, 255), font=f)\n"
        "im.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-I", "-c", code, path, title, json.dumps(rows), json.dumps(cols), json.dumps(colx), json.dumps(rowy)], check=False)


def main():
    builds = ["Small", "Medium", "Large", "Titan"]
    heights = ["Short", "Below", "Average", "Tall", "Very tall"]
    for oi, oname in enumerate(DATA["outfits"], 1):
        if ONLY and oi not in ONLY:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        PIECE_LIB.clear()
        TORSO_LIB.clear()
        LAYOUT.clear()
        STATS["miss"] = STATS["corners"] = 0
        kit.studio(res=(1200, 1760), samples=8)
        coll = bpy.context.scene.collection
        rows = []
        for b in DATA["bodies"]:
            if b["outfit"] != oi:
                continue
            r = (b["gender"] - 1) * 4 + (b["build"] - 1)
            c = b["height"] - 1
            shift = (c * COL, 0)
            zrow = (7 - r) * 9.0
            for p in b["parts"]:
                p = dict(p)
                cf = list(p["cf"])
                cf[1] += zrow
                p["cf"] = cf
                draw_part(p, b, shift, coll)
            for p in b["pieces"]:
                p = dict(p)
                cf = list(p["cf"])
                cf[1] += zrow
                p["cf"] = cf
                draw_piece(p, shift, coll)
        for g in ("Male", "Female"):
            for bl in builds:
                rows.append(g + " " + bl)
        lo, hi = Vector((-4, -3, -1)), Vector((4 * COL + 4, 3, 8 * 9.0))
        mid = (lo + hi) / 2
        mid = Vector((mid.x - 2.5, 0, mid.z + 1.5))  # (room on the left for the row names, on top for the title)
        cam = kit.camera(Vector((mid.x, 200, mid.z)), mid, lens=50)  # the front: Roblox's -z is Blender's +y
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = (hi.z - lo.z) * 1.08
        cam.data.clip_end = 1000
        name = "fit_bodies" + ("_" + TAG if TAG else "") + "_" + oname.replace(" ", "").lower() + ".png"
        out = os.path.join(ROOT, "art", "preview", name)
        kit.render(out)
        # label spots from the camera (ortho: the image's height spans ortho_scale; from the front +x is on the left)
        W, H = 1200, 1760
        k = H / cam.data.ortho_scale
        colx = [W / 2 - (c * COL - mid.x) * k for c in range(5)]
        rowy = [H / 2 - ((7 - r) * 9.0 + 7.0 - mid.z) * k for r in range(8)]
        caption(out, "%s%s: every body as the game dresses it (front)" % (oname, (" [" + TAG + "]") if TAG else ""),
                rows, heights, colx, rowy)
        print("wrote", out, "clothing corners", STATS["corners"], "outside Roblox's layout", STATS["miss"])


main()
