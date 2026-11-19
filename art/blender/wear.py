# wear.py: shared helpers for the hero creator's worn meshes (2026-11-18, creator art round 2): heads.py (the
# helmets, the visor and the 3D masks), hands.py (gloves and wraps), feet.py (boots and shoes) and coats.py (coats
# and scarves). Each script builds its pieces on the standard blocky R15 body (kit.py conventions: Blender +Y is
# the hero's front, Roblox -Z; the hero's left is -x; feet on z = 0) and calls write_fit, which writes the fit
# table LookKit reads (src/config/<Name>Art.luau): every kit's pieces with the body part each is welded to (a
# LookKit ATTACH role), its colour role, glow, material, transparency, and its box against that body part's centre
# in Roblox axes (x right, y up, z back), in studs on the standard rig (LookKit scales it with the part).
# One colour per mesh (the game sets MeshPart.Color from the role), so colour regions are separate meshes; a
# left and right pair is two meshes (a MeshPart cannot be mirrored), the right made by mirroring the left.
# preview_body draws the blocky body with the Hero face for the previews.
import math
import os

import kit
import bpy  # noqa: F401
from mathutils import Matrix, Vector

# body part centres (Blender coordinates) and sizes (x across, y depth, z up) on the standard rig
PARTS = {
    "head": ((0.0, 0.0, 4.61), (1.194, 1.194, 1.277)),
    "torso": ((0.0, 0.0, 3.2), (2.0, 1.0, 1.6)),
    "waist": ((0.0, 0.0, 2.2), (2.0, 1.0, 0.4)),
    "lhand": ((-1.5, 0.0, 2.15), (1.0, 1.0, 0.3)),
    "rhand": ((1.5, 0.0, 2.15), (1.0, 1.0, 0.3)),
    "llarm": ((-1.5, 0.0, 2.725), (1.0, 1.0, 0.85)),
    "rlarm": ((1.5, 0.0, 2.725), (1.0, 1.0, 0.85)),
    "luarm": ((-1.5, 0.0, 3.575), (1.0, 1.0, 0.85)),
    "ruarm": ((1.5, 0.0, 3.575), (1.0, 1.0, 0.85)),
    "lfoot": ((-0.5, 0.0, 0.15), (1.0, 1.0, 0.3)),
    "rfoot": ((0.5, 0.0, 0.15), (1.0, 1.0, 0.3)),
    "lshin": ((-0.5, 0.0, 0.725), (1.0, 1.0, 0.85)),
    "rshin": ((0.5, 0.0, 0.725), (1.0, 1.0, 0.85)),
    "lthigh": ((-0.5, 0.0, 1.575), (1.0, 1.0, 0.85)),
    "rthigh": ((0.5, 0.0, 1.575), (1.0, 1.0, 0.85)),
}
MIRROR = {"lhand": "rhand", "llarm": "rlarm", "luarm": "ruarm", "lfoot": "rfoot", "lshin": "rshin",
          "lthigh": "rthigh"}
ROLES = ("p", "s", "a", "dark", "white", "gold", "ice", "glowRed", "skin", "hair", "eye1", "eye2")
MATS = ("SmoothPlastic", "Metal", "Fabric", "Leather", "Glass", "Rubber", "Wood", "Foil", "Ice")

FIXED = {"dark": (34, 38, 52), "white": (240, 240, 245), "gold": (255, 210, 70), "ice": (200, 245, 255),
         "glowRed": (255, 80, 40), "skin": (224, 172, 130), "hair": (60, 40, 30), "eye1": (80, 255, 255),
         "eye2": (255, 90, 200)}
# bright sample slot colours (main, trim, accent) for the previews
SAMPLES = [((40, 110, 220), (235, 60, 60), (255, 210, 60)), ((235, 60, 60), (255, 210, 60), (245, 245, 245)),
           ((120, 80, 220), (245, 245, 245), (80, 255, 255)), ((40, 150, 80), (250, 240, 150), (255, 210, 60)),
           ((30, 45, 120), (175, 180, 190), (110, 210, 255)), ((150, 40, 110), (255, 200, 40), (255, 60, 140)),
           ((250, 150, 30), (40, 40, 48), (120, 255, 120)), ((20, 160, 170), (245, 245, 245), (255, 90, 60))]


