# hero.py: the hero base body on the standard Roblox R15 rig (nate, 2026-11-16: "All humanoid models should
# follow that basic r15 roblox model"). 15 smooth rigid parts named exactly as R15 (Head, UpperTorso,
# LowerTorso, Left/Right UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot). Each part is a closed, rounded
# shape that overlaps its neighbour at the joint, so elbows, knees and shoulders bend without gaps.
# Output: art/export/Hero.fbx (import with Studio's 3D Importer, save as art/models/Hero.rbxm),
# src/config/HeroRig.luau (each part's size and centre, every R15 rig and accessory attachment, the root
# part and hip height; HeroBody builds the character from it) and art/preview/hero.png.
# Run: python art/blender/hero.py --preview   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def bump(x, c, w):
    return math.exp(-((x - c) / w) ** 2)


# ---------------------------------------------------------------- the skeleton (Blender: z up, front +y,
# the hero's left is -x like Roblox). Feet on z = 0, about 5.85 studs tall.
J = {
    "Root": Vector((0, 0, 2.95)),
    "Waist": Vector((0, 0, 3.12)),
    "Neck": Vector((0, -0.02, 4.66)),
    "LeftShoulder": Vector((-0.86, 0, 4.36)),
    "LeftElbow": Vector((-0.98, 0, 3.4)),
    "LeftWrist": Vector((-0.99, 0.03, 2.44)),
    "LeftHip": Vector((-0.34, 0, 2.55)),
    "LeftKnee": Vector((-0.34, 0.02, 1.44)),
    "LeftAnkle": Vector((-0.34, 0, 0.36)),
}
for k in list(J):
    if k.startswith("Left"):
        v = J[k]
        J["Right" + k[4:]] = Vector((-v.x, v.y, v.z))

ROOT_PART = {"size": (2.0, 2.0, 1.0), "centre": Vector((0, 0, 3.0))}  # the HumanoidRootPart (Roblox x, up, depth)

# triangle budget per part (about 10k for the whole hero, Roblox's cap is 20k a mesh)
BUDGET = {"Head": 1500, "UpperTorso": 2000, "LowerTorso": 650, "UpperArm": 560, "LowerArm": 440, "Hand": 520,
          "UpperLeg": 620, "LowerLeg": 540, "Foot": 460}

parts = {}


def budget(ob, key):
    kit.apply_all(ob)
    have = kit.tris(ob)
    want = BUDGET[key]
    if have > want:
        kit.decimate(ob, want / have)
        kit.apply_all(ob)
    return ob


def done(ob, key):
    budget(ob, key)
    kit.shade_auto(ob, 50)
    parts[ob.name] = ob
    return ob


# ---------------------------------------------------------------- torso
def upper_torso():
    rings = [
        (3.02, 0.5, 0.35, 0, 0.0), (3.2, 0.51, 0.37, 0, 0.01), (3.42, 0.55, 0.4, 0, 0.02),
        (3.66, 0.62, 0.44, 0, 0.03), (3.88, 0.68, 0.47, 0, 0.03), (4.08, 0.72, 0.47, 0, 0.02),
        (4.24, 0.72, 0.44, 0, 0.0), (4.38, 0.62, 0.39, 0, -0.02), (4.5, 0.5, 0.32, 0, -0.03),
        (4.62, 0.3, 0.24, 0, -0.03), (4.72, 0.21, 0.19, 0, -0.02),
    ]
    ob = kit.loft("UpperTorso", rings, segs=32, power=2.35)
    kit.smooth(ob, 2)

    def muscles(v):
        x, y, z = v.x, v.y, v.z
        ax = abs(x)
        if y > 0:
            # pecs: a rounded plate each side with a crease under it and a groove down the middle
            k = smoothstep(3.78, 3.95, z) * (1 - smoothstep(4.18, 4.36, z)) * smoothstep(0.04, 0.16, ax) * (1 - smoothstep(0.52, 0.72, ax))
            y += 0.075 * k
            y -= 0.03 * bump(z, 3.8, 0.05) * smoothstep(0.08, 0.2, ax) * (1 - smoothstep(0.5, 0.66, ax))
            y -= 0.025 * bump(x, 0, 0.035) * smoothstep(3.25, 3.5, z) * (1 - smoothstep(4.25, 4.4, z))
            # abs: two columns, three rows
            if z < 3.76:
                rows = sum(bump(z, c, 0.025) for c in (3.27, 3.45, 3.62))
                y -= 0.02 * min(1.0, rows) * (ax < 0.3) * smoothstep(0.02, 0.06, ax)
                y += 0.025 * smoothstep(0.02, 0.08, ax) * (1 - smoothstep(0.24, 0.34, ax))
            # the collarbones
            y += 0.02 * bump(z, 4.4, 0.03) * smoothstep(0.08, 0.2, ax) * (1 - smoothstep(0.5, 0.6, ax))
        else:
            # the back: a groove down the spine, shoulder blades and lats
            y += 0.03 * bump(x, 0, 0.04) * smoothstep(3.1, 3.4, z)
            y -= 0.045 * bump(z, 4.08, 0.16) * bump(ax, 0.38, 0.17)
            y -= 0.02 * bump(z, 3.7, 0.2) * bump(ax, 0.55, 0.15)
        # trapezius: the slope from the neck to the shoulders swells a little
        if z > 4.4:
            s = bump(ax, 0.38, 0.14) * smoothstep(4.4, 4.55, z)
            z += 0.04 * s
        return Vector((x, y, z))

    kit.deform(ob, muscles)
    return done(ob, "UpperTorso")


