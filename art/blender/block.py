# block.py: a preview render of the city kit block (overhaul plan step 3, "one Downtown block"), built from the
# game's own layout (art/city/block.luau writes art/export/city/block.json from CityLayout) with the kit's
# textures (art/city/materials.py) and street props (street.py), the way CityBuilder dresses it once nate has
# uploaded them. The neighbouring blocks stay in their current plain look, for comparison.
# Run: lune run art/city/block.luau && python art/blender/block.py   (with the `bpy` module, Blender 5.0)
# Output: art/preview/block_street.png (street level) and art/preview/block_air.png (from above).
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import street  # noqa: E402  (builds the props into a fresh scene)
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

DATA = json.load(open(os.path.join(kit.ROOT, "export", "city", "block.json")))
TEX = os.path.join(kit.ROOT, "export", "city")
TILE = {"Brick": 12, "Office": 12, "Curtain": 12, "Stone": 12, "Paving": 8, "Asphalt": 16}
PALETTE = {  # Config.City.palette (the plain look)
    "concrete": (158, 156, 150), "brick": (140, 98, 82), "slate": (92, 100, 112), "sand": (196, 180, 150),
    "steel": (120, 130, 140), "glass": (70, 96, 120), "sidewalk": (120, 120, 118), "roof": (74, 76, 82),
    "window": (255, 214, 140), "kerb": (186, 184, 178), "mark": (236, 234, 226), "road": (46, 48, 54),
}

for objs in street.PROPS.values():
    for ob in objs.values():
        ob.hide_render = True
        ob.hide_viewport = True


def kit_material(name):
    m = bpy.data.materials.new("Kit" + name)
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
        n.image = bpy.data.images.load(path)
        if data:
            n.image.colorspace_settings.name = "Non-Color"
        n.projection = "BOX"
        n.projection_blend = 0.0
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    c = img("Color", False)
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
    return m


KITMAT = {k: kit_material(k) for k in TILE}
plain = {}


def plain_mat(key, kind):
    k = key + ":" + kind
    if k not in plain:
        rgb = PALETTE.get(key, (200, 0, 200))
        if kind == "band":
            plain[k] = kit.material(k, rgb, rough=0.2, emit=0.15)
        else:
            plain[k] = kit.material(k, rgb, rough=0.7 if kind != "mark" else 0.5)
    return plain[k]


def rb(x, y, z):
    """Roblox (x, up, back) to Blender (x, front, up)."""
    return Vector((x, -z, y))


def place_box(b):
    sx, sy, sz = b["sx"], b["sy"], b["sz"]
    if b.get("shape") == "cylinder":
        ob = kit.cyl("c", sx / 2, sx / 2, sy, segs=20)
        ob.location = rb(b["cx"], b["cy"], b["cz"])
    else:
        # origin at the box's lower corner so a texture tiles up from its base, like a storey
        ob = kit.box("b", sx, sz, sy, at=(sx / 2, sz / 2, sy / 2))
        ob.location = rb(b["cx"] - sx / 2, b["cy"] - sy / 2, b["cz"] + sz / 2)
    name = b.get("kit")
    ob.data.materials.append(KITMAT[name] if name else plain_mat(b["color"], b["kind"]))
    return ob


for b in DATA["boxes"]:
    if b["kind"] == "band" and b.get("plain"):
        continue
    place_box(b)

# the road: one big asphalt slab under everything
blk = DATA["block"]
cx, cz = blk["minX"] + blk["size"] / 2, blk["minZ"] + blk["size"] / 2
road = kit.box("road", 900, 900, 0.2, at=(450, 450, 0.1))
road.location = rb(cx - 450, -0.1, cz + 450) + Vector((0, 0, 0))
road.data.materials.append(KITMAT["Asphalt"])
# ground level in the layout: the sidewalk sits at gy + 0.5; find gy from the kit sidewalk
gy = [b for b in DATA["boxes"] if b.get("kit") == "Paving"][0]["cy"] - 0.5
road.location.z = gy

# the props: copies of street.py's pieces at each foot point, turned to face the street
LOOK = {  # Config.City.kit.props colours
    "Pole": ((48, 60, 56), 0.4, 0.8), "LampHead": ((48, 60, 56), 0.4, 0.8), "Bulb": ((255, 236, 190), 0.3, 0),
    "BenchSeat": ((150, 102, 64), 0.7, 0), "BenchFrame": ((40, 44, 48), 0.5, 0.8), "Hydrant": ((200, 52, 44), 0.4, 0),
    "Bin": ((60, 84, 72), 0.5, 0.6), "PlanterBox": ((168, 164, 156), 0.85, 0), "Trunk": ((96, 70, 50), 0.9, 0),
    "Crown": ((84, 140, 70), 0.9, 0), "SignalPole": ((54, 58, 64), 0.5, 0.8), "SignalBox": ((40, 42, 46), 0.5, 0.6),
    "SignalLights": ((120, 255, 140), 0.3, 0),
}
pmat = {}
for piece, (rgb, rough, metal) in LOOK.items():
    emit = 3.0 if piece in ("Bulb", "SignalLights") else 0.0
    pmat[piece] = kit.material("prop_" + piece, rgb, metal=metal, rough=rough, emit=emit)
for pr in DATA["props"]:
    at = Matrix.Translation(rb(pr["x"], pr["y"], pr["z"])) @ Matrix.Rotation(math.radians(pr["ry"]), 4, "Z")
    for piece, src in street.PROPS[pr["name"]].items():
        cp = src.copy()
        cp.data = src.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.hide_render = False
        cp.hide_viewport = False
        cp.matrix_world = at
        cp.data.materials.clear()
        cp.data.materials.append(pmat[piece])

# light: a warm afternoon sun and a blue sky (the game uses Future lighting with an atmosphere)
s = bpy.context.scene
s.render.engine = "CYCLES"
s.cycles.device = "CPU"
s.cycles.samples = 48
s.cycles.use_denoising = True
s.render.resolution_x, s.render.resolution_y = 1800, 1000
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
s.view_settings.exposure = -0.35

x0, z0, size, st = blk["minX"], blk["minZ"], blk["size"], blk["street"]
# street level: on the road at the block's north-west corner, looking along its north side
kit.camera(rb(x0 - st * 0.35, gy + 6.5, z0 - st * 0.55), rb(x0 + size * 0.55, gy + 22, z0 + 6), lens=24)
kit.render(os.path.join(kit.ROOT, "preview", "block_street.png"))
# from above: three-quarter view over the corner
kit.camera(rb(x0 + size * 0.5 - 150, gy + 330, z0 - 170), rb(x0 + size * 0.5, gy + 10, z0 + size * 0.5), lens=32)
kit.render(os.path.join(kit.ROOT, "preview", "block_air.png"))
