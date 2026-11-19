# fit.py: the fit check (pt-fit, nate's playtest 2026-11-19: "a lot of weapons and just customization things aren't
# modeled properly or aren't on the player properly"). Renders every creator mesh piece, every gear look and every
# weapon on Roblox's OWN blocky R15 body (the 15 real meshes, fetched by art/fit/robloxbody.py into build/robloxbody)
# at each body scale the creator offers (one today: Config.Creator.bodyStep is off, every hero is the standard
# body), placed exactly as the game places them: build/fit/fits.json from art/fit/dump.luau, which runs the game's
# own placement (Shared.BodyFit, the call LookKit, WeaponKit and LookService make) and also writes the old placement
# ("before"). Weapons are posed by HeroAnim's ready stance and one action moment on Roblox's own joints. Hats and
# open masks wear a Roblox catalog hair (build/catalog, art/panels/catalog.py) so hiding and clipping show; a piece
# that hides the hair (HeadArt hair = false, PieceKits.hatHidesHair) shows the bare head, as the game does.
# Sheets: art/preview/fit_<set>.png (after) and fit_<set>_before.png; each cell a kit seen from the front, the
# hero's right side and the back (weapons: ready front and side, action front and side, and the grip close up).
# Solid Workbench shading, so a full run takes a few minutes. Run from the repo root:
#   flock /tmp/capeline-lune.lock ~/tools/lune run art/fit/dump.luau
#   nice $HOME/tools/bpyenv/bin/python art/blender/fit.py [set ...|all|weapons] [--before] [--px 200]
import json
import math
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

REPO = os.path.normpath(os.path.join(kit.ROOT, ".."))
BUILD = os.path.join(REPO, "build")
OUT = os.path.join(kit.ROOT, "preview")
ARGS = [a for a in sys.argv[1:] if not a.startswith("--") and not a.isdigit()]
BEFORE = "--before" in sys.argv
PX = int(sys.argv[sys.argv.index("--px") + 1]) if "--px" in sys.argv else 200
FITS = json.load(open(os.path.join(BUILD, "fit", "fits.json")))
RIG = FITS["rig"]
# Roblox (x right, y up, z back) to Blender (x right, y front, z up)
MRB = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
MBR = MRB.inverted()

# which hats hide the catalog hair (Shared.PieceKits hatHidesHair, read from the source)
_pk = open(os.path.join(REPO, "src", "shared", "PieceKits.luau"), encoding="utf-8").read()
HAT_HIDES = {}
_m = re.search(r"local hatHidesHair = \{([^}]*)\}", _pk)
for k, v in re.findall(r"(\w+) = (true|false)", _m.group(1)):
    HAT_HIDES[k] = v == "true"
for k, v in re.findall(r"hatHidesHair\.(\w+) = (true|false)", _pk):
    HAT_HIDES[k] = v == "true"
# the head kits whose part-built look hides the hair (LookKit HIDES_HAIR, PieceKits.maskHidesHair): a head mesh
# says it itself (fit hair = false)

# per set: the cell's focus (Roblox x, y: the right hand for gloves, the right shoulder for shoulder pads), the
# window's size in studs and whether a catalog hair is worn under it
FRAME = {
    "heads": ((0, 4.45), 2.2, True), "hats": ((0, 4.65), 2.5, True), "ears": ((0, 4.45), 2.0, True),
    "necks": ((0, 4.05), 2.4, True), "capes": ((0, 2.6), 5.4, True), "coats": ((0, 2.6), 5.4, True),
    "backs": ((0, 3.1), 4.4, True), "gloves": ((1.5, 2.3), 1.8, False), "wrists": ((-1.5, 2.2), 1.4, False),
    "arms": ((1.5, 3.0), 2.6, False), "boots": ((0.5, 0.55), 1.8, False), "belts": ((0, 2.15), 3.0, False),
    "shoulders": ((-1.25, 3.75), 2.4, False), "gear": ((0, 2.7), 6.0, True),
}
# the side view: the hero's right (90) or, for sets whose one-sided pieces go on the left, the left (-90)
SIDE = {"shoulders": -90, "wrists": -90}
# full-body sets get bigger tiles
TILE = {"capes": 1.6, "coats": 1.6, "gear": 1.5, "backs": 1.3}
SKIN = (232, 186, 145)
SUIT = (140, 150, 172)
LEGS = (96, 104, 124)
ROLE = {"p": (220, 64, 64), "s": (245, 200, 60), "a": (70, 225, 255), "dark": (36, 40, 54), "white": (245, 245, 248),
        "gold": (255, 196, 50), "ice": (190, 240, 255), "glowRed": (255, 80, 40), "trim": (220, 70, 70),
        "glow": (70, 225, 255), "steel": (175, 180, 192), "skin": SKIN, "hair": (70, 45, 30)}
