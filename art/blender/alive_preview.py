# alive_preview.py: the round 3 looks (alive.py) the way the game stands them over their boxes:
# art/preview/alive_safehouse.png (a safehouse: pad, shelter, canopy and its five terminals, close and wide),
# alive_docks.png (a gantry crane over the quay and water with the Foundry's chimney behind) and alive_garden.png
# (an Uptown roof garden from a flying hero's height). Called by alive.py --preview.
import math
import os

import kit
import bpy
from mathutils import Vector

from studs import rb

TINTS = {"TermBankGlow": (255, 205, 70), "TermLoadoutGlow": (110, 190, 255), "TermRespawnGlow": (120, 230, 150),
         "TermContractsGlow": (255, 140, 60), "TermWeaponsGlow": (200, 205, 215)}


def run(GROUPS, LOOKS, FRAMES, INFO, MAPS, fast=False):
    import vkit

    mats = {}
    for gname, g in GROUPS.items():
        pm = vkit.export_material(g, MAPS[gname]) if gname in MAPS else None
        for name in g.meshes:
            inf = INFO[name]
            if inf["maps"] and pm:
                mats[name] = pm
                continue
            rgb = TINTS.get(name, inf["rgb"]) if inf["tint"] else inf["rgb"]
            if inf["maps"]:
                rgb = (150, 142, 132)
            m = kit.material("pv_" + name, rgb, rough=0.6, metal=0.6 if inf["mat"] == "Metal" else 0.0,
                             emit=4.0 if inf["mat"] == "Neon" else 0.0)
            if inf["alpha"]:
                m.blend_method = "BLEND"
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - inf["alpha"]
            mats[name] = m
    src = {}
    for g in GROUPS.values():
        for name, ob in g.meshes.items():
            ob.hide_render = True
            src[name] = ob
    made = []

    def place(lk, x, y, z, sx=None, sy=None, sz=None, ry=0.0):
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
            made.append(cp)

    def plain(sx, sy, sz, x, y, z, rgb, shape="box", emit=0.0, alpha=0.0):
        if shape == "cyl":
            ob = kit.cyl("p", sx / 2, sx / 2, sy, at=rb(x, y, z), segs=32)
        else:
            ob = kit.box("p", sx, sz, sy, at=rb(x, y, z))
        m = kit.material("pl%d_%d_%d_%g" % (rgb + (emit,)), rgb, rough=0.8, emit=emit)
        if alpha:
            m.blend_method = "BLEND"
            m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - alpha
        ob.data.materials.append(m)
        made.append(ob)

    def clear():
        for o in made:
            bpy.data.objects.remove(o, do_unlink=True)
        made.clear()
        for o in list(bpy.data.objects):
            if o.type == "CAMERA":
                bpy.data.objects.remove(o, do_unlink=True)

    kit.studio(res=(1600, 900), samples=12 if fast else 40)
    out = os.path.join(kit.ROOT, "preview")

    # ---------------------------------------------------------------- a safehouse as WorldMap.buildSafehouse lays it
    def safehouse(x0, z0):
        top = 1.2
        plain(140, 0.2, 140, x0, -0.1, z0, (120, 124, 120))
        plain(36, 1.2, 36, x0, 0.6, z0, (226, 230, 234))
        place("SafePadRing", x0, 0.6, z0)
        sz = z0 - 36 / 2 + 7
        plain(22, 12, 10, x0, top + 6, sz, (92, 100, 112))  # the shelter (a kit Office box in the game)
        for k in range(4):
            plain(3.4, 3.0, 0.1, x0 - 7.5 + k * 5, top + 7, sz + 5.05, (60, 80, 110), emit=0.3)
        place("SafeCanopy", x0, top + 12.75, sz + 3)
        plain(14, 2, 0.4, x0, top + 10, sz + 5.2, (120, 200, 255), emit=3.0)
        for i, kind in enumerate(("Bank", "Loadout", "Respawn", "Contracts", "Weapons")):
            place("Term" + kind, x0 + (i - 2) * 7, top + 2.5, sz + 8)

    safehouse(0, 0)
    kit.camera(rb(9, 9, 30), rb(0, 5, -6), lens=30)
    kit.render(os.path.join(out, "alive_safehouse.png"))
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    kit.camera(rb(-26, 40, 52), rb(0, 4, -4), lens=30)
    kit.render(os.path.join(out, "alive_safehouse_wide.png"))
    # the terminals up close, side by side
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    kit.camera(rb(0, 4.5, 16), rb(0, 3.6, -9), lens=48)
    kit.render(os.path.join(out, "alive_terminals.png"))
    clear()

    # ---------------------------------------------------------------- the Docks: a crane on the quay, the chimney behind
    plain(300, 0.2, 120, 0, -0.1, -40, (150, 146, 140))
    plain(300, 0.2, 200, 0, -3, 120, (60, 110, 150), alpha=0.1)
    span, height, boom, cz = 34, 102, 70, 0
    place("CraneLeg", -span / 2, height / 2, cz, 4, height, 4)
    place("CraneLeg", span / 2, height / 2, cz, 4, height, 4)
    place("CraneBeam", 0, height + 2, cz, span + 6, 6, 6)
    place("CraneBoom", 0, height - 4, cz + boom / 2, 4, 4, boom)
    for k, (x, z, col) in enumerate(((-30, -20, (200, 70, 60)), (-30, -26, (60, 120, 200)), (26, -22, (60, 160, 90)))):
        plain(12, 6, 6, x, 3, z, col)
    for k in range(3):
        place("FoundryChimney", 90 + k * 34, 85, -90, 16, 170, 16)
        plain(12, 2, 12, 90 + k * 34, 171, -90, (255, 90, 60), "cyl", emit=4.0)
    plain(130, 70, 50, 120, 35, -130, (62, 58, 60))
    kit.camera(rb(-60, 40, 150), rb(25, 60, -30), lens=24)
    kit.render(os.path.join(out, "alive_docks.png"))
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    kit.camera(rb(-14, 96, 34), rb(0, 98, 10), lens=30)
    kit.render(os.path.join(out, "alive_crane_close.png"))
    clear()

    # ---------------------------------------------------------------- an Uptown roof garden on a 46 x 48 roof
    plain(46, 40, 48, 0, -20, 0, (210, 196, 170))
    plain(28, 1.2, 29, 0, 0.6, 0, (70, 120, 60))
    place("RoofGarden", 0, 0.6, 0)
    kit.camera(rb(-30, 34, 40), rb(0, 0, 0), lens=34)
    kit.render(os.path.join(out, "alive_garden.png"))
