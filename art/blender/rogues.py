# rogues.py: the Rogues File's portraits, step 1 (WP3 art pass, 2026-11-18): every page's figure rendered from the
# game's own look on a clear background, for art/rogues/portraits.py to draw as the case-file portraits.
# * the 20 robot kinds: the blocky R15 body in their Grunt uniform (art/clothes/uniforms.py, the look most robots
#   wear: Config.NpcLooks.versionOdds), a shared face turned (the glowing robot eyes) and their hair, with the
#   gear EnemyRenderer adds for their Config.Enemies body flags (jets, mask and loot bag, the planted arm
#   cannon, the Warden's guard and cape, the glass diving helmet and tanks, the riot shield, the officer's cap,
#   the rifle and visor, the bandolier, the medpack, the wings, the hook arm, the wind-up key, the hook and
#   bandana), in the same places and colours;
# * the famous fakes and the finale villains: their own outfit and face (art/clothes/people.py), with the
#   creator pieces that show from the chest up (hats, masks, visors, capes and collars, pads, beards, chains,
#   the chest emblem from art/clothes/emblems.py) as simple shapes in the look's colours; the evil twin is a
#   hero in a hero suit whose face has cracked to the metal;
# * the finales that have their own model (the Bramblebeast, the Voidhound and the Toymaker's Wind-Up Giant):
#   art/export/finales/<Name>.fbx with its baked colour map, assembled by Config.FinaleArt;
# * the world bosses: art/export/Bosses.fbx assembled by Config.BossArt (hull, plates, the phase 1 glow and the
#   weak points' gold).
# Pages come from art/export/rogues/pages.json (lune run art/rogues/pages.luau), the people's skins, hair and faces
# from art/export/clothes/people/preview.json. Output: build/rogues/raw/<page id>.png (RGBA, 720 px, Freestyle
# ink lines; build/ is not in git), then python3 art/rogues/portraits.py draws art/export/rogues/*.png.
# Run: $HOME/tools/bpyenv/bin/python art/blender/rogues.py [--only Id,Id] [--samples N]   (under nice -n 15)
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import clothed  # noqa: E402  (imported: its figure() and helpers, no preview)
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

REPO = os.path.dirname(kit.ROOT)
PAGES = os.path.join(kit.ROOT, "export", "rogues", "pages.json")
PEOPLE = os.path.join(kit.ROOT, "export", "clothes", "people", "preview.json")
EMBLEMS = os.path.join(kit.ROOT, "export", "clothes", "emblems")
RAW = os.path.join(REPO, "build", "rogues", "raw")
RES = 720
ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
SAMPLES = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 32

DARK = (40, 40, 48)
METAL = (150, 155, 168)
GOLD = (255, 200, 60)
srgb = clothed.srgb

# the robots' faces and hair in the portraits (each kind its own, so the page row never looks like one person)
FACES = clothed_faces = ["Hero", "Stern", "Sharp", "Scarred", "Rookie", "Cold"]
SKINS = [(240, 190, 150), (141, 95, 64), (224, 172, 130), (198, 140, 96), (92, 62, 44), (250, 210, 180),
         (170, 120, 84), (120, 80, 56), (232, 180, 140)]
HAIRS = [(70, 46, 30), (30, 26, 24), (160, 120, 60), (20, 20, 22), (120, 50, 30), (200, 170, 110),
         (60, 40, 28), (40, 34, 30), (150, 140, 170)]


def rgb(t, fallback):
    return tuple(t) if t else fallback


def mat(name, c, metal=0.0, rough=0.55, emit=0.0):
    return kit.material("%s%d" % (name, len(bpy.data.materials)), srgb(c), metal=metal, rough=rough, emit=emit)


def put(ob, c, **kw):
    ob.data.materials.append(mat(ob.name, c, **kw))
    kit.shade_auto(ob, 35)
    return ob


def bx(name, size, at, c, bev=0.04, **kw):
    ob = kit.box(name, size[0], size[1], size[2], at=at)
    if bev:
        kit.bevel(ob, bev, 2)
    return put(ob, c, **kw)


def rot(ob, deg, axis, pivot):
    p = Vector(pivot)
    ob.data.transform(Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-p))
    return ob


# ------------------------------------------------------------------ robot gear (EnemyRenderer's parts)
# The blocky body: UpperTorso 2 x 1 x 1.6 (z 2.4-4), Head 1.2 (z 4-5.2, its front at y 0.62), arms x 1-2.
UT = Vector((2.0, 1.6, 1.0))
YAW = -22  # the camera's yaw round a figure: to its left of front, so a held shield or guard faces out
FACE_CAM = -YAW  # turns a front-facing plate (normal +y) to face the camera  # x, up, depth as EnemyRenderer's UT (X, Y, Z)
HD = 1.2


