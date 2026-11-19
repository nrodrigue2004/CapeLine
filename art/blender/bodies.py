# bodies.py: the 8 hero body sets of the creator plan (nate, 2026-11-16: Male and Female, Small, Medium, Large
# and Titan for "hulk or thing fantasies"). Each set reshapes the classic blocky R15 hero from hero.py, still
# blocky: tapered torsos, a broad V on the big builds, a soft chest and flared hips on the female sets, deltoids,
# thick forearms and tapered thighs and calves. Sizes do not change here: the game sizes each MeshPart from
# Config.HeroRig times BodyShape's factors, so a set only changes the shape inside each part's box.
# Only the parts a set changes are exported (Male Medium is hero.py's own body): 10 parts (both torsos, upper and
# lower arms, upper and lower legs) for each of the 7 other sets where the set changes it (54 meshes), named "<Set>_<Part>", for example
# "FemaleTitan_UpperTorso". Head, hands and feet always come from Art.Hero.
# Output: art/export/Bodies.fbx (nate imports it with Studio's 3D Importer into ReplicatedStorage.Art as
# "Bodies"; the model is then pulled back into art/models/Bodies.rbxm) and art/preview/bodies.png (all 8,
# sized by the game's own factors, front and side).
# Run: $HOME/tools/bpyenv/bin/python art/blender/bodies.py [--preview [--side]] [--no-export] [--torsos]
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import template_uv  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

BEVEL = 0.07

# hero.py's joints and block bounds (Blender: x across, y front, z up; the hero's left is -x)
J = {
    "Root": Vector((0, 0, 2.2)),
    "Waist": Vector((0, 0, 2.4)),
    "Neck": Vector((0, 0, 4.0)),
    "LeftShoulder": Vector((-1.0, 0, 3.76)),
    "LeftElbow": Vector((-1.5, 0, 3.15)),
    "LeftWrist": Vector((-1.5, 0, 2.3)),
    "LeftHip": Vector((-0.5, 0, 2.0)),
    "LeftKnee": Vector((-0.5, 0, 1.15)),
    "LeftAnkle": Vector((-0.5, 0, 0.3)),
}
for _k in list(J):
    if _k.startswith("Left"):
        _v = J[_k]
        J["Right" + _k[4:]] = Vector((-_v.x, _v.y, _v.z))

BOUNDS = {"UpperTorso": (-1.0, 1.0, 2.4, 4.0), "LowerTorso": (-1.0, 1.0, 2.0, 2.4)}
for _s in ("Left", "Right"):
    _x0, _x1 = (-2.0, -1.0) if _s == "Left" else (1.0, 2.0)
    _l0, _l1 = (-1.0, 0.0) if _s == "Left" else (0.0, 1.0)
    BOUNDS[_s + "UpperArm"] = (_x0, _x1, 3.15, 4.0)
    BOUNDS[_s + "LowerArm"] = (_x0, _x1, 2.3, 3.15)
    BOUNDS[_s + "Hand"] = (_x0, _x1, 2.0, 2.3)
    BOUNDS[_s + "UpperLeg"] = (_l0, _l1, 1.15, 2.0)
    BOUNDS[_s + "LowerLeg"] = (_l0, _l1, 0.3, 1.15)
    BOUNDS[_s + "Foot"] = (_l0, _l1, 0.0, 0.3)

SHAPED = ["UpperTorso", "LowerTorso"] + [s + p for s in ("Left", "Right") for p in ("UpperArm", "LowerArm", "UpperLeg", "LowerLeg")]

