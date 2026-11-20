# park_preview.py: previews for the city park (2026-11-20). kit_sheet(looks) renders every Art.Park look side by
# side in its game colours (Config.Park.looks) into art/preview/park_kit.png (called by park.py --preview).
# scene(json) renders the whole park as the game lays it out (art/park/layout.luau writes the json) from overhead
# and from the street: art/preview/park_overhead.png, art/preview/park_street_*.png.
#   ~/tools/bpyenv/bin/python art/blender/park_preview.py [overhead|street|all]
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = kit.ROOT
REPO = os.path.normpath(os.path.join(ROOT, ".."))
MATS = {"Neon": (0, 0.6, 6.0), "Metal": (0.8, 0.35, 0), "Glass": (0, 0.05, 0), "Ice": (0, 0.1, 0)}


def colours():
    text = open(os.path.join(REPO, "src", "config", "Park.luau")).read()
    out = {}
    for m in re.finditer(r"(\w+) = \{ \{ (\d+), (\d+), (\d+) \}, \"(\w+)\"(?:, ([\d.]+))? \}", text):
        out[m.group(1)] = ((int(m.group(2)), int(m.group(3)), int(m.group(4))), m.group(5), float(m.group(6) or 0))
    return out


_mat = {}


def mat_for(key, rgb, kind, alpha=0.0):
    k = (key, rgb, kind, alpha)
    if k in _mat:
        return _mat[k]
    metal, rough, emit = MATS.get(kind, (0, 0.6, 0))
    m = kit.material("m%d" % len(_mat), rgb, metal=metal, rough=rough, emit=emit)
    if alpha > 0 or kind in ("Glass", "Ice"):
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Alpha"].default_value = 1 - max(alpha, 0.15 if kind == "Glass" else 0)
        if kind == "Glass":
            p.inputs["Transmission Weight"].default_value = 0.6
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    _mat[k] = m
    return m


def paint(ob, name, cols):
    c = cols.get(name)
    rgb, kind, alpha = c if c else ((200, 200, 200), "SmoothPlastic", 0)
    ob.data.materials.clear()
    ob.data.materials.append(mat_for(name, rgb, kind, alpha))


def ground(size, rgb=(96, 150, 70), at=(0, 0, -0.05)):
    g = kit.box("ground", size, size, 0.1, at=at)
    g.data.materials.append(kit.material("ground", rgb, rough=0.9))
    return g


def kit_sheet(looks):
    cols = colours()
    order = ["Bandshell", "Carousel", "Boathouse", "Terrace", "BowBridge", "StoneBridge", "Rink", "SmallFountain",
             "GatePillar", "GateSign", "ParkWall", "ParkRail", "Reeds", "LilyPads", "Rowboat", "Duck", "Dog",
             "Picnic", "Guitar", "GuitarCase"]
    scale = {"Reeds": 3, "LilyPads": 3, "Duck": 5, "Dog": 4, "Picnic": 2.5, "Guitar": 4, "GuitarCase": 4, "Rowboat": 2,
             "ParkRail": 1.6, "GatePillar": 1.5, "SmallFountain": 1.4}
    slots = {
        "Bandshell": (-60, 60), "Carousel": (0, 60), "Boathouse": (60, 60), "Terrace": (-60, 0), "BowBridge": (0, 0),
        "StoneBridge": (40, 0), "Rink": (85, 5), "SmallFountain": (-95, 0), "GatePillar": (-105, 55), "GateSign": (-105, 40),
        "ParkWall": (-60, -50), "ParkRail": (-30, -50), "Reeds": (-10, -50), "LilyPads": (5, -50), "Rowboat": (25, -50),
        "Duck": (42, -50), "Dog": (56, -50), "Picnic": (72, -50), "Guitar": (88, -50), "GuitarCase": (98, -50),
    }
    for look in order:
        if look not in looks:
            continue
        sx, sy = slots[look]
        k = scale.get(look, 1)
        for name, ob in looks[look].items():
            cp = ob.copy()
            cp.data = ob.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            cp.scale = (k, k, k)
            cp.location = (sx, sy, 0 if look not in ("GateSign",) else -8)
            cp.rotation_euler = (0, 0, math.radians(200))
            paint(cp, name, cols)
        ob.hide_render = True
    for look in looks:
        for ob in looks[look].values():
            ob.hide_render = True
    ground(320, at=(0, 0, -0.05))
    kit.studio(res=(1600, 1000), samples=24)
    kit.camera((-10, -230, 170), (0, 10, 0), lens=42)
    kit.render(os.path.join(ROOT, "preview", "park_kit.png"))