def lower_torso():
    rings = [
        (2.42, 0.26, 0.22, 0, 0.0), (2.52, 0.45, 0.34, 0, -0.01), (2.68, 0.54, 0.39, 0, -0.02),
        (2.86, 0.56, 0.4, 0, -0.02), (3.0, 0.53, 0.38, 0, -0.01), (3.14, 0.5, 0.36, 0, 0.0),
        (3.24, 0.47, 0.33, 0, 0.0),
    ]
    ob = kit.loft("LowerTorso", rings, segs=28, power=2.4)
    kit.smooth(ob, 2)

    def shape(v):
        x, y, z = v.x, v.y, v.z
        ax = abs(x)
        if y < 0:  # glutes
            y -= 0.04 * bump(z, 2.66, 0.12) * bump(ax, 0.24, 0.15)
        else:  # a soft V from the hips into the groin
            y -= 0.03 * bump(ax, 0.34, 0.08) * bump(z, 2.6, 0.1)
        return Vector((x, y, z))

    kit.deform(ob, shape)
    return done(ob, "LowerTorso")


# ---------------------------------------------------------------- head and neck
def head():
    c = 5.27  # the middle of the skull
    prof = [  # (z, half width, half depth, front shift): chin to crown, anime proportions (big skull, small jaw)
        (4.56, 0.19, 0.18, -0.02), (4.8, 0.19, 0.18, -0.02), (4.88, 0.2, 0.19, 0.0),
        (4.93, 0.26, 0.26, 0.08), (4.98, 0.33, 0.33, 0.08), (5.07, 0.41, 0.42, 0.05),
        (5.17, 0.46, 0.48, 0.03), (5.3, 0.49, 0.51, 0.01), (5.44, 0.49, 0.51, 0.0),
        (5.58, 0.45, 0.48, -0.01), (5.7, 0.36, 0.4, -0.02), (5.79, 0.22, 0.26, -0.02), (5.83, 0.07, 0.08, -0.02),
    ]
    ob = kit.loft("Head", [(z, rx, ry, 0, cy) for z, rx, ry, cy in prof], segs=32, power=2.15)
    kit.smooth(ob, 2)

    def face(v):
        x, y, z = v.x, v.y, v.z
        ax = abs(x)
        if y > 0.15 and z > 4.9:
            # a gentle jaw line, cheeks, a small nose and soft eye sockets (the eyes and mouth are the creator's
            # face pieces, so the front stays smooth enough for them to sit on)
            y += 0.035 * bump(ax, 0.26, 0.09) * bump(z, 5.13, 0.06)
            y += 0.055 * bump(x, 0, 0.045) * bump(z, 5.16, 0.06) * smoothstep(0.2, 0.4, y)
            y -= 0.022 * bump(ax, 0.19, 0.08) * bump(z, 5.3, 0.045)
            y += 0.018 * bump(ax, 0.19, 0.12) * bump(z, 5.39, 0.03)
        # the jaw angles out under the ears
        if z < 5.1:
            x *= 1 + 0.08 * bump(z, 5.0, 0.06) * smoothstep(-0.1, 0.1, -y)
        return Vector((x, y, z))

    kit.deform(ob, face)
    for s in (-1, 1):
        ear = kit.loft("ear", [(-0.11, 0.02, 0.05, 0, 0), (-0.02, 0.045, 0.085, 0, 0), (0.08, 0.04, 0.075, 0, 0), (0.12, 0.02, 0.04, 0, 0)], segs=12)
        kit.smooth(ear, 1)
        kit.shift(ear, (s * 0.485, -0.05, c - 0.02))
        ob = kit.join("Head", [ob, ear], shade=False)
    return done(ob, "Head")


