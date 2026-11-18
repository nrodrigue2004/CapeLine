# art/store/store2.py: the store art refresh (overnight queue item 13, 2026-11-18): new icon variants and
# thumbnails with the newer villains and bosses, in the first set's style (art/store/icons.py, thumbs.py: the
# game's own meshes posed for a poster, Freestyle ink on the figures, effects-library cards, then post2.py's grade,
# speed lines and captions). Renders into art/export/store2/raw/; art/store/post2.py finishes them.
# Icons (1024 x 1024 renders, 512 x 512 files, no text), one hook each for the A/B test:
#   maw:   the Anime hero (white spikes, gold aura) flying a gold blast into the Lumen Maw's glowing jaws at night.
#   fake:  the twist up close: the Comic hero's fist landing on Radiant's face, cracked half open to the robot
#          beneath, its red eye glowing.
#   titan: the boss hook (Store Page icon 3): the Comic hero rising at the camera, fist first, in front of
#          Rustjaw Prime's face, its eyes red (phase 3), sparks, a sunset.
# Thumbnails (1920 x 1080):
#   maw:   the Lumen Maw lunging out of the Old Quarry at night (its arena), light pulled into its jaws, the
#          generators glowing red round the pit, a squad diving in. Caption GIANT WORLD BOSSES.
#   deep:  the Leviathan Engine bursting out of the sea at the Trench (its arena, at the water's surface), spray,
#          the Comic hero's Volt lightning on its head, Brightharbor on the horizon. Caption FROM THE DEEP.
#   fakes: the famous fakes (Bulwark, Radiant, Skylance) posing as heroes on a Downtown roof, Radiant's face cracked
#          to the metal and a red eye. Caption SPOT THE FAKE.
#   giant: Wind-Up Lane's finale in the Suburbs: the Wind-Up Giant stomping down the street, the Bramblebeast and
#          the Voidhound (the other finale creatures) behind it, the Comic hero leaping in. Caption TOPPLE THE GIANT.
# Run: python art/store/store2.py <icon_maw|icon_fake|icon_titan|thumb_maw|thumb_deep|thumb_fakes|thumb_giant>
#      [--draft]   (with the `bpy` module, Blender 5.0; or bash art/store/make2.sh)
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import cast as K  # noqa: E402
from icons import ANIME, COMIC  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

C.OUT = os.path.join(C.ART, "export", "store2")
C.RAW = os.path.join(C.OUT, "raw")
WHICH = [a for a in sys.argv[1:] if not a.startswith("-")]
WHICH = WHICH[0] if WHICH else "icon_maw"
NOCITY = bool(os.environ.get("STORE_NOCITY"))  # quick pose checks without the city
ICON = (1024, 1024)
THUMB = (1920, 1080)


def outlines(coll_names, thickness=2.0):
    """common.outlines, but the face decal planes leave the outlined collections first: Freestyle draws a flat plane's
    open edges as a thin box round the face, which shows in close-ups."""
    faces = C.collection("Faces")
    for name in coll_names:
        for ob in list(C.collection(name).objects):
            if ob.type == "MESH" and any(m and re.match(r"^face(\.\d+)?$", m.name) for m in ob.data.materials):
                C.put(ob, faces)
    C.outlines(coll_names, thickness=thickness)


def frame(cam):
    """The camera's forward, right and up vectors."""
    R = cam.rotation_euler.to_matrix()
    return (R @ Vector((0, 0, -1))).normalized(), (R @ Vector((1, 0, 0))).normalized(), (R @ Vector((0, 1, 0))).normalized()


def tilt(cam, degrees):
    """Rolls a camera about its view axis (a Dutch angle). common.camera's roll reads matrix_world before the
    scene updates, so it is done here from the rotation itself."""
    m = cam.rotation_euler.to_matrix() @ Matrix.Rotation(math.radians(degrees), 3, "Z")
    cam.rotation_euler = m.to_euler()
    return cam


def on_screen(cam, sx, sy, depth, aspect=1.0):
    """A world point at screen (sx, sy in -1..1) and depth studs in front of the camera (from its lens)."""
    f, r, u = frame(cam)
    half = 18.0 / cam.data.lens  # 36 mm sensor width
    hx, hy = half, half / aspect
    if aspect < 1:
        hx, hy = half * aspect, half
    return cam.location + f * depth + r * (sx * hx * depth) + u * (sy * hy * depth)


def beam(a, b, rgb, r0=0.4, r1=0.9, strength=3.0):
    ob = C.kit.tube_along("beam", [Vector(a), Vector(a).lerp(Vector(b), 0.5), Vector(b)], [r0, (r0 + r1) / 2, r1], segs=10)
    ob.data.materials.append(C.glow_mat("beam", rgb, strength, additive=True))
    ob.visible_shadow = False
    return C.put(ob, C.collection("Fx"))


def core_beam(a, b, rgb, width=0.5, strength=6.0):
    """A blast: a white-hot core in a coloured halo."""
    beam(a, b, (255, 255, 250), width * 0.35, width * 0.5, strength * 1.4)
    return beam(a, b, rgb, width, width * 1.6, strength * 0.4)


def trail(points, rgb, width=0.5, strength=0.9):
    pts = [Vector(p) for p in points]
    radii = [width * (1 - i / (len(pts) - 1)) ** 0.7 for i in range(len(pts))]
    ob = C.kit.tube_along("trail", pts, radii, segs=8)
    ob.data.materials.append(C.glow_mat("trail", rgb, strength, additive=True))
    ob.visible_shadow = False
    return C.put(ob, C.collection("Fx"))


def stars(cam, count=160, seed=1, depth=3000, aspect=1.0, below=-0.2):
    """A night sky's stars: small glow cards far behind everything, upper part of the frame."""
    rng = random.Random(seed)
    m = C.card_mat("star", "star.png", (230, 240, 255), strength=5.0)
    for _ in range(count):
        sx, sy = rng.uniform(-1.1, 1.1), rng.uniform(below, 1.1)
        C.billboard("star", m, on_screen(cam, sx, sy, depth, aspect), depth * rng.uniform(0.003, 0.008), cam)


