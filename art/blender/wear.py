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
ROLES = ("p", "s", "a", "dark", "white", "gold", "ice", "glowRed", "skin", "hair")
MATS = ("SmoothPlastic", "Metal", "Fabric", "Leather", "Glass", "Rubber", "Wood", "Foil", "Ice")

FIXED = {"dark": (34, 38, 52), "white": (240, 240, 245), "gold": (255, 210, 70), "ice": (200, 245, 255),
         "glowRed": (255, 80, 40), "skin": (224, 172, 130), "hair": (60, 40, 30)}
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
        obs += [h, face_plane()]
        if show_hair:
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
    `at` (so the cell's centre is the body's z = focus). look_down tilts the camera down (radians)."""
    import subprocess
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
