# pocket.py: a preview render of a mission or side quest pocket in its kit look (2026-11-19, the pocket kit pass),
# from the game's own layout and dressing (art/city/pocket.luau writes art/export/city/pocket_<name>.json from
# Shared.PocketLayout and Shared.PocketDress) with the kit's textures (art/city/materials.py and
# pocket_materials.py, tinted like the game tints them), the street props (street.py), the sign boards' lettering
# and the PointLights, the way a high preset sees it. Like block.py, for the pockets.
# Run: lune run art/city/pocket.luau [-- --plain] [name ...] && python art/blender/pocket.py <name> [--plain] [--fast]
#   (with the `bpy` module, Blender 5.0). Views: air (a cutaway from above: ceilings and the glass shell left
#   out), in (eye level from the spawn) and down (the lower floor, for the deck pockets).
# Output: art/preview/pocket_<name>_<view>.png (--plain: pocket_<name>_plain_air.png, the greybox before).
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import street  # noqa: E402  (builds the props into a fresh scene)
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
NAME = args[0]
PLAIN = "--plain" in sys.argv
FAST = "--fast" in sys.argv
STEM = "pocket_" + NAME + ("_plain" if PLAIN else "")
DATA = json.load(open(os.path.join(kit.ROOT, "export", "city", STEM + ".json")))
TEX = os.path.join(kit.ROOT, "export", "city")
TILE = DATA["studsPerTile"]
PALETTE = DATA["palette"]
TINTED = DATA["tinted"]
LOOKS = DATA["looks"]
FONT = "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf"  # (the game letters in Bangers)

for objs in street.PROPS.values():
    for ob in objs.values():
        ob.hide_render = True
        ob.hide_viewport = True


def lin(c):
    v = c / 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


kitmats = {}


