# lorebooks.py: the sculpted lore book and the HQ Lore Shelf (living-world, 2026-11-19; nate: "Too many simple
# shapes"). Shared.LoreBookKit lays the book and the shelf out as pieces (size and pose each); this draws one Blender
# mesh per piece role, each filling its piece's own box, so the device (Fx.LoreBooks) puts the mesh where the part
# was: the cloth cover board with a raised frame and a star emboss, the bowed page block with its page edges, the
# gold corner caps, the ribbed round spine and its beaded bands, the scalloped clasp rosette, the ribbon and its
# swallowtail, the faceted Spark star and its spikes; the shelf's panelled back, scrolled sides and bullnose boards,
# the closed books (round ribbed spine, page block) and their gold straps. Lines and the halo stay parts.
# Output: art/export/LoreBook.fbx (meshes named LoreBookKit.MESHES); --preview renders art/preview/lorebooks.png
# from `lune run art/lore/book.luau`'s piece list (the same layout the device builds).
# Run: lune run art/lore/book.luau && ~/tools/bpyenv/bin/python art/blender/lorebooks.py [--preview]
# Blender axes: x = Roblox x, y = Roblox -z (the front a piece faces), z = Roblox up.
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()
MESH = {}  # name -> (object, (Rx, Ry, Rz) the piece box it was drawn for)


def fit(ob, dims):
    """Centre the mesh on its bounds and scale it to exactly dims (Blender x, y, z)."""
    kit.apply_all(ob)
    vs = ob.data.vertices
    lo = [min(v.co[i] for v in vs) for i in range(3)]
    hi = [max(v.co[i] for v in vs) for i in range(3)]
    for v in vs:
        for i in range(3):
            c = (lo[i] + hi[i]) / 2
            span = max(hi[i] - lo[i], 1e-6)
            v.co[i] = (v.co[i] - c) / span * dims[i]
    return ob


def keep(name, parts, rbx, shade=True, flat=False):
    """Join parts into the role mesh drawn for the Roblox piece box rbx = (x, y, z)."""
    ob = kit.join(name, parts, shade=shade and not flat) if len(parts) > 1 else parts[0]
    kit.apply_all(ob)
    ob.name = name
    ob.data.name = name
    fit(ob, (rbx[0], rbx[2], rbx[1]))
    if flat:
        for p in ob.data.polygons:
            p.use_smooth = False
    elif len(parts) == 1 and shade:
        kit.shade_auto(ob)
    MESH[name] = (ob, rbx)
    return ob


def prism(name, outline, depth, axis="X"):
    """An outline (list of (a, b)) extruded `depth` along axis; X: outline in (y, z); Z: outline in (x, y)."""
    bm = bmesh.new()

    def at(a, b, d):
        return (d, a, b) if axis == "X" else ((a, d, b) if axis == "Y" else (a, b, d))

    front = [bm.verts.new(at(a, b, -depth / 2)) for a, b in outline]
    back = [bm.verts.new(at(a, b, depth / 2)) for a, b in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._obj(name, bm)


def subdivided_box(name, sx, sy, sz, cuts=8, at=(0, 0, 0)):
    ob = kit.box(name, sx, sy, sz, at=at)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=cuts, use_grid_fill=True)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def arc(cx, cy, r, a0, a1, n):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def rounded_rect(w, h, r, n=5):
    pts = []
    for cx, cy, a in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180),
                      (w / 2 - r, -h / 2 + r, 270)):
        pts += arc(cx, cy, r, math.radians(a), math.radians(a + 90), n)
    return pts


