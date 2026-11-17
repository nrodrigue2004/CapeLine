# art/store/thumbs.py: the store thumbnails (notes/Store Page.md, "Thumbnails (1920 x 1080)"; nate's picks
# 2026-11-17: build, boss and twist; the flying one was dropped), rendered into art/export/store/raw/;
# art/store/post.py grades them and adds the captions.
#   build: "Build your hero": four heroes side by side on a rooftop (Bruiser, Blaster, Speedster, Controller; two
#          Comic, two Anime, one in a villain look) with Titan, Volt, Pulse, Frost and Blade effects.
#          Caption HERO OR VILLAIN?
#   boss:  "World boss": a squad of heroes flying around the world boss (the remade RustjawPrime mesh) over
#          Downtown, beams and bolts on it, fireworks; post.py draws the boss bar. Caption GIANT WORLD BOSS.
#   twist: the lore's hook (lore step 4, the famous fakes): the Comic hero's punch landing on Radiant, the golden
#          flyer, its face cracked half open to the metal and a glowing red eye; a white flash and sparks; a
#          bright Downtown behind with a hint of the Crane Industries billboard. Caption TRUST NO HERO.
# The city is the game's own layout (art/export/city/DowntownWide.json) and the boss the game's own mesh
# (art/export/Bosses.fbx); STORE_ASSETS=<another checkout>/art reads them from a newer checkout.
# Run: python art/store/thumbs.py <build|boss|twist> [--draft]   (with the `bpy` module, Blender 5.0)
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
from icons import ANIME, COMIC  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

WHICH = [a for a in sys.argv[1:] if not a.startswith("-")]
WHICH = WHICH[0] if WHICH else "build"
RES = (1920, 1080)


def sunset_sky():
    C.sky(top=(38, 52, 130), horizon=(255, 170, 110), bottom=(255, 196, 150), mid=(150, 110, 170),
          ambient=(200, 170, 190), ambient_strength=0.75)


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


# Radiant, "The Golden Dawn" (Config.Enemies.Radiant.fake.look, lore step 4): the Chevron Suit in gold, white and
# electric yellow, a white Long Cape with gold trim, Long Cuffs, Winged Boots, the Burst emblem, a gold Hero
# Quiff, the Halo, metal Epaulettes and a white Sash; skin 2 and the Hero Face, here its cracked version
# (art/export/clothes/faces/Face_Hero_Cracked.png: half the face torn to a riveted plate with a red eye)
RADIANT_GOLD, RADIANT_WHITE, RADIANT_YELLOW = (255, 210, 60), (245, 245, 245), (255, 240, 80)
RADIANT = dict(suit=(RADIANT_GOLD, RADIANT_GOLD, (232, 176, 44)), gloves=RADIANT_WHITE, boots=RADIANT_WHITE,
               belt=(RADIANT_WHITE, RADIANT_YELLOW), cape_rgb=RADIANT_WHITE, hair="swept", hair_rgb=RADIANT_GOLD,
               skin=(241, 194, 160), face="Hero_Cracked")


def radiant_gear(M):
    """Radiant's Halo, metal Epaulettes, boot wings and the Burst emblem, placed on its parts."""
    gold = C.flat("rgold", RADIANT_GOLD, rough=0.25, metal=0.8, coat=0.4)
    out = []
    halo = C.kit.torus("halo", 0.66, 0.08, at=(0, 0, 0), segs=40, csegs=8)
    halo.matrix_world = Matrix.Translation((0, -0.15, 5.75)) @ Matrix.Rotation(math.radians(-30), 4, "X")
    halo.data.materials.append(C.glow_mat("halo", (255, 226, 110), 9.0))
    out.append(C._apply(halo, M["Head"]))
    for sx, side in ((-1, "Left"), (1, "Right")):
        ep = C.kit.box("epaulette", 1.2, 1.2, 0.3, at=(sx * 1.5, 0, 4.02))
        C.kit.bevel(ep, 0.1, 2)
        ep.data.materials.append(gold)
        out.append(C._apply(ep, M[side + "UpperArm"]))
        for k in range(3):  # the fringe
            f = C.kit.box("fringe", 0.14, 0.14, 0.36, at=(sx * 2.0, -0.36 + k * 0.36, 3.72))
            f.data.materials.append(gold)
            out.append(C._apply(f, M[side + "UpperArm"]))
        wing = C.kit.box("wing", 0.08, 0.8, 0.45, at=(sx * 1.05, -0.3, 0.9))
        wing.data.materials.append(gold)
        out.append(C._apply(wing, M[side + "LowerLeg"]))
    # the Burst emblem: a white disc with twelve gold rays and an electric-yellow core
    disc = C.kit.cyl("burstd", 0.56, 0.56, 0.05, at=(0, 0.53, 3.35), segs=32, axis="Y")
    disc.data.materials.append(C.flat("burstw", RADIANT_WHITE, rough=0.3, coat=0.5))
    out.append(C._apply(disc, M["UpperTorso"]))
    vs = []
    for i in range(12):
        a = i * math.pi / 6
        r0, r1, w = 0.17, (0.62 if i % 2 == 0 else 0.46), 0.055
        ux, uz = math.cos(a), math.sin(a)
        vs += [(ux * r0 - uz * w, 0.57, 3.35 + uz * r0 + ux * w), (ux * r1, 0.57, 3.35 + uz * r1),
               (ux * r0 + uz * w, 0.57, 3.35 + uz * r0 - ux * w)]
    me = C.bpy.data.meshes.new("burst")
    me.from_pydata(vs, [], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(12)])
    burst = C.bpy.data.objects.new("burst", me)
    C.bpy.context.scene.collection.objects.link(burst)
    burst.data.materials.append(C.flat("bursty", RADIANT_GOLD, rough=0.3, coat=0.5))
    out.append(C._apply(burst, M["UpperTorso"]))
    core = C.kit.cyl("burstc", 0.17, 0.17, 0.06, at=(0, 0.56, 3.35), segs=24, axis="Y")
    core.data.materials.append(C.glow_mat("burstcore", RADIANT_YELLOW, 3.0))
    out.append(C._apply(core, M["UpperTorso"]))
    return out