def flyer(p, aim_at, k, cam, scale=2.0, suit=None, legs=None, capec=None, trc=None, attack=None, rng=None):
    """A squad hero flying at a target with a trail behind; attack: 'beam' or 'bolt' from the fist."""
    rng = rng or random.Random(k)
    to = (Vector(aim_at) - Vector(p)).normalized()
    upv = (to + Vector((rng.uniform(-0.3, 0.3), 0, 0.3))).normalized()
    front = Vector((0, -1, -0.3)) if k % 2 else Vector((0.3, -1, 0.2))
    root = C.root_axes(p, upv, front, scale=scale)
    bends = {"RightShoulder": (170, -10, 0), "LeftShoulder": (10, 0, 8), "RightHip": (10, 0, 0), "LeftHip": (24, 0, 0),
             "LeftKnee": (50, 0, 0)}
    M, obs = C.hero(root, bends, suit=(suit, suit, legs), gloves=capec, boots=capec, cape_rgb=capec,
                    cape_kw=dict(length=4.4, flare=1.7, lift=1.2, wave=0.5, seed=k), mask=(20, 20, 30),
                    hair="spiky" if k % 3 == 0 else "swept", hair_rgb=(250, 250, 250) if k % 3 == 0 else (40, 30, 24),
                    emblem=("star", capec, (255, 255, 255)), skin=[(240, 190, 150), (141, 95, 64), (224, 172, 130)][k % 3])
    tail = [Vector(p) - to * (3 + i * 5) * scale / 2 + Vector((math.sin(i + k) * 2, 0, math.cos(i * 0.7 + k) * 2 - i * 1.5))
            for i in range(6)]
    trail(tail, trc, 0.45 * scale)
    if attack:
        fist = M["RightHand"] @ Vector((1.5, 0, 2.0))
        if attack == "bolt":
            C.lightning(fist, aim_at, rgb=trc, seed=k + 70, jag=0.06, width=0.22 * scale, branches=2, strength=10)
        else:
            core_beam(fist, aim_at, trc, width=0.3 * scale, strength=4.0)
        C.sparks(aim_at, 3, 10, cam, seed=k, rgb=(255, 220, 140), size=(1.0, 2.4), strength=10)
    return M, obs


SQUAD = [  # suit, legs, cape and trail colours (thumbs.py's squad)
    ((36, 92, 220), (28, 44, 110), (226, 28, 40), (90, 170, 255)),
    ((40, 170, 90), (30, 60, 40), (250, 210, 60), (120, 255, 150)),
    ((230, 200, 40), (60, 50, 40), (40, 40, 48), (255, 230, 90)),
    ((200, 40, 60), (40, 30, 40), (250, 250, 250), (255, 120, 120)),
    ((120, 70, 200), (40, 30, 60), (60, 200, 230), (200, 140, 255)),
    ((240, 120, 30), (60, 40, 30), (30, 90, 200), (255, 170, 80)),
    ((236, 236, 240), (60, 64, 80), (36, 92, 220), (220, 230, 255)),
]


def bounds(coll_name, name_part=None):
    """World bounds (min, max) of a collection's meshes (optionally only those whose mesh name has name_part)."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in C.collection(coll_name).all_objects:
        if ob.type != "MESH" or (name_part and name_part not in ob.data.name and name_part not in ob.name):
            continue
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def facing(yaw):
    """A boss's front (Blender) when turned yaw degrees (0 faces +y)."""
    return Vector((-math.sin(math.radians(yaw)), math.cos(math.radians(yaw)), 0))


def front_point(coll_name, name_part, zlo, zhi, d=(0, 1, 0)):
    """The front-most point (along d) of a mesh between two heights, averaged over the nearest verts: a boss's
    snout."""
    d = Vector(d)
    best = []
    for ob in C.collection(coll_name).all_objects:
        if ob.type != "MESH" or name_part not in ob.name:
            continue
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            if zlo <= w.z <= zhi:
                best.append(w)
    best.sort(key=lambda w: -w.dot(d))
    pts = best[:40]
    return sum(pts, Vector()) / max(1, len(pts))


def eyes(coll_name, name_part, at, face, depth=4.0, rise=8.0):
    """The two front glow lamps of a boss's face (left and right of its centre line): the averages of the glow
    piece's verts near the front, within `rise` studs of the face's height."""
    sides = {-1: [], 1: []}
    for ob in C.collection(coll_name).all_objects:
        if ob.type != "MESH" or name_part not in ob.name:
            continue
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            if abs(w.z - face.z) < rise and w.y > face.y - depth and abs(w.x - at.x) > 2:
                sides[1 if w.x > at.x else -1].append(w)
    return [sum(p, Vector()) / len(p) for p in sides.values() if p]