# ---------------------------------------------------------------- the 8 sets
# Each shape: top and bottom width (x) of the part as a share of its box, and for the upper torso a chest
# (how far the front pushes out over the chest, as a share of the depth). 1 = the classic straight block.
BUILDS = ["Small", "Medium", "Large", "Titan"]
GENDERS = ["Male", "Female"]
SHAPES = {
    "MaleSmall": {"UpperTorso": (1.0, 0.92, 0.0)},
    "MaleMedium": {},
    "MaleLarge": {"UpperTorso": (1.0, 0.8, 0.05), "UpperArm": (1.0, 0.88), "LowerArm": (1.0, 0.86), "UpperLeg": (1.0, 0.88), "LowerLeg": (1.0, 0.86)},
    "MaleTitan": {"UpperTorso": (1.0, 0.68, 0.1), "LowerTorso": (0.9, 0.86), "UpperArm": (1.0, 0.8), "LowerArm": (0.86, 1.0), "UpperLeg": (1.0, 0.82), "LowerLeg": (1.0, 0.8)},
    "FemaleSmall": {"UpperTorso": (1.0, 0.82, 0.06), "LowerTorso": (0.88, 1.0), "UpperArm": (1.0, 0.92), "UpperLeg": (1.0, 0.85)},
    "FemaleMedium": {"UpperTorso": (1.0, 0.8, 0.07), "LowerTorso": (0.88, 1.0), "UpperArm": (1.0, 0.92), "UpperLeg": (1.0, 0.85), "LowerLeg": (1.0, 0.9)},
    "FemaleLarge": {"UpperTorso": (1.0, 0.76, 0.08), "LowerTorso": (0.86, 1.0), "UpperArm": (1.0, 0.86), "LowerArm": (1.0, 0.88), "UpperLeg": (1.0, 0.84), "LowerLeg": (1.0, 0.86)},
    "FemaleTitan": {"UpperTorso": (1.0, 0.7, 0.1), "LowerTorso": (0.86, 0.96), "UpperArm": (1.0, 0.8), "LowerArm": (0.88, 1.0), "UpperLeg": (1.0, 0.82), "LowerLeg": (1.0, 0.8)},
}

# Config.Creator.body (kept in step by tests/run.luau "Body sets": builds' width, depth, limbs, hands, head, tall)
FACTORS = {
    "Small": (0.85, 0.9, 0.85, 1.0, 1.0, 0.95),
    "Medium": (1.0, 1.0, 1.0, 1.0, 1.0, 1.0),
    "Large": (1.25, 1.15, 1.2, 1.15, 1.0, 1.05),
    "Titan": (1.6, 1.4, 1.5, 1.4, 0.9, 1.15),
}
FEMALE_WAIST = 0.85


def shape_of(set_name, part):
    s = SHAPES[set_name]
    if part in s:
        return s[part]
    for kind in ("UpperArm", "LowerArm", "UpperLeg", "LowerLeg"):
        if part.endswith(kind) and kind in s:
            return s[kind]
    return None


def smoothstep(a, b, t):
    t = max(0.0, min(1.0, (t - a) / (b - a)))
    return t * t * (3 - 2 * t)


def block(name, part, shape):
    x0, x1, z0, z1 = BOUNDS[part]
    ob = kit.box(name, x1 - x0, 1.0, z1 - z0, at=((x0 + x1) / 2, 0, (z0 + z1) / 2))
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = BEVEL
    m.segments = 3
    m.limit_method = "NONE"
    kit.apply_all(ob)
    template_uv.apply(ob, part)  # classic Shirt and Pants need the template UVs, set before the taper bends the box
    if shape:
        top, bottom = shape[0], shape[1]
        chest = shape[2] if len(shape) > 2 else 0.0
        cx = (x0 + x1) / 2
        # a torso tapers about the body's middle; a limb about its own middle (so arms stay on the shoulders)
        widest = max(top, bottom)

        def fn(v):
            t = (v.z - z0) / (z1 - z0)
            w = (bottom + (top - bottom) * t) / widest
            v.x = cx + (v.x - cx) * w
            if chest > 0 and v.y > 0:
                # a soft shelf over the upper half of the chest, flat at the very top (the collar)
                bump = smoothstep(0.35, 0.6, t) * (1 - smoothstep(0.85, 1.0, t))
                v.y += chest * bump * (v.y / 0.5)
            return v

        kit.deform(ob, fn)
    kit.shade_auto(ob, 35)
    return ob


