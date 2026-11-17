# art/store/icons.py: the experience icons (notes/Store Page.md, "Icon (512 x 512), 3 variants to A/B test"; nate's
# picks 2026-11-17: clash and smash; the flying one was dropped), rendered at 1024 x 1024 into
# art/export/store/raw/; art/store/post.py grades them, adds the speed lines and saves the 512 x 512 PNGs nate
# uploads. thumbs.py imports COMIC and ANIME from here.
#   clash:  an Anime hero (white spiky hair, gold aura) and a turned Spark Trooper meeting fists in the centre,
#           a white shockwave ring between them, a cracked street and chunks. No text.
#   smash:  the city-destruction moment: a Comic hero punching a turned robot through a tower's corner, the
#           wall bursting into kit chunks and dust over Downtown. No text.
# Run: python art/store/icons.py <clash|smash> [--draft]   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
from mathutils import Vector  # noqa: E402

WHICH = [a for a in sys.argv[1:] if not a.startswith("-")]
WHICH = WHICH[0] if WHICH else "clash"

# the Comic hero (Store Page: bold outline, primary colours, a cape): Storm Front style suit colours on the
# blocky body, red cape, gloves and boots, a star emblem, the Domino Mask
COMIC = dict(suit=((36, 92, 220), (36, 92, 220), (28, 44, 110)), gloves=(230, 36, 44), boots=(230, 36, 44),
             belt=((250, 200, 40), (255, 236, 150)), emblem=("star", (232, 30, 40), (255, 214, 50)),
             mask=(18, 20, 34), cape_rgb=(226, 28, 40), hair="swept", hair_rgb=(60, 38, 24),
             skin=(240, 190, 150), face="Hero")


# the Anime hero (Store Page: white hair, gold aura, speed lines): our Leather Jacket and Joggers, Anime Spikes
ANIME = dict(shirt=("LeatherJacket", (196, 38, 48)), pants=("Joggers", (38, 38, 46)), hair="spiky",
             hair_rgb=(250, 250, 255), hair_glow=0.15, eyes=(255, 214, 90), face="Sharp", skin=(232, 180, 140))


