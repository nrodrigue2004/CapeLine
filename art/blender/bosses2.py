# bosses2.py: the second world boss set (bosses-3, nate 2026-11-20: "more bosses", Mix picked): the Storm Colossus,
# the Swarm Queen and the Quarry Titan. NAMES AND LOOKS ARE DRAFTS until nate OKs them (Config.Boss draft, Decisions.md).
# Built by bosses.py with --set 2 (the same helpers, roles, bake, fit table and previews as the first set):
#   python art/blender/bosses.py --set 2 [--preview] [--quick]
# writes art/export/Bosses2.fbx (meshes named "<Boss>_<Piece>"), art/export/bosses/<Boss>_*.png,
# src/config/BossArt2.luau (merged into Config.BossArt at boot, set = "Bosses2") and the previews
# art/preview/boss_<Boss>.png and art/preview/bosses2.png. Imported as ReplicatedStorage.Art.Bosses2.
# * StormColossus: a Crane Industries weather machine (navy and Crane yellow, white insulators): a ducted lift fan
#   under a coil drum, a radar-dome head with a lightning-rod crown (the dynamo weak point on top), Tesla-coil arms, a
#   glowing coil core in the chest (weak), three storm vanes on its shoulders and back (the objectives). It hovers.
# * SwarmQueen: the Crane drone swarm's hive core (graphite and Crane yellow, amber lights): a caged core (weak) in
#   two armour shells that swing open when its formations break, a crown of antennae, two orbit rings, a stinger
#   emitter; the formation relay nodes (the objectives) and the one small drone mesh the client swarms by the
#   hundred (Fx.SwarmFx, Shared.SwarmShapes).
# * QuarryTitan: a cartoon magma golem from the Old Quarry (faceted basalt boulders, lava cracks that glow, mossy
#   tufts, obsidian crystals): boulder fists, a magma heart in its chest and molten knees (weak), magma vents round
#   its pit (the objectives, they feed it). A creature: it bursts into light and rock chunks, never blood.
# Same budget as the first set: 16,000 triangles a boss, 10,000 a mesh. Original designs only.
import math

from mathutils import Vector

K = None  # bosses.py's helpers (its module), bound by bosses.py once they exist: bind(sys.modules[__name__])


def bind(module):
    global K
    K = module


def _h():
    return K


def tag(o, seg):
    """Put a sub-shape on a rig segment by name (when its centre alone cannot tell, like rings round the core)."""
    if isinstance(o, (list, tuple)):
        for x in o:
            tag(x, seg)
    else:
        o["seg"] = seg
    return o


# ================================================================ StormColossus: the Crane weather machine (72 studs)
NAVY = (36, 60, 116)
CRANE_Y = (250, 196, 40)
STEEL = (178, 188, 204)
INSUL = (226, 240, 250)
ARC = (150, 230, 255)


