# art/store/cast.py: the newer villains and bosses for the store art refresh (art/store/store2.py, overnight queue
# item 13, 2026-11-18), on top of art/store/common.py:
#   * the side quest finales that are not people (art/blender/finales.py: the Bramblebeast, the Voidhound, the
#     Wind-Up Giant), from their own FBX meshes and baked texture sets (art/export/finales), posed on the blocky
#     R15 rig like the heroes, coloured as EnemyRenderer colours them (FinaleArt.tint under the see-through region);
#   * the three famous fakes (Config.Enemies Radiant, Bulwark, Skylance fake.look) in their creator looks on the
#     blocky body, with their cracked Hero faces (art/export/clothes/faces) where the hook needs one;
#   * any world boss (art/export/Bosses.fbx: Rustjaw Prime, Lumen Maw, Leviathan Engine) with its own objectives
#     (BossArt anchors) and a phase's glow colour (Config.BossArt glow).
# Run nothing here directly: art/store/store2.py imports it after common.
import json
import math
import os

import common as C
from mathutils import Matrix, Vector

bpy = C.bpy
kit = C.kit
FINALES = os.path.join(C.ASSETS, "export", "finales")

# ------------------------------------------------------------------------------------------------ finales
_finale_src = {}


def _finale_pieces(name):
    if name in _finale_src:
        return _finale_src[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(FINALES, name + ".fbx"))
    out = {}
    for ob in set(bpy.data.objects) - before:
        if ob.type != "MESH":
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        ob.hide_render = True
        ob.hide_viewport = True
        ob.matrix_world = Matrix.Identity(4)
        out[ob.name.split(".")[0]] = ob
    _finale_src[name] = out
    return out


