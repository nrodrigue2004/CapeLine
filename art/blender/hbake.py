# hbake.py: the HQ texture bake (2026-11-19, the hideout art pass) for hq.py and hideout.py: every textured look
# gets one baked texture set (colour with alpha, normal, roughness, metalness) shared by its meshes, the way the
# vehicles' looks do (vkit.py: the same UV unwrap, region-id, position, normal and AO bakes, the same export
# material the importer turns into a SurfaceAppearance). Painting is per region: a region is a colour, a Roblox
# material name (which picks its pattern: wood grain, fabric weave, brushed or diamond plate metal, gold foil,
# board-formed concrete, marble veins, cork, leaves) or a named pattern (hazard stripes, riveted iron plates,
# a floor slab's saw cuts and stains, rust), and whether it is tinted: a tinted region's texels are see-through
# (alpha 0) with only its shading and pattern laid over, so the MeshPart's own Color (a plaque's side colour, the
# name plate's state, a rug in the side's colour) still paints it (SurfaceAppearance AlphaMode Overlay).
# Neon and see-through meshes are never baked (they stay the game's flat glowing or glass colour).
# Imported after kit (which imports bpy first).
import math
import os

import kit  # noqa: F401
import bpy
import numpy as np

import vkit

KIND = {  # Roblox material -> pattern
    "SmoothPlastic": "plastic", "Plastic": "plastic", "Metal": "metal", "DiamondPlate": "diamond", "Foil": "foil",
    "Wood": "wood", "WoodPlanks": "wood", "Fabric": "fabric", "Concrete": "concrete", "Marble": "marble",
    "Grass": "leaf", "Basalt": "concrete", "Slate": "slab", "Rock": "concrete", "Brick": "concrete",
}
ROUGH = {"plastic": 0.5, "metal": 0.38, "diamond": 0.42, "foil": 0.24, "wood": 0.72, "fabric": 0.92,
         "concrete": 0.88, "formwork": 0.88, "marble": 0.3, "leaf": 0.8, "slab": 0.78, "hazard": 0.6, "plates": 0.45,
         "rust": 0.7, "cork": 0.95, "grate": 0.5, "rubber": 0.9}
METAL = {"metal": 0.55, "diamond": 0.7, "foil": 0.9, "plates": 0.6, "grate": 0.5, "rust": 0.3}

_REG = {}


def region(rgb, mat="SmoothPlastic", pat=None, tint=False):
    """A paint region's material: its colour, Roblox material (the default pattern) or pattern, tinted or not."""
    rgb = tuple(int(c) for c in rgb)
    kind = pat or KIND.get(mat, "plastic")
    key = (rgb, kind, bool(tint))
    if key in _REG:
        return _REG[key]
    m = bpy.data.materials.new("hb%03d_%s" % (len(_REG), kind))
    m.use_nodes = True
    m["hb"] = 1
    m["rgb"] = list(rgb)
    m["kind"] = kind
    m["tint"] = 1 if tint else 0
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (vkit.lin(rgb[0]), vkit.lin(rgb[1]), vkit.lin(rgb[2]), 1)
    _REG[key] = m
    return m


def paint(ob, rgb, mat="SmoothPlastic", pat=None, tint=False):
    """Give a part (every face) one region; returns it."""
    return vkit.put(ob, region(rgb, mat, pat, tint))


def painted(ob):
    """Does every face of this object already carry a region?"""
    return bool(ob.data.materials) and all(m is not None and m.get("hb") for m in ob.data.materials)


# ---------------------------------------------------------------- noise (numpy, from object position in studs)
def _hash(ix, iy, iz):
    h = (ix.astype(np.int64) * 73856093) ^ (iy.astype(np.int64) * 19349663) ^ (iz.astype(np.int64) * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float32) / 65535.0