def clash():
    C.settings((1024, 1024), samples=96, exposure=0.0, view="Standard")
    # profile fight at a Downtown crossing: the hero on the left facing +x, the robot on the right facing -x
    yaw = 124  # past profile, so both faces show a little
    hero_root = C.root_matrix((-3.2, 0, 2.5), (-12, 0, -yaw))
    # each punches with the arm on the opponent's side, so neither arm crosses its own body
    hb = {"LeftElbow": (4, 0, 0),
          "RightShoulder": (40, 0, 30), "RightElbow": (95, 0, 0),
          "RightHip": (34, 0, 0), "RightKnee": (-40, 0, 0), "LeftHip": (-30, 0, 0), "LeftKnee": (-10, 0, 0),
          "Neck": (4, 0, -14), "Waist": (0, 0, -10)}
    hb["LeftShoulder"] = C.aim(hero_root, hb, "LeftShoulder", (1, -0.05, -0.05))
    HM, hobs = C.hero(hero_root, hb, **ANIME)
    rb = {"RightElbow": (4, 0, 0),
          "LeftShoulder": (40, 0, -30), "LeftElbow": (95, 0, 0),
          "LeftHip": (34, 0, 0), "LeftKnee": (-40, 0, 0), "RightHip": (-30, 0, 0), "RightKnee": (-10, 0, 0),
          "Neck": (4, 0, 14), "Waist": (0, 0, 10)}
    probe = C.root_matrix((0, 0, 2.5), (-12, 0, yaw))
    rb["RightShoulder"] = C.aim(probe, rb, "RightShoulder", (-1, -0.05, -0.05))
    # place the robot so the two fists meet with a small gap
    hfist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    rfist = C.rig(probe, rb)["RightHand"] @ Vector((1.5, 0, 2.0))
    off = hfist - rfist + Vector((0.3, 0, 0))
    robot_root = C.root_matrix(Vector((0, 0, 2.5)) + off, (-12, 0, yaw))
    RM, robs = C.trooper(robot_root, rb, broken=("LeftUpperArm", "LeftLowerArm", "LeftHand"))
    hit = (hfist + RM["RightHand"] @ Vector((1.5, 0, 2.0))) / 2
    cam = C.camera(hit + Vector((0.0, -13.0, 1.6)), hit + Vector((0, 0, 0.2)), lens=36)
    # the shockwave: a white ring between the fists, a glow and sparks
    ring = C.kit.torus("ring", 1.0, 0.07, at=(0, 0, 0), segs=48, csegs=8, axis="Y")
    ring.data.materials.append(C.glow_mat("ring", (255, 255, 255), 8.0))
    ring.rotation_euler = (math.radians(10), 0, 0)
    ring.location = hit
    C.put(ring, C.collection("Fx"))
    ring2 = C.kit.torus("ring2", 1.8, 0.04, at=(0, 0, 0), segs=48, csegs=6, axis="Y")
    ring2.data.materials.append(C.glow_mat("ring2", (255, 236, 170), 5.0))
    ring2.rotation_euler = (math.radians(10), 0, 0)
    ring2.location = hit
    C.put(ring2, C.collection("Fx"))
    C.glow(hit, 6, cam, (255, 250, 230), strength=2.0)
    C.glow(hit, 3.2, cam, (255, 255, 255), strength=5.0, tex="core.png")
    C.glow(hit + Vector((0, 0.5, 0)), 4.5, cam, (255, 250, 235), strength=1.2, tex="shock.png")
    C.sparks(hit, 1.6, 26, cam, seed=4, rgb=(255, 220, 120), size=(0.5, 1.3), strength=10)
    # the gold aura (Awakening look) on the hero, a blue-red rim on the robot side
    C.aura(hobs, (255, 196, 50), grow=0.09, strength=3.0, power=6.0)
    C.glow(HM["UpperTorso"] @ Vector((0, 0, 3.2)) + Vector((0, 2.0, 0)), 11, cam, (255, 180, 40), strength=1.4)
    C.lamp(hit - Vector((0, 2.0, 0)), 260, (255, 240, 200), size=1.0)
    C.lamp(HM["UpperTorso"] @ Vector((0, 0, 3.2)) + Vector((-1.5, -2.5, 1)), 220, (255, 190, 70), size=1.0)
    # the street: asphalt chunks kicked up around the feet
    C.chunks(hit + Vector((0, 1.5, -3.4)), 2.6, 14, seed=7, size=(0.2, 0.6),
             mats=[C.kit_mat("Asphalt"), C.flat("conc", C.PALETTE["concrete"], rough=0.85)])
    # Downtown: a crossing with towers down both streets
    C.ground(0, 0, 3000)
    C.city(0, 0, blocks=6, block=96, street=28, seed=21, hmin=90, hmax=260, centre_boost=1.3)
    C.fog("City", (190, 220, 250), start=120, half=600)
    C.sky(top=(30, 96, 226), horizon=(176, 220, 255), ambient=(176, 200, 236), ambient_strength=1.0)
    C.sun((52, 0, 150), energy=4.2, rgb=(255, 244, 226))
    C.area(cam.location + Vector((-6, 0, 5)), hit, 700, (255, 245, 230), size=10)
    C.outlines(["Heroes", "Robots"], thickness=2.6)
    C.render("icon_clash")


