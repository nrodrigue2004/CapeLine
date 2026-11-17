# art/store/thumbs.py: the three store thumbnail candidates (notes/Store Page.md, "Thumbnails (1920 x 1080), 3"),
# rendered into art/export/store/raw/; art/store/post.py grades them and adds the captions.
#   fly:   "Fly the city": the Comic hero banking down a street canyon of Downtown's skyscrapers at sunset, a tower
#          collapsing behind him in dust and chunks. Caption FLY. FIGHT. SAVE.
#   build: "Build your hero": four heroes side by side on a rooftop (Bruiser, Blaster, Speedster, Controller; two
#          Comic, two Anime, one in a villain look) with Titan, Volt, Pulse, Frost and Blade effects.
#          Caption HERO OR VILLAIN?
#   boss:  "World boss": a squad of heroes flying around the world boss (the remade RustjawPrime mesh) over
#          Downtown, beams and bolts on it, fireworks; post.py draws the boss bar. Caption GIANT WORLD BOSS.
# The city is the game's own layout (art/export/city/DowntownWide.json) and the boss the game's own mesh
# (art/export/Bosses.fbx); STORE_ASSETS=<another checkout>/art reads them from a newer checkout.
# Run: python art/store/thumbs.py <fly|build|boss> [--draft]   (with the `bpy` module, Blender 5.0)
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
from icons import ANIME, COMIC, FLIGHT_CAM, FLIGHT_CAPE, FLIGHT_FRONT, FLIGHT_POSE, FLIGHT_UP  # noqa: E402,E501
from mathutils import Matrix, Vector  # noqa: E402

WHICH = [a for a in sys.argv[1:] if not a.startswith("-")]
WHICH = WHICH[0] if WHICH else "fly"
RES = (1920, 1080)


def sunset_sky():
    C.sky(top=(38, 52, 130), horizon=(255, 170, 110), bottom=(255, 196, 150), mid=(150, 110, 170),
          ambient=(200, 170, 190), ambient_strength=0.75)


def collapsing(b, hbreak, tilt=14, drop=10, seed=1):
    """A tower breaking at hbreak: the base stays, the top leans over and slides down, with chunks and slabs."""
    sx, sy, sz = b["sx"], b["sy"], b["sz"]
    base = C.kit.box("base", sx, sz, hbreak, at=(sx / 2, sz / 2, hbreak / 2))
    base.location = C.rb(b["cx"] - sx / 2, 0, b["cz"] + sz / 2)
    m = C.kit_mat(b["kit"], b["color"] if b["kit"] in C.TINTED else None)
    base.data.materials.append(m)
    C.put(base, C.collection("City"))
    top_h = sy - hbreak - 6
    top = C.kit.box("top", sx, sz, top_h, at=(sx / 2, sz / 2, top_h / 2))
    top.data.materials.append(m)
    pivot = C.rb(b["cx"] + sx / 2, hbreak + 6 - drop, b["cz"])
    top.location = C.rb(b["cx"] - sx / 2, hbreak + 6 - drop, b["cz"] + sz / 2)
    C.put(top, C.collection("City"))
    # lean the top over its +x edge (toward the street)
    R = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-tilt), 4, "Y") @ Matrix.Translation(-pivot)
    top.matrix_world = R @ Matrix.Translation(top.location)  # (matrix_world is stale until an update)
    # the broken storeys: slabs and chunks spilling from the break
    c = C.rb(b["cx"], hbreak, b["cz"])
    C.chunks(c + Vector((10, 0, 0)), 26, 70, seed=seed, size=(1.5, 6.0), direction=(0.6, 0, -0.8), stretch=1.2,
             mats=[m, C.flat("conc", C.PALETTE["concrete"], rough=0.85), C.flat("conc2", (196, 190, 180), rough=0.85)])
    return c


