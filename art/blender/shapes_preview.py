# shapes_preview.py: art/preview/shapes.png (every look of shapes.py set the way the game stands it over its boxes:
# the pond's rocks, a park bench, the beach, a small windmill, a tractor, a parked car, a pier, a court hoop, the
# lighthouse, and a flat roof with its cornice, a parapet and a low roof's edge) and shapes_close.png (close-ups).
# Called by shapes.py --preview.
import math
import os

import kit
import bpy
from mathutils import Vector

from studs import rb

TINTS = {"UmbrellaCloth": (226, 72, 60), "LoungerCushion": (60, 130, 210), "AwningCloth": (226, 72, 60), "TowelCloth": (60, 130, 210), "CarPaint": (230, 190, 60),
         "LightBand": (204, 52, 44), "ParapetWall": (196, 188, 172), "CorniceRun": (226, 218, 200)}


def run(GROUPS, LOOKS, FRAMES, INFO, MAPS, fast=False):
    mats = {}
    for gname, g in GROUPS.items():
        pm = None
        if gname in MAPS:
            import vkit
            pm = vkit.export_material(g, MAPS[gname])
        for name in g.meshes:
            inf = INFO[name]
            if inf["maps"] and pm:
                mats[name] = pm
                continue
            rgb = TINTS.get(name, inf["rgb"]) if inf["tint"] else inf["rgb"]
            if inf["maps"]:
                rgb = (150, 142, 132)
            m = kit.material("pv_" + name, rgb, rough=0.6, metal=0.6 if inf["mat"] == "Metal" else 0.0,
                             emit=3.0 if inf["mat"] == "Neon" else 0.0)
            if inf["alpha"]:
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - inf["alpha"]
            mats[name] = m
    src = {}
    for g in GROUPS.values():
        for name, ob in g.meshes.items():
            ob.hide_render = True
            src[name] = ob

    def place(lk, x, y, z, sx=None, sy=None, sz=None, ry=0.0):
        """The look over a box centred at Roblox (x, y, z) of size (sx, sy, sz), turned ry degrees."""
        fx, fy, fz = FRAMES[lk]
        sx, sy, sz = sx or fx, sy or fy, sz or fz
        for name in LOOKS[lk]:
            ob = src[name]
            cp = ob.copy()
            cp.data = ob.data
            bpy.context.scene.collection.objects.link(cp)
            cp.hide_render = False
            cp.data.materials.clear()
            cp.data.materials.append(mats[name])
            cp.scale = (sx / fx, sz / fz, sy / fy)
            cp.rotation_euler = (0, 0, math.radians(ry))
            cp.location = Vector(rb(x, y, z))

    def ring(lk, x, y, z, sx, sy, sz):
        fx, fy, fz = FRAMES[lk]
        for (ox, oz, ry, length) in ((0, -sz / 2, 0, sx), (0, sz / 2, 180, sx), (-sx / 2, 0, 90, sz), (sx / 2, 0, -90, sz)):
            for name in LOOKS[lk]:
                ob = src[name]
                cp = ob.copy()
                cp.data = ob.data
                bpy.context.scene.collection.objects.link(cp)
                cp.hide_render = False
                cp.data.materials.clear()
                cp.data.materials.append(mats[name])
                cp.scale = (length / fx, 1, sy / fy)
                a = math.radians(ry)
                # the run's face is at -z in its frame: out past the box edge by half its depth
                dx, dz = math.sin(a) * 0, 0
                cx = x + ox - math.sin(a) * (fz / 2) * 0
                cz = z + oz
                # direction outwards
                nx, nz = (0, -1) if ry == 0 else (0, 1) if ry == 180 else (-1, 0) if ry == 90 else (1, 0)
                cx = x + ox + nx * (fz / 2 - 0.5)
                cz = z + oz + nz * (fz / 2 - 0.5)
                cp.rotation_euler = (0, 0, math.radians(-ry) if False else a)
                cp.location = Vector(rb(cx + dx, y, cz + dz))

    def plain(sx, sy, sz, x, y, z, rgb, shape="box"):
        if shape == "cyl":
            ob = kit.cyl("p", sx / 2, sx / 2, sy, at=rb(x, y, z), segs=32)
        else:
            ob = kit.box("p", sx, sz, sy, at=rb(x, y, z))
        ob.data.materials.append(kit.material("pl%d%d%d" % rgb, rgb, rough=0.8))

    # the ground
    plain(400, 0.2, 160, 60, -0.1, 0, (186, 190, 176))
    # the pond and its rocks
    plain(18, 0.6, 18, -60, 0.3, -20, (90, 150, 200), "cyl")
    place("RockA", -52, 1.5, -26, 5, 4, 5)
    place("RockB", -68, 1.2, -14, 4, 3, 4)
    place("RockC", -55, 1.5, -10, 5, 4, 5)
    # a park bench and the beach
    place("ParkBench", -60, 1, 6)
    plain(60, 0.2, 30, -40, 0.12, 30, (232, 214, 170))
    for k, x in enumerate((-56, -42, -28)):
        place("UmbrellaPole", x, 4, 26)
        place("UmbrellaTop", x, 8, 26, 9, 1, 9)
        place("BeachTowel", x + 4, 0.25, 32, ry=10 * k)
    place("Driftwood", -40, 0.8, 40)
    place("Dune", -20, 0.3, 40, 26, 10, 16)
    # an outskirts shop with its awning and a pool with its coping
    plain(26, 14, 20, -90, 7, 10, (240, 214, 170))
    place("ShopAwning", -90, 9, 22, 23.4, 0.6, 4)
    plain(16, 0.6, 12, -90, 0.3, 40, (90, 170, 220))
    ring("PoolEdge", -90, 0.3, 40, 16, 0.6, 12)
    place("PoolLadder", -86, 0.6 + 1.4, 34 + 0.2)
    for x in (-94, -89):
        place("Lounger", x, 0.7, 51)
    place("PondRim", -60, 0.3, -20, 18, 0.6, 18)
    # Radio Hill's mast on a step
    plain(20, 14, 20, 150, 7, -50, (120, 116, 110))
    place("RadioMast", 150, 74, -50, 3, 120, 3)
    # a small windmill
    place("WindTower", -10, 14, 0, 3, 28, 3)
    place("WindBladeV", -10, 28, -2, 1, 22, 1)
    place("WindBladeH", -10, 28, -2, 22, 1, 1)
    # a tractor and a parked car
    place("Tractor", 8, 3, -14)
    place("TractorCab", 8, 6.5, -12.5)
    place("LotCar", 22, 2.3, -14)
    # a pier on its pilings and a court hoop
    plain(8, 1, 30, 40, 2, -20, (150, 112, 74))
    for z in (-30, -10):
        place("Piling", 36, -2, z)
        place("Piling", 44, -2, z)
    place("HoopPost", 22, 5, 10, ry=0)
    plain(16, 0.4, 16, 22, 0.2, 2, (70, 110, 170))
    # the lighthouse
    place("RockBase", 70, 3, -10, 26, 6, 26)
    plain(12, 60, 12, 70, 36, -10, (240, 240, 236), "cyl")
    place("LightBand", 70, 6 + 60 * 0.35, -10, 12.6, 6, 12.6)
    place("LightBand", 70, 6 + 60 * 0.7, -10, 12.6, 6, 12.6)
    place("Lantern", 70, 6 + 63, -10, 8, 6, 8)
    # a flat roof: the body, its cap with the cornice round it, a parapet; a low roof's edge
    plain(30, 40, 24, 110, 20, 10, (196, 180, 160))
    plain(31, 1.2, 25, 110, 40.6, 10, (226, 218, 200))
    ring("CorniceRun", 110, 40.6, 10, 31, 1.2, 25)
    place("Parapet", 110, 42.2, -1.5, 28, 2, 1.5)
    plain(20, 16, 20, 140, 8, 10, (210, 196, 170))
    plain(21, 2, 21, 140, 17, 10, (180, 176, 170))
    ring("RoofEdge", 140, 17, 10, 21, 2, 21)

    kit.studio(res=(2000, 900) if not fast else (1000, 450), samples=12 if fast else 48)
    kit.camera(rb(30, 110, 170), rb(30, 20, -5), lens=24)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes.png"))
    kit.camera(rb(-30, 12, 70), rb(-40, 2, 20), lens=35)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_beach.png"))
    kit.camera(rb(14, 10, 22), rb(14, 3, -8), lens=35)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_farm.png"))
    kit.camera(rb(130, 52, 60), rb(115, 38, 5), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_roofs.png"))
    kit.camera(rb(88, 80, 40), rb(70, 62, -10), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_lighthouse.png"))
    kit.camera(rb(-72, 16, 70), rb(-90, 3, 38), lens=35)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_pool.png"))
    kit.camera(rb(-48, 14, 4), rb(-60, 0, -20), lens=35)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_pond.png"))
    kit.camera(rb(-70, 14, 60), rb(-88, 5, 20), lens=35)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_shop.png"))
    kit.camera(rb(185, 60, 20), rb(150, 70, -50), lens=30)
    kit.render(os.path.join(kit.ROOT, "preview", "shapes_mast.png"))