WROLE = {"p": (200, 205, 215), "s": (150, 70, 40), "a": (70, 225, 255), "white": (245, 245, 248),
         "dark": (36, 40, 54)}


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(rgb):
    return (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)


# ------------------------------------------------------------------ the scene
kit.reset()
sc = bpy.context.scene
sc.render.engine = "CYCLES"  # Workbench and EEVEE need a GPU; Cycles on the CPU, few samples, denoised
sc.cycles.device = "CPU"
sc.cycles.samples = 4
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 2
sc.view_settings.view_transform = "Standard"
_world = bpy.data.worlds.new("W")
_world.use_nodes = True
_world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.13, 0.14, 0.18, 1)
_world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
sc.world = _world
for _nm, _rot, _e in (("Key", (0.9, 0.2, 2.6), 3.0), ("Fill", (1.1, 0, -0.4), 1.3), ("Back", (1.2, 0, 1.3), 1.2)):
    _L = bpy.data.lights.new(_nm, "SUN")
    _L.energy = _e
    _ob = bpy.data.objects.new(_nm, _L)
    _ob.rotation_euler = _rot
    sc.collection.objects.link(_ob)
# one material: the base colour from each object's own colour (Object Info)
MAT = bpy.data.materials.new("ObjColour")
MAT.use_nodes = True
_nt = MAT.node_tree
_bsdf = _nt.nodes["Principled BSDF"]
_bsdf.inputs["Roughness"].default_value = 0.55
_info = _nt.nodes.new("ShaderNodeObjectInfo")
_nt.links.new(_info.outputs["Color"], _bsdf.inputs["Base Color"])


def mesh_object(name, verts, faces, rgb, parent):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    for poly in me.polygons:
        poly.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    ob.color = rgba(rgb)
    me.materials.append(MAT)
    ob.parent = parent
    return ob


# Roblox's body meshes, in each part's own frame (Roblox axes, about its centre)
BODY = {}
for name in RIG:
    d = json.load(open(os.path.join(BUILD, "robloxbody", name + ".json")))
    BODY[name] = ([tuple(p) for p in d["pos"]], [tuple(f) for f in d["faces"]])

# the piece meshes, from each set's exported FBX, in Roblox axes about their own box centre, with that box
PIECE = {}


def load_fbx(fbx):
    path = os.path.join(kit.ROOT, "export", fbx + ".fbx")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, axis_forward="-Z", axis_up="Y")
    new = [o for o in bpy.data.objects if o not in before]
    dg = bpy.context.evaluated_depsgraph_get()
    for o in new:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        vs = [MBR @ (o.matrix_world @ v.co) for v in me.vertices]
        fs = [tuple(p.vertices) for p in me.polygons]
        ev.to_mesh_clear()
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        c = (lo + hi) / 2
        nm = re.sub(r"\.\d+$", "", o.name)
        PIECE[nm] = ([v - c for v in vs], fs, hi - lo)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)


# ------------------------------------------------------------------ the rig and poses (Roblox's own joints)
JOINTS = [("Waist", "LowerTorso", "UpperTorso"), ("Neck", "UpperTorso", "Head"),
          ("LeftShoulder", "UpperTorso", "LeftUpperArm"), ("LeftElbow", "LeftUpperArm", "LeftLowerArm"),
          ("LeftWrist", "LeftLowerArm", "LeftHand"), ("RightShoulder", "UpperTorso", "RightUpperArm"),
          ("RightElbow", "RightUpperArm", "RightLowerArm"), ("RightWrist", "RightLowerArm", "RightHand"),
          ("LeftHip", "LowerTorso", "LeftUpperLeg"), ("LeftKnee", "LeftUpperLeg", "LeftLowerLeg"),
          ("LeftAnkle", "LeftLowerLeg", "LeftFoot"), ("RightHip", "LowerTorso", "RightUpperLeg"),
          ("RightKnee", "RightUpperLeg", "RightLowerLeg"), ("RightAnkle", "RightLowerLeg", "RightFoot")]