def fly():
    C.settings(RES, samples=64, exposure=0.0, view="Standard")
    # over Downtown's south edge at sunset, looking north into the skyscrapers; one of them is coming down
    for_collapse = 26  # the 464-stud Panel tower in the middle of the view
    hbreak = 300

    def keep(b):
        return not (b.get("bid") == for_collapse and b["cy"] + b["sy"] / 2 > hbreak)

    C.layout("DowntownWide", keep=keep)
    tower = [b for b in json_boxes("DowntownWide") if b.get("bid") == for_collapse and b["kind"] == "building"][0]
    cam_at = C.rb(-392, 296, 470)
    look = C.rb(-530, 262, -160)
    cam = C.camera(cam_at, look, lens=24)
    v = (look - cam_at).normalized()
    R = v.cross(Vector((0, 0, 1))).normalized()
    U = R.cross(v).normalized()
    T = -v
    brk = collapsing(tower, hbreak, tilt=22, drop=10, seed=3)
    C.smoke(brk + Vector((6, 0, -10)), 20, 40, cam, seed=5, size=(26, 54), rgb=(250, 228, 210), alpha=0.85, up=0.3)
    C.smoke(brk + Vector((24, 0, -120)), 34, 30, cam, seed=6, size=(50, 90), rgb=(226, 206, 192), alpha=0.75,
            up=0.3)
    C.glow(brk + Vector((0, -20, 0)), 120, cam, (255, 170, 80), strength=1.0)
    # the hero in the left third: icon 1's flying pose, carried into this camera
    at, W = C.staged(cam_at, look, *FLIGHT_CAM, offset=(-4.6, 0.4, -2.5), turn=-24)
    root = Matrix.Translation(at) @ W.to_4x4() @ C.root_axes((0, 0, 0), FLIGHT_UP, FLIGHT_FRONT)
    M, hobs = C.hero(root, FLIGHT_POSE, cape_kw=dict(FLIGHT_CAPE, lift=1.4, length=6.4, flow=(3.4, -1.0, -0.4)), **COMIC)
    body = root @ C.CENTRE
    C.fog("City", (250, 186, 150), start=150, half=1100, strength=1.0)
    sunset_sky()
    # a low warm sun from behind the camera's left: the hero and the towers' fronts glow orange
    C.sun((80, 0, -32), energy=4.6, rgb=(255, 176, 110), angle=2)
    C.area(body + T * 7 + U * 4 - R * 3, body, 1600, (255, 226, 200), size=6)
    C.area(body + T * 6 - U * 5 + R * 2, body, 900, (255, 200, 170), size=6)  # bounce from the lit city below
    C.area(body + v * 6 + R * 4 + U * 3, body, 900, (150, 170, 255), size=6)  # a cool rim from the sky side
    C.outlines(["Heroes"], thickness=3.4)
    C.render("thumb_fly")


def json_boxes(area):
    import json
    return json.load(open(os.path.join(C.CITY, area + ".json")))["boxes"]


# the creator line-up (Store Page thumbnail 2): Bruiser (Titan) and Blaster (Volt) in Comic looks, Speedster
# (Pulse, with a Blade) and a Controller (Frost) in Anime looks, the Controller as a villain
BRUISER = dict(suit=((214, 96, 36), (214, 96, 36), (70, 52, 44)), gloves=(120, 116, 110), boots=(120, 116, 110),
               belt=((60, 50, 44), (230, 190, 90)), emblem=("star", (70, 52, 44), (255, 200, 80)), mask=(40, 30, 26),
               cape_rgb=(120, 60, 30), hair="swept", hair_rgb=(30, 26, 24), skin=(141, 95, 64), face="Stern")
SPEEDSTER = dict(shirt=("TrackTop", (40, 170, 160)), pants=("TrackPants", (34, 40, 52)), hair="spiky",
                 hair_rgb=(255, 120, 200), hair_glow=0.1, eyes=(120, 255, 240), face="Sharp", skin=(240, 190, 150))
VILLAIN = dict(shirt=("Blazer", (120, 60, 190)), pants=("Slacks", (44, 34, 60)), hair="spiky", hair_rgb=(24, 22, 30),
               mask="horns", face="Cold", skin=(224, 172, 130), cape_rgb=(110, 50, 170))