def storm():
    k = _h()
    b = k.Boss("StormColossus", {
        "Paint": (NAVY, 0.42, 0.15),      # Crane navy
        "Paint2": (CRANE_Y, 0.45, 0.05),  # Crane yellow
        "Metal": (STEEL, 0.3, 1.0),       # steel struts, the duct, the rods
        "Dark": ((26, 28, 38), 0.6, 0.1),
        "Hazard": (CRANE_Y, 0.5, 0.0),    # hazard stripes
        "Accent": (INSUL, 0.3, 0.0),      # white ceramic insulators
    }, [ARC, (255, 226, 90), (255, 70, 110)], ("Vane", "VaneGlow"))
    b.look = "the Storm Colossus: a Crane Industries weather machine that hovers on a lift fan"
    b.theme = ARC
    b.debris = CRANE_Y
    H = "Hull"
    # the lift fan (its own segment: it spins): a steel duct ring, four struts up to the drum, five fat blades, a hub
    b.add(H, k.ring("Metal", 17, 2.4, (0, 0, 5), "Z", 28, 6))
    b.add(H, k.ring("Paint2", 17, 1.0, (0, 0, 7.6), "Z", 28, 4))
    for a in range(5):
        bl = k.bx("Dark", 1.5, 15.2, -2.4, 2.4, 4.3, 5.7, 0.3)
        k.turn(bl, 12, "X", (0, 0, 5))
        k.turn(bl, a * 72, "Z")
        b.add(H, bl)
    b.add(H, k.cy("Metal", 3.2, 3.2, 4, (0, 0, 5), "Z", 12))
    b.add("Glow", k.ring("Lamp", 17, 0.6, (0, 0, 2.4), "Z", 28, 4))
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        b.add(H, k.beam("Metal", (math.cos(r) * 17, math.sin(r) * 17, 7), (math.cos(r) * 11, math.sin(r) * 11, 13), 2.2,
                         2.2, 0.4, 1))
    # the coil drum: a navy body with Crane yellow bands and white insulator discs stacked round its waist
    b.add(H, k.loft("Paint", [(10, 10, 10, 0, 0), (14, 17, 17, 0, 0), (24, 20, 19.5, 0, 0), (36, 20.5, 20, 0, 0),
                             (44, 18, 17.5, 0, 0), (49, 12, 12, 0, 0)], segs=28, power=2.2))
    for z, r in ((15.5, 17.8), (43, 18.6)):
        b.add(H, k.ring("Paint2", r, 1.3, (0, 0, z), "Z", 28, 5))
    for z in (27, 30.5, 34):
        b.add(H, k.ring("Accent", 21.2, 1.25, (0, 0, z), "Z", 28, 5))
    b.add(H, k.hazard(-9, 9, 17.5, 21, 19.6, 5, facing=1))
    # the coil core: a ring window in the chest with the weak point behind steel prongs
    b.add(H, k.cy("Dark", 7.4, 7.4, 3, (0, 19.4, 30), "Y", 20))
    b.add(H, k.ring("Metal", 7.6, 1.2, (0, 20.8, 30), "Y", 20, 5))
    for a in range(4):
        r = math.radians(45 + a * 90)
        b.add(H, k.beam("Metal", (math.cos(r) * 7.4, 21, 30 + math.sin(r) * 7.4),
                         (math.cos(r) * 4.6, 23.2, 30 + math.sin(r) * 4.6), 1, 1, 0.2, 1))
    b.lamp("core", (0, 22, 30), 4.6)
    # arc lights round the drum (phase glow) and the back's battery pack
    for a in range(6):
        r = math.radians(a * 60 + 30)
        b.add("Glow", k.ball("Lamp", 1.3, (math.cos(r) * 21.6, math.sin(r) * 21.6, 38.4), segs=8, rings=6))
    b.add(H, k.bx("Paint2", -9, 9, -24, -18, 20, 40, 1.2, 2))
    for x in (-5, 0, 5):
        b.add(H, k.cy("Accent", 1.6, 1.6, 14, (x, -24.4, 30), "Z", 8))
        b.add("Glow", k.cy("Lamp", 1.0, 1.0, 1.0, (x, -24.4, 37.6), "Z", 8))
    # Plates2: yellow armour panels on the drum's flanks (off at 66%); Plates3: the shoulder pauldrons and brow (33%)
    for s in (-1, 1):
        for z0 in (17, 33):
            pl = k.loft_y("Paint2", [(-7, 1.4, 6.0, 0, 0), (7, 1.4, 6.0, 0, 0)], segs=12, power=3.2)
            k.move(pl, (s * 21.4, 0, z0 + 4))
            b.add("Plates2", pl)
            b.add("Plates2", k.rivets("Metal", [(s * 22.8, -5, z0 + 1), (s * 22.8, 5, z0 + 1), (s * 22.8, -5, z0 + 7),
                                                 (s * 22.8, 5, z0 + 7)], 0.5, "X", 0.4))
    # the head: a white radar dome with a navy cowl, a glowing visor band, ear dishes and a lightning-rod crown
    b.add(H, k.loft("Paint", [(47, 11, 11, 0, 0), (51, 13, 12.5, 0, 0.5), (55, 12.4, 12, 0, 0.5)], segs=24, power=2.4))
    b.add(H, k.ball("Accent", 11.6, (0, 0, 56), (1, 1, 0.92), 22, 12))
    visor = k.bx("Lamp", -8.4, 8.4, 10.6, 12.4, 55, 57.6, 0)
    k.shear(visor, lambda v: Vector((v.x, v.y - (v.x / 8.4) ** 2 * 3.8, v.z)))
    b.add("Glow", visor)
    for s in (-1, 1):
        dish = k.cy("Metal", 4.6, 1.2, 2.2, (s * 12.2, 0, 57), "X", 16)
        b.add(H, dish)
        b.add(H, k.spike("Metal", (s * 13.4, 0, 57), (s * 17, 0, 58), 0.5, 5))
        brow = k.bx("Paint2", min(s * 1, s * 10.5), max(s * 1, s * 10.5), 6, 11, 58.8, 61.2, 0.6, 2)
        k.shear(brow, lambda v, s=s: Vector((v.x, v.y, v.z - abs(v.x) * 0.18 + 1.2)))
        b.add("Plates3", brow)
    for a in range(3):
        r = math.radians(90 + a * 120)
        base = (math.cos(r) * 5, math.sin(r) * 5, 64)
        b.add(H, k.spike("Metal", base, (math.cos(r) * 2.4, math.sin(r) * 2.4, 72), 1.1, 6))
    b.add(H, k.cy("Metal", 1.0, 1.0, 8, (0, 0, 66), "Z", 8))
    b.lamp("dynamo", (0, 0, 71), 3.4)
    # the arms: steel shoulder balls, navy upper arms, ribbed forearms ending in Tesla-coil hands (glowing tips)
    for s in (-1, 1):
        sh = Vector((s * 23, 0, 42))
        el = Vector((s * 32, 4, 30))
        hand = Vector((s * 34, 10, 15))
        b.add(H, k.ball("Metal", 5.4, tuple(sh)))
        b.add(H, k.beam("Paint", tuple(sh), tuple(el), 6.4, 6.4, 1.0, 2, 0.9))
        b.add(H, k.ball("Dark", 3.8, tuple(el)))
        b.add(H, k.beam("Paint2", tuple(el), tuple(hand), 7.2, 7.2, 1.0, 2, 1.1))
        d = (hand - el).normalized()
        for j in range(3):
            c = hand + d * (2 + j * 2.6)
            b.add(H, k.ring("Accent", 3.4 - j * 0.6, 0.9, tuple(c), "Z", 14, 4))
        b.add("Glow", k.ball("Lamp", 2.6, tuple(hand + d * 9.4), segs=12, rings=8))
        pad = k.loft("Paint2", [(0, 6.6, 6.6, 0, 0), (2.4, 7.2, 7.2, 0, 0), (4.4, 5, 5, 0, 0)], segs=16, power=2.6)
        k.turn(pad, s * 48, "Y")
        k.move(pad, (s * 24, 0, 44.5))
        b.add("Plates3", pad)
    # the storm vane (one; the game sets one at each Config.Boss objective; its anchor at the origin): a steel mast on
    # a yellow collar, an arrow fin and a red lamp ball on top
    v = [k.cy("Paint2", 2.6, 2.2, 2.4, (0, 0, 1.2), "Z", 10), k.cy("Metal", 0.8, 0.6, 10, (0, 0, 6.6), "Z", 8),
         k.bx("Paint", -0.4, 0.4, -4.4, 3.2, 7.2, 9.4, 0.15, 1, taper=(1, 0.5)), k.ring("Accent", 1.6, 0.5, (0, 0, 4), "Z", 10, 4)]
    b.add("Vane", v)
    b.add("VaneGlow", k.ball("Lamp", 1.8, (0, 0, 12.4)))
    b.objective_lamp = Vector((0, 0, 12.4))
    # its look in motion: sparks arcing off the coils and the crown (Fx.WorldFx "storm": arcs and storm clouds)
    b.fx = {"kind": "storm", "every": 0.18, "at": [(0, 71, 0), (-35, 6, -17), (35, 6, -17), (0, 30, -22)], "reach": 26}
    # the part-built look until the meshes are imported (PLACEHOLDER ART)
    P = k.P
    b.parts = [
        P("body", "Cylinder", (36, 40, 40), (0, 30, 0), rot=(0, 0, 90), color=NAVY),
        P("body", "Cylinder", (4, 36, 36), (0, 5, 0), rot=(0, 0, 90), color=STEEL, mat="Metal"),
        P("body", "Ball", (23, 23, 23), (0, 56, 0), color=INSUL),
        P("glow", "Block", (16, 2.4, 1), (0, 56, -11)),
        P("weak", "Ball", (8, 8, 8), (0, 30, -21)),
        P("weak", "Ball", (6, 6, 6), (0, 71, 0)),
    ]
    for s in (-1, 1):
        b.parts.append(P("body", "Block", (7, 7, 22), (s * 30, 32, -3), rot=(30, 0, 0), color=CRANE_Y))
        b.parts.append(P("glow", "Ball", (5, 5, 5), (s * 35, 6, -17)))
    b.objective_parts = [
        P("objective", "Cylinder", (10, 1.6, 1.6), (0, 5, 0), rot=(0, 0, 90), color=STEEL, mat="Metal"),
        P("objectiveGlow", "Ball", (3.6, 3.6, 3.6), (0, 12.4, 0)),
    ]
    return b


