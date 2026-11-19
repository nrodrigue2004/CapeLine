# life_preview.py: art/preview/life.png, every look of the living-world set (life.py) in its game colours
# (Config.Life.looks), the trees as the game stands them (trunk box at 0.4 x size, crown at 1 x size).
# Run: ~/tools/bpyenv/bin/python art/blender/life_preview.py [--fast]
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.argv.append("--no-export")
import life  # noqa: E402  (builds the set into the scene)
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

FAST = "--fast" in sys.argv
COL = {
    "TreeTrunk": ((110, 78, 54), 0.9), "CanopyRound": ((88, 150, 64), 0.8), "CanopyTall": ((76, 140, 70), 0.8),
    "CanopyPine": ((46, 104, 64), 0.8), "CropRow": ((110, 178, 70), 0.8), "CornRow": ((150, 170, 70), 0.8),
    "CornCobs": ((240, 200, 70), 0.6), "HayBale": ((222, 184, 92), 0.95), "DoorPanel": ((60, 90, 140), 0.5),
    "DoorKnob": ((212, 175, 80), 0.3), "SiloBody": ((190, 196, 200), 0.4), "SiloDome": ((200, 205, 210), 0.4),
    "ShopFrame": ((40, 46, 58), 0.5), "ShopGlass": ((180, 215, 235), 0.05), "ShopBack": ((150, 118, 84), 0.8),
    "ShopSign": ((214, 60, 56), 0.5), "VendBody": ((210, 50, 50), 0.4), "VendTrim": ((40, 42, 48), 0.5),
    "VendGlass": ((200, 230, 245), 0.05), "VendCans": ((230, 230, 235), 0.3), "VendLight": ((255, 250, 220), 0.5),
    "Can": ((40, 110, 200), 0.3), "Manhole": ((70, 72, 76), 0.6), "PigeonBody": ((130, 134, 146), 0.7),
    "PigeonWingL": ((110, 114, 126), 0.7), "PigeonWingR": ((110, 114, 126), 0.7), "DroneBody": ((240, 242, 246), 0.4),
    "DroneArm": ((44, 48, 56), 0.5), "DroneRotor": ((30, 32, 36), 0.5), "DroneEye": ((255, 60, 60), 0.3),
    "FlagPole": ((220, 222, 226), 0.3), "FlagFinial": ((230, 190, 70), 0.3),
}
EMIT = {"VendLight": 3.0, "DroneEye": 4.0}

for name, ob in life.ALL.items():
    rgb, rough = COL.get(name, ((200, 0, 200), 0.5))
    m = kit.material("m_" + name, rgb, rough=rough, emit=EMIT.get(name, 0))
    if name in ("ShopGlass", "VendGlass"):
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Alpha"].default_value = 0.45
    ob.data.materials.clear()
    ob.data.materials.append(m)


def at(ob, loc, rz=0.0):
    ob.location = Vector(loc) + ob.location
    ob.rotation_euler = (0, 0, rz)


# trees: size 10 (trunk box centre at 4, crown at 10); three of them side by side with the trunk copied
x = -40.0
for k, canopy in enumerate(("CanopyRound", "CanopyTall", "CanopyPine")):
    t = life.ALL["TreeTrunk"] if k == 0 else life.ALL["TreeTrunk"].copy()
    if k:
        bpy.context.scene.collection.objects.link(t)
    at(t, (x + k * 12, 0, 4))
    at(life.ALL[canopy], (x + k * 12, 0, 10))
# crops, corn, a bale, a door, the silo
at(life.ALL["CropRow"], (-2, 6, 1.2))
at(life.ALL["CornRow"], (-2, -2, 1.2))
at(life.ALL["CornCobs"], (-2, -2, 1.2))
at(life.ALL["HayBale"], (18, 4, 2.5))
at(life.ALL["DoorPanel"], (18, -4, 3.5))
at(life.ALL["DoorKnob"], (18, -4, 3.5))
at(life.ALL["SiloBody"], (32, 4, 15))
at(life.ALL["SiloDome"], (32, 4, 30))
# foot looks
for name in ("ShopFrame", "ShopGlass", "ShopBack", "ShopSign"):
    at(life.ALL[name], (52, -6, 0))
for name in ("VendBody", "VendTrim", "VendGlass", "VendCans", "VendLight"):
    at(life.ALL[name], (64, -6, 0))
at(life.ALL["Can"], (67, -9, 0))
at(life.ALL["Manhole"], (70, -9, 0))
for name in ("PigeonBody", "PigeonWingL", "PigeonWingR"):
    at(life.ALL[name], (72, -10, 0))
for name in ("DroneBody", "DroneArm", "DroneEye"):
    at(life.ALL[name], (76, -8, 6))
for sx in (-1, 1):
    for sy in (-1, 1):
        r = life.ALL["DroneRotor"].copy()
        bpy.context.scene.collection.objects.link(r)
        at(r, (76 + sx * 1.3, -8 + sy * 1.3, 6.32))
life.ALL["DroneRotor"].hide_render = True
for name in ("FlagPole", "FlagFinial"):
    at(life.ALL[name], (82, -6, 0))

ground = kit.box("ground", 300, 120, 0.2, at=(20, 0, -0.1))
ground.data.materials.append(kit.material("g", (170, 172, 166), rough=0.9))
kit.studio(res=(2000, 840) if not FAST else (1000, 420), samples=12 if FAST else 48)
kit.camera((22, 105, 30), (22, 0, 7), lens=30)
kit.render(os.path.join(kit.ROOT, "preview", "life.png"))
# close-ups of the shop front, the machine, the pigeon and the drone
kit.camera((66, 14, 6), (66, -7, 3.5), lens=32)
kit.render(os.path.join(kit.ROOT, "preview", "life_street.png"))