def wall_with_hole(x0, y0, w, d, h, hole, front="Office", tint=None):
    """A tower (lower corner x0, y0; its -x face is the front toward the fight) with a hole punched through its
    front: (y, z, half width, half height). The front is built from four boxes around the hole, the inside dark."""
    hy, hz, hw, hh = hole
    coll = C.collection("City")
    m = C.kit_mat(front, tint)
    depth = 7.0  # how deep the hole goes before the dark office inside
    pieces = [
        (x0, y0, d, hy - hw - y0, 0, h),  # left of the hole
        (x0, hy + hw, d, y0 + w - hy - hw, 0, h),  # right of the hole
        (x0, hy - hw, d, 2 * hw, 0, hz - hh),  # below
        (x0, hy - hw, d, 2 * hw, hz + hh, h),  # above
        (x0 + depth, hy - hw, d - depth, 2 * hw, hz - hh, hz + hh),  # the back of the hole
    ]
    out = []
    dark = C.flat("room", (54, 48, 46), rough=0.9)
    for k, (bx, by, bd, bw, z0, z1) in enumerate(pieces):
        # every piece keeps its origin at the tower's corner so the storeys of the front line up
        ob = C.kit.box("wall", bd, bw, z1 - z0, at=(bx - x0 + bd / 2, by - y0 + bw / 2, z0 + (z1 - z0) / 2))
        ob.location = (x0, y0, 0)
        ob.data.materials.append(dark if k == 4 else m)
        out.append(C.put(ob, coll))
    roof = C.kit.box("roofrim", 1.2 + d, 1.2 + w, 1.6, at=(x0 + d / 2, y0 + w / 2, h + 0.4))
    roof.data.materials.append(C.flat("roofrim", (200, 198, 192), rough=0.8))
    out.append(C.put(roof, coll))
    return out


def cracks(x0, hole, seed=1, count=11):
    """Dark jagged cracks running out from the hole across the tower's front (BuildingFx's cracks)."""
    import random
    rng = random.Random(seed)
    hy, hz, hw, hh = hole
    mat = C.flat("crack", (34, 30, 30), rough=0.9)
    for k in range(count):
        a = k * 2 * math.pi / count + rng.random() * 0.4
        r0 = 1.0 / max(abs(math.cos(a)) / hw, abs(math.sin(a)) / hh)  # start on the hole's edge
        pts = [Vector((x0 - 0.06, hy + math.cos(a) * r0, hz + math.sin(a) * r0))]
        ln = 3 + rng.random() * 5
        for i in range(5):
            a2 = a + (rng.random() - 0.5) * 0.9
            step = ln / 5
            p = pts[-1] + Vector((0, math.cos(a2) * step, math.sin(a2) * step))
            pts.append(p)
        radii = [0.16 * (1 - i / 6) + 0.02 for i in range(len(pts))]
        ob = C.kit.tube_along("crack", pts, radii, segs=4)
        for v in ob.data.vertices:  # flatten onto the wall
            v.co.x = x0 - 0.06 + (v.co.x - (x0 - 0.06)) * 0.15
        ob.data.materials.append(mat)
        C.put(ob, C.collection("City"))


