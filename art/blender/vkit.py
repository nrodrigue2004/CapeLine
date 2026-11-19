# vkit.py: the vehicle art kit for vehicles.py (2026-11-18 remake): shapes built in Roblox studs (x, up, z; nose at -z)
# about a look's foot point, paint regions, the per-look texture bake (region ids, object position and normal,
# ambient occlusion) and the composed texture set (colour with alpha where the game's part colour shows through,
# normal, roughness, metalness), the fit table and the FBX export.
# Every look is a handful of meshes by role:
#   <P>Body    the shell: textured; its paint regions are see-through (alpha 0) on a car the game paints
#   <P>Detail  trim, chrome, rubber, grille, interior and props: textured, opaque
#   <P>Wheel<axle><side>  each road wheel on its own (2026-11-19: the game spins and steers them): split out of
#           Detail after the bake, so it keeps Detail's UVs and texture set. <axle> is F (the front, which steers)
#           or R1, R2.. back from it; <side> L (-x, the driver's left facing -z) or R. Centred on its axle.
#   <P>Glass   the windows: tinted and see-through (no texture), so the seats and dash show through
#   <P>Lamps   headlights and other white or amber lights (Neon), <P>Tails the red lights (Neon)
# Imported after kit (which imports bpy first).
import math
import os

import kit
import bpy
import bmesh
import numpy as np
from mathutils import Vector

from studs import rb, B, C, S, T, TOR, turn, shift, copy, rings_mesh, star  # noqa: F401

RES = 1024
OUT = os.path.join(kit.ROOT, "export", "vehicles")


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# ================================================================ paint regions (one material each, for the bake)
REG = []  # idx -> dict(name, rgb (None: the look's paint function), rough, metal, pat)
_REGK = {}


def R(name, rgb=None, rough=0.5, metal=0.0, pat=None):
    """A paint region: its albedo (None: the look's paint), roughness, metalness and an optional pattern."""
    key = (name, tuple(rgb) if rgb else None, rough, metal, pat)
    if key in _REGK:
        return _REGK[key]
    idx = len(REG)
    m = bpy.data.materials.new("r%02d_%s" % (idx, name))
    m.use_nodes = True
    m["rid"] = idx
    p = m.node_tree.nodes["Principled BSDF"]
    if rgb:
        p.inputs["Base Color"].default_value = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
    REG.append(dict(name=name, rgb=rgb, rough=rough, metal=metal, pat=pat, mat=m))
    _REGK[key] = m
    return m


def rid(m):
    return int(m["rid"])


def put(ob, m):
    """Give a part one region (every face)."""
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.material_index = 0
    return ob


def P(ob, m):
    return put(ob, m)


# ================================================================ shapes (Roblox studs)
def sec(wb, wt, yb, yt, p=3.0, segs=24, flat=False, pb=None):
    """A cross-section about x = 0: a superellipse from yb to yt whose half width runs from wb at the bottom to wt
    at the top (tumblehome); p the top half's power (2 round, higher boxier), pb the bottom half's; flat: a
    straight floor."""
    cy, ry = (yb + yt) / 2, (yt - yb) / 2
    out = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        pw = p if s >= 0 else (pb or p)
        y = cy + ry * math.copysign(abs(s) ** (2 / pw), s)
        if flat and s < -0.05:
            y = yb
        t = (y - yb) / max(1e-6, yt - yb)
        w = wb + (wt - wb) * t
        out.append((w * math.copysign(abs(c) ** (2 / pw), c), y))
    return out


def smooth_keys(keys, z):
    """Monotone cubic (Fritsch-Carlson) through (z, value) keys."""
    zs = [k[0] for k in keys]
    vs = [k[1] for k in keys]
    if z <= zs[0]:
        return vs[0]
    if z >= zs[-1]:
        return vs[-1]
    n = len(zs)
    d = [(vs[i + 1] - vs[i]) / (zs[i + 1] - zs[i]) for i in range(n - 1)]
    m = [d[0]] + [0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) / 2 for i in range(1, n - 1)] + [d[-1]]
    for i in range(n - 1):
        if abs(d[i]) < 1e-9:
            m[i] = m[i + 1] = 0.0
    i = max(k for k in range(n - 1) if zs[k] <= z)
    h = zs[i + 1] - zs[i]
    t = (z - zs[i]) / h
    h00, h10, h01, h11 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t, -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
    return h00 * vs[i] + h10 * h * m[i] + h01 * vs[i + 1] + h11 * h * m[i + 1]