class Piece:
    """One mesh of a kit: the object, the body part role it is welded to, its colour role and look."""

    def __init__(self, ob, at, role, glow=False, mat=None, alpha=0.0):
        assert at in PARTS, at
        assert role in ROLES, role
        assert mat is None or mat in MATS, mat
        self.ob, self.at, self.role, self.glow, self.mat, self.alpha = ob, at, role, glow, mat, alpha


def solid(ob, thick=0.04, offset=1.0):
    m = ob.modifiers.new("S", "SOLIDIFY")
    m.thickness = thick
    m.offset = offset
    kit.apply_all(ob)
    return fix_normals(ob)


def bake(ob):
    """Move an object's location, rotation and scale into its vertices (the fit reads the mesh itself)."""
    m = ob.matrix_basis.copy()
    if m != Matrix.Identity(4):
        ob.data.transform(m)
        if m.determinant() < 0:
            ob.data.flip_normals()
        ob.matrix_basis = Matrix.Identity(4)
    return ob


def turn(ob, euler, pivot):
    """Rotate a mesh's vertices by euler (x, y, z radians) about pivot."""
    from mathutils import Euler
    R = Euler(euler).to_matrix().to_4x4()
    P = Vector(pivot)
    ob.data.transform(Matrix.Translation(P) @ R @ Matrix.Translation(-P))
    return ob


def fix_normals(ob):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def name_all(prefix, pieces):
    """Give every piece its final mesh name prefix_<Name> (the object's current name is the short name)."""
    seen = set()
    for p in pieces:
        n = "%s_%s" % (prefix, p.ob.name.split(".")[0])
        assert n not in seen, n
        seen.add(n)
        p.ob.name = n
        p.ob.data.name = n
    return pieces


def pair(ob, at, role, glow=False, mat=None, alpha=0.0, short=None):
    """A left piece (built on the left body part) and its mirror on the right."""
    short = short or ob.name.split(".")[0]
    ob.name = short + "L"
    kit.apply_all(ob)
    r = kit.mirror_x(ob, short + "R")
    return [Piece(ob, at, role, glow, mat, alpha), Piece(r, MIRROR[at], role, glow, mat, alpha)]


def bounds(ob):
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def rbx(v):
    """Blender (x, y front, z up) to Roblox (X right, Y up, Z back)."""
    return (v.x, v.z, -v.y)


def fit_rows(styles, budget):
    """Build every kit (styles: kit -> fn returning [Piece]); returns rows for write_fit and kit -> pieces."""
    rows, built = {}, {}
    for name, fn in styles.items():
        pieces = fn()
        for p in pieces:
            kit.apply_all(p.ob)
            bake(p.ob)
        total = sum(kit.tris(p.ob) for p in pieces)
        assert total <= budget, "%s: %d triangles" % (name, total)
        out = []
        for p in pieces:
            lo, hi = bounds(p.ob)
            c = (lo + hi) / 2 - Vector(PARTS[p.at][0])
            size = hi - lo
            out.append({"mesh": p.ob.name, "at": p.at, "role": p.role, "glow": p.glow, "mat": p.mat,
                        "alpha": p.alpha, "offset": [round(x, 3) for x in rbx(c)],
                        "size": [round(max(size.x, 0.02), 3), round(max(size.z, 0.02), 3),
                                 round(max(size.y, 0.02), 3)]})
        rows[name] = {"triangles": total, "pieces": out}
        built[name] = pieces
        print(name, total, "triangles", len(pieces), "pieces")
    return rows, built