def build():
    C.settings(RES, samples=64, exposure=0.0, view="Standard")
    # a rooftop on Downtown's south edge at golden hour, the skyline behind
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
    z0 = base.z + 2.6  # the heroes' centres (feet on the deck)
    y0 = base.y
    cam_at = Vector((base.x, y0 - 17.0, z0 + 0.6))
    look = Vector((base.x, y0 + 10, z0 + 3.2))
    cam = C.camera(cam_at, look, lens=30)
    xs = [-6.9, -2.3, 2.3, 6.9]
    # 1 Bruiser (Titan): wide stance, fists down and out, rocks lifting off the roof
    br = {"LeftShoulder": (8, 26, 0), "RightShoulder": (8, -26, 0), "LeftElbow": (18, 0, 0),
          "RightElbow": (18, 0, 0), "LeftHip": (0, 12, 0), "RightHip": (0, -12, 0), "Neck": (6, 0, 0)}
    BM, bobs = C.hero(C.root_matrix((base.x + xs[0], y0, z0 + 0.15), (0, 0, 180 - 16), 1.12), br,
                      cape_kw=dict(length=3.6, flare=1.5, lift=0.5, wave=0.3, seed=2), **BRUISER)
    C.chunks(Vector((base.x + xs[0], y0 + 1.4, z0 - 1.2)), 3.0, 16, seed=12, size=(0.35, 1.0),
             mats=[C.flat("rock", (150, 120, 96), rough=0.9), C.flat("rock2", (120, 100, 84), rough=0.9)])
    C.glow(Vector((base.x + xs[0], y0 + 0.2, z0 - 2.2)), 7, cam, (255, 150, 60), strength=1.4)
    # 2 Blaster (Volt, the Comic mascot): one arm thrown out, lightning from the palm
    bl = {"RightShoulder": (168, -14, 0), "RightElbow": (4, 0, 0), "LeftShoulder": (-10, 12, 0),
          "LeftElbow": (-30, 0, 0), "LeftHip": (0, 6, 0), "RightHip": (10, -6, 0)}
    LM, lobs = C.hero(C.root_matrix((base.x + xs[1], y0, z0), (0, 0, 180 + 14)), bl,
                      cape_kw=dict(length=4.0, flare=1.6, lift=0.8, wave=0.4, flow=(0.6, -0.4, 0), seed=5), **COMIC)
    palm = LM["RightHand"] @ Vector((1.5, 0, 1.9))
    out = (LM["RightHand"].to_3x3() @ Vector((0, 0, -1))).normalized()
    for k in range(6):
        a = (k - 2.5) * 0.45
        d = Vector((math.sin(a), -0.3, math.cos(a))).normalized()
        C.lightning(palm, palm + d * (2.6 + (k % 3) * 0.9), seed=40 + k, jag=0.16, width=0.07, branches=1,
                    strength=12)
    C.glow(palm, 3.6, cam, (110, 190, 255), strength=2.4)
    # 3 Speedster (Pulse, with a Blade): low run-start lean, the blade up, pulse rings at the feet
    sp = {"RightShoulder": (130, 0, 10), "RightElbow": (30, 0, 0), "LeftShoulder": (-40, 0, -14),
          "LeftElbow": (-60, 0, 0), "LeftHip": (40, 0, 0), "LeftKnee": (-60, 0, 0), "RightHip": (-24, 0, 0),
          "RightKnee": (-20, 0, 0), "Waist": (16, 0, 0), "Neck": (-14, 0, 0)}
    SM, sobs = C.hero(C.root_matrix((base.x + xs[2], y0, z0 - 0.3), (0, 0, 180 - 18)), sp, **SPEEDSTER)
    C.blade(SM, "RightHand", (90, 230, 255), 4.0)
    C.aura(sobs, (120, 255, 240), grow=0.08, strength=2.2, power=6.0)
    for k, (r, h) in enumerate(((1.6, 0.15), (2.3, 0.5), (3.0, 0.9))):
        ring = C.kit.torus("pulse", r, 0.05, segs=48, csegs=6)
        ring.location = Vector((base.x + xs[2], y0, base.z + h))
        ring.data.materials.append(C.glow_mat("pulse", (190, 110, 255), 5.0 - k))
        C.put(ring, C.collection("Fx"))
    # 4 the villain Controller (Frost): one hand raised, ice shards swirling, a purple cape
    vl = {"LeftShoulder": (150, 10, 0), "LeftElbow": (20, 0, 0), "RightShoulder": (30, 0, 20),
          "RightElbow": (50, 0, 0), "LeftHip": (0, -8, 0), "RightHip": (0, 8, 0), "Neck": (-6, 0, 10)}
    VM, vobs = C.hero(C.root_matrix((base.x + xs[3], y0, z0), (0, 0, 180 + 22)), vl,
                      cape_kw=dict(length=4.6, flare=1.7, lift=0.9, wave=0.5, flow=(-0.6, -0.5, 0), seed=7),
                      **VILLAIN)
    hand = VM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    C.crystals(hand + Vector((0, 0, 0.6)), 2.2, 22, seed=3, size=(0.35, 1.2))
    C.crystals(Vector((base.x + xs[3], y0 - 0.6, base.z + 0.4)), 1.8, 10, seed=9, size=(0.6, 1.8))
    C.glow(hand, 4.2, cam, (150, 225, 255), strength=2.2)
    C.sparks(hand, 1.6, 16, cam, seed=2, rgb=(200, 240, 255), size=(0.3, 0.8), strength=6)
    C.fog("City", (250, 196, 160), start=200, half=1000)
    sunset_sky()
    C.sun((76, 0, -24), energy=4.4, rgb=(255, 186, 120), angle=2)
    centre = Vector((base.x, y0, z0 + 1.0))
    C.area(cam_at + Vector((-7, -2, 7)), centre, 5200, (255, 232, 210), size=14)
    C.area(centre + Vector((6, 9, 6)), centre, 2600, (150, 170, 255), size=10)  # a cool back rim
    C.outlines(["Heroes"], thickness=3.0)
    C.render("thumb_build")