def body_loft(zs, f, segs=24, cap=(True, True)):
    """A loft along z: f(z) -> (wb, wt, yb, yt, p[, pb]) at each station."""
    rings = []
    for z in zs:
        r = f(z)
        wb, wt, yb, yt, p = r[:5]
        pb = r[5] if len(r) > 5 else None
        rings.append([(x, y, z) for (x, y) in sec(wb, wt, yb, yt, p, segs, pb=pb)])
    return rings_mesh(rings, cap)


def stations(z0, z1, n, ends=0.0):
    """n stations from z0 to z1, closer together near the ends (ends 0..1)."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        t = t + ends * (-(math.sin(2 * math.pi * t)) / (2 * math.pi))
        out.append(z0 + (z1 - z0) * t)
    return out


def lathe(profile, at, axis="x", segs=18, side=1, closed=True):
    """A surface of revolution about an axis through `at`: profile [(radius, offset along the axis)]; side
    flips the offset (a wheel's outer face to the outside). closed: the profile is a loop."""
    cx, cy, cz = at
    rings = []
    for (r, o) in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            u, v = math.cos(a) * r, math.sin(a) * r
            if axis == "x":
                ring.append((cx + o * side, cy + u, cz + v))
            elif axis == "z":
                ring.append((cx + u, cy + v, cz + o * side))
            else:
                ring.append((cx + u, cy + o * side, cz + v))
        rings.append(ring)
    bm = bmesh.new()
    loops = [[bm.verts.new(rb(*p)) for p in ring] for ring in rings]
    n = len(loops)
    for k in range(n if closed else n - 1):
        a, b = loops[k], loops[(k + 1) % n]
        for i in range(segs):
            bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    if closed:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("lathe")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("lathe", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def face_out(ob, direction):
    """Point an open surface's faces along a Roblox direction (on average)."""
    d = Vector(rb(*direction))
    me = ob.data
    s = sum((p.normal.dot(d) * p.area for p in me.polygons), 0.0)
    if s < 0:
        me.flip_normals()
    return ob


def inward(ob):
    """Flip a closed part so it is seen from inside (cabin liners)."""
    outward(ob)
    ob.data.flip_normals()
    ob["inside"] = True
    return ob


def rbox(sx, sy, sz, x=0.0, y=0.0, z=0.0, bev=0.1, segs=2):
    ob = kit.box("b", sx, sz, sy, at=rb(x, y, z))
    if bev:
        kit.bevel(ob, bev, segs)
        kit.apply_all(ob)
    return ob


def bend(ob, fn):
    """Move every vertex: fn(x, y, z) -> (x, y, z) in Roblox studs."""
    kit.apply_all(ob)
    for v in ob.data.vertices:
        x, y, z = v.co.x, v.co.z, -v.co.y
        x, y, z = fn(x, y, z)
        v.co = Vector(rb(x, y, z))
    ob.data.update()
    return ob


def boolean(ob, cutter, op="DIFFERENCE"):
    kit.apply_all(ob)
    kit.apply_all(cutter)
    m = ob.modifiers.new("bool", "BOOLEAN")
    m.operation = op
    m.solver = "EXACT"
    try:
        m.material_mode = "TRANSFER"
    except Exception:
        pass
    m.object = cutter
    kit.apply_all(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return ob


def rcoords(f_center):
    """Blender (x, front, up) to Roblox (x, up, back)."""
    return (f_center.x, f_center.z, -f_center.y)


def cut_windows(ob, groups, frame_mat, frame=0.07, depth=0.05, cuts=()):
    """Cut window openings in a shell: each group a predicate on a face's Roblox centre and normal; the faces
    are inset (a rubber frame in frame_mat, recessed by depth) and come out as a separate glass object.
    cuts: [(axis, value)] planes (Roblox "x", "y" or "z") the shell is sliced along first, so window edges
    that follow them run straight instead of stepping along the loft's faces."""
    kit.apply_all(ob)
    if frame_mat.name not in [m.name for m in ob.data.materials]:
        ob.data.materials.append(frame_mat)
    fidx = [m.name for m in ob.data.materials].index(frame_mat.name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for (ax, v) in cuts:
        co, no = {"x": ((v, 0, 0), (1, 0, 0)), "y": ((0, 0, v), (0, 0, 1)), "z": ((0, -v, 0), (0, 1, 0))}[ax]
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    bm.faces.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    tag = bm.faces.layers.int.new("glass")
    for pred in groups:
        faces = []
        for f in bm.faces:
            if f[tag]:
                continue
            c = rcoords(f.calc_center_median())
            n = rcoords(f.normal)
            if pred(c, n):
                faces.append(f)
        if not faces:
            continue
        res = bmesh.ops.inset_region(bm, faces=faces, thickness=frame, depth=-depth, use_even_offset=True)
        for f in res["faces"]:
            f.material_index = fidx
        for f in faces:
            f[tag] = 1
    glass = bmesh.new()
    glass_me = bpy.data.meshes.new("glass")
    bm.to_mesh(glass_me)
    glass.from_mesh(glass_me)
    gt = glass.faces.layers.int.get("glass")
    bmesh.ops.delete(glass, geom=[f for f in glass.faces if not f[gt]], context="FACES")
    glass.to_mesh(glass_me)
    glass.free()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[tag]], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    g = bpy.data.objects.new("glass", glass_me)
    bpy.context.scene.collection.objects.link(g)
    return g


def outward(ob):
    """A closed part's faces all pointing out (some primitives come inside out); open surfaces are left alone."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    if bm.edges and all(len(e.link_faces) == 2 for e in bm.edges):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
    bm.free()
    return ob


def join(parts, name, fix=True):
    parts = [p for p in parts if p is not None]
    for p in parts:
        kit.apply_all(p)
        if fix and not p.get("inside"):
            outward(p)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def smooth_shade(ob, angle=38):
    kit.apply_all(ob)
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    bm = bmesh.new()
    bm.from_mesh(me)
    for e in bm.edges:
        e.smooth = True
        if len(e.link_faces) == 2:
            a, b = e.link_faces
            if a.normal.angle(b.normal, 0) > math.radians(angle) or a.material_index != b.material_index:
                e.smooth = False
    bm.to_mesh(me)
    bm.free()
    return ob


def mirror_x(ob):
    """A mirrored copy across x = 0 (normals kept outward)."""
    cp = copy(ob)
    kit.apply_all(cp)
    for v in cp.data.vertices:
        v.co.x = -v.co.x
    cp.data.flip_normals()
    return cp


def both(fn):
    out = []
    for s_ in (1, -1):
        r_ = fn(s_)
        out += r_ if isinstance(r_, list) else [r_]
    return out


# ================================================================ standard pieces
def wheel(x, y, z, r, w, side, tyre, rim, hub, segs=16, spokes=5, white=None, rim_r=0.66, dish=0.1):
    """A tyre (rounded sidewalls), a rim dish with spokes and a hub cap, outer face toward side."""
    hw = w / 2
    prof = [(r * 0.62, -hw * 0.9), (r * 0.93, -hw), (r, -hw * 0.55), (r, hw * 0.55), (r * 0.93, hw), (r * 0.62, hw * 0.9)]
    t = P(lathe(prof, (x, y, z), "x", segs, side), tyre)
    parts = [t]
    if white:  # a whitewall ring on the outer sidewall
        ww = P(lathe([(r * 0.86, hw + 0.012), (r * 0.7, hw * 0.97 + 0.012)], (x, y, z), "x", segs, side, closed=False), white)
        parts.append(face_out(ww, (side, 0, 0)))
    rr = r * rim_r
    disc = lathe([(rr * 1.02, hw * 0.93), (rr * 0.88, hw * 0.93 - dish * 0.5), (rr * 0.4, hw * 0.93 - dish),
                  (0.0, hw * 0.93 - dish * 0.6)], (x, y, z), "x", segs, side, closed=False)
    parts.append(face_out(P(disc, rim), (side, 0, 0)))
    for k in range(spokes):
        a = 2 * math.pi * k / spokes + 0.3
        sp = rbox(0.07, rr * 0.82, rr * 0.2, 0, 0, 0, bev=0)
        shift(sp, rb(0, rr * 0.5, 0))
        turn(sp, "x", math.degrees(a))
        shift(sp, rb(x + side * (hw * 0.93 - dish * 0.55), y, z))
        parts.append(P(sp, rim))
    cap = C(rr * 0.26, 0.12, x + side * (hw * 0.93 - dish * 0.35), y, z, segs=10, axis="x")
    parts.append(P(cap, hub))
    return parts


def seat(x, y, z, w=1.15, d=1.1, h=1.25, m=None, back_tilt=12, bench=False):
    """A seat: base, back and (unless a bench) a headrest; facing -z, its base top at y."""
    parts = [P(rbox(w, 0.38, d, x, y - 0.19, z, bev=0.12, segs=1), m)]
    bk = rbox(w * 0.96, h, 0.3, x, y + h / 2, z + d / 2 - 0.12, bev=0.12, segs=1)
    turn(bk, "x", back_tilt, (x, y, z + d / 2 - 0.12))
    parts.append(P(bk, m))
    if not bench:
        hr = rbox(w * 0.55, 0.34, 0.24, x, y + h + 0.25, z + d / 2 + 0.05, bev=0.1, segs=1)
        turn(hr, "x", back_tilt, (x, y, z + d / 2 - 0.12))
        parts.append(P(hr, m))
    return parts


def steering(x, y, z, r=0.38, m=None, tilt=60):
    ring = TOR(r, 0.055, 0, 0, 0, axis="z", segs=14, csegs=4)
    col = C(0.06, 0.7, 0, 0, 0.35, segs=6, axis="z")
    hubp = rbox(0.22, 0.14, 0.12, 0, 0, 0, bev=0.03, segs=1)
    bar = rbox(r * 2, 0.07, 0.06, 0, 0, 0, bev=0.0)
    parts = [ring, col, hubp, bar]
    for p_ in parts:
        turn(p_, "x", tilt - 90)
        shift(p_, rb(x, y, z))
        P(p_, m)
    return parts


def mirror_arm(side, x, y, z, paint, glass_m, dark, size=(0.36, 0.42, 0.62)):
    """A door mirror: a stalk from the door and a rounded housing (paint) with its glass facing back."""
    sx, sy, sz = size
    hx = x + side * (sx / 2 + 0.28)
    stalk = P(rbox(0.36, 0.1, 0.16, x + side * 0.16, y - 0.05, z + 0.05, bev=0.03, segs=1), dark)
    house = P(rbox(sz * 0.75, sy, sx, hx, y, z, bev=0.12, segs=2), paint)
    turn(house, "up", 90 if side > 0 else -90, (hx, y, z))
    glass = P(rbox(sz * 0.62, sy * 0.78, 0.04, hx, y, z + sx / 2 + 0.005, bev=0.0), glass_m)
    return [stalk, glass], [house]


# ================================================================ the looks
LOOKS = {}  # look -> dict


class Look:
    def __init__(self, name, prefix, tint, paint=None, seams=None, body_rgb=(220, 60, 50), detail_rgb=(62, 64, 70),
                 wheels=(), glass=((112, 160, 196), "Glass", 0.5), lamp=(255, 244, 214), tail=(236, 34, 40),
                 rings=()):
        self.name, self.prefix, self.tint = name, prefix, tint
        self.paint = paint  # fn(P, N) -> (rgb (n,3) in 0..1, alpha (n,)) for the body's paint pixels
        self.seams = seams or []  # fn(P, N) -> mask 0..1 (panel lines)
        self.body_rgb, self.detail_rgb = body_rgb, detail_rgb
        self.wheels = list(wheels)  # (x, y, z, r): tread and whitewall patterns
        self.road = []  # (x, y, z, r, w): the road wheels split into their own meshes (split_wheels)
        self.spin = {}  # wheel mesh name -> dict(r, axle, steer): the fit table's `wheel` row
        self.rings = list(rings)  # (x, y, z, r_in, r_out, axis): striped rings (life rings)
        self.glass, self.lamp, self.tail = glass, lamp, tail
        self.meshes = {}
        self.extra = {}  # extra untextured meshes: name -> (rgb, mat, alpha)
        LOOKS[name] = self

    def add(self, role, parts, rgb=None, mat=None, alpha=0.0):
        """Join parts into this look's <prefix><role> mesh."""
        parts = [p for p in (parts if isinstance(parts, (list, tuple)) else [parts]) if p is not None]
        name = self.prefix + role
        if name in self.meshes:
            parts = [self.meshes[name]] + parts
        ob = join(parts, name)
        smooth_shade(ob)
        self.meshes[name] = ob
        if rgb is not None:
            self.extra[name] = (tuple(int(c) for c in rgb), mat or "SmoothPlastic", alpha)
        return ob

    def textured(self):
        out = [self.meshes[self.prefix + r] for r in ("Body", "Detail") if self.prefix + r in self.meshes]
        return out + [self.meshes[n] for n in sorted(self.spin)]


def split_wheels(lk):
    """Split each road wheel (lk.road) out of the baked Detail mesh into <P>Wheel<axle><side>: every face whose
    corners all lie inside the wheel's cylinder (radius r, width w about its x). Run after bake_look, so the wheel
    keeps Detail's UVs and shares its texture set. The front axle steers (when there is more than one axle)."""
    det = lk.meshes.get(lk.prefix + "Detail")
    if det is None or not lk.road:
        return
    zs = sorted({round(w[2], 3) for w in lk.road})
    for (x, y, z, r, w) in lk.road:
        k = zs.index(round(z, 3))
        name = lk.prefix + "Wheel" + ("F" if k == 0 else "R%d" % k) + ("L" if x < 0 else "R")
        bpy.ops.object.select_all(action="DESELECT")
        det.select_set(True)
        bpy.context.view_layer.objects.active = det
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        me = det.data
        rr, hw = r * 1.01 + 0.01, w / 2 + 0.04
        n = 0
        for p in me.polygons:
            inside = True
            for vi in p.vertices:
                co = me.vertices[vi].co  # Blender (x, -z, up) of Roblox (x, up, z)
                if abs(co.x - x) > hw or (co.z - y) ** 2 + (-co.y - z) ** 2 > rr * rr:
                    inside = False
                    break
            p.select = inside
            n += inside
        if n == 0:
            raise SystemExit("%s: no faces for %s" % (lk.name, name))
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        new = [o for o in bpy.context.selected_objects if o is not det][0]
        new.name = name
        new.data.name = name
        lk.meshes[name] = new
        lk.spin[name] = dict(r=r, axle=k, steer=(k == 0 and len(zs) > 1))


# ================================================================ bake and compose
def _image(name, res, data=True, float_buf=False, alpha=False):
    img = bpy.data.images.new(name, res, res, alpha=alpha, float_buffer=float_buf)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


def _pixels(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def _mats(objs):
    out = []
    for o in objs:
        for m in o.data.materials:
            if m and m not in out:
                out.append(m)
    return out


def _bake(objs, kind, img, samples, emit=None):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    mats = _mats(objs)
    saved = {}
    for m in mats:
        nt = m.node_tree
        node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
        node.name = "BakeTarget"
        node.image = img
        nt.nodes.active = node
        if emit:
            out = nt.nodes["Material Output"]
            saved[m.name] = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].links else None
            em = nt.nodes.new("ShaderNodeEmission")
            em.name = "TmpEmit"
            emit(m, nt, em)
            nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.bake(type=kind)
    if emit:
        for m in mats:
            nt = m.node_tree
            em = nt.nodes.get("TmpEmit")
            if em:
                nt.nodes.remove(em)
            if saved.get(m.name) is not None:
                nt.links.new(saved[m.name], nt.nodes["Material Output"].inputs["Surface"])


def unwrap(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.003, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_look(lk, ao_samples=24):
    """Bake one look's maps and compose its texture set into art/export/vehicles/<Look>_*.png."""
    os.makedirs(OUT, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True
    sc.world = sc.world or bpy.data.worlds.new("W")
    mine = set(lk.meshes.values())
    for o in sc.objects:
        o.hide_render = o not in mine or o.name.endswith("Glass")
    objs = lk.textured()
    unwrap(objs)

    def id_emit(m, nt, em):
        i = int(m["rid"])
        em.inputs["Color"].default_value = ((i % 16 + 0.5) / 16, (i // 16 + 0.5) / 16, 0.5, 1)

    def pos_emit(m, nt, em):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        geo.name = "TmpGeo"
        nt.links.new(geo.outputs["Position"], em.inputs["Color"])

    def nrm_emit(m, nt, em):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        geo.name = "TmpGeo"
        nt.links.new(geo.outputs["Normal"], em.inputs["Color"])

    def clean(objs_):
        for m in _mats(objs_):
            g = m.node_tree.nodes.get("TmpGeo")
            if g:
                m.node_tree.nodes.remove(g)

    ids = _image("ids", RES, float_buf=True)
    sc.render.bake.margin = 0
    _bake(objs, "EMIT", ids, 1, id_emit)
    raw_ids = _pixels(ids)
    sc.render.bake.margin = 6
    _bake(objs, "EMIT", ids, 1, id_emit)
    pos = _image("pos", RES, float_buf=True)
    _bake(objs, "EMIT", pos, 1, pos_emit)
    clean(objs)
    nrm = _image("nrm", RES, float_buf=True)
    _bake(objs, "EMIT", nrm, 1, nrm_emit)
    clean(objs)
    ao = _image("ao", RES)
    _bake(objs, "AO", ao, ao_samples)
    I = _pixels(ids)
    inside = raw_ids[..., 2] > 0.25  # texels on an island (not the margin)
    Pb = _pixels(pos)[..., :3]
    Nb = _pixels(nrm)[..., :3]
    A = _pixels(ao)[..., 0]
    # Blender (x, front, up) to Roblox (x, up, back)
    Pr = np.stack([Pb[..., 0], Pb[..., 2], -Pb[..., 1]], axis=-1)
    Nr = np.stack([Nb[..., 0], Nb[..., 2], -Nb[..., 1]], axis=-1)
    region = (np.floor(I[..., 0] * 16)).astype(np.int32) + 16 * (np.floor(I[..., 1] * 16)).astype(np.int32)
    region[I[..., 2] < 0.25] = -1  # no island, not even its margin
    for img in (ids, pos, nrm, ao):
        bpy.data.images.remove(img)
    return compose(lk, region, inside, Pr, Nr, A)


def gauss(d, w):
    return np.exp(-(d / w) ** 2)


def compose(lk, region, inside, Pp, Nn, A):
    H, W = region.shape
    col = np.zeros((H, W, 3), dtype=np.float32)
    alpha = np.ones((H, W), dtype=np.float32)
    rough = np.full((H, W), 0.6, dtype=np.float32)
    metal = np.zeros((H, W), dtype=np.float32)
    height = np.zeros((H, W), dtype=np.float32)
    ao = np.clip(A, 0, 1)
    for _ in range(2):  # soften the bake's noise
        ao = (ao + np.roll(ao, 1, 0) + np.roll(ao, -1, 0) + np.roll(ao, 1, 1) + np.roll(ao, -1, 1)) / 5
    rng = np.random.default_rng(11)
    noise = rng.random((H // 8 + 2, W // 8 + 2)).astype(np.float32)
    noise = np.kron(noise, np.ones((8, 8), dtype=np.float32))[:H, :W]
    tinted = np.zeros((H, W), dtype=bool)
    for idx, rg in enumerate(REG):
        m = region == idx
        if not m.any():
            continue
        rough[m] = rg["rough"]
        metal[m] = rg["metal"]
        if rg["rgb"] is None:  # the look's paint
            if lk.paint:
                rgb, a = lk.paint(Pp[m], Nn[m])
            else:
                rgb, a = np.zeros((int(m.sum()), 3), np.float32), np.zeros(int(m.sum()), np.float32)
            col[m] = rgb
            alpha[m] = a
            tinted[m] = a < 0.5
            for sfn in lk.seams:
                s = np.clip(sfn(Pp[m], Nn[m]), 0, 1)
                height[m] -= s * 0.6
                c = col[m]
                col[m] = c * (1 - s[:, None] * 0.85) + np.array([0.04, 0.04, 0.05]) * s[:, None] * 0.85
                alpha[m] = np.maximum(alpha[m], s * 0.85)
        else:
            col[m] = np.array(rg["rgb"], dtype=np.float32) / 255
        pat = rg["pat"]
        if pat:
            _pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise)
    # shading: baked occlusion darkens the opaque paint, and shows over the game's colour as a dark veil
    shade = (0.55 + 0.45 * ao)[..., None]
    op = ~tinted
    col[op] = col[op] * shade[op]
    veil = np.clip((1 - ao) * 0.5, 0, 0.5)
    t_ = tinted
    col[t_] = np.array([0.03, 0.03, 0.04], dtype=np.float32) * (1 - alpha[t_, None]) + col[t_] * alpha[t_, None]
    alpha[t_] = np.clip(alpha[t_] + veil[t_] * (1 - alpha[t_]), 0, 1)
    # outside any island: opaque dark (never seen; keeps mip edges dark, not see-through)
    col[region < 0] = 0.1
    # normal from height (texture space; Roblox reads OpenGL style, +y up the texture)
    gy, gx = np.gradient(height)
    k = 3.0
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(gx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], axis=-1)
    return _save(lk, col, alpha, normal, rough, metal)


def _pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise):
    p = Pp[m]
    n = Nn[m]
    kind = pat[0] if isinstance(pat, tuple) else pat
    if kind == "tread":  # tyre: grooves across the tread, a ring line on the sidewall
        best = None
        for (wx, wy, wz, wr) in lk.wheels:
            d = (p[:, 1] - wy) ** 2 + (p[:, 2] - wz) ** 2 + ((np.abs(p[:, 0]) - abs(wx)) * 4) ** 2
            if best is None:
                best, cy, cz, rr = d, np.full(len(p), wy), np.full(len(p), wz), np.full(len(p), wr)
            else:
                sel = d < best
                best = np.where(sel, d, best)
                cy, cz, rr = np.where(sel, wy, cy), np.where(sel, wz, cz), np.where(sel, wr, rr)
        if best is None:
            return
        ang = np.arctan2(p[:, 1] - cy, p[:, 2] - cz)
        rad = np.sqrt((p[:, 1] - cy) ** 2 + (p[:, 2] - cz) ** 2)
        tread = np.abs(n[:, 0]) < 0.5
        g = (np.sin(ang * 26) > 0.55) & tread
        lat = tread & (np.abs(np.abs(p[:, 0]) % 0.3 - 0.15) < 0.025)
        c = col[m]
        c[g | lat] *= 0.45
        side = ~tread & (np.abs(rad - rr * 0.8) < 0.025)
        c[side] *= 1.6
        col[m] = c
        h = height[m]
        h[g | lat] -= 0.5
        height[m] = h
    elif kind == "grille":  # slats: dark gaps between bars (y), a mesh of holes
        y = p[:, 1]
        x = p[:, 0]
        hole = (np.abs((y * 6.5) % 1 - 0.5) < 0.3) & (np.abs((x * 6.5 + (np.floor(y * 6.5) % 2) * 0.5) % 1 - 0.5) < 0.38)
        c = col[m]
        c[hole] *= 0.25
        col[m] = c
        h = height[m]
        h[hole] -= 0.6
        height[m] = h
    elif kind == "slats":  # horizontal slats
        y = p[:, 1]
        gap = np.abs((y * float(pat[1] if isinstance(pat, tuple) else 4.0)) % 1 - 0.5) < 0.18
        c = col[m]
        c[gap] *= 0.3
        col[m] = c
        h = height[m]
        h[gap] -= 0.7
        height[m] = h
    elif kind == "fabric":  # seat cloth: stitched panels and a soft weave
        c = col[m]
        y = p[:, 1]
        z = p[:, 2]
        st = (np.abs((y * 2.6) % 1 - 0.5) < 0.04) | (np.abs((z * 2.6) % 1 - 0.5) < 0.04)
        c *= (0.92 + 0.08 * noise[m])[:, None]
        c[st] *= 0.7
        col[m] = c
        h = height[m]
        h[st] -= 0.4
        height[m] = h
    elif kind == "corrugate":  # a container's ribbed walls
        side = np.abs(n[:, 0]) > 0.6
        endw = np.abs(n[:, 2]) > 0.6
        w = np.where(side, np.sin(p[:, 2] * math.pi * 2 / 0.55), np.where(endw, np.sin(p[:, 0] * math.pi * 2 / 0.55), 0))
        h = height[m]
        h += w * 0.5
        height[m] = h
        c = col[m]
        c *= (0.93 + 0.07 * w)[:, None]
        col[m] = c
    elif kind == "planks":  # wood: planks along z with grain
        c = col[m]
        a = np.where(np.abs(n[:, 1]) > 0.6, p[:, 0], p[:, 1])
        gap = np.abs((a * 2.2) % 1 - 0.5) > 0.45
        grain = 0.88 + 0.12 * np.sin(p[:, 2] * 9 + noise[m] * 6)
        c *= grain[:, None]
        c[gap] *= 0.55
        col[m] = c
        h = height[m]
        h[gap] -= 0.5
        height[m] = h
    elif kind == "stripes":  # awning stripes along z: pat = ("stripes", rgb2, width)
        rgb2 = np.array(pat[1], dtype=np.float32) / 255
        wdt = pat[2]
        s = ((p[:, 2] / wdt) % 2) < 1
        c = col[m]
        c[s] = rgb2
        col[m] = c
    elif kind == "ring":  # a life ring: 4 white bands round its centre
        c = col[m]
        for (rx, ry, rz, r_in, r_out, axis) in lk.rings:
            d = np.sqrt((p[:, 1] - ry) ** 2 + (p[:, 2] - rz) ** 2) if axis == "x" else np.sqrt((p[:, 0] - rx) ** 2 + (p[:, 1] - ry) ** 2)
            near = (d < r_out + 0.2) & (np.abs((p[:, 0] if axis == "x" else p[:, 2]) - (rx if axis == "x" else rz)) < 0.6)
            ang = np.arctan2(p[:, 1] - ry, (p[:, 2] - rz) if axis == "x" else (p[:, 0] - rx))
            band = near & ((((ang + math.pi / 8) / (math.pi / 2)) % 1) < 0.35)
            c[band] = (0.96, 0.96, 0.94)
        col[m] = c
    elif kind == "sprinkles":  # sprinkles on a scoop
        c = col[m]
        q = np.floor(p * 7.0)
        hsh = np.sin(q[:, 0] * 12.9898 + q[:, 1] * 78.233 + q[:, 2] * 37.719) * 43758.5453
        hsh = hsh - np.floor(hsh)
        f = p * 7.0 - q
        dot = (np.abs(f[:, 0] - 0.5) < 0.22) & (np.abs(f[:, 1] - 0.5) < 0.12) & (hsh > 0.55)
        palette = np.array([[1, 1, 1], [0.35, 0.75, 1.0], [1.0, 0.85, 0.2], [0.55, 0.9, 0.45]], dtype=np.float32)
        pick = (hsh * 40).astype(np.int32) % 4
        c[dot] = palette[pick[dot]]
        col[m] = c
    elif kind == "waffle":  # a cone's waffle grid
        c = col[m]
        u = p[:, 1] * 3 + np.arctan2(p[:, 0], p[:, 2]) * 1.3
        v = p[:, 1] * 3 - np.arctan2(p[:, 0], p[:, 2]) * 1.3
        line = (np.abs(u % 1 - 0.5) > 0.42) | (np.abs(v % 1 - 0.5) > 0.42)
        c[line] *= 0.7
        col[m] = c
        h = height[m]
        h[line] -= 0.5
        height[m] = h
    elif kind == "checks":  # a taxi roof sign: checks
        c = col[m]
        ch = ((np.floor(p[:, 0] * 2.5) + np.floor(p[:, 1] * 2.5) + np.floor(p[:, 2] * 2.5)) % 2) == 0
        c[ch] = (0.06, 0.06, 0.07)
        col[m] = c


def _save(lk, col, alpha, normal, rough, metal):
    os.makedirs(OUT, exist_ok=True)
    H, W = alpha.shape

    def write(name, rgba, data, res=None):
        res = res or W
        if res != W:
            f = W // res
            rgba = rgba.reshape(res, f, res, f, 4).mean(axis=(1, 3))
        img = bpy.data.images.new(name, res, res, alpha=True)
        if data:
            img.colorspace_settings.name = "Non-Color"
        img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).reshape(-1))
        path = os.path.join(OUT, name + ".png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return img, path

    # colours are worked in display (sRGB) values throughout (region rgbs / 255 and the paint functions), which is
    # what a byte PNG holds
    one = np.ones_like(alpha)
    maps = {}
    maps["Color"] = write(lk.name + "_Color", np.dstack([np.clip(col, 0, 1), alpha]), False)
    maps["Normal"] = write(lk.name + "_Normal", np.dstack([normal, one]), True)
    maps["Roughness"] = write(lk.name + "_Roughness", np.dstack([rough, rough, rough, one]), True, RES // 2)
    maps["Metalness"] = write(lk.name + "_Metalness", np.dstack([metal, metal, metal, one]), True, RES // 2)
    return maps


def export_material(lk, maps):
    """The one material on a look's textured meshes (the importer makes a SurfaceAppearance of its four maps)."""
    m = bpy.data.materials.new(lk.name + "Paint")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex(img, data):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        if data:
            img.colorspace_settings.name = "Non-Color"
        return n

    tc = tex(maps["Color"][0], False)
    nt.links.new(tc.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(tc.outputs["Alpha"], p.inputs["Alpha"])
    tr = tex(maps["Roughness"][0], True)
    nt.links.new(tr.outputs["Color"], p.inputs["Roughness"])
    tm = tex(maps["Metalness"][0], True)
    nt.links.new(tm.outputs["Color"], p.inputs["Metallic"])
    tn = tex(maps["Normal"][0], True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return m