def write_fit(module, header, rows):
    def v(t):
        return "{ %s }" % ", ".join("%.3f" % x for x in t)

    def key(k):
        return k if k.replace("_", "").isalnum() and not k[0].isdigit() and ":" not in k else '["%s"]' % k

    lines = ["-- GENERATED by art/blender/%s: do not edit by hand." % header[0]] + ["-- " + h for h in header[1:]]
    lines.append("return {")
    for name in rows:
        r = rows[name]
        lines.append("\t%s = {" % key(name))
        lines.append("\t\ttriangles = %d," % r["triangles"])
        for fk, fv in sorted(r.get("flags", {}).items()):
            lines.append("\t\t%s = %s," % (fk, "true" if fv is True else ("false" if fv is False else repr(fv))))
        lines.append("\t\tpieces = {")
        for p in r["pieces"]:
            extra = ""
            if p["mat"]:
                extra += ', mat = "%s"' % p["mat"]
            if p["alpha"]:
                extra += ", alpha = %.2f" % p["alpha"]
            lines.append('\t\t\t{ mesh = "%s", at = "%s", role = "%s", glow = %s%s, offset = %s, size = %s },' % (
                p["mesh"], p["at"], p["role"], "true" if p["glow"] else "false", extra, v(p["offset"]),
                v(p["size"])))
        lines.append("\t\t},")
        lines.append("\t},")
    lines += ["}", ""]
    path = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", module + ".luau"))
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote", path)


# ---------------------------------------------------------------- previews
BLOCKS = {
    "UpperTorso": (-1.0, 1.0, -0.5, 0.5, 2.4, 4.0), "LowerTorso": (-1.0, 1.0, -0.5, 0.5, 2.0, 2.4),
    "LeftUpperArm": (-2.0, -1.0, -0.5, 0.5, 3.15, 4.0), "LeftLowerArm": (-2.0, -1.0, -0.5, 0.5, 2.3, 3.15),
    "LeftHand": (-2.0, -1.0, -0.5, 0.5, 2.0, 2.3), "LeftUpperLeg": (-1.0, 0.0, -0.5, 0.5, 1.15, 2.0),
    "LeftLowerLeg": (-1.0, 0.0, -0.5, 0.5, 0.3, 1.15), "LeftFoot": (-1.0, 0.0, -0.5, 0.5, 0.0, 0.3),
}
for _k in list(BLOCKS):
    if _k.startswith("Left"):
        x0, x1, y0, y1, z0, z1 = BLOCKS[_k]
        BLOCKS["Right" + _k[4:]] = (-x1, -x0, y0, y1, z0, z1)
FACE = os.path.join(kit.ROOT, "export", "clothes", "faces", "Face_Hero.png")


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def srgb(c):
    return tuple(lin(v) * 255 for v in c)


def mat(rgb, glow=False, rough=0.5, metal=0.0, alpha=0.0):
    m = kit.material("m%d" % len(bpy.data.materials), srgb(rgb), rough=rough, metal=metal,
                     emit=2.2 if glow else 0.0)
    if alpha > 0:
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Alpha"].default_value = 1 - alpha
    return m


def head_mesh():
    rings = []
    for z, r in ((4.02, 0.36), (4.04, 0.46), (4.08, 0.53), (4.15, 0.58), (4.25, 0.6), (4.97, 0.6), (5.07, 0.58),
                 (5.14, 0.53), (5.18, 0.46), (5.2, 0.36)):
        rings.append((z, r, r, 0, 0))
    ob = kit.loft("Head", rings, segs=40, power=2.25)
    kit.shade_auto(ob, 60)
    return ob


def face_plane():
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0.603, 4.6), rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.active_object
    m = bpy.data.materials.new("face%d" % len(bpy.data.materials))
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(FACE, check_existing=True)
    img.alpha_mode = "STRAIGHT"
    t.image = img
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], p.inputs["Alpha"])
    ob.data.materials.append(m)
    return ob


def hair_mesh():
    rings = []
    for z, r, cy in ((4.7, 0.63, 0.0), (4.9, 0.65, -0.02), (5.08, 0.64, -0.04), (5.22, 0.58, -0.06),
                     (5.32, 0.46, -0.08), (5.38, 0.3, -0.1)):
        rings.append((z, r, r, 0, cy))
    ob = kit.loft("Hair", rings, segs=24, power=2.4)
    for v in ob.data.vertices:
        if v.co.y > 0.25 and v.co.z < 5.0:
            v.co.z = 5.0 + (v.co.z - 4.7) * 0.3
    kit.shade_auto(ob, 40)
    return ob


