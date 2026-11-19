# ruinkit.py: shared helpers for crater.py (the Crater's blasted Crane lab) and wrecks.py (downed robots' wrecks)
# (gap-wrecks, 2026-11-19): broken shapes in Roblox studs (x, up, z; front at -z) on top of studs.py and vkit.py,
# the two extra paint patterns on hbake.py's bake (white lab panels, soot over any pattern), the per-look bake, the
# fit table (look -> frame + meshes, the shape of Config.DeepArt, read through Shared.DeepArtKit) and the FBX export.
# Imported after kit (which imports bpy first).
import math
import os
import random
import shutil
import subprocess

import kit
import bpy
import bmesh
import numpy as np
from mathutils import Vector

import hbake
import vkit
from studs import rb, C, S, T, LOOKS, INFO, turn, shift, copy  # noqa: F401
from vkit import rbox, bend

# ---------------------------------------------------------------- extra patterns on hbake's bake
_base = hbake.pattern


def _pattern(kind, rgb, P, N):
    if kind.endswith("+soot"):  # any pattern with burnt soot blotches (fire damage), a little rougher and duller
        col, mult, h, r, m = _base(kind[:-5], rgb, P, N)
        s = hbake.fbm(P + 7.0, 0.22)
        k = np.clip((s - 0.6) * 2.6, 0, 0.55) * (0.75 + 0.25 * hbake.fbm(P, 1.8))
        col = col * (1 - k[:, None]) + np.array([0.06, 0.055, 0.05], np.float32) * k[:, None]
        return col, mult * (1 - k), h, np.clip(r + 0.25 * k, 0.05, 1), m * (1 - k)
    if kind == "labpanel":  # white lab cladding: panel seams every 4 along and 3 up, a fine sheen, grime blotches
        u, v, ax = hbake.planar(P, N)
        n = len(P)
        col = np.tile(np.array(rgb, np.float32) / 255, (n, 1))
        seam = hbake._line(u, 4.0, 0.04) | hbake._line(v, 3.0, 0.04)
        mult = (0.93 + 0.07 * hbake.fbm(P, 1.4)) * np.where(seam, 0.62, 1.0)
        grime = hbake.fbm(P + 3.0, 0.45)
        mult = mult * np.where(grime > 0.62, 0.84, 1.0)
        crack = np.abs(np.sin(u * 0.8 + np.sin(v * 1.1 + ax) * 1.7)) < 0.03
        mult = mult * np.where(crack, 0.45, 1.0)
        h = -seam * 0.7 - crack * 0.6
        col = np.clip(col * mult[:, None], 0, 1)
        return col, mult, h.astype(np.float32), np.full(n, 0.42, np.float32), np.zeros(n, np.float32)
    return _base(kind, rgb, P, N)


hbake.pattern = _pattern
hbake.ROUGH.setdefault("labpanel", 0.42)


def paint(ob, rgb, mat="SmoothPlastic", pat=None, tint=False):
    return hbake.paint(ob, rgb, mat, pat, tint)


# ---------------------------------------------------------------- broken shapes
def jitter(ob, amt, seed, octant=True):
    """Knock a block about: each corner of a box built about its centre moves as one (octant), so a bevel stays
    whole; else every vertex on its own."""
    rnd = random.Random(seed)
    cache = {}
    kit.apply_all(ob)
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.z for v in ob.data.vertices]
    zs = [-v.co.y for v in ob.data.vertices]
    cx, cy, cz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2

    def fn(x, y, z):
        k = ((x > cx, y > cy, z > cz) if octant else (round(x, 3), round(y, 3), round(z, 3)))
        if k not in cache:
            cache[k] = (rnd.uniform(-amt, amt), rnd.uniform(-amt, amt), rnd.uniform(-amt, amt))
        dx, dy, dz = cache[k]
        return x + dx, y + dy, z + dz
    return bend(ob, fn)


def lump(sx, sy, sz, x, y, z, seed, amt=0.15, bev=0.08, tilt=(0, 0, 0)):
    """A broken block (a chunk of concrete, a cracked plate) centred at (x, y, z), tilted by (x, up, z) degrees."""
    ob = rbox(sx, sy, sz, 0, 0, 0, bev=bev)
    jitter(ob, amt, seed)
    for ax, d in zip(("x", "up", "z"), tilt):
        if d:
            turn(ob, ax, d)
    return shift(ob, rb(x, y, z))


