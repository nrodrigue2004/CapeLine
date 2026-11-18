# hero.py: the hero base body on the standard Roblox R15 rig, in the classic blocky Roblox look (nate,
# 2026-11-16: "All humanoid models should follow that basic r15 roblox model" ... "r15 is right but i want the
# blocky version like r6"). 15 parts named exactly as R15 (Head, UpperTorso, LowerTorso, Left/Right UpperArm,
# LowerArm, Hand, UpperLeg, LowerLeg, Foot) in the classic block proportions: a 2 x 2 x 1 torso (upper and
# lower), arms and legs 1 x 2 x 1 cut in three, and the classic rounded head. Edges are softly bevelled.
# Output: art/export/Hero.fbx (import with Studio's 3D Importer, save as art/models/Hero.rbxm),
# src/config/HeroRig.luau (each part's size and centre, every R15 rig and accessory attachment, the root
# part and hip height; HeroBody builds the character from it) and art/preview/hero.png.
# Run: python art/blender/hero.py --preview   (with the `bpy` module, Blender 5.0)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import template_uv  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()

# ---------------------------------------------------------------- the skeleton (Blender: z up, front +y,
# the hero's left is -x like Roblox). Feet on z = 0; the classic 5.2 studs with the head.
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
for k in list(J):
    if k.startswith("Left"):
        v = J[k]
        J["Right" + k[4:]] = Vector((-v.x, v.y, v.z))

ROOT_PART = {"size": (2.0, 2.0, 1.0), "centre": Vector((0, 0, 3.0))}  # the HumanoidRootPart (Roblox x, up, depth)

BEVEL = 0.07  # the soft edge on every block

parts = {}


def done(ob):
    kit.apply_all(ob)
    kit.shade_auto(ob, 35)
    parts[ob.name] = ob
    return ob


def block(name, x0, x1, z0, z1, y0=-0.5, y1=0.5, bevel=BEVEL):
    """A softly bevelled box between the given bounds (Blender: x across, y front, z up)."""
    ob = kit.box(name, x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = bevel
    m.segments = 3
    m.limit_method = "NONE"
    kit.apply_all(ob)
    template_uv.apply(ob, name)  # classic Shirt and Pants need the template UVs (template_uv.py)
    return done(ob)


def head():
    # the classic head: a rounded cylinder, a little square from above, with soft top and bottom rims
    rings = []
    for z, r in ((4.02, 0.36), (4.04, 0.46), (4.08, 0.53), (4.15, 0.58), (4.25, 0.6), (4.97, 0.6), (5.07, 0.58),
                 (5.14, 0.53), (5.18, 0.46), (5.2, 0.36)):
        rings.append((z, r, r, 0, 0))
    ob = kit.loft("Head", rings, segs=40, power=2.25)
    kit.smooth(ob, 1)
    return done(ob)


head()
block("UpperTorso", -1.0, 1.0, 2.4, 4.0)
block("LowerTorso", -1.0, 1.0, 2.0, 2.4)
for side in ("Left", "Right"):
    x0, x1 = (-2.0, -1.0) if side == "Left" else (1.0, 2.0)
    block(side + "UpperArm", x0, x1, 3.15, 4.0)
    block(side + "LowerArm", x0, x1, 2.3, 3.15)
    block(side + "Hand", x0, x1, 2.0, 2.3)
    lx0, lx1 = (-1.0, 0.0) if side == "Left" else (0.0, 1.0)
    block(side + "UpperLeg", lx0, lx1, 1.15, 2.0)
    block(side + "LowerLeg", lx0, lx1, 0.3, 1.15)
    block(side + "Foot", lx0, lx1, 0.0, 0.3)


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
        out["FaceCenterAttachment"] = mid.copy()
        out["FaceFrontAttachment"] = Vector((0, hi.y, mid.z))
        out["HairAttachment"] = Vector((0, 0, hi.z))
        out["HatAttachment"] = Vector((0, 0, hi.z))
    elif name == "UpperTorso":
        out["NeckAttachment"] = Vector((0, 0, hi.z))
        out["BodyFrontAttachment"] = Vector((0, hi.y, mid.z))
        out["BodyBackAttachment"] = Vector((0, lo.y, mid.z))
        out["LeftCollarAttachment"] = Vector((lo.x, 0, hi.z))
        out["RightCollarAttachment"] = Vector((hi.x, 0, hi.z))
    elif name == "LowerTorso":
        out["WaistCenterAttachment"] = mid.copy()
        out["WaistFrontAttachment"] = Vector((0, hi.y, mid.z))
        out["WaistBackAttachment"] = Vector((0, lo.y, mid.z))
    elif name.endswith("UpperArm"):
        out[name[:-8] + "ShoulderAttachment"] = Vector((mid.x, mid.y, hi.z))
    elif name.endswith("Hand"):
        out[name[:-4] + "GripAttachment"] = Vector((mid.x, mid.y, mid.z - 0.15 * (hi.z - lo.z)))
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
    pose_copy((7.8, 0, 0), {}, mats, skin_parts)
    pose_copy((2.6, 0, 0), {}, mats, skin_parts, yaw=90)
    pose_copy((-2.6, 0, 0), {"LeftShoulder": ("X", 70), "LeftElbow": ("X", 80), "RightShoulder": ("X", -40),
                            "RightElbow": ("X", 20), "LeftHip": ("X", 55), "LeftKnee": ("X", -75), "RightHip": ("X", -20),
                            "RightKnee": ("X", -20), "Neck": ("Z", 15)}, mats, skin_parts)
    pose_copy((-7.8, 0, 0), {}, mats, skin_parts, yaw=180)
    floor = kit.cyl("floor", 14, 14, 0.2, at=(0, 0, -0.1), segs=48)
    floor.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    kit.camera((0, 24.0, 5.0), (0, 0, 2.7), lens=42)
    kit.render(os.path.join(kit.ROOT, "preview", "hero.png"))
