# scenes.py: one staging per comic page panel (Config.Cinema.comic.pages), for art/blender/panels.py. Each panel
# is a small set built from boxes and the city kit's fronts (art/store/common.py), the story's people on the
# blocky R15 body in their game outfits with catalog faces and hair (panels.person), robots in their uniforms,
# and effects (glows, bursts, sparks, smoke, lightning). The panel's own sky and ground colours (the config's)
# tint each set, so the art keeps the page's colour script. Captions and sound words stay in the UI.
# Rendered 2:1 (the UI crops each panel to its shape, so the action sits in the middle).
import math
import os
import random

import common as C
import kit
import bpy
from mathutils import Vector

RES = (720, 360)
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
P = None  # the panels module (set by render)
CAM = None


def lighter(c, t=0.35):
    return tuple(int(a + (255 - a) * t) for a in c)


def darker(c, t=0.35):
    return tuple(int(a * (1 - t)) for a in c)


# ------------------------------------------------------------------ poses (joint -> degrees; see common.rig)
POSES = {
    "stand": {},
    "relaxed": {"LeftShoulder": (0, 8, 0), "RightShoulder": (0, -8, 0)},
    "wave": {"RightShoulder": (0, -150, 0), "RightElbow": (0, -20, 0), "LeftShoulder": (0, 8, 0)},
    "point": {"RightShoulder": (88, 0, 0), "LeftShoulder": (0, 10, 0)},
    "punch": {"RightShoulder": (90, 0, 0), "LeftShoulder": (50, 0, 10), "LeftElbow": (60, 0, 0),
              "Waist": (0, 0, -18), "LeftHip": (25, 0, 0), "RightHip": (-20, 0, 0), "LeftKnee": (-20, 0, 0)},
    "cheer": {"RightShoulder": (0, -160, 0), "LeftShoulder": (0, 160, 0)},
    "fist": {"RightShoulder": (0, -165, 0), "LeftShoulder": (0, 10, 0)},
    "hold": {"RightShoulder": (75, 0, 0), "LeftShoulder": (75, 0, 0)},
    "fly": {"RightShoulder": (175, 0, 0), "LeftShoulder": (10, 15, 0), "LeftHip": (-10, 0, 0),
            "RightHip": (10, 0, 0), "RightKnee": (-20, 0, 0)},
    "run": {"RightShoulder": (-45, 0, 0), "LeftShoulder": (55, 0, 0), "RightElbow": (50, 0, 0),
            "LeftElbow": (50, 0, 0), "RightHip": (45, 0, 0), "LeftHip": (-35, 0, 0), "RightKnee": (-40, 0, 0),
            "LeftKnee": (-70, 0, 0)},
    "sit": {"LeftHip": (90, 0, 0), "RightHip": (90, 0, 0), "LeftKnee": (-90, 0, 0), "RightKnee": (-90, 0, 0),
            "LeftShoulder": (30, 0, 0), "RightShoulder": (30, 0, 0)},
    "kneel": {"LeftHip": (90, 0, 0), "LeftKnee": (-90, 0, 0), "RightHip": (-10, 0, 0), "RightKnee": (-80, 0, 0),
              "RightShoulder": (20, 0, 0), "LeftShoulder": (20, 0, 0)},
    "cower": {"RightShoulder": (130, 0, -20), "LeftShoulder": (130, 0, 20), "RightElbow": (90, 0, 0),
              "LeftElbow": (90, 0, 0), "Waist": (15, 0, 0)},
    "kick": {"RightHip": (95, 0, 0), "LeftShoulder": (0, 70, 0), "RightShoulder": (0, -70, 0),
             "Waist": (-10, 0, 0)},
    "bow": {"Waist": (40, 0, 0), "RightShoulder": (0, -60, 0), "LeftShoulder": (0, 60, 0)},
    "lunge": {"RightShoulder": (95, 0, 0), "LeftShoulder": (95, 0, 0), "Waist": (25, 0, 0),
              "RightHip": (40, 0, 0), "RightKnee": (-50, 0, 0), "LeftHip": (-30, 0, 0)},
    "drive": {"RightShoulder": (60, 0, 0), "LeftShoulder": (60, 0, 0), "LeftHip": (90, 0, 0),
              "RightHip": (90, 0, 0), "LeftKnee": (-90, 0, 0), "RightKnee": (-90, 0, 0)},
    "hands": {"RightShoulder": (60, -30, 0), "LeftShoulder": (60, 30, 0), "RightElbow": (30, 0, 0),
              "LeftElbow": (30, 0, 0)},
    "lying": {"LeftShoulder": (0, 40, 0), "RightShoulder": (0, -40, 0)},
}
SEAT = {"sit": 1.75, "kneel": 0.85, "drive": 1.75}  # how far the body drops for that pose


# ------------------------------------------------------------------ people
HERO = {"key": "hero", "skin": (224, 172, 130), "clothes": "heroes/preview/Hero1", "color": (60, 130, 240),
        "face": {"image": 144080495}, "hair": {"asset": 5891039736}, "extras": []}
_rng = random.Random(7)


def citizen(seed):
    """A passer-by in a tinted hero shirt and pants, a catalog face and catalog hair (picked by seed)."""
    r = random.Random(seed)
    faces = sorted(int(f[:-4]) for f in os.listdir(os.path.join(P.CAT, "faces")) if f.endswith(".png"))
    hairs = sorted(P.HAIR_INDEX)
    shirts = ["Tee", "Hoodie", "Polo", "Flannel", "Sweater", "ButtonShirt", "TrackTop", "DenimJacket"]
    pants = ["Jeans", "Chinos", "Cargo", "Joggers", "Slacks", "Shorts"]
    skins = [(255, 224, 196), (241, 194, 160), (224, 172, 130), (198, 140, 100), (160, 105, 70), (110, 70, 50)]
    tint = lambda: tuple(r.randint(60, 240) for _ in range(3))  # noqa: E731
    return {"key": "citizen%d" % seed, "skin": r.choice(skins), "face": {"image": r.choice(faces)},
            "hair": {"asset": int(r.choice(hairs))}, "extras": [],
            "outfit": {"shirt": r.choice(shirts), "shirtTint": tint(), "pants": r.choice(pants),
                       "pantsTint": tint()}}


def robot(kind, seed=1, version="Grunt"):
    r = random.Random(seed)
    faces = sorted(int(f[:-4]) for f in os.listdir(os.path.join(P.CAT, "faces")) if f.endswith(".png"))
    return {"key": "robot", "skin": r.choice([(224, 172, 130), (198, 140, 100), (241, 194, 160), (160, 105, 70)]),
            "clothes": "uniforms/%s_%s" % (kind, version), "face": {"image": r.choice(faces)},
            "hair": {"asset": int(r.choice(sorted(P.HAIR_INDEX)))}, "extras": []}


def hero(cape=(200, 40, 50), **kw):
    row = dict(HERO, **kw)
    return row, cape


def fig(who, at, yaw=0.0, pose="stand", scale=1.0, tilt=(0, 0), extra=None):
    """Puts a person on the set: who is a cast key, a row, or ("hero", cape colour). at: where the feet stand."""
    cape = None
    if isinstance(who, tuple):
        who, cape = who
    if isinstance(who, str) and who == "hero":
        who = HERO
    row = P.PEOPLE[who] if isinstance(who, str) else who
    drop = SEAT.get(pose, 0.0) * scale
    centre = (at[0], at[1], at[2] + (C.CENTRE.z - drop) * scale)
    root = C.root_matrix(centre, (tilt[0], tilt[1], yaw), scale)
    M, obs = P.person(row, root=root, bends=POSES[pose])
    if cape:
        c = C.cape(cape)
        obs.append(C.put(C._apply(c, M["UpperTorso"]), C.collection("People")))
    if extra:
        for ob in extra(M):
            obs.append(C.put(ob, C.collection("People")))
    return M, obs


