# storyboard.py: storyboard frames of the directed prologue's camera shots (prologue-cine, 2026-11-20). Every frame
# is the game's own camera for one segment (art/prologue/storyboard.luau from Shared.PrologueCine, the weekly
# seed's real buildings, roofs, street path and subway lane), rendered from that camera with the Roblox field of
# view (70 degrees, vertical): a blocky stand-in for the hero (gold), Skylance (blue), the kid (yellow) and the
# moment's prop, so the framing can be checked by eye. Grey boxes are the city's buildings (no kit art: this checks
# framing, not looks).
# Run: lune run art/prologue/storyboard.luau && python art/blender/storyboard.py [--fast] [--redo]
# (with the `bpy` module, Blender 5.0). Output: art/export/prologue/frames/*.png, then python3
# art/prologue/storyboard_sheet.py packs them into art/preview/prologue_street.png, prologue_roofs.png and
# prologue_tunnel.png with each frame's beat, shot and prompt written under it.
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

FAST = "--fast" in sys.argv
DATA = json.load(open(os.path.join(kit.ROOT, "export", "prologue", "storyboard.json")))
OUT = os.path.join(kit.ROOT, "export", "prologue", "frames")
GY = DATA["ground"]


def rb(x, y, z):
    """Roblox (x, up, back) to Blender (x, front, up)."""
    return Vector((x, -z, y))


kit.reset()
s = bpy.context.scene
mats = {
    "bldg": kit.material("bldg", (150, 150, 158), rough=0.8),
    "roof": kit.material("roof", (120, 126, 140), rough=0.8),
    "ground": kit.material("ground", (88, 92, 98), rough=0.9),
    "path": kit.material("path", (230, 200, 90), rough=0.6, emit=0.4),
    "hero": kit.material("hero", (255, 196, 40), rough=0.4, emit=0.25),
    "skin": kit.material("skin", (240, 200, 160), rough=0.6),
    "sky": kit.material("skylance", (90, 170, 255), rough=0.4, emit=0.25),
    "kid": kit.material("kid", (255, 220, 70), rough=0.5),
    "prop": kit.material("prop", (250, 200, 40), rough=0.5),
    "rubble": kit.material("rubble", (110, 100, 92), rough=0.9),
    "wood": kit.material("wood", (120, 80, 50), rough=0.8),
    "tunnel": kit.material("tunnel", (70, 70, 78), rough=0.9),
}


def solid(name, size, at, mat, rot=0.0):
    ob = kit.box(name, size[0], size[2], size[1])  # Roblox (x, y, z) sizes to Blender (x, y=z, z=y)
    ob.location = rb(*at)
    ob.rotation_euler = (0, 0, rot)
    ob.data.materials.append(mats[mat])
    return ob


# the city round the route: the ground and every building box
ground = solid("Ground", (3000, 1, 3000), (DATA["stage"][0], GY - 0.5, DATA["stage"][2]), "ground")
for x, z, sx, sz, top in DATA["buildings"]:
    h = top - GY
    solid("B", (sx, h, sz), (x, GY + h / 2, z), "bldg")
# the street path the run follows (a thin gold line on the ground)
pts = DATA["runPath"]
for i in range(1, len(pts)):
    a, b = pts[i - 1], pts[i]
    d = math.hypot(b[0] - a[0], b[2] - a[2])
    mid = ((a[0] + b[0]) / 2, GY + 0.08, (a[2] + b[2]) / 2)
    seg = solid("Path", (0.6, 0.1, d), mid, "path")
    seg.rotation_euler = (0, 0, -math.atan2(b[0] - a[0], b[2] - a[2]))
# the subway lane: floor, walls, ceiling, the chamber
L = DATA["lane"]
length = L["z0"] - L["z1"]
zc = (L["z0"] + L["z1"]) / 2
fy = L["floorY"]
solid("Floor", (L["width"], 1, length + 20), (L["x"], fy - 0.5, zc), "tunnel")
for side in (-1, 1):
    solid("Wall", (1, L["height"], length), (L["x"] + side * L["width"] / 2, fy + L["height"] / 2, zc), "tunnel")
solid("Ceil", (L["width"], 1, length), (L["x"], fy + L["height"], zc), "tunnel")
cz = L["z1"] - L["chamber"] / 2
solid("Chamber", (L["chamber"], 1, L["chamber"]), (L["x"], fy - 0.5, cz), "tunnel")
for side in (-1, 1):
    solid("CWall", (1, L["height"], L["chamber"]), (L["x"] + side * L["chamber"] / 2, fy + L["height"] / 2, cz), "tunnel")