# ------------------------------------------------------------------------------------------------ icon: maw
def icon_maw():
    C.settings(ICON, samples=96, view="Standard")
    C.collection("Heroes")
    # the Lumen Maw at the Old Quarry, its jaws to the left; the hero flies in from the bottom left
    K.boss("LumenMaw", Vector((0, 0, 0)), yaw=-90, glow=(90, 240, 230), strength=7.0)  # the head faces -x
    mouth = front_point("Boss", "Glow", 8, 40, facing(-90))
    lo, hi = bounds("Boss")
    print("maw bounds", lo, hi, "mouth", mouth)
    # the hero 30 studs out in front of the jaws, the camera beside him (the boss's front F is screen right to
    # left, so the jaws sit top right and the hero bottom left)
    F, S, Z = facing(-90), Vector((0, 1, 0)), Vector((0, 0, 1))
    cam_at = mouth + F * 38 + S * 15 - Z * 5
    cam = C.camera(cam_at, mouth + F * 12 + Z * 3, lens=30)
    H = on_screen(cam, -0.4, -0.3, 7.2)
    to = (mouth - H).normalized()
    root = C.root_axes(H, (Z + to * 0.4).normalized(), ((cam_at - H).normalized() + to * 0.15).normalized(), scale=1.0)
    hb = {"LeftElbow": (4, 0, 0), "RightElbow": (80, 0, 0), "LeftHip": (16, 0, 0), "LeftKnee": (-50, 0, 0),
          "RightHip": (-28, 0, 0), "RightKnee": (-80, 0, 0), "Neck": (6, 0, -16), "Waist": (8, 0, -8)}
    hb["RightShoulder"] = C.aim(root, hb, "RightShoulder", (-0.6, -0.4, -0.7))
    hb["LeftShoulder"] = C.aim(root, hb, "LeftShoulder", to)
    HM, hobs = C.hero(root, hb, **ANIME)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    C.aura(hobs, (255, 196, 50), grow=0.09, strength=2.6, power=6.0)
    C.glow(H - (cam_at - H).normalized() * 2.5, 11, cam, (255, 180, 40), strength=1.2)  # behind him
    # the gold blast from the fist into the jaws, the jaws' cyan swirl pulling light in
    inside = mouth - F * 6
    core_beam(fist, inside, (255, 200, 60), width=1.1, strength=5.0)
    C.glow(fist, 4.0, cam, (255, 236, 160), strength=3.0, tex="core.png")
    C.glow(inside, 16, cam, (255, 210, 90), strength=1.6, tex="shock.png")
    C.glow(inside, 24, cam, (90, 240, 230), strength=1.4)
    C.glow(inside, 10, cam, (255, 230, 150), strength=2.0, tex="core.png")
    C.sparks(inside, 6, 30, cam, seed=5, rgb=(160, 255, 240), size=(0.6, 1.6), strength=10)
    C.sparks(fist, 1.2, 14, cam, seed=6, rgb=(255, 220, 120), size=(0.3, 0.8), strength=10)
    # the quarry: a pale rock floor and terraced walls far behind
    floor = C.kit.box("floor", 900, 900, 2, at=(0, 0, -1))
    floor.data.materials.append(C.flat("quarry", (110, 104, 120), rough=0.95))
    C.put(floor, C.collection("Set"))
    stars(cam, 140, seed=2, aspect=1.0, below=-0.1)
    C.sky(top=(10, 10, 40), horizon=(70, 44, 120), bottom=(40, 30, 70), mid=(36, 24, 80),
          ambient=(80, 90, 150), ambient_strength=0.6)
    C.sun((60, 0, 220), energy=1.2, rgb=(170, 190, 255))
    C.area(cam_at + F * 4 + Z * 6, H, 2600, (255, 236, 210), size=8)  # key on the hero
    C.lamp(inside, 60000, (90, 240, 230), size=10)  # the jaws' light on the boss
    C.lamp(H + Vector((3, 2, 0)), 400, (255, 190, 70), size=1.5)  # the aura's own glow
    outlines(["Heroes"], thickness=2.6)
    C.render("icon_maw")


# ------------------------------------------------------------------------------------------------ icon: fake
def icon_fake():
    C.settings(ICON, samples=96, view="Standard")
    # a close-up in the sky over Downtown: Radiant's head snapped by the hit, its face cracked open
    X, Y, Z = -470.0, -520.0, 150.0
    rroot = C.root_axes((X + 0.6, Y, Z - 2.0), (0.28, 0.08, 0.96), (-0.35, -1, 0), scale=1.0)
    rb = {"Neck": (-8, 6, 16), "LeftShoulder": (-10, 0, -8), "RightShoulder": (-10, 0, 8)}
    look = dict(K.RADIANT, face="Hero_Cracked")
    RM, robs = C.hero(rroot, rb, cape_kw=dict(inner=K.RADIANT_GOLD, length=5.0, flare=1.8, lift=1.0, wave=0.6,
                                               flow=(1.6, -1.2, -0.4), seed=11), extra=K.radiant_gear, **look)
    head = RM["Head"] @ Vector((0, 0.3, 4.62))
    jaw = RM["Head"] @ Vector((0.62, 0.36, 4.3))  # the cheek on its cracked side (screen left): the punch cracked it
    eye = RM["Head"] @ Vector((0.22, 0.66, 4.65))
    cam_at = RM["Head"] @ Vector((-0.2, 3.1, 4.8))
    cam = C.camera(cam_at, head + (jaw - head) * 0.45 + Vector((0, 0, 0.02)), lens=36)
    f, r, u = frame(cam)
    # the hero's lead fist (red glove) coming in from the left edge, his body out of frame
    hc = jaw - r * 2.25 + u * 0.55 - f * 0.45  # above Radiant's shoulder pad, so the fist reaches the cheek
    hroot = C.root_axes(hc, (u * 0.6 + Vector((0, 0, 0.8))).normalized(), (jaw - hc).normalized(), scale=1.0)
    hb = {"RightElbow": (70, 0, 0), "LeftElbow": (6, 0, 0)}
    sh = C.rig(hroot, hb)["UpperTorso"] @ Vector((-1.0, 0, 3.76))
    hb["LeftShoulder"] = C.aim(hroot, hb, "LeftShoulder", (jaw - sh).normalized())
    HM, hobs = C.hero(hroot, hb, cape_kw=dict(length=4.6, flare=1.8, lift=1.2, wave=0.5, flow=(-1.2, -1.0, -0.6),
                                                seed=9), **COMIC)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    hit = fist.lerp(jaw, 0.5) + (cam_at - jaw).normalized() * 0.3
    C.glow(hit, 0.9, cam, (255, 255, 255), strength=3.4, tex="core.png")
    C.glow(hit, 2.2, cam, (255, 250, 230), strength=1.3, tex="shock.png")
    C.sparks(hit, 0.45, 22, cam, seed=6, rgb=(255, 214, 120), size=(0.08, 0.24), strength=12)
    C.chunks(jaw + r * 0.25 + u * 0.15, 0.4, 10, seed=4, size=(0.04, 0.11), direction=r * 1.0,
             mats=[C.flat("shell", (241, 194, 160), rough=0.5), C.flat("plate", (150, 156, 170), rough=0.3, metal=0.9)])
    C.glow(eye, 0.75, cam, (255, 60, 40), strength=8.0)
    C.glow(eye, 0.25, cam, (255, 220, 200), strength=7.0, tex="core.png")
    C.sparks(eye + Vector((0.25, 0, 0.1)), 0.25, 8, cam, seed=8, rgb=(255, 120, 80), size=(0.08, 0.2), strength=10)
    if not NOCITY:
        C.layout("DowntownWide")
    C.fog("City", (196, 224, 250), start=140, half=600)
    C.sky(top=(30, 96, 226), horizon=(176, 220, 255), ambient=(176, 200, 236), ambient_strength=1.0)
    C.sun((48, 0, 140), energy=4.4, rgb=(255, 244, 226))
    C.area(cam_at + Vector((-3, 1, 3)), head, 260, (255, 245, 230), size=4)
    C.area(head + Vector((2, 4, 3)), head, 160, (150, 170, 255), size=4)
    C.lamp(hit, 30, (255, 240, 220), size=0.3)
    outlines(["Heroes"], thickness=2.2)
    C.render("icon_fake")


