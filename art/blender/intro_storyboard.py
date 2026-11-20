# intro_storyboard.py: storyboard frames of the intro film (list-combat 2026-11-20). Every frame is the game's own
# camera at one moment (art/intro/storyboard.luau from Shared.IntroFilm on the test seed's real buildings),
# rendered with the Roblox field of view (70 degrees, vertical): the buildings as window-gridded blocks (the
# smashed tower's holes where the hero went in and out), the cast as blocky stand-ins in their colours and poses
# (Lodestar navy and gold, Crane Troopers silver with red eyes, Crane in a dark suit, the three fakes, the Syndicate
# crook, the crowd and "you"), and the moment's effects (debris, dust ring, bolts, the spark). It checks framing,
# pacing and what is in shot, not the kit art (the game draws the city kit, the real rigs and FxLib).
# Run: lune run art/intro/storyboard.luau && $HOME/tools/bpyenv/bin/python art/blender/intro_storyboard.py [--fast]
# [--redo], then python3 art/intro/storyboard_sheet.py packs art/preview/intro_film_1.png and intro_film_2.png.
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

FAST = "--fast" in sys.argv
REDO = "--redo" in sys.argv
DATA = json.load(open(os.path.join(kit.ROOT, "export", "intro", "storyboard.json")))
OUT = os.path.join(kit.ROOT, "export", "intro", "frames")
GY = DATA["ground"]


def rb(x, y, z):
    """Roblox (x, up, back) to Blender (x, front, up)."""
    return Vector((x, -z, y))


kit.reset()
s = bpy.context.scene
M = {}


def mat(name, rgb, rough=0.6, emit=0.0, metal=0.0):
    if name not in M:
        M[name] = kit.material(name, rgb, metal=metal, rough=rough, emit=emit)
    return M[name]


