# sidegear.py: the side styles' own marks (list-combat 2026-11-20, Everything Left 398: "20 side styles
# (reputation gear in side colours) reuse old block gear shapes"). Each of Gizmo's 20 side styles (Config.Gear
# styles with tier "Rep": 10 Vigil, 10 Syndicate) keeps its slot's Blender shape (art/blender/gear.py) and wears
# its side's crest on top, placed for that shape (LookService adds them, all-or-nothing, once Art.SideGear is in):
#   Vigil       a gold heater shield with a glowing four-point lighthouse star in the style's colour
#   Syndicate   a steel crown-topped diamond with two glowing fangs in the style's colour
# Each crest is two meshes (plate, mark) drawn facing one way: F front (Roblox -z), B back (the capes), L and R
# the outer sides of the hands and feet. Placed on gear.py's own built looks on the standard body, so the fit
# rows (offset from the body part's centre, size, in Roblox axes on gear.py's reference boxes) come from the
# same geometry LookService scales.
# Output: art/export/SideGear.fbx, src/config/SideGearArt.luau (generated), art/preview/sidegear.png.
# Run: ~/tools/bpyenv/bin/python art/blender/sidegear.py [--no-export] [--no-preview]
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
EXPORT = "--no-export" not in sys.argv
PREVIEW = "--no-preview" not in sys.argv
# the base looks the side styles use (Config.Gear styles tier "Rep": slot:shape)
BASES = ["head:visor", "head:halo", "head:mask", "head:horns", "chest:vest", "chest:plate", "chest:harness",
         "chest:core", "hands:wraps", "hands:spikes", "feet:boots", "feet:jets", "back:cape", "back:longcape",
         "belt:buckle", "belt:sash"]
sys.argv = [sys.argv[0], "--quick", "--nopreview", "--only", ",".join(BASES)]
import gear  # noqa: E402  (registers gear.py's looks; kit.reset() already ran)
import kit  # noqa: E402
import wear  # noqa: E402
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

# Where each base shape's crest sits: (body part, Roblox offset from the part's centre in studs on the standard
# rig, facing, crest width). Faces: F front, B back, L the -x side, R the +x side.
PLACES = {
    "head:visor": [("head", (0.0, 0.42, -0.63), "F", 0.34)],
    "head:halo": [("head", (0.0, 0.3, -0.63), "F", 0.32)],
    "head:mask": [("head", (0.0, 0.09, -0.69), "F", 0.3)],
    "head:horns": [("head", (0.0, 0.46, -0.72), "F", 0.34)],
    "chest:vest": [("torso", (0.52, 0.52, -0.66), "F", 0.36)],
    "chest:plate": [("torso", (0.0, -0.2, -0.76), "F", 0.42)],
    "chest:harness": [("torso", (0.0, 0.28, -0.66), "F", 0.4)],
    "chest:core": [("torso", (0.0, -0.36, -0.64), "F", 0.36)],
    "hands:wraps": [("lhand", (-0.58, 0.1, 0.0), "L", 0.32), ("rhand", (0.58, 0.1, 0.0), "R", 0.32)],
    "hands:spikes": [("lhand", (-0.67, 0.16, 0.0), "L", 0.34), ("rhand", (0.67, 0.16, 0.0), "R", 0.34)],
    "feet:boots": [("lfoot", (-0.61, 0.14, 0.05), "L", 0.3), ("rfoot", (0.61, 0.14, 0.05), "R", 0.3)],
    "feet:jets": [("lfoot", (-0.62, 0.14, -0.05), "L", 0.3), ("rfoot", (0.62, 0.14, -0.05), "R", 0.3)],
    "back:cape": [("torso", (0.0, -0.35, 1.02), "B", 0.85)],
    "back:longcape": [("torso", (0.0, -0.55, 1.15), "B", 1.05)],
    "belt:buckle": [("waist", (0.0, 0.03, -0.7), "F", 0.32)],
    "belt:sash": [("torso", (0.5, -0.32, -0.6), "F", 0.32)],
}
SIDES = ("vigil", "syndicate")
SIDE_ROLE = {"vigil": "gold", "syndicate": "steel"}
# the 20 side styles (Config.Gear: name, slot:shape, side, colour) for the preview
STYLES = [("Vigil Patrol Visor", "head:visor", "vigil", (90, 170, 255)),
          ("Vigil Halo", "head:halo", "vigil", (255, 230, 150)),
          ("Syndicate Mask", "head:mask", "syndicate", (150, 30, 50)),
          ("Dread Horns", "head:horns", "syndicate", (120, 40, 160)),
          ("Lantern Vest", "chest:vest", "vigil", (70, 120, 220)),
          ("Beacon Plate", "chest:plate", "vigil", (235, 240, 255)),
          ("Foundry Harness", "chest:harness", "syndicate", (60, 40, 50)),
          ("Vault Core", "chest:core", "syndicate", (210, 60, 60)),
          ("Watchman Wraps", "hands:wraps", "vigil", (220, 230, 250)),
          ("Spike Knuckles", "hands:spikes", "syndicate", (90, 20, 40)),
          ("Rooftop Boots", "feet:boots", "vigil", (40, 70, 150)),
          ("Getaway Heels", "feet:jets", "syndicate", (230, 60, 60)),
          ("Safehouse Cape", "back:cape", "vigil", (60, 110, 230)),
          ("Guardian Longcape", "back:longcape", "vigil", (255, 215, 90)),
          ("Smoke Cape", "back:cape", "syndicate", (50, 40, 60)),
          ("Kingpin Longcape", "back:longcape", "syndicate", (170, 20, 40)),
          ("Vigil Buckle", "belt:buckle", "vigil", (90, 160, 255)),
          ("City Sash", "belt:sash", "vigil", (255, 200, 60)),
          ("Dread Buckle", "belt:buckle", "syndicate", (200, 40, 60)),
          ("Syndicate Sash", "belt:sash", "syndicate", (130, 30, 150))]