def vnoise(P, f):
    p = P * f
    i = np.floor(p)
    t = p - i
    s = t * t * (3 - 2 * t)
    i = i.astype(np.int64)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (s[:, 0] if dx else 1 - s[:, 0]) * (s[:, 1] if dy else 1 - s[:, 1]) * (s[:, 2] if dz else 1 - s[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out


def fbm(P, f, octaves=3):
    tot, amp, norm = 0, 1.0, 0
    for k in range(octaves):
        tot = tot + amp * vnoise(P + 17.3 * k, f * (2 ** k))
        norm += amp
        amp *= 0.5
    return tot / norm


def planar(P, N):
    """Each texel's flat (u, v) on its dominant face plane (v up the walls, z on the floors)."""
    a = np.abs(N)
    ax = np.argmax(a, axis=1)
    u = np.where(ax == 0, P[:, 2], P[:, 0])
    v = np.where(ax == 1, P[:, 2], P[:, 1])
    return u, v, ax


def _line(x, every, w):
    return np.abs((x / every) % 1.0 - 0.5) > 0.5 - w / every


# ---------------------------------------------------------------- the patterns: colour factor, height, roughness
def pattern(kind, rgb, P, N):
    n = len(P)
    col = np.tile(np.array(rgb, np.float32) / 255, (n, 1))
    mult = np.ones(n, np.float32)
    height = np.zeros(n, np.float32)
    rough = np.full(n, ROUGH.get(kind, 0.5), np.float32)
    metal = np.full(n, METAL.get(kind, 0.0), np.float32)
    u, v, ax = planar(P, N)
    big = fbm(P, 0.35)
    if kind == "plastic":
        mult *= 0.95 + 0.08 * fbm(P, 1.6)
    elif kind in ("metal", "plates", "grate", "diamond"):
        # brushed streaks along the face's u
        streak = vnoise(np.stack([u * 0.5, v * 16, ax * 3.1], axis=1), 1.0)
        mult *= 0.9 + 0.12 * streak + 0.05 * big
        rough += 0.12 * (streak - 0.5)
        sat = max(rgb) - min(rgb)
        if sat > 90:  # painted metal: less metallic so its colour reads
            metal *= 0.45
        if kind == "diamond":  # raised lozenges on a diagonal grid, alternating
            a, b = (u + v) * 1.4, (u - v) * 1.4
            cell = (np.floor(a) + np.floor(b)) % 2
            fa, fb = a % 1 - 0.5, b % 1 - 0.5
            lz = np.where(cell == 0, (np.abs(fa) < 0.11) & (np.abs(fb) < 0.32), (np.abs(fb) < 0.11) & (np.abs(fa) < 0.32))
            height += lz * 1.0
            mult *= np.where(lz, 1.12, 0.94)
        elif kind == "plates":  # riveted plate courses: seams every 3 up and 4 along (offset a row), rivets by them
            row = np.floor(v / 3.0)
            uu = u + (row % 2) * 2.0
            seam = _line(v, 3.0, 0.05) | _line(uu, 4.0, 0.05)
            mult *= np.where(seam, 0.45, 1.0)
            height -= seam * 0.8
            ru, rv = (uu % 4.0) - 0.0, (v % 3.0)
            dots = ((np.abs((uu % 0.8) - 0.4) < 0.11) & (np.minimum(rv, 3.0 - rv) < 0.32) & (np.minimum(rv, 3.0 - rv) > 0.12)) | \
                   ((np.abs((v % 0.75) - 0.375) < 0.11) & (np.minimum(ru, 4.0 - ru) < 0.32) & (np.minimum(ru, 4.0 - ru) > 0.12))
            height += dots * 1.2
            mult *= np.where(dots, 1.2, 1.0)
            mult *= 0.88 + 0.16 * fbm(P + 3.0, 0.5)  # each plate a little different
        elif kind == "grate":
            hole = (np.abs((u * 2.5) % 1 - 0.5) < 0.32) & (np.abs((v * 2.5) % 1 - 0.5) < 0.18)
            mult *= np.where(hole, 0.22, 1.0)
            height -= hole * 0.8
    elif kind == "foil":
        mult *= 0.9 + 0.14 * fbm(P, 6.0) + 0.05 * big
    elif kind == "wood":
        g = np.sin((v * 7.0 + 3.0 * fbm(P, 0.7)) * 2 * math.pi)
        mult *= 0.84 + 0.08 * (g * 0.5 + 0.5) + 0.1 * fbm(P, 2.5)
        seam = _line(v, 1.1, 0.025)
        mult *= np.where(seam, 0.6, 1.0)
        height += g * 0.12 - seam * 0.7
    elif kind == "fabric" or kind == "rubber":
        w = np.sin(u * 2 * math.pi * 7) * np.sin(v * 2 * math.pi * 7)
        mult *= 0.92 + 0.05 * w + 0.07 * fbm(P, 1.2)
        height += w * 0.25
    elif kind in ("concrete", "formwork", "slab"):
        mult *= 0.8 + 0.24 * big + 0.06 * fbm(P, 3.0)
        pit = vnoise(P, 7.0) > 0.86
        mult *= np.where(pit, 0.78, 1.0)
        height -= pit * 0.5
        if kind == "formwork":  # board-formed: a joint every 2.5 up, tie holes on a 3 x 2.5 grid
            seam = _line(v, 2.5, 0.04)
            mult *= np.where(seam, 0.78, 1.0)
            height -= seam * 0.6
            du = (u % 3.0) - 1.5
            dv = ((v + 1.25) % 2.5) - 1.25
            tie = du * du + dv * dv < 0.022
            mult *= np.where(tie, 0.35, 1.0)
            height -= tie * 1.0
            # damp near the floor and streaks down from the ties
            mult *= 1 - 0.18 * np.clip(1 - P[:, 1] / 3.5, 0, 1)
            streak = (np.abs(du) < 0.08) & (dv < 0) & (vnoise(np.stack([u * 9, v * 0.5, ax], axis=1), 1.0) > 0.5)
            mult *= np.where(streak, 0.9, 1.0)
        elif kind == "slab":  # a floor slab: saw cuts every 6, oil stains, a little polish
            cut = _line(u, 6.0, 0.035) | _line(v, 6.0, 0.035)
            mult *= np.where(cut, 0.55, 1.0)
            height -= cut * 0.8
            stain = fbm(P + 40.0, 0.09)
            mult *= np.where(stain > 0.62, 0.82, 1.0)
            rough -= 0.15 * (stain > 0.62)
    elif kind == "marble":
        vein = np.abs(np.sin((u * 1.4 + v * 0.6 + 4.0 * fbm(P, 0.5)) * math.pi))
        mult *= 0.93 + 0.07 * fbm(P, 2.0)
        mult *= np.where(vein < 0.06, 0.82, 1.0)
    elif kind == "cork":
        d = vnoise(P, 12.0)
        mult *= 0.82 + 0.3 * (d > 0.55) + 0.06 * fbm(P, 3.0)
        height += (d > 0.55) * 0.3
    elif kind == "leaf":
        mult *= 0.82 + 0.25 * fbm(P, 3.0)
    elif kind == "hazard":  # yellow and black diagonal stripes, worn
        s = ((u + v) / 1.4) % 1.0 < 0.5
        black = np.array([0.08, 0.08, 0.09], np.float32)
        col = np.where(s[:, None], col, black)
        wear = fbm(P, 2.2) > 0.68
        mult *= np.where(wear, 0.75, 1.0) * (0.92 + 0.08 * big)
    elif kind == "rust":  # painted metal with rust blotches and a flange line every so often
        r = fbm(P + 11.0, 0.9)
        rust = np.array([0.45, 0.22, 0.12], np.float32)
        k = np.clip((r - 0.5) * 4, 0, 1)[:, None]
        col = col * (1 - k) + rust * k
        mult *= 0.88 + 0.16 * fbm(P, 4.0)
        rough += 0.2 * k[:, 0]
        metal *= 1 - k[:, 0]
    col = np.clip(col * mult[:, None], 0, 1)
    return col, mult, height, np.clip(rough, 0.05, 1), np.clip(metal, 0, 1)


# ---------------------------------------------------------------- the bake
def reuse(name, objs, out_dir):
    """A look's set already on disk (hq.py --reuse, previews only): the same unwrap and the export material over the
    saved maps; None when any map is missing."""
    paths = {k: os.path.join(out_dir, name + "_" + k + ".png") for k in ("Color", "Normal", "Roughness", "Metalness")}
    if not all(os.path.isfile(v) for v in paths.values()):
        return None
    vkit.unwrap(objs)

    class _L:
        pass

    lk = _L()
    lk.name = name
    mat = vkit.export_material(lk, {k: (bpy.data.images.load(v), v) for k, v in paths.items()})
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
        for p in o.data.polygons:
            p.material_index = 0
    return mat


def bake(name, objs, out_dir, res=512, ao_samples=16, grime=0.0):
    """Bake one look's maps over `objs` (each face's region from its material), write <out_dir>/<name>_*.png, give
    every object the export material (the importer's SurfaceAppearance); returns the material."""
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.use_clear = True
    sc.world = sc.world or bpy.data.worlds.new("W")
    mine = set(objs)
    shown = {}
    for o in sc.objects:
        shown[o.name] = o.hide_render
        o.hide_render = o not in mine
    vkit.unwrap(objs)
    mats = vkit._mats(objs)
    local = {m.name: i for i, m in enumerate(mats)}
    assert len(mats) < 256, name + ": too many regions"

    def id_emit(m, nt, em):
        i = local[m.name]
        em.inputs["Color"].default_value = ((i % 16 + 0.5) / 16, (i // 16 + 0.5) / 16, 0.5, 1)

    def geo_emit(out):
        def f(m, nt, em):
            g = nt.nodes.new("ShaderNodeNewGeometry")
            g.name = "TmpGeo"
            nt.links.new(g.outputs[out], em.inputs["Color"])
        return f

    def clean():
        for m in mats:
            g = m.node_tree.nodes.get("TmpGeo")
            if g:
                m.node_tree.nodes.remove(g)

    ids = vkit._image("ids", res, float_buf=True)
    sc.render.bake.margin = 0
    vkit._bake(objs, "EMIT", ids, 1, id_emit)
    raw = vkit._pixels(ids)
    sc.render.bake.margin = 4
    vkit._bake(objs, "EMIT", ids, 1, id_emit)
    pos = vkit._image("pos", res, float_buf=True)
    vkit._bake(objs, "EMIT", pos, 1, geo_emit("Position"))
    clean()
    nrm = vkit._image("nrm", res, float_buf=True)
    vkit._bake(objs, "EMIT", nrm, 1, geo_emit("Normal"))
    clean()
    ao = vkit._image("ao", res)
    vkit._bake(objs, "AO", ao, ao_samples)
    I = vkit._pixels(ids)
    Pb = vkit._pixels(pos)[..., :3]
    Nb = vkit._pixels(nrm)[..., :3]
    A = vkit._pixels(ao)[..., 0]
    for img in (ids, pos, nrm, ao):
        bpy.data.images.remove(img)
    del raw
    for o in sc.objects:
        o.hide_render = shown.get(o.name, False)
    Pr = np.stack([Pb[..., 0], Pb[..., 2], -Pb[..., 1]], axis=-1)  # Blender (x, front, up) to Roblox (x, up, back)
    Nr = np.stack([Nb[..., 0], Nb[..., 2], -Nb[..., 1]], axis=-1)
    reg = np.floor(I[..., 0] * 16).astype(np.int32) + 16 * np.floor(I[..., 1] * 16).astype(np.int32)
    reg[I[..., 2] < 0.25] = -1
    H, W = reg.shape
    col = np.full((H, W, 3), 0.1, np.float32)
    alpha = np.ones((H, W), np.float32)
    rough = np.full((H, W), 0.6, np.float32)
    metal = np.zeros((H, W), np.float32)
    height = np.zeros((H, W), np.float32)
    aoc = np.clip(A, 0, 1)
    for _ in range(2):
        aoc = (aoc + np.roll(aoc, 1, 0) + np.roll(aoc, -1, 0) + np.roll(aoc, 1, 1) + np.roll(aoc, -1, 1)) / 5
    tinted = np.zeros((H, W), bool)
    for m in mats:
        k = reg == local[m.name]
        if not k.any():
            continue
        c, mult, h, r, mt = pattern(m["kind"], tuple(m["rgb"]), Pr[k], Nr[k])
        col[k] = c
        height[k] = h
        rough[k] = r
        metal[k] = mt
        if m["tint"]:
            tinted[k] = True
            alpha[k] = np.clip((1 - mult) * 0.9, 0, 0.6)
    shade = (0.58 + 0.42 * aoc)
    if grime:  # big shell pieces: darker toward the floor
        shade = shade * (1 - grime * np.clip(1 - Pr[..., 1] / 4.0, 0, 1))
    op = ~tinted
    col[op] = col[op] * shade[op][:, None]
    veil = np.clip((1 - aoc) * 0.5, 0, 0.5)
    col[tinted] = np.array([0.03, 0.03, 0.04], np.float32)
    alpha[tinted] = np.clip(alpha[tinted] + veil[tinted] * (1 - alpha[tinted]), 0, 1)
    col[reg < 0] = 0.1
    gy, gx = np.gradient(height)
    kk = 2.5
    nx, ny, nz = -gx * kk, -gy * kk, np.ones_like(gx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], axis=-1)
    one = np.ones_like(alpha)

    def write(suffix, rgba, data, r_=None):
        r_ = r_ or W
        if r_ != W:
            f = W // r_
            rgba = rgba.reshape(r_, f, r_, f, 4).mean(axis=(1, 3))
        img = bpy.data.images.new(name + "_" + suffix, r_, r_, alpha=True)
        if data:
            img.colorspace_settings.name = "Non-Color"
        img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).reshape(-1))
        path = os.path.join(out_dir, name + "_" + suffix + ".png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return img, path

    maps = {
        "Color": write("Color", np.dstack([np.clip(col, 0, 1), alpha]), False),
        "Normal": write("Normal", np.dstack([normal, one]), True),
        "Roughness": write("Roughness", np.dstack([rough, rough, rough, one]), True, max(64, W // 2)),
        "Metalness": write("Metalness", np.dstack([metal, metal, metal, one]), True, max(64, W // 2)),
    }

    class _L:
        pass

    lk = _L()
    lk.name = name
    mat = vkit.export_material(lk, maps)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
        for p in o.data.polygons:
            p.material_index = 0
    return mat


def res_for(objs):
    """Texture size by the look's size: small props 256, room pieces 512, wall-sized ones 1024."""
    span = 0.0
    for o in objs:
        d = o.dimensions
        span = max(span, d.x, d.y, d.z)
    return 256 if span <= 5 else (512 if span <= 16 else 1024)


def preview_material(base, tint_rgb):
    """(Previews) the export material as Roblox draws it: the colour map over the part's Color by its alpha."""
    m = base.copy()
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = None
    for n in nt.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.name.endswith("_Color"):
            tex = n
    if tex is None:
        return m
    for l_ in list(p.inputs["Alpha"].links):
        nt.links.remove(l_)
    p.inputs["Alpha"].default_value = 1.0
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (vkit.lin(tint_rgb[0]), vkit.lin(tint_rgb[1]), vkit.lin(tint_rgb[2]), 1)
    nt.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(tex.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    return m