# ------------------------------------------------------------------------------------ the whole park, as laid out
TERRAIN = {
    "grass": (98, 158, 72), "leafy": (78, 132, 60), "ground": (120, 96, 70), "mud": (90, 74, 58), "sand": (214, 196, 150),
    "rock": (128, 124, 118), "slate": (110, 112, 116), "water": (58, 120, 150), "ice": (220, 236, 246),
    "pavement": (176, 172, 164), "cobble": (150, 144, 136),
}
PALETTE = {"road": (58, 60, 66), "sidewalk": (190, 186, 178), "wood": (104, 74, 52), "leaf": (88, 150, 64)}
KITS = {"Flagstone": (168, 160, 148), "Asphalt": (82, 84, 88), "Paving": (186, 180, 168)}


def cam(loc, target, lens):
    c = kit.camera(loc, target, lens=lens)
    c.data.clip_end = 20000  # the park and the skylines round it are far past Blender's default 1,000
    return c


def scene(which):
    cols = colours()
    path = os.path.join(ROOT, "park", "layout.json")
    data = json.load(open(path))
    # meshes from the exports (the same files the game imports), transforms applied and centred on their boxes
    def load(path, skip):
        before = set(o.name for o in bpy.context.scene.objects)
        bpy.ops.import_scene.fbx(filepath=path)
        got = {}
        for ob in list(bpy.context.scene.objects):
            if ob.type == "MESH" and ob.name not in before and ob.name not in skip:
                bpy.ops.object.select_all(action="DESELECT")
                ob.select_set(True)
                bpy.context.view_layer.objects.active = ob
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
                kit.centre(ob)
                ob.hide_render = True
                ob.hide_viewport = True
                got[ob.name.split(".")[0]] = ob
        return got

    src = load(os.path.join(ROOT, "export", "Park.fbx"), {})
    street = load(os.path.join(ROOT, "export", "Street.fbx"), src)
    life = load(os.path.join(ROOT, "export", "Life.fbx"), {})
    coll = bpy.data.collections.new("Park")
    bpy.context.scene.collection.children.link(coll)

    def place(srcob, size, cx, cy, cz, ry, rgb, kind="SmoothPlastic", alpha=0):
        # Roblox (x, up, z) -> Blender (x, -z, up); the mesh is centred on its box, scaled to the size
        ob = srcob.copy()
        ob.data = srcob.data
        coll.objects.link(ob)
        ob.hide_render = False
        ob.hide_viewport = False
        ob.rotation_mode = "XYZ"
        ob.rotation_euler = (0, 0, math.radians(ry))
        vs = [v.co for v in srcob.data.vertices]
        dims = Vector((max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs),
                       max(v.z for v in vs) - min(v.z for v in vs)))
        ob.scale = (size[0] / max(dims.x, 1e-3), size[2] / max(dims.y, 1e-3), size[1] / max(dims.z, 1e-3))
        ob.location = (cx, -cz, cy)
        ob.data.materials.clear()
        ob.material_slots and None
        ob.active_material = mat_for("p", tuple(rgb), kind, alpha)
        return ob

    def cube(cx, cy, cz, sx, sy, sz, ry, rgb, kind="SmoothPlastic", alpha=0, shape=None):
        if shape == "cylinder":
            ob = kit.cyl("c", 0.5, 0.5, 1, segs=20)
        elif shape == "ball":
            ob = kit.sphere("b", 0.5, segs=12, rings=8)
            m = max(sx, sy, sz)
            sx, sy, sz = m, m, m
        else:
            ob = kit.box("b", 1, 1, 1)
        bpy.context.scene.collection.objects.unlink(ob)
        coll.objects.link(ob)
        ob.scale = (sx, sz, sy)
        ob.rotation_euler = (0, 0, math.radians(ry))
        ob.location = (cx, -cz, cy)
        ob.data.materials.append(mat_for("c", tuple(rgb), kind, alpha))
        return ob

    # Terrain fills, painted as slabs and discs (the same order the server fills them)
    for f in data["terrain"]:
        rgb = TERRAIN.get(f["material"], (255, 0, 255))
        if f["material"] == "air":
            continue
        alpha = 0.25 if f["material"] == "water" else 0
        kind = "Glass" if f["material"] == "water" else "SmoothPlastic"
        if f["shape"] == "block":
            cube(f["cx"], f["cy"], f["cz"], f["sx"], f["sy"], f["sz"], f.get("ry", 0), rgb, kind, alpha)
        elif f["shape"] == "cyl":
            cube(f["cx"], f["cy"], f["cz"], f["r"] * 2, f["h"], f["r"] * 2, 0, rgb, kind, alpha, shape="cylinder")
        elif f["shape"] == "ball":
            cube(f["cx"], f["cy"], f["cz"], f["r"] * 2, f["r"] * 2, f["r"] * 2, 0, rgb, kind, alpha, shape="ball")
    for b in data["boxes"]:
        if b.get("look") in ("TreeTrunk", "Canopy"):
            name = "TreeTrunk" if b["look"] == "TreeTrunk" else "CanopyRound"
            s = life.get(name)
            if s:
                rgb = (104, 74, 52) if name == "TreeTrunk" else tuple(b.get("leaf") or (88, 150, 64))
                size = [b["sx"], b["sy"], b["sz"]]
                if name != "TreeTrunk":
                    m = max(size)
                    size = [m, m, m]
                place(s, size, b["cx"], b["cy"], b["cz"], 0, rgb, "SmoothPlastic")
                continue
        rgb = KITS.get(b.get("kit")) or PALETTE.get(b["color"], (200, 200, 200))
        cube(b["cx"], b["cy"], b["cz"], b["sx"], b["sy"], b["sz"], b.get("ry", 0), rgb, shape=b.get("shape"))
    for m in data["meshes"]:
        s = src.get(m["name"])
        if not s:
            continue
        c = cols.get(m["name"], ((200, 200, 200), "SmoothPlastic", 0))
        place(s, m["size"], m["x"], m["y"], m["z"], m["ry"], m.get("color") or c[0], c[1], c[2])
    pcols = {"OldLamp": (40, 44, 50), "Bench": (150, 102, 64), "Bin": (60, 84, 72), "FoodCart": (200, 70, 60), "Bush": (70, 130, 60), "FlowerTub": (190, 120, 150)}
    for p in data["props"]:
        for piece, fit in p["pieces"].items():
            s = street.get(piece)
            if not s:
                continue
            a = math.radians(p["ry"])
            ox, oy, oz = fit["offset"]
            x = p["x"] + ox * math.cos(a) + oz * math.sin(a)
            z = p["z"] - ox * math.sin(a) + oz * math.cos(a)
            place(s, fit["size"], x, p["y"] + oy, z, p["ry"], pcols.get(p["name"], (120, 120, 120)))
    # the city round it, as plain blocks (buildings and roads of Downtown's north edge and Uptown's south edge)
    for b in data["city"]:
        cube(b["cx"], b["cy"], b["cz"], b["sx"], b["sy"], b["sz"], b.get("ry", 0), tuple(b["rgb"]))
    # the city's ground plates round the park (the green inside the wall is the Terrain above)
    g = data["green"]
    for x0, z0, x1, z1 in ((-1900, -2000, 900, g["z0"]), (-1900, g["z1"], 900, 900), (-1900, g["z0"], g["x0"], g["z1"]), (g["x1"], g["z0"], 900, g["z1"])):
        gp = kit.box("plate", x1 - x0, z1 - z0, 4, at=((x0 + x1) / 2, -(z0 + z1) / 2, -2))
        bpy.context.scene.collection.objects.unlink(gp)
        coll.objects.link(gp)
        gp.data.materials.append(kit.material("plate", (96, 150, 70), rough=0.9))

    bnd = data["bounds"]
    cx, cz = (bnd["minX"] + bnd["maxX"]) / 2, (bnd["minZ"] + bnd["maxZ"]) / 2
    kit.studio(res=(1800, 1200), samples=20)
    sun = bpy.data.objects.get("Key")
    if sun:
        sun.rotation_euler = (0.7, 0.3, 0.9)
    if which in ("top", "all"):
        c = cam((cx, -cz, 1200), (cx, -cz + 0.01, 0), 50)
        c.data.type = "ORTHO"
        c.data.ortho_scale = (bnd["maxX"] - bnd["minX"]) + 40
        bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = 2000, 1300
        kit.render(os.path.join(ROOT, "preview", "park_top.png"))
        bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = 1800, 1200
    if which in ("overhead", "all"):
        # from high over Downtown's north edge, looking north across the park to Uptown
        cam((cx - 60, -(bnd["maxZ"] + 330), 520), (cx, -cz - 60, 0), 26)
        kit.render(os.path.join(ROOT, "preview", "park_overhead.png"))
    if which in ("street", "all"):
        for name, (at, target) in data["views"].items():
            cam((at[0], -at[2], at[1]), (target[0], -target[2], target[1]), 28)
            kit.render(os.path.join(ROOT, "preview", "park_street_%s.png" % name))


if __name__ == "__main__" and os.path.basename(sys.argv[0]) == "park_preview.py":
    kit.reset()
    scene(sys.argv[1] if len(sys.argv) > 1 else "all")