# ================================================================ SwarmQueen: the Crane drone hive core (60 studs)
GRAPH = (54, 58, 72)
AMBER = (255, 170, 60)
DRONE_O = (255, 128, 40)


def swarm():
    k = _h()
    b = k.Boss("SwarmQueen", {
        "Paint": (GRAPH, 0.4, 0.3),        # graphite drone plastic
        "Paint2": (CRANE_Y, 0.45, 0.05),   # Crane yellow trims
        "Metal": ((190, 196, 212), 0.3, 1.0),
        "Dark": ((22, 22, 30), 0.55, 0.1),
        "Hazard": (CRANE_Y, 0.5, 0.0),
        "Accent": (DRONE_O, 0.4, 0.0),     # drone-orange lenses and stripes
    }, [AMBER, (255, 110, 40), (255, 50, 70)], ("Node", "NodeGlow"))
    b.look = "the Swarm Queen: the hive core of a swarm of Crane drones"
    b.theme = AMBER
    b.debris = DRONE_O
    H = "Hull"
    # the cage round the core: hex caps top and bottom, six steel struts, amber seam lights
    b.add(H, k.cy("Paint", 11, 8, 4, (0, 0, 17), "Z", 6))
    b.add(H, k.cy("Paint", 8, 11, 4, (0, 0, 43), "Z", 6))
    for a in range(6):
        r = math.radians(a * 60 + 30)
        b.add(H, k.beam("Metal", (math.cos(r) * 10.4, math.sin(r) * 10.4, 18), (math.cos(r) * 10.4, math.sin(r) * 10.4, 42),
                         1.6, 1.6, 0.3, 1))
        b.add("Glow", k.cy("Lamp", 0.6, 0.6, 20, (math.cos(r) * 11.4, math.sin(r) * 11.4, 30), "Z", 6))
    b.lamp("core", (0, 0, 30), 6.4)
    # the stinger emitter underneath and the yellow collar
    b.add(H, k.cy("Dark", 6, 1.2, 10, (0, 0, 10), "Z", 12))
    b.add(H, k.ring("Paint2", 7.4, 1.0, (0, 0, 14.6), "Z", 18, 4))
    b.add("Glow", k.ball("Lamp", 1.8, (0, 0, 4.6), segs=10, rings=6))
    # the two armour shells (their own segments: they swing open when the formations break): faceted half domes with
    # hex trims; Plates2 hex panels on them (66%), Plates3 their spiked rims (33%)
    for s in (-1, 1):
        seg = "Shell" + K.side(s)
        sh = k.ball("Paint", 16, (0, 0, 30), (1, 1.05, 1.12), 6, 5)
        k.kit.cut(sh, (-1, 0, 0) if s > 0 else (1, 0, 0), keep_positive=False)
        k.move(sh, (s * 2.2, 0, 0))
        b.add(H, tag(sh, seg))
        rim = k.ring("Paint2", 15.6, 1.0, (s * 2.4, 0, 30), "X", 6, 4)
        b.add(H, tag(rim, seg))
        for z, y in ((24, 8), (36, -8), (30, 0)):
            hx = k.cy("Paint2", 4.2, 4.2, 1.2, (s * 15.8, y, z), "X", 6)
            b.add("Plates2", tag(hx, seg))
            b.add("Glow", tag(k.cy("Lamp", 2.0, 2.0, 0.6, (s * 16.6, y, z), "X", 6), seg))
        for z in (18, 30, 42):
            b.add("Plates3", tag(k.spike("Metal", (s * 14.4, 0, z), (s * 20.4, 0, z + 1.5), 1.4, 5), seg))
    # the crown: a yellow hex plate and six antennae with glowing tips
    b.add(H, k.cy("Paint2", 9.4, 7, 2.4, (0, 0, 46.2), "Z", 6))
    for a in range(6):
        r = math.radians(a * 60)
        base = (math.cos(r) * 6.4, math.sin(r) * 6.4, 47)
        tip = (math.cos(r) * 10.4, math.sin(r) * 10.4, 57 + (a % 2) * 2)
        b.add(H, k.tube("Metal", [base, tip], [0.7, 0.35], 6))
        b.add("Glow", k.ball("Lamp", 1.0, tip, segs=8, rings=5))
    b.add(H, k.spike("Paint2", (0, 0, 47.4), (0, 0, 55), 2.4, 6))
    # the orbit rings (segments that spin) with amber lamps
    ra = k.ring("Metal", 22, 0.9, (0, 0, 30), "Z", 36, 5)
    b.add(H, tag(ra, "RingA"))
    for a in range(6):
        r = math.radians(a * 60)
        b.add("Glow", tag(k.ball("Lamp", 1.2, (math.cos(r) * 22, math.sin(r) * 22, 30), segs=8, rings=5), "RingA"))
    rb_ = k.ring("Metal", 25.5, 0.8, (0, 0, 0), "Z", 36, 5)
    k.turn(rb_, 62, "X")
    k.move(rb_, (0, 0, 30))
    b.add(H, tag(rb_, "RingB"))
    for a in range(4):
        r = math.radians(a * 90 + 45)
        p = Vector((math.cos(r) * 25.5, math.sin(r) * 25.5, 0))
        p.rotate(__import__("mathutils").Matrix.Rotation(math.radians(62), 3, "X"))
        b.add("Glow", tag(k.ball("Lamp", 1.1, (p.x, p.y, p.z + 30), segs=8, rings=5), "RingB"))
    # the formation relay node (one; the game sets one at each Config.Boss objective; anchor at the origin): a hex puck
    # with three fins and a red lamp in its middle
    n = [k.cy("Paint", 3.6, 3.6, 2.4, (0, 0, 0), "Z", 6), k.ring("Paint2", 3.8, 0.5, (0, 0, 0), "Z", 6, 4)]
    for a in range(3):
        f = k.bx("Metal", 3.2, 6.6, -0.35, 0.35, -0.9, 0.9, 0.1)
        k.turn(f, a * 120 + 30, "Z")
        n.append(f)
    b.add("Node", n)
    b.add("NodeGlow", k.ball("Lamp", 1.8, (0, 0, 1.4)))
    b.objective_lamp = Vector((0, 0, 1.4))
    # the drone (one mesh; Fx.SwarmFx draws hundreds of it): a graphite puck, four yellow rotor rings, an orange lens
    d = [k.cy("Paint", 1.1, 0.9, 0.7, (0, 0, 0), "Z", 8), k.ball("Accent", 0.45, (0, 0.85, 0.05), segs=8, rings=5)]
    for a in range(4):
        r = math.radians(45 + a * 90)
        d.append(k.ring("Paint2", 0.55, 0.12, (math.cos(r) * 1.35, math.sin(r) * 1.35, 0.2), "Z", 8, 3))
        d.append(k.beam("Metal", (0, 0, 0.1), (math.cos(r) * 1.35, math.sin(r) * 1.35, 0.2), 0.22, 0.22, 0, 1))
    b.add("Drone", d)
    b.roles["Drone"] = "drone"
    b.fx = {"kind": "swarm", "every": 0.2, "at": [(0, 30, 0)], "reach": 30}
    P = k.P
    b.parts = [
        P("body", "Ball", (30, 30, 30), (0, 30, 0), color=GRAPH),
        P("body", "Cylinder", (2, 50, 50), (0, 30, 0), rot=(0, 0, 90), color=(190, 196, 212), mat="Metal"),
        P("body", "Block", (18, 3, 18), (0, 46, 0), color=CRANE_Y),
        P("weak", "Ball", (12, 12, 12), (0, 30, -14)),
        P("glow", "Ball", (4, 4, 4), (0, 4.6, 0)),
    ]
    b.objective_parts = [
        P("objective", "Cylinder", (2.4, 7.2, 7.2), (0, 0, 0), rot=(0, 0, 90), color=GRAPH),
        P("objectiveGlow", "Ball", (3.6, 3.6, 3.6), (0, 1.4, 0)),
    ]
    return b