def body(at, yaw, suit=(70, 74, 88), skin=(224, 172, 130), hair=(50, 36, 30), show_hair=True, parts=None,
         paint=None, pivot=(0, 0, 0)):
    """The blocky body at `at`, turned `yaw` degrees about z (at 0 its front faces +y).
    parts: only these BLOCKS (None: all). paint: {part name: rgb} over the suit colour."""
    Y = (Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
         @ Matrix.Translation(-Vector(pivot)))
    obs = []
    for name, (x0, x1, y0, y1, z0, z1) in BLOCKS.items():
        if parts is not None and name not in parts:
            continue
        ob = kit.box(name, x1 - x0, y1 - y0, z1 - z0, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        kit.bevel(ob, 0.03, 1)
        c = (paint or {}).get(name, skin if "Hand" in name else suit)
        ob.data.materials.append(mat(c, rough=0.6))
        obs.append(ob)
    if parts is None or "Head" in parts:
        h = head_mesh()
        h.data.materials.append(mat(skin, rough=0.55))
        obs.append(h)
        # the creator thumbnails show a plain head: faces and hair come only from the Roblox catalog (nate's rule),
        # so a tile never shows a drawn face or hair as if it came with the piece
        thumbs = bool(os.environ.get("THUMBS"))
        if not thumbs:
            obs.append(face_plane())
        if show_hair and not thumbs:
            hr = hair_mesh()
            hr.data.materials.append(mat(hair, rough=0.6))
            obs.append(hr)
    for ob in obs:
        ob.matrix_world = Y @ ob.matrix_world
    return obs


def colour(role, pal):
    if role in ("p", "s", "a"):
        return pal["psa".index(role)]
    return FIXED[role]


def place(pieces, at, yaw, pal, pivot=(0, 0, 0)):
    """Copies of a kit's pieces on a body at `at`, turned `yaw`, in the slot colours pal (main, trim, accent)."""
    Y = (Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
         @ Matrix.Translation(-Vector(pivot)))
    for p in pieces:
        c = p.ob.copy()
        c.data = p.ob.data.copy()
        bpy.context.scene.collection.objects.link(c)
        c.data.materials.clear()
        metal = 0.3 if p.mat == "Metal" else 0.0
        rough = 0.3 if p.mat in ("Metal", "Glass") else (0.75 if p.mat in ("Fabric", "Leather") else 0.5)
        c.data.materials.append(mat(colour(p.role, pal), glow=p.glow, rough=rough, metal=metal, alpha=p.alpha))
        c.matrix_world = Y @ c.matrix_world
        c.hide_render = False
        c["thumb_piece"] = True  # thumb_cells frames these (the body around them is context)


def hide_sources(built):
    for pieces in built.values():
        for p in pieces:
            p.ob.hide_render = True


def floor(at=(0, 0, -0.1), r=60):
    f = kit.cyl("floor", r, r, 0.2, at=at, segs=48)
    f.data.materials.append(kit.material("floor", (60, 64, 72), rough=0.8))
    return f


def grid_preview(built, out, dress, cols=5, cell=2.8, px=320, focus=4.65, yaw_front=150, yaw_back=30,
                 samples=32, look_down=0.0):
    """Every kit in its own grid cell from the front three-quarter and from behind (two orthographic renders,
    paired and named by sheet.py into `out`). dress(name, at, yaw, pal) puts the body and the kit's pieces at
    `at` (so the cell's centre is the body's z = focus). look_down tilts the camera down (radians).
    With THUMBS=1 in the environment it renders the creator thumbnails instead (thumb_cells, from the front view)."""
    import subprocess
    if os.environ.get("THUMBS"):
        thumb_cells(built, os.path.splitext(os.path.basename(out))[0].replace("_test", ""), dress, yaw_front,
                    look_down)
        return
    hide_sources(built)
    names = list(built)
    rows = (len(names) + cols - 1) // cols
    tmp = []
    for view, yaw in (("front", yaw_front), ("back", yaw_back)):
        for o in list(bpy.context.scene.objects):
            if o.get("preview"):
                bpy.data.objects.remove(o, do_unlink=True)
        before = set(bpy.context.scene.objects)
        for i, name in enumerate(names):
            r, c = i // cols, i % cols
            # rows stack upward in the picture: on a tilted camera, along the camera's up
            up = Vector((0, math.sin(look_down), math.cos(look_down))) * (-(r - (rows - 1) / 2) * cell)
            at = Vector(((c - (cols - 1) / 2) * cell, 0.0, 0.0)) + up
            dress(name, (at.x, at.y, at.z - focus), yaw, SAMPLES[i % len(SAMPLES)])
        for o in set(bpy.context.scene.objects) - before:
            o["preview"] = True
        if view == "front":
            kit.studio(res=(cols * px, rows * px), samples=samples)
            bpy.context.scene.view_settings.view_transform = "Standard"
            d = 40.0
            cam = kit.camera((0, -d * math.cos(look_down), d * math.sin(look_down)), (0, 0, 0), lens=50)
            cam.data.type = "ORTHO"
            cam.data.ortho_scale = cols * cell
        path = out[:-4] + "_%s.png" % view
        kit.render(path)
        tmp.append(path)
    here = os.path.dirname(os.path.abspath(__file__))
    subprocess.run(["python3", os.path.join(here, "sheet.py"), out, tmp[0], tmp[1], str(cols), str(px),
                    ",".join(names)], check=True)
    for p in tmp:
        os.remove(p)


# ---------------------------------------------------------------- creator thumbnails (2026-11-19)
# The creator's picture tiles (art/thumbs/thumbs.py packs them): every kit rendered alone on a transparent
# background, the orthographic camera framed on the kit's own pieces (the body around them is context, cut by the
# frame), in one bright sample palette so every tile reads as the same hero. Cells land in
# art/thumbs/cells/<set>/<kit>.png (kit ":" written "~"). THUMB_PX and THUMB_SAMPLES tune the render.
THUMB_PAL = ((40, 110, 220), (235, 60, 60), (255, 210, 60))
# per set: (minimum frame in studs, zoom out factor, an extra tilt down in radians)
THUMB_FRAME = {"poses": (3.0, 1.2, 0.0), "heads": (1.5, 1.12, 0.0), "hats": (1.5, 1.1, 0.1), "ears": (0.8, 1.7, 0.0),
               "gloves": (1.2, 1.15, -0.18), "boots": (1.2, 1.15, -0.06), "necks": (1.5, 1.3, 0.0),
               "wrists": (1.1, 1.3, 0.0), "arms": (1.9, 1.15, 0.0), "belts": (2.0, 1.15, 0.0),
               "shoulders": (2.4, 1.1, 0.0), "backs": (2.6, 1.08, 0.0), "coats": (3.0, 1.06, 0.0),
               "capes": (3.0, 1.06, 0.0), "suits": (5.0, 1.06, 0.0), "shirts": (3.0, 1.08, 0.0),
               "pants": (2.6, 1.08, 0.0), "masks": (1.4, 1.12, 0.0), "legs": (2.6, 1.08, 0.0)}


THUMB_ONE_SIDE = {"wrists", "arms", "ears"}


def thumb_centre_x(o):
    vs = [(o.matrix_world @ v.co).x for v in o.data.vertices]
    return sum(vs) / max(1, len(vs))


def thumb_path(set_name, name):
    return os.path.join(kit.ROOT, "thumbs", "cells", set_name, name.replace(":", "~") + ".png")


def thumb_setup(px):
    s = bpy.context.scene
    if any(o.type == "LIGHT" for o in s.objects):
        return  # set up already (a script that clears its lights between sets gets them back here)
    kit.studio(res=(px, px), samples=int(os.environ.get("THUMB_SAMPLES", "16")))
    s.view_settings.view_transform = "Standard"
    s.render.film_transparent = True
    # a front fill so the side facing the camera never goes muddy on the small tile
    L = bpy.data.lights.new("ThumbFill", "SUN")
    L.energy = 1.6
    ob = bpy.data.objects.new("ThumbFill", L)
    ob.rotation_euler = (math.radians(70), 0, math.radians(-15))
    s.collection.objects.link(ob)


def thumb_frame(objs, look_down, set_name):
    """An orthographic camera looking along +y (tilted down by look_down) framed on objs' world vertices."""
    mn, zoom, tilt = THUMB_FRAME.get(set_name, (1.5, 1.15, 0.0))
    ld = look_down + tilt
    fwd = Vector((0, math.cos(ld), -math.sin(ld)))
    right = Vector((1, 0, 0))
    up = right.cross(fwd).normalized() * -1
    if up.z < 0:
        up = -up
    xs, ys, pts = [], [], []
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            pts.append(w)
            xs.append(w.dot(right))
            ys.append(w.dot(up))
    if not pts:
        return None
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    size = max(max(xs) - min(xs), max(ys) - min(ys), mn) * zoom
    depth = sum((p.dot(fwd) for p in pts)) / len(pts)
    centre = right * cx + up * cy + fwd * depth
    cam = bpy.context.scene.camera
    if cam is None or cam.name != "ThumbCam":
        cam = bpy.data.objects.new("ThumbCam", bpy.data.cameras.new("ThumbCam"))
        bpy.context.scene.collection.objects.link(cam)
        cam.data.type = "ORTHO"
        bpy.context.scene.camera = cam
    cam.data.ortho_scale = size
    cam.data.clip_end = 200
    cam.location = centre - fwd * 40
    cam.rotation_euler = fwd.to_track_quat("-Z", "Y").to_euler()
    return cam


def thumb_cells(names, set_name, dress, yaw, look_down=0.0):
    """Render each kit alone: dress(name, at, yaw, pal) as grid_preview's, framed on the pieces it placed."""
    px = int(os.environ.get("THUMB_PX", "224"))
    if isinstance(names, dict):
        hide_sources(names)
        names = list(names)
    thumb_setup(px)
    only = os.environ.get("THUMB_ONLY")
    for name in names:
        if only and name not in only.split(","):
            continue
        for o in list(bpy.context.scene.objects):
            if o.get("preview"):
                bpy.data.objects.remove(o, do_unlink=True)
        before = set(bpy.context.scene.objects)
        dress(name, (0.0, 0.0, 0.0), yaw, THUMB_PAL)
        new = [o for o in bpy.context.scene.objects if o not in before]
        for o in new:
            o["preview"] = True
        pieces = [o for o in new if o.get("thumb_piece")] or new
        if set_name in THUMB_ONE_SIDE:
            # a pair (both wrists, both arms): frame the one on the picture's right, close up
            right = [o for o in pieces if o.type == "MESH" and thumb_centre_x(o) > 0.05]
            pieces = right or pieces
        if set_name == "coats" and name.startswith("scarf"):
            # a scarf's tails hang behind: show it from the back three-quarter
            for o in new:
                bpy.data.objects.remove(o, do_unlink=True)
            dress(name, (0.0, 0.0, 0.0), 35, THUMB_PAL)
            new = [o for o in bpy.context.scene.objects if o not in before]
            for o in new:
                o["preview"] = True
            pieces = [o for o in new if o.get("thumb_piece")] or new
        if thumb_frame(pieces, look_down, set_name) is None:
            print("thumb: nothing to frame for", set_name, name)
            continue
        kit.render(thumb_path(set_name, name))
    for o in list(bpy.context.scene.objects):
        if o.get("preview"):
            bpy.data.objects.remove(o, do_unlink=True)


# ---------------------------------------------------------------- round 3 shapes (2026-11-18)
# Shared by belts.py, shoulders.py, backs.py and hats.py: rings round a vertical axis (belts, pads, hat crowns),
# rounded boxes, balls, rods, flat outlines and strips, each one a plain mesh ready for a Piece.
PI = math.pi


def spt(a, rx, ry, power):
    """A point on a superellipse at angle a (0 the front, +y; positive a turns toward +x)."""
    s, c = math.sin(a), math.cos(a)
    return (rx * math.copysign(abs(s) ** (2 / power), s), ry * math.copysign(abs(c) ** (2 / power), c))


def ring(name, rows, power=10.0, na=40, cx=0.0, cy=0.0, a0=-PI, a1=PI, hole=None, wave=None, thick=0.04,
         angle=50):
    """A surface round the vertical axis through (cx, cy): rows [(z, rx, ry)] bottom to top (a radius of 0 closes
    a dome). a0..a1 the angles it spans (a full turn closes the seam); hole(a, z) leaves a face out; wave(a, z)
    adds radius. Solidified `thick` about the surface (0: one sheet, faces pointing away from the axis)."""
    import bmesh
    full = a1 - a0 >= 2 * PI - 1e-6
    ncol = na if full else na + 1
    bm = bmesh.new()
    grid = []
    for z, rx, ry in rows:
        row = []
        for i in range(ncol):
            a = a0 + (a1 - a0) * i / na
            w = wave(a, z) if (wave and max(rx, ry) > 1e-4) else 0.0
            x, y = spt(a, rx + w, ry + w, power)
            row.append(bm.verts.new((cx + x, cy + y, z)))
        grid.append(row)
    for j in range(len(rows) - 1):
        for i in range(na):
            i2 = (i + 1) % ncol
            am = a0 + (a1 - a0) * (i + 0.5) / na
            zm = (rows[j][0] + rows[j + 1][0]) / 2
            if hole and hole(am, zm):
                continue
            q = [grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]]
            if len(set(q)) == 4:
                bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = kit._obj(name, bm)
    if thick > 0:
        solid(ob, thick, 0.0)
    else:
        me = ob.data
        s = sum(p.normal.dot(Vector((p.center.x - cx, p.center.y - cy, 0))) for p in me.polygons)
        if s < 0:
            me.flip_normals()
    kit.shade_auto(ob, angle)
    return ob