def teeth(x0, x1, y, z, th, seed, hmax, wmin=0.6, wmax=1.8, low=0.15):
    """A broken top edge along x from x0 to x1, standing on y (never below it): jittered chunks th thick at z, each
    a random width and height up to hmax."""
    rnd = random.Random(seed)
    out = []
    x = x0
    while x < x1 - 0.2:
        w = min(rnd.uniform(wmin, wmax), x1 - x)
        h = rnd.uniform(low, hmax) if rnd.random() < 0.8 else rnd.uniform(low, hmax * 0.3)
        ob = rbox(w + 0.12, h + 0.2, th * rnd.uniform(0.82, 0.98), 0, 0, 0, bev=0.05)
        jitter(ob, min(0.12, h * 0.25), rnd.randint(0, 99999))
        bend(ob, lambda a, b, c: (a, max(b, -h / 2 - 0.1), c))
        out.append(shift(ob, rb(x + w / 2, y + h / 2 - 0.1, z + rnd.uniform(-0.05, 0.05))))
        x += w
    return out


def rebar(points, r=0.08, segs=5):
    return T(points, r, segs=segs)


def bars(n, base, out_dir, length, seed, r=0.07, spread=0.35):
    """n bent rebar rods poking out of a broken face at base points (list) along out_dir (Roblox vector)."""
    rnd = random.Random(seed)
    res = []
    for i in range(n):
        bx, by, bz = base[i % len(base)]
        L = length * rnd.uniform(0.6, 1.1)
        dx, dy, dz = out_dir
        mid = (bx + dx * L * 0.55 + rnd.uniform(-spread, spread), by + dy * L * 0.55 + rnd.uniform(-spread, spread),
               bz + dz * L * 0.55 + rnd.uniform(-spread, spread))
        end = (bx + dx * L + rnd.uniform(-spread, spread) * 2, by + dy * L + rnd.uniform(-spread, spread) * 2,
               bz + dz * L + rnd.uniform(-spread, spread) * 2)
        res.append(rebar([(bx - dx * 0.3, by - dy * 0.3, bz - dz * 0.3), mid, end], r))
    return res


def nut(x, y, z, s=0.18, axis="up", tilt=0.0):
    """A hex nut (six-sided short cylinder)."""
    ob = C(s, s * 0.6, 0, 0, 0, segs=6, axis=axis)
    if tilt:
        turn(ob, "x", tilt)
    return shift(ob, rb(x, y, z))


def arc(cx, cy, cz, rad, a0, a1, r, n=14, plane="xy"):
    """A tube along a circular arc (angles in degrees) about (cx, cy, cz) in the x-up plane (or x-z)."""
    pts = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        if plane == "xy":
            pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad, cz))
        else:
            pts.append((cx + math.cos(a) * rad, cy, cz + math.sin(a) * rad))
    return T(pts, r, segs=8)


