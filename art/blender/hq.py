# hq.py: the HQ art pass (2026-11-18): the HQ rooms' most visible pieces as Blender meshes, in the set pieces' style
# (art/blender/setpieces.py: flat colours, one colour region a mesh, chunky silhouettes, low poly for phones; the
# shared helpers are art/blender/studs.py). Until nate imports them HqClient draws every piece from plain parts
# (PLACEHOLDER ART); once ReplicatedStorage.Art.Hq holds a look's meshes, HqClient draws them over those parts and
# hides the parts, whose prompts, signs and SurfaceGuis keep working exactly as before (Shared.HqArtKit).
# Two sides that read differently: the Vigil's Safehouse pieces are rounded, white and sky blue with gold stars and
# cyan glows; the Dread Syndicate's Foundry pieces are angular black iron and red with gold spikes, rivets, a
# three-spiked crown for a mark and red glows. Original designs, no real logos.
# Looks:
# * the station consoles, one per side (foot at the pad's middle on the floor, front at -z, HqArtKit.FACING turns
#   them into the room): the holo war table (Command Table), Gizmo's workbench, the mannequin and mirror, the
#   training meter console, the trophy lectern, the Hall of Legends' book stand, the scanner's radar console and
#   the exit door; and the station pad under each (a round Vigil pad, a hexagonal Syndicate one)
# * the Trophy Wall's frame, its plaques (tinted: the side's colour when filled, its trim when empty) and three
#   trophies (a cup, a star and a medal)
# * WP9's wall: the WANTED board (a cork board in a wood frame with red pins; a riveted steel plate with gold bolts),
#   the head mounts (a wooden shield plaque with a gold rim; an iron plaque with spikes) and the gold name plates;
#   the poster's paper and every SurfaceGui stay the game's parts
# * the shapes that fill a part of any size (HqArtKit.SHAPES): the dummies' base, target and visor and the nemesis
#   pieces (skull, faceplate, jaw, horn, spike, visor, chest, shoulders, cape); and the training dummy's own body
#   (the 15 R15 parts, named as the rig's: padded sparring bot armour, NpcRig's `look` "Hq")
# * the statues' plinths, the 22 thank-you, collection and Hero Pass props and the reputation tiers' dressing
#   (the Safehouse's cork board, notes, Patch's desk, monitors, rack and stool, the relic case, cape, shield and
#   helmet, the spotlight and the thanks banner; the Foundry's vault, gold bars, big screen and crown, the hook
#   chain, the captive robot, cash crates, carpet and the truss spotlight)
# Output: art/export/Hq.fbx, src/config/HqArt.luau; with --preview, art/preview/hq.png (close shots of each set and
# both rooms where the game puts everything, from art/export/hq/layout.json, which `lune run art/hq/layout.luau`
# writes from the game's own data, beside today's parts; --only <shot> renders shots whose name has it alone to
# art/preview/hq_<shot>.png, --fast at low quality).
# Run: python art/blender/hq.py [--preview] [--only <shot>] [--fast]   (with the `bpy` module, Blender 5.0)
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

from studs import *  # noqa: E402,F401,F403  (the colours and shape helpers)
from studs import LOOKS, INFO  # noqa: E402

# ---------------------------------------------------------------- the sides' colours
VWHITE = (240, 244, 255)  # the Vigil's trim (HqArtKit.COLORS)
VBLUE = (70, 140, 255)  # the Vigil's main
VNAVY = (34, 52, 112)
VGLOW = (110, 226, 245)
SIRON = (56, 50, 64)  # the Syndicate's iron (a step lighter than its trim, so it reads in a dark room)
SBLACK = (36, 32, 42)
SRED = (210, 60, 60)  # the Syndicate's main
SGLOW = (255, 70, 84)
GREENGLOW = (90, 236, 140)
AMBER = (255, 170, 40)
MIRROR = (176, 222, 246)
CORK = (196, 146, 96)
PAPER = (250, 246, 230)
CANVAS = (232, 214, 170)
LEAF = (78, 176, 84)
POT = (206, 106, 64)
CASH = (96, 170, 84)

STYLE = {
    "V": dict(tag="V", body=VWHITE, main=VBLUE, dark=VNAVY, gold=GOLD, glow=VGLOW, mat="SmoothPlastic", metal="SmoothPlastic", r=0.22, segs=3),
    "S": dict(tag="S", body=SIRON, main=SRED, dark=SBLACK, gold=GOLD, glow=SGLOW, mat="Metal", metal="DiamondPlate", r=0.16, segs=1),
}


# ---------------------------------------------------------------- helpers
def RB(sx, sy, sz, x=0.0, y=0.0, z=0.0, r=0.2, segs=3):
    """A box with rounded (segs 3) or chamfered (segs 1) edges."""
    ob = kit.box("rb", sx, sz, sy, at=rb(x, y, z))
    if r:
        kit.bevel(ob, min(r, sx / 2.05, sy / 2.05, sz / 2.05), segs)
        kit.apply_all(ob)
    return ob


def SB(st, sx, sy, sz, x=0.0, y=0.0, z=0.0, r=None):
    """A box in the side's style: rounded for the Vigil, chamfered for the Syndicate."""
    return RB(sx, sy, sz, x, y, z, st["r"] if r is None else r, st["segs"])


def face(poly, z0, z1):
    """A polygon in the (x, up) plane pushed from z0 to z1 (emblems, plates facing -z)."""
    return rings_mesh([[(px, py, z0) for (px, py) in poly], [(px, py, z1) for (px, py) in poly]])


def at(ob, x=0.0, y=0.0, z=0.0):
    return shift(ob, rb(x, y, z))


def crown_poly(w, h):
    """The Dread Syndicate's mark: a three-spiked crown (base band, two side spikes, a taller middle one)."""
    hw = w / 2
    return [(-hw, 0), (hw, 0), (hw, h * 0.62), (hw * 0.55, h * 0.34), (hw * 0.3, h * 0.5), (0, h), (-hw * 0.3, h * 0.5),
            (-hw * 0.55, h * 0.34), (-hw, h * 0.62)]


def crown(w, h, d, x=0.0, y=0.0, z=0.0):
    """The crown mark standing on (x, y), facing -z, d deep."""
    return at(face(crown_poly(w, h), -d / 2, d / 2), x, y, z)


def emblem(st, size, x, y, z, d=0.14):
    """The side's mark facing -z, its middle at (x, y, z): the Vigil's star, the Syndicate's crown."""
    if st["tag"] == "V":
        return star(size * 0.55, size * 0.23, d, x, y, z)
    return crown(size, size * 0.8, d, x, y - size * 0.4, z)


def flat_star(r_out, r_in, depth, x, y, z):
    """A star lying flat (facing up)."""
    return star(r_out, r_in, depth, x, y, z, axis="up")


def lathe(profile, x=0.0, y=0.0, z=0.0, segs=16):
    """A turned shape from (radius, up) points, bottom to top, capped."""
    rings = []
    for (r, py) in profile:
        r = max(r, 0.001)
        rings.append([(x + r * math.cos(2 * math.pi * i / segs), y + py, z + r * math.sin(2 * math.pi * i / segs)) for i in range(segs)])
    return rings_mesh(rings)


def gear(r_out, r_in, teeth, d, x=0.0, y=0.0, z=0.0, axis="z"):
    """A cog facing -z (or up), d deep."""
    poly = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4)
        r = r_out if (i % 4) in (1, 2) else r_in
        poly.append((math.cos(a) * r, math.sin(a) * r))
    if axis == "z":
        ob = face(poly, -d / 2, d / 2)
    else:
        ob = rings_mesh([[(px, -d / 2, py) for (px, py) in poly], [(px, d / 2, py) for (px, py) in poly]])
    return at(ob, x, y, z)


def spike(r, h, x, y, z, segs=4, tilt=(0, 0)):
    """A cone standing on (x, y, z), pointing up (tilted tilt degrees about x and z)."""
    ob = C(r, h, 0, h / 2, 0, segs=segs, r2=0.001)
    if tilt[0]:
        turn(ob, "x", tilt[0])
    if tilt[1]:
        turn(ob, "z", tilt[1])
    return at(ob, x, y, z)


def rivets(points, r=0.12, d=0.08, segs=6):
    """Little round heads facing -z at (x, y, z) points."""
    return [C(r, d, px, py, pz, segs=segs, axis="z") for (px, py, pz) in points]


def disc_up(r, h, x=0.0, y=0.0, z=0.0, segs=16):
    return C(r, h, x, y, z, segs=segs)