def crane_billboard(at, normal, size=(70, 40)):
    """A hint of the Crane Industries billboard from the Ceremony prologue (PrologueFx buildBoard: a navy board,
    Silas Crane's smiling face drawn with shapes, the brand in gold and the slogan in white, Config.Story's 70 x 40
    size), the words left as bars so the thumbnail carries no text but its caption; a frame on two rooftop legs."""
    w, h = size
    coll = C.collection("City")
    base = Matrix.Translation(Vector(at)) @ Vector(normal).normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()

    def piece(ob, mat):
        ob.data.materials.append(mat)
        ob.matrix_world = base @ ob.matrix_world
        C.put(ob, coll)

    def oval(name, cx, cz, rx, rz, mat, front=0.75):
        ob = C.kit.cyl(name, 1, 1, 0.3, segs=40, axis="Y")
        ob.matrix_world = Matrix.Translation((cx, front, cz)) @ Matrix.Diagonal((rx, 1, rz, 1))
        piece(ob, mat)

    steel = C.flat("bbsteel", (70, 74, 86), rough=0.5, metal=0.6)
    piece(C.kit.box("bbframe", w + 3, 1.4, h + 3, at=(0, -0.4, 0)), steel)
    piece(C.kit.box("bbface", w, 0.4, h, at=(0, 0.4, 0)), C.flat("bbnavy", (26, 30, 56), rough=0.6, emit=0.2))
    for sx in (-0.3, 0.3):
        piece(C.kit.box("bbleg", 1.6, 1.6, 40, at=(sx * w, -1.2, -h / 2 - 20)), steel)
    fx = w * 0.25  # the face fills the board's left quarter (local +x is the viewer's left)
    oval("bbhair", fx, h * 0.3, w * 0.17, h * 0.1, C.flat("bbhair", (190, 195, 205), rough=0.5, emit=0.4), 0.7)
    oval("bbskin", fx, -h * 0.05, w * 0.16, h * 0.4, C.flat("bbskin", (241, 194, 160), rough=0.6, emit=0.5))
    for ex in (-1, 1):
        oval("bbeye", fx + ex * w * 0.055, h * 0.06, w * 0.02, h * 0.035, C.flat("bbeye", (30, 30, 40)), 0.95)
    oval("bbsmile", fx, -h * 0.17, w * 0.085, h * 0.05, C.flat("bbsmile", (250, 250, 250), rough=0.4, emit=0.5), 0.95)
    piece(C.kit.box("bbtie", w * 0.05, 0.3, h * 0.12, at=(fx, 0.95, -h * 0.44)),
          C.flat("bbtie", (200, 30, 40), rough=0.5, emit=0.4))
    # the brand (gold) and the slogan (white) as bars, no words
    piece(C.kit.box("bbbrand", w * 0.46, 0.3, h * 0.17, at=(-w * 0.2, 0.95, h * 0.24)),
          C.glow_mat("bbbrand", (255, 210, 60), 1.4))
    for k, ln in enumerate((0.44, 0.34)):
        piece(C.kit.box("bbslogan", w * ln, 0.3, h * 0.07, at=(-w * (0.2 + (0.44 - ln) / 2), 0.95, -h * (0.06 + k * 0.16))),
              C.glow_mat("bbslogan", (245, 245, 245), 1.0))