def robot_gear(body, suit, trim, eye):
    metal = rgb(body.get("metal"), METAL)
    dark = DARK
    if body.get("mask"):
        # the burglar's black eye mask round the head and the loot bag on the back (over the shoulder)
        bx("Mask", (HD * 1.06, HD * 1.06, HD * 0.3), (0, 0, 4.66), (25, 25, 30), bev=0.03)
        bag = put(kit.sphere("Bag", 0.75, at=(0.75, -0.95, 3.5), scale=(1, 0.8, 1.15), segs=18, rings=12),
                  (120, 90, 50), rough=0.9)
        knot = put(kit.sphere("BagKnot", 0.22, at=(0.6, -0.8, 4.35), segs=10, rings=8), (100, 72, 40), rough=0.9)
        del bag, knot
    if body.get("planted"):
        # the arm cannon on the right forearm, pointed forward, its muzzle glowing
        c = kit.cyl("Cannon", 0.62, 0.55, 1.6, at=(1.5, 0.75, 3.05), segs=20, axis="Y")
        put(c, dark, metal=0.6, rough=0.35)
        m = kit.cyl("Muzzle", 0.36, 0.36, 0.1, at=(1.5, 1.57, 3.05), segs=18, axis="Y")
        put(m, eye, emit=4.0)
    if body.get("shield"):
        # the Warden's energy guard held up on the left forearm, facing out (see-through, lit)
        g = kit.box("Guard", 1.45, 0.1, 2.0, at=(-1.75, 0.95, 3.05))
        kit.bevel(g, 0.06, 2)
        gm = bpy.data.materials.new("GuardGlow%d" % len(bpy.data.materials))
        gm.use_nodes = True
        p = gm.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (*(clothed.lin(c) for c in (170, 215, 255)), 1)
        p.inputs["Emission Color"].default_value = (*(clothed.lin(c) for c in (150, 205, 255)), 1)
        p.inputs["Emission Strength"].default_value = 1.2
        p.inputs["Alpha"].default_value = 0.4
        g.data.materials.append(gm)
        rot(g, FACE_CAM, "Z", (-1.75, 0.95, 3.05))
        rim = kit.box("GuardRim", 1.55, 0.06, 0.12, at=(-1.75, 0.95, 4.07))
        rot(put(rim, (230, 240, 255), emit=2.5), FACE_CAM, "Z", (-1.75, 0.95, 3.05))
    if body.get("cape"):
        cape(rgb(body["cape"], (90, 40, 140)))
    if body.get("helmet"):
        # the glass diving helmet and its collar
        h = kit.sphere("Helmet", HD * 0.74, at=(0, 0, 4.6), segs=32, rings=20)
        gm = bpy.data.materials.new("Glass%d" % len(bpy.data.materials))
        gm.use_nodes = True
        p = gm.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (*(clothed.lin(c) for c in (190, 230, 255)), 1)
        p.inputs["Transmission Weight"].default_value = 1.0
        p.inputs["Roughness"].default_value = 0.05
        p.inputs["IOR"].default_value = 1.05
        p.inputs["Alpha"].default_value = 0.45
        h.data.materials.append(gm)
        kit.shade_auto(h, 80)
        put(kit.cyl("Collar", 0.78, 0.8, 0.22, at=(0, 0, 4.02), segs=28), trim, metal=0.6, rough=0.35)
    if body.get("tank"):
        for s in (-1, 1):
            put(kit.cyl("Tank", 0.24, 0.24, 1.35, at=(s * 0.45, -0.75, 3.25), segs=16), tuple(
                int(a * 0.7 + b * 0.3) for a, b in zip(trim, dark)), metal=0.5, rough=0.35)
    if body.get("riot"):
        # the riot shield on the left forearm, held up in front of that arm and facing out, so its window and
        # stripe show
        at = (-1.75, 1.0, 3.2)
        s = bx("Riot", (1.9, 0.22, 2.7), at, tuple(int(a * 0.6 + b * 0.4) for a, b in zip(suit, dark)),
               bev=0.06, metal=0.3)
        w = bx("RiotWin", (1.45, 0.06, 0.42), (at[0], at[1] + 0.13, at[2] + 0.8), (170, 210, 235), bev=0.02,
               emit=0.5)
        b = bx("RiotBar", (1.7, 0.06, 0.22), (at[0], at[1] + 0.13, at[2] - 0.3), trim, bev=0.02, emit=0.4)
        for ob in (s, w, b):
            rot(ob, FACE_CAM, "Z", at)
    if body.get("cap"):
        put(kit.cyl("Cap", 0.68, 0.7, 0.38, at=(0, 0, 5.28), segs=32),
            tuple(int(a * 0.7 + b * 0.3) for a, b in zip(suit, dark)), rough=0.8)
        peak = bx("CapPeak", (1.0, 0.55, 0.08), (0, 0.72, 5.12), (25, 25, 30), bev=0.03)
        rot(peak, -12, "X", (0, 0.5, 5.12))
        bx("CapBadge", (0.28, 0.06, 0.2), (0, 0.71, 5.3), trim, bev=0.01, metal=0.8, rough=0.3)
    if body.get("rifle"):
        # the long rifle held across the body, its tip glowing (the aim laser starts there)
        parts = [bx("Rifle", (0.2, 3.4, 0.26), (0.6, 0.85, 3.15), dark, metal=0.4),
                 bx("Scope", (0.16, 0.95, 0.16), (0.6, 0.95, 3.38), METAL, metal=0.7, rough=0.3),
                 bx("RifleTip", (0.16, 0.1, 0.16), (0.6, 2.58, 3.15), eye, bev=0.01, emit=4.0)]
        for ob in parts:
            rot(ob, 50, "Z", (0.6, 0.85, 3.15))
            rot(ob, 22, "Y", (0.6, 0.85, 3.15))
    if body.get("visor"):
        bx("Visor", (HD * 0.94, 0.08, HD * 0.17), (0, 0.65, 4.67), eye, bev=0.01, emit=3.0)
    if body.get("bandolier"):
        L = math.hypot(2.0, 1.6)
        strap = bx("Strap", (0.4, 0.1, L), (0, 0.55, 3.2), (70, 55, 35), bev=0.02, rough=0.9)
        rot(strap, 40, "Y", (0, 0.55, 3.2))
        for k in (-1, 0, 1):
            d = k * L * 0.28
            g = put(kit.sphere("Grenade", 0.2, at=(-d * math.sin(math.radians(40)), 0.68,
                                                  3.2 + d * math.cos(math.radians(40))), segs=14, rings=10),
                    (70, 85, 45), metal=0.3, rough=0.5)
            del g
    if body.get("medpack"):
        bx("Medpack", (1.5, 0.55, 1.36), (0, -0.78, 3.2), suit, bev=0.06)
        bx("MedLight", (0.3, 0.3, 0.22), (0, -0.78, 4.0), (70, 230, 120), bev=0.02, emit=4.0)
        for sz in ((0.8, 0.05, 0.24), (0.24, 0.05, 0.8)):
            bx("Plus", sz, (0, -1.07, 3.2), (70, 230, 120), bev=0.0, emit=2.0)
    if body.get("wings"):
        tip = rgb(body.get("jetColor"), eye)
        # swept jet wings on the back, raised in a V so they show past the shoulders
        for s in (-1, 1):
            w = bx("Wing", (2.4, 0.12, 0.8), (s * 2.0, -0.75, 4.0), metal, bev=0.03, metal=0.6, rough=0.3)
            t = bx("WingTip", (0.16, 0.16, 0.7), (s * 3.2, -0.75, 4.0), tip, bev=0.02, emit=3.0)
            for ob in (w, t):
                rot(ob, -s * 28, "Y", (s * 0.8, -0.75, 4.0))
    if body.get("hookArm"):
        put(kit.cyl("Launcher", 0.95, 0.85, 1.4, at=(1.5, 0.55, 3.0), segs=20, axis="Y"), dark, metal=0.5,
            rough=0.35)
        bx("Claw", (1.1, 0.5, 0.6), (1.5, 1.42, 3.0), trim, bev=0.05, metal=0.6)
        for s in (-1, 1):
            c = bx("ClawTine", (0.24, 0.8, 0.3), (1.5 + s * 0.42, 1.85, 3.0), metal, bev=0.04, metal=0.7)
            rot(c, -s * 20, "Z", (1.5 + s * 0.42, 1.5, 3.0))
    if body.get("windKey"):
        brass = (215, 170, 70)
        put(kit.cyl("KeyShaft", 0.13, 0.13, 0.75, at=(0, -0.85, 3.55), segs=12, axis="Y"), brass, metal=0.8,
            rough=0.3)
        for s in (-1, 1):
            put(kit.cyl("KeyBow", 0.42, 0.42, 0.12, at=(s * 0.45, -1.25, 3.55), segs=24, axis="Y"), brass,
                metal=0.8, rough=0.3)
    if body.get("hook"):
        steel = (190, 195, 205)
        bx("HookShaft", (0.22, 0.22, 0.4), (-1.5, 0.0, 1.7), steel, bev=0.02, metal=0.8)
        red = (210, 45, 45)
        put(kit.cyl("Bandana", 0.66, 0.66, 0.3, at=(0, 0, 5.0), segs=32), red, rough=0.8)
        put(kit.sphere("BandanaTop", 0.66, at=(0, 0, 5.12), scale=(1, 1, 0.42), segs=24, rings=12), red, rough=0.8)
        bx("BandanaKnot", (0.26, 0.2, 0.3), (0, -0.7, 4.95), red, bev=0.05, rough=0.8)