def star_outline(ro, ri, n=5, turn=90):
    pts = []
    for k in range(2 * n):
        r = ro if k % 2 == 0 else ri
        a = math.radians(turn + 180 * k / n)
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def lathe_x(name, profile, segs=20):
    """A solid of revolution about x from profile [(x, r)] (capped ends)."""
    bm = bmesh.new()
    rings = []
    for x, r in profile:
        rings.append([bm.verts.new((x, r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs)))
                      for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._obj(name, bm)


# ======================================================================== the open book (LoreBookKit.book)
# the cover board: a cloth board, a raised frame and a star emboss on its outside (+z, Blender -y), a rounded edge
W, H = 1.55, 2.16
board = kit.bevel(kit.box("board", W, 0.08, H, at=(0, 0.02, 0)), 0.025, 2)
frame = []
for x, z, sx, sz in ((0, H / 2 - 0.12, W - 0.2, 0.06), (0, -H / 2 + 0.12, W - 0.2, 0.06),
                     (W / 2 - 0.12, 0, 0.06, H - 0.2), (-W / 2 + 0.12, 0, 0.06, H - 0.2)):
    frame.append(kit.bevel(kit.box("rail", sx, 0.03, sz, at=(x, -0.035, z)), 0.012, 1))
emboss = prism("emboss", [(a * 1.0, b * 1.0) for a, b in star_outline(0.34, 0.15)], 0.03, axis="Y")
kit.shift(emboss, (0, -0.035, 0.05))
keep("LoreCover", [board] + frame + [emboss], (1.55, 2.16, 0.12))

# the page block: its face bows toward the reader, its three free edges show the stacked pages
pw, ph = 1.31, 1.8
pages = subdivided_box("pages", pw, 0.2, ph, cuts=10)


def bow(co):
    u, v = co.x / (pw / 2), co.z / (ph / 2)
    if co.y > 0:
        co.y += 0.06 * max(0.0, 1 - 0.55 * u * u - 0.25 * v * v)
    # page edges: little grooves across the block's thickness on the free sides
    edge = abs(abs(co.x) - pw / 2) < 1e-3 or abs(abs(co.z) - ph / 2) < 1e-3
    if edge and abs(co.y) < 0.099:
        k = 0.012 * (0.5 + 0.5 * math.cos(co.y * 140))
        if abs(abs(co.x) - pw / 2) < 1e-3:
            co.x -= math.copysign(k, co.x)
        else:
            co.z -= math.copysign(k, co.z)
    return co


kit.deform(pages, bow)
keep("LorePages", [pages], (1.31, 1.8, 0.26))

# a gold corner cap: a rounded boss wrapping the board's corner, a rivet dome each side
cap = kit.bevel(kit.box("cap", 0.26, 0.12, 0.26), 0.025, 2)
riv = [kit.sphere("rivet", 0.05, at=(0, s * 0.06, 0), scale=(1, 0.5, 1), segs=10, rings=6) for s in (-1, 1)]
keep("LoreCorner", [cap] + riv, (0.26, 0.26, 0.16))

# the round spine along x: a cloth roll with four raised ribs
prof = []
for i in range(41):
    x = -1.02 + 2.04 * i / 40
    r = 0.135
    for rx in (-0.62, -0.2, 0.2, 0.62):
        r += 0.015 * math.exp(-((x - rx) / 0.035) ** 2)
    r *= 1 - 0.12 * (abs(x) / 1.02) ** 8  # rounded ends
    prof.append((x, r))
keep("LoreSpine", [lathe_x("spine", prof, segs=20)], (2.04, 0.3, 0.3))

# a beaded gold band round the spine (along x)
band_prof = [(-0.04, 0.14), (-0.03, 0.165), (0, 0.17), (0.03, 0.165), (0.04, 0.14)]
bead = lathe_x("band", band_prof, segs=24)
beads = [kit.sphere("bead", 0.022, at=(0, 0.168 * math.cos(a), 0.168 * math.sin(a)), segs=8, rings=5)
         for a in [2 * math.pi * k / 14 for k in range(14)]]
keep("LoreBand", [bead] + beads, (0.08, 0.34, 0.34))

# the clasp: a scalloped rosette disc (axis along x) with a gem dome on each face
ros = []
for k in range(48):
    a = 2 * math.pi * k / 48
    r = 0.19 + 0.02 * math.cos(a * 12)
    ros.append((r * math.cos(a), r * math.sin(a)))
disc = prism("disc", ros, 0.05, axis="X")
gems = [kit.sphere("gem", 0.1, at=(s * 0.025, 0, 0), scale=(0.5, 1, 1), segs=12, rings=8) for s in (-1, 1)]
ring = kit.torus("ring", 0.13, 0.015, segs=24, csegs=6, axis="X")
keep("LoreClasp", [disc, ring] + gems, (0.1, 0.42, 0.42))

# the ribbon: a thin strip that ripples a little as it hangs
rib = subdivided_box("ribbon", 0.12, 0.008, 0.9, cuts=12)
kit.deform(rib, lambda co: Vector((co.x, co.y + 0.005 * math.sin(co.z * 9) + 0.003 * math.sin(co.x * 30), co.z)))
keep("LoreRibbon", [rib], (0.12, 0.9, 0.02))
# its swallowtail end (the piece box: thin x, 0.18 tall, 0.12 across z)
tail = prism("tail", [(-0.06, 0.09), (0.06, 0.09), (0.06, -0.09), (0.0, -0.035), (-0.06, -0.09)], 0.02, axis="X")
keep("LoreRibbonTip", [tail], (0.02, 0.18, 0.12))

# the Spark star: five points, faceted, a ridge down each point to its front and back tips
bm = bmesh.new()
out = [bm.verts.new((a, 0, b)) for a, b in star_outline(0.5, 0.22)]
f, b2 = bm.verts.new((0, 0.42, 0)), bm.verts.new((0, -0.42, 0))
for i in range(len(out)):
    j = (i + 1) % len(out)
    bm.faces.new((out[i], out[j], f))
    bm.faces.new((out[j], out[i], b2))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
keep("LoreStar", [kit._obj("star", bm)], (0.42, 0.42, 0.42), flat=True)

# a spark spike along x: a long four-sided diamond, thin at both ends
bm = bmesh.new()
tips = [bm.verts.new((-0.45, 0, 0)), bm.verts.new((0.45, 0, 0))]
mid = [bm.verts.new((0, 0.06 * math.cos(a), 0.06 * math.sin(a))) for a in [math.pi / 2 * k for k in range(4)]]
for i in range(4):
    j = (i + 1) % 4
    bm.faces.new((mid[i], mid[j], tips[1]))
    bm.faces.new((mid[j], mid[i], tips[0]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
keep("LoreSpark", [kit._obj("spark", bm)], (0.9, 0.12, 0.12), flat=True)

# ======================================================================== the Lore Shelf (LoreBookKit.shelf)
SW, SH = 6.4, 5.2
back = kit.box("backboard", SW, 0.08, SH, at=(0, -0.06, 0))
stiles = []
for x in (-SW / 2 + 0.15, 0, SW / 2 - 0.15):
    stiles.append(kit.bevel(kit.box("stile", 0.3, 0.12, SH, at=(x, 0.04, 0)), 0.03, 2))
for z in (-SH / 2 + 0.15, -0.1, SH / 2 - 0.15):
    stiles.append(kit.bevel(kit.box("rail", SW, 0.12, 0.3, at=(0, 0.04, z)), 0.03, 2))
for x in (-SW / 4, SW / 4):  # raised fielded panels between them
    for z in (-SH / 4 - 0.05, SH / 4 - 0.05):
        stiles.append(kit.bevel(kit.box("panel", SW / 2 - 0.6, 0.06, SH / 2 - 0.55, at=(x, 0.0, z)), 0.05, 2))
keep("LoreShelfBack", [back] + stiles, (6.4, 5.2, 0.2))

# a side: a scroll at the top front, feet with an arch cut between them (profile in y (front +) and z (up))
D = 1.4
# the arch cut between the feet
FOOT = 0.3
side_pts = [(-D / 2, -SH / 2), (-D / 2 + FOOT, -SH / 2)]
side_pts += [(y, -SH / 2 + 0.28 * math.sin(math.pi * (y + D / 2 - FOOT) / (D - 2 * FOOT)))
             for y in [(-D / 2 + FOOT) + (D - 2 * FOOT) * i / 10 for i in range(1, 10)]]
side_pts += [(D / 2 - 0.3, -SH / 2), (D / 2, -SH / 2), (D / 2, SH / 2 - 0.55)]
side_pts += arc(D / 2 - 0.3, SH / 2 - 0.55, 0.3, 0, math.pi / 2, 8)[1:]  # the scroll's curve back at the top front
side_pts += [(-D / 2 + 0.1, SH / 2), (-D / 2, SH / 2 - 0.1)]
side = prism("side", side_pts, 0.25, axis="X")
kit.bevel(side, 0.02, 2)
keep("LoreShelfSide", [side], (0.25, 5.2, 1.4))

# a shelf board: a bullnose lip along its front (profile in y, z)
lip = [(-D / 2, -0.11), (D / 2 - 0.11, -0.11)] + arc(D / 2 - 0.11, 0, 0.11, -math.pi / 2, math.pi / 2, 10)[1:-1]
lip += [(D / 2 - 0.11, 0.11), (-D / 2, 0.11)]
keep("LoreShelfBoard", [prism("board", lip, SW, axis="X")], (6.4, 0.22, 1.4))

# a closed book stood spine out (the spine toward the viewer, Blender +y): two boards, the page block between,
# a round ribbed spine
bh = 1.8
books = []
for s in (-1, 1):
    books.append(kit.bevel(kit.box("board", 0.07, 0.92, bh, at=(s * 0.315, -0.04, 0)), 0.02, 1))
books.append(kit.box("pageblock", 0.56, 0.86, bh - 0.08, at=(0, -0.08, 0)))
sp = lathe_x("spineroll", [(-bh / 2, 0.3), (-bh / 2 + 0.02, 0.35), (bh / 2 - 0.02, 0.35), (bh / 2, 0.3)], segs=20)
sp.rotation_euler = (0, math.pi / 2, 0)
kit.apply_all(sp)
kit.deform(sp, lambda co: Vector((co.x, co.y * 0.32 / 0.35, co.z)))
sp = kit.cut(sp, Vector((0, 1, 0)), keep_positive=True)
kit.shift(sp, (0, 0.36, 0))
books.append(sp)
for z in (bh / 2 - 0.25, -bh / 2 + 0.25):
    r = kit.torus("rib", 0.34, 0.025, at=(0, 0, 0), segs=20, csegs=6, arc=math.pi)
    kit.deform(r, lambda co: Vector((co.x, co.y * 0.32 / 0.34, co.z)))
    kit.shift(r, (0, 0.36, z))
    books.append(r)
keep("LoreBookClosed", books, (0.7, 1.8, 1.0))

# a shelf book's gold strap: a thin loop round the book's cross section, rounded over the spine
outer = rounded_rect(0.72, 1.02, 0.12, 4)
strap = prism("strap", outer, 0.12, axis="Z")
hole = prism("hole", rounded_rect(0.66, 0.96, 0.1, 4), 0.3, axis="Z")
m = strap.modifiers.new("cut", "BOOLEAN")
m.operation = "DIFFERENCE"
m.object = hole
kit.apply_all(strap)
bpy.data.objects.remove(hole, do_unlink=True)
keep("LoreSpineBand", [strap], (0.72, 0.12, 1.02))

# ======================================================================== export, then the preview
total = sum(kit.tris(ob) for ob, _ in MESH.values())
print("lore book set:", len(MESH), "meshes,", total, "tris")
if "--no-export" not in sys.argv:
    export = []
    for name, (ob, _) in MESH.items():
        kit.centre(ob)
        export.append(ob)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "LoreBook.fbx"))

if "--preview" in sys.argv:
    DATA = json.load(open(os.path.join(kit.ROOT, "export", "lore", "book.json")))
    R2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))

    def rbx_rot(rx, ry, rz):
        ax, ay, az = math.radians(rx), math.radians(ry), math.radians(rz)
        Rx = Matrix(((1, 0, 0), (0, math.cos(ax), -math.sin(ax)), (0, math.sin(ax), math.cos(ax))))
        Ry = Matrix(((math.cos(ay), 0, math.sin(ay)), (0, 1, 0), (-math.sin(ay), 0, math.cos(ay))))
        Rz = Matrix(((math.cos(az), -math.sin(az), 0), (math.sin(az), math.cos(az), 0), (0, 0, 1)))
        return Ry @ Rx @ Rz

    MATS = {}

    def mat(rgb, material, alpha):
        key = (tuple(rgb), material, alpha)
        if key not in MATS:
            name = "M%d" % len(MATS)
            if material == "neon":
                m = kit.material(name, rgb, rough=0.4, emit=6.0 * (1 - (alpha or 0)) ** 2)
            elif material == "metal":
                m = kit.material(name, rgb, metal=0.9, rough=0.3)
            elif material == "fabric":
                m = kit.material(name, rgb, rough=0.85)
            else:
                m = kit.material(name, rgb, rough=0.55)
            if alpha:
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 1 - alpha
            MATS[key] = m
        return MATS[key]

    def place(p, colors, origin, scale=1.0):
        sx, sy, sz = [v * scale for v in p["size"]]
        name = p.get("mesh")
        if name:
            src, rbx = MESH[name]
            me = src.data.copy()
            # the mesh's Blender coordinates into the piece's unit Roblox-local box
            for v in me.vertices:
                bx, by, bz = v.co
                v.co = Vector((bx / rbx[0], bz / rbx[1], -by / rbx[2]))
            ob = bpy.data.objects.new(p["name"], me)
            bpy.context.scene.collection.objects.link(ob)
            ob.data.materials.clear()
        elif p["shape"] == "cylinder":
            ob = kit.cyl(p["name"], 0.5, 0.5, 1.0, axis="X", segs=24)
            # kit.cyl is in Blender axes: x stays x, and Roblox-local x is the axis either way
        else:
            ob = kit.box(p["name"], 1, 1, 1)
        rot = rbx_rot(*p["rot"])
        pos = Vector(p["pos"]) * scale + Vector(origin)
        ob.matrix_world = R2B.to_4x4() @ Matrix.Translation(pos) @ rot.to_4x4() @ Matrix.Diagonal((sx, sy, sz, 1))
        col = p["color"]
        rgb = colors.get(col) if not col.startswith("book:") else DATA["colors"][col[5:]]["cover"]
        ob.data.materials.append(mat(rgb or (255, 0, 255), p["material"], p.get("alpha")))
        return ob

    for ob, _ in MESH.values():
        ob.hide_render = True
    kit.studio(res=(1400, 900), samples=48)
    for i, d in enumerate(DATA["show"]):
        origin = (-3.2 + i * 3.2, 3.6 + (0.25 if i == 1 else 0), 0)
        for p in DATA["book"]:
            place(p, DATA["colors"][d], origin)
    shelf_colors = dict(DATA["colors"]["Downtown"])
    shelf_colors["spine"] = (120, 80, 50)
    for p in DATA["shelf"]:
        place(p, shelf_colors, (0, 0, 4.5), 0.7)
    g = kit.box("Ground", 30, 30, 0.2, at=(0, 0, -0.1))
    g.data.materials.append(kit.material("Ground", (90, 95, 110), rough=0.9))
    kit.camera((1.5, 12.5, 5.6), (0, -1.0, 3.2), lens=40)
    out = os.path.join(kit.ROOT, "preview", "lorebooks.png")
    kit.render(out)
    print("wrote", out)

if "--sheet" in sys.argv:
    # every role mesh on its own, scaled up to a common size, for a close look (art/preview/lorebooks_sheet.png)
    kit.studio(res=(1500, 900), samples=32)
    gold = kit.material("Gold", (230, 180, 70), metal=0.9, rough=0.3)
    for ob, _ in MESH.values():
        ob.hide_render = True
    for i, (name, (ob, rbx)) in enumerate(MESH.items()):
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        big = max(cp.dimensions)
        k = 1.6 / big
        cp.scale = (k, k, k)
        cp.location = ((i % 5) * 2.2 - 4.4, 0, 3.6 - (i // 5) * 1.9)
        cp.rotation_euler = (0, 0, math.radians(-25))
        cp.data.materials.clear()
        cp.data.materials.append(gold)
        cp.hide_render = False
    kit.camera((0, 14, 1.8), (0, 0, 1.8), lens=50)
    kit.render(os.path.join(kit.ROOT, "preview", "lorebooks_sheet.png"))