def slab(name, poly, y0, y1, bevel=0.0):
    """A flat shape facing Blender +y (the hero's front): poly is (x, z) points, extruded from y0 to y1."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    back = [bm.verts.new((x, y0, z)) for x, z in poly]
    front = [bm.verts.new((x, y1, z)) for x, z in poly]
    bm.faces.new(list(reversed(back)))
    bm.faces.new(front)
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([back[i], back[j], front[j], front[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        edges = [e for e in bm.edges if all(abs(v.co.y - y1) < 1e-6 for v in e.verts)]
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for f in ob.data.polygons:
        f.use_smooth = False
    return ob


def star(n, r0, r1, rot=0.0, cx=0.0, cz=0.0):
    pts = []
    for i in range(2 * n):
        a = rot + math.pi * i / n
        r = r0 if i % 2 == 0 else r1
        pts.append((cx + math.sin(a) * r, cz + math.cos(a) * r))
    return pts


def vigil(face_name):
    """Unit crest 1 wide: the gold heater shield (plate) and the lighthouse star (mark), facing +y."""
    side = []  # the right edge from the top corner curving down to the point
    for k in range(1, 13):
        t = k / 12
        x = 0.5 * math.cos(t * math.pi / 2) ** 0.8
        z = 0.5 - 1.15 * t ** 1.6
        side.append((x, z))
    pts = [(-0.5, 0.5), (0.5, 0.5)] + side + [(-x, z) for x, z in reversed(side[:-1])]
    plate = slab("SideVigilPlate" + face_name, pts, -0.08, 0.06, bevel=0.035)
    mark = slab("SideVigilMark" + face_name, star(4, 0.36, 0.09, cz=0.0), 0.05, 0.11)
    return plate, mark


def syndicate(face_name):
    """Unit crest 1 wide: the steel crowned diamond (plate) and the two fangs (mark), facing +y."""
    pts = [(0.0, -0.62), (0.5, -0.02), (0.36, 0.22), (0.42, 0.52), (0.2, 0.32), (0.0, 0.56), (-0.2, 0.32),
           (-0.42, 0.52), (-0.36, 0.22), (-0.5, -0.02)]
    plate = slab("SideSyndicatePlate" + face_name, pts, -0.08, 0.06, bevel=0.03)
    fangs = []
    for sx in (-1, 1):
        fangs.append(slab("fang", [(sx * 0.07, 0.12), (sx * 0.27, 0.12), (sx * 0.15, -0.36)], 0.05, 0.11))
    bpy.ops.object.select_all(action="DESELECT")
    for o in fangs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = fangs[0]
    bpy.ops.object.join()
    mark = fangs[0]
    mark.name = "SideSyndicateMark" + face_name
    mark.data.name = mark.name
    return plate, mark


FACE_YAW = {"F": 0.0, "B": 180.0, "L": 90.0, "R": -90.0}  # Blender z-rotation turning +y (front) to that face


def turned(ob, face):
    ob.data.transform(Matrix.Rotation(math.radians(FACE_YAW[face]), 4, "Z"))
    ob.data.update()
    return ob


# the 16 exported meshes: each side's plate and mark, drawn once a face
SOURCES = {}
for side, fn in (("vigil", vigil), ("syndicate", syndicate)):
    for face in FACE_YAW:
        plate, mark = fn(face)
        SOURCES[(side, face)] = (turned(plate, face), turned(mark, face))


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def crest(side, key):
    """The crest pieces for one base shape on the standard body: [(object copy, part, role)]."""
    out = []
    for at, off, face, width in PLACES[key]:
        centre = Vector(wear.PARTS[at][0]) + Vector((off[0], -off[2], off[1]))
        for src, role in zip(SOURCES[(side, face)], (SIDE_ROLE[side], "glow")):
            o = src.copy()
            o.data = src.data.copy()
            bpy.context.scene.collection.objects.link(o)
            o.matrix_world = Matrix.Translation(centre) @ Matrix.Scale(width, 4)
            o["src"] = src.name
            out.append((o, at, role))
    return out


rows = {}
placed = {}
for key in BASES:
    rows[key] = {}
    for side in SIDES:
        pieces = []
        objs = crest(side, key)
        for o, at, role in objs:
            lo, hi = bounds(o)
            c = (lo + hi) / 2 - Vector(wear.PARTS[at][0])
            size = hi - lo
            pieces.append({"mesh": o["src"], "at": at, "role": role, "offset": wear.rbx(c),
                           "size": (max(size.x, 0.02), max(size.z, 0.02), max(size.y, 0.02))})
        rows[key][side] = pieces
        placed[(key, side)] = objs

tris = {name: kit.tris(o) for pair in SOURCES.values() for o in pair for name in [o.name]}
total = sum(tris.values())


def v(t):
    return "{ %.3f, %.3f, %.3f }" % tuple(t)


lines = ["-- GENERATED by art/blender/sidegear.py: do not edit by hand.",
         "-- The side styles' crests (ReplicatedStorage.Art.SideGear; LookService adds them over a side style's slot",
         "-- shape, Config.Gear styles with tier \"Rep\"): per base look \"slot:shape\" and side, each piece's mesh, the",
         "-- body part it is welded to (a LookService ATTACH role), its colour role (gold, steel; glow: Neon in the",
         "-- style's colour) and its box against that body part in Roblox axes (x right, y up, z back), in studs on",
         "-- the reference boxes of Config.GearArt.ref. %d meshes, %d triangles." % (len(tris), total),
         "return {",
         "\tmeshes = {"]
for name in sorted(tris):
    lines.append("\t\t%s = %d," % (name, tris[name]))
lines.append("\t},")
lines.append("\tlooks = {")
for key in BASES:
    lines.append('\t\t["%s"] = {' % key)
    for side in SIDES:
        lines.append("\t\t\t%s = {" % side)
        for p in rows[key][side]:
            lines.append('\t\t\t\t{ mesh = "%s", at = "%s", role = "%s", offset = %s, size = %s },'
                         % (p["mesh"], p["at"], p["role"], v(p["offset"]), v(p["size"])))
        lines.append("\t\t\t},")
    lines.append("\t\t},")
lines += ["\t},", "}", ""]
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "SideGearArt.luau"))
with open(FIT, "w") as f:
    f.write("\n".join(lines))
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)
print("sidegear: %d meshes, %d tris" % (len(tris), total))

if EXPORT:
    export = []
    for pair in SOURCES.values():
        for o in pair:
            target = o.name
            o.name = target + "_src"
            o.data.name = target + "_src"
            cp = o.copy()
            cp.data = o.data.copy()
            bpy.context.scene.collection.objects.link(cp)
            kit.centre(cp)
            cp.name = target
            cp.data.name = target
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "SideGear.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if PREVIEW:
    rows_, built = gear.build_all()
    wear.hide_sources(built)  # the base looks' own objects stand at the origin; each cell places copies
    for pair in SOURCES.values():
        for o in pair:
            o.hide_render = True
    for objs in placed.values():
        for o, _, _ in objs:
            o.hide_render = True
    names = [s[0] for s in STYLES]
    by_name = {s[0]: s for s in STYLES}
    COL = {"gold": (255, 200, 60), "steel": (175, 180, 192)}

    def dress(name, at, yaw, pal):
        _, key, side, trim = by_name[name]
        wear.body(at, yaw, suit=(150, 156, 170), show_hair=gear.LOOKS[key][2])
        gear.place(built[key], at, yaw, trim, None)
        Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        for o, _, role in placed[(key, side)]:
            c = o.copy()
            c.data = o.data.copy()
            bpy.context.scene.collection.objects.link(c)
            c.data.materials.clear()
            if role == "glow":
                c.data.materials.append(kit.material("g%s" % name, trim, emit=2.0))
            else:
                c.data.materials.append(kit.material(role, COL[role], metal=0.8, rough=0.3))
            c.matrix_world = Y @ c.matrix_world
            c.hide_render = False
    fake = {n: [] for n in names}
    wear.grid_preview(fake, os.path.join(kit.ROOT, "preview", "sidegear.png"), dress, cols=5, cell=6.0, px=300,
                      focus=2.85, yaw_front=150, yaw_back=25, samples=24)
