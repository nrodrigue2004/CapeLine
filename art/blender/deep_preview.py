# deep_preview.py: deep.py's previews with the baked texture sets the way the game shows them (vpreview's materials:
# the colour map's alpha over the part colour, as SurfaceAppearance AlphaMode Overlay does; tinted copies; Neon).
# Scenes from inside, in underwater fog (a world volume tinted like Config.Deep.look), where the game puts the looks
# (art/export/deep/layout.json from `lune run art/deep/layout.luau`): a tunnel stretch toward the flooded cars, the
# station, a reef stretch, a wreck, the sunken factory and the harbour basin's tunnel mouth; plus galleries of the reef
# looks and the gear. Writes art/preview/deep.png (one captioned sheet).
import json
import math
import os
import subprocess

import kit
import bpy
from mathutils import Matrix, Vector

import vpreview
from studs import rb, copy
from vkit import lin

PREV = os.path.join(kit.ROOT, "preview")
SHOWN = []


def keep(o):
    o.hide_render = False
    SHOWN.append(o)
    return o


def clear():
    for o in SHOWN:
        bpy.data.objects.remove(o, do_unlink=True)
    SHOWN.clear()


def run(GROUPS, LOOKS, FRAMES, INFO, MAPS, fast=False):
    sc = bpy.context.scene
    for g in GROUPS.values():
        for ob in g.meshes.values():
            ob.hide_render = True
    with open(os.path.join(kit.ROOT, "export", "deep", "layout.json")) as f:
        LAY = json.load(f)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 10 if fast else 28
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.volume_bounces = 0
    sc.render.resolution_x, sc.render.resolution_y = (520, 330) if fast else (760, 475)
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    TEX = {name: vpreview._mat_textured("deep_" + name, maps) for name, maps in MAPS.items()}

    def obj_mat(name, tint):
        inf = INFO[name]
        if inf["maps"] and inf["group"] in TEX:
            return TEX[inf["group"]], (tint if inf["tint"] and tint else inf["rgb"])
        rgb = tint if (inf["tint"] and tint) else inf["rgb"]
        m = vpreview._mat_flat(tuple(rgb), inf["mat"], inf["alpha"])
        if inf["mat"] == "Neon":
            p = m.node_tree.nodes["Principled BSDF"]
            p.inputs["Emission Strength"].default_value = 2.5
        return m, rgb

    def place(lk, at, size, ry=0.0, tint=None):
        fx, fy, fz = FRAMES[lk]
        k = (size[0] / fx, size[1] / fy, size[2] / fz)
        M = (Matrix.Translation(Vector(rb(*at))) @ Matrix.Rotation(math.radians(ry or 0), 4, "Z")
             @ Matrix.Diagonal((k[0], k[2], k[1], 1.0)))
        for name in LOOKS[lk]:
            g = GROUPS[INFO[name]["group"]]
            cp = keep(copy(g.meshes[name]))
            cp.matrix_world = M
            m, rgb = obj_mat(name, tint)
            cp.data.materials.clear()
            cp.data.materials.append(m)
            cp.color = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)

    def draw_box(b, rgb=None, mat="SmoothPlastic"):
        sx, sy, sz = b["size"]
        x, y, z = b["at"]
        if b.get("shape") == "cylinder":
            ob = kit.cyl("bx", min(sx, sz) / 2, min(sx, sz) / 2, sy, at=rb(x, y, z), segs=20)
        elif b.get("shape") == "ball":
            ob = kit.sphere("bx", r=max(sx, sy, sz) / 2, at=rb(x, y, z), segs=14, rings=8)
        else:
            ob = kit.box("bx", sx, sz, sy, at=(0, 0, 0))
            ob.matrix_world = Matrix.Translation(Vector(rb(x, y, z))) @ Matrix.Rotation(math.radians(b.get("ry") or 0), 4, "Z")
        keep(ob)
        col = rgb or b["color"]
        kind = "Neon" if b.get("kind") == "glow" else mat
        m = vpreview._mat_flat(tuple(col), kind, 0.0)
        ob.data.materials.append(m)
        ob.color = (lin(col[0]), lin(col[1]), lin(col[2]), 1)

    def near(at, r):
        return lambda p: max(abs(p[0] - at[0]), abs(p[2] - at[2])) < r

    def scene_at(focus, r, dressed=True):
        """The Deep round focus: every look and kept box within r studs, plus sand and rock fills."""
        ok = near(focus, r)
        for b in LAY["boxes"]:
            if ok(b["at"]) and (not dressed or not b.get("art")):
                draw_box(b)
        if dressed:
            for p in LAY["art"]:
                if ok(p["at"]):
                    place(p["look"], p["at"], p["size"], p["ry"], p.get("tint"))
        for t in LAY["terrain"]:
            if t["material"] == "water":
                continue
            x, y, z = t["at"]
            sx, sy, sz = t["size"]
            if abs(x - focus[0]) < r + sx / 2 and abs(z - focus[2]) < r + sz / 2:
                rgb = (186, 168, 128) if t["material"] == "sand" else (96, 90, 86)
                draw_box({"at": [x, y, z], "size": [sx, sy, sz]}, rgb, "Sand" if t["material"] == "sand" else "Slate")

    def water(deep=0.0, density=0.012, sun=True, ambient=0.5, focus=None, r=200):
        """Underwater fog: a world volume where no sun reaches (the tunnel), else a box of water from the surface down
        round focus (a world volume would swallow the sun), lit from above."""
        world = bpy.data.worlds.new("Deep")
        world.use_nodes = True
        nt = world.node_tree
        bg = nt.nodes["Background"]
        tint = (0.28, 0.55, 0.74)
        dk = (0.08, 0.22, 0.38)
        col = tuple(tint[i] * (1 - deep) + dk[i] * deep for i in range(3))
        bg.inputs["Color"].default_value = (col[0] * 0.6, col[1] * 0.6, col[2] * 0.6, 1)
        bg.inputs["Strength"].default_value = ambient
        sc.world = world

        def principled(tree, out_socket):
            vol = tree.nodes.new("ShaderNodeVolumePrincipled")
            vol.inputs["Color"].default_value = (col[0], col[1], col[2], 1)
            vol.inputs["Density"].default_value = density
            vol.inputs["Absorption Color"].default_value = (col[0] * 0.8, col[1] * 0.9, col[2], 1)
            tree.links.new(vol.outputs["Volume"], out_socket)

        if not sun:
            principled(nt, nt.nodes["World Output"].inputs["Volume"])
            return
        bottom = (focus[1] if focus else -100) - 400
        h = wy - bottom
        box = keep(kit.box("water", 2 * r + 400, 2 * r + 400, h, at=rb(focus[0], (wy + bottom) / 2, focus[2])))
        m = bpy.data.materials.new("water")
        m.use_nodes = True
        mt = m.node_tree
        mt.nodes.remove(mt.nodes["Principled BSDF"])
        principled(mt, mt.nodes["Material Output"].inputs["Volume"])
        box.data.materials.append(m)
        s_ = keep(bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")))
        s_.data.energy = 4.0
        s_.data.color = (0.8, 0.95, 1.0)
        s_.data.angle = math.radians(10)
        s_.rotation_euler = (math.radians(20), math.radians(10), math.radians(30))
        sc.collection.objects.link(s_)

    def studio():
        world = bpy.data.worlds.new("Studio")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.32, 0.42, 1)
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
        sc.world = world
        for rot, e in (((0.8, 0.2, 0.6), 3.4), ((1.2, 0, 3.6), 1.6)):
            L = keep(bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN")))
            L.data.energy = e
            L.rotation_euler = rot
            sc.collection.objects.link(L)

    def lamp(at, energy=400, color=(1.0, 0.85, 0.6), radius=1.0):
        L = keep(bpy.data.objects.new("Pt", bpy.data.lights.new("Pt", "POINT")))
        L.data.energy = energy
        L.data.color = color
        L.data.shadow_soft_size = radius
        L.location = Vector(rb(*at))
        sc.collection.objects.link(L)

    def hero(x, y, z, yaw=0):
        """A blocky 5-stud hero for scale."""
        skin = (242, 196, 152)
        for (s_, c, rgb) in (((2, 2, 1), (0, 3.0, 0), (60, 120, 220)), ((1.2, 1.2, 1.2), (0, 4.6, 0), skin),
                             ((0.95, 2, 1), (-0.5, 1.0, 0), (40, 50, 90)), ((0.95, 2, 1), (0.5, 1.0, 0), (40, 50, 90)),
                             ((1, 2, 1), (-1.5, 3.0, 0), skin), ((1, 2, 1), (1.5, 3.0, 0), skin)):
            o = keep(kit.box("hero", s_[0], s_[2], s_[1], at=(0, 0, 0)))
            o.matrix_world = Matrix.Translation(Vector(rb(x, y, z))) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ \
                Matrix.Translation(Vector(rb(*c)))
            o.data.materials.append(vpreview._mat_flat(rgb, "SmoothPlastic", 0.0))

    def shoot(name, frm, to, lens):
        cam = keep(kit.camera(rb(*frm), rb(*to), lens=lens))
        cam.data.clip_end = 5000
        out = os.path.join(PREV, "deep_%s.png" % name)
        kit.render(out)
        clear()
        return out

    def first(lk):
        return next(p for p in LAY["art"] if p["look"] == lk)

    wy = LAY["waterY"]
    made = []
    # ---- the tunnel, from near the basin mouth toward the cars
    water(deep=0.3, density=0.01, sun=False, ambient=0.6)
    scene_at((330, -27, 676), 160)
    for x in range(215, 440, 20):
        lamp((x, -19.5, 676), 120)
    lamp((428, -29, 672), 260, (0.75, 0.9, 1.0), 2.0)
    hero(415, -36, 672, 200)
    made.append(("The Sunken Line: a tunnel stretch, underwater fog",
                 shoot("tunnel", (432, -28.5, 680), (330, -30, 674), 22)))
    # ---- the station
    water(deep=0.3, density=0.008, sun=False, ambient=0.6)
    scene_at((162, -27, 676), 120)
    for x in (137, 154, 171, 188):
        for z in (660, 692):
            lamp((x, -19.5, z), 140)
    lamp((198, -26, 690), 300, (0.75, 0.9, 1.0), 2.0)
    hero(185, -30, 660, 140)
    made.append(("The Sunken Line: the flooded station", shoot("station", (202, -24, 698), (150, -30, 662), 18)))
    # ---- the station as it is today (the plain parts), for comparison
    water(deep=0.3, density=0.008, sun=False, ambient=0.6)
    scene_at((162, -27, 676), 120, dressed=False)
    for x in (137, 154, 171, 188):
        for z in (660, 692):
            lamp((x, -19.5, z), 140)
    lamp((198, -26, 690), 300, (0.75, 0.9, 1.0), 2.0)
    made.append(("The station today (plain parts fallback)", shoot("station_parts", (202, -24, 698), (150, -30, 662), 18)))
    # ---- a reef stretch: the busiest cluster of coral
    corals = [p for p in LAY["art"] if p["look"].startswith("Coral") or p["look"] == "KelpStrand"]
    best = max(corals, key=lambda c: sum(1 for d in corals if abs(d["at"][0] - c["at"][0]) < 40 and abs(d["at"][2] - c["at"][2]) < 40))
    bx, by, bz = best["at"]
    floor = min(p["at"][1] - p["size"][1] / 2 for p in corals if abs(p["at"][0] - bx) < 40 and abs(p["at"][2] - bz) < 40)
    water(deep=0.15, density=0.006, sun=True, ambient=0.6, focus=(bx, by, bz), r=110)
    scene_at((bx, by, bz), 110)
    hero(bx + 6, floor, bz - 7, 160)
    made.append(("Coral Shelf: a reef stretch, underwater fog",
                 shoot("reef", (bx + 13, floor + 6, bz - 19), (bx - 1, floor + 2.5, bz + 2), 20)))
    # ---- a wreck
    wh = first("WreckHull")
    x, y, z = wh["at"]
    a = math.radians(wh["ry"])
    fx, fz = math.sin(a), math.cos(a)
    water(deep=0.2, density=0.005, sun=True, ambient=0.6, focus=(x, y, z), r=120)
    scene_at((x, y, z), 120)
    sx, sz = x + fz * 55 - fx * 10, z - fx * 55 - fz * 10
    made.append(("Coral Shelf: a shipwreck", shoot("wreck", (sx, y + 16, sz), (x + fx * 8, y, z + fz * 8), 26)))
    # ---- the sunken factory from the Leviathan's arena
    fh = first("FactoryHall")
    x, y, z = fh["at"]
    water(deep=0.6, density=0.003, sun=True, ambient=0.6, focus=(x, y, z), r=260)
    scene_at((x, y, z), 260)
    made.append(("The Trench: the sunken factory", shoot("factory", (x + 60, y + 10, z - 220), (x, y + 5, z), 24)))
    # ---- the harbour basin and the tunnel mouth
    water(deep=0.1, density=0.006, sun=True, ambient=0.6, focus=(470, -18, 676), r=140)
    scene_at((470, -18, 676), 140)
    hero(468, -36, 668, 250)
    made.append(("Harbour Basin: the quay and the tunnel mouth", shoot("basin", (520, -24, 700), (440, -26, 674), 22)))
    # ---- galleries: the reef looks and the gear (studio light)
    studio()
    reef = ["CoralBrain", "CoralKnob", "CoralStag", "CoralTube", "CoralFinger", "CoralFan", "CoralLace", "KelpStrand",
            "CacheChest"]
    tints = [(255, 120, 120), (255, 180, 90), (190, 120, 230), (90, 210, 190), (255, 120, 120), (255, 180, 90),
             (190, 120, 230), (60, 120, 70), None]
    for i, lk in enumerate(reef):
        fx_, fy_, fz_ = FRAMES[lk]
        if lk == "KelpStrand":
            fy_ = 12
        place(lk, ((i - 4) * 6.4, fy_ / 2, (i % 2) * 5), (fx_, fy_, fz_), 20, tints[i])
    g = keep(kit.box("ground", 120, 60, 0.4, at=(0, 0, -0.2)))
    g.data.materials.append(vpreview._mat_flat((186, 168, 128), "Sand", 0.0))
    made.append(("The reef looks, the kelp and the cache chest", shoot("reef_gallery", (0, 12, -52), (0, 3.0, 2), 28)))
    studio()
    place("DiverHelmet", (-6, 2, 0), (2.4, 2.4, 2.4), 200)
    place("DiverTank", (-2.5, 2.4, 0), (1.0, 4.8, 1.0), 0)
    place("Torpedo", (1.8, 1.2, 0), (1.4, 1.4, 4.0), 60)
    place("AirBubble", (8, 3.6, 0), (7, 7, 7), 0)
    hero(8, 0.6, 0, 180)
    place("TrainCar", (0, 5.9, 18), (54.2, 11.8, 11.8), 0)
    place("WreckCabin", (-30, 3.5, 0), (10, 7, 12), 30)
    g = keep(kit.box("ground", 160, 80, 0.4, at=(0, 0, -0.2)))
    g.data.materials.append(vpreview._mat_flat((120, 124, 132), "SmoothPlastic", 0.0))
    made.append(("Diver helmet, tank, torpedo, the commuter's bubble, a car",
                 shoot("gear_gallery", (4, 10, -30), (2, 3.5, 6), 28)))
    # one sheet: every shot with its caption, 3 across (python3 with PIL)
    args = json.dumps([[c, p] for (c, p) in made])
    sheet = os.path.join(PREV, "deep.png")
    code = (
        "import json,sys\n"
        "from PIL import Image, ImageDraw, ImageFont\n"
        "shots=json.loads(sys.argv[1]); out=sys.argv[2]\n"
        "ims=[Image.open(p).convert('RGB') for _,p in shots]\n"
        "w,h=ims[0].size; cols=3; rows=(len(ims)+cols-1)//cols; bar=40\n"
        "sheet=Image.new('RGB',(cols*w,rows*(h+bar)),(24,26,32)); d=ImageDraw.Draw(sheet)\n"
        "try:\n f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',20)\n"
        "except Exception:\n f=ImageFont.load_default()\n"
        "for i,(im,(cap,_)) in enumerate(zip(ims,shots)):\n"
        " x=(i%cols)*w; y=(i//cols)*(h+bar); sheet.paste(im,(x,y+bar)); d.text((x+12,y+8),cap,fill=(255,236,150),font=f)\n"
        "sheet.save(out)\n"
    )
    subprocess.run(["python3", "-c", code, args, sheet], check=True)
    print("preview:", sheet)