def smash():
    C.settings((1024, 1024), samples=96, exposure=0.0, view="Standard")
    # high on a Downtown tower: the Comic hero has just punched a turned Spark Trooper through its front wall
    X0 = 0.0  # the tower's front (it faces -x)
    Z = 62.0
    hole = (0.0, Z + 0.5, 4.2, 3.8)
    wall_with_hole(X0, -30, 60, 46, 156, hole, "Office", (214, 232, 255))
    # the robot, flung backwards into the hole: head back, arms thrown forward, legs trailing
    rroot = C.root_matrix((X0 - 2.3, -0.8, Z - 0.3), (12, 0, 150))
    rb = {"LeftShoulder": (70, 0, -30), "RightShoulder": (95, 0, 35), "LeftElbow": (30, 0, 0),
          "RightElbow": (10, 0, 0), "LeftHip": (40, 0, -10), "RightHip": (-20, 0, 12), "LeftKnee": (-60, 0, 0),
          "RightKnee": (-20, 0, 0), "Neck": (-8, 0, 0)}
    RM, robs = C.trooper(rroot, rb, broken=("RightUpperArm", "RightLowerArm", "RightHand"))
    # the hero, follow-through: flying in from the left, the punching arm out at the robot
    yaw = 118
    hroot = C.root_matrix((X0 - 9.2, -1.2, Z - 0.6), (-16, 0, -yaw))
    hb = {"RightShoulder": (-30, 0, 20), "RightElbow": (-60, 0, 0), "LeftElbow": (2, 0, 0),
          "LeftHip": (10, 0, 0), "LeftKnee": (25, 0, 0), "RightHip": (-25, 0, 0), "RightKnee": (50, 0, 0),
          "Neck": (16, 0, -12)}
    target = RM["UpperTorso"] @ Vector((0, 0, 3.2))
    probe = C.rig(hroot, hb)
    sh = probe["UpperTorso"] @ Vector((-1.0, 0, 3.76))
    hb["LeftShoulder"] = C.aim(hroot, hb, "LeftShoulder", (target - sh).normalized())
    cape_kw = dict(length=4.4, flare=1.7, lift=1.0, wave=0.5, flow=(0.8, -1.4, -0.6), seed=9)
    HM, hobs = C.hero(hroot, hb, cape_kw=cape_kw, **COMIC)
    fist = HM["LeftHand"] @ Vector((-1.5, 0, 2.0))
    cam = C.camera(Vector((X0 - 6.5, -16.0, Z + 0.6)), Vector((X0 - 4.8, 0.0, Z - 0.4)), lens=30)
    # the blast: chunks of the front (with its windows) and dust bursting out of the hole toward the camera
    hc = Vector((X0, hole[0], hole[1]))
    out = Vector((-1, -0.35, 0.15))
    C.chunks(hc + Vector((-2.0, -0.5, 0)), 6.0, 26, seed=5, size=(0.3, 1.1), direction=out, stretch=0.9,
             mats=[C.flat("conc", C.PALETTE["concrete"], rough=0.85), C.flat("conc2", (200, 196, 188), rough=0.85),
                   C.flat("glass", (90, 130, 170), rough=0.2, metal=0.3)])
    cracks(X0, hole, seed=2)
    C.chunks(hc + Vector((-3, -1, -10)), 7.0, 14, seed=8, size=(0.4, 1.6), direction=(0, 0, -1), stretch=1.2,
             mats=[C.kit_mat("Office", (214, 232, 255)), C.flat("conc", C.PALETTE["concrete"], rough=0.85)])
    C.smoke(hc + Vector((-0.5, 0, -1.0)), 3.0, 10, cam, seed=3, size=(4, 8), rgb=(236, 228, 214), alpha=0.6,
            up=0.2)
    C.smoke(hc + Vector((0.5, 0, 3.5)), 3.5, 6, cam, seed=4, size=(5, 9), rgb=(220, 214, 204), alpha=0.5, up=0.6)
    C.glow(hc + Vector((-1, -1, 0)), 9, cam, (255, 220, 150), strength=1.6)
    C.glow(fist + (target - fist) * 0.5, 4.5, cam, (255, 255, 240), strength=2.0, tex="core.png")
    C.glow(target + Vector((-1.2, -0.6, 0)), 5.0, cam, (255, 250, 230), strength=1.0, tex="shock.png")
    C.sparks(target, 2.0, 24, cam, seed=6, rgb=(255, 210, 110), size=(0.5, 1.4), strength=10)
    C.lamp(hc + Vector((2, 0, 0)), 900, (255, 190, 120), size=2)
    # Downtown around it and the street far below
    C.ground(0, 0, 3000)

    def skip(x, y):
        return abs(x - 23) < 90 and abs(y) < 90 or (x < -20 and y < 0 and x > -260 and y > -200)

    C.city(30, 0, blocks=7, block=96, street=30, seed=33, hmin=60, hmax=230, centre_boost=1.4, skip=skip)
    C.fog("City", (196, 224, 250), start=140, half=650)
    C.sky(top=(30, 96, 226), horizon=(176, 220, 255), ambient=(176, 200, 236), ambient_strength=1.0)
    C.sun((48, 0, 120), energy=4.4, rgb=(255, 244, 226))
    C.area(cam.location + Vector((-4, 2, 6)), (fist + target) / 2, 900, (255, 245, 230), size=10)
    C.outlines(["Heroes", "Robots"], thickness=2.6)
    C.render("icon_smash")


if __name__ == "__main__":
    {"clash": clash, "smash": smash}[WHICH]()