def cape(c, inner=None, collar=False):
    # a cape hanging from the shoulders behind the body (its edges show past the arms in the three-quarter view)
    ob = kit.box("Cape", 2.3, 0.1, 3.2, at=(0, -0.62, 2.55))
    kit.deform(ob, lambda v: Vector((v.x * (1.0 + (4.15 - v.z) * 0.12), v.y - (4.15 - v.z) * 0.08, v.z)))
    kit.bevel(ob, 0.04, 2)
    put(ob, c, rough=0.85)
    if collar:
        # a high collar standing up behind the head
        col = kit.cyl("Collar", 0.95, 0.75, 1.05, at=(0, -0.15, 4.45), segs=28)
        kit.cut(col, Vector((0, 1, 0)), keep_positive=False)
        put(col, inner or c, rough=0.85)


# ------------------------------------------------------------------ creator pieces (from the chest up)
def emblem_spec():
    """{ piece name: (shape, backing) } from Config.Creator's emblem rows ({ "Burst", "burst:none", ... })."""
    import re
    src = open(os.path.join(REPO, "src", "config", "Creator.luau"), encoding="utf-8").read()
    return {n: (s, b) for n, s, b in re.findall(r'\{ "([^"]+)", "([a-z]+):([a-z]+)"', src)}


EMBLEM = None