def dome_rows(z0, z1, rx, ry, top=None, n=6, base=None):
    """Rows for `ring`: straight from z0 to z1 at (rx, ry), then a rounded dome closing at `top`."""
    top = top if top is not None else z1 + min(rx, ry) * 0.6
    out = [(z0, rx, ry)] if base is None else [(z0, base[0], base[1])]
    out.append((z1, rx, ry))
    for k in range(1, n + 1):
        t = k / n * PI / 2
        f = math.cos(t) if k < n else 0.0
        out.append((z1 + (top - z1) * math.sin(t), rx * f, ry * f))
    return out


def rbox(name, sx, sy, sz, at=(0, 0, 0), bev=0.03, segs=2):
    ob = kit.box(name, sx, sy, sz, at=at)
    if bev > 0:
        m = ob.modifiers.new("B", "BEVEL")
        m.width = min(bev, min(sx, sy, sz) * 0.45)
        m.segments = segs
        kit.apply_all(ob)
    kit.shade_auto(ob, 40)
    return ob


def ball(name, r, at, scale=(1, 1, 1), segs=14, rings=8):
    ob = kit.sphere(name, r, at=at, scale=scale, segs=segs, rings=rings)
    kit.shade_auto(ob, 80)
    return ob


def rod(name, pts, radii, segs=8, angle=60):
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * len(pts)
    ob = kit.tube_along(name, [Vector(p) for p in pts], list(radii), segs=segs)
    kit.shade_auto(ob, angle)
    return ob