def head(name):
    rings = []
    for z, r in ((4.02, 0.36), (4.04, 0.46), (4.08, 0.53), (4.15, 0.58), (4.25, 0.6), (4.97, 0.6), (5.07, 0.58),
                 (5.14, 0.53), (5.18, 0.46), (5.2, 0.36)):
        rings.append((z, r, r, 0, 0))
    ob = kit.loft(name, rings, segs=40, power=2.25)
    kit.smooth(ob, 1)
    kit.apply_all(ob)
    kit.shade_auto(ob, 35)
    return ob


# ---------------------------------------------------------------- build every set
sets = {}
for g in GENDERS:
    for b in BUILDS:
        key = g + b
        body = {}
        for part in BOUNDS:
            body[part] = block(key + "_" + part, part, shape_of(key, part) if part in SHAPED else None)
        body["Head"] = head(key + "_Head")
        sets[key] = body

exported = []
for key, body in sets.items():
    if key == "MaleMedium":
        continue
    for part in SHAPED:
        if shape_of(key, part) is None:
            continue  # this set keeps the hero's own part
        body[part].name = key + "_" + part + "_src"  # free the name so the copy gets it exactly (no .001)
        cp = body[part].copy()
        cp.data = body[part].data.copy()
        bpy.context.scene.collection.objects.link(cp)
        kit.centre(cp)
        cp.name = key + "_" + part
        cp.data.name = cp.name
        exported.append(cp)
print("body set meshes:", len(exported), "triangles each ~", kit.tris(exported[0]) if exported else 0)
for cp in exported:
    print("  ", cp.name)

if "--no-export" not in sys.argv:
    kit.export_fbx(exported, os.path.join(kit.ROOT, "export", "Bodies.fbx"))
# --torsos (fix-bodies, 2026-11-19): the sets' torsos again, PRE-TURNED 180 degrees about up, into
# art/export/BodyTorsos.fbx (uploaded as Art.BodyTorsos). Roblox's Open Cloud FBX import stores every mesh turned
# 180 degrees about y in its box (art/upload/meshcheck.py, art/models/meshturns.json); a placed MeshPart can be
# turned back (Shared.MeshFix), but LookKit.wearBodySet puts these on the live torsos with MeshPart:ApplyMesh,
# which cannot turn, so these copies are drawn turned and the import's turn faces them forward again. The UVs ride
# with the vertices, so classic Shirt and Pants still land front on front.
if "--torsos" in sys.argv:
    torsos = []
    for cp in exported:
        if cp.name.endswith("_UpperTorso") or cp.name.endswith("_LowerTorso"):
            t = cp.copy()
            t.data = cp.data.copy()
            bpy.context.scene.collection.objects.link(t)
            for v in t.data.vertices:
                v.co.x, v.co.y = -v.co.x, -v.co.y  # Blender x and y (Roblox x and z): 180 degrees about up
            t.data.update()
            torsos.append(t)
    for t in torsos:
        name = t.name.split(".")[0]
        t.name = name
    kit.export_fbx(torsos, os.path.join(kit.ROOT, "export", "BodyTorsos.fbx"))
    print("body torsos (pre-turned):", len(torsos))
    for t in torsos:
        bpy.data.objects.remove(t, do_unlink=True)
for cp in exported:
    bpy.data.objects.remove(cp, do_unlink=True)

# ---------------------------------------------------------------- preview: each set as the game sizes it
PARENT = {"UpperTorso": ("LowerTorso", "Waist"), "Head": ("UpperTorso", "Neck")}
for _s in ("Left", "Right"):
    PARENT[_s + "UpperArm"] = ("UpperTorso", _s + "Shoulder")
    PARENT[_s + "LowerArm"] = (_s + "UpperArm", _s + "Elbow")
    PARENT[_s + "Hand"] = (_s + "LowerArm", _s + "Wrist")
    PARENT[_s + "UpperLeg"] = ("LowerTorso", _s + "Hip")
    PARENT[_s + "LowerLeg"] = (_s + "UpperLeg", _s + "Knee")
    PARENT[_s + "Foot"] = (_s + "LowerLeg", _s + "Ankle")


def centre_of(part):
    if part == "Head":
        return Vector((0, 0, 4.61))
    x0, x1, z0, z1 = BOUNDS[part]
    return Vector(((x0 + x1) / 2, 0, (z0 + z1) / 2))