# ================================================================ QuarryTitan: the cartoon magma golem (92 studs)
BASALT = (98, 80, 74)
STONE2 = (156, 126, 100)
OBSID = (52, 40, 58)
LAVA = (255, 130, 40)
MOSS = (116, 156, 72)


def titan():
    k = _h()
    b = k.Boss("QuarryTitan", {
        "Paint": (BASALT, 0.85, 0.0),      # basalt boulders
        "Paint2": (STONE2, 0.8, 0.0),      # warm quarry stone
        "Metal": (OBSID, 0.2, 0.0),        # glossy obsidian crystals
        "Dark": ((34, 24, 24), 0.9, 0.0),  # scorched rock
        "Hazard": ((255, 150, 60), 0.6, 0.0),  # cooling lava crust
        "Accent": (MOSS, 0.85, 0.0),       # moss tufts
    }, [LAVA, (255, 96, 30), (255, 56, 40)], ("Vent", "VentPool"))
    b.look = "the Quarry Titan: a cartoon magma golem of quarry boulders"
    b.theme = LAVA
    b.debris = STONE2
    H = "Hull"

    def rock(region, r, at, scale=(1, 1, 1), seed=0):
        """A faceted cartoon boulder (a low ball nudged by a seed so no two match)."""
        o = k.ball(region, r, at, scale, 7, 5)
        for i, vtx in enumerate(o.data.vertices):
            j = (i * 37 + seed * 11) % 9
            vtx.co = Vector(at) + (vtx.co - Vector(at)) * (0.9 + j * 0.025)
        return o

    for s in (-1, 1):
        x = s * 14
        # feet and shins: flat boulder feet, stubby shins, molten knee (weak) under a crust ring
        b.add(H, rock("Paint", 9, (x, 3, 4), (1.1, 1.4, 0.55), 1 + s))
        b.add(H, rock("Paint2", 7.4, (x, 0, 16), (1, 1, 1.3), 2 + s))
        b.add(H, rock("Paint", 7.6, (x, 0, 36), (1.05, 1, 1.25), 3 + s))
        b.add(H, k.ring("Hazard", 5.2, 1.1, (x, 6.2, 26), "Y", 10, 4))
        b.lamp("knee" + ("L" if s < 0 else "R"), (x, 8.0, 26), 3.4)
        b.add("Glow", k.tube("Lamp", [(x - s * 3, 6.4, 13), (x + s * 1, 7.2, 18), (x - s * 1.6, 7.6, 22)], [0.6, 0.8, 0.4], 5))
        b.add("Glow", k.tube("Lamp", [(x + s * 2, 7.2, 31), (x - s * 2, 7.6, 37), (x + s * 1, 7.0, 42)], [0.5, 0.8, 0.4], 5))
        b.add("Plates2", rock("Paint2", 4.6, (x + s * 4, 4, 38), (0.6, 1.0, 1.2), 4 + s))
        b.add(H, rock("Accent", 2.4, (x - s * 2, 1, 9.4), (1.6, 1.4, 0.5), 9 + s))  # a moss tuft on the foot
    # the hips and the big boulder body (a belly slab, the chest boulder), lava cracks across it (phase glow)
    b.add(H, rock("Dark", 15, (0, 0, 44), (1.3, 0.9, 0.6), 5))
    b.add(H, rock("Paint", 24, (0, -2, 58), (1.15, 0.95, 0.95), 6))
    b.add(H, rock("Paint2", 14, (0, 8, 50), (1.2, 0.7, 0.8), 7))
    for pts in (((-14, 20, 66), (-6, 22, 60), (-9, 21.6, 52), (-3, 20.6, 46)), ((12, 20.2, 68), (5, 22.2, 62), (8, 21.4, 55)),
                ((-20, 10, 70), (-24, 6, 62), (-22, 4, 54)), ((20, 10, 66), (24, 4, 58))):
        b.add("Glow", k.tube("Lamp", [p for p in pts], [0.9] + [1.1] * (len(pts) - 2) + [0.5], 6))
    # the magma heart (weak): a glowing ball in a crusted crater in the chest
    b.add(H, k.ring("Hazard", 7.4, 1.8, (0, 19, 54), "Y", 12, 5))
    b.add(H, k.ring("Dark", 9.4, 1.4, (0, 18.2, 54), "Y", 12, 4))
    b.lamp("core", (0, 20.4, 54), 5.2)
    # Plates2: rock slabs on the belly (off at 66%); Plates3: obsidian crystal clusters on the shoulders and back (33%)
    for s in (-1, 1):
        b.add("Plates2", rock("Paint2", 6, (s * 9, 16, 44), (1.1, 0.5, 0.8), 10 + s))
        for j, (dx, dz, ln) in enumerate(((0, 0, 11), (4, -2, 8), (-3, -1, 7))):
            base = (s * (26 + dx), -6 + j * 3, 76 + dz)
            b.add("Plates3", k.spike("Metal", base, (base[0] + s * 4, base[1] - 2, base[2] + ln), 2.2, 5))
    for j in range(3):
        base = (-6 + j * 6, -20, 64 + j * 3)
        b.add("Plates3", k.spike("Metal", base, (base[0], -27, base[2] + 8), 2.4, 5))
    b.add(H, rock("Accent", 4, (8, -8, 79), (1.6, 1.4, 0.5), 12))  # moss on the shoulders
    b.add(H, rock("Accent", 3.4, (-10, -6, 79.5), (1.6, 1.4, 0.5), 13))
    # the head: a small boulder sunk between the shoulders, a heavy brow, two glowing eyes, a lava grin (all cartoon)
    b.add(H, rock("Paint2", 10, (0, 2, 82), (1.1, 1, 0.95), 14))
    brow = k.bx("Dark", -9, 9, 6, 12, 85.2, 88.6, 1.0, 2)
    k.shear(brow, lambda v: Vector((v.x, v.y, v.z - abs(v.x) * 0.14 + 0.8)))
    b.add(H, brow)
    for s in (-1, 1):
        b.add("Glow", k.ball("Lamp", 2.2, (s * 4.2, 10.4, 83.4), (1.2, 0.6, 0.8), 10, 6))
    grin = k.tube("Lamp", [(-5, 10.2, 78.6), (0, 11.2, 77.4), (5, 10.2, 78.6)], [0.6, 0.9, 0.6], 6)
    b.add("Glow", grin)
    # the arms: boulder shoulders and upper arms, rock forearms and giant boulder fists with lava knuckles
    for s in (-1, 1):
        sh = (s * 27, -2, 70)
        el = (s * 34, 2, 50)
        fist = (s * 35, 6, 30)
        b.add(H, rock("Paint", 10, sh, (1, 1, 1), 15 + s))
        b.add(H, rock("Paint2", 7.4, ((sh[0] + el[0]) / 2, 0, 60), (0.95, 0.95, 1.4), 17 + s))
        b.add(H, rock("Paint", 7.6, ((el[0] + fist[0]) / 2, 4, 40), (0.95, 0.95, 1.3), 19 + s))
        b.add(H, rock("Paint", 10.5, fist, (1.05, 1.05, 1), 21 + s))
        b.add("Glow", k.tube("Lamp", [(fist[0] - 6, fist[1] + 9.4, fist[2] + 2), (fist[0], fist[1] + 10.6, fist[2]),
                                      (fist[0] + 6, fist[1] + 9.4, fist[2] + 2)], [0.6, 0.9, 0.6], 5))
        b.add("Glow", k.tube("Lamp", [(s * 33, 8.6, 60), (s * 36, 7.6, 54), (s * 34, 9, 46)], [0.5, 0.8, 0.4], 5))
    # the magma vent (one; the game stands one at each point round the pit; its foot at the origin): a rock cone with a
    # bubbling lava pool on top (its lamp, inside its hit sphere 8 studs up)
    v = [k.cy("Paint", 8, 4.2, 7, (0, 0, 3.5), "Z", 7), rock("Paint2", 3, (5, 2, 1.5), (1.4, 1.2, 0.6), 30),
         rock("Dark", 2.6, (-5, -3, 1.4), (1.4, 1.2, 0.6), 31), k.ring("Hazard", 4.2, 0.9, (0, 0, 7), "Z", 7, 4)]
    b.add("Vent", v)
    b.add("VentPool", k.ball("Lamp", 3.4, (0, 0, 8), (1, 1, 0.55), 12, 6))
    b.objective_lamp = Vector((0, 0, 8))
    b.fx = {"kind": "magma", "every": 0.14, "at": [(0, 54, -20), (-35, 30, -6), (35, 30, -6), (0, 78, -11)], "reach": 20}
    P = k.P
    b.parts = [
        P("body", "Ball", (48, 44, 44), (0, 58, 2), color=BASALT, mat="Slate"),
        P("body", "Ball", (20, 18, 18), (0, 82, -2), color=STONE2, mat="Slate"),
        P("weak", "Ball", (10, 10, 10), (0, 54, -20)),
        P("glow", "Block", (12, 2, 1), (0, 83.4, -10.6)),
    ]
    for s in (-1, 1):
        b.parts.append(P("body", "Block", (14, 40, 14), (s * 14, 20, 0), color=BASALT, mat="Slate"))
        b.parts.append(P("body", "Ball", (20, 20, 20), (s * 35, 30, -6), color=BASALT, mat="Slate"))
        b.parts.append(P("weak", "Ball", (6, 6, 6), (s * 14, 26, -8)))
    b.objective_parts = [
        P("objective", "Block", (12, 7, 12), (0, 3.5, 0), color=BASALT, mat="Slate"),
        P("objectiveGlow", "Ball", (6, 6, 6), (0, 8, 0)),
    ]
    return b