def cone(name, r1, r2, h, at, segs=8, axis=(0, 0, 1)):
    """A cone (or a frustum) from `at` along `axis` (a direction), base radius r1, tip r2."""
    ob = kit.cyl(name, r1, r2, h, at=(0, 0, h / 2), segs=segs)
    d = Vector(axis).normalized()
    q = Vector((0, 0, 1)).rotation_difference(d)
    ob.data.transform(Matrix.Translation(Vector(at)) @ q.to_matrix().to_4x4())
    kit.shade_auto(ob, 40)
    return ob


def joined(name, obs, angle=50):
    for o in obs:
        kit.apply_all(o)
        bake(o)
    ob = kit.join(name, obs, shade=False)
    kit.shade_auto(ob, angle)
    return ob


def outline(name, pts, depth, at=(0, 0, 0), axis="Y", bev=0.0):
    """A flat outline pts [(u, v)] extruded `depth` thick, centred at `at`: across Y (u = x, v = z), X (u = y,
    v = z) or Z (u = x, v = y)."""
    import bmesh
    bm = bmesh.new()
    vs = []
    for u, v in pts:
        if axis == "Y":
            vs.append(bm.verts.new((at[0] + u, at[1], at[2] + v)))
        elif axis == "X":
            vs.append(bm.verts.new((at[0], at[1] + u, at[2] + v)))
        else:
            vs.append(bm.verts.new((at[0] + u, at[1] + v, at[2])))
    bm.faces.new(vs)
    if len(vs) > 4:
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    ob = kit._obj(name, bm)
    solid(ob, depth, 0.0)
    if bev:
        m = ob.modifiers.new("B", "BEVEL")
        m.width = bev
        m.segments = 1
        m.limit_method = "ANGLE"
        kit.apply_all(ob)
    kit.shade_auto(ob, 35)
    return ob