def window_mat(name, wall, glass):
    """A tower face: a window grid from a brick texture in object space (rows of glass between floor bands)."""
    if name in M:
        return M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 0.16
    brick.inputs["Mortar Size"].default_value = 0.06
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.3
    brick.inputs["Color1"].default_value = (glass[0] / 255, glass[1] / 255, glass[2] / 255, 1)
    brick.inputs["Color2"].default_value = (glass[0] / 255 * 0.8, glass[1] / 255 * 0.8, glass[2] / 255 * 0.9, 1)
    brick.inputs["Mortar"].default_value = (wall[0] / 255, wall[1] / 255, wall[2] / 255, 1)
    nt.links.new(tex.outputs["Object"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.45
    M[name] = m
    return m


def solid(name, size, at, material, rot=0.0, pitch=0.0):
    ob = kit.box(name, size[0], size[2], size[1])  # Roblox (x, y, z) sizes to Blender (x, y=z, z=y)
    ob.location = rb(*at)
    ob.rotation_euler = (pitch, 0, rot)
    ob.data.materials.append(material)
    return ob


# the city: the ground, the street grid's asphalt, every building near the stage
solid("Ground", (4000, 1, 4000), (DATA["tower"][0], GY - 0.5, DATA["tower"][1]), mat("asphalt", (70, 72, 78), 0.9))
TONES = [((196, 190, 178), (120, 160, 200)), ((170, 176, 186), (90, 130, 175)), ((210, 186, 150), (110, 150, 190)),
         ((150, 156, 170), (130, 175, 215))]
for i, (x, z, sx, sz, top, base, is_tower) in enumerate(DATA["buildings"]):
    h = top - base
    wall, glass = TONES[i % len(TONES)]
    if is_tower:
        wall, glass = (205, 200, 190), (140, 190, 230)
    ob = solid("B", (sx, h, sz), (x, base + h / 2, z), window_mat("win%d%d" % (i % len(TONES), is_tower), wall, glass))
    # a roof cap a little darker
    solid("Roof", (sx + 0.6, 1.2, sz + 0.6), (x, top + 0.6, z), mat("roof", (90, 94, 104), 0.8))

FIG = {
    "lodestar": ("navy", (30, 45, 120), (255, 210, 60)),
    "drone": ("metal", (200, 204, 214), (255, 50, 50)),
    "crane": ("suit", (34, 36, 44), (200, 30, 40)),
    "Radiant": ("gold", (255, 220, 120), (255, 255, 255)),
    "Bulwark": ("steel", (110, 120, 150), (255, 200, 60)),
    "Skylance": ("sky", (90, 170, 255), (255, 255, 255)),
    "villain": ("plum", (24, 24, 28), (140, 210, 70)),
    "you": ("hoodie", (235, 90, 80), (60, 60, 80)),
    "citizen": ("street", (120, 200, 120), (70, 70, 76)),
}
SKIN = mat("skin", (240, 200, 160))


def figure(a):
    key = a["kind"]
    if key == "fake":
        key = a["id"]
    name, body, trim = FIG.get(key, FIG["citizen"])
    if a["kind"] == "citizen":
        shirts = [(235, 90, 80), (80, 150, 235), (250, 200, 70), (120, 200, 120), (200, 120, 220), (245, 245, 245)]
        body = shirts[sum(map(ord, a["id"])) % len(shirts)]
        name = "c%d" % (sum(map(ord, a["id"])) % len(shirts))
    mb = mat("fig_" + name, body, 0.5, 0.15 if key in ("lodestar", "Radiant") else 0.0)
    mt = mat("trim_" + name, trim, 0.4, 0.6 if key == "drone" else 0.1)
    k = 1.25 if key == "Bulwark" else 1.0
    feet = a["p"]
    yaw = a["yaw"]
    clip = a["clip"]
    pitch = math.radians(78) if clip == "fly" else 0.0
    crouch = clip == "pound"
    hh = 0.7 if crouch else 1.0
    spec = [
        ((2.0, 2.0 * hh, 1.0), (0, 3.0 * hh, 0), mb),
        ((1.2, 1.2, 1.2), (0, 4.6 * hh, 0), mt if key == "drone" else SKIN),
        ((0.9, 2.0 * hh, 0.9), (-0.55, 1.0 * hh, 0), mt),
        ((0.9, 2.0 * hh, 0.9), (0.55, 1.0 * hh, 0), mt),
        ((0.8, 2.0, 0.8), (-1.45, 3.0 * hh + (1.6 if clip == "fly" else 0), 0), mb),
        ((0.8, 2.0, 0.8), (1.45, 3.0 * hh, 0), mb),
    ]
    if key in ("lodestar", "Radiant", "villain"):
        spec.append(((2.0, 3.2, 0.2), (0, 2.6 * hh, 0.65), mt))  # a cape
    made = []
    c, sn = math.cos(yaw), math.sin(yaw)
    for size, off, m in spec:
        ox, oy, oz = off
        if pitch:
            # pitched forward round the hips (y = 3): up becomes forward (-z)
            oy2 = 3 + (oy - 3) * math.cos(pitch) + oz * math.sin(pitch)
            oz2 = -(oy - 3) * math.sin(pitch) + oz * math.cos(pitch)
            oy, oz = oy2, oz2
        wx, wz = ox * c + oz * sn, -ox * sn + oz * c
        p = solid("Fig", tuple(v * k for v in size), (feet[0] + wx * k, feet[1] + oy * k, feet[2] + wz * k), m, yaw,
                  -pitch)
        made.append(p)
    if key == "lodestar" and clip == "fly":
        # the gold streak behind the hero
        back = Vector((-math.sin(yaw), 0, -math.cos(yaw)))
        tail = solid("Streak", (0.7, 0.7, 26), (feet[0] - back.x * 14, feet[1] + 3, feet[2] - back.z * 14),
                     mat("streak", (255, 200, 60), 0.3, 6.0), yaw)
        made.append(tail)
    if key == "drone":
        for side in (-0.55, 0.55):
            jet = solid("Jet", (0.5, 1.2, 0.5), (feet[0] + side * c, feet[1] - 0.6, feet[2] - side * sn),
                        mat("jet", (120, 210, 255), 0.3, 8.0))
            made.append(jet)
    return made


def effects(fr):
    made = []
    for e in fr["fx"]:
        p = e["p"]
        if e["kind"] == "smash":
            for i in range(26):
                a = i * 2.39996
                r = 2 + (i % 7) * 1.6
                at = (p[0] + math.cos(a) * r, p[1] + math.sin(a * 1.7) * r * 0.7, p[2] + math.sin(a) * r)
                sz = 0.6 + (i % 4) * 0.5
                made.append(solid("Debris", (sz, sz, sz), at, mat("debris", (165, 160, 152), 0.9), a, a * 0.5))
            made.append(solid("Dust", (16, 12, 16), p, mat("dust", (190, 180, 165), 1.0, 0.4)))
        elif e["kind"] == "land":
            ring = solid("Ring", (34, 0.3, 34), (p[0], p[1] + 0.2, p[2]), mat("ring", (255, 220, 90), 0.3, 4.0))
            made.append(ring)
            made.append(solid("Crater", (14, 0.4, 14), (p[0], p[1] + 0.25, p[2]), mat("crater", (40, 38, 36), 1.0)))
    return made


def holes(fr):
    made = []
    x, z, sx, sz, top, base = DATA["tower"]
    r, f = DATA["r"], DATA["f"]
    h = math.floor((top - base) * 0.55)
    hr = sx / 2 if r[0] != 0 else sz / 2
    dark = mat("hole", (20, 18, 16), 1.0)
    for key, side in (("entry", -1), ("exit", 1)):
        if fr["holes"][key]:
            at = (x + r[0] * side * hr, base + h + 2, z + r[2] * side * hr)
            made.append(solid("Hole", (9 if r[0] == 0 else 2.6, 9, 9 if r[2] == 0 else 2.6), at, dark))
    return made


world = bpy.data.worlds.new("Sky")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.58, 0.9, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
s.world = world
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.2
sun.data.color = (1.0, 0.92, 0.8)
sun.rotation_euler = (math.radians(55), 0, math.radians(300))
s.collection.objects.link(sun)
s.render.engine = "CYCLES"
s.cycles.device = "CPU"
s.cycles.samples = 6 if FAST else 14
s.cycles.use_denoising = True
s.cycles.max_bounces = 3
s.render.resolution_x, s.render.resolution_y = (480, 270) if FAST else (640, 360)
s.view_settings.view_transform = "Standard"

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.sensor_fit = "VERTICAL"
cam.data.angle_y = math.radians(70)
cam.data.clip_start = 0.3
cam.data.clip_end = 4000
s.collection.objects.link(cam)
s.camera = cam

os.makedirs(OUT, exist_ok=True)
for i, fr in enumerate(DATA["frames"]):
    path = os.path.join(OUT, "%02d_%05.1f.png" % (i, fr["t"]))
    if os.path.exists(path) and not REDO:
        continue
    made = []
    for a in fr["actors"]:
        made += figure(a)
    made += effects(fr)
    made += holes(fr)
    cam.location = rb(*fr["cam"])
    d = rb(*fr["look"]) - rb(*fr["cam"])
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    kit.render(path)
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)
print("intro storyboard: %d frames" % len(DATA["frames"]))