def ring_up(r, w, h, x=0.0, y=0.0, z=0.0, segs=24):
    """A flat annulus lying on the floor (inner r - w to r), h tall, centred at height y."""
    outer = [(x + r * math.cos(2 * math.pi * i / segs), z + r * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
    inner = [(x + (r - w) * math.cos(2 * math.pi * i / segs), z + (r - w) * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
    bm = bmesh.new()
    vs = {}
    for k, (ring, yy) in enumerate(((outer, y - h / 2), (outer, y + h / 2), (inner, y + h / 2), (inner, y - h / 2))):
        vs[k] = [bm.verts.new(rb(px, yy, pz)) for (px, pz) in ring]
    for k in range(4):
        a, b = vs[k], vs[(k + 1) % 4]
        for i in range(segs):
            bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("ring")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("ring", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def frame_z(w, h, t, d, x=0.0, y=0.0, z=0.0, st=None, r=0.06):
    """A rectangular frame (outer w x h, rails t wide, d deep) facing -z round (x, y, z)."""
    mk = (lambda *a: SB(st, *a, r=r)) if st else (lambda *a: RB(*a, r=r, segs=2))
    return [mk(w, t, d, x, y + h / 2 - t / 2, z), mk(w, t, d, x, y - h / 2 + t / 2, z),
            mk(t, h - 2 * t, d, x - w / 2 + t / 2, y, z), mk(t, h - 2 * t, d, x + w / 2 - t / 2, y, z)]


def hero(x, y, z, yaw=0):
    """(Previews only) a blocky 5-stud hero for scale; returns the parts and their colours."""
    out = []
    for (s_, c, rgb) in (((2, 2, 1), (0, 3.0, 0), (60, 120, 220)), ((1.2, 1.2, 1.2), (0, 4.6, 0), SKIN),
                         ((0.95, 2, 1), (-0.5, 1.0, 0), (40, 50, 90)), ((0.95, 2, 1), (0.5, 1.0, 0), (40, 50, 90)),
                         ((1, 2, 1), (-1.5, 3.0, 0), SKIN), ((1, 2, 1), (1.5, 3.0, 0), SKIN)):
        o = kit.box("hero", s_[0], s_[2], s_[1], at=rb(*c))
        move(o, x, y, z, yaw)
        out.append((o, rgb))
    return out


# ================================================================ the station pads (foot: the pad's middle on the floor)
for tag in ("V", "S"):
    st = STYLE[tag]
    L = "HqPad" + tag
    if tag == "V":  # a round pad: a white rim, a glowing blue ring, a white middle with gold stars round it
        mesh(L, "HqPadVRim", [disc_up(5.0, 0.32, 0, 0.26, 0, segs=32)], VWHITE)
        mesh(L, "HqPadVGlow", [ring_up(4.55, 0.75, 0.12, 0, 0.47, 0, segs=32)], VBLUE, "Neon", 0.25)
        mid = [disc_up(3.75, 0.1, 0, 0.47, 0, segs=28)]
        mesh(L, "HqPadVMid", mid, (214, 226, 246))
        stars = []
        for i in range(8):
            a = math.pi / 8 + i * math.pi / 4
            stars.append(flat_star(0.34, 0.14, 0.06, math.cos(a) * 4.78, 0.45, math.sin(a) * 4.78))
        mesh(L, "HqPadVGold", stars, GOLD)
    else:  # a hexagonal iron pad: a red glowing hex ring, a dark plate middle, gold rivets at the corners
        mesh(L, "HqPadSRim", [C(5.4, 0.32, 0, 0.26, 0, segs=6)], SIRON, "DiamondPlate")
        mesh(L, "HqPadSGlow", [C(4.85, 0.12, 0, 0.45, 0, segs=6)], SRED, "Neon", 0.25)
        mid = [C(4.0, 0.12, 0, 0.5, 0, segs=6)]
        for i in range(6):  # chevrons pointing in, between the corners
            a = math.pi / 6 + i * math.pi / 3 + math.pi / 6
            ch = at(face([(-0.5, 0), (0, -0.45), (0.5, 0), (0.5, 0.22), (0, -0.2), (-0.5, 0.22)], -0.04, 0.04), 0, 0, 0)
            turn(ch, "x", -90)
            turn(ch, "up", -math.degrees(a) - 90)
            at(ch, math.cos(a) * 4.45, 0.5, math.sin(a) * 4.45)
            mid.append(ch)
        mesh(L, "HqPadSMid", mid, SBLACK, "Metal")
        bolts = [C(0.28, 0.14, math.cos(a) * 5.0, 0.48, math.sin(a) * 5.0, segs=6) for a in (i * math.pi / 3 for i in range(6))]
        mesh(L, "HqPadSGold", bolts, GOLD, "Metal")


# ================================================================ the station consoles (foot: the pad's middle, front -z)
def console_command(st):
    """The Command Table: the holo war table. The Vigil's is round on a fluted pedestal with a holo city over it;
    the Syndicate's is a hexagonal iron table on three claw legs with a red holo spire and gold corner spikes."""
    t, L = st["tag"], "HqCommand" + st["tag"]
    if t == "V":
        body = [lathe([(1.9, 0.55), (1.6, 0.8), (1.05, 1.1), (0.9, 2.5), (1.3, 2.9), (3.5, 3.0), (3.6, 3.25), (3.45, 3.4)], segs=24)]
        body += [B(0.3, 1.4, 0.3, math.cos(a) * 0.95, 1.8, math.sin(a) * 0.95) for a in (i * math.pi / 3 for i in range(6))]
        mesh(L, "HqCommandVBody", body, VWHITE)
        trim = [TOR(3.55, 0.16, 0, 3.12, 0, segs=28, csegs=6), C(1.95, 0.22, 0, 0.62, 0, segs=20)]
        mesh(L, "HqCommandVTrim", trim, VBLUE)
        gold = [C(1.25, 0.18, 0, 3.47, 0, segs=18), TOR(1.25, 0.08, 0, 3.56, 0, segs=18, csegs=4),
                star(0.42, 0.18, 0.1, 0, 1.75, -1.0)]
        for a in (i * math.pi / 2 + math.pi / 4 for i in range(4)):  # little gold studs round the rim
            gold.append(S(0.16, math.cos(a) * 3.55, 3.3, math.sin(a) * 3.55, segs=8, rings=5))
        mesh(L, "HqCommandVGold", gold, GOLD)
        holo = []
        for gx in range(-2, 3):  # the holo city: blocks over the emitter, taller in the middle
            for gz in range(-2, 3):
                d = math.hypot(gx, gz)
                if d > 2.3:
                    continue
                h = 0.4 + (2.4 - d) * 0.45 + ((gx * 7 + gz * 3) % 3) * 0.15
                holo.append(B(0.5, h, 0.5, gx * 0.62, 3.62 + h / 2, gz * 0.62))
        holo.append(TOR(2.2, 0.05, 0, 3.75, 0, segs=28, csegs=4))
        holo.append(TOR(2.4, 0.04, 0, 5.1, 0, segs=28, csegs=4))
        mesh(L, "HqCommandVHolo", holo, VGLOW, "Neon", 0.45)
    else:
        top = [C(3.7, 0.4, 0, 3.15, 0, segs=6), C(3.2, 0.3, 0, 2.8, 0, segs=6), C(1.0, 2.2, 0, 1.7, 0, segs=6)]
        for i in range(3):  # three claw legs splayed out
            a = math.pi / 2 + i * 2 * math.pi / 3
            leg = prism([(-0.4, 0.0), (0.5, 0.0), (0.3, 2.6), (-0.3, 2.6)], -0.25, 0.25)
            turn(leg, "up", 90)
            turn(leg, "z", 0)
            claw = B(0.5, 0.35, 1.3, 0, 0.18, 0.6)
            for p_ in (leg, claw):
                turn(p_, "up", -math.degrees(a) + 90)
                at(p_, math.cos(a) * 1.6, 0, math.sin(a) * 1.6)
            top += [leg, claw]
        mesh(L, "HqCommandSBody", top, SIRON, "Metal")
        mesh(L, "HqCommandSEdge", [C(3.8, 0.14, 0, 2.96, 0, segs=6)], SRED, "Neon")
        gold = [spike(0.32, 1.0, math.cos(a) * 3.55, 3.35, math.sin(a) * 3.55) for a in (i * math.pi / 3 for i in range(6))]
        gold += [C(1.1, 0.16, 0, 3.42, 0, segs=6), crown(1.3, 1.0, 0.12, 0, 1.25, -0.92)]
        mesh(L, "HqCommandSGold", gold, GOLD, "Metal")
        holo = [C(1.3, 2.2, 0, 4.6, 0, segs=4, r2=0.001)]  # the holo spire and its rings
        holo += [TOR(1.7, 0.05, 0, 3.8, 0, segs=6, csegs=3), TOR(2.4, 0.05, 0, 3.7, 0, segs=6, csegs=3)]
        for i in range(5):  # targets marked round it
            a = i * 2 * math.pi / 5
            holo.append(C(0.18, 0.9, math.cos(a) * 2.2, 4.0, math.sin(a) * 2.2, segs=4, r2=0.001))
        mesh(L, "HqCommandSHolo", holo, SGLOW, "Neon", 0.45)


def console_bench(st):
    """Gizmo's Bench: a workbench with a pegboard of tools, a vise and a big cog. The Syndicate's has an anvil
    on an iron bench and a spiked cog on a red board."""
    t = st["tag"]
    L = "HqBench" + t
    body = [SB(st, 6.4, 0.45, 2.8, 0, 3.0, 0)]  # the top
    if t == "V":
        body += [SB(st, 2.4, 2.4, 2.4, -1.9, 1.55, 0.05), B(0.4, 2.6, 0.4, 2.9, 1.5, -1.1), B(0.4, 2.6, 0.4, 2.9, 1.5, 1.1),
                 B(0.36, 0.3, 2.4, 2.9, 0.8, 0)]
        mesh(L, "HqBenchVBody", body, VWHITE)
        mesh(L, "HqBenchVTop", [RB(6.6, 0.22, 3.0, 0, 3.32, 0, r=0.08, segs=2)], WOOD, "Wood")
        board = [RB(6.4, 4.2, 0.25, 0, 5.5, 1.3, r=0.1, segs=2)]
        board += [B(1.9, 0.12, 0.12, -1.9, 1.55 + dy, -1.22) for dy in (-0.55, 0.55)]  # drawer lines (dark)
        mesh(L, "HqBenchVBoard", board, VBLUE)
        tools = [T([(-2.2, 4.6, 1.1), (-2.2, 6.3, 1.1)], 0.14, segs=6), TOR(0.42, 0.13, -2.2, 6.65, 1.1, axis="z", segs=10, csegs=4),
                 B(0.22, 1.7, 0.16, -1.3, 5.4, 1.1), RB(0.9, 0.42, 0.3, -1.3, 6.35, 1.1, r=0.08, segs=2),
                 T([(2.4, 4.6, 1.1), (2.1, 6.4, 1.1)], 0.1, segs=5)]
        for dy in (-0.5, 0.0, 0.5):  # the drawer handles
            tools.append(B(0.7, 0.12, 0.12, -1.9, 1.55 + dy * 2, -1.3))
        mesh(L, "HqBenchVTools", tools, CHARCOAL, "Metal")
        gold = [gear(1.05, 0.8, 10, 0.22, 0.9, 5.7, 1.05), C(0.25, 0.3, 0.9, 5.7, 0.95, segs=8, axis="z"),
                star(0.38, 0.16, 0.1, 0, 7.15, 1.2)]
        mesh(L, "HqBenchVGold", gold, GOLD, "Metal")
        vise = [RB(1.0, 0.7, 0.8, 1.8, 3.6, -0.3, r=0.08, segs=2), RB(1.0, 0.7, 0.3, 1.8, 3.6, -0.95, r=0.06, segs=2),
                T([(1.3, 3.6, -1.25), (2.3, 3.6, -1.25)], 0.06, segs=5)]
        lamp = [T([(-3.0, 3.3, 0.9), (-3.0, 5.0, 0.9), (-2.2, 5.6, 0.2)], 0.08, segs=5), C(0.5, 0.5, -2.1, 5.4, 0.1, segs=10, r2=0.2)]
        mesh(L, "HqBenchVSteel", vise + lamp, STEEL, "Metal")
        mesh(L, "HqBenchVGlow", [C(0.35, 0.06, -2.1, 5.13, 0.1, segs=10)], (255, 246, 206), "Neon")
    else:
        body += [prism([(-1.2, 0.3), (1.2, 0.3), (1.0, 2.8), (-1.0, 2.8)], 2.4, 2.9), prism([(-1.2, 0.3), (1.2, 0.3), (1.0, 2.8), (-1.0, 2.8)], -2.9, -2.4),
                 B(5.0, 0.3, 0.3, 0, 1.0, 0.9)]
        anvil = [B(1.0, 0.7, 0.8, 1.4, 3.55, 0), RB(2.2, 0.5, 1.0, 1.4, 4.1, 0, r=0.06, segs=1),
                 C(0.35, 0.9, 2.9, 4.1, 0, segs=6, r2=0.05, axis="x")]
        turn(anvil[2], "up", 180, (2.9, 4.1, 0))
        mesh(L, "HqBenchSBody", body + anvil, SIRON, "Metal")
        board = [SB(st, 6.4, 4.2, 0.25, 0, 5.5, 1.3)]
        board += [spike(0.2, 0.6, x, 7.6, 1.3) for x in (-2.8, -1.4, 0, 1.4, 2.8)]
        mesh(L, "HqBenchSBoard", board, SRED, "Metal")
        tools = [T([(-2.2, 4.6, 1.1), (-2.2, 6.3, 1.1)], 0.14, segs=6), TOR(0.42, 0.13, -2.2, 6.65, 1.1, axis="z", segs=10, csegs=4),
                 B(0.22, 1.7, 0.16, -1.2, 5.4, 1.1), prism([(-0.15, 6.0), (0.15, 6.0), (0.15, 6.7), (-0.15, 6.7)], -1.8, -0.6)]
        tools += [B(6.3, 0.4, 0.2, 0, 2.6, -1.42)]  # the bench's front rail
        mesh(L, "HqBenchSTools", tools, SBLACK, "Metal")
        g = gear(1.15, 0.85, 8, 0.24, 1.2, 5.7, 1.05)
        gold = [g, C(0.28, 0.32, 1.2, 5.7, 0.95, segs=6, axis="z"), crown(0.9, 0.7, 0.1, -0.2, 6.9, 1.15)]
        gold += [C(0.12, 0.08, x, 2.6, -1.55, segs=6, axis="z") for x in (-2.8, -1.4, 0, 1.4, 2.8)]
        mesh(L, "HqBenchSGold", gold, GOLD, "Metal")
        mesh(L, "HqBenchSGlow", [B(0.9, 0.12, 0.6, 1.4, 4.38, 0)], (255, 130, 40), "Neon")  # the anvil's hot work


def console_mannequin(st):
    """The Mannequins: a dress form on a stand and a tall mirror beside it. The Syndicate's form wears spiked
    shoulder plates and its mirror has an iron frame with spikes on top."""
    t = st["tag"]
    L = "HqMannequin" + t
    # (kit.loft rings are (up, half width, half depth, x, depth) in Blender axes)
    form = [kit.loft("form", [(3.0, 0.62, 0.42, -1.0, 0), (3.6, 0.55, 0.38, -1.0, 0), (4.3, 0.72, 0.45, -1.0, 0), (5.0, 0.95, 0.5, -1.0, 0),
                              (5.35, 0.9, 0.48, -1.0, 0), (5.55, 0.35, 0.3, -1.0, 0)], segs=16, power=2.2)]
    form.append(C(0.22, 0.4, -1.0, 5.75, 0, segs=10))  # the neck knob
    mesh(L, "HqMannequin%sForm" % t, form, CANVAS if t == "V" else (78, 72, 88), "Fabric")
    stand = [C(1.0, 0.25, -1.0, 0.72, 0, segs=16 if t == "V" else 6), C(0.11, 2.5, -1.0, 1.9, 0, segs=8)]
    glass = [RB(2.0, 5.2, 0.12, 1.7, 3.5, 0.2, r=0.05, segs=1)]
    turn(glass[0], "up", -25, (1.7, 3.5, 0.2))
    if t == "V":
        mesh(L, "HqMannequinVStand", stand, GOLD, "Metal")
        fr = frame_z(2.5, 5.8, 0.3, 0.3, 1.7, 3.5, 0.28)
        fr.append(B(2.0, 0.5, 1.2, 1.7, 0.45, 0.5))
        fr.append(star(0.45, 0.19, 0.16, 1.7, 6.75, 0.28))
        for p_ in fr:
            turn(p_, "up", -25, (1.7, 3.5, 0.2))
        mesh(L, "HqMannequinVFrame", fr, GOLD, "Metal")
        mesh(L, "HqMannequinVGlass", glass, MIRROR, "Glass")
        sash = [T([(-1.75, 5.1, -0.4), (-1.0, 4.45, -0.55), (-0.3, 3.75, -0.42)], 0.18, segs=6),
                star(0.3, 0.13, 0.1, -1.0, 4.85, -0.55)]
        mesh(L, "HqMannequinVSash", sash, VBLUE)
    else:
        mesh(L, "HqMannequinSStand", stand, SIRON, "Metal")
        fr = [SB(st, 2.5, 0.3, 0.3, 1.7, 6.25, 0.28), SB(st, 2.5, 0.3, 0.3, 1.7, 0.75, 0.28), SB(st, 0.3, 5.2, 0.3, 0.6, 3.5, 0.28),
              SB(st, 0.3, 5.2, 0.3, 2.8, 3.5, 0.28), B(2.0, 0.6, 1.2, 1.7, 0.3, 0.5)]
        fr += [spike(0.16, 0.7, x, 6.4, 0.28) for x in (0.7, 1.7, 2.7)]
        for p_ in fr:
            turn(p_, "up", -25, (1.7, 3.5, 0.2))
        mesh(L, "HqMannequinSFrame", fr, SBLACK, "Metal")
        mesh(L, "HqMannequinSGlass", glass, (170, 150, 190), "Glass")
        pads = []
        for s_ in (-1, 1):  # spiked shoulder plates
            pad = S(0.5, -1.0 + s_ * 0.85, 5.25, 0, sc=(1.0, 0.55, 0.9), segs=10, rings=6)
            pads += [pad, spike(0.12, 0.55, -1.0 + s_ * 0.95, 5.45, 0, tilt=(0, -s_ * 25))]
        mesh(L, "HqMannequinSPads", pads, SRED, "Metal")
    mesh(L, "HqMannequin%sGold" % t if t == "S" else "HqMannequinVBase", [C(1.05, 0.08, -1.0, 0.86, 0, segs=16 if t == "V" else 6)],
         GOLD if t == "S" else VBLUE, "Metal" if t == "S" else "SmoothPlastic")


def console_training(st):
    """The Training Room's meter: a low console on the pad's north side with a big tilted screen (a bar meter), a
    stopwatch dial and a big start button, low enough to see the dummies over it."""
    t = st["tag"]
    L = "HqTraining" + t
    z0 = -2.8
    body = [prism([(-0.9, 0.3), (0.9, 0.3), (0.9, 2.6), (-0.3, 3.3), (-0.9, 3.3)], -2.0, 2.0)]
    body = [shift(body[0], rb(0, 0, z0))]
    if t == "V":
        kit.bevel(body[0], 0.18, 3)
        kit.apply_all(body[0])
    else:
        kit.bevel(body[0], 0.12, 1)
        kit.apply_all(body[0])
    body.append(SB(st, 4.6, 0.3, 2.2, 0, 0.45, z0))
    mesh(L, "HqTraining%sBody" % t, body, st["body"], st["mat"])
    # the screen on the slanted face (from (z -0.9, up 2.6) to (z -0.3, up 3.3) in the profile... front is -z)
    scr = RB(3.4, 1.0, 0.08, 0, 0, 0, r=0.02, segs=1)
    turn(scr, "x", 49)
    at(scr, 0, 2.98, z0 - 0.62)
    mesh(L, "HqTraining%sScreen" % t, [scr], st["glow"], "Neon")
    bars = []
    for i, h in enumerate((0.3, 0.5, 0.42, 0.7, 0.85)):
        b = B(0.42, h, 0.05, -1.2 + i * 0.6, 0, 0)
        shift(b, rb(0, h / 2 - 0.42, 0))
        turn(b, "x", 49)
        at(b, 0, 2.98, z0 - 0.68)
        bars.append(b)
    mesh(L, "HqTraining%sBars" % t, bars, WHITE if t == "V" else (255, 214, 120))
    if t == "V":
        dial = [C(0.75, 0.25, -1.4, 3.75, z0 - 0.1, segs=20, axis="z"), C(0.18, 0.25, -1.4, 4.62, z0 - 0.1, segs=8),
                B(0.36, 0.14, 0.14, -1.4, 4.8, z0 - 0.1)]
    else:
        dial = [C(0.8, 0.25, -1.4, 3.75, z0 - 0.1, segs=8, axis="z"), spike(0.1, 0.4, -1.4, 4.5, z0 - 0.1), spike(0.1, 0.35, -2.0, 4.2, z0 - 0.1, tilt=(0, 40)),
                spike(0.1, 0.35, -0.8, 4.2, z0 - 0.1, tilt=(0, -40))]
    dial.append(C(0.4, 0.2, 1.4, 3.35, z0 + 0.3, segs=12))  # the button's collar
    mesh(L, "HqTraining%sTrim" % t, dial, st["main"] if t == "V" else GOLD, "SmoothPlastic" if t == "V" else "Metal")
    face_ = [C(0.62, 0.06, -1.4, 3.75, z0 - 0.25, segs=20, axis="z")]
    mesh(L, "HqTraining%sDial" % t, face_, WHITE if t == "V" else (250, 236, 200))
    hand = [B(0.08, 0.5, 0.05, -1.4, 3.95, z0 - 0.3), S(0.36, 1.4, 3.5, z0 + 0.3, sc=(1, 0.6, 1), segs=12, rings=6)]
    mesh(L, "HqTraining%sRed" % t, hand, RED)
    emb = [emblem(st, 0.9, 0, 1.4, z0 - 0.93)]
    mesh(L, "HqTraining%sMark" % t, emb, GOLD, "Metal" if t == "S" else "SmoothPlastic")


def console_lectern(st):
    """The Trophy Wall's lectern: a short podium with a slanted top and a gold cup on it."""
    t = st["tag"]
    L = "HqLectern" + t
    z0 = -2.0
    segs = 16 if t == "V" else 6
    body = [lathe([(1.2, 0.4), (1.0, 0.7), (0.65, 1.0), (0.55, 2.6), (0.9, 2.9)], 0, 0, z0, segs=segs)]
    top = RB(2.2, 0.3, 1.6, 0, 0, 0, r=0.1, segs=st["segs"])
    turn(top, "x", -18)
    at(top, 0, 3.05, z0)
    body.append(top)
    mesh(L, "HqLectern%sBody" % t, body, st["body"], st["mat"])
    trim = [C(1.25, 0.18, 0, 0.5, z0, segs=segs), C(0.95, 0.12, 0, 2.85, z0, segs=segs)]
    mesh(L, "HqLectern%sTrim" % t, trim, st["main"])
    cup = [lathe([(0.3, 0), (0.12, 0.08), (0.08, 0.35), (0.42, 0.55), (0.5, 0.95), (0.47, 1.0)], 0.3, 3.25, z0 + 0.25, segs=12)]
    cup += [TOR(0.22, 0.05, 0.3 + s_ * 0.5, 4.0, z0 + 0.25, axis="z", segs=8, csegs=4) for s_ in (-1, 1)]
    cup.append(emblem(st, 0.7, 0, 1.75, z0 - 0.62))
    mesh(L, "HqLectern%sGold" % t, cup, GOLD, "Metal")


def console_legends(st):
    """The Hall of Legends: a stone book stand with the open book of legends; a gold laurel and star on the
    Vigil's, two torches with red flames on the Syndicate's obsidian one."""
    t = st["tag"]
    L = "HqLegends" + t
    stone = MARBLE if t == "V" else (46, 40, 52)
    body = [SB(st, 2.6, 0.4, 2.0, 0, 0.2, 0), SB(st, 1.4, 2.4, 1.2, 0, 1.6, 0)]
    tp = SB(st, 2.4, 0.3, 1.8, 0, 0, 0)
    turn(tp, "x", -16)
    at(tp, 0, 3.0, 0)
    body.append(tp)
    if t == "S":
        for s_ in (-1, 1):
            body += [SB(st, 0.5, 3.2, 0.5, s_ * 1.9, 1.6, 0.2)]
    mesh(L, "HqLegends%sStone" % t, body, stone, "Marble" if t == "V" else "Basalt")
    cover = RB(2.3, 0.12, 1.6, 0, 0, 0, r=0.04, segs=1)
    pages = [RB(1.05, 0.14, 1.45, x, 0.1, 0, r=0.04, segs=1) for x in (-0.55, 0.55)]
    for p_ in pages:
        turn(p_, "z", 6 if p_ is pages[0] else -6)
    book = [cover] + pages
    for p_ in book:
        turn(p_, "x", -16)
        at(p_, 0, 3.24, 0)
    mesh(L, "HqLegends%sCover" % t, [cover], VNAVY if t == "V" else SRED, "Fabric")
    mesh(L, "HqLegends%sPages" % t, pages, PAPER)
    if t == "V":
        laurel = []
        for s_ in (-1, 1):  # the laurel: leaves along two arcs round the star
            for k in range(7):
                a = math.radians(200 + k * 22) if s_ < 0 else math.radians(-20 - k * 22)
                lx, ly = math.cos(a) * 0.62, math.sin(a) * 0.62 + 1.75
                leaf = S(0.16, 0, 0, 0, sc=(0.55, 1.2, 0.3), segs=6, rings=4)
                turn(leaf, "z", math.degrees(a) + (90 if s_ < 0 else -90) + s_ * 20)
                laurel.append(at(leaf, lx, ly, -0.65))
        laurel.append(star(0.36, 0.15, 0.1, 0, 1.75, -0.66))
        laurel.append(T([(0, 3.4, 0.5), (0, 3.38, -0.4), (0.05, 2.9, -0.85)], 0.04, segs=4))  # the ribbon marker
        mesh(L, "HqLegendsVGold", laurel, GOLD, "Metal")
    else:
        gold = [crown(1.0, 0.8, 0.12, 0, 1.35, -0.66)]
        for s_ in (-1, 1):
            gold.append(lathe([(0.12, 0), (0.42, 0.45), (0.45, 0.55)], s_ * 1.9, 3.2, 0.2, segs=6))
        mesh(L, "HqLegendsSGold", gold, GOLD, "Metal")
        flames = [C(0.32, 0.9, s_ * 1.9, 4.2, 0.2, segs=6, r2=0.02) for s_ in (-1, 1)]
        mesh(L, "HqLegendsSFlame", flames, (255, 96, 50), "Neon")


def console_scanner(st):
    """The HQ Scanner: a console with a round scope (rings and a sweep) and a radar dish on a mast."""
    t = st["tag"]
    L = "HqScanner" + t
    z0 = -1.2
    body = [SB(st, 3.0, 2.8, 1.8, 0, 1.4, z0 + 0.2)]
    tp = SB(st, 3.0, 0.35, 1.6, 0, 0, 0)
    turn(tp, "x", -28)
    at(tp, 0, 2.95, z0 + 0.1)
    body.append(tp)
    body.append(C(0.18, 2.8, 0.9, 4.1, z0 + 1.0, segs=8))  # the mast
    mesh(L, "HqScanner%sBody" % t, body, st["body"], st["mat"])
    scope = C(0.62, 0.06, 0, 0, 0, segs=24)
    turn(scope, "x", -28)
    at(scope, -0.5, 3.15, z0 + 0.12)
    mesh(L, "HqScanner%sScope" % t, [scope], GREENGLOW if t == "V" else SGLOW, "Neon")
    rings = [ring_up(0.44, 0.05, 0.06, 0, 0, 0, segs=20), ring_up(0.22, 0.05, 0.06, 0, 0, 0, segs=16), B(0.05, 0.06, 0.6, 0.0, 0, -0.3)]
    for r_ in rings:
        turn(r_, "up", 35)
        turn(r_, "x", -28)
        at(r_, -0.5, 3.2, z0 + 0.12)
    mesh(L, "HqScanner%sRings" % t, rings, (20, 60, 40) if t == "V" else (70, 16, 24))
    # the dish: a shallow bowl on its yoke, tilted up and out
    dish = lathe([(0.05, 0.0), (0.7, 0.12), (1.2, 0.42), (1.35, 0.6), (1.28, 0.62), (0.6, 0.3), (0.05, 0.2)], 0, 0, 0, segs=16 if t == "V" else 8)
    feed = C(0.05, 0.9, 0, 0.75, 0, segs=5)
    tip = S(0.12, 0, 1.2, 0, segs=6, rings=4)
    for p_ in (dish, feed, tip):
        turn(p_, "x", -40)
        at(p_, 0.9, 5.4, z0 + 1.0)
    mesh(L, "HqScanner%sDish" % t, [dish], st["main"] if t == "S" else VWHITE, "Metal" if t == "S" else "SmoothPlastic")
    trim = [feed, tip, B(3.1, 0.3, 0.12, 0, 1.0, z0 - 0.72), B(3.1, 0.3, 0.12, 0, 2.2, z0 - 0.72)]
    trim.append(emblem(st, 0.8, -0.9, 1.6, z0 - 0.75))
    if t == "S":
        trim += [spike(0.12, 0.5, x, 5.95, z0 + 1.0) for x in (0.9,)]
    mesh(L, "HqScanner%sGold" % t, trim, GOLD if t == "S" else VBLUE, "Metal" if t == "S" else "SmoothPlastic")


def console_exit(st):
    """The Exit: a door frame on the north wall (its back on the wall, 4.6 studs behind the pad's middle), a
    closed door with a push bar and a lit up arrow over it. The Syndicate's is a blast door with hazard bands."""
    t = st["tag"]
    L = "HqExit" + t
    zb = 4.6
    fr = [SB(st, 1.0, 9.5, 0.9, -3.4, 4.75, zb), SB(st, 1.0, 9.5, 0.9, 3.4, 4.75, zb), SB(st, 7.8, 1.0, 0.9, 0, 9.0, zb)]
    if t == "S":
        fr += [prism([(-0.45, 9.5), (0.45, 9.5), (0.0, 10.6)], x - 0.3, x + 0.3) for x in (-3.4, 3.4)]
        fr = fr[:3] + [shift(p_, rb(0, 0, zb)) for p_ in fr[3:]]
    mesh(L, "HqExit%sFrame" % t, fr, st["body"], st["mat"])
    door = [SB(st, 5.8, 8.4, 0.3, 0, 4.2, zb + 0.1, r=0.06)]
    mesh(L, "HqExit%sDoor" % t, door, VNAVY if t == "V" else SBLACK, "SmoothPlastic" if t == "V" else "DiamondPlate")
    trim = [T([(-1.9, 4.0, zb - 0.25), (1.9, 4.0, zb - 0.25)], 0.12, segs=6), B(0.2, 0.4, 0.3, -2.0, 4.0, zb - 0.1),
            B(0.2, 0.4, 0.3, 2.0, 4.0, zb - 0.1)]
    if t == "V":
        trim += [B(4.6, 0.12, 0.08, 0, 6.8, zb - 0.08), B(4.6, 0.12, 0.08, 0, 1.6, zb - 0.08)]
        mesh(L, "HqExitVTrim", trim, VBLUE)
        mesh(L, "HqExitVGold", [star(0.45, 0.19, 0.12, 0, 9.0, zb - 0.5)], GOLD)
    else:
        for i in range(4):  # hazard bands across the frame's foot and the lintel
            trim.append(prism([(-0.2, 0.3 + i * 0.9), (0.2, 0.3 + i * 0.9), (0.2, 0.75 + i * 0.9), (-0.2, 0.75 + i * 0.9)], -3.95, -2.85))
        trim = trim[:3] + [shift(p_, rb(0, 0, zb - 0.47)) for p_ in trim[3:]]
        trim += [shift(prism([(-0.02, 0.3 + i * 0.9), (0.02, 0.3 + i * 0.9), (0.02, 0.75 + i * 0.9), (-0.02, 0.75 + i * 0.9)], 2.85, 3.95), rb(0, 0, zb - 0.47)) for i in range(4)]
        mesh(L, "HqExitSTrim", trim, AMBER, "Metal")
        mesh(L, "HqExitSGold", [crown(0.9, 0.7, 0.12, 0, 8.7, zb - 0.5)] + rivets([(x, y, zb - 0.47) for x in (-3.4, 3.4) for y in (2.2, 4.75, 7.3)]), GOLD, "Metal")
    arrow = face([(-0.9, 0), (0, 0.9), (0.9, 0), (0.45, 0), (0.45, -0.8), (-0.45, -0.8), (-0.45, 0)], -0.06, 0.06)
    at(arrow, 0, 10.55 if t == "V" else 10.4, zb - 0.1)
    lamp = [arrow]
    if t == "S":
        lamp.append(C(0.35, 0.5, -2.6, 9.75, zb - 0.3, segs=8))
    mesh(L, "HqExit%sGlow" % t, lamp, GREENGLOW, "Neon")


for tag in ("V", "S"):
    st = STYLE[tag]
    console_command(st)
    console_bench(st)
    console_mannequin(st)
    console_training(st)
    console_lectern(st)
    console_legends(st)
    console_scanner(st)
    console_exit(st)


# ================================================================ the Trophy Wall (foot: the middle of the plaque row
# on the floor; plaques at x +-2.1 and +-6.3, y 4, 7.6 and 11.2, z 0; front -z)
def trophy_wall(st):
    t = st["tag"]
    L = "HqTrophyWall" + t
    back = [SB(st, 18.4, 12.0, 0.4, 0, 7.6, 0.55, r=0.1)]
    cols = []
    for s_ in (-1, 1):
        x = s_ * 9.85
        if t == "V":
            cols += [lathe([(0.75, 0), (0.62, 0.4), (0.52, 0.6), (0.52, 13.2), (0.7, 13.5), (0.8, 13.9)], x, 0.0, 0.4, segs=12)]
        else:
            cols += [SB(st, 1.3, 14.2, 1.3, x, 7.1, 0.4)]
    base = [SB(st, 21.4, 1.0, 2.4, 0, 0.5, 0.4), SB(st, 20.6, 0.6, 1.8, 0, 1.3, 0.45)]
    top = [SB(st, 21.0, 0.8, 1.8, 0, 14.3, 0.4)]
    if t == "V":
        top.append(face([(-6.5, 14.7), (6.5, 14.7), (0, 16.9)], 0.0, 1.0))  # a pediment
        mesh(L, "HqTrophyWallVBack", back, VBLUE)
        mesh(L, "HqTrophyWallVStone", cols + base + top, VWHITE)
        gold = [TOR(1.0, 0.14, 0, 16.0, -0.1, axis="z", segs=20, csegs=5), star(0.8, 0.34, 0.25, 0, 16.0, -0.15),
                B(18.6, 0.18, 0.12, 0, 13.7, 0.3), B(18.6, 0.18, 0.12, 0, 1.75, 0.3)]
        for s_ in (-1, 1):
            gold += [C(0.85, 0.2, s_ * 9.85, 13.75, 0.4, segs=12), C(0.82, 0.2, s_ * 9.85, 0.75, 0.4, segs=12)]
            gold.append(star(0.5, 0.21, 0.14, s_ * 8.2, 15.3, -0.15))
        mesh(L, "HqTrophyWallVGold", gold, GOLD, "Metal")
        mesh(L, "HqTrophyWallVGlow", [B(18.0, 0.2, 0.1, 0, 2.15, 0.33), B(18.0, 0.2, 0.1, 0, 13.25, 0.33)], VGLOW, "Neon")
    else:
        mesh(L, "HqTrophyWallSBack", back, SBLACK, "Metal")
        horns = []
        for s_ in (-1, 1):  # two curved horns rising from the cornice ends
            horns.append(T([(s_ * 9.2, 14.6, 0.4), (s_ * 10.0, 15.8, 0.4), (s_ * 9.6, 17.0, 0.4), (s_ * 8.7, 17.6, 0.4)], [0.5, 0.42, 0.28, 0.04], segs=6))
        mesh(L, "HqTrophyWallSIron", cols + base + top + horns, SIRON, "Metal")
        gold = [crown(3.4, 2.7, 0.3, 0, 14.7, 0.0), B(18.6, 0.18, 0.12, 0, 13.7, 0.3), B(18.6, 0.18, 0.12, 0, 1.75, 0.3)]
        gold += [spike(0.22, 0.9, x, 14.7, 0.4) for x in (-7.5, -5.5, 5.5, 7.5)]
        gold += rivets([(s_ * 9.85, y, -0.27) for s_ in (-1, 1) for y in (2.5, 5.5, 8.5, 11.5)], r=0.16)
        mesh(L, "HqTrophyWallSGold", gold, GOLD, "Metal")
        mesh(L, "HqTrophyWallSGlow", [B(18.0, 0.2, 0.1, 0, 2.15, 0.33), B(18.0, 0.2, 0.1, 0, 13.25, 0.33)], SGLOW, "Neon")


def plaque(st):
    """A trophy's plaque (3.6 x 3 x 0.4 round its middle): the body takes the side's colour when it holds a
    trophy and its trim when empty (HqClient tints it); a gold rim round it."""
    t = st["tag"]
    L = "HqPlaque" + t
    if t == "V":
        body = [RB(3.4, 2.8, 0.3, 0, 0, 0.05, r=0.35, segs=3)]
        rim = [RB(3.6, 0.18, 0.2, 0, 1.35, -0.08, r=0.08, segs=2), RB(3.6, 0.18, 0.2, 0, -1.35, -0.08, r=0.08, segs=2),
               RB(0.18, 2.6, 0.2, -1.75, 0, -0.08, r=0.08, segs=2), RB(0.18, 2.6, 0.2, 1.75, 0, -0.08, r=0.08, segs=2)]
        rim.append(star(0.22, 0.09, 0.08, 0, -1.05, -0.15))
    else:
        body = [face([(-1.7, -1.2), (-1.3, -1.45), (1.3, -1.45), (1.7, -1.2), (1.7, 1.2), (1.3, 1.45), (-1.3, 1.45), (-1.7, 1.2)], -0.1, 0.2)]
        rim = rivets([(x, y, -0.14) for x in (-1.45, 1.45) for y in (-1.15, 1.15)], r=0.14)
        rim += [B(2.4, 0.12, 0.08, 0, -1.25, -0.13), B(2.4, 0.12, 0.08, 0, 1.25, -0.13)]
    mesh(L, "HqPlaque%sBody" % t, body, st["main"], "SmoothPlastic" if t == "V" else "Metal")
    mesh(L, "HqPlaque%sRim" % t, rim, GOLD, "Metal")


# the trophies (foot: the cup part's middle; about 1.2 x 1.4 x 1.2, in front of the plaque): gold, on a dark base
L = "HqTrophyCup"
cup = [lathe([(0.04, -0.28), (0.13, -0.2), (0.1, 0.0), (0.38, 0.12), (0.5, 0.45), (0.52, 0.66), (0.47, 0.68), (0.4, 0.3), (0.05, 0.2)], 0, 0, 0, segs=14)]
for s_ in (-1, 1):  # the handles: half rings on the sides
    hnd = TOR(0.2, 0.05, 0, 0, 0, axis="z", segs=8, csegs=4, arc=math.pi)
    turn(hnd, "z", -90 * s_)
    cup.append(at(hnd, s_ * 0.5, 0.4, 0))
mesh(L, "HqTrophyCupGold", cup, GOLD, "Metal")
mesh(L, "HqTrophyCupBase", [RB(0.7, 0.34, 0.7, 0, -0.5, 0, r=0.05, segs=1)], CHARCOAL)
L = "HqTrophyStar"
mesh(L, "HqTrophyStarGold", [star(0.55, 0.23, 0.24, 0, 0.2, 0), C(0.07, 0.4, 0, -0.35, 0, segs=6)], GOLD, "Metal")
mesh(L, "HqTrophyStarBase", [RB(0.7, 0.3, 0.7, 0, -0.55, 0, r=0.05, segs=1)], CHARCOAL)
L = "HqTrophyMedal"
mesh(L, "HqTrophyMedalGold", [C(0.42, 0.12, 0, -0.2, 0, segs=16, axis="z"), star(0.24, 0.1, 0.06, 0, -0.2, -0.08),
                              TOR(0.1, 0.03, 0, 0.25, 0, axis="z", segs=8, csegs=4)], GOLD, "Metal")
rib = [face([(-0.1, 0.3), (0.06, 0.3), (-0.12, 0.7), (-0.28, 0.7)], -0.03, 0.03), face([(0.1, 0.3), (-0.06, 0.3), (0.12, 0.7), (0.28, 0.7)], -0.03, 0.03)]
mesh(L, "HqTrophyMedalRibbon", rib, RED, "Fabric")


# ================================================================ WP9's wall (in the wall frame: front -z)
def wanted_board(st, lay):
    """The WANTED board, its middle at the board part's middle: the poster's paper (the game's part, 7 x 8, 0.2
    to 0.3 in front) hangs on it, so nothing comes forward of the cork inside the paper, and the frame keeps below
    the head plates (its top 4.2 up)."""
    t = st["tag"]
    L = "HqWantedBoard" + t
    w, h = lay["board"]["size"][0], lay["board"]["size"][1]
    bc = lay["board"]["at"]
    pins = [(p[0] - bc[0], p[1] - bc[1], p[2] - bc[2]) for p in lay["pins"]]
    if t == "V":
        mesh(L, "HqWantedBoardVCork", [RB(w, h, 0.27, 0, 0, 0.015, r=0.04, segs=1)], CORK, "Fabric")
        fr = [RB(0.75, h + 1.1, 0.55, s_ * (w / 2 + 0.3), -0.55, -0.05, r=0.1, segs=2) for s_ in (-1, 1)]
        fr += [RB(w + 1.35, 0.9, 0.55, 0, -h / 2 - 0.55, -0.05, r=0.1, segs=2), RB(w + 0.2, 0.25, 0.4, 0, h / 2 - 0.08, -0.05, r=0.05, segs=1)]
        fr.append(RB(w + 1.6, 0.18, 1.0, 0, -h / 2 - 0.92, -0.45, r=0.04, segs=1))  # the ledge
        mesh(L, "HqWantedBoardVWood", fr, DARKWOOD, "Wood")
        heads = [C(0.2, 0.12, px, py, pz - 0.02, segs=10, axis="z") for (px, py, pz) in pins]
        heads += [S(0.15, px, py, pz - 0.12, segs=8, rings=5) for (px, py, pz) in pins]
        heads += [C(0.16, 0.1, x, -h / 2 - 0.78, -0.5, segs=8) for x in (-2.6, 2.8)]  # spare pins on the ledge
        mesh(L, "HqWantedBoardVPins", heads, RED)
        mesh(L, "HqWantedBoardVBrass", [B(1.4, 0.4, 0.06, 0, -h / 2 - 0.55, -0.35)], BRASS, "Metal")
    else:
        mesh(L, "HqWantedBoardSPlate", [face([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)], -0.12, 0.15)], SIRON, "DiamondPlate")
        fr = []
        for s_ in (-1, 1):
            fr.append(at(face([(-0.45, -h / 2 - 1.2), (0.45, -h / 2 - 0.9), (0.45, h / 2 + 0.05), (-0.45, h / 2 + 0.05)], -0.45, 0.1), s_ * (w / 2 + 0.4), 0, 0))
        fr.append(face([(-w / 2 - 0.85, -h / 2 - 1.2), (w / 2 + 0.85, -h / 2 - 1.2), (w / 2 + 0.85, -h / 2 - 0.05), (-w / 2 - 0.85, -h / 2 - 0.05)], -0.45, 0.1))
        mesh(L, "HqWantedBoardSIron", fr, SBLACK, "Metal")
        bolts = [C(0.24, 0.16, px, py, pz, segs=6, axis="z") for (px, py, pz) in pins]
        bolts += rivets([(s_ * (w / 2 + 0.4), y, -0.48) for s_ in (-1, 1) for y in (-3.0, -1.0, 1.0, 3.0)], r=0.13)
        mesh(L, "HqWantedBoardSGold", bolts, GOLD, "Metal")
        stripes = []
        for i in range(9):  # hazard bands along the foot
            x0 = -w / 2 - 0.6 + i * 1.0
            stripes.append(face([(x0, -h / 2 - 1.1), (x0 + 0.45, -h / 2 - 1.1), (x0 + 0.85, -h / 2 - 0.15), (x0 + 0.4, -h / 2 - 0.15)], -0.5, -0.44))
        mesh(L, "HqWantedBoardSStripes", stripes, AMBER)
        mesh(L, "HqWantedBoardSGlow", [RB(0.5, 0.5, 0.3, s_ * (w / 2 + 0.4), -h / 2 - 0.62, -0.55, r=0.08, segs=1) for s_ in (-1, 1)], SGLOW, "Neon")


def mount(st):
    """A head mount (3 x 2.6, its middle at the mount part's middle): the head hangs 1 stud in front, and the "?"
    of an empty mount is drawn on the part's face (0.15 in front), so the plaque keeps behind it."""
    t = st["tag"]
    L = "HqMount" + t
    if t == "V":
        sh = [(-1.5, 1.3), (1.5, 1.3), (1.5, -0.2), (0.9, -1.0), (0, -1.3), (-0.9, -1.0), (-1.5, -0.2)]
        mesh(L, "HqMountVWood", [face(sh, -0.12, 0.15)], WOOD, "Wood")
        rim = []
        for k in range(len(sh)):  # a gold rim along the shield's edge
            a, b = sh[k], sh[(k + 1) % len(sh)]
            rim.append(T([(a[0], a[1], -0.14), (b[0], b[1], -0.14)], 0.08, segs=4))
        rim.append(C(0.16, 0.08, 0, 1.05, -0.17, segs=8, axis="z"))
        mesh(L, "HqMountVGold", rim, GOLD, "Metal")
    else:
        sh = [(-1.5, 1.3), (-0.6, 1.0), (0, 1.3), (0.6, 1.0), (1.5, 1.3), (1.5, -0.6), (0, -1.3), (-1.5, -0.6)]
        mesh(L, "HqMountSIron", [face(sh, -0.12, 0.15)], SIRON, "Metal")
        gold = rivets([(x, y, -0.16) for (x, y) in ((-1.25, 1.0), (1.25, 1.0), (-1.25, -0.5), (1.25, -0.5), (0, -1.0))], r=0.12)
        gold += [spike(0.14, 0.55, s_ * 1.45, 1.25, 0.0, tilt=(0, -s_ * 20)) for s_ in (-1, 1)]
        mesh(L, "HqMountSGold", gold, GOLD, "Metal")


L = "HqNamePlate"  # the name plate under a mount (3.4 x 0.7 x 0.2; its text is the part's SurfaceGui)
mesh(L, "HqNamePlateBody", [RB(3.4, 0.7, 0.18, 0, 0, 0.01, r=0.12, segs=2)], GOLD, "Metal")
mesh(L, "HqNamePlateScrews", [C(0.07, 0.06, x, 0, -0.1, segs=6, axis="z") for x in (-1.55, 1.55)], BRASS, "Metal")


# ================================================================ statue plinths (foot: the plinth's foot; 5 x 2 x 5)
def plinth(st):
    t = st["tag"]
    L = "HqPlinth" + t
    if t == "V":
        stone = [RB(5.0, 0.5, 5.0, 0, 0.25, 0, r=0.1, segs=2), RB(4.3, 1.1, 4.3, 0, 1.05, 0, r=0.08, segs=2), RB(4.7, 0.4, 4.7, 0, 1.8, 0, r=0.1, segs=2)]
        mesh(L, "HqPlinthVStone", stone, MARBLE, "Marble")
        mesh(L, "HqPlinthVGold", [RB(4.4, 0.2, 4.4, 0, 1.25, 0, r=0.05, segs=1), star(0.4, 0.17, 0.1, 0, 0.85, -2.17)], GOLD, "Metal")
    else:
        stone = [RB(5.0, 0.5, 5.0, 0, 0.25, 0, r=0.06, segs=1), RB(4.3, 1.1, 4.3, 0, 1.05, 0, r=0.06, segs=1), RB(4.7, 0.4, 4.7, 0, 1.8, 0, r=0.06, segs=1)]
        mesh(L, "HqPlinthSStone", stone, (46, 40, 52), "Basalt")
        gold = [RB(4.4, 0.2, 4.4, 0, 1.25, 0, r=0.04, segs=1), crown(0.8, 0.6, 0.1, 0, 0.6, -2.17)]
        gold += [spike(0.2, 0.8, sx * 2.1, 2.0, sz * 2.1) for sx in (-1, 1) for sz in (-1, 1)]
        mesh(L, "HqPlinthSGold", gold, GOLD, "Metal")
        mesh(L, "HqPlinthSRed", [RB(4.36, 0.12, 4.36, 0, 0.62, 0, r=0.03, segs=1)], SRED, "Neon")


# ================================================================ the shapes (HqArtKit.SHAPES): each fills a part of any
# size, so each is built to fill its own box exactly (the game stretches the joint box of a shape's meshes over the
# part); the colour and material are the part's own for the nemesis pieces
# ---------------------------------------------------------------- the training dummy: its base, chest target and visor
L = "HqDummy"
mesh(L, "HqDummyBase", [lathe([(1.5, -0.3), (1.5, 0.05), (1.3, 0.3), (0.55, 0.3)], segs=20)], (60, 64, 76), "Metal")
mesh(L, "HqDummyBolts", [C(0.14, 0.12, math.cos(a) * 1.28, 0.24, math.sin(a) * 1.28, segs=6) for a in (i * math.pi / 4 for i in range(8))]
     + [TOR(1.5, 0.03, 0, -0.27, 0, segs=20, csegs=3)], YELLOW, "Metal")
# the target: a bullseye across x (the part is a cylinder along x, turned to face out of the chest)
mesh(L, "HqDummyTarget", [C(0.5, 0.18, 0, 0, 0, segs=20, axis="x")], (230, 70, 60), "Neon")
rings = [ring_up(0.5, 0.07, 0.2, 0, 0, 0, segs=20), ring_up(0.33, 0.08, 0.2, 0, 0, 0, segs=20), C(0.09, 0.2, 0, 0, 0, segs=10)]
for r_ in rings:
    turn(r_, "z", 90)
mesh(L, "HqDummyRings", rings, WHITE)
vis = [kit.loft("vis", [(-0.5, 0.06, 0.06, 0, 0), (-0.42, 0.42, 0.45, 0, 0), (0.42, 0.42, 0.45, 0, 0), (0.5, 0.06, 0.06, 0, 0)], segs=10, power=2.0)]
turn(vis[0], "z", 90)  # (lofted along Blender z: turned to run along x)
vis[0].data.update()
mesh(L, "HqDummyVisor", vis, (120, 220, 255), "Neon")

# ---------------------------------------------------------------- the dummy's own body: the 15 R15 parts, named as the
# rig's (NpcRig `look` "Hq": the game finds Head, UpperTorso, ... in Art.Hq), each filling the hero rig's box for its
# part: a padded sparring bot (a round helmet, a barrel chest with pads, a belt, banded limbs, mitts and boots). One
# colour a part (HqClient paints them in the side's colours).
L = "HqDummyBody"
RIG = {
    "Head": (1.194, 1.277, 1.194), "UpperTorso": (2.0, 1.6, 1.0), "LowerTorso": (2.0, 0.4, 1.0),
    "LeftUpperArm": (1.0, 0.85, 1.0), "RightUpperArm": (1.0, 0.85, 1.0), "LeftLowerArm": (1.0, 0.85, 1.0),
    "RightLowerArm": (1.0, 0.85, 1.0), "LeftHand": (1.0, 0.3, 1.0), "RightHand": (1.0, 0.3, 1.0),
    "LeftUpperLeg": (1.0, 0.85, 1.0), "RightUpperLeg": (1.0, 0.85, 1.0), "LeftLowerLeg": (1.0, 0.85, 1.0),
    "RightLowerLeg": (1.0, 0.85, 1.0), "LeftFoot": (1.0, 0.3, 1.0), "RightFoot": (1.0, 0.3, 1.0),
}


def limb(sx, sy, sz, band=True):
    """A padded limb filling sx x sy x sz: a rounded cylinder with a raised band at its middle."""
    r = min(sx, sz) / 2
    prof = [(r * 0.8, -sy / 2), (r * 0.92, -sy / 2 + 0.05), (r * 0.92, -0.1), (r, -0.07), (r, 0.07), (r * 0.92, 0.1),
            (r * 0.92, sy / 2 - 0.05), (r * 0.8, sy / 2)] if band else [(r * 0.85, -sy / 2), (r, -sy / 2 + 0.08), (r, sy / 2 - 0.08), (r * 0.85, sy / 2)]
    return lathe(prof, segs=12)


for name, (sx, sy, sz) in RIG.items():
    if name == "Head":
        parts = [RB(sx * 0.92, sy, sz * 0.92, 0, 0, 0, r=0.42, segs=3)]
        parts += [C(0.22, 0.12, s_ * (sx / 2 - 0.06), 0, 0.05, segs=10, axis="x") for s_ in (-1, 1)]  # ear bolts
    elif name == "UpperTorso":
        parts = [kit.loft("ut", [(-0.8, 0.82, 0.42, 0, 0), (-0.3, 0.9, 0.47, 0, 0), (0.35, 1.0, 0.5, 0, 0), (0.8, 0.95, 0.46, 0, 0)], segs=16, power=3.0)]
        for s_ in (-1, 1):  # chest pads
            parts.append(RB(0.8, 0.7, 0.2, s_ * 0.45, 0.2, -0.4, r=0.09, segs=2))
    elif name == "LowerTorso":
        parts = [RB(sx * 0.9, sy, sz * 0.9, 0, 0, 0, r=0.12, segs=2), RB(sx, 0.18, sz, 0, 0, 0, r=0.06, segs=2)]
    elif "Hand" in name:
        parts = [RB(sx * 0.85, sy, sz, 0, 0, 0, r=0.12, segs=2)]
    elif "Foot" in name:
        parts = [RB(sx * 0.9, sy, sz * 0.7, 0, 0, 0.15, r=0.1, segs=2), RB(sx * 0.8, sy * 0.85, sz * 0.4, 0, -sy * 0.075, -0.3, r=0.12, segs=2)]
    else:
        parts = [limb(sx, sy, sz)]
    mesh(L, name, parts, (150, 156, 170), "Metal")

# ---------------------------------------------------------------- the nemesis pieces (Shared.WantedRules head and bust)
L = "HqNemesis"
skull = [RB(1.0, 0.86, 1.0, 0, -0.07, 0, r=0.36, segs=3), RB(0.16, 0.3, 0.8, 0, 0.35, 0.02, r=0.07, segs=2)]  # a dome and its crest
skull += [RB(0.1, 0.36, 0.42, s_ * 0.5, -0.08, 0.05, r=0.04, segs=1) for s_ in (-1, 1)]  # side vents
mesh(L, "HqNemSkull", skull, (40, 40, 48), "Metal")
mesh(L, "HqNemFace", [face([(-0.5, 0.5), (0.5, 0.5), (0.5, -0.1), (0.25, -0.5), (-0.25, -0.5), (-0.5, -0.1)], -0.5, 0.5)], (200, 60, 60), "Metal")
jaw = [RB(1.0, 1.0, 0.7, 0, 0, 0.15, r=0.18, segs=2)]
jaw += [B(0.06, 0.9, 0.3, x, 0, -0.35) for x in (-0.3, -0.1, 0.1, 0.3)]
mesh(L, "HqNemJaw", jaw, (40, 40, 48), "Metal")
mesh(L, "HqNemHorn", [T([(0, -0.5, -0.1), (0, -0.1, 0.0), (0, 0.25, 0.25), (0, 0.5, 0.5)], [0.5, 0.42, 0.26, 0.02], segs=8)], (40, 40, 48), "Metal")
mesh(L, "HqNemSpike", [C(0.5, 1.0, 0, 0, 0, segs=6, r2=0.02)], (40, 40, 48), "Metal")
vis = kit.loft("nv", [(-0.5, 0.02, 0.3, 0, 0), (-0.38, 0.42, 0.5, 0, 0), (0.38, 0.42, 0.5, 0, 0), (0.5, 0.02, 0.3, 0, 0)], segs=8, power=2.6)
turn(vis, "z", 90)
mesh(L, "HqNemVisor", [vis], (120, 230, 255), "Neon")
chest = [kit.loft("ch", [(-0.5, 0.34, 0.4, 0, 0), (-0.1, 0.42, 0.46, 0, 0), (0.3, 0.5, 0.5, 0, 0), (0.5, 0.46, 0.46, 0, 0)], segs=16, power=2.8)]
for s_ in (-1, 1):  # the pectoral plates
    chest.append(RB(0.38, 0.32, 0.12, s_ * 0.2, 0.2, -0.44, r=0.05, segs=2))
chest.append(RB(0.16, 0.5, 0.1, 0, -0.18, -0.45, r=0.04, segs=1))  # the ab ridge
mesh(L, "HqNemChest", chest, (200, 60, 60), "Metal")
sh = [RB(0.34, 0.6, 0.8, 0, -0.2, 0, r=0.12, segs=2)]  # the collar between them
for s_ in (-1, 1):
    sh.append(S(0.5, s_ * 0.33, 0.0, 0, sc=(0.34, 1.0, 1.0), segs=12, rings=8))
mesh(L, "HqNemShoulders", sh, (40, 40, 48), "Metal")
cape = []
pts = []
for i in range(13):  # a pleated sheet, the hem a little ragged
    x = -0.5 + i / 12
    pts.append((x, 0.5 * math.cos(i * math.pi / 2) * 0.6))
rows = []
for j in range(5):
    y = 0.5 - j * 0.25
    ring = [(x, y - (0.06 if (j == 4 and i % 2) else 0), dz) for i, (x, dz) in enumerate(pts)]
    rows.append(ring)
bm = bmesh.new()
grid = [[bm.verts.new(rb(x, y, z)) for (x, y, z) in row] for row in rows]
back = [[bm.verts.new(rb(x, y, z + 0.4)) for (x, y, z) in row] for row in rows]
for j in range(len(rows) - 1):
    for i in range(len(pts) - 1):
        bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
        bm.faces.new((back[j][i], back[j + 1][i], back[j + 1][i + 1], back[j][i + 1]))
for j in range(len(rows) - 1):
    for (i, k) in ((0, 0), (len(pts) - 1, len(pts) - 1)):
        bm.faces.new((grid[j][i], grid[j + 1][i], back[j + 1][k], back[j][k]))
for i in range(len(pts) - 1):
    for j in (0, len(rows) - 1):
        bm.faces.new((grid[j][i], back[j][i], back[j][i + 1], grid[j][i + 1]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("cape")
bm.to_mesh(me)
bm.free()
cob = bpy.data.objects.new("cape", me)
bpy.context.scene.collection.objects.link(cob)
mesh(L, "HqNemCape", [cob], (200, 60, 60), "Fabric")


# ================================================================ the props (HqArtKit.PROPS; foot on the floor at the
# prop's spot, front -z, turned into the room; about a 3-stud cube, as today's block)
def prop(look, parts_by_colour):
    for (suffix, parts, rgb, mat, alpha) in parts_by_colour:
        mesh(look, look + suffix, parts, rgb, mat or "SmoothPlastic", alpha or 0.0)


# 1 the Cafe Sign (a side quest's reward): a little shop sign on two posts, a striped awning and a steaming cup
awn = []
for k in range(6):
    s_ = B(1.0, 0.12, 0.9, -2.5 + k * 1.0, 3.95, -0.25)
    turn(s_, "x", 18, (0, 3.95, -0.25))
    awn.append(s_)
prop("HqCafeSign", [
    ("Board", [RB(5.2, 2.2, 0.3, 0, 2.6, 0, r=0.12, segs=2)], (60, 44, 36), None, None),
    ("Posts", [C(0.14, 3.6, x, 1.8, 0.1, segs=6) for x in (-2.7, 2.7)] + [RB(1.0, 0.25, 0.8, x, 0.12, 0.1, r=0.05, segs=1) for x in (-2.7, 2.7)], DARKWOOD, "Wood", None),
    ("Red", [awn[i] for i in range(0, 6, 2)], RED, "Fabric", None),
    ("White", [awn[i] for i in range(1, 6, 2)] + [lathe([(0.35, 0), (0.45, 0.7), (0.47, 0.72)], -1.2, 2.2, -0.2, segs=12),
                                                  TOR(0.18, 0.06, -0.72, 2.6, -0.2, axis="z", segs=8, csegs=4)], WHITE, None, None),
    ("Gold", [B(2.2, 0.16, 0.06, 0.8, 3.0, -0.18), B(1.6, 0.16, 0.06, 0.6, 2.6, -0.18), B(2.0, 0.16, 0.06, 0.75, 2.2, -0.18),
              T([(-1.25, 3.0, -0.2), (-1.1, 3.3, -0.2), (-1.3, 3.55, -0.2)], 0.05, segs=4)], GOLD, None, None),
])
# 2 the Potted Fern: a terracotta pot and arching fronds
fronds = []
for i in range(9):
    a = i * 2 * math.pi / 9
    r0, h0 = 0.25, 1.6
    fr = T([(math.cos(a) * r0, h0, math.sin(a) * r0), (math.cos(a) * 0.9, h0 + 1.0, math.sin(a) * 0.9),
            (math.cos(a) * 1.5, h0 + 0.9 + (i % 2) * 0.2, math.sin(a) * 1.5), (math.cos(a) * 1.75, h0 + 0.4, math.sin(a) * 1.75)], [0.16, 0.22, 0.16, 0.03], segs=5)
    fronds.append(fr)
prop("HqFern", [
    ("Pot", [lathe([(0.7, 0), (0.95, 1.2), (1.1, 1.25), (1.1, 1.55), (0.95, 1.6)], segs=14)], POT, None, None),
    ("Leaves", fronds + [C(0.85, 0.1, 0, 1.55, 0, segs=12)], LEAF, "Grass", None),
])
# 3 the City Map Table: a small table with the city map on it and three flag pins
FLAGS = ((-0.6, 0.3), (0.7, -0.2), (1.1, 0.6))
mp = [B(2.9, 0.05, 2.1, 0, 2.53, 0)]
blocks = [B(0.5, 0.18 + ((i * 5) % 3) * 0.12, 0.5, -1.0 + (i % 4) * 0.66, 2.6, -0.6 + (i // 4) * 0.62) for i in range(8)]
prop("HqMapTable", [
    ("Wood", [RB(3.2, 0.2, 2.4, 0, 2.4, 0, r=0.06, segs=1)] + [B(0.25, 2.3, 0.25, x, 1.15, z) for x in (-1.4, 1.4) for z in (-1.0, 1.0)], WOOD, "Wood", None),
    ("Map", mp, (232, 226, 196), None, None),
    ("Blocks", blocks, (110, 170, 220), None, None),
    ("Flags", [C(0.03, 0.6, x, 2.85, z, segs=4) for (x, z) in FLAGS]
     + [at(face([(0, 0), (0.35, -0.12), (0, -0.24)], -0.02, 0.02), x + 0.03, 3.15, z) for (x, z) in FLAGS], RED, None, None),
])
# 4 the Thank-You Board: an easel with a big card and a heart
ease = [T([(-0.8, 0, 0.3), (0, 3.6, 0.1)], 0.07, segs=5), T([(0.8, 0, 0.3), (0, 3.6, 0.1)], 0.07, segs=5), T([(0, 0, 1.2), (0, 3.4, 0.2)], 0.07, segs=5),
        B(2.4, 0.12, 0.3, 0, 1.25, 0.0)]
heart = face([(0, -0.55), (0.55, 0.05), (0.5, 0.35), (0.25, 0.5), (0, 0.3), (-0.25, 0.5), (-0.5, 0.35), (-0.55, 0.05)], -0.05, 0.05)
prop("HqThanksEasel", [
    ("Wood", ease, WOOD, "Wood", None),
    ("Card", [RB(2.3, 1.9, 0.1, 0, 2.3, -0.05, r=0.05, segs=1)], PAPER, None, None),
    ("Heart", [at(heart, 0, 2.45, -0.14)], PINK, None, None),
    ("Lines", [B(1.4, 0.07, 0.03, 0, y, -0.12) for y in (1.75, 1.6)], (120, 120, 140), None, None),
])
# 5 the Rescue Bell: a brass bell under a little wooden gallows frame with a red rope
bell = lathe([(0.75, 1.3), (0.7, 1.4), (0.5, 1.9), (0.42, 2.4), (0.2, 2.6), (0.05, 2.62)], segs=14)
prop("HqRescueBell", [
    ("Bell", [bell, S(0.14, 0, 1.25, 0, segs=6, rings=4)], BRASS, "Metal", None),
    ("Frame", [B(0.3, 3.4, 0.3, x, 1.7, 0) for x in (-1.2, 1.2)] + [B(2.8, 0.3, 0.4, 0, 3.4, 0), RB(3.0, 0.3, 1.4, 0, 0.15, 0, r=0.05, segs=1)], WOOD, "Wood", None),
    ("Rope", [T([(0, 1.25, 0), (0.15, 0.7, -0.05), (0.1, 0.35, -0.1)], 0.05, segs=4)], RED, "Fabric", None),
])
# 6 the Key to the City: a giant gold key standing tilted in a cushioned stand
key = [TOR(0.55, 0.16, 0, 5.6, 0, axis="z", segs=14, csegs=5), C(0.12, 3.2, 0, 3.6, 0, segs=8),
       B(0.5, 0.18, 0.16, 0.3, 2.3, 0), B(0.38, 0.18, 0.16, 0.25, 2.7, 0), star(0.25, 0.1, 0.06, 0, 5.6, -0.05)]
for p_ in key:
    turn(p_, "z", -12, (0, 2.0, 0))
prop("HqCityKey", [
    ("Gold", key, GOLD, "Foil", None),
    ("Stand", [lathe([(0.9, 0), (0.7, 0.3), (0.45, 0.5), (0.45, 1.6), (0.75, 1.75)], segs=12)], MARBLE, "Marble", None),
    ("Cushion", [RB(1.2, 0.35, 1.2, 0, 1.9, 0, r=0.15, segs=2)], CRIMSON, "Fabric", None),
])
# 7 the Comic Rack: a spinner rack with bright covers on four sides
covers = {0: [], 1: [], 2: []}
for side in range(4):
    for row in range(3):
        for col in range(2):
            c_ = B(0.62, 0.85, 0.05, -0.36 + col * 0.72, 1.4 + row * 1.0, -0.42)
            turn(c_, "up", side * 90)
            covers[(side + row + col) % 3].append(c_)
prop("HqComicRack", [
    ("Wire", [C(0.07, 4.0, 0, 2.1, 0, segs=6), C(0.8, 0.12, 0, 0.1, 0, segs=12)] + [TOR(0.6, 0.03, 0, y, 0, segs=4, csegs=3) for y in (1.0, 2.0, 3.0, 4.0)], STEEL, "Metal", None),
    ("Red", covers[0], RED, None, None),
    ("Yellow", covers[1], YELLOW, None, None),
    ("Blue", covers[2], TOYBLUE, None, None),
])
# 8 the Toy Shelf: a low shelf with a ball, blocks and a little wind-up robot
prop("HqToyShelf", [
    ("Wood", [B(3.2, 0.2, 1.2, 0, y, 0) for y in (0.2, 1.4, 2.6)] + [B(0.2, 2.8, 1.2, x, 1.4, 0) for x in (-1.5, 1.5)], (236, 200, 150), "Wood", None),
    ("Red", [S(0.45, -0.8, 0.75, 0, segs=12, rings=8), B(0.55, 0.55, 0.55, 0.7, 1.78, 0)], TOYRED, None, None),
    ("Blue", [B(0.55, 0.55, 0.55, 1.0, 0.58, 0), B(0.55, 0.55, 0.55, 0.45, 0.58, 0.05), B(0.5, 0.5, 0.5, 0.75, 1.1, 0)], TOYBLUE, None, None),
    ("Tin", [RB(0.6, 0.7, 0.45, -0.7, 1.95, 0, r=0.06, segs=1), B(0.45, 0.4, 0.4, -0.7, 2.5, 0), C(0.05, 0.3, -0.7, 2.85, 0, segs=4),
             TOR(0.15, 0.04, -0.7, 2.05, 0.35, axis="z", segs=6, csegs=3)], STEEL, "Metal", None),
])
# 9 the Ship's Bell: a brass bell on a bracket on a mooring post, with a rope tail
prop("HqShipBell", [
    ("Post", [lathe([(0.6, 0), (0.55, 3.2), (0.65, 3.35), (0.4, 3.5)], segs=10)], DARKWOOD, "Wood", None),
    ("Brass", [B(0.2, 0.2, 1.4, 0, 3.0, -0.9), lathe([(0.55, 1.6), (0.5, 1.7), (0.36, 2.2), (0.3, 2.6), (0.1, 2.75)], 0, 0, -1.5, segs=12)], BRASS, "Metal", None),
    ("Rope", [T([(0, 1.6, -1.5), (0.05, 1.2, -1.55), (0, 0.9, -1.5)], 0.06, segs=4), TOR(0.12, 0.05, 0, 0.85, -1.5, segs=6, csegs=3)], ROPE, "Fabric", None),
])
# 10 the Relic Case (sea relics): a glass case on a plinth with a shell and a little trident
prop("HqSeaCase", [
    ("Plinth", [RB(2.6, 1.6, 2.6, 0, 0.8, 0, r=0.08, segs=2)], (70, 120, 170), None, None),
    ("Glass", [B(2.3, 1.7, 2.3, 0, 2.45, 0)], GLASS, "Glass", 0.65),
    ("Gold", [B(2.45, 0.15, 2.45, 0, 3.35, 0)] + [B(0.12, 1.7, 0.12, sx * 1.15, 2.45, sz * 1.15) for sx in (-1, 1) for sz in (-1, 1)]
     + [C(0.03, 1.2, 0.4, 2.3, 0, segs=4)] + [spike(0.05, 0.35, 0.4 + dx, 2.85, 0) for dx in (-0.15, 0, 0.15)], GOLD, "Metal", None),
    ("Shell", [lathe([(0.02, 1.62), (0.45, 1.75), (0.35, 2.0), (0.02, 2.2)], -0.4, 0, 0, segs=6)], (250, 200, 190), None, None),
])
# 11 the Pigeon Coop: a little wooden coop with a slanted roof, round holes and a pigeon on top
pigeon = [S(0.3, 0.3, 3.55, 0, sc=(1.0, 0.8, 1.4), segs=8, rings=6), S(0.16, 0.3, 3.85, -0.32, segs=8, rings=5)]
prop("HqPigeonCoop", [
    ("Wood", [B(2.6, 2.4, 2.0, 0, 1.6, 0), B(0.2, 0.4, 0.2, -1.1, 0.2, -0.8), B(0.2, 0.4, 0.2, 1.1, 0.2, -0.8), B(0.2, 0.4, 0.2, -1.1, 0.2, 0.8),
              B(0.2, 0.4, 0.2, 1.1, 0.2, 0.8), B(2.0, 0.12, 0.5, 0, 1.15, -1.2)], WOOD, "Wood", None),
    ("Roof", [shift(prism([(-1.35, 2.75), (1.35, 3.25), (1.35, 3.45), (-1.35, 2.95)], -1.5, 1.5), rb(0, 0, 0))], RED, None, None),
    ("Holes", [C(0.28, 0.06, x, 1.85, -1.02, segs=10, axis="z") for x in (-0.6, 0.6)], (40, 30, 26), None, None),
    ("Bird", pigeon, (170, 176, 190), None, None),
])
# 12 the Star Lamp: a brass floor lamp with a glowing star for a shade
prop("HqStarLamp", [
    ("Brass", [lathe([(0.8, 0), (0.6, 0.2), (0.12, 0.3), (0.1, 3.4), (0.2, 3.5)], segs=12)], BRASS, "Metal", None),
    ("Star", [star(0.95, 0.42, 0.45, 0, 4.25, 0)], (255, 226, 110), "Neon", None),
])
# 13 the Parts Rack: a steel rack with robot parts: a dome head, gears and a forearm
prop("HqPartsRack", [
    ("Steel", [B(3.0, 0.15, 1.2, 0, y, 0) for y in (0.3, 1.5, 2.7)] + [B(0.15, 3.2, 0.15, sx * 1.45, 1.6, sz * 0.55) for sx in (-1, 1) for sz in (-1, 1)], STEEL, "Metal", None),
    ("Parts", [S(0.5, -0.7, 3.2, 0, sc=(1, 0.9, 1), segs=10, rings=6), RB(0.9, 0.45, 0.55, 0.8, 1.8, 0, r=0.1, segs=2), C(0.22, 0.9, 0.8, 0.65, 0, segs=8, axis="x")], (90, 96, 110), "Metal", None),
    ("Gold", [gear(0.5, 0.36, 8, 0.15, -0.6, 2.0, 0.0), gear(0.35, 0.25, 7, 0.12, -0.15, 0.62, 0.1), C(0.12, 0.1, -0.85, 3.3, -0.46, segs=6, axis="z")], GOLD, "Metal", None),
    ("Glow", [B(0.6, 0.12, 0.1, -0.7, 3.25, -0.48)], (255, 80, 60), "Neon", None),
])
# 14 the Boss Plate Wall: a free-standing frame holding three cracked boss armour plates with rivets
plates = []
for i, x in enumerate((-1.1, 0, 1.1)):
    pl = face([(-0.45, -0.7), (0.45, -0.7), (0.5, 0.5), (0, 0.8), (-0.5, 0.5)], -0.1, 0.1)
    at(pl, x, 2.6, -0.1)
    plates.append(pl)
prop("HqPlateWall", [
    ("Frame", frame_z(3.8, 3.2, 0.25, 0.4, 0, 2.6, 0.1) + [B(0.3, 1.1, 0.3, x, 0.55, 0.1) for x in (-1.5, 1.5)] + [B(3.6, 0.2, 1.4, 0, 0.1, 0.1)], DARKWOOD, "Wood", None),
    ("Back", [B(3.4, 2.8, 0.1, 0, 2.6, 0.25)], (60, 50, 60), "Fabric", None),
    ("Plates", plates, (120, 130, 150), "Metal", None),
    ("Rivets", rivets([(x + dx, 2.6 + dy, -0.22) for x in (-1.1, 0, 1.1) for (dx, dy) in ((-0.3, -0.5), (0.3, -0.5), (0, 0.45))], r=0.07), GOLD, "Metal", None),
])
# 15 the Core Case: nemesis cores glowing under a glass dome on a pedestal
prop("HqCoreCase", [
    ("Pedestal", [lathe([(1.1, 0), (0.9, 0.3), (0.6, 0.5), (0.6, 1.8), (1.0, 2.0)], segs=12)], (60, 62, 76), "Metal", None),
    ("Dome", [S(0.95, 0, 2.05, 0, sc=(1, 1.1, 1), segs=14, rings=8)], GLASS, "Glass", 0.65),
    ("Cores", [S(0.32, x, 2.4, z, segs=8, rings=6) for (x, z) in ((-0.35, 0.1), (0.35, 0.15), (0, -0.3))], (255, 214, 60), "Neon", None),
    ("Trim", [TOR(1.0, 0.08, 0, 2.05, 0, segs=16, csegs=4)], GOLD, "Metal", None),
])
# 16 the Ribbon Board: a board on legs pinned with contest rosettes
ros = {0: [], 1: [], 2: []}
for i in range(6):
    x, y = -0.9 + (i % 3) * 0.9, 2.8 - (i // 3) * 1.0
    ros[i % 3] += [C(0.32, 0.08, x, y, -0.12, segs=12, axis="z"), face([(-0.15, 0), (0.15, 0), (0.22, -0.6), (0, -0.45), (-0.22, -0.6)], -0.03, 0.03)]
    at(ros[i % 3][-1], x, y - 0.2, -0.14)
prop("HqRibbonBoard", [
    ("Board", [RB(3.2, 2.4, 0.2, 0, 2.4, 0, r=0.06, segs=1)], CORK, "Fabric", None),
    ("Legs", [B(0.2, 3.6, 0.2, x, 1.8, 0.15) for x in (-1.4, 1.4)] + frame_z(3.4, 2.6, 0.15, 0.3, 0, 2.4, 0.0), DARKWOOD, "Wood", None),
    ("Blue", ros[0], TOYBLUE, "Fabric", None),
    ("Red", ros[1], RED, "Fabric", None),
    ("Gold", ros[2], GOLD, "Fabric", None),
])
# 17 the Keepsake Box: a little treasure chest with a heart lock
prop("HqKeepsakeBox", [
    ("Wood", [RB(2.6, 1.4, 1.6, 0, 0.7, 0, r=0.08, segs=2), shift(prism([(-0.8, 1.4), (0.8, 1.4), (0.6, 1.9), (0.0, 2.05), (-0.6, 1.9)], -1.3, 1.3), rb(0, 0, 0))], (176, 96, 140), "Wood", None),
    ("Gold", [B(0.25, 2.1, 1.7, x, 1.0, 0) for x in (-0.9, 0.9)] + [B(2.7, 0.15, 1.7, 0, 1.4, 0)], GOLD, "Metal", None),
    ("Heart", [at(face([(0, -0.3), (0.3, 0.03), (0.27, 0.2), (0.14, 0.27), (0, 0.16), (-0.14, 0.27), (-0.27, 0.2), (-0.3, 0.03)], -0.06, 0.06), 0, 1.3, -0.86)], PINK, None, None),
])
# 18 the Crest Banner: a pennant banner on a pole stand with three crests
ban = face([(-1.0, 1.3), (1.0, 1.3), (1.0, 4.3), (-1.0, 4.3)], -0.04, 0.04)
ban2 = face([(-1.0, 1.3), (0, 0.7), (1.0, 1.3), (1.0, 1.35), (-1.0, 1.35)], -0.04, 0.04)
prop("HqCrestBanner", [
    ("Pole", [C(0.08, 4.8, 0, 2.4, 0.15, segs=6), B(2.4, 0.12, 0.12, 0, 4.4, 0.05), RB(1.4, 0.2, 1.4, 0, 0.1, 0.15, r=0.05, segs=1)], BRASS, "Metal", None),
    ("Cloth", [ban, ban2], (40, 70, 150), "Fabric", None),
    ("Crests", [at(face([(-0.3, 0.25), (0.3, 0.25), (0.3, -0.05), (0, -0.35), (-0.3, -0.05)], -0.06, 0.06), 0, y, -0.08) for y in (3.7, 2.8, 1.9)], GOLD, "Metal", None),
])
# 19 the Season One Poster: a framed poster on a stand: a hero's silhouette leaping across a star burst
burst = star(1.1, 0.6, 0.06, 0, 0, 0, points=8)
fig = face([(-0.2, -0.6), (0.0, -0.1), (0.35, -0.55), (0.45, -0.45), (0.15, 0.05), (0.4, 0.45), (0.55, 0.75), (0.4, 0.8), (0.1, 0.45),
            (-0.2, 0.5), (-0.4, 0.85), (-0.55, 0.75), (-0.25, 0.25), (-0.35, -0.55)], -0.04, 0.04)
prop("HqSeasonPoster", [
    ("Frame", frame_z(2.6, 3.4, 0.2, 0.25, 0, 2.6, 0) + [T([(-0.9, 0, 0.6), (-0.6, 1.0, 0.2)], 0.07, segs=4), T([(0.9, 0, 0.6), (0.6, 1.0, 0.2)], 0.07, segs=4)], GOLD, "Metal", None),
    ("Paper", [B(2.3, 3.1, 0.06, 0, 2.6, 0.05)], (40, 60, 150), None, None),
    ("Burst", [at(burst, 0, 2.8, -0.02)], YELLOW, None, None),
    ("Hero", [at(fig, 0, 2.8, -0.07)], RED, None, None),
])
# 20 the Golden Ticket Booth: a little striped booth with a counter and a giant gold ticket on top
tick = face([(-1.0, -0.45), (1.0, -0.45), (1.0, -0.15), (0.85, 0), (1.0, 0.15), (1.0, 0.45), (-1.0, 0.45), (-1.0, 0.15), (-0.85, 0), (-1.0, -0.15)], -0.06, 0.06)
prop("HqTicketBooth", [
    ("Red", [B(0.5, 3.6, 2.0, x, 1.8, 0.2) for x in (-1.3, 1.3)] + [RB(3.2, 0.6, 2.4, 0, 3.9, 0.2, r=0.1, segs=2)], RED, None, None),
    ("Cream", [B(2.1, 3.6, 0.2, 0, 1.8, 1.1), B(2.1, 1.4, 1.8, 0, 0.7, 0.2), B(2.5, 0.15, 0.6, 0, 1.45, -0.75)], CREAM, None, None),
    ("Gold", [at(tick, 0, 4.85, 0.2), C(0.05, 0.5, 0, 4.3, 0.2, segs=4)], GOLD, "Foil", None),
    ("Bulbs", [S(0.1, x, 4.2, -1.0, segs=6, rings=4) for x in (-1.2, -0.6, 0, 0.6, 1.2)], (255, 236, 160), "Neon", None),
])
# 21 the Spotlight Rig: a stage spotlight on a tripod
prop("HqSpotRig", [
    ("Legs", [T([(math.cos(a) * 1.1, 0, math.sin(a) * 1.1), (0, 2.2, 0)], 0.07, segs=4) for a in (i * 2 * math.pi / 3 + 0.5 for i in range(3))]
     + [C(0.08, 1.2, 0, 2.7, 0, segs=6)], CHARCOAL, "Metal", None),
    ("Can", [C(0.55, 1.4, 0, 3.6, -0.2, segs=12, r2=0.45, axis="z"), TOR(0.62, 0.05, 0, 3.3, 0, segs=10, csegs=3, arc=math.pi)], BLACK, "Metal", None),
    ("Lens", [C(0.48, 0.06, 0, 3.6, -0.92, segs=12, axis="z")], (255, 246, 210), "Neon", None),
])
# 22 the Season One Statue: a little gold hero, fist up, cape out, on a round plinth
st_fig = [RB(0.8, 1.0, 0.5, 0, 2.4, 0, r=0.1, segs=2), S(0.32, 0, 3.2, 0, segs=10, rings=6), RB(0.3, 1.0, 0.3, -0.2, 1.4, 0, r=0.06, segs=1),
          RB(0.3, 1.0, 0.3, 0.2, 1.4, 0.1, r=0.06, segs=1), T([(0.35, 2.75, 0), (0.6, 3.3, 0), (0.6, 3.8, 0)], 0.13, segs=5),
          S(0.18, 0.6, 3.95, 0, segs=6, rings=4), T([(-0.35, 2.75, 0), (-0.6, 2.3, -0.1)], 0.12, segs=5)]
cape_ = face([(-0.4, 2.85), (0.4, 2.85), (0.9, 1.5), (0.2, 1.7), (-0.5, 1.4)], 0.25, 0.32)
prop("HqSeasonStatue", [
    ("Gold", st_fig + [cape_], GOLD, "Foil", None),
    ("Plinth", [lathe([(1.0, 0), (1.0, 0.7), (0.85, 0.8), (0.85, 0.9)], segs=14)], (40, 60, 150), None, None),
    ("Trim", [TOR(0.96, 0.06, 0, 0.75, 0, segs=14, csegs=3), star(0.25, 0.1, 0.05, 0, 0.4, -1.0)], WHITE, None, None),
])


# ================================================================ the reputation tiers' dressing (HqArtKit.DRESS: each
# look's foot is its RepTiers piece's middle, front -z; the glowing screens, LEDs, frames, note icons and the
# captive's eyes and chest bars stay the game's parts, so every mesh keeps behind or round them)
# ---------------------------------------------------------------- the Safehouse
DESK = (40, 44, 56)
prop("HqCorkBoard", [  # the thank-you wall's cork board (26 x 12; the notes hang 0.25 in front)
    ("Cork", [B(26.0, 12.0, 0.4, 0, 0, 0)], CORK, "Fabric", None),
    ("Wood", [B(26.0, 0.6, 0.5, 0, 5.7, -0.05), B(26.0, 0.6, 0.5, 0, -5.7, -0.05), B(0.8, 10.8, 0.5, -12.6, 0, -0.05), B(0.8, 10.8, 0.5, 12.6, 0, -0.05)], DARKWOOD, "Wood", None),
])
note = rings_mesh([[(-1.5, -0.9, 0.04), (1.1, -0.9, 0.04), (1.5, -0.5, 0.04), (1.5, 0.9, 0.04), (-1.5, 0.9, 0.04)],
                   [(-1.5, -0.9, -0.03), (1.1, -0.9, -0.03), (1.5, -0.5, -0.03), (1.5, 0.9, -0.03), (-1.5, 0.9, -0.03)]])
fold = face([(1.1, -0.9), (1.5, -0.5), (1.1, -0.5)], -0.05, -0.03)
prop("HqNote", [  # a thank-you note (3 x 1.8): a folded corner and a red pin at the top (the icon is the game's part)
    ("Paper", [note], PAPER, None, None),
    ("Fold", [fold], (222, 214, 190), None, None),
    ("Pin", [C(0.14, 0.1, 0, 0.68, -0.06, segs=8, axis="z"), S(0.1, 0, 0.68, -0.14, segs=6, rings=4)], RED, None, None),
])
keys = [RB(4.0, 0.2, 1.2, 0, 0.4, -1.2, r=0.05, segs=1)]
prop("HqRigDesk", [  # Patch's desk (14 x 0.6 x 4; the legs 6 either side, the keyboard 1.2 in front)
    ("Top", [RB(14.0, 0.6, 4.0, 0, 0, 0, r=0.08, segs=1)], DESK, "Metal", None),
    ("Legs", [RB(0.6, 2.8, 3.4, x, -1.6, 0, r=0.05, segs=1) for x in (-6, 6)] + [B(11.4, 0.3, 0.2, 0, -2.4, 1.4)], STEEL, "Metal", None),
    ("Keys", keys + [B(0.25, 0.06, 0.25, -1.7 + i * 0.37, 0.53, -1.2 + r * 0.32) for i in range(10) for r in (-1, 0, 1)], (70, 74, 88), None, None),
    ("Bits", [lathe([(0.3, 0.3), (0.32, 1.0)], -4.6, 0, -1.0, segs=10), TOR(0.16, 0.05, -4.25, 0.75, -1.0, axis="z", segs=6, csegs=3),
              RB(0.4, 0.15, 0.6, 2.8, 0.38, -1.2, r=0.06, segs=2)], ORANGE, None, None),
    ("Cables", [T([(x, 0.3, 1.9), (x + 0.3, -1.0, 2.0), (x + 0.6, -2.7, 1.8)], 0.07, segs=4) for x in (-5, -1, 3)], (30, 30, 36), None, None),
])
prop("HqRigMonitor", [  # a monitor round its glowing screen (4.4 x 3.2; the screen 0.2 in front), on a stand to the desk
    ("Bezel", frame_z(4.4, 3.2, 0.32, 0.45, 0, 0, -0.08) + [B(4.2, 3.0, 0.25, 0, 0, 0.02)], DESK, "Metal", None),
    ("Stand", [B(0.4, 0.8, 0.3, 0, -1.9, 0.25), RB(1.6, 0.12, 1.0, 0, -2.25, 0.0, r=0.04, segs=1)], STEEL, "Metal", None),
])
prop("HqServerRack", [  # the server rack (3 x 8 x 3; its LEDs are the game's, 0.05 in front)
    ("Body", [RB(3.0, 8.0, 3.0, 0, 0, 0, r=0.1, segs=1)], DESK, "Metal", None),
    ("Vents", [B(2.4, 0.14, 0.05, 0, y, -1.5) for y in (-3.3, -2.9, -2.5, -2.1, -1.7, 0.6, 2.4)] + [B(0.05, 0.14, 2.2, s_ * 1.5, y, 0) for s_ in (-1, 1) for y in (-2, -1, 0, 1, 2)],
     (24, 26, 32), None, None),
    ("Trim", [B(3.1, 0.2, 3.1, 0, 3.9, 0), B(3.1, 0.2, 3.1, 0, -3.9, 0), C(0.7, 0.08, 0, 4.0, 0, segs=12)], (90, 230, 170), "Neon", None),
])
prop("HqStool", [  # a round stool (2.4 across, 2.4 tall round its middle)
    ("Seat", [RB(2.3, 0.4, 2.3, 0, 1.0, 0, r=0.18, segs=2)], (60, 64, 76), "Fabric", None),
    ("Steel", [C(0.12, 2.0, 0, 0, 0, segs=6)] + [T([(0, -1.0, 0), (math.cos(a) * 1.1, -1.15, math.sin(a) * 1.1)], 0.07, segs=4) for a in (i * 2 * math.pi / 5 for i in range(5))]
     + [TOR(0.55, 0.05, 0, -0.2, 0, segs=10, csegs=3)], STEEL, "Metal", None),
])
glassw = [B(5.6, 5.2, 3.6, 0, 3.6, 0)]
prop("HqRelicCase", [  # the relic display (the plinth 6 x 2 x 4 round its middle, the glass case on it)
    ("Plinth", [RB(6.0, 1.7, 4.0, 0, -0.15, 0, r=0.1, segs=2), RB(6.3, 0.3, 4.3, 0, 0.85, 0, r=0.05, segs=1)], (170, 170, 176), "Concrete", None),
    ("Gold", [B(6.0, 0.3, 4.0, 0, 6.3, 0), B(5.8, 0.14, 3.8, 0, 1.1, 0), B(6.1, 0.16, 4.1, 0, -0.9, 0)] + [B(0.18, 5.2, 0.18, sx * 2.8, 3.6, sz * 1.8) for sx in (-1, 1) for sz in (-1, 1)],
     GOLD, "Metal", None),
    ("Glass", glassw, (200, 230, 255), "Glass", 0.7),
])
cape_rows = []
for j in range(6):
    y = 1.5 - j * 0.6
    w = 0.6 + j * 0.04
    cape_rows.append([(x * w / 0.6, y - (0.18 if (j == 5 and k % 2) else 0), 0.05 * math.sin(k * 1.7)) for k, x in enumerate((-0.6, -0.3, 0.0, 0.3, 0.6))])
cape_m = rings_mesh([[(x, y, z - 0.06) for (x, y, z) in r] + [(x, y, z + 0.06) for (x, y, z) in reversed(r)] for r in cape_rows])
prop("HqRelicCape", [  # the old hero's torn red cape (1.6 x 3), hung from a gold clasp bar
    ("Cloth", [cape_m], (200, 40, 50), "Fabric", None),
    ("Clasp", [B(1.6, 0.16, 0.2, 0, 1.5, 0), S(0.14, -0.6, 1.5, -0.08, segs=6, rings=4), S(0.14, 0.6, 1.5, -0.08, segs=6, rings=4)], GOLD, "Metal", None),
])
shield_crack = [T([(0.3, 1.1, -0.17), (0.05, 0.6, -0.17), (0.35, 0.3, -0.17), (0.1, -0.1, -0.17)], 0.05, segs=4)]
prop("HqRelicShield", [  # the cracked blue shield (2.4 across, facing -z) and its gold chevron (0.2 in front)
    ("Blue", [C(1.2, 0.3, 0, 0, 0, segs=20, axis="z")], (50, 90, 200), "Metal", None),
    ("Rim", [TOR(1.15, 0.1, 0, 0, -0.1, axis="z", segs=20, csegs=4)], (200, 206, 220), "Metal", None),
    ("Gold", [face([(-0.5, -0.4), (0, 0.05), (0.5, -0.4), (0.5, 0.0), (0, 0.4), (-0.5, 0.0)], -0.25, -0.15)], GOLD, "Metal", None),
    ("Crack", shield_crack, (20, 30, 60), None, None),
])
prop("HqRelicHelmet", [  # the dented gold helmet (1.6 x 1.4 x 1.6): a fin crest and a T visor slit
    ("Gold", [S(0.8, 0, 0, 0, sc=(1.0, 0.86, 1.0), segs=14, rings=8), RB(0.18, 0.5, 1.2, 0, 0.6, 0.05, r=0.06, segs=2)], GOLD, "Foil", None),
    ("Slit", [B(0.9, 0.16, 0.1, 0, 0.05, -0.76), B(0.18, 0.5, 0.1, 0, -0.2, -0.77)], (30, 30, 36), None, None),
])
for (L, rod) in (("HqSpotlight", True), ("HqSpotTruss", False)):
    parts = [C(0.95, 1.2, 0, 0, 0, segs=12, r2=0.75), TOR(0.98, 0.08, 0, -0.55, 0, segs=12, csegs=3)]
    yoke = [B(0.15, 1.2, 0.3, s_ * 1.1, 0.3, 0) for s_ in (-1, 1)] + [B(2.35, 0.15, 0.3, 0, 0.9, 0)]
    if rod:  # the Safehouse's hangs on a rod from the ceiling
        yoke.append(C(0.1, 5.4, 0, 3.6, 0, segs=6))
        yoke.append(C(0.5, 0.2, 0, 6.2, 0, segs=8))
    else:  # the Foundry's from a short truss
        for s_ in (-1, 1):
            yoke.append(B(6.0, 0.15, 0.15, 0, 1.8, s_ * 0.4))
        yoke.append(B(6.0, 0.15, 0.15, 0, 2.5, 0))
        for k in range(6):
            yoke.append(T([(-2.7 + k * 1.0, 1.8, -0.4), (-2.2 + k * 1.0, 2.5, 0), (-2.7 + k * 1.0, 1.8, 0.4)], 0.05, segs=3))
        yoke.append(B(0.15, 0.9, 0.15, 0, 1.35, 0))
    prop(L, [("Can", parts, (34, 36, 44), "Metal", None), ("Yoke", yoke, STEEL, "Metal", None)])
ban = rings_mesh([[(-13.0 + k * 26.0 / 12, 1.3, 0.12 * math.sin(k * 0.9)) for k in range(13)] + [(-13.0 + k * 26.0 / 12, -1.3, 0.12 * math.sin(k * 0.9)) for k in reversed(range(13))],
                  [(-13.0 + k * 26.0 / 12, 1.3, 0.12 * math.sin(k * 0.9) + 0.15) for k in range(13)] + [(-13.0 + k * 26.0 / 12, -1.3, 0.12 * math.sin(k * 0.9) + 0.15) for k in reversed(range(13))]])
tails = [face([(-13.0, 1.3), (-14.6, 1.0), (-13.9, 0.0), (-14.6, -1.0), (-13.0, -1.3)], -0.06, 0.08), face([(13.0, 1.3), (14.6, 1.0), (13.9, 0.0), (14.6, -1.0), (13.0, -1.3)], -0.06, 0.08)]
prop("HqThanksBanner", [  # the city's thanks: a gold banner (26 x 2.6) with swallowtail ends and white stars
    ("Gold", [ban], GOLD, "Foil", None),
    ("Tails", tails, (214, 160, 40), "Fabric", None),
    ("Stars", [star(0.6, 0.25, 0.08, x, 0, -0.15 + 0.12 * math.sin((x + 13.0) / (26.0 / 12) * 0.9)) for x in (-9.0, -4.5, 0.0, 4.5, 9.0)], WHITE, None, None),
])
# ---------------------------------------------------------------- the Foundry
bolts = [C(0.3, 0.3, math.cos(a) * 5.3, math.sin(a) * 5.3, -1.35, segs=6, axis="z") for a in (i * math.pi / 6 for i in range(12))]
spokes = [B(4.0, 0.3, 0.3, 0, 0, -1.55), B(0.3, 4.0, 0.3, 0, 0, -1.55), C(0.55, 0.5, 0, 0, -1.55, segs=8, axis="z"), TOR(1.8, 0.15, 0, 0, -1.55, axis="z", segs=16, csegs=4)]
prop("HqVault", [  # the loot vault (frame 16 x 16; the round door 12 across, its wheel 1.5 in front; the gold trim ring the game's)
    ("Frame", [B(16.0, 16.0, 0.8, 0, 0, 0)] + [B(1.4, 2.4, 1.0, -7.2, y, -0.5) for y in (-4.0, 4.0)], (120, 126, 138), "DiamondPlate", None),
    ("Door", [C(6.0, 1.0, 0, 0, -0.8, segs=28, axis="z"), C(4.6, 0.2, 0, 0, -1.35, segs=24, axis="z")], (150, 156, 168), "Metal", None),
    ("Gold", spokes + bolts, GOLD, "Metal", None),
    ("Rivets", rivets([(x, y, -0.45) for x in (-7.4, 7.4) for y in (-7.0, -2.5, 2.5, 7.0)] + [(x, y, -0.45) for y in (-7.4, 7.4) for x in (-4.5, 0.0, 4.5)], r=0.22), (60, 64, 74), "Metal", None),
])
prop("HqGoldBar", [  # a gold ingot (1.1 x 0.8 x 2.2)
    ("Gold", [rings_mesh([[(-0.55, -0.4, -1.1), (0.55, -0.4, -1.1), (0.55, -0.4, 1.1), (-0.55, -0.4, 1.1)],
                          [(-0.38, 0.4, -0.92), (0.38, 0.4, -0.92), (0.38, 0.4, 0.92), (-0.38, 0.4, 0.92)]])], GOLD, "Foil", None),
])
prop("HqBigScreen", [  # the trophy screen's frame (23 x 13; the screen 0.3 in front is the game's), wall brackets
    ("Iron", [B(23.0, 13.0, 0.4, 0, 0, 0)] + frame_z(23.0, 13.0, 1.0, 0.55, 0, 0, -0.2) + [B(1.2, 3.0, 1.2, s_ * 10.6, -7.6, 0.2) for s_ in (-1, 1)], SBLACK, "Metal", None),
    ("Gold", rivets([(x, y, -0.5) for x in (-11.0, -5.5, 0, 5.5, 11.0) for y in (-6.0, 6.0)] + [(s_ * 11.0, y, -0.5) for s_ in (-1, 1) for y in (-3.0, 0.0, 3.0)], r=0.2), GOLD, "Metal", None),
])
prop("HqScreenCrown", [  # the crown on the screen (6 x 4, glowing gold), three jewels on its band
    ("Crown", [crown(6.0, 3.4, 0.2, 0, -2.0, 0)], GOLD, "Neon", None),
    ("Jewels", [C(0.32, 0.12, x, -1.35, -0.12, segs=8, axis="z") for x in (-1.6, 0.0, 1.6)] + [S(0.3, 0, 1.75, -0.05, segs=8, rings=5)], SGLOW, "Neon", None),
])
links = []
for k in range(12):
    lk = TOR(0.32, 0.08, 0, 4.25 - k * 0.72, 0, axis="z" if k % 2 == 0 else "x", segs=10, csegs=4)
    kit.apply_all(lk)
    for v in lk.data.vertices:
        v.co.z = 4.25 - k * 0.72 + (v.co.z - (4.25 - k * 0.72)) * 1.5
    links.append(lk)
hook = TOR(0.55, 0.13, 0, -4.95, 0, axis="z", segs=14, csegs=5, arc=math.pi * 1.4)
turn(hook, "z", 160, (0, -4.95, 0))
prop("HqHookChain", [  # the chain from the ceiling (9 tall) and the hook at its foot (0.2 below)
    ("Steel", links + [hook, spike(0.13, 0.4, -0.48, -5.15, 0, segs=5)], STEEL, "Metal", None),
])
NAVYBOT = (36, 48, 92)
bot = [RB(3.4, 4.0, 2.0, 0, 0, 0, r=0.4, segs=2), RB(2.4, 2.4, 2.4, 0, 3.4, 0, r=0.45, segs=2)]
for s_ in (-1, 1):
    arm = [RB(1.0, 1.7, 1.0, s_ * 2.2, 0.7, 0, r=0.3, segs=2), RB(0.9, 1.7, 0.9, s_ * 2.25, -1.0, 0, r=0.3, segs=2), RB(1.0, 0.6, 1.1, s_ * 2.25, -2.1, -0.05, r=0.2, segs=2)]
    leg = [RB(1.2, 1.7, 1.2, s_ * 0.8, -2.85, 0, r=0.35, segs=2), RB(1.1, 1.6, 1.1, s_ * 0.8, -4.45, 0.0, r=0.3, segs=2), RB(1.1, 0.5, 1.5, s_ * 0.8, -5.35, -0.3, r=0.15, segs=2)]
    for p_ in arm:
        turn(p_, "z", -s_ * 6, (s_ * 2.2, 1.6, 0))
    bot += arm + leg
joints = [C(0.45, 0.6, 0, 2.05, 0, segs=10)] + [S(0.55, s_ * 2.0, 1.5, 0, segs=10, rings=6) for s_ in (-1, 1)] + [S(0.45, s_ * 0.8, -2.0, 0, segs=10, rings=6) for s_ in (-1, 1)]
joints += [B(1.9, 0.6, 0.1, 0, 3.4, -1.18), RB(2.0, 0.5, 0.2, 0, 4.7, 0.6, r=0.05, segs=1)]  # the dead visor band and a dent plate
strap = [T([(0, 5.0, 0), (0.0, 4.9, 1.3), (1.4, 2.3, 1.1), (1.6, 1.7, 0.0), (0.9, 1.9, -1.05), (-0.9, 1.9, -1.05), (-1.6, 1.7, 0.0), (-1.4, 2.3, 1.1), (0.0, 4.9, 1.3)], 0.12, segs=5)]
prop("HqCaptiveBot", [  # the captured robot on the hook (round its torso, 3.4 x 4 x 2): limp, a strap under its arms
    ("Shell", bot, NAVYBOT, "Metal", None),
    ("Joints", joints, (70, 74, 88), "Metal", None),
    ("Strap", strap, ROPE, "Fabric", None),
])
prop("HqCashCrate", [  # a cash crate (3 x 3 x 3): slats, corner braces and bundles of cash peeking out of the top
    ("Wood", [B(2.8, 2.8, 2.8, 0, -0.1, 0)], WOOD, "Wood", None),
    ("Braces", [B(0.3, 3.0, 0.3, sx * 1.4, -0.0, sz * 1.4) for sx in (-1, 1) for sz in (-1, 1)] + [B(3.0, 0.3, 0.3, 0, y, -1.45) for y in (-1.2, 0.6)]
     + [B(0.3, 0.3, 3.0, s_ * 1.45, y, 0) for s_ in (-1, 1) for y in (-1.2, 0.6)], DARKWOOD, "Wood", None),
    ("Cash", [RB(0.9, 0.35, 1.6, x, 1.42 + (i % 2) * 0.32, z, r=0.05, segs=1) for i, (x, z) in enumerate(((-0.7, -0.4), (0.3, 0.5), (0.6, -0.5), (-0.4, 0.6)))], CASH, None, None),
    ("Bands", [B(0.95, 0.38, 0.25, x, 1.42 + (i % 2) * 0.32, z) for i, (x, z) in enumerate(((-0.7, -0.4), (0.3, 0.5), (0.6, -0.5), (-0.4, 0.6)))], PAPER, None, None),
])
prop("HqCarpet", [  # the kingpin's red carpet (8 x 0.1 x 12): gold edges and tassels at the ends
    ("Red", [B(8.0, 0.1, 12.0, 0, 0, 0)], SRED, "Fabric", None),
    ("Gold", [B(0.4, 0.04, 12.0, s_ * 3.4, 0.07, 0) for s_ in (-1, 1)] + [C(0.12, 0.08, x, 0.0, s_ * 6.1, segs=5) for x in (-3.2, -1.6, 0.0, 1.6, 3.2) for s_ in (-1, 1)], GOLD, "Fabric", None),
])


LAY_PATH = os.path.join(kit.ROOT, "export", "hq", "layout.json")
assert os.path.exists(LAY_PATH), "run `lune run art/hq/layout.luau` first (the WANTED wall's sizes come from the game)"
LAYOUT = json.load(open(LAY_PATH))
for tag in ("V", "S"):
    st = STYLE[tag]
    trophy_wall(st)
    plaque(st)
    wanted_board(st, LAYOUT["wanted"])
    mount(st)
    plinth(st)


# ================================================================ the fit table and the export (as setpieces.py's)
_mine = {o.name for look in LOOKS.values() for o in look.values()}
_stray = [o.name for o in bpy.context.scene.objects if o.type == "MESH" and o.name not in _mine]
assert not _stray, "every shape built belongs to a mesh: " + ", ".join(_stray[:8])


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


TRIS = {}
rows = []
total = 0
for look in sorted(LOOKS):
    rows.append("\t%s = {" % look)
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        TRIS[name] = t
        total += t
        rgb, mat, alpha = INFO[name]
        extra = (", alpha = %g" % alpha) if alpha else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat,
                       extra, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/hq.py: do not edit by hand.",
    "-- The HQ rooms in Blender meshes (ReplicatedStorage.Art.Hq; Shared.HqArtKit says where each look goes, HqClient",
    "-- draws them): look -> mesh -> its size and its centre from the look's foot point, in studs (x, up, z; front at",
    "-- -z), its colour, material, transparency and triangles. A shape (HqArtKit.SHAPES) is stretched over its part;",
    "-- HqDummyBody's 15 meshes are the training dummy's R15 parts (NpcRig look \"Hq\"), each filling its part's box.",
    "-- %d meshes in %d looks, %d triangles." % (len(INFO), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "HqArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)
print("hq: %d looks, %d meshes, %d tris" % (len(LOOKS), len(INFO), total))
for look in sorted(LOOKS):
    print("  %-16s %5d tris  %2d meshes" % (look, sum(TRIS[n] for n in LOOKS[look]), len(LOOKS[look])))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Hq.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

# ================================================================ previews
if "--preview" in sys.argv:
    FAST = "--fast" in sys.argv
    ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    for look in LOOKS.values():
        for ob in look.values():
            ob.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 8 if FAST else 32
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = (560, 350) if FAST else (760, 475)
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.34, 0.38, 0.48, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(10)
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(-150))
    sc.collection.objects.link(sun)

    def lin(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    MATS = {}
    ROUGH = {"Wood": 0.7, "Fabric": 0.9, "Glass": 0.05, "Metal": 0.35, "Foil": 0.2, "DiamondPlate": 0.4, "SmoothPlastic": 0.45, "Marble": 0.3}

    def mat(rgb, kind="SmoothPlastic", alpha=0.0):
        key = (tuple(int(c) for c in rgb), kind, round(alpha, 2))
        if key in MATS:
            return MATS[key]
        m = bpy.data.materials.new("m%d" % len(MATS))
        m.use_nodes = True
        p = m.node_tree.nodes["Principled BSDF"]
        col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
        p.inputs["Base Color"].default_value = col
        p.inputs["Roughness"].default_value = ROUGH.get(kind, 0.5)
        if kind in ("Metal", "Foil", "DiamondPlate"):
            p.inputs["Metallic"].default_value = 0.35
        if kind == "Neon":
            p.inputs["Emission Color"].default_value = col
            p.inputs["Emission Strength"].default_value = 2.5
        if alpha > 0:
            p.inputs["Alpha"].default_value = max(0.05, 1 - alpha)
        MATS[key] = m
        return m

    SHOWN = []

    def keep(o):
        o.hide_render = False
        SHOWN.append(o)
        return o

    def clear():
        for o in SHOWN:
            bpy.data.objects.remove(o, do_unlink=True)
        SHOWN.clear()

    def frame(at_, ry=0.0):
        return Matrix.Translation(Vector(rb(*at_))) @ Matrix.Rotation(math.radians(ry), 4, "Z")

    def place_look(look, at_, ry=0.0, tint=None, M0=None):
        M = (M0 or Matrix.Identity(4)) @ frame(at_, ry)
        tint = tint or {}
        for name, ob in LOOKS[look].items():
            rgb, kind, alpha = INFO[name]
            cp = keep(copy(ob))
            cp.matrix_world = M
            cp.data.materials.clear()
            cp.data.materials.append(mat(tint.get(name, rgb), kind, alpha))

    def draw_box(size, at_, rgb, kind="SmoothPlastic", alpha=0.0, shape=None, ry=0.0, rz=0.0, M0=None):
        sx, sy, sz = size
        if shape == "Ball":
            ob = kit.sphere("bx", r=0.5, segs=12, rings=8)
            kit.apply_all(ob)
            for v in ob.data.vertices:
                v.co = Vector((v.co.x * sx, v.co.y * sz, v.co.z * sy))
        elif shape == "Cylinder":  # Roblox's cylinder runs along its x
            ob = kit.cyl("bx", 0.5, 0.5, 1.0, segs=16, axis="X")
            kit.apply_all(ob)
            for v in ob.data.vertices:
                v.co = Vector((v.co.x * sx, v.co.y * sz, v.co.z * sy))
        else:
            ob = kit.box("bx", sx, sz, sy)
        if rz:
            turn(ob, "z", rz)
        if ry:
            turn(ob, "up", ry)
        ob.matrix_world = (M0 or Matrix.Identity(4)) @ Matrix.Translation(Vector(rb(*at_)))
        keep(ob).data.materials.append(mat(rgb, kind, alpha))
        return ob

    def fill(shape_meshes, size, at_, M0=None, rgb=None, kind=None, rz=0.0, ry=0.0):
        """HqArtKit.fill: the shape's meshes stretched so their joint box is the part's box."""
        bs = [bounds(LOOKS_BY_MESH[n]) for n in shape_meshes]
        lo = Vector((min(b[0].x for b in bs), min(b[0].y for b in bs), min(b[0].z for b in bs)))
        hi = Vector((max(b[1].x for b in bs), max(b[1].y for b in bs), max(b[1].z for b in bs)))
        c = (lo + hi) / 2
        span = hi - lo
        want = Vector((size[0], size[2], size[1]))
        S_ = Matrix.Diagonal((want.x / max(span.x, 1e-3), want.y / max(span.y, 1e-3), want.z / max(span.z, 1e-3), 1))
        R = Matrix.Rotation(math.radians(ry), 4, "Z") @ Matrix.Rotation(-math.radians(rz), 4, "Y")
        M = (M0 or Matrix.Identity(4)) @ Matrix.Translation(Vector(rb(*at_))) @ R @ S_ @ Matrix.Translation(-c)
        for n in shape_meshes:
            rgb0, kind0, alpha = INFO[n]
            cp = keep(copy(LOOKS_BY_MESH[n]))
            cp.matrix_world = M
            cp.data.materials.clear()
            cp.data.materials.append(mat(rgb or rgb0, kind or kind0, alpha))

    LOOKS_BY_MESH = {n: ob for look in LOOKS.values() for n, ob in look.items()}

    def ground(size, rgb=(110, 112, 120), at_=(0, 0, 0), kind="Concrete"):
        g = keep(kit.box("ground", size, size, 0.4, at=(at_[0], -at_[2], at_[1] - 0.2)))
        g.data.materials.append(mat(rgb, kind))

    def scale_hero(x, y, z, yaw=0):
        for (o, rgb) in hero(x, y, z, yaw):
            keep(o).data.materials.append(mat(rgb))

    # ---------------------------------------------------------------- the pieces as the game draws them today
    SIDE = {"V": "hero", "S": "villain"}

    def rgbof(c):
        return tuple(c)

    def today_station(tag, name, at_):
        col = LAYOUT["colors"][SIDE[tag]]
        draw_box((10, 0.4, 10), (at_[0], 0.4, at_[2]), rgbof(col["main"]), "Neon", 0.4)
        draw_box((1.2, 3.2, 1.2), (at_[0], 2.2, at_[2]), rgbof(col["trim"]))

    WALL = LAYOUT["wanted"]

    def wall_M(tag):
        """The WANTED wall's frame in the cell (its foot, turned to face the room)."""
        return frame((WALL["wall"][0], 0, WALL["wall"][1]), WALL["yaw"])

    def wanted(tag, dressed, M0, heads=True):
        b, s = WALL["board"], WALL["poster"]
        if dressed:
            place_look("HqWantedBoard" + tag, b["at"], 0, M0=M0)
        else:
            draw_box(b["size"], b["at"], (120, 78, 44), "Wood", M0=M0)
            for p in WALL["pins"]:
                draw_box((0.35, 0.35, 0.35), p, (200, 40, 40), shape="Ball", M0=M0)
        draw_box(s["size"], s["at"], (236, 220, 180), "Fabric", M0=M0)  # the paper (the game's part)
        draw_box((s["size"][0] * 0.86, 1.1, 0.02), (s["at"][0], s["at"][1] + 3.15, s["at"][2] - 0.06), (150, 30, 30), M0=M0)
        draw_box((s["size"][0] * 0.7, 3.2, 0.02), (s["at"][0], s["at"][1] + 0.6, s["at"][2] - 0.06), (214, 196, 156), M0=M0)
        for r, (m, pl) in enumerate(zip(WALL["mounts"], WALL["plates"])):
            full = r < 4
            if dressed:
                place_look("HqMount" + tag, m["at"], 0, M0=M0)
                place_look("HqNamePlate", pl["at"], 0, M0=M0, tint=None if full else {"HqNamePlateBody": (110, 100, 90)})
            else:
                draw_box(m["size"], m["at"], (120, 78, 44) if full else (70, 58, 48), "Wood", M0=M0)
                draw_box(pl["size"], pl["at"], (255, 200, 60) if full else (110, 100, 90), "Foil", M0=M0)
            if not (full and heads):
                continue
            for p in WALL["heads"][r]:
                shp = SHAPE_OF.get(p["name"])
                if dressed and shp:
                    fill(shp, p["size"], p["at"], M0=M0, rgb=tuple(p["rgb"]), kind=p["mat"], rz=math.degrees(p["rz"]))
                else:
                    draw_box(p["size"], p["at"], tuple(p["rgb"]), p["mat"], 0.35 if p["mat"] == "Glass" else 0.0, p.get("shape"),
                             rz=math.degrees(p["rz"]), M0=M0)

    SHAPE_OF = {"skull": ["HqNemSkull"], "faceplate": ["HqNemFace"], "jaw": ["HqNemJaw"], "horn": ["HqNemHorn"], "spike": ["HqNemSpike"],
                "visor": ["HqNemVisor"], "chest": ["HqNemChest"], "shoulders": ["HqNemShoulders"], "cape": ["HqNemCape"]}

    def trophies(tag, dressed, at_=None, filled=(1, 2, 3, 4, 5, 6, 7)):
        bx, by, bz = at_ or LAYOUT["trophy"]
        col = LAYOUT["colors"][SIDE[tag]]
        if dressed:
            place_look("HqTrophyWall" + tag, (bx, by, bz), 0)
        for i in range(12):
            colm, row = i % 4, i // 4
            p = (bx + (colm - 1.5) * 4.2, 4 + row * 3.6, bz)
            full = (i + 1) in filled
            body = col["main"] if full else col["trim"]
            if dressed:
                place_look("HqPlaque" + tag, p, 0, tint={"HqPlaque%sBody" % tag: tuple(body)})
                if full:
                    place_look(["HqTrophyCup", "HqTrophyStar", "HqTrophyMedal"][i % 3], (p[0], p[1] + 0.2, p[2] - 0.6), 0)
            elif i < 3 or full:
                draw_box((3.6, 3, 0.4), p, tuple(body), "Foil" if full else "SmoothPlastic")
                if full:
                    draw_box((1.4, 1.2, 1.2), (p[0], p[1] + 0.2, p[2] - 0.6), (255, 200, 60), shape="Cylinder", rz=90)

    DUMMY_COLS = {
        "V": {"body": (232, 236, 246), "limb": (150, 176, 226), "end": VBLUE},
        "S": {"body": (78, 70, 88), "limb": (120, 112, 128), "end": SRED},
    }
    RIG_CENTRES = {"Head": 4.61, "UpperTorso": 3.2, "LowerTorso": 2.2, "LeftUpperArm": 3.575, "RightUpperArm": 3.575, "LeftLowerArm": 2.725,
                   "RightLowerArm": 2.725, "LeftHand": 2.15, "RightHand": 2.15, "LeftUpperLeg": 1.575, "RightUpperLeg": 1.575,
                   "LeftLowerLeg": 0.725, "RightLowerLeg": 0.725, "LeftFoot": 0.15, "RightFoot": 0.15}
    RIG_X = {"Left": -1.5, "Right": 1.5}

    def dummy(tag, at_, dressed, big=False):
        s_ = 2.6 if big else 1.0
        x0, y0, z0 = at_
        cols = DUMMY_COLS[tag]
        if dressed:
            fill(["HqDummyBase", "HqDummyBolts"], (3 * s_, 0.6, 3 * s_), (x0, y0 + 0.3, z0))
        else:
            draw_box((3 * s_, 0.6, 3 * s_), (x0, y0 + 0.3, z0), (60, 64, 76))
        for name, cy in RIG_CENTRES.items():
            sz = RIG[name]
            x = 0.0
            for side_, sx in RIG_X.items():
                if name.startswith(side_):
                    x = sx if ("Arm" in name or "Hand" in name) else sx / 3
            at2 = (x0 + x * s_, y0 + 0.6 + cy * s_, z0)
            size = (sz[0] * s_, sz[1] * s_, sz[2] * s_)
            rgb = cols["body"] if "Torso" in name or name == "Head" else (cols["end"] if ("Hand" in name or "Foot" in name) else cols["limb"])
            if not dressed:
                rgb = (90, 94, 110) if (big and "Arm" in name) else (150, 156, 170)
            if dressed:
                fill([name], size, at2, rgb=rgb, kind="Metal")
            else:
                draw_box(size, at2, rgb, "Metal")
        hy = y0 + 0.6 + 4.61 * s_
        cy = y0 + 0.6 + 3.2 * s_
        vis = (1.194 * 0.7 * s_, 1.277 * 0.18 * s_, 0.2)
        tgt = (0.2, 1.6 * 0.8 * s_, 1.6 * 0.8 * s_)
        eye = (255, 120, 60) if big else (120, 220, 255)
        if dressed:
            fill(["HqDummyVisor"], vis, (x0, hy + 1.277 * 0.08 * s_, z0 - 0.597 * s_), rgb=eye)
            fill(["HqDummyTarget", "HqDummyRings"], tgt, (x0, cy, z0 - 0.5 * s_ - 0.05), ry=90)
        else:
            draw_box(vis, (x0, hy + 1.277 * 0.08 * s_, z0 - 0.597 * s_), eye, "Neon")
            draw_box(tgt, (x0, cy, z0 - 0.5 * s_ - 0.05), (230, 70, 60), "Neon", shape="Cylinder", ry=90)

    def room(tag, dressed, focus=None):
        """One side's whole HQ as the game draws it (every station, 12 trophies, every prop, the top dressing tier,
        the WANTED wall with four heads, five statues' plinths and the dummies), today's parts or the meshes."""
        side = LAYOUT["sides"][SIDE[tag]]
        col = LAYOUT["colors"][SIDE[tag]]
        half = LAYOUT["size"] / 2
        if tag == "V":
            for p in LAYOUT["hideout"]:
                if focus is None and (p["name"] in ("ceiling", "shaft", "beam") or p["at"][2] < -half + 6 or p["at"][0] < -half + 6):
                    continue  # (the ceiling, beams, north and west walls left out so the camera sees in)
                draw_box(p["size"], p["at"], tuple(p["rgb"]), p["mat"], 0.0, None, rz=p["rz"])
        else:
            draw_box((LAYOUT["size"] - 8, 0.2, LAYOUT["size"] - 8), (0, 0.15, 0), tuple(col["trim"]))
            draw_box((LAYOUT["size"] - 24, 0.25, LAYOUT["size"] - 24), (0, 0.2, 0), tuple(col["main"]))
            for i in range(4):
                a = i * 90
                if focus is None and i in (0, 1):
                    continue
                w = draw_box((LAYOUT["size"], 30, 2), (0, 15, -half), tuple(col["trim"]), "Concrete")
                band = draw_box((LAYOUT["size"] - 10, 6, 0.5), (0, 18, -half + 1.2), tuple(col["main"]), "Neon", 0.3)
                for o in (w, band):
                    o.matrix_world = Matrix.Rotation(math.radians(a), 4, "Z") @ o.matrix_world
        # the stations
        for name, (x, z) in LAYOUT["stations"].items():
            if dressed:
                pass
            else:
                today_station(tag, name, (x, 0, z))
        if dressed:
            for p in side["places"]:
                lk = p["look"]
                if lk.startswith("HqPlaque") or lk.startswith("HqTrophy") or lk.startswith("HqWanted") or lk.startswith("HqMount") or lk == "HqNamePlate":
                    continue  # (drawn below with their tints and heads)
                place_look(lk, p["at"], p["ry"])
        else:
            for b in side["boxes"]:
                if b["name"] == "prop":
                    draw_box(b["size"], b["at"], (120, 180, 110))
        # the dressing's own parts that stay (screens, LEDs, frames, icons, eyes)
        hidden = {i for i, b in enumerate(side["boxes"]) if b.get("art")}
        dress_boxes = [b for b in side["boxes"] if b["name"] not in ("pad", "post", "plaque", "cup", "plinth", "prop", "board", "pin", "mount", "plate")]
        for b, p in zip(dress_boxes, side["dressing"]):
            if dressed and b.get("art"):
                continue
            draw_box(p["size"], p["at"], tuple(p["rgb"]), p["mat"], p["clear"], p.get("shape"), ry=p["ry"], rz=p["rz"])
        trophies(tag, dressed)
        wanted(tag, dressed, wall_M(tag))
        for (x, z, a) in LAYOUT["statues"]:
            if dressed:
                place_look("HqPlinth" + tag, (x, 0, z), a)
            else:
                draw_box((5, 2, 5), (x, 1, z), (120, 120, 130), "Slate", ry=a)
            draw_box((2, 5, 1), (x, 4.5, z), (196, 190, 178), "Marble", ry=a)  # (the marble hero copy, roughly)
        for d in LAYOUT["dummies"]:
            dummy(tag, d, dressed)
        dummy(tag, LAYOUT["sim"], dressed, big=True)
        return hidden

    made = []
    SHOTS = ["stations_V", "stations_S", "trophies_V", "trophies_S", "wanted_V", "wanted_S", "dummies", "props", "notes_V", "rig_V",
             "relics_V", "vault_S", "screen_S", "captive_S", "room_V", "room_S", "room_today_V"]
    DRESS_CAMS = {
        "notes_V": ((-34, 10, 36), (-41, 10, 58), 34), "rig_V": ((34, 9, 40), (42, 5, 55), 34), "relics_V": ((28, 8, -3), (20, 4.5, 7), 32),
        "vault_S": ((-34, 9, 34), (-41, 7, 57), 36), "screen_S": ((48, 9, 38), (40, 11, 58), 40), "captive_S": ((-12, 13, -10), (-20, 15, 8), 34),
    }
    CAPTIONS = {
        "stations_V": "The Safehouse's station consoles", "stations_S": "The Foundry's station consoles",
        "trophies_V": "Trophy Wall (Vigil): 7 of 12 filled", "trophies_S": "Trophy Wall (Syndicate)",
        "wanted_V": "WANTED board, mounts, nemesis heads (Vigil)", "wanted_S": "WANTED board and mounts (Syndicate)",
        "dummies": "Training dummies and the boss sim (Vigil, Syndicate)", "props": "The 22 thank-you, collection and pass props",
        "notes_V": "Safehouse rank 1 and 5: thank-you wall, banner", "rig_V": "Safehouse rank 2: Patch's hacking rig",
        "relics_V": "Safehouse rank 3 and 4: the relic case", "vault_S": "Foundry rank 1 and 4: the loot vault",
        "screen_S": "Foundry rank 2 and 5: trophy screen, carpet", "captive_S": "Foundry rank 3: the captured robot",
        "room_V": "The Safehouse, everything shown", "room_S": "The Foundry, everything shown",
        "room_today_V": "The Safehouse today (plain parts)", "room_today_S": "The Foundry today (plain parts)",
    }
    STATION_ORDER = ["command", "gizmo", "mannequins", "training", "trophies", "legends", "scanner", "exit"]
    for shot in SHOTS:
        if ONLY and ONLY not in shot:
            continue
        tag = shot[-1]
        if shot.startswith("stations_"):
            ground(120, (70, 72, 82) if tag == "V" else (52, 46, 56))
            for i, name in enumerate(STATION_ORDER):
                x, z = (i % 4 - 1.5) * 12, (i // 4) * 13 - 6
                place_look("HqPad" + tag, (x, 0, z), 0)
                place_look("Hq%s%s" % ({"command": "Command", "gizmo": "Bench", "mannequins": "Mannequin", "training": "Training",
                                        "trophies": "Lectern", "legends": "Legends", "scanner": "Scanner", "exit": "Exit"}[name], tag), (x, 0, z), 0)
            scale_hero(-23, 0, -12, yaw=200)
            cam = ((8, 17, -36), (0, 2.6, 1), 33)
        elif shot.startswith("trophies_"):
            ground(120, (70, 72, 82) if tag == "V" else (52, 46, 56))
            trophies(tag, True, at_=(0, 0, 0))
            today = Matrix.Translation(Vector(rb(26, 0, 0)))
            scale_hero(-8, 0, -6, yaw=200)
            cam = ((12, 10, -34), (0, 8, 0), 30)
        elif shot.startswith("wanted_"):
            ground(120, (70, 72, 82) if tag == "V" else (52, 46, 56))
            M0 = frame((0, 0, 0), 0)
            draw_box((24, 18, 1), (0, 9, 0.55), (150, 150, 156) if tag == "V" else (40, 36, 44), "Concrete")
            wanted(tag, True, M0)
            scale_hero(-6, 0, -5, yaw=200)
            if tag == "V":  # and the poster's bust (its ViewportFrame) beside it, in fill shapes
                B0 = frame((11, 4.5, -2), 25)
                for p in WALL["bust"]:
                    shp = SHAPE_OF.get(p["name"])
                    if shp:
                        fill(shp, p["size"], p["at"], M0=B0, rgb=tuple(p["rgb"]), kind=p["mat"], rz=math.degrees(p["rz"]))
                    else:
                        draw_box(p["size"], p["at"], tuple(p["rgb"]), p["mat"], 0.0, p.get("shape"), ry=p["ry"], rz=math.degrees(p["rz"]), M0=B0)
            cam = ((7, 9, -26), (2, 8.5, 0), 34)
        elif shot == "dummies":
            ground(120, (70, 72, 82))
            for i, tg in enumerate(("V", "V", "S", "S")):
                dummy(tg, ((i - 1.5) * 7 - 4, 0, 0), True)
            dummy("V", (16, 0, 6), True, big=True)
            dummy("S", (-30, 0, 0), False)
            cam = ((4, 9, -36), (0, 4.5, 0), 34)
        elif shot == "props":
            ground(160, (70, 72, 82))
            for i, bit in enumerate(range(1, 23)):
                x, z = (i % 6 - 2.5) * 7, (i // 6) * 7 - 10
                look = ["HqCafeSign", "HqFern", "HqMapTable", "HqThanksEasel", "HqRescueBell", "HqCityKey", "HqComicRack", "HqToyShelf", "HqShipBell", "HqSeaCase",
                        "HqPigeonCoop", "HqStarLamp", "HqPartsRack", "HqPlateWall", "HqCoreCase", "HqRibbonBoard", "HqKeepsakeBox", "HqCrestBanner",
                        "HqSeasonPoster", "HqTicketBooth", "HqSpotRig", "HqSeasonStatue"][i]
                place_look(look, (x, 0, z), 0)
            scale_hero(-21, 0, -15, yaw=200)
            cam = ((8, 22, -40), (0, 1.0, 1), 36)
        elif shot in DRESS_CAMS:
            room(tag, True, focus="dress")
            cam = DRESS_CAMS[shot]
        else:
            room(tag, not shot.startswith("room_today"))
            cam = ((-66, 64, -66), (4, 0, 8), 34)
        frm, to, lens = cam
        cm = keep(kit.camera(rb(*frm), rb(*to), lens=lens))
        cm.data.clip_end = 3000
        if shot.startswith("room") or shot in DRESS_CAMS:
            for (lx, lz) in ((-30, -30), (30, -30), (-30, 30), (30, 30), (0, 0)):
                pl = bpy.data.objects.new("pl", bpy.data.lights.new("pl", "POINT"))
                pl.data.energy = 2500
                pl.data.shadow_soft_size = 4
                pl.location = rb(lx, 24, lz)
                sc.collection.objects.link(pl)
                SHOWN.append(pl)
        out = os.path.join(kit.ROOT, "preview", "hq_%s.png" % shot)
        kit.render(out)
        made.append((shot, out))
        clear()
    if not ONLY:
        args = json.dumps([[CAPTIONS[s_], p_] for (s_, p_) in made])
        sheet = os.path.join(kit.ROOT, "preview", "hq.png")
        code = (
            "import json,sys\n"
            "from PIL import Image, ImageDraw, ImageFont\n"
            "shots=json.loads(sys.argv[1]); out=sys.argv[2]\n"
            "ims=[Image.open(p).convert('RGB') for _,p in shots]\n"
            "w,h=ims[0].size; cols=4; rows=(len(ims)+cols-1)//cols; bar=44\n"
            "sheet=Image.new('RGB',(cols*w,rows*(h+bar)),(24,26,32)); d=ImageDraw.Draw(sheet)\n"
            "try:\n f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',22)\n"
            "except Exception:\n f=ImageFont.load_default()\n"
            "for i,(im,(cap,_)) in enumerate(zip(ims,shots)):\n"
            " x=(i%cols)*w; y=(i//cols)*(h+bar); sheet.paste(im,(x,y+bar)); d.text((x+14,y+8),cap,fill=(255,236,150),font=f)\n"
            "sheet.save(out)\n"
        )
        subprocess.run(["python3", "-c", code, args, sheet], check=True)
        for (_, p_) in made:
            os.remove(p_)
        print("preview:", sheet)