# ------------------------------------------------------------------------------------------------ icon: titan
def icon_titan():
    C.settings(ICON, samples=96, view="Standard")
    # Rustjaw Prime in the plaza at sunset, eyes red (phase 3); the hero rises at the camera in front of its face
    B = C.rb(-470, 0, 300)  # its feet in Downtown, a block cleared round it (thumbs.py's boss spot)
    K.boss("RustjawPrime", B, yaw=0, glow=(255, 52, 48), strength=14.0, phase=2)
    face = front_point("Boss", "Glow", B.z + 82, B.z + 104)
    print("rustjaw face", face - B)
    cam_at = face + Vector((10, 66, -36))
    cam = tilt(C.camera(cam_at, face + Vector((0, 0, -15)), lens=32), -6)
    f, r, u = frame(cam)
    H = on_screen(cam, 0.2, -0.5, 7.4)
    toc = (cam_at - H).normalized()
    root = C.root_axes(H, (toc * 0.5 + Vector((0, 0, 1))).normalized(), toc, scale=1.0)
    hb = {"LeftShoulder": (-30, 0, -20), "LeftElbow": (30, 0, 0), "LeftHip": (6, 0, 0), "LeftKnee": (-30, 0, 0),
          "RightHip": (-24, 0, 0), "RightKnee": (-60, 0, 0), "Neck": (-14, 0, 0)}
    hb["RightShoulder"] = C.aim(root, hb, "RightShoulder", (toc - r * 0.55 + u * 0.35).normalized())
    HM, hobs = C.hero(root, hb, cape_kw=dict(length=4.6, flare=1.9, lift=1.6, wave=0.6, flow=(0.4, 0, -1.4), seed=4),
                      **COMIC)
    fist = HM["RightHand"] @ Vector((1.5, 0, 2.0))
    # Volt lightning crackling round the fist, a wake of wind behind
    for k in range(4):
        a = k * 1.6 + 0.4
        d = (r * math.cos(a) + u * math.sin(a)).normalized()
        C.lightning(fist, fist + d * 1.4 - toc * 1.6, seed=60 + k, jag=0.2, width=0.05, branches=1, strength=12)
    C.glow(fist, 3.0, cam, (120, 200, 255), strength=2.0)
    C.sparks(face + Vector((0, 8, -14)), 24, 50, cam, seed=3, rgb=(255, 170, 70), size=(0.6, 1.8), strength=10)
    C.chunks(face + Vector((0, 20, -30)), 26, 24, seed=5, size=(0.8, 2.6),
             mats=[C.flat("rust", (196, 98, 48), rough=0.7, metal=0.4), C.flat("conc", (158, 156, 150), rough=0.85)])
    for e in eyes("Boss", "Glow", B, face):  # the red eyes (phase 3) burning
        C.glow(e + Vector((0, 3, 0)), 30, cam, (255, 60, 40), strength=2.6)
        C.glow(e + Vector((0, 3.5, 0)), 9, cam, (255, 220, 200), strength=3.4, tex="core.png")
        C.lamp(e + Vector((0, 6, 0)), 9000, (255, 60, 40), size=3)
    if not NOCITY:
        C.layout("DowntownWide", keep=lambda b: math.hypot(b["cx"] + 470, b["cz"] - 300) > 95 or b["kind"] in ("road", "sidewalk"))
    # a fiery sunset behind the titan: it stands nearly in silhouette, only its red eyes burning; the hero is lit
    C.fog("City", (240, 120, 90), start=150, half=700)
    C.sky(top=(70, 30, 90), horizon=(255, 170, 90), bottom=(255, 190, 120), mid=(220, 80, 70),
          ambient=(170, 110, 130), ambient_strength=0.45)
    C.sun((78, 0, 8), energy=4.0, rgb=(255, 170, 100))  # from behind it, a rim on its edges
    C.area(cam_at + Vector((-4, 2, 6)), H, 1500, (255, 236, 220), size=8)
    C.lamp(face + Vector((0, 14, 0)), 30000, (255, 60, 40), size=10)
    outlines(["Heroes"], thickness=2.6)
    C.render("icon_titan")