def finale_mat(name, tint):
    """The finale's texture set over the tint (SurfaceAppearance Overlay: the colour map's alpha is 0 where the
    part colour, FinaleArt.tint, shows)."""
    m = bpy.data.materials.new("finale_" + name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex(kind, data):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = C._image(os.path.join(FINALES, "%s_%s.png" % (name, kind)), data)
        return t

    c = tex("Color", False)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = C.lin3(tint)
    nt.links.new(c.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(c.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    nt.links.new(tex("Roughness", True).outputs["Color"], p.inputs["Roughness"])
    nt.links.new(tex("Metalness", True).outputs["Color"], p.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex("Normal", True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return m


def finale(name, root, bends=None, coll=None, glow=None):
    """A side quest finale on the blocky rig (root as common.root_matrix / root_axes; scale it there for the
    Wind-Up Giant's 10-stud body). Each R15 mesh fills its part's box; the extras sit against their part by
    src/config/FinaleArt.luau's fractions (art/export/finales/finales.json). glow: {piece: (rgb, strength)} to
    light a piece up (the Bramblebeast's seed of light). Returns the part matrices and the objects."""
    src = _finale_pieces(name)
    fit = json.load(open(os.path.join(FINALES, "finales.json")))[name]
    M = C.rig(root, bends or {})
    coll = coll or C.collection("Villains")
    mat = finale_mat(name, tuple(fit["tint"]))
    blocks = dict(C.BLOCKS)
    blocks["Head"] = (-0.6, 0.6, -0.6, 0.6, 4.0, 5.2)  # finales.py's head box
    obs = []

    def centre(part):
        x0, x1, y0, y1, z0, z1 = blocks[part]
        return Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), Vector((x1 - x0, y1 - y0, z1 - z0))

    for n in C.PARTS + list(fit["extras"]):
        if n not in src:
            continue
        if n in fit["extras"]:
            ex = fit["extras"][n]
            parent = ex["parent"]
            bc, bs = centre(parent)
            ox, oy, oz = ex["offset"]  # Roblox x, up, back as fractions of the part's size
            c = bc + Vector((ox * bs.x, -oz * bs.y, oy * bs.z))
        else:
            parent = n
            c, _ = centre(n)
        cp = src[n].copy()
        cp.data = src[n].data.copy()
        C.bpy.context.scene.collection.objects.link(cp)
        cp.hide_render = False
        cp.hide_viewport = False
        cp.matrix_world = M[parent] @ Matrix.Translation(c)
        cp.data.materials.clear()
        cp.data.materials.append(mat)
        obs.append(C.put(cp, coll))
    return M, obs


# ------------------------------------------------------------------------------------------------ the famous fakes
# Config.Enemies.<Name>.fake.look (lore step 4): the creator looks on the blocky body, in the palette's colours
RADIANT_GOLD, RADIANT_WHITE, RADIANT_YELLOW = (255, 210, 60), (245, 245, 245), (255, 240, 80)
RADIANT = dict(suit=(RADIANT_GOLD, RADIANT_GOLD, (232, 176, 44)), gloves=RADIANT_WHITE, boots=RADIANT_WHITE,
               belt=(RADIANT_WHITE, RADIANT_YELLOW), cape_rgb=RADIANT_WHITE, hair="swept", hair_rgb=RADIANT_GOLD,
               skin=(241, 194, 160), face="Hero")
# Bulwark, "The Unbreakable": Plated Suit in metal blue, silver Great Pauldrons, Armored Gauntlets, Champion Belt,
# the Hex Badge, a black Buzz Cut, the Stern Face; a Titan build, the tallest height
BULWARK_BLUE, BULWARK_SILVER, BULWARK_YELLOW = (40, 96, 210), (200, 206, 216), (255, 240, 80)
BULWARK = dict(suit=(BULWARK_BLUE, BULWARK_BLUE, (30, 64, 150)), gloves=BULWARK_SILVER, boots=(40, 44, 56),
               belt=(BULWARK_SILVER, BULWARK_YELLOW), hair="swept", hair_rgb=(24, 22, 26), skin=(141, 95, 64),
               face="Stern")
# Skylance, "The Silver Streak": Racer Stripe in azure and white, a white Wind Scarf, Bracers, Tall Boots, the Ring
# Star, a violet High Ponytail, the Sharp Face; a Small build
SKY_AZURE, SKY_WHITE, SKY_CYAN = (40, 150, 240), (245, 245, 250), (90, 240, 255)
SKYLANCE = dict(suit=(SKY_AZURE, SKY_AZURE, (30, 100, 190)), gloves=SKY_WHITE, boots=SKY_WHITE,
                belt=(SKY_WHITE, SKY_CYAN), hair="swept", hair_rgb=(150, 80, 230), skin=(224, 172, 130), face="Sharp")


def radiant_gear(M):
    """Radiant's Halo, metal Epaulettes, boot wings and the Burst emblem (art/store/thumbs.py's look)."""
    gold = C.flat("rgold", RADIANT_GOLD, rough=0.25, metal=0.8, coat=0.4)
    out = []
    halo = kit.torus("halo", 0.66, 0.08, at=(0, 0, 0), segs=40, csegs=8)
    halo.matrix_world = Matrix.Translation((0, -0.15, 5.75)) @ Matrix.Rotation(math.radians(-30), 4, "X")
    halo.data.materials.append(C.glow_mat("halo", (255, 226, 110), 9.0))
    out.append(C._apply(halo, M["Head"]))
    for sx, side in ((-1, "Left"), (1, "Right")):
        ep = kit.box("epaulette", 1.2, 1.2, 0.3, at=(sx * 1.5, 0, 4.02))
        kit.bevel(ep, 0.1, 2)
        ep.data.materials.append(gold)
        out.append(C._apply(ep, M[side + "UpperArm"]))
        for k in range(3):
            f = kit.box("fringe", 0.14, 0.14, 0.36, at=(sx * 2.0, -0.36 + k * 0.36, 3.72))
            f.data.materials.append(gold)
            out.append(C._apply(f, M[side + "UpperArm"]))
        wing = kit.box("wing", 0.08, 0.8, 0.45, at=(sx * 1.05, -0.3, 0.9))
        wing.data.materials.append(gold)
        out.append(C._apply(wing, M[side + "LowerLeg"]))
    disc = kit.cyl("burstd", 0.56, 0.56, 0.05, at=(0, 0.53, 3.35), segs=32, axis="Y")
    disc.data.materials.append(C.flat("burstw", RADIANT_WHITE, rough=0.3, coat=0.5))
    out.append(C._apply(disc, M["UpperTorso"]))
    vs = []
    for i in range(12):
        a = i * math.pi / 6
        r0, r1, w = 0.17, (0.62 if i % 2 == 0 else 0.46), 0.055
        ux, uz = math.cos(a), math.sin(a)
        vs += [(ux * r0 - uz * w, 0.57, 3.35 + uz * r0 + ux * w), (ux * r1, 0.57, 3.35 + uz * r1),
               (ux * r0 + uz * w, 0.57, 3.35 + uz * r0 - ux * w)]
    me = bpy.data.meshes.new("burst")
    me.from_pydata(vs, [], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(12)])
    burst = bpy.data.objects.new("burst", me)
    bpy.context.scene.collection.objects.link(burst)
    burst.data.materials.append(C.flat("bursty", RADIANT_GOLD, rough=0.3, coat=0.5))
    out.append(C._apply(burst, M["UpperTorso"]))
    core = kit.cyl("burstc", 0.17, 0.17, 0.06, at=(0, 0.56, 3.35), segs=24, axis="Y")
    core.data.materials.append(C.glow_mat("burstcore", RADIANT_YELLOW, 3.0))
    out.append(C._apply(core, M["UpperTorso"]))
    return out


def bulwark_gear(M):
    """Bulwark's silver Great Pauldrons, Arm Plates and the Hex Badge (electric yellow on silver)."""
    silver = C.flat("bsilver", BULWARK_SILVER, rough=0.22, metal=0.9, coat=0.3)
    out = []
    for sx, side in ((-1, "Left"), (1, "Right")):
        p = kit.box("pauldron", 1.5, 1.5, 0.7, at=(sx * 1.55, 0, 4.1))
        kit.bevel(p, 0.25, 3)
        kit.deform(p, lambda v, sx=sx: Vector((v.x, v.y, v.z + 0.18 * (1 - min(1, abs(v.x - sx * 1.55) / 0.75)))))
        p.data.materials.append(silver)
        out.append(C._apply(p, M[side + "UpperArm"]))
        pl = kit.box("armplate", 1.12, 1.12, 0.5, at=(sx * 1.5, 0, 3.4))
        kit.bevel(pl, 0.08, 2)
        pl.data.materials.append(silver)
        out.append(C._apply(pl, M[side + "UpperArm"]))
    hexb = kit.cyl("hex", 0.55, 0.55, 0.08, at=(0, 0.54, 3.35), segs=6, axis="Y")
    hexb.rotation_euler = (0, math.radians(30), 0)
    hexb.data.materials.append(silver)
    out.append(C._apply(hexb, M["UpperTorso"]))
    core = kit.cyl("hexc", 0.3, 0.3, 0.1, at=(0, 0.58, 3.35), segs=6, axis="Y")
    core.data.materials.append(C.glow_mat("hexcore", BULWARK_YELLOW, 3.0))
    out.append(C._apply(core, M["UpperTorso"]))
    return out


def skylance_gear(M):
    """Skylance's violet High Ponytail, white Wind Scarf, Wingtips and the Ring Star."""
    out = []
    hair = C.flat("skyhair", (150, 80, 230), rough=0.45)
    tail = kit.tube_along("ponytail", [Vector((0, -0.5, 5.25)), Vector((0, -0.95, 5.2)), Vector((0.1, -1.4, 4.7)),
                                       Vector((0.25, -1.7, 4.1))], [0.26, 0.24, 0.18, 0.02], segs=10)
    tail.data.materials.append(hair)
    out.append(C._apply(tail, M["Head"]))
    scarf = kit.torus("scarf", 0.62, 0.16, at=(0, 0, 4.05), segs=24, csegs=6)
    scarf.data.materials.append(C.flat("scarf", SKY_WHITE, rough=0.6))
    out.append(C._apply(scarf, M["UpperTorso"]))
    end = kit.tube_along("scarfend", [Vector((0.3, -0.5, 4.0)), Vector((0.6, -1.4, 4.1)), Vector((1.0, -2.4, 4.4))],
                         [0.22, 0.2, 0.1], segs=6)
    end.data.materials.append(C.flat("scarf", SKY_WHITE, rough=0.6))
    out.append(C._apply(end, M["UpperTorso"]))
    for sx, side in ((-1, "Left"), (1, "Right")):
        w = kit.box("wingtip", 0.9, 0.2, 0.5, at=(sx * 1.9, -0.1, 4.1))
        w.rotation_euler = (0, math.radians(sx * -30), 0)
        kit.apply_all(w)
        w.data.materials.append(C.flat("wingtip", SKY_WHITE, rough=0.3, metal=0.4))
        out.append(C._apply(w, M[side + "UpperArm"]))
    ring = kit.torus("ringstar", 0.4, 0.07, at=(0, 0.56, 3.35), segs=32, csegs=6, axis="Y")
    ring.data.materials.append(C.glow_mat("ringstar", SKY_CYAN, 3.0))
    out.append(C._apply(ring, M["UpperTorso"]))
    star = C.emblem_star(SKY_WHITE, SKY_AZURE, size=0.26)
    for ob in star:
        out.append(C._apply(ob, M["UpperTorso"]))
    return out


def spear(M, part="RightHand", rgb=SKY_CYAN, length=7.0):
    """Skylance's light spear (a cylinder and a wedge, CombatFx), held along the forearm."""
    x = 1.5 if part.startswith("Right") else -1.5
    shaft = kit.cyl("spear", 0.1, 0.1, length, at=(x, 0, 2.15), segs=10, axis="Y")
    shaft.data.materials.append(C.flat("spear", (230, 236, 245), rough=0.2, metal=0.7))
    tip = kit.cyl("speartip", 0.32, 0.0, 1.2, at=(x, length / 2 + 0.6, 2.15), segs=4, axis="Y")
    tip.data.materials.append(C.glow_mat("speartip", rgb, 6.0))
    out = []
    for ob in (shaft, tip):
        ob.matrix_world = M[part] @ ob.matrix_world
        out.append(C.put(ob, C.collection("Fx")))
    return out


# ------------------------------------------------------------------------------------------------ world bosses
ANCHORS = {"RustjawPrime": [(-26, 92, 0), (26, 92, 0)], "LeviathanEngine": [(-14, 16, 12), (14, 16, 12)],
           "NullWarFrame": [(-16, 50, 2), (16, 50, 2)], "LumenMaw": None}  # art/blender/bosses.py ANCHORS
PHASE_GLOW = {"RustjawPrime": (200, 236, 255), "LumenMaw": (90, 240, 230), "LeviathanEngine": (80, 230, 255)}


def boss(name, at, yaw=0.0, scale=1.0, glow=None, phase=1, strength=6.0, generators=None):
    """A world boss from art/export/Bosses.fbx at its feet `at` (Blender), turned yaw degrees (0 faces +y). Plates
    that break off at phases 2 and 3 are left off for those phases. LumenMaw's generators stand round its pit:
    pass generators=[Blender points] to place them. Returns the boss's matrix."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(C.ASSETS, "export", "Bosses.fbx"))
    src = {}
    for ob in set(bpy.data.objects) - before:
        if ob.type == "MESH" and ob.name.startswith(name + "_"):
            src[ob.name.split(".")[0][len(name) + 1:]] = ob
        else:
            bpy.data.objects.remove(ob, do_unlink=True)
    fit = C.boss_fit(name)
    hull = C.boss_mat(name)
    mats = {"hull": hull, "shed2": hull, "shed3": hull, "objective": hull,
            "glow": C.glow_mat("bglow", glow or PHASE_GLOW.get(name, (255, 136, 40)), strength),
            "weak": C.glow_mat("bweak", (255, 196, 40), 6.0), "objectiveGlow": C.glow_mat("bobj", (255, 70, 60), 8.0)}
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Scale(scale, 4)
    coll = C.collection("Boss")
    for piece, ob in src.items():
        role, off = fit.get(piece, ("hull", (0, 0, 0)))
        if role == "shed2" and phase >= 2 or role == "shed3" and phase >= 3:
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        places = [Y @ Matrix.Translation(C.rb(*off))]
        if role in ("objective", "objectiveGlow"):
            if ANCHORS.get(name):
                places = [Y @ Matrix.Translation(C.rb(a[0] + off[0], a[1] + off[1], a[2] + off[2]))
                          for a in ANCHORS[name]]
            elif generators:
                places = [Matrix.Translation(Vector(g) + C.rb(*off)) for g in generators]
            else:
                places = []
        for P in places:
            cp = ob.copy()
            cp.data = ob.data.copy()
            coll.objects.link(cp)
            cp.matrix_world = P
            cp.data.materials.clear()
            cp.data.materials.append(mats[role])
        bpy.data.objects.remove(ob, do_unlink=True)
    return Y