def T(v):
    return Matrix.Translation(Vector(v))


def angles(a):
    """Roblox CFrame.Angles(rx, ry, rz) in Roblox axes, from HeroAnim's degrees."""
    r = [math.radians(x) for x in a]
    return Matrix.Rotation(r[0], 4, "X") @ Matrix.Rotation(r[1], 4, "Y") @ Matrix.Rotation(r[2], 4, "Z")


def pose_world(pose):
    """Each part's CFrame (Roblox axes) for a pose {joint: (rx, ry, rz)}, as Motor6D: Part0 * C0 * Transform *
    C1:Inverse(), the C0 and C1 the two parts' rig attachments."""
    W = {"LowerTorso": T(RIG["LowerTorso"]["centre"])}
    for j, p0, p1 in JOINTS:
        a0 = RIG[p0]["attachments"][j + "RigAttachment"]
        a1 = RIG[p1]["attachments"][j + "RigAttachment"]
        R = angles(pose[j]) if pose and j in pose else Matrix.Identity(4)
        W[p1] = W[p0] @ T(a0) @ R @ T(a1).inverted()
    return W


# ------------------------------------------------------------------ catalog hair (as Roblox fits it)
CAT = os.path.join(BUILD, "catalog", "hair")
HAIR = None


def cframe(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


def load_hair():
    """A full catalog hair (the first of the game's list that loaded), in the head's frame (Roblox axes)."""
    idx_path = os.path.join(CAT, "index.json")
    if not os.path.exists(idx_path):
        return None
    idx = json.load(open(idx_path))
    src = open(os.path.join(REPO, "src", "config", "CatalogLooks.luau"), encoding="utf-8").read()
    hair_src = src.split("hair = {")[1].split("beards = {")[0]
    ids = [a for _, a in re.findall(r'\{ "([^"]+)", (\d+) \}', hair_src)]
    for aid in ids:
        e = idx.get(aid)
        if not e:
            continue
        fit = e["fit"]
        mesh = json.load(open(os.path.join(CAT, e["mesh"])))
        att = fit.get("attachment")
        head_att = Vector(RIG["Head"]["attachments"]["HairAttachment"])
        handle = T(head_att) @ (cframe(att["cframe"]).inverted() if att else Matrix.Identity(4))
        s = Vector(fit.get("scale") or (1, 1, 1))
        off = Vector(fit.get("offset") or (0, 0, 0))
        vs = [handle @ (off + Vector((p[0] * s.x, p[1] * s.y, p[2] * s.z))) for p in mesh["pos"]]
        return (vs, [tuple(f) for f in mesh["faces"]], aid)
    return None


# ------------------------------------------------------------------ one figure in a cell
# A cell is a list of meshes in Roblox world coordinates. Each view turns the cell about its focus, cuts it to the
# view's window (so cells sit edge to edge and no neighbour reaches in) and lays it in its place on the grid.
import bmesh  # noqa: E402


def figure(items, W, hair=None):
    for name, (vs, fs) in BODY.items():
        col = SKIN if name in ("Head", "LeftHand", "RightHand") else (
            LEGS if "Leg" in name or "Foot" in name or name == "LowerTorso" else SUIT)
        items.append(([W[name] @ Vector(v) for v in vs], fs, col))
    # a face mark (two eyes and a mouth), so front and back read at a glance
    Mh = W["Head"]
    for x, y, w, h in ((-0.2, 0.1, 0.1, 0.16), (0.2, 0.1, 0.1, 0.16), (0, -0.2, 0.34, 0.05)):
        z = -0.601
        q = [(x - w / 2, y - h / 2, z), (x + w / 2, y - h / 2, z), (x + w / 2, y + h / 2, z), (x - w / 2, y + h / 2, z)]
        items.append(([Mh @ Vector(p) for p in q], [(0, 1, 2, 3)], (25, 25, 30)))
    if hair:
        items.append(([Mh @ v for v in hair[0]], hair[1], ROLE["hair"]))


def piece(items, W, row, colours, which):
    src = PIECE.get(row["mesh"])
    if not src:
        print("fit.py: no mesh", row["mesh"])
        return
    if (row.get("alpha") or 0) >= 0.9:
        return
    vs, fs, native = src
    off, size = row[which]
    k = Vector((size[0] / max(native.x, 1e-6), size[1] / max(native.y, 1e-6), size[2] / max(native.z, 1e-6)))
    M = W[row["part"]] @ T(off)
    role = "glow" if row.get("glow") else row.get("role", "p")
    col = colours.get(role) or colours.get(row.get("role")) or (200, 60, 200)
    items.append(([M @ Vector((v.x * k.x, v.y * k.y, v.z * k.z)) for v in vs], fs, col))


def lay(items, home, yaw, focus, win):
    """The cell's meshes for one view: turned yaw degrees about the focus (Roblox), cut to a win-stud window."""
    R = Matrix.Rotation(math.radians(yaw), 4, "Z")
    M = T(home) @ R @ T(-(MRB @ Vector(focus))) @ MRB
    h = win / 2
    for vs, fs, col in items:
        pts = [M @ v for v in vs]
        if (max(p.x for p in pts) < home.x - h or min(p.x for p in pts) > home.x + h
                or max(p.z for p in pts) < home.z - h or min(p.z for p in pts) > home.z + h):
            continue
        me = bpy.data.meshes.new("m")
        me.from_pydata([tuple(p) for p in pts], [], fs)
        bm = bmesh.new()
        bm.from_mesh(me)
        for co, no in (((home.x + h, 0, 0), (1, 0, 0)), ((home.x - h, 0, 0), (-1, 0, 0)),
                       ((0, 0, home.z + h), (0, 0, 1)), ((0, 0, home.z - h), (0, 0, -1))):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
        if not bm.faces:
            bm.free()
            bpy.data.meshes.remove(me)
            continue
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = True
        me.materials.append(MAT)
        ob = bpy.data.objects.new("o", me)
        sc.collection.objects.link(ob)
        ob.color = rgba(col)


def camera(width, height):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(width, height)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    sc.camera = cam
    return cam


def clear():
    for o in list(bpy.data.objects):
        if o.type != "LIGHT":
            bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def render_grid(cells, cols, views, path_of):
    """cells: [items]; views: [(yaw, focus_of(i), win)]; one render per view, each cell a win x win window, PX
    pixels across. Returns the passes for sheet.py."""
    rows = (len(cells) + cols - 1) // cols
    passes = []
    for vi, (yaw, focus_of, win) in enumerate(views):
        gap = win * 1.0
        for i, items in enumerate(cells):
            r, c = i // cols, i % cols
            lay(items, Vector((-c * gap, 0, -r * gap)), yaw, focus_of(i), win)
        sc.render.resolution_x = cols * PX
        sc.render.resolution_y = rows * PX
        cam = camera(cols * gap, rows * gap)
        cam.location = (-(cols - 1) * gap / 2, 60, -(rows - 1) * gap / 2)
        p = path_of(vi)
        kit.render(p)
        clear()
        bx = [[(i % cols) * PX, (i // cols) * PX, (i % cols + 1) * PX, (i // cols + 1) * PX] for i in range(len(cells))]
        passes.append({"path": p, "boxes": bx})
    return passes


def write_sheet(path, names, passes):
    spec = os.path.join(BUILD, "fit", "_spec%d.json" % os.getpid())
    json.dump({"out": path, "tile": PX, "names": names, "passes": passes}, open(spec, "w"))
    subprocess.run(["python3", "-I", os.path.join(REPO, "art", "fit", "sheet.py"), spec], check=True)


def pass_path(vi):
    return os.path.join(BUILD, "fit", "_pass%d_%d.png" % (os.getpid(), vi))


# ------------------------------------------------------------------ creator sets and gear
def set_sheet(s):
    global PX
    px0 = PX
    PX = int(px0 * TILE.get(s["name"], 1))
    which = "before" if BEFORE else "after"
    load_fbx(s["fbx"])
    (fx, focus_y), win, hairy = FRAME[s["name"]]
    kits = s["kits"]
    if os.environ.get("FIT_ONLY"):
        kits = [k for k in kits if k["key"] in os.environ["FIT_ONLY"].split(",")]
    if os.environ.get("FIT_WIN"):
        win = float(os.environ["FIT_WIN"])
    cols = 6 if len(kits) > 24 else 5
    W = pose_world(None)
    cells = []
    for k in kits:
        items = []
        hides = (not k["hair"]) or (s["name"] == "hats" and HAT_HIDES.get(k["key"], False))
        figure(items, W, HAIR if (hairy and not hides) else None)
        for row in k["pieces"]:
            piece(items, W, row, ROLE, which)
        cells.append(items)
    f = (fx, focus_y, 0)
    views = [(0, lambda i: f, win), (SIDE.get(s["name"], 90), lambda i: f, win), (180, lambda i: f, win)]
    passes = render_grid(cells, cols, views, pass_path)
    suffix = "_before" if BEFORE else ""
    write_sheet(os.path.join(OUT, "fit_%s%s.png" % (s["name"], suffix)), [k["key"] for k in kits], passes)
    PIECE.clear()
    PX = px0


# ------------------------------------------------------------------ weapons
def weapon_sheet(ws, tag):
    which = "before" if BEFORE else "after"
    cols = 3
    cells = {"hold": [], "action": []}
    grips = []
    for kind in ("hold", "action"):
        for w in ws:
            pose = FITS["poses"].get(w[kind]) if w[kind] else None
            W = pose_world(pose)
            items = []
            figure(items, W, None)
            for row in w["pieces"]:
                piece(items, W, row, WROLE, which)
            cells[kind].append(items)
            if kind == "hold":
                g = w["grip"]
                grips.append(W[g["part"]] @ Vector(g[which]))
            g2 = w.get("grip2")
            if g2:
                # where the left hand should close (a small magenta ball) and how far its grip is from it
                at = W[g2["part"]] @ Vector(g2["pos"])
                lh = W["LeftHand"] @ Vector(RIG["LeftHand"]["attachments"]["LeftGripAttachment"])
                print("fit.py: %d %s %s: left hand %.2f studs from its grip2" % (w["id"], w["name"], kind,
                                                                                (lh - at).length))
                items.append(([at + Vector((math.cos(a) * 0.09 * math.cos(b), math.sin(b) * 0.09,
                                            math.sin(a) * 0.09 * math.cos(b)))
                               for b in (-1.2, -0.6, 0, 0.6, 1.2) for a in [k * math.pi / 4 for k in range(8)]],
                              [(r * 8 + k, r * 8 + (k + 1) % 8, (r + 1) * 8 + (k + 1) % 8, (r + 1) * 8 + k)
                               for r in range(4) for k in range(8)], (255, 0, 220)))
    body = (0, 2.9, 0)
    passes = []
    # ready stance front-right and side, action front-right and side (6.5 studs), the grip close up (1.4 studs)
    for group, yaw, win in (("hold", 30, 6.5), ("hold", 90, 6.5), ("action", 30, 6.5), ("action", 90, 6.5),
                            ("hold", 50, 1.4)):
        focus = (lambda i: tuple(grips[i])) if win < 2 else (lambda i: body)
        passes += render_grid(cells[group], cols, [(yaw, focus, win)], lambda vi: pass_path(len(passes)))
    suffix = "_before" if BEFORE else ""
    write_sheet(os.path.join(OUT, "fit_weapons%s%s.png" % (tag, suffix)),
                ["%d %s" % (w["id"], w["name"]) for w in ws], passes)


HAIR = load_hair()
print("fit.py: catalog hair", HAIR[2] if HAIR else "none (run art/panels/catalog.py)")
want = set(ARGS) if ARGS and "all" not in ARGS else None
for s in FITS["sets"]:
    if want is None or s["name"] in want:
        set_sheet(s)
        print("fit.py: wrote", s["name"])
if want is None or "weapons" in want:
    load_fbx("Weapons")
    ws = FITS["weapons"]
    weapon_sheet(ws[:18], "_1")
    weapon_sheet(ws[18:], "_2")
    print("fit.py: wrote weapons")