def tinted_plane(name, path, tint, at, size, emit=0.0):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=at, rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size, size, 1)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(path, check_existing=True)
    t.image.alpha_mode = "STRAIGHT"
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(t.outputs["Color"], mul.inputs["A"])
    mul.inputs["B"].default_value = (*(clothed.lin(c) for c in tint), 1)
    nt.links.new(mul.outputs["Result"], p.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], p.inputs["Alpha"])
    if emit:
        nt.links.new(mul.outputs["Result"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = emit
    ob.data.materials.append(m)
    return ob


def pieces(page, skin, hair_rgb):
    """The creator look's pieces that show in a bust portrait, as simple shapes in the look's colours."""
    global EMBLEM
    look = page.get("look") or {}
    pc = look.get("pieces") or {}
    prim, sec, acc = [tuple(c) if c else (128, 128, 128) for c in (page.get("rgb") or [None, None, None])]
    tints = page.get("tints") or {}

    def tint(slot, i, fallback):
        t = tints.get(slot)
        return tuple(t[i]) if t and len(t) > i and t[i] else fallback

    hat = pc.get("hat")
    if hat == "Halo":
        put(kit.torus("Halo", 0.48, 0.07, at=(0, 0, 5.75), segs=32, csegs=10), GOLD, metal=0.6, rough=0.3, emit=1.5)
    elif hat == "Top Hat":
        # Shared.PieceKits tophat: a dark crown and brim, the band in the slot's main colour
        c, band = (30, 30, 34), tint("hat", 1, tint("hat", 0, prim))
        put(kit.cyl("HatBrim", 0.85, 0.85, 0.07, at=(0, 0, 5.28), segs=32), c, rough=0.7)
        put(kit.cyl("HatCrown", 0.55, 0.58, 0.95, at=(0, 0, 5.78), segs=32), c, rough=0.7)
        put(kit.cyl("HatBand", 0.585, 0.585, 0.2, at=(0, 0, 5.42), segs=32), band, rough=0.7)
    elif hat == "Iron Crown":
        c = tint("hat", 0, (180, 150, 70))
        put(kit.cyl("Crown", 0.66, 0.68, 0.28, at=(0, 0, 5.28), segs=32), c, metal=0.8, rough=0.3)
        for k in range(7):
            a = 2 * math.pi * k / 7 + math.pi / 2
            sp = kit.cyl("Spike", 0.13, 0.0, 0.4, at=(0.64 * math.cos(a), 0.64 * math.sin(a), 5.6), segs=8)
            put(sp, c, metal=0.8, rough=0.3)
    elif hat == "Wide Brim":
        c = (45, 34, 30)
        put(kit.cyl("Brim", 1.05, 1.05, 0.08, at=(0, 0, 5.22), segs=36), c, rough=0.8)
        put(kit.sphere("BrimCrown", 0.62, at=(0, 0, 5.28), scale=(1, 1, 0.75), segs=28, rings=14), c, rough=0.8)
        put(kit.cyl("BrimBand", 0.64, 0.64, 0.14, at=(0, 0, 5.32), segs=28), sec, rough=0.6, metal=0.4)
    elif hat == "Ball Cap":
        put(kit.sphere("CapDome", 0.65, at=(0, 0, 5.02), scale=(1, 1, 0.6), segs=28, rings=14), prim, rough=0.8)
        peak = bx("CapPeak", (1.0, 0.6, 0.07), (0, 0.78, 5.0), sec, bev=0.03, rough=0.8)
        rot(peak, -8, "X", (0, 0.5, 5.0))
    elif hat == "Hachimaki":
        # a white headband with a red glow at the front and its two tails at the back (PieceKits hachimaki)
        white = (245, 245, 245)
        put(kit.cyl("Band", 0.71, 0.71, 0.2, at=(0, 0, 4.94), segs=28), white, rough=0.8)
        bx("BandMark", (0.26, 0.06, 0.14), (0, 0.73, 4.94), (255, 60, 50), bev=0.01, emit=3.0)
        for s in (-1, 1):
            t = bx("BandTail", (0.12, 0.08, 0.7), (s * 0.12, -0.76, 4.66), white, bev=0.02)
            rot(t, s * 18, "Y", (s * 0.12, -0.72, 4.94))
    elif hat == "Flight Goggles":
        put(kit.cyl("Strap", 0.63, 0.63, 0.14, at=(0, 0, 5.02), segs=28), DARK, rough=0.8)
        for s in (-1, 1):
            put(kit.cyl("Lens", 0.2, 0.2, 0.14, at=(s * 0.25, 0.64, 5.04), segs=18, axis="Y"), (255, 170, 60),
                metal=0.5, rough=0.2, emit=0.8)
    elif hat == "Tracker Lens":
        put(kit.cyl("TrackStrap", 0.63, 0.63, 0.1, at=(0, 0, 4.8), segs=28), DARK, rough=0.8)
        put(kit.cyl("Tracker", 0.2, 0.2, 0.24, at=(-0.24, 0.7, 4.72), segs=18, axis="Y"), acc, emit=3.0)
    head = pc.get("head")
    if head == "Masquerade":
        # PieceKits masquerade: the mask in the main colour, its swept wings in the accent
        c, wing = tint("head", 0, prim), tint("head", 2, acc)
        m = bx("Masq", (1.24, 0.08, 0.3), (0, 0.64, 4.72), c, bev=0.03, metal=0.5, rough=0.3)
        for s in (-1, 1):
            w = bx("MasqWing", (0.36, 0.07, 0.2), (s * 0.66, 0.6, 4.86), wing, bev=0.03, emit=0.8)
            rot(w, s * 30, "Y", (s * 0.6, 0.6, 4.8))
        del m
    elif head == "Mono Visor":
        # PieceKits monovisor: a metal band round the eyes in the main colour, a glowing slit in the accent
        put(kit.cyl("VisorBand", 0.66, 0.66, 0.42, at=(0, 0, 4.72), segs=32), tint("head", 0, prim), metal=0.6,
            rough=0.3)
        slit = tint("head", 2, acc)
        bx("VisorSlit", (0.9, 0.06, 0.08), (0, 0.67, 4.72), slit, bev=0.0, emit=0.0 if slit == (24, 24, 28) else 3.0)
    elif head == "Visor Band":
        bx("VisorBand", (1.28, 0.1, 0.2), (0, 0.65, 4.7), acc, bev=0.02, emit=2.0)
    elif head == "Full Face Plate":
        # PieceKits fullface (act1-choices, the Chairman): a plate over the whole face in the main colour, two thin
        # eye slits in the accent; the catalog face stays under it
        bx("FacePlate", (1.3, 0.1, 1.12), (0, 0.65, 4.58), tint("head", 0, prim), bev=0.06, metal=0.6, rough=0.3)
        for s in (-1, 1):
            bx("PlateSlit", (0.32, 0.04, 0.06), (s * 0.25, 0.71, 4.74), tint("head", 2, acc), bev=0.0, emit=1.5)
    elif head == "Eye Patch":
        bx("Patch", (0.3, 0.06, 0.26), (0.24, 0.65, 4.72), (24, 24, 28), bev=0.03)
        s = bx("PatchStrap", (1.3, 0.06, 0.06), (0, 0.64, 4.86), (24, 24, 28), bev=0.0)
        rot(s, -14, "Y", (0, 0.64, 4.8))
    back = pc.get("back")
    if back in ("Long Cape", "Star Cape", "Tattered Cape", "Meteor Cape"):
        cape(tint("back", 0, prim))
    elif back == "High Collar Cape":
        cape(tint("back", 0, prim), tint("back", 1, sec), collar=True)
    elif back in ("Hero Scarf", "Wind Scarf"):
        c = tint("back", 0, prim)
        put(kit.torus("Scarf", 0.6, 0.16, at=(0, 0, 4.02), segs=28, csegs=10), c, rough=0.85)
        t = bx("ScarfTail", (0.35, 0.1, 1.2), (0.45, -0.75, 3.5), c, bev=0.04, rough=0.85)
        rot(t, 18, "Y", (0.45, -0.75, 4.0))
    elif back in ("Duster Coat", "Field Coat"):
        # the coat's turned-up collar
        col = kit.cyl("CoatCollar", 0.92, 0.8, 0.45, at=(0, -0.05, 4.1), segs=28)
        kit.cut(col, Vector((0, 1, 0)), keep_positive=False)
        put(col, tint("back", 0, sec if back == "Duster Coat" else prim), rough=0.85)
    sh = pc.get("shoulders")
    if sh:
        c = tint("shoulders", 0, sec)
        big = {"Great Pauldrons": 1.25, "Riveted Pads": 1.05, "Layered Plates": 1.05, "Shell Pads": 1.05,
               "Gear Pads": 1.05}.get(sh, 0.9)
        metalish = sh in ("Great Pauldrons", "Riveted Pads", "Layered Plates", "Gear Pads", "Epaulettes",
                          "Shell Pads")
        for s in (-1, 1):
            if sh == "Epaulettes":
                bx("Epaulette", (1.05, 1.0, 0.12), (s * 1.5, 0, 4.06), c, bev=0.04, metal=0.7, rough=0.3)
                for k in range(5):
                    put(kit.cyl("Fringe", 0.05, 0.05, 0.3, at=(s * (1.0 + 0.0) + s * 0.22 * k + s * 0.05, 0.45,
                                                              3.88), segs=6), c, metal=0.7, rough=0.3)
            elif sh == "Crystal Shards":
                for k in range(3):
                    sp = kit.cyl("Shard", 0.16, 0.0, 0.7, at=(s * (1.25 + 0.25 * k), 0, 4.3), segs=6)
                    rot(sp, s * -25, "Y", (s * (1.25 + 0.25 * k), 0, 4.0))
                    put(sp, acc, emit=1.5)
            elif sh == "Flame Pads":
                put(kit.sphere("Pad", 0.6, at=(s * 1.5, 0, 4.0), scale=(1, 0.95, 0.5), segs=20, rings=10), c)
                for k in range(3):
                    f = kit.cyl("Flame", 0.16, 0.0, 0.55, at=(s * (1.2 + 0.28 * k), 0, 4.45), segs=8)
                    put(f, acc, emit=3.0)
            else:
                put(kit.sphere("Pad", 0.62 * big, at=(s * 1.5, 0, 4.0), scale=(1, 0.95, 0.55), segs=22,
                               rings=12), c, metal=0.6 if metalish else 0.0, rough=0.35 if metalish else 0.8)
    beard = pc.get("beard")
    if beard == "Full Beard":
        bx("Beard", (1.08, 0.3, 0.55), (0, 0.55, 4.27), hair_rgb, bev=0.1, rough=0.9)
    elif beard in ("Handlebar", "Pencil Mustache", "Horseshoe"):
        w = 0.5 if beard == "Pencil Mustache" else 0.62
        bx("Stache", (w, 0.08, 0.08 if beard == "Pencil Mustache" else 0.12), (0, 0.65, 4.47), hair_rgb, bev=0.03)
        if beard == "Handlebar":
            for s in (-1, 1):
                put(kit.sphere("Curl", 0.08, at=(s * 0.34, 0.65, 4.55), segs=10, rings=8), hair_rgb)
        if beard == "Horseshoe":
            for s in (-1, 1):
                bx("Drop", (0.1, 0.08, 0.32), (s * 0.27, 0.65, 4.3), hair_rgb, bev=0.03)
    elif beard == "Goatee":
        bx("Goatee", (0.28, 0.12, 0.26), (0, 0.62, 4.17), hair_rgb, bev=0.05)
    neck = pc.get("neck")
    if neck == "Chain":
        put(kit.torus("Chain", 0.62, 0.06, at=(0, 0.06, 3.96), segs=32, csegs=8), GOLD, metal=0.9, rough=0.25)
    elif neck == "Medal":
        put(kit.cyl("Medal", 0.2, 0.2, 0.06, at=(0, 0.53, 3.55), segs=20, axis="Y"), GOLD, metal=0.9, rough=0.25)
    elif neck == "High Collar":
        col = kit.cyl("HighCollar", 0.7, 0.66, 0.4, at=(0, -0.02, 4.12), segs=28)
        kit.cut(col, Vector((0, 1, 0)), keep_positive=False)
        put(col, sec, rough=0.6)
    elif neck == "Choker":
        put(kit.torus("Choker", 0.45, 0.05, at=(0, 0, 4.02), segs=28, csegs=8), DARK)
    if pc.get("ears") == "Fin Ears":
        for s in (-1, 1):
            f = bx("Fin", (0.06, 0.4, 0.5), (s * 0.64, -0.05, 4.75), tint("ears", 0, acc), bev=0.02)
            rot(f, s * -25, "Y", (s * 0.62, 0, 4.6))
    em = pc.get("emblem")
    if em:
        if EMBLEM is None:
            EMBLEM = emblem_spec()
        shape, backing = EMBLEM.get(em, (None, None))
        if backing and backing != "none":
            f = os.path.join(EMBLEMS, "EmblemBack_%s.png" % backing)
            if os.path.isfile(f):
                tinted_plane("EmblemBack", f, sec, (0, 0.512, 3.45), 0.9)
        f = shape and os.path.join(EMBLEMS, "Emblem_%s.png" % shape)
        if f and os.path.isfile(f):
            tinted_plane("Emblem", f, acc, (0, 0.52, 3.45), 0.72, emit=0.6)
    hair = pc.get("hair")
    if hair in ("Long Straight", "High Ponytail", "Wild Mane"):
        if hair == "Long Straight":
            bx("LongHair", (1.3, 0.3, 1.4), (0, -0.5, 4.3), hair_rgb, bev=0.12, rough=0.7)
        elif hair == "High Ponytail":
            t = kit.tube_along("Tail", [Vector(p) for p in ((0, -0.6, 5.2), (0, -0.95, 4.9), (0, -1.0, 4.2), (0, -0.9, 3.7))],
                               [0.2, 0.22, 0.17, 0.08], segs=12)
            put(t, hair_rgb, rough=0.7)
        else:
            for k in range(7):
                a = math.pi * (0.1 + 0.8 * k / 6)
                sp = kit.cyl("Mane", 0.2, 0.0, 0.7, at=(0.6 * math.cos(a), -0.3 - 0.15 * math.sin(a), 5.1 +
                                                       0.25 * math.sin(a)), segs=8)
                rot(sp, math.degrees(a) - 90, "Y", (0.6 * math.cos(a), -0.3, 5.1))
                put(sp, hair_rgb, rough=0.7)
    if pc.get("hair") == "Flame Hair":
        for k in range(5):
            x = (k - 2) * 0.24
            put(kit.cyl("Flame", 0.17, 0.0, 0.65, at=(x, -0.05 - abs(x) * 0.2, 5.6 - abs(x) * 0.3), segs=8),
                (255, 150, 40), emit=3.0)
    if pc.get("makeup") == "Star Mark":
        tinted_plane("StarMark", os.path.join(EMBLEMS, "Emblem_star.png"), (255, 255, 255), (0, 0.635, 5.0), 0.2,
                     emit=2.0)


# ------------------------------------------------------------------ finale models and world bosses
FINALE_BLOCKS = dict(clothed.BLOCKS)
FINALE_BLOCKS["Head"] = (-0.6, 0.6, -0.6, 0.6, 4.0, 5.2)


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before and o.type == "MESH"]


def recentre(ob):
    """Move the mesh so its bounds' centre is the object origin (FBX pieces come centred; make sure)."""
    vs = [v.co for v in ob.data.vertices]
    c = Vector((sum(v.x for v in vs) / len(vs), 0, 0))
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (lo + hi) / 2
    ob.data.transform(Matrix.Translation(-c))
    return hi - lo


def tinted_map(name, color_img, tint):
    """The baked colour map over the part colour where its alpha is clear (SurfaceAppearance Overlay)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.5
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = color_img
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(t.outputs["Alpha"], mix.inputs["Factor"])
    mix.inputs["A"].default_value = (*(clothed.lin(c) for c in tint), 1)
    nt.links.new(t.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    return m


def finale(name, art):
    obs = import_fbx(os.path.join(kit.ROOT, "export", "finales", name + ".fbx"))
    img = bpy.data.images.load(os.path.join(kit.ROOT, "export", "finales", name + "_Color.png"),
                               check_existing=True)
    m = tinted_map(name, img, tuple(art["tint"]))
    for ob in obs:
        part = ob.name.split(".")[0]
        recentre(ob)
        ob.data.materials.clear()
        ob.data.materials.append(m)
        if part in FINALE_BLOCKS:
            x0, x1, y0, y1, z0, z1 = FINALE_BLOCKS[part]
            ob.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        elif part in art["extras"]:
            x = art["extras"][part]
            x0, x1, y0, y1, z0, z1 = FINALE_BLOCKS[x["parent"]]
            c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
            sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
            o = x["offset"]
            # (x, up, depth) fractions of the parent's size; depth is Roblox's back (+z), Blender's -y
            ob.location = c + Vector((o[0] * sx, -o[2] * sy, o[1] * sz))
        else:
            ob.hide_render = True
        kit.shade_auto(ob, 40)
    return obs


def boss(name, art, glow, weak):
    # bosses-3: the second set (Storm Colossus, Swarm Queen, Quarry Titan) is in Bosses2.fbx (BossArt's `set`)
    obs = import_fbx(os.path.join(kit.ROOT, "export", (art.get("set") or "Bosses") + ".fbx"))
    img = bpy.data.images.load(os.path.join(kit.ROOT, "export", "bosses", name + "_Color.png"), check_existing=True)
    body = tinted_map(name, img, (128, 128, 128))
    shown = []
    for ob in obs:
        boss_name, _, piece = ob.name.split(".")[0].partition("_")
        if boss_name != name or piece not in art["pieces"]:
            ob.hide_render = True
            continue
        row = art["pieces"][piece]
        recentre(ob)
        o = row["offset"]
        ob.location = (o[0], -o[2], o[1])  # (x, up, back) from the feet; a boss faces Roblox -z, Blender +y
        ob.data.materials.clear()
        if row["role"] == "glow":
            ob.data.materials.append(kit.material("Glow" + name, srgb(glow), emit=4.0))
        elif row["role"] == "weak":
            ob.data.materials.append(kit.material("Weak" + name, srgb(weak), emit=4.0))
        else:
            ob.data.materials.append(body)
        kit.shade_auto(ob, 40)
        shown.append(ob)
    return shown


# ------------------------------------------------------------------ one page
BOSS_VIEW = {  # the camera's yaw round the boss (degrees from its front), a lift of the frame's centre (a
    # share of its size) and how much of its height from the top the frame takes
    "RustjawPrime": (24, 0.0, 0.72),
    "LumenMaw": (38, 0.0, 1.0),
    "LeviathanEngine": (40, 0.0, 0.62),
    "StormColossus": (28, 0.0, 0.9),
    "SwarmQueen": (30, 0.0, 1.0),
    "QuarryTitan": (26, 0.0, 0.75),
}


def setup(samples):
    kit.studio(res=(RES, RES), samples=samples)
    s = bpy.context.scene
    s.render.film_transparent = True
    s.view_settings.view_transform = "Standard"
    # comic ink: Freestyle silhouettes, borders and creases
    s.render.use_freestyle = True
    s.render.line_thickness_mode = "ABSOLUTE"
    s.render.line_thickness = 2.2
    vl = s.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(140)
    ls = fs.linesets[0] if fs.linesets else fs.linesets.new("Ink")
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("Ink")
    ls.linestyle.color = (0.04, 0.04, 0.06)
    ls.linestyle.thickness = 2.2
    # flatter comic light: a brighter sky fill
    s.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.62, 1)
    s.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0


def frame(yaw, centre, scale):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    bpy.context.scene.collection.objects.link(cam)
    a = math.radians(yaw)
    d = 60.0 * max(1.0, scale / 6)
    c = Vector(centre)
    cam.location = c + Vector((math.sin(a) * d, math.cos(a) * d, d * 0.08))
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = d * 4
    bpy.context.scene.camera = cam
    # turn the sun lights with the camera so every page is lit alike
    for ob in bpy.data.objects:
        if ob.type == "LIGHT":
            ob.rotation_euler.z += a


def bounds(objs, yaw, above=-1e9):
    """The objects' extent across (x seen by a camera at this yaw) and up (z), of the points above a height."""
    a = math.radians(yaw)
    right = Vector((math.cos(a), -math.sin(a), 0))
    xs, zs = [], []
    for ob in objs:
        if ob.type != "MESH" or ob.hide_render:
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            p = mw @ v.co
            if p.z < above:
                continue
            xs.append(p.dot(right))
            zs.append(p.z)
    return min(xs), max(xs), min(zs), max(zs)


def render_page(page, people):
    kit.reset()
    setup(SAMPLES)
    pid = page["id"]
    g = page["group"]
    yaw = YAW
    if g == "bosses":
        art = page["bossArt"]
        glow = tuple(art["glow"][0])
        weak = tuple(page["weakColor"])
        obs = boss(pid, art, glow, weak)
        yaw, lift, crop = BOSS_VIEW.get(pid, (24, 0.0, 1.0))
        bpy.context.view_layer.update()
        x0, x1, z0, z1 = bounds(obs, yaw)
        # the upper part of the body (crop of its height from the top), so the head and the glow read at row
        # size: framed on that part's own width
        top_part = z1 - (z1 - z0) * crop
        x0, x1, _, _ = bounds(obs, yaw, top_part)
        size = max(x1 - x0, z1 - top_part) * 1.04
        a = math.radians(yaw)
        mid = (x0 + x1) / 2
        centre = (mid * math.cos(a), -mid * math.sin(a), z1 - size / 2 + lift * size)
        frame(yaw, centre, size)
        bpy.context.scene.render.line_thickness = 2.6
    else:
        finale_art = page.get("finaleArt")
        if finale_art:
            finale(page["finaleName"], finale_art)
        elif g == "robots":
            i = page["index"]
            body = page.get("body") or {}
            suit, trim, eye = [tuple(c) for c in page["colors"]]
            clothed.figure((0, 0, 0), 0, SKINS[i % len(SKINS)], HAIRS[(i * 5) % len(HAIRS)], turned=True,
                           face=FACES[i % len(FACES)], outfit="uniforms/%s_Grunt" % pid,
                           hair_on=not (body.get("helmet") or body.get("cap") or body.get("hook")))
            robot_gear(body, suit, trim, eye)
        else:
            person = people.get(page.get("person") or "")
            if pid == "EvilTwin":
                # the double wears your look: a hero in a hero suit, its face cracked to the metal
                skin, hair, face, outfit = (224, 172, 130), (40, 30, 26), "faces/Face_Hero_Cracked", \
                    "heroes/preview/Hero1"
            else:
                skin, hair = tuple(person["skin"]), tuple(person["hair"])
                face, outfit = person["face"], "people/" + person["name"]
            pc = (page.get("look") or {}).get("pieces") or {}
            hatted = pc.get("hat") in ("Top Hat", "Wide Brim", "Ball Cap") or pc.get("hair") == "Buzz Cut"
            clothed.figure((0, 0, 0), 0, skin, hair, face=face, outfit=outfit, layered=True, hair_on=not hatted)
            pieces(page, skin, hair)
            if page.get("body", {}).get("riot") and pid == "Bulwark":
                robot_gear({"riot": True}, tuple(page["rgb"][0]), tuple(page["rgb"][1]), (255, 240, 80))
            if page.get("body", {}).get("spear"):
                # Skylance's spear, upright past the right shoulder
                put(kit.cyl("Spear", 0.09, 0.09, 4.6, at=(1.55, 0.35, 3.9), segs=10), (215, 220, 230), metal=0.8,
                    rough=0.3)
                put(kit.cyl("SpearTip", 0.2, 0.0, 0.8, at=(1.55, 0.35, 6.55), segs=4), tuple(page["rgb"][1]),
                    metal=0.6, rough=0.3, emit=0.5)
            # (Captain Brine's anchor hangs at his hip, below a bust's frame: his hat, patch and beard carry it)
        bpy.context.view_layer.update()
        objs = list(bpy.data.objects)
        x0, x1, z0, z1 = bounds(objs, yaw)
        top = max(z1, 5.45) + 0.15
        low = 2.6
        size = max(top - low, 3.6)
        a = math.radians(yaw)
        frame(yaw, (0, 0, low + size / 2), size)
    no_ink()
    os.makedirs(RAW, exist_ok=True)
    kit.render(os.path.join(RAW, pid + ".png"))


def no_ink():
    """Flat decal planes (the face, emblems, marks) take no ink line round their square edge."""
    s = bpy.context.scene
    col = bpy.data.collections.new("NoInk")
    s.collection.children.link(col)
    for ob in list(s.collection.objects):
        if ob.type == "MESH" and len(ob.data.vertices) == 4:
            col.objects.link(ob)
            s.collection.objects.unlink(ob)
    ls = s.view_layers[0].freestyle_settings.linesets[0]
    ls.select_by_collection = True
    ls.collection = col
    ls.collection_negation = "EXCLUSIVE"


def main():
    pages = json.load(open(PAGES, encoding="utf-8"))
    people = {r["name"]: r for page in json.load(open(PEOPLE, encoding="utf-8")) for r in page}
    robots = [p for p in pages if p["group"] == "robots"]
    for p in pages:
        p["index"] = robots.index(p) if p in robots else 0
        if ONLY and p["id"] not in ONLY:
            continue
        print("rogues.py:", p["id"], flush=True)
        render_page(p, people)


main()