# ------------------------------------------------------------------------------------------------ thumb: maw
def quarry(centre, radius=160, coll=None):
    """The Old Quarry's pit (Lumen Maw's arena, Config.Boss arenaRadius 160): a pale floor and stepped rock
    terraces round it (Shared.SideQuestSites' quarry: a gate and a floor), rock chunks on the floor."""
    coll = coll or C.collection("Set")
    rock = [C.flat("rock%d" % k, rgb, rough=0.95) for k, rgb in enumerate(((84, 76, 104), (70, 64, 90), (98, 88, 116)))]
    g = C.kit.box("pit", radius * 6, radius * 6, 2, at=(0, 0, -1))
    g.location = Vector(centre)
    g.data.materials.append(C.flat("pitfloor", (120, 112, 126), rough=0.95))
    C.put(g, coll)
    rng = random.Random(4)
    for step in range(5):
        r = radius + step * 26
        n = 26 + step * 4
        for i in range(n):
            a = i * 2 * math.pi / n + rng.random() * 0.1
            w = 2 * math.pi * r / n * 1.05
            h = 18 + step * 22 + rng.uniform(-4, 4)
            b = C.kit.box("ter", 30, w, h, at=(0, 0, h / 2))
            b.location = Vector(centre) + Vector((math.cos(a) * r, math.sin(a) * r, 0))
            b.rotation_euler = (rng.uniform(-0.12, 0.12), rng.uniform(-0.2, 0.05), a + rng.uniform(-0.1, 0.1))
            b.data.materials.append(rng.choice(rock))
            C.put(b, coll)


def thumb_maw():
    C.settings(THUMB, samples=64, view="Standard")
    C.collection("Heroes")
    # the Lumen Maw lunging at the camera's left out of its pit, jaws wide; the Comic hero punches in from the left
    yaw = -62
    F = facing(yaw)
    S = Vector((F.y, -F.x, 0))  # the boss's right (screen left from the front)
    Z = Vector((0, 0, 1))
    gens = [Vector((math.cos(a) * 110, math.sin(a) * 110, 0)) for a in (math.radians(120), math.radians(185), math.radians(250))]
    K.boss("LumenMaw", Vector((0, 0, 0)), yaw=yaw, glow=(90, 240, 230), strength=7.0, generators=gens)
    mouth = front_point("Boss", "Glow", 8, 40, F)
    print("maw mouth", mouth)
    cam_at = mouth + F * 64 - S * 38 - Z * 17
    cam = C.camera(cam_at, mouth + F * 24 + S * 6 + Z * 9, lens=28)
    aspect = THUMB[0] / THUMB[1]
    # the Comic hero, big in the left third, flying a punch at the jaws
    H = on_screen(cam, -0.5, -0.06, 19, aspect)
    to = (mouth - H).normalized()
    toc = (cam_at - H).normalized()
    root = C.root_axes(H, (Z + to * 0.4).normalized(), (toc + to * 0.35).normalized(), scale=1.5)
    hb = {"LeftElbow": (4, 0, 0), "RightElbow": (80, 0, 0), "LeftHip": (16, 0, 0), "LeftKnee": (-50, 0, 0),
          "RightHip": (-28, 0, 0), "RightKnee": (-80, 0, 0), "Neck": (6, 0, -16), "Waist": (8, 0, -8)}
    hb["RightShoulder"] = C.aim(root, hb, "RightShoulder", (-to - Z * 0.7).normalized())
    hb["LeftShoulder"] = C.aim(root, hb, "LeftShoulder", to)
    HM, hobs = C.hero(root, hb, cape_kw=dict(length=4.6, flare=1.8, lift=1.2, wave=0.5, flow=(-1.2, -1.0, -0.6), seed=9),
                      **COMIC)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    inside = mouth - F * 7
    C.lightning(fist, inside, rgb=(60, 160, 255), seed=7, jag=0.06, width=0.32, branches=3, strength=12)
    C.glow(fist, 6, cam, (140, 200, 255), strength=2.0)
    C.glow(inside, 46, cam, (90, 240, 230), strength=1.0)
    C.glow(inside, 16, cam, (220, 255, 250), strength=1.8, tex="core.png")
    C.glow(inside, 30, cam, (150, 255, 245), strength=0.9, tex="vortex.png")
    C.sparks(inside, 8, 30, cam, seed=5, rgb=(160, 255, 240), size=(1.0, 2.4), strength=10)
    # the squad diving at it from above, smaller, beams on its back
    rng = random.Random(3)
    back = Vector((0, 0, 58)) - F * 10
    for (sx, sy, depth), k in zip(((0.42, 0.66, 170), (0.86, 0.46, 140), (0.08, 0.78, 210)), range(3)):
        suit, legs, capec, trc = SQUAD[k + 1]
        p = on_screen(cam, sx, sy, depth, aspect)
        flyer(p, back + Vector((rng.uniform(-8, 8), rng.uniform(-8, 8), rng.uniform(0, 6))), k + 1, cam, scale=2.6,
              suit=suit, legs=legs, capec=capec, trc=trc, attack=("beam" if k % 2 == 0 else "bolt"), rng=rng)
    quarry(Vector((0, 0, 0)), radius=210)
    C.fog("Set", (46, 34, 84), start=60, half=160)
    stars(cam, 220, seed=2, depth=3000, aspect=aspect, below=0.0)
    C.sky(top=(10, 10, 40), horizon=(90, 50, 130), bottom=(40, 30, 70), mid=(36, 24, 80),
          ambient=(80, 90, 150), ambient_strength=0.55)
    C.sun((60, 0, 220), energy=1.4, rgb=(170, 190, 255))
    C.area(cam_at + Vector((-10, 0, 14)), H, 4000, (255, 236, 210), size=14)
    C.lamp(inside, 200000, (90, 240, 230), size=16)
    for g in gens:  # the generators' red glow
        g = g + Vector((0, 0, 12))
        C.lamp(g, 30000, (255, 70, 60), size=4)
        C.glow(g, 26, cam, (255, 80, 60), strength=1.0)
    outlines(["Heroes"], thickness=2.4)
    C.render("thumb_maw")