# ---------------------------------------------------------------- arms
def upper_arm(side):
    s = -1 if side == "Left" else 1
    sh, el = J[side + "Shoulder"], J[side + "Elbow"]
    x0 = el.x
    rings = [  # elbow to shoulder; the deltoid leans in over the joint
        (3.3, 0.16, 0.16, 0, 0.0), (3.42, 0.18, 0.18, 0, 0.0), (3.62, 0.2, 0.21, 0, 0.02),
        (3.86, 0.215, 0.235, 0, 0.03), (4.06, 0.225, 0.235, -0.01, 0.015), (4.22, 0.245, 0.24, -0.03, 0.0),
        (4.36, 0.245, 0.235, -0.07, -0.01), (4.46, 0.2, 0.2, -0.11, -0.01), (4.52, 0.09, 0.09, -0.12, -0.01),
    ]
    ob = kit.loft(side + "UpperArm", [(z, rx, ry, s * cx + x0, cy) for z, rx, ry, cx, cy in rings], segs=24, power=2.2)
    kit.smooth(ob, 2)

    def bicep(v):
        x, y, z = v.x, v.y, v.z
        if y > 0:
            y += 0.022 * bump(z, 3.78, 0.15)
        else:
            y -= 0.012 * bump(z, 3.95, 0.18)
        return Vector((x, y, z))

    kit.deform(ob, bicep)
    _ = sh
    return done(ob, "UpperArm")


def lower_arm(side):
    s = -1 if side == "Left" else 1
    x0 = J[side + "Elbow"].x
    rings = [  # wrist to elbow, flattened front-to-back with the forearm swell near the elbow
        (2.38, 0.125, 0.105, 0, 0.03), (2.52, 0.135, 0.115, 0, 0.025), (2.78, 0.16, 0.14, 0, 0.015),
        (3.06, 0.185, 0.165, 0.0, 0.01), (3.28, 0.18, 0.17, 0, 0.0), (3.44, 0.155, 0.155, 0, 0.0),
        (3.5, 0.08, 0.08, 0, 0.0),
    ]
    ob = kit.loft(side + "LowerArm", [(z, rx, ry, s * cx + x0, cy) for z, rx, ry, cx, cy in rings], segs=22, power=2.3)
    kit.smooth(ob, 2)
    return done(ob, "LowerArm")


def hand(side):
    s = -1 if side == "Left" else 1
    w = J[side + "Wrist"]
    # a relaxed hand, palm in, fingers together and a little curled; the thumb on the front
    palm = kit.loft("palm", [(2.44, 0.1, 0.12, 0, 0.0), (2.36, 0.12, 0.155, 0, 0.0), (2.2, 0.125, 0.18, 0, 0.0), (2.08, 0.115, 0.18, 0, 0.0)], segs=18, power=2.8)
    fingers = kit.loft("fingers", [(2.1, 0.11, 0.17, 0, 0.0), (1.98, 0.1, 0.165, 0, 0.0), (1.9, 0.09, 0.15, 0, 0.02), (1.84, 0.07, 0.11, 0, 0.04), (1.81, 0.03, 0.05, 0, 0.05)], segs=18, power=3.0)
    for ob in (palm, fingers):
        kit.smooth(ob, 1)

    def grooves(v):
        if v.z < 2.08:
            g = sum(bump(v.y, c, 0.012) for c in (-0.085, 0.0, 0.085))
            v.x *= 1 - 0.18 * min(1.0, g)
        return v

    kit.deform(fingers, grooves)
    thumb = kit.tube_along("thumb", [Vector((0.0, 0.1, 2.32)), Vector((0.02 * s, 0.17, 2.22)), Vector((0.03 * s, 0.2, 2.12)), Vector((0.02 * s, 0.19, 2.05))], [0.06, 0.055, 0.045, 0.035], segs=10)
    kit.smooth(thumb, 1)
    ob = kit.join(side + "Hand", [palm, fingers, thumb], shade=False)
    kit.shift(ob, (w.x, w.y, 0))
    return done(ob, "Hand")