SQUAD = [  # suit colours (torso and arms, legs), cape, trail: the squad flying the boss fight
    ((36, 92, 220), (28, 44, 110), (226, 28, 40), (90, 170, 255)),
    ((40, 170, 90), (30, 60, 40), (250, 210, 60), (120, 255, 150)),
    ((230, 200, 40), (60, 50, 40), (40, 40, 48), (255, 230, 90)),
    ((200, 40, 60), (40, 30, 40), (250, 250, 250), (255, 120, 120)),
    ((120, 70, 200), (40, 30, 60), (60, 200, 230), (200, 140, 255)),
    ((240, 120, 30), (60, 40, 30), (30, 90, 200), (255, 170, 80)),
    ((60, 200, 220), (30, 50, 80), (230, 60, 140), (120, 240, 255)),
    ((236, 236, 240), (60, 64, 80), (36, 92, 220), (220, 230, 255)),
    ((220, 60, 160), (50, 30, 60), (250, 200, 60), (255, 140, 220)),
    ((90, 90, 100), (30, 30, 36), (230, 40, 40), (255, 90, 70)),
    ((40, 120, 240), (240, 240, 240), (240, 200, 40), (140, 200, 255)),
]


def trail(points, rgb, width=0.5):
    """A flight trail (the creator's Flight trails): a soft emissive ribbon tube that thins to nothing."""
    pts = [Vector(p) for p in points]
    radii = [width * (1 - i / (len(pts) - 1)) ** 0.7 for i in range(len(pts))]
    ob = C.kit.tube_along("trail", pts, radii, segs=8)
    ob.data.materials.append(C.glow_mat("trail", rgb, 0.9, additive=True))
    ob.visible_shadow = False
    return C.put(ob, C.collection("Fx"))


def firework(centre, rgb, cam, seed=1, r=26, count=26):
    rng = random.Random(seed)
    c = Vector(centre)
    m = C.glow_mat("fw", rgb, 6.0, additive=True)
    for i in range(count):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        a, b = c + d * r * 0.35, c + d * r * (0.8 + rng.random() * 0.3)
        ob = C.kit.tube_along("fwl", [a, a.lerp(b, 0.5), b], [0.25, 0.4, 0.05], segs=5)
        ob.data.materials.append(m)
        C.put(ob, C.collection("Fx"))
    C.glow(c, r * 1.6, cam, rgb, strength=0.9)
    C.sparks(c, r * 0.7, 18, cam, seed=seed, rgb=rgb, size=(1.5, 3.5), strength=8)