solid("CBack", (L["chamber"], L["height"], 1), (L["x"], fy + L["height"] / 2, L["z1"] - L["chamber"]), "tunnel")
# tunnel lamps so the pocket is lit
for k in range(0, int(length) + 1, 30):
    lamp = bpy.data.objects.new("Lamp", bpy.data.lights.new("Lamp", "POINT"))
    lamp.data.energy = 3500
    lamp.data.color = (1.0, 0.85, 0.6)
    lamp.location = rb(L["x"], fy + L["height"] - 3, L["z0"] - k)
    s.collection.objects.link(lamp)


def figure(name, feet, yaw, body, scale=1.0, crouch=False):
    """A blocky R15-ish stand-in at the feet point, facing yaw (radians, Roblox: atan2(dx, dz))."""
    parts = []
    k = scale
    h = 0.75 if crouch else 1.0
    spec = [
        ((2.0, 2.0 * h, 1.0), (0, 3.0 * h + 0.0, 0), body),  # torso
        ((1.2, 1.2, 1.2), (0, 4.6 * h, 0), "skin"),  # head
        ((0.9, 2.0 * h, 0.9), (-0.55, 1.0 * h, 0), body),  # legs
        ((0.9, 2.0 * h, 0.9), (0.55, 1.0 * h, 0), body),
        ((0.8, 2.0 * h, 0.8), (-1.45, 3.0 * h, 0), body),  # arms
        ((0.8, 2.0 * h, 0.8), (1.45, 3.0 * h, 0), body),
    ]
    for size, off, mat in spec:
        c, sn = math.cos(yaw), math.sin(yaw)
        ox, oz = off[0] * c + off[2] * sn, -off[0] * sn + off[2] * c
        p = solid(name, tuple(v * k for v in size), (feet[0] + ox * k, feet[1] + off[1] * k, feet[2] + oz * k), mat)
        p.rotation_euler = (0, 0, yaw)
        parts.append(p)
    return parts


def prop(fr):
    fx, at = fr.get("fx"), fr.get("at")
    if not fx or not at:
        return []
    if fx == "barrier":
        return [solid("Barrier", (9, 2.4, 0.6), (at[0], at[1] + 1.2, at[2]), "prop", fr["yaw"])]
    if fx == "pile":
        return [solid("Pile", (L["width"] - 6, 3, 4), (at[0], at[1] + 1.5, at[2]), "rubble")]
    if fx == "beam":
        return [solid("Beam", (14, 1.6, 1.6), (at[0], at[1] + 5.2, at[2]), "wood")]
    if fx == "slab":
        return [solid("Chunk", (5, 3, 5), (at[0], at[1] + 8, at[2]), "rubble")]
    if fx == "sign":
        return [solid("Sign", (8, 3, 1), (at[0], at[1] + 20, at[2]), "prop")]
    if fx == "runner":
        return figure("Runner", at, fr["yaw"] + math.pi, "bldg")
    return []


# light: a bright afternoon (the game's prologue clock is 14.5)
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.7, 0.95, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
s.world = world
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), 0, math.radians(320))
s.collection.objects.link(sun)
s.render.engine = "CYCLES"  # (headless: no GPU, so Cycles on the CPU at a few samples, denoised)
s.cycles.device = "CPU"
s.cycles.samples = 6 if FAST else 16
s.cycles.use_denoising = True
s.cycles.max_bounces = 3
s.render.resolution_x, s.render.resolution_y = (480, 270) if FAST else (640, 360)
s.view_settings.view_transform = "Standard"

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.sensor_fit = "VERTICAL"
cam.data.angle_y = math.radians(70)  # Roblox's FieldOfView is vertical, 70 by default
cam.data.clip_start = 0.3
cam.data.clip_end = 3000
s.collection.objects.link(cam)
s.camera = cam

os.makedirs(OUT, exist_ok=True)
REDO = "--redo" in sys.argv
for i, fr in enumerate(DATA["frames"]):
    path = os.path.join(OUT, "%02d_%s_%s.png" % (i, fr["beat"], fr["id"]))
    if os.path.exists(path) and not REDO:
        continue  # (a long run can be resumed; --redo renders every frame again)
    made = []
    crouch = fr.get("clip") in ("leapCrouch", "brace", "powerCharge")
    made += figure("Hero", fr["hero"], fr["yaw"], "hero", crouch=crouch)
    ex = fr.get("extra") or {}
    if ex.get("skylance"):
        made += figure("Skylance", ex["skylance"], fr["yaw"], "sky")
    if ex.get("kid"):
        made += figure("Kid", ex["kid"], fr["yaw"] + math.pi, "kid", scale=0.68)
    made += prop(fr)
    cam.location = rb(*fr["cam"])
    d = rb(*fr["look"]) - rb(*fr["cam"])
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    kit.render(path)
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)
print("storyboard: %d frames" % len(DATA["frames"]))