# ---------------------------------------------------------------- legs
def upper_leg(side):
    s = -1 if side == "Left" else 1
    x0 = J[side + "Hip"].x
    rings = [  # knee to hip; the quads at the front, a little inward lean toward the knee
        (1.34, 0.19, 0.19, 0.0, 0.02), (1.48, 0.21, 0.21, 0.0, 0.03), (1.76, 0.25, 0.26, 0.0, 0.035),
        (2.06, 0.28, 0.29, 0.0, 0.025), (2.32, 0.3, 0.31, 0.0, 0.01), (2.52, 0.3, 0.3, 0.0, -0.01),
        (2.64, 0.24, 0.24, 0.0, -0.02), (2.7, 0.11, 0.11, 0.0, -0.02),
    ]
    ob = kit.loft(side + "UpperLeg", [(z, rx, ry, -s * cx + x0, cy) for z, rx, ry, cx, cy in rings], segs=24, power=2.2)
    kit.smooth(ob, 2)

    def quads(v):
        x, y, z = v.x, v.y, v.z
        if y > 0:
            y += 0.025 * bump(z, 1.62, 0.1) * bump(x - x0, -s * 0.1, 0.14)  # the teardrop over the knee
        return Vector((x, y, z))

    kit.deform(ob, quads)
    return done(ob, "UpperLeg")


def lower_leg(side):
    s = -1 if side == "Left" else 1
    x0 = J[side + "Knee"].x
    rings = [  # ankle to knee; the calf swells at the back
        (0.28, 0.13, 0.13, 0, 0.0), (0.42, 0.135, 0.14, 0, 0.0), (0.7, 0.17, 0.18, 0, -0.02),
        (0.98, 0.2, 0.22, 0, -0.04), (1.2, 0.2, 0.21, 0, -0.025), (1.4, 0.19, 0.19, 0, 0.0),
        (1.52, 0.16, 0.16, 0, 0.01), (1.56, 0.08, 0.08, 0, 0.01),
    ]
    ob = kit.loft(side + "LowerLeg", [(z, rx, ry, cx + x0, cy) for z, rx, ry, cx, cy in rings], segs=22, power=2.2)
    kit.smooth(ob, 2)
    _ = s
    return done(ob, "LowerLeg")


def foot(side):
    a = J[side + "Ankle"]
    # a shoe that runs front-to-back: lofted along y, then laid down; the heel under the ankle
    f = kit.loft("foot", [(-0.22, 0.12, 0.12, 0, 0.12), (-0.13, 0.145, 0.16, 0, 0.16), (0.08, 0.15, 0.16, 0, 0.14), (0.3, 0.15, 0.11, 0, 0.1), (0.46, 0.13, 0.085, 0, 0.085), (0.55, 0.09, 0.065, 0, 0.075), (0.59, 0.035, 0.035, 0, 0.075)], segs=22, power=2.8)
    kit.smooth(f, 2)
    kit.deform(f, lambda v: Vector((v.x, v.z, v.y)))  # the loft ran along z: make it run along y (toward the front)
    # flatten the sole
    kit.deform(f, lambda v: Vector((v.x, v.y, max(v.z, 0.0))))
    collar = kit.loft("collar", [(0.18, 0.135, 0.135, 0, -0.02), (0.3, 0.13, 0.13, 0, -0.01), (0.38, 0.11, 0.11, 0, 0.0), (0.41, 0.05, 0.05, 0, 0.0)], segs=18, power=2.2)
    kit.smooth(collar, 1)
    ob = kit.join(side + "Foot", [f, collar], shade=False)
    kit.shift(ob, (a.x, a.y, 0))
    return done(ob, "Foot")