def twist():
    C.settings(RES, samples=64, exposure=0.0, view="Standard")
    # mid-air over Downtown's south edge on a bright day, looking north into the skyline: the player's Comic hero
    # lands a punch on Radiant, the famous golden flyer, whose face has cracked open to the robot beneath
    C.layout("DowntownWide")
    X, Y, Z = -470.0, -520.0, 150.0
    cam_at = Vector((X + 0.3, Y - 10.0, Z + 1.6))
    look = Vector((X + 0.2, Y, Z + 1.45))
    cam = C.camera(cam_at, look, lens=32)
    # Radiant: knocked back to the right, head snapped by the hit, arms flung, its chest still to the camera
    rroot = C.root_axes((X + 2.3, Y + 0.6, Z + 0.4), (0.32, 0.12, 0.94), (-0.5, -0.9, 0), scale=1.08)
    rb = {"Neck": (-14, 10, 24), "LeftShoulder": (40, 0, 70), "LeftElbow": (40, 0, 0), "RightElbow": (30, 0, 0), "LeftHip": (20, 0, 12), "LeftKnee": (-40, 0, 0), "RightHip": (-24, 0, -8),
          "RightKnee": (-30, 0, 0), "Waist": (-10, 0, 0)}
    rb["RightShoulder"] = C.aim(rroot, rb, "RightShoulder", (-0.35, 0.9, 0.25))  # flung back, clear of its face
    RM, robs = C.hero(rroot, rb, cape_kw=dict(inner=RADIANT_GOLD, length=5.0, flare=1.8, lift=1.0, wave=0.6,
                                               flow=(1.6, -1.2, -0.4), seed=11), extra=radiant_gear, **RADIANT)
    jaw = RM["Head"] @ Vector((0.66, 0.2, 4.3))  # the cheek on its cracked side, toward the hero
    eye = RM["Head"] @ Vector((0.22, 0.66, 4.65))
    # the hero: flying in from the left, the lead (left) fist on Radiant's jaw, the other arm pulled back
    hroot = C.root_axes((X - 1.3, Y - 0.1, Z + 0.3), (0.5, 0.1, 0.86), (0.6, -0.8, 0))
    hb = {"RightElbow": (70, 0, 0), "LeftElbow": (4, 0, 0), "LeftHip": (14, 0, 0), "LeftKnee": (30, 0, 0),
          "RightHip": (-30, 0, 0), "RightKnee": (60, 0, 0), "Neck": (6, 0, -14)}
    hb["RightShoulder"] = C.aim(hroot, hb, "RightShoulder", (-1, 0.35, -0.55))  # cocked back for the next one
    sh = C.rig(hroot, hb)["UpperTorso"] @ Vector((-1.0, 0, 3.76))
    hb["LeftShoulder"] = C.aim(hroot, hb, "LeftShoulder", (jaw - sh).normalized())
    HM, hobs = C.hero(hroot, hb, cape_kw=dict(length=4.6, flare=1.8, lift=1.2, wave=0.5, flow=(-1.2, -1.0, -0.6),
                                                seed=9), **COMIC)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    hit = fist.lerp(jaw, 0.5) + (cam_at - jaw).normalized() * 0.5  # where they meet, in front of the face
    # the weighty hit (Config.Combat.weight): a white flash, a shock ring, sparks and shell chips off the jaw
    C.glow(hit, 2.2, cam, (255, 255, 255), strength=3.2, tex="core.png")
    C.glow(hit, 4.4, cam, (255, 250, 230), strength=1.4, tex="shock.png")
    C.sparks(hit, 0.9, 26, cam, seed=6, rgb=(255, 214, 120), size=(0.25, 0.7), strength=12)
    C.chunks(jaw + Vector((0.6, -0.2, 0.2)), 0.8, 9, seed=4, size=(0.08, 0.22), direction=(1, -0.2, 0.3),
             mats=[C.flat("shell", (241, 194, 160), rough=0.5), C.flat("plate", (150, 156, 170), rough=0.3, metal=0.9)])
    # the glowing red eye in the torn half of its face
    C.glow(eye, 1.6, cam, (255, 60, 40), strength=7.0)
    C.glow(eye, 0.5, cam, (255, 220, 200), strength=6.0, tex="core.png")
    C.sparks(eye + Vector((0.2, 0, 0.1)), 0.3, 6, cam, seed=8, rgb=(255, 120, 80), size=(0.15, 0.35), strength=10)
    # a hint of Crane: its billboard on a roof in the skyline behind Radiant
    crane_billboard(cam_at + Vector((94, 200, 44)), (-0.4, -1, 0))
    C.fog("City", (196, 224, 250), start=140, half=700)
    C.sky(top=(30, 96, 226), horizon=(176, 220, 255), ambient=(176, 200, 236), ambient_strength=1.0)
    C.sun((48, 0, 140), energy=4.4, rgb=(255, 244, 226))
    centre = (fist + jaw) / 2
    C.area(cam_at + Vector((-5, 2, 6)), centre, 1400, (255, 245, 230), size=10)
    C.area(centre + Vector((3, 8, 5)), centre, 900, (150, 170, 255), size=8)  # a cool back rim
    C.lamp(hit, 120, (255, 240, 220), size=0.6)
    C.outlines(["Heroes"], thickness=3.0)
    C.render("thumb_twist")


{"build": build, "boss": boss, "twist": twist}[WHICH]()
