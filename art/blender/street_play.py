# street_play.py: a preview sheet of the pt-city street and roof pieces (2026-11-19) from street.py, coloured as
# Config.City.kit.props colours them (tinted pieces in two of the play tints), on a plain floor, facing the camera.
# Run: python art/blender/street_play.py [--fast]   (with the `bpy` module, Blender 5.0)
# Output: art/preview/street_play.png
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.argv.append("--no-export")
import street  # noqa: E402
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

FAST = "--fast" in sys.argv
# piece colours (rgb, material) from Config.City.kit.props, by hand for the sheet: kept in step with City.luau
LOOK = {
    "AwningCanvas": ((222, 70, 62), "Fabric"), "AwningStripe": ((250, 244, 228), "Fabric"),
    "AwningFrame": ((52, 56, 62), "Metal"),
    "TowerLegs": ((96, 74, 58), "Wood"), "TowerTank": ((150, 108, 72), "Wood"), "TowerHoops": ((48, 50, 56), "Metal"),
    "TowerRoof": ((84, 92, 100), "Metal"),
    "AntennaMast": ((140, 146, 152), "Metal"), "AntennaDish": ((236, 236, 230), "Plastic"),
    "AntennaLight": ((255, 60, 60), "Neon"),
    "ACBox": ((206, 208, 204), "Metal"), "ACFan": ((70, 74, 80), "Metal"), "RoofVent": ((150, 156, 160), "Metal"),
    "BoardFrame": ((56, 60, 68), "Metal"), "BoardFace": ((40, 168, 170), "Plastic"), "BoardArt": ((255, 248, 230), "Plastic"),
    "BoardLamps": ((255, 236, 190), "Neon"), "Perch": ((128, 136, 146), "Metal"),
    "NewsBoxBody": ((62, 116, 200), "Plastic"), "NewsBoxGlass": ((200, 226, 236), "Glass"),
    "CartBody": ((250, 196, 58), "Plastic"), "CartTrim": ((64, 68, 76), "Metal"), "CartUmbrella": ((250, 244, 228), "Fabric"),
}
ROW = [("Awning", 0, 11), ("WaterTower", 16, 0), ("RoofAntenna", 28, 0), ("RoofAC", 36, 0), ("RoofVent", 42, 0),
       ("RoofBillboard", 58, 0), ("Perch", 80, 8), ("NewsBox", 90, 0), ("FoodCart", 98, 0)]

for objs in street.PROPS.values():
    for ob in objs.values():
        ob.hide_render = True
        ob.hide_viewport = True

mats = {}
for name, (rgb, kind) in LOOK.items():
    mats[name] = kit.material("m_" + name, rgb, metal=0.6 if kind == "Metal" else 0.0,
                              rough=0.3 if kind in ("Glass", "Neon") else 0.6, emit=3.0 if kind == "Neon" else 0.0)

for prop, x, y in ROW:
    at = Matrix.Translation(Vector((x, 0, y)))
    for piece, src in street.PROPS[prop].items():
        cp = src.copy()
        cp.data = src.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.hide_render = False
        cp.hide_viewport = False
        cp.matrix_world = at @ src.matrix_world
        cp.data.materials.clear()
        cp.data.materials.append(mats[piece])
    if prop in ("Awning", "Perch"):
        wall = kit.box("wall", 14, 0.6, y + 4, at=(x, -0.3, (y + 4) / 2))  # the wall they hang on
        wall.data.materials.append(kit.material("wall_" + prop, (180, 176, 170), rough=0.8))

floor = kit.box("floor", 400, 400, 1, at=(50, 0, -0.5))
floor.data.materials.append(kit.material("floor", (120, 120, 118), rough=0.9))
kit.studio(res=(1000, 420) if FAST else (2000, 840), samples=16 if FAST else 48)
kit.camera((50, 120, 40), (50, 0, 7), lens=40)
kit.render(os.path.join(kit.ROOT, "preview", "street_play.png"))