# ------------------------------------------------------------------ sets
def props():
    return C.collection("Props")


def box(size, at, rgb, rough=0.6, metal=0.0, emit=0.0, rot=None, bev=0.05, coll=None):
    ob = kit.box("b", size[0], size[1], size[2], at=(0, 0, 0))
    if bev:
        kit.bevel(ob, min(bev, min(size) * 0.3), 1)
    ob.location = at
    if rot:
        ob.rotation_euler = [math.radians(a) for a in rot]
    ob.data.materials.append(C.flat("p", rgb, rough=rough, metal=metal, emit=emit))
    return C.put(ob, coll or props())


def cyl(r1, r2, h, at, rgb, axis="Z", segs=24, rough=0.6, metal=0.0, emit=0.0, rot=None, coll=None):
    ob = kit.cyl("c", r1, r2, h, at=(0, 0, 0), segs=segs, axis=axis)
    ob.location = at
    if rot:
        ob.rotation_euler = [math.radians(a) for a in rot]
    ob.data.materials.append(C.flat("p", rgb, rough=rough, metal=metal, emit=emit))
    kit.shade_auto(ob, 40)
    return C.put(ob, coll or props())


def ball(r, at, rgb, scale=(1, 1, 1), emit=0.0, rough=0.6, metal=0.0, coll=None):
    ob = kit.sphere("s", r, at=(0, 0, 0), scale=scale, segs=24, rings=14)
    ob.location = at
    ob.data.materials.append(C.flat("p", rgb, rough=rough, metal=metal, emit=emit))
    kit.shade_auto(ob, 60)
    return C.put(ob, coll or props())


def glowbox(size, at, rgb, strength=3.0, rot=None, coll=None):
    ob = kit.box("g", size[0], size[1], size[2], at=(0, 0, 0))
    ob.location = at
    if rot:
        ob.rotation_euler = [math.radians(a) for a in rot]
    ob.data.materials.append(C.glow_mat("g", rgb, strength))
    return C.put(ob, coll or C.collection("Fx"))


def ring(r, w, at, rgb, strength=4.0, axis="Z"):
    ob = kit.torus("ring", r, w, at=(0, 0, 0), segs=48, csegs=10, axis=axis)
    ob.location = at
    ob.data.materials.append(C.glow_mat("ring", rgb, strength))
    return C.put(ob, C.collection("Fx"))


def ground(rgb, size=600, z=0.0):
    g = kit.box("ground", size, size, 1, at=(0, 0, z - 0.5))
    g.data.materials.append(C.flat("ground", rgb, rough=0.9))
    return C.put(g, C.collection("Set"))


def water(rgb, z=0.0, size=900):
    w = kit.box("water", size, size, 1, at=(0, 0, z - 0.5))
    m = bpy.data.materials.new("water")
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = C.lin3(rgb)
    p.inputs["Roughness"].default_value = 0.12
    p.inputs["Coat Weight"].default_value = 0.6
    w.data.materials.append(m)
    return C.put(w, C.collection("Set"))