def boss():
    C.settings(RES, samples=64, exposure=0.0, view="Standard")
    # the world boss lands in Downtown: a cleared block around it, the skyline behind, the squad all over it
    bx, bz = -470.0, 300.0  # Roblox x, z of its feet

    def keep(b):
        return math.hypot(b["cx"] - bx, b["cz"] - bz) > 95 or b["kind"] in ("road", "sidewalk")

    C.layout("DowntownWide", keep=keep)
    feet = C.rb(bx, 0, bz)
    C.boss("RustjawPrime", feet, yaw=180 + 18)
    cam_at = C.rb(bx + 30, 16, bz + 230)
    look = C.rb(bx + 4, 98, bz)
    cam = C.camera(cam_at, look, lens=26)
    v = (look - cam_at).normalized()
    R = v.cross(Vector((0, 0, 1))).normalized()
    U = R.cross(v).normalized()
    # rubble and dust where it landed
    C.chunks(feet + Vector((0, -30, 4)), 40, 60, seed=21, size=(2.0, 7.0),
             mats=[C.kit_mat("Office", (214, 232, 255)), C.flat("conc", (158, 156, 150), rough=0.85)])
    C.smoke(feet + Vector((0, -10, 4)), 34, 20, cam, seed=4, size=(34, 64), rgb=(220, 200, 190), alpha=0.55, up=0.1)
    # the squad: heroes flying around it, trails behind, bolts and beams on the weak points (gold)
    rng = random.Random(5)
    chest = feet + Vector((0, 0, 70))
    # where each hero sits on screen (x, y from -1 to 1) and how far from the camera, so all ten stay in frame
    # around the boss, clear of the boss bar (top) and the caption (bottom)
    spots = [(-0.74, 0.30, 120), (-0.52, -0.08, 92), (-0.80, -0.34, 72), (0.70, 0.36, 128), (0.52, 0.02, 96),
             (0.80, -0.28, 78), (-0.30, 0.50, 160), (0.30, 0.56, 170), (-0.40, -0.40, 64), (0.36, -0.44, 110)]
    for k, (sx, sy, depth) in enumerate(spots):
        suit, legs, capec, trc = SQUAD[k]
        p = cam_at + v * depth + R * (sx * 0.66 * depth) + U * (sy * 0.37 * depth)
        to_boss = (chest - p).normalized()
        upv = (to_boss + Vector((rng.uniform(-0.3, 0.3), 0, 0.3))).normalized()
        front = Vector((0, -1, -0.3)) if k % 2 else Vector((0.3, -1, 0.2))
        root = C.root_axes(p, upv, front, scale=2.2)  # a little big so each hero reads at this distance
        bends = {"RightShoulder": (170, -10, 0), "LeftShoulder": (10, 0, 8), "RightHip": (10, 0, 0),
                 "LeftHip": (24, 0, 0), "LeftKnee": (50, 0, 0)}
        M, obs = C.hero(root, bends, suit=(suit, suit, legs), gloves=capec, boots=capec, cape_rgb=capec,
                        cape_kw=dict(length=4.4, flare=1.7, lift=1.2, wave=0.5, seed=k), mask=(20, 20, 30),
                        hair="spiky" if k % 3 == 0 else "swept", hair_rgb=(250, 250, 250) if k % 3 == 0 else (40, 30, 24),
                        emblem=("star", capec, (255, 255, 255)), skin=[(240, 190, 150), (141, 95, 64), (224, 172, 130)][k % 3])
        tail = [p - to_boss * (3 + i * 5) + Vector((math.sin(i + k) * 2, 0, math.cos(i * 0.7 + k) * 2 - i * 1.5))
                for i in range(6)]
        trail(tail, trc, 0.9)
        if k in (0, 3, 6, 8):
            fist = M["RightHand"] @ Vector((1.5, 0, 2.0))
            target = chest + Vector((rng.uniform(-14, 14), rng.uniform(-14, -6), rng.uniform(-18, 26)))
            if k % 2:
                C.lightning(fist, target, rgb=trc, seed=k + 70, jag=0.06, width=0.8, branches=2, strength=10)
            else:
                beam = C.kit.tube_along("beam", [fist, fist.lerp(target, 0.5), target], [0.9, 1.4, 2.0], segs=10)
                beam.data.materials.append(C.glow_mat("beam", trc, 2.5, additive=True))
                C.put(beam, C.collection("Fx"))
                C.glow(target, 22, cam, trc, strength=1.4)
            C.sparks(target, 5, 10, cam, seed=k, rgb=(255, 220, 140), size=(1.4, 3.0), strength=10)
    # fireworks over the fight
    for k, (sx, sy, rgb) in enumerate(((-0.36, 0.62, (255, 90, 120)), (0.42, 0.7, (120, 220, 255)),
                                       (0.05, 0.86, (255, 220, 90)), (0.86, 0.66, (180, 120, 255)),
                                       (-0.86, 0.72, (120, 255, 160)))):
        depth = 330
        firework(cam_at + v * depth + R * (sx * 0.66 * depth) + U * (sy * 0.37 * depth), rgb, cam, seed=k + 1, r=30)
    C.fog("City", (120, 110, 160), start=200, half=900)
    C.sky(top=(16, 20, 60), horizon=(240, 120, 110), bottom=(250, 150, 130), mid=(90, 60, 130),
          ambient=(110, 110, 160), ambient_strength=0.7)
    C.sun((82, 0, 150), energy=2.6, rgb=(255, 150, 110), angle=3)
    C.area(cam_at + U * 40 - R * 20, chest, 900000, (255, 220, 200), size=60)  # key on the boss and squad
    C.lamp(chest + Vector((0, -30, 0)), 400000, (255, 150, 80), size=20)  # the fight's own glow
    C.outlines(["Heroes"], thickness=1.8)
    C.render("thumb_boss")


{"fly": fly, "build": build, "boss": boss}[WHICH]()