upper_torso()
lower_torso()
head()
for side in ("Left", "Right"):
    upper_arm(side)
    lower_arm(side)
    hand(side)
    upper_leg(side)
    lower_leg(side)
    foot(side)


# ---------------------------------------------------------------- the rig: sizes, centres and attachments
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def rbx(v):
    """Blender (x, front, up) to Roblox (x, up, back): Roblox looks down -Z."""
    return (v.x, v.z, -v.y)


# the joints each part carries (standard R15 names; both parts of a joint get the same world point)
RIG = {
    "LowerTorso": ["Root", "Waist", "LeftHip", "RightHip"],
    "UpperTorso": ["Waist", "Neck", "LeftShoulder", "RightShoulder"],
    "Head": ["Neck"],
}
for side in ("Left", "Right"):
    RIG[side + "UpperArm"] = [side + "Shoulder", side + "Elbow"]
    RIG[side + "LowerArm"] = [side + "Elbow", side + "Wrist"]
    RIG[side + "Hand"] = [side + "Wrist"]
    RIG[side + "UpperLeg"] = [side + "Hip", side + "Knee"]
    RIG[side + "LowerLeg"] = [side + "Knee", side + "Ankle"]
    RIG[side + "Foot"] = [side + "Ankle"]


def extra(name, lo, hi, c):
    """Accessory and tool attachments (standard R15 names), world points in Blender space."""
    mid = (lo + hi) / 2
    out = {}
    if name == "Head":
        out["FaceCenterAttachment"] = Vector((0, 0, 5.27))
        out["FaceFrontAttachment"] = Vector((0, hi.y, 5.27))
        out["HairAttachment"] = Vector((0, 0, hi.z))
        out["HatAttachment"] = Vector((0, 0, hi.z))
    elif name == "UpperTorso":
        out["NeckAttachment"] = Vector((0, 0, 4.66))
        out["BodyFrontAttachment"] = Vector((0, hi.y, 3.9))
        out["BodyBackAttachment"] = Vector((0, lo.y, 3.9))
        out["LeftCollarAttachment"] = Vector((-0.45, 0, 4.55))
        out["RightCollarAttachment"] = Vector((0.45, 0, 4.55))
    elif name == "LowerTorso":
        out["WaistCenterAttachment"] = Vector((0, 0, 2.95))
        out["WaistFrontAttachment"] = Vector((0, hi.y, 2.95))
        out["WaistBackAttachment"] = Vector((0, lo.y, 2.95))
    elif name.endswith("UpperArm"):
        out[name[:-8] + "ShoulderAttachment"] = Vector((mid.x, 0, hi.z))
    elif name.endswith("Hand"):
        out[name[:-4] + "GripAttachment"] = Vector((mid.x, mid.y, 2.06))
    elif name.endswith("Foot"):
        out[name[:-4] + "FootAttachment"] = Vector((mid.x, mid.y, lo.z))
    return out


def fmt(t):
    return "{ %.3f, %.3f, %.3f }" % t


def write_rig():
    rows = []
    total = 0
    for name in sorted(parts):
        ob = parts[name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)
        total += kit.tris(ob)
        att = []
        for j in RIG[name]:
            att.append("\t\t\t\t%sRigAttachment = %s," % (j, fmt(rbx(J[j] - c))))
        for k, p in sorted(extra(name, lo, hi, c).items()):
            att.append("\t\t\t\t%s = %s," % (k, fmt(rbx(p - c))))
        rows.append("\t\t%s = {\n\t\t\tsize = %s,\n\t\t\tcentre = %s,\n\t\t\tattachments = {\n%s\n\t\t\t},\n\t\t}," % (name, fmt(size), fmt(rbx(c)), "\n".join(att)))
    rc = ROOT_PART["centre"]
    text = "\n".join([
        "-- GENERATED by art/blender/hero.py: do not edit by hand.",
        "-- The hero body on the standard R15 rig (ReplicatedStorage.Art.Hero). Studs, Roblox axes (x, up, back),",
        "-- feet on y = 0. Each part: its size, its centre, and its attachments from its centre (the R15 rig joints",
        "-- plus the standard accessory and grip points). HeroBody builds the character from this.",
        "return {",
        "\troot = { size = %s, centre = %s, attachments = { RootRigAttachment = %s } }," % (fmt(ROOT_PART["size"]), fmt(rbx(rc)), fmt(rbx(J["Root"] - rc))),
        "\t-- distance from the ground to the bottom of the root part",
        "\thipHeight = %.3f," % (rc.z - ROOT_PART["size"][1] / 2),
        "\ttriangles = %d," % total,
        "\tparts = {",
    ] + rows + ["\t},", "}", ""])
    path = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "HeroRig.luau"))
    with open(path, "w") as f:
        f.write(text)
    print("wrote", path, "triangles", total)