def skyline(y=-160, x0=-260, x1=260, rgb=(90, 100, 130), seed=3, hmin=30, hmax=110, lit=0.0, kitfronts=True,
            depth=30):
    """A row of towers at the back (kit fronts, or flat colour with lit windows at night)."""
    r = random.Random(seed)
    x = x0
    fronts = ["Curtain", "Office", "Brick", "Stone", "Office"]
    while x < x1:
        w = r.uniform(18, 40)
        h = r.uniform(hmin, hmax)
        if kitfronts:
            C.tower(x, y - depth, w, depth, h, r.choice(fronts), coll=C.collection("Set"), rng=r, crown=False)
        else:
            box((w, depth, h), (x + w / 2, y - depth / 2, h / 2), darker(rgb, r.uniform(0, 0.25)), bev=0,
                coll=C.collection("Set"))
        if lit > 0:
            for k in range(int(h // 8)):
                for j in range(int(w // 7)):
                    if r.random() < lit:
                        glowbox((2.2, 0.3, 2.8), (x + 4 + j * 7, y + 0.3, 5 + k * 8), (255, 220, 140), 2.0)
        x += w + r.uniform(2, 8)


def room(wall, floor, w=40, d=24, h=18, side=True):
    box((w, 1, h), (0, -d / 2, h / 2), wall, bev=0, coll=C.collection("Set"))
    box((w, d + 20, 1), (0, 0, -0.5), floor, bev=0, coll=C.collection("Set"))
    if side:
        for s in (-1, 1):
            box((1, d + 20, h), (s * w / 2, 0, h / 2), darker(wall, 0.15), bev=0, coll=C.collection("Set"))


def stars(count=80, seed=2):
    r = random.Random(seed)
    for _ in range(count):
        a = r.uniform(-1.2, 1.2)
        e = r.uniform(0.15, 0.7)
        d = 900
        glowbox((1.6, 1.6, 1.6), (math.sin(a) * d, -math.cos(a) * d * math.cos(e), math.sin(e) * d), (255, 255, 240),
                4.0)


PENDING = []  # effects facing the camera wait until the scene's camera is set (run by finish)


def sparks(*a, **kw):
    PENDING.append(lambda: C.sparks(a[0], a[1], a[2], CAM, *a[3:], **kw))


def smoke(*a, **kw):
    PENDING.append(lambda: C.smoke(a[0], a[1], a[2], CAM, *a[3:], **kw))


def glow(at, size, rgb, **kw):
    PENDING.append(lambda: C.glow(at, size, CAM, rgb, **kw))


def burst(*a, **kw):
    PENDING.append(lambda: _burst(*a, **kw))


def aura(*a, **kw):
    PENDING.append(lambda: _aura(*a, **kw))


def _burst(at, rgb, size=6.0, rays=10, strength=5.0):
    """A comic burst: a glow, a hot core and spiky rays."""
    C.glow(Vector(at), size * 2.2, CAM, rgb, strength=strength * 0.6)
    ball(size * 0.28, at, lighter(rgb, 0.6), emit=8.0, coll=C.collection("Fx"))
    r = random.Random(int(size * 10))
    for k in range(rays):
        a = 2 * math.pi * k / rays + r.uniform(-0.15, 0.15)
        ln = size * r.uniform(0.6, 1.1)
        ob = kit.cyl("ray", size * 0.09, 0.0, ln, at=(0, 0, ln / 2), segs=4)
        ob.location = at
        cam_r = CAM.matrix_world.to_3x3()
        d = cam_r @ Vector((math.cos(a), math.sin(a), 0))
        ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        ob.data.materials.append(C.glow_mat("ray", lighter(rgb, 0.3), strength))
        C.put(ob, C.collection("Fx"))


def _aura(at, rgb, height=6.0):
    """The Spark waking: a glow column and rising motes round a figure."""
    C.glow(Vector((at[0], at[1], at[2] + height * 0.5)), height * 1.6, CAM, rgb, strength=3.0)
    C.sparks(Vector((at[0], at[1], at[2] + height * 0.5)), height * 0.35, 26, CAM, seed=5, rgb=rgb, size=(0.3, 0.8),
             strength=10)
    ring(1.8, 0.12, (at[0], at[1], at[2] + 0.2), rgb, 6.0)


def streaks(at, direction, rgb=(255, 255, 255), count=10, length=12, seed=1):
    r = random.Random(seed)
    d = Vector(direction).normalized()
    for _ in range(count):
        p = Vector(at) + Vector((r.gauss(0, 1), r.gauss(0, 1), r.gauss(0, 1))) * 2.2
        ob = kit.cyl("streak", 0.07, 0.07, length * r.uniform(0.5, 1), at=(0, 0, 0), segs=6)
        ob.location = p - d * length * 0.5
        ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        ob.data.materials.append(C.glow_mat("streak", rgb, 3.0))
        C.put(ob, C.collection("Fx"))


def van(at, yaw, rgb, dish=False, cage=False, label=(255, 255, 255)):
    x, y, z = at
    parts = [box((5, 11, 5), (0, 0, 3.4), rgb), box((4.6, 3.2, 3), (0, 6.6, 2.6), lighter(rgb, 0.1)),
             box((4.2, 0.2, 1.6), (0, 8.25, 3.2), (150, 200, 230), rough=0.1),
             box((5.1, 4, 1.0), (0, -1, 4.0), label)]
    for wx in (-2.5, 2.5):
        for wy in (-3.5, 5.5):
            parts.append(cyl(1.1, 1.1, 0.8, (wx, wy, 1.1), (30, 30, 34), axis="X"))
    if dish:
        parts.append(cyl(1.6, 0.2, 0.8, (0, -2, 7.2), (230, 230, 235), rot=(-35, 0, 0)))
        parts.append(cyl(0.12, 0.12, 1.5, (0, -2, 6.3), (90, 90, 96)))
    if cage:
        for k in range(6):
            parts.append(box((0.15, 0.15, 4.5), (-2.6, -4.5 + k * 1.6, 3.4), (60, 60, 66), metal=0.7))
    import mathutils
    T = mathutils.Matrix.Translation(Vector(at)) @ mathutils.Matrix.Rotation(math.radians(yaw), 4, "Z")
    for ob in parts:
        ob.matrix_world = T @ ob.matrix_world


def screen(size, at, rgb, strength=2.5, frame_rgb=(30, 30, 36), yaw=0.0):
    box((size[0] + 0.6, 0.6, size[1] + 0.6), at, frame_rgb, rot=(0, 0, yaw))
    a = math.radians(yaw)
    glowbox((size[0], 0.2, size[1]), (at[0] - math.sin(a) * 0.35, at[1] + math.cos(a) * 0.35, at[2]), rgb, strength,
            rot=(0, 0, yaw))


def bars(at, w, h, d, rgb=(70, 70, 78), step=0.7):
    x, y, z = at
    n = int(w / step)
    for k in range(n + 1):
        cyl(0.07, 0.07, h, (x - w / 2 + k * step, y + d / 2, z + h / 2), rgb, segs=6, metal=0.7)
    box((w, d, 0.2), (x, y, z + h), rgb, metal=0.6)
    box((w, d, 0.2), (x, y, z + 0.1), rgb, metal=0.6)


def tree(at, rgb=(90, 160, 70), h=6):
    cyl(0.4, 0.3, h * 0.5, (at[0], at[1], h * 0.25), (110, 80, 50))
    ball(h * 0.35, (at[0], at[1], h * 0.65), rgb, rough=0.9)


# ------------------------------------------------------------------ the world and camera
def setup(p):
    global CAM
    P.setup(RES, transparent=False)
    sky = tuple(p["sky"])
    C.sky(top=darker(sky, 0.15), horizon=lighter(sky, 0.35), ambient=lighter(sky, 0.2), ambient_strength=1.0)
    s = bpy.context.scene
    s.view_settings.view_transform = "Standard"
    for ob in list(bpy.data.objects):
        if ob.type == "LIGHT":
            bpy.data.objects.remove(ob)


def people_box():
    pts = []
    for ob in C.collection("People").all_objects:
        if ob.type == "MESH" and not ob.hide_render:
            pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    return pts


def camera(loc, target, lens=35, k=0.62, fill=0.72):
    """The panel's camera, looking the way loc -> target does. With people on the set (and no k=1, a wide shot
    placed by hand) it frames them: their group fills `fill` of the panel's height (the middle of a 2:1 render,
    which every panel shape crops to), centred a little low so heads never touch the top."""
    global CAM
    pts = people_box() if k != 1 else []
    if pts:
        d = (Vector(target) - Vector(loc)).normalized()
        right = d.cross(Vector((0, 0, 1))).normalized()
        up = right.cross(d).normalized()
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        c = (lo + hi) / 2
        hw = max(abs((p - c).dot(right)) for p in pts)
        hh = max(abs((p - c).dot(up)) for p in pts)
        hd = max(abs((p - c).dot(d)) for p in pts)
        tan_v, tan_h = 9.0 / lens, 18.0 / lens
        dist = max(hh / (tan_v * fill), hw / (tan_h * 0.8)) + hd
        target = c + up * hh * 0.12
        loc = target - d * dist
    else:
        loc = Vector(target) + (Vector(loc) - Vector(target)) * k
    CAM = C.camera(tuple(loc), tuple(target), lens)
    return CAM


def sun(rot=(50, 10, 30), energy=3.5, rgb=(255, 244, 226)):
    C.sun(rot, energy, rgb)


def finish(p):
    # a soft fill from the camera's side, so faces read in the night and indoor panels (comic art is never murky)
    if CAM:
        d = CAM.matrix_world.to_3x3() @ Vector((0, 0, -1))
        at = CAM.location - d * 2 + Vector((0, 0, 6))
        C.area(tuple(at), tuple(CAM.location + d * 30), 1800, (255, 246, 236), size=16)
    for fn in PENDING:
        fn()
    PENDING.clear()
    P.ink(["People", "Props"], 2.3)
    path = os.path.join(P.RAW, "panel_%s.png" % p["key"])
    kit.render(path)
    print("panels.py: rendered", path, flush=True)


def word_hint(p):
    return p.get("word")


# ------------------------------------------------------------------ the scenes
def city_day(p, seed=3):
    g = tuple(p["ground"])
    ground(g)
    box((300, 12, 0.3), (0, -10, 0.15), (60, 60, 66), bev=0, coll=C.collection("Set"))  # the street
    skyline(y=-80, rgb=g, seed=seed, hmin=30, hmax=90)
    sun()


def city_night(p, seed=4, lit=0.35):
    sky = tuple(p["sky"])
    ground(tuple(p["ground"]))
    skyline(y=-150, x0=-400, x1=400, rgb=darker(sky, 0.4), seed=seed, hmin=50, hmax=190, lit=lit, kitfronts=False)
    stars()
    C.lamp((0, 20, 30), 4000, (190, 200, 255), size=20)
    sun((60, 0, -30), 0.6, (150, 170, 255))


def S_lastStand(p, i):
    if i == 1:
        city_day(p)
        for k, (x, y, yaw, pose) in enumerate([(-6, 4, 20, "relaxed"), (-2, 8, -30, "wave"), (5, 5, 160, "stand"),
                                              (9, 2, -60, "relaxed")]):
            fig(citizen(10 + k), (x, y, 0), yaw, pose)
        camera((0, 34, 4), (0, 0, 4), 32, fill=0.5)
    elif i == 2:
        city_day(p, seed=8)
        sun((45, 0, 60), 4.0, (255, 210, 170))
        fig(hero(cape=(30, 70, 200), clothes="heroes/preview/Hero2", hair={"asset": 376526888}), (-7, 2, 0), 60, "punch")
        fig(hero(cape=(240, 190, 40), clothes="heroes/preview/Hero3", face={"image": 7074712}), (-10, -2, 0), 40, "fist")
        fig(hero(cape=(220, 60, 60), clothes="heroes/preview/Hero4", hair={"asset": 553722174}), (-4, -4, 0), 70,
            "point")
        for k, x in enumerate((5, 9, 13)):
            fig(robot("SparkDrone", k), (x, -1 + k * 2, 0), -110, "punch" if k == 0 else "hold")
        burst((0, 0, 4.5), (255, 220, 120), 3.5)
        camera((0, 30, 5), (0, 0, 4), 38)
    elif i == 3:
        city_day(p, seed=9)
        box((30, 24, 30), (0, -50, 15), (200, 200, 205), coll=C.collection("Set"))
        burst((0, -45, 26), (255, 230, 150), 26, rays=14, strength=6)
        C.chunks(Vector((0, -45, 26)), 30, 40, seed=3)
        camera((0, 60, 12), (0, -40, 22), 35, k=1)
        smoke(Vector((0, -50, 12)), 22, 18, seed=2)
    else:
        g = tuple(p["ground"])
        ground(g)
        bowl = kit.sphere("crater", 40, at=(0, 0, 0), scale=(1, 1, 0.25), segs=48, rings=24)
        bowl.location = (0, -30, 2)
        bowl.data.materials.append(C.flat("crater", darker(g, 0.3), rough=1.0))
        C.put(bowl, C.collection("Set"))
        ring(40, 1.2, (0, -30, 1.5), (255, 120, 60), 1.5)
        for k in range(7):
            a = k * 0.9
            box((10, 10, 12 + k * 4), (math.cos(a) * 60, -30 + math.sin(a) * 50 - 40, 6 + k * 2), darker(g, 0.1),
                rot=(k * 3, -k * 4, k * 20), coll=C.collection("Set"))
        camera((0, 60, 30), (0, -30, 0), 35, k=1)
        smoke(Vector((0, -30, 6)), 25, 14, seed=4, rgb=(150, 140, 150), alpha=0.6)
        sun((60, 0, 40), 2.0, (200, 200, 255))


def S_wrenStory(p, i):
    if i == 1:
        city_day(p, seed=5)
        box((50, 14, 20), (0, -14, 10), (235, 235, 240), coll=C.collection("Set"))
        for k in range(5):
            glowbox((5, 0.4, 6), (-18 + k * 9, -6.8, 13), (150, 210, 255), 0.8)
        box((8, 0.6, 10), (0, -6.8, 5), (70, 110, 170))
        ring(5, 0.6, (0, -6, 24), (255, 220, 90), 5, axis="Y")
        fig("wren", (-9, 10, 0), 20, "wave")
        camera((0, 40, 7), (0, -4, 11), 32, fill=0.35)
    elif i == 2:
        room((60, 70, 110), (120, 90, 70), w=50, d=24)
        box((30, 10, 1.4), (0, -4, 0.7), (150, 100, 60))
        C.lamp((0, 0, 20), 3000, (255, 240, 200), size=6)
        fig("halo", (-2, -3, 1.4), 15, "point")
        fig("wren", (3, -1, 1.4), -20, "cheer")
        camera((0, 34, 8), (0, -2, 5), 34)
    elif i == 3:
        room((40, 50, 60), (50, 50, 60), w=50, d=24)
        pod = cyl(2.4, 2.4, 7, (-7, -2, 3.5), (160, 230, 255))
        pod.data.materials[0] = C.glow_mat("pod", (160, 230, 255), 0.5, additive=True)
        fig("wren", (-7, -2, 0), 30, "cower")
        glowbox((10, 0.5, 0.5), (-1, -2, 4), (120, 255, 160), 6)
        fig("copy", (6, -2, 0), -40, "fist")
        burst((4, -2, 4), (120, 255, 160), 3)
        C.lamp((0, 10, 16), 2000, (140, 255, 170), size=8)
        camera((0, 26, 6), (0, -2, 4), 36)
    else:
        city_day(p, seed=6)
        sun((70, 0, -60), 3.0, (255, 160, 100))
        fig("wren", (0, 2, 0), -70, "run")
        streaks((6, 2, 3), (1, 0, 0), (255, 240, 220), 8, 6)
        camera((-4, 26, 4), (0, 0, 5), 38)


def S_tobyStory(p, i):
    if i == 1:
        city_day(p, seed=11)
        box((36, 12, 16), (0, -12, 8), (245, 225, 190), coll=C.collection("Set"))
        for k in range(6):
            box((6, 3, 1.2), (-15 + k * 6, -5, 12), (230, 70, 80) if k % 2 == 0 else (250, 250, 250), rot=(-20, 0, 0))
        glowbox((14, 0.4, 6), (-6, -5.8, 5), (150, 210, 255), 0.8)
        cyl(3, 3, 0.6, (8, -5.6, 14), (250, 245, 230), axis="Y")
        fig("toby", (-2, 4, 0), 20, "wave", scale=0.75)
        fig("toymaker", (4, 2, 0), -25, "point")
        camera((0, 34, 6), (0, -2, 8), 34, fill=0.5)
    elif i == 2:
        city_day(p, seed=12)
        fig("toby", (0, 2, 0), 0, "hold", scale=0.75,
            extra=lambda M: [C._apply(kit.sphere("bear", 0.8, at=(0, 2.0, 3.0), segs=16, rings=10), M["UpperTorso"])])
        for k in range(6):
            a = k * 1.05
            x, y = math.cos(a) * 7, math.sin(a) * 4 - 1
            box((1.4, 1.4, 2.2), (x, y, 1.1), [(230, 80, 80), (80, 160, 230), (240, 200, 60)][k % 3], rot=(0, 0, k * 30))
            cyl(0.4, 0.4, 0.1, (x, y - 0.75, 1.6), (215, 170, 70), axis="Y", metal=0.8)
        burst((0, 0, 4), (255, 220, 120), 2.5)
        camera((0, 22, 5), (0, 0, 3), 36)
    elif i == 3:
        room((140, 110, 90), (110, 80, 60))
        fig("toymaker", (-3, -2, 0), 30, "punch")
        C.chunks(Vector((1, -2, 4)), 3, 12, seed=6, size=(0.3, 0.9),
                 mats=[C.flat("toy", (230, 80, 80)), C.flat("toy2", (80, 160, 230))])
        fig("toby", (6, 2, 0), -40, "cower", scale=0.75)
        camera((0, 24, 5), (1, 0, 4), 36)
    else:
        room((50, 50, 70), (60, 55, 60))
        tank = cyl(4, 4, 10, (0, -6, 5), (100, 180, 255))
        tank.data.materials[0] = C.glow_mat("tank", (90, 170, 255), 1.4)
        for k in range(4):
            cyl(0.5, 0.5, 14, (-10 + k * 6, -9, 10), (120, 120, 130), metal=0.6, rot=(0, 90 if k % 2 else 0, 0))
        box((6, 4, 3), (-9, -3, 1.5), (90, 90, 100), metal=0.5)
        C.lamp((0, 6, 12), 1500, (120, 180, 255), size=6)
        fig("toymaker", (8, 0, 0), -60, "hands")
        camera((0, 28, 7), (0, -4, 5), 36)


def S_kingStory(p, i):
    g = tuple(p["ground"])
    if i == 1:
        ground(g)
        sun((40, 0, 20), 5.0, (255, 200, 140))
        box((14, 12, 10), (-18, -26, 5), (170, 60, 50))
        cyl(9, 0.5, 6, (-18, -26, 13), (120, 50, 40), segs=4, rot=(0, 0, 45))
        for k in range(30):
            r = random.Random(k)
            cyl(0.1, 0.05, 2, (r.uniform(-20, 20), r.uniform(-10, 6), 1), (150, 120, 70))
        ball(8, (40, -200, 60), (255, 240, 180), emit=6)
        fig("harvest", (4, 2, 0), -20, "relaxed")
        camera((0, 28, 6), (0, -6, 5), 34)
    elif i == 2:
        ground(g)
        sun()
        fig("harvest", (-3, 1, 0), 30, "hands")
        for k in range(9):
            r = random.Random(k + 3)
            x, y = r.uniform(0, 10), r.uniform(-4, 3)
            h = r.uniform(2, 6)
            cyl(0.2, 0.15, h, (x, y, h / 2), (70, 150, 60))
            ball(h * 0.3, (x, y, h), (90, 200, 80))
        camera((0, 24, 5), (2, 0, 3), 36)
        sparks(Vector((4, 0, 3)), 3, 24, seed=3, rgb=(140, 255, 120))
    elif i == 3:
        ground(g)
        sun((50, 0, 30), 3.0, (255, 220, 190))
        beast((6, -6, 0), -30, 3.2)
        fig("harvest", (-6, 4, 0), 30, "point")
        camera((-2, 34, 8), (2, -4, 9), 34, k=0.8)
    else:
        ground((90, 140, 60))
        sun()
        for k in range(20):
            r = random.Random(k)
            tree((r.uniform(-40, 40), r.uniform(-50, -15)), (80, 170, 70), r.uniform(5, 9))
        beast((7, -10, 0), -20, 3.6)
        fig("harvest", (-3, 4, 0), 10, "fist")
        camera((0, 34, 8), (1, -4, 9), 34, k=0.8)


def beast(at, yaw, scale):
    """The Bramblebeast: its own finale model (art/export/finales/Bramblebeast.fbx, Config.FinaleArt)."""
    import json
    import mathutils
    pages = json.load(open(os.path.join(REPO, "art", "export", "rogues", "pages.json")))
    art = next(pg["finaleArt"] for pg in pages if pg.get("finaleName") == "Bramblebeast")
    obs = P.R["finale"]("Bramblebeast", art)
    bpy.context.view_layer.update()
    T = mathutils.Matrix.Translation(Vector(at)) @ mathutils.Matrix.Rotation(math.radians(yaw), 4, "Z") @ \
        mathutils.Matrix.Scale(scale, 4)
    for ob in obs:
        ob.matrix_world = T @ ob.matrix_world
        C.put(ob, C.collection("People"))


def S_brineLegend(p, i):
    if i == 1:
        water((40, 110, 150))
        box((8, 40, 1), (0, -6, 1.5), (140, 100, 60))
        for k in range(5):
            cyl(0.4, 0.4, 5, (-3.6, -20 + k * 8, 0), (110, 80, 50))
            cyl(0.4, 0.4, 5, (3.6, -20 + k * 8, 0), (110, 80, 50))
        cyl(3, 2.4, 22, (30, -80, 11), (240, 240, 240))
        glowbox((4, 4, 3), (30, -80, 23.5), (255, 230, 150), 4)
        sun((50, 0, 40), 3.5)
        fig("brine", (0, 2, 2), 20, "relaxed")
        camera((0, 26, 7), (0, -4, 5), 36)
    elif i == 2:
        ground((60, 80, 90))
        bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
        C.lamp((0, 0, 30), 6000, (120, 200, 255), size=30)
        fig("brine", (-5, 2, 0), 40, "hold")
        cyl(0.3, 0.3, 30, (2, -1, 18), (90, 90, 96), metal=0.8)
        fig(robot("Diver", 3), (3, -1, 0), -60, "stand")
        fig(robot("Anchor", 4), (8, -3, 0), -50, "relaxed")
        sparks(Vector((2, 0, 4)), 6, 30, seed=8, rgb=(200, 240, 255),
                 size=(0.2, 0.5), strength=3)
        camera((0, 26, 5), (1, -1, 4), 36)
    elif i == 3:
        water((30, 50, 70))
        C.lamp((0, 0, 40), 5000, (160, 255, 200), size=40)
        ship((0, -18, 0), 0)
        fig(robot("SaltDog", 2), (-4, -16, 5.6), 20, "point")
        fig(robot("SaltDog", 5), (4, -16, 5.6), -10, "fist")
        camera((0, 34, 12), (0, -16, 10), 34, k=0.8)
        smoke(Vector((0, -4, 2)), 26, 12, seed=3, rgb=(200, 220, 230), alpha=0.35)
    else:
        water((30, 90, 110))
        for k in range(9):
            a = math.pi * k / 8
            ball(9, (math.cos(a) * 28, -18 - math.sin(a) * 4, math.sin(a) * 22), (90, 80, 70), scale=(1, 0.8, 1.2),
                 rough=1.0)
        for k in range(4):
            box((3, 2, 2), (-8 + k * 5, -6, 1.2), (150, 100, 50))
            box((3.1, 2.1, 0.5), (-8 + k * 5, -6, 2.3), (230, 190, 60), metal=0.8)
        C.lamp((0, 10, 16), 2500, (255, 220, 160), size=8)
        fig("brine", (5, 1, 0), -30, "point")
        camera((0, 30, 6), (0, -6, 6), 34)


def ship(at, yaw):
    """The ghost ship side on: a dark hull, a deck and three masts with glowing sails."""
    x, y, z = at
    box((34, 9, 6), (x, y, z + 2), (60, 50, 48))
    box((30, 8, 0.6), (x, y, z + 5.3), (100, 85, 70))
    box((6, 8, 4), (x - 13, y, z + 7), (70, 58, 52))
    for k, h in enumerate((20, 24, 17)):
        cx = x - 9 + k * 9
        cyl(0.4, 0.3, h, (cx, y, z + h / 2 + 5), (80, 60, 50))
        glowbox((6, 0.3, h * 0.42), (cx, y + 0.5, z + h * 0.62 + 5), (150, 255, 190), 0.45)


def S_pitStory(p, i):
    g = tuple(p["ground"])
    if i == 1:
        ground(g)
        for k in range(5):
            box((120 - k * 18, 30, 4), (0, -30 - k * 8, k * 4 + 2), darker(g, k * 0.06), coll=C.collection("Set"))
        box((10, 2, 10), (0, -14, 5), (30, 26, 24))
        for s in (-1, 1):
            box((1, 1, 11), (s * 5.5, -13.5, 5.5), (120, 90, 60))
        box((12, 1, 1), (0, -13.5, 11), (120, 90, 60))
        fig("pitboss", (6, 2, 0), -30, "relaxed")
        fig(citizen(31), (-6, 1, 0), 30, "point")
        sun((45, 0, 30), 3.0, (255, 210, 170))
        camera((0, 30, 8), (0, -10, 7), 34, fill=0.4)
    elif i == 2:
        room((80, 70, 60), (90, 80, 70))
        fig("pitboss", (0, 0, 0), 15, "fist")
        C.chunks(Vector((0, 0, 4)), 4, 16, seed=4, size=(0.3, 0.8), mats=[C.flat("rock", (150, 140, 130))])
        burst((0, -1, 4), (255, 200, 120), 4)
        C.lamp((4, 8, 10), 2000, (255, 200, 150), size=4)
        camera((0, 20, 5), (0, 0, 4), 38)
    else:
        ground((200, 180, 140))
        box((24, 24, 1), (0, -4, 0.5), (210, 190, 150))
        for x in (-12, 12):
            for y in (-16, 8):
                cyl(0.4, 0.4, 5, (x, y, 3), (40, 40, 44))
        for h in (2.5, 4):
            for s in (-12, 12):
                glowbox((0.2, 24, 0.2), (s, -4, h), (255, 80, 60), 3)
            glowbox((24, 0.2, 0.2), (0, -16, h), (255, 80, 60), 3)
        for k in range(16):
            r = random.Random(k)
            box((2, 1, 3), (-30 + k * 4, -34 - r.random() * 4, 3 + r.random() * 5), (40, 30, 30))
        C.lamp((0, 0, 30), 9000, (255, 240, 210), size=8)
        if i == 3:
            fig("pitboss", (0, -4, 1), 10, "fist")
        else:
            fig("pitboss", (2, -4, 1), -30, "cheer")
            fig(("hero", (200, 40, 50)), (-4, -2, 1), 0, "kneel")
        camera((0, 28, 9), (0, -4, 4), 36)


def S_tidewrightTale(p, i):
    if i == 1:
        water((60, 150, 180))
        ground((220, 200, 150), size=80)
        for k in range(7):
            h = 18 + (k * 7) % 20
            cyl(3, 2.2, h, (-24 + k * 8, -20 - (k % 2) * 6, h / 2), (200, 150, 80), metal=0.6, rough=0.3)
            ball(2.6, (-24 + k * 8, -20 - (k % 2) * 6, h + 1), (230, 190, 90), metal=0.7)
        sun((40, 0, 30), 4.5)
        camera((0, 40, 10), (0, -16, 10), 34, k=1)
    elif i == 2:
        water((40, 60, 90))
        for k in range(6):
            h = 18 + (k * 7) % 20
            cyl(3, 2.2, h, (-24 + k * 9, -24, h / 2 - 6), (150, 120, 80), metal=0.5, rot=(0, (k - 3) * 5, 0))
        for k in range(5):
            wv = kit.sphere("wave", 10, at=(0, 0, 0), scale=(2.2, 0.6, 0.8), segs=24, rings=12)
            wv.location = (-28 + k * 14, -12 + (k % 2) * 3, 2)
            wv.data.materials.append(C.flat("wave", (70, 140, 200), rough=0.15))
            C.put(wv, C.collection("Props"))
            ball(4, (-26 + k * 14, -9 + (k % 2) * 3, 6), (235, 245, 255), scale=(1.6, 0.6, 0.5))
        C.lightning(Vector((14, -40, 60)), Vector((8, -26, 20)), (200, 220, 255), seed=3, coll=C.collection("Fx"))
        C.lamp((0, 20, 40), 4000, (200, 220, 255), size=40)
        camera((0, 40, 10), (0, -12, 9), 34, k=1)
        streaks((0, -6, 22), (0.25, 0, -1), (200, 220, 255), 30, 12, seed=4)
    elif i == 3:
        ground((40, 70, 80))
        C.lamp((0, 0, 30), 6000, (100, 220, 220), size=30)
        for k in range(5):
            cyl(1.4, 1.4, 12 - k, (-16 + k * 8, -14, 6 - k / 2), (150, 130, 100))
        fig("tidewright", (0, -2, 0), 0, "relaxed", scale=1.7)
        sparks(Vector((0, -2, 8)), 9, 30, seed=2, rgb=(200, 255, 255),
                 size=(0.2, 0.5), strength=3)
        camera((0, 30, 7), (0, -4, 7), 36)
    else:
        ground((40, 60, 70))
        C.lamp((0, 0, 30), 5000, (100, 200, 220), size=30)
        cyl(2.5, 2.5, 12, (-8, 0, 6), (240, 170, 40), metal=0.5, rot=(0, -50, 0))
        cyl(2.5, 0.2, 4, (-1.5, 0, 1.5), (180, 180, 190), metal=0.8, rot=(0, -50, 0))
        glowbox((14, 0.3, 0.4), (4, -3, 0.3), (120, 255, 230), 6, rot=(0, 0, 20))
        fig("tidewright", (8, -4, 0), -40, "fist", scale=1.5)
        burst((0, 0, 1), (120, 255, 230), 4)
        camera((0, 30, 7), (1, -2, 5), 36)


def S_vesperStory(p, i):
    if i == 1:
        city_night(p, lit=0.25)
        fig("lodestar", (-5, 0, 14), 70, "fly", tilt=(-60, 0))
        fig("vesper", (5, -2, 16), 70, "fly", tilt=(-60, 0))
        ball(14, (60, -400, 140), (250, 245, 220), emit=3)
        camera((0, 34, 12), (0, 0, 14), 34)
    elif i == 2:
        room((120, 60, 70), (200, 190, 170), w=40, d=24)
        glowbox((24, 0.4, 9), (0, -11.4, 9), (60, 80, 140), 0.8)
        box((10, 5, 0.5), (0, -4, 3.1), (240, 240, 235))
        cyl(0.3, 0.3, 3, (0, -4, 1.5), (90, 90, 96), metal=0.6)
        for s_ in (-1, 1):
            box((10, 2.4, 1.8), (0, -4 + s_ * 3.6, 0.9), (200, 50, 60))
            box((10, 0.8, 4.6), (0, -4 + s_ * 5.2, 2.3), (200, 50, 60))
            cyl(0.4, 0.35, 0.8, (s_ * 1.6, -4 + s_ * 0.8, 3.75), (250, 250, 250))
        C.lamp((0, -2, 12), 2500, (255, 220, 170), size=4)
        fig("lodestar", (-1.5, -0.4, 1.55), 180, "sit")
        fig("vesper", (1.5, -7.6, 1.55), 0, "sit")
        camera((18, 2, 9), (0, -4, 3.6), 34, k=0.75)
    elif i == 3:
        water((30, 40, 60))
        box((30, 14, 14), (0, -24, 7), (90, 70, 60))
        burst((0, -20, 12), (255, 140, 50), 14, rays=12)
        C.lamp((0, -14, 10), 9000, (255, 140, 60), size=10)
        fig("vesper", (-8, 0, 10), 120, "fly", tilt=(-50, 0))
        camera((0, 34, 8), (-2, -10, 10), 34)
        smoke(Vector((0, -28, 22)), 18, 16, seed=5, rgb=(70, 60, 60), alpha=0.8)
    else:
        city_night(p, lit=0.2)
        screen((26, 14), (0, -20, 16), (250, 200, 120), 2.5)
        fig("vesper", (0, -19, 10), 0, "wave", scale=1.6)
        fig("lodestar", (2, 10, 0), 170, "relaxed")
        camera((6, 24, 6), (0, -12, 12), 34)


def S_larkStory(p, i):
    if i == 1:
        city_day(p, seed=14)
        box((30, 20, 1), (0, -2, 6), (120, 110, 110))
        box((30, 20, 6), (0, -2, 3), (160, 140, 130))
        fig("patch", (-4, 0, 6.5), 30, "kneel", scale=0.85)
        box((1.6, 1.2, 1.2), (-2.5, 1.5, 7.1), (60, 60, 66), metal=0.4)
        fig("lark", (5, -1, 9), 60, "fly", tilt=(-55, 0))
        camera((0, 30, 10), (0, -2, 9), 34)
    elif i == 2:
        city_night(p, lit=0.2)
        van((-6, -6, 0), 100, (60, 70, 60), cage=True)
        fig("catchpole", (5, 0, 0), -40, "point")
        fig("lark", (-1, 4, 0), 20, "cower")
        net = kit.sphere("net", 2.6, at=(0, 0, 0), scale=(1, 1, 1.2), segs=12, rings=8)
        net.location = (-1, 4, 2.8)
        mod = net.modifiers.new("W", "WIREFRAME")
        mod.thickness = 0.06
        net.data.materials.append(C.flat("net", (220, 220, 210)))
        C.put(net, C.collection("Props"))
        camera((0, 26, 6), (0, 0, 4), 36)
    elif i == 3:
        room((70, 70, 80), (60, 60, 66), w=50, d=30)
        C.lamp((0, 0, 14), 1200, (255, 90, 80), size=4)
        for k in range(4):
            bars((-15 + k * 10, -4, 0), 8, 8, 6)
        fig("lark", (-5, -4, 0), 20, "sit")
        ring(0.62, 0.1, (-5, -4, 0), (255, 80, 70), 4)  # placed on the neck below
        camera((0, 26, 6), (0, -4, 4), 36)
    else:
        city_night(p, lit=0.3)
        box((16, 16, 1), (0, -2, 8), (90, 90, 100))
        box((16, 16, 8), (0, -2, 4), (110, 110, 120))
        cyl(0.2, 0.1, 10, (3, -4, 13), (200, 200, 210), metal=0.7)
        for k in range(3):
            ring(2 + k * 2.2, 0.12, (3, -4, 18), (120, 230, 255), 4, axis="Y")
        fig("patch", (-2, 0, 8.5), 20, "hands", scale=0.85)
        camera((0, 26, 12), (0, -2, 12), 36)


def S_scorchStory(p, i):
    if i == 1:
        city_day(p, seed=21)
        for k in range(3):
            box((14, 10, 9), (-16 + k * 15, -14, 4.5), (150, 140, 130))
            box((10, 0.4, 6), (-16 + k * 15, -8.9, 3), (90, 90, 96), metal=0.5)
        van((-8, 2, 0), 90, (220, 120, 40))
        fig("scorch", (5, 3, 0), -30, "fist")
        glow(Vector((4.2, 3.5, 7.3)), 1.4, (255, 150, 40), strength=6)
        camera((0, 30, 6), (0, -4, 5), 34)
    elif i == 2:
        city_night(p, lit=0.15)
        box((20, 12, 12), (0, -14, 6), (150, 120, 100))
        burst((0, -8, 7), (255, 140, 40), 9, rays=12)
        C.lamp((0, -4, 8), 9000, (255, 140, 60), size=8)
        fig("scorch", (-8, 4, 0), 30, "point")
        camera((0, 30, 6), (-2, -4, 6), 34)
        smoke(Vector((0, -16, 16)), 12, 12, seed=7, rgb=(60, 50, 50), alpha=0.8)
    elif i == 3:
        room((70, 30, 80), (40, 20, 40), w=44, d=24)
        C.lamp((0, 0, 12), 1500, (230, 150, 255), size=6)
        box((4.4, 3, 1.8), (0, -6, 0.9), (120, 40, 60))
        box((4.4, 1, 6), (0, -7.6, 3), (120, 40, 60))
        fig("Vanta", (0, -5.6, 1.55), 10, "sit")
        for k in (-1, 1):
            cyl(0.15, 0.15, 6, (k * 7, -8, 3), (220, 190, 80), metal=0.8)
            ball(0.8, (k * 7, -8, 6.5), (255, 220, 150), emit=4)
        fig("scorch", (8, 4, 0), -150, "relaxed")
        camera((-4, 22, 6), (1, -3, 4), 36)
    else:
        city_night(p, lit=0.25)
        fig("Vanta", (-3, 0, 0), 30, "point")
        fig(("hero", (40, 40, 50)), (3, 2, 0), -40, "relaxed")
        camera((0, 22, 5), (0, 0, 4), 38)


def S_cutStory(p, i):
    if i == 1:
        room((60, 70, 100), (60, 50, 50))
        box((14, 4, 3), (0, -6, 1.5), (90, 70, 60))
        screen((14, 8), (0, -10.5, 8), (40, 90, 170), 1.6)
        for k, h in enumerate((3, 5, 2.4, 4, 3.4)):
            glowbox((1.6, 0.2, h), (-4 + k * 2, -9.9, 5.2 + h / 2), (20, 40, 90), 1.0)
        glowbox((13, 0.2, 1.4), (0, -9.8, 5.0), (230, 40, 40), 2.0)
        glowbox((3, 0.2, 1.4), (-5, -9.75, 5.0), (255, 255, 255), 2.5)
        fig("Nora", (6, -2, 0), -30, "relaxed")
        C.lamp((0, 8, 12), 1500, (255, 230, 200), size=8)
        camera((0, 24, 6), (0, -6, 6), 34)
    elif i == 2:
        room((30, 30, 36), (30, 30, 36))
        for k in range(3):
            if k == 1:
                screen((9, 6), (-11 + k * 11, -10, 8), (10, 10, 12), 0.1)
            else:
                screen((9, 6), (-11 + k * 11, -10, 8), (120, 160, 220), 1.6)
        fig("censor", (0, -2, 0), 0, "fist")
        C.lamp((0, 10, 10), 800, (200, 200, 220), size=8)
        camera((0, 22, 6), (0, -4, 6), 36)
    elif i == 3:
        city_night(p, lit=0.3)
        van((-4, -4, 0), 80, (240, 240, 245), dish=True)
        fig("Nora", (5, 2, 0), -30, "point")
        cyl(0.1, 0.1, 4, (8, 0, 2), (40, 40, 46))
        box((1.2, 1.8, 1), (8, 0, 4.4), (40, 40, 46))
        camera((0, 26, 6), (0, -2, 5), 34)
    else:
        city_night(p, lit=0.25)
        for k in range(5):
            screen((10, 6), (-30 + k * 15, -55, 26 + (k % 2) * 10), (255, 240, 200), 3.0)
        glowbox((0.6, 0.6, 60), (0, -10, 30), (255, 240, 180), 5, rot=(20, 0, 0))
        camera((0, 40, 8), (0, -30, 22), 34, k=1)


def S_kindlerTruth(p, i):
    if i == 1:
        room((235, 240, 245), (210, 215, 220))
        ring(4, 0.35, (0, -4, 4), (255, 200, 120), 5, axis="Y")
        box((3, 3, 2), (0, -4, 1), (200, 200, 210))
        fig(citizen(41), (0, -4, 0.0), 10, "sit")
        fig("Okafor", (8, 0, 0), -40, "point")
        C.lamp((0, 10, 16), 2500, (255, 255, 255), size=10)
        camera((0, 28, 6), (2, -2, 5), 34)
    elif i == 2:
        room((60, 60, 80), (70, 70, 80))
        ring(4, 0.45, (0, -4, 4), (255, 230, 150), 9, axis="Y")
        box((3, 3, 2), (0, -4, 1), (200, 200, 210))
        fig(("hero", None), (0, -4, 0), 10, "sit")
        burst((0, -4, 5), (255, 220, 120), 6)
        camera((0, 22, 6), (0, -4, 5), 36)
    elif i == 3:
        city_night(p, lit=0.15)
        box((30, 14, 16), (0, -16, 8), (200, 200, 205))
        for k in range(5):
            box((5, 0.6, 1), (-12 + k * 6, -8.8, 6), (140, 100, 60), rot=(0, 20 * (k % 2 * 2 - 1), 0))
        glowbox((4, 0.4, 3), (8, -8.8, 12), (255, 240, 180), 3)
        fig("holloway", (6, -4, 0), 20, "relaxed")
        camera((0, 24, 6), (0, -8, 7), 34, fill=0.45)
    else:
        spark_end(p, 1)


def spark_end(p, seed):
    """The origin lines' last panel: your Spark (each line its own pose, cape and glow)."""
    city_night(p, seed=seed + 30, lit=0.25)
    pose, cape, glow_rgb, yaw = [("fist", (200, 40, 50), (255, 220, 120), 15),
                                 ("cheer", (40, 90, 200), (150, 220, 255), -15),
                                 ("hands", (90, 40, 140), (200, 140, 255), 25),
                                 ("point", (30, 120, 90), (140, 255, 180), -25),
                                 ("fist", (220, 150, 40), (255, 190, 90), 0)][(seed - 1) % 5]
    fig(("hero", cape), (0, 0, 0), yaw, pose)
    aura((0, 0, 0), glow_rgb, 6)
    camera((0, 20, 3), (0, 0, 4.5), 36, fill=0.62)


def S_masterLesson(p, i):
    if i in (1, 2):
        room((230, 220, 190), (190, 150, 100), w=44, d=26)
        for k in range(5):
            box((0.6, 0.6, 18), (-20 + k * 10, -12.5, 9), (110, 70, 40))
        gi = dict(HERO, clothes=None, outfit={"shirt": "Tee", "shirtTint": (245, 245, 245), "pants": "Joggers",
                                              "pantsTint": (245, 245, 245)})
        if i == 1:
            fig("hoshi", (-4, -2, 0), 30, "point")
            fig(gi, (4, 0, 0), -40, "punch")
            C.lamp((0, 10, 14), 1500, (255, 220, 180), size=8)
            camera((0, 24, 6), (0, -2, 5), 34)
        else:
            fig(gi, (0, 0, 0), -40, "kick")
            burst((0, 0, 4), (180, 240, 255), 5)
            streaks((0, 0, 4), (1, 0, 0.2), (230, 250, 255), 14, 8, seed=2)
            C.lamp((0, 10, 14), 1500, (255, 220, 180), size=8)
            camera((0, 22, 5), (0, 0, 4), 36)
    elif i == 3:
        city_day(p, seed=33)

        def rig(M):
            out = []
            for s in (-1, 1):
                j = kit.cyl("jet", 0.45, 0.35, 2.2, at=(s * 0.55, -0.85, 3.2), segs=16)
                j.data.materials.append(C.flat("jet", (60, 180, 190), metal=0.6, rough=0.3))
                out.append(C._apply(j, M["UpperTorso"]))
                fl = kit.cyl("flame", 0.3, 0.0, 1.6, at=(s * 0.55, -0.85, 1.4), segs=10)
                fl.data.materials.append(C.glow_mat("flame", (120, 240, 255), 6))
                out.append(C._apply(fl, M["UpperTorso"]))
            return out
        fig("gale", (0, 0, 3), -80, "fly", tilt=(-35, 0), extra=rig)
        streaks((5, 0, 5), (1, 0, 0), (200, 255, 255), 16, 10, seed=5)
        camera((-2, 24, 6), (1, 0, 5), 36)
    else:
        spark_end(p, 2)


def S_podMessage(p, i):
    if i == 1:
        ground(tuple(p["ground"]))
        stars(120)
        hill = kit.sphere("hill", 40, at=(0, 0, 0), scale=(1.4, 1, 0.35), segs=32, rings=16)
        hill.location = (10, -60, 0)
        hill.data.materials.append(C.flat("hill", (50, 60, 60), rough=1))
        C.put(hill, C.collection("Set"))
        ball(2.2, (-6, -30, 26), (255, 240, 200), emit=10)
        streaks((-14, -30, 36), (0.6, 0, -0.8), (255, 220, 160), 8, 30, seed=3)
        C.lamp((0, 20, 30), 1500, (150, 170, 255), size=20)
        camera((0, 40, 10), (0, -30, 18), 34, k=1)
        glow(Vector((-6, -30, 26)), 14, (255, 200, 120), strength=3)
    elif i == 2:
        ground((70, 90, 60))
        sun((50, 0, 30), 3.0, (255, 230, 200))
        pod = ball(2.4, (-6, -4, 1.4), (200, 205, 220), scale=(1, 1, 0.7), rough=0.3)
        pod.data.materials[0] = C.flat("pod", (200, 205, 220), metal=0.7, rough=0.3)
        glowbox((1.6, 0.3, 0.6), (-6, -1.8, 2.2), (150, 220, 255), 4)
        fig(citizen(51), (0, -2, 0), -20, "wave")
        fig("Moth", (4, -1, 0), -30, "relaxed")
        camera((0, 24, 6), (-1, -2, 4), 36)
    elif i == 3:
        ground(tuple(p["ground"]))
        stars(60)
        cyl(0.6, 0.2, 30, (6, -14, 15), (200, 60, 50), metal=0.6)
        glowbox((1.2, 1.2, 1.2), (6, -14, 30.5), (255, 80, 60), 6)
        for k in range(3):
            ring(1.4 + k * 1.2, 0.08, (-6, -10, 3), (180, 230, 255), 4, axis="Y")
        ball(2.0, (-6, -10, 2), (210, 215, 230), scale=(1, 1, 0.7), rough=0.3, emit=0.5)
        fig("Ruth", (2, 2, 0), -20, "hands")
        C.lamp((0, 10, 20), 1500, (180, 200, 255), size=20)
        camera((0, 30, 8), (0, -8, 9), 34)
    else:
        spark_end(p, 3)


def S_relicTruth(p, i):
    def stage():
        room((90, 20, 30), (120, 80, 50), w=50, d=24, h=24)
        box((40, 12, 2), (0, -6, 1), (120, 80, 50))
        for s in (-1, 1):
            box((10, 2, 22), (s * 18, -10, 11), (170, 30, 40))
        C.lamp((0, 10, 22), 3000, (255, 230, 170), size=3)
    if i == 1:
        stage()
        fig("ambrose", (0, -6, 2), 10, "bow")
        camera((0, 34, 9), (0, -4, 6), 34)
    elif i == 2:
        stage()
        fig("ambrose", (0, -6, 2), 0, "hold")
        ball(0.28, (0, -3.7, 5.0), (255, 200, 90), emit=3, metal=0.6)
        sparks(Vector((0, -3.7, 5.0)), 1.0, 16, seed=9, rgb=(255, 230, 150), size=(0.2, 0.5))
        camera((0, 12, 7), (0, -5, 6), 40)
    elif i == 3:
        stage()
        fig("morrow", (-6, -6, 2), 50, "lunge")
        camera((0, 28, 7), (0, -6, 5), 34)
        smoke(Vector((4, -7, 5)), 1.5, 6, seed=6, rgb=(230, 220, 255), alpha=0.7, size=(1.5, 3))
        burst((3, -6, 5), (200, 160, 255), 3)
    else:
        spark_end(p, 4)


def S_coreTruth(p, i):
    if i == 1:
        room((110, 100, 90), (90, 85, 80), w=46, d=26)
        box((10, 4, 3.4), (-6, -6, 1.7), (120, 90, 60))
        for k in range(8):
            r = random.Random(k)
            box((r.uniform(0.6, 1.6),) * 3, (r.uniform(-10, -2), r.uniform(-7, -5), 3.6 + r.random()), (150, 150, 160),
                metal=0.7, rot=(k * 20, k * 13, 0))
        fig("Tess", (2, -2, 0), -30, "hands")
        fig(("hero", (200, 40, 50)), (-3, 2, 0), 30, "relaxed")
        C.lamp((0, 6, 14), 2000, (255, 220, 180), size=6)
        camera((0, 26, 6), (-1, -2, 5), 34)
    elif i == 2:
        room((60, 60, 70), (70, 70, 76))

        def core(M):
            c = kit.cyl("core", 0.45, 0.45, 0.2, at=(0, 0.6, 3.3), segs=24, axis="Y")
            c.data.materials.append(C.glow_mat("core", (120, 230, 255), 8))
            return [C._apply(c, M["UpperTorso"])]
        fig(("hero", (200, 40, 50)), (0, 0, 0), 10, "fist", extra=core)
        burst((0, 1.2, 3.3), (120, 230, 255), 1.3, rays=8)
        sparks(Vector((0, 0, 3.5)), 2.5, 24, seed=3, rgb=(140, 230, 255))
        camera((0, 20, 5), (0, 0, 4), 38)
    elif i == 3:
        city_day(p, seed=41)
        van((-8, -6, 0), 100, (210, 170, 50))
        fig("clawback", (6, 2, 0), -30, "point")
        fig(robot("Grappler", 2), (0, -2, 0), -60, "hold")
        box((2, 2, 2), (-2, -2, 4.5), (120, 230, 255), emit=2)
        camera((0, 28, 6), (-1, -2, 5), 34)
    else:
        spark_end(p, 5)


SCENES = {"lastStand": S_lastStand, "wrenStory": S_wrenStory, "tobyStory": S_tobyStory, "kingStory": S_kingStory,
          "brineLegend": S_brineLegend, "pitStory": S_pitStory, "tidewrightTale": S_tidewrightTale,
          "vesperStory": S_vesperStory, "larkStory": S_larkStory, "scorchStory": S_scorchStory,
          "cutStory": S_cutStory, "kindlerTruth": S_kindlerTruth, "masterLesson": S_masterLesson,
          "podMessage": S_podMessage, "relicTruth": S_relicTruth, "coreTruth": S_coreTruth}


def render(p, panels_module):
    global P, CAM
    P = panels_module
    CAM = None
    setup(p)
    SCENES[p["page"]](p, p["index"])
    finish(p)