# ================================================================ the rigs (segments the game poses: Shared.BossPose)
def storm_seg(name, c):
    x, y, z = c
    ax = abs(x)
    if z < 9.6 and ax < 19.5:
        return "Fan"
    if ax >= 23.5 and z < 46:
        return ("Arm" if z >= 31 else "Fore") + K.side(x)
    if z >= 46.5 and ax < 18:
        return "Head"
    return "Body"


STORM_RIG = [("Body", "Root", (0, 0, 30)), ("Fan", "Body", (0, 0, 5)), ("Head", "Body", (0, 0, 47)),
             ("ArmL", "Body", (-23, 0, 42)), ("ForeL", "ArmL", (-32, 4, 30)), ("ArmR", "Body", (23, 0, 42)),
             ("ForeR", "ArmR", (32, 4, 30))]


def swarm_seg(name, c):
    # the shells and rings are tagged where they are made; the rest by height
    return "Crown" if c[2] >= 45.5 else "Body"


SWARM_RIG = [("Body", "Root", (0, 0, 30)), ("ShellL", "Body", (-3, 0, 45)), ("ShellR", "Body", (3, 0, 45)),
             ("Crown", "Body", (0, 0, 46)), ("RingA", "Body", (0, 0, 30)), ("RingB", "Body", (0, 0, 30))]