def strip(name, pts, widths, up=(0, 0, 1), thick=0.035, angle=60):
    """A flat strip through pts (a ribbon, a strap, a flag), widths across it, lying across `up` x the run."""
    import bmesh
    bm = bmesh.new()
    rows = []
    for k, p in enumerate(pts):
        p = Vector(p)
        d = (Vector(pts[min(k + 1, len(pts) - 1)]) - Vector(pts[max(k - 1, 0)])).normalized()
        u = Vector(up(k) if callable(up) else up)
        side = u - d * d.dot(u)
        side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        w = (widths[k] if isinstance(widths, (list, tuple)) else widths) / 2
        rows.append((bm.verts.new(p - side * w), bm.verts.new(p + side * w)))
    for k in range(len(rows) - 1):
        a, b = rows[k], rows[k + 1]
        bm.faces.new([a[0], a[1], b[1], b[0]])
    ob = kit._obj(name, bm)
    solid(ob, thick, 0.0)
    kit.shade_auto(ob, angle)
    return ob


def loop_path(rx, ry, z, n, power=10.0, cx=0.0, cy=0.0, a0=-PI, a1=PI):
    """n points round a superellipse, evenly spaced along it (a path for rods, studs and chains). A high power
    bunches the angle steps at the corners, so the curve is walked finely and resampled by length."""
    full = a1 - a0 >= 2 * PI - 1e-6
    dense = []
    m = 2000
    for i in range(m + 1):
        x, y = spt(a0 + (a1 - a0) * i / m, rx, ry, power)
        dense.append((cx + x, cy + y))
    lens = [0.0]
    for i in range(1, len(dense)):
        lens.append(lens[-1] + math.dist(dense[i], dense[i - 1]))
    total = lens[-1]
    out, j = [], 0
    for k in range(n):
        t = total * k / (n if full else n - 1)
        while j < len(lens) - 2 and lens[j + 1] < t:
            j += 1
        f = (t - lens[j]) / max(lens[j + 1] - lens[j], 1e-9)
        x = dense[j][0] + (dense[j + 1][0] - dense[j][0]) * f
        y = dense[j][1] + (dense[j + 1][1] - dense[j][1]) * f
        out.append((x, y, z))
    return out


def gear(name, r, teeth, depth, at, axis="Y", hole=0.0, tooth=0.12):
    """A flat gear: `teeth` square teeth round a disc of radius r, `depth` thick, facing along axis."""
    pts = []
    for k in range(teeth * 4):
        a = 2 * PI * k / (teeth * 4)
        rr = r + (tooth if (k % 4) in (1, 2) else 0.0)
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    return outline(name, pts, depth, at=at, axis=axis)


def star_pts(r1, r2, n=5, rot=PI / 2):
    out = []
    for k in range(n * 2):
        a = rot + PI * k / n
        r = r1 if k % 2 == 0 else r2
        out.append((r * math.cos(a), r * math.sin(a)))
    return out


def rrect_pts(w, h, r, n=4):
    """A rounded rectangle outline, w x h, corner radius r."""
    out = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, PI / 2), (-w / 2 + r, -h / 2 + r, PI),
                       (w / 2 - r, -h / 2 + r, 1.5 * PI)):
        for k in range(n + 1):
            a = a0 + PI / 2 * k / n
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out