# ------------------------------------------------------------------------------------------------ thumb: deep
def water_mat():
    m = C.bpy.data.materials.new("sea")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = C.lin3((20, 110, 150))
    p.inputs["Roughness"].default_value = 0.06
    p.inputs["Coat Weight"].default_value = 0.4
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.04
    nz.inputs["Detail"].default_value = 6
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return m


def foam_mat():
    return C.flat("foam", (245, 250, 255), rough=0.4, emit=0.25)


def splash(centre, radius, cam, seed=1, count=60, height=30, coll=None):
    """The sea bursting up round the boss: white spray cards, foam rings on the water and drops flung out."""
    rng = random.Random(seed)
    c = Vector(centre)
    C.smoke(c + Vector((0, 0, height * 0.15)), radius * 0.7, 12, cam, seed=seed, size=(radius * 0.3, radius * 0.6),
            rgb=(245, 250, 255), alpha=0.6, up=0.5)
    m = foam_mat()
    for i in range(count):
        a = rng.uniform(0, 2 * math.pi)
        r = radius * rng.uniform(0.6, 1.3)
        p = c + Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(0, height)))
        s = rng.uniform(0.3, 1.0)
        d = C.kit.sphere("drop", s, at=(0, 0, 0), scale=(1, 1, 1.6), segs=8, rings=6)
        d.location = p
        d.data.materials.append(m)
        C.put(d, coll or C.collection("Fx"))
    foam = C.kit.cyl("foam", radius * 1.1, radius * 1.1, 0.3, segs=48)
    foam.location = c + Vector((0, 0, 0.2))
    fm = C.bpy.data.materials.new("foamdisc")
    fm.use_nodes = True
    nt = fm.node_tree
    pr = nt.nodes["Principled BSDF"]
    pr.inputs["Base Color"].default_value = C.lin3((240, 248, 255))
    pr.inputs["Roughness"].default_value = 0.5
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.12
    nz.inputs["Detail"].default_value = 4
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.5
    ramp.color_ramp.elements[1].position = 0.6
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], pr.inputs["Alpha"])
    foam.data.materials.append(fm)
    C.put(foam, coll or C.collection("Fx"))


def thumb_deep():
    C.settings(THUMB, samples=64, view="Standard")
    C.collection("Heroes")
    # the Trench at the water's surface on a bright day: the Leviathan Engine rearing out of the sea at the camera
    yaw = -130
    F = facing(yaw)
    S = Vector((F.y, -F.x, 0))
    Z = Vector((0, 0, 1))
    K.boss("LeviathanEngine", Vector((0, 0, -6)), yaw=yaw, glow=(80, 230, 255), strength=7.0)
    head = front_point("Boss", "Hull", 40, 80, F)
    print("leviathan head", head)
    cam_at = head + F * 66 - S * 34 - Z * 40
    cam = C.camera(cam_at, head + F * 26 + S * 2 - Z * 25, lens=24)
    aspect = THUMB[0] / THUMB[1]
    sea = C.kit.box("sea", 9000, 9000, 1, at=(0, 0, -0.5))
    sea.data.materials.append(water_mat())
    C.put(sea, C.collection("Set"))
    splash(Vector((head.x, head.y, 0)) - F * 22, 26, cam, seed=2, count=26, height=20)
    # the Comic hero flying in from the left, Volt lightning from the near fist into its head
    H = on_screen(cam, -0.52, 0.12, 24, aspect)
    to = (head - H).normalized()
    toc = (cam_at - H).normalized()
    root = C.root_axes(H, (Z + to * 0.4).normalized(), (toc + to * 0.35).normalized(), scale=1.5)
    hb = {"LeftElbow": (4, 0, 0), "RightElbow": (80, 0, 0), "LeftHip": (16, 0, 0), "LeftKnee": (-50, 0, 0),
          "RightHip": (-28, 0, 0), "RightKnee": (-80, 0, 0), "Neck": (6, 0, -16), "Waist": (8, 0, -8)}
    hb["RightShoulder"] = C.aim(root, hb, "RightShoulder", (-to * 0.6 - Z).normalized())
    hb["LeftShoulder"] = C.aim(root, hb, "LeftShoulder", to)
    HM, hobs = C.hero(root, hb, cape_kw=dict(length=4.6, flare=1.8, lift=1.2, wave=0.5, flow=(-1.2, -1.0, -0.6), seed=9),
                      **COMIC)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    target = head - F * 4
    C.lightning(fist, target, rgb=(60, 160, 255), seed=8, jag=0.07, width=0.32, branches=3, strength=12)
    C.glow(fist, 6, cam, (140, 200, 255), strength=2.0)
    C.glow(target, 26, cam, (140, 210, 255), strength=1.2)
    C.glow(target, 14, cam, (255, 250, 230), strength=1.2, tex="shock.png")
    C.sparks(target, 6, 26, cam, seed=4, rgb=(255, 220, 140), size=(1.0, 2.4), strength=10)
    rng = random.Random(9)
    for (sx, sy, depth), k in zip(((0.62, 0.56, 150), (0.9, 0.12, 110), (0.3, 0.75, 180)), range(3)):
        suit, legs, capec, trc = SQUAD[k + 2]
        p = on_screen(cam, sx, sy, depth, aspect)
        flyer(p, head - F * 20 + Vector((rng.uniform(-6, 6), rng.uniform(-6, 6), rng.uniform(-24, -10))), k + 2, cam,
              scale=2.4, suit=suit, legs=legs, capec=capec, trc=trc, attack="beam" if k % 2 else "bolt", rng=rng)
    if not NOCITY:  # Brightharbor's towers on the horizon behind
        far = head - F * 1500
        C.city(far.x, far.y, blocks=4, block=96, street=28, seed=21, hmin=90, hmax=300, centre_boost=1.5)
    C.fog("City", (190, 220, 245), start=300, half=700)
    C.sky(top=(30, 96, 226), horizon=(176, 220, 255), ambient=(176, 200, 236), ambient_strength=1.0)
    C.sun((52, 0, 200), energy=4.2, rgb=(255, 244, 226))
    C.area(cam_at + Z * 14 - S * 6, H, 1800, (255, 240, 225), size=14)
    C.area(cam_at + Vector((30, -10, 30)), head, 300000, (255, 240, 225), size=40)
    outlines(["Heroes"], thickness=2.4)
    C.render("thumb_deep")