def titan_seg(name, c):
    x, y, z = c
    ax = abs(x)
    if ax >= 25.5 and z < 78:
        return ("Arm" if z >= 52 else "Fore") + K.side(x)
    if z < 42.5 and 4 < ax < 24:
        return ("Thigh" if z >= 27 else "Shin") + K.side(x)
    if z >= 76.5 and ax < 14 and y > -4:
        return "Head"
    return "Body"


TITAN_RIG = [("Body", "Root", (0, 0, 44)), ("ThighL", "Root", (-14, 0, 42)), ("ShinL", "ThighL", (-14, 0, 27)),
             ("ThighR", "Root", (14, 0, 42)), ("ShinR", "ThighR", (14, 0, 27)), ("Head", "Body", (0, 0, 76)),
             ("ArmL", "Body", (-27, -2, 70)), ("ForeL", "ArmL", (-34, 2, 50)), ("ArmR", "Body", (27, -2, 70)),
             ("ForeR", "ArmR", (34, 2, 50))]

BUILDERS = {"StormColossus": storm, "SwarmQueen": swarm, "QuarryTitan": titan}
RIGS = {"StormColossus": (storm_seg, STORM_RIG), "SwarmQueen": (swarm_seg, SWARM_RIG),
        "QuarryTitan": (titan_seg, TITAN_RIG)}
# where the objectives sit on the body (Config.Boss objectives `at`, Roblox x, up, z); None: round the arena
ANCHORS = {
    "StormColossus": [(-22, 52, 8), (22, 52, 8), (0, 46, 22)],
    "SwarmQueen": [(-34, 4, -12), (34, 4, -12), (0, 2, 34)],
    "QuarryTitan": None,
}
VIEW = {  # boss spacing, camera distance, camera height, look-at height
    "StormColossus": (60, 240, 60, 36),
    "SwarmQueen": (52, 210, 50, 30),
    "QuarryTitan": (66, 260, 66, 44),
}
LINEUP = {"StormColossus": -95, "SwarmQueen": 0, "QuarryTitan": 100}