def kit_material(name, tint):
    key = name + ":" + (tint or "")
    if key in kitmats:
        return kitmats[key]
    m = bpy.data.materials.new("Kit" + key)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    s = 1.0 / TILE[name]
    mp.inputs["Scale"].default_value = (s, s, s)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])

    def img(kind, data):
        path = os.path.join(TEX, "%s_%s.png" % (name, kind))
        if not os.path.exists(path):
            return None
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path, check_existing=True)
        if data:
            n.image.colorspace_settings.name = "Non-Color"
        n.projection = "BOX"
        n.projection_blend = 0.15
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    c = img("Color", False)
    if tint:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        rgb = PALETTE[tint]
        mix.inputs["B"].default_value = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
        nt.links.new(c.outputs["Color"], mix.inputs["A"])
        nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    else:
        nt.links.new(c.outputs["Color"], p.inputs["Base Color"])
    r = img("Roughness", True)
    nt.links.new(r.outputs["Color"], p.inputs["Roughness"])
    mt = img("Metalness", True)
    if mt:
        nt.links.new(mt.outputs["Color"], p.inputs["Metallic"])
    n = img("Normal", True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    kitmats[key] = m
    return m


plain = {}


def plain_mat(key, kind, mat=None):
    k = key + ":" + kind + ":" + (mat or "")
    if k not in plain:
        rgb = PALETTE.get(key, (200, 0, 200))
        if kind == "glow" or mat == "Neon":
            plain[k] = kit.material(k, rgb, rough=0.3, emit=3.0)
        elif mat == "Metal":
            plain[k] = kit.material(k, rgb, metal=0.7, rough=0.35)
        elif mat == "Fabric":
            plain[k] = kit.material(k, rgb, rough=0.95)
        else:
            plain[k] = kit.material(k, rgb, rough=0.7 if kind != "mark" else 0.5)
    return plain[k]


def rb(x, y, z):
    """Roblox (x, up, back) to Blender (x, front, up)."""
    return Vector((x, -z, y))


def wedge(sx, sy, sz):
    import bmesh
    bm = bmesh.new()
    pts = [(-sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, sz / 2), (-sx / 2, -sy / 2, sz / 2),
           (-sx / 2, sy / 2, sz / 2), (sx / 2, sy / 2, sz / 2)]
    v = [bm.verts.new((x, -z, y)) for (x, y, z) in pts]
    for f in ((0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._obj("w", bm)


def place_box(b):
    sx, sy, sz = b["sx"], b["sy"], b["sz"]
    shape = b.get("shape")
    ryd = b.get("ry") or 0
    ry = math.radians(ryd)
    if shape == "cylinder":
        r = min(sx, sz) / 2
        ob = kit.cyl("c", r, r, sy, segs=28)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
    elif shape == "ball":
        s = max(sx, sy, sz)
        ob = kit.sphere("s", r=s / 2, segs=16, rings=10)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
    elif shape == "wedge":
        ob = wedge(sx, sy, sz)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
        ob.rotation_euler = (0, 0, ry)
    elif ryd % 90 != 0:
        ob = kit.box("b", sx, sz, sy)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
        ob.rotation_euler = (0, 0, ry)
    else:
        if ryd % 180 == 90:
            sx, sz = sz, sx
        ob = kit.box("b", sx, sz, sy, at=(sx / 2, sz / 2, sy / 2))
        ob.location = rb(b["cx"] - sx / 2, b["cy"] - sy / 2, b["cz"] + sz / 2)
    name = b.get("kit")
    if name and name in TILE:
        tint = b.get("tint") or (b["color"] if name in TINTED else None)
        ob.data.materials.append(kit_material(name, tint))
    else:
        ob.data.materials.append(plain_mat(b.get("tint") or b["color"], b["kind"], b.get("mat")))
    if b.get("tag") == "beam":
        ob.hide_render = True
    return ob


def sign_text(b):
    """The sign's lettering on its face (front at the box's local -z)."""
    s = b["sign"]
    cu = bpy.data.curves.new("sign", "FONT")
    cu.body = s["text"]
    try:
        cu.font = bpy.data.fonts.load(FONT, check_existing=True)
    except Exception:
        pass
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = b["sy"] * 0.72
    ob = bpy.data.objects.new("signText", cu)
    bpy.context.scene.collection.objects.link(ob)
    ry = math.radians(b.get("ry") or 0)
    off = b["sz"] / 2 + 0.05
    fx, fz = -off * math.sin(ry), -off * math.cos(ry)
    ob.location = rb(b["cx"] + fx, b["cy"], b["cz"] + fz)
    ob.rotation_euler = (math.radians(90), 0, math.pi + ry)
    bpy.context.view_layer.update()
    w = ob.dimensions.x
    if w > b["sx"] * 0.92:
        cu.size *= b["sx"] * 0.92 / w
    rgb = PALETTE[s["ink"]]
    m = kit.material("ink" + s["ink"], rgb, rough=0.5)
    cu.materials.append(m)
    cu.extrude = 0.04
    cu.bevel_depth = 0.02
    return ob


hidden_air = []
for b in DATA["boxes"]:
    if b.get("tag") == "pocketWall":
        continue  # the sealed glass (85% see-through in the game)
    ob = place_box(b)
    if b.get("tag") == "ceiling":
        hidden_air.append(ob)
    if b.get("sign"):
        sign_text(b)

pmat = {}
for name, pieces in LOOKS.items():
    for piece, look in pieces.items():
        rgb, mat = look[0], look[1]
        emit = 3.0 if mat == "Neon" else 0.0
        metal = 0.7 if mat == "Metal" else 0.0
        rough = 0.3 if mat in ("Glass", "Neon") else 0.6
        m = kit.material("prop_" + piece, rgb, metal=metal, rough=rough, emit=emit)
        if len(look) > 3 and look[3]:
            m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - look[3]
        pmat[piece] = m
for pr in DATA["props"]:
    at = Matrix.Translation(rb(pr["x"], pr["y"], pr["z"])) @ Matrix.Rotation(math.radians(pr["ry"]), 4, "Z")
    for piece, src in street.PROPS[pr["name"]].items():
        cp = src.copy()
        cp.data = src.data
        bpy.context.scene.collection.objects.link(cp)
        cp.hide_render = False
        cp.hide_viewport = False
        cp.matrix_world = at
        if not src.data.materials:
            src.data.materials.append(pmat[piece])

for li in DATA["lights"]:
    L = bpy.data.lights.new("pl", "POINT")
    rgb = PALETTE[li["color"]]
    L.color = (lin(rgb[0]) ** 0.5, lin(rgb[1]) ** 0.5, lin(rgb[2]) ** 0.5)
    L.energy = li["brightness"] * li["range"] ** 2 * 0.8
    L.shadow_soft_size = 1.0
    ob = bpy.data.objects.new("pl", L)
    ob.location = rb(li["x"], li["y"], li["z"])
    bpy.context.scene.collection.objects.link(ob)

s = bpy.context.scene
s.render.engine = "CYCLES"
s.cycles.device = "CPU"
s.cycles.samples = 12 if FAST else 32
s.cycles.use_denoising = True
s.render.resolution_x, s.render.resolution_y = (800, 450) if FAST else (1280, 720)
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
# a plain cartoon-blue sky (the pockets float at y 3,000: no horizon, no sun glare in the views)
bg.inputs["Color"].default_value = (0.42, 0.62, 0.9, 1)
bg.inputs["Strength"].default_value = 0.8
s.world = world
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.0
sun.data.angle = math.radians(2)
sun.data.color = (1.0, 0.95, 0.86)
sun.rotation_euler = (math.radians(30), 0, math.radians(25))  # from behind the spawn: the views look north
s.collection.objects.link(sun)
s.view_settings.view_transform = "Standard"  # (true colours: the kit tints read as in the game)
s.view_settings.exposure = -0.35

views = ["air"] if PLAIN else list(DATA["cams"].keys())
for view in views:
    frm, to, lens = DATA["cams"][view]
    for ob in hidden_air:
        ob.hide_render = view == "air"
    cam = kit.camera(rb(*frm), rb(*to), lens=lens)
    cam.data.clip_end = 5000
    kit.render(os.path.join(kit.ROOT, "preview", "%s_%s.png" % (STEM, view)))