def factor(build, female, part):
    """BodyShape.factors for one part, in Blender axes (x, depth, up)."""
    w, d, limbs, hands, hd, tall = FACTORS[build]
    if part == "Head":
        return Vector((hd, hd, hd))
    if part in ("UpperTorso", "LowerTorso"):
        ww = w * (FEMALE_WAIST if female and part == "LowerTorso" else 1)
        return Vector((ww, d, tall))
    if part.endswith("Hand"):
        return Vector((hands, hands, hands))
    if "Arm" in part:
        return Vector((limbs, limbs, tall))
    waist = w * (FEMALE_WAIST if female else 1)
    t = min(limbs, waist)
    return Vector((t, min(limbs, d), tall))


def place(key, at, mats, yaw=0.0):
    build = key[4:] if key.startswith("Male") else key[6:]
    female = key.startswith("Female")
    body = sets[key]
    cen = {"LowerTorso": Vector((0, 0, 0))}

    def find(p):
        if p in cen:
            return cen[p]
        par, jn = PARENT[p]
        pc = find(par)
        ka, kb = factor(build, female, par), factor(build, female, p)
        a = J[jn] - centre_of(par)
        bb = J[jn] - centre_of(p)
        cen[p] = pc + Vector((a.x * ka.x, a.y * ka.y, a.z * ka.z)) - Vector((bb.x * kb.x, bb.y * kb.y, bb.z * kb.z))
        return cen[p]

    out = []
    low = 1e9
    for p in body:
        find(p)
    for p, ob in body.items():
        k = factor(build, female, p)
        low = min(low, cen[p].z - k.z * (BOUNDS[p][3] - BOUNDS[p][2]) / 2 if p in BOUNDS else 1e9)
    Y = Matrix.Rotation(math.radians(yaw), 4, "Z")
    for p, ob in body.items():
        k = factor(build, female, p)
        c0 = centre_of(p)
        m = Matrix.Translation(Vector(at) + Y @ (cen[p] - Vector((0, 0, low)))) @ Y @ Matrix.Diagonal((k.x, k.y, k.z, 1)) @ Matrix.Translation(-c0)
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.matrix_world = m
        cp.data.materials.clear()
        skin = p == "Head" or p.endswith("Hand")
        cp.data.materials.append(mats["skin"] if skin else mats["trim"] if p.endswith("Foot") else mats["suit"])
        cp.hide_render = False
        out.append(cp)
    return out


if "--preview" in sys.argv:
    for body in sets.values():
        for ob in body.values():
            ob.hide_render = True
    kit.studio(res=(2400, 700), samples=40)
    suit = kit.material("suit", (46, 84, 168), rough=0.45)
    suitF = kit.material("suitF", (168, 52, 96), rough=0.45)
    trim = kit.material("trim", (240, 196, 70), rough=0.35)
    skin = kit.material("skin", (224, 172, 130), rough=0.6)
    # three-quarter views in a row, left to right as seen: Male Small to Titan, then Female Small to Titan
    # (--side turns them to a side view). The camera looks down -y, so the viewer's left is +x.
    order = [(g, b) for g in GENDERS for b in BUILDS]
    widths = [3.4 * FACTORS[b][0] + 1.4 for _, b in order]
    total = sum(widths) + 2.0
    x = total / 2
    for i, (g, b) in enumerate(order):
        if i == 4:
            x -= 2.0  # a gap between the male and female sets
        x -= widths[i] / 2
        mats = {"suit": suit if g == "Male" else suitF, "trim": trim, "skin": skin}
        side = "--side" in sys.argv
        place(g + b, (x, 0, 0), mats, yaw=(-90 if side else -28))
        x -= widths[i] / 2
    floor = kit.box("floor", total + 10, 30, 0.2, at=(0, -5, -0.1))
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 50.0, 9.0), (0, 0, 2.9), lens=40)
    kit.render(os.path.join(kit.ROOT, "preview", "bodies_side.png" if "--side" in sys.argv else "bodies.png"))