def jag_tube(r, thick, y0, tops, segs=28):
    """An upright open tube (radius r, wall thick) from y0 up to a broken rim: tops(i) -> the rim's height at
    segment i. Both faces point outward from the wall, so it reads from inside and out."""
    bm = bmesh.new()
    ob_ = []
    hs = [tops(i) for i in range(segs)]
    rings = []
    for (rr, yy) in ((r, None), (r - thick, None)):
        bot, top = [], []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            x, z = math.cos(a) * rr, math.sin(a) * rr
            bot.append(bm.verts.new(rb(x, y0, z)))
            top.append(bm.verts.new(rb(x, hs[i], z)))
        rings.append((bot, top))
    (ob0, ot0), (ib0, it0) = rings
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((ob0[i], ob0[j], ot0[j], ot0[i]))
        bm.faces.new((ib0[j], ib0[i], it0[i], it0[j]))
        bm.faces.new((ot0[i], ot0[j], it0[j], it0[i]))
        bm.faces.new((ob0[j], ob0[i], ib0[i], ib0[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("jt")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("jt", me)
    bpy.context.scene.collection.objects.link(ob)
    del ob_
    return ob


def sheet(pts_fn, nu, nv, thick=0.08):
    """A cloth sheet: pts_fn(u, v) -> Roblox point for u, v in 0..1, given a little thickness (two faces)."""
    bm = bmesh.new()
    grid = [[None] * (nv + 1) for _ in range(nu + 1)]
    back = [[None] * (nv + 1) for _ in range(nu + 1)]
    for i in range(nu + 1):
        for j in range(nv + 1):
            p = Vector(rb(*pts_fn(i / nu, j / nv)))
            grid[i][j] = bm.verts.new(p)
    bm.verts.ensure_lookup_table()
    # the back face: offset along a rough normal
    for i in range(nu + 1):
        for j in range(nv + 1):
            a = grid[min(i + 1, nu)][j].co - grid[max(i - 1, 0)][j].co
            b = grid[i][min(j + 1, nv)].co - grid[i][max(j - 1, 0)].co
            n = a.cross(b)
            n = n.normalized() if n.length > 1e-6 else Vector((1, 0, 0))
            back[i][j] = bm.verts.new(grid[i][j].co - n * thick)
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            bm.faces.new((back[i][j + 1], back[i + 1][j + 1], back[i + 1][j], back[i][j]))
    for i in range(nu):
        for (j, k) in ((0, 0), (nv, nv)):
            bm.faces.new((grid[i][j], back[i][k], back[i + 1][k], grid[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((grid[i][j], grid[i][j + 1], back[i][j + 1], back[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("sh")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("sh", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def shard(pts, thick, x, y, z, ry=0.0, tilt=(0.0, 0.0)):
    """A flat jagged plate: a polygon (x, y) points in its own plane, thick along z, turned and placed."""
    ob = vkit.rings_mesh([[(px, py, -thick / 2) for (px, py) in pts], [(px, py, thick / 2) for (px, py) in pts]])
    if tilt[0]:
        turn(ob, "x", tilt[0])
    if tilt[1]:
        turn(ob, "z", tilt[1])
    if ry:
        turn(ob, "up", ry)
    return shift(ob, rb(x, y, z))


def ragged(n, rx, ry_, seed, depth=0.35):
    """A rough polygon (n points about the origin, radii rx by ry_) for shards and torn plates."""
    rnd = random.Random(seed)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1 - rnd.uniform(0, depth) if i % 2 else 1 + rnd.uniform(0, depth * 0.4)
        pts.append((math.cos(a) * rx * k, math.sin(a) * ry_ * k))
    return pts


# ---------------------------------------------------------------- the bake, the fit table and the export
def bake_all(looks, out_dir, res_of, fast=False, ao=16, only=None, plain=()):
    """Bake every look's textured meshes (not Neon, Glass or see-through, nor the `plain` names, which keep their
    part colour so the game can light them): one set a look. Returns mesh -> material."""
    mapped = {}
    for look in sorted(looks):
        if only and look not in only:
            continue
        objs = []
        for name, ob in sorted(LOOKS[look].items()):
            rgb, mat, alpha = INFO[name]
            if mat in ("Neon", "Glass", "ForceField") or alpha or name in plain:
                continue
            if not hbake.painted(ob):
                hbake.paint(ob, rgb, mat)
            objs.append(ob)
        if not objs:
            continue
        res = 256 if fast else res_of(look, objs)
        m = hbake.bake(look, objs, out_dir, res=res, ao_samples=4 if fast else ao)
        for ob in objs:
            mapped[ob.name] = m
        print("baked", look, res, flush=True)
    return mapped


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def write_fit(path, head, looks, frames, mapped, origins=None):
    """The fit table: look -> { frame = its box (studs x, up, z), meshes = each mesh's size, centre from the frame's
    middle (origins[look]: where that middle is in the build's studs), colour, material, alpha, maps, tris }."""
    rows = []
    total, count = 0, 0
    tris = {}
    for look in sorted(looks):
        f = frames[look]
        o = (origins or {}).get(look, (0.0, 0.0, 0.0))
        rows.append("\t%s = {" % look)
        rows.append("\t\tframe = { %.3f, %.3f, %.3f }," % tuple(f))
        rows.append("\t\tmeshes = {")
        for name in sorted(LOOKS[look]):
            ob = LOOKS[look][name]
            lo, hi = bounds(ob)
            c = (lo + hi) / 2
            size = hi - lo
            t = kit.tris(ob)
            tris[name] = t
            total += t
            count += 1
            rgb, mat, alpha = INFO[name]
            extra = (", alpha = %g" % alpha) if alpha else ""
            if name in mapped:
                extra += ", maps = true"
            rows.append("\t\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                        % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x - o[0], c.z - o[1], -c.y - o[2],
                           rgb[0], rgb[1], rgb[2], mat, extra, t))
        rows.append("\t\t},")
        rows.append("\t},")
    text = "\n".join(head + ["-- %d meshes in %d looks, %d triangles." % (count, len(looks), total), "return {"] + rows + ["}", ""])
    with open(path, "w") as fh:
        fh.write(text)
    st = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
    if os.path.exists(st):
        subprocess.run([st, "--config-path", os.path.join(os.path.dirname(path), "..", "..", "stylua.toml"), path], check=False)
    return tris, total, count


def export_fbx(path, looks, mapped):
    export = []
    for look in sorted(looks):
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            if name not in mapped:
                cp.data.materials.clear()
            export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y",
        object_types={"MESH"}, use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False,
        bake_anim=False, path_mode="COPY", embed_textures=True)
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)


# ---------------------------------------------------------------- previews
def flat_mat(rgb, kind="SmoothPlastic", alpha=0.0):
    import vpreview as vp
    return vp._mat_flat(tuple(rgb), kind, alpha)


def placed(look, mapped, at, ry, keep):
    """A preview copy of a look's meshes moved so the look's build origin sits at `at` (Roblox), turned ry."""
    for name, ob in LOOKS[look].items():
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.data.materials.clear()
        rgb, mat, alpha = INFO[name]
        cp.data.materials.append(mapped[name] if name in mapped else flat_mat(rgb, mat, alpha))
        cp.location = rb(*at)
        cp.rotation_euler = (0, 0, math.radians(ry))
        keep(cp)