# ------------------------------------------------------------------------------------------------ thumb: fakes
def thumb_fakes():
    C.settings(THUMB, samples=64, view="Standard")
    # three famous heroes posing on a Downtown roof at golden hour, low angle; the middle one's face has cracked
    if not NOCITY:
        C.layout("DowntownWide")
    roof_z = 120.0
    base = C.rb(-470, roof_z, 500)
    deck = C.kit.box("deck", 70, 34, 2, at=(0, 0, -1))
    deck.location = base
    deck.data.materials.append(C.kit_mat("Paving"))
    C.put(deck, C.collection("Set"))
    rim = C.kit.box("rim", 70, 1.2, 2.4, at=(0, 17, 0.2))
    rim.location = base
    rim.data.materials.append(C.flat("rim", (200, 198, 192), rough=0.8))
    C.put(rim, C.collection("Set"))
    tower = C.kit.box("bld", 70, 34, roof_z, at=(0, 0, -roof_z / 2 - 2))
    tower.location = base
    tower.data.materials.append(C.kit_mat("Office", (214, 232, 255)))
    C.put(tower, C.collection("Set"))
    z0 = base.z + 2.6
    y0 = base.y
    cam_at = Vector((base.x + 0.7, y0 - 6.6, z0 + 0.9))
    cam = C.camera(cam_at, Vector((base.x + 0.2, y0, z0 + 2.0)), lens=28)
    # Bulwark (left, behind, the Titan): one fist raised, the other on his hip
    bw = {"RightShoulder": (172, 0, 6), "RightElbow": (6, 0, 0), "LeftShoulder": (0, 0, -18), "LeftElbow": (60, 0, -40),
          "LeftHip": (0, 10, 0), "RightHip": (0, -10, 0), "Neck": (-4, 0, 0)}
    C.hero(C.root_matrix((base.x - 4.8, y0 + 4.2, z0 + 0.6), (0, 0, 180 - 22), 1.24), bw, extra=K.bulwark_gear,
           **K.BULWARK)
    # Skylance (right): spear up, one knee lifted, a lean
    sk = {"RightShoulder": (160, -10, 0), "RightElbow": (20, 0, 0), "LeftShoulder": (-20, 0, 16), "LeftElbow": (-40, 0, 0),
          "LeftHip": (40, 0, 0), "LeftKnee": (-60, 0, 0), "Waist": (0, 0, 8), "Neck": (0, 0, -10)}
    SM, _ = C.hero(C.root_matrix((base.x + 5.0, y0 + 4.0, z0 - 0.15), (0, 0, 180 + 24), 0.94), sk, extra=K.skylance_gear,
                   **K.SKYLANCE)
    K.spear(SM, "RightHand", length=7.5)
    C.glow(SM["RightHand"] @ Vector((1.5, 4.4, 2.15)), 3.0, cam, (90, 240, 255), strength=2.0)
    # Radiant (middle, a step closer): the hero pose, one fist raised, the face cracked open to the plate, red eye
    rd = {"LeftShoulder": (165, 0, 12), "RightShoulder": (0, 0, 18), "LeftElbow": (10, 0, 0), "RightElbow": (60, 0, 40),
          "LeftHip": (0, 8, 0), "RightHip": (0, -8, 0), "Neck": (-8, 0, 4)}
    look = dict(K.RADIANT, face="Hero_Cracked")
    RM, robs = C.hero(C.root_matrix((base.x, y0 - 1.0, z0 + 0.1), (0, 0, 180 - 4), 1.04), rd,
                      cape_kw=dict(inner=K.RADIANT_GOLD, length=4.6, flare=1.8, lift=0.9, wave=0.5, flow=(0.8, 0.6, 0), seed=11),
                      extra=K.radiant_gear, **look)
    eye = RM["Head"] @ Vector((0.22, 0.66, 4.65))
    C.glow(eye + Vector((0, -0.2, 0)), 0.62, cam, (255, 60, 40), strength=6.0)
    C.glow(eye + Vector((0, -0.25, 0)), 0.22, cam, (255, 220, 200), strength=8.0, tex="core.png")
    C.sparks(eye + Vector((0.2, 0, 0.1)), 0.3, 8, cam, seed=8, rgb=(255, 120, 80), size=(0.1, 0.3), strength=10)
    halo = RM["Head"] @ Vector((0, -0.15, 5.75))
    C.glow(halo + Vector((0, 1.0, 0)), 5.0, cam, (255, 226, 110), strength=1.0)
    C.fog("City", (250, 196, 160), start=200, half=1000)
    C.sky(top=(38, 52, 130), horizon=(255, 170, 110), bottom=(255, 196, 150), mid=(150, 110, 170),
          ambient=(200, 170, 190), ambient_strength=0.75)
    C.sun((76, 0, -24), energy=4.4, rgb=(255, 186, 120), angle=2)
    centre = Vector((base.x, y0, z0 + 1.0))
    C.area(cam_at + Vector((-7, -2, 7)), centre, 1700, (255, 232, 210), size=14)
    C.area(centre + Vector((6, 9, 6)), centre, 2600, (150, 170, 255), size=10)
    C.lamp(eye + Vector((0.2, -0.8, 0)), 6, (255, 60, 40), size=0.3)
    outlines(["Heroes"], thickness=2.2)
    C.render("thumb_fakes")


