# block.py: a preview render of the dressed city (overhaul plan step 3 the first block, step 5 the whole city),
# built from the game's own layout (art/city/block.luau writes art/export/city/<area>.json from WorldMap) with
# the kit's textures (art/city/materials.py, tinted like the game tints them) and street props (street.py),
# the way the game looks once nate has uploaded the textures and imported Art.Street.
# Run: lune run art/city/block.luau <area> && python art/blender/block.py <area>   (with the `bpy` module,
# Blender 5.0; area: Downtown (default), Docks, OldTown, Suburbs; add --fast for a quick low-sample look)
# Output: art/preview/<area>_street.png (street level) and <area>_air.png (from above); Downtown keeps its
# first names, block_street.png and block_air.png.
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
AREA = args[0] if args else "Downtown"
FAST = "--fast" in sys.argv
NAME = "block" if AREA == "Downtown" else AREA
DATA = json.load(open(os.path.join(kit.ROOT, "export", "city", NAME + ".json")))
TEX = os.path.join(kit.ROOT, "export", "city")
TILE = DATA["studsPerTile"]
PALETTE = DATA["palette"]
TINTED = DATA["tinted"]
LOOKS = DATA["looks"]
GY = DATA["ground"]

for objs in street.PROPS.values():
    for ob in objs.values():
        ob.hide_render = True
        ob.hide_viewport = True


def lin(c):
    """sRGB 0..255 to linear."""
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
        n.projection_blend = 0.0
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


def plain_mat(key, kind):
    k = key + ":" + kind
    if k not in plain:
        rgb = PALETTE.get(key, (200, 0, 200))
        if kind == "glow":
            plain[k] = kit.material(k, rgb, rough=0.3, emit=2.0)
        elif kind == "water":
            plain[k] = kit.material(k, rgb, rough=0.05)
        else:
            plain[k] = kit.material(k, rgb, rough=0.7 if kind != "mark" else 0.5)
    return plain[k]


def rb(x, y, z):
    """Roblox (x, up, back) to Blender (x, front, up)."""
    return Vector((x, -z, y))


def wedge(sx, sy, sz):
    """A Roblox WedgePart in Blender axes: high edge at Roblox +z (Blender -y), sloping down to -z."""
    import bmesh
    bm = bmesh.new()
    # Roblox corners (x, y, z) with the wedge's slope: top only at z = +sz/2
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
    ry = math.radians(b.get("ry") or 0)
    if shape == "cylinder":
        ob = kit.cyl("c", sx / 2, sx / 2, sy, segs=20)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
    elif shape == "ball":
        s = max(sx, sy, sz)
        ob = kit.sphere("s", r=s / 2, segs=16, rings=10)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
    elif shape == "wedge":
        ob = wedge(sx, sy, sz)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
        ob.rotation_euler = (0, 0, ry)
    else:
        if (b.get("ry") or 0) % 180 == 90:
            sx, sz = sz, sx
        # origin at the box's lower corner so a texture tiles up from its base, like a storey
        ob = kit.box("b", sx, sz, sy, at=(sx / 2, sz / 2, sy / 2))
        ob.location = rb(b["cx"] - sx / 2, b["cy"] - sy / 2, b["cz"] + sz / 2)
    name = b.get("kit")
    if name:
        tint = b.get("tint") or (b["color"] if name in TINTED else None)
        ob.data.materials.append(kit_material(name, tint))
    else:
        ob.data.materials.append(plain_mat(b["color"], b["kind"]))
    return ob


for b in DATA["boxes"]:
    if b["kind"] == "band" and b.get("plain"):
        continue
    if b["kind"] in ("ground", "sea"):
        continue
    place_box(b)

# grass under everything, and the harbour water
x0, z0, x1, z1 = DATA["window"]
g = kit.box("ground", 3000, 3000, 2, at=(0, 0, -1))
g.location = rb((x0 + x1) / 2, GY, (z0 + z1) / 2)
g.data.materials.append(kit.material("grass", PALETTE["grass"], rough=0.9))
if "water" in DATA:
    wx0, wz0, wx1, wz1 = DATA["water"]
    wt = kit.box("water", wx1 - wx0, wz1 - wz0, 0.5, at=(0, 0, 0))
    wt.location = rb((wx0 + wx1) / 2, GY + 0.1, (wz0 + wz1) / 2)  # (Terrain water in the game)
    wt.data.materials.append(kit.material("sea", (56, 120, 168), rough=0.08))

# the props: copies of street.py's pieces at each foot point, turned to face the street
pmat = {}
for name, pieces in LOOKS.items():
    for piece, look in pieces.items():
        rgb, mat = look[0], look[1]
        emit = 3.0 if mat == "Neon" else 0.0
        metal = 0.7 if mat == "Metal" else 0.0
        rough = 0.3 if mat in ("Glass", "Neon") else 0.6
        m = kit.material("prop_" + piece, rgb, metal=metal, rough=rough, emit=emit)
        if len(look) > 3 and look[3]:
            p = m.node_tree.nodes["Principled BSDF"]
            p.inputs["Alpha"].default_value = 1 - look[3]
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
            src.data.materials.append(pmat[piece])  # the mesh is shared by every copy
        look = LOOKS[pr["name"]][piece]
        if pr.get("tint") and len(look) > 4 and look[4]:
            # a tinted piece (pt-city: awnings, billboards, news boxes, carts) in its placement's colour
            key = "tint_" + piece + "_" + pr["tint"]
            if key not in pmat:
                pmat[key] = kit.material(key, PALETTE[pr["tint"]], rough=0.6)
            cp.data = src.data.copy()  # its own mesh, so the shared one keeps its colour
            cp.data.materials.clear()
            cp.data.materials.append(pmat[key])

# light: a warm afternoon sun and a blue sky (the game uses Future lighting with an atmosphere)
s = bpy.context.scene
s.render.engine = "CYCLES"
s.cycles.device = "CPU"
s.cycles.samples = 12 if FAST else 40
s.cycles.use_denoising = True
s.render.resolution_x, s.render.resolution_y = (900, 500) if FAST else (1600, 900)
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
sky = world.node_tree.nodes.new("ShaderNodeTexSky")
try:
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(38)
    sky.sun_rotation = math.radians(140)
    sky.altitude = 200
except Exception:
    pass
world.node_tree.links.new(sky.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 0.35
s.world = world
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0
sun.data.angle = math.radians(1.5)
sun.data.color = (1.0, 0.95, 0.86)
sun.rotation_euler = (math.radians(52), 0, math.radians(140 + 180))
s.collection.objects.link(sun)
s.view_settings.view_transform = "AgX"
s.view_settings.exposure = -0.55

for view, (frm, to, lens) in DATA["cams"].items():
    cam = kit.camera(rb(*frm), rb(*to), lens=lens)
    cam.data.clip_end = 20000  # a whole skyline from the air (the default 100 cut the towers' feet off)
    kit.render(os.path.join(kit.ROOT, "preview", "%s_%s.png" % (NAME, view)))