write_rig()
for name, ob in parts.items():
    print("%-14s %5d tris" % (name, kit.tris(ob)))

# the export: each part centred on its own box (the game places parts from HeroRig)
if "--no-export" not in sys.argv:
    export = []
    for name, ob in parts.items():
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.name = name + "_x"
        kit.centre(cp)
        cp.name = name
        cp.data.name = name
        export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Hero.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)


# ---------------------------------------------------------------- preview: standing, posed, and a turnaround
PARENT = {"UpperTorso": ("LowerTorso", "Waist"), "Head": ("UpperTorso", "Neck")}
for _s in ("Left", "Right"):
    PARENT[_s + "UpperArm"] = ("UpperTorso", _s + "Shoulder")
    PARENT[_s + "LowerArm"] = (_s + "UpperArm", _s + "Elbow")
    PARENT[_s + "Hand"] = (_s + "LowerArm", _s + "Wrist")
    PARENT[_s + "UpperLeg"] = ("LowerTorso", _s + "Hip")
    PARENT[_s + "LowerLeg"] = (_s + "UpperLeg", _s + "Knee")
    PARENT[_s + "Foot"] = (_s + "LowerLeg", _s + "Ankle")


def pose_copy(at, bends, mats, skin_parts, yaw=0.0):
    """A copy of the hero at `at` with joints bent like the R15 Motor6Ds would: bends = {joint: (axis, deg)}."""
    from mathutils import Matrix

    world = {}

    def matrix(n):
        if n in world:
            return world[n]
        if n not in PARENT:
            world[n] = Matrix.Identity(4)
            return world[n]
        par, jn = PARENT[n]
        m = matrix(par)
        if jn in bends:
            axis, deg = bends[jn]
            p = J[jn]
            m = m @ Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-p)
        world[n] = m
        return m

    out = []
    Y = Matrix.Rotation(math.radians(yaw), 4, "Z")
    for n, ob in parts.items():
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.matrix_world = Matrix.Translation(Vector(at)) @ Y @ matrix(n)
        cp.data.materials.clear()
        mat = mats["skin"] if n in skin_parts else mats["trim"] if n.endswith("Foot") else mats["suit"]
        cp.data.materials.append(mat)
        cp.hide_render = False
        out.append(cp)
    return out


if "--preview" in sys.argv:
    for ob in parts.values():
        ob.hide_render = True
    kit.studio(res=(1600, 900), samples=48)
    suit = kit.material("suit", (46, 84, 168), rough=0.45)
    trim = kit.material("trim", (240, 196, 70), rough=0.35)
    skin = kit.material("skin", (224, 172, 130), rough=0.6)
    mats = {"suit": suit, "trim": trim, "skin": skin}
    skin_parts = {"Head", "LeftHand", "RightHand"}
    pose_copy((-4.5, 0, 0), {}, mats, skin_parts)
    pose_copy((-1.5, 0, 0), {}, mats, skin_parts, yaw=90)
    pose_copy((1.6, 0, 0), {"LeftShoulder": ("X", 70), "LeftElbow": ("X", 80), "RightShoulder": ("X", -40),
                            "RightElbow": ("X", 20), "LeftHip": ("X", 55), "LeftKnee": ("X", -75), "RightHip": ("X", -20),
                            "RightKnee": ("X", -20), "Neck": ("Z", 15)}, mats, skin_parts)
    pose_copy((4.8, 0, 0), {}, mats, skin_parts, yaw=180)
    floor = kit.cyl("floor", 14, 14, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0.2, 15.0, 4.2), (0.2, 0, 2.9), lens=42)
    kit.render(os.path.join(kit.ROOT, "preview", "hero.png"))