# ------------------------------------------------------------------------------------------------ thumb: giant
def thumb_giant():
    C.settings(THUMB, samples=64, view="Standard")
    C.collection("Heroes")
    # Wind-Up Lane's street in the Suburbs (art/export/city/Suburbs.json, the 30-stud road at Roblox x -1150): the
    # Wind-Up Giant (a 10-stud body, Config.Enemies.WindupGiant.body.height) stomps at the camera
    if not NOCITY:
        C.layout("Suburbs", skip_kinds=("mark", "terminal"))
    street = C.rb(-1150, 0, -120)
    G = street + Vector((0, 0, 2.6 * 1.95))
    gb = {"LeftShoulder": (70, 0, -20), "LeftElbow": (30, 0, 0), "RightShoulder": (-40, 0, 20), "RightElbow": (20, 0, 0),
          "LeftHip": (36, 0, 0), "LeftKnee": (-30, 0, 0), "RightHip": (-14, 0, 0), "Neck": (8, 0, 0)}
    GM, gobs = K.finale("WindupGiant", C.root_matrix(G + Vector((0, 0, 0.3)), (6, 0, 180), 1.95), gb)
    # the Bramblebeast and the Voidhound a step behind on either side
    bb = {"LeftShoulder": (110, 0, -30), "RightShoulder": (110, 0, 30), "LeftElbow": (30, 0, 0), "RightElbow": (30, 0, 0),
          "LeftHip": (20, 0, 0), "LeftKnee": (-20, 0, 0)}
    K.finale("Bramblebeast", C.root_matrix(street + Vector((7.6, 15, 2.6 * 1.2)), (0, 0, 180 - 14), 1.2), bb)
    vh = {"RightShoulder": (80, 0, 30), "RightElbow": (60, 0, 0), "LeftShoulder": (-20, 0, -10), "LeftHip": (30, 0, 0),
          "LeftKnee": (-40, 0, 0), "Waist": (14, 0, 0), "Neck": (-10, 0, 0)}
    K.finale("Voidhound", C.root_matrix(street + Vector((11.5, 3.5, 2.6 * 1.12)), (10, 0, 180 - 30), 1.12), vh)
    cam_at = street + Vector((-1.5, -16, 1.5))
    cam = C.camera(cam_at, street + Vector((1.4, 4, 6.8)), lens=22)
    aspect = THUMB[0] / THUMB[1]
    # the Comic hero leaping in from the left foreground, fist cocked at the giant
    H = on_screen(cam, -0.6, 0.02, 8.5, aspect)
    tgt = GM["UpperTorso"] @ Vector((0, 0, 3.4))
    to = (tgt - H).normalized()
    toc = (cam_at - H).normalized()
    Z = Vector((0, 0, 1))
    root = C.root_axes(H, (Z + to * 0.4).normalized(), (toc + to * 0.35).normalized())
    hb = {"LeftElbow": (4, 0, 0), "RightElbow": (80, 0, 0), "LeftHip": (16, 0, 0), "LeftKnee": (-50, 0, 0),
          "RightHip": (-28, 0, 0), "RightKnee": (-80, 0, 0), "Neck": (6, 0, -16), "Waist": (8, 0, -8)}
    hb["RightShoulder"] = C.aim(root, hb, "RightShoulder", (-to * 0.6 - Z).normalized())
    hb["LeftShoulder"] = C.aim(root, hb, "LeftShoulder", to)
    HM, hobs = C.hero(root, hb, cape_kw=dict(length=4.6, flare=1.8, lift=1.2, wave=0.5, flow=(-1.2, -1.0, -0.6), seed=9),
                      **COMIC)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    C.glow(fist, 2.6, cam, (140, 200, 255), strength=2.0)
    for k in range(4):
        a = k * 1.6
        d = Vector((math.cos(a), math.sin(a) * 0.3, math.sin(a))).normalized()
        C.lightning(fist, fist + d * 1.6 + to * 0.8, seed=80 + k, jag=0.2, width=0.05, branches=1, strength=12)
    # the stomp: a cracked street, asphalt chunks and dust round the giant's lead foot
    foot = GM["LeftFoot"] @ Vector((-0.5, 0, 0.15))
    C.chunks(Vector((foot.x, foot.y, street.z + 0.6)), 3.0, 22, seed=5, size=(0.15, 0.5), direction=(0, -1, 0.6), stretch=0.6,
             mats=[C.kit_mat("Asphalt"), C.flat("conc", C.PALETTE["concrete"], rough=0.85)])
    C.smoke(Vector((foot.x, foot.y, street.z + 0.4)), 2.4, 7, cam, seed=3, size=(2.5, 5), rgb=(236, 228, 214), alpha=0.5,
            up=0.2)
    ring = C.kit.torus("stomp", 5.0, 0.12, segs=64, csegs=6)
    ring.location = Vector((foot.x, foot.y, street.z + 0.3))
    ring.data.materials.append(C.glow_mat("stomp", (255, 220, 120), 4.0))
    C.put(ring, C.collection("Fx"))
    C.fog("City", (196, 224, 250), start=60, half=500)
    C.sky(top=(30, 96, 226), horizon=(176, 220, 255), ambient=(176, 200, 236), ambient_strength=1.0)
    C.sun((50, 0, 210), energy=4.4, rgb=(255, 244, 226))
    C.area(cam_at + Vector((-6, 2, 8)), G, 4000, (255, 240, 225), size=14)
    C.area(G + Vector((10, 14, 8)), G, 2400, (150, 170, 255), size=10)
    C.area(street + Vector((8, -10, 8)), street + Vector((11, 6, 3)), 2600, (255, 240, 225), size=10)  # the two behind
    outlines(["Heroes", "Villains"], thickness=2.6)
    C.render("thumb_giant")


{"icon_maw": icon_maw, "icon_fake": icon_fake, "icon_titan": icon_titan, "thumb_maw": thumb_maw,
 "thumb_deep": thumb_deep, "thumb_fakes": thumb_fakes, "thumb_giant": thumb_giant}[WHICH]()
